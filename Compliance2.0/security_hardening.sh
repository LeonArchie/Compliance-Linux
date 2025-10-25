#!/bin/bash

# Управляющий скрипт для настройки безопасности системы
# Включает настройку сети, времени, SSH, аудита, мониторинга и других компонентов

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Функция подтверждения выполнения
confirm_execution() {
    local script_name=$1
    warn "Выполнить скрипт $script_name? (y/N)"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Функция запуска скрипта
run_script() {
    local script=$1
    local script_name=$(basename "$script")
    
    if [[ ! -f "$script" ]]; then
        error "Скрипт $script не найден"
        return 1
    fi
    
    info "Запуск скрипта: $script_name"
    
    # Даем права на выполнение если нужно
    if [[ ! -x "$script" ]]; then
        chmod +x "$script"
    fi
    
    # Запускаем скрипт
    if bash "$script"; then
        log "Скрипт $script_name выполнен успешно"
    else
        error "Скрипт $script_name завершился с ошибкой"
        return 1
    fi
}

# Основная функция
main() {
    check_root
    
    log "=== Управляющий скрипт настройки безопасности ==="
    log "Дата: $(date)"
    log "Хост: $(hostname)"
    echo
    
    # Массив всех скриптов в порядке выполнения
    scripts=(
        "01-init_network.sh"
        "02-Mount.sh"
        "03-update_a_time.sh"
        "05-kernel-disable.sh"
        "06-grub-pass.sh"
        "07-Service.sh"
        "08-session.sh"
        "09-banner.sh"
        "10-network.sh"
        "11-sudo.sh"
        "12-rsyslog.sh"
        "13-logs.sh"
        "14-SSH.sh"
        "15-cron.sh"
        "16-Network2.sh"
        "17-sudo_a_pass_a_root.sh"
        "995-audit.sh"
        "996-privileges.sh"
        "997-AIDE.sh"
        "998-Wazuh.sh"
    )
    
    # Показать меню
    echo "Выберите опцию:"
    echo "1) Только настройка сети (01-init_network.sh)"
    echo "2) Все скрипты с 02 по последний"
    echo "3) Выбрать конкретный скрипт"
    echo "4) Все скрипты по порядку"
    echo "q) Выход"
    echo
    
    read -p "Ваш выбор: " choice
    
    case $choice in
        1)
            info "Запуск только настройки сети..."
            run_script "01-init_network.sh"
            ;;
        2)
            info "Запуск скриптов с 02 по последний..."
            for script in "${scripts[@]:1}"; do
                if confirm_execution "$script"; then
                    run_script "$script"
                else
                    warn "Пропуск скрипта $script"
                fi
                echo
            done
            ;;
        3)
            info "Доступные скрипты:"
            for i in "${!scripts[@]}"; do
                echo "$((i+1))) ${scripts[$i]}"
            done
            echo
            read -p "Введите номер скрипта: " script_num
            if [[ $script_num -ge 1 && $script_num -le ${#scripts[@]} ]]; then
                run_script "${scripts[$((script_num-1))]}"
            else
                error "Неверный номер скрипта"
            fi
            ;;
        4)
            info "Запуск всех скриптов по порядку..."
            for script in "${scripts[@]}"; do
                if confirm_execution "$script"; then
                    run_script "$script"
                else
                    warn "Пропуск скрипта $script"
                fi
                echo
            done
            ;;
        q|Q)
            info "Выход"
            exit 0
            ;;
        *)
            error "Неверный выбор"
            exit 1
            ;;
    esac
    
    log "=== Настройка безопасности завершена ==="
    warn "Рекомендуется перезагрузить систему для применения всех изменений"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"