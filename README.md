# Kubernetes Bastion Host Toolkit

A toolkit for converting former Kubernetes nodes into secure bastion hosts with short-lived certificate-based access management.

## Overview

This project provides scripts and tooling to:
- Transform a Kubernetes node into a clean bastion host
- Manage Kubernetes access via short-lived client certificates (default: 7 days)
- Automate user/group management based on Linux system groups
- Provide self-service certificate renewal for users
- Install and manage common Kubernetes client tools

## Quick Start

### Architecture Overview

This toolkit has a **two-phase architecture** that separates machine setup from user configuration:

1. **Machine Phase** (`bastion-bootstrap-machine`): Installs containerd, tools, and scripts
2. **Users Phase** (`bastion-bootstrap-users`): Configures policy, groups, and kubeconfigs

**Why the split?** The users phase requires `yq` to parse YAML files, but yq isn't installed until the machine phase completes. This separation also allows you to:
- Set up the machine without needing a policy file
- Update machine and users independently
- Render policy from a private repository (requires yq)

### Mode 1: Simple Setup (Single Policy File)

For basic setups, edit `access-policy.yaml` directly:

```bash
# 1. Configure the policy
vim access-policy.yaml

# 2. Bootstrap everything at once
sudo ./bastion_init.sh <environment>

# Example:
sudo ./bastion_init.sh prod
```

### Mode 2: Production Setup (Policy Merge)

**⚠️ IMPORTANT:** When using policy merge mode, never edit `access-policy.yaml` directly. Always edit files in your private `k8s-bastion-policy` repository.

#### Initial Setup

```bash
# Using wrapper script (does machine setup, renders policy, configures users)
sudo ./bastion_init.sh <environment>

# Example:
sudo ./bastion_init.sh prod
```

This will:
1. Install containerd, tools (including yq), and bastion scripts
2. Render policy from private repository (now yq is available!)
3. Configure users, groups, and kubeconfigs

#### Update Configuration (When Private Policy Changes)

```bash
# Update everything
sudo ./bastion_reconcile.sh <environment>

# Example:
sudo ./bastion_reconcile.sh prod
```

#### Manual Steps (Advanced)

If you need to run phases separately:

```bash
# 1. Machine setup (installs yq)
sudo ./sbin/bastion-bootstrap-machine --init --source .

# 2. Render policy (requires yq from step 1)
sudo ./sbin/bastion-render-policy \
  --policy-repo ../k8s-bastion-policy \
  --env prod \
  --init-repo .

# 3. Configure users (requires rendered policy)
sudo ./sbin/bastion-bootstrap-users --init --source .
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Bastion Host                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Linux Users  │  │  k8s-*       │  │ Certificate  │       │
│  │ & Groups     │──│  Groups      │──│ Management   │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│         │                   │                   │           │
│         └───────────────────┴───────────────────┘           │
│                             │                               │
│                    ┌────────▼───────────┐                   │
│                    │ Kubernetes Cluster │                   │
│                    │   (CSR API)        │                   │
│                    └────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Architecture

This project supports two configuration modes:

### Mode 1: Simple (Single Policy File)
Edit `access-policy.yaml` directly in this repository for basic setups.

### Mode 2: Policy Merge (Recommended for Production)
Uses a **three-layer policy merge system** for managing sensitive configuration separately:

1. **Public Base** (`access-policy.yaml`) - Base structure in this repo (dummy/template)
2. **Private Base** (`k8s-bastion-policy/base.yaml`) - Sensitive configuration (cluster URLs, etc.)
3. **Environment Overlay** (`k8s-bastion-policy/envs/<env>.yaml`) - Environment-specific settings

**Merge precedence:** Environment > Private > Public

### Expected Directory Structure (Mode 2)

```
/workspace/
├── k8s-bastion-init/           # This repository (public)
│   ├── bastion_init.sh         # Wrapper: render + init
│   ├── bastion_reconcile.sh    # Wrapper: render + reconcile
│   ├── sbin/
│   │   └── bastion-render-policy
│   └── access-policy.yaml      # Public base (template)
└── k8s-bastion-policy/         # Private policy repository
    ├── base.yaml               # Private base configuration
    └── envs/
        ├── prod.yaml           # Production overlay
        └── preprod.yaml        # Pre-production overlay
