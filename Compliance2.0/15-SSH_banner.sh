#!/bin/bash

# Настройка баннера SSH

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

# Функция создания баннера
create_ssh_banner() {
    log "Создание баннера SSH..."
    
    # Создаем баннер
    cat > /etc/issue.net << 'EOF'
 =========================================================

 Муниципальное автономное общеобразовательное учреждение
 Средняя общеобразовательная школа № 59

 Только для авторизованных пользователей.
 Все действия регистрируются.
 Поддержка: it@school59-ekb.ru

 =========================================================
EOF

    # Устанавливаем правильные права доступа
    chmod 644 /etc/issue.net
    chown root:root /etc/issue.net
    
    log "✓ Баннер создан: /etc/issue.net"
    
    # Настраиваем использование баннера в SSH
    if [ -f "/etc/ssh/sshd_config" ]; then
        log "Настройка использования баннера в SSH..."
        
        # Создаем backup если его нет
        if [ ! -f "/etc/ssh/sshd_config.banner_backup" ]; then
            cp /etc/ssh/sshd_config /etc/ssh/sshd_config.banner_backup
            log "Создан backup конфигурации SSH: /etc/ssh/sshd_config.banner_backup"
        fi
        
        # Устанавливаем баннер в конфигурации SSH
        sed -i 's/^#*Banner.*/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
        
        # Если параметр не существует, добавляем его
        if ! grep -q "^Banner" /etc/ssh/sshd_config; then
            echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config
        fi
        
        log "✓ Баннер настроен в SSH конфигурации"
        
        # Перезагружаем SSH службу
        log "Перезагрузка службы SSH..."
        if systemctl is-active --quiet ssh; then
            systemctl reload ssh
            log "✓ Служба SSH перезагружена"
        else
            warn "Служба SSH не активна"
        fi
    else
        warn "Файл конфигурации SSH не найден"
    fi
}

# Функция проверки баннера
verify_banner() {
    log "Проверка настроек баннера..."
    
    if [ -f "/etc/issue.net" ]; then
        log "✓ Баннер существует"
        log "Содержимое баннера:"
        echo "----------------------------------------"
        cat /etc/issue.net
        echo "----------------------------------------"
    else
        error "✗ Баннер не создан"
    fi
    
    if sshd -T 2>/dev/null | grep -q "banner /etc/issue.net"; then
        log "✓ Баннер настроен в SSH"
    else
        warn "Баннер не настроен в SSH (возможно, служба SSH не запущена)"
    fi
}

# Основная функция
main() {
    log "=== Настройка баннера SSH ==="
    
    check_root
    create_ssh_banner
    verify_banner
    
    log "=== Настройка баннера завершена ==="
    log "Баннер будет отображаться при подключении по SSH"
}

# Обработка сигналов
trap 'error "Скрипт прерван"; exit 1' INT TERM

# Запуск основной функции
main