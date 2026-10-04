BEGIN;
INSERT INTO auth.users VALUES('ad000000-0000-4000-8000-000000000001'),('ad000000-0000-4000-8000-000000000002'),('ad000000-0000-4000-8000-000000000003');
INSERT INTO public.empleados(usuario_id,local_id,rol) VALUES
 ('ad000000-0000-4000-8000-000000000001','caba0000-0000-4000-8000-000000000001','MOZO'),
 ('ad000000-0000-4000-8000-000000000002','caba0000-0000-4000-8000-000000000001','CAJA'),
 ('ad000000-0000-4000-8000-000000000003','caba0000-0000-4000-8000-000000000001','COCINA');
SET LOCAL ROLE authenticated;
DO $$ DECLARE ids uuid[]:='{}';p jsonb;s jsonb;r jsonb;repetido jsonb;clave uuid;metodo text;i integer; BEGIN
 PERFORM set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000001"}',true);
 FOR i IN 1..5 LOOP
 p:=public.abrir_pedido_mesa((SELECT id FROM public.mesas WHERE numero=i LIMIT 1),gen_random_uuid());
 p:=public.editar_pedido_mesa((p->>'id')::uuid,1,'[{"product_id":"ba000000-0000-4000-8000-000000000002","quantity":1}]','','Toma inicial');
 p:=public.enviar_pedido_caja((p->>'id')::uuid,2);ids:=array_append(ids,(p->>'id')::uuid);
 END LOOP;
 PERFORM set_config('test.fallo_pago',ids[5]::text,true);
 BEGIN PERFORM public.abrir_caja('caba0000-0000-4000-8000-000000000001',50,gen_random_uuid()); RAISE EXCEPTION 'Mozo abre caja'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000002"}',true);
 BEGIN PERFORM public.abrir_caja('caba0000-0000-4000-8000-000000000001','NaN'::numeric,gen_random_uuid()); RAISE EXCEPTION 'Inicial NaN aceptado'; EXCEPTION WHEN check_violation THEN NULL; END;
 clave:=gen_random_uuid();s:=public.abrir_caja('caba0000-0000-4000-8000-000000000001',50,clave);
 IF s->>'id'<>public.abrir_caja('caba0000-0000-4000-8000-000000000001',50,clave)->>'id' THEN RAISE EXCEPTION 'Apertura no idempotente'; END IF;
 PERFORM set_config('test.sesion_pago',s->>'id',true);
 BEGIN PERFORM public.registrar_pago(ids[1],3,(s->>'id')::uuid,'EFECTIVO',20,NULL,gen_random_uuid(),false); RAISE EXCEPTION 'Pago no confirmado'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.registrar_pago(ids[1],3,(s->>'id')::uuid,'EFECTIVO',19,NULL,gen_random_uuid(),true); RAISE EXCEPTION 'Efectivo insuficiente'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.registrar_pago(ids[1],3,(s->>'id')::uuid,'EFECTIVO',20.001,NULL,gen_random_uuid(),true); RAISE EXCEPTION 'Decimales imprecisos'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.registrar_pago(ids[1],3,(s->>'id')::uuid,'EFECTIVO','NaN'::numeric,NULL,gen_random_uuid(),true); RAISE EXCEPTION 'Recibido NaN aceptado'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM public.pagos WHERE pedido_id=ids[1]) OR public.orden_operativa(ids[1])->>'estado_pago'<>'PENDIENTE' THEN RAISE EXCEPTION 'Importe inválido deja pago parcial'; END IF;
 i:=0;
 FOREACH metodo IN ARRAY ARRAY['EFECTIVO','YAPE','PLIN','TARJETA_POS'] LOOP
 i:=i+1;clave:=gen_random_uuid();
 r:=public.registrar_pago(ids[i],3,(s->>'id')::uuid,metodo,CASE WHEN metodo='EFECTIVO' THEN 20 ELSE NULL END,'Referencia de prueba',clave,true);
 repetido:=public.registrar_pago(ids[i],3,(s->>'id')::uuid,metodo,CASE WHEN metodo='EFECTIVO' THEN 20 ELSE NULL END,'Referencia de prueba',clave,true);
 IF r->>'pago_id'<>repetido->>'pago_id' OR NOT(repetido->>'reutilizado')::boolean OR(r->>'monto')::numeric<>19.90 THEN RAISE EXCEPTION 'Pago/idempotencia incorrectos'; END IF;
 IF metodo='EFECTIVO' AND(r->>'vuelto')::numeric<>0.10 THEN RAISE EXCEPTION 'Vuelto impreciso'; END IF;
 p:=public.orden_operativa(ids[i]);
 IF p->>'estado_pago'<>'APROBADO' OR p->>'estado_pedido'<>'CONFIRMADO' THEN RAISE EXCEPTION 'Pago/pedido desincronizados'; END IF;
 BEGIN PERFORM public.registrar_pago(ids[i],3,(s->>'id')::uuid,metodo,CASE WHEN metodo='EFECTIVO' THEN 20 ELSE NULL END,NULL,gen_random_uuid(),true); RAISE EXCEPTION 'Doble cobro'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 s:=public.resumen_caja((s->>'id')::uuid);
 IF (s->>'total_ventas')::numeric<>79.60 OR(s->>'efectivo_esperado')::numeric<>69.90 OR(s->>'total_esperado')::numeric<>129.60 OR(s->'ventas'->>'PLIN')::numeric<>19.90 THEN RAISE EXCEPTION 'Resumen incorrecto'; END IF;
 IF NOT(public.consultar_orden_operativa(ids[1]) ? 'cliente') THEN RAISE EXCEPTION 'Caja no recibe metadatos individuales'; END IF;
 BEGIN UPDATE public.empleados SET rol='ADMINISTRADOR'; RAISE EXCEPTION 'Caja cambia permisos'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000001"}',true);
 IF public.consultar_orden_operativa(ids[1]) ? 'cliente' THEN RAISE EXCEPTION 'Mozo recibe contacto de caja'; END IF;
 BEGIN PERFORM public.registrar_pago(ids[5],3,(s->>'id')::uuid,'YAPE',NULL,NULL,gen_random_uuid(),true); RAISE EXCEPTION 'Mozo aprueba pago'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.editar_pedido_mesa(ids[1],4,'[{"product_id":"ba000000-0000-4000-8000-000000000002","quantity":2}]','','Corrección indebida'); RAISE EXCEPTION 'Mozo edita pagado'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000003"}',true);
 IF (SELECT count(id) FROM public.pagos)<>0 THEN RAISE EXCEPTION 'Cocina lee pagos'; END IF;
 BEGIN UPDATE public.productos SET precio_base=1; RAISE EXCEPTION 'Cocina edita precio'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