```

## Directory Structure

```
.
├── bin/                           # User-facing commands
│   └── bastion-kube-renew        # Self-service certificate renewal
├── sbin/                          # Admin commands
│   ├── bastion-bootstrap-machine # Machine setup (containerd, tools)
│   ├── bastion-bootstrap-users   # User setup (policy, groups, kubeconfigs)
│   ├── bastion-bootstrap-*       # Component bootstrap scripts
│   ├── bastion-csr-*             # CSR management
│   ├── bastion-install-*         # Installation scripts
│   ├── bastion-render-policy     # Policy merge/render script
│   └── bastion-*                 # Other admin utilities
├── lib/                           # Shared libraries
│   ├── log.sh                    # Logging functions
│   ├── common.sh                 # Common utilities
│   ├── args.sh                   # Argument parsing
│   └── system.sh                 # System helpers
├── docs/                          # Documentation
│   ├── bastion-bootstrap.md      # Bootstrap documentation
│   └── k8s-users-management.md   # User management guide
├── kubeconfigs/                   # Admin kubeconfig storage
│   └── k8s-admin.kubeconfig      # Admin kubeconfig template
├── bastion_init.sh               # Main entry point: machine → render → users init
├── bastion_reconcile.sh          # Main entry point: machine → render → users reconcile
├── access-policy.yaml            # Access policy (public base or rendered)
├── user-tools.txt                # List of tools for all users
├── admin-tools.txt               # List of admin tools
├── download.sh                   # Tool download script
├── download.conf                 # Tool version configuration
└── VERSION                       # Version file
```

## Core Scripts

### User Scripts (`bin/`)

- **bastion-kube-renew**: Users run this to obtain new certificates based on their group membership

### Admin Scripts (`sbin/`)

**Core Bootstrap Scripts:**
- **bastion-bootstrap-machine**: Machine setup - installs containerd, tools (yq, kubectl, etc.), and bastion scripts
- **bastion-bootstrap-users**: User setup - configures policy, groups, kubeconfigs, and login profiles (requires yq from machine phase)

**Policy Management:**
- **bastion-render-policy**: Merges policy from public + private + environment layers (requires yq - must run after machine setup)

**Helper Scripts:**
- **bastion-bootstrap-user-groups**: Creates groups and assigns users from policy
- **bastion-bootstrap-kubeconfig**: Bootstrap user kubeconfigs
- **bastion-bootstrap-admin-kubeconfig**: Setup admin kubeconfig for privileged users
- **bastion-csr-approver**: Automated CSR approval daemon
- **bastion-csr-cleanup**: Removes expired CSR objects
- **bastion-install-containerd**: Installs containerd runtime
- **bastion-install-tools**: Installs Kubernetes client tools (including yq)
- **bastion-kubeconfig-expiry**: Check certificate expiration
- **bastion-login-profile**: Manages user login messages
- **bastion-audit-kube-dirs**: Audit user kubeconfig directories
- **bastion-version**: Display installed version

### Wrapper Scripts (Root Directory)

**Primary Entry Points:**
- **bastion_init.sh**: Main initialization - installs machine, renders policy, configures users (requires `<environment>`)
  - Execution order: Machine → Render Policy → Configure Users
  - This ensures yq is installed before attempting to render policy
- **bastion_reconcile.sh**: Updates existing installation - reconciles machine, renders policy, updates users (requires `<environment>`)

**Quick Reference:**
```bash
# Initial setup
sudo ./bastion_init.sh prod

# Update configuration (when policy changes)
sudo ./bastion_reconcile.sh prod

