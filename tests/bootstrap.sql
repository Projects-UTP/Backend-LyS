-- Solo CI efímero: reproduce las referencias de Auth sin modificar el esquema de LYS.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO anon,authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon,authenticated;
-- Contrato SQL administrado de Realtime, solo para evaluar políticas/trigger en CI.
-- No simula un servidor WebSocket ni constituye prueba de entrega por red.
CREATE SCHEMA realtime;
CREATE TABLE realtime.channels(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),pattern text UNIQUE,description text,enabled boolean DEFAULT true);
CREATE TABLE realtime.messages(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),channel_id uuid REFERENCES realtime.channels(id),channel_name text,event_name text,payload jsonb,sender_type text DEFAULT 'system');
CREATE FUNCTION realtime.channel_name() RETURNS text LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('realtime.channel_name',true),'') $$;
CREATE FUNCTION realtime.publish(p_channel_name text,p_event_name text,p_payload jsonb) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE canal uuid;mensaje uuid; BEGIN
 SELECT id INTO canal FROM realtime.channels WHERE enabled AND(p_channel_name=pattern OR p_channel_name LIKE pattern) LIMIT 1;
 INSERT INTO realtime.messages(channel_id,channel_name,event_name,payload) VALUES(canal,p_channel_name,p_event_name,p_payload) RETURNING id INTO mensaje;RETURN mensaje;
END $$;
