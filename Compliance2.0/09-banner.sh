#!/bin/bash

# Настройка баннеров входа и MOTD

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
    log "=== Настройка баннеров входа и MOTD ==="
    
    check_root
    
    # Настройка баннера входа
    log "Настройка баннера входа..."
    tee /etc/issue.net > /dev/null << 'EOF'
Только для авторизованных пользователей.
Все действия регистрируются.
Поддержка: it@school59-ekb.ru

Сервер: \n
Текущая дата: \d
Текущее время: \t
Подключенных пользователей: \u
EOF
    check_command "Настройка баннера входа"

    # Настройка стартовой страницы MOTD
    log "Настройка стартовой страницы..."
    bash -c 'cat > /etc/update-motd.d/10-help-text << "EOF"
#!/bin/sh
printf " =========================================================\n"
printf "\n"
printf " Муниципальное автономное общеобразовательное учреждение\n"
printf " Средняя общеобразовательная школа № 59\n"
printf "\n"
printf " Только для авторизованных пользователей.\n"
printf " Все действия регистрируются.\n"
printf " Поддержка: it@school59-ekb.ru\n"
printf "\n"
printf " =========================================================\n"
EOF'

    chmod +x /etc/update-motd.d/10-help-text
    chmod -x /etc/update-motd.d/50-motd-news
    chmod -x /etc/update-motd.d/90-updates-available
    check_command "Настройка стартовой страницы"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"