# Manual steps (if needed)
sudo ./sbin/bastion-bootstrap-machine --init --source .
sudo ./sbin/bastion-render-policy --policy-repo ../k8s-bastion-policy --env prod --init-repo .
sudo ./sbin/bastion-bootstrap-users --init --source .
```

## Configuration

This toolkit supports two configuration modes:

- **Mode 1: Simple** - Single policy file in this repository
- **Mode 2: Policy Merge** - Three-layer merge (public + private + environment)

### Mode 1: Simple Configuration (Single File)

For basic setups or when you don't need to separate sensitive configuration:

**IMPORTANT:** The `access-policy.yaml` file in this repository is your **source of truth**. Always edit this file in the repository/project directory, NOT in `/etc/kubernetes/access-policy.yaml` (which is a copy managed by the system).

The access policy defines:
- Certificate TTL and signer settings
- Cluster connection information
- Kubernetes groups and namespaces
- User-to-group mappings

#### Access Policy Sections

1. **CSR Configuration** - Certificate signing request settings
2. **Cluster Configuration** - Kubernetes cluster connection details
3. **Groups** - Define `k8s-*` groups and their associated namespaces
4. **Users** - Map system users to Kubernetes groups

#### Example Configuration

```yaml
apiVersion: bastion.access/v1

csr:
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 604800  # 7 days
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

  k8s-admins:
    namespaces:
      - all

users:
  alice:
    ensureGroups:
      - k8s-developers

  bob:
    ensureGroups:
      - k8s-developers
      - k8s-admins
```

#### Managing Users and Groups (Simple Mode)

To add or modify users and groups:

1. **Edit the policy file** in the repository:
   ```bash
   vim access-policy.yaml
   # Add/modify users and their group memberships
   ```

2. **Apply changes** using the reconcile command:
   ```bash
   sudo ./sbin/bastion-bootstrap --reconcile --source .
   ```

This will:
- Copy the updated policy to `/etc/kubernetes/access-policy.yaml`
- Create any new groups defined in the policy
- Update user group memberships
- Regenerate login profiles

**Note:** Users must exist on the Linux system before they can be added to the policy. The toolkit does not create system users.

### Mode 2: Policy Merge Configuration (Production)

For production setups where you want to keep sensitive configuration (cluster URLs, specific user lists) in a private repository separate from this public repository.

**⚠️ CRITICAL:** When using policy merge mode, **never edit** `access-policy.yaml` directly. It will be overwritten by `bastion-render-policy`. Always edit files in your private `k8s-bastion-policy` repository.

#### How Policy Merge Works

The `bastion-render-policy` script merges three layers:

1. **Public Base** (`access-policy.yaml` in this repo) - Base structure, dummy values
2. **Private Base** (`k8s-bastion-policy/base.yaml`) - Sensitive configuration, cluster details
3. **Environment Overlay** (`k8s-bastion-policy/envs/<env>.yaml`) - Environment-specific users/groups

**Merge precedence:** Later files override earlier ones (Environment > Private > Public)

#### Required Directory Structure

```
/workspace/
├── k8s-bastion-init/          # This repository
│   ├── bastion_init.sh
│   ├── bastion_reconcile.sh
│   ├── sbin/bastion-render-policy
│   └── access-policy.yaml     # Public base (template/dummy)
└── k8s-bastion-policy/        # Private repository
    ├── base.yaml              # Private base configuration
    └── envs/
        ├── prod.yaml          # Production environment
        └── preprod.yaml       # Pre-production environment
```

#### Private Policy Repository Structure

**`k8s-bastion-policy/base.yaml`** - Private base configuration:
```yaml
apiVersion: bastion.access/v1

cluster:
  name: production-cluster
  server: https://prod-k8s-api.internal:6443
  caFile: /etc/kubernetes/pki/ca.crt

# Private groups (not in public repo)
groups:
  k8s-production-admins:
    namespaces:
      - all
```

**`k8s-bastion-policy/envs/prod.yaml`** - Production environment:
```yaml
# Production users
users:
  alice:
    ensureGroups:
      - k8s-production-admins

  bob:
    ensureGroups:
      - k8s-developers
      - k8s-production-admins
