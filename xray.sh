#!/bin/bash

# === CONFIGURATION ===
CONFIG_FILE="/usr/local/etc/xray/config.json"
CLIENTS_DIR="$HOME/clients"
ASK_RESTART=true  # 🔹 Whether to ask before restarting

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "\033[0;31mError: Config not found at $CONFIG_FILE\033[0m"
    exit 1
fi

# 🔹 Create clients folder if it doesn't exist
mkdir -p "$CLIENTS_DIR" 2>/dev/null || {
    echo -e "\033[0;31mError: no permissions to create $CLIENTS_DIR\033[0m"
    exit 1
}

show_help() {
    echo "Usage:"
    echo "  $0 <command> [arguments]"
    echo "  $0 <username> <link|conf>   (or $0 <link|conf> <username>)"
    echo ""
    echo "Commands:"
    echo "  add <username>    Add a new user"
    echo "  del <username>    Delete a user"
    echo "  list              List all users (names)"
    echo "  link <username>   Generate link for an existing user"
    echo "  conf <username>   Show connection config (Hiddify/Happ/v2rayNG)"
    echo "  help              Show this help"
}

list_users() {
    echo -e "\033[0;32mUser list:\033[0m"
    jq -r '.inbounds[0].settings.clients[] | .email // "No name"' "$CONFIG_FILE" | nl
}

