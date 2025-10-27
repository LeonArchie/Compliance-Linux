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

# Настройка FileCreateMode для rsyslog
configure_rsyslog_filemode() {
    log "Настройка режима создания файлов rsyslog..."
    
    # Создаем директорию если не существует
    mkdir -p /etc/rsyslog.d/
    
    # Добавляем настройку FileCreateMode в основной конфиг
    if ! grep -q '^\$FileCreateMode' /etc/rsyslog.conf && ! grep -q '^\$FileCreateMode' /etc/rsyslog.d/*.conf 2>/dev/null; then
        echo '$FileCreateMode 0640' >> /etc/rsyslog.d/60-filemode.conf
        log "Добавлен \$FileCreateMode 0640 в конфигурацию"
    else
        # Обновляем существующие настройки
        sed -i 's/^\$FileCreateMode.*/\$FileCreateMode 0640/' /etc/rsyslog.conf 2>/dev/null || true
        for file in /etc/rsyslog.d/*.conf; do
            if [ -f "$file" ]; then
                sed -i 's/^\$FileCreateMode.*/\$FileCreateMode 0640/' "$file" 2>/dev/null || true
            fi
        done
    fi
}

# Основная функция
main() {
    log "=== Настройка rsyslog ==="
    
    check_root
    
    # Настройка rsyslog - отключение приема удаленных логов
    log "Отключение приема удаленных логов rsyslog..."
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

    # Настройка FileCreateMode
    configure_rsyslog_filemode

    # Проверка конфигурации
    log "Проверка конфигурации rsyslog..."
    if ! rsyslogd -N 1 > /dev/null 2>&1; then
        warn "Предупреждение: конфигурация rsyslog содержит предупреждения, но продолжаем выполнение"
    fi
    
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