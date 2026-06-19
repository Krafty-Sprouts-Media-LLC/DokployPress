# KSM WordPress Stack

Production-ready WordPress deployment stack optimized for Dokploy with Redis object cache, MilliCache full-page caching, Nginx, and management tools.

Forked and extended from [itsmereal/dokploy-wp](https://github.com/itsmereal/dokploy-wp) by [Al-Mamun Talukder](https://itsmereal.com).

## Stack Components

| Service | Description |
|---------|-------------|
| **WordPress** | PHP 8.3 FPM with Redis extension, OPcache, and WP-CLI |
| **Nginx** | Optimized reverse proxy with caching and security headers |
| **MariaDB 10.6** | Database server with health checks |
| **Redis** | Shared store for object cache (DB 0) and MilliCache full-page cache (DB 1) |
| **phpMyAdmin** | Database administration interface |
| **Plugin Installer** | Automatically installs Redis Object Cache and MilliCache plugins |
| **WP-Cron** | Alpine sidecar — triggers `wp-cron.php` every 5 min via internal Docker network. Ensures scheduled events run regardless of traffic. |
| **SFTP** (optional) | Separate SFTP container — enable with `COMPOSE_PROFILES=tools` |

## Quick Start

Pick one of the two deploy methods below, then follow the shared **Post-Deploy Setup** steps.

### Option A: One-Click Template Deploy (Auto-Generated Passwords)

1. In Dokploy, go to **Projects**
2. Create a Project or open an existing Project
3. Click **Create Service**
4. Choose **Template**
5. Set the **Base URL** to:
   ```
   https://raw.githubusercontent.com/Krafty-Sprouts-Media-LLC/WPDokploystack/main
   ```
6. You will find **"KSM WordPress Stack"**
7. Click **Create** and **Confirm**
8. Open **Environment** — `STACK_SLUG` is **already set** to the service ID shown under the stack name (e.g. `mysite-ksmwpstack-8zv3p5`). **Before first Deploy**, replace it with your short project name (e.g. `STACK_SLUG=mysite`) so volumes are `mysite_data`, not `mysite-ksmwpstack-8zv3p5_data`
9. Click **Deploy**

### Option B: Manual Compose Deploy

1. Create a new **Compose** service in Dokploy
2. Point to: `https://github.com/Krafty-Sprouts-Media-LLC/WPDokploystack`
3. Set Compose Path: `./docker-compose.yml`
4. Go to **Environment** tab and add:
   ```
   STACK_SLUG=your-short-name
   MYSQL_ROOT_PASSWORD=YourSecureRootPass123!
   MYSQL_PASSWORD=YourSecureDbPass456!
   WORDPRESS_DB_PASSWORD=YourSecureDbPass456!
   ```
   Use a short `STACK_SLUG` (e.g. `mysite`) **before the first deploy** so volumes are named `mysite_data`, not a long Dokploy-generated name.
5. Click **Deploy**

## Post-Deploy Setup

These steps apply to both deploy options.

### 1. Configure Domains

Go to the **Domains** tab and add:

| Domain | Service | Port |
|--------|---------|------|
| yourdomain.com | nginx | 80 |
| pma.yourdomain.com (optional) | phpmyadmin | 80 |

Then return to the **General** tab and click **Reload**.

**phpMyAdmin credentials:**
| Username | Password |
|----------|----------|
| wordpress | (your `MYSQL_PASSWORD`) |

### 2. Complete WordPress Setup

1. Visit `yourdomain.com` and finish the WordPress installation wizard (if this is a new site).
2. Load any front-end page once while logged out — caching activates automatically.

The stack installs both plugins via the plugin-installer sidecar, then activates and enables **Redis Object Cache** and **MilliCache** automatically on the first front-end page load (cache-bootstrap mu-plugin). No manual steps in wp-admin are required.

### 3. Verify Caching (Optional)

```bash
docker exec -it <wordpress-container-name> bash
wp redis status
wp millicache status
wp millicache test
```

For browser verification, add `define('MC_CACHE_DEBUG', true);` to wp-config (or via **Settings → MilliCache**), then check response headers: `X-MilliCache-Status: hit` on repeat visits (logged out).

### 4. Accessing WordPress files (Optional)

WordPress files live in a Docker volume on the VPS. In WinSCP you may see the volume folder first; the site root is the **`_data` subfolder inside it**:

```
/var/lib/docker/volumes/<stack-slug>_data/_data/
```

With `STACK_SLUG=mysite`, browse to `/var/lib/docker/volumes/mysite_data/_data/` — that inner `_data` folder contains `wp-admin`, `wp-content`, `wp-includes`, etc. The volume folder `mysite_data` alone is not the WordPress root.

Use WinSCP/SSH to the VPS (port 22) and browse there. An optional **SFTP container** is also available — enable with `COMPOSE_PROFILES=tools` in Dokploy Environment. See [docs/sftp-setup.md](docs/sftp-setup.md).

## Environment Variables

### Stack Naming

After **Create**, Dokploy pre-fills **Environment** with `STACK_SLUG` matching the service ID under the stack name (e.g. `mysite-ksmwpstack-8zv3p5`). That value becomes your Docker volume prefix if you deploy as-is.

**Before first Deploy**, replace it with a short name (usually your Dokploy **project** name):

1. **Create** the service from the template — **do not Deploy yet**
2. Open **Environment** — you will see e.g. `STACK_SLUG=mysite-ksmwpstack-8zv3p5`
3. **Replace** with `STACK_SLUG=mysite`
4. Click **Deploy** (first deploy only — changing `STACK_SLUG` later creates new empty volumes)

Result on the VPS:

| `STACK_SLUG` | Docker volumes |
|--------------|----------------|
| `mysite` (short — recommended) | `mysite_data`, `mysite_db_data`, `mysite_redis_data` |
| `mysite-ksmwpstack-8zv3p5` (left as-is) | `mysite-ksmwpstack-8zv3p5_data`, etc. |

| Variable | Default | Description |
|----------|---------|-------------|
| `STACK_SLUG` | Pre-filled service ID on template create. Manual compose: unset → `COMPOSE_PROJECT_NAME` | Docker volume prefix. Replace the auto value before first Deploy for short paths. |

### Database Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MYSQL_ROOT_PASSWORD` | - | **Required.** MariaDB root password |
| `MYSQL_DATABASE` | wordpress | Database name |
| `MYSQL_USER` | wordpress | Database user |
| `MYSQL_PASSWORD` | - | **Required.** Database password |
| `WORDPRESS_DB_HOST` | db | Database host |
| `WORDPRESS_DB_USER` | wordpress | WordPress database user |
| `WORDPRESS_DB_PASSWORD` | - | **Required.** WordPress database password |
| `WORDPRESS_DB_NAME` | wordpress | WordPress database name |

### PHP Settings (No Rebuild Required)

| Variable | Default | Description |
|----------|---------|-------------|
| `PHP_UPLOAD_MAX_FILESIZE` | 256M | Maximum upload file size |
| `PHP_POST_MAX_SIZE` | 256M | Maximum POST data size |
| `PHP_MEMORY_LIMIT` | 256M | PHP memory limit |
| `PHP_MAX_EXECUTION_TIME` | 300 | Script timeout in seconds |
| `PHP_MAX_INPUT_TIME` | 300 | Input parsing timeout |
| `PHP_MAX_INPUT_VARS` | 3000 | Maximum input variables |

### OPcache Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PHP_OPCACHE_MEMORY` | 128 | OPcache memory in MB |
| `PHP_OPCACHE_MAX_FILES` | 4000 | Maximum cached files |
| `PHP_OPCACHE_VALIDATE` | 0 | Validate timestamps (0=off for production) |

### Nginx Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_CLIENT_MAX_BODY_SIZE` | 256M | Maximum upload size in Nginx |

### Redis Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_MAXMEMORY` | 512mb | Redis maximum memory |
| `REDIS_MAXMEMORY_POLICY` | allkeys-lru | Eviction policy |

### WP-Cron Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `WP_CRON_INTERVAL` | `300` | Seconds between each `wp-cron.php` trigger (default: 5 minutes). `DISABLE_WP_CRON=true` is set automatically in `wp-config.php` by the entrypoint — the sidecar is the sole scheduler. |

### Resource Limits (No Rebuild Required)

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_CPU_LIMIT` | 0.5 | Nginx CPU limit |
| `NGINX_MEMORY_LIMIT` | 256M | Nginx memory limit |
| `WORDPRESS_CPU_LIMIT` | 1.0 | WordPress CPU limit |
| `WORDPRESS_MEMORY_LIMIT` | 1G | WordPress memory limit |
| `DB_CPU_LIMIT` | 1.0 | MariaDB CPU limit |
| `DB_MEMORY_LIMIT` | 1G | MariaDB memory limit |
| `REDIS_CPU_LIMIT` | 0.5 | Redis CPU limit |
| `REDIS_MEMORY_LIMIT` | 512M | Redis memory limit |
| `PHPMYADMIN_CPU_LIMIT` | 0.5 | phpMyAdmin CPU limit |
| `PHPMYADMIN_MEMORY_LIMIT` | 256M | phpMyAdmin memory limit |

### SFTP (Optional — requires `COMPOSE_PROFILES=tools`)

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPOSE_PROFILES` | — | Set to `tools` to enable the SFTP service |
| `SFTP_USER` | wpuser | SFTP username |
| `SFTP_PASSWORD` | — | **Required** when `tools` profile is enabled |
| `SFTP_PORT` | 2222 | Public VPS port forwarded to the SFTP container |
| `SFTP_UID` | 33 | File owner UID (`www-data` in WordPress image) |
| `SFTP_CPU_LIMIT` | 0.25 | SFTP CPU limit |
| `SFTP_MEMORY_LIMIT` | 128M | SFTP memory limit |

When using the optional SFTP container, the WordPress root is `/public_html` in the SFTP client. The VPS Docker volume path under `/var/lib/docker/volumes/.../_data/` is only for direct VPS SSH access.

## Changing Settings After Deployment

All PHP, Nginx, Redis, and resource settings can be changed without rebuilding:

1. Go to your Compose service in Dokploy
2. Navigate to **Environment** tab
3. Update the desired variables
4. Click **Redeploy**

The containers will restart with the new settings.

## Using WP-CLI

WP-CLI is pre-installed in the WordPress container. To use it:

```bash
# Access the WordPress container
docker exec -it <wordpress-container-name> bash

# Run WP-CLI commands
wp plugin list
wp cache flush
wp core update
wp cron event list --allow-root
wp cron event run --due-now --allow-root
```

## Volumes

Named volumes use `STACK_SLUG` when set (e.g. `mysite_data`). Without `STACK_SLUG`, Docker falls back to Dokploy's compose project name.

| Volume suffix | Purpose |
|---------------|---------|
| `_data` | WordPress files (`/var/www/html`) |
| `_db_data` | MariaDB data |
| `_redis_data` | Redis persistence |

## Security Recommendations

1. Set strong passwords for all database credentials
2. Consider restricting access to phpMyAdmin subdomain
3. Enable Dokploy's built-in SSL/TLS
4. Keep WordPress and plugins updated

## Troubleshooting

### WordPress not loading

1. Check if all containers are running in Dokploy
2. Verify database credentials match between services
3. Check container logs for errors

### Upload size issues

Make sure both PHP and Nginx limits are set:

```env
PHP_UPLOAD_MAX_FILESIZE=512M
PHP_POST_MAX_SIZE=512M
NGINX_CLIENT_MAX_BODY_SIZE=512M
```

### Redis not connecting

1. Verify Redis container is healthy
2. Run `wp redis status` and `wp millicache test` inside the WordPress container
3. Confirm wp-config contains `WP_REDIS_HOST=redis` and `MC_STORAGE_HOST=redis`

### MilliCache not serving cached pages

1. Ensure you are logged out (logged-in users bypass full-page cache by default)
2. Run `wp millicache drop` inside the WordPress container
3. Check `wp millicache status` — `advanced_cache` should show `symlink` or `file`
4. Do not install other page-cache plugins (WP Super Cache, W3 Total Cache, etc.) — they conflict on `advanced-cache.php`

### WP-Cron not running / scheduled events delayed

1. In Dokploy → **Logs** → select the `wp-cron` container — you should see `[timestamp] wp-cron triggered` every 5 minutes
2. If you see `wp-cron request failed`, nginx may still be starting — it retries automatically
3. Verify `DISABLE_WP_CRON` is in wp-config: `grep DISABLE_WP_CRON /var/www/html/wp-config.php` inside the WordPress container
4. Check WordPress container startup logs for `[KSM] ✅ DISABLE_WP_CRON set in wp-config.php`
5. To manually trigger all due events: `wp cron event run --due-now --allow-root`

## Smoke Testing

Run a full integration test locally (requires Docker):

```bash
bash tests/smoke-test.sh
```

This starts the stack, installs WordPress, verifies Redis Object Cache and MilliCache (plugins, wp-config, WP-CLI, Redis connectivity), and checks HTTP responses. Use `--keep` to leave the stack running after the test:

```bash
bash tests/smoke-test.sh --keep
```

The same test runs automatically in GitHub Actions on every push to `main` (`.github/workflows/smoke-test.yml`).

## Acknowledgments

This stack is based on [dokploy-wp](https://github.com/itsmereal/dokploy-wp) by **Al-Mamun Talukder** ([@almamunreal](https://twitter.com/almamunreal)). See [itsmereal.com](https://itsmereal.com) for the original article and project.

Maintained and extended by [Krafty Sprouts Media LLC](https://github.com/Krafty-Sprouts-Media-LLC).

## License

MIT
