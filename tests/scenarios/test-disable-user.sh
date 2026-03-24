#!/bin/bash
# Test bastion-disable-user workflow
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

test_disable_requires_policy_removal() {
  log_info "Checking that disable-user requires policy removal first..."

  if podman exec "$CONTAINER_NAME" /usr/local/sbin/bastion-disable-user --user bob > /dev/null 2>&1; then
    log_fail "disable-user unexpectedly succeeded while bob is still in policy"
    return 1
  fi

  log_success "disable-user correctly refused a user still present in policy"
}

test_disable_user() {
  log_info "Removing alice from installed bastion policy..."

  podman exec "$CONTAINER_NAME" yq -i 'del(.users.alice)' /etc/kubernetes/access-policy.yaml

  log_info "Disabling alice on bastion..."
  if ! podman exec "$CONTAINER_NAME" /usr/local/sbin/bastion-disable-user --user alice; then
    log_fail "bastion-disable-user failed"
    return 1
  fi

  if podman exec "$CONTAINER_NAME" bash -c "id -nG alice | tr ' ' '\n' | grep -qx 'k8s-test-group'"; then
    log_fail "alice still has k8s-test-group"
    return 1
  fi
  log_success "alice no longer has bastion-managed Kubernetes groups"

  if podman exec "$CONTAINER_NAME" test -f /home/alice/.kube/bootstrap; then
    log_fail "alice bootstrap kubeconfig still exists"
    return 1
  fi
  log_success "alice bootstrap kubeconfig is no longer active"

  if ! podman exec "$CONTAINER_NAME" bash -c 'compgen -G "/home/alice/.kube/bootstrap.disabled.*" >/dev/null'; then
    log_fail "alice disabled bootstrap backup not found"
    return 1
  fi
  log_success "alice bootstrap kubeconfig was disabled with a backup"
}

main() {
  log_info "=== Testing User Disable Workflow ==="

  test_disable_requires_policy_removal
  test_disable_user

  log_info "=== User Disable Test Complete ==="
}

main "$@"
