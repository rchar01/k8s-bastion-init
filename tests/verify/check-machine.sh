#!/bin/bash
# Verify machine setup
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

# Check containerd
check_containerd() {
	log_info "Checking containerd..."

	if podman exec "$CONTAINER_NAME" systemctl is-active containerd &>/dev/null; then
		log_success "containerd is running"
	else
		log_fail "containerd is not running"
		return 1
	fi
}

# Check tools
check_tools() {
	log_info "Checking tools..."

	local tools=("yq" "kubectl" "helm" "jq")
	local all_present=true

	for tool in "${tools[@]}"; do
		if podman exec "$CONTAINER_NAME" which "$tool" &>/dev/null; then
			log_success "$tool is installed"
		else
			log_fail "$tool not found"
			all_present=false
		fi
	done

	$all_present
}

# Check scripts
check_scripts() {
	log_info "Checking bastion scripts..."

	local scripts=("bastion-bootstrap-machine" "bastion-bootstrap-users" "bastion-render-policy" "bastion-disable-user")
	local all_present=true

	for script in "${scripts[@]}"; do
		if podman exec "$CONTAINER_NAME" test -x "/usr/local/sbin/$script"; then
			log_success "$script installed"
		else
			log_fail "$script not found or not executable"
			all_present=false
		fi
	done

	$all_present
}

# Check marker files
check_markers() {
	log_info "Checking initialization markers..."

	if podman exec "$CONTAINER_NAME" bash -c 'test -f /usr/local/lib/bastion/.machine-init-done || test -f /usr/lib/bastion/.machine-init-done'; then
		log_success "Machine init marker exists"
	else
		log_fail "Machine init marker missing"
		return 1
	fi
}

# Main
main() {
	log_info "=== Verifying Machine Setup ==="

	local failed=0

	check_containerd || failed=1
	check_tools || failed=1
	check_scripts || failed=1
	check_markers || failed=1

	log_info "=== Machine Verification Complete ==="

	return $failed
}

main "$@"
