# Migration: foreign_import

Diese Datei beschreibt die Prozedur `public.import_remote_database_safe` aus `foreign_import.sql`.

## Zweck

Die Prozedur automatisiert den Import von entfernten Tabellen über `postgres_fdw` in lokale Schemas. Sie legt dazu eine FDW-Serververbindung, das passende User Mapping und Metatabellen für `information_schema.schemata` und `information_schema.tables` an.

## Technische Beschreibung

`public.import_remote_database_safe(remote_host, remote_port, remote_dbname, remote_user, remote_password, local_prefix)` führt folgende Schritte aus:

1. Erstellt das Schema `fdw_sys`, falls es noch nicht existiert.
2. Legt die Log-Tabelle `fdw_sys.import_log` an, um Importfehler pro Remote-Schema/Table zu protokollieren.
3. Erstellt einen FDW-Server `fdw_<remote_dbname>` mit Wrapper `postgres_fdw`.
4. Erstellt ein `USER MAPPING` für den aktuellen Benutzer mit den angegebenen Remote-Zugangsdaten.
5. Erzeugt zwei Foreign Tables in `fdw_sys`:
   - `remote_schemata_<remote_dbname>` für `information_schema.schemata`
   - `remote_tables_<remote_dbname>` für `information_schema.tables`
6. Iteriert über alle entfernten Schemas, die nicht mit `pg_` beginnen und nicht `information_schema` sind.
7. Für jedes entfernte Schema wird ein lokales Schema mit dem Namen `<local_prefix>_<remote_schema>` angelegt.
8. Für jede Tabelle im entfernten Schema wird ein gezielter `IMPORT FOREIGN SCHEMA ... LIMIT TO (...)`-Befehl ausgeführt.
9. Bei Importfehlern wird der Fehler in `fdw_sys.import_log` geschrieben und die Tabelle übersprungen.

## Besonderheiten

- Doppelte Objekte werden mit `EXCEPTION WHEN duplicate_object` bzw. `EXCEPTION WHEN duplicate_table` abgefangen, damit wiederholte Aufrufe der Prozedur keine Fehler wegen bereits existierender Objekte erzeugen.
- Fehler beim Import einzelner Tabellen werden gefangen, geloggt und führen nicht zum Abbruch der gesamten Prozedur.
- Lokale Schemas verwenden den angegebenen `local_prefix`, so dass mehrere Remote-Datenbanken parallel importiert werden können.

## Voraussetzungen

- Erweiterung `postgres_fdw` muss installiert und aktiviert sein.
- Der aktuelle Benutzer muss `CREATE SERVER`, `CREATE USER MAPPING` und `IMPORT FOREIGN SCHEMA` ausführen dürfen.
- Remote-Zugangsdaten müssen korrekt sein, da die Verbindung beim Erstellen des User Mappings geprüft wird.

## Beispiel

```sql
CALL public.import_remote_database_safe(
    'remote.host.example',
    5432,
    'remote_db',
    'remote_user',
    'remote_password',
    'fdw'
);
```

Dies erzeugt lokale Schemas wie `fdw_public`, `fdw_sales` usw. für die entfernten Schemas der Ziel-Datenbank.
