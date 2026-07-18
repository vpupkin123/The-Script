#!/bin/bash

# === КОНФИГУРАЦИЯ ===
CONFIG_FILE="/usr/local/etc/xray/config.json"
CLIENTS_DIR="$HOME/clients"
ASK_RESTART=true  # 🔹 Спрашивать ли перед перезапуском

# Проверка существования конфига
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "\033[0;31mОшибка: Конфиг не найден по пути $CONFIG_FILE\033[0m"
    exit 1
fi

# 🔹 Создаём папку для клиентов, если нет
mkdir -p "$CLIENTS_DIR" 2>/dev/null || {
    echo -e "\033[0;31mОшибка: нет прав на создание $CLIENTS_DIR\033[0m"
    exit 1
}

show_help() {
    echo "Использование: $0 <команда> [аргументы]"
    echo ""
    echo "Команды:"
    echo "  add <username>    Добавить нового пользователя"
    echo "  del <username>    Удалить пользователя"
    echo "  list              Список всех пользователей (имена)"
    echo "  help              Показать эту справку"
}

list_users() {
    echo -e "\033[0;32mСписок пользователей:\033[0m"
    jq -r '.inbounds[0].settings.clients[] | .email // "Без имени"' "$CONFIG_FILE" | nl
}

restart_xray() {
    if [ "$ASK_RESTART" = true ]; then
        read -p "🔄 Перезапустить службу Xray? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "\033[0;33m⚠️  Служба Xray не перезапущена. Изменения вступят в силу после ручного перезапуска.\033[0m"
            return 1
        fi
    fi
    systemctl restart xray 2>/dev/null || service xray restart 2>/dev/null
    echo -e "\033[0;32m✅ Xray перезапущен\033[0m"
}

# 🔹 Функция сохранения параметров клиента в файл
save_client_config() {
    local USERNAME="$1"
    local LINK="$2"
    local UUID="$3"
    local FILE="${CLIENTS_DIR}/${USERNAME}.txt"

    cat > "$FILE" <<EOF
=== Xray Reality Client: $USERNAME ===
Дата создания: $(date '+%Y-%m-%d %H:%M:%S')

🔗 VLESS-ссылка (для импорта в v2rayNG/Hiddify):
$LINK

📋 Параметры для ручной настройки:
  UUID:       $UUID
  Адрес:      $(curl -s ifconfig.me)
  Порт:       $(jq -r '.inbounds[0].port' "$CONFIG_FILE")
  SNI:        $(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
  ShortID:    $(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")
  PublicKey:  $(echo "$X25519_OUTPUT" | awk '/Password \(PublicKey\):/ {print $3}')
  Flow:       xtls-rprx-vision
  FP:         safari
  Network:    tcp

⚠️  Файл содержит чувствительные данные — храните в безопасном месте!
EOF
    chmod 600 "$FILE" 2>/dev/null
    echo -e "\033[0;32m📄 Конфиг сохранён: $FILE\033[0m"
}

add_user() {
    local USERNAME="$1"

    if [ -z "$USERNAME" ]; then
        echo -e "\033[0;31mОшибка: укажите имя пользователя\033[0m"
        echo "Использование: $0 add <username>"
        exit 1
    fi

    # Проверка дубликата
    EXISTS=$(jq -r --arg u "$USERNAME" '.inbounds[0].settings.clients[] | select(.email == $u)' "$CONFIG_FILE")
    if [ -n "$EXISTS" ]; then
        echo -e "\033[0;31mОшибка: пользователь '$USERNAME' уже существует\033[0m"
        exit 1
    fi

    UUID=$(xray uuid)

    # Безопасное редактирование
    TEMP=$(mktemp)
    jq --arg uuid "$UUID" --arg user "$USERNAME" \
       '.inbounds[0].settings.clients += [{"id": $uuid, "flow": "xtls-rprx-vision", "level": 0, "email": $user}]' \
       "$CONFIG_FILE" > "$TEMP" && cat "$TEMP" > "$CONFIG_FILE" && rm "$TEMP"

    # Динамическое извлечение параметров
    SERVER_IP=$(curl -s ifconfig.me)
    PORT=$(jq -r '.inbounds[0].port' "$CONFIG_FILE")
    SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
    SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")
    PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")
    X25519_OUTPUT=$(xray x25519 -i "$PRIVATE_KEY" 2>&1)
    PUBLIC_KEY=$(echo "$X25519_OUTPUT" | awk '/Password \(PublicKey\):/ {print $3}')

    LINK="vless://${UUID}@${SERVER_IP}:${PORT}?type=tcp&security=reality&sni=${SNI}&fp=safari&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${USERNAME}"

    echo -e "\033[0;32m✅ Пользователь '$USERNAME' добавлен в конфиг!\033[0m"
    echo ""
    echo "🔗 Ссылка для подключения:"
    echo "$LINK"
    echo ""

    # 🔹 Сохраняем конфиг клиента
    save_client_config "$USERNAME" "$LINK" "$UUID"

    restart_xray
}

del_user() {
    local USERNAME="$1"

    if [ -z "$USERNAME" ]; then
        echo -e "\033[0;31mОшибка: укажите имя пользователя\033[0m"
        echo "Использование: $0 del <username>"
        exit 1
    fi

    EXISTS=$(jq -r --arg u "$USERNAME" '.inbounds[0].settings.clients[] | select(.email == $u)' "$CONFIG_FILE")
    if [ -z "$EXISTS" ]; then
        echo -e "\033[0;31mОшибка: пользователь '$USERNAME' не найден\033[0m"
        exit 1
    fi

    TEMP=$(mktemp)
    jq --arg u "$USERNAME" \
       '.inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.email != $u)]' \
       "$CONFIG_FILE" > "$TEMP" && cat "$TEMP" > "$CONFIG_FILE" && rm "$TEMP"

    # 🔹 Удаляем файл клиента, если есть
    CLIENT_FILE="${CLIENTS_DIR}/${USERNAME}.txt"
    [ -f "$CLIENT_FILE" ] && rm -f "$CLIENT_FILE" && echo -e "\033[0;33m🗑️  Удалён файл: $CLIENT_FILE\033[0m"

    echo -e "\033[0;32m✅ Пользователь '$USERNAME' удалён из конфига!\033[0m"
    echo ""

    restart_xray
}

# === MAIN ===
case "${1:-help}" in
    add)    add_user "$2" ;;
    del)    del_user "$2" ;;
    list)   list_users ;;
    help)   show_help ;;
    *)      echo -e "\033[0;31mНеизвестная команда: $1\033[0m"; show_help; exit 1 ;;
esac