FROM nginx:1.30-alpine

# Install envsubst (part of gettext) and wget for healthcheck
RUN apk add --no-cache gettext wget

# Copy nginx config template, shared security-headers snippet, and entrypoint
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY security-headers.conf /etc/nginx/snippets/security-headers.conf
COPY docker-entrypoint.sh /docker-entrypoint-custom.sh
RUN chmod +x /docker-entrypoint-custom.sh

EXPOSE 80

ENTRYPOINT ["/docker-entrypoint-custom.sh"]
CMD ["nginx", "-g", "daemon off;"]