```

#### Managing Users and Groups (Policy Merge Mode)

When your private policy changes:

1. **Edit files in your private repository** (`k8s-bastion-policy/`):
   ```bash
   cd /path/to/k8s-bastion-policy
   vim envs/prod.yaml  # Add/modify users
   vim base.yaml       # Modify cluster settings
   ```

2. **Apply changes** using the wrapper script:
   ```bash
   cd /path/to/k8s-bastion-init
   sudo ./bastion_reconcile.sh prod
   ```

   Or manually:
   ```bash
   # 1. Render the policy (merges all layers)
   sudo ./sbin/bastion-render-policy \
     --policy-repo ../k8s-bastion-policy \
     --env prod \
     --init-repo .

   # 2. Apply the rendered policy
   sudo ./sbin/bastion-bootstrap --reconcile --source .
   ```

#### Policy Rendering Reference

```bash
# Basic usage
bastion-render-policy --policy-repo DIR --env ENV [options]

# Options:
#   --policy-repo DIR    Path to private policy repository (required)
#   --env ENV           Environment name (required)
#   --init-repo DIR     Path to this repo (auto-detected)
#   --output FILE       Output file (default: <init-repo>/access-policy.yaml)
#   --env-marker FILE   Marker file to record environment
```

#### Initial Setup with Policy Merge

1. **Ensure directory structure is correct**:
   ```
   k8s-bastion-init/
   k8s-bastion-policy/   (at ../k8s-bastion-policy relative to init)
   ```

2. **Run initial bootstrap**:
   ```bash
   sudo ./bastion_init.sh prod
   ```

This will:
- Check that `k8s-bastion-policy` exists at expected location
- Render the merged policy to `access-policy.yaml`
- Run `bastion-bootstrap --init` to install everything

### Tool Configuration (`download.conf`)

Defines versions for client tools. Only edit this if you need to update tool versions:
- Kubernetes tools (kubectl, helm, k9s, stern)
- CLI utilities (jq, yq)
- Registry tools (crane, regctl, skopeo)
- etcd tools
- Container runtime (containerd, nerdctl, runc, CNI)

**Note:** After changing tool versions, run:
```bash
./download.sh
sudo ./sbin/bastion-bootstrap --reconcile --source .
```

## User Groups

Users are assigned to Linux groups with the `k8s-` prefix. These groups are defined in your access policy and automatically mapped to Kubernetes RBAC groups via certificate `O=` fields.

### Creating Groups

Groups are defined in the access policy (see [Configuration](#configuration) section):

```yaml
groups:
  k8s-developers:
    namespaces:
      - dev-namespace
      - staging-namespace
```

### Adding Users to Groups

**Prerequisites:** Users must exist on the Linux system first.

```bash
# Add user to Linux system
sudo useradd -m username

