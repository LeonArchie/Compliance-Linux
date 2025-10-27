#!/bin/bash

# Настройка параметров качества паролей и политик старения

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

# Функция для настройки параметров pwquality
configure_pwquality() {
    log "=== Настройка параметров качества паролей ==="
    
    # Создаем директорию для конфигурационных файлов pwquality
    if [ ! -d /etc/security/pwquality.conf.d/ ]; then
        log "Создание директории /etc/security/pwquality.conf.d/"
        mkdir -p /etc/security/pwquality.conf.d/
        check_command "Создание директории /etc/security/pwquality.conf.d/"
    fi
    
    # Создаем резервную копию основного файла конфигурации
    if [ -f /etc/security/pwquality.conf ]; then
        log "Создание резервной копии pwquality.conf..."
        cp /etc/security/pwquality.conf /etc/security/pwquality.conf.backup.$(date +%Y%m%d_%H%M%S)
        check_command "Создание резервной копии pwquality.conf"
    fi
    
    # Настройка параметров в основном файле (раскомментируем и устанавливаем значения)
    log "Настройка параметров в основном файле pwquality.conf..."
    
    # Раскомментируем и устанавливаем параметры в основном файле
    sed -i 's/^#\s*difok\s*=.*/difok = 2/' /etc/security/pwquality.conf
    sed -i 's/^#\s*minlen\s*=.*/minlen = 15/' /etc/security/pwquality.conf
    sed -i 's/^#\s*minclass\s*=.*/minclass = 4/' /etc/security/pwquality.conf
    sed -i 's/^#\s*maxrepeat\s*=.*/maxrepeat = 3/' /etc/security/pwquality.conf
    sed -i 's/^#\s*maxsequence\s*=.*/maxsequence = 3/' /etc/security/pwquality.conf
    sed -i 's/^#\s*enforce_for_root\s*=.*/enforce_for_root = 1/' /etc/security/pwquality.conf
    
    # Если параметры не были закомментированы, добавляем их
    if ! grep -q "^difok\s*=" /etc/security/pwquality.conf; then
        echo "difok = 2" >> /etc/security/pwquality.conf
    fi
    if ! grep -q "^minlen\s*=" /etc/security/pwquality.conf; then
        echo "minlen = 15" >> /etc/security/pwquality.conf
    fi
    if ! grep -q "^minclass\s*=" /etc/security/pwquality.conf; then
        echo "minclass = 4" >> /etc/security/pwquality.conf
    fi
    if ! grep -q "^maxrepeat\s*=" /etc/security/pwquality.conf; then
        echo "maxrepeat = 3" >> /etc/security/pwquality.conf
    fi
    if ! grep -q "^maxsequence\s*=" /etc/security/pwquality.conf; then
        echo "maxsequence = 3" >> /etc/security/pwquality.conf
    fi
    if ! grep -q "^enforce_for_root\s*=" /etc/security/pwquality.conf; then
        echo "enforce_for_root = 1" >> /etc/security/pwquality.conf
    fi
    
    # Дополнительно создаем файл в conf.d для гарантии
    local PWQUALITY_CONF="/etc/security/pwquality.conf.d/50-pwpolicy.conf"
    
    log "Создание дополнительного конфигурационного файла..."
    
    cat > "$PWQUALITY_CONF" << EOF
# Параметры качества паролей
# Настроено автоматически $(date)

# Количество измененных символов в пароле (difok)
difok = 2

# Минимальная длина пароля
minlen = 15

# Сложность пароля - минимальное количество классов символов
minclass = 4

# Максимальное количество одинаковых символов подряд
maxrepeat = 3

# Максимальное количество последовательных символов
maxsequence = 3

# Применять политики качества паролей для пользователя root
enforce_for_root = 1
EOF

    check_command "Создание конфигурационного файла pwquality"
    
    # Убеждаемся, что параметры не закомментированы в основном файле
    sed -i 's/^#\s*\(difok\s*=\)/\1/' /etc/security/pwquality.conf
    sed -i 's/^#\s*\(minlen\s*=\)/\1/' /etc/security/pwquality.conf
    sed -i 's/^#\s*\(minclass\s*=\)/\1/' /etc/security/pwquality.conf
    sed -i 's/^#\s*\(maxrepeat\s*=\)/\1/' /etc/security/pwquality.conf
    sed -i 's/^#\s*\(maxsequence\s*=\)/\1/' /etc/security/pwquality.conf
    sed -i 's/^#\s*\(enforce_for_root\s*=\)/\1/' /etc/security/pwquality.conf
    
    log "Параметры качества паролей настроены"
}