-- Un fallo posterior al pago revierte también el registro y el avance de la orden.
CREATE FUNCTION public.fallar_venta_ci() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Fallo de libro de caja' USING ERRCODE='23514'; END $$;
CREATE TRIGGER fallar_venta_ci BEFORE INSERT ON public.movimientos_caja FOR EACH ROW EXECUTE FUNCTION public.fallar_venta_ci();
SELECT set_config('request.jwt.claims','{"sub":"ad000000-0000-4000-8000-000000000002"}',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE p jsonb;s jsonb; BEGIN
 BEGIN PERFORM public.registrar_pago(current_setting('test.fallo_pago')::uuid,3,current_setting('test.sesion_pago')::uuid,'YAPE',NULL,NULL,gen_random_uuid(),true); RAISE EXCEPTION 'Fallo ignorado'; EXCEPTION WHEN check_violation THEN NULL; END;
 p:=public.orden_operativa(current_setting('test.fallo_pago')::uuid);
 IF p->>'estado_pago'<>'PENDIENTE' OR p->>'estado_pedido'<>'PENDIENTE_PAGO' OR EXISTS(SELECT 1 FROM public.pagos WHERE pedido_id=(p->>'id')::uuid) THEN RAISE EXCEPTION 'Cobro parcial persistido'; END IF;
 s:=public.mi_caja('caba0000-0000-4000-8000-000000000001');
 BEGIN PERFORM public.cerrar_caja((s->>'id')::uuid,1); RAISE EXCEPTION 'Cierre con revisión obsoleta'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 s:=public.cerrar_caja((s->>'id')::uuid,(s->>'revision')::integer);
 IF s->>'estado'<>'CERRADA' OR(s->>'total_ventas')::numeric<>79.60 THEN RAISE EXCEPTION 'Cierre incorrecto'; END IF;
 BEGIN PERFORM public.registrar_pago(current_setting('test.fallo_pago')::uuid,3,(s->>'id')::uuid,'YAPE',NULL,NULL,gen_random_uuid(),true); RAISE EXCEPTION 'Sesión cerrada acepta pago'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
ROLLBACK;
