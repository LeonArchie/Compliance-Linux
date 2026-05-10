#!/bin/bash

# Настройка параметров монтирования файловых систем

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
    log "=== Настройка параметров монтирования файловых систем ==="
    
    check_root
    
    # Создаем резервную копию
    log "Создание резервной копии fstab..."
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    check_command "Создание резервной копии"

    # Обновляем параметры для каждой точки монтирования
    log "Обновление параметров монтирования..."
    sed -i '/\/tmp[[:space:]]/s/defaults[^,]*/defaults,nodev,nosuid,noexec/' /etc/fstab
    sed -i '/\/home[[:space:]]/s/defaults[^,]*/defaults,nodev,nosuid/' /etc/fstab
    sed -i '/\/var[[:space:]]/s/defaults[^,]*/defaults,nodev,nosuid/' /etc/fstab
    sed -i '/\/var\/tmp[[:space:]]/s/defaults[^,]*/defaults,nodev,nosuid,noexec/' /etc/fstab
    sed -i '/\/var\/log[[:space:]]/s/defaults[^,]*/defaults,nodev,nosuid,noexec/' /etc/fstab
    sed -i '/\/var\/log\/audit[[:space:]]/s/defaults[^,]*/defaults,nodev,nosuid,noexec/' /etc/fstab

    # Очищаем возможные существующие дубликаты параметров
    sed -i 's/,nodev,nodev/,nodev/g; s/,nosuid,nosuid/,nosuid/g; s/,noexec,noexec/,noexec/g' /etc/fstab
    sed -i 's/,nodev,nosuid,noexec,nodev,nosuid,noexec/,nodev,nosuid,noexec/g;' /etc/fstab
    
    # Перезагружаем systemd
    log "Перезагрузка systemd..."
    systemctl daemon-reload
    check_command "Перезагрузка systemd"

    # Проверяем синтаксис
    log "Проверка синтаксиса fstab..."
    mount -a --fake
    check_command "Проверка синтаксиса fstab"

    # Перемонтируем файловые системы
    log "Перемонтирование файловых систем..."
    mount -o remount /tmp
    mount -o remount /home
    mount -o remount /var
    mount -o remount /var/tmp
    mount -o remount /var/log
    mount -o remount /var/log/audit
    check_command "Перемонтирование файловых систем"

    # Проверяем результат
    log "=== Результат в fstab ==="
    grep -E "(tmp|home|var)" /etc/fstab

    log "=== Текущие параметры монтирования ==="
    mount | grep -E "/(tmp|home|var|var/tmp|var/log|var/log/audit) "
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"