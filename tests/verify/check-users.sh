#!/bin/bash
# Verify users and groups setup
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

# Check groups
check_groups() {
	log_info "Checking k8s-* groups..."

	local groups=("k8s-test-group")
	local all_present=true

	for group in "${groups[@]}"; do
		if podman exec "$CONTAINER_NAME" getent group "$group" &>/dev/null; then
			log_success "Group $group exists"
		else
			log_fail "Group $group not found"
			all_present=false
		fi
	done

	$all_present
}

# Check user memberships
check_user_memberships() {
	log_info "Checking user group memberships..."

	local users=("alice" "bob")
	local all_ok=true

	for user in "${users[@]}"; do
		if podman exec "$CONTAINER_NAME" id -nG "$user" | grep -q "k8s-test-group"; then
			log_success "User $user is in k8s-test-group"
		else
			log_fail "User $user not in k8s-test-group"
			all_ok=false
		fi
	done

	$all_ok
}

# Check kubeconfig directories
check_kubeconfigs() {
	log_info "Checking kubeconfig directories..."

	local users=("alice" "bob")
	local all_ok=true

	for user in "${users[@]}"; do
		if podman exec "$CONTAINER_NAME" test -d "/home/$user/.kube"; then
			log_success "Kubeconfig directory for $user exists"
		else
			log_fail "Kubeconfig directory for $user not found"
			all_ok=false
		fi
	done

	$all_ok
}

# Check bootstrap kubeconfigs
check_bootstrap_configs() {
	log_info "Checking bootstrap kubeconfigs..."

	local users=("alice" "bob")
	local all_ok=true

	for user in "${users[@]}"; do
		if podman exec "$CONTAINER_NAME" test -f "/home/$user/.kube/bootstrap"; then
			log_success "Bootstrap kubeconfig for $user exists"
		else
			log_fail "Bootstrap kubeconfig for $user not found"
			all_ok=false
		fi
	done

	$all_ok
}

# Check marker files
check_markers() {
	log_info "Checking users initialization markers..."

	if podman exec "$CONTAINER_NAME" bash -c 'test -f /usr/local/lib/bastion/.users-init-done || test -f /usr/lib/bastion/.users-init-done'; then
		log_success "Users init marker exists"
	else
		log_fail "Users init marker missing"
		return 1
	fi
}

# Main
main() {
	log_info "=== Verifying Users Setup ==="

	local failed=0

	check_groups || failed=1
	check_user_memberships || failed=1
	check_kubeconfigs || failed=1
	check_bootstrap_configs || failed=1
	check_markers || failed=1

	log_info "=== Users Verification Complete ==="

	return $failed
}

main "$@"
