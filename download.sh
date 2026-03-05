#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="./download.conf"
BIN_DIR="./tools"

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
  x86_64|amd64)
    ARCH="amd64"
    ARCH_X86_64="x86_64"
    ;;
  aarch64|arm64)
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

download() {
  local url="$1"
  local file
  file="$(basename "$url")"
  local tmp="${file}.part"

#  echo "==> Downloading ${file}"

  rm -f "$tmp"

  wget \
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
    *.tgz|*.tar.gz)
 #     echo "    validating gzip archive..."
      gzip -t "$f"
      ;;
  esac
}

# --------------------------------------------------
# Downloads
# --------------------------------------------------

# kubectl
download "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"

# helm
download "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"

# k9s
download "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz"

# jq
download "https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-linux-${ARCH}"

# yq
download "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}"

# stern
download "https://github.com/stern/stern/releases/download/${STERN_VERSION}/stern_${STERN_VERSION#v}_linux_${ARCH}.tar.gz"

# crane (go-containerregistry)
download "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_${ARCH_X86_64}.tar.gz"

# regctl
download "https://github.com/regclient/regclient/releases/download/${REGCTL_VERSION}/regctl-linux-${ARCH}"

# etcdctl
download "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"

# skopeo static
download "https://github.com/lework/skopeo-binary/releases/download/${SKOPEO_VERSION}/skopeo-linux-${ARCH}"

# containerd
download "https://github.com/containerd/containerd/releases/download/${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION#v}-linux-${ARCH}.tar.gz"

# nerdctl
download "https://github.com/containerd/nerdctl/releases/download/${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION#v}-linux-${ARCH}.tar.gz"

# runc
download "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${ARCH}"

# CNI plugins
download "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz"

echo
echo "==> All downloads complete in ${BIN_DIR}"
