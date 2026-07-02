#!/bin/bash
# =============================================================================
# multisite-regression-test.sh
# KSM WPDokploystack — Multisite release regression checks
#
# Verifies that multisite setup remains configurable through Dokploy environment
# variables and that migration URL repair cannot learn Docker-internal hosts.
#
# Usage (from repo root):
#   bash tests/multisite-regression-test.sh
#
# @package KSM-WPDokploystack
# @since   1.14.2
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass() {
	echo "[PASS] $*"
}

fail() {
	echo "[FAIL] $*"
	exit 1
}

assert_file_contains() {
	local file_path="$1"
	local expected="$2"
	local label="$3"

	if grep -Fq "${expected}" "${file_path}"; then
		pass "${label}"
		return 0
	fi

	fail "${label}: missing '${expected}' in ${file_path}"
}

assert_file_contains "${ROOT_DIR}/docker-compose.yml" 'WORDPRESS_MULTISITE_CONFIG=${WORDPRESS_MULTISITE_CONFIG:-}' "Main compose exposes multisite config env"
assert_file_contains "${ROOT_DIR}/docker-compose.yml" 'WORDPRESS_PUBLIC_URL=${WORDPRESS_PUBLIC_URL:-}' "Main compose exposes public URL env"
assert_file_contains "${ROOT_DIR}/blueprints/dokploypress/docker-compose.yml" 'WORDPRESS_MULTISITE_CONFIG=${WORDPRESS_MULTISITE_CONFIG:-}' "Blueprint compose exposes multisite config env"
assert_file_contains "${ROOT_DIR}/blueprints/dokploypress/docker-compose.yml" 'WORDPRESS_PUBLIC_URL=${WORDPRESS_PUBLIC_URL:-}' "Blueprint compose exposes public URL env"
assert_file_contains "${ROOT_DIR}/blueprints/dokploypress/template.toml" 'WORDPRESS_PUBLIC_URL=https://${main_domain}' "Blueprint template injects public URL"
assert_file_contains "${ROOT_DIR}/blueprints/dokploypress/docker-compose.yml" 'dokploypress-nginx' "Blueprint uses dokploypress GHCR images"
assert_file_contains "${ROOT_DIR}/template.toml" 'WORDPRESS_PUBLIC_URL=https://${main_domain}' "Root template injects public URL"
assert_file_contains "${ROOT_DIR}/wordpress/docker-entrypoint-custom.sh" 'repair_internal_site_url' "Entrypoint repairs internal site URLs"
assert_file_contains "${ROOT_DIR}/wordpress/docker-entrypoint-custom.sh" 'apply_multisite_config' "Entrypoint applies multisite config env"
assert_file_contains "${ROOT_DIR}/wordpress/docker-entrypoint-custom.sh" 'BEGIN KSM WORDPRESS_MULTISITE_CONFIG' "Entrypoint writes managed multisite block"
assert_file_contains "${ROOT_DIR}/wordpress/ksm-migration-fixer.php" 'is_internal_request' "Migration fixer detects internal requests"
assert_file_contains "${ROOT_DIR}/wordpress/ksm-migration-fixer.php" 'wp_doing_cron' "Migration fixer skips wp-cron requests"
assert_file_contains "${ROOT_DIR}/wordpress/ksm-cache-bootstrap.php" 'ksm_cache_bootstrap_is_network_setup_pending' "Cache bootstrap pauses during multisite network setup"
assert_file_contains "${ROOT_DIR}/docs/hosting-guide.md" 'WORDPRESS_MULTISITE_CONFIG=' "Hosting guide documents multisite config env"
assert_file_contains "${ROOT_DIR}/README.md" 'not affiliated with or endorsed by' "README documents Dokploy affiliation disclaimer"
assert_file_contains "${ROOT_DIR}/meta.json" 'Not affiliated with or endorsed by Dokploy' "Template description includes affiliation disclaimer"

echo ""
echo "=============================================="
echo "  MULTISITE REGRESSION CHECKS PASSED"
echo "=============================================="
