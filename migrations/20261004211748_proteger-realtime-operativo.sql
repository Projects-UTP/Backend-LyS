-- Canales privados por local y rol. Solo el servidor publica eventos operativos.
INSERT INTO realtime.channels(pattern,description,enabled) VALUES('lys-operativo:%','Operación privada por local y rol',true)
ON CONFLICT(pattern) DO UPDATE SET description=EXCLUDED.description,enabled=true;
CREATE FUNCTION public.permiso_canal_operativo(p_canal text) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE partes text[]; BEGIN
 partes:=string_to_array(p_canal,':');
 IF cardinality(partes) IS DISTINCT FROM 3 OR partes[1]<>'lys-operativo' OR partes[2] !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' OR partes[3] NOT IN ('MOZO','CAJA','COCINA','ADMINISTRADOR') THEN RETURN false; END IF;
 RETURN public.permiso_local(partes[2]::uuid,ARRAY[partes[3]]);
END $$;
REVOKE ALL ON FUNCTION public.permiso_canal_operativo(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.permiso_canal_operativo(text) TO anon,authenticated;
ALTER TABLE realtime.channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA realtime TO anon,authenticated;
GRANT SELECT ON realtime.channels TO anon,authenticated;
GRANT SELECT ON realtime.messages TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON realtime.channels,realtime.messages FROM anon,authenticated;
-- publish es SECURITY DEFINER administrada: no se expone a clientes que podrían falsificar eventos.
REVOKE EXECUTE ON FUNCTION realtime.publish(text,text,jsonb) FROM PUBLIC,anon,authenticated;
CREATE POLICY lys_canal_lectura ON realtime.channels FOR SELECT TO authenticated USING(pattern='lys-operativo:%' AND public.permiso_canal_operativo(realtime.channel_name()));
CREATE POLICY lys_canal_limite ON realtime.channels AS RESTRICTIVE FOR SELECT TO PUBLIC USING(
 CASE WHEN realtime.channel_name() LIKE 'lys-operativo:%' THEN pattern='lys-operativo:%' AND public.permiso_canal_operativo(realtime.channel_name()) ELSE pattern<>'lys-operativo:%' END);
CREATE POLICY lys_mensaje_lectura ON realtime.messages FOR SELECT TO authenticated USING(channel_name LIKE 'lys-operativo:%' AND public.permiso_canal_operativo(channel_name));
CREATE POLICY lys_mensaje_limite ON realtime.messages AS RESTRICTIVE FOR SELECT TO PUBLIC USING(channel_name NOT LIKE 'lys-operativo:%' OR public.permiso_canal_operativo(channel_name));
CREATE POLICY lys_mensaje_no_cliente ON realtime.messages AS RESTRICTIVE FOR INSERT TO PUBLIC WITH CHECK(channel_name NOT LIKE 'lys-operativo:%');
CREATE FUNCTION public.notificar_operativo() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,realtime,pg_temp AS $$
DECLARE rol text;datos jsonb;cocina boolean; BEGIN
 datos:=jsonb_build_object('id',NEW.id,'local_id',NEW.local_id,'mesa_id',NEW.mesa_id,'revision',NEW.revision,'estado_pedido',NEW.estado_pedido,'estado_pago',NEW.estado_pago);
 cocina:=NEW.estado_pago='APROBADO' AND NEW.estado_pedido IN ('CONFIRMADO','EN_PREPARACION','LISTO');
 IF TG_OP='UPDATE' THEN cocina:=cocina OR(OLD.estado_pago='APROBADO' AND OLD.estado_pedido IN ('CONFIRMADO','EN_PREPARACION','LISTO')); END IF;
 FOREACH rol IN ARRAY ARRAY['MOZO','CAJA','ADMINISTRADOR','COCINA'] LOOP
 IF rol<>'COCINA' OR cocina THEN
 PERFORM realtime.publish('lys-operativo:'||NEW.local_id::text||':'||rol,'pedido_actualizado',datos);
 END IF;
 END LOOP;
 RETURN NEW;
EXCEPTION WHEN OTHERS THEN
 -- Un fallo de transporte no revierte un cobro legítimo; el fallback vuelve a consultar.
 RAISE WARNING 'LYS_REALTIME_PUBLICACION_FALLIDA'; RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.notificar_operativo() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER pedido_operativo_insert AFTER INSERT ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.notificar_operativo();
CREATE TRIGGER pedido_operativo_update AFTER UPDATE ON public.pedidos FOR EACH ROW WHEN(OLD.revision IS DISTINCT FROM NEW.revision) EXECUTE FUNCTION public.notificar_operativo();
