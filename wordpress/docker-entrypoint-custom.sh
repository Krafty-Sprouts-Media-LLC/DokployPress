#!/bin/bash
# =============================================================================
# docker-entrypoint-custom.sh
# DokployPress — WordPress container custom entrypoint
#
# Responsibilities:
#   1. Apply PHP/OPcache settings from environment variables
#   2. Ensure WordPress core files exist in volume (fresh installs)
#   3. Auto-correct wp-config.php if overwritten by a migration tool
#      (e.g. Migrate Guru) with host-specific values that don't match
#      this Docker stack's internal network configuration
#   3a. Repair siteurl/home if a Docker-internal host was stored
#   4. Enforce DISABLE_WP_CRON=true in wp-config.php via WP-CLI
#      (WORDPRESS_CONFIG_EXTRA only runs on fresh installs; this ensures
#       existing installs also get the constant on every container start)
#   4a. Enforce WP_ALLOW_MULTISITE in wp-config.php when WP_MULTISITE_MODE
#       is set to 'subfolder' or 'subdomain' — fixes missing Network Setup menu
#   5. Deploy DokployPress mu-plugins after core exists (avoids fresh-install wipe by tar extract)
#   6. Start php-fpm via upstream entrypoint
#      (Cache plugin activation runs via dokploypress-cache-bootstrap mu-plugin on first HTTP request.)
#
# @package DokployPress
# @since   1.7.0
# =============================================================================

set -e

# ---------------------------------------------------------------------------
# 1. PHP & OPcache settings from environment variables
# ---------------------------------------------------------------------------
PHP_INI_DIR="/usr/local/etc/php/conf.d"

cat > "${PHP_INI_DIR}/custom-settings.ini" << EOF
; Custom PHP Settings — Configurable via Environment Variables
; Generated at container start. Do not edit manually.
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-256M}
post_max_size       = ${PHP_POST_MAX_SIZE:-256M}
memory_limit        = ${PHP_MEMORY_LIMIT:-256M}
max_execution_time  = ${PHP_MAX_EXECUTION_TIME:-300}
max_input_time      = ${PHP_MAX_INPUT_TIME:-300}
max_input_vars      = ${PHP_MAX_INPUT_VARS:-3000}
EOF

cat > "${PHP_INI_DIR}/opcache-settings.ini" << EOF
; OPcache Settings — Configurable via Environment Variables
; Generated at container start. Do not edit manually.
opcache.enable                 = 1
opcache.memory_consumption     = ${PHP_OPCACHE_MEMORY:-128}
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files  = ${PHP_OPCACHE_MAX_FILES:-4000}
opcache.validate_timestamps    = ${PHP_OPCACHE_VALIDATE:-0}
opcache.revalidate_freq        = 60
opcache.fast_shutdown          = 1
opcache.enable_cli             = 0
EOF

# PHP-FPM pool sizing — defaults match the base wordpress:php8.3-fpm image's
# stock www.conf exactly (pm=dynamic, max_children=5, start_servers=2,
# min/max_spare_servers=1/3), so an install that never sets these env vars
# behaves identically to before this was configurable. Loads after www.conf
# (zz- prefix, same convention as the Dockerfile's zz-docker.conf status page)
# so these values win.
cat > /usr/local/etc/php-fpm.d/zz-dokploypress-pool.conf << EOF
; PHP-FPM Pool Settings — Configurable via Environment Variables
; Generated at container start. Do not edit manually.
[www]
pm = ${PHP_FPM_PM:-dynamic}
pm.max_children = ${PHP_FPM_MAX_CHILDREN:-5}
pm.start_servers = ${PHP_FPM_START_SERVERS:-2}
pm.min_spare_servers = ${PHP_FPM_MIN_SPARE_SERVERS:-1}
pm.max_spare_servers = ${PHP_FPM_MAX_SPARE_SERVERS:-3}
EOF

