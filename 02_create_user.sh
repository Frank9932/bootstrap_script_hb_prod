#!/usr/bin/env bash
#
# 02_create_user.sh
# Create a new non-root user and configure SSH public key authentication.
# Configurable via env / bootstrap.conf:
#   ADMIN_USER         - username to create (default: admin; empty = prompt)
#   ADMIN_SHELL        - login shell (default: /bin/bash)
#   ADMIN_SSH_KEYS     - multiline env var with one or more public keys
#   ADMIN_SSH_KEYS_FILE- file containing one or more public keys
#   SSH_PUBKEYS / SSH_PUBKEYS_FILE are also accepted aliases.
#

set -euo pipefail

source "$(dirname "$0")/00_common.sh"
require_root
require_rhel_like

ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_SHELL="${ADMIN_SHELL:-/bin/bash}"
ADMIN_SSH_KEYS="${ADMIN_SSH_KEYS:-${SSH_PUBKEYS:-}}"
ADMIN_SSH_KEYS_FILE="${ADMIN_SSH_KEYS_FILE:-${SSH_PUBKEYS_FILE:-}}"

prompt_for_username() {
  local name
  read -rp "Enter the username to create (e.g., trader): " name
  echo "$name"
}

ensure_user_exists() {
  local user="$1"
  if id "$user" &>/dev/null; then
    warn "User '$user' already exists. Continuing..."
  else
    log "Creating user '$user'..."
    useradd -m -s "$ADMIN_SHELL" "$user"
    log "Adding '$user' to the 'wheel' group for sudo access..."
    usermod -aG wheel "$user"
  fi
}

collect_keys() {
  local dest_tmp="$1"

  # From file, if provided
  if [[ -n "$ADMIN_SSH_KEYS_FILE" && -f "$ADMIN_SSH_KEYS_FILE" ]]; then
    cat "$ADMIN_SSH_KEYS_FILE" >>"$dest_tmp"
  fi

  # From env multiline variable
  if [[ -n "$ADMIN_SSH_KEYS" ]]; then
    printf '%s\n' "$ADMIN_SSH_KEYS" >>"$dest_tmp"
  fi

  # From interactive input if still empty
  if [[ ! -s "$dest_tmp" ]]; then
    log "Paste one or more SSH public keys for the admin user."
    log "Accepted formats: ssh-ed25519 and ssh-rsa."
    log "Press Ctrl+D when finished."
    cat >>"$dest_tmp"
  fi
}

install_keys() {
  local user="$1" tmp="$2"
  local ssh_dir="/home/$user/.ssh"
  local auth_file="${ssh_dir}/authorized_keys"

  ensure_dirs_permissions "$ssh_dir" 700 "${user}:${user}"
  touch "$auth_file"

  if [[ -s "$tmp" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue

      if [[ -f "$auth_file" ]] && grep -Fxq "$line" "$auth_file"; then
        warn "Duplicate key skipped: $line"
      else
        echo "$line" >>"$auth_file"
        log "Added SSH key for ${user}."
      fi
    done <"$tmp"
  else
    warn "No SSH keys were provided."
  fi

  chmod 600 "$auth_file"
  chown "$user:$user" "$auth_file"
}

main() {
  local user="${ADMIN_USER}"
  [[ -z "$user" ]] && user="$(prompt_for_username)"

  if [[ -z "$user" ]]; then
    err "Username cannot be empty."
    exit 1
  fi

  ensure_user_exists "$user"

  TEMP_FILE="$(mktemp)"
  collect_keys "$TEMP_FILE"
  install_keys "$user" "$TEMP_FILE"
  rm -f "$TEMP_FILE"

  log "User '$user' SSH configuration completed."
  echo "You may now log in as:"
  echo "  ssh ${user}@your_server_ip"
}

main "$@"
