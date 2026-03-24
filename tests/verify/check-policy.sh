#!/bin/bash
# Verify policy rendering
set -euo pipefail

CONTAINER_NAME="bastion-test"

log_info() {
  echo "[VERIFY] $1"
}

log_success() {
  echo "[PASS] $1"
}

log_fail() {
  echo "[FAIL] $1" >&2
}

# Check policy file exists
check_policy_file() {
  log_info "Checking policy files..."

  # Check source policy
  if podman exec "$CONTAINER_NAME" test -f /bastion/access-policy.yaml; then
    log_success "Source policy exists at /bastion/access-policy.yaml"
  else
    log_fail "Source policy not found"
    return 1
  fi

  # Check installed policy
  if podman exec "$CONTAINER_NAME" test -f /etc/kubernetes/access-policy.yaml; then
    log_success "Installed policy exists at /etc/kubernetes/access-policy.yaml"
  else
    log_fail "Installed policy not found"
    return 1
  fi
}

# Check policy is valid YAML
check_policy_valid() {
  log_info "Validating policy YAML..."

  if podman exec "$CONTAINER_NAME" bash -c "yq '.' /etc/kubernetes/access-policy.yaml > /dev/null 2>&1"; then
    log_success "Policy is valid YAML"
  else
    log_fail "Policy is not valid YAML"
    return 1
  fi
}

# Check policy contains expected content
check_policy_content() {
  log_info "Checking policy content..."

  # Check cluster config from base
  if podman exec "$CONTAINER_NAME" yq '.cluster.name' /etc/kubernetes/access-policy.yaml | grep -q "test-cluster"; then
    log_success "Cluster name from base policy present"
  else
    log_fail "Cluster name not found in policy"
    return 1
  fi

  # Check users from env overlay
  if podman exec "$CONTAINER_NAME" yq '.users.alice' /etc/kubernetes/access-policy.yaml > /dev/null 2>&1; then
    log_success "User alice from env overlay present"
  else
    log_fail "User alice not found in policy"
    return 1
  fi

  if podman exec "$CONTAINER_NAME" yq '.users.bob' /etc/kubernetes/access-policy.yaml > /dev/null 2>&1; then
    log_success "User bob from env overlay present"
  else
    log_fail "User bob not found in policy"
    return 1
  fi

  # Check groups
  if podman exec "$CONTAINER_NAME" yq '.groups.k8s-test-group' /etc/kubernetes/access-policy.yaml > /dev/null 2>&1; then
    log_success "Group k8s-test-group present"
  else
    log_fail "Group k8s-test-group not found"
    return 1
  fi
}

# Check environment marker
check_env_marker() {
  log_info "Checking environment marker..."

  if podman exec "$CONTAINER_NAME" test -f /bastion/.policy-env; then
    local env
    env=$(podman exec "$CONTAINER_NAME" cat /bastion/.policy-env)
    if [[ "$env" == "test" ]]; then
      log_success "Environment marker set to 'test'"
    else
      log_fail "Environment marker is '$env', expected 'test'"
      return 1
    fi
  else
    log_fail "Environment marker not found"
    return 1
  fi
}

# Main
main() {
  log_info "=== Verifying Policy Setup ==="

  local failed=0

  check_policy_file || failed=1
  check_policy_valid || failed=1
  check_policy_content || failed=1
  check_env_marker || failed=1

  log_info "=== Policy Verification Complete ==="

  return $failed
}

main "$@"
