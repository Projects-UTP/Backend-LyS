# ADR — Orden de mesa

Se reutilizan pedidos/detalles/historial: origen MOZO, modalidad CONSUMO_LOCAL, mesa y mozo como referencias. Abrir crea borrador vacío con total cero, ocupa la mesa y no inventa datos de contacto del cliente. Es invitado presencial: su capacidad interna aleatoria ya vencida nunca se entrega ni permite consulta pública por código. El personal consulta exclusivamente RPC autorizadas por local/rol, sin hashes privados.

Mesa bloqueada con FOR UPDATE y un índice único de pedido activo impiden doble apertura. La misma clave de apertura devuelve la orden anterior. Ediciones bloquean la orden, exigen revisión actual, recalculan precios de catálogo bloqueado y escriben auditoría (actor, acción, producto, cantidad anterior/nueva y motivo). Límites: 30 productos distintos, 1–50 unidades; observaciones 400 de orden y 240 por producto. Una orden no vacía se envía a caja: PENDIENTE_PAGO y mesa POR_COBRAR. Cocina no recibe órdenes pendientes.

Solo MOZO/ADMINISTRADOR del local pueden editar mientras pago PENDIENTE y estado BORRADOR/PENDIENTE_PAGO. No se conceden UPDATE directos. El futuro aviso LISTO usará estado de pedido, separado del estado de mesa. La orden abonada conservará snapshots y bloqueará edición libre.
