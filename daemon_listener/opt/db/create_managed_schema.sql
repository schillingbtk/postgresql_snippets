CREATE OR REPLACE PROCEDURE create_managed_schema(schema_name text)
LANGUAGE plpgsql
AS $$
DECLARE
    admin_role text := current_database() || '_admin';
    user_role  text := current_database() || '_user';
BEGIN
    IF schema_name <> 'public' THEN
        RAISE EXCEPTION 'Nur das Schema "public" ist erlaubt. Übergeben: %', schema_name;
    END IF;

    -- Owner setzen
    EXECUTE 'ALTER SCHEMA public OWNER TO creator;';

    -- Schema-Rechte
    EXECUTE 'REVOKE ALL ON SCHEMA public FROM PUBLIC;';
    EXECUTE format('GRANT ALL ON SCHEMA public TO %I;', admin_role);
    EXECUTE format('GRANT USAGE ON SCHEMA public TO %I;', user_role);

    -- Default Privileges für Tabellen
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I;',
        user_role
    );
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO %I;',
        admin_role
    );

    -- Default Privileges für Sequenzen
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %I;',
        user_role
    );
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO %I;',
        admin_role
    );

    RAISE NOTICE 'Schema public initialisiert.';
END;
$$;