# Функция для настройки политик старения паролей
configure_password_aging() {
    log "=== Настройка политик старения паролей ==="
    
    # Создаем резервную копию login.defs
    log "Создание резервной копии login.defs..."
    cp /etc/login.defs /etc/login.defs.backup.$(date +%Y%m%d_%H%M%S)
    check_command "Создание резервной копии login.defs"
    
    # Настраиваем параметры в login.defs
    log "Настройка параметров старения паролей в login.defs..."
    
    # Обновляем или добавляем PASS_MAX_DAYS
    if grep -q "^PASS_MAX_DAYS" /etc/login.defs; then
        sed -i 's/^PASS_MAX_DAYS\s*.*/PASS_MAX_DAYS\t120/' /etc/login.defs
    else
        echo "PASS_MAX_DAYS\t120" >> /etc/login.defs
    fi
    
    # Обновляем или добавляем PASS_MIN_DAYS
    if grep -q "^PASS_MIN_DAYS" /etc/login.defs; then
        sed -i 's/^PASS_MIN_DAYS\s*.*/PASS_MIN_DAYS\t1/' /etc/login.defs
    else
        echo "PASS_MIN_DAYS\t1" >> /etc/login.defs
    fi
    
    check_command "Настройка параметров в login.defs"
    
    # Применяем настройки к существующим пользователям
    log "Применение настроек к существующим пользователям..."
    
    # Получаем список пользователей с паролями (исключая системных)
    local users_with_passwords=$(awk -F: '($2 != "" && $2 !~ /^!/ && $2 !~ /^[*]/ && $1 != "nobody" && $1 != "nfsnobody") {print $1}' /etc/shadow)
    
    for user in $users_with_passwords; do
        # Устанавливаем максимальный срок действия пароля
        if chage --list "$user" 2>/dev/null | grep -q "Maximum number of days between password change"; then
            chage --maxdays 120 "$user" 2>/dev/null && log "Установлен PASS_MAX_DAYS=120 для пользователя $user" || warn "Не удалось установить PASS_MAX_DAYS для $user"
        fi
        
        # Устанавливаем минимальный срок действия пароля
        if chage --list "$user" 2>/dev/null | grep -q "Minimum number of days between password change"; then
            chage --mindays 1 "$user" 2>/dev/null && log "Установлен PASS_MIN_DAYS=1 для пользователя $user" || warn "Не удалось установить PASS_MIN_DAYS для $user"
        fi
    done
    
    # Особые настройки для root
    if chage --list root 2>/dev/null | grep -q "Maximum number of days between password change"; then
        chage --maxdays 120 root
        chage --mindays 1 root
        log "Настройки применены для пользователя root"
    fi
    
    log "Политики старения паролей настроены"
}

