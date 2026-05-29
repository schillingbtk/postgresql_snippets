# Verbindungen

Dieses Verzeichnis beschreibt SQL-Statements zur Überwachung, Berechtigungsanalyse und Auditierung von PostgreSQL-Verbindungen und DDL-Operationen.

## Dateien in `Verbindungen/`

- `audit.sql`
  - Erstellt die Audit-Tabelle `public.ddl_audit_log` für DDL-Ereignisse.
  - Definiert die Funktionen `public.log_ddl_command()` und `public.log_ddl_drop()` als `event_trigger`-Handler.
  - Legt zwei Event-Trigger an: `ddl_audit_trigger` für `DDL_COMMAND_END` und `ddl_drop_audit_trigger` für `SQL_DROP`.
  - Enthält Beispielbefehle zum Deaktivieren und Aktivieren der Audit-Trigger.

- `privilegien.sql`
  - Definiert `public.effective_privileges` als sichtbare, direkte Privilegien für alle Login-Rollen über Tabellen, Funktionen, Schemas und die Datenbank.
  - Definiert `public.effective_privileges_all` als erweiterte Ansicht mit rollenbasierter Vererbung und Herkunft der Berechtigungen.
  - Nutzt PostgreSQL-Systemkataloge (`pg_roles`, `pg_class`, `pg_proc`, `pg_namespace`) sowie Funktionen wie `has_table_privilege()`, `has_function_privilege()`, `has_schema_privilege()` und `has_database_privilege()`.
  - Berücksichtigt Default-ACLs aus `pg_default_acl` und unterscheidet direkte vs. geerbte Privilegien.

## Dateien in `Verbindungen/Views/`

- `listen.sql`
  - Definiert `pgbouncer.stats` als `VIEW`, die per `dblink` auf `SHOW STATS` von PgBouncer zugreift.
  - Enthält einen Kommentar zur erforderlichen `dblink`-Erweiterung und `.pgpass`-Konfiguration.
  - Definiert `public.db_groessen` als Ansicht über `pg_database_size()` zur Anzeige der Datenbankgrößen.
  - Definiert `pgbouncer.engpaesse`, um wartende PgBouncer-Verbindungen (`cl_waiting > 0`) aus `pgbouncer.clients` und `pgbouncer.pools` zu melden.
  - Hinweis: Die Definition von `pgbouncer.stats` ist im File zweimal vorhanden.

- `lokal.sql`
  - Definiert `public.verbindungen` als Ansicht über `pg_stat_activity`.
  - Gruppiert nach Datenbank, Benutzer, Applikation und Verbindungsstatus.
  - Zählt offene Client-Server-Verbindungen und zeigt die älteste Verbindung je Gruppe.
  - Sortiert die Ergebnisse nach der Anzahl offener Verbindungen.
