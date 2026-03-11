SHELL := /bin/bash

.PHONY: help download test test-no-cleanup test-setup test-cleanup init reconcile

help:
	@printf '%s\n' \
	  'Available targets:' \
	  '  make download               Download tool artifacts into tools/' \
	  '  make test                   Run the full Podman test suite' \
	  '  make test-no-cleanup        Run tests and keep the container for inspection' \
	  '  make test-setup             Build and start the test container only' \
	  '  make test-cleanup           Remove test containers and volumes' \
	  '  make init ENV=<env>         Run bastion_init.sh for policy-merge mode' \
	  '  make reconcile ENV=<env>    Run bastion_reconcile.sh for policy-merge mode'

download:
	./download.sh

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
