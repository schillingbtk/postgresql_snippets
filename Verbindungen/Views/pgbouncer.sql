-- Liste der Clients, die mit PgBouncer verbunden sind

CREATE OR REPLACE VIEW pgbouncer.clients
 AS
 SELECT type,
    "user",
    database,
    replication,
    state,
    addr,
    port,
    local_addr,
    local_port,
    connect_time,
    request_time,
    wait,
    wait_us,
    close_needed,
    ptr,
    link,
    remote_pid,
    tls,
    application_name,
    prepared_statements,
    id
   FROM dblink('host=127.0.0.1 port=6432 dbname=pgbouncer user=postgres'::text, 'SHOW CLIENTS'::text) clients(type text, "user" text, database text, replication text, state text, addr text, port integer, local_addr text, local_port integer, connect_time timestamp with time zone, request_time timestamp with time zone, wait integer, wait_us integer, close_needed integer, ptr text, link text, remote_pid integer, tls text, application_name text, prepared_statements integer, id bigint);

-- dblink Erweiterung muss installiert sein, um diese Ansicht zu verwenden
-- ich setze voraus, dass .pgpass korrekt konfiguriert ist, damit die Verbindung zu PgBouncer funktioniert

-- Lister der Pools, die von PgBouncer verwaltet werden

CREATE OR REPLACE VIEW pgbouncer.pools
 AS
 SELECT database,
    "user",
    cl_active,
    cl_waiting,
    cl_active_cancel_req,
    cl_waiting_cancel_req,
    sv_active,
    sv_active_cancel,
    sv_being_canceled,
    sv_idle,
    sv_used,
    sv_tested,
    sv_login,
    maxwait,
    maxwait_us,
    pool_mode,
    load_balance_hosts
   FROM dblink('host=127.0.0.1 port=6432 dbname=pgbouncer user=postgres'::text, 'SHOW POOLS'::text) pools(database text, "user" text, cl_active integer, cl_waiting integer, cl_active_cancel_req integer, cl_waiting_cancel_req integer, sv_active integer, sv_active_cancel integer, sv_being_canceled integer, sv_idle integer, sv_used integer, sv_tested integer, sv_login integer, maxwait integer, maxwait_us integer, pool_mode text, load_balance_hosts integer);

