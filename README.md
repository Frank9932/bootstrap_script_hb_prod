# Secure AlmaLinux Server Bootstrap

A complete, modular, idempotent hardening and provisioning toolkit for
fresh **AlmaLinux / RHEL 8+** servers.

This toolkit is designed for **operators and power-users**, especially those
deploying **Docker-heavy workloads** (e.g., algorithmic trading bots,
self-hosted services, automation systems) while maintaining a strongly
locked-down baseline security posture.

---

## ð Features

This bootstrap system provides:

### **1. Secure SSH**
- Strong emergency root password rotation
- Non-root user creation with SSH key authentication only
- Root login disabled
- Password login disabled
- Enforced drop-in configuration using `sshd_config.d/`

### **2. Firewall Baseline (firewalld)**
- Only SSH exposed to the Internet
- All other services/ports removed
- Supports custom SSH ports
- Idempotent configuration

### **3. Fail2ban Protection**
- Protects SSH from brute-force attacks
- Uses firewall rich rules (`firewallcmd-rich-rules`)
- Config in `/etc/fail2ban/jail.d/`
- Safe to run multiple times

### **4. Docker + Tools Setup**
- Installs Docker CE, CLI, Buildx, and Compose plugin
- Installs common CLI utilities (htop, git, traceroute, etc.)
- Adds your non-root user to the `docker` group
- Runs a test container to validate Docker installation

### **5. Reliable Orchestration**
- A top-level `bootstrap.sh` that:
  - Runs modules in the correct order
  - Pauses for safety checks after risky changes
  - Ensures you never lock yourself out of SSH
  - Makes all scripts executable automatically

---

## ð Directory Structure

bootstrap/
âââ 00_common.sh
âââ 01_root_password.sh
âââ 02_create_user.sh
âââ 03_harden_sshd.sh
âââ 04_firewall.sh
âââ 05_fail2ban.sh
âââ 06_docker_tools.sh
âââ bootstrap.sh

yaml
Copy code

`bootstrap.sh` calls each script in order.

---

## ð Quick Start

### 1. Upload files to your server:

```bash
mkdir -p ~/bootstrap
cd ~/bootstrap
# Upload scripts into this directory
2. Make the bootstrap executable:
bash
Copy code
chmod +x bootstrap.sh
3. Run the bootstrap:
bash
Copy code
sudo ./bootstrap.sh
4. Follow prompts carefully
The bootstrap will request confirmation before:

Hardening SSH

Reloading SSH configuration

Enabling firewalld

Applying firewall rules

Proceeding after each critical step

It will always remind you to test SSH from a new terminal before continuing.

ð¡ Safety Philosophy
The system is engineered to avoid accidental lockouts:

SSH changes always pause for validation.

firewalld changes always pause for external connectivity checks.

bootstrap.sh will not continue unless you explicitly confirm.

Every module is idempotent:

Re-running scripts will not duplicate settings

Drop-in configs are overwritten cleanly

No inconsistent/fragmented state

ð§ Individual Modules
00_common.sh
Shared helper functions (logging, root checks, command checks).

01_root_password.sh
Rotates rootâs emergency password and stores it in:

bash
Copy code
/root/root_emergency_password.txt
Permission restricted to root only.

02_create_user.sh
Guides you to:

Choose a username

Paste one or more SSH public keys

Sets up .ssh/authorized_keys

Adds user to wheel for sudo

03_harden_sshd.sh
Ensures Include /etc/ssh/sshd_config.d/*.conf

Comments conflicting parameters in all other configs

Creates 99-hardening.conf with final overrides:

PermitRootLogin no

PasswordAuthentication no

ChallengeResponseAuthentication no

PubkeyAuthentication yes

Reloads SSH safely after syntax validation

04_firewall.sh
Installs & enables firewalld

Detects your actual SSH port using sshd -T

Allows only the SSH service/port

Removes all other services from the default zone

Reloads and prints the active config

05_fail2ban.sh
Installs EPEL + fail2ban

Creates /etc/fail2ban/jail.d/sshd-hardening.conf

Bans after:

5 failures

within 10 minutes

ban lasts 1 hour

Integrated with firewalld rich rules

06_docker_tools.sh
Inhe Docker service

Adds your non-root user to the docker group

Runs docker run hello-world as validation

ð After Bootstrapping
As your non-root user:

bash
Copy code
docker ps
docker run --rm hello-world
Deploying services securely
Expose container ports only when needed

Use firewalld to explicitly allow each one

Avoid --privileged containers

Prefer network isolation (user-defined Docker networks)

A clean, minimal attack surface is ideal for:

Algorithmic trading bots

API services

Monitoring agents

Local data pipelines

ð§ª Idempotency and Testing
Each module can be executed independently:

bash
Copy code
sudo ./03_harden_sshd.sh
sudo ./04_firewall.sh
sudo ./05_fail2ban.sh
sudo ./06_docker_tools.sh
Re-running modules:

Does not break configurations

Does not create duplicate entries

Updates configs safely

ð Future Extensions (Optional)
You may extend the toolkit with additional modules:

Automatic Docker backup system

Daily log rotation & cleanup

System monitoring with Prometheus node_exporter

Swap optimization

Kernel tuning for network performance

Automatic unattended upgrades

I can generate these modules on request.

ð Conclusion
This bootstrap system transforms a fresh AlmaLinux/RHEL server into a:

Strongly secured

Minimal exposure

Docker-ready

Operator-friendly
environment.

Perfect for self-hosting, operations engineering, and quantitative trading workloads.

