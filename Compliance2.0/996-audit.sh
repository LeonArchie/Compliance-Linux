#!/bin/bash

# Установка и настройка auditd

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

# Настройка прав инструментов аудита
fix_audit_tools_permissions() {
    log "Настройка прав доступа к инструментам аудита..."
    chmod 750 /sbin/auditctl /sbin/aureport /sbin/ausearch /sbin/autrace /sbin/auditd /sbin/augenrules
    check_command "Настройка прав инструментов аудита"
    
    # Проверка прав
    log "Проверка прав инструментов аудита:"
    for tool in /sbin/auditctl /sbin/aureport /sbin/ausearch /sbin/autrace /sbin/auditd /sbin/augenrules; do
        if [ -f "$tool" ]; then
            perms=$(stat -c "%a" "$tool")
            if [ "$perms" = "750" ]; then
                log "✓ $tool: права $perms"
            else
                warn "$tool: неправильные права $perms (ожидалось 750)"
                chmod 750 "$tool"
            fi
        fi
    done
}

# Настройка конфигурации auditd
configure_auditd() {
    log "Настройка конфигурации auditd..."
    
    # Создание резервной копии оригинального конфига
    if [ -f /etc/audit/auditd.conf ]; then
        cp /etc/audit/auditd.conf /etc/audit/auditd.conf.bak
        log "Создана резервная копия /etc/audit/auditd.conf.bak"
    fi
    
    # Полная перезапись конфигурационного файла
    cat > /etc/audit/auditd.conf << 'EOF'
# Конфигурация auditd
log_file = /var/log/audit/audit.log
log_format = RAW
log_group = root
priority_boost = 4
flush = INCREMENTAL
freq = 20
num_logs = 100
disp_qos = lossy
dispatcher = /sbin/audispd
name_format = NONE
max_log_file = 100
max_log_file_action = keep_logs
space_left = 250
space_left_action = email
admin_space_left = 100
admin_space_left_action = single
action_mail_acct = root
disk_full_action = halt
disk_error_action = halt
use_libwrap = yes
tcp_listen_port = 60
tcp_max_per_addr = 1
tcp_client_ports = 1024-65535
tcp_client_max_idle = 0
enable_krb5 = no
krb5_principal = auditd
EOF

    systemctl restart auditd
    check_command "Настройка auditd.conf"
}

# Настройка правил аудита
configure_audit_rules() {
    log "Настройка правил аудита..."
    
    # Получение UID_MIN
    local UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)
    if [ -z "${UID_MIN}" ]; then
        UID_MIN=1000
        warn "UID_MIN не найден, используется значение по умолчанию: $UID_MIN"
    fi
    log "Используется UID_MIN: $UID_MIN"
    
    # Создание отдельных файлов правил для соответствия требованиям проверок
    
    # 1. Правила для scope (sudoers) - 35731
    cat > /etc/audit/rules.d/50-scope.rules << EOF
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d -p wa -k scope
EOF

    # 2. Правила для sudo log - 35733
    cat > /etc/audit/rules.d/50-sudo.rules << EOF
-w /var/log/sudo.log -p wa -k sudo_log_file
EOF

    # 3. Правила для времени - 35734
    cat > /etc/audit/rules.d/50-time-change.rules << EOF
-a always,exit -F arch=b64 -S adjtimex,settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex,settimeofday -k time-change
-a always,exit -F arch=b64 -S clock_settime -F a0=0x0 -k time-change
-a always,exit -F arch=b32 -S clock_settime -F a0=0x0 -k time-change
-w /etc/localtime -p wa -k time-change
EOF

    # 4. Правила для команд изменения прав - 35744, 35745, 35746, 35747
    cat > /etc/audit/rules.d/50-perm_chng.rules << EOF
-a always,exit -F path=/usr/bin/chcon -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k perm_chng
-a always,exit -F path=/usr/bin/setfacl -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k perm_chng
-a always,exit -F path=/usr/bin/chacl -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k perm_chng
EOF

    # 5. Правила для usermod - 35747
    cat > /etc/audit/rules.d/50-usermod.rules << EOF
