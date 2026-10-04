#!/usr/bin/env bash
set -euo pipefail
test "$(psql -Atc 'select current_database()')" = lys_test
psql -v ON_ERROR_STOP=1 -f tests/concurrencia.sql
log_a=$(mktemp)
log_b=$(mktemp)
trap 'rm -f "$log_a" "$log_b"' EXIT
# Las dos sesiones compiten por el mismo pedido. La primera retiene el bloqueo
# para hacer reproducible la contención; la segunda espera y rechaza el doble pago.
psql -v ON_ERROR_STOP=1 >"$log_a" 2>&1 <<'SQL' &
BEGIN;
SELECT id FROM public.pedidos WHERE id=(SELECT pedido FROM public.fixture_concurrencia) FOR UPDATE;
SELECT pg_sleep(2);
SELECT set_config('request.jwt.claims','{"sub":"af000000-0000-4000-8000-000000000002"}',true);
SELECT public.registrar_pago(pedido,3,sesion_a,'EFECTIVO',20,NULL,gen_random_uuid(),true) FROM public.fixture_concurrencia;
COMMIT;
SQL
pid_a=$!
# El segundo proceso puede ganar si el planificador lo inicia antes. Ambas
# variantes deben producir exactamente una venta y un rechazo por pedido cobrado.
set +e
psql -v ON_ERROR_STOP=1 >"$log_b" 2>&1 <<'SQL'
BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"af000000-0000-4000-8000-000000000003"}',true);
SELECT public.registrar_pago(pedido,3,sesion_b,'EFECTIVO',20,NULL,gen_random_uuid(),true) FROM public.fixture_concurrencia;
COMMIT;
SQL
resultado_b=$?
wait "$pid_a"
resultado_a=$?
set -e
if test "$resultado_a" = 0 && test "$resultado_b" != 0; then
  grep -q PEDIDO_YA_COBRADO_O_INVALIDO "$log_b"
elif test "$resultado_b" = 0 && test "$resultado_a" != 0; then
  grep -q PEDIDO_YA_COBRADO_O_INVALIDO "$log_a"
else
  cat "$log_a" "$log_b"
  exit 1
fi
psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
 IF (SELECT count(*) FROM public.pagos WHERE pedido_id=(SELECT pedido FROM public.fixture_concurrencia))<>1
 OR(SELECT count(*) FROM public.movimientos_caja WHERE pago_id IN(SELECT id FROM public.pagos WHERE pedido_id=(SELECT pedido FROM public.fixture_concurrencia)))<>1
 OR NOT EXISTS(SELECT 1 FROM public.pedidos WHERE id=(SELECT pedido FROM public.fixture_concurrencia) AND estado_pago='APROBADO' AND estado_pedido='CONFIRMADO')
 THEN RAISE EXCEPTION 'Concurrencia duplicó o separó el cobro'; END IF;
END $$;
SQL
