# Bastion Toolkit Architecture

This document gives a high-level view of how the bastion host, host users,
policy-driven groups, and Kubernetes certificate workflows fit together.

## High-Level Diagram

```text
┌─────────────────────────────────────────────────────────────┐
│                         Bastion Host                        │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Linux Users  │  │   k8s-*      │  │ Certificate  │       │
│  │ & Groups     │──│   Groups     │──│ Management   │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│         │                   │                   │           │
│         └───────────────────┴───────────────────┘           │
│                             │                               │
│                    ┌────────▼───────────┐                   │
│                    │ Kubernetes Cluster │                   │
│                    │      (CSR API)     │                   │
│                    └────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

## Main Components

- **Linux users and groups** - host accounts are the local identity source
- **`k8s-*` groups** - Unix groups mapped from policy and used as Kubernetes
  group claims during renewal
- **Certificate management** - bootstrap kubeconfigs, CSR submission, approval,
  cleanup, and short-lived kubeconfig generation
- **Systemd timers** - default scheduling for CSR approver, cleanup, and transparent cert renewal
- **Kubernetes CSR API** - signs client certificates after bastion-side checks

## Control Flow

1. Admin bootstraps the bastion host.
2. Policy defines users, groups, CSR settings, and cluster connection data.
3. Bastion scripts create or update host group membership from policy.
4. Users receive bootstrap kubeconfigs or admin kubeconfigs, depending on role.
5. Login auto-bootstrap (internal runtime helper) recovers missing/expired/broken credentials through local root daemon `bastion-bootstrapd`; renewal timer and `bastion-renew-cert` handle in-band renewals.
6. `bastion-csr-approver` validates signer, CN, requested groups, and current
   host group membership.
7. Kubernetes issues a short-lived client certificate.
8. The user kubeconfig is rebuilt with the new client certificate.

## Access Model

- **Regular users** get bootstrap kubeconfigs and renew access through CSR flow
- **Admin users** receive the shared admin kubeconfig when they are in
  `k8s-admin`
- **Current Unix group membership** is the source of truth for renewal
- **Policy** is the source of truth for bootstrap intent and group assignment

## Day-2 Changes

- **Grant access** - add or update the user in policy, reconcile, bootstrap as
  needed, and renew
- **Reduce access** - update policy, reconcile, and have the user renew after
  re-login
- **Disable access** - remove the user from policy, then run
  `bastion-disable-user --user <user>` to remove bastion-managed groups and
  disable active kubeconfigs on the host

## Related Docs

- `README.md` - project overview and mode selection
- `docs/bastion-bootstrap.md` - bootstrap, reconcile, and operator workflows
- `docs/k8s-users-management.md` - user renewal, approval, cleanup, and disable
  workflows