-a always,exit -F path=/usr/sbin/usermod -F perm=x -F auid>=${UID_MIN} -F auid!=-1 -k usermod
EOF

    # 6. Основные правила аудита (объединенные)
    cat > /etc/audit/rules.d/50-audit.rules << EOF
## CIS 6.2.4.8 - Защита инструментов аудита
-w /sbin/auditctl -p x -k audit_tools
-w /sbin/aureport -p x -k audit_tools  
-w /sbin/ausearch -p x -k audit_tools
-w /sbin/autrace -p x -k audit_tools
-w /sbin/auditd -p x -k audit_tools
-w /sbin/augenrules -p x -k audit_tools

## Изменение учетных записей и идентичности
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity
-w /etc/nsswitch.conf -p wa -k identity
-w /etc/pam.conf -p wa -k identity
-w /etc/pam.d -p wa -k identity

## Сетевые настройки
-a always,exit -F arch=b64 -S sethostname,setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname,setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/networks -p wa -k system-locale
-w /etc/network/ -p wa -k system-locale
-w /etc/netplan/ -p wa -k system-locale

## Сессии и логины
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins

## Права доступа и изменения разрешений
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=${UID_MIN} -F auid!=unset -k perm_mod
-a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=${UID_MIN} -F auid!=unset -k perm_mod
-a always,exit -F arch=b64 -S chown,fchown,lchown,fchownat -F auid>=${UID_MIN} -F auid!=unset -k perm_mod
-a always,exit -F arch=b32 -S lchown,fchown,chown,fchownat -F auid>=${UID_MIN} -F auid!=unset -k perm_mod
-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=${UID_MIN} -F auid!=unset -k perm_mod
-a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=${UID_MIN} -F auid!=unset -k perm_mod

## Удаление файлов
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=${UID_MIN} -F auid!=unset -k delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=${UID_MIN} -F auid!=unset -k delete

## Монтирование файловых систем
-a always,exit -F arch=b64 -S mount -F auid>=${UID_MIN} -F auid!=unset -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=${UID_MIN} -F auid!=unset -k mounts

## Модули ядра
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module,create_module,query_module -F auid>=${UID_MIN} -F auid!=unset -k kernel_modules
-a always,exit -F path=/usr/bin/kmod -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k kernel_modules

## Эскалация привилегий
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k privilege_escalation
-a always,exit -F arch=b64 -C euid!=uid -F auid!=unset -S execve -k user_emulation
-a always,exit -F arch=b32 -C euid!=uid -F auid!=unset -S execve -k user_emulation

## Доступ к файлам (неудачные попытки)
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=${UID_MIN} -F auid!=unset -k access
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=${UID_MIN} -F auid!=unset -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=${UID_MIN} -F auid!=unset -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=${UID_MIN} -F auid!=unset -k access

## Конфигурационные файлы SSH
-w /etc/ssh/sshd_config -p wa -k ssh_config
-w /etc/ssh/ -p wa -k ssh_config

## AppArmor и MAC-политики
-w /etc/apparmor/ -p wa -k MAC-policy
-w /etc/apparmor.d/ -p wa -k MAC-policy
EOF

    # 7. Финальное правило для блокировки конфигурации
    cat > /etc/audit/rules.d/99-finalize.rules << 'EOF'
-e 2
EOF

    # Загрузка правил
    log "Загрузка правил аудита..."
    augenrules --load
    systemctl restart auditd
    check_command "Загрузка правил аудита"
}

# Настройка прав конфигурационных файлов
configure_audit_permissions() {
    log "Настройка прав конфигурационных файлов..."
    
    # Права на конфигурационные файлы
    find /etc/audit/ -type f \( -name '*.conf' -o -name '*.rules' \) -exec chmod 640 {} \;
    chmod 750 /etc/audit/rules.d/
    
    # Права на инструменты аудита
    fix_audit_tools_permissions
    
    check_command "Настройка прав конфигурационных файлов"
}

