#!/usr/bin/env bash

policy_read() {
  local policy="${POLICY_FILE:-/etc/bastion/access-policy.yaml}"

  [[ -f "$policy" ]] || die "Policy file not found: $policy"

  local signer cert_ttl_default cert_ttl_min cert_ttl_max renew_threshold
  local bootstrap_ttl_default bootstrap_ttl_max group_prefix
  local cluster_name cluster_server cluster_ca_file

  signer="$(yq -r '.csr.signerName // ""' "$policy")"
  cert_ttl_default="$(yq -r '.csr.ttl.defaultSeconds // ""' "$policy")"
  cert_ttl_min="$(yq -r '.csr.ttl.minSeconds // ""' "$policy")"
  cert_ttl_max="$(yq -r '.csr.ttl.maxSeconds // ""' "$policy")"
  renew_threshold="$(yq -r '.csr.renewal.thresholdSeconds // ""' "$policy")"
  bootstrap_ttl_default="$(yq -r '.bootstrap.ttl.defaultSeconds // ""' "$policy")"
  bootstrap_ttl_max="$(yq -r '.bootstrap.ttl.maxSeconds // ""' "$policy")"
  group_prefix="$(yq -r '.csr.groupPrefix // ""' "$policy")"
  cluster_name="$(yq -r '.cluster.name // ""' "$policy")"
  cluster_server="$(yq -r '.cluster.server // ""' "$policy")"
  cluster_ca_file="$(yq -r '.cluster.caFile // ""' "$policy")"

  [[ -n "$signer" ]] || die "csr.signerName missing in policy"
  [[ "$cert_ttl_default" =~ ^[0-9]+$ ]] || die "csr.ttl.defaultSeconds must be integer"
  [[ "$cert_ttl_min" =~ ^[0-9]+$ ]] || die "csr.ttl.minSeconds must be integer"
  [[ "$cert_ttl_max" =~ ^[0-9]+$ ]] || die "csr.ttl.maxSeconds must be integer"
  [[ "$renew_threshold" =~ ^[0-9]+$ ]] || die "csr.renewal.thresholdSeconds must be integer"
  [[ "$bootstrap_ttl_default" =~ ^[0-9]+$ ]] || die "bootstrap.ttl.defaultSeconds must be integer"
  [[ "$bootstrap_ttl_max" =~ ^[0-9]+$ ]] || die "bootstrap.ttl.maxSeconds must be integer"
  [[ -n "$group_prefix" ]] || die "csr.groupPrefix missing in policy"
  [[ -n "$cluster_name" ]] || die "cluster.name missing in policy"
  [[ -n "$cluster_server" ]] || die "cluster.server missing in policy"
  [[ -n "$cluster_ca_file" ]] || die "cluster.caFile missing in policy"

  ((cert_ttl_min <= cert_ttl_default)) || die "csr.ttl.defaultSeconds must be >= csr.ttl.minSeconds"
  ((cert_ttl_default <= cert_ttl_max)) || die "csr.ttl.defaultSeconds must be <= csr.ttl.maxSeconds"
  ((renew_threshold > 0)) || die "csr.renewal.thresholdSeconds must be > 0"
  ((bootstrap_ttl_default > 0)) || die "bootstrap.ttl.defaultSeconds must be > 0"
  ((bootstrap_ttl_default <= bootstrap_ttl_max)) || die "bootstrap.ttl.defaultSeconds must be <= bootstrap.ttl.maxSeconds"

  export CSR_SIGNER_NAME="$signer"
  export CLIENT_CERT_TTL_DEFAULT_SECONDS="$cert_ttl_default"
  export CLIENT_CERT_TTL_MIN_SECONDS="$cert_ttl_min"
  export CLIENT_CERT_TTL_MAX_SECONDS="$cert_ttl_max"
  export CLIENT_CERT_RENEW_THRESHOLD_SECONDS="$renew_threshold"
  export BOOTSTRAP_TOKEN_TTL_DEFAULT_SECONDS="$bootstrap_ttl_default"
  export BOOTSTRAP_TOKEN_TTL_MAX_SECONDS="$bootstrap_ttl_max"
  export GROUP_PREFIX="$group_prefix"
  export BASTION_CLUSTER_NAME="$cluster_name"
  export BASTION_CLUSTER_SERVER="$cluster_server"
  export BASTION_CLUSTER_CA_FILE="$cluster_ca_file"
}