# Функция проверки PAM конфигурации
check_pam_configuration() {
    log "=== Проверка PAM конфигурации ==="
    
    # Проверяем, есть ли параметры в PAM файлах, которые нужно удалить
    local pam_files=$(grep -Pl -- '\bpam_pwquality\.so\h+([^#\n\r]+\h+)?(difok|minlen|minclass|maxrepeat|maxsequence|enforce_for_root)\b' /usr/share/pam-configs/* 2>/dev/null || true)
    
    if [ -n "$pam_files" ]; then
        warn "Найдены PAM файлы с параметрами, которые нужно очистить:"
        echo "$pam_files"
        log "Рекомендуется вручную отредактировать эти файлы и удалить параметры difok, minlen, minclass, maxrepeat, maxsequence, enforce_for_root из pam_pwquality.so"
    else
        log "PAM конфигурация в порядке - нет конфликтующих параметров"
    fi
}

# Функция проверки конфигурации
verify_configuration() {
    log "=== Проверка конфигурации ==="
    
    # Проверяем настройки pwquality
    log "Проверка настроек качества паролей в основном файле:"
    grep -E "^(difok|minlen|minclass|maxrepeat|maxsequence|enforce_for_root)\s*=" /etc/security/pwquality.conf || warn "Параметры не найдены в основном файле"
    
    if [ -f /etc/security/pwquality.conf.d/50-pwpolicy.conf ]; then
        log "Проверка настроек качества паролей в conf.d:"
        grep -E "^(difok|minlen|minclass|maxrepeat|maxsequence|enforce_for_root)" /etc/security/pwquality.conf.d/50-pwpolicy.conf
    fi
    
    # Проверяем настройки login.defs
    log "Проверка настроек login.defs:"
    grep -E "^(PASS_MAX_DAYS|PASS_MIN_DAYS)" /etc/login.defs
    
    # Проверяем настройки для пользователей
    log "Проверка настроек для пользователей (первые 10):"
    echo "Пользователь : Макс.дни : Мин.дни"
    for user in $(awk -F: '($2 != "" && $2 !~ /^!/ && $2 !~ /^[*]/) {print $1}' /etc/shadow | head -10); do
        max_days=$(chage --list "$user" 2>/dev/null | grep "Maximum number" | awk -F: '{print $2}' | tr -d ' ' || echo "N/A")
        min_days=$(chage --list "$user" 2>/dev/null | grep "Minimum number" | awk -F: '{print $2}' | tr -d ' ' || echo "N/A")
        echo "$user : $max_days : $min_days"
    done
    
    # Специальная проверка для enforce_for_root
    log "=== Проверка параметра enforce_for_root ==="
    if grep -q "^enforce_for_root\s*=\s*1" /etc/security/pwquality.conf || \
       ( [ -f /etc/security/pwquality.conf.d/50-pwpolicy.conf ] && \
         grep -q "^enforce_for_root\s*=\s*1" /etc/security/pwquality.conf.d/50-pwpolicy.conf ); then
        log "✓ Параметр enforce_for_root = 1 настроен корректно"
    else
        error "✗ Параметр enforce_for_root не настроен или не равен 1"
        exit 1
    fi
}

# Основная функция
main() {
    log "=== Настройка параметров качества паролей и политик старения ==="
    
    check_root
    
    # Настраиваем параметры качества паролей
    configure_pwquality
    
    # Настраиваем политики старения паролей
    configure_password_aging
    
    # Проверяем PAM конфигурацию
    check_pam_configuration
    
    # Проверяем конфигурацию
    verify_configuration
    
    log "=== Настройка завершена успешно ==="
    log "Параметры:"
    log "  - Минимальная длина пароля: 15 символов"
    log "  - Максимальный срок действия пароля: 120 дней"
    log "  - Минимальный срок между сменами пароля: 1 день"
    log "  - Минимальное количество классов символов: 4"
    log "  - Максимальное количество повторяющихся символов: 3"
    log "  - Максимальная длина последовательностей: 3"
    log "  - Минимальное количество измененных символов: 2"
    log "  - Применение политик для root (enforce_for_root): включено"
    
    warn "ВАЖНО: Если проверки все еще не проходят, выполните вручную:"
    warn "grep -Pl -- '\\bpam_pwquality\\.so\\h+([^#\\n\\r]+\\h+)?(difok|minlen|minclass|maxrepeat|maxsequence|enforce_for_root)\\b' /usr/share/pam-configs/*"
    warn "И удалите соответствующие параметры из найденных файлов"
    
    log "Уязвимость 35686 устранена: для пользователя root установлены требования к надежному паролю"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"