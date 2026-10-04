BEGIN;
INSERT INTO auth.users VALUES('ac000000-0000-4000-8000-000000000001'),('ac000000-0000-4000-8000-000000000002'),('ac000000-0000-4000-8000-000000000003');
INSERT INTO public.empleados(usuario_id,local_id,rol) VALUES
 ('ac000000-0000-4000-8000-000000000001','caba0000-0000-4000-8000-000000000001','MOZO'),
 ('ac000000-0000-4000-8000-000000000002','caba0000-0000-4000-8000-000000000001','COCINA');
SELECT set_config('test.mesa',(SELECT id::text FROM public.mesas WHERE numero=1 LIMIT 1),true);
SELECT set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000001"}',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE p jsonb; r jsonb; items jsonb; BEGIN
 p:=public.abrir_pedido_mesa(current_setting('test.mesa')::uuid,'de000000-0000-4000-8000-000000000001');
 r:=public.abrir_pedido_mesa(current_setting('test.mesa')::uuid,'de000000-0000-4000-8000-000000000001');
 IF p->>'id'<>r->>'id' OR p->>'estado_pedido'<>'BORRADOR' OR p->'mesa'->>'estado'<>'OCUPADA' THEN RAISE EXCEPTION 'Apertura incorrecta'; END IF;
 PERFORM set_config('test.presencial',p->>'id',true);
 IF jsonb_array_length(public.listar_pedidos_mesa('caba0000-0000-4000-8000-000000000001'))<>1 THEN RAISE EXCEPTION 'Mapa sin orden activa'; END IF;
 BEGIN PERFORM public.abrir_pedido_mesa(current_setting('test.mesa')::uuid,'de000000-0000-4000-8000-000000000002'); RAISE EXCEPTION 'Mesa duplicada'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.enviar_pedido_caja((p->>'id')::uuid,1); RAISE EXCEPTION 'Orden vacía confirmada'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 items:='[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":2,"observaciones":"Papas aparte"}]';
 p:=public.editar_pedido_mesa((p->>'id')::uuid,1,items,'Sin mayonesa','Toma inicial');
 IF (p->>'total')::numeric<>119.80 OR p->'items'->0->>'observaciones'<>'Papas aparte' THEN RAISE EXCEPTION 'Snapshot/observación incorrectos'; END IF;
 BEGIN PERFORM public.editar_pedido_mesa((p->>'id')::uuid,1,items,'','Revisión obsoleta'); RAISE EXCEPTION 'Edición perdida'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.editar_pedido_mesa((p->>'id')::uuid,2,items,repeat('x',401),'Obs inválida'); RAISE EXCEPTION 'Observación excesiva'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 p:=public.enviar_pedido_caja((p->>'id')::uuid,2);
 IF p->>'estado_pedido'<>'PENDIENTE_PAGO' OR p->>'estado_pago'<>'PENDIENTE' OR p->'mesa'->>'estado'<>'POR_COBRAR' THEN RAISE EXCEPTION 'Envío a caja incorrecto'; END IF;
 p:=public.editar_pedido_mesa((p->>'id')::uuid,3,jsonb_set(items,'{0,quantity}','1'),'Sin mayonesa','Corrección de cantidad');
 IF (p->>'total')::numeric<>59.90 OR (p->>'revision')::integer<>4 THEN RAISE EXCEPTION 'Corrección incorrecta'; END IF;
 BEGIN UPDATE public.productos SET precio_base=1; RAISE EXCEPTION 'Mozo edita precios'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.auditoria_pedido WHERE pedido_id=current_setting('test.presencial')::uuid AND cantidad_anterior=2 AND cantidad_nueva=1 AND motivo='Corrección de cantidad') THEN RAISE EXCEPTION 'Auditoría incompleta'; END IF;
END $$;
SELECT set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000002"}',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.orden_operativa(current_setting('test.presencial')::uuid); RAISE EXCEPTION 'Cocina ve pedido sin pagar'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.editar_pedido_mesa(current_setting('test.presencial')::uuid,4,'[]','','No autorizado'); RAISE EXCEPTION 'Cocina edita'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"ac000000-0000-4000-8000-000000000003"}',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.pedido_de_mesa(current_setting('test.mesa')::uuid); RAISE EXCEPTION 'Cliente consulta mesa'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
