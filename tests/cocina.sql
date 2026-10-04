BEGIN;
-- Identidades exclusivas del PostgreSQL efímero de CI; nunca se provisionan en LYS.
INSERT INTO auth.users VALUES ('ae000000-0000-4000-8000-000000000001'),('ae000000-0000-4000-8000-000000000002'),('ae000000-0000-4000-8000-000000000003'),('ae000000-0000-4000-8000-000000000004');
INSERT INTO public.empleados(usuario_id,local_id,rol) VALUES
 ('ae000000-0000-4000-8000-000000000001','caba0000-0000-4000-8000-000000000001','MOZO'),
 ('ae000000-0000-4000-8000-000000000002','caba0000-0000-4000-8000-000000000001','CAJA'),
 ('ae000000-0000-4000-8000-000000000003','caba0000-0000-4000-8000-000000000001','COCINA'),
 ('ae000000-0000-4000-8000-000000000004','caba0000-0000-4000-8000-000000000001','ADMINISTRADOR');
SET LOCAL ROLE authenticated;
DO $$ DECLARE p jsonb;s jsonb;r jsonb;id uuid;anulable uuid;pago uuid; BEGIN
 PERFORM set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000001"}',true);
 p:=public.abrir_pedido_mesa((SELECT m.id FROM public.mesas m WHERE numero=1 LIMIT 1),gen_random_uuid());id:=(p->>'id')::uuid;
 p:=public.editar_pedido_mesa(id,1,'[{"product_id":"ba000000-0000-4000-8000-000000000002","quantity":1,"observaciones":"Papas aparte"}]','Sin sal','Toma inicial');
 p:=public.enviar_pedido_caja(id,2);
 p:=public.abrir_pedido_mesa((SELECT m.id FROM public.mesas m WHERE numero=2 LIMIT 1),gen_random_uuid());anulable:=(p->>'id')::uuid;
 p:=public.editar_pedido_mesa(anulable,1,'[{"product_id":"ba000000-0000-4000-8000-000000000002","quantity":1}]','','Toma inicial');
 p:=public.enviar_pedido_caja(anulable,2);
 PERFORM set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000003"}',true);
 IF jsonb_array_length(public.cola_cocina('caba0000-0000-4000-8000-000000000001'))<>0 OR public.consultar_cocina(id) IS NOT NULL THEN RAISE EXCEPTION 'Cocina recibe impagado'; END IF;
 BEGIN PERFORM public.cambiar_estado_pedido(id,3,'EN_PREPARACION'); RAISE EXCEPTION 'Cocina inicia impagado'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.aplicar_transicion_pedido(id,3,'CONFIRMADO','Atajo'); RAISE EXCEPTION 'Función privada expuesta'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000002"}',true);
 s:=public.abrir_caja('caba0000-0000-4000-8000-000000000001',50,gen_random_uuid());
 BEGIN PERFORM public.registrar_pago(id,3,(s->>'id')::uuid,'TARJETA_POS',NULL,'4111111111111111',gen_random_uuid(),true); RAISE EXCEPTION 'PAN aceptado'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.registrar_pago(id,3,(s->>'id')::uuid,'TARJETA_POS',NULL,'CVV: 123',gen_random_uuid(),true); RAISE EXCEPTION 'CVV aceptado'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.registrar_pago(id,3,(s->>'id')::uuid,'TARJETA_POS',NULL,'4111 1111 1111 1111',gen_random_uuid(),true); RAISE EXCEPTION 'PAN separado aceptado'; EXCEPTION WHEN check_violation THEN NULL; END;
 r:=public.registrar_pago(id,3,(s->>'id')::uuid,'EFECTIVO',20,NULL,gen_random_uuid(),true);
 r:=public.registrar_pago(anulable,3,(s->>'id')::uuid,'EFECTIVO',20,NULL,gen_random_uuid(),true);pago:=(r->>'pago_id')::uuid;
 p:=public.orden_operativa(id);
 IF p->>'paid_at' IS NULL OR p->>'confirmed_at' IS NULL OR p->>'estado_pedido'<>'CONFIRMADO' THEN RAISE EXCEPTION 'Confirmación sin timestamps'; END IF;
 BEGIN PERFORM public.cambiar_estado_pedido(id,4,'EN_PREPARACION'); RAISE EXCEPTION 'Caja cocina'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.anular_pago(pago,'Pago duplicado',true); RAISE EXCEPTION 'Caja anula'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000003"}',true);
 IF jsonb_array_length(public.cola_cocina('caba0000-0000-4000-8000-000000000001'))<>2 THEN RAISE EXCEPTION 'Cola no recibe aprobados'; END IF;
 BEGIN PERFORM public.cambiar_estado_pedido(id,4,'LISTO'); RAISE EXCEPTION 'Salto de preparación'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.cambiar_estado_pedido(id,3,'EN_PREPARACION'); RAISE EXCEPTION 'Revisión vieja'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 p:=public.cambiar_estado_pedido(id,4,'EN_PREPARACION');
 IF p->>'preparation_started_at' IS NULL THEN RAISE EXCEPTION 'Preparación sin hora'; END IF;
 BEGIN PERFORM public.cambiar_estado_pedido(id,5,'CONFIRMADO'); RAISE EXCEPTION 'Retroceso'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 p:=public.cambiar_estado_pedido(id,5,'LISTO');
 IF p->>'ready_at' IS NULL OR p->'mesa'->>'estado'<>'OCUPADA' THEN RAISE EXCEPTION 'Mesa libre antes de entregar'; END IF;
 BEGIN PERFORM public.cambiar_estado_pedido(id,6,'ENTREGADO'); RAISE EXCEPTION 'Cocina entrega'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000001"}',true);
 IF jsonb_array_length(public.cola_listos('caba0000-0000-4000-8000-000000000001'))<>1 THEN RAISE EXCEPTION 'Mozo no recibe aviso'; END IF;
 p:=public.cambiar_estado_pedido(id,6,'ENTREGADO');
 IF p->>'estado_pedido'<>'FINALIZADO' OR p->>'delivered_at' IS NULL OR p->>'finalized_at' IS NULL OR p->'mesa'->>'estado'<>'LIBRE' THEN RAISE EXCEPTION 'Entrega no finaliza/libera'; END IF;
 BEGIN PERFORM public.anular_pago(pago,'Pago duplicado',true); RAISE EXCEPTION 'Mozo anula'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000004"}',true);
 p:=public.orden_operativa(anulable);
 IF(public.consultar_pago_administrador('caba0000-0000-4000-8000-000000000001',p->>'codigo')->>'puede_anular')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'Administrador no puede revisar'; END IF;
 BEGIN PERFORM public.anular_pago(pago,'',true); RAISE EXCEPTION 'Anulación sin motivo'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 r:=public.anular_pago(pago,'Operación anulada por administrador',true);
 IF r->>'estado'<>'ANULADO' OR public.anular_pago(pago,'Operación anulada por administrador',true)->>'reutilizado'<>'true' THEN RAISE EXCEPTION 'Anulación/idempotencia incorrecta'; END IF;
 p:=public.orden_operativa(anulable);
 IF public.consultar_pago_administrador('caba0000-0000-4000-8000-000000000001',p->>'codigo')->>'estado'<>'ANULADO' THEN RAISE EXCEPTION 'Consulta oculta anulación'; END IF;
 IF p->>'estado_pedido'<>'ANULADO' OR p->>'estado_pago'<>'ANULADO' OR p->'mesa'->>'estado'<>'LIBRE' THEN RAISE EXCEPTION 'Anulación incoherente'; END IF;
 s:=public.resumen_caja((s->>'id')::uuid);
 IF(s->>'total_ventas')::numeric<>19.90 OR(s->>'fondos_anulados')::numeric<>19.90 OR(s->>'efectivo_esperado')::numeric<>89.80 THEN RAISE EXCEPTION 'Anulación inventa devolución'; END IF;
 IF(SELECT count(*) FROM public.pagos)<>2 OR(SELECT count(*) FROM public.movimientos_caja)<>2 OR NOT EXISTS(SELECT 1 FROM public.auditoria_operativa WHERE pago_id=pago AND accion='PAGO_ANULADO' AND usuario_id=auth.uid() AND length(motivo)>3) THEN RAISE EXCEPTION 'Pago eliminado o sin auditoría'; END IF;
 PERFORM set_config('request.jwt.claims','{"sub":"ae000000-0000-4000-8000-000000000003"}',true);
 BEGIN PERFORM public.consultar_pago_administrador('caba0000-0000-4000-8000-000000000001',p->>'codigo'); RAISE EXCEPTION 'Cocina consulta anulación'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF jsonb_array_length(public.cola_cocina('caba0000-0000-4000-8000-000000000001'))<>0 OR public.consultar_cocina(id) IS NOT NULL THEN RAISE EXCEPTION 'KDS retiene finalizado'; END IF;
 BEGIN PERFORM public.cola_cocina('ffffffff-ffff-4fff-8fff-ffffffffffff'); RAISE EXCEPTION 'Cocina cruza local'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
