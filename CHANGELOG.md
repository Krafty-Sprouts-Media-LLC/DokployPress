# Changelog

All notable changes to **KSM WPDokploystack** will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

Upstream project: [itsmereal/dokploy-wp](https://github.com/itsmereal/dokploy-wp) by [Al-Mamun Talukder](https://itsmereal.com)

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
