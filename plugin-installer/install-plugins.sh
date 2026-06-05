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
	unzip -q -o "${expected_dir}.zip" -d "${PLUGINS_PATH}/"
	rm -f "${expected_dir}.zip"

	if [ ! -d "${PLUGINS_PATH}/${expected_dir}" ]; then
		echo "ERROR: ${name} installation verification failed."
		exit 1
	fi

	echo "${name} installed successfully."
}

install_millicache() {
	local name="MilliCache"
	local expected_dir="millicache"
	local attempt=1
	local max_attempts=3

	if [ -f "${PLUGINS_PATH}/${expected_dir}/millicache.php" ]; then
		echo "${name} is already installed. Skipping download."
		return 0
	fi

	while [ "${attempt}" -le "${max_attempts}" ]; do
		echo "Downloading ${name} (attempt ${attempt}/${max_attempts})..."
		cd /tmp
		if curl -fsSL -o millicache.zip "${MILLICACHE_PLUGIN_URL}"; then
			mkdir -p "${PLUGINS_PATH}/${expected_dir}"
			unzip -q -o millicache.zip -d "${PLUGINS_PATH}/${expected_dir}/"
			rm -f millicache.zip

			if [ -f "${PLUGINS_PATH}/${expected_dir}/millicache.php" ]; then
				echo "${name} installed successfully."
				return 0
			fi
			echo "WARNING: ${name} extract verification failed on attempt ${attempt}."
		else
			echo "WARNING: Failed to download ${name} on attempt ${attempt}."
		fi
		attempt=$((attempt + 1))
		sleep 5
	done

	echo "ERROR: ${name} installation failed after ${max_attempts} attempts."
	return 1
}

fix_plugin_permissions() {
	if id www-data >/dev/null 2>&1; then
		chown -R www-data:www-data "${PLUGINS_PATH}" 2>/dev/null || true
	fi
}

install_plugin_zip "Redis Object Cache" "${REDIS_PLUGIN_URL}" "redis-cache"

if ! install_millicache; then
	echo "ERROR: MilliCache could not be installed. Redis Object Cache was installed."
	exit 1
fi

fix_plugin_permissions

echo "=== Cache plugins installed. Mu-plugin bootstrap activates them on first front-end request. ==="
