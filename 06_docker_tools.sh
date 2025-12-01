#!/usr/bin/env bash
#
# 06_docker_tools.sh
# Install common tools + Docker CE + Docker Compose plugin on AlmaLinux / RHEL 8+.
#
# Goals:
# - Install basic CLI utilities (htop, screen, network tools, etc.)
# - Configure Docker CE repo and install Docker + Compose plugin
# - Enable and start Docker service
# - Add a non-root user to the docker group
# - Run a simple test container (hello-world)
#

set -euo pipefail

source "$(dirname "$0")/00_common.sh"

DOCKER_REPO_URL="https://download.docker.com/linux/centos/docker-ce.repo"
ENABLE_DOCKER="${ENABLE_DOCKER:-0}"
DOCKER_USER="${DOCKER_USER:-${ADMIN_USER:-}}"

install_cli_tools() {
  log "Installing common CLI tools..."
  ensure_packages \
    htop screen \
    curl wget git \
    nc traceroute \
    net-tools bind-utils \
    lsof iotop iftop \
    tar unzip
}

configure_docker_repo() {
  log "Configuring Docker CE repository..."
  # Install dnf-plugins-core if not present
  ensure_package dnf-plugins-core

  # If the repo already exists, don't add it again
  if ! grep -q "docker-ce-stable" /etc/yum.repos.d/*.repo 2>/dev/null; then
    dnf config-manager --add-repo "${DOCKER_REPO_URL}"
    log "Docker CE repo added: ${DOCKER_REPO_URL}"
  else
    log "Docker CE repo already configured."
  fi
}

install_docker() {
  log "Installing Docker CE and related components..."
  dnf install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  log "Enabling and starting Docker service..."
  systemctl enable --now docker

  if ! systemctl is-active docker &>/dev/null; then
    err "Docker service is not active after start attempt."
    exit 1
  fi
}

choose_docker_user() {
  # Prefer SUDO_USER if available and not root.
  if [[ -n "${DOCKER_USER}" ]]; then
    echo "${DOCKER_USER}"
    return 0
  fi

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    echo "${SUDO_USER}"
    return 0
  fi

  # Otherwise, ask explicitly.
  local user
  read -rp "Enter the username to add to 'docker' group (non-root): " user
  echo "${user}"
}

add_user_to_docker_group() {
  local user
  user="$(choose_docker_user)"

  if [[ -z "${user}" ]]; then
    warn "No username provided. Skipping docker group membership."
    return
  fi

  if ! id "${user}" &>/dev/null; then
    err "User '${user}' does not exist. Please create it first (e.g., via 02_create_user.sh)."
    return
  fi

  if id -nG "${user}" | grep -qw docker; then
    log "User '${user}' is already in the 'docker' group."
  else
    log "Adding user '${user}' to 'docker' group..."
    usermod -aG docker "${user}"
    log "User '${user}' added to 'docker' group. They must re-login for group changes to take effect."
  fi
}

test_docker() {
  log "Testing Docker with hello-world container..."
  if docker run --rm hello-world >/dev/null 2>&1; then
    log "Docker hello-world test succeeded."
  else
    warn "Docker hello-world test failed. Check 'docker ps -a' and 'journalctl -u docker' for details."
  fi
}

main() {
  require_root
  require_rhel_like

  if [[ "${ENABLE_DOCKER}" != "1" ]]; then
    log "ENABLE_DOCKER=${ENABLE_DOCKER}; skipping Docker installation."
    return 0
  fi

  log "=== Docker + tools installation start ==="

  install_cli_tools
  configure_docker_repo
  install_docker
  add_user_to_docker_group
  test_docker

  cat << 'INFO'

========================================================
Docker + tools setup completed.

- Common CLI tools installed (htop, screen, curl, traceroute, etc.).
- Docker CE and Docker Compose plugin installed.
- Docker service is enabled and running.
- A non-root user has been added to the 'docker' group (or was already in it).

IMPORTANT:
- The user added to the 'docker' group must log out and log back in
  for the new group membership to take effect.
- From that user's shell, you should be able to run:

    docker ps
    docker run --rm hello-world

SECURITY NOTE:
- At this point, your firewall (firewalld) only exposes SSH from outside.
- Docker containers will not be reachable from the Internet unless you
  explicitly publish ports (and optionally open them in firewalld).
- This is the desired baseline for a secure, Docker-heavy trading host.
========================================================
INFO

  log "=== Docker + tools installation finished ==="
}

main "$@"
