#!/bin/bash

# Настройка прав доступа к лог-файлам и systemd-journald

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

# Удаление systemd-journal-remote если он установлен
remove_journal_remote() {
    log "Проверка systemd-journal-remote..."
    
    if dpkg-query -W -f='${Status}' systemd-journal-remote 2>/dev/null | grep -q "install ok installed"; then
        log "Удаление systemd-journal-remote..."
        apt-get remove -y systemd-journal-remote
        log "systemd-journal-remote удален"
    else
        log "systemd-journal-remote не установлен"
    fi
}

# Расширенная настройка journald
configure_journald_advanced() {
    log "Расширенная настройка journald..."
    mkdir -p /etc/systemd/journald.conf.d/

    cat > /etc/systemd/journald.conf.d/60-journald.conf << 'EOF'
[Journal]
SystemMaxUse=1G
SystemKeepFree=500M
RuntimeMaxUse=200M
RuntimeKeepFree=50M
MaxFileSec=1month
Compress=yes
Storage=persistent
ForwardToSyslog=no
EOF

    systemctl restart systemd-journald
    check_command "Расширенная настройка systemd-journald"
}

# Функция для исправления прав файлов логов
fix_log_permissions() {
    log "Проверка и исправление прав доступа к лог-файлам..."
    
    # Создаем временный файл для списка проблемных файлов
    local temp_file=$(mktemp)
    
    # Находим файлы с неправильными правами
    find /var/log -type f \( -perm /0137 -o ! -user root \) > "$temp_file" 2>/dev/null || true
    
    local file_count=0
    
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            # Определяем соответствующие права в зависимости от типа файла
            case "$(basename "$file")" in
                lastlog|lastlog.*|wtmp|wtmp.*|btmp|btmp.*)
                    chmod 664 "$file" 2>/dev/null || true
                    chown root:utmp "$file" 2>/dev/null || true
                    ;;
                *.journal|*.journal~)
                    chmod 640 "$file" 2>/dev/null || true
                    chown root:systemd-journal "$file" 2>/dev/null || true
                    ;;
                auth.log|secure|syslog|messages)
                    chmod 640 "$file" 2>/dev/null || true
                    chown root:adm "$file" 2>/dev/null || true
                    ;;
                *)
                    chmod 640 "$file" 2>/dev/null || true
                    chown root:adm "$file" 2>/dev/null || true
                    ;;
            esac
            ((file_count++))
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    if [ $file_count -eq 0 ]; then
        log "Все файлы логов имеют корректные права доступа"
    else
        log "Исправлены права доступа для $file_count файлов"
    fi
}

# Отключение служб journald remote
disable_journal_remote_services() {
    log "Отключение служб journald remote..."
    
    # Останавливаем и отключаем службы удаленной загрузки журналов
    systemctl stop systemd-journal-upload.service 2>/dev/null || true
    systemctl disable systemd-journal-upload.service 2>/dev/null || true
    systemctl stop systemd-journal-remote.socket 2>/dev/null || true
    systemctl disable systemd-journal-remote.socket 2>/dev/null || true
    systemctl stop systemd-journal-remote.service 2>/dev/null || true
    systemctl disable systemd-journal-remote.service 2>/dev/null || true
    
    # Маскируем службы чтобы предотвратить их запуск
    systemctl mask systemd-journal-upload.service 2>/dev/null || true
    systemctl mask systemd-journal-remote.socket 2>/dev/null || true
    systemctl mask systemd-journal-remote.service 2>/dev/null || true
    
    log "Службы удаленной загрузки журналов отключены и замаскированы"
}

# Основная функция
main() {
    log "=== Настройка прав доступа к лог-файлам и systemd-journald ==="
    
    check_root
    
    # Удаление и отключение компонентов удаленной загрузки логов
    remove_journal_remote
    disable_journal_remote_services
    
    # Расширенная настройка journald
    configure_journald_advanced
    
    # Настройка прав доступа к лог-файлам
    log "Настройка прав доступа к лог-файлам..."
    
    # Основные системные логи
    chmod 640 /var/log/auth.log /var/log/secure /var/log/syslog /var/log/messages 2>/dev/null || true
    chown root:adm /var/log/auth.log /var/log/secure /var/log/syslog /var/log/messages 2>/dev/null || true

    # Логи входа
    chmod 664 /var/log/wtmp /var/log/btmp 2>/dev/null || true
    chown root:utmp /var/log/wtmp /var/log/btmp 2>/dev/null || true

    # Lastlog
    chmod 644 /var/log/lastlog 2>/dev/null || true
    chown root:utmp /var/log/lastlog 2>/dev/null || true

    # Журналы systemd
    find /var/log -name "*.journal" -exec chmod 640 {} \; 2>/dev/null || true
    find /var/log -name "*.journal" -exec chown root:systemd-journal {} \; 2>/dev/null || true

    # Дополнительная настройка прав
    log "Дополнительная настройка прав лог-файлов..."
    find /var/log -name "*.log" -type f -exec chmod 640 {} \; 2>/dev/null || true
    find /var/log -name "*.log.*" -type f -exec chmod 640 {} \; 2>/dev/null || true
    find /var/log -name "*.gz" -type f -exec chmod 640 {} \; 2>/dev/null || true

    # Специфичные файлы
    chmod 660 /var/log/btmp /var/log/btmp.1 /var/log/wtmp 2>/dev/null || true
    chmod 640 /var/log/lastlog /var/log/faillog 2>/dev/null || true
    chown root:utmp /var/log/btmp /var/log/btmp.1 /var/log/wtmp /var/log/lastlog /var/log/faillog 2>/dev/null || true
    
    # Дополнительное исправление прав
    fix_log_permissions
    
    check_command "Настройка прав доступа к лог-файлам"

    log "Проверка настроек journald:"
    journalctl --disk-usage
    
    log "Проверка прав доступа к лог-файлам:"
    find /var/log -type f -exec ls -la {} \; | head -10
    
    log "Проверка статуса служб journald remote:"
    systemctl status systemd-journal-upload.service systemd-journal-remote.service --no-pager -l 2>/dev/null || true
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"