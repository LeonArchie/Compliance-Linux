#!/bin/bash

# Настройка тайм-аута сессии

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
    log "=== Настройка тайм-аута сессии ==="
    
    check_root
    
    # Настройка тайм-аута сессии
    log "Настройка тайм-аута сессии..."
    tee /etc/profile.d/session-timeout.sh > /dev/null << 'EOF'
#!/bin/bash
# Session timeout configuration for security compliance
TMOUT=900
readonly TMOUT
export TMOUT
EOF

    chmod 644 /etc/profile.d/session-timeout.sh

    # Закомментирование TMOUT в других файлах
    log "Закомментирование TMOUT в других файлах..."
    sed -i 's/^\([^#]*TMOUT\)/#\1/' /etc/bashrc 2>/dev/null || true
    sed -i 's/^\([^#]*TMOUT\)/#\1/' /etc/profile 2>/dev/null || true
    find /etc/profile.d/ -name "*.sh" ! -name "session-timeout.sh" -exec sed -i 's/^\([^#]*TMOUT\)/#\1/' {} \; 2>/dev/null || true

    source /etc/profile.d/session-timeout.sh
    check_command "Настройка тайм-аута сессии"

    log "=== Настройка завершена ==="
    warn "Для применения всех изменений требуется перезагрузка системы."
    warn "Выполните: sudo reboot"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"