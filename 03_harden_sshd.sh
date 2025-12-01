#!/usr/bin/env bash
#
# 03_harden_sshd.sh
# SSH hardening for AlmaLinux / RHEL 8+:
# - Backup /etc/ssh/sshd_config
# - Ensure Include /etc/ssh/sshd_config.d/*.conf
# - Comment out sensitive directives elsewhere
# - Create 99-hardening.conf as the final override
# - Enforce key auth; optionally change port and allow/deny root/password login
#

set -euo pipefail

# Common helpers
source "$(dirname "$0")/00_common.sh"

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
HARDEN_CONF="${SSHD_DROPIN_DIR}/99-hardening.conf"

SSH_PORT="${SSH_PORT:-22}"
DISABLE_ROOT_LOGIN="${DISABLE_ROOT_LOGIN:-1}"
DISABLE_PASSWORD_AUTH="${DISABLE_PASSWORD_AUTH:-1}"

backup_sshd_config() {
  if [[ -f "$SSHD_CONFIG" && ! -f "${SSHD_CONFIG}.orig" ]]; then
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.orig"
    log "Backed up original SSH config to ${SSHD_CONFIG}.orig"
  fi

  if [[ -d "$SSHD_DROPIN_DIR" ]]; then
    for f in "${SSHD_DROPIN_DIR}"/*.conf; do
      [[ ! -f "$f" ]] && continue
      if [[ ! -f "${f}.orig" ]]; then
        cp "$f" "${f}.orig"
        log "Backed up drop-in config ${f} -> ${f}.orig"
      fi
    done
  fi
}

ensure_include_dropins() {
  # Make sure sshd_config actually includes the drop-in directory
  if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*\.conf' "$SSHD_CONFIG"; then
    log "Adding Include /etc/ssh/sshd_config.d/*.conf to $SSHD_CONFIG"
    # Insert at the top (after possible initial comments)
    sed -i '1iInclude /etc/ssh/sshd_config.d/*.conf' "$SSHD_CONFIG"
  fi
}

comment_key_everywhere() {
  local key="$1"

  # 1) Main sshd_config
  if [[ -f "$SSHD_CONFIG" ]]; then
    sed -ri "s/^[[:space:]]*${key}[[:space:]].*/# ${key} disabled by hardening script/" "$SSHD_CONFIG"
  fi

  # 2) All drop-in files except our own
  if [[ -d "$SSHD_DROPIN_DIR" ]]; then
    for f in "${SSHD_DROPIN_DIR}"/*.conf; do
      [[ ! -f "$f" ]] && continue
      [[ "$f" == "$HARDEN_CONF" ]] && continue
      sed -ri "s/^[[:space:]]*${key}[[:space:]].*/# ${key} disabled by hardening script/" "$f"
    done
  fi
}

write_hardening_dropin() {
  [[ -d "$SSHD_DROPIN_DIR" ]] || mkdir -p "$SSHD_DROPIN_DIR"

  log "Writing final override config to ${HARDEN_CONF}"

  cat > "$HARDEN_CONF" << 'EOF_INNER'
# 99-hardening.conf
# Final SSH hardening overrides for RHEL 8+ / AlmaLinux.
EOF_INNER

  {
    echo
    echo "Port ${SSH_PORT}"
    if [[ "${DISABLE_ROOT_LOGIN}" == "1" ]]; then
      echo "PermitRootLogin no"
    else
      echo "PermitRootLogin prohibit-password"
    fi

    if [[ "${DISABLE_PASSWORD_AUTH}" == "1" ]]; then
      echo "PasswordAuthentication no"
    else
      echo "PasswordAuthentication yes"
    fi

    cat <<'EOF_INNER'
ChallengeResponseAuthentication no
PubkeyAuthentication yes
EOF_INNER
  } >>"$HARDEN_CONF"
}

test_and_reload_sshd() {
  if ! command -v sshd &>/dev/null; then
    err "sshd command not found. Is OpenSSH server installed?"
    exit 1
  fi

  log "Testing sshd configuration syntax..."
  if sshd -t; then
    log "sshd configuration syntax is valid. Reloading service..."
    if systemctl reload sshd 2>/dev/null; then
      log "sshd reloaded successfully."
    else
      warn "reload failed, trying restart..."
      systemctl restart sshd
      log "sshd restarted successfully."
    fi
  else
    err "sshd configuration syntax error detected. Original configs are backed up."
    exit 1
  fi
}

show_effective_settings() {
  log "Effective sshd settings (subset):"
  if sshd -T -C user=root -C addr=127.0.0.1 -C host=localhost 2>/dev/null \
      | grep -E 'port |permitrootlogin|passwordauthentication|pubkeyauthentication'; then
    :
  else
    sshd -T 2>/dev/null | grep -E 'port |permitrootlogin|passwordauthentication|pubkeyauthentication' || true
  fi
}

main() {
  require_root
  require_rhel_like

  log "SSH_PORT=${SSH_PORT} DISABLE_ROOT_LOGIN=${DISABLE_ROOT_LOGIN} DISABLE_PASSWORD_AUTH=${DISABLE_PASSWORD_AUTH}"
  log "=== SSH hardening start ==="
  backup_sshd_config
  ensure_include_dropins

  # Comment conflicting keys everywhere else so there is no override
  comment_key_everywhere "PasswordAuthentication"
  comment_key_everywhere "PermitRootLogin"
  comment_key_everywhere "ChallengeResponseAuthentication"
  comment_key_everywhere "PubkeyAuthentication"
  # Port lines in other files should not override
  comment_key_everywhere "Port"

  # Our final override
  write_hardening_dropin
  test_and_reload_sshd
  show_effective_settings

  cat << 'INFO'

========================================================
SSH hardening applied.

Now test from a NEW terminal (keep this session open):

1) Check that password auth is REALLY disabled:

   ssh -vvv -o PreferredAuthentications=password \
           -o PubkeyAuthentication=no \
           root@YOUR_SERVER_IP

   You should NOT see "password" in:
     Authentications that can continue: ...
   And login should fail.

2) Check that your non-root user with SSH key still works:

   ssh youruser@YOUR_SERVER_IP

If both are correct:
- root login is disabled
- password authentication is disabled
- key-based auth only is enabled
========================================================
INFO

  log "=== SSH hardening finished ==="
}

main "$@"
