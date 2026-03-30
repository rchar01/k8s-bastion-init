SHELL := /bin/bash

.PHONY: help download fmt-shell fmt-shell-check lint-shell check-shell test test-no-cleanup test-setup test-cleanup init reconcile

help:
	@printf '%s\n' \
	  'Available targets:' \
	  '  make download               Download tool artifacts into tools/' \
	  '  make fmt-shell              Format shell files with shfmt' \
	  '  make fmt-shell-check        Check shell formatting (fails on diffs)' \
	  '  make lint-shell             Run shellcheck on shell scripts' \
	  '  make check-shell            Run shell format + lint checks' \
	  '  make test                   Run the full Podman test suite' \
	  '  make test-no-cleanup        Run tests and keep the container for inspection' \
	  '  make test-setup             Build and start the test container only' \
	  '  make test-cleanup           Remove test containers and volumes' \
	  '  make init ENV=<env>         Run bastion_init.sh for policy-merge mode' \
	  '  make reconcile ENV=<env>    Run bastion_reconcile.sh for policy-merge mode'

download:
	./download.sh

fmt-shell:
	shfmt -i 2 -ci -sr -bn -w .

fmt-shell-check:
	shfmt -i 2 -ci -sr -bn -d .

lint-shell:
	bash -O globstar -c 'shellcheck -x -S warning -e SC1090,SC2034 ./*.sh ./bin/* ./internal-bin/* ./sbin/* ./lib/*.sh ./tests/**/*.sh'

check-shell: fmt-shell-check lint-shell

test:
	./tests/run-all.sh

test-no-cleanup:
	./tests/run-all.sh --no-cleanup

test-setup:
	./tests/podman/setup.sh

test-cleanup:
	./tests/podman/cleanup.sh

init:
	@if [[ -z "$(ENV)" ]]; then \
	  printf '%s\n' 'Usage: make init ENV=<environment>' >&2; \
	  exit 1; \
	fi
	sudo ./bastion_init.sh "$(ENV)"

reconcile:
	@if [[ -z "$(ENV)" ]]; then \
	  printf '%s\n' 'Usage: make reconcile ENV=<environment>' >&2; \
	  exit 1; \
	fi
	sudo ./bastion_reconcile.sh "$(ENV)"
