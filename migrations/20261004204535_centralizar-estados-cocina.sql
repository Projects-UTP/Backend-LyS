-- Todas las mutaciones de estado consultan esta matriz privada de rol/transición.
CREATE TABLE public.transiciones_pedido (
 desde text NOT NULL,hacia text NOT NULL,roles text[] NOT NULL,PRIMARY KEY(desde,hacia)
);
INSERT INTO public.transiciones_pedido VALUES
 ('PENDIENTE_PAGO','CONFIRMADO',ARRAY['CAJA','ADMINISTRADOR']),
 ('CONFIRMADO','EN_PREPARACION',ARRAY['COCINA','ADMINISTRADOR']),
 ('EN_PREPARACION','LISTO',ARRAY['COCINA','ADMINISTRADOR']),
 ('LISTO','ENTREGADO',ARRAY['MOZO','ADMINISTRADOR']),
 ('ENTREGADO','FINALIZADO',ARRAY['MOZO','ADMINISTRADOR']),
 ('BORRADOR','ANULADO',ARRAY['ADMINISTRADOR']),
 ('PENDIENTE_PAGO','ANULADO',ARRAY['ADMINISTRADOR']),
 ('CONFIRMADO','ANULADO',ARRAY['ADMINISTRADOR']);
ALTER TABLE public.transiciones_pedido ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.transiciones_pedido FROM PUBLIC,anon,authenticated;
ALTER TABLE public.pedidos DROP CONSTRAINT pedidos_subtotal_check,DROP CONSTRAINT pedidos_total_check;
ALTER TABLE public.pedidos ADD CONSTRAINT pedidos_subtotal_check CHECK(subtotal>=0 AND(subtotal>0 OR estado_pedido IN ('BORRADOR','ANULADO'))),
 ADD CONSTRAINT pedidos_total_check CHECK(total>=0 AND(total>0 OR estado_pedido IN ('BORRADOR','ANULADO')));

