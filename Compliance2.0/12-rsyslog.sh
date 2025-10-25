#!/bin/bash

# Настройка rsyslog

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
    log "=== Настройка rsyslog ==="
    
    check_root
    
    # Настройка rsyslog
    log "Настройка rsyslog..."
    sed -i 's/^\s*$ModLoad imtcp/#$ModLoad imtcp/' /etc/rsyslog.conf
    sed -i 's/^\s*$InputTCPServerRun/#$InputTCPServerRun/' /etc/rsyslog.conf
    sed -i 's/^\s*module(load="imtcp")/#module(load="imtcp")/' /etc/rsyslog.conf
    sed -i 's/^\s*input(type="imtcp" port="514")/#input(type="imtcp" port="514")/' /etc/rsyslog.conf

    # Обработка файлов в директории rsyslog.d
    for file in /etc/rsyslog.d/*.conf; do
        if [ -f "$file" ]; then
            log "Обработка файла: $file"
            sed -i 's/^\s*$ModLoad imtcp/#$ModLoad imtcp/' "$file"
            sed -i 's/^\s*$InputTCPServerRun/#$InputTCPServerRun/' "$file"
            sed -i 's/^\s*module(load="imtcp")/#module(load="imtcp")/' "$file"
            sed -i 's/^\s*input(type="imtcp" port="514")/#input(type="imtcp" port="514")/' "$file"
        fi
    done

    # Настройка прав доступа к файлам логов
    log "Настройка прав доступа к файлам логов..."
    sed -i '/^global(/a\\n# Set file creation mode to 0640\n$FileCreateMode 0640' /etc/rsyslog.conf

    # Проверка конфигурации
    log "Проверка конфигурации rsyslog..."
    rsyslogd -N 1 > /dev/null 2>&1
    
    # Перезагрузка службы
    log "Перезагрузка службы rsyslog..."
    systemctl reload-or-restart rsyslog
    check_command "Настройка rsyslog"
    
    log "Статус службы rsyslog:"
    systemctl status rsyslog --no-pager -l
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"