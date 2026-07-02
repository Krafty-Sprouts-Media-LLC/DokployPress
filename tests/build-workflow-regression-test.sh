#!/bin/bash
# =============================================================================
# build-workflow-regression-test.sh
# DokployPress — Docker image build workflow regression checks
#
# Verifies the GitHub Actions build workflow stays parallel and cache-friendly.
#
# Usage (from repo root):
#   bash tests/build-workflow-regression-test.sh
#
# @package DokployPress
# @since   1.14.3
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/build-images.yml"

pass() {
	echo "[PASS] $*"
}

fail() {
	echo "[FAIL] $*"
	exit 1
}

assert_contains() {
	local expected="$1"
	local label="$2"

	if grep -Fq "${expected}" "${WORKFLOW}"; then
		pass "${label}"
		return 0
	fi

	fail "${label}: missing '${expected}'"
}

assert_not_contains() {
	local unexpected="$1"
	local label="$2"

	if grep -Fq "${unexpected}" "${WORKFLOW}"; then
		fail "${label}: found '${unexpected}'"
	fi

	pass "${label}"
}

assert_contains "strategy:" "Workflow uses a build matrix"
assert_contains "fail-fast: false" "Matrix does not cancel sibling image builds"
assert_contains "image: wordpress" "Matrix includes WordPress image"
assert_contains "image: nginx" "Matrix includes Nginx image"
assert_contains "image: plugin-installer" "Matrix includes plugin-installer image"
assert_contains "context: \${{ matrix.context }}" "Build context comes from matrix"
assert_contains "platforms: \${{ matrix.platforms }}" "Build platforms come from matrix"
assert_contains "cache-from: type=gha,scope=\${{ matrix.image }}" "Build uses per-image GitHub Actions cache"
assert_contains "cache-to: type=gha,mode=max,scope=\${{ matrix.image }}" "Build saves per-image GitHub Actions cache"
assert_not_contains "no-cache: true" "Plugin-installer build is not forced cold"
assert_contains "IMAGE_PREFIX=ghcr.io/\${OWNER_LC}/dokploypress" "Workflow publishes dokploypress GHCR images"
assert_not_contains "dokploy-wp" "Workflow does not publish legacy dokploy-wp images"
assert_contains "blueprints/dokploypress/docker-compose.yml" "Blueprint tag update targets dokploypress"

echo ""
echo "=============================================="
echo "  BUILD WORKFLOW REGRESSION CHECKS PASSED"
echo "=============================================="
