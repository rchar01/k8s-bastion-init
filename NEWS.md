# News

This file gives a short, release-oriented view of what changed between versions.

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
