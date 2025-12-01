#!/usr/bin/env bash
#
# bootstrap.sh
# Top-level orchestrator for hardening a fresh AlmaLinux/RHEL server.
#
# It runs the following modules in order:
#   00_common.sh        (helpers, sourced by others)
#   System basics       (dnf update, epel, base tools, timezone, chrony)
#   01_root_password.sh (set strong emergency root password)
#   02_create_user.sh   (create non-root user + SSH key)
#   03_harden_sshd.sh   (disable root login + password auth)
#   04_firewall.sh      (firewalld baseline, only expose SSH)
#   05_fail2ban.sh      (SSH brute-force protection)
#   06_docker_tools.sh  (Docker CE + Compose + CLI tools) [optional]
#
# Usage:
#   chmod +x bootstrap.sh
#   sudo ./bootstrap.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/bootstrap.conf}"

# Simple local logger (bootstrap may be run before 00_common exists / is sourced)
log()  { echo -e "[\e[32mINFO\e[0m] $*"; }
warn() { echo -e "[\e[33mWARN\e[0m] $*"; }
err()  { echo -e "[\e[31mERR \e[0m] $*" >&2; }

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    err "This script must be run as root (use sudo)."
    exit 1
  fi
}

require_file_exec() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    err "Required script not found: $file"
    exit 1
  fi
  if [[ ! -x "$file" ]]; then
    log "Making script executable: $file"
    chmod +x "$file"
  fi
}

pause_for_confirmation() {
  local msg="$1"
  echo
  warn "$msg"
  read -rp "Type 'yes' to continue, anything else to abort: " answer
  if [[ "$answer" != "yes" ]]; then
    err "Aborted by user."
    exit 1
  fi
}

main() {
  require_root

  # shellcheck disable=SC1090
  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

  cd "$SCRIPT_DIR"

  cat << 'BANNER'
========================================================
 Secure AlmaLinux Bootstrap (SSH + Firewall + Fail2ban + Docker)
========================================================

This orchestrator will run the following modules:

  System basics         - dnf update, epel, base tools, timezone, chrony
  01_root_password.sh   - Generate new emergency root password
  02_create_user.sh     - Create non-root user + SSH key
  03_harden_sshd.sh     - Disable root login and password auth
  04_firewall.sh        - Install firewalld, expose ONLY SSH
  05_fail2ban.sh        - Install Fail2ban, protect SSH
  06_docker_tools.sh    - Install Docker CE + Compose + CLI tools (if ENABLE_DOCKER=1)

!!! IMPORTANT !!!
- Keep your current SSH session open at all times.
- After SSH and firewall changes, ALWAYS open a NEW terminal and
  test you can still log in before continuing.
BANNER

  pause_for_confirmation "Ready to start bootstrap?"

  require_file_exec "${SCRIPT_DIR}/00_common.sh"
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/00_common.sh"

  # Ensure all module scripts exist and are executable
  require_file_exec "${SCRIPT_DIR}/01_root_password.sh"
  require_file_exec "${SCRIPT_DIR}/02_create_user.sh"
  require_file_exec "${SCRIPT_DIR}/03_harden_sshd.sh"
  require_file_exec "${SCRIPT_DIR}/04_firewall.sh"
  require_file_exec "${SCRIPT_DIR}/05_fail2ban.sh"
  require_file_exec "${SCRIPT_DIR}/06_docker_tools.sh"

  log "Config loaded from ${CONFIG_FILE:-<none>} (if present)."
  log "Settings: ADMIN_USER=${ADMIN_USER:-admin} SSH_PORT=${SSH_PORT:-auto} ENABLE_WEB=${ENABLE_WEB:-0} ENABLE_DOCKER=${ENABLE_DOCKER:-0} TIMEZONE=${TIMEZONE:-UTC}"

  log "Step 1/7: Running system basics (dnf update, epel, base tools, timezone, chrony)..."
  run_system_basics

  log "Step 2/7: Running 01_root_password.sh (emergency root password)..."
  "${SCRIPT_DIR}/01_root_password.sh"

  pause_for_confirmation "Root password rotated. Have you stored the new emergency password safely?"

  log "Step 3/7: Running 02_create_user.sh (non-root user + SSH key)..."
  "${SCRIPT_DIR}/02_create_user.sh"

  pause_for_confirmation "Non-root user and SSH keys configured. Have you tested 'ssh youruser@server' in a NEW terminal?"

  log "Step 4/7: Running 03_harden_sshd.sh (disable root + password auth)..."
  "${SCRIPT_DIR}/03_harden_sshd.sh"

  cat << 'INFO_SSH'

>>> ACTION REQUIRED: TEST SSH LOGIN NOW <<<

Open a NEW terminal on your local machine and test:

  1) SSH with your non-root user + key:
       ssh youruser@YOUR_SERVER_IP

  2) Root login and password login should fail:
       ssh root@YOUR_SERVER_IP
       ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no youruser@YOUR_SERVER_IP

If your non-root SSH login works and root/password logins fail, press 'yes' to continue.
If not, FIX IT BEFORE GOING FURTHER.
INFO_SSH

  pause_for_confirmation "Have you confirmed SSH hardening works and you can still log in as non-root?"

  log "Step 5/7: Running 04_firewall.sh (firewalld baseline: SSH only)..."
  "${SCRIPT_DIR}/04_firewall.sh"

  cat << 'INFO_FW'

>>> ACTION REQUIRED: TEST FIREWALL + SSH <<<

From a NEW local terminal:

  - Test SSH again (with the correct port if you changed it in sshd):
      ssh -p SSH_PORT youruser@YOUR_SERVER_IP

  - Optionally, from another host:
      nmap -p 1-1024 YOUR_SERVER_IP

You should see ONLY the SSH port open.

If SSH still works and only SSH is exposed, press 'yes' to continue.
INFO_FW

  pause_for_confirmation "Have you confirmed firewall rules (SSH only) and SSH access still work?"

  log "Step 6/7: Running 05_fail2ban.sh (SSH brute-force protection)..."
  "${SCRIPT_DIR}/05_fail2ban.sh"

  cat << 'INFO_F2B'

You can now verify Fail2ban:

  fail2ban-client status sshd

Optionally, generate some failed SSH attempts from another IP,
then check the jail status again to see bans being applied.
INFO_F2B

  log "Step 7/7: Running 06_docker_tools.sh (Docker + CLI tools, optional)..."
  "${SCRIPT_DIR}/06_docker_tools.sh"

  cat << 'DONE'

========================================================
Bootstrap completed.

You now have:
- System basics applied (dnf update, epel, base tools, timezone, chrony).
- Strong emergency root password (unless skipped).
- Non-root user with SSH key login.
- SSH hardened (custom port, root/password auth controlled by flags).
- firewalld baseline (only SSH exposed; web ports only if ENABLE_WEB=1).
- Fail2ban protecting SSH using firewalld.
- Docker CE + Compose + common CLI tools (only if ENABLE_DOCKER=1).

Next recommended steps:
- Relogin as your non-root user and use sudo when needed.
- Use Docker for your trading services, publishing only the
  ports you explicitly need, and opening them in firewalld
  on a per-service basis.
========================================================
DONE
}

main "$@"
