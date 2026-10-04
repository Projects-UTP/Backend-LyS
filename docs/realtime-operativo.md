# Realtime operativo protegido

Canal exacto `lys-operativo:<local_uuid>:<rol>`, patrón administrado `lys-operativo:%`. La suscripción exige el rol exacto activo en ese local. Las políticas restrictivas continúan protegiendo los canales aunque aparezca una política permisiva posterior. Anónimo, cliente sin asignación, otro local u otro rol quedan denegados; los clientes tampoco publican ni ejecutan la función SECURITY DEFINER administrada `realtime.publish`.

Triggers de `public.pedidos` publican `pedido_actualizado` tras insertar/cambiar revisión, con id, local, mesa, revisión y estados. No hay contacto, dirección, importe ni capacidad de invitado en el evento. Cocina solo recibe órdenes aprobadas activas y su salida de cola. Frontend consulta la orden individual autorizada para actualizar su caché; un evento nunca acredita por sí mismo un pago.

Ante fallo de publicación se registra únicamente `LYS_REALTIME_PUBLICACION_FALLIDA`, sin datos del pedido ni detalle del proveedor. El cobro no se revierte por una falla de transporte: la recuperación/fallback vuelve a consultar estados reales. No hay triggers añadidos a tablas administradas de Realtime.

CI reproduce solo el contrato SQL mínimo del esquema administrado para probar RLS, payloads y publicación del trigger. Las pruebas de navegador simulan el protocolo de transporte; la comprobación de suscripción de personal real queda pendiente de cuentas y roles confirmados. No se crean identidades ficticias en LYS para suplirlas.
