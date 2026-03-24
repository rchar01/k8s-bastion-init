# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.5.0] - 2026-03-24

### Added
- Add hardening verification script `tests/verify/check-hardening.sh` and include it in `tests/run-all.sh`.
- Add bootstrap installation of `/etc/kubernetes/admin.kubeconfig` for service-side Kubernetes operations.
- Add sudo secure path configuration at `/etc/sudoers.d/bastion-path` during machine bootstrap.

### Changed
- Install admin scripts under `/usr/local/sbin` with mode `0750` to reduce non-admin execution surface.
- Enforce root-only execution for admin operational commands (audit, CSR handlers, render, expiry, version).
- Configure CSR timer services to run with `KUBECONFIG=/etc/kubernetes/admin.kubeconfig`.
- Normalize PATH in wrappers and shared library to include `/usr/local/bin` and `/usr/local/sbin` in sudo/root contexts.
- Use `/etc/kubernetes/ca.crt` as the documented bastion default for `cluster.caFile` and update operator docs accordingly.
- Convert public `access-policy.yaml` into a merge baseline (`groups: {}`, `users: {}`) and move dummy examples into documentation.

### Fixed
- Fix bootstrap kubeconfig ownership setup for users whose primary group differs from username.
- Fix `bastion-install-containerd` dependency install to avoid `curl` vs `curl-minimal` package conflicts.
- Fix `bastion-manage-csr-timers` cleanup trap failure under `set -u`.
- Fix `bastion-audit-kube-dirs --no-list` to return success instead of failing due to shell truthiness.

## [1.4.0] - 2026-03-11

### Added
- Add `bastion-disable-user` to explicitly remove bastion-managed Kubernetes access for a target host user.
- Add automated coverage for user deactivation in `tests/scenarios/test-disable-user.sh` and include it in `tests/run-all.sh`.
- Add `Makefile` convenience targets for downloads, tests, and wrapper-based init/reconcile workflows.
- Add `docs/architecture.md` with a high-level bastion access and certificate flow diagram.

### Changed
- Reorganize `README.md` into a cleaner landing page that points operators to the dedicated bootstrap and user-management docs.
- Clarify that Mode 1 is non-production and Mode 2 is the recommended production workflow.
- Expand bootstrap and user-management documentation with day-2 operations, maintenance guidance, and explicit user deactivation procedures.
- Update admin tool listings to include `bastion-disable-user`.
- Broaden project wording to cover both clean Linux VMs and repurposed Kubernetes nodes.

## [1.3.0] - 2026-03-09
### Added
- Add configurable per-tool download URL templates in `download.conf` so tool sources can be redirected to internal mirrors or custom artifact hosts.
- Add automated coverage for downloader URL template resolution and override behavior in `tests/scenarios/test-download-config.sh`.

### Changed
- Move default downloader URLs out of `download.sh` and into `download.conf` to keep all tool source configuration in one place.
- Add downloader test execution to `tests/run-all.sh` and document the scenario in `tests/README.md`.
- Bump project version to `1.3.0` for the next release.

## [1.2.0] - 2026-03-09
### Added
- Add project logo asset and display it in `README.md` for the public repository landing page.
- Add a `NEWS.md` file summarizing release-to-release changes for readers who want a quick upgrade overview.

### Changed
- Bump project version to `1.2.0` for the next public release.

## [1.1.0] - 2026-03-06
### Fixed
- Add shared `die()` helper in common library so all scripts fail consistently on validation and argument errors.
- Scope CSR approval to bastion-managed requests and validate signer, usages, and group prefix against policy before approval.
- Scope CSR cleanup to bastion-labeled CSRs for the configured signer to avoid deleting unrelated CSRs.

### Changed
- Update README command references to the split bootstrap flow (`bastion-bootstrap-machine` and `bastion-bootstrap-users`).
- Clarify Mode 1/Mode 2 workflows and align examples with current script behavior.
- Replace and clean up user management documentation for publish-ready accuracy.
- Update tests documentation to clarify host-vs-container verification steps and `--no-cleanup` behavior.

## [1.0.0] - 2026-03-05
### Added
- Initial release of Kubernetes Bastion Host Toolkit
- Machine bootstrap with containerd and tool installation
- User/group management with policy-based configuration
- Certificate-based Kubernetes access with short-lived certs (7-day default)
- Policy merge system (public + private + environment layers)
- Self-service certificate renewal for users
- CSR approval automation
- Podman-based test suite
