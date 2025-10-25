#!/bin/bash

# Настройка системных служб

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
    log "=== Настройка системных служб ==="
    
    check_root
    
    # Отключение Apport
    log "Отключение Apport..."
    sed -i 's/^enabled=1/enabled=0/' /etc/default/apport
    echo "enabled=0" | tee -a /etc/default/apport > /dev/null

    systemctl stop apport.service
    systemctl disable apport.service
    systemctl mask apport.service
    check_command "Отключение Apport"

    # Удаление GDM
    log "Удаление GDM..."
    systemctl get-default
    systemctl set-default multi-user.target
    systemctl stop gdm3 2>/dev/null || true
    apt purge -y gdm3 2>/dev/null || true
    apt autoremove -y
    check_command "Удаление GDM"

    # Отключение ненужных служб
    log "Отключение ненужных служб..."
    systemctl stop rsync.service 2>/dev/null || true
    systemctl disable rsync.service 2>/dev/null || true
    systemctl mask rsync.service 2>/dev/null || true

    # Удаление ненужных клиентов
    apt purge -y telnet inetutils-telnet ftp tnftp 2>/dev/null || true
    apt autoremove -y
    check_command "Отключение ненужных служб"

    # Настройка systemd-timesyncd
    log "Настройка systemd-timesyncd..."
    systemctl stop systemd-timesyncd.service
    systemctl disable systemd-timesyncd.service
    systemctl --now mask systemd-timesyncd.service
    check_command "Настройка systemd-timesyncd"

    # установка библиотеки libpam-pwquality
    log "установка библиотеки libpam-pwquality"
    apt install libpam-pwquality -y
    check_command "установка библиотеки libpam-pwquality"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"