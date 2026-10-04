# Configuración de InsForge

Proyecto creado el 4 de octubre de 2026: **LYS**.

- ID: `7530444f-0a07-4688-8926-dace77de2c9d`.
- Organización personal de la cuenta autenticada.
- Región: `us-east`, elegida por proximidad geográfica entre las regiones disponibles; latencia real pendiente de medir desde Lima.
- API: `https://4rdisy8j.us-east.insforge.app`.
- Panel: <https://insforge.dev/dashboard/project/7530444f-0a07-4688-8926-dace77de2c9d>.
- Directorio vinculado: `Backend-LyS/`.
- Plantilla: `empty`, para mantener React separado del backend.

## Estado verificado

La consulta `npx -y @insforge/cli metadata --json` respondió correctamente. No hay tablas de aplicación, funciones, buckets ni canales de Realtime: se crearán por historia, mediante migraciones y políticas verificadas. No se han creado usuarios ni datos del negocio.

El primer intento de `projects get` devolvió 502 durante el arranque. La verificación posterior de metadata confirmó disponibilidad. La memoria semántica de InsForge requiere un plan de pago; las decisiones se conservan en los documentos locales. No se cambió el plan.

## Trabajo local

Desde este directorio:

```powershell
npx -y @insforge/cli current --json
npx -y @insforge/cli metadata --json
npx -y @insforge/cli docs db typescript
npx -y @insforge/cli secrets get ANON_KEY
```

La CLI guarda su vinculación administrativa en `.insforge/project.json`. No versionar ese directorio ni `.env.local`. El frontend recibe únicamente URL y `ANON_KEY`, con prefijo `VITE_`. Nunca compartir claves `uak_` ni API keys administrativas con React.

La creación generó `AGENTS.md` y registró las skills de InsForge disponibles en el entorno. Leer `insforge-cli` para infraestructura y `insforge` para código SDK; no suponer contratos de API.

## Próximas tareas

1. Definir locales, roles y membresías con permisos mínimos.
2. Escribir migraciones versionadas en este repositorio, con constraints, grants y RLS.
3. Verificar separación por `local_id` y denegación de acceso entre roles y locales.
4. Configurar Auth, orígenes y redirecciones para las URLs reales de desarrollo y despliegue.
5. Añadir canales privados y eventos al implementar pedidos y cocina.

## Reglas de seguridad

El backend valida precios, totales, descuentos, stock y estados de pago. Los permisos del cliente nunca son una autorización de servidor. No modificar objetos administrados de InsForge fuera de las operaciones documentadas. Usar branches de backend antes de cambios que afecten un entorno operativo.
