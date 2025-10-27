#!/bin/bash

# Настройка прав доступа для cron

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

# Проверка наличия cron
check_cron_installed() {
    if ! command -v cron &> /dev/null && ! command -v crond &> /dev/null; then
        warn "Cron не установлен в системе"
        return 1
    fi
    return 0
}

# Настройка прав для файла /etc/crontab
secure_crontab_file() {
    log "Настройка прав доступа для /etc/crontab..."
    
    if [ -f /etc/crontab ]; then
        chown root:root /etc/crontab
        chmod og-rwx /etc/crontab
        check_command "Установка прав для /etc/crontab"
        
        # Проверка результата
        local current_mode=$(stat -c "%a" /etc/crontab)
        local current_owner=$(stat -c "%U:%G" /etc/crontab)
        
        if [ "$current_mode" = "600" ] && [ "$current_owner" = "root:root" ]; then
            log "Права /etc/crontab настроены правильно: mode=$current_mode, owner=$current_owner"
        else
            warn "Права /etc/crontab могут быть настроены некорректно: mode=$current_mode, owner=$current_owner"
        fi
    else
        warn "Файл /etc/crontab не найден"
    fi
}

# Настройка прав для каталогов cron
secure_cron_directory() {
    local dir_path="$1"
    local dir_name="$2"
    
    log "Настройка прав доступа для $dir_path..."
    
    if [ -d "$dir_path" ]; then
        chown root:root "$dir_path"
        chown root:root /etc/cron.allow
        chmod og-rwx "$dir_path"
        check_command "Установка прав для $dir_path"
        
        # Проверка результата
        local current_mode=$(stat -c "%a" "$dir_path")
        local current_owner=$(stat -c "%U:%G" "$dir_path")
        
        if [ "$current_mode" = "700" ] && [ "$current_owner" = "root:root" ]; then
            log "Права $dir_path настроены правильно: mode=$current_mode, owner=$current_owner"
        else
            warn "Права $dir_path могут быть настроены некорректно: mode=$current_mode, owner=$current_owner"
        fi
    else
        warn "Каталог $dir_path не найден"
    fi
}

# Настройка файлов cron.allow и cron.deny
secure_cron_access_files() {
    log "Настройка файлов контроля доступа cron..."
    
    # Определяем группу для cron файлов
    local cron_group="root"
    if grep -Pq -- '^\h*crontab\:' /etc/group; then
        cron_group="crontab"
        log "Обнаружена группа crontab, будет использована для владения файлами"
    fi
    
    # Обработка cron.allow
    if [ ! -e "/etc/cron.allow" ]; then
        log "Создание файла /etc/cron.allow..."
        touch /etc/cron.allow
    fi
    
    if [ -f "/etc/cron.allow" ]; then
        chmod u-x,g-wx,o-rwx /etc/cron.allow
        chown root:"$cron_group" /etc/cron.allow
        check_command "Настройка прав для /etc/cron.allow"
    fi
    
    # Обработка cron.deny (если существует)
    if [ -e "/etc/cron.deny" ]; then
        chmod u-x,g-wx,o-rwx /etc/cron.deny
        chown root:"$cron_group" /etc/cron.deny
        check_command "Настройка прав для /etc/cron.deny"
    fi
    
    # Проверка результатов для cron.allow
    if [ -f "/etc/cron.allow" ]; then
        local allow_mode=$(stat -c "%a" /etc/cron.allow)
        local allow_owner=$(stat -c "%U:%G" /etc/cron.allow)
        
        if [ "$allow_mode" = "640" ] && [ "$allow_owner" = "root:$cron_group" ]; then
            log "Права /etc/cron.allow настроены правильно: mode=$allow_mode, owner=$allow_owner"
        else
            warn "Права /etc/cron.allow могут быть настроены некорректно: mode=$allow_mode, owner=$allow_owner"
        fi
    fi
}

# Основная функция
main() {
    log "=== Настройка прав доступа для cron ==="
    
    check_root
    
    # Проверяем наличие cron
    if ! check_cron_installed; then
        warn "Cron не обнаружен, некоторые операции могут быть пропущены"
    fi
    
    # Настройка файла crontab
    secure_crontab_file
    
    # Настройка каталогов cron
    secure_cron_directory "/etc/cron.hourly" "cron.hourly"
    secure_cron_directory "/etc/cron.daily" "cron.daily" 
    secure_cron_directory "/etc/cron.weekly" "cron.weekly"
    secure_cron_directory "/etc/cron.monthly" "cron.monthly"
    secure_cron_directory "/etc/cron.d" "cron.d"
    
    # Настройка файлов контроля доступа
    secure_cron_access_files
    
    log "=== Проверка текущих прав доступа ==="
    
    # Вывод текущих прав для проверки
    local cron_files=("/etc/crontab" "/etc/cron.hourly" "/etc/cron.daily" "/etc/cron.weekly" "/etc/cron.monthly" "/etc/cron.d")
    
    for item in "${cron_files[@]}"; do
        if [ -e "$item" ]; then
            local mode=$(stat -c "%a" "$item")
            local owner=$(stat -c "%U:%G" "$item")
            log "$item: mode=$mode, owner=$owner"
        fi
    done
    
    if [ -f "/etc/cron.allow" ]; then
        local allow_mode=$(stat -c "%a" /etc/cron.allow)
        local allow_owner=$(stat -c "%U:%G" /etc/cron.allow)
        log "/etc/cron.allow: mode=$allow_mode, owner=$allow_owner"
    fi
    
    if [ -f "/etc/cron.deny" ]; then
        local deny_mode=$(stat -c "%a" /etc/cron.deny)
        local deny_owner=$(stat -c "%U:%G" /etc/cron.deny)
        log "/etc/cron.deny: mode=$deny_mode, owner=$deny_owner"
    fi
    
    log "Настройка прав доступа для cron завершена"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"