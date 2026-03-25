# Kubernetes Bastion Host Toolkit

<div align="center">
  <img src="docs/assets/k8s-bastion-init-transparent.png" width="256">
</div>

A toolkit for turning a clean Linux VM or a former Kubernetes node into a secure bastion host with short-lived certificate-based access management.

## Installation

### Clone This Repository

```bash
git clone https://codeberg.org/rch/k8s-bastion-init
cd k8s-bastion-init
```

### Optional: Clone Private Policy Repository

If you are using the production policy-merge workflow, clone the private policy repository next to this one:

```bash
cd ..
git clone https://codeberg.org/rch/k8s-bastion-policy
```

Expected layout:

```text
/workspace/
├── k8s-bastion-init/
└── k8s-bastion-policy/
```

### Prerequisites

- A Linux host you want to convert into a bastion host
- `sudo` access on that host
- For production mode: access to the private `k8s-bastion-policy` repository
- Downloaded tool artifacts in `tools/` via `./download.sh`
- A real admin kubeconfig template at `kubeconfigs/k8s-admin.kubeconfig`
- A valid `cluster.caFile` path in policy that exists on the bastion host

### Prepare Bootstrap Inputs

Before running machine or users bootstrap:

```bash
./download.sh
```

Also make sure:

- `kubeconfigs/k8s-admin.kubeconfig` contains a real admin kubeconfig template for the target cluster
- `cluster.caFile` in your policy points to a readable CA certificate on the bastion host
- Bootstrap will install and enable systemd timers for `bastion-csr-approver`, `bastion-csr-cleanup`, and `bastion-cert-renew` by default

## Overview

This project provides scripts and tooling to:
- Transform a clean Linux VM or repurpose a former Kubernetes node into a bastion host
- Manage Kubernetes access via short-lived client certificates (policy-driven, bounded to 1h..24h)
- Automate user/group management based on Linux system groups
- Provide self-service certificate renewal for users
- Install and manage common Kubernetes client tools

## How It Works

This toolkit has a two-phase architecture that separates machine setup from user configuration:

1. **Machine Phase** (`bastion-bootstrap-machine`): installs containerd, tools, and bastion scripts
2. **Users Phase** (`bastion-bootstrap-users`): installs policy, groups, kubeconfigs, and login profile

The users phase depends on `yq`, which is installed by the machine phase. That is why wrapper workflows run in this order:

1. Machine
2. Render policy when using private overlays
3. Users

### Configuration Modes

- **Mode 1: Simple (non-production)** - edit `access-policy.yaml` directly in this repository; suitable for labs, testing, and small standalone setups
- **Mode 2: Policy Merge (recommended for production)** - keep sensitive configuration in `k8s-bastion-policy`; `bastion-render-policy` merges public base + private base + environment overlay

When using policy merge mode, never edit `access-policy.yaml` directly in this repository after rendering. Update the private policy repository instead.

## Quick Start

For a single command overview of common repository tasks, run:

```bash
make help
```

Use `make` as a convenience layer for discovery and local workflows.
Use the shell scripts as the primary operational interface.

- **Production / recommended**
  - use Mode 2 with `k8s-bastion-policy`
  - initialize with `sudo ./bastion_init.sh <env>`
  - update with `sudo ./bastion_reconcile.sh <env>`
- **Non-production / simple**
  - use Mode 1 with `access-policy.yaml` directly in this repo
  - initialize and reconcile with the direct `bastion-bootstrap-machine` and `bastion-bootstrap-users` commands

For exact bootstrap, reconcile, production rollout, and operator runbook procedures, see `docs/bastion-bootstrap.md`.

### Common Commands

```bash
# Download tool artifacts
make download

# Format shell scripts in-place
make fmt-shell

# Check shell formatting (no writes)
make fmt-shell-check

# Run shell lint checks
make lint-shell

# Run shell formatting + lint checks
make check-shell

# Render merged policy manually
sudo ./sbin/bastion-render-policy --policy-repo ../k8s-bastion-policy --env prod --init-repo .

# Production bootstrap
sudo ./bastion_init.sh prod

# Production reconcile
sudo ./bastion_reconcile.sh prod

# User certificate renewal
bastion-kube-renew

# Admin verification
kubectl cluster-info
bastion-kubeconfig-expiry

# Test suite
make test
```

## Shell Quality Checks

Use these targets for fast, local shell script quality checks.

- `make fmt-shell` - format shell files in-place with `shfmt -i 2 -ci -sr -bn -w .`
- `make fmt-shell-check` - verify shell formatting without modifying files (returns non-zero when diffs exist)
- `make lint-shell` - run `shellcheck` across repository shell scripts
- `make check-shell` - run both formatting check and shell lint in one command

Recommended usage:

- After editing shell scripts: run `make fmt-shell`
- Before commit or PR: run `make check-shell`
- Before release or broader validation: run `make check-shell && make test`

## Configuration Snapshot

The access policy defines:
- CSR settings such as signer, TTL, and group prefix
- Cluster connection settings including `cluster.caFile`
- Kubernetes-oriented Linux groups
- User-to-group mappings via `ensureGroups`

Contract note: bastion CSR scripts enforce signer `platform.example.io/client` as a fixed integration constant.

Minimal example:

```yaml
csr:
  signerName: platform.example.io/client
  expirationSeconds: 28800
  groupPrefix: "k8s-"

cluster:
  name: my-cluster
  server: https://10.0.0.1:6443
  caFile: /etc/kubernetes/ca.crt
```