# Add to k8s-* group (optional - can be done via policy)
sudo usermod -aG k8s-developers username
```

Users are assigned to groups via the `ensureGroups` field in the policy (see Configuration section for detailed workflow).

## Typical Workflow

### Mode 1: Simple Configuration

#### Initial Setup

1. **Configure the policy** - Edit `access-policy.yaml` with your cluster details and user mappings

2. **Bootstrap the bastion** (first time only):
   ```bash
   sudo ./sbin/bastion-bootstrap --init --source .
   ```

#### Adding or Modifying Users

3. **Edit the access policy** in the repository:
   ```bash
   vim access-policy.yaml
   # Add new users or modify group assignments
   ```

4. **Apply changes** using reconcile:
   ```bash
   sudo ./sbin/bastion-bootstrap --reconcile --source .
   ```

### Mode 2: Policy Merge Configuration

#### Initial Setup

1. **Ensure directory structure is correct**:
   ```
   k8s-bastion-init/              # This repository
   k8s-bastion-policy/            # Private repo at ../k8s-bastion-policy
   ```

2. **Configure private policy** in `k8s-bastion-policy/`:
   - Edit `base.yaml` for cluster settings
   - Edit `envs/<environment>.yaml` for users

3. **Bootstrap the bastion** (first time only):
   ```bash
   sudo ./bastion_init.sh <environment>
   ```

   Example:
   ```bash
   sudo ./bastion_init.sh prod
   ```

#### Adding or Modifying Users

4. **Edit the private policy** in `k8s-bastion-policy/`:
   ```bash
   cd ../k8s-bastion-policy
   vim envs/prod.yaml
   # Add new users or modify group assignments
   ```

5. **Apply changes** using the wrapper script:
   ```bash
   cd ../k8s-bastion-init
   sudo ./bastion_reconcile.sh prod
   ```

   **⚠️ CRITICAL:** Never run reconcile without first rendering the policy! If the private policy changed but you didn't render it, the old policy will be used.

### User Certificate Renewal (Both Modes)

6. **User renews their certificate**:
   ```bash
   # Run as regular user (not root)
   bastion-kube-renew
   ```

### Maintenance

7. **Verify access**:
   ```bash
   kubectl cluster-info
   ```

8. **Check certificate expiry** (admins):
   ```bash
   sudo bastion-kubeconfig-expiry
   ```

### Key Commands Summary

| Command | Purpose |
|---------|---------|
| `bastion_init.sh <env>` | First-time setup with policy merge (Mode 2) |
| `bastion_reconcile.sh <env>` | Update configuration with policy merge (Mode 2) |
| `bastion-render-policy --policy-repo DIR --env ENV` | Render merged policy from private repo |
| `bastion-bootstrap --init --source .` | First-time initialization (Mode 1 or after render) |
| `bastion-bootstrap --reconcile --source .` | Update configuration without destructive changes |
| `bastion-kube-renew` | User self-service certificate renewal |
| `bastion-kubeconfig-expiry` | Check certificate expiration |

## Certificate Lifecycle

1. **User runs**: `bastion-kube-renew`
2. **Script reads**: User's `k8s-*` groups from system
3. **CSR created**: With CN=username, O=groups
4. **Automated approval**: Validates user and groups match
5. **Certificate issued**: Valid for 7 days (default)
6. **Kubeconfig updated**: User can access cluster
7. **Auto-expiration**: Certificate expires automatically

## Testing

A comprehensive test suite is available using Podman containers. See [tests/README.md](tests/README.md) for details.

**Quick test run:**
```bash
./tests/run-all.sh
```

The test suite:
- Creates Rocky Linux 9.5 container with systemd
- Tests machine setup (containerd, tools, yq installation)
- Tests policy rendering from mock private repository
- Tests users and groups configuration
- Validates complete init and reconcile workflows
- Cleans up containers after tests

## Documentation

- [Bootstrap Documentation](docs/bastion-bootstrap.md) - Detailed bootstrap process
- [User Management Guide](docs/k8s-users-management.md) - User access management and troubleshooting
- [Test Suite](tests/README.md) - Testing documentation

## Requirements

- Linux system (tested on RHEL/CentOS/Fedora)
- Root access for bootstrap
- Kubernetes cluster access
- `dnf` package manager (for containerd installation)

## System Changes

This toolkit is designed to be run as root for bootstrap/reconcile and will modify the host.

Common changes include:
- Installs scripts and libraries under `/usr/local/bin`, `/usr/local/sbin`, `/usr/local/lib/bastion`
- Writes policy/config under `/etc/kubernetes`
- Installs login profile under `/etc/profile.d`
- Installs and manages `containerd` via systemd

## Security Model

- **Users**: Can request certificates, cannot approve them, cannot choose arbitrary groups
- **Admins**: Validate CSR contents, enforce policy via automated approval
- **Certificates**: Short-lived (7 days), automatic expiration, no manual revocation needed
- **Identity**: Host groups are the source of truth, not Kubernetes

## License

MIT License. See `LICENSE`.

## Version

Current version: `1.0.0`
