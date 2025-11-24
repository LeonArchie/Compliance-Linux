#!/bin/bash

# Укажите желаемое имя сервера
name="serv-hw2-k8s-master"

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
    echo "Этот скрипт должен быть запущен с правами root"
    exit 1
fi

# Смена hostname
hostnamectl set-hostname "$name"

# Обновление файла /etc/hosts
sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$name/g" /etc/hosts

echo "Имя сервера успешно изменено на: $name"
echo "Для применения изменений требуется перезагрузка системы"