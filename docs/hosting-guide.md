# DokployPress — Advanced Guide

> **Start here first if you haven't already:** the [main README](../README.md) covers deploying the stack, every configuration variable, common tasks, and everyday troubleshooting. This guide is the companion to it — deeper material on specific topics that most people won't need day-to-day, kept separate so the README stays short enough to actually read.

> **DokployPress** is an independent project by Krafty Sprouts Media LLC, adapted from Al-Mamun Talukder's [original article](https://itsmereal.com/easily-host-wordpress-sites-using-dokploy-with-redis-and-nginx/) on hosting WordPress on Dokploy. **Not affiliated with or endorsed by Dokploy.**

## Contents

- [Installing Dokploy itself](#installing-dokploy-itself)
- [MariaDB & phpMyAdmin — internals and root access](#mariadb--phpmyadmin--internals-and-root-access)
- [Upgrading the database (MariaDB 10.6 → 11.8)](#upgrading-the-database-mariadb-106--118)
- [Renaming the stack — will it break updates?](#renaming-the-stack-in-dokploy--will-it-break-updates)
- [Fresh install: plugins/mu-plugins not showing?](#fresh-install-pluginsmu-plugins-not-showing)
- [Migrating an existing WordPress site onto this stack](#migrating-wordpress-sites-from-local-disk)
- [How MilliCache full-page caching works](#millicache-full-page-caching-built-in)
- [How the WP-Cron sidecar works](#wp-cron--reliable-scheduled-tasks)
- [How the Action Scheduler runner works](#action-scheduler-runner--plugin-background-queues)
- [WordPress Multisite — full setup walkthrough](#wordpress-multisite)
- [How updates reach an existing deployment](#how-updates-reach-an-existing-deployment)

---

## Installing Dokploy itself

If you don't have Dokploy running on a server yet (this is about the Dokploy platform, not this stack):

```bash
curl -sSL https://dokploy.com/install.sh | sh
```

Run as root or a user with `sudo` access, on a **freshly provisioned** VPS — mixed installations (existing Docker, Nginx, etc. already on the box) can conflict with what the installer sets up.

Once it finishes, open `http://<your-vps-ip>:3000` in a browser to create your admin account.

- Official install docs: https://docs.dokploy.com/docs/core/installation
- Setup walkthrough video: https://www.youtube.com/watch?v=_FErnBwMpj8 (initial config, SSL, custom domain for the dashboard itself)

Once Dokploy is running, go to the [main README](../README.md) to deploy this stack.

---

## MariaDB & phpMyAdmin — internals and root access

> MariaDB isn't something you install separately — it's already bundled into this stack as the `db` service, and starts automatically with everything else. phpMyAdmin is opt-in (`COMPOSE_PROFILES=tools`, see the README) — turning it on is covered there; this section is what's underneath it.

### How the services actually talk to each other

Every container communicates over a private Docker network called `internal`. WordPress reaches MariaDB using the container name `db` as its hostname — Docker's own internal DNS resolves that automatically, no IP addresses involved anywhere.

```
┌──────────────────────────────────────────────────────┐
│               Docker "internal" network              │
│                                                        │
│  [nginx] ──► [wordpress / php-fpm]                    │
│                       │                                │
│                       ├──► [db / MariaDB] ◄── [phpmyadmin]*
│                       │                                │
│                       └──► [redis]                     │
│                                                        │
│  Only nginx (always) & phpmyadmin (*if enabled)       │
│  are reachable from outside                            │
└──────────────────────────────────────────────────────┘
```

### phpMyAdmin — common tasks once you're in

| Task | How |
|------|-----|
| Browse/edit tables | Left panel → select the `wordpress` database |
| Import a `.sql` backup | **Import** tab → choose file → Go |
| Export/backup the database | **Export** tab → Quick → Go |
| Run raw SQL | **SQL** tab |
| Change the site URL by hand | `wordpress` → `wp_options` → edit the `siteurl` and `home` rows |

### Root database access (advanced, bypasses phpMyAdmin entirely)

```bash
# Get into the db container
docker exec -it <compose-name>-db-1 bash

# Log in as root (enter MYSQL_ROOT_PASSWORD when prompted)
mysql -u root -p

# Inside MySQL
SHOW DATABASES;
CREATE DATABASE another_site;
GRANT ALL PRIVILEGES ON another_site.* TO 'wordpress'@'%';
FLUSH PRIVILEGES;
```

---

## Upgrading the Database (MariaDB 10.6 → 11.8)

This stack runs `mariadb:11.8`. If your deployment predates this version, your `db_data` volume was created under an older MariaDB (commonly `10.6`) — here's exactly what happens on your next Redeploy, and what to check.

### What happens automatically

`MARIADB_AUTO_UPGRADE=1` is set on the `db` service. The official MariaDB image detects an older data directory on startup and runs `mariadb-upgrade` automatically — this updates system tables (`mysql.*`), views, and metadata only. **Your actual site data (posts, users, options — the InnoDB tables) is not rewritten and is not at risk in the normal case.**

A one-shot `db-preupgrade-snapshot` service runs before `db` starts and takes a file-level snapshot of the datadir into the `db_backup` volume, but **only** if it detects a pre-11.x datadir it hasn't already snapshotted — on a fresh install, or a volume already on 11.x, it does nothing and exits immediately.

### What is NOT automatic — read this before redeploying

- **The upgrade is one-way.** Once MariaDB 11.8 opens a 10.6 datadir, it can no longer be read by `mariadb:10.6`. There is no downgrade path other than restoring a backup.
- **`MARIADB_AUTO_UPGRADE` only backs up system tables**, not your actual WordPress content — that's what the automatic `db-preupgrade-snapshot` is for, but it's a one-time safety net for this upgrade, not a substitute for a real backup habit.
- **A manual database export is still required before you redeploy** — via phpMyAdmin (**Export** tab → Quick → Go) or `docker exec <db-container> mariadb-dump`. This is the only protection against an interruption during the upgrade itself (OOM kill, disk full, container restart mid-upgrade) — the one realistic data-loss scenario, and a backup fully covers it.
- **First restart after the bump takes longer than usual** while `mariadb-upgrade` runs — give it a few minutes before assuming something's wrong; check the `db` container's logs if the healthcheck doesn't pass.

### Restoring from the automatic pre-upgrade snapshot

If the upgrade goes wrong and you need to roll back to the pre-upgrade state:

1. Stop the stack in Dokploy.
2. Find the snapshot: it's inside the `db_backup` volume (`{STACK_SLUG}_db_backup`), named `preupgrade-<old-version>-<date>.tar.gz`.
3. Clear the current `db_data` volume contents and extract the tarball into it:
   ```bash
   docker run --rm -v <stack>_db_backup:/backup -v <stack>_db_data:/restore \
     alpine sh -c "rm -rf /restore/* && tar -xzf /backup/preupgrade-*.tar.gz -C /restore"
   ```
4. In the **Compose** tab, pin the `db` image back to `mariadb:10.6` and remove (or leave — it will no-op) `MARIADB_AUTO_UPGRADE`.
5. Redeploy.

Once an upgrade is verified working, the snapshot tarball in `db_backup` can be deleted — it's a one-time restore point for this specific upgrade, not an ongoing backup solution. Keep making regular manual database exports as your primary backup strategy.

---

## Renaming the Stack in Dokploy — Will It Break Updates?

**Short answer: UI display names are safe. Volume names are controlled by `STACK_SLUG` — set it once before the first deploy.** (The README's [Volumes section](../README.md#volumes--where-your-data-lives) covers the basics; this is the fuller reference.)

### Display name vs. volume names

- The **display name** in Dokploy (e.g. "DokployPress") is cosmetic — rename anytime in **General**, nothing else is affected.
- **Docker volume names** come from `STACK_SLUG` (or Dokploy's `COMPOSE_PROJECT_NAME` if you never set one). They do **not** follow UI renames.

### What changing `STACK_SLUG` after data exists actually does

> **Warning:** Docker doesn't rename anything — it creates **new, empty** volumes under the new name. Your WordPress files, database, and Redis data stay in the **old** volumes, fully intact on disk, just detached from the stack Dokploy is now pointing at.

### Safe procedure if you're already on a long, auto-generated volume name

1. Note your current volume names: `docker volume ls | grep _data`
2. Back up the database and `wp-content` before touching anything.
3. Don't change `STACK_SLUG` on a live site unless you're prepared to manually migrate the data into the new volumes afterward.
4. Pure UI display renames (the cosmetic name in Dokploy's dashboard) are always safe and need no redeploy.

---

## Fresh install: plugins/mu-plugins not showing?

On a genuinely new site you should see, once it's finished setting up:

| Location | What |
|----------|------|
| **Plugins** | Redis Object Cache + MilliCache (inactive until the first front-end visit) |
| **Plugins → Must-Use** (bottom of the Plugins screen) | DokployPress Cache Bootstrap + DokployPress Migration Fixer |

**Plugins stay inactive until the first front-end page load** — visiting only wp-admin doesn't trigger it. Load your homepage once while logged out, then refresh the Plugins screen.

If MilliCache or the mu-plugins are still missing after that:

1. Dokploy → **Logs** → `plugin-installer` — confirm both plugins actually downloaded without errors.
2. **Redeploy** — a WordPress container restart re-deploys the mu-plugins into the volume.
3. Or fix it directly:
   ```bash
   docker exec -it <wordpress-container-name> bash
   ls wp-content/plugins/millicache/millicache.php
   ls wp-content/mu-plugins/
   wp plugin activate redis-cache millicache --allow-root
   wp redis enable --allow-root
   wp millicache drop --allow-root
   ```

---

## Migrating WordPress Sites from Local Disk

If your existing WordPress site stores files on local server disk (uploads, themes, plugins) rather than object storage, here's the full migration workflow.

### What needs migrating

| Component | Method |
|-----------|--------|
| Database | Export `.sql` → import via phpMyAdmin or WP-CLI |
| WordPress files (uploads, themes, plugins) | Upload via SFTP, File Browser, or WP-CLI |
| `wp-config.php` | **Not migrated** — this stack auto-generates it from environment variables |
| Credentials/settings | Set via Dokploy environment variables at deploy time |

### Step 1 — Deploy the empty stack first

Deploy as described in the README. Complete the WordPress setup wizard with any temporary credentials. Wait until **all containers show healthy** in Dokploy before proceeding.

### Step 2 — Export the old database

```bash
# Via SSH, using mysqldump
mysqldump -u <db_user> -p <database_name> > site_backup.sql

# Or via phpMyAdmin on the OLD server → Export → Quick → Go
```

### Step 3 — Export WordPress files

```bash
zip -r wp-content-backup.zip wp-content/uploads/ wp-content/themes/ wp-content/plugins/
```

### Step 4 — Upload files to the new server

Pick one:
- **[SFTP Setup](./sftp-setup.md)** — best for large transfers
- **[File Browser Setup](./filebrowser-setup.md)** — browser-based drag & drop
- **[VS Code Remote Setup](./vscode-remote-setup.md)** — best if you're a developer already using VS Code

Upload into the WordPress volume at `/var/www/html/wp-content/`.

### Step 5 — Import the database

**Via phpMyAdmin (small/medium databases):**
1. Open `pma.yourdomain.com`
2. Select the `wordpress` database → **Import** tab → choose `site_backup.sql` → **Go**

**Via WP-CLI (recommended for large databases):**
```bash
docker cp site_backup.sql <wordpress-container-name>:/tmp/
docker exec -it <wordpress-container-name> bash
wp db import /tmp/site_backup.sql --allow-root
```

### Step 6 — Update the site URL

```bash
docker exec -it <wordpress-container-name> bash
wp search-replace 'https://old-domain.com' 'https://new-domain.com' --allow-root
wp cache flush --allow-root
```

`wp search-replace` correctly handles WordPress's serialized data — don't do this with a plain find-and-replace in phpMyAdmin unless you have to (if so: table `wp_options`, rows `siteurl` and `home`).

### Step 7 — Fix file permissions

```bash
docker exec -it <wordpress-container-name> bash
chown -R www-data:www-data /var/www/html/wp-content/
find /var/www/html/wp-content/ -type d -exec chmod 755 {} \;
find /var/www/html/wp-content/ -type f -exec chmod 644 {} \;
```

### Step 8 — Re-activate Redis cache

```bash
docker exec -it <wordpress-container-name> bash
wp plugin activate redis-cache --allow-root
wp redis enable --allow-root
```

### Local disk vs. object storage

This stack stores `wp-content/uploads/` in the `wordpress_data` Docker volume on the VPS disk — fine for most sites. To offload media to S3 or Cloudflare R2, install the **WP Offload Media** plugin; no changes to this stack's Docker configuration are needed.

### Alternative — Migrate Guru (plugin-based)

If you'd rather not do manual export/import, [Migrate Guru](https://wordpress.org/plugins/migrate-guru/) is a solid free option that handles large sites well.

1. Install and activate Migrate Guru on your **source** site.
2. Select **Other Host** as the destination type.
3. Provide destination credentials for whatever access method you're using (SSH/SFTP volume path, or the optional SFTP container — see [SFTP Setup](./sftp-setup.md) for where files live on the VPS). You choose the exact path based on what your WinSCP/SFTP session shows.
4. For the database, use phpMyAdmin or WP-CLI import after files transfer.
5. Once done, run the same URL-update step as Step 6 above.

Migrate Guru handles serialized data, multisite, and large databases gracefully — particularly useful when the source site is on shared hosting where SSH/`mysqldump` access is restricted.

---

## MilliCache Full-Page Caching (Built In)

[MilliCache](https://github.com/MilliPress/MilliCache) is bundled alongside Redis Object Cache. It stores complete rendered HTML pages in Redis and serves them via the `advanced-cache.php` drop-in **before WordPress fully boots** on a cache hit.

| | Redis Object Cache | MilliCache |
|---|---|---|
| Caches | DB queries and PHP objects | The entire rendered HTML page |
| Drop-in | `object-cache.php` | `advanced-cache.php` |
| Redis DB | 0 (default) | 1 (`MC_STORAGE_DB`) |
| Nginx changes needed | None | None |

### How a request flows through it

```
Visitor → Nginx → PHP-FPM → advanced-cache.php → Redis (hit) → HTML response
                                              ↓ (miss)
                                         Full WordPress boot → store in Redis
```

PHP-FPM still runs on cache hits (the drop-in is PHP), but WordPress core, plugins, and the database are all skipped.

### wp-config constants this stack sets automatically

```php
define( 'WP_CACHE', true );
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'MC_STORAGE_HOST', 'redis' );
define( 'MC_STORAGE_PORT', 6379 );
define( 'MC_STORAGE_DB', 1 );
```

### Rules to keep in mind

- **Don't** install another full-page cache plugin (WP Super Cache, W3 Total Cache, Cache Enabler) — only one plugin can own `advanced-cache.php`, they'll conflict.
- **Keep** Redis Object Cache running alongside it — they cache different layers, MilliPress recommends both together.
- Logged-in users bypass MilliCache by default (personalized content shouldn't be cached).
- For a large, content-heavy site, raise `REDIS_MAXMEMORY` (e.g. `1gb`) in Dokploy Environment.

### Verifying cache hits

```bash
wp millicache test
wp millicache stats
```

Or turn on `MC_CACHE_DEBUG` and look for `X-MilliCache-Status: hit` on a repeat, logged-out visit.

---

## WP-Cron — Reliable Scheduled Tasks

WordPress's built-in pseudo-cron (`wp-cron.php`) only fires when a visitor happens to load the site. On a low-traffic site, that can delay scheduled posts, plugin cleanup jobs, and email queues by hours. This stack ships a dedicated sidecar that triggers it on a fixed schedule instead, regardless of traffic.

### How it works

```
[wp-cron container] ──every 5 min──► http://nginx/wp-cron.php?doing_wp_cron
                                           │
                                     [nginx] → [wordpress/php-fpm]
                                           │
                                     WordPress processes due events
```

The request travels over the internal Docker network — no SSL, no external DNS, no dependency on your public domain being reachable. `DISABLE_WP_CRON=true` is set in `wp-config.php` automatically, so WordPress never fires its own pseudo-cron — this sidecar is the sole scheduler.

### Verifying it's running

```bash
docker logs <compose-name>-wp-cron-1 --tail 20
```

Expected, every `WP_CRON_INTERVAL` seconds (default 300):

```
WP-Cron sidecar started. Interval: 300s
[2026-06-09 16:45:00] wp-cron triggered
[2026-06-09 16:50:00] wp-cron triggered
```

### Triggering it manually

```bash
docker exec -it <wordpress-container-name> bash
wp cron event run --due-now --allow-root
wp cron event list --allow-root
```

### Disabling the sidecar

If you want to manage WP-Cron yourself (host-level system cron, Cronicle, etc.):

1. Remove the `wp-cron:` service block from your compose file.
2. Add `DISABLE_WP_CRON=false` to Dokploy Environment (or otherwise stop the stack from forcing it on).
3. Redeploy.

---

## Action Scheduler runner — plugin background queues

Many plugins (WooCommerce, Writura, Rank Math, WP Mail SMTP…) queue their background work with [Action Scheduler](https://actionscheduler.org/) instead of plain WP-Cron events. Action Scheduler can run from `wp-cron.php`, but on this stack that means:

- tasks only get a turn every `WP_CRON_INTERVAL` (default 5 minutes), and
- each run is a web request through Nginx and PHP-FPM, so a long task (an import, an AI article, a large export) is cut off at `PHP_MAX_EXECUTION_TIME` / `NGINX_FASTCGI_TIMEOUT` (default 300 s).

The `action-scheduler` container fixes both by running the queue from the command line:

```
[action-scheduler container] ──every 60 s──► wp action-scheduler run   (as www-data, no time limit)
```

How it is built:

- It `extends` the `wordpress` service, so it has exactly the same image, environment (database, Redis, `WORDPRESS_CONFIG_EXTRA`, your own variables) and `wordpress_data` volume.
- It replaces the entrypoint, so it never starts PHP-FPM and never re-runs the WordPress container's `wp-config.php` or migration fixes.
- It runs as `www-data`, so files a task creates (for example images a plugin downloads) stay owned by WordPress. Never run the queue with `--allow-root`.
- `PHP_MEMORY_LIMIT` is passed to WP-CLI directly (the WordPress entrypoint that normally writes the PHP settings doesn't run here).
- It checks for the `wp action-scheduler` command before each run until it finds it, and logs a single "waiting" line meanwhile — a site with no Action Scheduler plugin costs one short WP-CLI call per interval.
- Runs happen one after another, never overlapping; Action Scheduler's own claims also stop two runners from taking the same task.

### Verifying it's running

```bash
docker logs <compose-name>-action-scheduler-1 --tail 20
```

Expected:

```
Action Scheduler runner started. Interval: 60s
[2026-09-24 12:00:00] Action Scheduler found — running the queue every 60s
```

`--quiet` keeps successful runs silent; only failures are logged. The queue itself is visible in WordPress admin under **Tools → Scheduled Actions**.

### Settings

| Variable | Default | Meaning |
|---|---|---|
| `ACTION_SCHEDULER_INTERVAL` | `60` | Seconds between runs. |
| `ACTION_SCHEDULER_RUNNER` | `enabled` | `disabled` keeps the container idle. |
| `ACTION_SCHEDULER_CPU_LIMIT` | `0.5` | CPU limit for the runner. |
| `ACTION_SCHEDULER_MEMORY_LIMIT` | `512M` | Memory limit for the runner container. |

### If you already added a Dokploy Schedule

Sites that were running `wp action-scheduler run` from a Dokploy **Schedule** can delete that schedule after upgrading — the container does the same job without a Dokploy log entry every minute. Leaving both on is harmless (Action Scheduler never runs the same task twice), just redundant.

---

## WordPress Multisite

This stack supports WordPress Multisite (Network) via one environment variable — both **subfolder** and **subdomain** network types.

### How it works

Setting `WP_MULTISITE_MODE` to `subfolder` or `subdomain` makes the entrypoint enforce `WP_ALLOW_MULTISITE=true` in `wp-config.php` on every container start — the same idempotent pattern used for `DISABLE_WP_CRON`. This is what makes **Tools → Network Setup** appear in WP Admin.

Nginx already includes multisite-safe rewrites for both modes, guarded so they're no-ops on single-site installs:

| Rewrite | Mode | Purpose |
|---------|------|---------|
| `rewrite /wp-admin$ … permanent` | Both | Trailing-slash redirect for subsite admin panels |
| `rewrite ^(/[^/]+)?(/wp-.*)` | Subfolder | Strips `/site1` prefix from `/site1/wp-admin` |
| `rewrite ^(/[^/]+)?(/.*\.php)` | Subfolder | Strips `/site1` prefix from `/site1/wp-login.php` |
| `location ^~ /blogs.dir` | Both (legacy) | Pre-WP 3.5 upload alias — no-op on modern installs |

> Modern WordPress multisite (3.5+) stores uploads at `wp-content/uploads/sites/N/` and serves them as normal static files — no special Nginx rules needed for uploads themselves.

### Subdomain vs. subfolder

| | Subfolder | Subdomain |
|---|---|---|
| Sub-sites at | `yourdomain.com/site1/` | `site1.yourdomain.com` |
| DNS required | Single A record | **Wildcard DNS** `*.yourdomain.com` |
| Traefik config | Standard | Wildcard domain rule required |
| Can convert later | Yes (WP-CLI) | Yes (WP-CLI) |

> **Subdomain mode requires a wildcard DNS record** (`*.yourdomain.com → your server IP`) at your DNS provider **before** running Network Setup, plus a matching wildcard domain entry in Dokploy (Phase 3 below). DNS alone isn't enough — Traefik/Dokploy needs the wildcard route too.

### Phase 1 — Enable Network Setup

1. Dokploy Environment:
   ```env
   WP_MULTISITE_MODE=subdomain
   # or: WP_MULTISITE_MODE=subfolder
   ```
2. Redeploy.
3. Check **Logs → wordpress** for:
   ```
   [DokployPress] ✅ WP_ALLOW_MULTISITE set in wp-config.php (Tools → Network Setup now available).
   ```
4. Open WP Admin in a **private/incognito window** (bypasses the full-page cache) → **Tools → Network Setup**.

### Phase 2 — Run the Network Setup wizard

WordPress asks you to deactivate all plugins first. Redis Object Cache and MilliCache normally auto-activate via a mu-plugin — that bootstrap pauses itself automatically while Network Setup is in progress, so deactivating them in wp-admin sticks.

1. In **Plugins**, deactivate Redis Object Cache, MilliCache, and anything else active.
2. **Tools → Network Setup** → choose the type matching `WP_MULTISITE_MODE` → enter a Network Title and Admin Email → **Install**.
3. WordPress shows you two blocks of generated code. **Don't** paste these into `wp-config.php` directly — the entrypoint manages that file. Instead, put only the generated `define(...)` lines as the *value* of `WORDPRESS_MULTISITE_CONFIG` in Dokploy Environment:
   ```env
   WORDPRESS_MULTISITE_CONFIG=define( 'MULTISITE', true ); define( 'SUBDOMAIN_INSTALL', true ); define( 'DOMAIN_CURRENT_SITE', 'yourdomain.com' ); define( 'PATH_CURRENT_SITE', '/' ); define( 'SITE_ID_CURRENT_SITE', 1 ); define( 'BLOG_ID_CURRENT_SITE', 1 );
   ```
   Copy **exactly** what WordPress generated for you — the values are specific to your install, and subfolder mode's constants differ slightly (`SUBDOMAIN_INSTALL` is `false`, etc.). Don't add these as separate bare `define(...)` environment rows — they're PHP constants, not env var names, and won't be read unless they're inside `WORDPRESS_MULTISITE_CONFIG`.
4. Redeploy. Check **Logs → wordpress** for `WORDPRESS_MULTISITE_CONFIG applied to wp-config.php`.
5. Log back into WP Admin — you'll have a **My Sites** menu and **Network Admin** panel now.

**"An existing network was detected"** — WordPress found multisite tables already in the database (network was already created or partially created). Don't remove tables; just make sure `WORDPRESS_MULTISITE_CONFIG` has the generated constants, redeploy, and confirm the "applied to wp-config.php" log line.

**Plugins keep reactivating themselves during setup** — if Redis Object Cache/MilliCache turn back on right after you deactivate them, disable the bootstrap mu-plugin temporarily:
```bash
docker exec -it <wordpress-container-name> bash
mv /var/www/html/wp-content/mu-plugins/dokploypress-cache-bootstrap.php \
   /var/www/html/wp-content/mu-plugins/dokploypress-cache-bootstrap.php.off
wp plugin deactivate redis-cache millicache --allow-root --path=/var/www/html
```
Finish Network Setup, add `WORDPRESS_MULTISITE_CONFIG`, and Redeploy — the entrypoint restores the mu-plugin from the image automatically.

### If WP Admin redirects to `https://nginx/wp-login.php`

`nginx` is the internal Docker service name and should never appear in a browser redirect. Confirm `WORDPRESS_PUBLIC_URL=https://yourdomain.com` is set, redeploy (the stack repairs `siteurl`/`home` on startup, but only when it detects an internal-host value), and try again in a private window.

### Phase 3 — Wildcard domain in Dokploy (subdomain mode only)

Dokploy → **Domains** tab → add domain `*.yourdomain.com` → service `nginx` → port `80` → **Reload**. Traefik now routes all subdomain requests to nginx, which passes them to WordPress; WordPress uses the `HTTP_HOST` header to pick the right subsite.

### Caching compatibility

Both Redis Object Cache and MilliCache are fully compatible with multisite — MilliCache caches per unique URL, so `site1.yourdomain.com/` and `site2.yourdomain.com/` are cached independently, no extra config needed.

### Creating sub-sites

**Network Admin → Sites → Add New**. For subdomain mode, enter just the prefix (e.g. `site1` for `site1.yourdomain.com`).

### Disabling Multisite

1. Set `WP_MULTISITE_MODE=disabled` in Dokploy Environment.
2. Remove the multisite constants from `WORDPRESS_MULTISITE_CONFIG`.
3. Redeploy.

> **Warning:** reverting after sub-sites exist makes those sub-sites inaccessible. Back up the database first.

---

## How updates reach an existing deployment

### Custom stack images (nginx, WordPress, plugin-installer)

These are published to GHCR under a specific version tag (not `:latest`) that gets bumped by this project's own release process — check `blueprints/dokploypress/docker-compose.yml` for the exact tag currently pinned. Updating means pulling the new pinned version, not an automatic background update:

- **Option A (One-Click Template):** Dokploy stored a snapshot of the compose YAML at create time — it does **not** auto-update. Go to the service's **Compose** tab, update the image tags to match the current `blueprints/dokploypress/docker-compose.yml` in this repo, then **Redeploy**.
- **Option B (GitHub-linked):** **General → Pull** fetches the latest blueprint compose (including the current pinned tags), then **Redeploy**.

### Third-party images (MariaDB, Redis, phpMyAdmin, optional SFTP)

Also version-pinned (see the README's version tables). To move to a newer pinned version yourself: edit the `image:` tag in the **Compose** tab, then **Redeploy**. MariaDB specifically — read [Upgrading the Database](#upgrading-the-database-mariadb-106--118) above before doing this, it's not a plain tag bump.

### Compose file changes in general (new services, new env vars)

Same two paths as above — Option A needs a manual **Compose** tab edit, Option B just needs **Pull** then **Redeploy**. New environment variables that ship with a default apply automatically on Redeploy; ones without a default need to be added manually in the **Environment** tab first. `CHANGELOG.md` documents which is which for every release, plus anything that needs action versus what's automatic.

### Your data is always safe across an update

Docker volumes (`wordpress_data`, `db_data`, `redis_data`, `db_backup`) are named and persistent — a standard Redeploy never deletes them, only a manual `docker volume rm` would. The one exception: if the Compose project name changes underneath you (e.g. after certain kinds of service renames in Dokploy), a redeploy can create *new*, empty volumes instead of reusing the old ones — see [Renaming the Stack](#renaming-the-stack-in-dokploy--will-it-break-updates) above. Always back up the database before a major update regardless.

---

## Related Documentation

- [Main README](../README.md) — start here for deploying and configuring the stack
- [File Browser Setup](./filebrowser-setup.md) — browser-based file manager
- [SFTP Setup](./sftp-setup.md) — SFTP file access
- [VS Code Remote Setup](./vscode-remote-setup.md) — edit files directly in VS Code
- [CHANGELOG](../CHANGELOG.md) — what changed in each release
