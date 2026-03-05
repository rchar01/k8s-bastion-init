#!/bin/bash
# Test bastion_reconcile.sh workflow
set -euo pipefail

CONTAINER_NAME="bastion-test"
TEST_ENV="test"

log_info() {
	echo "[TEST] $1"
}

log_success() {
	echo "[PASS] $1"
}

log_fail() {
	echo "[FAIL] $1" >&2
}

# Modify policy and run reconcile
test_reconcile() {
	log_info "Modifying policy to test reconcile..."

	# Add a new group to test policy
	podman exec "$CONTAINER_NAME" bash -c "
        cat >> /k8s-bastion-policy/envs/$TEST_ENV.yaml << 'EOF'

  # Added during reconcile test
  charlie:
    ensureGroups:
      - k8s-test-group
EOF
"

	log_info "Running bastion_reconcile.sh $TEST_ENV..."

	if podman exec "$CONTAINER_NAME" bash -c "cd /bastion && ./bastion_reconcile.sh $TEST_ENV"; then
		log_success "bastion_reconcile.sh completed"
		return 0
	else
		log_fail "bastion_reconcile.sh failed"
		return 1
	fi
}

# Main
main() {
	log_info "=== Testing Reconcile Workflow ==="

	if ! test_reconcile; then
		exit 1
	fi

	log_info "=== Reconcile Test Complete ==="
}

main "$@"
