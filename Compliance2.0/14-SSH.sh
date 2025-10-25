#!/bin/bash

# Настройка SSH

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

# Функция проверки наличия SSH-ключа у пользователя
check_ssh_key() {
    local user="$1"
    log "Проверка наличия SSH-ключа у пользователя $user..."
    
    # Проверяем существование пользователя
    if id "$user" &>/dev/null; then
        # Проверяем наличие SSH-ключа в стандартных местах
        local ssh_dir="/home/$user/.ssh"
        local authorized_keys="$ssh_dir/authorized_keys"
        
        if [ -d "$ssh_dir" ] && [ -f "$authorized_keys" ] && [ -s "$authorized_keys" ]; then
            local key_count=$(grep -c "ssh-" "$authorized_keys" 2>/dev/null || echo 0)
            if [ $key_count -gt 0 ]; then
                log "✓ Найден SSH-ключ у пользователя $user (ключей: $key_count)"
                return 0
            else
                error "Файл authorized_keys существует, но не содержит валидных SSH-ключей"
                return 1
            fi
        else
            error "У пользователя $user не настроен SSH-ключ"
            log "  Каталог .ssh существует: $([ -d "$ssh_dir" ] && echo "да" || echo "нет")"
            log "  Файл authorized_keys существует: $([ -f "$authorized_keys" ] && echo "да" || echo "нет")"
            log "  Файл authorized_keys не пустой: $([ -s "$authorized_keys" ] && echo "да" || echo "нет")"
            return 1
        fi
    else
        warn "Пользователь $user не существует"
        return 1
    fi
}

# Функция настройки SSH
configure_ssh() {
    log "Настройка SSH..."
    
    # Создаем backup конфигурации
    if [ ! -f "/etc/ssh/sshd_config.backup" ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
        log "Создан backup конфигурации SSH: /etc/ssh/sshd_config.backup"
    fi
    
    # Применяем настройки SSH
    log "Применение настроек SSH..."
    sed -i 's/^Include/#Include/g' /etc/ssh/sshd_config
    sed -i 's/^#Port 22/Port 56314/g' /etc/ssh/sshd_config
    sed -i 's/^#SyslogFacility AUTH/SyslogFacility AUTH/g' /etc/ssh/sshd_config
    sed -i 's/^#LogLevel INFO/LogLevel INFO/g' /etc/ssh/sshd_config
    sed -i 's/^#LoginGraceTime 2m/LoginGraceTime 30/g' /etc/ssh/sshd_config
    sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
    sed -i 's/^#MaxAuthTries 6/MaxAuthTries 3/g' /etc/ssh/sshd_config
    sed -i 's/^#MaxSessions 10/MaxSessions 2/g' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

    # Перезагрузка службы SSH
    log "Перезагрузка службы SSH..."
    systemctl restart ssh
    check_command "Настройка SSH завершена"
    
    log "SSH настроен на порт 56314, аутентификация по паролю отключена"
    log "Текущие настройки SSH:"
    grep -E "^(Port|PasswordAuthentication|PermitRootLogin)" /etc/ssh/sshd_config
}

# Основная логика скрипта
main() {
    log "=== Настройка SSH ==="
    
    check_root
    
    # Проверяем наличие SSH-ключа у пользователя archie
    if check_ssh_key "archie"; then
        log "SSH-ключ найден, выполняется настройка SSH..."
        configure_ssh
    else
        error "=== НАСТРОЙКА SSH ПРОПУЩЕНА ==="
        error "Причина: у пользователя archie не настроен SSH-ключ"
        log "Для настройки SSH выполните следующие шаги:"
        log "1. На клиенте: ssh-keygen -t ed25519 -C 'ваш_комментарий'"
        log "2. Скопируйте ключ: ssh-copy-id -p 22 archie@$(hostname -I | awk '{print $1}')"
        log "3. Проверьте подключение: ssh -p 22 archie@$(hostname -I | awk '{print $1}')"
        log "4. После успешной настройки ключа запустите этот скрипт снова"
        warn "================================="
    fi
    
    log "=== Настройка системы завершена ==="
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main