log() { echo "[$PROGRAM_NAME] $*"; }

die() {
	local msg="$*"
	if declare -F log_error >/dev/null 2>&1; then
		log_error "$msg"
	else
		echo "ERROR: $msg" >&2
	fi
	exit 1
}

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
