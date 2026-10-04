-- Solo para PostgreSQL efímero de CI; todos los datos se revierten al terminar.
BEGIN;
INSERT INTO public.locales (nombre, direccion, telefono, horario_desde, horario_hasta, activo)
VALUES ('Local de prueba', 'Dirección de prueba', '+51900000000', '12:00', '00:00', true),
       ('Local oculto', 'Dirección de prueba', '+51900000001', '12:00', '00:00', false);
SET LOCAL ROLE anon;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.locales) <> 2 THEN RAISE EXCEPTION 'RLS permite ver locales inactivos'; END IF;
  BEGIN
    INSERT INTO public.locales (nombre, direccion, telefono, horario_desde, horario_hasta)
    VALUES ('No autorizado', 'Prueba', '+51900000000', '12:00', '00:00');
    RAISE EXCEPTION 'Escritura anónima permitida';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.locales) <> 2 THEN RAISE EXCEPTION 'RLS autenticado incorrecto'; END IF;
  BEGIN
    UPDATE public.locales SET nombre = 'No autorizado';
    RAISE EXCEPTION 'Actualización autenticada permitida';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
ROLLBACK;
