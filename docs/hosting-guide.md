# Easily Host WordPress Sites Using Dokploy with Redis and Nginx

> **DokployPress:** Unofficial WordPress stack for Dokploy — by Krafty Sprouts Media. **Not affiliated with or endorsed by Dokploy.**

> **Original Article:** [Easily Host WordPress Sites Using Dokploy with Redis and Nginx](https://itsmereal.com/easily-host-wordpress-sites-using-dokploy-with-redis-and-nginx/)
> **Original Author:** Al-Mamun Talukder ([@almamunreal](https://twitter.com/almamunreal)) — Full-Stack Developer, Minimalist Designer, Tech Enthusiast. Founder of [Omnixima](https://itsmereal.com).
> **Published:** December 19, 2025 | **Adapted for DokployPress**

---

## Introduction

This guide is adapted from Al-Mamun Talukder's excellent article on hosting WordPress on Dokploy. The original author switched from Coolify (a Docker-based server management tool) to Dokploy, and to replicate the same production performance — featuring Redis caching, Nginx reverse proxying, and PHP-FPM — he created a custom Docker Compose stack specifically optimized for Dokploy.

This documentation captures those steps and supplements them with additional details for **DokployPress** deployments.

DokployPress is maintained by Krafty Sprouts Media LLC and is **not affiliated with or endorsed by Dokploy**.

For upgrading an existing 1.x install (`dokploy-wp-*` images), see [upgrade-to-2.0.0.md](upgrade-to-2.0.0.md).

---

## What Is Dokploy?

Dokploy is an open-source PaaS (Platform as a Service) solution that simplifies deploying and managing Docker-based applications on your own VPS. It supports Docker Compose services, provides a web dashboard, handles domains and SSL, and integrates with GitHub for automated deployments.

---

## Step 1 — Setting Up Dokploy

If Dokploy is not yet installed on your VPS, run the following command as root or a user with `sudo` access:

```bash
curl -sSL https://dokploy.com/install.sh | sh
```

> **Note:** Make sure the VPS is freshly provisioned for best results. Mixed installations (existing Docker, Nginx, etc.) can cause conflicts.

After the script finishes, open your browser and navigate to:

```
http://<your-vps-ip>:3000
```

This opens the Dokploy setup page where you can create the administrative account.

### Useful References

- **Official Dokploy Installation Docs:** https://docs.dokploy.com/docs/core/installation
- **YouTube Setup Guide:** https://www.youtube.com/watch?v=_FErnBwMpj8 — Covers initial Dokploy configuration, enabling SSL, and setting up a custom domain for the Dokploy dashboard itself.

---

## Step 2 — Understanding the WordPress Stack

Rather than using Dokploy's built-in official WordPress template (which can surface issues in long-term use), this stack uses a production-ready, custom Docker Compose configuration.

### Stack Components

| Service            | Description                                              |
|--------------------|----------------------------------------------------------|
| **WordPress**      | PHP 8.3 FPM with Redis extension, OPcache, and WP-CLI  |
| **Nginx**          | Optimized reverse proxy with caching and security headers|
| **MariaDB 10.6**   | Database server with health checks                       |
| **Redis**          | Shared Redis for object cache (DB 0) and MilliCache full-page cache (DB 1) |
| **phpMyAdmin**     | Database administration interface                        |
| **Plugin Installer** | Automatically installs Redis Object Cache and MilliCache |
| **WP-Cron**        | Alpine sidecar that triggers `wp-cron.php` every 5 min via the internal Docker network. Eliminates reliance on visitor traffic for scheduled tasks. |
| **SFTP** (optional) | Separate SFTP container — enable with `COMPOSE_PROFILES=tools` |

The stack is available at: **https://github.com/Krafty-Sprouts-Media-LLC/DokployPress**

---

## Step 3 — Deploying WordPress on Dokploy

### Option A: One-Click Template Deploy (Recommended)

1. In the Dokploy dashboard, navigate to **Projects**.
2. Create a new Project or open an existing one.
3. Click **Create Service**.
4. Choose **Template**.
5. Set the **Base URL** to:
   ```
   https://raw.githubusercontent.com/Krafty-Sprouts-Media-LLC/DokployPress/main
   ```
6. Find and select **"DokployPress"**.
7. Click **Create** and then **Confirm**.
8. Open **Environment** — `STACK_SLUG` is already set to the service ID under the stack name (e.g. `mysite-dokploypress-8zv3p5`, same string as on the **General** tab). **Before first Deploy**, replace it with your short project name (e.g. `STACK_SLUG=mysite`) so host volumes are `mysite_data`, `mysite_db_data`, `mysite_redis_data`.
9. Click **Deploy** once ready.

### Option B: Manual Compose Deploy (GitHub)

1. Create a new **Compose** service in Dokploy.
2. **Provider → GitHub** → Repository: `DokployPress` → Branch: `main`
3. Set **Compose Path** to:
   ```
   ./blueprints/dokploypress/docker-compose.yml
   ```
   This blueprint pulls pre-built `dokploypress-*` images from GHCR. The root `./docker-compose.yml` builds on the server and is for local development.
4. Go to the **Environment** tab and add:
   ```env
   STACK_SLUG=your-short-name
   MYSQL_ROOT_PASSWORD=YourSecureRootPass123!
   MYSQL_PASSWORD=YourSecureDbPass456!
   WORDPRESS_DB_PASSWORD=YourSecureDbPass456!
   ```
   Set `STACK_SLUG` to a short identifier (e.g. `mysite`) **before the first deploy**.
5. Click **Deploy**.

---

## Step 4 — Post-Deploy Configuration

These steps apply after either deployment option.

### 4a. Configure Domains

Go to the **Domains** tab in your Compose service and add:

| Domain                        | Service     | Port |
|-------------------------------|-------------|------|
| `yourdomain.com`              | nginx       | 80   |
| `pma.yourdomain.com` (optional) | phpmyadmin | 80  |

After adding domains, return to the **General** tab and click **Reload**.

> SSL is handled automatically by Dokploy via Let's Encrypt once the domain is pointed correctly.

**phpMyAdmin credentials:**

| Username    | Password              |
|-------------|-----------------------|
| `wordpress` | Your `MYSQL_PASSWORD` |

### 4b. Caching (Automatic)

After you complete the WordPress setup wizard on a new site, the stack handles caching for you:

1. **Plugin Installer** downloads Redis Object Cache and MilliCache into `wp-content/plugins`.
2. The **cache-bootstrap mu-plugin** activates both plugins and enables their drop-ins on the first front-end page load after WordPress is installed.

No manual activation in wp-admin is required. To verify:

```bash
docker exec -it <wordpress-container-name> bash
wp redis status
wp millicache status
wp millicache test
```

| Layer | Plugin | Redis DB | What it caches |
|-------|--------|----------|----------------|
| Object cache | Redis Object Cache | 0 | DB queries and PHP objects |
| Full-page cache | MilliCache | 1 | Complete rendered HTML pages |

Both layers use the same `redis` container. MilliCache connects via `MC_STORAGE_HOST=redis` (Docker internal DNS). **No Nginx changes are required** — MilliCache uses WordPress's `advanced-cache.php` drop-in, not Nginx FastCGI cache.

### 4c. Fresh install — plugins and mu-plugins not showing?

On a **new** site you should see:

| Location | What |
|----------|------|
| **Plugins** | Redis Object Cache + MilliCache (inactive until bootstrap runs) |
| **Plugins → Must-Use** (bottom of screen) | DokployPress Cache Bootstrap + DokployPress Migration Fixer |

**Plugins stay inactive until the first front-end page load** (not wp-admin only). Visit your site homepage while logged out, then refresh **Plugins**.

If MilliCache is missing or mu-plugins are absent:

1. In Dokploy → **Logs** → open **plugin-installer** — confirm both plugins downloaded without errors.
2. **Redeploy** the stack (pulls fixed images from v1.8.7+). A WordPress container restart deploys mu-plugins into the volume.
3. Or fix manually via SSH:

```bash
docker exec -it <wordpress-container-name> bash
ls wp-content/plugins/millicache/millicache.php
ls wp-content/mu-plugins/
wp plugin activate redis-cache millicache --allow-root
wp redis enable --allow-root
wp millicache drop --allow-root
```

---

## Environment Variable Reference

### Stack Naming

On template **Create**, Dokploy pre-fills **Environment** with `STACK_SLUG` equal to the service ID shown under the stack name on the **General** tab (e.g. `mysite-dokploypress-8zv3p5`). There is no separate wizard field — check **Environment** after create.

**Replace before first Deploy** (recommended):

1. **Create** the service — **do not Deploy yet**
2. Open **Environment** — note the pre-filled value, e.g. `STACK_SLUG=mysite-dokploypress-8zv3p5`
3. **Replace** with your short project slug, e.g. `STACK_SLUG=mysite`
4. Click **Deploy** (first deploy only)

| Variable      | Default                                      | Description |
|---------------|----------------------------------------------|-------------|
| `STACK_SLUG`  | Pre-filled service ID (template). Manual compose: `COMPOSE_PROJECT_NAME` if unset | Volume prefix: `{STACK_SLUG}_data`, `{STACK_SLUG}_db_data`, `{STACK_SLUG}_redis_data`. |

> **Important:** Changing `STACK_SLUG` after the first deploy does **not** rename existing volumes. Docker creates new empty volumes under the new name. Your site data remains in the old volumes until you migrate manually.

On the VPS (WinSCP/SSH), you will see volume **folders** like `/var/lib/docker/volumes/mysite_data/`. WordPress files are in the **`_data` subfolder** inside that volume:

```
/var/lib/docker/volumes/mysite_data/_data/
```

That inner `_data` path is the site root (`wp-admin`, `wp-content`, `wp-includes`). Do not edit files only at `/var/lib/docker/volumes/mysite_data/` without the `_data` suffix.

### Database Configuration

| Variable                  | Default     | Description                      |
|---------------------------|-------------|----------------------------------|
| `MYSQL_ROOT_PASSWORD`     | —           | **Required.** MariaDB root password |
| `MYSQL_DATABASE`          | `wordpress` | Database name                    |
| `MYSQL_USER`              | `wordpress` | Database user                    |
| `MYSQL_PASSWORD`          | —           | **Required.** Database password  |
| `WORDPRESS_DB_HOST`       | `db`        | Database host                    |
| `WORDPRESS_DB_USER`       | `wordpress` | WordPress database user          |
| `WORDPRESS_DB_PASSWORD`   | —           | **Required.** WordPress DB password |
| `WORDPRESS_DB_NAME`       | `wordpress` | WordPress database name          |

### PHP Settings

| Variable                      | Default | Description                    |
|-------------------------------|---------|--------------------------------|
| `PHP_UPLOAD_MAX_FILESIZE`     | `256M`  | Maximum upload file size       |
| `PHP_POST_MAX_SIZE`           | `256M`  | Maximum POST data size         |
| `PHP_MEMORY_LIMIT`            | `256M`  | PHP memory limit               |
| `PHP_MAX_EXECUTION_TIME`      | `300`   | Script timeout in seconds      |
| `PHP_MAX_INPUT_TIME`          | `300`   | Input parsing timeout          |
| `PHP_MAX_INPUT_VARS`          | `3000`  | Maximum input variables        |

### OPcache Settings

| Variable                   | Default | Description                              |
|----------------------------|---------|------------------------------------------|
| `PHP_OPCACHE_MEMORY`       | `128`   | OPcache memory in MB                     |
| `PHP_OPCACHE_MAX_FILES`    | `4000`  | Maximum cached files                     |
| `PHP_OPCACHE_VALIDATE`     | `0`     | Validate timestamps (0=off for production)|

### Nginx Settings

| Variable                     | Default | Description                  |
|------------------------------|---------|------------------------------|
| `NGINX_CLIENT_MAX_BODY_SIZE` | `256M`  | Maximum upload size in Nginx |

### Redis Settings

| Variable                  | Default         | Description          |
|---------------------------|-----------------|----------------------|
| `REDIS_MAXMEMORY`         | `512mb`         | Redis maximum memory |
| `REDIS_MAXMEMORY_POLICY`  | `allkeys-lru`   | Eviction policy      |

### WordPress Settings

| Variable               | Default | Description |
|------------------------|---------|-------------|
| `WORDPRESS_PUBLIC_URL` | —       | Public site URL, e.g. `https://yourdomain.com`. Dokploy blueprints set this automatically from the main domain. Used to repair `siteurl`/`home` if they were accidentally set to a Docker-internal host such as `nginx`. |

### WP-Cron Settings

| Variable           | Default | Description                                                                 |
|--------------------|---------|-----------------------------------------------------------------------------|
| `WP_CRON_INTERVAL` | `300`   | Seconds between each `wp-cron.php` trigger. Lower = more frequent; default is 5 minutes. |

### Multisite Settings

| Variable             | Default    | Description                                                                   |
|----------------------|------------|-------------------------------------------------------------------------------|
| `WP_MULTISITE_MODE`  | `disabled` | WordPress Multisite mode. `disabled` = single-site (default). `subfolder` = path-based sub-sites (`/site1`, `/site2`). `subdomain` = subdomain-based sub-sites (`site1.domain.com`). See **WordPress Multisite** section below. |
| `WORDPRESS_MULTISITE_CONFIG` | — | Optional WordPress-generated multisite constants. Must be entered as the value of this environment variable, not as standalone `define(...)` environment rows. The entrypoint writes it into a managed `wp-config.php` block after running Network Setup. |

### Resource Limits

| Variable                  | Default | Description               |
|---------------------------|---------|---------------------------|
| `NGINX_CPU_LIMIT`         | `0.5`   | Nginx CPU limit            |
| `NGINX_MEMORY_LIMIT`      | `256M`  | Nginx memory limit         |
| `WORDPRESS_CPU_LIMIT`     | `1.0`   | WordPress CPU limit        |
| `WORDPRESS_MEMORY_LIMIT`  | `1G`    | WordPress memory limit     |
| `DB_CPU_LIMIT`            | `1.0`   | MariaDB CPU limit          |
| `DB_MEMORY_LIMIT`         | `1G`    | MariaDB memory limit       |
| `REDIS_CPU_LIMIT`         | `0.5`   | Redis CPU limit            |
| `REDIS_MEMORY_LIMIT`      | `512M`  | Redis memory limit         |
| `PHPMYADMIN_CPU_LIMIT`    | `0.5`   | phpMyAdmin CPU limit       |
| `PHPMYADMIN_MEMORY_LIMIT` | `256M`  | phpMyAdmin memory limit    |

---

## Updating the Stack

### What a New Version Means

When this repo releases a new version (e.g., `1.4.0` → `1.6.0`), the changes typically fall into one of three categories:

| Change type | Example | Auto-applied on Redeploy? |
|---|---|---|
| Docker image update | Nginx config change, PHP version bump | ✅ Yes — `:latest` is pulled |
| Compose file change | New service, new env var | ⚠️ Depends on deploy method |
| Docs/template only | Guide updates, meta.json version | ✅ No container change needed |

---

### How Image Updates Work

#### Custom stack images (nginx, WordPress, plugin-installer)

Published to GHCR as `:latest`. When GitHub Actions builds a new release, **Redeploy** in Dokploy pulls the new image for these three services automatically.

| Service | Image | How to update |
|---------|-------|---------------|
| **nginx** | `ghcr.io/krafty-sprouts-media-llc/dokploypress-nginx:latest` | **Redeploy** — pulls latest GHCR build |
| **wordpress** (PHP-FPM) | `ghcr.io/krafty-sprouts-media-llc/dokploypress-wordpress:latest` | **Redeploy** — pulls latest (PHP version bumps ship in this image) |
| **plugin-installer** | `ghcr.io/krafty-sprouts-media-llc/dokploypress-plugin-installer:latest` | **Redeploy** — one-shot sidecar re-runs if plugins missing |

#### Third-party images (MariaDB, Redis, phpMyAdmin, optional SFTP)

| Service | Image | How to update |
|---------|-------|---------------|
| **MariaDB** | `mariadb:10.6` (pinned) | Edit the `image:` tag in the **Compose** tab (e.g. `mariadb:10.11`), back up the database first, then **Redeploy**. Major MariaDB jumps need a planned migration — not just a tag change. |
| **Redis** | `redis:alpine` | **Redeploy** pulls the current Alpine build. Pin a version (e.g. `redis:7-alpine`) in Compose if you want reproducible updates. |
| **phpMyAdmin** | `phpmyadmin/phpmyadmin:latest` | **Redeploy** pulls latest. Pin a version in Compose for stricter control. |
| **SFTP** (optional) | `atmoz/sftp:latest` | **Redeploy** when `COMPOSE_PROFILES=tools` is enabled. |

> **Option A (template):** Dokploy stores a compose **snapshot** at create time. To change a pinned tag (e.g. MariaDB `10.6` → `10.11`), edit the **Compose** tab manually, then Redeploy. Image `:latest` services still update on Redeploy without compose edits.

> **Option B (GitHub-linked):** **General → Pull** fetches the latest blueprint compose from the repo, then **Redeploy**.

No action is required for custom GHCR images beyond clicking **Redeploy** after a new stack release.

---

### How Compose File Changes Reach You

This depends on which deployment option you used:

#### Option A (One-Click Template)

The template was consumed at deploy time — Dokploy stored a snapshot of the compose YAML. **Changes to the compose file in this repo do NOT automatically update your running service.**

To apply compose-level changes:
1. In Dokploy, go to the service's **Compose** tab.
2. Manually apply the relevant changes from `blueprints/dokploypress/docker-compose.yml` in this repo.
3. Click **Redeploy**.

#### Option B (Linked to GitHub Repo)

Dokploy can fetch the latest compose from the repo. To update:
1. In Dokploy, go to the service's **General** tab.
2. Click **Pull** to fetch the latest blueprint compose (`./blueprints/dokploypress/docker-compose.yml`).
3. Click **Redeploy**.

New or changed services, ports, and environment variable defaults will be applied.

---

### Your Data Is Always Safe

Docker volumes (`wordpress_data`, `db_data`, `redis_data`) are **named and persistent**. A standard Redeploy never deletes volumes — only a manual `docker volume rm` would.

> **Warning:** If the Compose project name changes (e.g., after a service rename in Dokploy), a redeploy may create new empty volumes. Always back up the database before a major update. See [phpMyAdmin — Common Tasks](#phpmyadmin--common-tasks) for export instructions.

---

### New Environment Variables in Updates

When a new version adds environment variables:

- **If the variable has a default** (e.g., `NEW_VAR=${NEW_VAR:-default_value}`), it applies automatically on Redeploy. No action needed.
- **If the variable is required** (no default), you must add it manually:
  1. Go to **Environment** tab in Dokploy.
  2. Add the new variable and its value.
  3. Click **Redeploy**.

The CHANGELOG always documents which new variables were introduced and whether they have defaults.

---

### Upgrading to v1.13.x — Existing Installs

v1.13.0 added the **WP-Cron sidecar**. v1.13.2 ensured `DISABLE_WP_CRON=true` is enforced via the entrypoint on every container start (new and existing installs alike). Here is what existing deployments need to do:

#### What changes automatically on Redeploy

| Change | Auto-applied? | Notes |
|--------|:---:|-------|
| `wp-cron` service starts | ✅ Yes (Option B) / ⚠️ Manual (Option A) | New service; must exist in your compose |
| `DISABLE_WP_CRON=true` in wp-config | ✅ Yes — v1.13.2+ | Set by entrypoint via WP-CLI on every container start. No manual action needed. |
| `WP_CRON_INTERVAL` env var | ✅ Default `300` | No action needed unless you want a different interval |

#### Option A (One-Click Template) — Manual compose edit required

Your compose snapshot does not have the `wp-cron` service. Add it manually:

1. In Dokploy → **Compose** tab of your service.
2. Add the following block before the `sftp:` service entry:

```yaml
  # ---------------------------------------------------------------------------
  # WP-Cron sidecar — triggers wp-cron.php every 5 min via internal network.
  # ---------------------------------------------------------------------------
  wp-cron:
    image: alpine:latest
    command:
      - /bin/sh
      - -c
      - |
        echo 'WP-Cron sidecar started. Interval: 300s'
        while true; do
          if wget -q -O /dev/null 'http://nginx/wp-cron.php?doing_wp_cron' 2>&1; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] wp-cron triggered"
          else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] wp-cron request failed"
          fi
          sleep "${WP_CRON_INTERVAL:-300}"
        done
    depends_on:
      nginx:
        condition: service_healthy
    networks:
      - internal
    restart: unless-stopped
```

3. Click **Redeploy**.

> **`DISABLE_WP_CRON` is handled automatically** — the WordPress entrypoint (v1.13.2+) sets it in `wp-config.php` via WP-CLI on every container start. You do not need to add it manually to `WORDPRESS_CONFIG_EXTRA`.

#### Option B (GitHub-linked) — Pull and Redeploy

1. In Dokploy → **General** tab → click **Pull**.
2. Click **Redeploy**.

The `wp-cron` service, updated compose, and `DISABLE_WP_CRON` enforcement are all picked up automatically.

#### Is there any risk?

> **No data risk.** The WP-Cron sidecar is a read-only HTTP client — it only calls `wp-cron.php`. It does not touch any files, volumes, or databases. A failed cron trigger is silently logged and retried in 5 minutes.

> **DISABLE_WP_CRON impact:** Before this change, WP fired pseudo-cron on every page load (if due). After this change, WP never fires cron on its own — the sidecar is solely responsible. If the `wp-cron` container is stopped or crashes, no scheduled jobs run until it restarts. `restart: unless-stopped` protects against this.

---

### Upgrading to v1.14.0 — Existing Installs

v1.14.0 adds WordPress Multisite support via `WP_MULTISITE_MODE`. Existing single-site deployments are **completely unaffected** — the new variable defaults to `disabled`.

#### What changes automatically on Redeploy

| Change | Auto-applied? | Notes |
|--------|:---:|-------|
| `WP_MULTISITE_MODE` env var | ✅ Default `disabled` | No action needed for single-site installs |
| Nginx multisite rewrites | ✅ Yes — v1.14.0+ | Guarded by `!-e` — safe no-ops on single-site |
| `WP_ALLOW_MULTISITE` enforcement | ✅ Only when `WP_MULTISITE_MODE` is set | Entrypoint Step 4a only acts on `subfolder`/`subdomain` |

#### Option A (One-Click Template) — No action needed for single-site

Your single-site install continues working with zero changes. If you want to **enable multisite**, add `WP_MULTISITE_MODE=subdomain` (or `subfolder`) to your Dokploy **Environment** tab and Redeploy. Then follow the **WordPress Multisite** section in this guide.

#### Option B (GitHub-linked) — Pull and Redeploy

1. In Dokploy → **General** tab → click **Pull**.
2. Click **Redeploy**.

The updated compose and entrypoint are picked up automatically. Single-site behaviour is unchanged.

---

### Updating Settings Without a Version Change

All PHP, Nginx, Redis, and resource limit settings can be changed **at any time without rebuilding images**:

1. Go to your Compose service in Dokploy.
2. Navigate to the **Environment** tab.
3. Update the desired variables.
4. Click **Redeploy**.

The containers will restart with the new settings applied.

---

## Using WP-CLI

WP-CLI is pre-installed in the WordPress container. To use it:

```bash
# Access the WordPress container
docker exec -it <wordpress-container-name> bash

# Run WP-CLI commands
wp plugin list
wp cache flush
wp core update
wp cron event run --due-now
```

---

## Troubleshooting

### WordPress Not Loading

1. Check if all containers are running in Dokploy (look for green status).
2. Verify database credentials match between services.
3. Check container logs for errors via Dokploy's Logs tab.

### Upload Size Issues

Ensure both PHP and Nginx limits are set to the same value:

```env
PHP_UPLOAD_MAX_FILESIZE=512M
PHP_POST_MAX_SIZE=512M
NGINX_CLIENT_MAX_BODY_SIZE=512M
```

### Redis Not Connecting

1. Verify the Redis container is healthy in Dokploy.
2. Run `wp redis status` and `wp millicache test` inside the WordPress container.
3. Go to **Settings → Redis** and click **Enable Object Cache**.
4. If still failing, check Redis settings in `wp-config.php` (auto-configured by this stack):
   ```php
   define('WP_REDIS_HOST', 'redis');
   define('WP_REDIS_PORT', 6379);
   define('WP_CACHE', true);
   ```

---

## MariaDB & phpMyAdmin — Full Walkthrough

> **Important:** MariaDB is **not a separate service you install** in Dokploy. It is already bundled in this Docker Compose stack as the `db` service. When you deploy the stack, all six containers (nginx, wordpress, db, redis, phpmyadmin, plugin-installer) start together automatically. **No separate MariaDB installation step exists.**

### How Services Are Connected — Internal Networking

All containers communicate over a private Docker network named `internal`. WordPress connects to MariaDB using the container name `db` as the hostname — Docker's internal DNS resolves this automatically. You never touch an IP address.

```
┌──────────────────────────────────────────────────────┐
│               Docker "internal" network              │
│                                                      │
│  [nginx] ──► [wordpress / php-fpm]                   │
│                       │                              │
│                       ├──► [db / MariaDB] ◄── [phpmyadmin]
│                       │                              │
│                       └──► [redis]                   │
│                                                      │
│  Only nginx & phpmyadmin are reachable from outside  │
└──────────────────────────────────────────────────────┘
```

The environment variables that wire WordPress to the database:

```env
WORDPRESS_DB_HOST=db          # Container name — Docker DNS resolves automatically
WORDPRESS_DB_USER=wordpress
WORDPRESS_DB_PASSWORD=<your password>
WORDPRESS_DB_NAME=wordpress
```

No manual connection step is needed. Everything is wired by the Compose file at deploy time.

### Setting Up phpMyAdmin Access

1. In Dokploy → **Domains** tab of your Compose service, add:
   - **Domain:** `pma.yourdomain.com`
   - **Service:** `phpmyadmin`
   - **Port:** `80`
2. Go to **General** tab → click **Reload**.
3. Navigate to `https://pma.yourdomain.com`.
4. Log in:
   - **Username:** `wordpress`
   - **Password:** value of `MYSQL_PASSWORD`

### After First Deployment

The database starts empty — WordPress auto-populates it during the **WordPress setup wizard** (first visit to your domain, where you set the site title, admin username, etc.).

### phpMyAdmin — Common Tasks

| Task | How |
|------|-----|
| Browse/edit tables | Left panel → select `wordpress` database |
| Import a `.sql` backup | **Import** tab → choose file → Go |
| Export/backup database | **Export** tab → Quick → Go |
| Run raw SQL | **SQL** tab |
| Change site URL | `wordpress` → `wp_options` → edit `siteurl` and `home` rows |

### Root Database Access (Advanced)

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

## Renaming the Stack in Dokploy — Will It Break Updates?

**Short answer: UI display names are safe. Volume names are controlled by `STACK_SLUG` — set it once before the first deploy.**

### Display name vs volume names

- The **display name** in Dokploy (e.g. "DokployPress") is cosmetic — rename anytime in **General**.
- **Docker volume names** come from `STACK_SLUG` (preferred) or Dokploy's `COMPOSE_PROJECT_NAME` fallback. They do **not** follow UI renames.

### Prevent long volume names

Set `STACK_SLUG` to a short site identifier **before the first deploy**:

```env
STACK_SLUG=mysite
```

Volumes become `mysite_data`, `mysite_db_data`, `mysite_redis_data`.

### What changing `STACK_SLUG` later does

> **Warning:** If you change `STACK_SLUG` after data exists, Docker creates **new empty volumes** with the new prefix. Your WordPress files, database, and Redis data stay in the **old** volumes (still on disk, but detached from the stack).

### Safe procedure for existing long-named volumes

1. Note current volume names: `docker volume ls | grep _data`
2. Back up database and `wp-content` before any compose changes.
3. Do **not** change `STACK_SLUG` on a live site unless you plan to migrate data into the new volumes.
4. UI display renames alone are safe — no redeploy required.

---

## Migrating WordPress Sites from Local Disk

If your existing WordPress sites store files on local server disk (uploads, themes, plugins) rather than object storage, here is the full migration workflow.

### What Needs Migrating

| Component | Method |
|-----------|--------|
| Database | Export `.sql` → Import via phpMyAdmin or WP-CLI |
| WordPress files (uploads, themes, plugins) | Upload via SFTP, File Browser, or WP-CLI |
| `wp-config.php` | **Not migrated** — auto-generated from env vars by this stack |
| Credentials/settings | Set via Dokploy environment variables at deploy time |

### Step 1 — Deploy the Empty Stack First

Deploy the stack as in Step 3. Complete the WordPress setup wizard with any temporary credentials. Wait until **all containers show as healthy** in Dokploy before proceeding.

### Step 2 — Export the Old Database

On your existing server (via SSH or the server's phpMyAdmin):

```bash
# Via SSH — using mysqldump
mysqldump -u <db_user> -p <database_name> > site_backup.sql

# Or via phpMyAdmin on the old server → Export → Quick → Go
```

### Step 3 — Export WordPress Files

```bash
# Compress wp-content for transfer
zip -r wp-content-backup.zip wp-content/uploads/ wp-content/themes/ wp-content/plugins/
```

### Step 4 — Upload Files to the New Server

Use one of the file access methods in this repo's docs:

- **[SFTP Setup](./sftp-setup.md)** — Best for large file transfers
- **[File Browser Setup](./filebrowser-setup.md)** — Browser-based drag & drop
- **[VS Code Remote Setup](./vscode-remote-setup.md)** — Best for developers

Upload files into the WordPress volume at `/var/www/html/wp-content/`.

### Step 5 — Import the Database

**Via phpMyAdmin (best for small/medium databases):**
1. Open `pma.yourdomain.com`
2. Select the `wordpress` database in the left panel
3. **Import** tab → choose `site_backup.sql` → **Go**

**Via WP-CLI (recommended for large databases):**
```bash
# Copy the SQL file into the container
docker cp site_backup.sql <wordpress-container-name>:/tmp/

# Import it
docker exec -it <wordpress-container-name> bash
wp db import /tmp/site_backup.sql --allow-root
```

### Step 6 — Update the Site URL

After import, the database still references your old domain. Update it with WP-CLI (this correctly handles PHP serialized data):

```bash
docker exec -it <wordpress-container-name> bash
wp search-replace 'https://old-domain.com' 'https://new-domain.com' --allow-root
wp cache flush --allow-root
```

Or manually in phpMyAdmin:
- Table `wp_options` → rows `siteurl` and `home` → update both values to the new domain.

### Step 7 — Fix File Permissions

```bash
docker exec -it <wordpress-container-name> bash
chown -R www-data:www-data /var/www/html/wp-content/
find /var/www/html/wp-content/ -type d -exec chmod 755 {} \;
find /var/www/html/wp-content/ -type f -exec chmod 644 {} \;
```

### Step 8 — Re-activate Redis Cache

```bash
docker exec -it <wordpress-container-name> bash
wp plugin activate redis-cache --allow-root
wp redis enable --allow-root
```

### Note on Local Disk vs. Object Storage

This stack stores `wp-content/uploads/` in the `wordpress_data` Docker volume on the **VPS disk**. This works well for most sites. To offload media to **S3 or Cloudflare R2**, install the **WP Offload Media** plugin — no changes to this stack's Docker configuration are required.

---

### Alternative Migration Method — Migrate Guru (Plugin-Based)

If you prefer a plugin-driven migration rather than manual export/import, **Migrate Guru** is a solid free option that handles large sites well and avoids the file size limits that affect other migration plugins.

**Plugin:** [Migrate Guru — WordPress.org](https://wordpress.org/plugins/migrate-guru/)

**How it works with this stack:**

1. Install and activate **Migrate Guru** on your **source site** (the existing live server).
2. On Migrate Guru, select **Other Host** as the destination type.
3. Provide destination credentials for however **you** access files on this server (SSH/SFTP volume path, optional SFTP container, etc.). See [SFTP Setup](./sftp-setup.md) for where WordPress files live on the VPS — e.g. `/var/lib/docker/volumes/<project-name>_data/_data/`. **You choose the path in the migration plugin** based on what works in your WinSCP session.
4. For the database, use phpMyAdmin or WP-CLI import after Migrate Guru transfers files.
5. Once the migration completes, run the URL update step:
   ```bash
   docker exec -it <wordpress-container-name> bash
   wp search-replace 'https://old-domain.com' 'https://new-domain.com' --allow-root
   wp cache flush --allow-root
   ```

> **Note:** Migrate Guru handles serialized data, multisite, and large databases gracefully. It is particularly useful when the source site is on shared hosting where SSH/mysqldump access is restricted.

---

## MilliCache Full-Page Caching (Built In)

**[MilliCache](https://github.com/MilliPress/MilliCache)** is bundled in this stack alongside Redis Object Cache. MilliCache stores complete HTML pages in Redis and serves them via the `advanced-cache.php` drop-in **before WordPress fully boots** on cache hits.

| | Redis Object Cache | MilliCache |
|---|---|---|
| **Caches** | DB queries and PHP objects | Entire rendered HTML page |
| **Drop-in** | `object-cache.php` | `advanced-cache.php` |
| **Redis DB** | 0 (default) | 1 (`MC_STORAGE_DB`) |
| **Nginx changes** | None | None |

### How it works in this stack

```
Visitor → Nginx → PHP-FPM → advanced-cache.php → Redis (hit) → HTML response
                                              ↓ (miss)
                                         Full WordPress boot → store in Redis
```

PHP-FPM still runs on cache hits (the drop-in is PHP), but WordPress core, plugins, and the database are skipped.

### wp-config constants (auto-applied)

```php
define( 'WP_CACHE', true );
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'MC_STORAGE_HOST', 'redis' );
define( 'MC_STORAGE_PORT', 6379 );
define( 'MC_STORAGE_DB', 1 );
```

### Important rules

- **Do not** install other page-cache plugins (WP Super Cache, W3 Total Cache, Cache Enabler) — only one plugin can own `advanced-cache.php`.
- **Keep** Redis Object Cache — MilliPress recommends both; they cache different layers.
- **Logged-in users** bypass MilliCache by default (personalized content).
- For large sites, increase `REDIS_MAXMEMORY` (e.g. `1gb`) in Dokploy Environment.

### Verify cache hits

```bash
wp millicache test
wp millicache stats
```

Or enable debug headers (`MC_CACHE_DEBUG`) and look for `X-MilliCache-Status: hit` on repeat anonymous visits.

---

## WP-Cron — Reliable Scheduled Tasks

WordPress's built-in pseudo-cron (`wp-cron.php`) only fires when a visitor hits the site. On low-traffic sites, this means scheduled events (e.g., scheduled posts, plugin cleanups, email queues) can be delayed by hours.

This stack ships a dedicated **WP-Cron sidecar** that triggers `wp-cron.php` on a fixed schedule regardless of traffic.

### How it works

```
[wp-cron container] ──every 5 min──► http://nginx/wp-cron.php?doing_wp_cron
                                           │
                                     [nginx] → [wordpress/php-fpm]
                                           │
                                     WordPress processes due events
```

The request travels over the **internal Docker network** — no SSL, no external DNS, no dependency on your public domain being reachable.

`DISABLE_WP_CRON=true` is set in `wp-config.php` so WordPress does **not** fire its own pseudo-cron on page load. The sidecar is the only scheduler.

### Verifying it's running

```bash
# View real-time cron log in Dokploy → Logs → wp-cron
# Or via SSH:
docker logs <compose-name>-wp-cron-1 --tail 20
```

Expected output every 5 minutes:

```
WP-Cron sidecar started. Interval: 300s
[2026-06-09 16:45:00] wp-cron triggered
[2026-06-09 16:50:00] wp-cron triggered
```

### Manually triggering cron (WP-CLI)

```bash
docker exec -it <wordpress-container-name> bash
wp cron event run --due-now --allow-root
wp cron event list --allow-root
```

### Changing the cron interval

Add to Dokploy **Environment**, then **Redeploy**:

```env
WP_CRON_INTERVAL=60   # Every 1 minute (high-frequency sites)
WP_CRON_INTERVAL=600  # Every 10 minutes (low-activity sites)
```

### Disabling the sidecar

If you want to manage WP-Cron yourself (e.g., via a host-level system cron or Cronicle):

1. Remove or comment out the `wp-cron:` service block in your compose.
2. Remove `define('DISABLE_WP_CRON', true);` from `WORDPRESS_CONFIG_EXTRA` — or add `DISABLE_WP_CRON=false` to Environment.
3. Redeploy.

---

## WordPress Multisite

This stack supports WordPress Multisite (Network) with a single environment variable. Both **subfolder** and **subdomain** network types are fully supported.

### How it works

Setting `WP_MULTISITE_MODE` to `subfolder` or `subdomain` causes the custom entrypoint to enforce `WP_ALLOW_MULTISITE=true` in `wp-config.php` via WP-CLI on every container start — the same idempotent pattern used for `DISABLE_WP_CRON`. This is what makes **Tools → Network Setup** appear in WP Admin.

The Nginx configuration already includes multisite-safe rewrites for both modes:

| Rewrite | Mode | Purpose |
|---------|------|---------|
| `rewrite /wp-admin$ … permanent` | Both | Trailing-slash redirect for subsite admin panels |
| `rewrite ^(/[^/]+)?(/wp-.*)` | Subfolder | Strips `/site1` prefix from `/site1/wp-admin` |
| `rewrite ^(/[^/]+)?(/.*\.php)` | Subfolder | Strips `/site1` prefix from `/site1/wp-login.php` |
| `location ^~ /blogs.dir` | Both (legacy) | Pre-WP 3.5 internal upload alias — no-op on all modern installs |

All rewrites are guarded by `!-e $request_filename` — they are no-ops on single-site installs.

> **Note:** Modern WordPress multisite (3.5+, 2013) stores uploads at `wp-content/uploads/sites/N/` and serves them as standard static files. No special nginx rules are needed for uploads.

### Subdomain vs Subfolder — which to choose

| | Subfolder | Subdomain |
|---|---|---|
| Sub-sites at | `yourdomain.com/site1/` | `site1.yourdomain.com` |
| DNS required | Single A record | **Wildcard DNS** `*.yourdomain.com` |
| Traefik config | Standard | Wildcard domain rule required |
| Can convert later | ✅ Yes (WP CLI) | ✅ Yes (WP CLI) |
| Install on existing WP? | ✅ Yes | ✅ Yes |

> **Important for subdomain mode:** You **must** add a wildcard DNS record (`*.yourdomain.com → your server IP`) at your DNS provider **before** the Network Setup wizard runs. Without wildcard DNS, new subsites will not resolve. In Dokploy, you also need a wildcard domain entry (`*.yourdomain.com`) pointing to the nginx service on port 80. DNS alone is not enough; Traefik/Dokploy still needs the wildcard domain route.

### Phase 1 — Enable Network Setup

1. Add to Dokploy **Environment**:
   ```env
   WP_MULTISITE_MODE=subdomain
   # or: WP_MULTISITE_MODE=subfolder
   ```
2. Click **Redeploy**.
3. Check **Logs → wordpress** — you should see:
   ```
   [KSM] Multisite mode: subdomain — enforcing WP_ALLOW_MULTISITE...
   [KSM] ✅ WP_ALLOW_MULTISITE set in wp-config.php (Tools → Network Setup now available).
   ```
4. Open WP Admin in a **private/incognito window** (bypasses full-page cache) → **Tools → Network Setup**.

### Phase 2 — Run the Network Setup Wizard

WordPress asks you to **deactivate all plugins** before creating the network. On this stack, Redis Object Cache and MilliCache are normally auto-activated by the `dokploypress-cache-bootstrap` mu-plugin. **From stack version 1.14.5 onward**, that bootstrap is paused automatically while Network Setup is in progress (`WP_ALLOW_MULTISITE` is true but `MULTISITE` is not yet defined), so you can deactivate plugins in wp-admin and they will stay off.

1. In **Plugins**, deactivate **Redis Object Cache** and **MilliCache** (and any other active plugins).
2. In **Tools → Network Setup**, choose your network type (must match `WP_MULTISITE_MODE`).
3. Enter a **Network Title** and **Network Admin Email**.
4. Click **Install**.
5. WordPress displays two blocks of code. **Do not** paste these directly into `wp-config.php` — the entrypoint manages that file. Instead:

**Add only the WordPress-generated multisite constants to `WORDPRESS_MULTISITE_CONFIG`** in Dokploy Environment. They must be the value of the `WORDPRESS_MULTISITE_CONFIG` variable.

If Dokploy shows a plain text environment editor, use one `KEY=value` line:

```env
WORDPRESS_MULTISITE_CONFIG=define( 'MULTISITE', true ); define( 'SUBDOMAIN_INSTALL', true ); define( 'DOMAIN_CURRENT_SITE', 'yourdomain.com' ); define( 'PATH_CURRENT_SITE', '/' ); define( 'SITE_ID_CURRENT_SITE', 1 ); define( 'BLOG_ID_CURRENT_SITE', 1 );
```

If Dokploy shows separate **Name** and **Value** fields, use this:

```text
Name: WORDPRESS_MULTISITE_CONFIG
Value:
define( 'MULTISITE', true );
define( 'SUBDOMAIN_INSTALL', true );
define( 'DOMAIN_CURRENT_SITE', 'yourdomain.com' );
define( 'PATH_CURRENT_SITE', '/' );
define( 'SITE_ID_CURRENT_SITE', 1 );
define( 'BLOG_ID_CURRENT_SITE', 1 );
```

Do **not** add bare `define(...)` lines as separate environment rows. They are PHP constants, not environment variable names, and the stack will not read them unless they are inside `WORDPRESS_MULTISITE_CONFIG`.

> For subfolder mode, `SUBDOMAIN_INSTALL` is `false` and WordPress may also add `define( 'MULTISITE_COOKIE_PATH', '/' );` and similar. Copy **exactly** what WordPress generated in the wizard — the values are specific to your install.

6. Click **Redeploy**.
7. Check **Logs → wordpress** for `WORDPRESS_MULTISITE_CONFIG applied to wp-config.php`.
8. Log back into WP Admin — you now have a **My Sites** menu and **Network Admin** panel.

#### Network Setup says an existing network was detected

This means WordPress found multisite database tables, so the network was already created or partially created. In most cases, do **not** remove database tables. Finish the setup by making sure `WORDPRESS_MULTISITE_CONFIG` contains the generated constants, redeploy, and confirm the log line `WORDPRESS_MULTISITE_CONFIG applied to wp-config.php`.

#### Network Setup: plugins keep reactivating (stack before 1.14.5)

If Redis Object Cache and MilliCache turn back on immediately after you deactivate them, the cache bootstrap mu-plugin is re-activating them on every page load. Use either approach:

**Option A — Temporary disable bootstrap (no image rebuild):**

```bash
docker exec -it <wordpress-container-name> bash
if [ -f /var/www/html/wp-content/mu-plugins/dokploypress-cache-bootstrap.php ]; then
  mv /var/www/html/wp-content/mu-plugins/dokploypress-cache-bootstrap.php \
     /var/www/html/wp-content/mu-plugins/dokploypress-cache-bootstrap.php.off
elif [ -f /var/www/html/wp-content/mu-plugins/ksm-cache-bootstrap.php ]; then
  mv /var/www/html/wp-content/mu-plugins/ksm-cache-bootstrap.php \
     /var/www/html/wp-content/mu-plugins/ksm-cache-bootstrap.php.off
fi
wp plugin deactivate redis-cache millicache --allow-root --path=/var/www/html
```

Then deactivate any remaining plugins in wp-admin, complete **Tools → Network Setup**, add `WORDPRESS_MULTISITE_CONFIG` in Dokploy, and **Redeploy**. The entrypoint restores the mu-plugin from the image on redeploy.

**Option B — Upgrade to stack 1.14.5+** (bootstrap pauses automatically during Network Setup), then deactivate plugins in wp-admin and continue the wizard.

### If WP Admin redirects to `https://nginx/wp-login.php`

`nginx` is the internal Docker service name and should never appear in browser redirects. This can happen if an internal request writes the Docker hostname into WordPress `siteurl` or `home`.

1. Confirm `WORDPRESS_PUBLIC_URL=https://yourdomain.com` is set in Dokploy **Environment**. New blueprint deployments set this automatically from the main domain.
2. Click **Redeploy**.
3. Check **Logs → wordpress** for `Repaired siteurl` or `Repaired home`.
4. Open WP Admin again in a private/incognito window.

The repair is intentionally narrow: it only changes `siteurl`/`home` when the current value is an internal host such as `nginx`, `wordpress`, `localhost`, an IP address, or a non-domain container name.

### Phase 3 — Wildcard domain in Dokploy (subdomain mode only)

1. In Dokploy → **Domains** tab of your Compose service, add:
   - **Domain:** `*.yourdomain.com`
   - **Service:** `nginx`
   - **Port:** `80`
2. Click **Reload**.

Traefik will now route all subdomain requests to the nginx container, which passes them to WordPress. WordPress uses the `HTTP_HOST` header to determine which subsite to serve.

### Caching compatibility

Both Redis Object Cache and MilliCache are **fully compatible** with multisite. MilliCache stores full-page cache per unique URL, so `site1.yourdomain.com/` and `site2.yourdomain.com/` are cached independently. No additional configuration is required.

### Creating sub-sites

Once Network Setup is complete, go to **Network Admin → Sites → Add New**. For subdomain mode, enter just the subdomain prefix (e.g. `site1` for `site1.yourdomain.com`).

### Disabling Multisite

To revert to single-site:

1. Change `WP_MULTISITE_MODE=disabled` in Dokploy Environment.
2. Remove the multisite constants (`MULTISITE`, `SUBDOMAIN_INSTALL`, etc.) from `WORDPRESS_MULTISITE_CONFIG`.
3. Redeploy.

> **Warning:** Reverting multisite after sub-sites have been created will make those sub-sites inaccessible. Back up the database before reverting.

---

## Related Documentation

- [File Browser Setup](./filebrowser-setup.md) — Access WordPress files via a browser-based file manager
- [SFTP Setup](./sftp-setup.md) — Access WordPress files via SFTP
- [VS Code Remote Setup](./vscode-remote-setup.md) — Edit WordPress files directly in VS Code

---

## Credits

This guide is adapted from an article by **Al-Mamun Talukder** published on [itsmereal.com](https://itsmereal.com).

> **Original Article:** [Easily Host WordPress Sites Using Dokploy with Redis and Nginx](https://itsmereal.com/easily-host-wordpress-sites-using-dokploy-with-redis-and-nginx/)
> © Al-Mamun Talukder — shared with attribution under the spirit of open knowledge. All credit for the original concept, Docker Compose stack design, and article content belongs to the original author.