# Проверка установки
verify_installation() {
    log "=== Проверка установки ==="
    
    log "Проверка статуса auditd:"
    if systemctl is-active auditd > /dev/null; then
        log "✓ auditd работает"
    else
        error "✗ auditd не работает"
        systemctl status auditd --no-pager -l
        return 1
    fi
    
    log "Проверка загруженных правил:"
    local rule_count=$(auditctl -l | wc -l)
    if [ $rule_count -gt 10 ]; then
        log "✓ Загружено $rule_count правил"
        
        # Проверка конкретных правил
        log "Проверка ключевых правил:"
        
        # Проверка правил для sudoers
        if auditctl -l | grep -q "/etc/sudoers.*scope"; then
            log "✓ Правило для /etc/sudoers найдено"
        else
            error "✗ Правило для /etc/sudoers не найдено"
        fi
        
        if auditctl -l | grep -q "/etc/sudoers.d.*scope"; then
            log "✓ Правило для /etc/sudoers.d найдено"
        else
            error "✗ Правило для /etc/sudoers.d не найдено"
        fi
        
        # Проверка правила для sudo.log
        if auditctl -l | grep -q "/var/log/sudo.log.*sudo_log_file"; then
            log "✓ Правило для /var/log/sudo.log найдено"
        else
            error "✗ Правило для /var/log/sudo.log не найдено"
        fi
        
        # Проверка правил времени
        if auditctl -l | grep -q "clock_settime.*a0=0x0.*time-change"; then
            log "✓ Правило для clock_settime с a0=0x0 найдено"
        else
            error "✗ Правило для clock_settime с a0=0x0 не найдено"
        fi
        
        # Проверка правил для команд
        for cmd in chcon setfacl chacl usermod; do
            if auditctl -l | grep -q "$cmd.*perm_chng"; then
                log "✓ Правило для $cmd найдено"
            else
                error "✗ Правило для $cmd не найдено"
            fi
        done
        
        auditctl -l | head -20
        log "... (показаны первые 20 правил, всего $rule_count)"
    else
        warn "Загружено мало правил: $rule_count"
        auditctl -l
    fi
    
    log "Проверка прав инструментов аудита:"
    local tools=("/sbin/auditctl" "/sbin/aureport" "/sbin/ausearch" "/sbin/autrace" "/sbin/auditd" "/sbin/augenrules")
    local all_correct=true
    for tool in "${tools[@]}"; do
        if [ -f "$tool" ]; then
            local perms=$(stat -c "%a" "$tool")
            if [ "$perms" = "750" ]; then
                log "✓ $tool: права $perms"
            else
                error "✗ $tool: неправильные права $perms (ожидалось 750)"
                all_correct=false
            fi
        else
            warn "$tool: файл не найден"
            all_correct=false
        fi
    done
    
    if [ "$all_correct" = true ]; then
        log "✓ Все инструменты аудита имеют правильные права доступа"
    else
        error "✗ Некоторые инструменты аудита имеют неправильные права доступа"
        # Повторная попытка исправления
        fix_audit_tools_permissions
    fi
    
    log "Проверка конфигурационных файлов:"
    local config_files=$(find /etc/audit/ -name "*.conf" -o -name "*.rules" | wc -l)
    log "Найдено конфигурационных файлов: $config_files"
    
    log "✓ Проверка завершена"
}

# Основная функция
main() {
    log "=== Установка и настройка auditd ==="
    
    check_root
    
    # Обновление пакетов
    log "Обновление списка пакетов..."
    apt update
    
    # Установка auditd
    log "Установка auditd и дополнительных компонентов..."
    apt install -y auditd audispd-plugins
    check_command "Установка auditd"
    
    # Включение и запуск службы
    systemctl enable auditd
    systemctl start auditd
    check_command "Запуск службы auditd"
    
    # Настройка конфигурации
    configure_auditd
    
    # Настройка правил
    configure_audit_rules
    
    # Настройка прав
    configure_audit_permissions
    
    # Проверка установки
    verify_installation
    
    log "=== Настройка auditd завершена успешно ==="
    log "Для просмотра логов аудита используйте:"
    log "  aureport -l" 
    log "  ausearch -k key_name"
    log "  tail -f /var/log/audit/audit.log"
    
    # Проверка необходимости перезагрузки
    log "Проверка необходимости перезагрузки..."
    if [[ $(auditctl -s | grep "enabled") =~ "2" ]]; then
        warn "Для загрузки правил требуется перезагрузка системы"
    else
        log "✓ Перезагрузка не требуется"
    fi
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"