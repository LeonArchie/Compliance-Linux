#!/bin/bash

# Настройка SSH для root

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

# Функция проверки наличия SSH-ключа у root
check_root_ssh_key() {
    log "Проверка наличия SSH-ключа у пользователя root..."
    
    local ssh_dir="/root/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"
    
    if [ -d "$ssh_dir" ] && [ -f "$authorized_keys" ] && [ -s "$authorized_keys" ]; then
        local key_count=$(grep -c "ssh-" "$authorized_keys" 2>/dev/null || echo 0)
        if [ $key_count -gt 0 ]; then
            log "✓ Найден SSH-ключ у пользователя root (ключей: $key_count)"
            return 0
        else
            error "Файл authorized_keys существует, но не содержит валидных SSH-ключей"
            return 1
        fi
    else
        error "У пользователя root не настроен SSH-ключ"
        log "  Каталог .ssh существует: $([ -d "$ssh_dir" ] && echo "да" || echo "нет")"
        log "  Файл authorized_keys существует: $([ -f "$authorized_keys" ] && echo "да" || echo "нет")"
        log "  Файл authorized_keys не пустой: $([ -s "$authorized_keys" ] && echo "да" || echo "нет")"
        return 1
    fi
}

# Функция проверки безопасности конфигурации для root
check_root_access_safety() {
    log "Проверка безопасности конфигурации для root..."
    
    local has_key=false
    local passwd_auth=false
    local root_login=""
    
    # Проверяем наличие ключа
    if check_root_ssh_key; then
        has_key=true
    fi
    
    # Проверяем настройки аутентификации
    if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
        passwd_auth=true
    fi
    
    if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
        root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | tail -1 | awk '{print $2}')
    else
        root_login="not_set"
    fi
    
    # Анализируем безопасность конфигурации
    if [ "$has_key" = true ] && [ "$root_login" = "prohibit-password" ] && [ "$passwd_auth" = false ]; then
        log "✓ Безопасная конфигурация для root: ключ + запрет пароля"
        return 0
    elif [ "$has_key" = true ] && [ "$root_login" = "yes" ] && [ "$passwd_auth" = false ]; then
        warn "⚠ Root доступ разрешен только по ключу"
        warn "Рекомендуется использовать 'PermitRootLogin prohibit-password' вместо 'yes'"
        return 0
    elif [ "$has_key" = false ] && [ "$root_login" = "yes" ] && [ "$passwd_auth" = true ]; then
        error "✗ ОПАСНО: Root доступ разрешен по паролю без SSH-ключа"
        return 1
    else
        warn "⚠ Смешанная конфигурация"
        warn "  SSH ключ: $has_key"
        warn "  Парольная аутентификация: $passwd_auth"
        warn "  PermitRootLogin: $root_login"
        return 0
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
    
    # Устанавливаем права для каталога .ssh root
    local root_ssh_dir="/root/.ssh"
    if [ -d "$root_ssh_dir" ]; then
        chmod 700 "$root_ssh_dir"
        chown root:root "$root_ssh_dir"
        log "✓ Установлены права для $root_ssh_dir"
        
        # Права для authorized_keys
        if [ -f "$root_ssh_dir/authorized_keys" ]; then
            chmod 600 "$root_ssh_dir/authorized_keys"
            chown root:root "$root_ssh_dir/authorized_keys"
            log "✓ Установлены права для $root_ssh_dir/authorized_keys"
        fi
    fi
    
    log "Права доступа к файлам SSH настроены"
}

