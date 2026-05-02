-- #############################################################
-- init_managed_database.sql
-- Wird vom Python-Provisioning-Script in der neuen DB ausgeführt
-- #############################################################

-- 1. Rollen anlegen (idempotent)
DO $$
DECLARE
    dbname text := current_database();
    admin_role text := current_database() || '_admin';
    user_role  text := current_database() || '_user';
BEGIN
    -- Admin-Rolle
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = admin_role) THEN
        EXECUTE format('CREATE ROLE %I NOLOGIN;', admin_role);
    END IF;

    -- User-Rolle
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = user_role) THEN
        EXECUTE format('CREATE ROLE %I NOLOGIN;', user_role);
    END IF;
END$$;


-- 2. CONNECT-Rechte setzen
DO $$
DECLARE
    dbname text := current_database();
BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC;', dbname);
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO PUBLIC;', dbname);
END$$;


-- 3. Standardrechte für neue Schemas
DO $$
DECLARE
    admin_role text := current_database() || '_admin';
BEGIN
    EXECUTE format('ALTER DEFAULT PRIVILEGES GRANT USAGE, CREATE ON SCHEMAS TO %I;', admin_role);
END$$;


-- 4. Standardrechte für neue Tabellen
DO $$
DECLARE
    user_role text := current_database() || '_user';
BEGIN
    EXECUTE format('ALTER DEFAULT PRIVILEGES GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I;', user_role);
END$$;


-- 5. creator in Admin-Rolle aufnehmen
DO $$
DECLARE
    admin_role text := current_database() || '_admin';
BEGIN
    EXECUTE format('GRANT %I TO creator;', admin_role);
END$$;


-- 6. admin in Admin-Rolle aufnehmen (falls vorhanden)
DO $$
DECLARE
    admin_role text := current_database() || '_admin';
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin') THEN
        EXECUTE format('GRANT %I TO admin;', admin_role);
    END IF;
END$$;


-- 7. noadmin in User-Rolle aufnehmen (falls vorhanden)
DO $$
DECLARE
    user_role text := current_database() || '_user';
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'noadmin') THEN
        EXECUTE format('GRANT %I TO noadmin;', user_role);
    END IF;
END$$;


-- 8. Prozedur init_managed_database() definieren
--    (wird vom Python-Script nach Import aufgerufen)
CREATE OR REPLACE PROCEDURE init_managed_database()
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE NOTICE 'Managed Database initialisiert: %', current_database();
END;
$$;

-- 9. mein persoenliches View fuer alle Rechte aller User
CREATE OR REPLACE VIEW effective_privileges_all AS
WITH
-- Alle Login-User
users AS (
    SELECT rolname::text AS user_name
    FROM pg_roles
    WHERE rolcanlogin = true
),
 
-- Default Privileges
defacl AS (
    SELECT
        d.defaclrole::regrole::text AS grantor,
        n.nspname::text AS schema_name,
        d.defaclobjtype AS objtype,
        d.defaclacl AS acl
    FROM pg_default_acl d
    LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
),
 
-- Tabellen, Views, MatViews, Sequenzen
tables AS (
    SELECT
        c.oid,
        c.relkind,
        n.nspname::text AS schema_name,
        c.relname::text AS object_name,
        format('%I.%I', n.nspname, c.relname) AS fqname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND c.relkind IN ('r','v','m','S')
),
 
-- Funktionen & Prozeduren
funcs AS (
    SELECT
        p.oid,
        n.nspname::text AS schema_name,
        p.proname::text AS object_name,
        format('%I.%I(%s)', n.nspname, p.proname,
            pg_get_function_identity_arguments(p.oid)) AS fqname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
),
 
-- Schemas
schemas AS (
    SELECT
        n.oid,
        n.nspname::text AS schema_name
    FROM pg_namespace n
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
)
 
-- 1) Tabellenrechte
SELECT
    u.user_name,
    'table' AS object_type,
    t.schema_name,
    t.object_name,
    has_table_privilege(u.user_name, t.fqname, 'select')     AS select_priv,
    has_table_privilege(u.user_name, t.fqname, 'insert')     AS insert_priv,
    has_table_privilege(u.user_name, t.fqname, 'update')     AS update_priv,
    has_table_privilege(u.user_name, t.fqname, 'delete')     AS delete_priv,
    has_table_privilege(u.user_name, t.fqname, 'truncate')   AS truncate_priv,
    has_table_privilege(u.user_name, t.fqname, 'references') AS references_priv,
    has_table_privilege(u.user_name, t.fqname, 'trigger')    AS trigger_priv,
    false AS create_priv,
    false AS create_schema_priv,
    EXISTS (
        SELECT 1
        FROM defacl d
        WHERE d.schema_name = t.schema_name
          AND d.objtype = 'r'
          AND d.acl::text LIKE '%' || u.user_name || '%'
    ) AS default_priv
FROM users u CROSS JOIN tables t
 
UNION ALL
 
-- 2) Funktionsrechte
SELECT
    u.user_name,
    'function' AS object_type,
    f.schema_name,
    f.object_name,
    has_function_privilege(u.user_name, f.oid, 'execute') AS select_priv,
    null AS insert_priv,
    null AS update_priv,
    null AS delete_priv,
    null AS truncate_priv,
    null AS references_priv,
    null AS trigger_priv,
    false AS create_priv,
    false AS create_schema_priv,
    EXISTS (
        SELECT 1
        FROM defacl d
        WHERE d.schema_name = f.schema_name
          AND d.objtype = 'f'
          AND d.acl::text LIKE '%' || u.user_name || '%'
    ) AS default_priv
FROM users u CROSS JOIN funcs f
 
UNION ALL
 
-- 3) Schemas (USAGE + CREATE)
SELECT
    u.user_name,
    'schema' AS object_type,
    s.schema_name,
    s.schema_name AS object_name,
    has_schema_privilege(u.user_name, s.schema_name, 'usage')  AS select_priv,
    has_schema_privilege(u.user_name, s.schema_name, 'create') AS insert_priv,
    null AS update_priv,
    null AS delete_priv,
    null AS truncate_priv,
    null AS references_priv,
    null AS trigger_priv,
    has_schema_privilege(u.user_name, s.schema_name, 'create') AS create_priv,
    false AS create_schema_priv,
    EXISTS (
        SELECT 1
        FROM defacl d
        WHERE d.schema_name = s.schema_name
          AND d.objtype = 'n'
          AND d.acl::text LIKE '%' || u.user_name || '%'
    ) AS default_priv
FROM users u CROSS JOIN schemas s
 
UNION ALL
 
-- 4) Database CREATE (CREATE SCHEMA)
SELECT
    u.user_name,
    'database' AS object_type,
    current_database() AS schema_name,
    current_database() AS object_name,
    null AS select_priv,
    null AS insert_priv,
    null AS update_priv,
    null AS delete_priv,
    null AS truncate_priv,
    null AS references_priv,
    null AS trigger_priv,
    false AS create_priv,
    has_database_privilege(u.user_name, current_database(), 'create') AS create_schema_priv,
    false AS default_priv
FROM users u
 
ORDER BY user_name, object_type, schema_name, object_name;

