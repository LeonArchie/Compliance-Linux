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

# Основная функция
main() {
    log "=== Установка и настройка auditd ==="
    
    check_root
    
    # Установка и настройка auditd
    log "Установка auditd..."
    apt install -y auditd audispd-plugins
    systemctl start auditd
    systemctl enable auditd
    check_command "Установка auditd"

    # Конфигурация auditd
    log "Настройка конфигурации auditd..."
    sed -i 's/^max_log_file =.*/max_log_file = 100/' /etc/audit/auditd.conf
    sed -i 's/^max_log_file_action =.*/max_log_file_action = keep_logs/' /etc/audit/auditd.conf
    sed -i 's/^num_logs =.*/num_logs = 100/' /etc/audit/auditd.conf
    sed -i 's/^space_left =.*/space_left = 250/' /etc/audit/auditd.conf
    sed -i 's/^space_left_action =.*/space_left_action = email/' /etc/audit/auditd.conf
    sed -i 's/^admin_space_left =.*/admin_space_left = 100/' /etc/audit/auditd.conf
    sed -i 's/^admin_space_left_action =.*/admin_space_left_action = single/' /etc/audit/auditd.conf
    sed -i 's/^disk_full_action =.*/disk_full_action = halt/' /etc/audit/auditd.conf
    sed -i 's/^disk_error_action =.*/disk_error_action = halt/' /etc/audit/auditd.conf
    sed -i 's/^action_mail_acct =.*/action_mail_acct = root/' /etc/audit/auditd.conf

    systemctl restart auditd
    check_command "Настройка auditd"

    # Настройка правил аудита
    log "Настройка правил аудита..."
    
    # Создание всех правил аудита
    log "Создание правил аудита..."
    
    # Правила scope
    cat > /etc/audit/rules.d/50-scope.rules << 'EOF'
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d -p wa -k scope
EOF

    # Правила user_emulation
    cat > /etc/audit/rules.d/50-user_emulation.rules << 'EOF'
-a always,exit -F arch=b64 -C euid!=uid -F auid!=unset -S execve -k user_emulation
-a always,exit -F arch=b32 -C euid!=uid -F auid!=unset -S execve -k user_emulation
EOF

    # Правила sudo
    cat > /etc/audit/rules.d/50-sudo.rules << 'EOF'
-w /var/log/sudo.log -p wa -k sudo_log_file
EOF

    # Правила time-change
    cat > /etc/audit/rules.d/50-time-change.rules << 'EOF'
-a always,exit -F arch=b64 -S adjtimex,settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex,settimeofday -k time-change
-a always,exit -F arch=b64 -S clock_settime -F a0=0x0 -k time-change
-a always,exit -F arch=b32 -S clock_settime -F a0=0x0 -k time-change
-w /etc/localtime -p wa -k time-change
EOF

    # Правила system_locale
    cat > /etc/audit/rules.d/50-system_locale.rules << 'EOF'
-a always,exit -F arch=b64 -S sethostname,setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname,setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/networks -p wa -k system-locale
-w /etc/network/ -p wa -k system-locale
-w /etc/netplan/ -p wa -k system-locale
EOF

    # Получение UID_MIN для правил аудита
    UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)

    # Правила доступа к файлам
    log "Настройка правил доступа к файлам (UID_MIN=$UID_MIN)..."
    if [ -n "${UID_MIN}" ]; then
        cat > /etc/audit/rules.d/50-access.rules << EOF
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=${UID_MIN} -F auid!=unset -k access
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=${UID_MIN} -F auid!=unset -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=${UID_MIN} -F auid!=unset -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=${UID_MIN} -F auid!=unset -k access
EOF
    else
        cat > /etc/audit/rules.d/50-access.rules << 'EOF'
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b64 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b32 -S creat,open,openat,truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -k access
EOF
    fi

    # Правила identity
    cat > /etc/audit/rules.d/50-identity.rules << 'EOF'
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity
-w /etc/nsswitch.conf -p wa -k identity
-w /etc/pam.conf -p wa -k identity
-w /etc/pam.d -p wa -k identity
EOF

    # Правила изменения разрешений
    if [ -n "${UID_MIN}" ]; then
        cat > /etc/audit/rules.d/50-perm_mod.rules << EOF
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b64 -S chown,fchown,lchown,fchownat -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b32 -S lchown,fchown,chown,fchownat -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=${UID_MIN} -F auid!=unset -F key=perm_mod
EOF
    else
        cat > /etc/audit/rules.d/50-perm_mod.rules << 'EOF'
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b64 -S chown,fchown,lchown,fchownat -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b32 -S lchown,fchown,chown,fchownat -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=unset -F key=perm_mod
EOF
    fi

    # Правила mounts
    UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)
    if [ -n "${UID_MIN}" ]; then
        cat > /etc/audit/rules.d/50-mounts.rules << EOF
