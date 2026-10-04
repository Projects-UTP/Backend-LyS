ALTER TABLE public.pedidos DROP CONSTRAINT pedidos_estado_valido,DROP CONSTRAINT pedidos_pago_valido;
ALTER TABLE public.pedidos ADD CONSTRAINT pedidos_estado_valido CHECK(estado_pedido IN ('BORRADOR','PENDIENTE_PAGO','CONFIRMADO','EN_PREPARACION','LISTO','ENTREGADO','FINALIZADO','ANULADO')),
 ADD CONSTRAINT pedidos_pago_valido CHECK(estado_pago IN ('PENDIENTE','APROBADO','ANULADO')),
 ADD CONSTRAINT pedido_pago_coherente CHECK((estado_pedido IN ('BORRADOR','PENDIENTE_PAGO') AND estado_pago='PENDIENTE') OR(estado_pedido IN ('CONFIRMADO','EN_PREPARACION','LISTO','ENTREGADO','FINALIZADO') AND estado_pago='APROBADO') OR(estado_pedido='ANULADO' AND estado_pago IN ('PENDIENTE','ANULADO'))),
 ADD COLUMN paid_at timestamptz,ADD COLUMN confirmed_at timestamptz,ADD COLUMN preparation_started_at timestamptz,
 ADD COLUMN ready_at timestamptz,ADD COLUMN delivered_at timestamptz,ADD COLUMN finalized_at timestamptz;

CREATE TABLE public.sesiones_caja (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),local_id uuid NOT NULL REFERENCES public.locales(id),
 cajero_id uuid NOT NULL REFERENCES auth.users(id),monto_inicial numeric(12,2) NOT NULL CHECK(monto_inicial>=0),
 estado text NOT NULL DEFAULT 'ABIERTA' CHECK(estado IN ('ABIERTA','CERRADA')),
 idempotencia uuid NOT NULL,revision integer NOT NULL DEFAULT 1,
 opened_at timestamptz NOT NULL DEFAULT now(),closed_at timestamptz,resumen_cierre jsonb,
 UNIQUE(cajero_id,idempotencia),CHECK((estado='ABIERTA' AND closed_at IS NULL AND resumen_cierre IS NULL) OR(estado='CERRADA' AND closed_at IS NOT NULL AND resumen_cierre IS NOT NULL))
);
CREATE UNIQUE INDEX sesion_abierta_cajero_local ON public.sesiones_caja(cajero_id,local_id) WHERE estado='ABIERTA';
CREATE INDEX sesiones_local ON public.sesiones_caja(local_id,opened_at);
CREATE TABLE public.pagos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),pedido_id uuid NOT NULL UNIQUE REFERENCES public.pedidos(id),
 local_id uuid NOT NULL REFERENCES public.locales(id),sesion_id uuid NOT NULL REFERENCES public.sesiones_caja(id),cajero_id uuid NOT NULL REFERENCES auth.users(id),
 metodo text NOT NULL CHECK(metodo IN ('EFECTIVO','YAPE','PLIN','TARJETA_POS')),
 monto numeric(12,2) NOT NULL CHECK(monto>0),recibido numeric(12,2),vuelto numeric(12,2) NOT NULL,
 referencia text CHECK(referencia IS NULL OR length(referencia)<=120),
 estado text NOT NULL DEFAULT 'PENDIENTE' CHECK(estado IN ('PENDIENTE','APROBADO','ANULADO')),
 idempotencia uuid NOT NULL,solicitud_hash text NOT NULL,
 tipo_comprobante text NOT NULL DEFAULT 'BOLETA' CHECK(tipo_comprobante='BOLETA'),
 estado_comprobante text NOT NULL DEFAULT 'PENDIENTE_PROVEEDOR' CHECK(estado_comprobante='PENDIENTE_PROVEEDOR'),
 created_at timestamptz NOT NULL DEFAULT now(),anulado_at timestamptz,anulado_por uuid REFERENCES auth.users(id),motivo_anulacion text,
 UNIQUE(cajero_id,idempotencia),CHECK((metodo='EFECTIVO' AND recibido>=monto AND vuelto=recibido-monto) OR(metodo<>'EFECTIVO' AND recibido IS NULL AND vuelto=0)),
 CHECK((estado<>'ANULADO' AND anulado_at IS NULL AND anulado_por IS NULL AND motivo_anulacion IS NULL) OR(estado='ANULADO' AND anulado_at IS NOT NULL AND anulado_por IS NOT NULL AND length(trim(motivo_anulacion)) BETWEEN 3 AND 400))
);
CREATE INDEX pagos_sesion ON public.pagos(sesion_id,metodo);
CREATE INDEX pagos_local ON public.pagos(local_id,created_at);
CREATE TABLE public.movimientos_caja (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),sesion_id uuid NOT NULL REFERENCES public.sesiones_caja(id),
 usuario_id uuid NOT NULL REFERENCES auth.users(id),pago_id uuid UNIQUE REFERENCES public.pagos(id),
 tipo text NOT NULL CHECK(tipo IN ('VENTA','INGRESO','EGRESO','AJUSTE')),monto numeric(12,2) NOT NULL CHECK(monto>0),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX movimientos_sesion ON public.movimientos_caja(sesion_id,created_at);
