# Secure AlmaLinux Server Bootstrap

A complete, modular, idempotent hardening and provisioning toolkit for fresh **AlmaLinux / RHEL 8+** servers.

Designed for **operators and power-users**, especially those deploying **Docker-heavy workloads** (e.g., algorithmic trading bots, self-hosted services, automation systems) while maintaining a strongly locked-down baseline security posture.

---

## 🔐 What it does
- Runs `dnf update`, installs EPEL, chrony, timezone, and base CLI tools.
- Rotates the emergency root password (stored in `/root/root_emergency_password.txt`).
- Creates a primary admin user with multiple SSH keys, adds it to `wheel`.
- Hardens SSH: drop-in config, custom port, optional root/password login disable.
- Firewalld baseline: open only SSH (plus HTTP/HTTPS if enabled), remove everything else.
- Fail2ban: sane SSH jail, uses firewalld rich rules, respects custom SSH port.
- Optional Docker: install Docker CE/CLI/Buildx/Compose and add your user to `docker`.
- Orchestration with safety pauses so you don’t lock yourself out.

---

## 🗂 Directory Structure

```
bootstrap/
├── 00_common.sh
├── 01_root_password.sh
├── 02_create_user.sh
├── 03_harden_sshd.sh
├── 04_firewall.sh
├── 05_fail2ban.sh
├── 06_docker_tools.sh
└── bootstrap.sh
```

`bootstrap.sh` calls each script in order and handles safety pauses.

---

## 🚀 Quick Start

1) Upload files to your server:
```bash
mkdir -p ~/bootstrap
cd ~/bootstrap
# Upload scripts into this directory
```

2) Make the bootstrap executable:
```bash
chmod +x bootstrap.sh
```

3) Run the bootstrap:
```bash
sudo ./bootstrap.sh
```

4) Follow prompts carefully. The bootstrap will request confirmation before:
- Hardening SSH
- Reloading SSH configuration
- Enabling firewalld
- Applying firewall rules
- Proceeding after each critical step

It will remind you to test SSH from a new terminal before continuing.

Run with environment overrides or a config file:
```bash
# One-off overrides
SSH_PORT=2222 ADMIN_USER=alice ENABLE_WEB=1 sudo ./bootstrap.sh

# Or create an optional config file (auto-sourced if present)
cat > bootstrap.conf <<'EOF'
ADMIN_USER=admin
SSH_PORT=22
DISABLE_ROOT_LOGIN=1
DISABLE_PASSWORD_AUTH=1
ENABLE_WEB=0
ENABLE_DOCKER=0
ADMIN_SSH_KEYS="ssh-ed25519 AAA... user@example
ssh-rsa BBB... user2@example"
TIMEZONE=UTC
EOF
```
You can also set `CONFIG_FILE=/path/to/conf` to point at another config file.

---

## 🛡 Safety Philosophy

Engineered to avoid accidental lockouts:
- SSH changes pause for validation
- firewalld changes pause for external connectivity checks
- `bootstrap.sh` will not continue unless you explicitly confirm

Every module is idempotent:
- Re-running scripts will not duplicate settings
- Drop-in configs are overwritten cleanly
- No inconsistent/fragmented state

---

## 🛠 Individual Modules

### 00_common.sh
Shared helpers (logging, OS guard, package install wrapper, config loader, timezone/chrony setup, base tools).

### 01_root_password.sh
Rotates root’s emergency password and stores it in:
```bash
/root/root_emergency_password.txt
```
Permission is restricted to root only.
Env: `ROTATE_ROOT_PASSWORD=0` to skip; `ROOT_PASSWORD` to provide your own.

### 02_create_user.sh
Creates a primary admin user, adds to `wheel`, and loads multiple SSH keys from:
- `ADMIN_SSH_KEYS` (multiline env), `ADMIN_SSH_KEYS_FILE` (file), or interactive paste.
Permissions: `~/.ssh` 700, `authorized_keys` 600, owned by the user.
Env: `ADMIN_USER` (default `admin`), `ADMIN_SHELL` (default `/bin/bash`).

