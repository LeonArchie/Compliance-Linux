#!/bin/bash

# Настройка прав доступа к лог-файлам и systemd-journald

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
    log "=== Настройка прав доступа к лог-файлам и systemd-journald ==="
    
    check_root
    
    # Настройка прав доступа к лог-файлам
    log "Настройка прав доступа к лог-файлам..."
    
    # Основные системные логи
    chmod 640 /var/log/auth.log /var/log/secure /var/log/syslog /var/log/messages 2>/dev/null || true
    chown root:adm /var/log/auth.log /var/log/secure /var/log/syslog /var/log/messages 2>/dev/null || true

    # Логи входа
    chmod 664 /var/log/wtmp /var/log/btmp 2>/dev/null || true
    chown root:utmp /var/log/wtmp /var/log/btmp 2>/dev/null || true

    # Lastlog
    chmod 644 /var/log/lastlog 2>/dev/null || true
    chown root:utmp /var/log/lastlog 2>/dev/null || true

    # Журналы systemd
    find /var/log -name "*.journal" -exec chmod 640 {} \; 2>/dev/null || true
    find /var/log -name "*.journal" -exec chown root:systemd-journal {} \; 2>/dev/null || true

    # Дополнительная настройка прав
    log "Дополнительная настройка прав лог-файлов..."
    find /var/log -name "*.log" -type f -exec chmod 640 {} \; 2>/dev/null || true
    find /var/log -name "*.log.*" -type f -exec chmod 640 {} \; 2>/dev/null || true
    find /var/log -name "*.gz" -type f -exec chmod 640 {} \; 2>/dev/null || true

    # Специфичные файлы
    chmod 660 /var/log/btmp /var/log/btmp.1 /var/log/wtmp 2>/dev/null || true
    chmod 640 /var/log/lastlog /var/log/faillog 2>/dev/null || true
    chown root:utmp /var/log/btmp /var/log/btmp.1 /var/log/wtmp /var/log/lastlog /var/log/faillog 2>/dev/null || true
    
    check_command "Настройка прав доступа к лог-файлам"

    # Настройка systemd-journald
    log "Настройка systemd-journald..."
    mkdir -p /etc/systemd/journald.conf.d/

    cat > /etc/systemd/journald.conf.d/60-journald.conf << 'EOF'
[Journal]
SystemMaxUse=1G
SystemKeepFree=500M
RuntimeMaxUse=200M
RuntimeKeepFree=50M
MaxFileSec=1month
Compress=yes
Storage=persistent
EOF

    systemctl restart systemd-journald
    
    # Отключение ненужных служб journald
    log "Отключение ненужных служб journald..."
    systemctl stop systemd-journal-upload.service 2>/dev/null || true
    systemctl disable systemd-journal-upload.service 2>/dev/null || true
    systemctl mask systemd-journal-upload.service 2>/dev/null || true
    
    check_command "Настройка systemd-journald"
    
    log "Проверка настроек journald:"
    journalctl --disk-usage
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"