ALTER TABLE public.pedidos DROP CONSTRAINT pedidos_origen_check, DROP CONSTRAINT pedidos_modalidad_check,
 DROP CONSTRAINT pedidos_estado_valido, DROP CONSTRAINT pedidos_total_consistente,
 DROP CONSTRAINT pedidos_subtotal_check, DROP CONSTRAINT pedidos_total_check;
ALTER TABLE public.pedidos ADD CONSTRAINT pedidos_origen_check CHECK(origen IN ('WEB','MOZO')),
 ADD CONSTRAINT pedidos_modalidad_check CHECK(modalidad IN ('RECOJO_LOCAL','DELIVERY','CONSUMO_LOCAL')),
 ADD CONSTRAINT pedidos_estado_valido CHECK(estado_pedido IN ('BORRADOR','PENDIENTE_PAGO')),
 ADD CONSTRAINT pedidos_subtotal_check CHECK(subtotal>=0 AND (subtotal>0 OR estado_pedido='BORRADOR')),
 ADD CONSTRAINT pedidos_total_check CHECK(total>=0 AND (total>0 OR estado_pedido='BORRADOR')),
 ADD CONSTRAINT pedidos_total_consistente CHECK((modalidad IN ('RECOJO_LOCAL','CONSUMO_LOCAL') AND costo_delivery=0 AND total IS NOT NULL AND total=subtotal AND direccion_delivery IS NULL)
 OR(modalidad='DELIVERY' AND costo_delivery IS NULL AND total IS NULL AND direccion_delivery IS NOT NULL));
ALTER TABLE public.pedidos ALTER COLUMN nombres_contacto DROP NOT NULL, ALTER COLUMN telefono_contacto DROP NOT NULL;
ALTER TABLE public.pedidos ADD COLUMN mesa_id uuid REFERENCES public.mesas(id),
 ADD COLUMN mozo_id uuid REFERENCES auth.users(id),
 ADD COLUMN revision integer NOT NULL DEFAULT 1 CHECK(revision>0),
 ADD COLUMN observaciones text NOT NULL DEFAULT '' CHECK(length(observaciones)<=400),
 ADD CONSTRAINT pedidos_presencial_consistente CHECK((origen='MOZO' AND modalidad='CONSUMO_LOCAL' AND mesa_id IS NOT NULL AND mozo_id IS NOT NULL)
 OR(origen='WEB' AND modalidad IN ('RECOJO_LOCAL','DELIVERY') AND mesa_id IS NULL AND mozo_id IS NULL AND nombres_contacto IS NOT NULL AND telefono_contacto IS NOT NULL));
CREATE UNIQUE INDEX pedido_activo_mesa ON public.pedidos(mesa_id) WHERE mesa_id IS NOT NULL AND estado_pedido NOT IN ('FINALIZADO','ANULADO');
CREATE INDEX pedidos_mozo ON public.pedidos(mozo_id);
ALTER TABLE public.detalles_pedido ADD COLUMN observaciones text NOT NULL DEFAULT '' CHECK(length(observaciones)<=240);
CREATE TABLE public.auditoria_pedido (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),pedido_id uuid NOT NULL REFERENCES public.pedidos(id),
 usuario_id uuid NOT NULL REFERENCES auth.users(id),accion text NOT NULL,
 producto_id uuid REFERENCES public.productos(id),cantidad_anterior integer,cantidad_nueva integer,
 motivo text NOT NULL CHECK(length(motivo) BETWEEN 1 AND 400),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auditoria_pedido_fecha ON public.auditoria_pedido(pedido_id,created_at);
ALTER TABLE public.auditoria_pedido ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.auditoria_pedido FROM PUBLIC,anon,authenticated;

