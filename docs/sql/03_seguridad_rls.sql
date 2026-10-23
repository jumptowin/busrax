-- =====================================================================
-- BUSRAX - Seguridad por filas (RLS)
-- Correr en Supabase > SQL Editor después de crear la base y cargar los datos.
-- Se puede volver a correr: primero borra las políticas existentes.
-- La aplicación usa la clave pública (anon). Con estas reglas:
--   * se pueden leer las tablas que muestra la aplicación;
--   * se puede dar de alta y modificar solo lo que registra la operación
--     (pedidos, movimientos, compras, hojas de ruta y entregas);
--   * el stock no se modifica directamente: solo a través de movimientos;
--   * no se puede borrar nada desde la API.
-- =====================================================================
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['proveedor','producto','deposito','ubicacion','stock','cliente','pedido',
    'detalle_pedido','orden_compra','detalle_orden_compra','movimiento_stock','vehiculo','chofer',
    'hoja_ruta','entrega'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public' AND policyname LIKE 'app_%' LOOP
    EXECUTE format('DROP POLICY %I ON public.%I', p.policyname, p.tablename);
  END LOOP;
END $$;

-- Lectura de todas las tablas
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['proveedor','producto','deposito','ubicacion','stock','cliente','pedido',
    'detalle_pedido','orden_compra','detalle_orden_compra','movimiento_stock','vehiculo','chofer',
    'hoja_ruta','entrega'] LOOP
    EXECUTE format('CREATE POLICY app_leer ON public.%I FOR SELECT TO anon, authenticated USING (true)', t);
  END LOOP;
END $$;

-- Altas
CREATE POLICY app_alta ON pedido               FOR INSERT TO anon, authenticated WITH CHECK (estado = 'PENDIENTE');
CREATE POLICY app_alta ON detalle_pedido       FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY app_alta ON movimiento_stock     FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY app_alta ON orden_compra         FOR INSERT TO anon, authenticated WITH CHECK (estado = 'PENDIENTE');
CREATE POLICY app_alta ON detalle_orden_compra FOR INSERT TO anon, authenticated WITH CHECK (true);
CREATE POLICY app_alta ON hoja_ruta            FOR INSERT TO anon, authenticated WITH CHECK (estado = 'PLANIFICADA');
CREATE POLICY app_alta ON entrega              FOR INSERT TO anon, authenticated WITH CHECK (estado = 'PENDIENTE');

-- Cambios de estado (no se modifican registros cerrados)
CREATE POLICY app_cambio ON pedido       FOR UPDATE TO anon, authenticated USING (estado NOT IN ('ENTREGADO','CANCELADO')) WITH CHECK (true);
CREATE POLICY app_cambio ON orden_compra FOR UPDATE TO anon, authenticated USING (estado = 'PENDIENTE') WITH CHECK (true);
CREATE POLICY app_cambio ON hoja_ruta    FOR UPDATE TO anon, authenticated USING (estado <> 'CERRADA') WITH CHECK (true);
CREATE POLICY app_cambio ON entrega      FOR UPDATE TO anon, authenticated USING (estado = 'PENDIENTE') WITH CHECK (true);

-- El stock solo cambia por los movimientos: el trigger corre con permisos del dueño
ALTER FUNCTION fn_aplicar_movimiento() SECURITY DEFINER SET search_path = public;

-- Sin vaciado de tablas desde la API
REVOKE TRUNCATE ON ALL TABLES IN SCHEMA public FROM anon, authenticated;

-- Las vistas respetan los permisos de quien consulta
ALTER VIEW v_stock_producto     SET (security_invoker = true);
ALTER VIEW v_ocupacion_deposito SET (security_invoker = true);
ALTER VIEW v_hojas_ruta         SET (security_invoker = true);
ALTER VIEW v_indicadores        SET (security_invoker = true);

-- Control: 15 tablas con rowsecurity = true
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;

