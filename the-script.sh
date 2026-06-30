#!/bin/bash

set -e

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Failed to detect operating system"
    exit 1
fi

case "$OS" in
    ubuntu|debian)
        PKG_MANAGER="apt"
        LOG_PATH="/var/log/auth.log"
        SSH_SERVICE="ssh"
        ;;
    centos|rocky|almalinux|rhel)
        PKG_MANAGER="dnf"
        LOG_PATH="/var/log/secure"
        SSH_SERVICE="sshd"
        ;;
    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

echo "Detected OS: $OS"
echo "Package manager: $PKG_MANAGER"

# Update system
echo "Updating system..."
if [ "$PKG_MANAGER" = "apt" ]; then
    apt update
    apt upgrade -y
    apt install -y fail2ban wget
else
    dnf update -y
    dnf install -y fail2ban wget
fi

# Configure fail2ban
echo "Configuring fail2ban..."
cat > /etc/fail2ban/jail.d/sshd.conf << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = $LOG_PATH
maxretry = 5
findtime = 600
bantime = 3600
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# Install Xray
echo "Installing Xray..."
cd ~
wget https://github.com/XTLS/Xray-install/raw/main/install-release.sh
bash install-release.sh
rm install-release.sh
systemctl enable xray
systemctl start xray

# Change root password
echo "Changing root password..."
read -sp "Enter new password for root: " ROOT_PASSWORD
echo
passwd root << EOF
$ROOT_PASSWORD
$ROOT_PASSWORD
EOF

# Create new user
echo "Creating new user..."
read -p "Enter login for new user: " NEW_USER
useradd -m -s /bin/bash "$NEW_USER"

read -sp "Enter password for $NEW_USER: " NEW_USER_PASSWORD
echo
passwd "$NEW_USER" << EOF
$NEW_USER_PASSWORD
$NEW_USER_PASSWORD
EOF

# Disable root SSH login
echo "Disabling root SSH login..."
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart "$SSH_SERVICE"

# Final message
echo ""
echo "Setup complete!"
echo "Created user: $NEW_USER"
echo "Fail2ban configured and running"
echo "Xray installed and running"
echo "Root SSH login disabled"
echo ""
echo "Don't forget:"
echo "1. Add your config for Xray to /usr/local/etc/xray/config.json"
echo "2. Reconnect to server as user $NEW_USER"