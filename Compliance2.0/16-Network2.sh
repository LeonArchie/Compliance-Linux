#!/bin/bash

# Настройка сетевой безопасности и отключение беспроводных интерфейсов

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

# Функция для отключения беспроводных модулей
disable_wireless_modules() {
    log "=== Отключение беспроводных модулей ==="
    
    if [ -n "$(find /sys/class/net/*/ -type d -name wireless 2>/dev/null)" ]; then
        local driver_names
        driver_names=$(for driverdir in $(find /sys/class/net/*/ -type d -name wireless | xargs -0 dirname); do
            basename "$(readlink -f "$driverdir"/device/driver/module 2>/dev/null)" 2>/dev/null
        done | sort -u)
        
        for module_name in $driver_names; do
            if [ -n "$module_name" ]; then
                log "Обработка модуля: $module_name"
                
                # Установка модуля для предотвращения загрузки
                if ! modprobe -n -v "$module_name" | grep -P -- '^\h*install \/bin\/(true|false)' >/dev/null 2>&1; then
                    echo "install $module_name /bin/false" >> "/etc/modprobe.d/$module_name.conf"
                    log "Установка модуля '$module_name' для предотвращения загрузки"
                fi
                
                # Выгрузка модуля, если он загружен
                if lsmod | grep "$module_name" >/dev/null 2>&1; then
                    modprobe -r "$module_name" 2>/dev/null || true
                    log "Выгрузка модуля '$module_name'"
                fi
                
                # Добавление в черный список
                if ! grep -Pq "^\h*blacklist\h+$module_name\b" /etc/modprobe.d/* 2>/dev/null; then
                    echo "blacklist $module_name" >> "/etc/modprobe.d/$module_name.conf"
                    log "Добавление модуля '$module_name' в черный список"
                fi
            fi
        done
    else
        log "Беспроводные интерфейсы не обнаружены"
    fi
    
    check_command "Отключение беспроводных модулей"
}

# Функция для отключения радио в NetworkManager
disable_nm_radio() {
    log "=== Отключение беспроводного радио в NetworkManager ==="
    
    if command -v nmcli >/dev/null 2>&1; then
        # Отключаем Wi-Fi радио
        if nmcli radio wifi | grep -q "enabled"; then
            nmcli radio wifi off
            log "Wi-Fi радио отключено"
        else
            log "Wi-Fi радио уже отключено"
        fi
        
        # Отключаем WWAN (мобильное) радио
        if nmcli radio wwan | grep -q "enabled"; then
            nmcli radio wwan off
            log "WWAN радио отключено"
        else
            log "WWAN радио уже отключено"
        fi
        
        # Блокируем автоматическое включение
        nmcli radio all off
        log "Все радиоинтерфейсы отключены и заблокированы"
        
    else
        warn "NetworkManager не установлен, пропускаем отключение радио"
    fi
    
    check_command "Отключение беспроводного радио"
}

# Функция для настройки параметров sysctl
configure_sysctl() {
    log "=== Настройка параметров сетевой безопасности ==="
    
    local sysctl_file="/etc/sysctl.d/60-network-security.conf"
    
    # Создаем файл с настройками
    cat > "$sysctl_file" << EOF
# Network security settings
# Disable IP forwarding and redirects

# Отключение отправки перенаправленных пакетов
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Отключение принятия ICMP перенаправлений
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Отключение безопасных ICMP перенаправлений
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Включение фильтрации обратного пути
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Отключение принятия пакетов с исходной маршрутизацией
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Включение логирования подозрительных пакетов
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Отключение принятия объявлений маршрутизаторов IPv6
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Дополнительные настройки безопасности
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
EOF
    
    check_command "Создание файла конфигурации sysctl"
    
    # Применяем настройки
    log "Применение параметров сетевой безопасности..."
    
    # IPv4 настройки
    sysctl -w net.ipv4.conf.all.send_redirects=0
    sysctl -w net.ipv4.conf.default.send_redirects=0
    
    sysctl -w net.ipv4.conf.all.accept_redirects=0
    sysctl -w net.ipv4.conf.default.accept_redirects=0
    
    sysctl -w net.ipv4.conf.all.secure_redirects=0
    sysctl -w net.ipv4.conf.default.secure_redirects=0
    
    sysctl -w net.ipv4.conf.all.rp_filter=1
    sysctl -w net.ipv4.conf.default.rp_filter=1
    
    sysctl -w net.ipv4.conf.all.accept_source_route=0
    sysctl -w net.ipv4.conf.default.accept_source_route=0
    
    sysctl -w net.ipv4.conf.all.log_martians=1
    sysctl -w net.ipv4.conf.default.log_martians=1
    
    # IPv6 настройки (если IPv6 включен)
    if [ -d "/proc/sys/net/ipv6" ]; then
        sysctl -w net.ipv6.conf.all.accept_redirects=0
        sysctl -w net.ipv6.conf.default.accept_redirects=0
        sysctl -w net.ipv6.conf.all.accept_source_route=0
        sysctl -w net.ipv6.conf.default.accept_source_route=0
        sysctl -w net.ipv6.conf.all.accept_ra=0
        sysctl -w net.ipv6.conf.default.accept_ra=0
        log "Применены настройки IPv6"
    else
        warn "IPv6 отключен, пропускаем настройки IPv6"
    fi
    
    # Обновляем маршруты
    sysctl -w net.ipv4.route.flush=1
    if [ -d "/proc/sys/net/ipv6" ]; then
        sysctl -w net.ipv6.route.flush=1
    fi
    
    check_command "Применение параметров сетевой безопасности"
}

# Функция проверки результата
verify_configuration() {
    log "=== Проверка примененных настроек ==="
    
    # Проверяем статус радио
    if command -v nmcli >/dev/null 2>&1; then
        log "Статус Wi-Fi радио: $(nmcli radio wifi)"
        log "Статус WWAN радио: $(nmcli radio wwan)"
    fi
    
    # Проверяем ключевые параметры sysctl
    log "Проверка параметров сетевой безопасности:"
    
    local params=(
        "net.ipv4.conf.all.send_redirects"
        "net.ipv4.conf.default.send_redirects"
        "net.ipv4.conf.all.accept_redirects" 
        "net.ipv4.conf.default.accept_redirects"
        "net.ipv4.conf.all.secure_redirects"
        "net.ipv4.conf.default.secure_redirects"
        "net.ipv4.conf.all.rp_filter"
        "net.ipv4.conf.default.rp_filter"
        "net.ipv4.conf.all.accept_source_route"
        "net.ipv4.conf.default.accept_source_route"
        "net.ipv4.conf.all.log_martians"
        "net.ipv4.conf.default.log_martians"
    )
    
    for param in "${params[@]}"; do
        local value
        value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
        log "  $param = $value"
    done
    
    if [ -d "/proc/sys/net/ipv6" ]; then
        local ipv6_params=(
            "net.ipv6.conf.all.accept_redirects"
            "net.ipv6.conf.default.accept_redirects"
            "net.ipv6.conf.all.accept_source_route"
            "net.ipv6.conf.default.accept_source_route"
            "net.ipv6.conf.all.accept_ra"
            "net.ipv6.conf.default.accept_ra"
        )
        
        for param in "${ipv6_params[@]}"; do
            local value
            value=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
            log "  $param = $value"
        done
    fi
}

# Основная функция
main() {
    log "=== Настройка сетевой безопасности ==="
    
    check_root
    
    # Отключение беспроводных модулей
    disable_wireless_modules
    
    # Отключение радио в NetworkManager
    disable_nm_radio
    
    # Настройка параметров sysctl
    configure_sysctl
    
    # Проверка примененных настроек
    verify_configuration
    
    log "=== Настройка завершена ==="
    log "Для применения всех изменений может потребоваться перезагрузка системы"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"