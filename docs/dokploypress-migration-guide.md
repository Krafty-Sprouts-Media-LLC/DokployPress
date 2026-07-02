<!--
DokployPress identity migration plan and guide.

@package DokployPress
@subpackage Documentation
-->

# DokployPress Identity Migration Guide

> **Status:** Completed in **2.0.0** (same repository)  
> **Audience:** Reference for identifier changes and upgrade safety  
> **Product name:** DokployPress (formerly KSM WordPress Stack / KSM WPDokploystack)  
> **Affiliation:** Unofficial WordPress stack for Dokploy — by Krafty Sprouts Media. **Not affiliated with or endorsed by Dokploy.**

This guide documents the **2.0.0 DokployPress rebrand** in this repository. For the production upgrade checklist, see [upgrade-to-2.0.0.md](upgrade-to-2.0.0.md).

---

## Goals

1. Adopt **DokployPress** as the public product identity.
2. **Preserve all existing production data** (WordPress files, database, Redis).
3. **Keep seamless version upgrades** for sites already deployed from this stack.
4. Allow forks (Coolify, custom PaaS) without forcing everyone onto DokployPress naming.

---

## How existing installs actually work

A deployed site does **not** run from the GitHub repo name. It runs from:

| Layer | Where it lives | Example |
|-------|----------------|---------|
| **Compose definition** | Dokploy project (snapshot or Git pull) | `docker-compose.yml` on server |
| **Container images** | GHCR | `ghcr.io/krafty-sprouts-media-llc/dokploy-wp-wordpress:1.14.3` |
| **WordPress files** | Docker volume | `mysite_data` → `/var/www/html` |
| **Database** | Docker volume | `mysite_db_data` |
| **Redis cache** | Docker volume | `mysite_redis_data` |
| **Environment** | Dokploy **Environment** tab | `STACK_SLUG`, `MYSQL_PASSWORD`, etc. |

Renaming the GitHub repo or changing README titles **does not** touch volumes or the database.

---

## Identifier map (what matters)

### Safe to change anytime (no install impact)

| Identifier | Current | Target (example) |
|------------|---------|------------------|
| Display name | KSM WordPress Stack | DokployPress |
| README / docs titles | KSM WPDokploystack | DokployPress |
| `meta.json` → `name` | KSM WordPress Stack | DokployPress |
| `meta.json` → `links.github` | `.../WPDokploystack` | `.../DokployPress` (after rename) |
| Logos, tags, marketing copy | — | DokployPress branding |

### Change with care (can break upgrades if done wrong)

| Identifier | Current | Risk if changed |
|------------|---------|-----------------|
| GitHub repo name | `WPDokploystack` | Low — GitHub redirects old URLs; update Dokploy template Base URL |
| Blueprint folder | `blueprints/ksm-wp-stack/` | Medium — affects new template deploys and CI paths |
| Blueprint `id` in `meta.json` | `ksm-wp-stack` | Medium — new Dokploy templates; existing projects unaffected |
| GHCR image names | `dokploy-wp-nginx`, `dokploy-wp-wordpress`, `dokploy-wp-plugin-installer` | **High** — existing compose pins old URLs; pulls fail until compose is edited |
| Compose service names | `nginx`, `wordpress`, `db`, `redis`, … | **High** — Dokploy may recreate services; volume attachment can break |
| `STACK_SLUG` on live site | e.g. `mysite` | **Critical** — new slug = **new empty volumes**; old data orphaned |

### Keep stable for backward compatibility (recommended long-term)

Even after full DokployPress branding, keep publishing to these paths for existing installs:

```
ghcr.io/krafty-sprouts-media-llc/dokploy-wp-nginx:<version>
ghcr.io/krafty-sprouts-media-llc/dokploy-wp-wordpress:<version>
ghcr.io/krafty-sprouts-media-llc/dokploy-wp-plugin-installer:<version>
```

Optional: publish **additional** `dokploypress-*` images for new installs while dual-publishing `dokploy-wp-*` for 6–12 months.

---

## Phased migration plan (maintainers)

### Phase 1 — Display branding only

**Impact:** None on live sites  
**Effort:** Low  
**When:** Anytime

#### Checklist

- [ ] Update `meta.json` → `name`, `description` to DokployPress
- [ ] Update `README.md` title and intro (keep upstream credit to `itsmereal/dokploy-wp`)
- [ ] Update `docs/hosting-guide.md` header references where appropriate
- [ ] Add DokployPress logo (optional); keep `logo.svg` path or add `dokploypress-logo.svg`
- [ ] Update `CHANGELOG.md` product name in header (can note "formerly KSM WPDokploystack")
- [ ] **Do not** change: GHCR image names, blueprint `id`, compose service names, volume naming

