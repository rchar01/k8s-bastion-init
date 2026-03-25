# Bastion Bootstrap RBAC Implementation Guide

## Purpose

This document is the canonical Kubernetes-side implementation guide for bastion user bootstrap using short-lived bootstrap tokens and short-lived client certificates.

It defines what is implemented in this repository, what the external bastion project must rely on, and how to validate the full RBAC contract.

## Scope

In scope for this guide:

- namespace and ServiceAccount primitives for bastion controllers
- RBAC capabilities and bindings for bootstrap request, approval, signing, cleanup, and token issuance
- deployment order, guardrails, and verification checks
- stable handoff contract for external bastion automation

Out of scope for this guide:

- OIDC/SPIFFE/external CA integrations
- bastion host script internals and UX
- controller runtime implementation details

## Security Model

Credential classes:

- bootstrap credential: short-lived bootstrap token (enrollment/recovery only)
- operating credential: short-lived X.509 client certificate (day-to-day kubectl + in-band renewal)

Required invariants:

- bootstrap identities can submit CSR but cannot perform ordinary cluster operations
- bootstrap identities cannot list/watch all CSRs
- approval and signing remain separate capabilities
- signer is constrained to platform signer name
- CSR cleanup is explicit and automated

## Implemented Kubernetes Components

### Chart: `platform/bastion-system`

Owns foundational identities for bastion CSR controllers:

- namespace: `bastion-system`
- ServiceAccounts:
  - `bastion-csr-approver`
  - `bastion-csr-signer`
  - `bastion-csr-cleanup`
  - `bastion-token-issuer`

Source paths:

- `helm-charts/platform/bastion-system`
- `platform-deployments/platform/bastion-system`

### Chart: `platform/rbac-policy`

Owns CSR bootstrap capabilities and bindings:

- `capability-k8s-csr-bootstrap-request`
  - CSR verbs: `create`, `get`
- `capability-k8s-csr-approve-platform-client`
  - CSR read: `get`, `list`, `watch`
  - approval subresource: `update`, `patch`
  - signer authorization: `approve` on `signers` resource name `platform.example.io/client`
- `capability-k8s-csr-sign-platform-client`
  - CSR read: `get`, `list`, `watch`
  - status subresource: `update`, `patch`
  - signer authorization: `sign` on `signers` resource name `platform.example.io/client`
- `capability-k8s-csr-cleanup`
  - CSR verbs: `get`, `list`, `watch`, `delete`
- `capability-k8s-bootstrap-token-issuer`
  - secret verbs in `kube-system`: `create`, `get`, `list`, `watch`, `update`, `patch`, `delete`

Source paths:

- `helm-charts/platform/rbac-policy`
- `platform-deployments/platform/rbac-policy`

## Binding Model

Cluster bindings:

- bootstrap requester: `Group` `system:bootstrappers:platform-users` -> `capability-k8s-csr-bootstrap-request`
- approver controller: `ServiceAccount` `bastion-csr-approver` in `bastion-system` -> `capability-k8s-csr-approve-platform-client`
- signer controller: `ServiceAccount` `bastion-csr-signer` in `bastion-system` -> `capability-k8s-csr-sign-platform-client`
- cleanup controller: `ServiceAccount` `bastion-csr-cleanup` in `bastion-system` -> `capability-k8s-csr-cleanup`

Namespace binding:

- token issuer: `ServiceAccount` `bastion-token-issuer` in `bastion-system` -> `capability-k8s-bootstrap-token-issuer` in namespace `kube-system`

## Signer and CSR Contract

Platform signer name:

- `platform.example.io/client`

Expected CSR shape from bastion flow:

- `apiVersion: certificates.k8s.io/v1`
- `kind: CertificateSigningRequest`
- `spec.signerName: platform.example.io/client`
- `spec.usages: ["client auth"]`
- `spec.expirationSeconds` set within policy

Approval and issuance policy is enforced by approver/signer controllers; RBAC here provides the minimum permission envelope.

## Deployment Order

1. Install `platform/bastion-system`.
2. Install `platform/rbac-policy`.
3. Deploy approver/signer/cleanup/issuer workloads using the created ServiceAccounts.
4. Enable strict RBAC guardrails for live validation when desired.

## Guardrails

`platform/rbac-policy` includes optional strict guardrails for ServiceAccount subjects:

- `validation.mode=apiOnly` (default): CI/offline-safe, no cluster existence checks
- `validation.mode=strict`: validates each referenced ServiceAccount subject namespace and ServiceAccount exists
- `validation.requireServiceAccountSubjects=true`: enables strict ServiceAccount checks

Use strict mode in live installs/upgrades after `platform/bastion-system` is deployed.

## Verification Commands

Bootstrap requester identity checks:

```bash
kubectl --kubeconfig "$HOME/.kube/bootstrap" auth can-i create certificatesigningrequests.certificates.k8s.io
kubectl --kubeconfig "$HOME/.kube/bootstrap" auth can-i get certificatesigningrequests.certificates.k8s.io
kubectl --kubeconfig "$HOME/.kube/bootstrap" auth can-i list certificatesigningrequests.certificates.k8s.io
```

Expected:

- `create`: yes
- `get`: yes
- `list`: no

Controller identity checks:

```bash
kubectl --as=system:serviceaccount:bastion-system:bastion-csr-approver auth can-i update certificatesigningrequests.certificates.k8s.io/approval
kubectl --as=system:serviceaccount:bastion-system:bastion-csr-signer auth can-i update certificatesigningrequests.certificates.k8s.io/status
kubectl --as=system:serviceaccount:bastion-system:bastion-csr-cleanup auth can-i delete certificatesigningrequests.certificates.k8s.io
kubectl --as=system:serviceaccount:bastion-system:bastion-token-issuer -n kube-system auth can-i create secrets
```

## Handoff Contract for External Bastion Project

Treat the following values as stable integration inputs:

- bootstrap auth group: `system:bootstrappers:platform-users`
- signer name: `platform.example.io/client`
- controller namespace: `bastion-system`
- controller ServiceAccounts:
  - `bastion-csr-approver`
  - `bastion-csr-signer`
  - `bastion-csr-cleanup`
  - `bastion-token-issuer`
- issuer namespace for bootstrap-token Secrets: `kube-system`

If any of these values change, update `platform-deployments/platform/rbac-policy` and bastion-side configuration in lockstep.

## Related Documentation

- `helm-charts/platform/bastion-system/README.md`
- `helm-charts/platform/rbac-policy/README.md`
- `helm-charts/docs/validation-guardrails.md`
