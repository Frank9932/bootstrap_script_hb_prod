# Secure AlmaLinux / Rocky Bootstrap

Hardens a fresh AlmaLinux/Rocky (RHEL 8/9) VPS with sane defaults: patched system, EPEL, timezone/chrony, admin user + SSH keys, SSH lock-down, firewalld baseline, Fail2ban, optional Docker, and clear orchestration.

---

## What the scripts do
- **System basics (packages installed)**:
  - `epel-release`, `chrony`, base CLI: `vim`, `nano`, `wget`, `curl`, `git`, `unzip`, `net-tools`, `htop`, `lsof`, `traceroute`, `bind-utils`, `tar` (plus `telnet` if `INSTALL_TELNET=1`).
  - Runs `dnf update -y`.
  - Sets timezone (default UTC) and enables/starts `chronyd`.
- **Root password**:
  - Generates a strong password, applies it, writes to `/root/root_emergency_password.txt` (0600).
  - Can lock root password (`LOCK_ROOT_PASSWORD=1`).
- **Admin user**:
  - Creates the admin, sets shell, adds to `wheel`.
  - Imports multiple SSH keys (env/file/interactive), sets `~/.ssh` 700 and `authorized_keys` 600.
  - Locks the admin password by default (`LOCK_ADMIN_PASSWORD=1`).
  - Ensures `/etc/sudoers.d/00-wheel-nopasswd` with `%wheel ALL=(ALL) NOPASSWD: ALL` and `Defaults:%wheel !requiretty`.
- **SSH hardening (files modified)**:
  - Backs up `/etc/ssh/sshd_config*` (once), ensures `Include /etc/ssh/sshd_config.d/*.conf`.
  - Writes `/etc/ssh/sshd_config.d/99-hardening.conf` with:
    - `Port` (from `SSH_PORT` or detected/22)
    - `PermitRootLogin no` (if `DISABLE_ROOT_LOGIN=1`, else `prohibit-password`)
    - `PasswordAuthentication no` (if `DISABLE_PASSWORD_AUTH=1`, else `yes`)
    - `ChallengeResponseAuthentication no`, `PubkeyAuthentication yes`
  - Reloads/restarts sshd after syntax check.
- **Firewall (firewalld)**:
  - Installs/enables `firewalld`.
  - Default zone: allow SSH service; open custom SSH port if set; remove other services/ports.
  - If `ENABLE_WEB=1`, also allow HTTP/HTTPS (and any `WEB_PORTS` provided).
  - Shows resulting zone config.
- **Fail2ban**:
  - Installs `fail2ban` (+ `fail2ban-firewalld` when available).
  - Writes `/etc/fail2ban/jail.d/sshd-hardening.conf` targeting the active SSH port.
  - Enables/starts `fail2ban` service (bans after 5 failures/10m for 1h using firewalld rich rules).
- **Docker (optional)**:
  - If `ENABLE_DOCKER=1`: installs Docker CE, Docker CLI, containerd, Buildx plugin, Compose plugin, and CLI tools from the module (htop, screen, curl, wget, git, nc, traceroute, net-tools, bind-utils, lsof, iotop, iftop, tar, unzip). Adds admin to `docker`, enables/starts Docker, runs `hello-world`.
- **Orchestration**:
  - `bootstrap.sh` runs all steps in order with prompts to test SSH/firewall between risky changes.

---

## Files
```
00_common.sh        Shared helpers (config loader, logging, OS guard, dnf helpers, timezone/chrony/base tools, sudoers drop-in)
01_root_password.sh Rotate root password (optional lock)
02_create_user.sh   Create admin user + SSH keys; lock password; ensure wheel NOPASSWD sudo
03_harden_sshd.sh   Harden sshd (port, root/password auth flags, drop-ins)
04_firewall.sh      Firewalld baseline (SSH only, optional web)
05_fail2ban.sh      Fail2ban SSH jail using firewalld rich rules
06_docker_tools.sh  Optional Docker install + CLI tools
bootstrap.sh        Orchestrator with safety pauses
```

---

## Quick start
```bash
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```
You’ll be prompted between critical steps to test SSH/firewall.

### Config via env or file
One-off:
```bash
SSH_PORT=2222 ADMIN_USER=alice ENABLE_WEB=1 ENABLE_DOCKER=0 sudo ./bootstrap.sh
```
Config file (auto-sourced if `bootstrap.conf` exists):
```bash
cat > bootstrap.conf <<'EOF'
ADMIN_USER=admin
ADMIN_SSH_KEYS="ssh-ed25519 AAA... alice@example
ssh-rsa BBB... bob@example"
SSH_PORT=22
DISABLE_ROOT_LOGIN=1
DISABLE_PASSWORD_AUTH=1
LOCK_ROOT_PASSWORD=1
LOCK_ADMIN_PASSWORD=1
ENABLE_WEB=0
ENABLE_DOCKER=0
TIMEZONE=UTC
EOF
sudo ./bootstrap.sh
```
Override config path with `CONFIG_FILE=/path/to/conf`.

---

## Key defaults / switches
- `RUN_DNF_UPDATE`=1 – run `dnf update -y`
- `TIMEZONE`=UTC – set via timedatectl
- `INSTALL_TELNET`=0 – add telnet to base tools
- `ADMIN_USER`=admin, `ADMIN_SHELL`=/bin/bash
- `ADMIN_SSH_KEYS` / `ADMIN_SSH_KEYS_FILE` / `SSH_PUBKEYS(_FILE)` – supply keys
- `SSH_PORT` (default detect/22)
- `DISABLE_ROOT_LOGIN`=1, `DISABLE_PASSWORD_AUTH`=1
- `LOCK_ROOT_PASSWORD`=1, `LOCK_ADMIN_PASSWORD`=1
- `ENABLE_WEB`=0, `WEB_PORTS`="80 443"
- `ROTATE_ROOT_PASSWORD`=1, `ROOT_PASSWORD`/`ROOT_PASSWORD_FILE`
- `ENABLE_DOCKER`=0, `DOCKER_USER` (defaults to ADMIN_USER/SUDO_USER)
- `CONFIG_FILE` (default `./bootstrap.conf`)

---

## After running
- Test SSH with your admin user/key on the configured port.
- Verify firewall: only SSH (plus web if enabled) is open.
- Fail2ban: `fail2ban-client status sshd`
- Docker (if enabled): `docker run --rm hello-world`

Re-running scripts is safe; drop-ins and jails are rewritten idempotently.
