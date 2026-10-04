# Backend-LyS

[Mesas, roles y provisionamiento seguro](docs/mesas-roles.md).

[Pedidos presenciales, revisión y auditoría](docs/pedidos-presenciales.md).

[Sesiones de caja y registro manual de pagos](docs/caja-pagos.md).

[Estados, KDS, entrega y anulación auditada](docs/estados-cocina.md).

Backend de Leñas y Sabores: PostgreSQL, Auth, Realtime, funciones, RLS y almacenamiento privado mediante InsForge.

El proyecto **LYS** está creado y vinculado localmente. Ver [configuración de InsForge](docs/insforge.md) y leer [AGENTS.md](AGENTS.md) antes de trabajar.

El estado Scrum se mantiene exclusivamente en `../SCRUM.md`.

Sprint 2 incorpora `categorias`, `productos` y `perfiles_cliente`, además del local confirmado de Carabayllo. El catálogo contiene siete categorías y tres productos de demostración con precios no oficiales. RLS permite leer únicamente categorías/productos activos y restringe el perfil a su propietario. Los clientes no pueden editar precios, asignarse roles ni leer otro perfil.

[Catálogo y semillas](docs/catalogo.md). [Perfiles privados y configuración Auth](docs/autenticacion.md). `insforge.toml` conserva verificación y recuperación por código y contraseña mínima de ocho caracteres; no incluye secretos. Las credenciales siguen en archivos locales ignorados.

`npm test` verifica las migraciones y ausencia de secretos. CI aplica todas las migraciones en PostgreSQL 17 efímero y comprueba RLS positiva/negativa de locales, catálogo y perfiles. `tests/bootstrap.sql` reproduce únicamente el contrato mínimo de Auth para CI; nunca se ejecuta sobre el esquema administrado de LYS.

Las migraciones aplicadas en LYS son aditivas y quedan registradas por la CLI. El correo de Auth usa el servicio administrado; la recepción externa requiere un buzón controlado. No se ha deshabilitado la verificación para simular pruebas.
