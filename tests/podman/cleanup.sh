#!/bin/bash
# Cleanup test environment
set -euo pipefail

CONTAINER_NAME="bastion-test"
IMAGE_NAME="bastion-test:rocky9.5"

log_info() {
	echo "[CLEANUP] $1"
}

# Stop and remove container
cleanup_container() {
	log_info "Stopping and removing container..."
	podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

# Remove image
cleanup_image() {
	log_info "Removing test image..."
	podman rmi -f "$IMAGE_NAME" 2>/dev/null || true
}

# Remove volumes
cleanup_volumes() {
	log_info "Removing volumes..."
	# no named volumes currently used
}

# Main
main() {
	log_info "=== Cleaning up test environment ==="

	cleanup_container
	cleanup_volumes
	cleanup_image

	log_info "=== Cleanup complete ==="
}

main "$@"
