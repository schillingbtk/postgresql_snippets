CREATE OR REPLACE VIEW pgbouncer.stats
 AS
 SELECT database,
    total_server_assignment_count,
    total_xact_count,
    total_query_count,
    total_received,
    total_sent,
    total_xact_time,
    total_query_time,
    total_wait_time,
    total_client_parse_count,
    total_server_parse_count,
    total_bind_count,
    avg_server_assignment_count,
    avg_xact_count,
    avg_query_count,
    avg_recv,
    avg_sent,
    avg_xact_time,
    avg_query_time,
    avg_wait_time,
    avg_client_parse_count,
    avg_server_parse_count,
    avg_bind_count
   FROM dblink('host=127.0.0.1 port=6432 dbname=pgbouncer user=postgres'::text, 'SHOW STATS'::text) stats(database text, total_server_assignment_count bigint, total_xact_count bigint, total_query_count bigint, total_received bigint, total_sent bigint, total_xact_time bigint, total_query_time bigint, total_wait_time bigint, total_client_parse_count bigint, total_server_parse_count bigint, total_bind_count bigint, avg_server_assignment_count bigint, avg_xact_count bigint, avg_query_count bigint, avg_recv bigint, avg_sent bigint, avg_xact_time bigint, avg_query_time bigint, avg_wait_time bigint, avg_client_parse_count bigint, avg_server_parse_count bigint, avg_bind_count bigint);

-- dblink Erweiterung muss installiert sein, um diese Ansicht zu verwenden
-- ich setze voraus, dass .pgpass korrekt konfiguriert ist, damit die Verbindung zu PgBouncer funktioniert

-- Liste der Datenbanken mit Speicherverbrauch, sortiert nach Speicherverbrauchi
CREATE OR REPLACE VIEW public.db_groessen
 AS
 SELECT datname AS database_name,
    pg_size_pretty(pg_database_size(datname)) AS size_pretty,
    pg_database_size(datname) AS size_bytes
   FROM pg_database d
  WHERE datistemplate = false
  ORDER BY (pg_database_size(datname)) DESC;

-- Datenbank Statistik
CREATE OR REPLACE VIEW pgbouncer.stats
 AS
 SELECT database,
    total_server_assignment_count,
    total_xact_count,
    total_query_count,
    total_received,
    total_sent,
    total_xact_time,
    total_query_time,
    total_wait_time,
    total_client_parse_count,
    total_server_parse_count,
    total_bind_count,
    avg_server_assignment_count,
    avg_xact_count,
    avg_query_count,
    avg_recv,
    avg_sent,
    avg_xact_time,
    avg_query_time,
    avg_wait_time,
    avg_client_parse_count,
    avg_server_parse_count,
    avg_bind_count
   FROM dblink('host=127.0.0.1 port=6432 dbname=pgbouncer user=postgres'::text, 'SHOW STATS'::text) stats(database text, total_server_assignment_count bigint, total_xact_count bigint, total_query_count bigint, total_received bigint, total_sent bigint, total_xact_time bigint, total_query_time bigint, total_wait_time bigint, total_client_parse_count bigint, total_server_parse_count bigint, total_bind_count bigint, avg_server_assignment_count bigint, avg_xact_count bigint, avg_query_count bigint, avg_recv bigint, avg_sent bigint, avg_xact_time bigint, avg_query_time bigint, avg_wait_time bigint, avg_client_parse_count bigint, avg_server_parse_count bigint, avg_bind_count bigint);

-- Liste der Datenbanken, die ein wait haben, sortiert nach Anzahl der wartenden Verbindungen
CREATE OR REPLACE VIEW pgbouncer.engpaesse
 AS
 SELECT c.application_name,
    c.addr,
    p.cl_active,
    p.cl_waiting
   FROM pgbouncer.clients c
     JOIN pgbouncer.pools p ON c.database = p.database AND c."user" = p."user"
  WHERE p.cl_waiting > 0;