echo "[DokployPress] PHP settings configured:"
echo "  upload_max_filesize : ${PHP_UPLOAD_MAX_FILESIZE:-256M}"
echo "  post_max_size       : ${PHP_POST_MAX_SIZE:-256M}"
echo "  memory_limit        : ${PHP_MEMORY_LIMIT:-256M}"
echo "  max_execution_time  : ${PHP_MAX_EXECUTION_TIME:-300}s"
echo "  OPcache memory      : ${PHP_OPCACHE_MEMORY:-128}MB"
echo "  PHP-FPM pm          : ${PHP_FPM_PM:-dynamic}"
echo "  PHP-FPM max_children: ${PHP_FPM_MAX_CHILDREN:-5}"

WP_PATH="/var/www/html"
WP_CONFIG="${WP_PATH}/wp-config.php"
EXPECTED_DB_HOST="${WORDPRESS_DB_HOST:-db}"
EXPECTED_DB_USER="${WORDPRESS_DB_USER:-wordpress}"
EXPECTED_DB_NAME="${WORDPRESS_DB_NAME:-wordpress}"

normalize_public_url() {
    local url="${1%/}"

    case "${url}" in
        http://*|https://*)
            echo "${url}"
            ;;
        *)
            echo ""
            ;;
    esac
}

get_url_host() {
    php -r '
        $url = $argv[1] ?? "";
        $host = parse_url($url, PHP_URL_HOST);
        echo strtolower($host ?: "");
    ' "$1"
}

is_internal_url() {
    local url="$1"
    local host
    host="$(get_url_host "${url}")"

    if [ -z "${host}" ]; then
        return 0
    fi

    case "${host}" in
        nginx|wordpress|localhost)
            return 0
            ;;
    esac

    if php -r 'exit(filter_var($argv[1] ?? "", FILTER_VALIDATE_IP) ? 0 : 1);' "${host}"; then
        return 0
    fi

    case "${host}" in
        *.*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

repair_internal_site_url() {
    if [ -z "${WORDPRESS_PUBLIC_URL:-}" ]; then
        return 0
    fi

    if [ ! -f "${WP_CONFIG}" ]; then
        return 0
    fi

    if ! wp core is-installed --path="${WP_PATH}" --allow-root 2>/dev/null; then
        return 0
    fi

    local public_url
    public_url="$(normalize_public_url "${WORDPRESS_PUBLIC_URL}")"

    if [ -z "${public_url}" ]; then
        echo "[DokployPress] ⚠️  WORDPRESS_PUBLIC_URL must start with http:// or https://; skipping site URL repair."
        return 0
    fi

    local repaired=0
    local option
    local current_url

    for option in siteurl home; do
        current_url="$(wp option get "${option}" --path="${WP_PATH}" --allow-root 2>/dev/null || echo "")"

        if is_internal_url "${current_url}"; then
            wp option update "${option}" "${public_url}" --path="${WP_PATH}" --allow-root >/dev/null
            echo "[DokployPress] ✅ Repaired ${option}: ${current_url:-empty} → ${public_url}"
            repaired=1
        fi
    done

    if [ "${repaired}" = "1" ]; then
        wp cache flush --path="${WP_PATH}" --allow-root >/dev/null 2>&1 || true
        echo "[DokployPress] ✅ WordPress cache flushed after site URL repair."
    fi
}

