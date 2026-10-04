BEGIN;
SET LOCAL ROLE anon;
DO $$ DECLARE q jsonb; x jsonb; BEGIN
 q:=public.cotizar_pedido('[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":2}]','RECOJO_LOCAL','caba0000-0000-4000-8000-000000000001');
 IF (q->>'total')::numeric<>119.80 OR (q->>'subtotal')::numeric<>119.80 THEN RAISE EXCEPTION 'Precio incorrecto'; END IF;
 q:=public.cotizar_pedido('[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":1}]','DELIVERY','caba0000-0000-4000-8000-000000000001');
 IF q->>'total' IS NOT NULL OR q->>'costo_delivery' IS NOT NULL THEN RAISE EXCEPTION 'Tarifa inventada'; END IF;
 FOREACH x IN ARRAY ARRAY['[]'::jsonb,'[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":0}]'::jsonb,
 '[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":1,"precio":0.01}]'::jsonb,
 '[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":1.5}]'::jsonb,
 '[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":1},{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb,
 '[{"product_id":"ba000000-0000-4000-8000-000000000099","quantity":1}]'::jsonb] LOOP
  BEGIN
   PERFORM public.cotizar_pedido(x,'RECOJO_LOCAL','caba0000-0000-4000-8000-000000000001');
   RAISE EXCEPTION 'Entrada peligrosa aceptada';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
UPDATE public.productos SET disponible=false WHERE id='ba000000-0000-4000-8000-000000000001';
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN
  PERFORM public.cotizar_pedido('[{"product_id":"ba000000-0000-4000-8000-000000000001","quantity":1}]','RECOJO_LOCAL','caba0000-0000-4000-8000-000000000001');
  RAISE EXCEPTION 'Producto no disponible aceptado';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
RESET ROLE;
ROLLBACK;
