#!/bin/bash
# =============================================================================
# db-upgrade-regression-test.sh
# DokployPress — MariaDB 10.6 → 11.8 upgrade regression check
#
# Verifies the in-place MariaDB upgrade path end to end:
#   1. Bring up the stack pinned to mariadb:10.6, install WP, write a marker.
#   2. Stop, then bring the stack up again on the real docker-compose.yml
#      (mariadb:11.8 + MARIADB_AUTO_UPGRADE=1) against the SAME db_data volume.
#   3. Confirm db + wordpress come back healthy and the marker survived.
#   4. Confirm db-preupgrade-snapshot captured a preupgrade-*.tar.gz.
#   5. Confirm that snapshot restores onto a clean volume and boots under 10.6.
#
# Usage (from repo root):
#   bash tests/db-upgrade-regression-test.sh
#
# @package DokployPress
# @since   3.0.0
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_SLUG="dbupgradetest"
ENV_FILE="${ROOT_DIR}/tests/db-upgrade-test.env"
LEGACY_OVERRIDE="${ROOT_DIR}/tests/compose.db-legacy-override.yml"
COMPOSE_BASE="docker compose -f ${ROOT_DIR}/docker-compose.yml -f ${ROOT_DIR}/tests/compose.override.yml --env-file ${ENV_FILE}"
COMPOSE_LEGACY="${COMPOSE_BASE} -f ${LEGACY_OVERRIDE}"
TEST_HTTP_PORT="${TEST_HTTP_PORT:-18081}"
BASE_URL="http://127.0.0.1:${TEST_HTTP_PORT}"
MARKER_TITLE="DbUpgradeRegressionMarker-$$"

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; exit 1; }
info() { echo "[INFO] $*"; }

cleanup() {
	info "Tearing down test stack and volumes..."
	${COMPOSE_LEGACY} down -v --remove-orphans 2>/dev/null || true
	docker volume rm "${STACK_SLUG}_db_backup_restore_test" >/dev/null 2>&1 || true
	rm -f "${ENV_FILE}" "${LEGACY_OVERRIDE}"
}
trap cleanup EXIT

info "Writing test env and legacy (10.6, no auto-upgrade) override..."
cat > "${ENV_FILE}" <<EOF
STACK_SLUG=${STACK_SLUG}
MYSQL_ROOT_PASSWORD=TestRootPass123!
MYSQL_PASSWORD=TestDbPass456!
WORDPRESS_DB_PASSWORD=TestDbPass456!
TEST_HTTP_PORT=${TEST_HTTP_PORT}
EOF

cat > "${LEGACY_OVERRIDE}" <<'EOF'
services:
  db:
    image: mariadb:10.6
    environment:
      - MARIADB_AUTO_UPGRADE=
EOF

info "Creating dokploy-network if missing..."
docker network inspect dokploy-network >/dev/null 2>&1 || docker network create dokploy-network

info "Phase 1 — bringing up stack pinned to mariadb:10.6..."
${COMPOSE_LEGACY} up -d --build

info "Waiting for db container to be healthy (10.6)..."
for i in $(seq 1 60); do
	${COMPOSE_LEGACY} ps db 2>/dev/null | grep -q "(healthy)" && { pass "db healthy on 10.6"; break; }
	[ "$i" -eq 60 ] && fail "db did not become healthy on 10.6 in time"
	sleep 5
done

info "Waiting for wordpress container to be healthy..."
for i in $(seq 1 60); do
	${COMPOSE_LEGACY} ps wordpress 2>/dev/null | grep -q "(healthy)" && { pass "wordpress healthy on 10.6"; break; }
	[ "$i" -eq 60 ] && fail "wordpress did not become healthy in time"
	sleep 5
done

WP="${COMPOSE_LEGACY} exec -T wordpress"

info "Installing WordPress core and writing a marker option..."
${WP} wp core install \
	--url="${BASE_URL}" \
	--title="DB Upgrade Regression Test" \
	--admin_user=admin \
	--admin_password='UpgradeTestAdmin123!' \
	--admin_email=upgrade-test@test.local \
	--skip-email \
	--allow-root
${WP} wp option update blogname "${MARKER_TITLE}" --allow-root
BEFORE_VALUE="$(${WP} wp option get blogname --allow-root)"
[ "${BEFORE_VALUE}" = "${MARKER_TITLE}" ] || fail "Marker option did not write correctly before upgrade"
pass "Marker option written: ${BEFORE_VALUE}"

info "Confirming db-preupgrade-snapshot no-op'd on this fresh 10.6 volume..."
${COMPOSE_LEGACY} logs db-preupgrade-snapshot 2>/dev/null | grep -q "Fresh install" \
	&& pass "db-preupgrade-snapshot correctly no-op'd on fresh install" \
	|| info "db-preupgrade-snapshot log did not show fresh-install no-op (non-fatal, continuing)"