#### Verify

- [ ] `bash tests/smoke-test.sh` passes
- [ ] `bash tests/multisite-regression-test.sh` passes
- [ ] `bash tests/build-workflow-regression-test.sh` passes
- [ ] Blueprint compose still references `dokploy-wp-*` images

---

### Phase 2 — GitHub repository rename

**Impact:** Low on live sites; update links for **new** deploys  
**Effort:** Low  
**When:** After Phase 1 is merged and released

#### Maintainer checklist

- [ ] Choose final repo name (e.g. `DokployPress`)
- [ ] In GitHub: **Settings → General → Repository name** → rename
- [ ] Confirm GitHub redirect works:
  - `https://github.com/Krafty-Sprouts-Media-LLC/DokployPress` → new URL
  - `https://raw.githubusercontent.com/Krafty-Sprouts-Media-LLC/DokployPress/main/meta.json` → redirect
- [ ] Update all hardcoded URLs in repo:
  - [ ] `meta.json` → `links.github`, `links.docs`
  - [ ] `README.md` → template Base URL, manual compose URL
  - [ ] `docs/hosting-guide.md`, `docs/sftp-setup.md`, file headers with GitHub URLs
  - [ ] `wordpress/ksm-cache-bootstrap.php` Plugin URI (optional)
  - [ ] `.github/workflows/release.yml` release name
- [ ] Update Dokploy template **Base URL** in README to new `raw.githubusercontent.com/.../DokployPress/main`
- [ ] Re-tag or note in release notes: "Repo renamed; image paths unchanged"
- [ ] **Do not** rename GHCR packages in this phase

#### Existing operator actions (optional)

| Deploy type | Action required? |
|-------------|------------------|
| **Already running** | None — site keeps running |
| **Redeploy / upgrade** | None — if compose still points to same GHCR images |
| **Git-connected compose in Dokploy** | Update repo URL in Dokploy (GitHub redirect may work temporarily) |
| **New template deploy** | Use new Base URL from README |

---

### Phase 3 — Blueprint identity (optional)

**Impact:** New template deploys only  
**Effort:** Medium  
**When:** Only if you want `dokploypress` as the Dokploy template slug

#### Option A — Alias (safest)

- [ ] Add `blueprints/dokploypress/` as a copy or symlink of `ksm-wp-stack/`
- [ ] Add second entry in `meta.json` with `id: dokploypress`, same compose
- [ ] Keep `ksm-wp-stack` entry for backward compatibility in docs

#### Option B — Rename (breaking for template URL bookmarks)

- [ ] Rename `blueprints/ksm-wp-stack/` → `blueprints/dokploypress/`
- [ ] Update `meta.json` `id` → `dokploypress`
- [ ] Update `.github/workflows/build-images.yml` blueprint path
- [ ] Update regression tests
- [ ] Document: "Existing deployed stacks unaffected; only new template installs use new id"

---

### Phase 4 — GHCR image rename (optional, highest risk)

**Impact:** High if old image paths stop publishing  
**Effort:** High  
**When:** Only with dual-publish transition period

#### Recommended approach: dual-publish

1. CI builds and pushes **both**:
   - `ghcr.io/.../dokploy-wp-wordpress:1.15.0` (legacy)
   - `ghcr.io/.../dokploypress-wordpress:1.15.0` (new)
2. Blueprint default switches to `dokploypress-*` for new installs.
3. Legacy `dokploy-wp-*` kept for **≥ 12 months** with same tags.
4. Migration doc tells existing users they can stay on `dokploy-wp-*` indefinitely.

#### If you must retire `dokploy-wp-*`

Existing operators must edit compose image lines and redeploy (volumes unchanged):

```yaml
# Before
image: ghcr.io/krafty-sprouts-media-llc/dokploy-wp-wordpress:1.14.3

# After
image: ghcr.io/krafty-sprouts-media-llc/dokploypress-wordpress:1.15.0
```

Update all three services: `nginx`, `wordpress`, `plugin-installer`. Bump tag to current release.

---

## Guide for existing site operators

### Will my data be affected?

**No**, if you:

- Redeploy with newer image **tags** only
- Keep the same `STACK_SLUG`
- Keep the same compose **service names** (`wordpress`, `db`, `nginx`, …)

