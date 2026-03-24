#!/bin/bash
# Verify security hardening defaults
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

check_sudo_path_file() {
  log_info "Checking sudo secure_path configuration..."

  if podman exec "$CONTAINER_NAME" test -f /etc/sudoers.d/bastion-path; then
    log_success "sudoers drop-in exists: /etc/sudoers.d/bastion-path"
  else
    log_fail "Missing sudoers drop-in: /etc/sudoers.d/bastion-path"
    return 1
  fi

  if podman exec "$CONTAINER_NAME" grep -q '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' /etc/sudoers.d/bastion-path; then
    log_success "sudoers secure_path includes /usr/local/sbin"
  else
    log_fail "sudoers secure_path does not include expected path"
    return 1
  fi
}

check_admin_script_modes() {
  log_info "Checking /usr/local/sbin script permissions..."

  if podman exec "$CONTAINER_NAME" bash -c '
		for f in /usr/local/sbin/bastion-*; do
			[[ -f "$f" ]] || continue
			mode="$(stat -c %a "$f")"
			if [[ "$mode" != "750" ]]; then
				echo "$f mode=$mode"
				exit 1
			fi
		done
	'; then
    log_success "Admin scripts are mode 0750"
  else
    log_fail "One or more admin scripts are not mode 0750"
    return 1
  fi
}

check_non_root_denied() {
  log_info "Checking non-root cannot run admin script directly..."

  if podman exec -u alice "$CONTAINER_NAME" bash -lc '/usr/local/sbin/bastion-audit-kube-dirs --no-list >/dev/null 2>&1'; then
    log_fail "alice unexpectedly executed admin script without sudo"
    return 1
  else
    log_success "alice cannot execute admin script without sudo"
  fi
}

check_sudo_resolution() {
  log_info "Checking sudo can run admin commands..."

  local output=""
  if output=$(podman exec -u alice "$CONTAINER_NAME" bash -lc 'sudo /usr/local/sbin/bastion-audit-kube-dirs --no-list >/dev/null' 2>&1); then
    log_success "sudo can execute /usr/local/sbin/bastion-audit-kube-dirs for alice"
  else
    log_fail "sudo execution of /usr/local/sbin/bastion-audit-kube-dirs failed for alice"
    if [[ -n "$output" ]]; then
      log_info "sudo output: $output"
    fi
    return 1
  fi
}

check_service_kubeconfig() {
  log_info "Checking service kubeconfig wiring..."

  if podman exec "$CONTAINER_NAME" test -f /etc/kubernetes/admin.kubeconfig; then
    log_success "Service kubeconfig exists at /etc/kubernetes/admin.kubeconfig"
  else
    log_fail "Missing /etc/kubernetes/admin.kubeconfig"
    return 1
  fi

  if podman exec "$CONTAINER_NAME" bash -c '[[ "$(stat -c "%a %U %G" /etc/kubernetes/admin.kubeconfig)" == "600 root root" ]]'; then
    log_success "Service kubeconfig permissions are 0600 root:root"
  else
    log_fail "Service kubeconfig permissions are incorrect"
    return 1
  fi

  if podman exec "$CONTAINER_NAME" grep -q '^Environment=KUBECONFIG=/etc/kubernetes/admin.kubeconfig$' /etc/systemd/system/bastion-csr-approver.service; then
    log_success "Approver service uses service kubeconfig"
  else
    log_fail "Approver service missing KUBECONFIG environment"
    return 1
  fi

  if podman exec "$CONTAINER_NAME" grep -q '^Environment=KUBECONFIG=/etc/kubernetes/admin.kubeconfig$' /etc/systemd/system/bastion-csr-cleanup.service; then
    log_success "Cleanup service uses service kubeconfig"
  else
    log_fail "Cleanup service missing KUBECONFIG environment"
    return 1
  fi
}

main() {
  log_info "=== Verifying Security Hardening ==="

  local failed=0

  check_sudo_path_file || failed=1
  check_admin_script_modes || failed=1
  check_non_root_denied || failed=1
  check_sudo_resolution || failed=1
  check_service_kubeconfig || failed=1

  log_info "=== Hardening Verification Complete ==="

  return $failed
}

main "$@"
