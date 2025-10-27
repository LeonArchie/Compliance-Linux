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

# Функция проверки наличия локального пакета
check_local_package() {
    local package_file="wazuh-agent_4.13.1-1_amd64.deb"
    if [ -f "./$package_file" ]; then
        log "Локальный пакет WAZUH найден: $package_file"
        return 0
    else
        error "Локальный пакет WAZUH не найден: $package_file"
        error "Убедитесь, что файл находится в той же директории, что и скрипт"
        return 1
    fi
}

# Основная функция
main() {
    log "=== Установка WAZUH агента ==="
    
    check_root
    check_local_package
    
    # Установка WAZUH агента
    log "Установка WAZUH агента из локального пакета..."
    
    # Параметры установки
    WAZUH_MANAGER="wazuh.school59.ru"
    PACKAGE_FILE="wazuh-agent_4.13.1-1_amd64.deb"
    
    # Установка пакета
    log "Установка WAZUH агента..."
    if WAZUH_MANAGER="$WAZUH_MANAGER" dpkg -i "./$PACKAGE_FILE"; then
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
    
    log "WAZUH агент успешно установлен и настроен"
    log "Менеджер: $WAZUH_MANAGER"
    log "Агент зарегистрирован на менеджере: $WAZUH_MANAGER"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"