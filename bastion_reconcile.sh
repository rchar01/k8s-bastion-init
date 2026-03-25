#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ENVIRONMENT=""
OFFLINE_BOOTSTRAP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --offline-bootstrap)
      OFFLINE_BOOTSTRAP=1
      shift
      ;;
    *)
      if [[ -z "$ENVIRONMENT" ]]; then
        ENVIRONMENT="$1"
        shift
      else
        echo "ERROR: Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$ENVIRONMENT" ]]; then
  echo "ERROR: Environment argument is required" >&2
  echo "Usage: $0 <environment> [--offline-bootstrap]" >&2
  echo "Example: $0 prod" >&2
  echo "" >&2
  echo "This script will:" >&2
  echo "  1. Reconcile machine configuration (non-destructive updates)" >&2
  echo "  2. Render policy from ../k8s-bastion-policy for the specified environment" >&2
  echo "  3. Reconcile users, groups, and policies" >&2
  exit 1
fi

POLICY_REPO="${SCRIPT_DIR}/../k8s-bastion-policy"

# Validate policy repo exists
if [[ ! -d "$POLICY_REPO" ]]; then
  echo "ERROR: Policy repository not found at: $POLICY_REPO" >&2
  echo "Expected: ../k8s-bastion-policy relative to this script" >&2
  exit 1
fi

echo "==============================================="
echo "Bastion Reconciliation"
echo "Environment: $ENVIRONMENT"
echo "==============================================="
echo ""

echo "Step 1/3: Reconciling machine configuration"
"$SCRIPT_DIR/sbin/bastion-bootstrap-machine" \
  --reconcile \
  --source "$SCRIPT_DIR"

echo ""
echo "Step 2/3: Rendering policy for env=${ENVIRONMENT}"
"$SCRIPT_DIR/sbin/bastion-render-policy" \
  --policy-repo "$POLICY_REPO" \
  --env "$ENVIRONMENT" \
  --init-repo "$SCRIPT_DIR"

echo ""
echo "Step 3/3: Reconciling users, groups, and policies"
users_args=(--reconcile --source "$SCRIPT_DIR")
if [[ "$OFFLINE_BOOTSTRAP" -eq 1 ]]; then
  users_args+=(--offline-bootstrap)
fi
"$SCRIPT_DIR/sbin/bastion-bootstrap-users" \
  "${users_args[@]}"

echo ""
echo "==============================================="
echo "Reconciliation complete!"
echo "Environment: $ENVIRONMENT"
echo "Version: $(/usr/local/bin/bastion-version 2> /dev/null || echo 'unknown')"
echo "==============================================="
