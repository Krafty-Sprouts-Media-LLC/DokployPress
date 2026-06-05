#!/bin/bash
# =============================================================================
# docker-entrypoint-custom.sh
# KSM WPDokploystack — WordPress container custom entrypoint
#
# Responsibilities:
#   1. Apply PHP/OPcache settings from environment variables
#   2. Auto-correct wp-config.php if overwritten by a migration tool
#      (e.g. Migrate Guru) with host-specific values that don't match
#      this Docker stack's internal network configuration
#   3. Ensure Redis Object Cache and MilliCache wp-config constants
#   4. Deploy the KSM Migration Fixer mu-plugin on every start
#   5. Hand off to the upstream WordPress entrypoint
#      (Cache plugin activation runs via ksm-cache-bootstrap mu-plugin on first HTTP request.)
#
# @package KSM-WPDokploystack
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

echo "[KSM] PHP settings configured:"
echo "  upload_max_filesize : ${PHP_UPLOAD_MAX_FILESIZE:-256M}"
echo "  post_max_size       : ${PHP_POST_MAX_SIZE:-256M}"
echo "  memory_limit        : ${PHP_MEMORY_LIMIT:-256M}"
echo "  max_execution_time  : ${PHP_MAX_EXECUTION_TIME:-300}s"
echo "  OPcache memory      : ${PHP_OPCACHE_MEMORY:-128}MB"

# ---------------------------------------------------------------------------
# 2. wp-config.php migration auto-fix (Layer 1)
#    Runs every container start. Safe to run repeatedly — only acts when
#    values are actually wrong. Fixes DB connection and Redis config so
#    WordPress can boot after a migration tool (e.g. Migrate Guru) has
#    overwritten wp-config.php with the source host's settings.
# ---------------------------------------------------------------------------
WP_PATH="/var/www/html"
WP_CONFIG="${WP_PATH}/wp-config.php"
EXPECTED_DB_HOST="${WORDPRESS_DB_HOST:-db}"
EXPECTED_DB_USER="${WORDPRESS_DB_USER:-wordpress}"
EXPECTED_DB_NAME="${WORDPRESS_DB_NAME:-wordpress}"

if [ -f "${WP_CONFIG}" ]; then
    # Read the DB_HOST currently written in wp-config.php
    CURRENT_DB_HOST=$(grep -oP "(?<=DB_HOST', ')[^']+" "${WP_CONFIG}" 2>/dev/null || echo "")

    if [ -n "${CURRENT_DB_HOST}" ] && [ "${CURRENT_DB_HOST}" != "${EXPECTED_DB_HOST}" ]; then
        echo ""
        echo "[KSM] ⚠️  wp-config.php mismatch detected!"
        echo "[KSM]    Found DB_HOST='${CURRENT_DB_HOST}' — expected '${EXPECTED_DB_HOST}'"
        echo "[KSM]    Auto-correcting for Docker internal network..."

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

        echo "[KSM] ✅ wp-config.php corrected successfully."
        echo ""
    else
        echo "[KSM] wp-config.php DB_HOST looks correct (${CURRENT_DB_HOST:-not yet written})."
    fi

fi

# ---------------------------------------------------------------------------
# 3. Deploy KSM Migration Fixer mu-plugin (Layer 2)
#    Copies the mu-plugin into wp-content/mu-plugins/ on every start so
#    it is always present even after a migration tool overwrites wp-content.
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
    if [ ! -f "${dest}" ] || [ "${src}" -nt "${dest}" ]; then
        cp "${src}" "${dest}"
        chown www-data:www-data "${dest}"
        echo "[KSM] ✅ ${dest_name} deployed to mu-plugins/."
    fi
}

deploy_mu_plugin "/usr/local/lib/ksm/ksm-migration-fixer.php" "ksm-migration-fixer.php"
deploy_mu_plugin "/usr/local/lib/ksm/ksm-cache-bootstrap.php" "ksm-cache-bootstrap.php"

# ---------------------------------------------------------------------------
# 4. Hand off to the upstream WordPress Docker entrypoint
# ---------------------------------------------------------------------------
exec docker-entrypoint.sh "$@"
