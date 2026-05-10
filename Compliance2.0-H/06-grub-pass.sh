#!/bin/bash

# Настройка безопасности GRUB

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
    log "=== Настройка безопасности GRUB ==="
    
    check_root
    
    # Создаем файлы для логирования
    PASSWORD_FILE="/root/grub_password_$(date +%Y%m%d_%H%M%S).txt"
    LOG_FILE="/root/grub_setup.log"

    # Генерация пароля
    log "Генерация пароля GRUB..."
    PASSWORD=$(openssl rand -base64 15 | tr -d '/+=' | cut -c1-20)

    # НЕМЕДЛЕННО сохраняем пароль в файл
    echo "Пароль GRUB: $PASSWORD" > "$PASSWORD_FILE"
    echo "Дата: $(date)" >> "$PASSWORD_FILE"
    echo "Хост: $(hostname)" >> "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"

    log "🔐 Пароль сохранен в: $PASSWORD_FILE"
    log "📝 Пароль: $PASSWORD"
    echo ""

    # Создаем хэш пароля (ИСПРАВЛЕННАЯ ЧАСТЬ)
    log "Создание PBKDF2 хэша..."
    GRUB_HASH=$(printf "$PASSWORD\n$PASSWORD" | grub-mkpasswd-pbkdf2 2>/dev/null | grep -oP 'grub\.pbkdf2\.sha512\.10000\.\S+')

    if [ -z "$GRUB_HASH" ]; then
        error "Не удалось создать хэш пароля"
        # Альтернативный метод
        GRUB_HASH=$(grub-mkpasswd-pbkdf2 <<< "$PASSWORD"$'\n'"$PASSWORD" 2>/dev/null | grep -oP 'grub\.pbkdf2\.sha512\.10000\.\S+')
        
        if [ -z "$GRUB_HASH" ]; then
            error "Не удалось создать хэш пароля даже альтернативным методом"
            exit 1
        fi
    fi

    log "Хэш пароля создан: ${GRUB_HASH:0:20}..."

    # Создаем конфигурационный файл (ИСПРАВЛЕННАЯ ЧАСТЬ)
    log "Настройка GRUB..."
    cat > /etc/grub.d/01_password << EOF
#!/bin/sh
exec tail -n +2 \$0
set superusers="root"
password_pbkdf2 root $GRUB_HASH
EOF

    # Устанавливаем правильные права (ИСПРАВЛЕНО)
    chmod 600 /etc/grub.d/01_password
    chown root:root /etc/grub.d/01_password
    chmod +x /etc/grub.d/01_password

    log "Установка правильных прав доступа к grub.cfg..."
    chown root:root /boot/grub/grub.cfg
    chmod 400 /boot/grub/grub.cfg

    # Разрешаем обычную загрузку без пароля
    if [ -f /etc/grub.d/10_linux ]; then
        log "Настройка unrestricted доступа для обычной загрузки..."
        sed -i 's/CLASS="--class gnu-linux --class gnu --class os"/CLASS="--class gnu-linux --class gnu --class os --unrestricted"/' /etc/grub.d/10_linux
        check_command "Настройка unrestricted доступа"
    fi

    # Обновляем GRUB
    log "Обновление конфигурации GRUB..."
    update-grub 2>&1 | tee -a "$LOG_FILE"
    check_command "Обновление GRUB"

    # Проверяем результат более тщательно
    log "=== ПРОВЕРКА ==="
    if grep -q "password_pbkdf2" /boot/grub/grub.cfg && grep -q "set superusers=" /boot/grub/grub.cfg; then
        log "✅ Пароль успешно добавлен в GRUB"
        log "✅ Superusers настроены в GRUB"
    else
        error "❌ Ошибка: настройки безопасности не добавлены в grub.cfg"
        error "Проверьте содержимое /boot/grub/grub.cfg вручную"
        exit 1
    fi

    # Дополнительная проверка
    log "Проверка наличия настроек в grub.cfg:"
    grep -E "(password_pbkdf2|set superusers)" /boot/grub/grub.cfg

    # Настройка безопасности загрузчика и дампов памяти
    log "Настройка дополнительной безопасности..."
    echo "fs.suid_dumpable = 0" >> /etc/sysctl.d/60-fs_sysctl.conf
    sysctl -w fs.suid_dumpable=0
    echo "* hard core 0" >> /etc/security/limits.conf

    cat > /etc/systemd/coredump.conf << EOF
Storage=none
ProcessSizeMax=0
EOF

    systemctl daemon-reload
    check_command "Настройка безопасности загрузчика"

    log ""
    log "=== ЗАВЕРШЕНО ==="
    log "✅ Пароль GRUB: $PASSWORD"
    log "✅ Файл с паролем: $PASSWORD_FILE"
    log "✅ Настройки безопасности применены"
    log ""
    warn "После перезагрузки пароль потребуется для:"
    warn "• Редактирования параметров загрузки (клавиша 'e')"
    warn "• Командной строки GRUB (клавиша 'c')"
    warn "• Однопользовательского режима"
    log ""
    warn "⚠️  Обязательно перезагрузите систему для проверки работы пароля!"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"