Your data lives in:

```
/var/lib/docker/volumes/<STACK_SLUG>_data/
/var/lib/docker/volumes/<STACK_SLUG>_db_data/
/var/lib/docker/volumes/<STACK_SLUG>_redis_data/
```

### How do I upgrade to a new stack version?

This is independent of the DokployPress rebrand.

1. In Dokploy, open your stack → **Environment** or compose editor.
2. Update image tags (or pull latest compose from GitHub if connected):

   ```yaml
   image: ghcr.io/krafty-sprouts-media-llc/dokploy-wp-wordpress:1.14.3
   ```

   Change `1.14.3` → latest version from [releases](https://github.com/Krafty-Sprouts-Media-LLC/DokployPress/releases) or `meta.json`.

3. Click **Deploy** / **Redeploy**.
4. Confirm containers are healthy; spot-check site and `wp redis status`.

**Do not change `STACK_SLUG` on a live site** unless you intend to migrate data manually.

### After the GitHub repo is renamed

| Scenario | What to do |
|----------|------------|
| Site already deployed | Nothing — keeps running |
| Upgrade via image tags | Nothing extra — GHCR paths unchanged in Phase 1–2 |
| Dokploy compose linked to GitHub | Update repository URL to `DokployPress` when convenient |
| New site from template | Use updated Base URL in README |

### After GHCR images are renamed (Phase 4 only)

1. Edit compose: replace `dokploy-wp-*` with `dokploypress-*` (all three custom images).
2. Set tag to current release.
3. Redeploy once.
4. Volumes reattach automatically — **no WordPress reinstall**.

---

## Pre-migration backup (recommended)

Before any compose or image-path change on production:

```bash
# On the VPS — replace mysite with your STACK_SLUG
docker run --rm \
  -v mysite_db_data:/data \
  -v $(pwd):/backup alpine \
  tar czf /backup/mysite-db-backup-$(date +%Y%m%d).tar.gz -C /data .

docker run --rm \
  -v mysite_data:/data \
  -v $(pwd):/backup alpine \
  tar czf /backup/mysite-wp-backup-$(date +%Y%m%d).tar.gz -C /data wp-content
```

Also export via phpMyAdmin or `wp db export` if WP-CLI is available.

---

## Rollback plan

| Change | Rollback |
|--------|----------|
| Phase 1 branding | Revert docs/meta commit |
| Repo rename | GitHub allows rename again; redirects update |
| Wrong image tag on redeploy | Pin previous tag in compose; redeploy |
| Changed `STACK_SLUG` by mistake | **Do not deploy** — fix env before deploy; if already deployed, restore from backup volumes |
| Phase 4 image rename issues | Revert compose to `dokploy-wp-*` tags; redeploy |

---

## FAQ

### Do I need to reinstall WordPress?

No. Rebranding is repository and packaging identity. WordPress data stays in Docker volumes.

### Will multisite break?

Not if you only change branding or bump image tags. Keep `WORDPRESS_PUBLIC_URL` and `WORDPRESS_MULTISITE_CONFIG` env vars as documented in [hosting-guide.md](hosting-guide.md#wordpress-multisite).

### Should forks rename too?

No requirement. Forks can keep their own names; they should document which upstream image tags they track.

### Can we use DokployPress name but keep `dokploy-wp-*` images forever?

Yes. This is the **recommended** approach for minimum operator friction. Product name ≠ container registry package name.

### What about Coolify users who forked us?

They inherit the same rules: data in volumes, upgrades via image tags. Fork maintainers update their own repo URLs and compose; upstream rebranding does not break their running stacks unless they change image paths without updating compose.

---

## Maintainer release notes template

When executing a migration phase, include in the GitHub release:

```markdown
## DokployPress migration note

- **Phase:** 1 / 2 / 3 / 4 (see docs/dokploypress-migration-guide.md)
- **Existing installs:** No action required / Action required (describe)
- **GHCR images:** Unchanged at `ghcr.io/krafty-sprouts-media-llc/dokploy-wp-*`
- **Data:** Volumes and database unaffected
```

---

## Related documentation

- [README — Quick Start](../README.md)
- [Hosting Guide](hosting-guide.md)
- [SFTP Setup](sftp-setup.md)
- Upstream: [itsmereal/dokploy-wp](https://github.com/itsmereal/dokploy-wp)

---

*Maintained by [Krafty Sprouts Media LLC](https://github.com/Krafty-Sprouts-Media-LLC). Last updated for stack version 1.14.4.*