# Функция настройки доступа root
configure_root_access() {
    log "Настройка доступа root..."
    
    local root_access_method="$1"
    
    case "$root_access_method" in
        "key-only")
            # Разрешаем root доступ только по ключу
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
            log "✓ Root доступ разрешен только по SSH-ключу"
            ;;
        "password-only")
            # Разрешаем root доступ только по паролю (не рекомендуется)
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
            sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
            warn "⚠ Root доступ разрешен по паролю (не рекомендуется для продакшена)"
            ;;
        "key-and-password")
            # Разрешаем root доступ по ключу и паролю
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
            sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
            warn "⚠ Root доступ разрешен по ключу и паролю"
            ;;
        "deny")
            # Запрещаем root доступ полностью
            sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/g' /etc/ssh/sshd_config
            log "✓ Root доступ полностью запрещен"
            ;;
    esac
    
    # Если параметр не существует, добавляем его
    if ! grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
        echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config
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
    
    # Устанавливаем MAC-алгоритмы
    sed -i 's/^#*MACs.*/MACs '"$safe_macs"'/g' /etc/ssh/sshd_config
    
    # Если параметр не существует, добавляем его
    if ! grep -q "^MACs" /etc/ssh/sshd_config; then
        echo "MACs $safe_macs" >> /etc/ssh/sshd_config
    fi
    
    log "✓ Безопасные MAC-алгоритмы настроены"
}

configure_ssh_maxstartups() {
    log "Настройка MaxStartups..."
    
    # Устанавливаем безопасные значения: 10:30:60
    sed -i 's/^#*MaxStartups.*/MaxStartups 10:30:60/g' /etc/ssh/sshd_config
    
    # Если параметр не существует, добавляем его
    if ! grep -q "^MaxStartups" /etc/ssh/sshd_config; then
        echo "MaxStartups 10:30:60" >> /etc/ssh/sshd_config
    fi
    
    log "✓ MaxStartups настроен: 10:30:60"
}

# Функция создания SSH ключа для root (если не существует)
generate_root_ssh_key() {
    log "Создание SSH ключа для root..."
    
    local ssh_dir="/root/.ssh"
    local key_file="$ssh_dir/id_ed25519"
    
    # Создаем каталог .ssh если не существует
    if [ ! -d "$ssh_dir" ]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown root:root "$ssh_dir"
        log "✓ Создан каталог $ssh_dir"
    fi
    
    # Генерируем ключ если не существует
    if [ ! -f "$key_file" ]; then
        ssh-keygen -t ed25519 -f "$key_file" -N "" -C "root@$(hostname)"
        check_command "Генерация SSH ключа для root"
        
        # Добавляем публичный ключ в authorized_keys
        cat "$key_file.pub" >> "$ssh_dir/authorized_keys"
        chmod 600 "$ssh_dir/authorized_keys"
        chown root:root "$ssh_dir/authorized_keys"
        
        log "✓ SSH ключ создан: $key_file"
        log "✓ Публичный ключ добавлен в authorized_keys"
        
        # Показываем публичный ключ для копирования
        echo ""
        warn "=== ПУБЛИЧНЫЙ КЛЮЧ ROOT ==="
        cat "$key_file.pub"
        warn "=== КОНЕЦ ПУБЛИЧНОГО КЛЮЧА ==="
        echo ""
        warn "Скопируйте этот ключ в вашу локальную систему для доступа к серверу"
    else
        log "✓ SSH ключ для root уже существует"
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
    
    # Применяем основные настройки SSH
    log "Применение основных настроек SSH..."
    sed -i 's/^Include/#Include/g' /etc/ssh/sshd_config
    sed -i 's/^#Port 22/Port 56314/g' /etc/ssh/sshd_config
    sed -i 's/^#SyslogFacility AUTH/SyslogFacility AUTH/g' /etc/ssh/sshd_config
    sed -i 's/^#LogLevel INFO/LogLevel INFO/g' /etc/ssh/sshd_config
    sed -i 's/^#LoginGraceTime 2m/LoginGraceTime 30/g' /etc/ssh/sshd_config
    sed -i 's/^#MaxAuthTries 6/MaxAuthTries 3/g' /etc/ssh/sshd_config
    sed -i 's/^#MaxSessions 10/MaxSessions 2/g' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

    # Настраиваем доступ для root (только по ключу)
    configure_root_access "key-only"
    
    # Применяем дополнительные настройки безопасности
    configure_ssh_permissions
    configure_ssh_banner
    configure_ssh_timeouts
    configure_ssh_forwarding
    configure_ssh_macs
    configure_ssh_maxstartups

    # Перезагрузка службы SSH
    log "Перезагрузка службы SSH..."
    systemctl restart ssh
    check_command "Настройка SSH завершена"
    
    log "SSH настроен на порт 56314"
    log "Root доступ разрешен только по SSH-ключу"
    log "Аутентификация по паролю отключена"
    log "Текущие настройки SSH:"
    grep -E "^(Port|PasswordAuthentication|PermitRootLogin|Banner|ClientAliveInterval|ClientAliveCountMax|DisableForwarding|MACs)" /etc/ssh/sshd_config
}

