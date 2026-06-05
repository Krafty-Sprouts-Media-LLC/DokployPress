# =============================================================================
# KSM WPDokploystack — Cache plugin installer image
#
# One-shot sidecar that downloads Redis Object Cache and MilliCache plugins.
#
# @package KSM-WPDokploystack
# @since   1.8.0
# =============================================================================

FROM alpine:3.19

RUN apk add --no-cache bash curl unzip

COPY install-plugins.sh /install-plugins.sh
RUN chmod +x /install-plugins.sh

ENTRYPOINT ["/install-plugins.sh"]
