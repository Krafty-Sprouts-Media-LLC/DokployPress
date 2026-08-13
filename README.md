# DokployPress

**Unofficial WordPress stack for Dokploy — by Krafty Sprouts Media**

A ready-to-deploy WordPress stack for [Dokploy](https://dokploy.com): WordPress + Nginx + MariaDB + Redis object cache + MilliCache full-page cache, wired together and pre-configured so a new site works out of the box. No server setup, no manually installing PHP/MySQL/Redis, no cache plugin configuration — you deploy one stack and get a fast, cached WordPress site.

> **Disclaimer:** DokployPress is an independent project by [Krafty Sprouts Media LLC](https://github.com/Krafty-Sprouts-Media-LLC). It is **not affiliated with or endorsed by** [Dokploy](https://dokploy.com) or the WordPress Foundation. Forked and extended from [itsmereal/dokploy-wp](https://github.com/itsmereal/dokploy-wp) by [Al-Mamun Talukder](https://itsmereal.com).

## Contents

- [What's in the stack](#whats-in-the-stack)
- [Deploy it](#deploy-it)
- [After you deploy](#after-you-deploy)
- [Configuration reference](#configuration-reference) — every setting, grouped and commented
- [Common tasks](#common-tasks)
- [Volumes — where your data lives](#volumes--where-your-data-lives)
- [Upgrading the database](#upgrading-the-database)
- [Security recommendations](#security-recommendations)
- [Troubleshooting](#troubleshooting)
- [Going further](#going-further) — advanced guides
- [Testing this repo's own changes](#testing-this-repos-own-changes)

---

## What's in the stack

One deploy starts these containers, already talking to each other correctly:

| Service | What it does |
|---|---|
| **WordPress** | Runs your site. PHP 8.4, with the Redis extension and OPcache already enabled. |
| **Nginx** | Sits in front of WordPress, serves static files, and forwards page requests to it. |
| **MariaDB** | The database. |
| **Redis** | One shared cache used two ways: WordPress object caching, and full-page caching (see MilliCache below). |
| **Plugin Installer** | Runs once on first deploy, installs the Redis Object Cache and MilliCache plugins for you. |
| **WP-Cron** | Triggers WordPress's scheduled tasks (scheduled posts, cleanup jobs, etc.) every 5 minutes, reliably — instead of relying on a visitor happening to load the site. |
| **phpMyAdmin** *(optional)* | A web UI for browsing/editing the database directly. Off by default — see [Optional tools](#optional-tools-phpmyadmin--sftp). |
| **SFTP** *(optional)* | A dedicated file-transfer login, separate from your server's own SSH login. Off by default — see [Optional tools](#optional-tools-phpmyadmin--sftp). |

You don't need to configure how these talk to each other — that's already done. The rest of this doc is about the choices *you* make: your domain, your passwords, and how much CPU/memory each part gets.

---

## Deploy it

Pick **one** of these two methods.

### Option A — One-click template (easiest, generates passwords for you)

1. In Dokploy, go to **Projects** → open or create a Project.
2. Click **Create Service** → **Template**.
3. For the **Base URL**, paste:
   ```
   https://raw.githubusercontent.com/Krafty-Sprouts-Media-LLC/DokployPress/main
   ```
4. Find **"DokployPress"** in the list, click **Create**, then **Confirm**.
5. Open the **Environment** tab. You'll see `STACK_SLUG` already filled in with something long, like `mysite-dokploypress-8zv3p5`. **Before you click Deploy**, shorten it to something simple, e.g.:
   ```env
   STACK_SLUG=mysite
   ```
   *(Why: this becomes the name of your site's storage on disk. Short now is much easier to read later — see [Volumes](#volumes--where-your-data-lives) for why this matters and why it's a one-time choice.)*
6. Click **Deploy**.

### Option B — Manual compose deploy (if you want to link this to GitHub)

1. In Dokploy, create a new **Compose** service.
2. Set **Provider** to **GitHub** → Repository: `DokployPress` → Branch: `main`.
3. Set **Compose Path** to:
   ```
   ./blueprints/dokploypress/docker-compose.yml
   ```
   *(This path uses pre-built images and is the one meant for real deployments. The plain `docker-compose.yml` at the repo root builds images from source on your own server — that one's for local development, not this.)*
4. Open the **Environment** tab and paste in:
   ```env
   # A short name for this site — becomes your volume/backup names on disk.
   # Pick this once, before your first deploy — see Volumes section for why.
   STACK_SLUG=mysite

   # Database passwords — make these strong and unique, they're not shown again.
   MYSQL_ROOT_PASSWORD=YourSecureRootPass123!
   MYSQL_PASSWORD=YourSecureDbPass456!
   WORDPRESS_DB_PASSWORD=YourSecureDbPass456!
   ```
5. Click **Deploy**.

Either way, once it's deployed, move on to the next section.

---

## After you deploy

Do these in order.

### 1. Point your domain at it

Go to the **Domains** tab in Dokploy and add:

| Domain | Service | Port |
|---|---|---|
| `yourdomain.com` | `nginx` | `80` |

Go back to **General** and click **Reload**. Dokploy/Traefik handles SSL automatically once the domain resolves.

### 2. Finish the WordPress setup wizard

Visit `yourdomain.com` — you'll land on WordPress's normal install screen (site title, admin username, admin password). Fill it in as you normally would.

### 3. Load the homepage once, logged out

After finishing the wizard, visit your homepage while **not** logged into WP Admin (use a private/incognito window if you're still logged in). This one visit is what activates caching — nothing else to do.

To double check it worked:

```bash
docker exec -it <wordpress-container-name> bash
wp redis status
wp millicache status
```

Both should report as connected/active. See [Verifying caching](#verifying-caching-works) in Common Tasks for what "working" looks like in more detail.

That's it — your site is live and cached. Everything past this point is optional configuration and reference material.

---

## Configuration reference

Every setting below is an environment variable you set in Dokploy's **Environment** tab, then click **Redeploy**. Nothing here requires rebuilding an image or editing a file — that's true for everything except the two marked ⚠️ below.

Copy whichever block you need, adjust the values, paste into Dokploy's Environment tab.

### Required — database credentials

These three have no default. The stack won't have a working database without them (already filled in for you if you used Option A).

```env
MYSQL_ROOT_PASSWORD=              # MariaDB's admin password
MYSQL_PASSWORD=                   # Password for the "wordpress" database user
WORDPRESS_DB_PASSWORD=            # Same value as MYSQL_PASSWORD — WordPress's copy of it
```

### Your site's identity

```env
# Public URL of your site. Blueprint deploys (Option A/B above) fill this in
# automatically from your domain. Only set it by hand if you're not using a
# blueprint, or if WP Admin ever redirects to a broken "nginx" URL — see
# Troubleshooting.
WORDPRESS_PUBLIC_URL=https://yourdomain.com

# Short name used for this site's storage on disk (Docker volumes/backups).
# Set this ONCE, before your first deploy. See Volumes section below for why
# changing it later is not simply a rename.
STACK_SLUG=mysite
```

### Uploads and script limits

```env
# How big a file can someone upload (media, plugin/theme zips, etc.)?
# All three must move together — see the note below.
PHP_UPLOAD_MAX_FILESIZE=256M
PHP_POST_MAX_SIZE=256M
NGINX_CLIENT_MAX_BODY_SIZE=256M

# PHP's own memory ceiling per request. Deliberately set HIGHER than the
# upload size above — receiving and then processing a big upload (e.g.
# generating image thumbnails) needs real headroom above the raw file size,
# not just enough to hold it.
PHP_MEMORY_LIMIT=384M

# How long (seconds) a single PHP script is allowed to run before it's
# killed — and how long Nginx will wait for PHP before giving up. These two
# MUST stay equal, or Nginx can cut off a request PHP would've finished.
# Raise both together (e.g. for a big import job), never just one.
PHP_MAX_EXECUTION_TIME=300
NGINX_FASTCGI_TIMEOUT=300

PHP_MAX_INPUT_TIME=300            # Time limit for parsing incoming request data
PHP_MAX_INPUT_VARS=3000           # Max number of form fields in one request
```

### Caching

```env
# Redis holds two things at once: WordPress's object cache, and MilliCache's
# full-page cache. Raise this if wp millicache status shows evictions/misses
# on a content-heavy site.
REDIS_MAXMEMORY=512mb
REDIS_MAXMEMORY_POLICY=allkeys-lru

# OPcache stores compiled PHP so it doesn't get re-parsed every request.
PHP_OPCACHE_MEMORY=128
PHP_OPCACHE_MAX_FILES=4000

# Leave at 1 (the default) unless your deploy process reliably restarts
# PHP-FPM after every code change — otherwise old code keeps serving until
# the container restarts, even after you update a plugin/theme.
PHP_OPCACHE_VALIDATE=1
```

*What these plugins actually do, and how to verify caching is working, is covered in [Common Tasks](#verifying-caching-works) and the deep-dive in [Going Further](#going-further).*

### How many requests can WordPress handle at once

```env
# How many PHP requests can run simultaneously. Once this many are busy,
# everything else queues — this is the #1 unstated cause of a site that's
# "slow" or throwing 502/504 errors under real traffic. Raising
# WORDPRESS_MEMORY_LIMIT alone does NOT fix this.
PHP_FPM_MAX_CHILDREN=6
PHP_FPM_PM=dynamic

# These three must satisfy: MIN_SPARE <= START <= MAX_SPARE, or PHP-FPM
# refuses to start. If you raise MAX_CHILDREN, scale these up proportionally
# (e.g. MAX_CHILDREN=20 → START=4, MIN_SPARE=2, MAX_SPARE=8).
PHP_FPM_START_SERVERS=2
PHP_FPM_MIN_SPARE_SERVERS=1
PHP_FPM_MAX_SPARE_SERVERS=4
```

**How to tell if you're hitting this limit:**

```bash
docker exec <wordpress-container-name> sh -c "SCRIPT_NAME=/status SCRIPT_FILENAME=/status REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000"
```

A nonzero `max children reached` in the output means the pool is the bottleneck.

**Sizing rule of thumb:** `PHP_FPM_MAX_CHILDREN ≈ (WORDPRESS_MEMORY_LIMIT × 0.75) / ~50-100MB per worker`. If you raise `PHP_FPM_MAX_CHILDREN` or `PHP_MEMORY_LIMIT` a lot for one specific site, raise `WORDPRESS_MEMORY_LIMIT` (below) to match — they're linked.

### Resource limits (how much CPU/memory each container gets)

```env
WORDPRESS_CPU_LIMIT=1.0
WORDPRESS_MEMORY_LIMIT=1G
DB_CPU_LIMIT=1.0
DB_MEMORY_LIMIT=1G
REDIS_CPU_LIMIT=0.5
REDIS_MEMORY_LIMIT=512M
NGINX_CPU_LIMIT=0.5
NGINX_MEMORY_LIMIT=256M
```

These defaults are sized to just work for one site (or a few) on a typical server, with no tuning. They're **not** the right numbers if you're running many WordPress sites on the same server — memory can't safely be oversubscribed the way CPU can (an over-limit container gets killed, not just slowed down). If that's your situation, don't touch these repo defaults; instead set smaller, host-specific values per site in each site's own Dokploy Environment tab. The math for working out those numbers: total available RAM × 0.6, divided across every site/app sharing the server, weighted by how many containers each one runs.

### WordPress scheduled tasks (WP-Cron)

```env
# How often (seconds) the WP-Cron sidecar triggers wp-cron.php.
# Lower = more responsive scheduled tasks, slightly more background load.
WP_CRON_INTERVAL=300
```

`DISABLE_WP_CRON=true` is set for you automatically — WordPress's own page-load-triggered pseudo-cron is turned off so this sidecar is the only scheduler. Nothing to configure there.

### Multisite (running more than one site from one WordPress install)

Most people don't need this — skip it unless you specifically want a WordPress Network.

```env
# disabled (default) | subfolder | subdomain
WP_MULTISITE_MODE=disabled

# Only set after running WordPress's own Network Setup wizard — it will
# generate this value for you. See "Going Further" for the full walkthrough.
WORDPRESS_MULTISITE_CONFIG=
```

### Optional tools: phpMyAdmin & SFTP

Both are **off by default** — they don't run, don't use resources, and aren't reachable, unless you turn them on:

```env
# Turns on BOTH phpMyAdmin and SFTP together (there's no separate switch
# for just one — if you only want one of the two, just don't set up
# domain/credentials for the other).
COMPOSE_PROFILES=tools
```

**phpMyAdmin** — once enabled, add a domain for it (**Domains** tab → `pma.yourdomain.com` → service `phpmyadmin` → port `80`), then log in with username `wordpress` and your `MYSQL_PASSWORD`.

```env
PHPMYADMIN_CPU_LIMIT=0.5
PHPMYADMIN_MEMORY_LIMIT=256M
```

**SFTP** — a separate login for file transfers, isolated from your server's own SSH.

```env
SFTP_USER=wpuser
SFTP_PASSWORD=                    # REQUIRED — see note below
SFTP_PORT=2222
SFTP_UID=33
SFTP_CPU_LIMIT=0.25
SFTP_MEMORY_LIMIT=128M
```

⚠️ **`SFTP_PASSWORD` has no default on purpose.** Leave it unset and the SFTP container starts but with a *locked* account — nobody can log in, including you, and Dokploy shows it as **unhealthy** so you notice. Set a real password to actually use it. Full walkthrough: [docs/sftp-setup.md](docs/sftp-setup.md).

### Bring your own variables (theme/plugin config)

Anything else you add in Dokploy's **Environment** tab reaches the WordPress container automatically via `getenv()` — no compose changes needed. Useful for a theme/plugin license key or an update-checker token:

```env
YOUR_VARIABLE_NAME=some-value
```

If a plugin/theme instead needs it as a PHP constant (`defined('YOUR_CONSTANT')` rather than `getenv()`), use this variable name instead — it gets written into `wp-config.php` for you, and reaches even already-running sites on redeploy:

```env
WORDPRESS_CONFIG_EXTRA_PERSISTENT=define('YOUR_CONSTANT', 'some-value');
```

---

## Common tasks

### Changing any setting above

1. Dokploy → your Compose service → **Environment** tab.
2. Change the variable(s).
3. Click **Redeploy**.

No rebuild needed for anything in the Configuration Reference above.

### Verifying caching works

```bash
docker exec -it <wordpress-container-name> bash
wp redis status              # should say "Status: Connected"
wp millicache test            # runs a live read/write test against Redis
wp millicache status          # should show storage: connected
```

To see it from the browser: turn on `MC_CACHE_DEBUG` (Settings → MilliCache, or `define('MC_CACHE_DEBUG', true);`), then check response headers on a repeat, logged-out visit for `X-MilliCache-Status: hit`.

### Using WP-CLI directly

```bash
docker exec -it <wordpress-container-name> bash
wp plugin list
wp cache flush
wp core update
wp cron event list --allow-root
```

---

## Volumes — where your data lives

Three things persist on disk, named using your `STACK_SLUG`:

| Volume | Contains |
|---|---|
| `<slug>_data` | Your WordPress files (`/var/www/html`) |
| `<slug>_db_data` | The database |
| `<slug>_redis_data` | Redis's persisted cache data |
| `<slug>_db_backup` | A one-time safety snapshot, only created during a MariaDB version upgrade — see [Upgrading the Database](#upgrading-the-database) |

**Why `STACK_SLUG` matters, and why to set it before your first deploy:** these volume names are fixed the moment they're first created. If you change `STACK_SLUG` *after* your site has data, Docker doesn't rename anything — it creates brand-new, empty volumes under the new name, and your actual site stays behind in the old ones (nothing is lost, but your live site now points at empty storage until you fix it). Pick the name once, at the start, and leave it alone.

If you deploy without ever touching `STACK_SLUG`, Dokploy's own long auto-generated name is used instead — everything still works, the volume names are just longer and harder to read on the server.

---

## Upgrading the database

The `db` service runs `mariadb:11.8`. If your site was deployed a while ago, it may be running an older MariaDB version underneath.

**What happens automatically on your next Redeploy:** the stack upgrades your existing database in place — no manual steps. Before it touches anything, a one-time safety snapshot is automatically taken into the `_db_backup` volume (see [Volumes](#volumes--where-your-data-lives) above).

**What's still on you:** this upgrade is **one-way** — there's no going back to an older MariaDB version once it's run, other than restoring a backup. Export your database (phpMyAdmin's Export tab, or `mariadb-dump`) before redeploying. The automatic snapshot is a safety net for this specific upgrade, not a substitute for that habit. The first restart after the version bump also takes a bit longer than usual while the upgrade runs — that's expected, not a hang.

Full explanation and the step-by-step restore procedure if something goes wrong: [docs/hosting-guide.md → Upgrading the Database](docs/hosting-guide.md#upgrading-the-database-mariadb-106--118).

---

## Security recommendations

1. Use strong, unique passwords for every database credential.
2. Only enable phpMyAdmin (`COMPOSE_PROFILES=tools`) when you're actively using it, or restrict access to its subdomain.
3. Dokploy handles SSL/TLS automatically once your domain resolves — make sure it's actually on.
4. Keep WordPress core, plugins, and themes updated as you normally would.

---

## Troubleshooting

**WordPress not loading**
1. Check that all containers show healthy/green in Dokploy.
2. Confirm the database passwords match between services (`MYSQL_PASSWORD` and `WORDPRESS_DB_PASSWORD` should be the same value).
3. Check container logs in Dokploy's **Logs** tab for the actual error.

**"413 Request Entity Too Large" or an upload silently fails**
All three of these need to move together — see [Uploads and script limits](#uploads-and-script-limits):
```env
PHP_UPLOAD_MAX_FILESIZE=512M
PHP_POST_MAX_SIZE=512M
NGINX_CLIENT_MAX_BODY_SIZE=512M
```

**504 Gateway Timeout on a slow request (large import, big migration, heavy report)**
Check these in order — raising one without the others won't fix it:
1. `PHP_MAX_EXECUTION_TIME` — is PHP itself even allowed to run that long?
2. `NGINX_FASTCGI_TIMEOUT` — must be `>=` the value above, or Nginx gives up on PHP first regardless of PHP's own limit.
3. If both are raised and it *still* 504s, the issue is one layer further out — Dokploy's own Traefik reverse proxy, which this stack doesn't control. That's a Dokploy-side thing to check next, not a setting in this repo.

**Redis not connecting**
1. Check the `redis` container is healthy in Dokploy.
2. Run `wp redis status` and `wp millicache test` inside the WordPress container (see [Common Tasks](#verifying-caching-works)).

**MilliCache not serving cached pages**
1. Make sure you're testing logged out — logged-in users always bypass the full-page cache.
2. `wp millicache drop` inside the container, then try again.
3. Don't run another full-page cache plugin (WP Super Cache, W3 Total Cache, etc.) alongside it — only one plugin can own the cache drop-in file, and they'll conflict.

**Scheduled posts / cron jobs running late**
1. Dokploy → **Logs** → `wp-cron` container — you should see a trigger line every `WP_CRON_INTERVAL` seconds (default 300).
2. `wp cron event run --due-now --allow-root` inside the WordPress container to run everything due right now.

**Database healthcheck failing right after a MariaDB version bump**
Expected to take a bit longer than a normal restart the first time — check the `db` container's logs for `mariadb-upgrade` output before assuming something's wrong. See [Upgrading the Database](#upgrading-the-database).

**WP Admin redirects to `https://nginx/wp-login.php`**
1. Confirm `WORDPRESS_PUBLIC_URL=https://yourdomain.com` is set (blueprint deploys set this automatically).
2. Redeploy — the stack repairs this on startup, but only when it detects the broken internal value.
3. Try again in a private/incognito window.

Multisite-specific troubleshooting (Network Setup issues, plugin reactivation, etc.) is in the [Going Further](#going-further) guide, since it only applies if you're using Multisite at all.

---

## Going further

Deeper material that most people won't need day-to-day, kept out of this file so the essentials above stay short:

- **[docs/hosting-guide.md](docs/hosting-guide.md)** — MariaDB/phpMyAdmin internals and root database access, the full database restore procedure, migrating an existing WordPress site onto this stack, how MilliCache and WP-Cron work under the hood, and the complete WordPress Multisite setup walkthrough.
- **[docs/sftp-setup.md](docs/sftp-setup.md)** — Full SFTP setup and usage.
- **[docs/filebrowser-setup.md](docs/filebrowser-setup.md)** — Browser-based file manager as an alternative to SFTP.
- **[docs/vscode-remote-setup.md](docs/vscode-remote-setup.md)** — Editing site files directly from VS Code.
- **[CHANGELOG.md](CHANGELOG.md)** — What changed in each release, including any action needed on redeploy for existing sites.

---

## Testing this repo's own changes

If you're contributing to DokployPress itself (not just deploying it), run the integration test locally:

```bash
bash tests/smoke-test.sh
```

Brings up the full stack, installs WordPress, and verifies both cache plugins actually work. Add `--keep` to leave the stack running afterward for manual poking around. The same test runs automatically in GitHub Actions on every push to `main`.

---

## Acknowledgments

Based on [dokploy-wp](https://github.com/itsmereal/dokploy-wp) by **Al-Mamun Talukder** ([@almamunreal](https://twitter.com/almamunreal)) — see [itsmereal.com](https://itsmereal.com) for the original article and project.

Maintained and extended by [Krafty Sprouts Media LLC](https://github.com/Krafty-Sprouts-Media-LLC). DokployPress is unofficial third-party software, not a Dokploy product.

## License

MIT
