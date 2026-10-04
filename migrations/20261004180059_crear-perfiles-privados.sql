-- Identidad y contraseña pertenecen a InsForge Auth; estos son datos privados de negocio.
CREATE TABLE public.perfiles_cliente (
 id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 nombres text NOT NULL CHECK(length(trim(nombres)) BETWEEN 2 AND 100),
 apellidos text NOT NULL CHECK(length(trim(apellidos)) BETWEEN 2 AND 100),
 celular text NOT NULL CHECK(celular ~ '^9[0-9]{8}$'),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.perfiles_cliente ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.perfiles_cliente FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.perfiles_cliente TO authenticated;
GRANT INSERT(id,nombres,apellidos,celular) ON public.perfiles_cliente TO authenticated;
GRANT UPDATE(nombres,apellidos,celular) ON public.perfiles_cliente TO authenticated;
CREATE POLICY perfil_propio_lectura ON public.perfiles_cliente FOR SELECT TO authenticated USING(id=(SELECT auth.uid()));
CREATE POLICY perfil_propio_creacion ON public.perfiles_cliente FOR INSERT TO authenticated WITH CHECK(id=(SELECT auth.uid()));
CREATE POLICY perfil_propio_edicion ON public.perfiles_cliente FOR UPDATE TO authenticated USING(id=(SELECT auth.uid())) WITH CHECK(id=(SELECT auth.uid()));
CREATE TRIGGER perfil_actualizado BEFORE UPDATE ON public.perfiles_cliente FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamp();
COMMENT ON TABLE public.perfiles_cliente IS 'Perfil privado sin roles ni credenciales. Email se consulta exclusivamente en Auth.';
