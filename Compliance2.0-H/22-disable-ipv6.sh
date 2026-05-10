#!/bin/bash

# Скрипт для полного отключения IPv6

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
    echo -e "${YELLOW}[WARNING]${NC} $1"
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

# Проверка текущего статуса IPv6
check_ipv6_status() {
    # Проверяем настройки в sysctl.conf
    if grep -q "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.conf && \
       grep -q "net.ipv6.conf.default.disable_ipv6 = 1" /etc/sysctl.conf && \
       grep -q "net.ipv6.conf.lo.disable_ipv6 = 1" /etc/sysctl.conf; then
        return 0  # IPv6 уже отключен в конфигах
    else
        return 1  # IPv6 включен или частично отключен
    fi
}

# Проверка активности IPv6 в системе
check_ipv6_active() {
    # Проверяем, есть ли активные IPv6 адреса (кроме loopback)
    if ip -6 addr show | grep -q "inet6" && ! ip -6 addr show | grep -q "inet6 ::1"; then
        return 1  # IPv6 активен
    else
        return 0  # IPv6 не активен
    fi
}

# Отключение через sysctl.conf
disable_ipv6_sysctl() {
    log "Настройка отключения IPv6 через sysctl..."
    
    # Создаем backup sysctl.conf
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Удаляем старые настройки IPv6 если есть
    sed -i '/net.ipv6.conf.*.disable_ipv6/d' /etc/sysctl.conf
    sed -i '/# Отключение IPv6/d' /etc/sysctl.conf
    
    # Добавляем параметры отключения IPv6 в sysctl.conf
    cat >> /etc/sysctl.conf << EOF

# Отключение IPv6 - добавлено скриптом $(date +%Y-%m-%d)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    # Добавляем отключение для каждого существующего интерфейса
    for iface in $(ls /sys/class/net/ 2>/dev/null); do
        if [[ "$iface" != "lo" ]]; then
            echo "net.ipv6.conf.${iface}.disable_ipv6 = 1" >> /etc/sysctl.conf
        fi
    done

    # Применяем изменения
    sysctl -p > /dev/null 2>&1
    
    log "✓ Параметры IPv6 добавлены в sysctl.conf"
}

# Немедленное отключение через /proc
disable_ipv6_immediate() {
    log "Немедленное отключение IPv6 через /proc..."
    
    # Отключаем для всех интерфейсов через /proc
    find /proc/sys/net/ipv6/conf -name disable_ipv6 -type f 2>/dev/null | while read file; do
        echo 1 > "$file" 2>/dev/null || true
    done
    
    # Принудительно применяем настройки
    sysctl -p > /dev/null 2>&1
    
    log "✓ IPv6 отключен на уровне ядра"
}

# Отключение через модуль ядра
disable_ipv6_kernel() {
    log "Настройка отключения IPv6 на уровне модуля ядра..."
    
    # Добавляем в черный список
    if [ ! -f /etc/modprobe.d/blacklist-ipv6.conf ]; then
        cat > /etc/modprobe.d/blacklist-ipv6.conf << EOF
# Отключение IPv6 модуля - добавлено скриптом $(date +%Y-%m-%d)
blacklist ipv6
alias ipv6 off
options ipv6 disable=1
EOF
    fi
    
    # Пытаемся выгрузить модуль
    if lsmod | grep -q ipv6; then
        modprobe -r ipv6 2>/dev/null || warn "Не удалось выгрузить модуль ipv6 (может быть в использовании)"
    fi
    
    log "✓ Настройки модуля ядра применены"
}

# Отключение через параметры загрузки GRUB
disable_ipv6_grub() {
    log "Настройка отключения IPv6 в загрузчике..."
    
    if [ -f /etc/default/grub ]; then
        # Создаем backup
        cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d_%H%M%S)
        
        # Добавляем параметр отключения IPv6
        if grep -q "GRUB_CMDLINE_LINUX.*ipv6.disable=1" /etc/default/grub; then
            log "✓ Параметр ipv6.disable=1 уже присутствует в GRUB"
        else
            sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' /etc/default/grub
            log "✓ Параметр ipv6.disable=1 добавлен в GRUB"
        fi
        
        # Обновляем конфигурацию GRUB
        if command -v update-grub > /dev/null 2>&1; then
            update-grub > /dev/null 2>&1
            log "✓ GRUB обновлен"
        elif command -v grub2-mkconfig > /dev/null 2>&1; then
            grub2-mkconfig -o /boot/grub2/grub.cfg > /dev/null 2>&1
            log "✓ GRUB2 конфиг обновлен"
        else
            warn "Не удалось обновить GRUB (команда не найдена)"
        fi
    else
        warn "Файл /etc/default/grub не найден, пропускаем настройку GRUB"
    fi
}

# Проверка результата
verify_disabled() {
    log "Проверка отключения IPv6..."
    
    local ipv6_active=0
    local sysctl_configured=0
    
    # Проверяем активные IPv6 адреса
    if check_ipv6_active; then
        log "✓ IPv6 адреса не обнаружены"
    else
        warn "Обнаружены IPv6 адреса, требуется перезагрузка"
        ipv6_active=1
    fi
    
    # Проверяем настройки sysctl
    if check_ipv6_status; then
        log "✓ Настройки sysctl применены"
    else
        error "Настройки sysctl не применены корректно"
        sysctl_configured=1
    fi
    
    # Проверяем параметры в /proc
    local disabled_count=0
    local total_count=0
    
    for file in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
        if [ -f "$file" ]; then
            total_count=$((total_count + 1))
            if [ "$(cat "$file")" = "1" ]; then
                disabled_count=$((disabled_count + 1))
            fi
        fi
    done
    
    if [ $total_count -eq $disabled_count ]; then
        log "✓ Все интерфейсы отключены в /proc"
    else
        warn "Не все интерфейсы отключены в /proc: $disabled_count/$total_count"
    fi
    
    return $((ipv6_active + sysctl_configured))
}

# Основная функция
main() {
    log "=== Полное отключение IPv6 ==="
    
    check_root
    
    # Проверяем текущий статус в конфигах
    if check_ipv6_status && check_ipv6_active; then
        log "IPv6 уже отключен в системе"
        exit 0
    fi
    
    # Применяем все методы отключения
    disable_ipv6_sysctl
    disable_ipv6_immediate
    disable_ipv6_kernel
    disable_ipv6_grub
    
    # Проверяем результат
    if verify_disabled; then
        log "✓ IPv6 успешно отключен"
    else
        warn "IPv6 частично отключен, для полного отключения требуется перезагрузка"
    fi
    
    echo
    warn "РЕКОМЕНДАЦИЯ: Для гарантированного отключения выполните перезагрузку системы"
    echo "              командой: reboot"
    echo
    log "Текущий статус IPv6:"
    ip -6 addr show 2>/dev/null || log "IPv6 адреса не найдены"
}

# Запуск основной функции
main "$@"