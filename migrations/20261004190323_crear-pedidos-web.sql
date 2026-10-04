CREATE SEQUENCE public.numero_pedido;
CREATE FUNCTION public.nuevo_codigo_pedido() RETURNS text LANGUAGE plpgsql
SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE n text; BEGIN n:=nextval('public.numero_pedido')::text; RETURN 'LYS-'||lpad(n,greatest(6,length(n)),'0'); END $$;
REVOKE ALL ON SEQUENCE public.numero_pedido FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.nuevo_codigo_pedido() FROM PUBLIC;

CREATE TABLE public.pedidos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 codigo text NOT NULL UNIQUE DEFAULT public.nuevo_codigo_pedido(),
 local_id uuid NOT NULL REFERENCES public.locales(id),
 cliente_id uuid REFERENCES auth.users(id),
 tipo_cliente text NOT NULL CHECK(tipo_cliente IN ('REGISTRADO','INVITADO')),
 origen text NOT NULL DEFAULT 'WEB' CHECK(origen='WEB'),
 modalidad text NOT NULL CHECK(modalidad IN ('RECOJO_LOCAL','DELIVERY')),
 estado_pedido text NOT NULL DEFAULT 'PENDIENTE_PAGO' CONSTRAINT pedidos_estado_valido CHECK(estado_pedido='PENDIENTE_PAGO'),
 estado_pago text NOT NULL DEFAULT 'PENDIENTE' CONSTRAINT pedidos_pago_valido CHECK(estado_pago='PENDIENTE'),
 metodo_previsto text NOT NULL CHECK(metodo_previsto IN ('EFECTIVO','YAPE','PLIN','TARJETA')),
 subtotal numeric(12,2) NOT NULL CHECK(subtotal>0),
 descuento numeric(12,2) NOT NULL DEFAULT 0 CHECK(descuento=0),
 costo_delivery numeric(12,2) CHECK(costo_delivery>=0),
 total numeric(12,2) CHECK(total>0),
 nombres_contacto text NOT NULL CHECK(length(trim(nombres_contacto)) BETWEEN 2 AND 150),
 telefono_contacto text NOT NULL CHECK(telefono_contacto ~ '^9[0-9]{8}$'),
 correo_contacto text CHECK(correo_contacto IS NULL OR length(correo_contacto)<=254),
 direccion_delivery jsonb,
 latitud numeric(9,6),longitud numeric(9,6),zona_delivery text,
 demostracion boolean NOT NULL,
 idempotencia uuid NOT NULL,identidad_hash text NOT NULL,solicitud_hash text NOT NULL,
 acceso_hash text,acceso_expira timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(identidad_hash,idempotencia),
 CONSTRAINT pedidos_total_consistente CHECK((modalidad='RECOJO_LOCAL' AND costo_delivery=0 AND total=subtotal AND direccion_delivery IS NULL)
   OR (modalidad='DELIVERY' AND costo_delivery IS NULL AND total IS NULL AND direccion_delivery IS NOT NULL)),
 CHECK((tipo_cliente='REGISTRADO' AND cliente_id IS NOT NULL AND acceso_hash IS NULL)
   OR (tipo_cliente='INVITADO' AND cliente_id IS NULL AND acceso_hash IS NOT NULL AND acceso_expira IS NOT NULL))
);
CREATE INDEX pedidos_cliente ON public.pedidos(cliente_id,created_at DESC);
CREATE INDEX pedidos_local_estado ON public.pedidos(local_id,estado_pedido,created_at);
CREATE TABLE public.detalles_pedido (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),pedido_id uuid NOT NULL REFERENCES public.pedidos(id),
 producto_id uuid NOT NULL REFERENCES public.productos(id),nombre_producto text NOT NULL,
 cantidad integer NOT NULL CHECK(cantidad BETWEEN 1 AND 50),precio_unitario numeric(10,2) NOT NULL CHECK(precio_unitario>0),
 subtotal numeric(12,2) NOT NULL CHECK(subtotal=precio_unitario*cantidad),
 UNIQUE(pedido_id,producto_id)
);
CREATE INDEX detalles_producto ON public.detalles_pedido(producto_id);
CREATE TABLE public.historial_pedido (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),pedido_id uuid NOT NULL REFERENCES public.pedidos(id),
 usuario_id uuid REFERENCES auth.users(id),accion text NOT NULL,estado text NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX historial_pedido_fecha ON public.historial_pedido(pedido_id,created_at);
