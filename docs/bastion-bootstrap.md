# Bastion Host Toolkit Bootstrap Guide

This guide covers operator installation, bootstrap, reconcile, and policy-rendering workflows for the Kubernetes Bastion Host Toolkit.

For a high-level view of the bastion access model and certificate flow, see `docs/architecture.md`.
For the canonical Kubernetes-side bootstrap/RBAC contract, see `docs/bastion-bootstrap-components.md`.

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

Recommended CA file location on bastion hosts:

- Use `/etc/kubernetes/ca.crt` as the default `cluster.caFile` path
- Avoid `/etc/kubernetes/pki/ca.crt` on bastion hosts running `--init`, because node cleanup can remove `/etc/kubernetes/pki`

### Required Operator Scheduling

Bootstrap and reconcile install and enable systemd timers for CSR processing by default.

- `bastion-csr-approver.timer`: `OnBootSec=1min`, `OnUnitActiveSec=2min`
- `bastion-csr-cleanup.timer`: `OnBootSec=10min`, `OnUnitActiveSec=6h`

To remove these timers, run:

```bash
sudo bastion-manage-csr-timers --remove
```

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
  caFile: /etc/kubernetes/ca.crt

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

Example non-production policy (for local testing only):

```yaml
# access-policy.yaml
apiVersion: bastion.access/v1
csr:
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 604800
  groupPrefix: "k8s-"

cluster:
  name: test-cluster
  server: https://test-api-server:6443
  caFile: /etc/kubernetes/ca.crt

groups:
  k8s-group1:
    namespaces:
      - namespace-group1a
      - namespace-group1b
  k8s-group2:
    namespaces:
      - namespace-group2
  k8s-test-group:
    namespaces:
      - test-namespace
      - default

users:
  user1:
    ensureGroups:
      - k8s-group1
  user2:
    ensureGroups:
      - k8s-group1
      - k8s-group2
  alice:
    ensureGroups:
      - k8s-test-group
  bob:
    ensureGroups:
      - k8s-test-group
  charlie:
    ensureGroups:
      - k8s-test-group
```

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

Security defaults applied during machine bootstrap:

- admin scripts in `/usr/local/sbin` are installed with mode `0750`
- `/etc/sudoers.d/bastion-path` is installed so `sudo` can resolve `/usr/local/sbin` commands

During users bootstrap, the admin kubeconfig template is also installed as:

- `/etc/kubernetes/admin.kubeconfig` (used by CSR approver/cleanup systemd services)

### Additional Admin Scripts

- **`bastion-bootstrap-user-groups`**: creates groups and updates supplementary group membership from policy
- **`bastion-bootstrap-kubeconfig`**: creates `~/.kube/bootstrap` for users defined in policy
- **`bastion-bootstrap-token-issue`**: requests short-lived bootstrap token from in-cluster issuer
- **`bastion-bootstrap-token-revoke`**: revokes bootstrap token via in-cluster issuer
- **`bastion-bootstrap-admin-kubeconfig`**: installs admin kubeconfigs for users in the `k8s-admin` policy group
- **`bastion-disable-user`**: removes bastion-managed groups and disables active kubeconfigs for a target user
- **`bastion-audit-kube-dirs`**: audits per-user `.kube` directories
- **`bastion-login-profile`**: generates the login banner and tool summary
- **`bastion-manage-csr-timers`**: installs/removes CSR approver and cleanup systemd timers
- **`bastion-cluster-probe`**: writes compact cluster status cache for login banner
- **`bastion-manage-cluster-status-timer`**: installs/removes cluster status probe timer

CSR timer services run `kubectl` with:

- `KUBECONFIG=/etc/kubernetes/admin.kubeconfig`

### User Script

- **`bastion-kube-renew`**: renews a user certificate based on current Unix group membership
- **`bastion-kubeconfig-expiry`**: checks certificate expiry in kubeconfigs

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

