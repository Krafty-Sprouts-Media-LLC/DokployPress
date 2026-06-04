#!/bin/bash
set -e

WORDPRESS_PATH="/var/www/html"
PLUGINS_PATH="${WORDPRESS_PATH}/wp-content/plugins"
REDIS_PLUGIN_URL="https://downloads.wordpress.org/plugin/redis-cache.latest-stable.zip"

echo "=== Redis Object Cache Plugin Installer ==="

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

# Check if Redis Object Cache plugin is already installed
if [ -d "${PLUGINS_PATH}/redis-cache" ]; then
    echo "Redis Object Cache plugin is already installed. Skipping."
    exit 0
fi

# Create plugins directory if it doesn't exist
mkdir -p "${PLUGINS_PATH}"

# Download Redis Object Cache plugin
echo "Downloading Redis Object Cache plugin..."
cd /tmp
curl -sL -o redis-cache.zip "${REDIS_PLUGIN_URL}"

# Verify download
if [ ! -f "redis-cache.zip" ]; then
    echo "ERROR: Failed to download Redis Object Cache plugin."
    exit 1
fi

# Extract plugin
echo "Extracting plugin..."
unzip -q redis-cache.zip -d "${PLUGINS_PATH}/"

# Clean up
rm -f redis-cache.zip

# Verify installation
if [ -d "${PLUGINS_PATH}/redis-cache" ]; then
    echo "=== Redis Object Cache plugin installed successfully! ==="
    echo ""
    echo "Next steps:"
    echo "1. Log in to WordPress admin"
    echo "2. Go to Plugins > Installed Plugins"
    echo "3. Activate 'Redis Object Cache'"
    echo "4. Go to Settings > Redis"
    echo "5. Click 'Enable Object Cache'"
else
    echo "ERROR: Plugin installation verification failed."
    exit 1
fi

echo "Plugin installer completed."
