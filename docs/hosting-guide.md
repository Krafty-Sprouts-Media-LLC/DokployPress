# Easily Host WordPress Sites Using Dokploy with Redis and Nginx

> **Original Article:** [Easily Host WordPress Sites Using Dokploy with Redis and Nginx](https://itsmereal.com/easily-host-wordpress-sites-using-dokploy-with-redis-and-nginx/)
> **Original Author:** Al-Mamun Talukder ([@almamunreal](https://twitter.com/almamunreal)) — Full-Stack Developer, Minimalist Designer, Tech Enthusiast. Founder of [Omnixima](https://itsmereal.com).
> **Published:** December 19, 2025 | **Adapted for KSM WPDokploystack use**

---

## Introduction

This guide is adapted from Al-Mamun Talukder's excellent article on hosting WordPress on Dokploy. The original author switched from Coolify (a Docker-based server management tool) to Dokploy, and to replicate the same production performance — featuring Redis caching, Nginx reverse proxying, and PHP-FPM — he created a custom Docker Compose stack specifically optimized for Dokploy.

This documentation captures those steps and supplements them with additional details for our KSM WPDokploystack deployment.

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

The stack is available at: **https://github.com/Krafty-Sprouts-Media-LLC/WPDokploystack**

---

## Step 3 — Deploying WordPress on Dokploy

### Option A: One-Click Template Deploy (Recommended)

1. In the Dokploy dashboard, navigate to **Projects**.
2. Create a new Project or open an existing one.
3. Click **Create Service**.
4. Choose **Template**.
5. Set the **Base URL** to:
   ```
   https://raw.githubusercontent.com/Krafty-Sprouts-Media-LLC/WPDokploystack/main
   ```
6. Find and select **"WordPress + Redis Stack"**.
7. Click **Create** and then **Confirm**.
8. Click **Deploy** once the service is created.

### Option B: Manual Compose Deploy

1. Create a new **Compose** service in Dokploy.
2. Point to: `https://github.com/Krafty-Sprouts-Media-LLC/WPDokploystack`
3. Set Compose Path: `./docker-compose.yml`
4. Go to the **Environment** tab and add:
   ```env
   MYSQL_ROOT_PASSWORD=YourSecureRootPass123!
   MYSQL_PASSWORD=YourSecureDbPass456!
   WORDPRESS_DB_PASSWORD=YourSecureDbPass456!
   ```
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
2. The **WordPress entrypoint** activates both plugins and enables their drop-ins via WP-CLI on every container start (once WordPress is installed).

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

---

## Environment Variable Reference

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

All images are tagged `:latest`. When GitHub Actions builds a new version, the `latest` tag in GHCR is overwritten. **Any Redeploy in Dokploy will pull the new image** for wordpress, nginx, and plugin-installer automatically.

No action is required from you beyond clicking **Redeploy** in Dokploy.

---

### How Compose File Changes Reach You

This depends on which deployment option you used:

#### Option A (One-Click Template)

The template was consumed at deploy time — Dokploy stored a snapshot of the compose YAML. **Changes to the compose file in this repo do NOT automatically update your running service.**

To apply compose-level changes:
1. In Dokploy, go to the service's **Compose** tab.
2. Manually apply the relevant changes from the updated `docker-compose.yml` in this repo.
3. Click **Redeploy**.

#### Option B (Linked to GitHub Repo)

Dokploy can fetch the latest compose from the repo. To update:
1. In Dokploy, go to the service's **General** tab.
2. Click **Pull** to fetch the latest `docker-compose.yml`.
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

**Short answer: Safe for display purposes. Watch out for full redeployments after rename.**

### What Renaming Changes

The **display name** shown in the Dokploy UI is cosmetic. You can rename it in the service's **General** tab at any time.

### What Renaming Does NOT Affect

- Running containers and their internal networking
- Domain and SSL configuration
- Volume data (WordPress files, database, Redis — stored in named Docker volumes)
- Future redeployments triggered from the Dokploy UI

### What to Watch Out For

> **Warning:** Dokploy may use the service name as the Docker project name (`COMPOSE_PROJECT_NAME`), which controls volume naming (e.g., `wordpress_data`). If a **full redeploy** is performed after renaming, Docker may treat it as a brand-new project and create empty volumes — leaving your data in the old volumes, detached.

### Safe Rename Procedure

1. In Dokploy → service **General** tab → edit the display name → Save.
2. **Do not** click Redeploy immediately after renaming.
3. The containers continue running under their existing Docker names.
4. If you must redeploy after a rename, first run `docker volume ls` on the server to confirm volume names haven't changed, and back up your database first.

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
3. Provide your new server's SFTP credentials (see [SFTP Setup](./sftp-setup.md)) — Migrate Guru will transfer files directly to the WordPress container volume.
4. For the database destination, provide the phpMyAdmin details or use the WP-CLI import approach after Migrate Guru transfers the files.
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

## Related Documentation

- [File Browser Setup](./filebrowser-setup.md) — Access WordPress files via a browser-based file manager
- [SFTP Setup](./sftp-setup.md) — Access WordPress files via SFTP
- [VS Code Remote Setup](./vscode-remote-setup.md) — Edit WordPress files directly in VS Code

---

## Credits

This guide is adapted from an article by **Al-Mamun Talukder** published on [itsmereal.com](https://itsmereal.com).

> **Original Article:** [Easily Host WordPress Sites Using Dokploy with Redis and Nginx](https://itsmereal.com/easily-host-wordpress-sites-using-dokploy-with-redis-and-nginx/)
> © Al-Mamun Talukder — shared with attribution under the spirit of open knowledge. All credit for the original concept, Docker Compose stack design, and article content belongs to the original author.
