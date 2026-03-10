# Bastion Host Toolkit (Kubernetes)

This repository contains scripts to turn a former Kubernetes node into a clean **bastion host** with short-lived certificate-based access management.

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

## Architecture Overview

This toolkit has a **two-phase architecture** that separates machine setup from user configuration:

1. **Machine Phase** (`bastion-bootstrap-machine`): Installs containerd, tools, and scripts
2. **Users Phase** (`bastion-bootstrap-users`): Configures policy, groups, and kubeconfigs

**Why the split?** The users phase requires `yq` to parse YAML files, but `yq` is not installed until the machine phase completes. This separation also allows you to:
- Set up the machine without needing a policy file
- Update machine and users independently
- Render policy from a private repository after the machine phase installs `yq`

## Configuration Modes

This toolkit supports two configuration approaches:

### Mode 1: Simple (Single Policy File)
Edit `access-policy.yaml` directly in this repository for basic setups. Good for testing or simple deployments.

### Mode 2: Policy Merge (Production)
Uses a three-layer merge system (public + private + environment) for managing sensitive configuration separately from this public repository. 

## Configuration Architecture

### Mode 1: Simple (Single Policy File)

Edit `access-policy.yaml` directly in this repository for basic setups.

### Mode 2: Policy Merge (Recommended for Production)

Uses a three-layer policy merge system for managing sensitive configuration separately:

1. **Public Base** (`access-policy.yaml`) - Base structure in this repo
2. **Private Base** (`k8s-bastion-policy/base.yaml`) - Sensitive configuration such as cluster URLs
3. **Environment Overlay** (`k8s-bastion-policy/envs/<env>.yaml`) - Environment-specific settings

**Merge precedence:** Environment > Private > Public

**⚠️ IMPORTANT:** When using policy merge mode, never edit `access-policy.yaml` directly. Always edit files in your private `k8s-bastion-policy` repository.

## Scripts

### 1) `bastion_init.sh` / `bastion_reconcile.sh`

**Main wrapper scripts that orchestrate the entire setup.**

**`bastion_init.sh`** - First-time initialization:
```bash
sudo ./bastion_init.sh <environment>
# Example: sudo ./bastion_init.sh prod
```

**`bastion_reconcile.sh`** - Update configuration:
```bash
sudo ./bastion_reconcile.sh <environment>
# Example: sudo ./bastion_reconcile.sh prod
```

Both scripts execute in this order:
1. **Machine setup** (`bastion-bootstrap-machine`) - Installs containerd, tools (including yq), scripts
2. **Policy rendering** (`bastion-render-policy`) - Merges policy from private repo (requires yq from step 1)
3. **Users setup** (`bastion-bootstrap-users`) - Configures groups, kubeconfigs, login profiles

**⚠️ CRITICAL:** Machine setup runs BEFORE policy rendering to ensure `yq` is installed.

**Environment argument is required** for both scripts.

**What it does**
- Installs containerd, tools (kubectl, helm, yq, etc.), and bastion scripts
- Renders policy from private repository (after machine setup ensures yq is available)
- Configures users, groups, and kubeconfigs
- Stops/disables node services (kubelet/container runtime) if present
- Removes node binaries and runtime/node state (only in --init mode)
- Installs kubeconfigs to user home directories
- Installs `/etc/profile.d/bastion-login.sh` for user login information
- Verifies end state.

**Running phases manually** (without wrapper):
``` bash
# 1. Machine setup (installs yq)
sudo ./sbin/bastion-bootstrap-machine --init --source .

# 2. Render policy (requires yq from step 1)
sudo ./sbin/bastion-render-policy \
  --policy-repo ../k8s-bastion-policy \
  --env prod \
  --init-repo .

# 3. Users setup
sudo ./sbin/bastion-bootstrap-users --init --source .
```

**⚠️ WARNING:** Do not run `bastion-render-policy` before `bastion-bootstrap-machine` - it requires yq which is installed by the machine phase.

### 2) `bastion-render-policy` (Admin Script)

Merges access policy from three layers: public base + private base + environment overlay.

**What it does**
- Merges `access-policy.yaml` (public) with `k8s-bastion-policy/base.yaml` (private)
- Applies environment-specific overlay `k8s-bastion-policy/envs/<env>.yaml`
- Writes merged result to `access-policy.yaml` in this repository
- Records environment marker for tracking

**⚠️ WARNING:** This overwrites `access-policy.yaml` in this repo. Never edit that file directly when using policy merge mode.

**Usage**