CREATE INDEX historial_usuario ON public.historial_pedido(usuario_id);
CREATE TRIGGER pedidos_actualizado BEFORE UPDATE ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamp();
ALTER TABLE public.pedidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.detalles_pedido ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historial_pedido ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pedidos,public.detalles_pedido,public.historial_pedido FROM PUBLIC,anon,authenticated;
-- Ni los hashes de acceso ni las claves de idempotencia se exponen en lecturas directas.
GRANT SELECT(id,codigo,local_id,cliente_id,tipo_cliente,origen,modalidad,estado_pedido,estado_pago,metodo_previsto,subtotal,descuento,costo_delivery,total,nombres_contacto,telefono_contacto,correo_contacto,direccion_delivery,demostracion,created_at,updated_at) ON public.pedidos TO authenticated;
GRANT SELECT ON public.detalles_pedido,public.historial_pedido TO authenticated;
CREATE POLICY pedido_propietario ON public.pedidos FOR SELECT TO authenticated USING(cliente_id=(SELECT auth.uid()));
CREATE POLICY detalles_propietario ON public.detalles_pedido FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.pedidos p WHERE p.id=pedido_id AND p.cliente_id=(SELECT auth.uid())));
CREATE POLICY historial_propietario ON public.historial_pedido FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.pedidos p WHERE p.id=pedido_id AND p.cliente_id=(SELECT auth.uid())));

