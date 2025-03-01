import os
import psycopg2

# Настройки подключения к PostgreSQL
DB_HOST = os.getenv("DB_HOST", "postgrestest")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "postgres_db")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

# Путь к файлу для записи метрик
METRICS_FILE = "/metrics/pg_metrics.prom"

def collect_and_write_metrics():
    try:
        # Подключение к PostgreSQL
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        cursor = conn.cursor()

        # Создаем строку для записи метрик
        metrics_data = ""

        # Запрос для получения размеров таблиц и их владельцев
        cursor.execute("""
            SELECT 
                c.relname AS table_name, 
                pg_total_relation_size(c.oid) AS table_size,
                pg_get_userbyid(c.relowner) AS table_owner
            FROM pg_class c
            JOIN pg_stat_user_tables t ON c.relname = t.relname;
        """)
        table_sizes = cursor.fetchall()

        # Добавляем метрики размеров таблиц с информацией о владельцах
        metrics_data += "# HELP pg_table_size_bytes Size of tables in bytes\n"
        metrics_data += "# TYPE pg_table_size_bytes gauge\n"
        for table_name, size, owner in table_sizes:
            metrics_data += f'pg_table_size_bytes{{table_name="{table_name}", owner="{owner}"}} {size}\n'

        # Запрос для получения размера баз данных в мегабайтах
        cursor.execute("""
            SELECT datname, pg_database_size(datname) / 1024 / 1024 AS size_mb
            FROM pg_database;
        """)
        db_sizes = cursor.fetchall()

        # Добавляем метрики размеров баз данных
        metrics_data += "# HELP pg_database_size_mb Size of databases in megabytes\n"
        metrics_data += "# TYPE pg_database_size_mb gauge\n"
        for db_name, size_mb in db_sizes:
            metrics_data += f'pg_database_size_mb{{database="{db_name}"}} {size_mb}\n'

        # Запрос для получения количества операций (оставляем только seq_scan и seq_tup_read)
        cursor.execute("""
            SELECT 
                t.relname AS table_name, 
                t.seq_scan, 
                t.seq_tup_read,
                pg_get_userbyid(c.relowner) AS table_owner
            FROM pg_stat_user_tables t
            JOIN pg_class c ON t.relname = c.relname;
        """)
        table_operations = cursor.fetchall()

        # Добавляем метрики операций с информацией о владельцах
        metrics_data += "# HELP pg_table_seq_scan_total Total sequential scans\n"
        metrics_data += "# TYPE pg_table_seq_scan_total counter\n"
        metrics_data += "# HELP pg_table_seq_tup_read_total Total tuples read sequentially\n"
        metrics_data += "# TYPE pg_table_seq_tup_read_total counter\n"

        for table_name, seq_scan, seq_tup_read, owner in table_operations:
            metrics_data += f'pg_table_seq_scan_total{{table_name="{table_name}", owner="{owner}"}} {seq_scan}\n'
            metrics_data += f'pg_table_seq_tup_read_total{{table_name="{table_name}", owner="{owner}"}} {seq_tup_read}\n'

        # Записываем метрики в файл
        with open(METRICS_FILE, "w") as f:
            f.write(metrics_data)

        print("Metrics successfully written to file.")

    except Exception as e:
        print(f"Error: {e}")
    finally:
        if conn:
            conn.close()

if __name__ == "__main__":
    collect_and_write_metrics()