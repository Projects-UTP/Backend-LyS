# Cotización y pedidos — Sprint 3

`cotizar_pedido(p_items,p_modalidad,p_local_id)` es un RPC de lectura para anon/authenticated. Solo acepta identificador y cantidad de cada producto, rechaza dinero/descuentos enviados, UUID inválidos, cantidades fraccionarias/fuera de 1–50, duplicados, catálogo inactivo/no disponible y locales inactivos. Máximo treinta líneas por solicitud.

Los importes se calculan en numeric(12,2) a partir de precios del catálogo. La respuesta contiene el snapshot para revisar y una versión hash de la cotización; no acredita un pago. En delivery tanto costo como total definitivo son null, y se indica pendiente de confirmación; no se inventa una tarifa. En recojo total=subtotal y descuento=0. Los productos demo mantienen su indicador.

La función SECURITY DEFINER tiene search_path fijo y referencias de esquema explícitas. Se revoca EXECUTE de PUBLIC y se concede solo a roles de la aplicación. No otorga escritura sobre el catálogo. `tests/cotizacion.sql` prueba cálculos y entradas manipuladas en PostgreSQL efímero; el entorno aislado `lys-validacion` se utiliza para validar cambios antes del proyecto principal.