CREATE FUNCTION public.crear_pedido_web(p_solicitud jsonb,p_version text,p_idempotencia uuid,p_acceso text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE uid uuid:=auth.uid(); identidad text; huella text; previo public.pedidos; cotizacion jsonb; contacto jsonb;
 direccion jsonb; pedido uuid; codigo_nuevo text; local uuid; modalidad_nueva text; elemento jsonb;
BEGIN
 IF jsonb_typeof(p_solicitud) IS DISTINCT FROM 'object' OR p_idempotencia IS NULL OR p_version IS NULL THEN RAISE EXCEPTION 'SOLICITUD_INVALIDA' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_solicitud) k WHERE k NOT IN ('items','modalidad','local_id','contacto','direccion','metodo_previsto')) THEN RAISE EXCEPTION 'CAMPOS_NO_PERMITIDOS' USING ERRCODE='22023'; END IF;
 IF uid IS NULL AND (p_acceso IS NULL OR p_acceso !~ '^[a-f0-9]{64}$') THEN RAISE EXCEPTION 'ACCESO_INVITADO_INVALIDO' USING ERRCODE='22023'; END IF;
 identidad:=CASE WHEN uid IS NOT NULL THEN 'usuario:'||uid::text ELSE 'invitado:'||encode(sha256(convert_to(p_acceso,'UTF8')),'hex') END;
 huella:=encode(sha256(convert_to(p_solicitud::text||p_version,'UTF8')),'hex');
 -- Serializamos el mismo intento antes de buscar/insertar, incluso con dos pestañas.
 PERFORM pg_advisory_xact_lock(hashtextextended(identidad||p_idempotencia::text,0));
 SELECT * INTO previo FROM public.pedidos WHERE identidad_hash=identidad AND idempotencia=p_idempotencia;
 IF FOUND THEN
  IF previo.solicitud_hash<>huella THEN RAISE EXCEPTION 'IDEMPOTENCIA_CONFLICTO' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('codigo',previo.codigo,'id',previo.id,'reutilizado',true);
 END IF;
 contacto:=p_solicitud->'contacto';
 IF jsonb_typeof(contacto) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'CONTACTO_INVALIDO' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(contacto) k WHERE k NOT IN ('nombres','celular','correo'))
  OR jsonb_typeof(contacto->'nombres') IS DISTINCT FROM 'string'
  OR length(trim(coalesce(contacto->>'nombres',''))) NOT BETWEEN 2 AND 150
  OR jsonb_typeof(contacto->'celular') IS DISTINCT FROM 'string'
  OR coalesce(contacto->>'celular','') !~ '^9[0-9]{8}$'
  OR (nullif(contacto->>'correo','') IS NOT NULL AND (length(contacto->>'correo')>254 OR contacto->>'correo' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'))
 THEN RAISE EXCEPTION 'CONTACTO_INVALIDO' USING ERRCODE='22023'; END IF;
 IF coalesce(p_solicitud->>'metodo_previsto','') NOT IN ('EFECTIVO','YAPE','PLIN','TARJETA') THEN RAISE EXCEPTION 'METODO_INVALIDO' USING ERRCODE='22023'; END IF;
 local:=(p_solicitud->>'local_id')::uuid;modalidad_nueva:=p_solicitud->>'modalidad';
 direccion:=p_solicitud->'direccion';
 IF modalidad_nueva='DELIVERY' THEN
  IF jsonb_typeof(direccion) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'DIRECCION_INVALIDA' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(direccion) k WHERE k NOT IN ('direccion','distrito','referencia'))
   OR jsonb_typeof(direccion->'direccion') IS DISTINCT FROM 'string'
   OR length(trim(coalesce(direccion->>'direccion',''))) NOT BETWEEN 5 AND 300
   OR jsonb_typeof(direccion->'distrito') IS DISTINCT FROM 'string'
   OR length(trim(coalesce(direccion->>'distrito',''))) NOT BETWEEN 2 AND 100
   OR jsonb_typeof(direccion->'referencia') IS DISTINCT FROM 'string'
   OR length(direccion->>'referencia')>300
  THEN RAISE EXCEPTION 'DIRECCION_INVALIDA' USING ERRCODE='22023'; END IF;
 ELSE
  IF direccion IS NOT NULL AND direccion<>'null'::jsonb THEN RAISE EXCEPTION 'DIRECCION_NO_CORRESPONDE' USING ERRCODE='22023'; END IF;
  direccion:=NULL;
 END IF;
 cotizacion:=public.cotizar_pedido(p_solicitud->'items',modalidad_nueva,local);
 -- Bloqueamos productos, categorías y local hasta guardar todos los snapshots.
 PERFORM p.id FROM public.productos p JOIN public.categorias c ON c.id=p.categoria_id
  WHERE p.id IN(SELECT (x->>'product_id')::uuid FROM jsonb_array_elements(p_solicitud->'items') x) ORDER BY p.id FOR SHARE OF p,c;
 PERFORM id FROM public.locales WHERE id=local FOR SHARE;
 cotizacion:=public.cotizar_pedido(p_solicitud->'items',modalidad_nueva,local);
 IF cotizacion->>'version'<>p_version THEN RAISE EXCEPTION 'COTIZACION_CAMBIO' USING ERRCODE='22023'; END IF;
 INSERT INTO public.pedidos(local_id,cliente_id,tipo_cliente,modalidad,metodo_previsto,subtotal,costo_delivery,total,
  nombres_contacto,telefono_contacto,correo_contacto,direccion_delivery,demostracion,idempotencia,identidad_hash,solicitud_hash,acceso_hash,acceso_expira)
 VALUES(local,uid,CASE WHEN uid IS NULL THEN 'INVITADO' ELSE 'REGISTRADO' END,modalidad_nueva,p_solicitud->>'metodo_previsto',
  (cotizacion->>'subtotal')::numeric,(cotizacion->>'costo_delivery')::numeric,(cotizacion->>'total')::numeric,
  trim(contacto->>'nombres'),contacto->>'celular',nullif(contacto->>'correo',''),direccion,(cotizacion->>'demostracion')::boolean,
  p_idempotencia,identidad,huella,CASE WHEN uid IS NULL THEN encode(sha256(convert_to(p_acceso,'UTF8')),'hex') END,
  CASE WHEN uid IS NULL THEN now()+interval '7 days' END) RETURNING id,codigo INTO pedido,codigo_nuevo;
 FOR elemento IN SELECT value FROM jsonb_array_elements(cotizacion->'items') LOOP
  INSERT INTO public.detalles_pedido(pedido_id,producto_id,nombre_producto,cantidad,precio_unitario,subtotal)
  VALUES(pedido,(elemento->>'product_id')::uuid,elemento->>'nombre',(elemento->>'quantity')::integer,
   (elemento->>'precio_unitario')::numeric,(elemento->>'subtotal')::numeric);
 END LOOP;
 INSERT INTO public.historial_pedido(pedido_id,usuario_id,accion,estado) VALUES(pedido,uid,'PEDIDO_CREADO','PENDIENTE_PAGO');
 RETURN jsonb_build_object('codigo',codigo_nuevo,'id',pedido,'reutilizado',false);
END $$;
REVOKE ALL ON FUNCTION public.crear_pedido_web(jsonb,text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crear_pedido_web(jsonb,text,uuid,text) TO anon,authenticated;

CREATE FUNCTION public.consultar_pedido(p_codigo text,p_acceso text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE p public.pedidos; detalle jsonb; historial jsonb; local jsonb;
BEGIN
 -- El código legible nunca basta para leer un pedido de invitado.
 SELECT * INTO p FROM public.pedidos WHERE codigo=p_codigo AND
  ((cliente_id=auth.uid() AND auth.uid() IS NOT NULL) OR
   (cliente_id IS NULL AND acceso_expira>now() AND p_acceso ~ '^[a-f0-9]{64}$' AND acceso_hash=encode(sha256(convert_to(p_acceso,'UTF8')),'hex')));
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT jsonb_agg(jsonb_build_object('producto_id',producto_id,'nombre_producto',nombre_producto,'cantidad',cantidad,'precio_unitario',precio_unitario,'subtotal',subtotal) ORDER BY producto_id)
 INTO detalle FROM public.detalles_pedido WHERE pedido_id=p.id;
 SELECT jsonb_agg(jsonb_build_object('accion',accion,'estado',estado,'created_at',created_at) ORDER BY created_at,id)
 INTO historial FROM public.historial_pedido WHERE pedido_id=p.id;
 SELECT jsonb_build_object('id',id,'nombre',nombre,'direccion',direccion,'telefono',telefono) INTO local FROM public.locales WHERE id=p.local_id;
 RETURN jsonb_build_object('codigo',p.codigo,'modalidad',p.modalidad,'estado_pedido',p.estado_pedido,'estado_pago',p.estado_pago,
  'metodo_previsto',p.metodo_previsto,'subtotal',p.subtotal,'descuento',p.descuento,'costo_delivery',p.costo_delivery,'total',p.total,
  'demostracion',p.demostracion,'created_at',p.created_at,'items',detalle,'historial',historial,'local',local);
END $$;
REVOKE ALL ON FUNCTION public.consultar_pedido(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consultar_pedido(text,text) TO anon,authenticated;
