#!/bin/bash
# Test full bastion_init.sh workflow
set -euo pipefail

CONTAINER_NAME="bastion-test"
TEST_ENV="test"

log_info() {
	echo "[TEST] $1"
}

log_error() {
	echo "[ERROR] $1" >&2
}

log_success() {
	echo "[PASS] $1"
}

log_fail() {
	echo "[FAIL] $1" >&2
}

# Run bastion_init.sh in container
test_full_init() {
	log_info "Running bastion_init.sh $TEST_ENV..."

	if podman exec "$CONTAINER_NAME" bash -c "cd /bastion && ./bastion_init.sh $TEST_ENV"; then
		log_success "bastion_init.sh completed"
		return 0
	else
		log_fail "bastion_init.sh failed"
		return 1
	fi
}

# Main
main() {
	log_info "=== Testing Full Init Workflow ==="

	if ! test_full_init; then
		exit 1
	fi

	log_info "=== Full Init Test Complete ==="
}

main "$@"
