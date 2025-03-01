# ДЗ2. Мониторинг в Grafana сервисов JupyterHub и PosgresQL (+алерты)

В рамках выполнения домашнего задания будут развернуты необходимые сервисы, созданы скрипты и настроены дашборды в Grafana для отображения информации:

- О активности пользователей в JupyterHub
- Сведения о потреблении ресурсов тетрадей ноутбука
- Сведения о топовых таблицах в PostgreSQL с их владельцами

### Созданние и настройка алертов

- **Алерт** оповещающий при заходе пользователя на сервер по SSH на почту.
- **Алерт** оповещающий при превышении общей мощности контейнеров более чем на 80%.

---

## Структура проекта

```
Grafana/
│
├── docker-compose.yaml 
│
├── jupyterhub/ Каталог, содержащий конфигурацию для JupyterHub (он был уже развернут по ДЗ1).
│   ├── docker-compose.yaml
│   ├── Dockerfile.jupyterhub
│   └── jupyterhub_config.py
│
├── prometheus/ Каталог с конфигурацией Prometheus.
│   ├── prometheus.yml
│   └── alert.rules.yml
│
├── grafana/ Каталог для Grafana
│   ├── JupyterHub сведения о контейнерах 2.json
│   ├── Сведения о размерах контейнеров и томов.json
│   └── Сведения PostgresQL.json
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

Учитывая что юпитер хаб у нас уже развернут в рамках выполнения другого задания, то переходим сразу к выполнению этих задач.

---

## Настройка JupyterHub для сбора метрик

Необходимо добавить следующие параметры в файл конфигурации `jupyterhub_config.py`:

```python
c.JupyterHub.metrics_enabled = True
c.JupyterHub.metrics_port = 8000
c.JupyterHub.authenticate_prometheus = False
```

---

## Запуск сервисов

Мой `docker compose` включает в себя сервисы:

```
services:
 
  postgrestest:
    image: postgres:17.2-bookworm
    container_name: postgrestest
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: postgres_db
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
      - jupyterhub-network

  pg_metrics_exporter:
    build:
      context: ./pg_metrics_exporter
      dockerfile: Dockerfile.exporter
    container_name: pg_metrics_exportertest
    volumes:
      - ./metrics:/metrics  # Монтируем директорию для метрик
    environment:
      POSTGRES_HOST: postgrestest
      POSTGRES_PORT: 5432
      POSTGRES_DB: postgres_db
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    depends_on:
      - postgrestest
    networks:
      - jupyterhub-network 

  prometheus:
    image: prom/prometheus:latest #v3.1.0
    container_name: prometheustest
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-datatest:/prometheus
      - ./prometheus/alert.rules.yml:/etc/prometheus/alert.rules.yml
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
    ports:
      - "35101:9090"
    networks:
      - jupyterhub-network
    
  grafana:
    image: grafana/grafana-enterprise:latest #11.5.1
    container_name: grafanatest
    ports:
      - "35100:3000"
    networks:
      - jupyterhub-network
    volumes:
      - grafana-datatest:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_AUTH_ANONYMOUS_ENABLED=true

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest #v0.49.2
    container_name: cadvisortest
    ports:
      - "35008:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    networks:
      - jupyterhub-network
    restart: unless-stopped
  
  node-exporter:
    image: prom/node-exporter:v1.5.0 #latest #v1.8.2
    container_name: node-exportertest
    ports:
      - "35102:9100"
    networks:
      - jupyterhub-network
    volumes:
      - /var/lib/node_exporter:/app/metrics:ro
    command:
      - '--collector.filesystem.ignored-mount-points="^/(sys|proc|dev|host|etc)($$|/)"'
      # - '--collector.textfile.directory=/var/lib/node_exporter'
      - '--collector.textfile.directory=/app/metrics'

  alertmanager:
    image: prom/alertmanager:v0.28.0
    container_name: alertmanagertest
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
    ports:
      - "35007:9093"
    networks:
      - jupyterhub-network

volumes:
  postgres-datatest:
  grafana-datatest:
  prometheus-datatest:

networks:
  jupyterhub-network:
    name: jupyterhub-network
```

Перейдим в директорию с проектом и запускаем сервисы:

```
docker compose up --build -d
```
![image](https://github.com/user-attachments/assets/9989da70-518a-4dc4-9bb8-eb60a8e05ad1)


### Настройка источника данных в Grafana

Перейдите в веб-интерфейс Grafana:

```
http://skayfaks.keenetic.pro:35100/
```

Выберите источник данных Prometheus, используя полученный IP-адрес `http://prometheustest` и порт `9090`.

