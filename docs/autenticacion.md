# Perfiles privados y Auth

Auth de InsForge administra credenciales y sesiones; `perfiles_cliente.id` referencia `auth.users.id`. Los nombres, apellidos y celular pertenecen al perfil de negocio. El cliente no proporciona roles y no obtiene permisos operativos.

La migración `20261004180059_crear-perfiles-privados.sql` habilita RLS de propietario para SELECT/INSERT/UPDATE. Solo se permite editar nombres, apellidos y celular; identidad y timestamps permanecen protegidos. Anon no tiene acceso. No se concede DELETE desde la web.

`insforge.toml` conserva la verificación y recuperación por código y fija ocho caracteres mínimos de contraseña. La aplicación usa la cookie httpOnly y CSRF del SDK con proxy del mismo origen. La entrega de correo es administrada, sin SMTP ficticio ni verificaciones desactivadas.

CI ejecuta `tests/perfiles.sql` con dos usuarios sintéticos en PostgreSQL efímero: lectura propia, escritura válida y denegación de lectura/insert ajeno, cambio de identidad y acceso anónimo. `tests/bootstrap.sql` es exclusivamente de CI; no modifica el esquema administrado del proyecto LYS.
