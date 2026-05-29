-- FUNCTION: pgbouncer.get_auth(text)

-- DROP FUNCTION IF EXISTS pgbouncer.get_auth(text);

CREATE OR REPLACE FUNCTION pgbouncer.get_auth(
	p_usename text)
    RETURNS TABLE(usename name, passwd text) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE SECURITY DEFINER PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
 BEGIN
  RETURN QUERY
  SELECT u.usename, u.passwd FROM pg_catalog.pg_shadow u
  WHERE u.usename = p_usename;
END; 
$BODY$;
