CREATE FUNCTION public.consultar_pago_administrador(p_local uuid,p_codigo text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos;pago public.pagos;s public.sesiones_caja; BEGIN
 IF NOT public.permiso_local(p_local,ARRAY['ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF p_codigo IS NULL OR trim(p_codigo) !~ '^LYS-[0-9]{6,12}$' THEN RAISE EXCEPTION 'CODIGO_INVALIDO' USING ERRCODE='22023'; END IF;
 SELECT * INTO p FROM public.pedidos WHERE local_id=p_local AND codigo=trim(p_codigo);
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO pago FROM public.pagos WHERE pedido_id=p.id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT * INTO s FROM public.sesiones_caja WHERE id=pago.sesion_id;
 RETURN jsonb_build_object('pago_id',pago.id,'codigo',p.codigo,'metodo',pago.metodo,'monto',pago.monto,'estado',pago.estado,'created_at',pago.created_at,
 'estado_pedido',p.estado_pedido,'sesion_estado',s.estado,'anulado_at',pago.anulado_at,'anulado_por',pago.anulado_por,'motivo_anulacion',pago.motivo_anulacion,
 'puede_anular',pago.estado='APROBADO' AND p.estado_pedido='CONFIRMADO' AND s.estado='ABIERTA');
END $$;
REVOKE ALL ON FUNCTION public.consultar_pago_administrador(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consultar_pago_administrador(uuid,text) TO authenticated;
-- Ningún método almacena PAN ni CVV, incluso con espacios o guiones.
ALTER TABLE public.pagos ADD CONSTRAINT pago_referencia_no_tarjeta CHECK(
 coalesce(referencia,'') !~ '(^|[^0-9])([0-9][ -]?){13,19}([^0-9]|$)' AND coalesce(referencia,'') !~* '(cvv|cvc|pan)[[:space:]:=-]*[0-9]');
CREATE INDEX pedidos_cola_cocina ON public.pedidos(local_id,confirmed_at) WHERE estado_pago='APROBADO' AND estado_pedido IN ('CONFIRMADO','EN_PREPARACION','LISTO');
CREATE INDEX pedidos_cola_caja ON public.pedidos(local_id,created_at) WHERE estado_pago='PENDIENTE' AND estado_pedido='PENDIENTE_PAGO';
CREATE INDEX pedidos_cola_listos ON public.pedidos(local_id,ready_at) WHERE estado_pago='APROBADO' AND estado_pedido='LISTO';
