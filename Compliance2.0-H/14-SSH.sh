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

# Функция настройки прав доступа к файлам SSH
configure_ssh_permissions() {
    log "Настройка прав доступа к файлам SSH..."
    
    # Устанавливаем правильные права для основного конфигурационного файла
    chmod u-x,og-rwx /etc/ssh/sshd_config
    chown root:root /etc/ssh/sshd_config
    check_command "Установка прав для /etc/ssh/sshd_config"
    
    # Устанавливаем правильные права для файлов в каталоге конфигурации
    if [ -d "/etc/ssh/sshd_config.d" ]; then
        find /etc/ssh/sshd_config.d -type f -name "*.conf" | while read -r config_file; do
            if [ -e "$config_file" ]; then
                chmod u-x,og-rwx "$config_file"
                chown root:root "$config_file"
                log "✓ Установлены права для $config_file"
            fi
        done
    fi
    
    log "Права доступа к файлам SSH настроены"
}

# Функция настройки ограничения доступа по пользователям
configure_ssh_access() {
    log "Настройка ограничения доступа по пользователям..."
    
    # Добавляем разрешение только для пользователя archie
    if ! grep -q "^AllowUsers" /etc/ssh/sshd_config; then
        echo "AllowUsers archie" >> /etc/ssh/sshd_config
        log "✓ Добавлено ограничение AllowUsers archie"
    else
        log "✓ Ограничение AllowUsers уже настроено"
    fi
}

# Функция настройки баннера
configure_ssh_banner() {
    log "Настройка баннера SSH..."
    
    # Устанавливаем баннер
    if ! grep -q "^Banner" /etc/ssh/sshd_config; then
        echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
        log "✓ Настроен баннер /etc/issue.net"
    else
        log "✓ Баннер уже настроен"
    fi
}

# Функция настройки таймаутов SSH
configure_ssh_timeouts() {
    log "Настройка таймаутов SSH..."
    
    # Устанавливаем ClientAliveInterval и ClientAliveCountMax
    sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 15/g' /etc/ssh/sshd_config
    sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 3/g' /etc/ssh/sshd_config
    
    # Если параметры не существуют, добавляем их
    if ! grep -q "^ClientAliveInterval" /etc/ssh/sshd_config; then
        echo "ClientAliveInterval 15" >> /etc/ssh/sshd_config
    fi
    
    if ! grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config; then
        echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
    fi
    
    log "✓ Таймауты SSH настроены: ClientAliveInterval=15, ClientAliveCountMax=3"
}

# Функция отключения переадресации
configure_ssh_forwarding() {
    log "Настройка отключения переадресации SSH..."
    
    # Отключаем все виды переадресации
    sed -i 's/^#*DisableForwarding.*/DisableForwarding yes/g' /etc/ssh/sshd_config
    
    # Если параметр не существует, добавляем его
    if ! grep -q "^DisableForwarding" /etc/ssh/sshd_config; then
        echo "DisableForwarding yes" >> /etc/ssh/sshd_config
    fi
    
    log "✓ Переадресация SSH отключена"
}

# Функция настройки MAC-алгоритмов
configure_ssh_macs() {
    log "Настройка MAC-алгоритмов SSH..."
    
    # Определяем безопасные MAC-алгоритмы
    local safe_macs="hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com"
    
    # Запрещаем слабые MAC-алгоритмы
    local disabled_macs="-hmac-md5,-hmac-md5-96,-hmac-ripemd160,-hmac-sha1,-hmac-sha1-96,-umac-64@openssh.com,-umac-128@openssh.com,-hmac-md5-etm@openssh.com,-hmac-md5-96-etm@openssh.com,-hmac-ripemd160-etm@openssh.com,-hmac-sha1-etm@openssh.com,-hmac-sha1-96-etm@openssh.com,-umac-64-etm@openssh.com,-umac-128-etm@openssh.com"
    
    # Устанавливаем MAC-алгоритмы
    sed -i 's/^#*MACs.*/MACs '"$safe_macs"'/g' /etc/ssh/sshd_config
    
    # Если параметр не существует, добавляем его
    if ! grep -q "^MACs" /etc/ssh/sshd_config; then
        echo "MACs $safe_macs" >> /etc/ssh/sshd_config
    fi
    
    log "✓ Безопасные MAC-алгоритмы настроены"
}

# Функция настройки SSH
configure_ssh() {
    log "Настройка SSH..."
    
    # Создаем backup конфигурации
    if [ ! -f "/etc/ssh/sshd_config.backup" ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
        log "Создан backup конфигурации SSH: /etc/ssh/sshd_config.backup"
    fi
    
    # Применяем основные настройки SSH
    log "Применение основных настроек SSH..."
    sed -i 's/^Include/#Include/g' /etc/ssh/sshd_config
    sed -i 's/^#Port 22/Port 56314/g' /etc/ssh/sshd_config
    sed -i 's/^#SyslogFacility AUTH/SyslogFacility AUTH/g' /etc/ssh/sshd_config
    sed -i 's/^#LogLevel INFO/LogLevel INFO/g' /etc/ssh/sshd_config
    sed -i 's/^#LoginGraceTime 2m/LoginGraceTime 30/g' /etc/ssh/sshd_config
    sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
    sed -i 's/^#MaxAuthTries 6/MaxAuthTries 3/g' /etc/ssh/sshd_config
    sed -i 's/^#MaxSessions 10/MaxSessions 2/g' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

    # Применяем дополнительные настройки безопасности
    configure_ssh_permissions
    configure_ssh_access
    configure_ssh_banner
    configure_ssh_timeouts
    configure_ssh_forwarding
    configure_ssh_macs
    configure_ssh_maxstartups

    # Перезагрузка службы SSH
    log "Перезагрузка службы SSH..."
    systemctl restart ssh
    check_command "Настройка SSH завершена"
    
    log "SSH настроен на порт 56314, аутентификация по паролю отключена"
    log "Текущие настройки SSH:"
    grep -E "^(Port|PasswordAuthentication|PermitRootLogin|AllowUsers|Banner|ClientAliveInterval|ClientAliveCountMax|DisableForwarding|MACs)" /etc/ssh/sshd_config
}

configure_ssh_maxstartups() {
    log "Настройка MaxStartups..."
    
    # Устанавливаем безопасные значения: 10:30:60
    # Первое число: 1-10, второе: 1-30, третье: 1-60
    sed -i 's/^#*MaxStartups.*/MaxStartups 10:30:60/g' /etc/ssh/sshd_config
    
    # Если параметр не существует, добавляем его
    if ! grep -q "^MaxStartups" /etc/ssh/sshd_config; then
        echo "MaxStartups 10:30:60" >> /etc/ssh/sshd_config
    fi
    
    log "✓ MaxStartups настроен: 10:30:60"
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