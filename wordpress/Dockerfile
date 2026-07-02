FROM wordpress:php8.3-fpm

# =============================================================================
# DokployPress — WordPress container image
#
# Extends the official WordPress PHP-FPM image with:
#   - GD, ZIP, OPcache PHP extensions
#   - Redis PHP extension (for WP Redis Object Cache)
#   - WP-CLI (for admin automation and the migration auto-fix)
#   - php-fpm-healthcheck (for Dokploy health checks)
#   - Custom entrypoint for env-driven PHP config and migration self-healing
#   - DokployPress Migration Fixer mu-plugin (Layer 2 of migration auto-fix)
#   - DokployPress Cache Bootstrap mu-plugin (activates cache plugins on first request)
#
# @package DokployPress
# @since   1.0.0
# =============================================================================

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libzip-dev \
    unzip \
    wget \
    libfcgi-bin \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd zip opcache

# Install Redis extension via PECL
RUN pecl install redis \
    && docker-php-ext-enable redis

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Install php-fpm-healthcheck
RUN wget -O /usr/local/bin/php-fpm-healthcheck \
    https://raw.githubusercontent.com/renatomefi/php-fpm-healthcheck/master/php-fpm-healthcheck \
    && chmod +x /usr/local/bin/php-fpm-healthcheck

# Enable PHP-FPM status page for healthcheck
RUN echo "pm.status_path = /status" >> /usr/local/etc/php-fpm.d/zz-docker.conf

# Copy custom entrypoint (handles PHP config + migration auto-fix Layer 1)
COPY docker-entrypoint-custom.sh /usr/local/bin/docker-entrypoint-custom.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-custom.sh

# Bundle DokployPress mu-plugins for entrypoint deploy and fresh-volume tar extract.
RUN mkdir -p /usr/local/lib/dokploypress /usr/src/wordpress/wp-content/mu-plugins
COPY dokploypress-migration-fixer.php /usr/local/lib/dokploypress/dokploypress-migration-fixer.php
COPY dokploypress-cache-bootstrap.php /usr/local/lib/dokploypress/dokploypress-cache-bootstrap.php
COPY dokploypress-migration-fixer.php /usr/src/wordpress/wp-content/mu-plugins/dokploypress-migration-fixer.php
COPY dokploypress-cache-bootstrap.php /usr/src/wordpress/wp-content/mu-plugins/dokploypress-cache-bootstrap.php

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html

ENTRYPOINT ["docker-entrypoint-custom.sh"]
CMD ["php-fpm"]
