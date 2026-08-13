# DokployPress — Hardening & Reproducibility Implementation Plan

Status: **ALL SIX TASKS (INCLUDING 1.2) IMPLEMENTED AND VERIFIED** against
real running containers (not just code review) — 1.1 (image pinning), 1.2
(WP-CLI `v2.12.0` + `php-fpm-healthcheck` `v0.6.0`, build-verified with
`wp --version`), 2 (MariaDB 11.8 upgrade + snapshot safety net), 3
(phpMyAdmin behind `tools`), 4 (SFTP locked-account-by-default + unhealthy
signal), 5 (nginx security headers), 6 (PHP 8.4). Task 1.3's optional
Renovate/Dependabot follow-up is also done — `.github/dependabot.yml`
added. `CHANGELOG.md` has the finished entry under **`3.0.0`** (strict
semver — the phpMyAdmin profile change is a genuine breaking change for
existing deployments, so this went out as a major bump rather than folded
into a minor with an operator note). Task 4's shipped design deviates from
this doc's original `:?` required-variable proposal — that approach was
tested and confirmed broken (Compose interpolates before profile
filtering, breaking every deployment, not just SFTP users); see
`CHANGELOG.md` for the empty-default + healthcheck approach actually
shipped. (A separate, pre-existing bug unrelated to this plan — a
false-positive `DB_HOST` mismatch detection on every site's first restart
— was also found and fixed along the way; see `CHANGELOG.md`.) Nothing
from this plan remains outstanding.

Based on a code review of v2.1.1. Five workstreams, ordered by risk/benefit.
Each task lists the exact files to touch, the change, and acceptance criteria.

> **Sync rule:** `docker-compose.yml` and `template.toml` at the repo root are
> mirrored in `blueprints/dokploypress/`. Every compose/template change below
> must be applied to **both** copies, then verified identical (ignoring any
> intentional template-only differences).

> **Docs rule:** Every behavior-affecting change gets a `CHANGELOG.md` entry
> (semver — see "Versioning" at the bottom) and README/docs updates where the
> old behavior is documented.

---

## 1. Pin images and fetched artifacts (reproducibility / supply chain)

**Problem:** Several images use floating tags and two build-time artifacts are
fetched from moving refs. Redeploys months apart can produce different stacks.

### 1.1 Pin Docker image tags

Files: `docker-compose.yml`, `blueprints/dokploypress/docker-compose.yml`