restart_xray() {
    if [ "$ASK_RESTART" = true ]; then
        read -p "🔄 Restart Xray service? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "\033[0;33m⚠️  Xray service not restarted. Changes will take effect after a manual restart.\033[0m"
            return 1
        fi
    fi
    systemctl restart xray 2>/dev/null || service xray restart 2>/dev/null
    echo -e "\033[0;32m✅ Xray restarted\033[0m"
}

# Function to save client parameters to a file
save_client_config() {
    local USERNAME="$1"
    local LINK="$2"
    local UUID="$3"
    local PUBLIC_KEY="$4"
    local FILE="${CLIENTS_DIR}/${USERNAME}.txt"

    cat > "$FILE" <<EOF
=== Xray Reality Client: $USERNAME ===
Creation date: $(date '+%Y-%m-%d %H:%M:%S')

🔗 VLESS link (for import to v2rayNG/Hiddify):
$LINK

📋 Parameters for manual setup:
  UUID:       $UUID
  Address:    $(curl -s ifconfig.me)
  Port:       $(jq -r '.inbounds[0].port' "$CONFIG_FILE")
  SNI:        $(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
  ShortID:    $(jq -r --arg u "$USERNAME" '.inbounds[0].settings.clients[] | select(.email == $u) | .shortId' "$CONFIG_FILE")
  PublicKey:  $PUBLIC_KEY
  Flow:       xtls-rprx-vision
  FP:         safari
  Network:    tcp

⚠️  This file contains sensitive data — store in a safe place!
EOF
    chmod 600 "$FILE" 2>/dev/null
    echo -e "\033[0;32m📄 Config saved: $FILE\033[0m"
}

# 🔹 Function to generate a link for an existing user
show_link() {
    local USERNAME="$1"

    if [ -z "$USERNAME" ]; then
        echo -e "\033[0;31mError: please specify a username\033[0m"
        echo "Usage: $0 link <username>"
        exit 1
    fi

    local USER_DATA=$(jq -r --arg u "$USERNAME" '.inbounds[0].settings.clients[] | select(.email == $u)' "$CONFIG_FILE")
    if [ -z "$USER_DATA" ] || [ "$USER_DATA" = "null" ]; then
        echo -e "\033[0;31mError: user '$USERNAME' not found\033[0m"
        exit 1
    fi

    local UUID=$(echo "$USER_DATA" | jq -r '.id')
    local SHORT_ID=$(echo "$USER_DATA" | jq -r '.shortId // empty')
    local PORT=$(jq -r '.inbounds[0].port' "$CONFIG_FILE")
    local SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
    local SERVER_IP=$(curl -s ifconfig.me)
    local PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")
    
    X25519_OUTPUT=$(xray x25519 -i "$PRIVATE_KEY" 2>&1)
    PUBLIC_KEY=$(echo "$X25519_OUTPUT" | awk '/Password \(PublicKey\):/ {print $3}')

    local LINK="vless://${UUID}@${SERVER_IP}:${PORT}?type=tcp&security=reality&sni=${SNI}&fp=safari&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${USERNAME}"

    echo -e "\033[0;32m🔗 Link for user '$USERNAME':\033[0m"
    echo ""
    echo "$LINK"
    echo ""
}

add_user() {
    local USERNAME="$1"

    if [ -z "$USERNAME" ]; then
        echo -e "\033[0;31mError: please specify a username\033[0m"
        echo "Usage: $0 add <username>"
        exit 1
    fi

    # Check for duplicate
    EXISTS=$(jq -r --arg u "$USERNAME" '.inbounds[0].settings.clients[] | select(.email == $u)' "$CONFIG_FILE")
    if [ -n "$EXISTS" ] && [ "$EXISTS" != "null" ]; then
        echo -e "\033[0;31mError: user '$USERNAME' already exists\033[0m"
        exit 1
    fi

    UUID=$(xray uuid)
    
    # 🔹 Generate unique ShortID
    NEW_SHORT_ID=$(openssl rand -hex 8)

    # Safe editing
    TEMP=$(mktemp)
    
    # 1. Add new ShortID to the global shortIds array
    jq --arg sid "$NEW_SHORT_ID" '.inbounds[0].streamSettings.realitySettings.shortIds += [$sid]' "$CONFIG_FILE" > "$TEMP" && cat "$TEMP" > "$CONFIG_FILE" && rm "$TEMP"
    
    TEMP=$(mktemp)
    # 2. Add user (save shortId in client object for correct deletion)
    jq --arg uuid "$UUID" --arg user "$USERNAME" --arg sid "$NEW_SHORT_ID" \
       '.inbounds[0].settings.clients += [{"id": $uuid, "flow": "xtls-rprx-vision", "level": 0, "email": $user, "shortId": $sid}]' \
       "$CONFIG_FILE" > "$TEMP" && cat "$TEMP" > "$CONFIG_FILE" && rm "$TEMP"

    # Dynamic parameter extraction
    SERVER_IP=$(curl -s ifconfig.me)
    PORT=$(jq -r '.inbounds[0].port' "$CONFIG_FILE")
    SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
    PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")
    
    # Original Public Key parsing
    X25519_OUTPUT=$(xray x25519 -i "$PRIVATE_KEY" 2>&1)
    PUBLIC_KEY=$(echo "$X25519_OUTPUT" | awk '/Password \(PublicKey\):/ {print $3}')

    LINK="vless://${UUID}@${SERVER_IP}:${PORT}?type=tcp&security=reality&sni=${SNI}&fp=safari&pbk=${PUBLIC_KEY}&sid=${NEW_SHORT_ID}&flow=xtls-rprx-vision#${USERNAME}"

    echo -e "\033[0;32m✅ User '$USERNAME' added to config!\033[0m"
    echo -e "\033[0;32m✅ Generated unique ShortID: $NEW_SHORT_ID\033[0m"
    echo ""
    echo "🔗 Connection link:"
    echo "$LINK"
    echo ""

    # 🔹 Save client config
    save_client_config "$USERNAME" "$LINK" "$UUID" "$PUBLIC_KEY"

    restart_xray
}

del_user() {
    local USERNAME="$1"

    if [ -z "$USERNAME" ]; then
        echo -e "\033[0;31mError: please specify a username\033[0m"
        echo "Usage: $0 del <username>"
        exit 1
    fi

    EXISTS=$(jq -r --arg u "$USERNAME" '.inbounds[0].settings.clients[] | select(.email == $u)' "$CONFIG_FILE")
    if [ -z "$EXISTS" ] || [ "$EXISTS" = "null" ]; then
        echo -e "\033[0;31mError: user '$USERNAME' not found\033[0m"
        exit 1
    fi

    # Find the shortId of the user being deleted before deletion
    USER_SHORT_ID=$(jq -r --arg u "$USERNAME" '.inbounds[0].settings.clients[] | select(.email == $u) | .shortId // empty' "$CONFIG_FILE")

    TEMP=$(mktemp)
    jq --arg u "$USERNAME" \
       '.inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.email != $u)]' \
       "$CONFIG_FILE" > "$TEMP" && cat "$TEMP" > "$CONFIG_FILE" && rm "$TEMP"

    # Remove shortId from the global array if it was tied to the user
    if [ -n "$USER_SHORT_ID" ]; then
        TEMP=$(mktemp)
        jq --arg sid "$USER_SHORT_ID" '.inbounds[0].streamSettings.realitySettings.shortIds = [.inbounds[0].streamSettings.realitySettings.shortIds[] | select(. != $sid)]' "$CONFIG_FILE" > "$TEMP" && cat "$TEMP" > "$CONFIG_FILE" && rm "$TEMP"
        echo -e "\033[0;33m🗑️  ShortID $USER_SHORT_ID removed from config\033[0m"
    fi

    # 🔹 Delete client file if it exists
    CLIENT_FILE="${CLIENTS_DIR}/${USERNAME}.txt"
    [ -f "$CLIENT_FILE" ] && rm -f "$CLIENT_FILE" && echo -e "\033[0;33m🗑️  Deleted file: $CLIENT_FILE\033[0m"

    echo -e "\033[0;32m✅ User '$USERNAME' removed from config!\033[0m"
    echo ""

    restart_xray
}

# === MAIN ===
# Support both formats: ./xray.sh username <cmd>  OR  ./xray.sh <cmd> username
if [ "$2" = "link" ] || [ "$2" = "conf" ]; then
    if [ "$2" = "link" ]; then
        show_link "$1"
    else
        show_conf "$1" 2>/dev/null || echo -e "\033[0;31mCommand conf is not yet implemented\033[0m"
    fi
elif [ "$1" = "link" ]; then
    show_link "$2"
elif [ "$1" = "conf" ]; then
    show_conf "$2" 2>/dev/null || echo -e "\033[0;31mCommand conf is not yet implemented\033[0m"
else
    case "${1:-help}" in
        add)    add_user "$2" ;;
        del)    del_user "$2" ;;
        list)   list_users ;;
        help)   show_help ;;
        *)      echo -e "\033[0;31mUnknown command: $1\033[0m"; show_help; exit 1 ;;
    esac
fi