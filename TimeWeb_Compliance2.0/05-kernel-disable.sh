#!/bin/bash

# Скрипт для проверки и отключения неиспользуемых модулей ядра
# Повышает безопасность системы в соответствии с CIS Benchmark

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
if [[ $EUID -ne 0 ]]; then
    error "Этот скрипт должен быть запущен с правами root"
    exit 1
fi

# Список модулей для отключения с описанием
# cramfs    - Устаревшая сжатая ФС только для чтения
# freevxfs  - ФС VxFS (Veritas File System)
# hfs       - Hierarchical File System (Apple Macintosh)
# hfsplus   - HFS+ ФС (современные системы Apple)  
# jffs2     - Journaling Flash File System v2
# overlayfs - Overlay File System (объединение ФС)
# squashfs  - Сжатая ФС только для чтения (часто в live CD)
# udf       - Universal Disk Format (DVD, Blu-ray)
# usb-storage - USB накопители
# dccp      - Datagram Congestion Control Protocol
# tipc      - Transparent Inter-Process Communication  
# rds       - Reliable Datagram Sockets
# sctp      - Stream Control Transmission Protocol

MODULES=(
    "cramfs"
    "freevxfs" 
    "hfs"
    "hfsplus"
    "jffs2"
    "overlayfs"
    "squashfs"
    "udf"
    "usb-storage"
    "dccp"
    "tipc"
    "rds"
    "sctp"
)

CONFIG_FILE="/etc/modprobe.d/disable-unused-modules.conf"

log "Начало отключения неиспользуемых модулей ядра"
echo

# Создаем конфигурационный файл если не существует
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "Создаем файл конфигурации: $CONFIG_FILE"
    touch "$CONFIG_FILE"
fi

DISABLED_COUNT=0
SKIPPED_COUNT=0

for MODULE in "${MODULES[@]}"; do
    echo "=== Обработка модуля: $MODULE ==="
    
    # Проверяем существует ли модуль в системе
    if ! modinfo "$MODULE" &>/dev/null; then
        warn "Модуль $MODULE не найден в системе"
        ((SKIPPED_COUNT++))
        echo
        continue
    fi
    
    # Проверяем загружен ли модуль и используется ли
    if lsmod | grep -q "^${MODULE}[[:space:]]"; then
        USAGE_COUNT=$(lsmod | grep "^${MODULE}[[:space:]]" | awk '{print $3}')
        if [[ $USAGE_COUNT -gt 0 ]]; then
            warn "Модуль $MODULE используется ($USAGE_COUNT использований), пропускаем"
            ((SKIPPED_COUNT++))
            echo
            continue
        else
            log "Модуль $MODULE загружен, но не используется, выгружаем"
            modprobe -r "$MODULE" 2>/dev/null || true
        fi
    else
        log "Модуль $MODULE не загружен"
    fi
    
    # Добавляем правила отключения в конфигурационный файл
    if ! grep -q "install $MODULE /bin/false" "$CONFIG_FILE"; then
        echo "install $MODULE /bin/false" >> "$CONFIG_FILE"
        log "Добавлено: install $MODULE /bin/false"
    fi
    
    if ! grep -q "blacklist $MODULE" "$CONFIG_FILE"; then
        echo "blacklist $MODULE" >> "$CONFIG_FILE"
        log "Добавлено: blacklist $MODULE"
    fi
    
    log "Модуль $MODULE успешно отключен"
    ((DISABLED_COUNT++))
    echo
done

# Обновляем initramfs если были изменения
if [[ $DISABLED_COUNT -gt 0 ]]; then
    log "Обновляем initramfs..."
    if command -v update-initramfs &> /dev/null; then
        update-initramfs -u
    elif command -v dracut &> /dev/null; then
        dracut -f
    elif command -v mkinitcpio &> /dev/null; then
        mkinitcpio -P
    fi
    log "Initramfs обновлен"
fi

log "=== РЕЗУЛЬТАТЫ ==="
log "Отключено модулей: $DISABLED_COUNT"
log "Пропущено модулей: $SKIPPED_COUNT"

if [[ $DISABLED_COUNT -gt 0 ]]; then
    warn "Рекомендуется перезагрузить систему для применения изменений"
fi

log "Проверка завершена"nan