CREATE FUNCTION public.aplicar_transicion_pedido(p_id uuid,p_revision integer,p_hacia text,p_motivo text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos;roles_permitidos text[];pago_nuevo text; BEGIN
 SELECT * INTO p FROM public.pedidos WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 SELECT roles INTO roles_permitidos FROM public.transiciones_pedido WHERE desde=p.estado_pedido AND hacia=p_hacia;
 IF roles_permitidos IS NULL THEN RAISE EXCEPTION 'TRANSICION_INVALIDA' USING ERRCODE='22023'; END IF;
 IF NOT public.permiso_local(p.local_id,roles_permitidos) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF p_revision IS DISTINCT FROM p.revision THEN RAISE EXCEPTION 'REVISION_CONFLICTO' USING ERRCODE='22023'; END IF;
 IF p_motivo IS NULL OR length(trim(p_motivo)) NOT BETWEEN 1 AND 400 THEN RAISE EXCEPTION 'MOTIVO_INVALIDO' USING ERRCODE='22023'; END IF;
 IF p_hacia<>'ANULADO' AND NOT EXISTS(SELECT 1 FROM public.pagos WHERE pedido_id=p.id AND estado='APROBADO') THEN RAISE EXCEPTION 'PAGO_NO_APROBADO' USING ERRCODE='22023'; END IF;
 pago_nuevo:=CASE WHEN p_hacia='CONFIRMADO' THEN 'APROBADO' WHEN p_hacia='ANULADO' AND p.estado_pago='APROBADO' THEN 'ANULADO' ELSE p.estado_pago END;
 UPDATE public.pedidos SET estado_pedido=p_hacia,estado_pago=pago_nuevo,revision=revision+1,
 paid_at=CASE WHEN p_hacia='CONFIRMADO' THEN now() ELSE paid_at END,
 confirmed_at=CASE WHEN p_hacia='CONFIRMADO' THEN now() ELSE confirmed_at END,
 preparation_started_at=CASE WHEN p_hacia='EN_PREPARACION' THEN now() ELSE preparation_started_at END,
 ready_at=CASE WHEN p_hacia='LISTO' THEN now() ELSE ready_at END,
 delivered_at=CASE WHEN p_hacia='ENTREGADO' THEN now() ELSE delivered_at END,
 finalized_at=CASE WHEN p_hacia='FINALIZADO' THEN now() ELSE finalized_at END WHERE id=p.id;
 INSERT INTO public.historial_pedido(pedido_id,usuario_id,accion,estado) VALUES(p.id,auth.uid(),'ESTADO_'||p_hacia,p_hacia);
 INSERT INTO public.auditoria_operativa(local_id,usuario_id,pedido_id,accion,motivo) VALUES(p.local_id,auth.uid(),p.id,'ESTADO_'||p_hacia,trim(p_motivo));
 IF p.mesa_id IS NOT NULL THEN
 IF p_hacia='CONFIRMADO' THEN UPDATE public.mesas SET estado='OCUPADA' WHERE id=p.mesa_id;
 ELSIF p_hacia IN ('FINALIZADO','ANULADO') AND NOT EXISTS(SELECT 1 FROM public.pedidos WHERE mesa_id=p.mesa_id AND id<>p.id AND estado_pedido NOT IN ('FINALIZADO','ANULADO')) THEN
 -- La mesa solo se libera al finalizar/anular, nunca al marcar LISTO.
 UPDATE public.mesas SET estado='LIBRE' WHERE id=p.mesa_id;
 END IF;
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.aplicar_transicion_pedido(uuid,integer,text,text) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.cambiar_estado_pedido(p_id uuid,p_revision integer,p_estado text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos; BEGIN
 IF p_estado IS NULL OR p_estado NOT IN ('EN_PREPARACION','LISTO','ENTREGADO') THEN RAISE EXCEPTION 'TRANSICION_INVALIDA' USING ERRCODE='22023'; END IF;
 PERFORM public.aplicar_transicion_pedido(p_id,p_revision,p_estado,'Acción confirmada por personal autorizado');
 SELECT * INTO p FROM public.pedidos WHERE id=p_id;
 IF p_estado='ENTREGADO' AND p.modalidad IN ('CONSUMO_LOCAL','RECOJO_LOCAL') THEN
 PERFORM public.aplicar_transicion_pedido(p.id,p.revision,'FINALIZADO','Finalización automática tras entrega registrada'); END IF;
 RETURN public.orden_operativa(p_id);
END $$;
CREATE FUNCTION public.cola_cocina(p_local uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
 IF NOT public.permiso_local(p_local,ARRAY['COCINA','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(public.orden_operativa(id) ORDER BY confirmed_at) FROM public.pedidos WHERE local_id=p_local AND estado_pago='APROBADO' AND estado_pedido IN ('CONFIRMADO','EN_PREPARACION','LISTO')),'[]'::jsonb);
END $$;
CREATE FUNCTION public.consultar_cocina(p_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos; BEGIN
 SELECT * INTO p FROM public.pedidos WHERE id=p_id;
 IF NOT FOUND OR NOT public.permiso_local(p.local_id,ARRAY['COCINA','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF p.estado_pago<>'APROBADO' OR p.estado_pedido NOT IN ('CONFIRMADO','EN_PREPARACION','LISTO') THEN RETURN NULL; END IF;
 RETURN public.orden_operativa(p.id);
END $$;
CREATE FUNCTION public.cola_listos(p_local uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
 IF NOT public.permiso_local(p_local,ARRAY['MOZO','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(public.orden_operativa(id) ORDER BY ready_at) FROM public.pedidos WHERE local_id=p_local AND estado_pago='APROBADO' AND estado_pedido='LISTO'),'[]'::jsonb);
END $$;
CREATE FUNCTION public.anular_pago(p_pago uuid,p_motivo text,p_confirmado boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE pago public.pagos;s public.sesiones_caja;p public.pedidos; BEGIN
 SELECT * INTO pago FROM public.pagos WHERE id=p_pago;
 IF NOT FOUND OR NOT public.permiso_local(pago.local_id,ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF p_confirmado IS DISTINCT FROM true OR p_motivo IS NULL OR length(trim(p_motivo)) NOT BETWEEN 3 AND 400 THEN RAISE EXCEPTION 'MOTIVO_INVALIDO' USING ERRCODE='22023'; END IF;
 SELECT * INTO s FROM public.sesiones_caja WHERE id=pago.sesion_id FOR UPDATE;
 SELECT * INTO p FROM public.pedidos WHERE id=pago.pedido_id FOR UPDATE;
 SELECT * INTO pago FROM public.pagos WHERE id=p_pago FOR UPDATE;
 IF pago.estado='ANULADO' THEN RETURN jsonb_build_object('pago_id',pago.id,'estado','ANULADO','reutilizado',true); END IF;
 -- Sin reglas de devolución confirmadas, no se anula después de comenzar cocina o cerrar turno.
 IF s.estado<>'ABIERTA' OR p.estado_pedido<>'CONFIRMADO' OR pago.estado<>'APROBADO' THEN RAISE EXCEPTION 'ANULACION_NO_PERMITIDA' USING ERRCODE='22023'; END IF;
 UPDATE public.pagos SET estado='ANULADO',anulado_at=now(),anulado_por=auth.uid(),motivo_anulacion=trim(p_motivo) WHERE id=pago.id;
 PERFORM public.aplicar_transicion_pedido(p.id,p.revision,'ANULADO',trim(p_motivo));
 UPDATE public.sesiones_caja SET revision=revision+1 WHERE id=s.id;
 INSERT INTO public.auditoria_operativa(local_id,usuario_id,pedido_id,pago_id,sesion_id,accion,motivo) VALUES(p.local_id,auth.uid(),p.id,pago.id,s.id,'PAGO_ANULADO',trim(p_motivo));
 RETURN jsonb_build_object('pago_id',pago.id,'estado','ANULADO','reutilizado',false);
END $$;
REVOKE ALL ON FUNCTION public.cambiar_estado_pedido(uuid,integer,text),public.cola_cocina(uuid),public.consultar_cocina(uuid),public.cola_listos(uuid),public.anular_pago(uuid,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cambiar_estado_pedido(uuid,integer,text),public.cola_cocina(uuid),public.consultar_cocina(uuid),public.cola_listos(uuid),public.anular_pago(uuid,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.orden_operativa(p_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos; cocina boolean; BEGIN
 SELECT * INTO p FROM public.pedidos WHERE id=p_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 cocina:=public.permiso_local(p.local_id,ARRAY['COCINA']);
 IF NOT public.permiso_local(p.local_id,ARRAY['MOZO','CAJA','ADMINISTRADOR']) AND NOT(cocina AND p.estado_pago='APROBADO' AND p.estado_pedido IN ('CONFIRMADO','EN_PREPARACION','LISTO'))
 THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('id',p.id,'codigo',p.codigo,'local_id',p.local_id,'mesa_id',p.mesa_id,'mozo_id',p.mozo_id,'modalidad',p.modalidad,
 'estado_pedido',p.estado_pedido,'estado_pago',p.estado_pago,'revision',p.revision,'subtotal',p.subtotal,'total',p.total,'demostracion',p.demostracion,
 'observaciones',p.observaciones,'created_at',p.created_at,'paid_at',p.paid_at,'confirmed_at',p.confirmed_at,'preparation_started_at',p.preparation_started_at,'ready_at',p.ready_at,'delivered_at',p.delivered_at,'finalized_at',p.finalized_at,
 'mozo_nombre',(SELECT nullif(trim(concat_ws(' ',nombres,apellidos)),'') FROM public.perfiles_cliente WHERE id=p.mozo_id),
 'mesa',(SELECT jsonb_build_object('numero',numero,'nombre',nombre,'estado',estado) FROM public.mesas WHERE id=p.mesa_id),
 'items',coalesce((SELECT jsonb_agg(jsonb_build_object('producto_id',producto_id,'nombre_producto',nombre_producto,'cantidad',cantidad,'precio_unitario',precio_unitario,'subtotal',subtotal,'observaciones',observaciones) ORDER BY nombre_producto) FROM public.detalles_pedido WHERE pedido_id=p.id),'[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.registrar_pago(p_id uuid,p_revision integer,p_sesion uuid,p_metodo text,p_recibido numeric,p_referencia text,p_intento uuid,p_confirmado boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos;s public.sesiones_caja;pago public.pagos;huella text;subtotal_actual numeric(12,2);vuelto numeric(12,2); BEGIN
 IF coalesce(p_referencia,'') ~ '[0-9]{13,19}' OR coalesce(p_referencia,'') ~* '(cvv|cvc|pan)[[:space:]:=-]*[0-9]' THEN RAISE EXCEPTION 'REFERENCIA_SENSIBLE' USING ERRCODE='22023'; END IF;
 IF p_intento IS NULL OR p_confirmado IS DISTINCT FROM true OR p_metodo IS NULL OR p_metodo NOT IN ('EFECTIVO','YAPE','PLIN','TARJETA_POS') OR length(coalesce(p_referencia,''))>120 THEN RAISE EXCEPTION 'PAGO_INVALIDO' USING ERRCODE='22023'; END IF;
 IF p_metodo='EFECTIVO' AND (p_recibido IS NULL OR p_recibido<=0 OR p_recibido<>round(p_recibido,2)) OR(p_metodo<>'EFECTIVO' AND p_recibido IS NOT NULL) THEN RAISE EXCEPTION 'MONTO_INVALIDO' USING ERRCODE='22023'; END IF;
 huella:=md5(jsonb_build_object('pedido',p_id,'revision',p_revision,'sesion',p_sesion,'metodo',p_metodo,'recibido',p_recibido,'referencia',nullif(trim(p_referencia),''))::text);
 PERFORM pg_advisory_xact_lock(hashtextextended('pago:'||auth.uid()::text||p_intento::text,0));
 -- Se bloquea la sesión antes del pedido; el cierre nunca puede adelantarse a un cobro.
 SELECT * INTO s FROM public.sesiones_caja WHERE id=p_sesion FOR UPDATE;
 IF NOT FOUND OR s.cajero_id IS DISTINCT FROM auth.uid() OR NOT public.permiso_local(s.local_id,ARRAY['CAJA','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 SELECT * INTO pago FROM public.pagos WHERE cajero_id=auth.uid() AND idempotencia=p_intento;
 IF FOUND THEN
 IF pago.solicitud_hash<>huella THEN RAISE EXCEPTION 'IDEMPOTENCIA_CONFLICTO' USING ERRCODE='22023'; END IF;
 RETURN jsonb_build_object('pago_id',pago.id,'estado',pago.estado,'monto',pago.monto,'vuelto',pago.vuelto,'reutilizado',true);
 END IF;
 IF s.estado<>'ABIERTA' THEN RAISE EXCEPTION 'CAJA_CERRADA' USING ERRCODE='22023'; END IF;
 SELECT * INTO p FROM public.pedidos WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR p.local_id<>s.local_id THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF p.estado_pago<>'PENDIENTE' OR p.estado_pedido<>'PENDIENTE_PAGO' OR EXISTS(SELECT 1 FROM public.pagos WHERE pedido_id=p.id) THEN RAISE EXCEPTION 'PEDIDO_YA_COBRADO_O_INVALIDO' USING ERRCODE='22023'; END IF;
 IF p_revision IS DISTINCT FROM p.revision THEN RAISE EXCEPTION 'REVISION_CONFLICTO' USING ERRCODE='22023'; END IF;
 SELECT coalesce(sum(subtotal),0) INTO subtotal_actual FROM public.detalles_pedido WHERE pedido_id=p.id;
 IF p.total IS NULL OR p.total<=0 OR p.subtotal<>subtotal_actual OR p.total<>p.subtotal-p.descuento+coalesce(p.costo_delivery,0) THEN RAISE EXCEPTION 'TOTAL_NO_CONFIRMADO' USING ERRCODE='22023'; END IF;
 IF p_metodo='EFECTIVO' AND p_recibido<p.total THEN RAISE EXCEPTION 'EFECTIVO_INSUFICIENTE' USING ERRCODE='22023'; END IF;
 vuelto:=CASE WHEN p_metodo='EFECTIVO' THEN p_recibido-p.total ELSE 0 END;
 INSERT INTO public.pagos(pedido_id,local_id,sesion_id,cajero_id,metodo,monto,recibido,vuelto,referencia,estado,idempotencia,solicitud_hash)
 VALUES(p.id,p.local_id,s.id,auth.uid(),p_metodo,p.total,p_recibido,vuelto,nullif(trim(p_referencia),''),'APROBADO',p_intento,huella) RETURNING * INTO pago;
 INSERT INTO public.movimientos_caja(sesion_id,usuario_id,pago_id,tipo,monto) VALUES(s.id,auth.uid(),pago.id,'VENTA',p.total);
 -- Pago y pedido se confirman en la misma transacción, sin total enviado por frontend.
 PERFORM public.aplicar_transicion_pedido(p.id,p.revision,'CONFIRMADO','Pago recibido y verificado por caja');
 UPDATE public.sesiones_caja SET revision=revision+1 WHERE id=s.id;
 INSERT INTO public.auditoria_operativa(local_id,usuario_id,pedido_id,pago_id,sesion_id,accion,motivo) VALUES(p.local_id,auth.uid(),p.id,pago.id,s.id,'PAGO_REGISTRADO','Cobro confirmado manualmente por caja');
 RETURN jsonb_build_object('pago_id',pago.id,'estado',pago.estado,'monto',pago.monto,'vuelto',pago.vuelto,'reutilizado',false);
END $$;
