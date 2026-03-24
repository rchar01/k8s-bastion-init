# Kubernetes User Access Management

This guide explains how user access works on the bastion host.

For operator installation, bootstrap, and reconcile workflows, see `docs/bastion-bootstrap.md`.

## Overview

Access is based on:

- Linux groups on the bastion host (typically `k8s-*` groups)
- Short-lived client certificates (default 7 days)
- Kubernetes RBAC bindings to certificate groups (`O=` fields)

Users do not get long-lived static kubeconfig credentials.

## Access Flow

1. Admin bootstraps a user kubeconfig (`~/.kube/bootstrap`).
2. User runs `bastion-kube-renew`.
3. User CSR is submitted to Kubernetes.
4. `bastion-csr-approver` runs via systemd timer and approves valid CSRs.
5. User receives a signed certificate and `~/.kube/config` is rebuilt.
6. Access expires automatically when the certificate expires.

## Core Files

- `/etc/kubernetes/access-policy.yaml`: policy source on the bastion host
- `~/.kube/bootstrap`: limited kubeconfig used to submit CSRs
- `~/.kube/config`: active user kubeconfig with signed cert

## Main Commands

| Command | Purpose |
| --- | --- |
| `sudo bastion-bootstrap-kubeconfig --user <user>` | Create bootstrap kubeconfig for one user |
| `sudo bastion-bootstrap-kubeconfig --all` | Create bootstrap kubeconfigs for all policy users present on host |
| `bastion-kube-renew` | User self-service certificate renewal |
| `sudo bastion-csr-approver` | Validate and approve bastion CSRs |
| `sudo bastion-csr-cleanup` | Delete old bastion CSRs |
| `bastion-kubeconfig-expiry` | Show certificate expiry summary |

## Admin Bootstrap

Bootstrap kubeconfig creation is policy-driven: the target user must exist in `users:` in the access policy, and the user must also exist on the Linux host.

This guide focuses on the access lifecycle after the bastion is installed. For full host bootstrap procedures, use `docs/bastion-bootstrap.md`.

Run as root:

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

`bastion-kube-renew`:

- reads the policy for CSR settings (`signerName`, TTL, group prefix)
- derives requested groups from the user's current host groups
- submits a labeled CSR (`bastion-access=true`)
- waits for approval and rebuilds `~/.kube/config`

If `~/.kube/config` exists, it is backed up to `~/.kube/config.bak.<timestamp>`.

Important:

- renewal approval is based on current Unix group membership, not a second lookup of `users.<name>` in policy
- users should log out and back in after group changes before running `bastion-kube-renew`
- `cluster.caFile` in policy must exist and be readable on the bastion host (recommended default: `/etc/kubernetes/ca.crt`)

## Approver Validation Behavior

`bastion-csr-approver` currently validates:

- CSR has label `bastion-access=true`
- signer matches `csr.signerName` from policy
- CSR usages are `client auth`
- subject CN equals CSR username
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
4. Bootstrap kubeconfig (`sudo bastion-bootstrap-kubeconfig --user <user>`).
5. User starts a new login session if group membership changed.
6. User runs `bastion-kube-renew`.

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
