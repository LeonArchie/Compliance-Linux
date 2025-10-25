#!/bin/bash

# Настройка сетевого интерфейса

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
    log "=== Настройка сетевого интерфейса ==="
    
    check_root
    
    log "Настройка сетевого интерфейса..."
    tee /etc/netplan/50-cloud-init.yaml > /dev/null <<EOF
network:
  ethernets:
    eth0:
      dhcp4: false
      addresses: [192.168.8.13/24]
      nameservers:
        addresses: [192.168.8.2, 192.168.8.3]
      routes:
        - to: default
          via: 192.168.8.1
          on-link: true
  version: 2
EOF

    netplan generate
    netplan apply
    check_command "Настройка сетевого интерфейса"
    
    log "Проверка сетевых настроек..."
    ip addr show eth0
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"