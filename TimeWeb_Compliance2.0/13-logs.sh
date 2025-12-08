#!/bin/bash

# Настройка прав доступа к лог-файлам и systemd-journald

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функции для логирования
log() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Функция для вывода разделителя
section() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

# Проверка прав root
check_root() {
    log "Проверка прав доступа..."
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
    log "Права root подтверждены"
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

# Проверка установленных пакетов
check_installed_packages() {
    log "Проверка установленных пакетов, связанных с логированием..."
    
    # Список пакетов для проверки
    local packages=(
        "systemd-journal-remote"
        "rsyslog"
        "syslog-ng"
        "logrotate"
        "auditd"
    )
    
    for pkg in "${packages[@]}"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            local version=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)
            log "Установлен пакет: $pkg (версия: $version)"
        else
            debug "Пакет $pkg не установлен"
        fi
    done
}

# Проверка текущих настроек journald
check_current_journald_config() {
    log "Проверка текущих настроек systemd-journald..."
    
    if [ -f /etc/systemd/journald.conf ]; then
        log "Текущий файл конфигурации journald.conf:"
        grep -v '^#' /etc/systemd/journald.conf | grep -v '^$' | while read line; do
            debug "  $line"
        done || true
    fi
    
    if [ -d /etc/systemd/journald.conf.d/ ]; then
        log "Дополнительные файлы конфигурации в /etc/systemd/journald.conf.d/:"
        ls -la /etc/systemd/journald.conf.d/ 2>/dev/null | while read line; do
            debug "  $line"
        done || true
    fi
    
    # Проверка текущего использования журналов
    log "Текущее использование диска журналами:"
    journalctl --disk-usage 2>/dev/null || warn "Не удалось получить информацию об использовании журналов"
}

# Удаление systemd-journal-remote если он установлен
remove_journal_remote() {
    section "УДАЛЕНИЕ SYSTEMD-JOURNAL-REMOTE"
    
    log "Проверка systemd-journal-remote..."
    
    if dpkg-query -W -f='${Status}' systemd-journal-remote 2>/dev/null | grep -q "install ok installed"; then
        local version=$(dpkg-query -W -f='${Version}' systemd-journal-remote 2>/dev/null)
        warn "Найден systemd-journal-remote (версия: $version), начинаем удаление..."
        
        # Получаем информацию о пакете перед удалением
        log "Информация о пакете systemd-journal-remote:"
        dpkg -s systemd-journal-remote 2>/dev/null | grep -E '(Package|Version|Status)' | while read line; do
            debug "  $line"
        done || true
        
        log "Удаление systemd-journal-remote..."
        apt-get remove -y systemd-journal-remote
        check_command "Удаление systemd-journal-remote"
        
        # Проверяем что пакет действительно удален
        if dpkg-query -W -f='${Status}' systemd-journal-remote 2>/dev/null | grep -q "install ok installed"; then
            error "Не удалось удалить systemd-journal-remote"
            exit 1
        else
            log "systemd-journal-remote успешно удален"
        fi
    else
        log "systemd-journal-remote не установлен"
    fi
}

# Расширенная настройка journald
configure_journald_advanced() {
    section "НАСТРОЙКА SYSTEMD-JOURNALD"
    
    log "Расширенная настройка journald..."
    
    # Создаем директорию для конфигурации если её нет
    mkdir -p /etc/systemd/journald.conf.d/
    log "Создана директория /etc/systemd/journald.conf.d/"
    
    # Сохраняем старую конфигурацию если она существует
    if [ -f /etc/systemd/journald.conf.d/60-journald.conf ]; then
        local backup_file="/etc/systemd/journald.conf.d/60-journald.conf.backup.$(date +%Y%m%d_%H%M%S)"
        cp /etc/systemd/journald.conf.d/60-journald.conf "$backup_file"
        log "Создана резервная копия конфигурации: $backup_file"
    fi
    
    log "Создание новой конфигурации journald..."
    cat > /etc/systemd/journald.conf.d/60-journald.conf << 'EOF'
[Journal]
# Максимальный размер журналов в постоянном хранилище
SystemMaxUse=1G
# Минимальное свободное место в постоянном хранилище
SystemKeepFree=500M
# Максимальный размер журналов в runtime хранилище
RuntimeMaxUse=200M
# Минимальное свободное место в runtime хранилище
RuntimeKeepFree=50M
# Максимальное время хранения файлов
MaxFileSec=1month
# Сжатие старых журналов
Compress=yes
# Постоянное хранилище журналов
Storage=persistent
# Не перенаправлять логи в syslog
ForwardToSyslog=no
# Максимальный размер одного файла журнала
SystemMaxFileSize=100M
# Максимальное количество файлов журнала
SystemMaxFiles=10
EOF

    log "Новая конфигурация journald:"
    cat /etc/systemd/journald.conf.d/60-journald.conf | while read line; do
        debug "  $line"
    done
    
    log "Перезапуск systemd-journald..."
    systemctl restart systemd-journald
    check_command "Перезапуск systemd-journald"
    
    # Проверяем статус службы
    log "Проверка статуса systemd-journald..."
    systemctl status systemd-journald --no-pager -l | head -10 | while read line; do
        debug "  $line"
    done
}

