#!/bin/bash

output_file="/deploy/monitoring_grafana/metrics/gpu.prom"
> "$output_file"

# Функция для безопасного извлечения значений
get_metric() {
    echo "$1" | awk -F', ' -v idx="$2" '{print $idx}' | sed 's/^ *//;s/ *$//' | tr -d '\n'
}

# Получаем основные метрики GPU
gpu_metrics=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits)
gpu_utilization=$(get_metric "$gpu_metrics" 1)
gpu_memory_used=$(get_metric "$gpu_metrics" 2)
gpu_memory_total=$(get_metric "$gpu_metrics" 3)
gpu_temperature=$(get_metric "$gpu_metrics" 4)

# Формируем основную часть метрик
cat <<EOF > "$output_file"
# HELP gpu_utilization GPU utilization percentage
# TYPE gpu_utilization gauge
gpu_utilization $gpu_utilization

# HELP gpu_memory_used GPU memory used in MiB
# TYPE gpu_memory_used gauge
gpu_memory_used $gpu_memory_used

# HELP gpu_memory_total Total GPU memory in MiB
# TYPE gpu_memory_total gauge
gpu_memory_total $gpu_memory_total

# HELP gpu_temperature GPU temperature in Celsius
# TYPE gpu_temperature gauge
gpu_temperature $gpu_temperature

# HELP gpu_process_memory_usage GPU memory usage by process in MiB
# TYPE gpu_process_memory_usage gauge
EOF

# Обрабатываем процессы
nvidia-smi --query-compute-apps=pid,used_memory,process_name --format=csv,noheader,nounits | while read -r line; do
    # Пропускаем пустые строки
    [ -z "$line" ] && continue
    
    # Извлекаем значения с учетом возможных пробелов
    pid=$(get_metric "$line" 1)
    used_memory=$(get_metric "$line" 2)
    process_name=$(get_metric "$line" 3)

    # Если имя процесса пустое, пытаемся получить через ps
    if [ -z "$process_name" ] && [[ "$pid" =~ ^[0-9]+$ ]]; then
        process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
    fi

    # Заменяем проблемные символы (кроме разрешенных)
    process_name=$(echo "$process_name" | sed 's/[^a-zA-Z0-9_\/\.:-]/_/g')

    # Записываем метрику
    echo "gpu_process_memory_usage{pid=\"$pid\", process_name=\"$process_name\"} $used_memory" >> "$output_file"
done

echo "Метрики успешно записаны в $output_file"