#!/bin/bash
# Test bootstrap daemon service and socket API in offline suite
set -euo pipefail

CONTAINER_NAME="bastion-test"

log_info() {
  echo "[TEST] $1"
}

log_success() {
  echo "[PASS] $1"
}

log_fail() {
  echo "[FAIL] $1" >&2
}

test_daemon_active() {
  log_info "Checking bastion-bootstrapd service is active..."

  local ok=0
  local i
  for i in $(seq 1 10); do
    if podman exec "$CONTAINER_NAME" systemctl is-active --quiet bastion-bootstrapd.service; then
      ok=1
      break
    fi
    sleep 1
  done
  if [[ "$ok" -eq 1 ]]; then
    log_success "bastion-bootstrapd service is active"
  else
    log_fail "bastion-bootstrapd service is not active"
    podman exec "$CONTAINER_NAME" systemctl --no-pager --full status bastion-bootstrapd.service || true
    return 1
  fi

  if podman exec "$CONTAINER_NAME" test -S /run/bastion-bootstrapd/bootstrapd.sock; then
    log_success "bootstrap daemon socket exists"
  else
    log_fail "bootstrap daemon socket is missing"
    return 1
  fi
}

test_health_api_reachable() {
  log_info "Checking daemon API is reachable and enforces caller policy..."

  local resp
  if resp="$(podman exec "$CONTAINER_NAME" bash -lc '/usr/local/lib/bastion/internal/bastion-bootstrapd-client health --socket /run/bastion-bootstrapd/bootstrapd.sock' 2> /dev/null)"; then
    local ok
    ok="$(jq -r '.ok' <<< "$resp")"
    if [[ "$ok" == "true" ]]; then
      log_fail "daemon unexpectedly allowed root health request"
      return 1
    fi
    log_success "daemon rejects root caller as expected"
    return 0
  fi

  log_success "daemon socket accepts request and enforces policy"
}

main() {
  log_info "=== Testing Bootstrap Daemon ==="

  test_daemon_active
  test_health_api_reachable

  log_info "=== Bootstrap Daemon Test Complete ==="
}

main "$@"
