# Bastion Toolkit Test Suite

This directory contains a comprehensive test suite for the Kubernetes Bastion Host Toolkit using Podman containers.

## Overview

The test suite creates a Rocky Linux 9.5 container environment to validate:
- Machine setup (containerd, tools including yq)
- Policy rendering from private repository
- Users and groups configuration
- Complete initialization and reconciliation workflows

## Prerequisites

- Podman installed on your system
- Sufficient disk space (~2GB for container image)
- Root or sudo access (for privileged containers)

## Quick Start

Run all tests with a single command:

```bash
./tests/run-all.sh
```

This will:
1. Build Rocky Linux 9.5 container image
2. Start privileged container with systemd
3. Run component tests
4. Run full initialization test
5. Run reconciliation test
6. Verify all aspects of the setup
7. Clean up containers

## Test Structure

```
tests/
├── podman/
│   ├── Containerfile          # Rocky Linux 9.5 base image
│   ├── setup.sh               # Build and start container
│   └── cleanup.sh             # Remove containers/volumes
├── fixtures/
│   ├── k8s-bastion-policy/    # Mock private policy repository
│   │   ├── base.yaml          # Base cluster config
│   │   └── envs/
│   │       └── test.yaml      # Test users (alice, bob)
│   └── test-users.sh          # Script to create test users
├── scenarios/
│   ├── test-download-config.sh # Test download.conf URL templates/overrides
│   ├── test-full-init.sh      # Test complete initialization
│   ├── test-reconcile.sh      # Test policy updates
│   └── test-components.sh     # Test individual phases
├── verify/
│   ├── check-machine.sh       # Verify containerd, tools, yq
│   ├── check-users.sh         # Verify groups and memberships
│   └── check-policy.sh        # Verify policy rendering
└── run-all.sh                 # Main test orchestrator
```

## Usage

### Run All Tests

```bash
./tests/run-all.sh
```

### Run Tests Without Cleanup (for debugging)

```bash
./tests/run-all.sh --no-cleanup
```

Note: `--no-cleanup` preserves the container only on successful runs. On failure,
the EXIT trap still performs cleanup.

After tests complete, you can inspect the container:

```bash
podman exec -it bastion-test bash
# Inside container:
cat /etc/kubernetes/access-policy.yaml
id alice
ls -la /home/alice/.kube/
```

Then cleanup manually:

```bash
./tests/podman/cleanup.sh
```

### Run Individual Tests

```bash
# Setup container only
./tests/podman/setup.sh

# Run specific test
./tests/scenarios/test-full-init.sh

# Run downloader config test
./tests/scenarios/test-download-config.sh

# Verify specific aspect
./tests/verify/check-machine.sh

# Cleanup
./tests/podman/cleanup.sh
```

### Manual Testing in Container

```bash
# Setup and enter container
./tests/podman/setup.sh
podman exec -it bastion-test bash

# Inside container:
cd /bastion
./bastion_init.sh test
```

Run verification scripts from the host shell (not inside the container):

```bash
./tests/verify/check-machine.sh
./tests/verify/check-users.sh
./tests/verify/check-policy.sh
```

## What is Tested

### Machine Phase
- ✅ containerd installation and service startup
- ✅ Tools installation (yq, kubectl, helm, jq)
- ✅ Bastion scripts installation
- ✅ Library installation
- ✅ Marker file creation

### Policy Rendering
- ✅ Three-layer policy merge (public + base + env)
- ✅ YAML validity
- ✅ Users and groups present in final policy
- ✅ Environment marker file

### Users Phase
- ✅ k8s-* group creation
- ✅ User group assignments
- ✅ Bootstrap kubeconfig generation
- ✅ Login profile installation
- ✅ Marker file creation

### Integration
- ✅ Full init workflow (machine → render → users)
- ✅ Reconcile workflow (updates existing installation)
- ✅ Component isolation (can run phases separately)

## Test Users

The test creates two users:
- **alice** - Member of k8s-test-group
- **bob** - Member of k8s-test-group

Both users:
- Have home directories at `/home/alice` and `/home/bob`
- Have bootstrap kubeconfigs at `~/.kube/bootstrap`
- Are configured in the test policy

## Mock Policy

The test uses a mock private policy repository at `/k8s-bastion-policy`:

**base.yaml** - Cluster configuration:
- Cluster name: test-cluster
- Test groups: k8s-test-group

**envs/test.yaml** - Test users:
- alice with k8s-test-group
- bob with k8s-test-group

## Troubleshooting

### Container fails to start

Check systemd status:
```bash
podman logs bastion-test
podman exec bastion-test systemctl status
```

### Tests fail due to missing tools

Check if download.sh was run before tests:
```bash
ls -la tools/
```

If empty, run:
```bash
./download.sh
```

### Policy rendering fails

Verify yq is installed (it should be installed by machine phase):
```bash
podman exec bastion-test which yq
```

### Permission denied errors

Ensure scripts are executable:
```bash
chmod +x tests/**/*.sh
```

## Notes

- **No Kubernetes cluster**: These tests validate the bastion setup without requiring a real K8s cluster. CSR approval will fail (expected), but everything up to CSR creation is tested.
- **Privileged containers**: Required for containerd installation and systemd operation
- **Cleanup**: All containers and volumes are removed after tests (`--no-cleanup` preserves them only on success)
- **Idempotent**: Tests clean up previous state before running
