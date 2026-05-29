-- Zwei Versionen der Sicht "effective_privileges": Die erste zeigt nur die effektiven Privilegien für die Benutzer selbst, während die zweite auch die geerbten Privilegien von Rollen berücksichtigt. Beide Sichten schließen Systemkataloge und Informationen über Standardprivilegien ein, um ein umfassendes Bild der Berechtigungen zu bieten.


CREATE OR REPLACE VIEW public.effective_privileges
 AS
 WITH users AS (
         SELECT pg_roles.rolname::text AS user_name
           FROM pg_roles
          WHERE pg_roles.rolcanlogin = true
        ), defacl AS (
         SELECT d.defaclrole::regrole::text AS grantor,
            n.nspname::text AS schema_name,
            d.defaclobjtype AS objtype,
            d.defaclacl AS acl
           FROM pg_default_acl d
             LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
        ), tables AS (
         SELECT c.oid,
            c.relkind,
            n.nspname::text AS schema_name,
            c.relname::text AS object_name,
            format('%I.%I'::text, n.nspname, c.relname) AS fqname
           FROM pg_class c
             JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE (n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name])) AND (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'm'::"char", 'S'::"char"]))
        ), funcs AS (
         SELECT p.oid,
            n.nspname::text AS schema_name,
            p.proname::text AS object_name,
            format('%I.%I(%s)'::text, n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)) AS fqname
           FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name])
        ), schemas AS (
         SELECT n.oid,
            n.nspname::text AS schema_name
           FROM pg_namespace n
          WHERE n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name])
        )
 SELECT u.user_name,
    'table'::text AS object_type,
    t.schema_name,
    t.object_name,
    has_table_privilege(u.user_name::name, t.fqname, 'select'::text) AS select_priv,
    has_table_privilege(u.user_name::name, t.fqname, 'insert'::text) AS insert_priv,
    has_table_privilege(u.user_name::name, t.fqname, 'update'::text) AS update_priv,
    has_table_privilege(u.user_name::name, t.fqname, 'delete'::text) AS delete_priv,
    has_table_privilege(u.user_name::name, t.fqname, 'truncate'::text) AS truncate_priv,
    has_table_privilege(u.user_name::name, t.fqname, 'references'::text) AS references_priv,
    has_table_privilege(u.user_name::name, t.fqname, 'trigger'::text) AS trigger_priv,
    false AS create_priv,
    false AS create_schema_priv,
    (EXISTS ( SELECT 1
           FROM defacl d
          WHERE d.schema_name = t.schema_name AND d.objtype = 'r'::"char" AND d.acl::text ~~ (('%'::text || u.user_name) || '%'::text))) AS default_priv
   FROM users u
     CROSS JOIN tables t
UNION ALL
 SELECT u.user_name,
    'function'::text AS object_type,
    f.schema_name,
    f.object_name,
    has_function_privilege(u.user_name::name, f.oid, 'execute'::text) AS select_priv,
    NULL::boolean AS insert_priv,
    NULL::boolean AS update_priv,
    NULL::boolean AS delete_priv,
    NULL::boolean AS truncate_priv,
    NULL::boolean AS references_priv,
    NULL::boolean AS trigger_priv,
    false AS create_priv,
    false AS create_schema_priv,
    (EXISTS ( SELECT 1
           FROM defacl d
          WHERE d.schema_name = f.schema_name AND d.objtype = 'f'::"char" AND d.acl::text ~~ (('%'::text || u.user_name) || '%'::text))) AS default_priv
   FROM users u
     CROSS JOIN funcs f