apply_multisite_config() {
    if [ ! -f "${WP_CONFIG}" ]; then
        return 0
    fi

    local multisite_config="${WORDPRESS_MULTISITE_CONFIG:-}"

    case "${WP_MULTISITE_MODE:-disabled}" in
        subfolder|subdomain)
            ;;
        *)
            multisite_config=""
            ;;
    esac

    php -r '
        $config_file      = $argv[1] ?? "";
        $multisite_config = trim($argv[2] ?? "");
        $begin            = "// BEGIN DOKPLOYPRESS WORDPRESS_MULTISITE_CONFIG";
        $end              = "// END DOKPLOYPRESS WORDPRESS_MULTISITE_CONFIG";

        if ( "" === $config_file || ! is_readable( $config_file ) || ! is_writable( $config_file ) ) {
            exit( 1 );
        }

        $contents = file_get_contents( $config_file );

        if ( false === $contents ) {
            exit( 1 );
        }

        $pattern  = "/\n?" . preg_quote( $begin, "/" ) . ".*?" . preg_quote( $end, "/" ) . "\n?/s";
        $contents = preg_replace( $pattern, "\n", $contents );

        if ( "" !== $multisite_config ) {
            $block = $begin . PHP_EOL . $multisite_config . PHP_EOL . $end . PHP_EOL;
            $stop  = "/* That" . chr( 39 ) . "s all, stop editing! Happy publishing. */";

            if ( false !== strpos( $contents, $stop ) ) {
                $contents = str_replace( $stop, $block . PHP_EOL . $stop, $contents );
            } else {
                $require_single = "require_once ABSPATH . " . chr( 39 ) . "wp-settings.php" . chr( 39 ) . ";";
                $require_double = "require_once ABSPATH . \"wp-settings.php\";";

                if ( false !== strpos( $contents, $require_single ) ) {
                    $contents = str_replace( $require_single, $block . PHP_EOL . $require_single, $contents );
                } elseif ( false !== strpos( $contents, $require_double ) ) {
                    $contents = str_replace( $require_double, $block . PHP_EOL . $require_double, $contents );
                } else {
                    $contents = rtrim( $contents ) . PHP_EOL . PHP_EOL . $block;
                }
            }
        }

        if ( false === file_put_contents( $config_file, $contents ) ) {
            exit( 1 );
        }
    ' "${WP_CONFIG}" "${multisite_config}"

    if [ -n "${multisite_config}" ]; then
        echo "[DokployPress] ✅ WORDPRESS_MULTISITE_CONFIG applied to wp-config.php."
    else
        echo "[DokployPress] WORDPRESS_MULTISITE_CONFIG not active; managed multisite config block removed if present."
    fi
}

# ---------------------------------------------------------------------------
# 2. Ensure WordPress core files exist in volume (fresh install only)
#    The official image ships WordPress in /usr/src/wordpress. On first boot
#    it copies it into /var/www/html. We replicate that same copy here so
#    mu-plugins bundled in /usr/src/wordpress/wp-content/mu-plugins/ land
#    in the volume before php-fpm starts — no separate entrypoint call needed.
# ---------------------------------------------------------------------------
if [ ! -f "${WP_PATH}/wp-includes/version.php" ]; then
    echo "[DokployPress] Fresh volume — copying WordPress core files..."
    cp -a /usr/src/wordpress/. "${WP_PATH}/"
    chown -R www-data:www-data "${WP_PATH}"
    echo "[DokployPress] ✅ WordPress core copied (includes bundled mu-plugins)."
fi

