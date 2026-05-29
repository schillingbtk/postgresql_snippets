-- FUNCTION: public.get_user_privileges(text)

-- DROP FUNCTION IF EXISTS public.get_user_privileges(text);

CREATE OR REPLACE FUNCTION public.get_user_privileges(
	username text)
    RETURNS TABLE(section text, info text) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
    -- Rollenmitgliedschaften
    RETURN QUERY
    WITH RECURSIVE member_of AS (
        SELECT oid, rolname
        FROM pg_roles
        WHERE rolname = username
 
        UNION
 
        SELECT m.roleid, r.rolname
        FROM pg_auth_members m
        JOIN pg_roles r ON r.oid = m.roleid
        JOIN member_of mo ON mo.oid = m.member
    )
    SELECT
        'ROLE MEMBERSHIP'::text AS section,
        rolname::text AS info
    FROM member_of;
 
    -- Schema-Rechte
    RETURN QUERY
    WITH RECURSIVE member_of AS (
        SELECT oid, rolname
        FROM pg_roles
        WHERE rolname = username
 
        UNION
 
        SELECT m.roleid, r.rolname
        FROM pg_auth_members m
        JOIN pg_roles r ON r.oid = m.roleid
        JOIN member_of mo ON mo.oid = m.member
    )
    SELECT
        'SCHEMA PRIVILEGE'::text,
        (n.nspname || ' → ' || p.privilege_type || ' (via ' || r.rolname || ')')::text
    FROM pg_namespace n
    CROSS JOIN LATERAL aclexplode(n.nspacl) AS p
    JOIN pg_roles r ON r.oid = p.grantee
    WHERE r.rolname IN (SELECT rolname FROM member_of);
 
    -- Tabellen-Rechte
    RETURN QUERY
    WITH RECURSIVE member_of AS (
        SELECT oid, rolname
        FROM pg_roles
        WHERE rolname = username
 
        UNION
 
        SELECT m.roleid, r.rolname
        FROM pg_auth_members m
        JOIN pg_roles r ON r.oid = m.roleid
        JOIN member_of mo ON mo.oid = m.member
    )
    SELECT
        'TABLE PRIVILEGE'::text,
        (n.nspname || '.' || c.relname || ' → ' || p.privilege_type || ' (via ' || r.rolname || ')')::text
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    CROSS JOIN LATERAL aclexplode(c.relacl) AS p
    JOIN pg_roles r ON r.oid = p.grantee
    WHERE c.relkind = 'r'
      AND r.rolname IN (SELECT rolname FROM member_of);
 
END;
$BODY$;
