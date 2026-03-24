#!/bin/bash
# Test individual components
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

# Test machine component
test_machine_component() {
  log_info "Testing bastion-bootstrap-machine..."

  if podman exec "$CONTAINER_NAME" bash -c "cd /bastion && ./sbin/bastion-bootstrap-machine --init --source /bastion"; then
    log_success "Machine bootstrap completed"

    # Verify yq is installed
    if podman exec "$CONTAINER_NAME" which yq &> /dev/null; then
      log_success "yq is installed"
    else
      log_fail "yq not found after machine bootstrap"
      return 1
    fi

    return 0
  else
    log_fail "Machine bootstrap failed"
    return 1
  fi
}

# Test policy render component
test_render_component() {
  log_info "Testing bastion-render-policy..."

  # First ensure machine is set up (yq required)
  if ! test_machine_component; then
    return 1
  fi

  if podman exec "$CONTAINER_NAME" bash -c "cd /bastion && ./sbin/bastion-render-policy --policy-repo /k8s-bastion-policy --env $TEST_ENV --init-repo /bastion"; then
    log_success "Policy render completed"

    # Verify policy file was created
    if podman exec "$CONTAINER_NAME" test -f /bastion/access-policy.yaml; then
      log_success "Policy file created"
    else
      log_fail "Policy file not found"
      return 1
    fi

    return 0
  else
    log_fail "Policy render failed"
    return 1
  fi
}

# Test users component
test_users_component() {
  log_info "Testing bastion-bootstrap-users..."

  # First ensure machine and policy are ready
  if ! test_render_component; then
    return 1
  fi

  if podman exec "$CONTAINER_NAME" bash -c "cd /bastion && ./sbin/bastion-bootstrap-users --init --source /bastion"; then
    log_success "Users bootstrap completed"

    # Verify groups were created
    if podman exec "$CONTAINER_NAME" getent group k8s-test-group &> /dev/null; then
      log_success "Group k8s-test-group created"
    else
      log_fail "Group k8s-test-group not found"
      return 1
    fi

    return 0
  else
    log_fail "Users bootstrap failed"
    return 1
  fi
}

# Main
main() {
  log_info "=== Testing Individual Components ==="

  test_users_component

  log_info "=== Component Tests Complete ==="
}

main "$@"
