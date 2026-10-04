BEGIN;
INSERT INTO auth.users VALUES('aa000000-0000-4000-8000-000000000001'),('aa000000-0000-4000-8000-000000000002');
SET LOCAL ROLE anon;
DO $$ DECLARE solicitud jsonb; q jsonb; r jsonb; repetido jsonb; resumen jsonb; BEGIN
 solicitud:='{"items":[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":2}],"modalidad":"RECOJO_LOCAL","local_id":"caba0000-0000-4000-8000-000000000001","contacto":{"nombres":"Invitado Prueba","celular":"900000001","correo":"invitado@example.test"},"metodo_previsto":"YAPE"}';
 q:=public.cotizar_pedido(solicitud->'items',solicitud->>'modalidad',(solicitud->>'local_id')::uuid);
 r:=public.crear_pedido_web(solicitud,q->>'version','dd000000-0000-4000-8000-000000000001',repeat('a',64));
 repetido:=public.crear_pedido_web(solicitud,q->>'version','dd000000-0000-4000-8000-000000000001',repeat('a',64));
 IF r->>'codigo' !~ '^LYS-[0-9]{6,}$' OR r->>'id'<>repetido->>'id' OR NOT (repetido->>'reutilizado')::boolean THEN RAISE EXCEPTION 'Idempotencia falló'; END IF;
 IF public.consultar_pedido(r->>'codigo') IS NOT NULL OR public.consultar_pedido(r->>'codigo',repeat('b',64)) IS NOT NULL THEN RAISE EXCEPTION 'Invitado expuesto por código'; END IF;
 resumen:=public.consultar_pedido(r->>'codigo',repeat('a',64));
 IF resumen->>'estado_pedido'<>'PENDIENTE_PAGO' OR resumen->>'estado_pago'<>'PENDIENTE' OR (resumen->>'total')::numeric<>119.80
  OR jsonb_array_length(resumen->'items')<>1 OR jsonb_array_length(resumen->'historial')<>1 THEN RAISE EXCEPTION 'Pedido incompleto'; END IF;
 PERFORM set_config('test.codigo_invitado',r->>'codigo',true);
 PERFORM set_config('test.version_antigua',q->>'version',true);
 BEGIN
  PERFORM public.crear_pedido_web(solicitud||'{"total":0.01}',q->>'version','dd000000-0000-4000-8000-000000000002',repeat('a',64));
  RAISE EXCEPTION 'Total externo aceptado';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM public.crear_pedido_web(jsonb_set(solicitud,'{contacto,nombres}','"Otra persona"'),q->>'version','dd000000-0000-4000-8000-000000000001',repeat('a',64));
  RAISE EXCEPTION 'Idempotencia permite otro contenido';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM codigo FROM public.pedidos; RAISE EXCEPTION 'Lectura anónima directa permitida'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE public.pedidos SET estado_pago='PENDIENTE'; RAISE EXCEPTION 'Escritura directa permitida'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000001"}',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE solicitud jsonb; q jsonb; r jsonb; BEGIN
 solicitud:='{"items":[{"product_id":"ba000000-0000-4000-8000-000000000002","quantity":1}],"modalidad":"DELIVERY","local_id":"caba0000-0000-4000-8000-000000000001","contacto":{"nombres":"Cliente Prueba","celular":"900000001"},"direccion":{"direccion":"Calle de prueba 123","distrito":"Carabayllo","referencia":"Puerta de prueba"},"metodo_previsto":"EFECTIVO"}';
 q:=public.cotizar_pedido(solicitud->'items',solicitud->>'modalidad',(solicitud->>'local_id')::uuid);
 r:=public.crear_pedido_web(solicitud,q->>'version','dd000000-0000-4000-8000-000000000003');
 IF (SELECT count(codigo) FROM public.pedidos)<>1 OR public.consultar_pedido(r->>'codigo')->>'total' IS NOT NULL THEN RAISE EXCEPTION 'RLS/Delivery incorrectos'; END IF;
 PERFORM set_config('test.codigo_cliente',r->>'codigo',true);
 BEGIN PERFORM acceso_hash FROM public.pedidos; RAISE EXCEPTION 'Hash expuesto'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000002"}',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF (SELECT count(codigo) FROM public.pedidos)<>0 OR public.consultar_pedido(current_setting('test.codigo_cliente')) IS NOT NULL
  OR (SELECT count(*) FROM public.detalles_pedido)<>0 THEN RAISE EXCEPTION 'Otro cliente ve el pedido'; END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{}',true);
UPDATE public.productos SET precio_base=64.90 WHERE id='ba000000-0000-4000-8000-000000000001';
SET LOCAL ROLE anon;
DO $$ DECLARE solicitud jsonb; resumen jsonb; BEGIN
 resumen:=public.consultar_pedido(current_setting('test.codigo_invitado'),repeat('a',64));
 IF (resumen->>'total')::numeric<>119.80 OR (resumen->'items'->0->>'precio_unitario')::numeric<>59.90 THEN RAISE EXCEPTION 'Snapshot alterado'; END IF;
 solicitud:='{"items":[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":2}],"modalidad":"RECOJO_LOCAL","local_id":"caba0000-0000-4000-8000-000000000001","contacto":{"nombres":"Invitado Prueba","celular":"900000001"},"metodo_previsto":"EFECTIVO"}';
 BEGIN
  PERFORM public.crear_pedido_web(solicitud,current_setting('test.version_antigua'),'dd000000-0000-4000-8000-000000000004',repeat('a',64));
  RAISE EXCEPTION 'Cambio de precio no detectado';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
RESET ROLE;
-- Un fallo al insertar detalles debe revertir también pedido e historial.
CREATE FUNCTION public.fallar_detalle_prueba() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Fallo de detalle de prueba' USING ERRCODE='23514'; END $$;
CREATE TRIGGER fallo_detalle BEFORE INSERT ON public.detalles_pedido FOR EACH ROW WHEN(NEW.nombre_producto='Anticuchos') EXECUTE FUNCTION public.fallar_detalle_prueba();
DO $$ DECLARE antes integer; q jsonb; solicitud jsonb; BEGIN
 antes:=(SELECT count(*) FROM public.pedidos);
 solicitud:='{"items":[{"product_id":"ba000000-0000-4000-8000-000000000003","quantity":1}],"modalidad":"RECOJO_LOCAL","local_id":"caba0000-0000-4000-8000-000000000001","contacto":{"nombres":"Invitado Prueba","celular":"900000001"},"metodo_previsto":"EFECTIVO"}';
 q:=public.cotizar_pedido(solicitud->'items',solicitud->>'modalidad',(solicitud->>'local_id')::uuid);
 BEGIN PERFORM public.crear_pedido_web(solicitud,q->>'version','dd000000-0000-4000-8000-000000000005',repeat('a',64)); EXCEPTION WHEN check_violation THEN NULL; END;
 IF (SELECT count(*) FROM public.pedidos)<>antes OR EXISTS(SELECT 1 FROM public.pedidos p WHERE NOT EXISTS(SELECT 1 FROM public.detalles_pedido d WHERE d.pedido_id=p.id)) THEN RAISE EXCEPTION 'Transacción incompleta'; END IF;
 UPDATE public.pedidos SET acceso_expira=now()-interval '1 second' WHERE codigo=current_setting('test.codigo_invitado');
 IF public.consultar_pedido(current_setting('test.codigo_invitado'),repeat('a',64)) IS NOT NULL THEN RAISE EXCEPTION 'Acceso vencido aceptado'; END IF;
END $$;
ROLLBACK;
