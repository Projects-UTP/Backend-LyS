# Cotización y pedidos — Sprint 3

`cotizar_pedido(p_items,p_modalidad,p_local_id)` es un RPC de lectura para anon/authenticated. Solo acepta identificador y cantidad de cada producto, rechaza dinero/descuentos enviados, UUID inválidos, cantidades fraccionarias/fuera de 1–50, duplicados, catálogo inactivo/no disponible y locales inactivos. Máximo treinta líneas por solicitud.

Los importes se calculan en numeric(12,2) a partir de precios del catálogo. La respuesta contiene el snapshot para revisar y una versión hash de la cotización; no acredita un pago. En delivery tanto costo como total definitivo son null, y se indica pendiente de confirmación; no se inventa una tarifa. En recojo total=subtotal y descuento=0. Los productos demo mantienen su indicador.

La función SECURITY DEFINER tiene search_path fijo y referencias de esquema explícitas. Se revoca EXECUTE de PUBLIC y se concede solo a roles de la aplicación. No otorga escritura sobre el catálogo. `tests/cotizacion.sql` prueba cálculos y entradas manipuladas en PostgreSQL efímero; el entorno aislado `lys-validacion` se utiliza para validar cambios antes del proyecto principal.

## Creación transaccional

`crear_pedido_web(solicitud,version,idempotencia,acceso)` deriva el usuario de auth.uid(), valida contacto/modalidad/método, vuelve a cotizar y bloquea catálogo/local mientras guarda pedido+detalles+historial. Rechaza una versión de precio cambiada. El código LYS-000001 usa secuencia y UUID interno; puede haber huecos tras transacciones abortadas.

La identidad y UUID de idempotencia son únicos y tienen bloqueo transaccional; repetir el mismo intento devuelve el mismo pedido, mientras otro contenido con la misma clave falla. Los importes y nombres comprados permanecen como snapshot. Todos los pedidos quedan PENDIENTE_PAGO y pago PENDIENTE; la selección Yape/Plin/Tarjeta no acredita cobro. Origen WEB y local real mediante FK.

Anon no lee tablas ni inserta directamente. Los clientes autenticados solo leen su pedido/detalles/historial bajo RLS; no ven hashes de acceso o idempotencia. `consultar_pedido(codigo,acceso)` entrega únicamente resumen, sin contactos/direcciones privadas. Invitados necesitan una capacidad aleatoria de 256 bits que el servidor almacena como SHA-256 y vence a siete días. Código solo, token incorrecto, otro usuario y capacidad vencida no dan acceso.

La capacidad del invitado se conserva posteriormente en sessionStorage de su navegador, separada del carrito, sin datos personales y nunca en URL. Es un permiso limitado de lectura de un único resumen; quien la posea puede leerlo hasta su vencimiento. Producción debe añadir protección contra XSS, HTTPS y límites de abuso para crear pedidos públicos. JWT de Auth y contraseñas no se guardan ahí.

Pruebas SQL: invitado/registrado, snapshots tras cambio de precio, idempotencia, dinero externo, acceso ajeno/por código, hashes privados, expiración y fallo forzado de detalle con reversión total. Usuarios y trigger de fallo existen solo en PostgreSQL efímero de CI.
