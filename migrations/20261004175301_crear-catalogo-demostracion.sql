-- El local está confirmado; los productos y sus precios son exclusivamente demostrativos.
INSERT INTO public.locales (id,nombre,direccion,telefono,horario_desde,horario_hasta)
VALUES ('caba0000-0000-4000-8000-000000000001','Leñas y Sabores — Carabayllo',
 'C. Turístico Los Palomares Mz. D Lt. 5, frente a la Planta Eléctrica San Benito, Carabayllo, Lima, Perú.',
 '+51947540597','12:00','00:00');

CREATE TABLE public.categorias (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 nombre text NOT NULL CHECK (length(trim(nombre)) BETWEEN 1 AND 100),
 slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
 descripcion text NOT NULL DEFAULT '',
 imagen_url text,
 orden integer NOT NULL DEFAULT 0,
 activo boolean NOT NULL DEFAULT true,
 demostracion boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.productos (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 categoria_id uuid NOT NULL REFERENCES public.categorias(id),
 nombre text NOT NULL CHECK (length(trim(nombre)) BETWEEN 1 AND 150),
 slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
 descripcion text NOT NULL CHECK (length(descripcion) <= 1500),
 precio_base numeric(10,2) NOT NULL CHECK (precio_base > 0 AND precio_base <= 10000),
 imagen_url text,
 activo boolean NOT NULL DEFAULT true,
 disponible boolean NOT NULL DEFAULT true,
 destacado boolean NOT NULL DEFAULT false,
 demostracion boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX productos_categoria ON public.productos(categoria_id);
CREATE TRIGGER categorias_actualizado BEFORE UPDATE ON public.categorias
 FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamp();
CREATE TRIGGER productos_actualizado BEFORE UPDATE ON public.productos
 FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamp();
ALTER TABLE public.categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.productos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.categorias,public.productos FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.categorias,public.productos TO anon,authenticated;
CREATE POLICY categorias_publicas ON public.categorias FOR SELECT TO anon,authenticated USING (activo);
CREATE POLICY productos_publicos ON public.productos FOR SELECT TO anon,authenticated
 USING (activo AND EXISTS (SELECT 1 FROM public.categorias c WHERE c.id=categoria_id AND c.activo));

INSERT INTO public.categorias(id,nombre,slug,imagen_url,orden) VALUES
 ('ca000000-0000-4000-8000-000000000001','Pollos a la brasa','pollos-a-la-brasa','/images/cat-pollos.webp',1),
 ('ca000000-0000-4000-8000-000000000002','Parrillas','parrillas','/images/cat-parrillas.webp',2),
 ('ca000000-0000-4000-8000-000000000003','Anticuchos','anticuchos','/images/fav-anticuchos.webp',3),
 ('ca000000-0000-4000-8000-000000000004','Acompañamientos','acompanamientos','/images/catalogo-v2-papas.webp',4),
 ('ca000000-0000-4000-8000-000000000005','Bebidas','bebidas','/images/cat-bebidas.webp',5),
 ('ca000000-0000-4000-8000-000000000006','Combos','combos','/images/cat-combos.webp',6),
 ('ca000000-0000-4000-8000-000000000007','Alitas','alitas','/images/cat-alitas.webp',7);
INSERT INTO public.productos(id,categoria_id,nombre,slug,descripcion,precio_base,imagen_url,destacado) VALUES
 ('ba000000-0000-4000-8000-000000000001','ca000000-0000-4000-8000-000000000001','Pollo entero','pollo-entero','Producto de demostración para compartir. Fotografía referencial; precio no oficial.',59.90,'/images/fav-pollo-entero.webp',true),
 ('ba000000-0000-4000-8000-000000000002','ca000000-0000-4000-8000-000000000001','Un cuarto de pollo','cuarto-pollo','Presentación individual de demostración. Fotografía referencial; precio no oficial.',19.90,'/images/fav-cuarto-pollo.webp',true),
 ('ba000000-0000-4000-8000-000000000003','ca000000-0000-4000-8000-000000000003','Anticuchos','anticuchos','Producto de demostración. Fotografía referencial; precio no oficial.',25.90,'/images/fav-anticuchos.webp',true);
COMMENT ON TABLE public.productos IS 'Catálogo de demostración sustituible. Precio autorizado por backend; sin inventario automático.';
