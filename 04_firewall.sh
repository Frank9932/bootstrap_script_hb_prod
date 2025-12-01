#!/usr/bin/env bash
#
# 04_firewall.sh
# Firewall baseline for AlmaLinux / RHEL 8+ using firewalld.
#
# Goals:
# - Install and enable firewalld
# - Restrict external access to SSH only
# - Automatically detect the SSH port from sshd configuration
# - Remove other default services from the active zone
# - Print the resulting firewall state
#

set -euo pipefail

source "$(dirname "$0")/00_common.sh"

FIREWALLD_PKG="firewalld"
SSH_PORT="${SSH_PORT:-}"
ENABLE_WEB="${ENABLE_WEB:-0}"
WEB_PORTS="${WEB_PORTS:-80 443}"

ensure_firewalld_installed() {
  ensure_package "${FIREWALLD_PKG}"
  log "firewalld is already installed or has been installed."
}

ensure_firewalld_running() {
  log "Enabling and starting firewalld..."
  systemctl enable --now firewalld

  if ! systemctl is-active firewalld &>/dev/null; then
    err "firewalld service is not active after start attempt."
    exit 1
  fi
}

get_default_zone() {
  local zone
  zone="$(firewall-cmd --get-default-zone)"
  echo "$zone"
}

detect_ssh_port() {
  # Detect the primary SSH port from sshd effective config.
  # Fallback to 22 if detection fails.
  local port

  if command -v sshd &>/dev/null; then
    # sshd -T shows effective config; grab the first "port" line.
    port="$(sshd -T 2>/dev/null | awk '/^port / {print $2; exit}')"
    if [[ -n "${port:-}" ]]; then
      echo "$port"
      return 0
    fi
  fi

  # Fallback
  echo "22"
}

configure_zone_for_ssh_only() {
  local zone="$1"
  local ssh_port="$2"

  log "Configuring firewalld zone '${zone}' to allow SSH (and web if enabled)..."

  # Always allow ssh service
  firewall-cmd --permanent --zone="$zone" --add-service=ssh

  # Allow custom ssh port when not default
  if [[ "$ssh_port" != "22" ]]; then
    firewall-cmd --permanent --zone="$zone" --add-port="${ssh_port}/tcp"
  fi

  if [[ "${ENABLE_WEB}" == "1" ]]; then
    log "ENABLE_WEB=1; opening HTTP/HTTPS (${WEB_PORTS})."
    firewall-cmd --permanent --zone="$zone" --add-service=http
    firewall-cmd --permanent --zone="$zone" --add-service=https
    for p in ${WEB_PORTS}; do
      firewall-cmd --permanent --zone="$zone" --add-port="${p}/tcp" || true
    done
  fi

  # Remove all services other than ssh (+ http/https if enabled)
  local svc
  for svc in $(firewall-cmd --permanent --zone="$zone" --list-services); do
    case "$svc" in
      ssh) continue ;;
      http|https)
        [[ "${ENABLE_WEB}" == "1" ]] && continue
        ;;
    esac
    log "Removing unnecessary service '${svc}' from zone '${zone}'..."
    firewall-cmd --permanent --zone="$zone" --remove-service="$svc" || true
  done

  # Remove ports except allowed ssh (+ optional web)
  for p in $(firewall-cmd --permanent --zone="$zone" --list-ports); do
    case "$p" in
      "${ssh_port}/tcp") continue ;;
      "80/tcp"|"443/tcp")
        [[ "${ENABLE_WEB}" == "1" ]] && continue
        ;;
    esac
    log "Removing unnecessary port '${p}' from zone '${zone}'..."
    firewall-cmd --permanent --zone="$zone" --remove-port="$p" || true
  done
}

reload_and_show() {
  log "Reloading firewalld to apply changes..."
  firewall-cmd --reload

  local zone
  zone="$(get_default_zone)"

  log "Current firewalld configuration for zone '${zone}':"
  firewall-cmd --zone="$zone" --list-all || true
}

main() {
  require_root
  require_rhel_like

  log "=== Firewall baseline setup (firewalld + SSH only) ==="

  ensure_firewalld_installed
  ensure_firewalld_running

  local zone ssh_port web_state
  zone="$(get_default_zone)"
  ssh_port="${SSH_PORT:-}"
  if [[ -z "$ssh_port" ]]; then
    ssh_port="$(detect_ssh_port)"
  fi
  if [[ "${ENABLE_WEB}" == "1" ]]; then
    web_state="OPEN (ENABLE_WEB=1)"
  else
    web_state="CLOSED by default (set ENABLE_WEB=1 to open)"
  fi

  log "Default firewalld zone: ${zone}"
  log "Detected SSH port: ${ssh_port}"

  configure_zone_for_ssh_only "$zone" "$ssh_port"
  reload_and_show

  cat <<INFO

========================================================
Firewall baseline applied.

- firewalld is installed and running.
- Default zone: ${zone}
- SSH service is allowed.
- SSH port ${ssh_port}/tcp is explicitly opened (if not 22).
- Other default services in zone '${zone}' have been removed.
- Web ports (80/443) are ${web_state}.

Next steps (VERY IMPORTANT):

1) From your LOCAL machine, open a NEW terminal and test:

   ssh -p ${ssh_port} youruser@YOUR_SERVER_IP

   Make sure you can still log in.

2) (Optional) From another host, run a quick scan:

   nmap -p 1-1024 YOUR_SERVER_IP

   You should only see port ${ssh_port}/tcp open (SSH).

If login works and only SSH is exposed, the firewall baseline
is correctly in place. You can safely continue to use Fail2ban
and Docker on top of this configuration.
========================================================
INFO

  log "=== Firewall baseline setup completed ==="
}

main "$@"
