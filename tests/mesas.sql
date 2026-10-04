BEGIN;
INSERT INTO auth.users VALUES('ab000000-0000-4000-8000-000000000001'),('ab000000-0000-4000-8000-000000000002');
INSERT INTO public.empleados(usuario_id,local_id,rol) VALUES('ab000000-0000-4000-8000-000000000001','caba0000-0000-4000-8000-000000000001','MOZO');
SELECT set_config('request.jwt.claims','{"sub":"ab000000-0000-4000-8000-000000000001"}',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.mesas)<>20 OR NOT public.permiso_local('caba0000-0000-4000-8000-000000000001',ARRAY['MOZO'])
 OR public.permiso_local('caba0000-0000-4000-8000-000000000001',ARRAY['CAJA'])
 OR public.permiso_local('caba0000-0000-4000-8000-000000000099',ARRAY['MOZO']) THEN RAISE EXCEPTION 'Alcance de rol/local incorrecto'; END IF;
 BEGIN UPDATE public.empleados SET rol='ADMINISTRADOR'; RAISE EXCEPTION 'Autoasignación permitida'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE public.mesas SET estado='LIBRE'; RAISE EXCEPTION 'Cambio directo permitido'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"ab000000-0000-4000-8000-000000000002"}',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.mesas)<>0 OR (SELECT count(*) FROM public.empleados)<>0 THEN RAISE EXCEPTION 'Cliente ve operación'; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM * FROM public.mesas; RAISE EXCEPTION 'Mesas públicas'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
