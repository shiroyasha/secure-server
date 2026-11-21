# Secure (Ubuntu) Server

Harden an Ubuntu server. 

- 🔒 Disable root login and password authentication for SSH.
- 🔒 Set up a non-root `app` user with sudo privileges.
- 🔒 Install and configure UFW firewall.
- 🔒 Configure UFW forwarding plus host and Docker DNS (Cloudflare).
- 🔒 Install and configure fail2ban to protect against brute-force attacks.
- 🔒 Set up SSH key authentication using GitHub keys, provided public keys, or both.

## Usage

#### 1/ SSH into your server as root

```bash
ssh root@your-server-ip
```

#### 2/ Run one command (choose one flow, or both).

```bash
# Flow A: use GitHub username
curl -fsSL https://raw.githubusercontent.com/shiroyasha/secure-server/main/harden.sh | GITHUB_USERNAME=your_username bash

# Flow B: provide one or more public keys directly
curl -fsSL https://raw.githubusercontent.com/shiroyasha/secure-server/main/harden.sh | SSH_PUBLIC_KEYS='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your@host' bash

# Flow C: combine both
curl -fsSL https://raw.githubusercontent.com/shiroyasha/secure-server/main/harden.sh | GITHUB_USERNAME=your_username SSH_PUBLIC_KEYS='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your@host' bash

# Optional: disable reboot at the end of the script
curl -fsSL https://raw.githubusercontent.com/shiroyasha/secure-server/main/harden.sh | NO_REBOOT=1 GITHUB_USERNAME=your_username bash
```

#### 3/ Use your new `app` user to SSH into your server.

```bash
ssh app@your-server-ip
```