Recommended: use `/etc/kubernetes/ca.crt` on bastion hosts. Avoid `/etc/kubernetes/pki/ca.crt` for bastion `--init` flows, because node cleanup can remove `/etc/kubernetes/pki`.

Policy merge mode uses these layers:

1. Public base: `access-policy.yaml`
2. Private base: `k8s-bastion-policy/base.yaml`
3. Environment overlay: `k8s-bastion-policy/envs/<env>.yaml`

Merge precedence is `Environment > Private > Public`.

For the expected private policy repository structure and full examples, see `docs/bastion-bootstrap.md`.

## Configuration Files

This repository intentionally keeps different configuration inputs separate:

- `access-policy.yaml` - main bastion access policy in Mode 1, and the rendered public output in Mode 2
- `k8s-bastion-policy/base.yaml` - private base policy for Mode 2
- `k8s-bastion-policy/envs/<env>.yaml` - environment-specific policy overlays for Mode 2
- `download.conf` - tool versions and download URL configuration for `download.sh`
- `user-tools.txt` - tool names shown to regular bastion users
- `admin-tools.txt` - additional tool names shown to `k8s-admin` users
- `kubeconfigs/k8s-admin.kubeconfig` - admin kubeconfig template installed for privileged users

Runtime files created during bootstrap:

- `/etc/kubernetes/admin.kubeconfig` - host-level kubeconfig used by `bastion-csr-approver` and `bastion-csr-cleanup` services

Additional repository metadata and generated state:

- `VERSION` - project version metadata
- `.policy-env` - last rendered environment marker for Mode 2

These files are kept separate because they have different roles, change cadences, and consumers.

### Tool Configuration

`download.conf` defines tool versions and default URL templates used by `download.sh`.

- Override `*_URL` variables to use an internal mirror if needed
- After changing versions or URLs, run `./download.sh`
- Bootstrap and reconcile use the contents of `tools/`; they do not download artifacts automatically

Example override:

```bash
KUBECTL_URL='https://mirror.example/k8s/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl'
```

## Core Scripts

- `./download.sh` - download tool artifacts defined in `download.conf`
- `./bastion_init.sh <env>` - production bootstrap wrapper for Mode 2
- `./bastion_reconcile.sh <env>` - production reconcile wrapper for Mode 2
- `sudo bastion-disable-user --user <user>` - disable bastion-managed Kubernetes access for a target user
- `sudo bastion-manage-csr-timers --remove` - remove default CSR approver/cleanup systemd timers
- `sudo bastion-manage-cert-renew-timer --install` - install transparent renewal timer
- `sudo bastion-manage-cluster-status-timer --install` - install timer that refreshes login-banner cluster status cache
- `sudo bastion-cluster-probe` - run one-shot cluster status cache refresh
- `sudo bastion-bootstrap-token-issue --user <user> --reason initial-enrollment --json` - issue short-lived bootstrap kubeconfig via in-cluster issuer
- `sudo bastion-bootstrap-token-revoke --token-id <id>` - revoke bootstrap token via in-cluster issuer
- `bastion-login-bootstrap --quiet` - login-triggered best-effort auto-bootstrap
- `bastion-renew-cert --quiet` - non-interactive renewal engine
- `bastion-kube-renew` - manual renewal wrapper
- `make help` - list convenience targets for local workflows and tests

For the full script reference, see `docs/bastion-bootstrap.md` and `docs/k8s-users-management.md`.

## Day-2 Operations

For the full operator runbook, including reconcile, new-user onboarding,
tool updates, and periodic maintenance, see `docs/bastion-bootstrap.md`.

## Certificate Lifecycle

User access is based on short-lived certificates with login-triggered bootstrap
recovery and timer-driven transparent renewal. For the detailed flow,
see `docs/k8s-users-management.md`.

## Testing

A comprehensive Podman-based test suite is available. See `tests/README.md` for full details.

For quick static shell checks, run `make check-shell`.
Use `make test` for the full container-based integration suite.

Quick run:

```bash
./tests/run-all.sh
# or
make test
```

The test suite validates:
- Machine setup and tool installation
- Policy rendering from a mock private repository
- User and group configuration
- Init and reconcile workflows

## Documentation

- `docs/architecture.md` - high-level architecture and access flow diagram
- `docs/bastion-bootstrap.md` - full operator bootstrap and reconcile guide
- `docs/k8s-users-management.md` - user access, renewal, approver, and cleanup guide
- `tests/README.md` - test suite usage and troubleshooting

## Requirements

- Linux system
- Root access for bootstrap and reconcile
- Kubernetes cluster access
- `dnf` package manager for containerd installation path used by this repository

## System Changes

This toolkit is designed to be run as root for bootstrap and reconcile and will modify the host.

Common changes include:
- Installs scripts and libraries under `/usr/local/bin`, `/usr/local/sbin`, `/usr/local/lib/bastion`
- Installs admin scripts in `/usr/local/sbin` with restricted execute permissions (`0750`)
- Writes policy and kube-related files under `/etc/kubernetes`
- Installs login profile under `/etc/profile.d`
- Installs and manages `containerd` via systemd
- Installs and enables CSR processing timers under `/etc/systemd/system`
- Installs `/etc/sudoers.d/bastion-path` to ensure `sudo` resolves `/usr/local/sbin` commands

## Security Model

- **Users**: can request certificates, but cannot approve them or request arbitrary groups
- **Admins**: enforce access indirectly through host group membership, policy-driven bootstrap, and CSR approval
- **Certificates**: are short-lived by default and expire automatically
- **Identity**: current host group membership is the source of truth during renewal approval

## License

MIT License. See `LICENSE`.