- Bastion host identity (hostname and bastion version)
- User kubeconfig status (path/context/namespace and cert lifetime state)
- Cluster status from cache (`cluster`, `API server`, `health`) plus cache timestamp/age
- Consolidated notices in one place (cert renewal, kubeconfig/bootstrap state, context mismatch, prod/preprod safety)
- Compact tool lines (`Tools:` and `Bastion:`)

Notes:

- The message is shown only for interactive shells over SSH
- Users must re-login to pick up group changes, or manually source `/etc/profile.d/bastion-login.sh`

### Cluster Status Cache

Cluster health shown in the login banner is read from `/run/bastion-cluster-status.json`.
The cache is produced by root-owned systemd units:

- `bastion-cluster-status.service`
- `bastion-cluster-status.timer` (default cadence: every 30s)

This avoids exposing `/etc/kubernetes/admin.kubeconfig` to regular users while keeping banner probes fast.

Useful commands:

```bash
sudo systemctl status bastion-cluster-status.timer
sudo systemctl start bastion-cluster-status.service
sudo cat /run/bastion-cluster-status.json | jq .
```

### Notice Severity and Meanings

The login banner prints notices as plain lines without a header. Notices are capped to 4 lines; if more exist, the banner prints `INFO: Additional notices: <N>`.

Certificate state thresholds:

- `OK`: more than 3 days remaining
- `WARN`: 1-3 days remaining
- `CRIT`: less than 24 hours remaining
- `EXPIRED`: certificate already expired

Notice catalog:

| Severity | Notice text | Meaning | Recommended action |
| --- | --- | --- | --- |
| `CRIT` | `Client cert expired. Run: bastion-kube-renew` | User cert is no longer valid | Run `bastion-kube-renew` |
| `CRIT` | `Client cert expires in <Nh>. Run: bastion-kube-renew` | User cert is below 24h lifetime | Run `bastion-kube-renew` now |
| `WARN` | `Client cert expires in <Nd>. Run: bastion-kube-renew` | User cert has 1-3 days left | Renew soon with `bastion-kube-renew` |
| `WARN` | `No active kubeconfig. Bootstrap found - run: bastion-kube-renew` | `~/.kube/config` missing, bootstrap exists | Run `bastion-kube-renew` |
| `CRIT` | `No kubeconfig or bootstrap. Ask admin: sudo bastion-bootstrap-kubeconfig --user <user>` | User cannot self-recover | Admin runs `sudo bastion-bootstrap-kubeconfig --user <user>` |
| `CRIT` | `User kubeconfig is invalid. Run: bastion-kube-renew` | Kubeconfig exists but is malformed/unreadable | Run `bastion-kube-renew` |
| `WARN` | `No user client certificate. Run: bastion-kube-renew` | Kubeconfig has no usable client cert | Run `bastion-kube-renew` |
| `CRIT` | `Admin probe kubeconfig missing: /etc/kubernetes/admin.kubeconfig` | Cluster health probe cannot run | Restore `/etc/kubernetes/admin.kubeconfig` |
| `CRIT` | `Cluster API is unreachable` | API `/readyz` probe failed | Check API endpoint/network/auth from bastion |
| `WARN` | `Cluster has NotReady nodes (<ready>/<total> Ready)` | API is up but node readiness degraded | Investigate node readiness in cluster |
| `WARN` | `User context cluster differs from admin probe cluster` | User kubeconfig cluster differs from admin probe cluster | Verify target cluster/context before changes |
| `WARN` | `PRODUCTION cluster - actions are audited` | Cluster name matches `prod|live|main` | Apply extra change safety controls |
| `INFO` | `PREPROD cluster - validate target before changes` | Cluster name matches `preprod|stage|staging` | Verify target and intent before changes |

## Verification

```bash
kubectl cluster-info
bastion-kubeconfig-expiry
```

For end-user renewal and access behavior, see `docs/k8s-users-management.md`.

## Production Rollout Checklist

