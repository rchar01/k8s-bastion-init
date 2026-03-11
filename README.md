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
- You plan to run `bastion-csr-approver` and `bastion-csr-cleanup` periodically via cron or a systemd timer

## Overview

This project provides scripts and tooling to:
- Transform a clean Linux VM or repurpose a former Kubernetes node into a bastion host
- Manage Kubernetes access via short-lived client certificates (default: 7 days)
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

- **Mode 1: Simple** - edit `access-policy.yaml` directly in this repository; this file is the source of truth
- **Mode 2: Policy Merge** - keep sensitive configuration in `k8s-bastion-policy`; `bastion-render-policy` merges public base + private base + environment overlay

When using policy merge mode, never edit `access-policy.yaml` directly in this repository after rendering. Update the private policy repository instead.

## Quick Start

For a single command overview of common repository tasks, run:

```bash
make help
```

### Mode 1: Simple Setup

```bash
vim access-policy.yaml
sudo ./sbin/bastion-bootstrap-machine --init --source .
sudo ./sbin/bastion-bootstrap-users --init --source .
```

### Mode 2: Policy Merge Setup

```bash
sudo ./bastion_init.sh prod
sudo ./bastion_reconcile.sh prod
```

### Common Commands

```bash
# Download tool artifacts
make download

# Render merged policy manually
sudo ./sbin/bastion-render-policy --policy-repo ../k8s-bastion-policy --env prod --init-repo .

# User certificate renewal
bastion-kube-renew

# Admin verification
kubectl cluster-info
sudo bastion-kubeconfig-expiry

# Test suite
make test
```

For full bootstrap and reconcile procedures, see `docs/bastion-bootstrap.md`.

## Configuration Snapshot

The access policy defines:
- CSR settings such as signer, TTL, and group prefix
- Cluster connection settings including `cluster.caFile`
- Kubernetes-oriented Linux groups
- User-to-group mappings via `ensureGroups`

Example policy:

```yaml
apiVersion: bastion.access/v1

csr:
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 604800
  groupPrefix: "k8s-"

cluster:
  name: my-cluster
  server: https://10.0.0.1:6443
  caFile: /etc/kubernetes/pki/ca.crt

groups:
  k8s-developers:
    namespaces:
      - dev-namespace
      - staging-namespace
  k8s-admin:
    namespaces:
      - all

users:
  alice:
    ensureGroups:
      - k8s-developers
  bob:
    ensureGroups:
      - k8s-developers
      - k8s-admin
```

Policy merge mode uses these layers:

1. Public base: `access-policy.yaml`
2. Private base: `k8s-bastion-policy/base.yaml`
3. Environment overlay: `k8s-bastion-policy/envs/<env>.yaml`

Merge precedence is `Environment > Private > Public`.

Expected private policy repository structure:

```text
k8s-bastion-policy/
├── base.yaml
└── envs/
    ├── prod.yaml
    └── preprod.yaml
```

- `base.yaml` stores the private base policy, such as real cluster connection settings and shared groups
- `envs/<env>.yaml` stores environment-specific overlays, such as user assignments

Detailed examples for `base.yaml` and `envs/<env>.yaml` are in `docs/bastion-bootstrap.md`.

### Tool Configuration

`download.conf` defines tool versions and default URL templates used by `download.sh`.

- Override `*_URL` variables to use an internal mirror if needed
- After changing versions or URLs, run `./download.sh`
- Bootstrap and reconcile use the contents of `tools/`; they do not download artifacts automatically

Example override:

```bash
KUBECTL_URL='https://mirror.example/k8s/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl'
```

## Repository Layout

```text
.
├── bin/                          # User-facing commands
├── sbin/                         # Admin commands
├── lib/                          # Shared libraries
├── docs/                         # Project documentation
├── Makefile                      # Convenience targets for local workflows
├── kubeconfigs/                  # Admin kubeconfig templates
├── tools/                        # Downloaded tool artifacts
├── bastion_init.sh               # Wrapper: machine -> render -> users init
├── bastion_reconcile.sh          # Wrapper: machine -> render -> users reconcile
├── access-policy.yaml            # Policy source or public base template
├── user-tools.txt                # Tools visible to all users
├── admin-tools.txt               # Tools visible to k8s-admin users
├── download.sh                   # Tool download helper
├── download.conf                 # Tool version and URL configuration
└── VERSION                       # Project version
```

