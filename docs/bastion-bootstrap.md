# Bastion Host Toolkit Bootstrap Guide

This guide covers operator installation, bootstrap, reconcile, and policy-rendering workflows for the Kubernetes Bastion Host Toolkit.

For a high-level view of the bastion access model and certificate flow, see `docs/architecture.md`.

## Repository Placement

Start from a checked-out `k8s-bastion-init` repository. For clone commands, see `README.md`.

If you are using policy-merge mode, place the private repository next to this one.

Expected layout:

```text
/workspace/
├── k8s-bastion-init/
└── k8s-bastion-policy/
```

## Prerequisites

- A Linux host you want to convert into a bastion host
- `sudo` access on that host
- Downloaded tool artifacts in `tools/` via `./download.sh`
- A real admin kubeconfig template at `kubeconfigs/k8s-admin.kubeconfig`
- A valid `cluster.caFile` path in policy that exists on the bastion host
- For policy-merge mode: access to `k8s-bastion-policy`

### Prepare Bootstrap Inputs

Before running bootstrap or reconcile workflows:

```bash
./download.sh
```

Make sure these inputs are ready:

- `tools/` contains the artifacts used by `bastion-install-tools`
- `kubeconfigs/k8s-admin.kubeconfig` contains a real cluster-admin kubeconfig template
- `cluster.caFile` in the rendered policy points to a readable CA file on the bastion host

### Required Operator Scheduling

This repository does not install a service, cron job, or systemd timer for CSR processing.

- Run `bastion-csr-approver` periodically so user renewals can complete
- Run `bastion-csr-cleanup` periodically to remove old issued CSRs

## Architecture And Modes

The toolkit has a two-phase architecture:

1. **Machine Phase** (`bastion-bootstrap-machine`) installs containerd, tools, and bastion scripts
2. **Users Phase** (`bastion-bootstrap-users`) installs policy, groups, kubeconfigs, and the login profile

The users phase depends on `yq`, so the machine phase must run first.

### Mode 1: Simple Configuration (Non-Production)

- Edit `access-policy.yaml` directly in this repository
- Use direct machine and users bootstrap commands
- Best for labs, testing, and small self-contained deployments

### Mode 2: Policy Merge Configuration (Recommended For Production)

- Keep sensitive cluster data and environment overlays in `k8s-bastion-policy`
- Use `bastion-render-policy` or the wrapper scripts
- Best for production workflows and separated policy management

Policy merge uses three layers:

1. Public base: `access-policy.yaml`
2. Private base: `k8s-bastion-policy/base.yaml`
3. Environment overlay: `k8s-bastion-policy/envs/<env>.yaml`

Merge precedence is `Environment > Private > Public`.

When using policy-merge mode, never edit the rendered `access-policy.yaml` directly in this repository after rendering.

### Private Policy Repository Structure

The private repository should be organized like this:

```text
k8s-bastion-policy/
├── base.yaml
└── envs/
    ├── prod.yaml
    └── preprod.yaml
```

- `base.yaml` contains the private base policy, such as real cluster endpoint data and shared groups
- `envs/<env>.yaml` contains environment-specific overlays, such as user assignments and environment-only groups

Example split:

```yaml
# k8s-bastion-policy/base.yaml
cluster:
  name: production-cluster
  server: https://prod-k8s-api.internal:6443
  caFile: /etc/kubernetes/pki/ca.crt

groups:
  k8s-production-admins:
    namespaces:
      - all
```

```yaml
# k8s-bastion-policy/envs/prod.yaml
users:
  alice:
    ensureGroups:
      - k8s-production-admins
  bob:
    ensureGroups:
      - k8s-developers
      - k8s-production-admins
```

## Bastion Initialization And Reconcile

Choose one of these first-time bootstrap paths:

### Production Bootstrap (Recommended)

Use policy-merge mode when building a real bastion host for ongoing operations.

```bash
./download.sh
cd ../k8s-bastion-policy
vim base.yaml
vim envs/prod.yaml

cd ../k8s-bastion-init
sudo ./bastion_init.sh prod
```

This is the main operational path for production use.

Production reconcile after policy changes:

```bash
cd ../k8s-bastion-policy
vim envs/prod.yaml

cd ../k8s-bastion-init
sudo ./bastion_reconcile.sh prod
```