UNION ALL
 SELECT u.user_name,
    'schema'::text AS object_type,
    s.schema_name,
    s.schema_name AS object_name,
    has_schema_privilege(u.user_name::name, s.schema_name, 'usage'::text) AS select_priv,
    has_schema_privilege(u.user_name::name, s.schema_name, 'create'::text) AS insert_priv,
    NULL::boolean AS update_priv,
    NULL::boolean AS delete_priv,
    NULL::boolean AS truncate_priv,
    NULL::boolean AS references_priv,
    NULL::boolean AS trigger_priv,
    has_schema_privilege(u.user_name::name, s.schema_name, 'create'::text) AS create_priv,
    false AS create_schema_priv,
    (EXISTS ( SELECT 1
           FROM defacl d
          WHERE d.schema_name = s.schema_name AND d.objtype = 'n'::"char" AND d.acl::text ~~ (('%'::text || u.user_name) || '%'::text))) AS default_priv
   FROM users u
     CROSS JOIN schemas s
UNION ALL
 SELECT u.user_name,
    'database'::text AS object_type,
    current_database() AS schema_name,
    current_database() AS object_name,
    NULL::boolean AS select_priv,
    NULL::boolean AS insert_priv,
    NULL::boolean AS update_priv,
    NULL::boolean AS delete_priv,
    NULL::boolean AS truncate_priv,
    NULL::boolean AS references_priv,
    NULL::boolean AS trigger_priv,
    false AS create_priv,
    has_database_privilege(u.user_name::name, current_database()::text, 'create'::text) AS create_schema_priv,
    false AS default_priv
   FROM users u
  ORDER BY 1, 2, 3, 4;

CREATE OR REPLACE VIEW public.effective_privileges_all
 AS
 WITH RECURSIVE inherited_roles AS (
         SELECT r.oid AS role_oid,
            r.rolname AS role_name,
            r.oid AS root_oid,
            r.rolname AS root_name
           FROM pg_roles r
        UNION ALL
         SELECT parent.oid AS role_oid,
            parent.rolname AS role_name,
            child.root_oid,
            child.root_name
           FROM pg_auth_members m
             JOIN pg_roles parent ON m.roleid = parent.oid
             JOIN inherited_roles child ON m.member = child.role_oid
        ), users AS (
         SELECT DISTINCT inherited_roles.root_name AS user_name
           FROM inherited_roles
        ), tables AS (
         SELECT c.oid,
            c.relkind,
            n.nspname AS schema_name,
            c.relname AS object_name,
            format('%I.%I'::text, n.nspname, c.relname) AS fqname
           FROM pg_class c
             JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE (n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name])) AND (c.relkind = ANY (ARRAY['r'::"char", 'v'::"char", 'm'::"char", 'S'::"char"]))
        ), direct_table_privs AS (
         SELECT r.rolname AS role_name,
            n.nspname AS schema_name,
            c.relname AS object_name,
            a.privilege_type
           FROM pg_class c
             JOIN pg_namespace n ON n.oid = c.relnamespace
             JOIN LATERAL aclexplode(c.relacl) a(grantor, grantee, privilege_type, is_grantable) ON true
             JOIN pg_roles r ON a.grantee = r.oid
        ), funcs AS (
         SELECT p.oid,
            n.nspname AS schema_name,
            p.proname AS object_name,
            format('%I.%I(%s)'::text, n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)) AS fqname
           FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name])
        ), direct_function_privs AS (
         SELECT r.rolname AS role_name,
            n.nspname AS schema_name,
            p.proname AS object_name,
            a.privilege_type
           FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             JOIN LATERAL aclexplode(p.proacl) a(grantor, grantee, privilege_type, is_grantable) ON true
             JOIN pg_roles r ON a.grantee = r.oid
        ), schemas AS (
         SELECT n.oid,
            n.nspname AS schema_name
           FROM pg_namespace n
          WHERE n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name])
        ), direct_schema_privs AS (
         SELECT r.rolname AS role_name,
            n.nspname AS schema_name,
            a.privilege_type
           FROM pg_namespace n
             JOIN LATERAL aclexplode(n.nspacl) a(grantor, grantee, privilege_type, is_grantable) ON true
             JOIN pg_roles r ON a.grantee = r.oid
        )
 SELECT u.user_name,
    'table'::text AS object_type,
    t.schema_name,
    t.object_name,
    p.privilege,
        CASE
            WHEN p.has_priv = false THEN 'none'::text
            WHEN d.role_name = u.user_name THEN 'direct'::text
            WHEN d.role_name IS NOT NULL THEN 'inherited_from: '::text || d.role_name::text
            ELSE 'inherited_from: ownership_or_default'::text
        END AS privilege_origin
   FROM users u
     CROSS JOIN tables t
     CROSS JOIN LATERAL ( VALUES ('select'::text,has_table_privilege(u.user_name, t.fqname, 'select'::text)), ('insert'::text,has_table_privilege(u.user_name, t.fqname, 'insert'::text)), ('update'::text,has_table_privilege(u.user_name, t.fqname, 'update'::text)), ('delete'::text,has_table_privilege(u.user_name, t.fqname, 'delete'::text)), ('truncate'::text,has_table_privilege(u.user_name, t.fqname, 'truncate'::text)), ('references'::text,has_table_privilege(u.user_name, t.fqname, 'references'::text)), ('trigger'::text,has_table_privilege(u.user_name, t.fqname, 'trigger'::text))) p(privilege, has_priv)
     LEFT JOIN direct_table_privs d ON d.schema_name = t.schema_name AND d.object_name = t.object_name AND d.privilege_type = p.privilege AND (d.role_name IN ( SELECT inherited_roles.role_name
           FROM inherited_roles
          WHERE inherited_roles.root_name = u.user_name))