### 03_harden_sshd.sh
Enforces drop-in config, comments conflicting directives elsewhere, writes `99-hardening.conf` with:
- `Port` (from `SSH_PORT`, default 22)
- `PermitRootLogin` (`DISABLE_ROOT_LOGIN=1` => `no`, else `prohibit-password`)
- `PasswordAuthentication` (`DISABLE_PASSWORD_AUTH=1` => `no`, else `yes`)
- `ChallengeResponseAuthentication no`, `PubkeyAuthentication yes`

Reloads SSH safely after syntax validation.

### 04_firewall.sh
Installs/enables firewalld, opens only SSH (uses `SSH_PORT` or detected port). Removes other services/ports. If `ENABLE_WEB=1`, opens HTTP/HTTPS (custom `WEB_PORTS` allowed).

### 05_fail2ban.sh
Installs EPEL + fail2ban, creates `/etc/fail2ban/jail.d/sshd-hardening.conf` for your SSH port, bans after 5 failures within 10 minutes for 1 hour, and integrates with firewalld rich rules.

### 06_docker_tools.sh
Optional (ENABLE_DOCKER=1): installs Docker CE/CLI/Buildx/Compose + CLI utilities, adds your admin user to `docker`, runs `hello-world` test.

---

## 🔍 After Bootstrapping

As your non-root user:
```bash
docker ps
docker run --rm hello-world
```

Deploy services securely:
- Expose container ports only when needed
- Use firewalld to explicitly allow each one
- Avoid `--privileged` containers
- Prefer network isolation (user-defined Docker networks)

---

## 🧪 Idempotency and Testing

Each module can be executed independently:
```bash
sudo ./03_harden_sshd.sh
sudo ./04_firewall.sh
sudo ./05_fail2ban.sh
sudo ./06_docker_tools.sh
```

Re-running modules:
- Does not break configurations
- Does not create duplicate entries
- Updates configs safely

---

## 📚 Future Extensions (Optional)

You may extend the toolkit with additional modules:
- Automatic Docker backup system
- Daily log rotation & cleanup
- System monitoring with Prometheus node_exporter
- Swap optimization
- Kernel tuning for network performance
- Automatic unattended upgrades

---

## ⚙️ Configuration (env vars or `bootstrap.conf`)
- `RUN_DNF_UPDATE` (default `1`) – run `dnf update -y`.
- `TIMEZONE` (default `UTC`) – set with `timedatectl`.
- `INSTALL_TELNET` (default `0`) – add telnet to base tools.
- `ADMIN_USER` (default `admin`) – primary admin username.
- `ADMIN_SHELL` (default `/bin/bash`) – login shell.
- `ADMIN_SSH_KEYS` – multiline public keys.
- `ADMIN_SSH_KEYS_FILE` – file with public keys.
- `SSH_PUBKEYS` / `SSH_PUBKEYS_FILE` – aliases for the above.
- `SSH_PORT` (default detect/22) – SSH listen port.
- `DISABLE_ROOT_LOGIN` (default `1`) – set `PermitRootLogin no`.
- `DISABLE_PASSWORD_AUTH` (default `1`) – set `PasswordAuthentication no`.
- `ENABLE_WEB` (default `0`) – open HTTP/HTTPS in firewalld.
- `WEB_PORTS` (default `80 443`) – extra web ports to open when `ENABLE_WEB=1`.
- `ROTATE_ROOT_PASSWORD` (default `1`) – skip with `0`; `ROOT_PASSWORD` to supply your own.
- `ENABLE_DOCKER` (default `0`) – install Docker when `1`.
- `DOCKER_USER` (default `ADMIN_USER` or `SUDO_USER`) – user to add to `docker`.
- `CONFIG_FILE` – override path to config (default `./bootstrap.conf`).

Set them in the environment or place them in `bootstrap.conf` (auto-sourced by all scripts).

---

## 🎉 Conclusion

This bootstrap system transforms a fresh AlmaLinux/RHEL server into a:
- Strongly secured
- Minimal exposure
- Docker-ready
- Operator-friendly environment

Perfect for self-hosting, operations engineering, and quantitative trading workloads.
