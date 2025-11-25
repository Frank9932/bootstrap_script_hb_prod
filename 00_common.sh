#!/usr/bin/env bash
#
# 00_common.sh
# Shared helper functions for all modules.
#

set -euo pipefail

# Logging helpers
log()  { echo -e "[\e[32mINFO\e[0m] $*"; }
warn() { echo -e "[\e[33mWARN\e[0m] $*"; }
err()  { echo -e "[\e[31mERR \e[0m] $*" >&2; }

# Ensure the script is executed as root
require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    err "This script must be run as root."
    exit 1
  fi
}

# Ensure a required command exists in PATH
require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    err "Command '$cmd' not found. Please install it or add it to PATH."
    exit 1
  fi
}
