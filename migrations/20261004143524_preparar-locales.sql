-- Solo información pública de sucursales; no contiene usuarios ni datos operativos.
CREATE TABLE public.locales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre text NOT NULL CHECK (length(trim(nombre)) BETWEEN 1 AND 120),
  direccion text NOT NULL CHECK (length(trim(direccion)) BETWEEN 1 AND 500),
  telefono text NOT NULL CHECK (telefono ~ '^\+[0-9]{8,15}$'),
  horario_desde time NOT NULL,
  horario_hasta time NOT NULL,
  zona_horaria text NOT NULL DEFAULT 'America/Lima',
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION public.actualizar_timestamp() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.actualizar_timestamp() FROM PUBLIC;
CREATE TRIGGER locales_actualizado BEFORE UPDATE ON public.locales
FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamp();

ALTER TABLE public.locales ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.locales FROM anon, authenticated;
GRANT SELECT ON public.locales TO anon, authenticated;
CREATE POLICY locales_publicos ON public.locales
FOR SELECT TO anon, authenticated USING (activo);
COMMENT ON TABLE public.locales IS 'Sucursales públicas; escritura solo por administración. Datos operativos usarán local_id.';
