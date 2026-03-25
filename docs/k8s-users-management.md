# Kubernetes User Access Management

This guide explains how user access works on the bastion host.

For operator installation, bootstrap, and reconcile workflows, see `docs/bastion-bootstrap.md`.
For the canonical Kubernetes RBAC/bootstrap contract, see `docs/bastion-bootstrap-components.md`.

## Overview

Access is based on:

- Linux groups on the bastion host (typically `k8s-*` groups)
- Short-lived client certificates (policy-driven, bounded to 1h..24h)
- Kubernetes RBAC bindings to certificate groups (`O=` fields)

Users do not get long-lived static kubeconfig credentials.

## Access Flow

1. User starts an interactive bastion login session.
2. `bastion-login-bootstrap` checks local credential state (`missing|valid|renewable|expired|broken`).
3. For `missing|expired|broken`, root helper obtains short-lived bootstrap kubeconfig from in-cluster issuer and writes `~/.kube/bootstrap`.
4. `bastion-enroll-cert` submits CSR with signer `platform.example.io/client`, waits for signing, and atomically writes `~/.kube/user.crt`, `~/.kube/user.key`, and `~/.kube/config`.
5. Bootstrap kubeconfig is removed and token revoke is attempted best-effort.
6. Background renewal timer runs every 30 minutes; users in renew window are renewed automatically with current valid cert.

## Core Files

- `/etc/bastion/access-policy.yaml`: policy source on the bastion host
- `~/.kube/bootstrap`: temporary bootstrap kubeconfig used only for enrollment/recovery
- `~/.kube/config`: active user kubeconfig (file-based cert references)
- `~/.kube/user.crt`: user client certificate
- `~/.kube/user.key`: user private key
- `~/.cache/bastion-bootstrap/state.json`: per-user bootstrap/renew state
- `~/.cache/bastion-bootstrap/lock`: per-user enrollment/renew lock

Token issuance dependency:

- in-cluster issuer service reachable via Kubernetes service proxy at
  `/api/v1/namespaces/bastion-system/services/http:bastion-token-issuer/proxy/v1/bootstrap-token/issue`
- bootstrap tokens are short-lived enrollment credentials and are revoked after successful renewal

## Main Commands

| Command | Purpose |
| --- | --- |
| `sudo bastion-bootstrap-token-issue --user <user> --json` | Issue short-lived bootstrap token via issuer workload |
| `sudo bastion-bootstrap-kubeconfig --user <user>` | Create bootstrap kubeconfig for one user (token-backed) |
| `sudo bastion-bootstrap-kubeconfig --all` | Create bootstrap kubeconfigs for all policy users present on host |
| `sudo bastion-bootstrap-token-revoke --token-id <id>` | Revoke bootstrap token via issuer workload |
| `bastion-login-bootstrap --quiet` | Login-triggered auto-bootstrap orchestration (best-effort) |
| `bastion-enroll-cert --reason login-recovery` | Bootstrap-based enrollment using temporary `~/.kube/bootstrap` |
| `bastion-kube-renew` | User self-service certificate renewal |
| `bastion-renew-cert --quiet` | Non-interactive renewal engine (used by timer) |
| `sudo bastion-manage-cert-renew-timer --install` | Install transparent cert renewal timer |
| `sudo bastion-csr-approver` | Validate and approve bastion CSRs |
| `sudo bastion-csr-cleanup` | Delete old bastion CSRs |
| `bastion-kubeconfig-expiry` | Show certificate expiry summary |

## Admin Bootstrap

Bootstrap kubeconfig creation is policy-driven: the target user must exist in `users:` in the access policy, and the user must also exist on the Linux host.

This guide focuses on the access lifecycle after the bastion is installed. For full host bootstrap procedures, use `docs/bastion-bootstrap.md`.

Run as root to pre-bootstrap specific users (optional; login auto-bootstrap can also recover on demand):

```bash
sudo bastion-bootstrap-kubeconfig --user alice
```

This installs `/home/alice/.kube/bootstrap`.

To bootstrap all users from policy:

```bash
sudo bastion-bootstrap-kubeconfig --all
```

Users not present on the Linux host are skipped.

## User Renewal

