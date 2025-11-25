#!/usr/bin/env bash
#
# 02_create_user.sh
# Create a new non-root user and configure SSH public key authentication.
#

source "$(dirname "$0")/00_common.sh"
require_root

main() {
  read -rp "Enter the username to create (e.g., trader): " NEW_USER

  if [[ -z "$NEW_USER" ]]; then
    err "Username cannot be empty."
    exit 1
  fi

  # Create the user if it does not already exist
  if id "$NEW_USER" &>/dev/null; then
    warn "User '$NEW_USER' already exists. Continuing..."
  else
    log "Creating user '$NEW_USER'..."
    useradd -m -s /bin/bash "$NEW_USER"

    log "Adding '$NEW_USER' to the 'wheel' group for sudo access..."
    usermod -aG wheel "$NEW_USER"
  fi

  # Prepare the .ssh directory
  local ssh_dir="/home/$NEW_USER/.ssh"
  local auth_file="${ssh_dir}/authorized_keys"

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  chown "$NEW_USER:$NEW_USER" "$ssh_dir"

  log "Paste one or more SSH public keys for user '$NEW_USER'."
  log "Accepted formats: ssh-ed25519 and ssh-rsa."
  log "Press Ctrl+D when finished."

  # Read keys from stdin into a temporary file
  TEMP_FILE="$(mktemp)"
  cat > "$TEMP_FILE"

  if [[ -s "$TEMP_FILE" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue

      # Avoid duplicate keys
      if [[ -f "$auth_file" ]] && grep -Fxq "$line" "$auth_file"; then
        warn "Duplicate key skipped: $line"
      else
        echo "$line" >> "$auth_file"
        log "Added SSH key."
      fi
    done < "$TEMP_FILE"
  else
    warn "No SSH keys were provided."
  fi

  rm -f "$TEMP_FILE"

  chmod 600 "$auth_file"
  chown "$NEW_USER:$NEW_USER" "$auth_file"

  log "User '$NEW_USER' SSH configuration completed."
  echo "You may now log in as:"
  echo "  ssh ${NEW_USER}@your_server_ip"
}

main "$@"