# Проверка текущих прав лог-файлов
check_current_log_permissions() {
    log "Проверка текущих прав доступа к лог-файлам..."
    
    local log_dirs=("/var/log" "/var/log/journal" "/var/log/audit")
    
    for dir in "${log_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log "Права доступа в директории $dir:"
            ls -ld "$dir" | while read line; do
                debug "  $line"
            done
            
            # Проверяем несколько ключевых файлов
            local key_files=$(find "$dir" -maxdepth 1 -type f -name "*.log" -o -name "*.journal" -o -name "lastlog" -o -name "wtmp" -o -name "btmp" | head -5)
            if [ -n "$key_files" ]; then
                log "Ключевые файлы в $dir:"
                echo "$key_files" | while read file; do
                    if [ -f "$file" ]; then
                        ls -la "$file" | while read line; do
                            debug "  $line"
                        done
                    fi
                done
            fi
        else
            debug "Директория $dir не существует"
        fi
    done
}

# Функция для исправления прав файлов логов
fix_log_permissions() {
    section "ИСПРАВЛЕНИЕ ПРАВ ДОСТУПА К ЛОГ-ФАЙЛАМ"
    
    log "Начало проверки и исправления прав доступа к лог-файлам..."
    
    # Создаем временный файл для списка проблемных файлов
    local temp_file=$(mktemp)
    log "Создан временный файл для списка проблемных файлов: $temp_file"
    
    # Находим файлы с неправильными правами
    log "Поиск файлов с неправильными правами доступа..."
    find /var/log -type f \( -perm /0137 -o ! -user root \) > "$temp_file" 2>/dev/null || true
    
    local file_count=$(wc -l < "$temp_file" 2>/dev/null || echo "0")
    log "Найдено файлов с проблемными правами: $file_count"
    
    if [ $file_count -gt 0 ]; then
        log "Список проблемных файлов:"
        head -10 "$temp_file" | while read file; do
            warn "  $file"
        done
        
        if [ $file_count -gt 10 ]; then
            log "... и еще $((file_count - 10)) файлов"
        fi
    fi
    
    local processed_count=0
    
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            debug "Обработка файла: $file"
            
            # Получаем текущие права и владельца
            local current_perms=$(stat -c "%a %U:%G" "$file" 2>/dev/null || echo "unknown")
            
            # Определяем соответствующие права в зависимости от типа файла
            case "$(basename "$file")" in
                lastlog|lastlog.*|wtmp|wtmp.*|btmp|btmp.*)
                    chmod 664 "$file" 2>/dev/null || true
                    chown root:utmp "$file" 2>/dev/null || true
                    local new_perms="664 root:utmp"
                    ;;
                *.journal|*.journal~)
                    chmod 640 "$file" 2>/dev/null || true
                    chown root:systemd-journal "$file" 2>/dev/null || true
                    local new_perms="640 root:systemd-journal"
                    ;;
                auth.log|secure|syslog|messages|audit.log|audit|*.audit)
                    chmod 640 "$file" 2>/dev/null || true
                    chown root:adm "$file" 2>/dev/null || true
                    local new_perms="640 root:adm"
                    ;;
                *)
                    chmod 640 "$file" 2>/dev/null || true
                    chown root:adm "$file" 2>/dev/null || true
                    local new_perms="640 root:adm"
                    ;;
            esac
            
            local new_actual_perms=$(stat -c "%a %U:%G" "$file" 2>/dev/null || echo "unknown")
            debug "  Было: $current_perms -> Стало: $new_actual_perms"
            
            processed_count=$((processed_count + 1))
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    log "Удален временный файл $temp_file"
    
    if [ $processed_count -eq 0 ]; then
        log "✓ Все файлы логов имеют корректные права доступа"
    else
        log "✓ Исправлены права доступа для $processed_count файлов"
    fi
}

