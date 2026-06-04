#!/bin/sh
set -e

# Set default value for NGINX_CLIENT_MAX_BODY_SIZE if not set
export NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-256M}"

echo "Nginx configuration:"
echo "  client_max_body_size: ${NGINX_CLIENT_MAX_BODY_SIZE}"

# Process the template and generate the actual config
envsubst '${NGINX_CLIENT_MAX_BODY_SIZE}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf

echo "Nginx configuration generated successfully"

# Execute the main command
exec "$@"