## Core Scripts

### User Scripts

- **`bastion-kube-renew`**: user self-service certificate renewal based on current host groups

### Admin Scripts

- **`bastion-bootstrap-machine`**: machine setup for containerd, tools, and installed scripts
- **`bastion-bootstrap-users`**: installs policy, groups, kubeconfigs, and login profile
- **`bastion-render-policy`**: merges policy from public, private, and environment layers
- **`bastion-bootstrap-user-groups`**: creates groups and assigns policy-managed supplementary groups
- **`bastion-bootstrap-kubeconfig`**: creates bootstrap kubeconfigs for users defined in policy
- **`bastion-bootstrap-admin-kubeconfig`**: installs admin kubeconfigs for users in the `k8s-admin` policy group
- **`bastion-csr-approver`**: one-shot CSR approval command intended for periodic execution
- **`bastion-csr-cleanup`**: removes old bastion-managed CSRs
- **`bastion-kubeconfig-expiry`**: checks client certificate expiration
- **`bastion-login-profile`**: generates the SSH login banner and tool summary
- **`bastion-audit-kube-dirs`**: audits per-user `.kube` directories

### Wrapper Scripts

- **`bastion_init.sh`**: Mode 2 initialization using machine -> render -> users
- **`bastion_reconcile.sh`**: Mode 2 update workflow using machine -> render -> users

### Makefile Convenience Targets

- **`make help`**: list common repository tasks
- **`make download`**: run `./download.sh`
- **`make test`**: run the full Podman-based test suite
- **`make test-no-cleanup`**: run tests and keep the container for inspection
- **`make test-setup`** / **`make test-cleanup`**: manage the test container lifecycle
- **`make init ENV=<env>`**: convenience wrapper for `sudo ./bastion_init.sh <env>`
- **`make reconcile ENV=<env>`**: convenience wrapper for `sudo ./bastion_reconcile.sh <env>`

The shell scripts remain the primary operational interface. The `Makefile` is a convenience layer for common local and operator tasks.

## Day-2 Operations

Common maintenance tasks after initial bootstrap:

- **Policy changed**
  - Mode 1: edit `access-policy.yaml`, then run `sudo ./sbin/bastion-bootstrap-machine --reconcile --source .` and `sudo ./sbin/bastion-bootstrap-users --reconcile --source .`
  - Mode 2: update `k8s-bastion-policy`, then run `sudo ./bastion_reconcile.sh <env>` or `make reconcile ENV=<env>`
- **New user added**
  - add the Linux user on the bastion
  - add the user in policy
  - reconcile
  - run `sudo bastion-bootstrap-kubeconfig --user <user>`
  - have the user log in and run `bastion-kube-renew`
- **Group membership changed**
  - update policy and reconcile
  - have the user start a new login session
  - have the user run `bastion-kube-renew`
- **Tool versions updated**
  - update `download.conf`
  - run `./download.sh` or `make download`
  - reconcile the machine phase
- **Periodic operator tasks**
  - run `bastion-csr-approver` on a schedule
  - run `bastion-csr-cleanup` on a schedule
  - review `sudo bastion-kubeconfig-expiry`

For the full operator runbook, see `docs/bastion-bootstrap.md`.

## Certificate Lifecycle

1. User runs `bastion-kube-renew`
2. The script reads the user's current `k8s-*` groups from the host
3. A CSR is created with `CN=<username>` and `O=<group>` values
4. `bastion-csr-approver` validates signer, usages, CN, prefix, and current host group membership
5. The signed certificate is embedded into `~/.kube/config`
6. The certificate expires automatically after its TTL

This repository does not install CSR approval or cleanup timers for you. Operators should schedule `bastion-csr-approver` and `bastion-csr-cleanup` separately.

## Testing

A comprehensive Podman-based test suite is available. See `tests/README.md` for full details.

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
- Writes policy and kube-related files under `/etc/kubernetes`
- Installs login profile under `/etc/profile.d`
- Installs and manages `containerd` via systemd

## Security Model

- **Users**: can request certificates, but cannot approve them or request arbitrary groups
- **Admins**: enforce access indirectly through host group membership, policy-driven bootstrap, and CSR approval
- **Certificates**: are short-lived by default and expire automatically
- **Identity**: current host group membership is the source of truth during renewal approval

## License

MIT License. See `LICENSE`.
