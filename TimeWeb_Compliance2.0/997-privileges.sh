#!/bin/bash

# Настройка прав доступа к системным файлам и параметров ядра

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
    log "=== Настройка прав доступа к системным файлам и параметров ядра ==="
    
    check_root
    
    # Настройка прав доступа к системным файлам
    log "Настройка прав доступа к системным файлам..."
    
    # Настройка прав для gshadow-
    if [ -f "/etc/gshadow-" ]; then
        chown root:shadow /etc/gshadow-
        chmod 640 /etc/gshadow-
        log "Права для /etc/gshadow- установлены"
    else
        warn "Файл /etc/gshadow- не найден"
    fi

    # Настройка прав для утилит audit
    log "Настройка прав для утилит audit..."
    chmod 750 /sbin/auditctl /sbin/aureport /sbin/ausearch /sbin/autrace /sbin/auditd /sbin/augenrules

    # Настройка прав для opasswd файлов
    log "Настройка прав для opasswd файлов..."
    for file in /etc/security/opasswd /etc/security/opasswd.old; do
        if [ -e "$file" ]; then
            chmod 600 "$file"
            chown root:root "$file"
            log "Права установлены для $file"
        else
            warn "Файл $file не найден"
        fi
    done

    # Проверка дублирующихся имен групп
    log "Проверка дублирующихся имен групп..."
    if [ $(cut -f1 -d":" /etc/group | sort | uniq -dc | wc -l) -eq 0 ]; then
        log "✓ Дублирующихся имен групп не найдено"
    else
        warn "⚠ Обнаружены дублирующиеся имена групп"
        cut -f1 -d":" /etc/group | sort | uniq -dc
    fi
    
    check_command "Настройка прав доступа"

    # Настройка параметров ядра для аудита
    log "Настройка параметров ядра для аудита..."
    
    # Создание резервной копии grub
    if [ -f "/etc/default/grub" ]; then
        cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d)
        log "Создана резервная копия /etc/default/grub"
    fi

    # Добавление параметров аудита в GRUB
    log "Добавление параметров аудита в GRUB..."
    if grep -q "GRUB_CMDLINE_LINUX=" /etc/default/grub; then
        if ! grep -q "audit=1" /etc/default/grub; then
            sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 audit=1 audit_backlog_limit=8192"/' /etc/default/grub
            log "Параметры аудита добавлены в GRUB"
        else
            log "Параметры аудита уже присутствуют в GRUB"
        fi
    else
        warn "Не удалось найти GRUB_CMDLINE_LINUX в конфигурации"
    fi

    # Обновление GRUB
    log "Обновление конфигурации GRUB..."
    update-grub
    check_command "Настройка параметров ядра"
    
    log "Текущие параметры ядра:"
    grep "GRUB_CMDLINE_LINUX" /etc/default/grub
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"