CREATE TABLE public.auditoria_operativa (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),local_id uuid NOT NULL REFERENCES public.locales(id),usuario_id uuid NOT NULL REFERENCES auth.users(id),
 pedido_id uuid REFERENCES public.pedidos(id),pago_id uuid REFERENCES public.pagos(id),sesion_id uuid REFERENCES public.sesiones_caja(id),
 accion text NOT NULL,motivo text NOT NULL CHECK(length(motivo) BETWEEN 1 AND 400),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auditoria_operativa_local ON public.auditoria_operativa(local_id,created_at);
ALTER TABLE public.sesiones_caja ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pagos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimientos_caja ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria_operativa ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sesiones_caja,public.pagos,public.movimientos_caja,public.auditoria_operativa FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.sesiones_caja TO authenticated;
GRANT SELECT(id,pedido_id,local_id,sesion_id,cajero_id,metodo,monto,recibido,vuelto,referencia,estado,tipo_comprobante,estado_comprobante,created_at,anulado_at,anulado_por,motivo_anulacion) ON public.pagos TO authenticated;
GRANT SELECT ON public.movimientos_caja,public.auditoria_operativa TO authenticated;
CREATE POLICY sesion_personal ON public.sesiones_caja FOR SELECT TO authenticated USING((cajero_id=(SELECT auth.uid()) AND public.permiso_local(local_id,ARRAY['CAJA','ADMINISTRADOR'])) OR public.permiso_local(local_id,ARRAY['ADMINISTRADOR']));
CREATE POLICY pago_caja ON public.pagos FOR SELECT TO authenticated USING(public.permiso_local(local_id,ARRAY['CAJA','ADMINISTRADOR']));
CREATE POLICY movimientos_personal ON public.movimientos_caja FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.sesiones_caja s WHERE s.id=sesion_id));
CREATE POLICY auditoria_admin ON public.auditoria_operativa FOR SELECT TO authenticated USING(public.permiso_local(local_id,ARRAY['ADMINISTRADOR']));

