#!/bin/bash
# =============================================================================
# install-plugins.sh
# KSM WPDokploystack — Cache plugin installer (one-shot sidecar)
#
# Downloads and extracts Redis Object Cache and MilliCache into wp-content/plugins.
# Activation and drop-in setup are handled by the WordPress entrypoint via WP-CLI.
#
# @package KSM-WPDokploystack
# @since   1.8.0
# =============================================================================

set -e

WORDPRESS_PATH="/var/www/html"
PLUGINS_PATH="${WORDPRESS_PATH}/wp-content/plugins"
REDIS_PLUGIN_URL="https://downloads.wordpress.org/plugin/redis-cache.latest-stable.zip"
MILLICACHE_PLUGIN_URL="https://github.com/MilliPress/MilliCache/releases/download/v1.6.2/millicache.zip"

echo "=== KSM Cache Plugin Installer ==="

# Wait for WordPress to be ready (check for wp-config.php)
echo "Waiting for WordPress to be ready..."
RETRY_COUNT=0
MAX_RETRIES=60

while [ ! -f "${WORDPRESS_PATH}/wp-config.php" ]; do
	RETRY_COUNT=$((RETRY_COUNT + 1))
	if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
		echo "ERROR: WordPress not ready after ${MAX_RETRIES} attempts. Exiting."
		exit 1
	fi
	echo "Waiting for WordPress... (attempt ${RETRY_COUNT}/${MAX_RETRIES})"
	sleep 5
done

echo "WordPress is ready!"
mkdir -p "${PLUGINS_PATH}"

install_plugin_zip() {
	local name="$1"
	local url="$2"
	local expected_dir="$3"

	if [ -d "${PLUGINS_PATH}/${expected_dir}" ]; then
		echo "${name} is already installed. Skipping download."
		return 0
	fi

	echo "Downloading ${name}..."
	cd /tmp
	curl -fsSL -o "${expected_dir}.zip" "${url}"

	if [ ! -f "${expected_dir}.zip" ]; then
		echo "ERROR: Failed to download ${name}."
		exit 1
	fi

	echo "Extracting ${name}..."
	unzip -q "${expected_dir}.zip" -d "${PLUGINS_PATH}/"
	rm -f "${expected_dir}.zip"

	if [ ! -d "${PLUGINS_PATH}/${expected_dir}" ]; then
		echo "ERROR: ${name} installation verification failed."
		exit 1
	fi

	echo "${name} installed successfully."
}

install_plugin_zip "Redis Object Cache" "${REDIS_PLUGIN_URL}" "redis-cache"
install_plugin_zip "MilliCache" "${MILLICACHE_PLUGIN_URL}" "millicache"

echo "=== Cache plugins installed. Entrypoint will activate on next WordPress start. ==="
