#!/bin/sh
set -e

# Set default values if not set
export NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-256M}"
# Keep in sync with PHP_MAX_EXECUTION_TIME (wordpress/docker-entrypoint-custom.sh,
# default 300) — nginx gives up waiting on php-fpm at this value regardless of
# what PHP itself is allowed to run for. Raise both together.
export NGINX_FASTCGI_TIMEOUT="${NGINX_FASTCGI_TIMEOUT:-300}"

echo "Nginx configuration:"
echo "  client_max_body_size: ${NGINX_CLIENT_MAX_BODY_SIZE}"
echo "  fastcgi_timeout: ${NGINX_FASTCGI_TIMEOUT}s (keep >= PHP_MAX_EXECUTION_TIME)"

# Process the template and generate the actual config
envsubst '${NGINX_CLIENT_MAX_BODY_SIZE} ${NGINX_FASTCGI_TIMEOUT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf

echo "Nginx configuration generated successfully"

# Validate the generated config before starting nginx
nginx -t -c /etc/nginx/nginx.conf
echo "Nginx configuration test passed"

# Execute the main command
exec "$@"
