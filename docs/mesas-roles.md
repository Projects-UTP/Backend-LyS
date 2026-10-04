# ADR — Mesas y personal por local

`empleados` asigna usuario existente de InsForge Auth, local y rol (MOZO, CAJA, COCINA, ADMINISTRADOR). No se concede un rol al registrarse ni al editar el perfil. Solo credenciales administrativas pueden provisionar asignaciones después de confirmar identidad y local del personal. No crear usuarios ficticios en Auth de producción; los tests sintetizan únicamente el esquema Auth de CI efímero.

`permiso_local` consulta las asignaciones activas sin recursión RLS. Empleados solo lee sus asignaciones; mesas permite lectura operativa MOZO/CAJA/ADMINISTRADOR del mismo local. Ninguno tiene escritura directa de mesas, precios o permisos. Las futuras mutaciones se realizarán por RPC con verificación servidor.

Veinte mesas son seed de demostración configurable, sin capacidad inventada. La interfaz consulta registros y no depende de esta cantidad. El número es único por local, zona/nombre configurables; LIBRE, OCUPADA y POR_COBRAR forman el flujo inicial. Los demás estados están preparados y no se activan todavía.