`bastion_reconcile.sh` runs these steps in order:

1. `bastion-bootstrap-machine --reconcile --source .`
2. `bastion-render-policy --policy-repo ../k8s-bastion-policy --env <env> --init-repo .`
3. `bastion-bootstrap-users --reconcile --source .`

### Simple Bootstrap (Non-Production)

Use simple mode for labs, testing, and standalone setups where editing a single policy file directly is acceptable.

```bash
./download.sh
vim access-policy.yaml
sudo ./sbin/bastion-bootstrap-machine --init --source .
sudo ./sbin/bastion-bootstrap-users --init --source .
```

Do not treat this as the preferred production workflow.

Simple-mode reconcile after policy changes:

```bash
vim access-policy.yaml
sudo ./sbin/bastion-bootstrap-machine --reconcile --source .
sudo ./sbin/bastion-bootstrap-users --reconcile --source .
```

This updates:

- `/etc/kubernetes/access-policy.yaml`
- Linux groups and supplementary group membership
- bootstrap kubeconfigs
- admin kubeconfigs for users in `k8s-admin`
- `/etc/profile.d/bastion-login.sh`

After private policy changes, use the wrapper or render policy first. Do not run `bastion-bootstrap-users` directly against stale rendered policy.

### Manual Policy-Render Flow

If you need to run Mode 2 manually without wrappers:

```bash
sudo ./sbin/bastion-bootstrap-machine --init --source .
sudo ./sbin/bastion-render-policy \
  --policy-repo ../k8s-bastion-policy \
  --env prod \
  --init-repo .
sudo ./sbin/bastion-bootstrap-users --init --source .
```

Do not run `bastion-render-policy` before the machine phase, because `yq` is installed during machine bootstrap.

## Script Reference

Use the shell scripts in this guide as the canonical operator interface.
The `Makefile` mirrors a few common commands for convenience, but does
not replace the direct script workflows.

### Wrapper Scripts

- **`bastion_init.sh`**: first-time Mode 2 initialization
- **`bastion_reconcile.sh`**: Mode 2 update workflow

These scripts assume:

- `./download.sh` has already populated `tools/`
- `../k8s-bastion-policy` exists for policy-merge mode
- `kubeconfigs/k8s-admin.kubeconfig` is present in this repository

### Core Bootstrap Scripts

- **`bastion-bootstrap-machine`**: installs runtime, tools, libraries, and scripts
- **`bastion-bootstrap-users`**: validates prerequisites, installs policy, applies user state, and verifies setup
- **`bastion-render-policy`**: merges public, private, and environment policy layers and records `.policy-env`

### Additional Admin Scripts

- **`bastion-bootstrap-user-groups`**: creates groups and updates supplementary group membership from policy
- **`bastion-bootstrap-kubeconfig`**: creates `~/.kube/bootstrap` for users defined in policy
- **`bastion-bootstrap-admin-kubeconfig`**: installs admin kubeconfigs for users in the `k8s-admin` policy group
- **`bastion-disable-user`**: removes bastion-managed groups and disables active kubeconfigs for a target user
- **`bastion-kubeconfig-expiry`**: checks certificate expiry in kubeconfigs
- **`bastion-audit-kube-dirs`**: audits per-user `.kube` directories
- **`bastion-login-profile`**: generates the login banner and tool summary

### User Script

- **`bastion-kube-renew`**: renews a user certificate based on current Unix group membership

Requirements:

- `~/.kube/bootstrap` must exist
- the user must belong to at least one `k8s-*` group, or whatever `csr.groupPrefix` is configured to match
- the policy must contain valid `csr.*`, `cluster.name`, `cluster.server`, and `cluster.caFile` values
- users should start a new login session after group changes before running `bastion-kube-renew`

## Operator Inputs

- `access-policy.yaml` - source policy in Mode 1, or rendered output in Mode 2
- `kubeconfigs/k8s-admin.kubeconfig` - admin kubeconfig template copied to `k8s-admin` users
- `tools/` - downloaded tool artifacts consumed by `bastion-install-tools`
- `download.conf` - tool version and URL configuration for `download.sh`
- `bastion_init.sh` and `bastion_reconcile.sh` - Mode 2 wrapper entry points

## User Login Notice

