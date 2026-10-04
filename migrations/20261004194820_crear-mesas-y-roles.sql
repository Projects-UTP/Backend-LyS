-- Las asignaciones se realizan con acceso administrativo, nunca desde el registro público.
CREATE TABLE public.empleados (
 usuario_id uuid NOT NULL REFERENCES auth.users(id),
 local_id uuid NOT NULL REFERENCES public.locales(id),
 rol text NOT NULL CHECK(rol IN ('MOZO','CAJA','COCINA','ADMINISTRADOR')),
 activo boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(usuario_id,local_id,rol)
);
CREATE INDEX empleados_local ON public.empleados(local_id);
ALTER TABLE public.empleados ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.empleados FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.empleados TO authenticated;
CREATE POLICY empleado_propio ON public.empleados FOR SELECT TO authenticated
 USING(usuario_id=(SELECT auth.uid()) AND activo);
CREATE FUNCTION public.permiso_local(p_local uuid,p_roles text[]) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM public.empleados WHERE usuario_id=auth.uid() AND local_id=p_local AND activo AND rol=ANY(p_roles))
$$;
REVOKE ALL ON FUNCTION public.permiso_local(uuid,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.permiso_local(uuid,text[]) TO authenticated;

CREATE TABLE public.mesas (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 local_id uuid NOT NULL REFERENCES public.locales(id),
 numero integer NOT NULL CHECK(numero>0),
 nombre text NOT NULL CHECK(length(nombre) BETWEEN 1 AND 80),
 zona text NOT NULL CHECK(length(zona) BETWEEN 1 AND 80),
 capacidad integer CHECK(capacidad BETWEEN 1 AND 100),
 estado text NOT NULL DEFAULT 'LIBRE' CHECK(estado IN ('LIBRE','OCUPADA','POR_COBRAR','RESERVADA','POR_LIMPIAR','INACTIVA')),
 activo boolean NOT NULL DEFAULT true,
 demostracion boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(local_id,numero)
);
CREATE TRIGGER mesas_actualizado BEFORE UPDATE ON public.mesas FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamp();
ALTER TABLE public.mesas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.mesas FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.mesas TO authenticated;
CREATE POLICY mesas_personal ON public.mesas FOR SELECT TO authenticated
 USING(public.permiso_local(local_id,ARRAY['MOZO','CAJA','ADMINISTRADOR']));
-- Seed configurable: no representa el plano ni aforo confirmado del restaurante.
INSERT INTO public.mesas(local_id,numero,nombre,zona,demostracion)
 SELECT 'caba0000-0000-4000-8000-000000000001',n,'Mesa '||lpad(n::text,2,'0'),'Salón de demostración',true
 FROM generate_series(1,20) n;
