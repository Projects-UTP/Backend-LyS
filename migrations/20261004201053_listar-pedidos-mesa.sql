-- Una consulta por local actualiza el mapa completo sin una petición por mesa.
CREATE FUNCTION public.listar_pedidos_mesa(p_local uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
BEGIN
 IF NOT public.permiso_local(p_local,ARRAY['MOZO','CAJA','ADMINISTRADOR']) THEN RAISE EXCEPTION 'SIN_PERMISO' USING ERRCODE='42501'; END IF;
 RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('mesa_id',mesa_id,'codigo',codigo,'estado_pedido',estado_pedido,'estado_pago',estado_pago) ORDER BY created_at)
 FROM public.pedidos WHERE local_id=p_local AND mesa_id IS NOT NULL AND estado_pedido NOT IN ('FINALIZADO','ANULADO')),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.listar_pedidos_mesa(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.listar_pedidos_mesa(uuid) TO authenticated;
