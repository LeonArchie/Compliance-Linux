#!/bin/bash

# Отключение беспроводных интерфейсов

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

# Функция отключения беспроводных интерфейсов
disable_wireless() {
    log "Отключение беспроводных интерфейсов..."
    
    # Установка network-manager (если еще не установлен)
    if ! command -v nmcli &> /dev/null; then
        log "Установка network-manager..."
        apt update && apt install -y network-manager
    fi
    
    # Отключение WiFi через NetworkManager
    log "Отключение WiFi через NetworkManager..."
    nmcli radio wifi off 2>/dev/null || true
    
    # Создание конфигурации для отключения WiFi
    log "Создание конфигурации NetworkManager..."
    cat > /etc/NetworkManager/conf.d/99-disable-wifi.conf << 'EOF'
[device]
match-device=interface-name:wlan0,interface-name:wlp*
managed=0
EOF

    systemctl restart NetworkManager 2>/dev/null || true

    # Принудительное отключение беспроводных интерфейсов
    log "Принудительное отключение беспроводных интерфейсов..."
    for interface in $(ip link show | grep -o 'wlan[0-9]*\|wlp[0-9]*s[0-9]*' 2>/dev/null || true); do
        ip link set "$interface" down 2>/dev/null || true
        log "Интерфейс $interface отключен"
    done

    # Блокировка загрузки модулей WiFi
    log "Блокировка загрузки модулей WiFi..."
    WIFI_MODULES=("ath9k" "rtl8192ce" "iwlwifi" "brcmfmac" "brcmutil" "cfg80211")
    for module in "${WIFI_MODULES[@]}"; do
        if lsmod | grep -q "$module" 2>/dev/null; then
            modprobe -r "$module" 2>/dev/null || true
            log "Модуль $module выгружен"
        fi
        if ! grep -q "blacklist $module" /etc/modprobe.d/disable-wireless.conf 2>/dev/null; then
            echo "blacklist $module" >> /etc/modprobe.d/disable-wireless.conf
            log "Модуль $module добавлен в черный список"
        fi
    done
    
    log "✓ Отключение беспроводных интерфейсов завершено"
}

# Основная функция
main() {
    log "=== Отключение беспроводных интерфейсов ==="
    
    check_root
    
    # Вызов функции отключения беспроводных интерфейсов
    disable_wireless

    log "=== Настройка завершена ==="
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"