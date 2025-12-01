#!/usr/bin/env bash
#
# 01_root_password.sh
# Generate a new strong emergency password for root and store it securely.
# Supports non-interactive usage via env:
#   ROTATE_ROOT_PASSWORD=0   -> skip rotation
#   ROOT_PASSWORD            -> pre-provided password (otherwise random)
#   ROOT_PASSWORD_FILE       -> where to store the password (default /root/root_emergency_password.txt)
#

source "$(dirname "$0")/00_common.sh"
require_root
require_rhel_like
require_cmd openssl

ROTATE_ROOT_PASSWORD="${ROTATE_ROOT_PASSWORD:-1}"
ROOT_PASSWORD_FILE="${ROOT_PASSWORD_FILE:-/root/root_emergency_password.txt}"

generate_password() {
  if [[ -n "${ROOT_PASSWORD:-}" ]]; then
    echo "${ROOT_PASSWORD}"
  else
    # Secure random base64 password (24 bytes ≈ 32 chars)
    openssl rand -base64 24
  fi
}

main() {
  if [[ "${ROTATE_ROOT_PASSWORD}" != "1" ]]; then
    warn "ROTATE_ROOT_PASSWORD=${ROTATE_ROOT_PASSWORD}; skipping root password rotation."
    return 0
  fi

  log "Generating a new strong emergency password for root..."
  NEW_PASS="$(generate_password)"

  echo "root:${NEW_PASS}" | chpasswd
  log "Root password updated successfully."

  umask 0077
  {
    echo "New root emergency password (generated on $(date)):"
    echo "${NEW_PASS}"
  } > "$ROOT_PASSWORD_FILE"

  log "Emergency root password written to: $ROOT_PASSWORD_FILE"

  cat <<EOF

==================== IMPORTANT ====================
Your new root emergency password is:
    ${NEW_PASS}

This is stored in ${ROOT_PASSWORD_FILE} with strict permissions.
Keep it safe. Do NOT lose access to it.
====================================================
EOF
}

main "$@"
