#!/usr/bin/env bash
# Create test users alice and bob
set -euo pipefail

log_info() {
  echo "[INFO] $1"
}

# Create users if they don't exist
if ! id "alice" &> /dev/null; then
  log_info "Creating user: alice"
  useradd -m -s /bin/bash alice
  echo "alice:alice123" | chpasswd
  echo "alice ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

if ! id "bob" &> /dev/null; then
  log_info "Creating user: bob"
  useradd -m -s /bin/bash bob
  echo "bob:bob123" | chpasswd
  echo "bob ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

log_info "Test users created successfully"
