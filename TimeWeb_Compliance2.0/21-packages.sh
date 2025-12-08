#!/bin/bash

# Скрипт для удаления пакета libbluetooth3

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

# Основная функция
main() {
    log "=== Удаление пакета libbluetooth3 ==="
    
    check_root
    
    # Проверяем установлен ли пакет
    if ! dpkg -l libbluetooth3 2>/dev/null | grep -q "^ii"; then
        log "Пакет libbluetooth3 не установлен"
        exit 0
    fi
    
    # Удаляем пакет
    log "Удаление пакета libbluetooth3..."
    apt-get remove --purge -y libbluetooth3
    
    if [ $? -eq 0 ]; then
        log "✓ Пакет libbluetooth3 успешно удален"
    else
        error "✗ Ошибка при удалении пакета"
        exit 1
    fi
}

# Запуск основной функции
main "$@"