# Changelog

All notable changes to **KSM WPDokploystack** will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

Upstream project: [itsmereal/dokploy-wp](https://github.com/itsmereal/dokploy-wp) by [Al-Mamun Talukder](https://itsmereal.com)

---

## [1.14.0] - 02/07/2026

### Added
- **WordPress Multisite support** — New `WP_MULTISITE_MODE` environment variable controls multisite mode.
  Set to `subfolder` (path-based sub-sites) or `subdomain` (subdomain-based sub-sites) to enable Network Setup.
  Defaults to `disabled` — zero impact on existing single-site deployments.
- **`WP_ALLOW_MULTISITE` enforcement in entrypoint** — When `WP_MULTISITE_MODE` is `subfolder` or `subdomain`,
  the custom entrypoint (Step 4a) uses WP-CLI to ensure `WP_ALLOW_MULTISITE=true` is always present in
  `wp-config.php` on every container start. Idempotent — mirrors the existing `DISABLE_WP_CRON` enforcement.
  Fixes the "Tools → Network Setup" menu not appearing after manually adding the constant to wp-config.php.
- **Nginx multisite rewrites** — `nginx/default.conf.template` now includes:
  - `/wp-admin` trailing-slash redirect (both subfolder and subdomain modes).
  - Subfolder prefix-strip rewrites (`^(/[^/]+)?(/wp-.*)` and `^(/[^/]+)?(/.*\.php)`) — routes `/site1/wp-admin`, `/site1/wp-login.php`, etc. correctly in subfolder mode.
  - Legacy `/blogs.dir` and `/files/` upload-path compatibility locations (pre-WP 3.5, no-ops on modern installs).
  All rules are guarded by `!-e $request_filename` — safe no-ops on single-site installs.

### Changed
- `docker-compose.yml` — `WP_MULTISITE_MODE` env var added to `wordpress` service (default: `disabled`).
- `blueprints/ksm-wp-stack/docker-compose.yml` — Same `WP_MULTISITE_MODE` env var added to blueprint.
- `wordpress/docker-entrypoint-custom.sh` v1.14.0 — Added Step 4a: multisite constant enforcement.
- `nginx/default.conf.template` — Added multisite rewrite rules and file header comment.
- `meta.json` — Version bumped `1.13.5` → `1.14.0`.

---

## [1.13.5] - 19/06/2026

### Fixed
- **Optional SFTP container port ambiguity** — Changed SFTP publishing from an anonymous host port to `${SFTP_PORT:-2222}:22`, so Dokploy deployments can use a predictable public SFTP port instead of a random Docker-assigned port.
- **SFTP path documentation** — Clarified that VPS SSH uses Docker volume paths like `/var/lib/docker/volumes/<stack-slug>_data/_data/`, while the optional SFTP container exposes the WordPress root as `/public_html` because the SFTP user is chrooted.

### Changed
- `docs/sftp-setup.md` and `README.md` — Added generic examples for SFTP paths and warned not to use VPS Docker volume paths through the SFTP container.
- `.gitignore` — Ignore local `config.txt` inspect dumps that may contain live deployment details.
- `blueprints/ksm-wp-stack/docker-compose.yml` — Image tags bumped to `1.13.5`.

---

## [1.13.4] - 09/06/2026

### Fixed
- **CI build failing on blueprint tag update** — The `sed` step added in v1.13.3 used `|` as the substitution delimiter while the ERE alternation `(nginx|wordpress|plugin-installer)` also contains pipe characters. GNU sed treated the first inner `|` as the end of the pattern, causing `unknown option to 's'` and aborting the workflow before images were pushed or blueprint tags were committed. Delimiter changed to `#`.

### Changed
- `blueprints/ksm-wp-stack/docker-compose.yml` — Image tags bumped to `1.13.4`.

---

## [1.13.3] - 09/06/2026

### Fixed
- **Blueprint image tags out of sync** — `blueprints/ksm-wp-stack/docker-compose.yml` was still pinned to `1.12.0` images after the `1.13.x` releases, meaning Dokploy deployments pulled the old WordPress image without the entrypoint fixes. Tags updated to `1.13.2` (current release).

### Changed
- `.github/workflows/build-images.yml` — Added two steps after the plugin-installer build: (1) `sed` replaces all three custom image tags in the blueprint compose with the current `meta.json` version, (2) `stefanzweifel/git-auto-commit-action` commits the change back to the repo with `[skip ci]` so it doesn't trigger a recursive build loop. Blueprint image tags will now always stay in sync automatically on every CI build.
- `blueprints/ksm-wp-stack/docker-compose.yml` — Image tags bumped from `1.12.0` → `1.13.3` for nginx, wordpress, and plugin-installer. From this release, the CI auto-update step keeps blueprint tags permanently in sync with `meta.json` on every build.

---

## [1.13.2] - 09/06/2026

### Fixed
- **`DISABLE_WP_CRON` not applied to existing installs** — `WORDPRESS_CONFIG_EXTRA` is only written to `wp-config.php` by the official WordPress Docker image on a fresh volume (first boot). Existing installs with an existing `wp-config.php` on the volume never received the constant, leaving WordPress's pseudo-cron still firing on page load despite the sidecar running.
- `wordpress/docker-entrypoint-custom.sh` v1.13.2 — Added step 4: on every container start, checks for `DISABLE_WP_CRON` via `wp config has` and surgically sets it via `wp config set --raw` if missing. Idempotent — only acts when the constant is absent; all other wp-config.php content is untouched.

---

## [1.13.1] - 09/06/2026

### Fixed
- **`wp-cron` container: `sh: syntax error: unexpected "&&"`** — The `>` (YAML folded block scalar) collapses newlines into spaces, which broke `&&`/`||` chaining inside the nested `sh -c "..."` string. Replaced with YAML list form (`command: [/bin/sh, -c, |...]`) and `if/then/fi` instead of `&&`/`||`. No escaping issues, no folding, works correctly in Alpine `sh`.
- Applies to both `docker-compose.yml` and `blueprints/ksm-wp-stack/docker-compose.yml`.

---

## [1.13.0] - 09/06/2026

### Added
- **WP-Cron sidecar service** (`wp-cron`) — Always-on Alpine container that triggers `wp-cron.php` every 5 minutes via the internal Docker network (`http://nginx/wp-cron.php?doing_wp_cron`). Bypasses public DNS and SSL overhead; runs reliably regardless of site traffic. Configurable interval via `WP_CRON_INTERVAL` env var (default: `300` seconds).
- `DISABLE_WP_CRON=true` constant added to `WORDPRESS_CONFIG_EXTRA` in both `docker-compose.yml` and `blueprints/ksm-wp-stack/docker-compose.yml` — prevents WordPress from spawning its own pseudo-cron on page load when the sidecar is managing scheduling.

### Changed
- `docker-compose.yml` — `wp-cron` service added with resource limits (`0.05` CPU / `32M` RAM), `restart: unless-stopped`, and `depends_on: nginx: healthy`.
- `blueprints/ksm-wp-stack/docker-compose.yml` — Same `wp-cron` service added (no resource limits block in blueprint to keep the template lean).
- `docs/hosting-guide.md` — Added `WP-Cron` to stack component table; new **WP-Cron — Reliable Scheduled Tasks** section covering how it works, log verification, interval tuning, and disabling; new `WP_CRON_INTERVAL` env var entry; **Upgrading to v1.13.0** guide for existing Option A and Option B installs.

---

## [1.12.0] - 05/06/2026

### Removed
- **Automatic database search-replace** — Removed from entrypoint and migration fixer. URL changes in post content, widgets, and plugin settings are left to **WP-CLI** (`wp search-replace`) or a user-installed plugin (e.g. Better Search Replace). Avoids stale `KSM_SITE_URL` env conflicts when Dokploy domains change after deploy.
- `KSM_SITE_URL` and `KSM_MIGRATION_OLD_URL` environment variables — no longer used by the stack.

### Changed
- `wordpress/ksm-migration-fixer.php` v1.3.0 — Still updates `siteurl`/`home` from the current request host; logs a reminder to run manual search-replace when needed.

---

## [1.11.0] - 05/06/2026

### Added
- **Automatic database search-replace on migration** — `wp search-replace` runs at **container start** (before php-fpm) when `ksm-migration-pending.txt` exists, so large DBs do not block HTTP requests or hit proxy timeouts. Fallback in `ksm-migration-fixer.php` v1.2.0 if `KSM_SITE_URL` was not set at boot.
- `KSM_SITE_URL` — Pre-filled in Dokploy template from `${main_domain}` (e.g. `https://thexplorion.com`). Used as the search-replace target URL.
- `KSM_MIGRATION_OLD_URL` — Optional override for the source URL when auto-detect from `siteurl` is wrong.

### Changed
- `blueprints/ksm-wp-stack/template.toml` — Inject `KSM_SITE_URL=https://${main_domain}` into stack environment.

---

## [1.10.0] - 05/06/2026

### Added
- `wordpress/ksm-migration-fixer.php` — Post-migration cleanup v1.1.0: flush stale Redis before reading options; restore `active_plugins` and theme from database; deactivate third-party cache plugins (WP Rocket, LiteSpeed, W3TC, etc.); remove foreign `object-cache.php` / `advanced-cache.php` drop-ins; re-enable Redis Object Cache + MilliCache drop-ins.

### Changed
- `wordpress/docker-entrypoint-custom.sh` — Strip migrated `WP_HOME` / `WP_SITEURL` from wp-config; auto-create `ksm-migration-pending.txt` when migration artefacts or wp-config mismatch are detected.

---

## [1.9.0] - 05/06/2026

### Fixed
- **GHCR `:latest` served stale plugin-installer image** — VPS pulls showed `Entrypoint: /install-redis-plugin.sh` (pre-1.8.0) while CI built from source. Plugin-installer image now built with `no-cache: true` to bust bad GHA layer cache.
- `blueprints/ksm-wp-stack/docker-compose.yml` — Pin images to version tag `1.9.0` (not bare `:latest`) and add `pull_policy: always` on nginx, wordpress, and plugin-installer.

### Changed
- `.github/workflows/build-images.yml` — Push both `:latest` and `:{version}` tags from `meta.json` for all three stack images.

---

## [1.8.9] - 05/06/2026

### Fixed
- `tests/smoke-test.sh` — Plugin installer wait loop now polls log output for the final success banner (`Cache plugins installed`) instead of checking container state, which was unreliable when container exit happened between iterations. Timeout extended to 6 min.

---

## [1.8.8] - 05/06/2026

### Fixed
- `wordpress/docker-entrypoint-custom.sh` — Replaced broken `docker-entrypoint.sh /bin/true` approach with a direct `cp` of `/usr/src/wordpress` on fresh volumes. This reliably copies WordPress core (including bundled mu-plugins) without calling the upstream entrypoint twice.
- `tests/smoke-test.sh` — Plugin installer wait loop now checks log content for success rather than relying on `--format '{{.ExitCode}}'` which varies across Docker Compose versions, fixing CI smoke test failures.

---

## [1.8.7] - 04/06/2026

### Fixed
- **Fresh install mu-plugins missing** — `docker-entrypoint-custom.sh` deployed mu-plugins before the official WordPress tar extract on empty volumes, so they were wiped on first boot. Entrypoint now runs core setup first, then deploys mu-plugins.
- `plugin-installer/install-plugins.sh` — MilliCache download retries (3 attempts); `chown` plugins after install.
- `blueprints/ksm-wp-stack/docker-compose.yml` — `plugin-installer` `restart: on-failure` so a slow first boot can retry.

### Changed
- `wordpress/Dockerfile` — Bundle mu-plugins in `/usr/src/wordpress/wp-content/mu-plugins/` for fresh-volume extract.
- `tests/smoke-test.sh` — Assert KSM mu-plugins exist after stack start.
- `docs/hosting-guide.md` — Troubleshooting for missing MilliCache / inactive plugins on fresh installs.

---

## [1.8.6] - 04/06/2026

### Changed
- `README.md`, `docs/hosting-guide.md`, `docs/sftp-setup.md` — Document real Dokploy behaviour: `STACK_SLUG` is pre-filled in Environment after template Create (matches service ID under stack name); replace with short project slug before first Deploy. Clarify WordPress files live in `.../<slug>_data/_data/`, not the volume folder root alone.

---

## [1.8.5] - 04/06/2026

### Changed
- `.github/workflows/build-images.yml` and `.github/workflows/smoke-test.yml` — Added path filters so docs-only commits skip image rebuilds and the integration smoke test.

---

## [1.8.4] - 04/06/2026

### Changed
- `README.md`, `docs/hosting-guide.md`, `docs/sftp-setup.md`, `docs/filebrowser-setup.md` — Replaced real site name in `STACK_SLUG` examples with generic `mysite` placeholder.

---

## [1.8.3] - 04/06/2026

### Fixed
- **CI smoke test** — `tests/.env.test` was excluded by `.gitignore` (`/.env.*/`) and never reached GitHub, causing `couldn't find env file` on Actions. Renamed to committed `tests/smoke-test.env` and updated `tests/smoke-test.sh`.

---

## [1.8.2] - 04/06/2026

### Added
- **`STACK_SLUG` environment variable** — Optional short name for Docker volumes. When set before first deploy, volumes are `{slug}_data`, `{slug}_db_data`, `{slug}_redis_data` instead of long Dokploy `COMPOSE_PROJECT_NAME` values. Template auto-fills from Dokploy `${APP_NAME}`; override in Environment before first Deploy for a short prefix (documented step-by-step in README and hosting guide).
- `README.md` — **Acknowledgments** section crediting [itsmereal/dokploy-wp](https://github.com/itsmereal/dokploy-wp) and Al-Mamun Talukder.

### Fixed
- `template.toml` — `${slug}` is not a Dokploy template variable; `STACK_SLUG` now uses Dokploy-injected `${APP_NAME}` so it resolves correctly at deploy time.

### Changed
- Template **id** `ksm-wp-stack`, **display name** **KSM WordPress Stack** (`meta.json`).
- Blueprint folder renamed `blueprints/wordpress-redis-stack/` → `blueprints/ksm-wp-stack/`.
- `docker-compose.yml` and `blueprints/ksm-wp-stack/docker-compose.yml` — Named volumes use `STACK_SLUG` with fallback to `COMPOSE_PROJECT_NAME`.
- `blueprints/ksm-wp-stack/template.toml` — Passes `STACK_SLUG` from Dokploy-injected `${APP_NAME}` (override in Environment before first deploy for a shorter prefix).
- `README.md`, `docs/hosting-guide.md`, `docs/sftp-setup.md`, `docs/filebrowser-setup.md` — Template name, volume path, and `STACK_SLUG` documentation updated.
- `README.md` and `docs/hosting-guide.md` — Clarified `STACK_SLUG` is not a Dokploy wizard prompt; added explicit Create → Environment → Deploy steps for short volume names; per-service image update table added.

### Notes
- Existing deployments keep their current volume names. Changing `STACK_SLUG` after deploy creates new empty volumes; data remains in old volumes until manually migrated.

---

## [1.8.1] - 04/06/2026

### Added
- **SFTP service (optional `tools` profile)** — Built into `docker-compose.yml` and blueprint compose. Off by default; enable with `COMPOSE_PROFILES=tools` + `SFTP_PASSWORD` in Dokploy Environment, then redeploy. Mounts the same `wordpress_data` volume as WordPress.
- `tests/smoke-test.sh` — Full integration smoke test: starts the stack, installs WordPress, verifies Redis Object Cache + MilliCache plugins, runs `wp redis status`, `wp millicache test`, and checks HTTP cache behaviour.
- `tests/compose.override.yml` and `tests/.env.test` — Test overrides (published port `18080`) and non-production credentials for local/CI runs.
- `.github/workflows/smoke-test.yml` — Runs smoke test on every push/PR to `main` and on manual dispatch.

### Changed
- `docs/sftp-setup.md` — Documents real VPS file location (`/var/lib/docker/volumes/<project>_data/_data/`) and optional SFTP container enable steps. No prescribed migration-plugin paths.
- `README.md` and `docs/hosting-guide.md` — File access and SFTP enable docs corrected; Migrate Guru path instructions removed (users configure per their own connection).

### Fixed
- `plugin-installer/install-plugins.sh` — MilliCache GitHub zip extracts flat (not into a `millicache/` subfolder). Installer now extracts into `wp-content/plugins/millicache/` with `unzip -o` to avoid interactive prompts and partial installs.
- `wordpress/docker-entrypoint-custom.sh` — Avoid duplicate `define()` warnings by not writing cache constants to `wp-config.php` when `WORDPRESS_CONFIG_EXTRA` already supplies them.
- `wordpress/ksm-cache-bootstrap.php` — Skip bootstrap during WP-CLI runs to prevent activation side effects during `wp core install` and other commands.
- `wordpress/docker-entrypoint-custom.sh` — Moved cache plugin activation out of container start (was causing OOM/slow boots). Activation now runs via `ksm-cache-bootstrap` mu-plugin on the first HTTP request after WordPress is installed.

---

## [1.8.0] - 04/06/2026

### Added
- **MilliCache full-page caching** — integrated alongside Redis Object Cache. Both plugins are installed by the plugin-installer sidecar, activated and configured automatically by the WordPress entrypoint via WP-CLI (`wp plugin activate`, `wp redis enable`, `wp millicache drop`).
- `plugin-installer/install-plugins.sh` — Replaces `install-redis-plugin.sh`. Downloads Redis Object Cache (wordpress.org) and MilliCache v1.6.2 (GitHub release) into `wp-content/plugins`.
- `wordpress/docker-entrypoint-custom.sh` — Ensures `MC_STORAGE_HOST`, `MC_STORAGE_PORT`, and `MC_STORAGE_DB` wp-config constants; bootstraps cache plugins on every start when WordPress is installed.
- `wordpress/ksm-migration-fixer.php` — Post-migration step to re-activate MilliCache if present.
- `wordpress/ksm-cache-bootstrap.php` — Must-use plugin that activates cache plugins on the first HTTP request after WordPress setup (no redeploy required).

### Changed
- `docker-compose.yml` and `blueprints/wordpress-redis-stack/docker-compose.yml` — Added MilliCache wp-config constants to `WORDPRESS_CONFIG_EXTRA`; bumped default `REDIS_MAXMEMORY` from `256mb` to `512mb` to accommodate full-page HTML storage.
- `README.md` and `docs/hosting-guide.md` — Replaced manual Redis activation steps with automatic caching documentation; corrected MilliCache section (no Nginx rebuild required — uses `advanced-cache.php` drop-in, not Nginx FastCGI cache).
- `meta.json` — Version `1.8.0`; updated description and tags.

### Removed
- `plugin-installer/install-redis-plugin.sh` — Superseded by `install-plugins.sh`.

---

## [1.7.1] - 04/06/2026

### Added
- `.github/workflows/release.yml` — Automated GitHub Release creation on `v*.*.*` tag push. Extracts the relevant CHANGELOG.md section as the release body. Future version tags will automatically appear under GitHub Releases with formatted notes.

### Notes
- Retroactive tags `v1.1.0` through `v1.7.0` are available under the **Tags** tab on GitHub. To promote them to full Releases with notes, open each tag on GitHub and click **Create release from tag** — the release workflow only applies to future tag pushes.

---

## [1.7.0] - 04/06/2026

### Added
- `wordpress/docker-entrypoint-custom.sh` — **Layer 1: wp-config.php auto-fix.** On every container start, detects if `DB_HOST` in wp-config.php differs from the `WORDPRESS_DB_HOST` environment variable (indicating a migration tool has overwritten it). If mismatch is found, uses `wp config set` to surgically correct only: `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `WP_REDIS_HOST`, `WP_REDIS_PORT`, `WP_CACHE`. All other custom constants (`DISABLE_WP_CRON`, auth keys, table prefix, `WP_DEBUG`, etc.) are completely untouched.
- `wordpress/ksm-migration-fixer.php` — **Layer 2: Must-use plugin.** Deployed to `wp-content/mu-plugins/` by the entrypoint on every container start. Fires only when `ksm-migration-pending.txt` marker file exists. Handles: siteurl/home URL correction, rewrite rule flush, Redis cache flush, Migrate Guru artefact removal (`migrategurupull.php`, `mg_storage`), Migrate Guru destination deactivation, Redis Object Cache re-activation. Writes audit log to `wp-content/ksm-migration-fixer.log`. Removes marker after running so cleanup fires only once.
- `wordpress/Dockerfile` — Added `COPY ksm-migration-fixer.php /usr/local/lib/ksm/` step to bundle the mu-plugin inside the image (outside `wp-content`) so it cannot be overwritten by migration tools.

---

## [1.6.0] - 04/06/2026

### Added
- `docs/hosting-guide.md` — New **Updating the Stack** section replacing the brief settings-only note. Covers: version change categories (image vs compose vs docs), how `:latest` image pulls work on Redeploy, how compose changes reach Option A vs Option B deployments, data volume persistence guarantee, how to handle new required vs defaulted environment variables.

---

## [1.5.0] - 04/06/2026

### Added
- `docs/hosting-guide.md` — **Alternative Migration Method** section covering Migrate Guru plugin-based migration, including SFTP integration steps and note on usefulness for shared hosting sources.
- `docs/hosting-guide.md` — **Future Enhancements** section documenting MilliCache full-page Redis caching as a planned enhancement, including comparison table vs. current Redis Object Cache, and a step-by-step outline of what integration would require (Nginx config merge, image rebuild, redeploy).

---

## [1.4.0] - 04/06/2026

### Added
- `docs/hosting-guide.md` — Major expansion with four new sections:
  - **MariaDB & phpMyAdmin Full Walkthrough** — clarifies that MariaDB is bundled in the stack (not a separate install), shows internal Docker networking diagram, phpMyAdmin access setup, common tasks, and root access.
  - **How Services Are Connected** — ASCII diagram showing internal Docker network topology, explains container DNS resolution (`db`, `redis`), and why no manual connection configuration is needed.
  - **Renaming the Stack in Dokploy** — explains what is safe to rename, what renaming does not affect, and safe rename procedure with volume warning.
  - **Migrating WordPress from Local Disk** — full 8-step migration guide covering database export/import, file upload, `search-replace` for domain change, permission fix, and Redis re-activation.

---

## [1.3.0] - 04/06/2026

### Fixed
- `.github/workflows/build-images.yml` — GHCR requires image tags to be fully lowercase. Removed static `IMAGE_PREFIX` env var (which preserved the mixed-case org name `Krafty-Sprouts-Media-LLC`) and replaced with a `Set lowercase image prefix` step that uses `tr '[:upper:]' '[:lower:]'` to produce `ghcr.io/krafty-sprouts-media-llc/dokploy-wp` at runtime before any build steps execute.

---

## [1.2.0] - 04/06/2026

### Fixed
- `README.md` — Corrected template Base URL and manual compose URL from `itsmereal/dokploy-wp` to `Krafty-Sprouts-Media-LLC/WPDokploystack`.
- `blueprints/wordpress-redis-stack/docker-compose.yml` — Updated all three Docker image references (`nginx`, `wordpress`, `plugin-installer`) from `ghcr.io/itsmereal/...` to `ghcr.io/krafty-sprouts-media-llc/...` so the one-click template pulls from the org's own GHCR registry.

---

## [1.1.0] - 04/06/2026

### Added
- `docs/hosting-guide.md` — Comprehensive hosting guide adapted from the original article by Al-Mamun Talukder at [itsmereal.com](https://itsmereal.com/easily-host-wordpress-sites-using-dokploy-with-redis-and-nginx/), with full attribution and expanded reference tables.

### Changed
- `meta.json` — Updated `github` and `docs` links to point to the new **Krafty-Sprouts-Media-LLC/WPDokploystack** repository. Added `upstream` link referencing the original `itsmereal/dokploy-wp` source for attribution.
- Bumped version from `1.0.0` to `1.1.0`.

---

## [1.0.0] - Initial Import

### Added
- Initial import from [itsmereal/dokploy-wp](https://github.com/itsmereal/dokploy-wp) by Al-Mamun Talukder.
- Production-ready Docker Compose stack for WordPress on Dokploy.
- Services: WordPress (PHP 8.3 FPM), Nginx, MariaDB 10.6, Redis, phpMyAdmin, Plugin Installer.
- Dokploy one-click template (`template.toml`, `meta.json`).
- Existing docs: `filebrowser-setup.md`, `sftp-setup.md`, `vscode-remote-setup.md`.
- GitHub Actions workflows.