-- Solo la RPC operativa entrega columnas necesarias, sin hashes ni capacidades de invitados.
CREATE FUNCTION public.orden_operativa(p_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos; cocina boolean; BEGIN
 SELECT * INTO p FROM public.pedidos WHERE id=p_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 cocina:=public.permiso_local(p.local_id,ARRAY['COCINA']);
 IF NOT public.permiso_local(p.local_id,ARRAY['MOZO','CAJA','ADMINISTRADOR']) AND NOT(cocina AND p.estado_pago='APROBADO' AND p.estado_pedido IN ('CONFIRMADO','EN_PREPARACION','LISTO'))
 THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('id',p.id,'codigo',p.codigo,'local_id',p.local_id,'mesa_id',p.mesa_id,'mozo_id',p.mozo_id,'modalidad',p.modalidad,
 'estado_pedido',p.estado_pedido,'estado_pago',p.estado_pago,'revision',p.revision,'subtotal',p.subtotal,'total',p.total,'demostracion',p.demostracion,
 'observaciones',p.observaciones,'created_at',p.created_at,
 'mesa',(SELECT jsonb_build_object('numero',numero,'nombre',nombre,'estado',estado) FROM public.mesas WHERE id=p.mesa_id),
 'items',coalesce((SELECT jsonb_agg(jsonb_build_object('producto_id',producto_id,'nombre_producto',nombre_producto,'cantidad',cantidad,'precio_unitario',precio_unitario,'subtotal',subtotal,'observaciones',observaciones) ORDER BY nombre_producto) FROM public.detalles_pedido WHERE pedido_id=p.id),'[]'::jsonb));
END $$;
CREATE FUNCTION public.pedido_de_mesa(p_mesa uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE l uuid; id_pedido uuid; BEGIN
 SELECT local_id INTO l FROM public.mesas WHERE id=p_mesa AND activo;
 IF l IS NULL OR NOT public.permiso_local(l,ARRAY['MOZO','CAJA','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 SELECT id INTO id_pedido FROM public.pedidos WHERE mesa_id=p_mesa AND estado_pedido NOT IN ('FINALIZADO','ANULADO');
 RETURN CASE WHEN id_pedido IS NULL THEN NULL ELSE public.orden_operativa(id_pedido) END;
END $$;
CREATE FUNCTION public.abrir_pedido_mesa(p_mesa uuid,p_intento uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE m public.mesas;p public.pedidos; id_nuevo uuid; BEGIN
 SELECT * INTO m FROM public.mesas WHERE id=p_mesa FOR UPDATE;
 IF NOT FOUND OR NOT m.activo OR NOT public.permiso_local(m.local_id,ARRAY['MOZO','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF p_intento IS NULL THEN RAISE EXCEPTION 'INTENTO_INVALIDO' USING ERRCODE='22023'; END IF;
 SELECT * INTO p FROM public.pedidos WHERE mesa_id=p_mesa AND mozo_id=auth.uid() AND idempotencia=p_intento;
 IF FOUND THEN RETURN public.orden_operativa(p.id); END IF;
 IF m.estado<>'LIBRE' OR EXISTS(SELECT 1 FROM public.pedidos WHERE mesa_id=m.id AND estado_pedido NOT IN ('FINALIZADO','ANULADO')) THEN RAISE EXCEPTION 'MESA_OCUPADA' USING ERRCODE='22023'; END IF;
 -- El borrador no inventa un nombre, teléfono ni identidad de cliente presencial.
 INSERT INTO public.pedidos(local_id,tipo_cliente,origen,modalidad,estado_pedido,metodo_previsto,subtotal,costo_delivery,total,demostracion,idempotencia,identidad_hash,solicitud_hash,acceso_hash,acceso_expira,mesa_id,mozo_id)
 VALUES(m.local_id,'INVITADO','MOZO','CONSUMO_LOCAL','BORRADOR','EFECTIVO',0,0,0,m.demostracion,p_intento,'mesa:'||m.id::text,'mesa:'||m.id::text,encode(sha256(convert_to(gen_random_uuid()::text,'UTF8')),'hex'),now(),m.id,auth.uid()) RETURNING id INTO id_nuevo;
 UPDATE public.mesas SET estado='OCUPADA' WHERE id=m.id;
 INSERT INTO public.historial_pedido(pedido_id,usuario_id,accion,estado) VALUES(id_nuevo,auth.uid(),'MESA_ABIERTA','BORRADOR');
 INSERT INTO public.auditoria_pedido(pedido_id,usuario_id,accion,motivo) VALUES(id_nuevo,auth.uid(),'ABRIR_MESA','Nueva orden presencial');
 RETURN public.orden_operativa(id_nuevo);
END $$;
CREATE FUNCTION public.editar_pedido_mesa(p_id uuid,p_revision integer,p_items jsonb,p_observaciones text,p_motivo text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos;q jsonb; item jsonb; anterior public.detalles_pedido; obs text; BEGIN
 SELECT * INTO p FROM public.pedidos WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR p.origen<>'MOZO' OR NOT public.permiso_local(p.local_id,ARRAY['MOZO','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF p.estado_pago<>'PENDIENTE' OR p.estado_pedido NOT IN ('BORRADOR','PENDIENTE_PAGO') THEN RAISE EXCEPTION 'PEDIDO_PAGADO' USING ERRCODE='22023'; END IF;
 IF p_revision IS DISTINCT FROM p.revision THEN RAISE EXCEPTION 'REVISION_CONFLICTO' USING ERRCODE='22023'; END IF;
 IF p_observaciones IS NULL OR length(p_observaciones)>400 OR p_motivo IS NULL OR length(trim(p_motivo)) NOT BETWEEN 1 AND 400
 OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'DATOS_INVALIDOS' USING ERRCODE='22023'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
 IF jsonb_typeof(item) IS DISTINCT FROM 'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(item) k WHERE k NOT IN ('product_id','quantity','observaciones'))
 OR (item ? 'observaciones' AND (jsonb_typeof(item->'observaciones') IS DISTINCT FROM 'string' OR length(item->>'observaciones')>240)) THEN RAISE EXCEPTION 'ITEM_INVALIDO' USING ERRCODE='22023'; END IF;
 END LOOP;
 -- Bloquear referencias antes de cotizar evita cambios de precio/disponibilidad a mitad de edición.
 PERFORM pr.id FROM public.productos pr JOIN public.categorias c ON c.id=pr.categoria_id WHERE pr.id IN(SELECT (value->>'product_id')::uuid FROM jsonb_array_elements(p_items)) FOR SHARE OF pr,c;
 SELECT public.cotizar_pedido(jsonb_agg(value-'observaciones'),'RECOJO_LOCAL',p.local_id) INTO q FROM jsonb_array_elements(p_items);
 FOR anterior IN SELECT * FROM public.detalles_pedido WHERE pedido_id=p.id LOOP
 SELECT value INTO item FROM jsonb_array_elements(p_items) WHERE (value->>'product_id')::uuid=anterior.producto_id;
 IF item IS NULL OR (item->>'quantity')::integer<>anterior.cantidad OR coalesce(item->>'observaciones','')<>anterior.observaciones THEN
 INSERT INTO public.auditoria_pedido(pedido_id,usuario_id,accion,producto_id,cantidad_anterior,cantidad_nueva,motivo)
 VALUES(p.id,auth.uid(),CASE WHEN item IS NULL THEN 'QUITAR_PRODUCTO' ELSE 'EDITAR_PRODUCTO' END,anterior.producto_id,anterior.cantidad,coalesce((item->>'quantity')::integer,0),trim(p_motivo)); END IF;
 END LOOP;
 FOR item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
 IF NOT EXISTS(SELECT 1 FROM public.detalles_pedido WHERE pedido_id=p.id AND producto_id=(item->>'product_id')::uuid) THEN
 INSERT INTO public.auditoria_pedido(pedido_id,usuario_id,accion,producto_id,cantidad_anterior,cantidad_nueva,motivo) VALUES(p.id,auth.uid(),'AGREGAR_PRODUCTO',(item->>'product_id')::uuid,0,(item->>'quantity')::integer,trim(p_motivo)); END IF;
 END LOOP;
 DELETE FROM public.detalles_pedido WHERE pedido_id=p.id;
 FOR item IN SELECT value FROM jsonb_array_elements(q->'items') LOOP
 SELECT coalesce(value->>'observaciones','') INTO obs FROM jsonb_array_elements(p_items) WHERE value->>'product_id'=item->>'product_id';
 INSERT INTO public.detalles_pedido(pedido_id,producto_id,nombre_producto,cantidad,precio_unitario,subtotal,observaciones) VALUES(p.id,(item->>'product_id')::uuid,item->>'nombre',(item->>'quantity')::integer,(item->>'precio_unitario')::numeric,(item->>'subtotal')::numeric,obs);
 END LOOP;
 INSERT INTO public.auditoria_pedido(pedido_id,usuario_id,accion,motivo) VALUES(p.id,auth.uid(),'EDITAR_ORDEN',trim(p_motivo));
 UPDATE public.pedidos SET subtotal=(q->>'subtotal')::numeric,total=(q->>'total')::numeric,demostracion=demostracion OR (q->>'demostracion')::boolean,observaciones=p_observaciones,revision=revision+1 WHERE id=p.id;
 RETURN public.orden_operativa(p.id);
END $$;
CREATE FUNCTION public.enviar_pedido_caja(p_id uuid,p_revision integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos; BEGIN
 SELECT * INTO p FROM public.pedidos WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR p.origen<>'MOZO' OR NOT public.permiso_local(p.local_id,ARRAY['MOZO','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF p.estado_pedido='PENDIENTE_PAGO' AND p.estado_pago='PENDIENTE' THEN RETURN public.orden_operativa(p.id); END IF;
 IF p_revision IS DISTINCT FROM p.revision THEN RAISE EXCEPTION 'REVISION_CONFLICTO' USING ERRCODE='22023'; END IF;
 IF p.estado_pedido<>'BORRADOR' OR p.estado_pago<>'PENDIENTE' OR p.total<=0 OR NOT EXISTS(SELECT 1 FROM public.detalles_pedido WHERE pedido_id=p.id) THEN RAISE EXCEPTION 'ORDEN_INVALIDA' USING ERRCODE='22023'; END IF;
 UPDATE public.pedidos SET estado_pedido='PENDIENTE_PAGO',revision=revision+1 WHERE id=p.id;
 UPDATE public.mesas SET estado='POR_COBRAR' WHERE id=p.mesa_id;
 INSERT INTO public.historial_pedido(pedido_id,usuario_id,accion,estado) VALUES(p.id,auth.uid(),'ENVIADO_CAJA','PENDIENTE_PAGO');
 INSERT INTO public.auditoria_pedido(pedido_id,usuario_id,accion,motivo) VALUES(p.id,auth.uid(),'ENVIAR_CAJA','Orden revisada');
 RETURN public.orden_operativa(p.id);
END $$;
REVOKE ALL ON FUNCTION public.orden_operativa(uuid),public.pedido_de_mesa(uuid),public.abrir_pedido_mesa(uuid,uuid),public.editar_pedido_mesa(uuid,integer,jsonb,text,text),public.enviar_pedido_caja(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.orden_operativa(uuid),public.pedido_de_mesa(uuid),public.abrir_pedido_mesa(uuid,uuid),public.editar_pedido_mesa(uuid,integer,jsonb,text,text),public.enviar_pedido_caja(uuid,integer) TO authenticated;
