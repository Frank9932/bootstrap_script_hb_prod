#!/usr/bin/env bash
#
# 00_common.sh
# Shared helper functions for all modules.
#

set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${BOOTSTRAP_DIR}/bootstrap.conf}"

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

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

require_rhel_like() {
  if [[ ! -f /etc/os-release ]]; then
    err "/etc/os-release not found; cannot verify OS."
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID_LIKE:-}" != *"rhel"* && "${ID:-}" != *"rhel"* && "${ID:-}" != *"centos"* && "${ID:-}" != *"almalinux"* && "${ID:-}" != *"rocky"* ]]; then
    err "This toolkit targets RHEL-like systems (Rocky/Alma/RHEL). Detected: ${ID:-unknown}"
    exit 1
  fi
}

ensure_package() {
  local pkg="$1"
  if ! rpm -q "$pkg" &>/dev/null; then
    dnf install -y "$pkg"
  fi
}

ensure_packages() {
  local pkgs=("$@")
  if ((${#pkgs[@]} > 0)); then
    dnf install -y "${pkgs[@]}"
  fi
}

dnf_update_if_enabled() {
  local run_update="${RUN_DNF_UPDATE:-1}"
  if [[ "$run_update" == "1" ]]; then
    log "Running dnf update -y (RUN_DNF_UPDATE=${run_update})..."
    dnf update -y
  else
    log "Skipping dnf update (RUN_DNF_UPDATE=${run_update})."
  fi
}

ensure_epel() {
  if ! rpm -q epel-release &>/dev/null; then
    log "Installing epel-release..."
    dnf install -y epel-release
  else
    log "epel-release already installed."
  fi
}

ensure_timezone() {
  local tz="${TIMEZONE:-UTC}"
  if command -v timedatectl &>/dev/null; then
    current_tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    if [[ "${current_tz}" != "${tz}" ]]; then
      log "Setting timezone to ${tz} (current: ${current_tz:-unknown})"
      timedatectl set-timezone "${tz}"
    else
      log "Timezone already set to ${tz}."
    fi
  else
    warn "timedatectl not available; skipping timezone configuration."
  fi
}

ensure_chrony() {
  ensure_package chrony
  log "Enabling and starting chronyd..."
  systemctl enable --now chronyd
}

ensure_base_tools() {
  local default_tools=(
    vim nano wget curl git unzip
    net-tools htop lsof traceroute
    bind-utils tar
  )
  local extra_tools=()
  if [[ "${INSTALL_TELNET:-0}" == "1" ]]; then
    extra_tools+=(telnet)
  fi
  log "Installing base tools..."
  ensure_packages "${default_tools[@]}" "${extra_tools[@]}"
}

ensure_dirs_permissions() {
  local path="$1" mode="$2" owner="$3"
  mkdir -p "$path"
  chmod "$mode" "$path"
  chown "$owner" "$path"
}

write_file_if_changed() {
  local target="$1" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  if [[ ! -f "$target" ]] || ! cmp -s "$tmp" "$target"; then
    mv "$tmp" "$target"
  else
    rm -f "$tmp"
  fi
}

ensure_wheel_nopasswd() {
  local file="/etc/sudoers.d/00-wheel-nopasswd"
  require_cmd visudo
  umask 0137 # ensures 0640 max; we'll set to 0440 explicitly
  write_file_if_changed "$file" <<'EOF'
%wheel ALL=(ALL) NOPASSWD: ALL
Defaults:%wheel !requiretty
EOF
  chmod 0440 "$file"
  if ! visudo -cf "$file" >/dev/null; then
    err "visudo validation failed for $file"
    exit 1
  fi
  log "Sudoers drop-in ensured at ${file} (wheel passwordless sudo, !requiretty)."
}

run_system_basics() {
  require_rhel_like
  dnf_update_if_enabled
  ensure_epel
  ensure_base_tools
  ensure_timezone
  ensure_chrony
}