Run as regular user (not root):

```bash
bastion-kube-renew
```

`bastion-kube-renew` (wrapper for `bastion-renew-cert`):

- reads policy for signer, TTL, and group prefix
- derives requested groups from the user's current host groups
- submits a labeled CSR (`bastion-access=true`)
- waits for approval and atomically rotates cert/key/kubeconfig files

Transparent renewal:

- `bastion-cert-renew.timer` runs every 30 minutes with jitter
- renewal occurs only when remaining cert lifetime is below 2 hours
- renewal is fully user-context and does not call issuer
- expired certs do not renew and are recovered through next login auto-bootstrap

Important:

- renewal approval is based on current Unix group membership, not a second lookup of `users.<name>` in policy
- users should log out and back in after group changes to trigger login checks and updated group state
- `cluster.caFile` in policy must exist and be readable on the bastion host (recommended default: `/etc/bastion/ca.crt`)

## Approver Validation Behavior

`bastion-csr-approver` currently validates:

- CSR has label `bastion-access=true`
- signer matches configured policy signer
- CSR usages are `client auth`
- CSR requested `expirationSeconds` is within allowed bounds (1h..24h)
- requester must be either in bootstrap auth group `system:bootstrappers:platform-users` or match CN identity fallback
- subject CN resolves to an existing host user
- all requested groups use the configured group prefix
- all requested groups are present in host group membership for that user

It does not re-check whether the user appears under `.users` in policy or whether each requested group is defined under `.groups`.

If checks pass, CSR is approved.

Because it is a one-shot command, bastion bootstrap installs a systemd timer for it by default.

If you need to remove default CSR scheduling units:

```bash
sudo bastion-manage-csr-timers --remove
```

## Cleanup Behavior

`bastion-csr-cleanup` removes only bastion-managed CSRs that are:

- labeled `bastion-access=true`
- signed with the configured policy signer
- already issued (`status.certificate` present)
- older than retention window (default: 14 days)

Example:

```bash
sudo bastion-csr-cleanup --retention-days 7
```

## Typical Operations

Add access:

1. Add user to Linux host.
2. Add or update user/group mapping in policy.
3. Reconcile users/groups from admin workflow.
4. Optional pre-bootstrap: `sudo bastion-bootstrap-kubeconfig --user <user>`.
5. User starts a new interactive login session (auto-bootstrap/enroll runs best-effort).
6. Validate resulting `~/.kube/config` and access.

Remove access:

1. Remove or update the user entry in policy.
2. Reconcile bastion policy from the admin workflow.
3. Run `sudo bastion-disable-user --user <user>` on the bastion host.
4. Verify the user no longer has `k8s-*` groups and no active kubeconfig files.

### Deactivate Or Reduce Access

Use this flow when a user should lose bastion-managed Kubernetes access:

1. Remove the user from policy, or remove the relevant `ensureGroups` entries.
2. Reconcile the bastion so the active installed policy matches your intended state.
3. Run:

```bash
sudo bastion-disable-user --user <user>
```

By default this command:

- removes bastion-managed `k8s-*` groups from the target user on the host
- disables `~/.kube/bootstrap`
- disables `~/.kube/config`

Important:

- remove the user from policy first, otherwise a later reconcile can add groups back
- for former admins, removing Unix groups alone is not enough; the active kubeconfig must also be removed or disabled
- existing short-lived certificates copied elsewhere remain valid until their TTL expires

## Troubleshooting

### User cannot access cluster

Check in order:

1. Host groups:

```bash
id -nG <user>
```

2. Bootstrap config exists:

```bash
ls -l /home/<user>/.kube/bootstrap
```

3. CSR status:

```bash
kubectl get csr
```

4. Approver logs/output (run manually):

```bash
sudo bastion-csr-approver
```

### `bastion-kube-renew` says no matching groups

- confirm user is in at least one group with policy prefix (default `k8s-`)
- confirm policy `csr.groupPrefix` matches your group naming convention
- if group membership was changed recently, log out and back in before retrying

### Certificate issued but RBAC denied

- verify RoleBinding/ClusterRoleBinding subjects match certificate groups
- verify namespace scope and verbs in RBAC rules
