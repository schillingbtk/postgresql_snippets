-- Lokale Verbindungen pro Datenbank, User, Applikation und Verbindungsstatus

CREATE OR REPLACE VIEW public.verbindungen
 AS
 SELECT datname AS datenbank,
    usename AS "user",
    application_name,
    count(*) AS offene_server_conns,
    state,
    min(backend_start) AS aelteste_verbindung
   FROM pg_stat_activity
  WHERE backend_type = 'client backend'::text
  GROUP BY datname, usename, application_name, state
  ORDER BY (count(*)) DESC;