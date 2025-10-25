#!/bin/bash

# Установка WAZUH агента

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

# Функция проверки наличия wget
check_wget() {
    if ! command -v wget &> /dev/null; then
        log "Установка wget..."
        apt update && apt install -y wget
    fi
}

# Основная функция
main() {
    log "=== Установка WAZUH агента ==="
    
    check_root
    check_wget
    
    # Установка WAZUH агента
    log "Загрузка и установка WAZUH агента..."
    
    # URL пакета Wazuh агента
    WAZUH_URL="https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.13.1-1_amd64.deb"
    WAZUH_MANAGER="wazuh.school59.ru"
    
    # Загрузка пакета
    log "Загрузка WAZUH агента..."
    if wget -q "$WAZUH_URL"; then
        log "Пакет WAZUH успешно загружен"
    else
        error "Ошибка загрузки WAZUH агента"
        exit 1
    fi

    # Установка пакета
    log "Установка WAZUH агента..."
    local package_file=$(basename "$WAZUH_URL")
    if WAZUH_MANAGER="$WAZUH_MANAGER" dpkg -i "./$package_file"; then
        log "WAZUH агент успешно установлен"
    else
        error "Ошибка установки WAZUH агента"
        exit 1
    fi

    # Настройка службы WAZUH
    log "Настройка службы WAZUH..."
    systemctl daemon-reload
    systemctl enable wazuh-agent
    systemctl start wazuh-agent
    check_command "Настройка WAZUH агента"
    
    # Проверка статуса службы
    log "Проверка статуса WAZUH агента..."
    systemctl status wazuh-agent --no-pager -l
    
    # Очистка загруженного пакета
    log "Очистка загруженного пакета..."
    rm -f "./$package_file"
    
    log "WAZUH агент успешно установлен и настроен"
    log "Менеджер: $WAZUH_MANAGER"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"