info "Phase 2 — stopping stack (keeping volumes)..."
${COMPOSE_LEGACY} down --remove-orphans

info "Phase 2 — bringing the SAME volumes up on the real docker-compose.yml (mariadb:11.8 + auto-upgrade)..."
${COMPOSE_BASE} up -d --build

info "Waiting for db-preupgrade-snapshot to complete..."
for i in $(seq 1 30); do
	${COMPOSE_BASE} ps -a db-preupgrade-snapshot 2>/dev/null | grep -qiE "exited \(0\)" && { pass "db-preupgrade-snapshot completed"; break; }
	[ "$i" -eq 30 ] && fail "db-preupgrade-snapshot did not complete in time"
	sleep 3
done

SNAPSHOT_LOG="$(${COMPOSE_BASE} logs db-preupgrade-snapshot 2>/dev/null)"
echo "${SNAPSHOT_LOG}" | grep -q "Snapshot written to" \
	&& pass "Pre-upgrade snapshot was taken" \
	|| fail "db-preupgrade-snapshot did not report taking a snapshot — check output:\n${SNAPSHOT_LOG}"

info "Waiting for db container to be healthy (11.8, post mariadb-upgrade)..."
for i in $(seq 1 60); do
	${COMPOSE_BASE} ps db 2>/dev/null | grep -q "(healthy)" && { pass "db healthy on 11.8 after in-place upgrade"; break; }
	[ "$i" -eq 60 ] && fail "db did not become healthy on 11.8 in time"
	sleep 5
done

info "Waiting for wordpress container to be healthy..."
for i in $(seq 1 60); do
	${COMPOSE_BASE} ps wordpress 2>/dev/null | grep -q "(healthy)" && { pass "wordpress healthy after upgrade"; break; }
	[ "$i" -eq 60 ] && fail "wordpress did not become healthy after upgrade"
	sleep 5
done

WP="${COMPOSE_BASE} exec -T wordpress"

info "Verifying marker option survived the upgrade..."
AFTER_VALUE="$(${WP} wp option get blogname --allow-root)"
[ "${AFTER_VALUE}" = "${MARKER_TITLE}" ] || fail "Marker option lost after upgrade (before='${BEFORE_VALUE}' after='${AFTER_VALUE}')"
pass "Marker option intact after upgrade: ${AFTER_VALUE}"

info "Verifying site loads over HTTP after upgrade..."
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/")"
[ "${HTTP_CODE}" = "200" ] || fail "Site returned ${HTTP_CODE} after upgrade, expected 200"
pass "Site loads (200) after upgrade"

info "Phase 3 — verifying the snapshot restores and boots under mariadb:10.6..."
BACKUP_VOLUME="${STACK_SLUG}_db_backup"
RESTORE_VOLUME="${STACK_SLUG}_db_backup_restore_test"
docker volume create "${RESTORE_VOLUME}" >/dev/null

docker run --rm \
	-v "${BACKUP_VOLUME}:/backup:ro" \
	-v "${RESTORE_VOLUME}:/restore" \
	alpine:3 sh -c 'set -e; tar -xzf /backup/preupgrade-*.tar.gz -C /restore' \
	&& pass "Snapshot tarball extracted onto a clean volume" \
	|| fail "Failed to extract preupgrade snapshot tarball"

RESTORE_CONTAINER="dbupgradetest-restore-check"
docker rm -f "${RESTORE_CONTAINER}" >/dev/null 2>&1 || true
docker run -d --name "${RESTORE_CONTAINER}" \
	-e MARIADB_ROOT_PASSWORD=TestRootPass123! \
	-v "${RESTORE_VOLUME}:/var/lib/mysql" \
	mariadb:10.6 >/dev/null

info "Waiting for restored 10.6 datadir to boot..."
RESTORE_OK=false
for i in $(seq 1 30); do
	if docker exec "${RESTORE_CONTAINER}" healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
		RESTORE_OK=true
		break
	fi
	sleep 3
done

docker logs "${RESTORE_CONTAINER}" 2>&1 | tail -20
docker rm -f "${RESTORE_CONTAINER}" >/dev/null 2>&1 || true
docker volume rm "${RESTORE_VOLUME}" >/dev/null 2>&1 || true

[ "${RESTORE_OK}" = true ] || fail "Restored snapshot did not boot cleanly under mariadb:10.6"
pass "Restored snapshot boots cleanly under mariadb:10.6"

echo ""
echo "=============================================="
echo "  DB UPGRADE REGRESSION CHECKS PASSED"
echo "=============================================="