# Функция выбора метода доступа для root
select_root_access_method() {
    echo ""
    warn "=== ВЫБОР МЕТОДА ДОСТУПА ДЛЯ ROOT ==="
    log "1. Только по SSH-ключу (рекомендуется)"
    log "2. Только по паролю (не рекомендуется)"
    log "3. По ключу и паролю"
    log "4. Полностью запретить доступ root"
    echo ""
    
    read -p "Выберите метод доступа (1-4): " choice
    
    case $choice in
        1)
            configure_root_access "key-only"
            ;;
        2)
            configure_root_access "password-only"
            ;;
        3)
            configure_root_access "key-and-password"
            ;;
        4)
            configure_root_access "deny"
            ;;
        *)
            warn "Неверный выбор. Используется метод по умолчанию: только по ключу"
            configure_root_access "key-only"
            ;;
    esac
}

# Основная логика скрипта
main() {
    log "=== Настройка SSH для root ==="
    
    check_root
    
    # Проверяем текущую конфигурацию безопасности
    check_root_access_safety
    
    echo ""
    log "Что вы хотите сделать?"
    log "1. Настроить SSH с существующим ключом root"
    log "2. Создать новый SSH ключ для root и настроить SSH"
    log "3. Проверить текущую конфигурацию"
    log "4. Настроить метод доступа для root"
    echo ""
    
    read -p "Выберите действие (1-4): " action
    
    case $action in
        1)
            # Проверяем наличие SSH-ключа у root
            if check_root_ssh_key; then
                log "SSH-ключ найден, выполняется настройка SSH..."
                select_root_access_method
                configure_ssh
            else
                error "У пользователя root не настроен SSH-ключ"
                read -p "Создать новый SSH ключ? (y/n): " create_key
                if [[ $create_key =~ ^[Yy]$ ]]; then
                    generate_root_ssh_key
                    select_root_access_method
                    configure_ssh
                else
                    error "Настройка SSH отменена"
                fi
            fi
            ;;
        2)
            generate_root_ssh_key
            select_root_access_method
            configure_ssh
            ;;
        3)
            log "=== ТЕКУЩАЯ КОНФИГУРАЦИЯ SSH ==="
            sshd -T | grep -E "(port|passwordauthentication|permitrootlogin|banner|clientaliveinterval|clientalivecountmax|disableforwarding|macs)"
            echo ""
            check_root_ssh_key
            check_root_access_safety
            ;;
        4)
            select_root_access_method
            systemctl restart ssh
            log "Метод доступа для root изменен"
            ;;
        *)
            error "Неверный выбор"
            exit 1
            ;;
    esac
    
    # Показываем информацию для подключения
    if [[ $action == 1 || $action == 2 ]]; then
        echo ""
        log "=== ИНФОРМАЦИЯ ДЛЯ ПОДКЛЮЧЕНИЯ ==="
        local ip_address=$(hostname -I | awk '{print $1}')
        log "IP адрес сервера: $ip_address"
        log "Порт SSH: 56314"
        log "Пользователь: root"
        
        if [ -f "/root/.ssh/id_ed25519.pub" ] && [[ $action == 2 ]]; then
            log "Публичный ключ создан и добавлен в authorized_keys"
            warn "Не забудьте скопировать приватный ключ в безопасное место!"
        fi
        
        log "Для подключения используйте:"
        log "  ssh -p 56314 root@$ip_address"
    fi
    
    log "=== Настройка системы завершена ==="
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main