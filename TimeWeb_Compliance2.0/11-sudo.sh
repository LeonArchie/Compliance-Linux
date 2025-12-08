#!/bin/bash

# Настройка журналирования sudo

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
    log "=== Настройка журналирования sudo ==="
    
    check_root
    
    # Настройка журналирования sudo
    log "Настройка журналирования sudo..."
    echo "Defaults logfile=/var/log/sudo.log" >> /etc/sudoers
    touch /var/log/sudo.log
    chmod 640 /var/log/sudo.log
    check_command "Настройка журналирования sudo"
    
    log "Проверка настроек sudo..."
    grep "logfile" /etc/sudoers
    ls -la /var/log/sudo.log
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"