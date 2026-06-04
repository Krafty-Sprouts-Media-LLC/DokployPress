#!/bin/bash
set -e

# Generate PHP configuration from environment variables
PHP_INI_DIR="/usr/local/etc/php/conf.d"

# Create custom PHP settings
cat > "${PHP_INI_DIR}/custom-settings.ini" << EOF
; Custom PHP Settings - Configurable via Environment Variables
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-256M}
post_max_size = ${PHP_POST_MAX_SIZE:-256M}
memory_limit = ${PHP_MEMORY_LIMIT:-256M}
max_execution_time = ${PHP_MAX_EXECUTION_TIME:-300}
max_input_time = ${PHP_MAX_INPUT_TIME:-300}
max_input_vars = ${PHP_MAX_INPUT_VARS:-3000}
EOF

# Create OPcache configuration
cat > "${PHP_INI_DIR}/opcache-settings.ini" << EOF
; OPcache Settings - Configurable via Environment Variables
opcache.enable = 1
opcache.memory_consumption = ${PHP_OPCACHE_MEMORY:-128}
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = ${PHP_OPCACHE_MAX_FILES:-4000}
opcache.validate_timestamps = ${PHP_OPCACHE_VALIDATE:-0}
opcache.revalidate_freq = 60
opcache.fast_shutdown = 1
opcache.enable_cli = 0
EOF

echo "PHP settings configured:"
echo "  upload_max_filesize: ${PHP_UPLOAD_MAX_FILESIZE:-256M}"
echo "  post_max_size: ${PHP_POST_MAX_SIZE:-256M}"
echo "  memory_limit: ${PHP_MEMORY_LIMIT:-256M}"
echo "  max_execution_time: ${PHP_MAX_EXECUTION_TIME:-300}s"
echo "  OPcache memory: ${PHP_OPCACHE_MEMORY:-128}MB"

# Call the original WordPress entrypoint
exec docker-entrypoint.sh "$@"