| Service | Current | Change to |
|---|---|---|
| `nginx` (base image in `nginx/Dockerfile`) | `nginx:alpine` | `nginx:1.30-alpine` (stable branch, confirmed current as of this plan's last review — re-check at execution time since nginx cuts a new stable branch roughly yearly) |
| `redis` | `redis:alpine` | `redis:8-alpine` (Redis 8 is GA and available under AGPLv3 — an OSI-approved open-source license again, unlike the 7.4–7.8 RSALv2/SSPLv1-only releases) |
| `phpmyadmin` | `phpmyadmin/phpmyadmin:latest` | `phpmyadmin/phpmyadmin:5` |
| `wp-cron` | `alpine:latest` | `alpine:3` (major pin; image only needs `wget` + `sh`) |
| `sftp` | `atmoz/sftp:latest` | `atmoz/sftp:alpine` — evaluate whether a versioned tag exists; if not, document why in a compose comment |

Pin to **major** (not digest) to keep security patches flowing while avoiding
surprise majors. Note in compose comments that this is deliberate.

Also confirmed acceptable as-is (already stream-pinned, note in comments):

- `wordpress:php8.3-fpm` in `wordpress/Dockerfile` — stream-pinned; the PHP
  version bump itself is handled separately in Task 6.
- `mariadb` — handled separately in Task 2.

### 1.2 Pin build-time artifacts in `wordpress/Dockerfile` — DONE

- **WP-CLI:** ~~replace the `gh-pages/phar/wp-cli.phar`~~ → pinned to tagged
  release `v2.12.0` (confirmed current stable at execution time, and the
  download URL confirmed resolving before pinning). `wp --version --allow-root`
  verification added in the same `RUN` layer — confirmed the build fails if
  the pinned binary breaks, and confirmed a real build prints
  `WP-CLI 2.12.0`.
- **php-fpm-healthcheck:** ~~replace the `master` ref~~ → pinned to tagged
  release `v0.6.0` (confirmed current at execution time, URL confirmed
  resolving before pinning).

### 1.3 Optional follow-up — Dependabot done, compose comment block skipped

- ~~Add a comment block in both compose files explaining the pinning
  policy.~~ Not done — genuinely optional, and the per-line comments already
  added throughout Task 1 (e.g. the `atmoz/sftp` and `db-preupgrade-snapshot`
  comments) cover the "why" at the point of use, which reads better than a
  single upfront block. Revisit if a future maintainer wants it.
- **Renovate/Dependabot config — done.** `.github/dependabot.yml` added:
  weekly `docker` ecosystem checks across every Dockerfile/compose-file
  directory (root, `blueprints/dokploypress`, `nginx`, `wordpress`,
  `plugin-installer`) plus `github-actions` checks for `.github/workflows/`.
  Does not cover the two build-time artifact URLs from 1.2 above (WP-CLI,
  `php-fpm-healthcheck`) — those are plain `curl`/`wget` calls Dependabot's
  `docker` ecosystem doesn't parse; revisit those by hand periodically.

**Acceptance criteria**

- `grep -n "latest" docker-compose.yml blueprints/dokploypress/docker-compose.yml`
  returns no image tags (the `redis-cache.latest-stable.zip` plugin URL in
  `plugin-installer/install-plugins.sh` is out of scope — WordPress.org's
  "latest-stable" is the supported channel for plugins; leave it).
- `wordpress/Dockerfile` contains no `master`/unversioned artifact URLs.
- Full stack builds and passes `tests/smoke-test.sh`.

---

## 2. MariaDB 10.6 → 11.8 LTS upgrade path

**Problem:** `mariadb:10.6` reaches EOL July 2026. Existing deployments have
10.6 data volumes, so this is **not** a simple tag bump.

**Target version:** `11.8`, not `11.4`. 11.8 is the current LTS (support
through June 2028, vs. 11.4's shorter window) and MariaDB documents a direct,
officially supported upgrade path from 10.6 straight to 11.8 — there's no
reason to land on an LTS that's already one behind.

### 2.1 Data-safety analysis (read before executing)

- **No data loss is expected in the normal case.** `mariadb-upgrade` (run
  automatically via `MARIADB_AUTO_UPGRADE=1`) only updates system tables
  (`mysql.*`), views, and metadata. User data in InnoDB tables (posts, users,
  options) is not rewritten.
- **The upgrade is one-way.** Once 11.8 opens the data directory, 10.6 can no
  longer read it. There is no downgrade path. If the upgrade is interrupted
  (OOM kill, disk full), recovery without a backup may be impossible — this is
  the only realistic data-loss scenario, and a pre-upgrade backup fully
  mitigates it. Treat the backup as **mandatory**, not recommended.
- **What is and is not automatic:** `MARIADB_AUTO_UPGRADE=1` automatically
  backs up the **system tables only** (a `system_mysql_backup_*.sql.zst` file
  in the datadir) before upgrading. Site content (posts, users, options) is
  **not** backed up automatically by the image — hence the automated snapshot
  in 2.2b below, so operators are protected even if they skip the manual dump.
- **Version jump:** 10.6 → 11.8 skips several majors (10.11, 11.0–11.7).
  MariaDB's own documentation includes a dedicated guide for upgrading
  directly from 10.6 to 11.8, so this is an officially supported jump, not
  just "generally works." Default recommendation: **direct jump + mandatory
  backup**, since the regression test in 2.4 covers exactly this transition.

### 2.2 Compose change

Files: `docker-compose.yml`, `blueprints/dokploypress/docker-compose.yml`

- Change `db` image to `mariadb:11.8`.
- Add `MARIADB_AUTO_UPGRADE=1` to the `db` service environment. The official
  image then runs `mariadb-upgrade` automatically when it detects an older
  data directory — this is the supported in-place upgrade mechanism and makes
  existing 10.6 volumes work on redeploy without operator action.
  (Verify current official-image env var name at execution time.)

### 2.2b Automated pre-upgrade datadir snapshot (safety net)

Rationale: a `mariadb-dump` cannot be automated at redeploy time (it needs the
old server running, which is already gone), but a **file-level snapshot of the
datadir taken before 11.8 first opens it** can be, and is a full restore point.

Files: `docker-compose.yml`, `blueprints/dokploypress/docker-compose.yml`

- Add a one-shot `db-preupgrade-snapshot` service (small `alpine:3` image):
  - Mounts `db_data` (rw) and a new `db_backup` named volume.
  - Logic: if the datadir exists and its version marker (e.g.
    `mysql_upgrade_info` content, or absence of an 11.x marker) indicates a
    pre-11.8 datadir **and** no snapshot for that version exists in
    `db_backup`, `tar` the datadir into
    `db_backup/preupgrade-<version>-<date>.tar.gz`, then exit 0. Otherwise
    exit 0 immediately (no-op on fresh installs and already-upgraded volumes).
  - `db` gains `depends_on: db-preupgrade-snapshot:
    condition: service_completed_successfully` so MariaDB 11.8 never opens the
    datadir before the snapshot completes.
- Add `db_backup` to the `volumes:` section (named with the same
  `STACK_SLUG` pattern as the others).
- Document restore procedure in `docs/hosting-guide.md`: stop stack, restore
  tarball into `db_data`, pin image back to `mariadb:10.6`, start.
- Note in compose comments: the snapshot is a one-time upgrade safety net,
  **not** a recurring backup solution; keep the manual-dump recommendation in
  the docs as primary guidance, and note the extra disk usage (≈ datadir size,
  compressed). Operators may delete the tarball once the upgrade is verified.
- Snapshot failure (e.g. disk full) must fail the service (non-zero exit) so
  the `db` service does not start and the datadir is left untouched.

### 2.3 Documentation

Files: `README.md`, `docs/hosting-guide.md`

- Add an "Upgrading the database" note: what `MARIADB_AUTO_UPGRADE` does, that
  the first restart after the bump may take longer, that the upgrade is
  **one-way** (no downgrade to 10.6), and that a DB backup (phpMyAdmin or
  `docker exec … mariadb-dump`) before redeploying is **required** — it is the
  only protection against an interrupted upgrade.
- Troubleshooting entry: db healthcheck failing after upgrade → check
  `docker logs` for `mariadb-upgrade` output.

### 2.4 Testing

- Run `tests/smoke-test.sh` for the fresh-install path.
- Manual/scripted upgrade test: start the stack pinned to 10.6, install WP,
  stop, switch image to 11.8 with auto-upgrade, restart, verify healthcheck
  passes and the site loads. If practical, capture this as
  `tests/db-upgrade-regression-test.sh` following the style of
  `tests/multisite-regression-test.sh`.

**Acceptance criteria**

- Fresh install works on 11.8 (smoke test green), with the snapshot service
  exiting 0 as a no-op.
- A 10.6 volume upgrades in place with no manual steps, and post-upgrade the
  WP site's content (posts, users, options) is intact — verify in the
  regression test, e.g. compare a `wp post list` / option value before and
  after the upgrade.
- The upgrade regression test confirms a `preupgrade-*.tar.gz` exists in
  `db_backup` after upgrading a 10.6 volume, and that restoring it onto a
  clean `db_data` volume boots under `mariadb:10.6`.
- README documents the one-way nature of the upgrade, the automatic snapshot,
  and the still-recommended manual dump.

---

## 3. Move phpMyAdmin behind the `tools` profile (attack surface)

**Problem:** phpMyAdmin runs 24/7 and is attached to `dokploy-network`
(Traefik-reachable). It should be opt-in, like SFTP already is.

### 3.1 Compose change

Files: `docker-compose.yml`, `blueprints/dokploypress/docker-compose.yml`

- Add to the `phpmyadmin` service:
  ```yaml
  profiles:
    - tools
  ```
  (same pattern as the existing `sftp` service).

### 3.2 Documentation

Files: `README.md`, `docs/hosting-guide.md`, `template.toml` /
`blueprints/dokploypress/template.toml` (if they reference phpMyAadmin domains
or env), `config.txt` (check for references).

- Update the SFTP section heading pattern — phpMyAdmin now also requires
  `COMPOSE_PROFILES=tools`.
- Update "Post-Deploy Setup → Configure Domains" so the phpMyAdmin domain step
  is conditional on the profile being enabled.
- **Breaking-change callout** in `CHANGELOG.md`: existing deployments that use
  phpMyAdmin must add `COMPOSE_PROFILES=tools` in Dokploy's Environment tab or
  the service disappears on next redeploy. State this prominently.

### 3.3 Testing

Files: `tests/smoke-test.sh`, `tests/smoke-test.env`, `tests/compose.override.yml`

- If the smoke test asserts phpMyAdmin health, either set
  `COMPOSE_PROFILES=tools` in `tests/smoke-test.env` (keeps coverage — preferred)
  or drop the assertion. Check `tests/build-workflow-regression-test.sh` too.

**Acceptance criteria**

- Default deploy (`docker compose up`) starts **no** phpMyAdmin container.
- `COMPOSE_PROFILES=tools docker compose up` starts phpMyAdmin and SFTP; both healthy.
- Smoke test green; changelog documents migration step for existing users.

---

## 4. SFTP: fail loudly on default password

**Problem:** `sftp` falls back to the guessable password
`changeme_set_in_dokploy` when `SFTP_PASSWORD` is unset.

### 4.1 Compose change — SHIPPED, but not as originally proposed

**The `:?` required-variable approach below was tested against the actual
Compose version in use (v5.2.0) and confirmed broken — not a caveat, an
actual failure:**

```yaml
command: "${SFTP_USER:-wpuser}:${SFTP_PASSWORD:?SFTP_PASSWORD must be set when COMPOSE_PROFILES=tools}:${SFTP_UID:-33}"
```

`docker compose config` (and by extension `up`) errors on this for **every**
deployment, including ones with the `tools` profile inactive and ones that
never touch SFTP at all — confirmed directly, not inferred. Compose
interpolates the whole file before profile-based filtering happens; this is
not a version quirk fixable by requiring a newer Compose, it's the order
Compose's own pipeline runs in.

**What shipped instead** (the plan's own documented fallback: sentinel
default + healthcheck guard):

```yaml
command: "${SFTP_USER:-wpuser}:${SFTP_PASSWORD:-}:${SFTP_UID:-33}"
environment:
  - SFTP_PASSWORD=${SFTP_PASSWORD:-}
healthcheck:
  test: ["CMD-SHELL", "test -n \"$$SFTP_PASSWORD\""]
```

Verified directly (not assumed) that `atmoz/sftp` given an empty password
creates a **locked** account (`*` in `/etc/shadow`) — no login possible for
anyone — rather than an unprotected or default-credentialed one. The
healthcheck turns "silently locked out, including the operator" into a
visible **unhealthy** status in Dokploy.

### 4.2 Documentation

Files: `README.md` (SFTP section), `docs/sftp-setup.md`

- State that `SFTP_PASSWORD` is required for a usable login and that an
  unset value produces a locked account + unhealthy container, not a
  guessable default. Remove any mention of the old default password.

**Acceptance criteria**

- ~~`COMPOSE_PROFILES=tools` without `SFTP_PASSWORD` → compose fails with the
  clear error message above.~~ **Revised**: compose starts normally either
  way (the hard-fail approach broke non-SFTP deployments); the `sftp`
  container itself reports unhealthy when the password is missing.
- Without the profile, the stack starts normally with no `SFTP_PASSWORD` set. ✅
- With profile + password set, SFTP works as before — verified with a real
  password hash present in `/etc/shadow`, not just a healthy status. ✅

---

## 5. Nginx header fixes (`nginx/default.conf.template`)

**Problem A:** nginx `add_header` directives are inherited from the `server`
block **only if a location adds none of its own**. The static-asset location
adds `Cache-Control`, which silently drops the security headers there. The
`/healthz` location has the same issue (adds `Content-Type`).

**Problem B:** `X-XSS-Protection` is deprecated (removed from modern browsers,
can introduce issues in old ones); missing `Referrer-Policy`.

### 5.1 Changes

File: `nginx/default.conf.template`

1. Extract the security headers into a snippet to avoid duplication drift.
   Since the image build copies only the template, either:
   - **Preferred:** add `nginx/security-headers.conf` (plain, no envsubst
     needed), COPY it in `nginx/Dockerfile` to
     `/etc/nginx/snippets/security-headers.conf`, and `include` it in the
     `server` block **and** in every location that uses `add_header`
     (static assets, `/healthz`); or
   - if keeping a single file is strongly preferred, duplicate the
     `add_header` lines into those locations with a comment explaining the
     nginx inheritance gotcha.
2. Replace `X-XSS-Protection "1; mode=block"` with `X-XSS-Protection "0"` or
   remove it entirely (removal preferred; note in changelog).
3. Add `add_header Referrer-Policy "strict-origin-when-cross-origin" always;`.
4. **Do not** add `Content-Security-Policy` in this pass — WordPress
   admin/plugins break easily under CSP; out of scope. Note as future work.
5. Verify `nginx/docker-entrypoint.sh` envsubst variable whitelist (if any)
   doesn't mangle the new include (`security-headers.conf` must not pass
   through envsubst, or `$` characters would need escaping — none expected).

### 5.2 Testing

- `docker compose up` then:
  - `curl -sI http://<host>/` → shows `X-Frame-Options`,
    `X-Content-Type-Options`, `Referrer-Policy`.
  - `curl -sI http://<host>/wp-includes/js/jquery/jquery.min.js` (any static
    asset) → shows the same security headers **plus** `Cache-Control`.
  - `curl -sI http://<host>/healthz` → security headers present.
- Add these header assertions to `tests/smoke-test.sh` if it already does
  HTTP checks (it does — extend the existing curl section).

**Acceptance criteria**

- Security headers present on HTML, static assets, and `/healthz` responses.
- No `X-XSS-Protection: 1` anywhere.
- `nginx -t` passes in the built image; smoke test green.

---

## 6. PHP base image bump (8.3 → 8.4)

**Problem:** `wordpress:php8.3-fpm` — PHP 8.3 left active support in Dec 2025
and receives security fixes only until Dec 2027. Not urgent, but should be
scheduled rather than left open-ended.

### 6.0 Target version decision rule

Prefer **PHP 8.5** (security support until Dec 2029 — two extra years vs. 8.4,
fewer forced bumps for deployed sites) **if and only if**, at execution time:

1. The official `wordpress:php8.5-fpm` image exists and is current;
2. WordPress core declares **full** (non-beta) PHP 8.5 support — check
   https://make.wordpress.org/core/handbook/references/php-compatibility-and-wordpress-versions/ ;
3. The PECL `redis` extension has a stable release supporting 8.5.

**Checked as of this plan's last review:** criteria 2 and 3 are met — WP core
support is full/non-beta as of 6.9/7.0, and PECL `redis` has stable 8.5
support. Criterion 1 fails: Docker Hub's official `wordpress` repo only
publishes `beta-php8.5-fpm`-prefixed tags, no stable `php8.5-fpm`. **Target is
therefore PHP 8.4** (`wordpress:php8.4-fpm`, confirmed stable and actively
maintained; security support until Dec 2028). Re-check criterion 1 at
execution time — if Docker Hub has dropped the `beta-` prefix by then, 8.5
becomes the better choice per the rule above. Rationale for caution otherwise:
this template runs arbitrary end-user plugins/themes, whose compatibility
lags the newest PHP branch — the plugin-compatibility caveat in 6.2 applies
doubly to a still-beta packaged image.

### 6.1 Changes

File: `wordpress/Dockerfile`

- Change base image to `wordpress:php8.4-fpm` per the 6.0 decision rule
  (re-verify the rule still resolves to 8.4, not 8.5, at execution time).
- Rebuild verifies: GD (freetype/jpeg), zip, opcache via `docker-php-ext-*`,
  and the PECL `redis` extension all compile against PHP 8.4. Pin the PECL
  redis version while at it (ties into Task 1's pinning policy), e.g.
  `pecl install redis-6.2.0` — confirm latest stable at execution time.
- Confirm `php-fpm-healthcheck` still works (it reads the FPM status page —
  version-agnostic, but verify in the smoke test).
- Update the stream-pin comment from Task 1 to reference the chosen branch.

### 6.2 Documentation & compatibility notes

Files: `README.md`, `CHANGELOG.md`

- Changelog operator note: sites with old plugins/themes should verify
  compatibility with the chosen PHP version before redeploying; deprecation
  warnings may appear in logs. Since images rebuild on redeploy, existing
  installs get the new PHP on their next redeploy automatically — state this
  clearly.

### 6.3 Testing

- `tests/smoke-test.sh` and `tests/multisite-regression-test.sh` green.
- `docker exec` check: `php -v` reports the chosen version, `php -m` lists
  `redis`, `gd`, `zip`, `opcache` (add these asserts to the smoke test if not
  present).

**Acceptance criteria**

- Stack builds and all tests pass on the chosen PHP version with all
  extensions loaded.
- Changelog records which version was chosen and the 6.0 check results.
- Changelog documents the bump and plugin-compatibility caveat.

---

## Execution order & versioning — DONE (all six tasks shipped)

Recommended order (as originally planned) vs. actual order executed:

1. **Task 5** (nginx headers) — lowest risk, pure config. *(done 4th)*
2. **Task 1** (pinning) — low risk, high value. *(done 1st, in two passes — 1.1 then 1.2)*
3. **Task 4** (SFTP password) — small, behavior-gated by profile. *(done 5th, alongside Task 3)*
4. **Task 3** (phpMyAdmin profile) — breaking for some users; needs changelog care. *(done 5th, alongside Task 4)*
5. **Task 6** (PHP bump to 8.4 per decision rule) — medium risk; isolated to one image, well covered by tests. *(done 1st, alongside Task 1)*
6. **Task 2** (MariaDB 11.8 + snapshot) — highest blast radius; do last with the upgrade test. *(done 1st, alongside Tasks 1 and 6)*

The actual order didn't follow the risk-ordered recommendation above (1/2/6
landed together first, then 5, then 3/4 together) — no issues resulted from
that, noted here for accuracy rather than as a concern.

**Versioning decision: `3.0.0`, strict semver.** Task 3's phpMyAdmin change
is a genuine breaking change for existing deployments (a running service
disappears on redeploy unless the operator adds `COMPOSE_PROFILES=tools`
first) — shipped as a major bump with a prominent breaking-change callout in
`CHANGELOG.md`, rather than folded into a minor release with an operator
note (the project's other established option, per the original text of this
section — considered, not used this time).

Final gate before release, run locally or via CI:

```sh
bash tests/smoke-test.sh
bash tests/multisite-regression-test.sh
bash tests/db-upgrade-regression-test.sh
```

All three must pass with the `tools` profile both on and off. (The original
text here referenced `tests/build-workflow-regression-test.sh` — that file
does not exist in this repo; corrected to the two regression tests that
actually do, plus the new `db-upgrade-regression-test.sh` from Task 2.)
