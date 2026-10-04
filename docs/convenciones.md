# Convenciones de infraestructura

- Tablas y campos de negocio en español, snake_case; tablas plurales.
- IDs UUID con `gen_random_uuid()`. Timestamps `created_at`/`updated_at` con zona (`timestamptz`), almacenados como instantes, presentación local America/Lima.
- Objetos de aplicación en `public`; no alterar esquemas administrados.
- Migraciones `migrations/<14 dígitos>_<nombre-kebab>.sql`, creadas con CLI, sin transacciones explícitas. No editar historia aplicada.
- Locales: solo información pública, SELECT de activos por anon/authenticated. Escritura administrativa; sin datos sensibles ni membresías en esta tabla.
- Multisucursal: los futuros pedidos, mesas, cajas e inventario referenciarán `locales(id)` mediante `local_id`. Roles/membresías se refinan en el Sprint de autenticación, antes de operaciones sensibles.
- Seeds: no cargar productos, precios ni cuentas inventadas. Pruebas usan datos efímeros con rollback; seeds de negocio requieren datos aprobados y una tarea propia.
- Auth, Realtime y funciones están disponibles en LYS; no crear canales, funciones o autenticación UI que pertenezcan a Sprints posteriores.
- Redirecciones y CORS: registrar únicamente orígenes reales al implementar Auth/despliegue; no habilitar comodines con credenciales. Backend administrado por InsForge; no añadir un proxy sin necesidad.
- Logs sin claves, tokens o datos personales. Auditoría de acciones operativas se implementará junto a esas historias.

## Validación

`npm test` valida higiene de migraciones y entorno. CI aplica SQL contra PostgreSQL 17 efímero y verifica RLS positivo/negativo con ambos roles. La CLI verifica metadata/migraciones del backend real; CI no usa secretos ni modifica la nube.
