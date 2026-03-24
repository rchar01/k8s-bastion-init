#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TMP_DIR="$(mktemp -d "${SCRIPT_DIR}/tmp.download.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

TOOLS_DIR="${TMP_DIR}/tools"
URL_LOG="${TMP_DIR}/urls.log"
CONFIG_PATH="${TMP_DIR}/download.conf"

mkdir -p "$TOOLS_DIR"
: > "$URL_LOG"

cat > "${TMP_DIR}/mock-wget" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

out=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -O)
      out="$2"
      shift 2
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

printf '%s\n' "$url" >> "$URL_LOG"

case "$out" in
  *.tgz|*.tgz.part|*.tar.gz|*.tar.gz.part)
    printf 'test archive\n' | gzip -c > "$out"
    ;;
  *)
    printf 'test file\n' > "$out"
    ;;
esac
EOF

chmod +x "${TMP_DIR}/mock-wget"

printf 'source "%s"\n' "${REPO_DIR}/download.conf" > "$CONFIG_PATH"
printf 'ARCH=arm64\n' >> "$CONFIG_PATH"
cat >> "$CONFIG_PATH" << 'EOF'
KUBECTL_URL='https://mirror.example/k8s/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl'
EOF

URL_LOG="$URL_LOG" WGET_BIN="${TMP_DIR}/mock-wget" CONFIG_FILE="$CONFIG_PATH" BIN_DIR="$TOOLS_DIR" \
  bash "${REPO_DIR}/download.sh" > /dev/null

grep -qx 'https://mirror.example/k8s/v1.29.15/bin/linux/arm64/kubectl' "$URL_LOG"
grep -qx 'https://get.helm.sh/helm-v4.1.1-linux-arm64.tar.gz' "$URL_LOG"
grep -qx 'https://github.com/google/go-containerregistry/releases/download/v0.21.1/go-containerregistry_Linux_aarch64.tar.gz' "$URL_LOG"

test -f "${TOOLS_DIR}/kubectl"
test -f "${TOOLS_DIR}/helm-v4.1.1-linux-arm64.tar.gz"

printf 'Verified custom and default download URLs\n'
printf 'download config URL override test: PASS\n'
