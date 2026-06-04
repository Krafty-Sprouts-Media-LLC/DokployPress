# Changelog

All notable changes to **KSM WPDokploystack** will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

Upstream project: [itsmereal/dokploy-wp](https://github.com/itsmereal/dokploy-wp) by [Al-Mamun Talukder](https://itsmereal.com)

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
