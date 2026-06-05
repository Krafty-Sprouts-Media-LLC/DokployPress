# Dokploy WordPress Stack

Production-ready WordPress deployment stack optimized for Dokploy with Redis object cache, MilliCache full-page caching, Nginx, and management tools.

## Stack Components

| Service | Description |
|---------|-------------|
| **WordPress** | PHP 8.3 FPM with Redis extension, OPcache, and WP-CLI |
| **Nginx** | Optimized reverse proxy with caching and security headers |
| **MariaDB 10.6** | Database server with health checks |
| **Redis** | Shared store for object cache (DB 0) and MilliCache full-page cache (DB 1) |
| **phpMyAdmin** | Database administration interface |
| **Plugin Installer** | Automatically installs Redis Object Cache and MilliCache plugins |

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
6. You will find **"WordPress + Redis Stack"**
7. Click **Create** and **Confirm**
8. Click **Deploy** when the service is created

### Option B: Manual Compose Deploy

1. Create a new **Compose** service in Dokploy
2. Point to: `https://github.com/Krafty-Sprouts-Media-LLC/WPDokploystack`
3. Set Compose Path: `./docker-compose.yml`
4. Go to **Environment** tab and add:
   ```
   MYSQL_ROOT_PASSWORD=YourSecureRootPass123!
   MYSQL_PASSWORD=YourSecureDbPass456!
   WORDPRESS_DB_PASSWORD=YourSecureDbPass456!
   ```
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

The stack installs both plugins via the plugin-installer sidecar, then activates and enables **Redis Object Cache** and **MilliCache** via the WordPress entrypoint and cache-bootstrap mu-plugin. No manual steps in wp-admin are required.

### 3. Verify Caching (Optional)

```bash
docker exec -it <wordpress-container-name> bash
wp redis status
wp millicache status
wp millicache test
```

For browser verification, add `define('MC_CACHE_DEBUG', true);` to wp-config (or via **Settings → MilliCache**), then check response headers: `X-MilliCache-Status: hit` on repeat visits (logged out).

## Environment Variables

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
```

## Volumes

| Volume | Purpose |
|--------|---------|
| `wordpress_data` | WordPress files (/var/www/html) |
| `db_data` | MariaDB data |
| `redis_data` | Redis persistence |

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

## License

MIT