UNION ALL
 SELECT u.user_name,
    'function'::text AS object_type,
    f.schema_name,
    f.object_name,
    'execute'::text AS privilege,
        CASE
            WHEN has_function_privilege(u.user_name, f.oid, 'execute'::text) AND d.role_name = u.user_name THEN 'direct'::text
            WHEN has_function_privilege(u.user_name, f.oid, 'execute'::text) AND d.role_name IS NOT NULL THEN 'inherited_from: '::text || d.role_name::text
            WHEN has_function_privilege(u.user_name, f.oid, 'execute'::text) THEN 'inherited_from: ownership_or_default'::text
            ELSE 'none'::text
        END AS privilege_origin
   FROM users u
     CROSS JOIN funcs f
     LEFT JOIN direct_function_privs d ON d.schema_name = f.schema_name AND d.object_name = f.object_name AND d.privilege_type = 'EXECUTE'::text AND (d.role_name IN ( SELECT inherited_roles.role_name
           FROM inherited_roles
          WHERE inherited_roles.root_name = u.user_name))
UNION ALL
 SELECT u.user_name,
    'schema'::text AS object_type,
    s.schema_name,
    s.schema_name AS object_name,
    p.privilege,
        CASE
            WHEN p.has_priv = false THEN 'none'::text
            WHEN d.role_name = u.user_name THEN 'direct'::text
            WHEN d.role_name IS NOT NULL THEN 'inherited_from: '::text || d.role_name::text
            ELSE 'inherited_from: ownership_or_default'::text
        END AS privilege_origin
   FROM users u
     CROSS JOIN schemas s
     CROSS JOIN LATERAL ( VALUES ('usage'::text,has_schema_privilege(u.user_name, s.schema_name::text, 'usage'::text)), ('create'::text,has_schema_privilege(u.user_name, s.schema_name::text, 'create'::text))) p(privilege, has_priv)
     LEFT JOIN direct_schema_privs d ON d.schema_name = s.schema_name AND d.privilege_type = p.privilege AND (d.role_name IN ( SELECT inherited_roles.role_name
           FROM inherited_roles
          WHERE inherited_roles.root_name = u.user_name))
UNION ALL
 SELECT u.user_name,
    'database'::text AS object_type,
    current_database() AS schema_name,
    current_database() AS object_name,
    p.privilege,
        CASE
            WHEN p.has_priv THEN 'direct'::text
            ELSE 'none'::text
        END AS privilege_origin
   FROM users u
     CROSS JOIN LATERAL ( VALUES ('connect'::text,has_database_privilege(u.user_name, current_database()::text, 'connect'::text)), ('create'::text,has_database_privilege(u.user_name, current_database()::text, 'create'::text))) p(privilege, has_priv)
  ORDER BY 1, 2, 3, 4, 5;