# ---------------------------------------------------------------------------
# 3. wp-config.php migration auto-fix (Layer 1)
#    Runs every container start. Safe to run repeatedly — only acts when
#    values are actually wrong. Fixes DB connection and Redis config so
#    WordPress can boot after a migration tool (e.g. Migrate Guru) has
#    overwritten wp-config.php with the source host's settings.
# ---------------------------------------------------------------------------
if [ -f "${WP_CONFIG}" ]; then
    # Read the DB_HOST currently written in wp-config.php
    CURRENT_DB_HOST=$(grep -oP "(?<=DB_HOST', ')[^']+" "${WP_CONFIG}" 2>/dev/null || echo "")

    if [ -n "${CURRENT_DB_HOST}" ] && [ "${CURRENT_DB_HOST}" != "${EXPECTED_DB_HOST}" ]; then
        echo ""
        echo "[DokployPress] ⚠️  wp-config.php mismatch detected!"
        echo "[DokployPress]    Found DB_HOST='${CURRENT_DB_HOST}' — expected '${EXPECTED_DB_HOST}'"
        echo "[DokployPress]    Auto-correcting for Docker internal network..."

        # Fix database connection settings
        wp config set DB_HOST     "${EXPECTED_DB_HOST}"                  --path="${WP_PATH}" --allow-root
        wp config set DB_USER     "${EXPECTED_DB_USER}"                  --path="${WP_PATH}" --allow-root
        wp config set DB_PASSWORD "${WORDPRESS_DB_PASSWORD}"             --path="${WP_PATH}" --allow-root
        wp config set DB_NAME     "${EXPECTED_DB_NAME}"                  --path="${WP_PATH}" --allow-root

        # Restore cache constants only if a migration tool removed them.
        # WORDPRESS_CONFIG_EXTRA already injects these on normal boots — avoid duplicate define().
        for constant in WP_CACHE:true:raw WP_REDIS_HOST:redis WP_REDIS_PORT:6379 MC_STORAGE_HOST:redis MC_STORAGE_PORT:6379 MC_STORAGE_DB:1:raw; do
            IFS=':' read -r name value flags <<< "${constant}"
            if ! wp config has "${name}" --path="${WP_PATH}" --allow-root 2>/dev/null; then
                if [ "${flags}" = "raw" ]; then
                    wp config set "${name}" "${value}" --path="${WP_PATH}" --allow-root --raw
                else
                    wp config set "${name}" "${value}" --path="${WP_PATH}" --allow-root
                fi
            fi
        done

        echo "[DokployPress] ✅ wp-config.php corrected successfully."
        echo ""
        MIGRATION_DETECTED=1
    else
        echo "[DokployPress] wp-config.php DB_HOST looks correct (${CURRENT_DB_HOST:-not yet written})."
    fi

    # URL constants from the source host override database values — remove them
    # so WordPress uses siteurl/home from the migrated database (or fixer).
    for constant in WP_HOME WP_SITEURL; do
        if wp config has "${constant}" --path="${WP_PATH}" --allow-root 2>/dev/null; then
            wp config delete "${constant}" --path="${WP_PATH}" --allow-root
            echo "[DokployPress] ✅ Removed ${constant} from wp-config.php (stack uses database URLs)."
            MIGRATION_DETECTED=1
        fi
    done

fi

# ---------------------------------------------------------------------------
# 3a. Site URL repair for Docker-internal hosts
#     If a background/internal request caused siteurl/home to become "nginx",
#     restore them from WORDPRESS_PUBLIC_URL without touching valid domains.
# ---------------------------------------------------------------------------
repair_internal_site_url

# ---------------------------------------------------------------------------
# 4. Enforce DISABLE_WP_CRON constant in wp-config.php
#    WORDPRESS_CONFIG_EXTRA only writes constants on a fresh install.
#    To guarantee DISABLE_WP_CRON=true on all installs (new and existing),
#    we set it explicitly via WP-CLI on every container start.
#    Idempotent — safe to run on every boot.
# ---------------------------------------------------------------------------
if [ -f "${WP_CONFIG}" ]; then
    if ! wp config has DISABLE_WP_CRON --path="${WP_PATH}" --allow-root 2>/dev/null; then
        wp config set DISABLE_WP_CRON true --path="${WP_PATH}" --allow-root --raw
        echo "[DokployPress] ✅ DISABLE_WP_CRON set in wp-config.php (WP-Cron sidecar manages scheduling)."
    else
        echo "[DokployPress] DISABLE_WP_CRON already present in wp-config.php."
    fi
fi

