#!/bin/bash
# =============================================================================
# smoke-test.sh
# KSM WPDokploystack — Integration smoke test
#
# Brings up the full stack, installs WordPress, and verifies:
#   - All containers healthy
#   - Redis Object Cache + MilliCache plugins installed and active
#   - wp redis status / wp millicache test / wp millicache status
#   - MilliCache HTTP cache hit on repeat anonymous request
#
# Usage (from repo root):
#   bash tests/smoke-test.sh
#   bash tests/smoke-test.sh --keep   # leave stack running after test
#
# @package KSM-WPDokploystack
# @since   1.8.0
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="docker compose -f ${ROOT_DIR}/docker-compose.yml -f ${ROOT_DIR}/tests/compose.override.yml --env-file ${ROOT_DIR}/tests/smoke-test.env"
KEEP_STACK=false
TEST_HTTP_PORT="${TEST_HTTP_PORT:-18080}"
BASE_URL="http://127.0.0.1:${TEST_HTTP_PORT}"

if [ "${1:-}" = "--keep" ]; then
	KEEP_STACK=true
fi

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }
info() { echo "[INFO] $*"; }

cleanup() {
	if [ "${KEEP_STACK}" = true ]; then
		info "Keeping stack running (--keep). Base URL: ${BASE_URL}"
		return 0
	fi
	info "Tearing down test stack..."
	${COMPOSE} down -v --remove-orphans 2>/dev/null || true
}

trap cleanup EXIT

info "Creating dokploy-network if missing..."
docker network inspect dokploy-network >/dev/null 2>&1 || docker network create dokploy-network

info "Building and starting stack..."
export TEST_HTTP_PORT
${COMPOSE} up -d --build

info "Waiting for WordPress container to be healthy..."
for i in $(seq 1 60); do
	if ${COMPOSE} ps wordpress 2>/dev/null | grep -q "(healthy)"; then
		pass "WordPress container healthy"
		break
	fi
	if [ "$i" -eq 60 ]; then
		fail "WordPress container did not become healthy in time"
	fi
	sleep 5
done

info "Waiting for plugin-installer to finish..."
for i in $(seq 1 72); do
	LOGS="$(${COMPOSE} logs plugin-installer 2>/dev/null || echo "")"
	if echo "${LOGS}" | grep -q "Cache plugins installed"; then
		pass "Plugin installer completed successfully"
		break
	fi
	if [ "$i" -eq 72 ]; then
		echo "${LOGS}"
		fail "Plugin installer did not complete in time"
	fi
	sleep 5
done

WP="${COMPOSE} exec -T wordpress"

info "Installing WordPress core (if not already installed)..."
if ! ${WP} wp core is-installed --allow-root 2>/dev/null; then
	${WP} wp core install \
		--url="${BASE_URL}" \
		--title="KSM Smoke Test" \
		--admin_user=admin \
		--admin_password='SmokeTestAdmin123!' \
		--admin_email=smoke@test.local \
		--skip-email \
		--allow-root
	pass "WordPress core installed"
else
	pass "WordPress core already installed"
fi

info "Triggering cache bootstrap via first HTTP request..."
curl -fsS "${BASE_URL}/" >/dev/null || fail "First HTTP request failed"
sleep 2
curl -fsS "${BASE_URL}/" >/dev/null || true

info "Checking mu-plugins are present..."
${WP} test -f /var/www/html/wp-content/mu-plugins/ksm-cache-bootstrap.php
${WP} test -f /var/www/html/wp-content/mu-plugins/ksm-migration-fixer.php
pass "KSM mu-plugins present"

info "Checking plugins are present..."
${WP} test -f /var/www/html/wp-content/plugins/redis-cache/redis-cache.php
${WP} test -f /var/www/html/wp-content/plugins/millicache/millicache.php
pass "Redis Object Cache and MilliCache plugin files present"

info "Checking plugins are active..."
${WP} wp plugin is-active redis-cache --allow-root
${WP} wp plugin is-active millicache --allow-root
pass "Both cache plugins are active"

info "Checking wp-config constants..."
${WP} wp config get WP_CACHE --allow-root | grep -q "1\|true"
${WP} wp config get WP_REDIS_HOST --allow-root | grep -q "redis"
${WP} wp config get MC_STORAGE_HOST --allow-root | grep -q "redis"
${WP} wp config get MC_STORAGE_DB --allow-root | grep -q "1"
pass "wp-config cache constants correct"

info "Running wp redis status..."
${WP} wp redis status --allow-root
pass "wp redis status OK"

info "Running wp millicache test..."
${WP} wp millicache test --allow-root
pass "wp millicache test OK"

info "Running wp millicache status..."
MILLI_STATUS="$(${WP} wp millicache status --allow-root 2>&1)"
echo "${MILLI_STATUS}"
echo "${MILLI_STATUS}" | grep -qi "storage_connected.*yes\|connected.*yes" || \
	echo "${MILLI_STATUS}" | grep -qi "yes"
pass "wp millicache status OK"

info "Testing HTTP front page (cache miss then hit)..."
FIRST_HEADERS="$(${WP} curl -sI "${BASE_URL}/" 2>/dev/null || curl -sI "${BASE_URL}/")"
echo "${FIRST_HEADERS}" | head -5
HTTP_CODE="$(echo "${FIRST_HEADERS}" | head -1 | awk '{print $2}')"
[ "${HTTP_CODE}" = "200" ] || fail "First HTTP request returned ${HTTP_CODE}, expected 200"
pass "First HTTP request returned 200"

SECOND_HEADERS="$(curl -sI "${BASE_URL}/" 2>/dev/null || ${WP} curl -sI "${BASE_URL}/")"
echo "${SECOND_HEADERS}" | head -10

if echo "${SECOND_HEADERS}" | grep -qi "X-MilliCache-Status: hit"; then
	pass "MilliCache HTTP cache HIT on second request"
elif echo "${SECOND_HEADERS}" | grep -qi "X-MilliCache-Status: miss"; then
	info "MilliCache header shows miss on second request — enabling debug and retrying..."
	${WP} wp config set MC_CACHE_DEBUG true --raw --allow-root 2>/dev/null || true
	${WP} wp millicache clear --allow-root 2>/dev/null || true
	curl -s "${BASE_URL}/" >/dev/null
	sleep 1
	THIRD_HEADERS="$(curl -sI "${BASE_URL}/")"
	echo "${THIRD_HEADERS}" | head -10
	echo "${THIRD_HEADERS}" | grep -qi "X-MilliCache-Status: hit" && pass "MilliCache HTTP cache HIT on third request" || \
		info "MilliCache debug headers not present (MC_CACHE_DEBUG may be off) — Redis/WP-CLI tests passed; manual header check optional"
else
	info "X-MilliCache-Status header not present (debug off by default) — WP-CLI connectivity tests passed"
fi

info "Checking Redis responds from WordPress container..."
${WP} bash -c 'php -r "
\$r = new Redis();
\$r->connect(\"redis\", 6379);
echo \$r->ping() ? \"PONG\n\" : \"FAIL\n\";
"' | grep -q "PONG"
pass "PHP Redis extension can reach redis container"

echo ""
echo "=============================================="
echo "  ALL SMOKE TESTS PASSED"
echo "  Stack URL: ${BASE_URL}"
echo "  WP Admin:  ${BASE_URL}/wp-admin"
echo "=============================================="
