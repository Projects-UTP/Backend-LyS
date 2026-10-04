CREATE FUNCTION public.consultar_orden_operativa(p_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE resultado jsonb;p public.pedidos; BEGIN
 resultado:=public.orden_operativa(p_id);
 IF resultado IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO p FROM public.pedidos WHERE id=p_id;
 IF public.permiso_local(p.local_id,ARRAY['CAJA','ADMINISTRADOR']) THEN
 RETURN resultado||jsonb_build_object('cliente',p.nombres_contacto,'metodo_previsto',p.metodo_previsto);
 END IF;
 RETURN resultado;
END $$;
REVOKE ALL ON FUNCTION public.consultar_orden_operativa(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consultar_orden_operativa(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.resumen_caja(p_sesion uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE s public.sesiones_caja;ventas jsonb;total_ventas numeric(12,2);efectivo numeric(12,2);anulados numeric(12,2); BEGIN
 SELECT * INTO s FROM public.sesiones_caja WHERE id=p_sesion;
 IF NOT FOUND OR NOT((s.cajero_id=auth.uid() AND public.permiso_local(s.local_id,ARRAY['CAJA','ADMINISTRADOR'])) OR public.permiso_local(s.local_id,ARRAY['ADMINISTRADOR'])) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 IF s.estado='CERRADA' THEN RETURN s.resumen_cierre; END IF;
 SELECT coalesce(jsonb_object_agg(metodo,importe),'{}'::jsonb) INTO ventas FROM(SELECT metodo,sum(monto) importe FROM public.pagos WHERE sesion_id=s.id AND estado='APROBADO' GROUP BY metodo) v;
 SELECT coalesce(sum(monto) FILTER(WHERE estado='APROBADO'),0),coalesce(sum(monto) FILTER(WHERE metodo='EFECTIVO' AND estado IN ('APROBADO','ANULADO')),0),coalesce(sum(monto) FILTER(WHERE estado='ANULADO'),0)
 INTO total_ventas,efectivo,anulados FROM public.pagos WHERE sesion_id=s.id;
 -- Anular un registro no acredita una devolución: el efectivo recibido sigue en el esperado.
 RETURN jsonb_build_object('id',s.id,'local_id',s.local_id,'cajero_id',s.cajero_id,'estado',s.estado,'revision',s.revision,'opened_at',s.opened_at,'closed_at',s.closed_at,
 'monto_inicial',s.monto_inicial,'ventas',ventas,'total_ventas',total_ventas,'fondos_anulados',anulados,'efectivo_esperado',s.monto_inicial+efectivo,'total_esperado',s.monto_inicial+total_ventas+anulados);
END $$;
