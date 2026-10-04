-- numeric admite NaN: los límites de escala y CHECK >= 0 no lo excluyen solos.
-- Se protege toda la cadena monetaria, no únicamente el formulario de caja.
ALTER TABLE public.productos ADD CONSTRAINT producto_precio_finito CHECK(precio_base::text NOT IN ('NaN','Infinity','-Infinity'));
ALTER TABLE public.pedidos ADD CONSTRAINT pedido_importes_finitos CHECK(
 subtotal::text NOT IN ('NaN','Infinity','-Infinity') AND descuento::text NOT IN ('NaN','Infinity','-Infinity')
 AND (costo_delivery IS NULL OR costo_delivery::text NOT IN ('NaN','Infinity','-Infinity'))
 AND (total IS NULL OR total::text NOT IN ('NaN','Infinity','-Infinity')));
ALTER TABLE public.detalles_pedido ADD CONSTRAINT detalle_importes_finitos CHECK(precio_unitario::text NOT IN ('NaN','Infinity','-Infinity') AND subtotal::text NOT IN ('NaN','Infinity','-Infinity'));
ALTER TABLE public.sesiones_caja ADD CONSTRAINT sesion_inicial_finito CHECK(monto_inicial::text NOT IN ('NaN','Infinity','-Infinity'));
ALTER TABLE public.pagos ADD CONSTRAINT pago_importes_finitos CHECK(monto::text NOT IN ('NaN','Infinity','-Infinity') AND vuelto::text NOT IN ('NaN','Infinity','-Infinity') AND (recibido IS NULL OR recibido::text NOT IN ('NaN','Infinity','-Infinity')));
ALTER TABLE public.movimientos_caja ADD CONSTRAINT movimiento_importe_finito CHECK(monto::text NOT IN ('NaN','Infinity','-Infinity'));
