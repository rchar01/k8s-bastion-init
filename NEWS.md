# News

This file gives a short, release-oriented view of what changed between versions.

## Unreleased

## 1.6.0

Compared with `1.5.0`:

- replaces the `pkexec` login bootstrap helper flow with a root-owned local daemon (`bastion-bootstrapd`) and Unix socket API
- adds daemon service lifecycle management and policy-driven daemon settings (socket path, request limits, timeouts, and backoff)
- moves privileged daemon/client Python logic to `lib/python` with shell wrappers so shellcheck workflows remain intact
- adds offline daemon scenario test coverage and expands verification checks for daemon service/policy expectations
- strengthens CSR security controls with strict identity binding, duplicate pending CSR denial, and explicit system identity/group rejection
- hardens root token issue/revoke script temp-file handling and tightens revoke/cache consistency semantics
- broadens CSR cleanup to remove stale bastion-managed requests by signer/label/retention policy
- consolidates RBAC hardening documentation into `docs/rbac-hardening.md` and updates component/workflow docs accordingly

## 1.5.0

Compared with `1.4.0`:

- hardens admin command execution by installing `/usr/local/sbin/bastion-*` with restricted permissions and root-only guards
- adds sudo `secure_path` bootstrap support so `sudo bastion-*` can resolve admin commands reliably
- installs service kubeconfig at `/etc/kubernetes/admin.kubeconfig` and wires CSR timer services to use it via `KUBECONFIG`
- fixes bootstrap kubeconfig ownership logic to use each user's real primary group instead of assuming group name equals username
- improves RHEL-family dependency install behavior to avoid `curl`/`curl-minimal` conflicts during containerd bootstrap
- standardizes bastion CA guidance to `/etc/kubernetes/ca.crt` and documents why `/etc/kubernetes/pki/ca.crt` is unsafe for init cleanup flows
- converts public `access-policy.yaml` into a clean merge baseline and moves dummy policy examples into docs
- adds dedicated hardening verification tests and includes them in `./tests/run-all.sh`

## 1.4.0

Compared with `1.3.0`:

- adds `bastion-disable-user` for explicit bastion-side user access deactivation
- disables active kubeconfigs and removes bastion-managed `k8s-*` groups during user offboarding
- adds automated test coverage for the user deactivation workflow
- adds `Makefile` convenience targets for download, test, and wrapper-based workflows
- reorganizes the docs around clearer bootstrap, day-2 operations, and architecture guidance
- broadens project positioning to cover both clean Linux VMs and repurposed Kubernetes nodes

## 1.3.0

Compared with `1.2.0`:

- makes downloader source URLs configurable per tool in `download.conf`
- moves default download URLs out of `download.sh` and into config
- adds automated test coverage for downloader URL template and override behavior
- includes the new downloader test in the main `./tests/run-all.sh` suite

## 1.2.0

Compared with `1.1.0`:

- adds project branding with the new repository logo in `README.md`
- adds this `NEWS.md` overview for quick release-to-release reading
- bumps the project version for the next public release

## 1.1.0

Compared with `1.0.0`:

- fixes shared shell error handling by adding a common `die()` helper
- scopes CSR approval to bastion-managed requests and validates signer, usages, and group prefix
- scopes CSR cleanup to bastion-labeled CSRs for the configured signer
- cleans up and aligns public documentation with the current split bootstrap flow
- improves user management and test documentation for public release readiness

## 1.0.0

Initial public release:

- machine bootstrap for bastion host setup
- policy-based user and group management
- short-lived certificate-based Kubernetes access
- policy merge support with public/private/environment layers
- self-service certificate renewal workflow
- automated CSR approval support
- Podman-based test suite