The bastion displays login information via `/etc/profile.d/bastion-login.sh`.

On a fresh interactive SSH login, users see:

- Kubernetes access status and certificate expiry
- Available tools based on user and admin group membership
- `k8s-*` groups the user belongs to

Notes:

- The message is shown only for interactive shells over SSH
- Users must re-login to pick up group changes, or manually source `/etc/profile.d/bastion-login.sh`

## Verification

```bash
kubectl cluster-info
sudo bastion-kubeconfig-expiry
```

For end-user renewal and access behavior, see `docs/k8s-users-management.md`.

## Operator Runbook

### First Bootstrap

- run `./download.sh` or `make download`
- verify `kubeconfigs/k8s-admin.kubeconfig` and policy inputs
- use Mode 1 direct bootstrap commands or Mode 2 `bastion_init.sh`
- verify `kubectl cluster-info` and `sudo bastion-kubeconfig-expiry`

### After Policy Changes

- **Mode 1**
  - edit `access-policy.yaml`
  - run `sudo ./sbin/bastion-bootstrap-machine --reconcile --source .`
  - run `sudo ./sbin/bastion-bootstrap-users --reconcile --source .`
- **Mode 2**
  - edit `k8s-bastion-policy/base.yaml` or `k8s-bastion-policy/envs/<env>.yaml`
  - run `sudo ./bastion_reconcile.sh <env>` or `make reconcile ENV=<env>`

### New User Onboarding

- create the Linux user on the bastion host
- add the user and `ensureGroups` mapping in policy
- reconcile the bastion
- run `sudo bastion-bootstrap-kubeconfig --user <user>`
- ask the user to start a new login session and run `bastion-kube-renew`

### Disable Or Reduce User Access

- remove or update the user entry in policy first
- reconcile the bastion so installed policy matches the intended state
- run `sudo bastion-disable-user --user <user>`
- verify the user no longer has bastion-managed `k8s-*` groups
- verify `~/.kube/bootstrap` and `~/.kube/config` are no longer active for that user

### Group Membership Changes

- update the policy mapping
- reconcile the bastion
- ask affected users to log out and back in
- ask affected users to run `bastion-kube-renew`

### Tool Updates

- edit `download.conf`
- run `./download.sh` or `make download`
- run the machine reconcile step to install updated artifacts

### Environment Verification

- inspect `.policy-env` to confirm the last rendered environment in Mode 2
- verify `/etc/kubernetes/access-policy.yaml` matches the intended state
- verify `/etc/profile.d/bastion-login.sh` exists and has been regenerated when needed

## Maintenance Cadence

### Event-Driven Tasks

- reconcile after policy changes
- bootstrap a kubeconfig after adding a new user
- ask users to renew after group membership changes
- refresh tools after changing `download.conf`

### Periodic Tasks

- run `bastion-csr-approver` on a schedule
- run `bastion-csr-cleanup` on a schedule
- review certificate expiry with `sudo bastion-kubeconfig-expiry`

### Manual Verification

- confirm cluster connectivity with `kubectl cluster-info`
- inspect user group state with `id -nG <user>`
- inspect kube directories with `sudo bastion-audit-kube-dirs`
- inspect the active rendered policy and `.policy-env` when troubleshooting Mode 2

## Troubleshooting

### Policy Rendering Issues

**Error: Policy repository not found at: ../k8s-bastion-policy**
- Ensure `k8s-bastion-policy` exists one directory above `k8s-bastion-init`
- Check the directory layout used in the canonical workflows

**Error: Missing required environment argument**
- `bastion_init.sh` and `bastion_reconcile.sh` require an environment argument
- Example: `sudo ./bastion_init.sh prod`

**Policy changes not applied**
- Ensure machine setup completed successfully and `yq` is installed
- Run `bastion_init.sh` or `bastion_reconcile.sh` so the order is machine -> render -> users
- Do not run `bastion-bootstrap-users` directly after changing private policy without rendering first
- Check `.policy-env` to confirm the last rendered environment

### General Issues

- If `echo $KUBECONFIG` is empty, ensure the user is in the expected Unix group, `/etc/profile.d/bastion-login.sh` exists, and the user started a new login shell
- If `kubectl` talks to `localhost:6443`, the kubeconfig `clusters[].cluster.server` value is wrong; update it to the real API endpoint
