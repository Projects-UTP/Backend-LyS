# Estados, cocina y entrega

La matriz privada `transiciones_pedido` y `aplicar_transicion_pedido` concentran el avance de órdenes. Los roles se comprueban contra la asignación activa del usuario y local. Ningún cliente ejecuta la función privada ni actualiza directamente un estado.

`registrar_pago` acredita el pago y pasa a CONFIRMADO en la misma transacción del libro de caja. Cocina avanza CONFIRMADO → EN_PREPARACION → LISTO; mozo registra ENTREGADO y el servidor finaliza automáticamente consumo local/recojo. Mesa sigue ocupada en LISTO y solo se libera al finalizar. Delivery operativo continúa fuera del alcance.

Los RPC verifican la revisión optimista y la transición permitida bajo bloqueo de fila. Cada avance conserva actor, hora, motivo e historial, además de timestamps específicos de pago, confirmación, preparación, listo, entrega y finalización. KDS solo consulta órdenes pagadas del local asignado. La consulta individual devuelve null al salir de la cola para retirar tarjetas sin exponer impagados.

`anular_pago` requiere ADMINISTRADOR del local, confirmación explícita y motivo de 3–400 caracteres. Como no existen reglas de devolución confirmadas, solo permite anular antes de comenzar cocina y con la sesión abierta. Retiene pago, movimiento original y auditoría; los fondos permanecen en el saldo esperado hasta una devolución conciliada fuera de esta versión. Nunca declara un reembolso ni borra una venta.

Las referencias de operación rechazan secuencias similares a PAN y etiquetas CVV/CVC/PAN. No existen campos de tarjeta ni conexión a una pasarela. La boleta mantiene PENDIENTE_PROVEEDOR; no se anuncia emisión SUNAT.

La revisión por código humano usa `consultar_pago_administrador(local,codigo)`, solo para administrador activo del local. Muestra pago, estado, importe, fecha y motivo de anulación; nunca capacidad de invitado o datos de contacto. Índices parciales sirven las colas de pago, cocina y listos. La tabla rechaza además números de tarjeta separados por espacios/guiones.

`tests/cocina.sql` usa identidades sintéticas únicamente dentro de una transacción de PostgreSQL efímero de CI y revierte toda la operación.
