# VPS Auto Setup Script

Automatic script for initial VPS setup for VPN based on Xray with VLESS + Reality protocol.

## What the script does

*   Checks that it is run as root
*   Detects the operating system (Ubuntu/Debian or CentOS/Rocky/AlmaLinux)
*   Updates the system and installs required packages (fail2ban, wget, jq, openssl)
*   Configures fail2ban to protect SSH from brute-force attacks
*   Installs the latest version of Xray
*   Generates keys for the Reality protocol (PrivateKey and PublicKey)
*   Creates a basic Xray configuration file with VLESS + Reality on port 443
*   Prompts for and sets a new password for root
*   Creates a new regular user without sudo privileges
*   Disables SSH login for the root user
*   Displays client setup information (PublicKey, ShortID, port, SNI)

## Requirements

*   Freshly installed VPS with Ubuntu 20.04+, Debian 11+, CentOS 8+, Rocky Linux, or AlmaLinux
*   SSH access as root
*   Minimum 512 MB RAM

## Usage

Download the script to your VPS:

`wget https://raw.githubusercontent.com/vpupkin123/The-Script/main/the-script.sh`

Make it executable:

`chmod +x the-script.sh`

Run as root:

`./the-script.sh`

The script will ask a few questions:

*   New password for root
*   Login for the new user
*   Password for the new user

## Xray User Management

After installation, use the separate `xray.sh` script to manage clients:

*   `./xray.sh add <username>` — add a user
*   `./xray.sh del <username>` — remove a user
*   `./xray.sh list` — list users
*   `./xray.sh link <username>` — get client link
*   `./xray.sh help` — help

## Configuration features

The script creates a VLESS + Reality configuration with the following parameters:

*   Protocol: VLESS with xtls-rprx-vision flow
*   Port: 443
*   Masking: traffic simulates a connection to cloudflare.com
*   Automatic generation of unique keys on each run

## Security

*   SSH access for root is disabled
*   Fail2ban blocks IP after 5 failed login attempts within 10 minutes for 1 hour
*   The new user is created without sudo privileges

## License

MIT