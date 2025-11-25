#!/usr/bin/env bash
#
# 01_root_password.sh
# Generate a new strong emergency password for root and store it securely.
#

source "$(dirname "$0")/00_common.sh"
require_root
require_cmd openssl

main() {
  log "Generating a new strong emergency password for root..."

  # Generate a secure random base64 password (24 bytes â 32 characters)
  NEW_PASS="$(openssl rand -base64 24)"

  # Apply the new password
  echo "root:${NEW_PASS}" | chpasswd
  log "Root password updated successfully."

  # Save the emergency password securely (root-readable only)
  PASS_FILE="/root/root_emergency_password.txt"
  umask 0077
  {
    echo "New root emergency password (generated on $(date)):"
    echo "${NEW_PASS}"
  } > "$PASS_FILE"

  log "Emergency root password written to: $PASS_FILE"

  echo
  echo "==================== IMPORTANT ===================="
  echo "Your new root emergency password is:"
  echo "    ${NEW_PASS}"
  echo
  echo "This is stored in ${PASS_FILE} with strict permissions."
  echo "Keep it safe. Do NOT lose access to it."
  echo "===================================================="
}

main "$@"
