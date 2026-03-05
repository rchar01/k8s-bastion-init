log() { echo "[$PROGRAM_NAME] $*"; }

require_root() {
  [[ $EUID -eq 0 ]] || {
    echo "Run as root"
    exit 1
  }
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1"
    exit 1
  }
}