# Отключение служб journald remote
disable_journal_remote_services() {
    section "ОТКЛЮЧЕНИЕ СЛУЖБ JOURNALD REMOTE"
    
    log "Начало отключения служб journald remote..."
    
    local services=(
        "systemd-journal-upload.service"
        "systemd-journal-remote.socket"
        "systemd-journal-remote.service"
        "systemd-journal-gatewayd.socket"
        "systemd-journal-gatewayd.service"
    )
    
    for service in "${services[@]}"; do
        log "Обработка службы: $service"
        
        # Проверяем существует ли служба
        if systemctl list-unit-files | grep -q "$service"; then
            # Проверяем текущий статус
            local status=$(systemctl is-active "$service" 2>/dev/null || echo "not-found")
            local enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "not-found")
            
            debug "  Текущий статус: active=$status, enabled=$enabled"
            
            # Останавливаем службу если она запущена
            if [ "$status" = "active" ]; then
                log "  Остановка службы $service..."
                systemctl stop "$service" 2>/dev/null || warn "Не удалось остановить $service"
            fi
            
            # Отключаем автозапуск
            if [ "$enabled" != "disabled" ] && [ "$enabled" != "not-found" ]; then
                log "  Отключение автозапуска $service..."
                systemctl disable "$service" 2>/dev/null || warn "Не удалось отключить $service"
            fi
            
            # Маскируем службу чтобы предотвратить её запуск
            log "  Маскирование службы $service..."
            systemctl mask "$service" 2>/dev/null || warn "Не удалось замаскировать $service"
            
            # Проверяем результат
            local new_status=$(systemctl is-active "$service" 2>/dev/null || echo "not-found")
            local new_enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "not-found")
            
            if [ "$new_status" = "inactive" ] && [ "$new_enabled" = "disabled" ]; then
                log "  ✓ Служба $service успешно отключена"
            else
                warn "  ⚠ Служба $service может быть не полностью отключена (статус: $new_status, автозапуск: $new_enabled)"
            fi
        else
            debug "  Служба $service не найдена"
        fi
    done
    
    log "Все службы удаленной загрузки журналов обработаны"
}

# Проверка результатов настройки
verify_configuration() {
    section "ПРОВЕРКА РЕЗУЛЬТАТОВ НАСТРОЙКИ"
    
    log "Проверка настроек journald:"
    journalctl --disk-usage 2>/dev/null | while read line; do
        log "  $line"
    done || warn "Не удалось получить информацию об использовании журналов"
    
    log "Проверка прав доступа к ключевым лог-файлам:"
    local key_files=(
        "/var/log/auth.log"
        "/var/log/syslog"
        "/var/log/wtmp"
        "/var/log/btmp"
        "/var/log/lastlog"
        "/var/log/journal"
    )
    
    for file in "${key_files[@]}"; do
        if [ -e "$file" ]; then
            local perms=$(stat -c "%A %U %G" "$file" 2>/dev/null || echo "unknown")
            log "  $file: $perms"
        else
            debug "  $file: не существует"
        fi
    done
    
    log "Проверка статуса служб journald:"
    systemctl status systemd-journald --no-pager -l | head -5 | while read line; do
        debug "  $line"
    done
    
    log "Проверка отключенных служб remote:"
    local remote_services=(
        "systemd-journal-upload.service"
        "systemd-journal-remote.service"
    )
    
    for service in "${remote_services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            local status=$(systemctl is-active "$service" 2>/dev/null || echo "not-found")
            local enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "not-found")
            log "  $service: статус=$status, автозапуск=$enabled"
        fi
    done
}

