#!/bin/bash

DIR="/var/lib/node_exporter"
METRICS_FILE="$DIR/ssh_login_metrics.prom"

# Проверка существования файла логов
if [ ! -f /var/log/auth.log ]; then
  echo "Log file not found!"
  exit 1
fi

# Генерация файла метрик с заголовками
{
  echo "# HELP ssh_login_attempt_info SSH login attempts with username and IP"
  echo "# TYPE ssh_login_attempt_info gauge"

  # Обработка лог-файла за один проход
  awk '
    /sshd.*Accepted/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "for") user = $(i + 1)
        if ($i == "from") ip = $(i + 1)
      }
      if (user != "" && ip != "") counts[user "," ip]++
    }
    END {
      for (pair in counts) {
        split(pair, arr, ",")
        printf "ssh_login_attempt_info{username=\"%s\", ip=\"%s\"} %d\n", arr[1], arr[2], counts[pair]
      }
    }
  ' /var/log/auth.log
} > "$METRICS_FILE"
# Проверка успешности записи
if [ $? -eq 0 ]; then
  echo "Метрики успешно записаны в $METRICS_FILE"
else
  echo "Ошибка при записи метрик в $METRICS_FILE"
  exit 1
fi