-a always,exit -F arch=b32 -S mount -F auid>=${UID_MIN} -F auid!=unset -k mounts
-a always,exit -F arch=b64 -S mount -F auid>=${UID_MIN} -F auid!=unset -k mounts
EOF
    else
        cat > /etc/audit/rules.d/50-mounts.rules << 'EOF'
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=unset -k mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=unset -k mounts
EOF
    fi

    # Правила session
    cat > /etc/audit/rules.d/50-session.rules << 'EOF'
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session
EOF

    # Правила login
    cat > /etc/audit/rules.d/50-login.rules << 'EOF'
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins
EOF

    # Правила delete
    UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)
    if [ -n "${UID_MIN}" ]; then
        cat > /etc/audit/rules.d/50-delete.rules << EOF
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=${UID_MIN} -F auid!=unset -F key=delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=${UID_MIN} -F auid!=unset -F key=delete
EOF
    else
        cat > /etc/audit/rules.d/50-delete.rules << 'EOF'
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=unset -F key=delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=unset -F key=delete
EOF
    fi

    # Правила MAC-policy
    cat > /etc/audit/rules.d/50-MAC-policy.rules << 'EOF'
-w /etc/apparmor -p wa -k MAC-policy
-w /etc/apparmor.d -p wa -k MAC-policy
EOF

    # Правила perm_chng
    UID_MIN=$(awk '/^\s*UID_MIN/{print $2}' /etc/login.defs)
    if [ -n "${UID_MIN}" ]; then
        cat > /etc/audit/rules.d/50-perm_chng.rules << EOF
-a always,exit -F path=/usr/bin/chcon -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k perm_chng
-a always,exit -F path=/usr/bin/setfacl -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k perm_chng
-a always,exit -F path=/usr/bin/chacl -F perm=x -F auid>=${UID_MIN} -F auid!=unset -k perm_chng
EOF
    else
        cat > /etc/audit/rules.d/50-perm_chng.rules << 'EOF'
-a always,exit -F path=/usr/bin/chcon -F perm=x -F auid>=1000 -F auid!=unset -k perm_chng
-a always,exit -F path=/usr/bin/setfacl -F perm=x -F auid>=1000 -F auid!=unset -k perm_chng
-a always,exit -F path=/usr/bin/chacl -F perm=x -F auid>=1000 -F auid!=unset -k perm_chng
EOF
    fi

    # Правила kernel_modules
    cat > /etc/audit/rules.d/50-kernel_modules.rules << 'EOF'
# Мониторинг системных вызовов работы с модулями ядра
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module,create_module,query_module -F auid>=1000 -F auid!=-1 -k kernel_modules
# Мониторинг выполнения утилиты kmod
-a always,exit -F path=/usr/bin/kmod -F perm=x -F auid>=1000 -F auid!=-1 -k kernel_modules
EOF

    # Правила usermod
    cat > /etc/audit/rules.d/50-usermod.rules << 'EOF'
-a always,exit -F path=/usr/sbin/usermod -F perm=x -F auid>=1000 -F auid!=unset -k usermod
EOF

    # Правила privilege-escalation
    cat > /etc/audit/rules.d/50-privilege-escalation.rules << 'EOF'
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k privilege_escalation
EOF

    # Правила ssh
    cat > /etc/audit/rules.d/50-ssh.rules << 'EOF'
-w /etc/ssh/ -p wa -k ssh_config
EOF

    # Настройка прав доступа к файлам audit
    log "Настройка прав доступа к файлам audit..."
    find /etc/audit/ -type f \( -name '*.conf' -o -name '*.rules' \) -exec chmod u-x,g-wx,o-rwx {} +

    # Финальная настройка аудита
    log "Финальная настройка аудита..."
    echo "-e 2" | tee -a /etc/audit/rules.d/99-finalize.rules > /dev/null
    augenrules --load

    check_command "Настройка правил аудита"
    
    log "Проверка статуса auditd:"
    systemctl status auditd --no-pager -l
    log "Текущие правила аудита:"
    auditctl -l | head -20
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main "$@"