# Основная функция
main() {
    section "НАЧАЛО РАБОТЫ СКРИПТА"
    log "Скрипт: Настройка прав доступа к лог-файлам и systemd-journald"
    log "Время начала: $(date)"
    
    check_root
    check_installed_packages
    check_current_journald_config
    check_current_log_permissions
    
    # Удаление и отключение компонентов удаленной загрузки логов
    remove_journal_remote
    disable_journal_remote_services
    
    # Расширенная настройка journald
    configure_journald_advanced
    
    # Настройка прав доступа к лог-файлам
    section "ОСНОВНАЯ НАСТРОЙКА ПРАВ ДОСТУПА"
    
    log "Настройка прав доступа к лог-файлам..."
    
    # Основные системные логи
    log "Настройка прав основных системных логов..."
    for file in /var/log/auth.log /var/log/secure /var/log/syslog /var/log/messages; do
        if [ -f "$file" ]; then
            chmod 640 "$file" 2>/dev/null && debug "  Установлены права для $file" || debug "  Не удалось изменить права для $file"
            chown root:adm "$file" 2>/dev/null && debug "  Установлен владелец для $file" || debug "  Не удалось изменить владельца для $file"
        fi
    done

    # Логи входа
    log "Настройка прав логов входа..."
    for file in /var/log/wtmp /var/log/btmp; do
        if [ -f "$file" ]; then
            chmod 664 "$file" 2>/dev/null && debug "  Установлены права для $file" || debug "  Не удалось изменить права для $file"
            chown root:utmp "$file" 2>/dev/null && debug "  Установлен владелец для $file" || debug "  Не удалось изменить владельца для $file"
        fi
    done

    # Lastlog
    log "Настройка прав lastlog..."
    if [ -f /var/log/lastlog ]; then
        chmod 644 /var/log/lastlog 2>/dev/null && debug "  Установлены права для lastlog" || debug "  Не удалось изменить права для lastlog"
        chown root:utmp /var/log/lastlog 2>/dev/null && debug "  Установлен владелец для lastlog" || debug "  Не удалось изменить владельца для lastlog"
    fi

    # Журналы systemd
    log "Настройка прав журналов systemd..."
    find /var/log -name "*.journal" -exec chmod 640 {} \; 2>/dev/null && debug "  Установлены права для journal файлов" || debug "  Не удалось изменить права для journal файлов"
    find /var/log -name "*.journal" -exec chown root:systemd-journal {} \; 2>/dev/null && debug "  Установлены владельцы для journal файлов" || debug "  Не удалось изменить владельцев для journal файлов"

    # Дополнительная настройка прав
    log "Дополнительная настройка прав лог-файлов..."
    find /var/log -name "*.log" -type f -exec chmod 640 {} \; 2>/dev/null && debug "  Установлены права для .log файлов" || debug "  Не удалось изменить права для .log файлов"
    find /var/log -name "*.log.*" -type f -exec chmod 640 {} \; 2>/dev/null && debug "  Установлены права для .log.* файлов" || debug "  Не удалось изменить права для .log.* файлов"
    find /var/log -name "*.gz" -type f -exec chmod 640 {} \; 2>/dev/null && debug "  Установлены права для .gz файлов" || debug "  Не удалось изменить права для .gz файлов"

    # Специфичные файлы
    log "Настройка прав специфичных файлов..."
    for file in /var/log/btmp /var/log/btmp.1 /var/log/wtmp /var/log/lastlog /var/log/faillog; do
        if [ -f "$file" ]; then
            if [[ "$file" =~ (btmp|wtmp) ]]; then
                chmod 660 "$file" 2>/dev/null && debug "  Установлены права для $file" || debug "  Не удалось изменить права для $file"
            else
                chmod 640 "$file" 2>/dev/null && debug "  Установлены права для $file" || debug "  Не удалось изменить права для $file"
            fi
            chown root:utmp "$file" 2>/dev/null && debug "  Установлен владелец для $file" || debug "  Не удалось изменить владельца для $file"
        fi
    done
    
    # Дополнительное исправление прав
    fix_log_permissions
    
    check_command "Настройка прав доступа к лог-файлам"

    # Финальная проверка
    verify_configuration
    
    section "ЗАВЕРШЕНИЕ РАБОТЫ СКРИПТА"
    log "Все операции успешно завершены"
    log "Время завершения: $(date)"
    log "=== СКРИПТ ВЫПОЛНЕН УСПЕШНО ==="
}

# Обработка сигналов
trap 'error "Скрипт прерван пользователем"; exit 1' INT
trap 'error "Скрипт завершен аварийно"; exit 1' TERM

# Запуск основной функции
main "$@"