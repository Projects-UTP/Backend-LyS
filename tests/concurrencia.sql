-- Solo se ejecuta en el servicio PostgreSQL efímero del workflow.
DO $$ BEGIN IF current_database()<>'lys_test' THEN RAISE EXCEPTION 'Solo CI efímero'; END IF; END $$;
INSERT INTO auth.users VALUES('af000000-0000-4000-8000-000000000001'),('af000000-0000-4000-8000-000000000002'),('af000000-0000-4000-8000-000000000003');
INSERT INTO public.empleados(usuario_id,local_id,rol) VALUES
 ('af000000-0000-4000-8000-000000000001','caba0000-0000-4000-8000-000000000001','MOZO'),
 ('af000000-0000-4000-8000-000000000002','caba0000-0000-4000-8000-000000000001','CAJA'),
 ('af000000-0000-4000-8000-000000000003','caba0000-0000-4000-8000-000000000001','CAJA');
CREATE TABLE public.fixture_concurrencia(pedido uuid,sesion_a uuid,sesion_b uuid);
DO $$ DECLARE p jsonb;a jsonb;b jsonb; BEGIN
 PERFORM set_config('request.jwt.claims','{"sub":"af000000-0000-4000-8000-000000000001"}',true);
 p:=public.abrir_pedido_mesa((SELECT id FROM public.mesas WHERE numero=20 LIMIT 1),gen_random_uuid());
 p:=public.editar_pedido_mesa((p->>'id')::uuid,1,'[{"product_id":"ba000000-0000-4000-8000-000000000002","quantity":1}]','','Toma inicial');
 p:=public.enviar_pedido_caja((p->>'id')::uuid,2);
 PERFORM set_config('request.jwt.claims','{"sub":"af000000-0000-4000-8000-000000000002"}',true);
 a:=public.abrir_caja('caba0000-0000-4000-8000-000000000001',0,gen_random_uuid());
 PERFORM set_config('request.jwt.claims','{"sub":"af000000-0000-4000-8000-000000000003"}',true);
 b:=public.abrir_caja('caba0000-0000-4000-8000-000000000001',0,gen_random_uuid());
 INSERT INTO public.fixture_concurrencia VALUES((p->>'id')::uuid,(a->>'id')::uuid,(b->>'id')::uuid);
END $$;
