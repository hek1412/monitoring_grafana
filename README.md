# ДЗ2. Мониторинг в Grafana сервисов JupyterHub и PosgresQL (+алерты)

В рамках выполнения домашнего задания будут развернуты необходимые сервисы, созданы скрипты и настроены дашборды в Grafana для отображения информации:
- О активности пользователей в JupyterHub.
- Сведения о потреблении ресурсов тетрадей ноутбука.
- Сведения о топовых таблицах в PostgreSQL с их владельцами.
- Алерт оповещающий при заходе пользователя на сервер по SSH на почту.
- Алерт оповещающий при превышении общей мощности контейнеров более чем на 80%.

---
## Описание проекта

Сервисы которые будем использовать для мониторинга PostgreSQL, JupyterHub и системных метрик сервера:
- **Prometheus**: Система сбора метрик.
- **Grafana**: Инструмент визуализации метрик.
- **cAdvisor**: Мониторинг ресурсов Docker-контейнеров.
- **Node Exporter**: Сбор системных метрик хоста.
- **Alertmanager**: Управление оповещениями.
- **pg_metrics_exporter**: Экспортер PostgreSQL.


Учитывая что Jupyterhub у нас уже был создан в рамках выполнения другого задания, описывать процесс его развертывания не буду.
[Jupyterhub](https://github.com/hek1412/JupyterHub?tab=readme-ov-file#jupyterhub--postgresql-%D1%81-%D0%BF%D0%BE%D0%BC%D0%BE%D1%89%D1%8C%D1%8E-docker-compose)

В данном проекте, я ипользовал другой созданный мной jupyterhub_v1 с поддержкой графического процессора через среду выполнения NVIDIA, аутентификацией пользователей через GitHub OAuth (для перехода в репозиторий кликаем по по ссылке [Jupyterhub_v1](https://github.com/hek1412/JupyterHub_v1?tab=readme-ov-file#jupyterhub_v1))

---

## Структура проекта

```
Grafana/
│
├── docker-compose.yaml 
│
├──.env
│
├── prometheus/ Каталог с конфигурацией Prometheus.
│   ├── prometheus.yml
│   └── alert.rules.yml
│
├── grafana/ Каталог для Grafana
│   ├── JupyterHub.json
│   ├── Information_on_container_and_volume_sizes.json
│   └── PostgresQL_information.json
│
├── alertmanager/ Каталог с конфигурацией Alertmanager.
│   └── alertmanager.yml
│
├── script/ Каталог для скриптов
│   ├── sum_container_sizes.sh
│   ├── move_metrics.sh
│   └── ssh_monitor.sh
│
├── metrics/ Создаваемая сервисами дирекpия с метрики.
│   ├── container_sizes.prom
│   ├── pg_metrics.prom
│   └── image_sizes.prom
│
└── pg_metrics_exporter/ Каталог со скриптом на питоне для осуществления запросов в POSTGRES_DB.
    ├── Dockerfile.exporter
    └── pg_metrics_exporter.py 

```

## Запуск сервисов

Мой `docker compose` включает в себя сервисы с параметрами:

```
services:
 
  postgrestest:
    image: postgres:17.2-bookworm
    container_name: postgrestest
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD} 
      POSTGRES_DB: ${POSTGRES_DB}
      PGDATA: /var/lib/postgresql/data/
    ports:
      - "5434:5432"
    volumes:
      - postgres-datatest:/var/lib/postgresql/data/
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U postgres -d postgres_db" ]
      interval: 30s
      timeout: 10s
      retries: 5
    restart: unless-stopped
    networks:
      - monitoring-network
      - jupyterhub-network

  pg_metrics_exporter:
    build:
      context: ./pg_metrics_exporter # относительный путь к директории, где находится контекст сборки
      dockerfile: Dockerfile.exporter
    container_name: pg_metrics_exportertest
    volumes:
      - ./metrics:/metrics  # Монтируем директорию для метрик
    environment:
      POSTGRES_HOST: postgrestest
      POSTGRES_PORT: 5432
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    depends_on:
      - postgrestest
    restart: unless-stopped
    networks:
      - monitoring-network

  prometheus:
    image: prom/prometheus:v3.1.0
    container_name: prometheustest
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml # Конфигурационный файл Prometheus
      - prometheus-datatest:/prometheus # Volume для сохранения данных Prometheus
      - ./prometheus/alert.rules.yml:/etc/prometheus/alert.rules.yml  # Правила оповещений
    command:
      - '--config.file=/etc/prometheus/prometheus.yml' # Команда для запуска с конфигурационным файлом
    ports:
      - "35101:9090"
    restart: unless-stopped
    networks:
      - monitoring-network
      - jupyterhub-network
    
  grafana:
    image: grafana/grafana-enterprise:11.5.1
    container_name: grafanatest
    ports:
      - "35100:3000"
    networks:
      - monitoring-network
    volumes:
      - grafana-datatest:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_AUTH_ANONYMOUS_ENABLED=true # Включение анонимного доступа
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.2
    container_name: cadvisortest
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    networks:
      - monitoring-network
    restart: unless-stopped
  
  node-exporter:
    image: prom/node-exporter:v1.5.0 
    container_name: node-exportertest
    ports:
      - "35102:9100"
    networks:
      - monitoring-network
    volumes:
      - /var/lib/node_exporter:/app/metrics:ro # Монтируемая директория для метрик
    command:
      - '--collector.filesystem.ignored-mount-points="^/(sys|proc|dev|host|etc)($$|/)"' # Игнорируемые точки монтирования
      - '--collector.textfile.directory=/app/metrics'  # Директория для текстовых метрик
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:v0.28.0
    container_name: alertmanagertest
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml # Конфигурационный файл Alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
    ports:
      - "9093:9093"
    networks:
      - monitoring-network
    restart: unless-stopped
    
volumes:
  postgres-datatest:
  grafana-datatest:
  prometheus-datatest:

networks:
  monitoring-network:
    name: monitoring-network
  jupyterhub-network:
    name: jupyterhub-network
    external: true
```

Переходим в директорию с проектом, создаем образы и запускаем контейнеры сервисов:

```
docker compose up --build -d
```
![image](https://github.com/user-attachments/assets/a67c1e60-e489-4a61-9969-4d01cfc88b44)


### Настройка источника данных в Grafana

Переходим в веб-интерфейс Grafana:

```
http://skayfaks.keenetic.pro:35100/
```

Выбераем источник данных Prometheus, используем  `http://prometheustest` и порт `9090`, нажимаем тест.

![image](https://github.com/user-attachments/assets/70ec9228-1be6-4658-916c-758db0a96098)

---

## Дашборды

### 1. Сведения о контейнерах JupyterHub

Импортируем дашборд для мониторинга активности пользователей в JupyterHub:

```
grafana/JupyterHub.json
```

Ссылка на публичный дашборд: http://skayfaks.keenetic.pro:35100/d/bedxa8g8anqiof/jupyterhub-svedenija-o-kontejnerah-2?orgId=1&from=now-15m&to=now&timezone=browser&refresh=1m

Теперь благодаря этого дашборда мы можем в графане отслеживать активность пользователей JupyterHub, анализировать использования CPU и размер файловой системы.

![image](https://github.com/user-attachments/assets/4f9a88ff-2f94-4a60-80c2-be0a29a0d54f)

Получили первый дашборд, отлично, но мне не понравилось что юпитер хаб не дает метрики по реальному размеру контейнеров с учетом слоев образа.

### 2. Размеры контейнеров и томов

Для реализации этого используем скрипт для получения полных размеров контейнеров [`script/sum_container_sizes.sh`](https://github.com/hek1412/monitoring_grafana/tree/main/script#%D1%81%D0%BA%D1%80%D0%B8%D0%BF%D1%82-%D0%B4%D0%BB%D1%8F-%D1%81%D0%B1%D0%BE%D1%80%D0%B0-%D0%BC%D0%B5%D1%82%D1%80%D0%B8%D0%BA-%D0%B8%D1%81%D0%BF%D0%BE%D0%BB%D1%8C%D0%B7%D0%BE%D0%B2%D0%B0%D0%BD%D0%B8%D1%8F-%D0%B4%D0%B8%D1%81%D0%BA%D0%BE%D0%B2%D0%BE%D0%B3%D0%BE-%D0%BF%D1%80%D0%BE%D1%81%D1%82%D1%80%D0%B0%D0%BD%D1%81%D1%82%D0%B2%D0%B0-docker-%D0%BA%D0%BE%D0%BD%D1%82%D0%B5%D0%B9%D0%BD%D0%B5%D1%80%D0%BE%D0%B2-%D0%B8-%D0%BE%D0%B1%D1%80%D0%B0%D0%B7%D0%BE%D0%B2-sum_container_sizessh)

Импортируем дашборд:

```
grafana/Information_on_container_and_volume_sizes.json
```

Ссылка на публичный дашборд:
http://skayfaks.keenetic.pro:35100/d/aedxfkzowsyyoa/svedenija-o-razmerah-kontejnerov-i-tomov?orgId=1&from=now-6h&to=now&timezone=browser

Используем написанный скрипт
`script/sum_container_sizes.sh`
[Ссылка на README в script](script/README.md)

с его помощью получаем полные размеры всех контейнеров и не только юпитера 
![image](https://github.com/user-attachments/assets/63654216-614e-4d1f-936c-6a7f1d04adbf)

если нужно только сведения по юпитеру то смотрим в другую панель (теперь сразу видно кто сжирает все место на серваке)
![image](https://github.com/user-attachments/assets/eb85976d-35aa-4546-a06c-d7cfbc090bc2)

Так же добавил отображения размера томов контейнеров)
![image](https://github.com/user-attachments/assets/473e1c36-2343-46ae-bcb6-6a6af0a6e438)



### 3. Сведения о PostgreSQL

Следующий этап, это PosgreSQL и получение сведений о таблицах с их владельцами.
для получения метрик используем созданный [`pg_metrics_exporter.py`](https://github.com/hek1412/monitoring_grafana/tree/main/pg_metrics_exporter#%D0%BE%D0%BF%D0%B8%D1%81%D0%B0%D0%BD%D0%B8%D0%B5-%D1%81%D0%B5%D1%80%D0%B2%D0%B8%D1%81%D0%B0-%D0%B4%D0%BB%D1%8F-%D1%8D%D0%BA%D1%81%D0%BF%D0%BE%D1%80%D1%82%D0%B0-%D0%BC%D0%B5%D1%82%D1%80%D0%B8%D0%BA-postgresql) завернутый в контейнер и в бесконечный цикл.
Импортируем дашборд:

```
grafana/PostgresQL_information.json
```

Ссылка на публичный дашборд: http://skayfaks.keenetic.pro:35100/d/eedyi3fmm718gc/svedenija-postgresql?orgId=1&from=now-6h&to=now&timezone=browser

С этой задачей справляется скрипт `pg_metrics_exporter.py` который запускается в контейнере `pg_metrics_exporter` и исполняется в бесконечном цикле, каждые 10 минут.
Так же как и скрипт для получения метрик о размерах контейнеров и томов, этот скрипт выводит все метрики в директорию с метриками в файл `pg_metrics.prom` и далее они копируются в `/var/lib/node_exporter` скриптом `move_metrics.sh`.
Важно не забыть наполнить БД необходимыми таблицами для тестов).

Теперь у нас отражается общий размер БД и размеры таблиц с их владельцами:

![image](https://github.com/user-attachments/assets/16332c0b-943d-4d36-8a94-1abb0bedf211)

Так же в дашборд добавлены метрики отображающие информацию по количеству сканирований таблиц и общее колическло прочитанных строк которые были обработаны при выполнении запросов.

---

## Алерты

### Настройка алертов в Prometheus

Теперь переходим к алертам.
Первый алерт отслеживает контейнеры у которых использование CPU более 80 %, второй отслеживает вход на сервер пользователей по SSH.
Переходим в веб интерфейс Prometheus, вкладку алертов, убеждаемся, что они неактивны и зеленые: http://skayfaks.keenetic.pro:35101/alerts

![image](https://github.com/user-attachments/assets/0f9e69da-4666-4676-ae48-97f2b7f377b0)


#### Алерт 1: Использование CPU более 80%

Даем нагрузку на процессор, например через блокнот Jupyter `jupyter-yurecc197` запустив скрипт:
Проверяем активацию алерта. (sum (rate(container_cpu_usage_seconds_total{name=~".+"}[5m]))* 100 > 80)

![image](https://github.com/user-attachments/assets/8e48e29e-3c32-4cbb-b667-85f21f3b2739)

Получаем соответствующее уведомление

![image](https://github.com/user-attachments/assets/1995ce90-c9e0-4881-a4fe-00a47b3378bf)

#### Алерт 2: Вход пользователей по SSH

Для отслеживания входа пользователей по SSH используем скрипт [`script/ssh_monitor.sh`](https://github.com/hek1412/monitoring_grafana/tree/main/script#%D1%81%D0%BA%D1%80%D0%B8%D0%BF%D1%82-%D0%B4%D0%BB%D1%8F-%D1%81%D0%B1%D0%BE%D1%80%D0%B0-%D0%BC%D0%B5%D1%82%D1%80%D0%B8%D0%BA-%D0%BF%D0%BE%D0%BF%D1%8B%D1%82%D0%BE%D0%BA-%D0%B2%D1%85%D0%BE%D0%B4%D0%B0-%D1%87%D0%B5%D1%80%D0%B5%D0%B7-ssh-ssh_monitorsh)
который считывает логи `/var/log/auth.log` и выводит в файл `/var/lib/node_exporter/ssh_login_metrics.prom` который монтируется в экспортер.

Теперь входим по SSH и ждем когда скрипт запишет метрики)
![image](https://github.com/user-attachments/assets/0c11c746-d27f-450b-8caf-2c014be3637b)

Получаем уведомление! Теперь никто не пройдет не замеченным)))
![image](https://github.com/user-attachments/assets/0017e910-d72d-4ae5-95dc-b77eab73688e)

---

## Cron-задания

При написании скриптов необходимо обязательно дать разрешения на запись в соответствующие директории и сделать скрипты исполняемыми для использования в cron. 

Добавляем эти строчки в `sudo crontab -e` и направим вывод логов в отдельный файл для записи логов.

```
*/6 * * * * /home/vitaliyaleks/monitoring/script/move_metrics.sh >> /home/vitaliyaleks/cron.log 2>&1
*/1 * * * * /home/vitaliyaleks/monitoring/script/ssh_monitor.sh >> /home/vitaliyaleks/cron.log 2>&1
*/15 * * * * /home/vitaliyaleks/monitoring/script/sum_container_sizes.sh >> /home/vitaliyaleks/cron.log 2>&1
```
---

## Monitiring GPU

В связи с постоянными трудностями по мониторингу нагрузки за GPU, решено было добавить мониторинг Bash-скриптом `gpu_test.sh` который собирает информацию о состоянии графических процессоров (GPU) с использованием утилиты nvidia-smi и записывает данные в формате Prometheus. Метрики включают использование GPU, потребление памяти, температуру и использование памяти отдельными процессами.
[`gpu_test.sh`
](https://github.com/hek1412/monitoring_grafana/tree/main/script#%D1%81%D0%BA%D1%80%D0%B8%D0%BF%D1%82-%D0%B4%D0%BB%D1%8F-%D1%81%D0%B1%D0%BE%D1%80%D0%B0-%D0%BC%D0%B5%D1%82%D1%80%D0%B8%D0%BA-%D0%B8%D1%81%D0%BF%D0%BE%D0%BB%D1%8C%D0%B7%D0%BE%D0%B2%D0%B0%D0%BD%D0%B8%D1%8F-gpu-%D0%B8-%D0%BF%D1%80%D0%BE%D1%86%D0%B5%D1%81%D1%81%D0%BE%D0%B2-gpu_testsh)

Импортируем дашборд:

```
grafana/Monitiring_GPU.json
```

Не забываем добавить в sudo crontab -e
```
*/5 * * * * /home/vitaliyaleks/monitoring/script/gpu_test.sh >> /home/vitaliyaleks/cron.log 2>&1
```

http://skayfaks.keenetic.pro:35100/d/bee2c3g6nhnggb/ispol-zovanie-gpu?orgId=1&from=now-1h&to=now&timezone=browser&refresh=1m

Получился еще одна важная визуализация)
 ![image](https://github.com/user-attachments/assets/75b3aa8f-b1fb-4a82-8003-da4251450fa2)

---

## cAdvisor

Так же импортировал готовый дашборд cAdvisor с основной информацией по Docker
![image](https://github.com/user-attachments/assets/cb1f8010-09c0-43d2-95c5-7455c0ff4892)

Импортируем дашборд:

```
grafana/cAdvisor_Docker.json
```

Все дашборды по http://skayfaks.keenetic.pro:35100/dashboards


 

