#!/usr/bin/env bash

#
# Applies common security measures for Ubuntu servers.
#
# Usage:
#   GITHUB_USERNAME=your_username ./harden.sh
#   SSH_PUBLIC_KEYS="ssh-ed25519 AAAAC3Nza... you@host" ./harden.sh
#   GITHUB_USERNAME=your_username SSH_PUBLIC_KEYS="ssh-ed25519 AAAAC3Nza... you@host" ./harden.sh
# Optional:
# - NO_REBOOT=1 (skip final reboot)
#
# Requires at least one of:
# - GITHUB_USERNAME (fetches SSH public keys from GitHub)
# - SSH_PUBLIC_KEYS (one or more newline-separated SSH public keys)
# Then adds keys to the app user's authorized_keys. Afterwards, you'll only be
# able to SSH into the server as 'app', e.g. app@1.2.3.4
#

set -e

if [ -z "${GITHUB_USERNAME}" ] && [ -z "${SSH_PUBLIC_KEYS}" ]; then
    echo "Error: You must set GITHUB_USERNAME and/or SSH_PUBLIC_KEYS."
    echo "Usage:"
    echo "  GITHUB_USERNAME=your_username $0"
    echo "  SSH_PUBLIC_KEYS=\"ssh-ed25519 AAAAC3Nza... you@host\" $0"
    echo "  GITHUB_USERNAME=your_username SSH_PUBLIC_KEYS=\"ssh-ed25519 AAAAC3Nza... you@host\" $0"
    exit 1
fi

# ---------------------------------------------------------
# Step 1: Update and upgrade system packages
# ---------------------------------------------------------

apt update -y
apt upgrade -y
apt install -y vim curl htop jq

# Configure 'needrestart' for auto-restart of services after upgrades
sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/g" /etc/needrestart/needrestart.conf

# ---------------------------------------------------------
# Step 2: Install Docker and Docker Compose
# ---------------------------------------------------------

# Update package list and install prerequisites
apt update -y
apt install -y ca-certificates curl gnupg

# Add Docker's official GPG key and set up repository
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker and Docker Compose plugins
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure host DNS via systemd-resolved (Cloudflare)
mkdir -p /etc/systemd/resolved.conf.d
cat <<EOF > /etc/systemd/resolved.conf.d/cloudflare-dns.conf
[Resolve]
DNS=1.1.1.1 1.0.0.1
EOF
systemctl restart systemd-resolved

# Configure Docker daemon DNS to avoid resolver issues inside containers
mkdir -p /etc/docker
if [ -f /etc/docker/daemon.json ]; then
    tmp_daemon_json=$(mktemp)
    jq '. + {"dns":["1.1.1.1"]}' /etc/docker/daemon.json > "$tmp_daemon_json"
    mv "$tmp_daemon_json" /etc/docker/daemon.json
else
    cat <<EOF > /etc/docker/daemon.json
{
  "dns": ["1.1.1.1"]
}
EOF
fi
systemctl restart docker

# ---------------------------------------------------------
# Step 3: Configure Virtual Memory Overcommit
# ---------------------------------------------------------

sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf

# ---------------------------------------------------------
# Step 4: Configure UFW Firewall
# ---------------------------------------------------------

sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

# ---------------------------------------------------------
# Step 5: Secure SSH Configuration
# ---------------------------------------------------------

# 1/ Enable public key authentication
# 2/ disable password-based login
# 3/ and enforce other security settings

sed -i -e '/^\(#\|\)PasswordAuthentication/s/^.*$/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)PubkeyAuthentication/s/^.*$/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i -e '/^\(#\|\)PermitEmptyPasswords/s/^.*$/PermitEmptyPasswords no/' /etc/ssh/sshd_config

if ! grep -q "^ChallengeResponseAuthentication" /etc/ssh/sshd_config; then
    echo 'ChallengeResponseAuthentication no' >> /etc/ssh/sshd_config
else
    sed -i -e '/^\(#\|\)ChallengeResponseAuthentication/s/^.*$/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
fi

echo 'Reloading ssh agent'
systemctl reload ssh

# ---------------------------------------------------------
# Step 6: Create Non-Root User with Sudo and Docker Access
# ---------------------------------------------------------

echo "Setup app user"
adduser --disabled-password --gecos "" app
echo "app ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

sudo -H -u app bash -c 'mkdir -p ~/.ssh'
sudo -H -u app bash -c 'chmod 700 ~/.ssh'

echo "Collecting SSH public keys for app user's authorized_keys"
KEYS_FILE=$(mktemp)
trap 'rm -f "$KEYS_FILE"' EXIT
touch "$KEYS_FILE"

if [ -n "${GITHUB_USERNAME}" ]; then
    echo "Fetching SSH keys from GitHub for user: $GITHUB_USERNAME"
    curl -sf "https://api.github.com/users/${GITHUB_USERNAME}/keys" | jq -r '.[].key' >> "$KEYS_FILE"
fi

if [ -n "${SSH_PUBLIC_KEYS}" ]; then
    echo "Adding SSH keys from SSH_PUBLIC_KEYS"
    printf '%s\n' "$SSH_PUBLIC_KEYS" >> "$KEYS_FILE"
fi

# Normalize and deduplicate key entries
sed -i '/^[[:space:]]*$/d' "$KEYS_FILE"
sort -u -o "$KEYS_FILE" "$KEYS_FILE"

# Validate each key format to avoid writing malformed entries
while IFS= read -r key; do
    if ! printf '%s' "$key" | grep -Eq '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ecdsa-sha2-nistp256@openssh\.com|sk-ssh-ed25519@openssh\.com) [A-Za-z0-9+/=]+([[:space:]].*)?$'; then
        echo "Error: Invalid SSH public key format detected:"
        echo "$key"
        exit 1
    fi
done < "$KEYS_FILE"

if [ ! -s "$KEYS_FILE" ]; then
    echo "Error: No SSH public keys found from the provided inputs."
    exit 1
fi

sudo -H -u app bash -c 'touch ~/.ssh/authorized_keys'
sudo -H -u app bash -c 'chmod 600 ~/.ssh/authorized_keys'
cp "$KEYS_FILE" /home/app/.ssh/authorized_keys
chown app:app /home/app/.ssh/authorized_keys
chmod 600 /home/app/.ssh/authorized_keys

# Add app user to Docker group
usermod -aG docker app

# ---------------------------------------------------------
# Step 7: Install and Configure fail2ban
# ---------------------------------------------------------

echo "Setup fail2ban"
apt install -y fail2ban

cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 5
findtime = 600
bantime = 600
ignoreip = 127.0.0.1/8
logpath = /var/log/auth.log
EOF

systemctl restart fail2ban

# ---------------------------------------------------------
# Step 8: Secure Shared Memory
# ---------------------------------------------------------

echo "Secure shared memory"
echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab

# ---------------------------------------------------------
# Step 9: Disable Root User Login
# ---------------------------------------------------------

echo "Disable root user login"
sed -i -e '/^\(#\|\)PermitRootLogin/s/^.*$/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl reload ssh

# ---------------------------------------------------------
# Step 10: Reboot to Apply Changes
# ---------------------------------------------------------

echo "Rebooting so changes can take effect"
if [ "${NO_REBOOT}" = "1" ] || [ "${NO_REBOOT}" = "true" ] || [ "${NO_REBOOT}" = "yes" ]; then
    echo "NO_REBOOT is set; skipping reboot."
else
    reboot
fi
