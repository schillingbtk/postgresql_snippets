# PostgreSQL Listener Service (`db_listener`)

## Zweck

Der Dienst ist ein dauerhaft laufender Python-Prozess, der über PostgreSQL **LISTEN/NOTIFY** auf dem Kanal `create_database` lauscht. Sobald ein Client **`NOTIFY create_database, '<dbname>'`** auslöst, wird die angegebene Datenbank automatisch angelegt und mit Schema-, Rollen- und Rechte-Setup initialisiert.

## Komponenten

| Teil | Pfad / Rolle |
|------|----------------|
| Skript | `/usr/local/bin/db_listener.py` |
| systemd-Unit | `/etc/systemd/system/db_listener.service` |
| SQL beim Provisioning | `/opt/db/init_managed_database.sql`, `/opt/db/create_managed_schema.sql` |

## Technik

- **Laufzeit:** Python 3, Bibliothek **psycopg2**.
- **Steuerverbindung:** Verbindung zur Datenbank `postgres` (DSN im Skript: Host, Port 6432 — typisch Connection-Pooler/PgBouncer, Benutzer `creator`). Zugangsdaten können z. B. über Umgebung oder `.pgpass` ergänzt werden.
- **Ereignisschleife:** `LISTEN create_database;`, dann Warten mit `select()` (Timeout 60 s) und `conn.poll()` zum Auslesen von `NOTIFY`-Nachrichten. Die **Payload** ist der **Datenbankname** (ohne Leerzeichen am Rand).
- **Fehler:** Verbindungsfehler → Log, 5 s Pause, erneuter Verbindungsaufbau. Fehler bei der Provisionierung einer einzelnen DB → Log, Listener bleibt aktiv.

## Benutzer `creator`

- Der Datenbankbenutzer **`creator`** ist **ausschließlich** für diesen Listener und die automatische Datenbank-Provisionierung vorgesehen — nicht für allgemeinen Anwendungs- oder Ad-hoc-Zugriff.
- **`ALTER DEFAULT PRIVILEGES`** in PostgreSQL gilt jeweils für Objekte, die eine bestimmte Rolle anlegt. Die Provisioning-SQL wird mit **`creator`** ausgeführt; damit werden die **Default Privileges** nur in diesem Kontext gesetzt. Andere Rollen sollten beim Anlegen von Objekten in verwalteten Datenbanken nicht genutzt werden, sonst entfallen die vorgesehenen Standardrechte.

## Ablauf nach NOTIFY

1. `CREATE DATABASE "<dbname>" OWNER creator` (über Steuerverbindung, Autocommit).
2. Ausführung von `init_managed_database.sql` in der neuen DB (Rollen, Rechte, Prozedur `init_managed_database()` u. a.).
3. Ausführung von `create_managed_schema.sql` (u. a. Prozedur `create_managed_schema`).
4. `CALL create_managed_schema('public');`
5. `CALL init_managed_database();`

## systemd

- Service-Typ: `simple`, Benutzer/Gruppe: `sqladmin`.
- `Restart=always`, `RestartSec=3`.
- Standardausgabe und Fehlerausgabe ins Journal (`journalctl -u db_listener.service`).

## Aktivierung (Beispiel)

```bash
sudo systemctl daemon-reload
sudo systemctl enable db_listener.service
sudo systemctl start db_listener.service
sudo systemctl status db_listener.service
```

## Hinweis

Es handelt sich **nicht** um Replikation oder den nativen Postgres-Protokoll-Listener, sondern um einen **Anwendungs-Daemon**, der PostgreSQL-**Benachrichtigungen** nutzt, um Datenbank-Erstellung asynchron anzustoßen.
