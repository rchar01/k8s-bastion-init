#!/usr/bin/env bash

# Fixed Kubernetes integration contract constants.
BOOTSTRAP_AUTH_GROUP="system:bootstrappers:platform-users"
CSR_SIGNER_NAME="platform.example.io/client"

CONTROLLER_NAMESPACE="bastion-system"
CSR_APPROVER_SA="bastion-csr-approver"
CSR_SIGNER_SA="bastion-csr-signer"
CSR_CLEANUP_SA="bastion-csr-cleanup"
TOKEN_ISSUER_SA="bastion-token-issuer"

BOOTSTRAP_TOKEN_NAMESPACE="kube-system"

# TTL policy (Model A)
BOOTSTRAP_TOKEN_TTL_DEFAULT_SECONDS=900
BOOTSTRAP_TOKEN_TTL_MAX_SECONDS=1800

CLIENT_CERT_TTL_DEFAULT_SECONDS=28800
CLIENT_CERT_TTL_MIN_SECONDS=3600
CLIENT_CERT_TTL_MAX_SECONDS=86400
CLIENT_CERT_RENEW_THRESHOLD_SECONDS=7200

# Renewal guard: allow renewal only when cert lifetime remaining <= 25%
CLIENT_CERT_RENEW_WINDOW_PERCENT=25
