#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"
TOOLS_DIR=""

parse_common_args() {

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-dir)
        BASE_DIR="$2"
        shift 2
        ;;
      --tools-dir)
        TOOLS_DIR="$2"
        shift 2
        ;;
      --dest-bin)
        DEST_BIN="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  # derive defaults
  [[ -z "${TOOLS_DIR:-}" ]] && TOOLS_DIR="${BASE_DIR%/}/tools"
}
