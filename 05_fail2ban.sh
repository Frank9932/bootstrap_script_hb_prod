#!/usr/bin/env bash
#
# 05_fail2ban.sh
# Install and configure Fail2ban to protect SSH on AlmaLinux / RHEL 8+.
#
# Goals:
# - Install EPEL + fail2ban (+ firewalld integration if available)
# - Create a dedicated jail for sshd using /etc/fail2ban/jail.d/
# - Enable and start fail2ban service
# - Safe to run multiple times (idempotent)
#

set -euo pipefail

source "$(dirname "$0")/00_common.sh"

JAILD_DIR="/etc/fail2ban/jail.d"
SSHD_JAIL_CONF="${JAILD_DIR}/sshd-hardening.conf"

install_fail2ban() {
  log "Installing EPEL repository (idempotent)..."
  dnf install -y epel-release || warn "epel-release installation issue; likely already installed."

  log "Installing Fail2ban..."
  if ! dnf install -y fail2ban fail2ban-firewalld; then
    warn "fail2ban-firewalld not available, installing fail2ban only..."
    dnf install -y fail2ban
  fi
}

write_sshd_jail() {
  log "Writing SSH jail configuration to ${SSHD_JAIL_CONF}..."
  mkdir -p "$JAILD_DIR"

  # Overwrite every time to ensure consistent configuration
  cat > "$SSHD_JAIL_CONF" << 'EOF_JAIL'
[sshd]
enabled  = true
port     = ssh
filter   = sshd

# Default SSH log location on RHEL / AlmaLinux
logpath  = /var/log/secure

# Ban after 5 failures within 10 minutes; ban lasts 1 hour
maxretry = 5
findtime = 600
bantime  = 3600

# Use systemd/journald backend (fallback handled by Fail2ban)
backend  = systemd

# Use firewalld rich rules for banning
banaction = firewallcmd-rich-rules
EOF_JAIL
}

enable_and_start_fail2ban() {
  log "Enabling and starting Fail2ban service..."
  systemctl enable --now fail2ban

  if command -v fail2ban-client &>/dev/null; then
    log "Fail2ban overall status:"
    fail2ban-client status || warn "fail2ban-client returned non-zero."

    log "Fail2ban sshd jail status (if active):"
    fail2ban-client status sshd || warn "sshd jail may not be active yet."
  else
    warn "fail2ban-client not found; cannot display jail status."
  fi
}

main() {
  require_root

  log "=== Fail2ban SSH protection setup start ==="

  install_fail2ban
  write_sshd_jail
  enable_and_start_fail2ban

  cat << 'INFO'

========================================================
Fail2ban is installed and configured to protect SSH.

To verify:

1) Check the SSH jail:
   fail2ban-client status sshd

   Expected:
   - Status: active
   - Currently banned: 0
   - Total banned:     0

2) Generate several failed SSH attempts from another IP,
   then run again:
   fail2ban-client status sshd

   "Currently banned" should increase after exceeding maxretry.

3) Check rich rules created by Fail2ban:
   firewall-cmd --zone=public --list-rich-rules

Re-running this script is safe:
- No duplicate configurations
- SSH jail always stays in sync
========================================================
INFO

  log "=== Fail2ban SSH protection setup finished ==="
}

main "$@"
