#!/bin/bash

# Установка и настройка AIDE (Advanced Intrusion Detection Environment)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функции для логирования
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Функция проверки выполнения команды
check_command() {
    if [ $? -eq 0 ]; then
        log "✓ $1"
    else
        error "✗ Ошибка: $1"
        exit 1
    fi
}

# Основная функция
main() {
    log "=== Установка и настройка AIDE ==="
    
    check_root
    
    # Установка и настройка AIDE
    log "Установка AIDE..."
    DEBIAN_FRONTEND=noninteractive apt install -y aide
    check_command "Установка AIDE"

    # Настройка конфигурации AIDE
    log "Настройка конфигурации AIDE..."
    tee -a /etc/aide/aide.conf > /dev/null << 'EOF'

# Правила проверки файлов
Binlib = p+i+n+u+g+s+b+m+c+sha256
Log = p+i+n+u+g
Config = p+i+n+u+g+s+b+m+c+sha256
Data = p+n+u+g+s+b+m+c+sha256

# Пути для проверки
/bin         Binlib
/sbin        Binlib
/usr/bin     Binlib
/usr/sbin    Binlib
/lib         Binlib
/lib64       Binlib
/usr/lib     Binlib
/usr/lib64   Binlib

/etc         Config
/boot        Config
/root        Config

/var/log     Log
/var/lib     Data

/usr/sbin/auditctl p+i+n+u+g+s+b+acl+xattrs+sha512
/usr/sbin/auditd p+i+n+u+g+s+b+acl+xattrs+sha512
/usr/sbin/ausearch p+i+n+u+g+s+b+acl+xattrs+sha512
/usr/sbin/aureport p+i+n+u+g+s+b+acl+xattrs+sha512
/usr/sbin/autrace p+i+n+u+g+s+b+acl+xattrs+sha512
/usr/sbin/augenrules p+i+n+u+g+s+b+acl+xattrs+sha512

# Исключения
!/var/log/.*
!/var/tmp/.*
!/tmp/.*
!/proc/.*
!/sys/.*
!/dev/.*
!/run/.*
!/var/ossec/.*
EOF

    # Создание необходимых директорий
    log "Создание директорий AIDE..."
    mkdir -p /var/lib/aide /var/log/aide

    # Инициализация базы данных AIDE
    log "Инициализация базы данных AIDE..."
    aide --config=/etc/aide/aide.conf --init
    cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    check_command "Инициализация базы данных AIDE"

    # Создание службы AIDE для ежедневной проверки
    log "Создание службы AIDE..."
    cat > /etc/systemd/system/dailyaidecheck.service << 'EOF'
[Unit]
Description=AIDE File Integrity Check
Wants=dailyaidecheck.timer

[Service]
Type=oneshot
ExecStart=/usr/bin/aide --config=/etc/aide/aide.conf --check
EOF

    cat > /etc/systemd/system/dailyaidecheck.timer << 'EOF'
[Unit]
Description=Daily AIDE check
Requires=dailyaidecheck.service

[Timer]
OnCalendar=daily
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Перезагрузка systemd и настройка таймера
    log "Настройка systemd таймера для AIDE..."
    systemctl daemon-reload
    systemctl unmask dailyaidecheck.timer dailyaidecheck.service 2>/dev/null || true
    systemctl enable dailyaidecheck.timer
    systemctl start dailyaidecheck.timer
    check_command "Настройка systemd таймера"

    # Настройка logrotate для логов AIDE
    log "Настройка logrotate для AIDE..."
    cat > /etc/logrotate.d/aide << 'EOF'
/var/log/aide/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 640 root adm
    maxsize 100M
}
EOF

    log "Проверка конфигурации AIDE:"
    aide --config=/etc/aide/aide.conf --config-check
    
    log "Статус таймера AIDE:"
    systemctl status dailyaidecheck.timer --no-pager -l
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"