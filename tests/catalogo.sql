BEGIN;
INSERT INTO public.categorias(nombre,slug,activo) VALUES ('Oculta','oculta',false);
INSERT INTO public.productos(categoria_id,nombre,slug,descripcion,precio_base)
 SELECT id,'Producto oculto','oculto','Fixture',1 FROM public.categorias WHERE slug='oculta';
SET LOCAL ROLE anon;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.productos)<>3 THEN RAISE EXCEPTION 'Productos privados visibles'; END IF;
 IF EXISTS(SELECT 1 FROM public.categorias WHERE slug='oculta') THEN RAISE EXCEPTION 'Categoría privada visible'; END IF;
 BEGIN
  UPDATE public.productos SET precio_base=0.01;
  RAISE EXCEPTION 'Precio modificable por visitante';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
ROLLBACK;