# ---------------------------------------------------------------------------
# 4a. Enforce WP_ALLOW_MULTISITE constant when multisite mode is configured
#     Controls whether "Tools → Network Setup" appears in WP Admin.
#     Idempotent — uses WP-CLI, safe to run on every boot.
#
#     WP_MULTISITE_MODE values:
#       disabled  — (default) single-site install, no changes made
#       subfolder — multisite with path-based sub-sites (/site1, /site2)
#       subdomain — multisite with subdomain-based sub-sites (site1.domain.com)
#
#     NOTE: After "Tools → Network Setup" completes the wizard, WordPress
#     provides additional constants (MULTISITE, SUBDOMAIN_INSTALL, etc.).
#     Add those via WORDPRESS_MULTISITE_CONFIG in Dokploy and redeploy
#     — do NOT edit wp-config.php manually (it will be overwritten on restart).
# ---------------------------------------------------------------------------
if [ -f "${WP_CONFIG}" ]; then
    case "${WP_MULTISITE_MODE:-disabled}" in
        subfolder|subdomain)
            echo "[DokployPress] Multisite mode: ${WP_MULTISITE_MODE} — enforcing WP_ALLOW_MULTISITE..."
            if ! wp config has WP_ALLOW_MULTISITE --path="${WP_PATH}" --allow-root 2>/dev/null; then
                wp config set WP_ALLOW_MULTISITE true --path="${WP_PATH}" --allow-root --raw
                echo "[DokployPress] ✅ WP_ALLOW_MULTISITE set in wp-config.php (Tools → Network Setup now available)."
            else
                echo "[DokployPress] WP_ALLOW_MULTISITE already present in wp-config.php."
            fi
            apply_multisite_config
            ;;
        disabled|"")
            echo "[DokployPress] Multisite mode: disabled (single-site)."
            apply_multisite_config
            ;;
        *)
            echo "[DokployPress] ⚠️  Unknown WP_MULTISITE_MODE='${WP_MULTISITE_MODE}' — expected: disabled, subfolder, subdomain."
            apply_multisite_config
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# 5. Deploy DokployPress mu-plugins — always refresh from image bundle
# ---------------------------------------------------------------------------
MU_PLUGINS_DIR="${WP_PATH}/wp-content/mu-plugins"
mkdir -p "${MU_PLUGINS_DIR}"

deploy_mu_plugin() {
    local src="$1"
    local dest_name="$2"

    if [ ! -f "${src}" ]; then
        return 0
    fi

    local dest="${MU_PLUGINS_DIR}/${dest_name}"
    cp "${src}" "${dest}"
    chown www-data:www-data "${dest}"
    echo "[DokployPress] ✅ ${dest_name} deployed to mu-plugins/."
}

remove_legacy_mu_plugin() {
    local legacy_name="$1"
    local legacy_path="${MU_PLUGINS_DIR}/${legacy_name}"

    if [ -f "${legacy_path}" ]; then
        rm -f "${legacy_path}"
        echo "[DokployPress] ✅ Removed legacy mu-plugin ${legacy_name}."
    fi
}

deploy_mu_plugin "/usr/local/lib/dokploypress/dokploypress-migration-fixer.php" "dokploypress-migration-fixer.php"
deploy_mu_plugin "/usr/local/lib/dokploypress/dokploypress-cache-bootstrap.php" "dokploypress-cache-bootstrap.php"
remove_legacy_mu_plugin "ksm-migration-fixer.php"
remove_legacy_mu_plugin "ksm-cache-bootstrap.php"

# ---------------------------------------------------------------------------
# 5a. Auto-detect post-migration state and queue fixer on first HTTP request
#     Marker is consumed once by dokploypress-migration-fixer.php.
# ---------------------------------------------------------------------------
MARKER_FILE="${WP_PATH}/ksm-migration-pending.txt"

if [ -f "${WP_PATH}/migrategurupull.php" ] || [ -d "${WP_PATH}/mg_storage" ]; then
    MIGRATION_DETECTED=1
fi

if [ "${MIGRATION_DETECTED:-0}" = "1" ] && [ ! -f "${MARKER_FILE}" ]; then
    touch "${MARKER_FILE}"
    chown www-data:www-data "${MARKER_FILE}"
    echo "[DokployPress] ✅ Migration detected — ksm-migration-pending.txt marker created for fixer."
fi

# ---------------------------------------------------------------------------
# 6. Start php-fpm via upstream WordPress entrypoint
# ---------------------------------------------------------------------------
exec docker-entrypoint.sh "$@"
