#!/bin/bash

# Настройка PAM для безопасности системы

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

# Функция для создания профиля PAM
create_pam_profile() {
    local filename=$1
    local content=$2
    
    log "Создание профиля PAM: $filename"
    tee "/usr/share/pam-configs/$filename" > /dev/null << EOF
$content
EOF
    check_command "Создание профиля $filename"
}

# Основная функция
main() {
    log "=== Настройка PAM для безопасности системы ==="
    
    check_root
    
    # 1. Включение модуля pam_unix
    log "Включение модуля pam_unix..."
    pam-auth-update --enable unix
    check_command "Включение модуля pam_unix"
    
    # 2. Настройка pam_faillock
    log "Настройка pam_faillock..."
    
    # Создание профиля faillock
    create_pam_profile "faillock" "Name: Enable pam_faillock for access denial
Default: yes
Priority: 0
Auth-Type: Primary
Auth: [default=die] pam_faillock.so authfail"
    
    # Создание профиля faillock_notify
    create_pam_profile "faillock_notify" "Name: Notify on failed logins and reset counter on success
Default: yes
Priority: 1024
Auth-Type: Primary
Auth: requisite pam_faillock.so preauth
Account-Type: Primary
Account: required pam_faillock.so"
    
    # Включение профилей faillock
    pam-auth-update --enable faillock
    pam-auth-update --enable faillock_notify
    check_command "Настройка pam_faillock"
    
    # 3. Настройка pam_pwquality
    log "Настройка pam_pwquality..."
    
    # Проверка существования профиля
    if ! grep -q "pam_pwquality.so" /usr/share/pam-configs/* 2>/dev/null; then
        create_pam_profile "pwquality" "Name: Pwquality password strength checking
Default: yes
Priority: 1024
Conflicts: cracklib
Password-Type: Primary
Password: requisite pam_pwquality.so retry=3"
    fi
    
    pam-auth-update --enable pwquality
    check_command "Настройка pam_pwquality"
    
    # 4. Настройка pam_pwhistory
    log "Настройка pam_pwhistory..."
    
    # Проверка существования профиля
    if ! grep -q "pam_pwhistory.so" /usr/share/pam-configs/* 2>/dev/null; then
        create_pam_profile "pwhistory" "Name: Pwhistory password history checking
Default: yes
Priority: 1024
Password-Type: Primary
Password: requisite pam_pwhistory.so remember=24 enforce_for_root try_first_pass use_authtok"
    fi
    
    pam-auth-update --enable pwhistory
    check_command "Настройка pam_pwhistory"
    
    # 5. Настройка faillock.conf
    log "Настройка /etc/security/faillock.conf..."
    
    # Создание/обновление файла faillock.conf
    tee /etc/security/faillock.conf > /dev/null << 'EOF'
# Блокировка после неудачных попыток ввода пароля
deny = 5
unlock_time = 900
even_deny_root
EOF
    check_command "Настройка faillock.conf"
    
    # 6. Удаление nullok из pam_unix
    log "Удаление nullok из конфигураций pam_unix..."
    
    # Поиск и удаление nullok в существующих профилях
    find /usr/share/pam-configs/ -name "*.pam" -exec sed -i 's/\snullok\b//g' {} \; 2>/dev/null || true
    find /usr/share/pam-configs/ -name "*" -exec sed -i 's/\snullok\b//g' {} \; 2>/dev/null || true
    
    # Обновление конфигурации unix
    pam-auth-update --enable unix
    check_command "Удаление nullok"
    
    # 7. Настройка неактивных учетных записей
    log "Настройка неактивных учетных записей..."
    useradd -D -f 45
    check_command "Установка периода неактивности по умолчанию"
    
    # Применение к существующим пользователям
    awk -F: '($2 ~ /^\$.+\$/) { 
        if($7 > 45 || $7 == "" || $7 == -1) 
            system("chage --inactive 45 " $1 " 2>/dev/null || true")
    }' /etc/shadow
    check_command "Настройка неактивности для существующих пользователей"
    
    # 8. Настройка umask для root
    log "Настройка umask для root..."
    
    for file in /root/.bash_profile /root/.bashrc; do
        if [ -f "$file" ]; then
            # Удаляем существующие настройки umask
            sed -i '/^umask/d' "$file"
            # Добавляем безопасный umask
            echo "umask 0027" >> "$file"
        else
            # Создаем файл с безопасным umask
            echo "umask 0027" > "$file"
        fi
    done
    check_command "Настройка umask для root"

    warn "Для применения всех изменений может потребоваться перезагрузка системы."
    warn "Выполните: sudo reboot"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"