#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONTAINER_NAME="bastion-test"
IMAGE_NAME="bastion-test:rocky9.5"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Clean up any existing containers
cleanup_existing() {
  log_info "Cleaning up existing containers..."
  podman rm -f "$CONTAINER_NAME" 2> /dev/null || true
}

# Build the container image
build_image() {
  log_info "Building container image..."
  podman build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
  log_info "Image built successfully: $IMAGE_NAME"
}

# Run the container
run_container() {
  log_info "Starting container: $CONTAINER_NAME"

  # Build a compatible set of args across podman versions.
  # Some podman builds do not support flags like --pidns.
  local -a extra_args=()
  if podman run --help 2> /dev/null | grep -q -- '--cgroupns'; then
    extra_args+=(--cgroupns=host)
  fi
  # Do NOT use --pid=host: it makes systemd exit immediately in this image.

  podman run -d \
    --name "$CONTAINER_NAME" \
    --privileged \
    --systemd=always \
    --stop-signal SIGRTMIN+3 \
    "${extra_args[@]}" \
    --security-opt label=disable \
    --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
    --volume "$PROJECT_ROOT:/bastion:Z" \
    --tmpfs /run \
    --tmpfs /run/lock \
    --tmpfs /tmp \
    "$IMAGE_NAME"

  log_info "Container started"

  # Wait for systemd to be ready (increased timeout and better detection)
  log_info "Waiting for systemd to be ready..."
  local max_attempts=60
  for i in $(seq 1 $max_attempts); do
    # If container died, stop waiting and print logs.
    local cstate
    cstate=$(podman inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2> /dev/null || echo unknown)
    if [[ "$cstate" != "running" ]]; then
      log_error "Container is not running (state: $cstate)"
      podman logs "$CONTAINER_NAME" || true
      return 1
    fi

    local status
    status=$(podman exec "$CONTAINER_NAME" systemctl is-system-running 2>&1 || true)

    if [[ "$status" == "running" ]] || [[ "$status" == "degraded" ]]; then
      log_info "Systemd is ready (status: $status)"
      return 0
    fi

    if [[ $((i % 10)) -eq 0 ]]; then
      log_info "Still waiting for systemd... (attempt $i/$max_attempts, status: $status)"
    fi

    sleep 1
  done

  log_error "Timeout waiting for systemd after $max_attempts attempts"
  log_error "Final status: $status"
  return 1
}

# Setup mock policy repository
setup_mock_policy() {
  log_info "Setting up mock policy repository..."

  # Copy fixtures to container
  podman cp "$SCRIPT_DIR/../fixtures/k8s-bastion-policy" "$CONTAINER_NAME:/k8s-bastion-policy"

  log_info "Mock policy repository ready at /k8s-bastion-policy"
}

setup_kubernetes_mock_files() {
  log_info "Creating mock Kubernetes CA file..."
  # The bootstrap kubeconfig generation embeds the CA from the policy path.
  # In tests we don't have a real cluster PKI, but kubectl requires the file to exist.
  podman exec "$CONTAINER_NAME" bash -c 'mkdir -p /etc/bastion && : > /etc/bastion/ca.crt'
}

# Main execution
main() {
  log_info "Setting up bastion test environment..."

  cleanup_existing
  build_image
  run_container
  setup_mock_policy
  setup_kubernetes_mock_files

  log_info "Setup complete!"
  log_info "Container: $CONTAINER_NAME"
  log_info "Project mounted at: /bastion"
  log_info "Policy repo at: /k8s-bastion-policy"
  log_info ""
  log_info "To enter container: podman exec -it $CONTAINER_NAME bash"
  log_info "To run tests: ./tests/run-all.sh"
}

main "$@"
