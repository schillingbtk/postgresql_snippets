-- PROCEDURE: public.import_remote_database_safe(text, integer, text, text, text, text)

-- DROP PROCEDURE IF EXISTS public.import_remote_database_safe(text, integer, text, text, text, text);

CREATE OR REPLACE PROCEDURE public.import_remote_database_safe(
	IN remote_host text,
	IN remote_port integer,
	IN remote_dbname text,
	IN remote_user text,
	IN remote_password text,
	IN local_prefix text DEFAULT 'fdw'::text)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
    dyn_server   text := 'fdw_' || replace(remote_dbname, '-', '_');
    schemata_ft  text := 'remote_schemata_' || replace(remote_dbname, '-', '_');
    tables_ft    text := 'remote_tables_'   || replace(remote_dbname, '-', '_');
    r_schema     text;
    r_table      text;
BEGIN
    --------------------------------------------------------------------
    -- 0. Schema fdw_sys anlegen (falls nicht vorhanden)
    --------------------------------------------------------------------
    EXECUTE 'CREATE SCHEMA IF NOT EXISTS fdw_sys';

    --------------------------------------------------------------------
    -- 1. Log-Tabelle anlegen
    --------------------------------------------------------------------
    EXECUTE '
        CREATE TABLE IF NOT EXISTS fdw_sys.import_log (
            id              bigserial PRIMARY KEY,
            remote_db       text NOT NULL,
            remote_schema   text NOT NULL,
            remote_table    text NOT NULL,
            error_message   text NOT NULL,
            logged_at       timestamptz NOT NULL DEFAULT now()
        )';

    --------------------------------------------------------------------
    -- 2. FDW-Server anlegen (falls noch nicht vorhanden)
    --------------------------------------------------------------------
    BEGIN
        EXECUTE format(
            'CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw
             OPTIONS (host %L, dbname %L, port %L)',
            dyn_server, remote_host, remote_dbname, remote_port
        );
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE 'Server % bereits vorhanden, wird wiederverwendet.', dyn_server;
    END;

    --------------------------------------------------------------------
    -- 3. User Mapping anlegen (falls noch nicht vorhanden)
    --------------------------------------------------------------------
    BEGIN
        EXECUTE format(
            'CREATE USER MAPPING FOR CURRENT_USER
             SERVER %I
             OPTIONS (user %L, password %L)',
            dyn_server, remote_user, remote_password
        );
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE 'User Mapping für % bereits vorhanden, wird wiederverwendet.', dyn_server;
    END;

    --------------------------------------------------------------------
    -- 4. Foreign Table auf information_schema.schemata (remote)
    --------------------------------------------------------------------
    BEGIN
        EXECUTE format(
            'CREATE FOREIGN TABLE fdw_sys.%I (
                catalog_name                  text,
                schema_name                   text,
                schema_owner                  text,
                default_character_set_catalog text,
                default_character_set_schema  text,
                default_character_set_name    text,
                sql_path                      text
            )
            SERVER %I
            OPTIONS (schema_name ''information_schema'', table_name ''schemata'')',
            schemata_ft, dyn_server
        );
    EXCEPTION WHEN duplicate_table THEN
        RAISE NOTICE 'Metatabelle fdw_sys.% bereits vorhanden, wird wiederverwendet.', schemata_ft;
    END;

    --------------------------------------------------------------------
    -- 5. Foreign Table auf information_schema.tables (remote)
    --------------------------------------------------------------------
    BEGIN
        EXECUTE format(
            'CREATE FOREIGN TABLE fdw_sys.%I (
                table_catalog text,
                table_schema  text,
                table_name    text,
                table_type    text
            )
            SERVER %I
            OPTIONS (schema_name ''information_schema'', table_name ''tables'')',
            tables_ft, dyn_server
        );
    EXCEPTION WHEN duplicate_table THEN
        RAISE NOTICE 'Metatabelle fdw_sys.% bereits vorhanden, wird wiederverwendet.', tables_ft;
    END;

    --------------------------------------------------------------------
    -- 6. Alle entfernten Schemas durchlaufen
    --------------------------------------------------------------------
    FOR r_schema IN
        EXECUTE format(
            'SELECT schema_name
             FROM fdw_sys.%I
             WHERE schema_name NOT LIKE ''pg_%%''
               AND schema_name <> ''information_schema''
             ORDER BY schema_name',
            schemata_ft
        )
    LOOP
        -- lokales Schema anlegen
        EXECUTE format(
            'CREATE SCHEMA IF NOT EXISTS %I_%I',
            local_prefix, r_schema
        );

        ----------------------------------------------------------------
        -- 7. Alle Tabellen dieses Schemas (remote) durchlaufen
        ----------------------------------------------------------------
        FOR r_table IN
            EXECUTE format(
                'SELECT table_name
                 FROM fdw_sys.%I
                 WHERE table_schema = %L
                 ORDER BY table_name',
                tables_ft, r_schema
            )
        LOOP
            BEGIN
                -- Versuch: nur diese eine Tabelle importieren
                EXECUTE format(
                    'IMPORT FOREIGN SCHEMA %I
                     LIMIT TO (%I)
                     FROM SERVER %I
                     INTO %I_%I',
                    r_schema, r_table, dyn_server, local_prefix, r_schema
                );
            EXCEPTION WHEN OTHERS THEN
                -- Fehler in Log-Tabelle schreiben
                INSERT INTO fdw_sys.import_log (remote_db, remote_schema, remote_table, error_message)
                VALUES (remote_dbname, r_schema, r_table, SQLERRM);

                RAISE NOTICE 'Tabelle %.% wird übersprungen (siehe fdw_sys.import_log): %',
                    r_schema, r_table, SQLERRM;
            END;
        END LOOP;
    END LOOP;
END;
$BODY$;
