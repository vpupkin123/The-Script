#!/bin/bash

set -e

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Этот скрипт должен быть запущен от имени root"
    exit 1
fi

# Определение ОС
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Не удалось определить операционную систему"
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
        echo "Неподдерживаемая операционная система: $OS"
        exit 1
        ;;
esac

echo "Обнаружена ОС: $OS"
echo "Пакетный менеджер: $PKG_MANAGER"

# Обновление системы
echo "Обновление системы..."
if [ "$PKG_MANAGER" = "apt" ]; then
    apt update
    apt upgrade -y
    apt install -y fail2ban wget
else
    dnf update -y
    dnf install -y fail2ban wget
fi

# Настройка fail2ban
echo "Настройка fail2ban..."
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

# Установка Xray
echo "Установка Xray..."
cd ~
wget https://github.com/XTLS/Xray-install/raw/main/install-release.sh
bash install-release.sh
rm install-release.sh
systemctl enable xray
systemctl start xray

# Смена пароля root
echo "Смена пароля root..."
read -sp "Введите новый пароль для root: " ROOT_PASSWORD
echo
passwd root << EOF
$ROOT_PASSWORD
$ROOT_PASSWORD
EOF

# Создание нового пользователя
echo "Создание нового пользователя..."
read -p "Введите логин нового пользователя: " NEW_USER
useradd -m -s /bin/bash "$NEW_USER"

read -sp "Введите пароль для $NEW_USER: " NEW_USER_PASSWORD
echo
passwd "$NEW_USER" << EOF
$NEW_USER_PASSWORD
$NEW_USER_PASSWORD
EOF

# Запрет входа root по SSH
echo "Запрет входа root по SSH..."
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart "$SSH_SERVICE"

# Финальное сообщение
echo ""
echo "Настройка завершена!"
echo "Создан пользователь: $NEW_USER"
echo "Fail2ban настроен и запущен"
echo "Xray установлен и запущен"
echo "Вход root по SSH запрещен"
echo ""
echo "Не забудьте:"
echo "1. Подсунуть свой конфиг для Xray в /usr/local/etc/xray/config.json"
echo "2. Перезайти на сервер под пользователем $NEW_USER"