CREATE FUNCTION public.resumen_caja(p_sesion uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE s public.sesiones_caja;ventas jsonb;total_ventas numeric(12,2);efectivo numeric(12,2);anulados numeric(12,2); BEGIN
 SELECT * INTO s FROM public.sesiones_caja WHERE id=p_sesion;
 IF NOT FOUND OR NOT((s.cajero_id=auth.uid() AND public.permiso_local(s.local_id,ARRAY['CAJA','ADMINISTRADOR'])) OR public.permiso_local(s.local_id,ARRAY['ADMINISTRADOR'])) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF s.estado='CERRADA' THEN RETURN s.resumen_cierre; END IF;
 SELECT coalesce(jsonb_object_agg(metodo,importe),'{}'::jsonb) INTO ventas FROM(SELECT metodo,sum(monto) importe FROM public.pagos WHERE sesion_id=s.id AND estado='APROBADO' GROUP BY metodo) v;
 SELECT coalesce(sum(monto) FILTER(WHERE estado='APROBADO'),0),coalesce(sum(monto) FILTER(WHERE metodo='EFECTIVO' AND estado IN ('APROBADO','ANULADO')),0),coalesce(sum(monto) FILTER(WHERE estado='ANULADO'),0)
 INTO total_ventas,efectivo,anulados FROM public.pagos WHERE sesion_id=s.id;
 -- Anular un registro no acredita una devolución: el efectivo recibido sigue en el esperado.
 RETURN jsonb_build_object('id',s.id,'local_id',s.local_id,'cajero_id',s.cajero_id,'estado',s.estado,'revision',s.revision,'opened_at',s.opened_at,'closed_at',s.closed_at,
 'monto_inicial',s.monto_inicial,'ventas',ventas,'total_ventas',total_ventas,'fondos_anulados',anulados,'efectivo_esperado',s.monto_inicial+efectivo,'total_esperado',s.monto_inicial+efectivo);
END $$;
CREATE FUNCTION public.mi_caja(p_local uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE id_sesion uuid; BEGIN
 IF NOT public.permiso_local(p_local,ARRAY['CAJA','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 SELECT id INTO id_sesion FROM public.sesiones_caja WHERE local_id=p_local AND cajero_id=auth.uid() ORDER BY (estado='ABIERTA') DESC,opened_at DESC LIMIT 1;
 RETURN CASE WHEN id_sesion IS NULL THEN NULL ELSE public.resumen_caja(id_sesion) END;
END $$;
CREATE FUNCTION public.abrir_caja(p_local uuid,p_monto numeric,p_intento uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE s public.sesiones_caja; id_sesion uuid; BEGIN
 IF NOT public.permiso_local(p_local,ARRAY['CAJA','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF p_monto IS NULL OR p_monto<0 OR p_monto<>round(p_monto,2) OR p_intento IS NULL THEN RAISE EXCEPTION 'MONTO_INVALIDO' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('caja:'||auth.uid()::text||p_local::text,0));
 SELECT * INTO s FROM public.sesiones_caja WHERE cajero_id=auth.uid() AND idempotencia=p_intento;
 IF FOUND THEN IF s.local_id<>p_local OR s.monto_inicial<>p_monto THEN RAISE EXCEPTION 'IDEMPOTENCIA_CONFLICTO' USING ERRCODE='22023'; END IF; RETURN public.resumen_caja(s.id); END IF;
 IF EXISTS(SELECT 1 FROM public.sesiones_caja WHERE cajero_id=auth.uid() AND local_id=p_local AND estado='ABIERTA') THEN RAISE EXCEPTION 'CAJA_YA_ABIERTA' USING ERRCODE='22023'; END IF;
 INSERT INTO public.sesiones_caja(local_id,cajero_id,monto_inicial,idempotencia) VALUES(p_local,auth.uid(),p_monto,p_intento) RETURNING id INTO id_sesion;
 INSERT INTO public.auditoria_operativa(local_id,usuario_id,sesion_id,accion,motivo) VALUES(p_local,auth.uid(),id_sesion,'ABRIR_CAJA','Monto inicial confirmado por caja');
 RETURN public.resumen_caja(id_sesion);
END $$;
CREATE FUNCTION public.cerrar_caja(p_sesion uuid,p_revision integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE s public.sesiones_caja;r jsonb; BEGIN
 SELECT * INTO s FROM public.sesiones_caja WHERE id=p_sesion FOR UPDATE;
 IF NOT FOUND OR s.cajero_id IS DISTINCT FROM auth.uid() OR NOT public.permiso_local(s.local_id,ARRAY['CAJA','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF s.estado='CERRADA' THEN RETURN s.resumen_cierre; END IF;
 IF p_revision IS DISTINCT FROM s.revision THEN RAISE EXCEPTION 'REVISION_CONFLICTO' USING ERRCODE='22023'; END IF;
 r:=public.resumen_caja(s.id)||jsonb_build_object('estado','CERRADA','closed_at',now(),'revision',s.revision+1);
 UPDATE public.sesiones_caja SET estado='CERRADA',closed_at=now(),revision=revision+1,resumen_cierre=r WHERE id=s.id;
 INSERT INTO public.auditoria_operativa(local_id,usuario_id,sesion_id,accion,motivo) VALUES(s.local_id,auth.uid(),s.id,'CERRAR_CAJA','Cierre básico; arqueo físico y movimientos manuales pendientes');
 RETURN r;
END $$;

CREATE FUNCTION public.registrar_pago(p_id uuid,p_revision integer,p_sesion uuid,p_metodo text,p_recibido numeric,p_referencia text,p_intento uuid,p_confirmado boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos;s public.sesiones_caja;pago public.pagos;huella text;subtotal_actual numeric(12,2);vuelto numeric(12,2); BEGIN
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
 UPDATE public.pedidos SET estado_pago='APROBADO',estado_pedido='CONFIRMADO',paid_at=now(),confirmed_at=now(),revision=revision+1 WHERE id=p.id;
 IF p.mesa_id IS NOT NULL THEN UPDATE public.mesas SET estado='OCUPADA' WHERE id=p.mesa_id; END IF;
 UPDATE public.sesiones_caja SET revision=revision+1 WHERE id=s.id;
 INSERT INTO public.historial_pedido(pedido_id,usuario_id,accion,estado) VALUES(p.id,auth.uid(),'PAGO_APROBADO','CONFIRMADO');
 INSERT INTO public.auditoria_operativa(local_id,usuario_id,pedido_id,pago_id,sesion_id,accion,motivo) VALUES(p.local_id,auth.uid(),p.id,pago.id,s.id,'PAGO_REGISTRADO','Cobro confirmado manualmente por caja');
 RETURN jsonb_build_object('pago_id',pago.id,'estado',pago.estado,'monto',pago.monto,'vuelto',pago.vuelto,'reutilizado',false);
END $$;
CREATE FUNCTION public.cola_pagos(p_local uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
 IF NOT public.permiso_local(p_local,ARRAY['CAJA','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(public.orden_operativa(id)||jsonb_build_object('cliente',nombres_contacto,'metodo_previsto',metodo_previsto) ORDER BY created_at) FROM public.pedidos WHERE local_id=p_local AND estado_pedido='PENDIENTE_PAGO' AND estado_pago='PENDIENTE'),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.resumen_caja(uuid),public.mi_caja(uuid),public.abrir_caja(uuid,numeric,uuid),public.cerrar_caja(uuid,integer),public.registrar_pago(uuid,integer,uuid,text,numeric,text,uuid,boolean),public.cola_pagos(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resumen_caja(uuid),public.mi_caja(uuid),public.abrir_caja(uuid,numeric,uuid),public.cerrar_caja(uuid,integer),public.registrar_pago(uuid,integer,uuid,text,numeric,text,uuid,boolean),public.cola_pagos(uuid) TO authenticated;