```bash
# Basic usage
sudo ./sbin/bastion-render-policy --policy-repo DIR --env ENV

# With explicit paths
sudo ./sbin/bastion-render-policy \
  --policy-repo ../k8s-bastion-policy \
  --env prod \
  --init-repo .
```

**Required Arguments:**
- `--policy-repo DIR` - Path to private policy repository
- `--env ENV` - Environment name (e.g., prod, preprod)

**Optional Arguments:**
- `--init-repo DIR` - Path to this repository (auto-detected)
- `--output FILE` - Output file (default: <init-repo>/access-policy.yaml)
- `--env-marker FILE` - Marker file to record environment

**Expected Directory Structure:**
```
/workspace/
├── k8s-bastion-init/              # This repository
│   ├── bastion_init.sh
│   ├── bastion_reconcile.sh
│   └── access-policy.yaml         # Will be overwritten by render
└── k8s-bastion-policy/            # Private repository
    ├── base.yaml                  # Private base config
    └── envs/
        ├── prod.yaml              # Production overlay
        └── preprod.yaml           # Pre-production overlay
```

### 3) `bastion-kube-renew` (User Script)

Generates/refreshes a **user kubeconfig** using the Kubernetes CSR API based on the user's Linux group membership.

**What it does**
- Reads user's `k8s-*` groups from the system.
- Creates a CSR with CN=username, O=groups.
- Waits for automated approval.
- Builds a kubeconfig with embedded certificate.
- Installs it to `~/.kube/config`.
- Backs up existing kubeconfig: `*.bak.TIMESTAMP`.

**Usage**

``` bash
# Run as regular user (not root)
bastion-kube-renew
```

**Requirements**
- Must have a bootstrap kubeconfig at `~/.kube/bootstrap`
- Must belong to at least one `k8s-*` group
- User must exist in the access policy file

**Important**
- This script cannot be run as root.
- Certificate is valid for 7 days by default (configurable in policy).

### 4) `bastion-bootstrap-user-groups` (Admin Script)

Bulk, idempotent management of users' supplementary Unix group memberships based on the access policy.

**What it does**
- Reads users and groups from the access policy.
- Creates groups if missing.
- Ensures users are members of specified groups.
- Does not create users (users must exist on system).

**Usage**

``` bash
sudo bastion-bootstrap-user-groups [--policy FILE]

# Default policy location: /etc/kubernetes/access-policy.yaml
```

**Input**

Groups and users are read from the policy file (`access-policy.yaml`):

```yaml
groups:
  k8s-developers:
    namespaces:
      - dev-namespace

users:
  alice:
    ensureGroups:
      - k8s-developers
```

**Note:** This script is called automatically by `bastion-bootstrap-users`. You usually don't need to run it manually unless you want to update groups without running a full users setup.

### 5) `bastion-audit-kube-dirs` (Admin Script)

Audits per-user kubeconfig directories.

**What it does**
- Lists users with home directories under `/home`.
- For each, reports whether `~/.kube` exists and prints its non-recursive contents.

**Usage**

``` bash
sudo bastion-audit-kube-dirs [--home-prefix DIR] [--no-list]
```

**Options**
- `--home-prefix DIR` - Scan homes under DIR (default: /home)
- `--no-list` - Do not list directory contents

### 6) `bastion-kubeconfig-expiry` (Admin Script)

Helper script to inspect **client certificate expiration dates** for kubeconfigs (works with embedded certs or file-referenced certs).

**Usage**
```bash
bastion-kubeconfig-expiry
bastion-kubeconfig-expiry ~/.kube
bastion-kubeconfig-expiry ~/.kube/config
```

**Options**
- `WARN_DAYS=30` (default: `30`) - Highlight kubeconfigs expiring in `<= WARN_DAYS`.

Example:
```bash
WARN_DAYS=14 bastion-kubeconfig-expiry ~/.kube
```


## Directory Layout (expected)

- `./bin/` — user-facing scripts installed to `/usr/local/bin`
- `./sbin/` — admin scripts installed to `/usr/local/sbin`
- `./lib/` — shared library functions installed to `/usr/local/lib/bastion`
- `./tools/` — downloaded tool binaries (kubectl, helm, k9s, jq, yq, etc.)
- `./kubeconfigs/` — admin kubeconfig templates (k8s-admin.kubeconfig)
- `./docs/` — documentation files
- `bastion_init.sh` — wrapper: render policy + init bootstrap
- `bastion_reconcile.sh` — wrapper: render policy + reconcile bootstrap
- `access-policy.yaml` — central access policy (source or rendered)
- `user-tools.txt` — list of tools available to all users
- `admin-tools.txt` — list of tools available to k8s-admin group
- `VERSION` — version file

