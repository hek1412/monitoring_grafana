#!/bin/bash

# Создаем директорию metrics, если её нет
mkdir -p metrics
# Файлы для вывода метрик
container_output_file="/home/vitaliyaleks/test1/metrics/container_sizes.prom"
image_output_file="/home/vitaliyaleks/test1/metrics/image_sizes.prom"

# Очистка файлов перед записью
> "$container_output_file"
> "$image_output_file"

# Функция для преобразования размера в байты
convert_to_bytes() {
  local value=$(echo "$1" | grep -oP '\d+\.?\d*')
  local unit=$(echo "$1" | grep -oP '[A-Za-z]+')

  case $unit in
    GB)
      echo "$value * 1024 * 1024 * 1024" | bc
      ;;
    MB)
      echo "$value * 1024 * 1024" | bc
      ;;
    KB)
      echo "$value * 1024" | bc
      ;;
    B)
      echo "$value"
      ;;
    *)
      echo "0"
      ;;
  esac
}

# Добавляем описание метрики для контейнеров в начало файла
echo "# HELP container_disk_usage_bytes Total disk usage of Docker containers in MB" > "$container_output_file"
echo "# TYPE container_disk_usage_bytes gauge" >> "$container_output_file"

# Обрабатываем информацию о контейнерах
container_info=$(docker ps -s --format "{{.Names}}\t{{.Size}}")
echo "$container_info" | while read -r line; do
  # Извлекаем имя контейнера, размер файловой системы и виртуальный размер
  container_name=$(echo "$line" | awk '{print $1}')
  size=$(echo "$line" | awk '{print $2}')           # Размер файловой системы
  virtual_size=$(echo "$line" | awk '{print $4}')  # Виртуальный размер

  # Преобразуем размер файловой системы и виртуальный размер в байты
  size_bytes=$(convert_to_bytes "$size")
  virtual_size_bytes=$(convert_to_bytes "$virtual_size")

  # Складываем размер файловой системы и виртуальный размер
  total_size_bytes=$(echo "$size_bytes + $virtual_size_bytes" | bc)

  # Преобразуем общий размер в мегабайты (MB)
  total_size_mb=$(echo "scale=2; $total_size_bytes / (1024 * 1024)" | bc)

  # Записываем метрику в файл в формате .prom
  echo "container_disk_usage_bytes{container=\"$container_name\"} $total_size_mb" >> "$container_output_file"
done

# Добавляем описание метрики для образов в начало файла
echo "# HELP image_disk_usage_bytes Total disk usage of Docker images in MB" > "$image_output_file"
echo "# TYPE image_disk_usage_bytes gauge" >> "$image_output_file"

# Обрабатываем информацию о образах Docker
image_info=$(docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}")
echo "$image_info" | while read -r line; do
  # Извлекаем имя образа и его размер
  image_name=$(echo "$line" | awk '{print $1}')
  size=$(echo "$line" | awk '{print $2}')  # Размер образа

  # Пропускаем образы с пустыми значениями Repository или Tag
  if [[ "$image_name" == "<none>:<none>" ]]; then
    continue
  fi

  # Преобразуем размер в байты
  size_bytes=$(convert_to_bytes "$size")

  # Преобразуем размер в мегабайты (MB)
  size_mb=$(echo "scale=2; $size_bytes / (1024 * 1024)" | bc)

  # Записываем метрику в файл в формате .prom
  echo "image_disk_usage_bytes{image=\"$image_name\"} $size_mb" >> "$image_output_file"
done

echo "Метрики успешно записаны в $image_output_file"