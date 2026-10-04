-- Una cotización nunca confía en precios ni totales suministrados por el cliente.
CREATE FUNCTION public.cotizar_pedido(p_items jsonb,p_modalidad text,p_local_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE item jsonb; ids uuid[] := '{}'; detalle jsonb; subtotal numeric(12,2); local_nombre text; resultado jsonb;
BEGIN
 IF p_modalidad IS NULL OR p_modalidad NOT IN ('RECOJO_LOCAL','DELIVERY') THEN RAISE EXCEPTION 'MODALIDAD_INVALIDA' USING ERRCODE='22023'; END IF;
 SELECT nombre INTO local_nombre FROM public.locales WHERE id=p_local_id AND activo;
 IF local_nombre IS NULL THEN RAISE EXCEPTION 'LOCAL_NO_DISPONIBLE' USING ERRCODE='22023'; END IF;
 IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'ITEMS_INVALIDOS' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_items) NOT BETWEEN 1 AND 30 THEN RAISE EXCEPTION 'ITEMS_INVALIDOS' USING ERRCODE='22023'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  IF jsonb_typeof(item) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'ITEM_INVALIDO' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(item) k WHERE k NOT IN ('product_id','quantity'))
    OR jsonb_typeof(item->'product_id') IS DISTINCT FROM 'string'
    OR coalesce(item->>'product_id','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    OR jsonb_typeof(item->'quantity') IS DISTINCT FROM 'number'
    OR coalesce(item->>'quantity','') !~ '^[0-9]{1,2}$'
  THEN RAISE EXCEPTION 'ITEM_INVALIDO' USING ERRCODE='22023'; END IF;
  IF (item->>'quantity')::integer NOT BETWEEN 1 AND 50 OR (item->>'product_id')::uuid=ANY(ids)
  THEN RAISE EXCEPTION 'CANTIDAD_INVALIDA_O_DUPLICADA' USING ERRCODE='22023'; END IF;
  ids := array_append(ids,(item->>'product_id')::uuid);
 END LOOP;
 IF (SELECT count(*) FROM public.productos p JOIN public.categorias c ON c.id=p.categoria_id
      WHERE p.id=ANY(ids) AND p.activo AND p.disponible AND c.activo)<>cardinality(ids)
 THEN RAISE EXCEPTION 'PRODUCTO_NO_DISPONIBLE' USING ERRCODE='22023'; END IF;
 SELECT jsonb_agg(jsonb_build_object('product_id',p.id,'nombre',p.nombre,'quantity',(i->>'quantity')::integer,
   'precio_unitario',p.precio_base,'subtotal',p.precio_base*(i->>'quantity')::integer,
   'demostracion',p.demostracion,'imagen_url',p.imagen_url) ORDER BY p.id),
   sum(p.precio_base*(i->>'quantity')::integer)
 INTO detalle,subtotal FROM jsonb_array_elements(p_items) i JOIN public.productos p ON p.id=(i->>'product_id')::uuid;
 resultado := jsonb_build_object('items',detalle,'subtotal',subtotal,'descuento',0,'modalidad',p_modalidad,
   'local_id',p_local_id,'local_nombre',local_nombre,
   'costo_delivery',CASE WHEN p_modalidad='DELIVERY' THEN NULL ELSE 0 END,
   'total',CASE WHEN p_modalidad='DELIVERY' THEN NULL ELSE subtotal END,
   'delivery_pendiente',p_modalidad='DELIVERY','demostracion',EXISTS(SELECT 1 FROM public.productos WHERE id=ANY(ids) AND demostracion));
 RETURN resultado || jsonb_build_object('version',md5(resultado::text));
END $$;
REVOKE ALL ON FUNCTION public.cotizar_pedido(jsonb,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cotizar_pedido(jsonb,text,uuid) TO anon,authenticated;
