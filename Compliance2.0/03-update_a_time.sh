#!/bin/bash

# Обновление системы и настройка времени

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
    log "=== Обновление системы и настройка времени ==="
    
    check_root
    
    # Обновление системы
    log "Обновление системы..."
    apt update -y && apt full-upgrade -y && apt autoremove -y
    check_command "Обновление системы"

    # Установка временной зоны
    log "Установка временной зоны Europe/Moscow..."
    timedatectl set-timezone Europe/Moscow
    check_command "Установка временной зоны"

    # Установка и настройка Chrony
    log "Установка и настройка Chrony..."
    apt install -y chrony
    systemctl enable chrony
    systemctl start chrony

    sed -i 's/^pool/#pool/g' /etc/chrony/chrony.conf
    echo "server 192.168.8.15 iburst" >> /etc/chrony/chrony.conf
    echo "server 192.168.8.15 iburst" >> /etc/chrony/sources.d/local-ntp-server.sources
    echo "cmddeny all" >> /etc/chrony/chrony.conf

    systemctl restart chrony
    log "Проверка источников времени:"
    chronyc sources
    check_command "Настройка Chrony"

    # Настройка пользователя Chrony
    log "Настройка пользователя Chrony..."
    tee -a /etc/chrony/chrony.conf > /dev/null << 'EOF'
user _chrony
EOF
    check_command "Настройка пользователя Chrony"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"