Use this checklist before and immediately after the first production bootstrap.

### Preflight

- verify `k8s-bastion-policy/base.yaml` and `k8s-bastion-policy/envs/<env>.yaml` contain the intended production users and groups
- verify `cluster.server` points to the real Kubernetes API endpoint
- verify `cluster.caFile` exists on the bastion host and matches the target cluster CA
- prefer `/etc/kubernetes/ca.crt` for `cluster.caFile` on bastion hosts
- verify `kubeconfigs/k8s-admin.kubeconfig` is the intended admin template for the target cluster
- review `k8s-admin` membership carefully before the first init
- run `./download.sh` or `make download`

### Initial Production Bootstrap

```bash
sudo ./bastion_init.sh <env>
```

### Immediate Post-Init Checks

- run `kubectl cluster-info`
- run `bastion-kubeconfig-expiry`
- verify `/etc/kubernetes/access-policy.yaml` matches the rendered production policy
- verify `/etc/profile.d/bastion-login.sh` exists
- verify at least one intended admin received the expected kubeconfig

## Post-Init Verification Checklist

Use these checks before declaring the bastion ready for general use.

### Admin Verification

- SSH to the bastion as an intended admin user
- verify `kubectl cluster-info` works from that account
- verify the admin sees the expected `k8s-*` groups and tool list on login

### Regular User Verification

- bootstrap a test user with `sudo bastion-bootstrap-kubeconfig --user <user>` if needed
- SSH as that user and run `bastion-kube-renew`
- verify the resulting `~/.kube/config` can reach the cluster with the expected permissions

### Deactivation Verification

- remove a test user from policy or reduce their groups
- reconcile the bastion
- run `sudo bastion-disable-user --user <user>`
- verify `id -nG <user>` no longer contains bastion-managed `k8s-*` groups
- verify `~/.kube/bootstrap` and `~/.kube/config` are no longer active for that user

## Scheduling Examples

Default timers are installed automatically during bootstrap and reconcile.

To reinstall defaults manually:

```bash
sudo bastion-manage-csr-timers --install
```

To remove all CSR timer units:

```bash
sudo bastion-manage-csr-timers --remove
```

Use custom schedules only when you need non-default cadence.

### Cron Example

```cron
*/2 * * * * root /usr/local/sbin/bastion-csr-approver >/var/log/bastion-csr-approver.log 2>&1
15 */6 * * * root /usr/local/sbin/bastion-csr-cleanup >/var/log/bastion-csr-cleanup.log 2>&1
```

### systemd Timer Example

Approver service:

```ini
[Unit]
Description=Bastion CSR approver

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bastion-csr-approver
```

Approver timer:

```ini
[Unit]
Description=Run bastion CSR approver periodically

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
Unit=bastion-csr-approver.service

[Install]
WantedBy=timers.target
```

Cleanup service:

```ini
[Unit]
Description=Bastion CSR cleanup

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bastion-csr-cleanup
```

Cleanup timer:

```ini
[Unit]
Description=Run bastion CSR cleanup periodically

[Timer]
OnBootSec=10min
OnUnitActiveSec=6h
Unit=bastion-csr-cleanup.service

[Install]
WantedBy=timers.target
```

## Operator Runbook

### First Bootstrap

- run `./download.sh` or `make download`
- verify `kubeconfigs/k8s-admin.kubeconfig` and policy inputs
- use Mode 1 direct bootstrap commands or Mode 2 `bastion_init.sh`
- verify `kubectl cluster-info` and `bastion-kubeconfig-expiry`

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

- verify `bastion-csr-approver.timer` is enabled and active
- verify `bastion-csr-cleanup.timer` is enabled and active
- review certificate expiry with `bastion-kubeconfig-expiry`

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
- If `sudo bastion-<command>` says `command not found`, verify `/etc/sudoers.d/bastion-path` exists and `sudo -V` shows `/usr/local/sbin` in `secure_path`
