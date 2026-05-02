#!/usr/bin/env python3
import os
import sys
import time
import select
import psycopg2
import psycopg2.extensions

# Basis-DSN für die Steuerverbindung (postgres-DB)
DSN_CONTROL = "host=10.100.21.169 port=6432 dbname=postgres user=creator"

# Pfade zu deinen SQL-Dateien in der Zieldatenbank
INIT_DB_SQL = "/opt/db/init_managed_database.sql"
INIT_SCHEMA_SQL = "/opt/db/create_managed_schema.sql"

LOGTAG = "db-listener"


def log(msg):
    sys.stdout.write(f"{LOGTAG}: {msg}\n")
    sys.stdout.flush()


def create_database(dbname: str):
    log(f"Erzeuge Datenbank: {dbname}")
    conn = psycopg2.connect(DSN_CONTROL)
    conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
    try:
        cur = conn.cursor()
        cur.execute(f'CREATE DATABASE "{dbname}" OWNER creator;')
        cur.close()
    finally:
        conn.close()
    log(f"Datenbank {dbname} erstellt")


def run_sql_file(dbname: str, path: str):
    log(f"Importiere SQL-Datei in {dbname}: {path}")
    if not os.path.isfile(path):
        raise RuntimeError(f"SQL-Datei nicht gefunden: {path}")

    dsn_db = DSN_CONTROL.replace("dbname=postgres", f'dbname={dbname}')
    conn = psycopg2.connect(dsn_db)
    conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
    try:
        cur = conn.cursor()
        with open(path, "r", encoding="utf-8") as f:
            sql = f.read()
        cur.execute(sql)
        cur.close()
    finally:
        conn.close()
    log(f"SQL-Datei importiert: {path}")


def init_database(dbname: str):
    log(f"Führe init_managed_database() in {dbname} aus")
    dsn_db = DSN_CONTROL.replace("dbname=postgres", f'dbname={dbname}')
    conn = psycopg2.connect(dsn_db)
    conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
    try:
        cur = conn.cursor()
        cur.execute("CALL init_managed_database();")
        cur.close()
    finally:
        conn.close()
    log(f"Initialisierung von {dbname} abgeschlossen")


def init_public_schema(dbname: str):
    log(f"Initialisiere Schema public in {dbname}")
    dsn_db = DSN_CONTROL.replace("dbname=postgres", f'dbname={dbname}')
    conn = psycopg2.connect(dsn_db)
    conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
    try:
        cur = conn.cursor()
        cur.execute("CALL create_managed_schema('public');")
        cur.close()
    finally:
        conn.close()
    log(f"Schema public initialisiert")


def provision_database(dbname: str):
    create_database(dbname)
    run_sql_file(dbname, INIT_DB_SQL)
    run_sql_file(dbname, INIT_SCHEMA_SQL)
    init_public_schema(dbname)
    init_database(dbname)


def listen_loop():
    while True:
        try:
            log("Verbinde zu PostgreSQL (Steuerverbindung)…")
            conn = psycopg2.connect(DSN_CONTROL)
            conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)

            cur = conn.cursor()
            cur.execute("LISTEN create_database;")
            log("Listener aktiv – warte auf NOTIFY create_database")

            while True:
                if select.select([conn], [], [], 60) == ([], [], []):
                    continue

                conn.poll()

                while conn.notifies:
                    notify = conn.notifies.pop(0)
                    payload = notify.payload.strip()
                    if not payload:
                        continue

                    dbname = payload
                    log(f"NOTIFY empfangen, Payload: {dbname}")

                    try:
                        provision_database(dbname)
                    except Exception as e:
                        log(f"Fehler bei Provisionierung von {dbname}: {e}")

        except Exception as e:
            log(f"Verbindungsfehler: {e}")
            log("Neuer Verbindungsversuch in 5 Sekunden…")
            time.sleep(5)


if __name__ == "__main__":
    listen_loop()