## User login notice (SSH only)

The bastion displays login information automatically based on Unix group membership via:

- `/etc/profile.d/bastion-login.sh`

On a **fresh interactive SSH login**, users see a short banner showing:
- Kubernetes access status and certificate expiry
- Available tools based on user/admin group membership
- k8s-* groups the user belongs to

Notes:
- The message is shown only for interactive shells over SSH (`SSH_CONNECTION` is set).
- Users must re-login to pick up group changes (or `source /etc/profile.d/bastion-login.sh`).

## Typical Workflow

### Mode 1: Simple Configuration (Single Policy File)

For basic setups where you edit `access-policy.yaml` directly:

1. **Configure the policy**:
   ```bash
   vim access-policy.yaml
   # Edit cluster settings, groups, users
   ```

2. **Bootstrap the bastion** (first time):
   ```bash
   sudo ./sbin/bastion-bootstrap-machine --init --source .
   sudo ./sbin/bastion-bootstrap-users --init --source .
   ```

3. **Update configuration** (later):
   ```bash
   vim access-policy.yaml
   sudo ./sbin/bastion-bootstrap-machine --reconcile --source .
   sudo ./sbin/bastion-bootstrap-users --reconcile --source .
   ```

### Mode 2: Policy Merge Configuration (Production)

For setups with sensitive configuration in a private repository:

**Expected directory structure:**
```
/workspace/
├── k8s-bastion-init/              # This repo
└── k8s-bastion-policy/            # Private repo
    ├── base.yaml                  # Private base config
    └── envs/
        ├── prod.yaml              # Production overlay
        └── preprod.yaml           # Pre-production overlay
```

1. **Configure the private policy**:
   ```bash
   cd ../k8s-bastion-policy
   vim base.yaml                    # Cluster settings, etc.
   vim envs/prod.yaml               # Production users
   ```

2. **Bootstrap the bastion** (first time):
   ```bash
   cd ../k8s-bastion-init
   sudo ./bastion_init.sh prod
   ```

3. **Update configuration** (later - ⚠️ CRITICAL WORKFLOW):
   ```bash
   cd ../k8s-bastion-policy
   vim envs/prod.yaml               # Modify users
   
   cd ../k8s-bastion-init
   sudo ./bastion_reconcile.sh prod
   ```

   **⚠️ NEVER run bootstrap directly after policy changes!** Always use the wrapper or render policy first.

### What Each Mode Uses

- **Mode 1** - Run `bastion-bootstrap-machine` and `bastion-bootstrap-users` directly against the repository policy file
- **Mode 2** - Run `bastion_init.sh` or `bastion_reconcile.sh` so policy rendering happens before user configuration

### User Certificate Renewal (Both Modes)

Users renew their certificates independently of admin configuration:

```bash
# Run as regular user (not root)
bastion-kube-renew
```

**Note:** Users must re-run `bastion-kube-renew` after admin changes to their group memberships.

### Verification

```bash
# Check access
kubectl cluster-info

# Check certificate expiry (admins)
sudo bastion-kubeconfig-expiry
```

## Troubleshooting

### Policy Rendering Issues

**Error: Policy repository not found at: ../k8s-bastion-policy**
- Ensure `k8s-bastion-policy` directory exists at the expected location (one directory up from k8s-bastion-init)
- Check directory structure matches [Typical Workflow](#typical-workflow) section

**Error: Missing required environment argument**
- `bastion_init.sh` and `bastion_reconcile.sh` require an environment argument
- Usage: `sudo ./bastion_init.sh <environment>` (e.g., `prod`, `preprod`)

**Policy changes not applied**
- Ensure machine setup completed successfully (check `yq` is installed: `which yq`)
- Run `bastion_init.sh` or `bastion_reconcile.sh` which handles the correct order: machine → render → users
- Do not run `bastion-bootstrap-users` directly after changing private policy without first rendering it
- Check `.policy-env` file exists to confirm last rendered environment

### General Issues

- If `echo $KUBECONFIG` is empty, ensure:
  - user is in the expected Unix group (`id -nG`)
  - `/etc/profile.d/bastion-login.sh` exists
  - user started a new login shell (re-login or `source /etc/profile.d/bastion-login.sh`)
- If kubectl talks to `localhost:6443`, the kubeconfig’s `clusters[].cluster.server` is wrong; update to the real API endpoint (LB/DNS/IP).
