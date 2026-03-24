#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-./download.conf}"
BIN_DIR="${BIN_DIR:-./tools}"
WGET_BIN="${WGET_BIN:-wget}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing download.conf"
  exit 1
fi

source "$CONFIG_FILE"

mkdir -p "$BIN_DIR"

# --------------------------------------------------
# Architecture resolution
# --------------------------------------------------

if [[ -z "${ARCH:-}" ]]; then
  SYS_ARCH="$(uname -m)"
else
  SYS_ARCH="$ARCH"
fi

case "$SYS_ARCH" in
  x86_64 | amd64)
    ARCH="amd64"
    ARCH_X86_64="x86_64"
    ;;
  aarch64 | arm64)
    ARCH="arm64"
    ARCH_X86_64="aarch64"
    ;;
  *)
    echo "Unsupported architecture: $SYS_ARCH"
    exit 1
    ;;
esac

echo "==> Using ARCH=${ARCH}"

cd "$BIN_DIR"

# --------------------------------------------------
# Download helpers
# --------------------------------------------------

resolve_url() {
  local template_name="$1"
  local template_value="${!template_name:-}"

  if [[ -z "$template_value" ]]; then
    echo "Missing URL template: $template_name" >&2
    exit 1
  fi

  eval "printf '%s\\n' \"$template_value\""
}

download() {
  local url="$1"
  local file
  file="$(basename "$url")"
  local tmp="${file}.part"

  #  echo "==> Downloading ${file}"

  rm -f "$tmp"

  "$WGET_BIN" \
    --quiet \
    --https-only \
    --tries=5 \
    --timeout=30 \
    --retry-connrefused \
    --waitretry=2 \
    --show-progress \
    -O "$tmp" "$url"

  mv "$tmp" "$file"

  validate_archive "$file"
}

validate_archive() {
  local f="$1"

  case "$f" in
    *.tgz | *.tar.gz)
      #     echo "    validating gzip archive..."
      gzip -t "$f"
      ;;
  esac
}

# --------------------------------------------------
# Downloads
# --------------------------------------------------

# kubectl
download "$(resolve_url KUBECTL_URL)"

# helm
download "$(resolve_url HELM_URL)"

# k9s
download "$(resolve_url K9S_URL)"

# jq
download "$(resolve_url JQ_URL)"

# yq
download "$(resolve_url YQ_URL)"

# stern
download "$(resolve_url STERN_URL)"

# crane (go-containerregistry)
download "$(resolve_url CRANE_URL)"

# regctl
download "$(resolve_url REGCTL_URL)"

# etcdctl
download "$(resolve_url ETCD_URL)"

# skopeo static
download "$(resolve_url SKOPEO_URL)"

# containerd
download "$(resolve_url CONTAINERD_URL)"

# nerdctl
download "$(resolve_url NERDCTL_URL)"

# runc
download "$(resolve_url RUNC_URL)"

# CNI plugins
download "$(resolve_url CNI_URL)"

echo
echo "==> All downloads complete in ${BIN_DIR}"
