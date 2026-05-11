#!/bin/bash

# Скрипт для установки и настройки Zabbix Agent 2

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

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Проверка успешности выполнения команды
check_success() {
    if [ $? -eq 0 ]; then
        log "✓ $1"
    else
        error "✗ $2"
        exit 1
    fi
}

# Основная функция
main() {
    log "=== Установка и настройка Zabbix Agent 2 ==="
    
    check_root
    
    # 1. Скачиваем пакет Zabbix репозитория
    log "Скачивание пакета Zabbix репозитория..."
    wget -q https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu26.04_all.deb
    
    if [ -f "zabbix-release_latest_7.4+ubuntu26.04_all.deb" ]; then
        log "✓ Пакет Zabbix репозитория успешно скачан"
    else
        error "✗ Ошибка при скачивании пакета"
        exit 1
    fi
    
    # Устанавливаем пакет репозитория
    log "Установка пакета Zabbix репозитория..."
    dpkg -i zabbix-release_latest_7.4+ubuntu26.04_all.deb
    check_success "Пакет репозитория установлен" "Ошибка при установке пакета репозитория"
    
    # Обновляем список пакетов
    log "Обновление списка пакетов..."
    apt-get update -qq
    check_success "Список пакетов обновлен" "Ошибка при обновлении списка пакетов"
    
    # 2. Устанавливаем zabbix-agent2
    log "Установка Zabbix Agent 2..."
    apt-get install -y zabbix-agent2
    check_success "Zabbix Agent 2 установлен" "Ошибка при установке Zabbix Agent 2"
    
    # Останавливаем сервис для внесения изменений
    log "Остановка Zabbix Agent 2 для внесения изменений..."
    systemctl stop zabbix-agent2
    check_success "Сервис остановлен" "Ошибка при остановке сервиса"
    
    # 3. Настройка конфигурационного файла
    CONF_FILE="/etc/zabbix/zabbix_agent2.conf"
    
    if [ -f "$CONF_FILE" ]; then
        log "Настройка конфигурационного файла: $CONF_FILE"
        
        # Создаем резервную копию
        cp "$CONF_FILE" "${CONF_FILE}.backup"
        log "✓ Создана резервная копия: ${CONF_FILE}.backup"
        
        # Заменяем Server=127.0.0.1 на Server=10.100.0.4
        sed -i 's/^Server=127.0.0.1$/Server=10.100.0.4/' "$CONF_FILE"
        
        # Проверяем, что замена выполнена
        if grep -q "^Server=10.100.0.4" "$CONF_FILE"; then
            log "✓ Настройка Server=10.100.0.4 применена"
        else
            warn "Не удалось автоматически заменить Server, проверьте конфигурацию вручную"
        fi
    else
        error "Файл конфигурации не найден: $CONF_FILE"
        exit 1
    fi
    
    # 4. Запускаем сервис
    log "Запуск Zabbix Agent 2..."
    systemctl start zabbix-agent2
    check_success "Сервис запущен" "Ошибка при запуске сервиса"
    
    # Включаем автозапуск
    log "Включение автозапуска Zabbix Agent 2..."
    systemctl enable zabbix-agent2
    check_success "Автозапуск включен" "Ошибка при включении автозапуска"
    
    # Проверяем статус сервиса
    if systemctl is-active --quiet zabbix-agent2; then
        log "✓ Zabbix Agent 2 успешно установлен, настроен и запущен"
        log "=== Установка завершена успешно ==="
    else
        error "Zabbix Agent 2 не запущен. Проверьте статус: systemctl status zabbix-agent2"
        exit 1
    fi
    
    # Удаляем скачанный .deb файл
    rm -f zabbix-release_latest_7.4+ubuntu26.04_all.deb
    log "✓ Временные файлы удалены"
}

# Запуск основной функции
main "$@"