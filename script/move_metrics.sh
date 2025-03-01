#!/bin/bash

# Исходная директория (где находятся файлы)
SOURCE_DIR="/home/vitaliyaleks/test1/metrics/"

# Целевая директория (куда нужно перенести файлы)
TARGET_DIR="/var/lib/node_exporter"

# Имена файлов
FILES=("pg_metrics.prom" "container_sizes.prom" "image_sizes.prom" "gpu.prom")

# Создаем целевую директорию, если её нет
mkdir -p "$TARGET_DIR"

# Переносим файлы
for FILE_NAME in "${FILES[@]}"; do
    # Проверяем, существует ли файл
    if [ -f "$SOURCE_DIR/$FILE_NAME" ]; then
        # Переносим файл в целевую директорию
        cp "$SOURCE_DIR/$FILE_NAME" "$TARGET_DIR/$FILE_NAME"
        echo "Файл $FILE_NAME перенесен в $TARGET_DIR"
    else
        echo "Файл $FILE_NAME не найден в $SOURCE_DIR"
    fi
done