![image](https://github.com/user-attachments/assets/a593b693-cbda-4760-b8ce-c70e438a2acc)

![image](https://github.com/user-attachments/assets/416d26eb-b066-449b-b8d0-6bf34a988b59)


---

## Дашборды

### 1. Сведения о контейнерах JupyterHub

Импортируйте дашборд:

```
grafana/JupyterHub сведения о контейнерах 2.json
```

Ссылка на дашборд:
```
http://skayfaks.keenetic.pro:35100/d/bedxa8g8anqiof/jupyterhub-svedenija-o-kontejnerah-2?orgId=1&from=now-15m&to=now&timezone=browser&refresh=1m
```
Пока у нас запушенных контейнеров пользователей нет, проверим это например в панели юпитер хаба

![image](https://github.com/user-attachments/assets/8ebba85f-379d-4ed3-bcbb-e32232782d6a)

Теперь запустим 3 сервера
![image](https://github.com/user-attachments/assets/a9d7e787-4695-4b26-a8ea-7b63f0701270)

Возвращаемся в графану и анализируем полученные результаты)
![image](https://github.com/user-attachments/assets/4d64bb49-91df-4565-9642-84dde9a78d4b)


Получили первый дашборд, отлично, но мне не понравилось что юпитер хаб не дает реальный размер контейнеров с учетом слоев образа.

### 2. Размеры контейнеров и томов

Используем скрипт для получения полных размеров контейнеров `script/sum_container_sizes.sh`

Импортируем дашборд:

```
grafana/Сведения о размерах контейнеров и томов.json
```

Ссылка на дашборд:
```
http://skayfaks.keenetic.pro:35100/d/aedxfkzowsyyoa/svedenija-o-razmerah-kontejnerov-i-tomov?orgId=1&from=now-6h&to=now&timezone=browser
```

Используем написанный скрипт
`script/sum_container_sizes.sh`
[Ссылка на README в script](script/README.md)

с его помощью получаем полные размеры всех контейнеров и не только юпитера 
![image](https://github.com/user-attachments/assets/03ed3408-d57f-48a5-b822-cd58b1f19106)

если нужно только спедения по юпитеру то используем другой дашборд (теперь сразу видно кто сжирает все место на серваке)
![image](https://github.com/user-attachments/assets/e611db6f-36d8-4c4c-9aed-ca7f44f8628f)

Так же добавил отображения размера томов контейнеров)
![image](https://github.com/user-attachments/assets/ad421893-713c-4807-a6e4-cedffd83fc98)


### 3. Сведения о PostgreSQL

Следующий этап, это PosgresQL и получение сведений о таблицах с их владельцами.
Импортируйте дашборд:

```
grafana/Сведения PostgresQL.json
```

Ссылка на дашборд:
```
http://skayfaks.keenetic.pro:35100/d/eedyi3fmm718gc/svedenija-postgresql?orgId=1&from=now-6h&to=now&timezone=browser
```

С этой задачей справляется скрипт `pg_metrics_exporter.py` который запускается в контейнере `pg_metrics_exporter` каждые 10 минут.
Так же как и получение сведений о размерах контейнеров и томов, этот скрипт выводит все метрики в директорию с метриками в файл `pg_metrics.prom` и далее они копируются в `/var/lib/node_exporter` скриптом `move_metrics.sh`.
Важно не забыть наполнить БД необходимыми таблицами для тестов).

Теперь у нас отражается общий размер БД и размеры таблиц:
![image](https://github.com/user-attachments/assets/33100cfe-ef0e-4154-a309-a2edc4f80be5)
![image](https://github.com/user-attachments/assets/a3acd668-82f3-4414-b963-552621808a95)

Так же в дашборд добавлены метрики отображающие информацию по количеству сканирований таблиц и прочитанных строк которые были прочитаны, что может влиять на нагрузку и возможно запросы необходимо оптимизировать. 

---

## Алерты

### Проверка алертов в Prometheus

Теперь переходим к алертам.
Первый алерт отслеживает контейнеры у которых использование CPU более 80 %, второй отслеживает вход на сервер пользователей по SSH.
Переходим в веб интерфейс Prometheus, вкладку алертов, убеждаемся, что они неактивны и зеленые:

```
http://skayfaks.keenetic.pro:35101/alerts
```
![image](https://github.com/user-attachments/assets/622c9479-df48-4da5-ba8c-70d399d4f334)


#### Алерт 1: Использование CPU более 80%

Даем нагрузку на процессор например через блокнот Jupyter`jupyter-yurecc197` запустив скрипт на работу с языковой моделью:

![image](https://github.com/user-attachments/assets/577c55d4-f573-44ae-96ff-2366df989a88)

Проверяем активацию алерта.
![image](https://github.com/user-attachments/assets/289e1917-6eac-4e3b-96a1-34c92cb63783)

Получаем уведомление
![image](https://github.com/user-attachments/assets/785ab5cc-c298-4f91-9c98-51f5ea065831)

#### Алерт 2: Вход пользователей по SSH

Для отслеживания входа пользователей по SSH используем скрипт `script/ssh_monitor.sh`
который считывает логи `/var/log/auth.log` и выводит в файл `/var/lib/node_exporter/ssh_login_metrics.prom` который монтируется в экспортер.

Добавил в дашборд метрику по SSH для наглядности
![image](https://github.com/user-attachments/assets/8d72f0cb-b7f1-43b8-a65a-781041bca082)

теперь входим по SSH и ждем получения уведомления)
![image](https://github.com/user-attachments/assets/1dda5dc3-e5cb-4d72-b99e-7c255125a4e5)

Теперь никто не пройдет не замеченным)))
![image](https://github.com/user-attachments/assets/6c7f5d38-345e-4186-abb7-dc02d537952b)

---

## Cron-задания

При написании скриптов необходимо обязательно дать разрешения на запись в соответствующие директории и сделать скрипты исполняемыми для использования в cron. 

Добавляем эти строчки в `crontab -e` и направляем вывод логов в отдельный файл для чтения логов и понимания почему метрики не обновляются)

```
*/6 * * * * /home/vitaliyaleks/test1/script/move_metrics.sh >> /home/vitaliyaleks/cron.log 2>&1
*/5 * * * * /home/vitaliyaleks/test1/script/ssh_monitor.sh >> /home/vitaliyaleks/cron.log 2>&1
*/15 * * * * /home/vitaliyaleks/test1/script/sum_container_sizes.sh >> /home/vitaliyaleks/cron.log 2>&1
```

---




 



 

