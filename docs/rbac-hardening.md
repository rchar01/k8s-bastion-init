# RBAC Hardening Guide

This guide captures the RBAC and controller hardening rules relevant to this bastion CSR bootstrap architecture.

## Scope

- bootstrap token issuer permissions
- CSR approver/signer policy enforcement
- CSR cleanup safety boundaries
- bootstrap token and issuer logic constraints

## Issuer RBAC Model

Required model:

- `Role` `capability-k8s-bootstrap-token-issuer` in namespace `kube-system`
- verbs on Secrets: `create`, `get`, `delete`
- `RoleBinding` in `kube-system` to `ServiceAccount` `bastion-system/bastion-token-issuer`

Do not grant cluster-wide Secret access for issuer behavior.

Notes:

- Avoid `list`/`watch` on Secrets unless strictly required.
- Keep permissions namespace-scoped and purpose-specific.

## RBAC Limits And Required Issuer Logic

RBAC cannot safely enforce dynamic Secret naming/prefix policy.

Issuer logic must enforce:

- namespace fixed to `kube-system`
- Secret name format `bootstrap-token-<id>`
- required token labels are present and validated
- TTL policy bounds are enforced
- token issuance constraints (single active token per user, revoke on replacement)

## CSR Controller Policy (Code-Enforced)

Approver/signer controllers must enforce in code:

- subject CN and requester identity binding
- group allow-list and system group deny-list
- `expirationSeconds` policy bounds
- duplicate pending CSR controls
- signerName allow-list

These checks are not provided by RBAC alone.

## CSR Cleanup Safety

Cleanup behavior should be constrained by controller logic:

- only policy signer CSRs
- only bastion-managed/labeled CSRs
- only older than retention window

This prevents broad indiscriminate deletion while still allowing lifecycle cleanup of stale/issued requests.

## Operational Verification

- verify issuer is bound via namespaced `RoleBinding` in `kube-system`
- verify issuer Secret verbs are minimal (`create`, `get`, `delete`)
- verify approver/signer and cleanup code-path checks remain enabled in release testing
- review RBAC and controller logic together during periodic security reviews
