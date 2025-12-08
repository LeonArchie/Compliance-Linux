#!/bin/bash

# Создание и настройка файла at.allow для контроля доступа к at

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

# Определение группы для at
determine_at_group() {
    if grep -Pq '^daemon\b' /etc/group; then
        echo "daemon"
    else
        echo "root"
    fi
}

# Создание файла at.allow
create_at_allow() {
    log "Создание файла /etc/at.allow..."
    
    if [ ! -f "/etc/at.allow" ]; then
        touch /etc/at.allow
        check_command "Создание файла /etc/at.allow"
    else
        warn "Файл /etc/at.allow уже существует"
    fi
}

# Настройка прав доступа для файла at.allow
set_at_allow_permissions() {
    local l_group=$(determine_at_group)
    
    log "Установка владельца и прав доступа для /etc/at.allow..."
    log "Используемая группа: $l_group"
    
    # Устанавливаем владельца и группу
    chown root:"$l_group" /etc/at.allow
    check_command "Установка владельца root:$l_group для /etc/at.allow"
    
    # Устанавливаем права доступа
    chmod 640 /etc/at.allow
    check_command "Установка прав 640 для /etc/at.allow"
}

# Настройка прав доступа для файла at.deny (если существует)
set_at_deny_permissions() {
    if [ -f "/etc/at.deny" ]; then
        local l_group=$(determine_at_group)
        
        log "Настройка прав доступа для существующего файла /etc/at.deny..."
        
        # Устанавливаем владельца и группу
        chown root:"$l_group" /etc/at.deny
        check_command "Установка владельца root:$l_group для /etc/at.deny"
        
        # Устанавливаем права доступа
        chmod 640 /etc/at.deny
        check_command "Установка прав 640 для /etc/at.deny"
    else
        warn "Файл /etc/at.deny не существует"
    fi
}

# Добавление пользователей в at.allow (опционально)
add_users_to_at_allow() {
    log "Добавление пользователей в /etc/at.allow..."
    
    # Очищаем файл (опционально)
    > /etc/at.allow
    
    # Добавляем root (рекомендуется)
    echo "root" >> /etc/at.allow
    check_command "Добавление пользователя root в at.allow"
    
    # Можно добавить других пользователей здесь
    # echo "username" >> /etc/at.allow
    
    log "Текущее содержимое /etc/at.allow:"
    cat /etc/at.allow
}

# Проверка текущих настроек
verify_settings() {
    log "=== Проверка текущих настроек ==="
    
    # Проверка at.allow
    if [ -f "/etc/at.allow" ]; then
        log "Файл /etc/at.allow:"
        echo "  Владелец: $(stat -c "%U:%G" /etc/at.allow)"
        echo "  Права: $(stat -c "%a" /etc/at.allow)"
        echo "  Содержимое:"
        cat /etc/at.allow | sed 's/^/    /'
    else
        error "Файл /etc/at.allow не создан"
    fi
    
    # Проверка at.deny
    if [ -f "/etc/at.deny" ]; then
        log "Файл /etc/at.deny:"
        echo "  Владелец: $(stat -c "%U:%G" /etc/at.deny)"
        echo "  Права: $(stat -c "%a" /etc/at.deny)"
    fi
    
    # Проверка политики доступа
    log "=== Политика доступа к at ==="
    if [ -f "/etc/at.allow" ]; then
        log "✅ Используется политика разрешений (at.allow)"
        log "Только пользователи из /etc/at.allow могут использовать at"
    elif [ -f "/etc/at.deny" ]; then
        warn "⚠️  Используется политика запретов (at.deny)"
        warn "Все пользователи, кроме указанных в /etc/at.deny, могут использовать at"
    else
        error "❌ ОПАСНО: Ни at.allow, ни at.deny не существуют"
        error "Только root может использовать at"
    fi
}

# Основная функция
main() {
    log "=== Создание и настройка файла at.allow ==="
    
    check_root
    
    # Создаем файл at.allow
    create_at_allow
    
    # Настраиваем права доступа
    set_at_allow_permissions
    set_at_deny_permissions
    
    # Добавляем пользователей (опционально)
    add_users_to_at_allow
    
    # Проверяем настройки
    verify_settings
    
    log "=== Настройка завершена успешно ==="
    log "Для применения изменений перезапустите демон at или перезагрузите систему"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"