BEGIN;
INSERT INTO auth.users VALUES('aa000000-0000-4000-8000-000000000001'),('aa000000-0000-4000-8000-000000000002');
INSERT INTO public.perfiles_cliente(id,nombres,apellidos,celular) VALUES('aa000000-0000-4000-8000-000000000002','Otro','Cliente','900000002');
SELECT set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000001"}',true);
SET LOCAL ROLE authenticated;
INSERT INTO public.perfiles_cliente(id,nombres,apellidos,celular) VALUES('aa000000-0000-4000-8000-000000000001','Cliente','Prueba','900000001');
DO $$ BEGIN
 IF (SELECT count(*) FROM public.perfiles_cliente)<>1 THEN RAISE EXCEPTION 'Fuga de perfiles'; END IF;
 UPDATE public.perfiles_cliente SET nombres='Actualizado';
 BEGIN
  UPDATE public.perfiles_cliente SET id='aa000000-0000-4000-8000-000000000002';
  RAISE EXCEPTION 'Identidad modificable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO public.perfiles_cliente(id,nombres,apellidos,celular) VALUES('aa000000-0000-4000-8000-000000000002','Ajeno','Prueba','900000002');
  RAISE EXCEPTION 'Perfil ajeno modificable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN
  PERFORM * FROM public.perfiles_cliente;
  RAISE EXCEPTION 'Perfil visible sin sesión';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
ROLLBACK;
