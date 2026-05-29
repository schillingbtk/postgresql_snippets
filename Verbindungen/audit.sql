-- Logging DDL Ereignisse

CREATE TABLE IF NOT EXISTS public.ddl_audit_log (
  id serial NOT NULL,
  command_tag text,
  object_type text,
  schema_name text,
  object_name text,
  executed_by text DEFAULT CURRENT_USER,
  executed_at TIMESTAMP WITH TIME zone DEFAULT CURRENT_TIMESTAMP,
  strg text,
  CONSTRAINT ddl_audit_log_pkey PRIMARY KEY (id)
);

CREATE OR REPLACE FUNCTION public.log_ddl_command()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
DECLARE
  ddl_record RECORD;
BEGIN
  FOR ddl_record IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    INSERT INTO public.ddl_audit_log (
      command_tag,
      object_type,
      schema_name,
      object_name,
      executed_by,
      strg
    )
    VALUES (
      ddl_record.command_tag,
      ddl_record.object_type,
      split_part(ddl_record.object_identity, '.', 1),
      split_part(ddl_record.object_identity, '.', 2),
      CURRENT_USER,
      current_query()
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.log_ddl_drop()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
DECLARE
  obj RECORD;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    INSERT INTO public.ddl_audit_log (
      command_tag,
      object_type,
      schema_name,
      object_name,
      executed_by
    )
    VALUES (
      'DROP',
      obj.object_type,
      split_part(obj.object_identity, '.', 1),
      split_part(obj.object_identity, '.', 2),
      CURRENT_USER
    );
  END LOOP;
END;
$$;


CREATE EVENT TRIGGER ddl_audit_trigger ON DDL_COMMAND_END
  EXECUTE PROCEDURE public.log_ddl_command();
 
CREATE EVENT TRIGGER ddl_drop_audit_trigger ON SQL_DROP
  EXECUTE PROCEDURE public.log_ddl_drop();

-- beide Audit-Trigger abschalten (z. B. Massenmigration, Wartung)
ALTER EVENT TRIGGER ddl_audit_trigger DISABLE;
ALTER EVENT TRIGGER ddl_drop_audit_trigger DISABLE;
 
-- nur einen Abschnitt abschalten (CREATE/ALTER oder DROP)
ALTER EVENT TRIGGER ddl_audit_trigger DISABLE;
-- oder nur DROP-Protokollierung:
ALTER EVENT TRIGGER ddl_drop_audit_trigger DISABLE;
 
-- wieder einschalten (Standardzustand)
ALTER EVENT TRIGGER ddl_audit_trigger ENABLE;
ALTER EVENT TRIGGER ddl_drop_audit_trigger ENABLE;
