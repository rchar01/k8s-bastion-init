#!/bin/bash
# Main test orchestrator
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="bastion-test"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_header() {
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}"
}

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Track results
TESTS_PASSED=0
TESTS_FAILED=0

# Run a test and track result
run_test() {
  local test_name="$1"
  local test_script="$2"

  log_header "Running: $test_name"

  if bash "$test_script"; then
    log_info "$test_name: PASSED"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    log_error "$test_name: FAILED"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

# Setup phase
setup() {
  log_header "SETUP PHASE"
  bash "$SCRIPT_DIR/podman/setup.sh"
}

# Test phase
test_phase() {
  log_header "TEST PHASE"

  # Test 0: Downloader config behavior
  run_test "Download Config Test" "$SCRIPT_DIR/scenarios/test-download-config.sh"

  # Test 1: Component tests
  run_test "Component Tests" "$SCRIPT_DIR/scenarios/test-components.sh"

  # Clean and restart for full init test
  log_info "Cleaning container state for full init test..."
  podman exec "$CONTAINER_NAME" rm -f \
    /usr/local/lib/bastion/.machine-init-done \
    /usr/local/lib/bastion/.users-init-done \
    /usr/lib/bastion/.machine-init-done \
    /usr/lib/bastion/.users-init-done \
    2> /dev/null || true
  podman exec "$CONTAINER_NAME" rm -rf /etc/kubernetes /home/*/.kube 2> /dev/null || true
  # Recreate the mock CA file expected by policy fixtures.
  podman exec "$CONTAINER_NAME" bash -c 'mkdir -p /etc/kubernetes && : > /etc/kubernetes/ca.crt' 2> /dev/null || true

  # Test 2: Full init
  run_test "Full Init Test" "$SCRIPT_DIR/scenarios/test-full-init.sh"

  # Test 3: Full reconcile
  run_test "Reconcile Test" "$SCRIPT_DIR/scenarios/test-reconcile.sh"

  # Test 4: User disable workflow
  run_test "Disable User Test" "$SCRIPT_DIR/scenarios/test-disable-user.sh"
}

# Verification phase
verify_phase() {
  log_header "VERIFICATION PHASE"

  run_test "Machine Verification" "$SCRIPT_DIR/verify/check-machine.sh" || true
  run_test "Users Verification" "$SCRIPT_DIR/verify/check-users.sh" || true
  run_test "Policy Verification" "$SCRIPT_DIR/verify/check-policy.sh" || true
  run_test "Hardening Verification" "$SCRIPT_DIR/verify/check-hardening.sh" || true
}

# Cleanup phase
cleanup() {
  log_header "CLEANUP PHASE"
  bash "$SCRIPT_DIR/podman/cleanup.sh"
}

# Results
show_results() {
  log_header "TEST RESULTS"
  echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}ALL TESTS PASSED!${NC}"
    return 0
  else
    echo -e "\n${RED}SOME TESTS FAILED${NC}"
    return 1
  fi
}

# Main execution
main() {
  log_header "Bastion Toolkit Test Suite"

  local cleanup_on_exit=true

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-cleanup)
        cleanup_on_exit=false
        shift
        ;;
      --help | -h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --no-cleanup    Keep container after tests (for debugging)"
        echo "  --help, -h      Show this help message"
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  # Setup
  if ! setup; then
    log_error "Setup failed!"
    exit 1
  fi

  # Run tests
  test_phase

  # Verify
  verify_phase

  # Cleanup (unless disabled)
  if $cleanup_on_exit; then
    cleanup
  else
    log_warn "Skipping cleanup (--no-cleanup specified)"
    log_info "Container '$CONTAINER_NAME' is still running for inspection"
    log_info "To cleanup later: ./tests/podman/cleanup.sh"
  fi

  # Show results
  show_results
}

# Cleanup on error
trap 'if [[ $? -ne 0 ]]; then log_error "Test suite failed!"; cleanup; fi' EXIT

main "$@"
