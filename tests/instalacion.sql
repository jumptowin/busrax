-- Reproduce la instalación en un esquema temporal de comprobación y lo revierte.
CREATE OR REPLACE FUNCTION pg_temp.busrax_verificar_instalacion() RETURNS jsonb LANGUAGE plpgsql AS $run$
DECLARE evidencia jsonb;
BEGIN
 BEGIN
  CREATE SCHEMA busrax_qa_instalacion;
  EXECUTE $bundle$-- BUSRAX. Solo para una base nueva y vacía. No elimina datos existentes.

SET LOCAL search_path=busrax_qa_instalacion;
DO $$ BEGIN IF to_regclass('busrax_qa_instalacion.producto') IS NOT NULL THEN RAISE EXCEPTION 'La base ya existe. Aplicá solo 04_mejoras_busrax.sql'; END IF; END $$;
CREATE TABLE proveedor (
  cuit          CHAR(11)     PRIMARY KEY CHECK (cuit ~ '^[0-9]{11}$'),
  razon_social  VARCHAR(120) NOT NULL,
  telefono      VARCHAR(30),
  plazo_entrega_dias SMALLINT NOT NULL DEFAULT 3 CHECK (plazo_entrega_dias > 0)
);

CREATE TABLE producto (
  sku              VARCHAR(20)  PRIMARY KEY,
  descripcion      VARCHAR(150) NOT NULL,
  unidad_medida    VARCHAR(10)  NOT NULL CHECK (unidad_medida IN ('UN','CAJA','KG','LT')),
  peso_unitario_kg NUMERIC(8,3) NOT NULL CHECK (peso_unitario_kg > 0),
  cuit_proveedor   CHAR(11)     NOT NULL REFERENCES proveedor(cuit),
  stock_minimo     INTEGER      NOT NULL DEFAULT 0  CHECK (stock_minimo >= 0),            -- punto de pedido
  lote_reposicion  INTEGER      NOT NULL DEFAULT 10 CHECK (lote_reposicion > 0)           -- cantidad a pedir
);

CREATE TABLE deposito (
  codigo     VARCHAR(10)  PRIMARY KEY,
  nombre     VARCHAR(80)  NOT NULL,
  direccion  VARCHAR(150) NOT NULL
);

CREATE TABLE ubicacion (
  codigo_deposito  VARCHAR(10) NOT NULL REFERENCES deposito(codigo) ON DELETE CASCADE,
  pasillo          VARCHAR(5)  NOT NULL,
  estante          SMALLINT    NOT NULL CHECK (estante > 0),
  nivel            SMALLINT    NOT NULL CHECK (nivel BETWEEN 1 AND 6),
  capacidad_unid   INTEGER     NOT NULL CHECK (capacidad_unid > 0),
  PRIMARY KEY (codigo_deposito, pasillo, estante, nivel)
);

CREATE TABLE stock (
  sku              VARCHAR(20) NOT NULL REFERENCES producto(sku),
  codigo_deposito  VARCHAR(10) NOT NULL,
  pasillo          VARCHAR(5)  NOT NULL,
  estante          SMALLINT    NOT NULL,
  nivel            SMALLINT    NOT NULL,
  cantidad         INTEGER     NOT NULL CHECK (cantidad >= 0),
  PRIMARY KEY (sku, codigo_deposito, pasillo, estante, nivel),
  FOREIGN KEY (codigo_deposito, pasillo, estante, nivel)
    REFERENCES ubicacion(codigo_deposito, pasillo, estante, nivel)
);

CREATE TABLE cliente (
  cuit               CHAR(11)     PRIMARY KEY CHECK (cuit ~ '^[0-9]{11}$'),
  razon_social       VARCHAR(120) NOT NULL,
  direccion_entrega  VARCHAR(150) NOT NULL,
  zona               VARCHAR(30)  NOT NULL
);

CREATE TABLE pedido (
  nro_pedido        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cuit_cliente      CHAR(11)    NOT NULL REFERENCES cliente(cuit),
  fecha             DATE        NOT NULL DEFAULT CURRENT_DATE,
  fecha_compromiso  DATE        NOT NULL DEFAULT CURRENT_DATE + 2,
  estado            VARCHAR(12) NOT NULL DEFAULT 'PENDIENTE'
                    CHECK (estado IN ('PENDIENTE','PREPARADO','DESPACHADO','ENTREGADO','RECHAZADO','CANCELADO')),
  CHECK (fecha_compromiso >= fecha)
);

CREATE TABLE detalle_pedido (
  nro_pedido  INTEGER     NOT NULL REFERENCES pedido(nro_pedido) ON DELETE CASCADE,
  sku         VARCHAR(20) NOT NULL REFERENCES producto(sku),
  cantidad    INTEGER     NOT NULL CHECK (cantidad > 0),
  PRIMARY KEY (nro_pedido, sku)
);

-- compras a proveedores (F1 Reposición)
CREATE TABLE orden_compra (
  nro_oc            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cuit_proveedor    CHAR(11)    NOT NULL REFERENCES proveedor(cuit),
  fecha             DATE        NOT NULL DEFAULT CURRENT_DATE,
  estado            VARCHAR(10) NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE','RECIBIDA','CANCELADA')),
  fecha_recepcion   DATE,
  CHECK ((estado = 'RECIBIDA') = (fecha_recepcion IS NOT NULL)),
  CHECK (fecha_recepcion IS NULL OR fecha_recepcion >= fecha)
);
CREATE TABLE detalle_orden_compra (
  nro_oc    INTEGER     NOT NULL REFERENCES orden_compra(nro_oc) ON DELETE CASCADE,
  sku       VARCHAR(20) NOT NULL REFERENCES producto(sku),
  cantidad  INTEGER     NOT NULL CHECK (cantidad > 0),
  PRIMARY KEY (nro_oc, sku)
);

-- movimientos de stock (F2 Trazabilidad). El stock se actualiza solo desde acá.
CREATE TABLE movimiento_stock (
  id_movimiento    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha_hora       TIMESTAMPTZ NOT NULL DEFAULT now(),
  tipo             VARCHAR(8)  NOT NULL CHECK (tipo IN ('INGRESO','EGRESO','AJUSTE')),
  sku              VARCHAR(20) NOT NULL REFERENCES producto(sku),
  codigo_deposito  VARCHAR(10) NOT NULL,
  pasillo          VARCHAR(5)  NOT NULL,
  estante          SMALLINT    NOT NULL,
  nivel            SMALLINT    NOT NULL,
  cantidad         INTEGER     NOT NULL CHECK (cantidad <> 0),
  nro_pedido       INTEGER REFERENCES pedido(nro_pedido),
  nro_oc           INTEGER REFERENCES orden_compra(nro_oc),
  observacion      VARCHAR(200),
  FOREIGN KEY (codigo_deposito, pasillo, estante, nivel)
    REFERENCES ubicacion(codigo_deposito, pasillo, estante, nivel),
  CHECK (tipo = 'AJUSTE' OR cantidad > 0),
  CHECK (tipo <> 'EGRESO' OR nro_pedido IS NOT NULL),
  CHECK (tipo <> 'AJUSTE' OR observacion IS NOT NULL)
);

CREATE TABLE vehiculo (
  patente        VARCHAR(9)   PRIMARY KEY CHECK (patente ~ '^([A-Z]{3}[0-9]{3}|[A-Z]{2}[0-9]{3}[A-Z]{2})$'),
  descripcion    VARCHAR(60)  NOT NULL,
  capacidad_kg   NUMERIC(8,1) NOT NULL CHECK (capacidad_kg > 0),
  activo         BOOLEAN      NOT NULL DEFAULT true
);

CREATE TABLE chofer (
  legajo               INTEGER      PRIMARY KEY CHECK (legajo > 0),
  nombre               VARCHAR(120) NOT NULL,
  licencia_vencimiento DATE         NOT NULL
);

-- hoja de ruta (F4 Planificación de rutas). Agrupa varias entregas de un viaje.
CREATE TABLE hoja_ruta (
  id_hoja             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha               DATE        NOT NULL DEFAULT CURRENT_DATE,
  patente             VARCHAR(9)  NOT NULL REFERENCES vehiculo(patente),
  legajo_chofer       INTEGER     NOT NULL REFERENCES chofer(legajo),
  estado              VARCHAR(11) NOT NULL DEFAULT 'PLANIFICADA' CHECK (estado IN ('PLANIFICADA','EN_CURSO','CERRADA')),
  fecha_hora_salida   TIMESTAMPTZ,
  fecha_hora_regreso  TIMESTAMPTZ,
  CHECK ((estado = 'PLANIFICADA') = (fecha_hora_salida IS NULL)),
  CHECK ((estado = 'CERRADA') = (fecha_hora_regreso IS NOT NULL)),
  CHECK (fecha_hora_regreso IS NULL OR fecha_hora_regreso > fecha_hora_salida)
);
CREATE UNIQUE INDEX un_hoja_en_curso_vehiculo ON hoja_ruta (patente)       WHERE estado = 'EN_CURSO';
CREATE UNIQUE INDEX un_hoja_en_curso_chofer   ON hoja_ruta (legajo_chofer) WHERE estado = 'EN_CURSO';

-- La entrega pertenece a una hoja de ruta, con orden de visita
CREATE TABLE entrega (
  id_entrega          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nro_pedido          INTEGER     NOT NULL UNIQUE REFERENCES pedido(nro_pedido),
  id_hoja             INTEGER     NOT NULL REFERENCES hoja_ruta(id_hoja) ON DELETE CASCADE,
  orden_visita        SMALLINT    NOT NULL CHECK (orden_visita > 0),
  estado              VARCHAR(10) NOT NULL DEFAULT 'PENDIENTE' CHECK (estado IN ('PENDIENTE','ENTREGADA','RECHAZADA')),
  fecha_hora_entrega  TIMESTAMPTZ,
  receptor            VARCHAR(120),
  motivo_rechazo      VARCHAR(200),
  UNIQUE (id_hoja, orden_visita),
  CHECK ((estado = 'PENDIENTE') = (fecha_hora_entrega IS NULL)),
  CHECK (estado <> 'ENTREGADA' OR receptor IS NOT NULL),
  CHECK (estado <> 'RECHAZADA' OR motivo_rechazo IS NOT NULL)
);

-- ===== Reglas automáticas =====
-- R1 Capacidad de cada ubicación
CREATE FUNCTION fn_controlar_capacidad_ubicacion() RETURNS trigger AS $$
DECLARE total INTEGER; cap INTEGER;
BEGIN
  SELECT COALESCE(SUM(cantidad),0) INTO total FROM stock
   WHERE codigo_deposito = NEW.codigo_deposito AND pasillo = NEW.pasillo AND estante = NEW.estante AND nivel = NEW.nivel;
  SELECT capacidad_unid INTO cap FROM ubicacion
   WHERE codigo_deposito = NEW.codigo_deposito AND pasillo = NEW.pasillo AND estante = NEW.estante AND nivel = NEW.nivel;
  IF total > cap THEN
    RAISE EXCEPTION 'La ubicacion %-%-%-% supera su capacidad (% de % unidades)',
      NEW.codigo_deposito, NEW.pasillo, NEW.estante, NEW.nivel, total, cap;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_capacidad_ubicacion AFTER INSERT OR UPDATE ON stock
FOR EACH ROW EXECUTE FUNCTION fn_controlar_capacidad_ubicacion();

-- R2 Cada movimiento actualiza el stock de la ubicación (si no alcanza, falla por cantidad >= 0)
CREATE FUNCTION fn_aplicar_movimiento() RETURNS trigger AS $$
DECLARE delta INTEGER := CASE WHEN NEW.tipo = 'EGRESO' THEN -NEW.cantidad ELSE NEW.cantidad END;
BEGIN
  UPDATE stock SET cantidad = cantidad + delta
   WHERE sku = NEW.sku AND codigo_deposito = NEW.codigo_deposito AND pasillo = NEW.pasillo
     AND estante = NEW.estante AND nivel = NEW.nivel;
  IF NOT FOUND THEN
    INSERT INTO stock (sku, codigo_deposito, pasillo, estante, nivel, cantidad)
    VALUES (NEW.sku, NEW.codigo_deposito, NEW.pasillo, NEW.estante, NEW.nivel, delta);
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_aplicar_movimiento AFTER INSERT ON movimiento_stock
FOR EACH ROW EXECUTE FUNCTION fn_aplicar_movimiento();

-- R3 Una orden de compra solo lleva productos de su proveedor
CREATE FUNCTION fn_controlar_detalle_oc() RETURNS trigger AS $$
BEGIN
  IF (SELECT cuit_proveedor FROM producto WHERE sku = NEW.sku)
     <> (SELECT cuit_proveedor FROM orden_compra WHERE nro_oc = NEW.nro_oc) THEN
    RAISE EXCEPTION 'El producto % no es de ese proveedor', NEW.sku;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_controlar_detalle_oc BEFORE INSERT OR UPDATE ON detalle_orden_compra
FOR EACH ROW EXECUTE FUNCTION fn_controlar_detalle_oc();

-- R4 La hoja de ruta usa un vehículo activo y un chofer con licencia vigente
CREATE FUNCTION fn_controlar_hoja_ruta() RETURNS trigger AS $$
BEGIN
  IF NOT (SELECT activo FROM vehiculo WHERE patente = NEW.patente) THEN
    RAISE EXCEPTION 'El vehiculo % no esta activo', NEW.patente;
  END IF;
  IF (SELECT licencia_vencimiento FROM chofer WHERE legajo = NEW.legajo_chofer) < NEW.fecha THEN
    RAISE EXCEPTION 'El chofer % tiene la licencia vencida', NEW.legajo_chofer;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_controlar_hoja_ruta BEFORE INSERT OR UPDATE OF patente, legajo_chofer, fecha ON hoja_ruta
FOR EACH ROW EXECUTE FUNCTION fn_controlar_hoja_ruta();

-- R5 Solo se cargan pedidos PREPARADOS y el peso total no supera la capacidad del vehículo
CREATE FUNCTION fn_controlar_entrega() RETURNS trigger AS $$
DECLARE est VARCHAR; peso NUMERIC; cap NUMERIC;
BEGIN
  SELECT estado INTO est FROM pedido WHERE nro_pedido = NEW.nro_pedido;
  IF est <> 'PREPARADO' THEN
    RAISE EXCEPTION 'El pedido % no esta PREPARADO (estado %)', NEW.nro_pedido, est;
  END IF;
  SELECT COALESCE(SUM(d.cantidad * p.peso_unitario_kg),0) INTO peso
    FROM detalle_pedido d JOIN producto p ON p.sku = d.sku
   WHERE d.nro_pedido = NEW.nro_pedido
      OR d.nro_pedido IN (SELECT nro_pedido FROM entrega WHERE id_hoja = NEW.id_hoja);
  SELECT v.capacidad_kg INTO cap FROM hoja_ruta h JOIN vehiculo v ON v.patente = h.patente WHERE h.id_hoja = NEW.id_hoja;
  IF peso > cap THEN
    RAISE EXCEPTION 'La carga de la hoja % seria de % kg y el vehiculo admite % kg', NEW.id_hoja, peso, cap;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_controlar_entrega BEFORE INSERT ON entrega
FOR EACH ROW EXECUTE FUNCTION fn_controlar_entrega();

-- ===== Vistas para las funciones logísticas =====
-- F1 Stock por producto y alerta de reposición
CREATE VIEW v_stock_producto AS
SELECT p.sku, p.descripcion, p.unidad_medida, p.stock_minimo, p.lote_reposicion,
       p.cuit_proveedor, pr.razon_social AS proveedor,
       COALESCE(SUM(s.cantidad),0)::int AS unidades,
       COALESCE(SUM(s.cantidad),0) <= p.stock_minimo AS a_reponer,
       EXISTS (SELECT 1 FROM detalle_orden_compra d JOIN orden_compra o ON o.nro_oc = d.nro_oc
                WHERE d.sku = p.sku AND o.estado = 'PENDIENTE') AS compra_en_curso
FROM producto p JOIN proveedor pr ON pr.cuit = p.cuit_proveedor
LEFT JOIN stock s ON s.sku = p.sku
GROUP BY p.sku, pr.razon_social;

-- F2 Ocupación de cada depósito
CREATE VIEW v_ocupacion_deposito AS
SELECT d.codigo, d.nombre,
       (SELECT SUM(capacidad_unid) FROM ubicacion u WHERE u.codigo_deposito = d.codigo)::int AS capacidad,
       COALESCE((SELECT SUM(cantidad) FROM stock s WHERE s.codigo_deposito = d.codigo),0)::int AS ocupado,
       ROUND(100.0 * COALESCE((SELECT SUM(cantidad) FROM stock s WHERE s.codigo_deposito = d.codigo),0)
             / NULLIF((SELECT SUM(capacidad_unid) FROM ubicacion u WHERE u.codigo_deposito = d.codigo),0),1) AS pct_ocupacion
FROM deposito d;

-- F4 Hojas de ruta con carga y aprovechamiento del vehículo
CREATE VIEW v_hojas_ruta AS
SELECT h.id_hoja, h.fecha, h.estado, h.patente, v.descripcion AS vehiculo, v.capacidad_kg,
       h.legajo_chofer, c.nombre AS chofer, h.fecha_hora_salida, h.fecha_hora_regreso,
       COUNT(DISTINCT e.id_entrega)::int AS entregas,
       COALESCE(SUM(d.cantidad * p.peso_unitario_kg),0) AS carga_kg,
       ROUND(100 * COALESCE(SUM(d.cantidad * p.peso_unitario_kg),0) / v.capacidad_kg, 1) AS pct_carga
FROM hoja_ruta h JOIN vehiculo v ON v.patente = h.patente JOIN chofer c ON c.legajo = h.legajo_chofer
LEFT JOIN entrega e ON e.id_hoja = h.id_hoja
LEFT JOIN detalle_pedido d ON d.nro_pedido = e.nro_pedido
LEFT JOIN producto p ON p.sku = d.sku
GROUP BY h.id_hoja, v.descripcion, v.capacidad_kg, c.nombre;

-- F5 Indicadores de gestión
CREATE VIEW v_indicadores AS
SELECT
  (SELECT COUNT(*) FROM pedido WHERE estado IN ('PENDIENTE','PREPARADO'))               AS pedidos_abiertos,
  (SELECT COUNT(*) FROM entrega WHERE estado = 'ENTREGADA')                             AS entregas_realizadas,
  (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE e.fecha_hora_entrega::date <= p.fecha_compromiso) / NULLIF(COUNT(*),0), 1)
     FROM entrega e JOIN pedido p ON p.nro_pedido = e.nro_pedido WHERE e.estado = 'ENTREGADA') AS pct_entregas_a_tiempo,
  (SELECT COUNT(*) FROM entrega WHERE estado = 'RECHAZADA')                             AS entregas_rechazadas,
  (SELECT COUNT(*) FROM v_stock_producto WHERE a_reponer)                               AS productos_a_reponer,
  (SELECT COUNT(*) FROM orden_compra WHERE estado = 'PENDIENTE')                        AS compras_pendientes,
  (SELECT ROUND(100.0 * SUM(ocupado) / NULLIF(SUM(capacidad),0), 1) FROM v_ocupacion_deposito) AS pct_ocupacion_total;

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
    EXECUTE format('ALTER TABLE busrax_qa_instalacion.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'busrax_qa_instalacion' AND policyname LIKE 'app_%' LOOP
    EXECUTE format('DROP POLICY %I ON busrax_qa_instalacion.%I', p.policyname, p.tablename);
  END LOOP;
END $$;

-- Lectura de todas las tablas
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['proveedor','producto','deposito','ubicacion','stock','cliente','pedido',
    'detalle_pedido','orden_compra','detalle_orden_compra','movimiento_stock','vehiculo','chofer',
    'hoja_ruta','entrega'] LOOP
    EXECUTE format('CREATE POLICY app_leer ON busrax_qa_instalacion.%I FOR SELECT TO anon, authenticated USING (true)', t);
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
ALTER FUNCTION fn_aplicar_movimiento() SECURITY DEFINER SET search_path = busrax_qa_instalacion;

-- Sin vaciado de tablas desde la API
REVOKE TRUNCATE ON ALL TABLES IN SCHEMA busrax_qa_instalacion FROM anon, authenticated;

-- Las vistas respetan los permisos de quien consulta
ALTER VIEW v_stock_producto     SET (security_invoker = true);
ALTER VIEW v_ocupacion_deposito SET (security_invoker = true);
ALTER VIEW v_hojas_ruta         SET (security_invoker = true);
ALTER VIEW v_indicadores        SET (security_invoker = true);

-- Control: 15 tablas con rowsecurity = true
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'busrax_qa_instalacion' ORDER BY tablename;


-- BUSRAX. Actualización sobre la base existente, sin borrar tablas ni datos.
-- Las operaciones compuestas se confirman en una sola transacción.

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.fn_aplicar_movimiento() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE delta integer := CASE WHEN NEW.tipo = 'EGRESO' THEN -NEW.cantidad ELSE NEW.cantidad END;
BEGIN
  -- Serializa las modificaciones de una misma ubicación, incluso de SKU distintos.
  PERFORM 1 FROM busrax_qa_instalacion.ubicacion u WHERE u.codigo_deposito=NEW.codigo_deposito
    AND u.pasillo=NEW.pasillo AND u.estante=NEW.estante AND u.nivel=NEW.nivel FOR UPDATE;
  UPDATE busrax_qa_instalacion.stock SET cantidad=cantidad+delta WHERE sku=NEW.sku
    AND codigo_deposito=NEW.codigo_deposito AND pasillo=NEW.pasillo
    AND estante=NEW.estante AND nivel=NEW.nivel;
  IF NOT FOUND THEN
    INSERT INTO busrax_qa_instalacion.stock(sku,codigo_deposito,pasillo,estante,nivel,cantidad)
    VALUES(NEW.sku,NEW.codigo_deposito,NEW.pasillo,NEW.estante,NEW.nivel,delta);
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION busrax_qa_instalacion.fn_aplicar_movimiento() FROM PUBLIC, anon, authenticated;

ALTER FUNCTION busrax_qa_instalacion.fn_controlar_capacidad_ubicacion() SET search_path=busrax_qa_instalacion,pg_temp;
ALTER FUNCTION busrax_qa_instalacion.fn_controlar_detalle_oc() SET search_path=busrax_qa_instalacion,pg_temp;
ALTER FUNCTION busrax_qa_instalacion.fn_controlar_hoja_ruta() SET search_path=busrax_qa_instalacion,pg_temp;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.fn_controlar_entrega() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE est text; h_estado text; peso numeric; cap numeric;
BEGIN
  SELECT estado INTO h_estado FROM busrax_qa_instalacion.hoja_ruta WHERE id_hoja=NEW.id_hoja FOR UPDATE;
  IF h_estado IS DISTINCT FROM 'PLANIFICADA' THEN RAISE EXCEPTION 'Solo se agregan pedidos a hojas PLANIFICADAS'; END IF;
  SELECT estado INTO est FROM busrax_qa_instalacion.pedido WHERE nro_pedido=NEW.nro_pedido FOR UPDATE;
  IF est IS DISTINCT FROM 'PREPARADO' THEN RAISE EXCEPTION 'El pedido no está PREPARADO'; END IF;
  SELECT COALESCE(sum(d.cantidad*p.peso_unitario_kg),0) INTO peso
    FROM busrax_qa_instalacion.detalle_pedido d JOIN busrax_qa_instalacion.producto p ON p.sku=d.sku
    WHERE d.nro_pedido=NEW.nro_pedido OR d.nro_pedido IN
      (SELECT e.nro_pedido FROM busrax_qa_instalacion.entrega e WHERE e.id_hoja=NEW.id_hoja);
  SELECT v.capacidad_kg INTO cap FROM busrax_qa_instalacion.hoja_ruta h JOIN busrax_qa_instalacion.vehiculo v ON v.patente=h.patente WHERE h.id_hoja=NEW.id_hoja;
  IF peso>cap THEN RAISE EXCEPTION 'La carga de % kg supera la capacidad de % kg',peso,cap; END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.busrax_crear_pedido(p_cliente text,p_fecha date,p_lineas jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE n integer; l jsonb;
BEGIN
  IF p_fecha IS NULL OR p_fecha<CURRENT_DATE THEN RAISE EXCEPTION 'La fecha de entrega debe ser hoy o posterior'; END IF;
  IF jsonb_typeof(p_lineas) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lineas) NOT BETWEEN 1 AND 50
    THEN RAISE EXCEPTION 'El pedido debe tener entre 1 y 50 renglones'; END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(p_lineas)) <>
     (SELECT count(DISTINCT item.value->>'sku') FROM jsonb_array_elements(p_lineas) AS item(value))
    THEN RAISE EXCEPTION 'No se permiten productos repetidos ni vacíos'; END IF;
  INSERT INTO busrax_qa_instalacion.pedido(cuit_cliente,fecha_compromiso) VALUES(p_cliente,p_fecha) RETURNING nro_pedido INTO n;
  FOR l IN SELECT value FROM jsonb_array_elements(p_lineas) LOOP
    IF l->>'cantidad' IS NULL OR (l->>'cantidad') !~ '^[1-9][0-9]*$'
      THEN RAISE EXCEPTION 'Las cantidades deben ser enteros positivos'; END IF;
    INSERT INTO busrax_qa_instalacion.detalle_pedido(nro_pedido,sku,cantidad) VALUES(n,l->>'sku',(l->>'cantidad')::integer);
  END LOOP;
  RETURN n;
END; $$;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.busrax_reponer(p_sku text)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE p busrax_qa_instalacion.producto; n integer; disponible integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('busrax:compra:'||p_sku,0));
  SELECT * INTO p FROM busrax_qa_instalacion.producto WHERE sku=p_sku;
  IF NOT FOUND THEN RAISE EXCEPTION 'Producto inexistente'; END IF;
  SELECT COALESCE(sum(cantidad),0) INTO disponible FROM busrax_qa_instalacion.stock WHERE sku=p_sku;
  IF disponible>p.stock_minimo THEN RAISE EXCEPTION 'El producto ya está por encima del mínimo'; END IF;
  IF EXISTS(SELECT 1 FROM busrax_qa_instalacion.detalle_orden_compra d JOIN busrax_qa_instalacion.orden_compra o USING(nro_oc)
    WHERE d.sku=p_sku AND o.estado='PENDIENTE') THEN RAISE EXCEPTION 'Ya hay una compra pendiente para este producto'; END IF;
  INSERT INTO busrax_qa_instalacion.orden_compra(cuit_proveedor) VALUES(p.cuit_proveedor) RETURNING nro_oc INTO n;
  INSERT INTO busrax_qa_instalacion.detalle_orden_compra(nro_oc,sku,cantidad) VALUES(n,p_sku,p.lote_reposicion);
  RETURN n;
END; $$;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.busrax_recibir_compra(p_compra integer,p_lineas jsonb)
RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE o busrax_qa_instalacion.orden_compra; l jsonb; pendiente integer; recibida integer; estado_final text;
BEGIN
  SELECT * INTO o FROM busrax_qa_instalacion.orden_compra WHERE nro_oc=p_compra FOR UPDATE;
  IF NOT FOUND OR o.estado<>'PENDIENTE' THEN RAISE EXCEPTION 'La compra ya no está pendiente'; END IF;
  IF jsonb_typeof(p_lineas) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lineas) NOT BETWEEN 1 AND 50
    THEN RAISE EXCEPTION 'Indicá al menos un ingreso'; END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(p_lineas)) <>
     (SELECT count(DISTINCT item.value->>'sku') FROM jsonb_array_elements(p_lineas) AS item(value))
    THEN RAISE EXCEPTION 'No se permiten productos repetidos'; END IF;
  FOR l IN SELECT value FROM jsonb_array_elements(p_lineas) ORDER BY value->>'codigo_deposito',value->>'pasillo',value->>'estante',value->>'nivel' LOOP
    IF l->>'cantidad' IS NULL OR (l->>'cantidad') !~ '^[1-9][0-9]*$' THEN RAISE EXCEPTION 'El ingreso debe ser un entero positivo'; END IF;
    SELECT d.cantidad-COALESCE((SELECT sum(m.cantidad) FROM busrax_qa_instalacion.movimiento_stock m
      WHERE m.nro_oc=p_compra AND m.sku=d.sku AND m.tipo='INGRESO'),0)
      INTO pendiente FROM busrax_qa_instalacion.detalle_orden_compra d WHERE d.nro_oc=p_compra AND d.sku=l->>'sku';
    IF pendiente IS NULL THEN RAISE EXCEPTION 'El producto no pertenece a esta compra'; END IF;
    recibida:=(l->>'cantidad')::integer;
    IF recibida>pendiente THEN RAISE EXCEPTION 'Solo quedan % unidades por recibir de %',pendiente,l->>'sku'; END IF;
    INSERT INTO busrax_qa_instalacion.movimiento_stock(tipo,sku,codigo_deposito,pasillo,estante,nivel,cantidad,nro_oc,observacion)
      VALUES('INGRESO',l->>'sku',l->>'codigo_deposito',l->>'pasillo',(l->>'estante')::smallint,
      (l->>'nivel')::smallint,recibida,p_compra,'Recepción BUSRAX OC '||p_compra);
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM busrax_qa_instalacion.detalle_orden_compra d WHERE d.nro_oc=p_compra AND
    d.cantidad>COALESCE((SELECT sum(m.cantidad) FROM busrax_qa_instalacion.movimiento_stock m
       WHERE m.nro_oc=p_compra AND m.sku=d.sku AND m.tipo='INGRESO'),0)) THEN
    UPDATE busrax_qa_instalacion.orden_compra SET estado='RECIBIDA',fecha_recepcion=CURRENT_DATE WHERE nro_oc=p_compra;
    estado_final:='RECIBIDA';
  ELSE estado_final:='PENDIENTE'; END IF;
  RETURN estado_final;
END; $$;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.busrax_preparar_pedido(p_pedido integer)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE p busrax_qa_instalacion.pedido; d record; s record; falta integer; tomar integer; n integer:=0;
BEGIN
  SELECT * INTO p FROM busrax_qa_instalacion.pedido WHERE nro_pedido=p_pedido FOR UPDATE;
  IF NOT FOUND OR p.estado<>'PENDIENTE' THEN RAISE EXCEPTION 'El pedido ya no está pendiente'; END IF;
  IF NOT EXISTS(SELECT 1 FROM busrax_qa_instalacion.detalle_pedido WHERE nro_pedido=p_pedido) THEN RAISE EXCEPTION 'El pedido no tiene renglones'; END IF;
  IF EXISTS(SELECT 1 FROM busrax_qa_instalacion.movimiento_stock WHERE nro_pedido=p_pedido AND tipo='EGRESO')
    THEN RAISE EXCEPTION 'Este pedido tiene egresos anteriores y necesita revisión'; END IF;
  FOR d IN SELECT * FROM busrax_qa_instalacion.detalle_pedido WHERE nro_pedido=p_pedido ORDER BY sku LOOP
    falta:=d.cantidad;
    FOR s IN SELECT * FROM busrax_qa_instalacion.stock WHERE sku=d.sku AND cantidad>0 ORDER BY codigo_deposito,pasillo,estante,nivel LOOP
      tomar:=least(falta,s.cantidad);
      INSERT INTO busrax_qa_instalacion.movimiento_stock(tipo,sku,codigo_deposito,pasillo,estante,nivel,cantidad,nro_pedido,observacion)
        VALUES('EGRESO',d.sku,s.codigo_deposito,s.pasillo,s.estante,s.nivel,tomar,p_pedido,'Picking BUSRAX');
      n:=n+1; falta:=falta-tomar; EXIT WHEN falta=0;
    END LOOP;
    IF falta>0 THEN RAISE EXCEPTION 'Faltan % unidades de %. No se descontó ningún renglón',falta,d.sku; END IF;
  END LOOP;
  UPDATE busrax_qa_instalacion.pedido SET estado='PREPARADO' WHERE nro_pedido=p_pedido;
  RETURN n;
END; $$;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.busrax_iniciar_hoja(p_hoja integer)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE h busrax_qa_instalacion.hoja_ruta; v busrax_qa_instalacion.vehiculo; c busrax_qa_instalacion.chofer; peso numeric;
BEGIN
  SELECT * INTO h FROM busrax_qa_instalacion.hoja_ruta WHERE id_hoja=p_hoja FOR UPDATE;
  IF NOT FOUND OR h.estado<>'PLANIFICADA' THEN RAISE EXCEPTION 'La hoja ya no está planificada'; END IF;
  IF h.fecha>CURRENT_DATE THEN RAISE EXCEPTION 'La fecha de salida todavía no llegó'; END IF;
  SELECT * INTO v FROM busrax_qa_instalacion.vehiculo WHERE patente=h.patente;
  SELECT * INTO c FROM busrax_qa_instalacion.chofer WHERE legajo=h.legajo_chofer;
  IF NOT v.activo OR c.licencia_vencimiento<CURRENT_DATE THEN RAISE EXCEPTION 'Revisá el vehículo o la vigencia de la licencia'; END IF;
  IF NOT EXISTS(SELECT 1 FROM busrax_qa_instalacion.entrega WHERE id_hoja=p_hoja) THEN RAISE EXCEPTION 'La hoja no tiene pedidos'; END IF;
  PERFORM p.nro_pedido FROM busrax_qa_instalacion.pedido p JOIN busrax_qa_instalacion.entrega e USING(nro_pedido) WHERE e.id_hoja=p_hoja ORDER BY p.nro_pedido FOR UPDATE OF p;
  IF EXISTS(SELECT 1 FROM busrax_qa_instalacion.entrega e JOIN busrax_qa_instalacion.pedido p USING(nro_pedido) WHERE e.id_hoja=p_hoja AND p.estado<>'PREPARADO')
    THEN RAISE EXCEPTION 'Todos los pedidos deben estar preparados'; END IF;
  SELECT COALESCE(sum(d.cantidad*p.peso_unitario_kg),0) INTO peso FROM busrax_qa_instalacion.entrega e
    JOIN busrax_qa_instalacion.detalle_pedido d USING(nro_pedido) JOIN busrax_qa_instalacion.producto p USING(sku) WHERE e.id_hoja=p_hoja;
  IF peso>v.capacidad_kg THEN RAISE EXCEPTION 'La carga supera la capacidad del vehículo'; END IF;
  UPDATE busrax_qa_instalacion.hoja_ruta SET estado='EN_CURSO',fecha_hora_salida=clock_timestamp() WHERE id_hoja=p_hoja;
  UPDATE busrax_qa_instalacion.pedido SET estado='DESPACHADO' WHERE nro_pedido IN(SELECT nro_pedido FROM busrax_qa_instalacion.entrega WHERE id_hoja=p_hoja);
END; $$;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.busrax_registrar_entrega(p_entrega integer,p_estado text,p_texto text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE e busrax_qa_instalacion.entrega; h busrax_qa_instalacion.hoja_ruta; n integer;
BEGIN
  IF p_estado IS NULL OR p_estado NOT IN('ENTREGADA','RECHAZADA') OR nullif(btrim(p_texto),'') IS NULL
    OR length(p_texto)>120 THEN RAISE EXCEPTION 'Indicá un resultado y un receptor o motivo de hasta 120 caracteres'; END IF;
  SELECT id_hoja INTO n FROM busrax_qa_instalacion.entrega WHERE id_entrega=p_entrega;
  SELECT * INTO h FROM busrax_qa_instalacion.hoja_ruta WHERE id_hoja=n FOR UPDATE;
  IF NOT FOUND OR h.estado<>'EN_CURSO' THEN RAISE EXCEPTION 'La hoja debe estar en curso'; END IF;
  SELECT * INTO e FROM busrax_qa_instalacion.entrega WHERE id_entrega=p_entrega FOR UPDATE;
  IF NOT FOUND OR e.estado<>'PENDIENTE' THEN RAISE EXCEPTION 'Esta entrega ya fue registrada'; END IF;
  PERFORM 1 FROM busrax_qa_instalacion.pedido WHERE nro_pedido=e.nro_pedido AND estado='DESPACHADO' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'El pedido no está despachado'; END IF;
  UPDATE busrax_qa_instalacion.entrega SET estado=p_estado,fecha_hora_entrega=clock_timestamp(),
    receptor=CASE WHEN p_estado='ENTREGADA' THEN btrim(p_texto) END,
    motivo_rechazo=CASE WHEN p_estado='RECHAZADA' THEN btrim(p_texto) END WHERE id_entrega=p_entrega;
  UPDATE busrax_qa_instalacion.pedido SET estado=CASE WHEN p_estado='ENTREGADA' THEN 'ENTREGADO' ELSE 'RECHAZADO' END WHERE nro_pedido=e.nro_pedido;
END; $$;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.busrax_cerrar_hoja(p_hoja integer)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE h busrax_qa_instalacion.hoja_ruta;
BEGIN
  SELECT * INTO h FROM busrax_qa_instalacion.hoja_ruta WHERE id_hoja=p_hoja FOR UPDATE;
  IF NOT FOUND OR h.estado<>'EN_CURSO' THEN RAISE EXCEPTION 'La hoja debe estar en curso'; END IF;
  IF EXISTS(SELECT 1 FROM busrax_qa_instalacion.entrega WHERE id_hoja=p_hoja AND estado='PENDIENTE') THEN RAISE EXCEPTION 'Todavía hay entregas sin resolver'; END IF;
  UPDATE busrax_qa_instalacion.hoja_ruta SET estado='CERRADA',fecha_hora_regreso=clock_timestamp() WHERE id_hoja=p_hoja;
END; $$;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.busrax_cancelar_pedido(p_pedido integer)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM busrax_qa_instalacion.pedido WHERE nro_pedido=p_pedido AND estado='PENDIENTE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solo se cancela un pedido pendiente'; END IF;
  IF EXISTS(SELECT 1 FROM busrax_qa_instalacion.movimiento_stock WHERE nro_pedido=p_pedido AND tipo='EGRESO') THEN RAISE EXCEPTION 'El pedido ya tiene egresos'; END IF;
  UPDATE busrax_qa_instalacion.pedido SET estado='CANCELADO' WHERE nro_pedido=p_pedido;
END; $$;

CREATE OR REPLACE FUNCTION busrax_qa_instalacion.busrax_cancelar_compra(p_compra integer)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM busrax_qa_instalacion.orden_compra WHERE nro_oc=p_compra AND estado='PENDIENTE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solo se cancela una compra pendiente'; END IF;
  IF EXISTS(SELECT 1 FROM busrax_qa_instalacion.movimiento_stock WHERE nro_oc=p_compra AND tipo='INGRESO') THEN RAISE EXCEPTION 'La compra tiene recepciones parciales. Completá el saldo pendiente'; END IF;
  UPDATE busrax_qa_instalacion.orden_compra SET estado='CANCELADA' WHERE nro_oc=p_compra;
END; $$;

-- Permisos explícitos. Se conserva el acceso compartido del proyecto.
DO $$ DECLARE f record; BEGIN
  FOR f IN SELECT p.oid::regprocedure firma FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='busrax_qa_instalacion' AND p.proname LIKE 'busrax_%' LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.firma);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon,authenticated',f.firma);
  END LOOP;
END $$;
NOTIFY pgrst,'reload schema';

-- Índices para las claves foráneas y los filtros de trazabilidad.
CREATE INDEX IF NOT EXISTS busrax_detalle_oc_sku ON busrax_qa_instalacion.detalle_orden_compra(sku);
CREATE INDEX IF NOT EXISTS busrax_detalle_pedido_sku ON busrax_qa_instalacion.detalle_pedido(sku);
CREATE INDEX IF NOT EXISTS busrax_mov_ubicacion ON busrax_qa_instalacion.movimiento_stock(codigo_deposito,pasillo,estante,nivel);
CREATE INDEX IF NOT EXISTS busrax_mov_compra_sku ON busrax_qa_instalacion.movimiento_stock(nro_oc,sku);
CREATE INDEX IF NOT EXISTS busrax_mov_pedido ON busrax_qa_instalacion.movimiento_stock(nro_pedido);
CREATE INDEX IF NOT EXISTS busrax_mov_sku ON busrax_qa_instalacion.movimiento_stock(sku);
CREATE INDEX IF NOT EXISTS busrax_oc_proveedor ON busrax_qa_instalacion.orden_compra(cuit_proveedor);
CREATE INDEX IF NOT EXISTS busrax_pedido_cliente ON busrax_qa_instalacion.pedido(cuit_cliente);
CREATE INDEX IF NOT EXISTS busrax_producto_proveedor ON busrax_qa_instalacion.producto(cuit_proveedor);
CREATE INDEX IF NOT EXISTS busrax_stock_ubicacion ON busrax_qa_instalacion.stock(codigo_deposito,pasillo,estante,nivel);

-- BUSRAX. Carga inicial de datos de la operatoria regional.
-- No son clientes, contactos ni empleados reales. No contiene teléfonos.
-- Solo para una base vacía. No borra registros. Fecha de referencia: 23/10/2026.

DO $$ BEGIN IF EXISTS(SELECT 1 FROM busrax_qa_instalacion.producto) THEN RAISE EXCEPTION 'La base ya tiene un catálogo. No repitas la carga inicial'; END IF; END $$;
INSERT INTO busrax_qa_instalacion.proveedor(cuit,telefono,razon_social,plazo_entrega_dias) VALUES
 ('30711111119',NULL,'Mayorista San Roque',3),
 ('30722222228',NULL,'Bebidas del Paraná',2),
 ('30733333337',NULL,'Química Santa Rita',2);
INSERT INTO busrax_qa_instalacion.producto(sku,descripcion,stock_minimo,unidad_medida,cuit_proveedor,lote_reposicion,peso_unitario_kg) VALUES
 ('ALM-003','Fideos secos 500 g · bulto x 20',15,'CAJA','30711111119',20,10.7),
 ('ALM-004','Harina 000 1 kg · bulto x 10',12,'CAJA','30711111119',20,10.3),
 ('ALM-005','Aceite de girasol 900 ml · caja x 12',10,'CAJA','30711111119',12,10.1),
 ('BEB-003','Soda 2 L · pack x 6',12,'CAJA','30722222228',18,12.5),
 ('LIM-003','Jabón líquido 800 ml · caja x 12',8,'CAJA','30733333337',12,10.2),
 ('LIM-004','Desinfectante 900 ml · caja x 12',12,'CAJA','30733333337',12,11.3),
 ('ALM-001','Arroz largo fino 1 kg · bulto x 10',30,'CAJA','30711111119',40,10.5),
 ('ALM-002','Azúcar común 1 kg · bulto x 10',20,'CAJA','30711111119',30,10.3),
 ('BEB-001','Agua de mesa 2 L · pack x 6',30,'CAJA','30722222228',40,12.4),
 ('BEB-002','Gaseosa cola 1,5 L · pack x 6',25,'CAJA','30722222228',40,9.6),
 ('LIM-001','Lavandina 1 L · caja x 12',30,'CAJA','30733333337',30,12.8),
 ('LIM-002','Detergente 750 ml · caja x 12',15,'CAJA','30733333337',20,9.9);
INSERT INTO busrax_qa_instalacion.deposito(codigo,nombre,direccion) VALUES
 ('D1','Depósito central','Sector de abastecimiento · Ituzaingó, Corrientes'),
 ('D2','Sector higiene y limpieza','Sector de reparto · Ituzaingó, Corrientes');
INSERT INTO busrax_qa_instalacion.ubicacion(nivel,estante,pasillo,capacidad_unid,codigo_deposito) VALUES
 (1,1,'A',100,'D1'),
 (2,1,'A',100,'D1'),
 (1,1,'B',80,'D1'),
 (1,2,'B',80,'D1'),
 (1,1,'C',60,'D1'),
 (1,1,'A',60,'D2'),
 (2,1,'A',60,'D2');
INSERT INTO busrax_qa_instalacion.cliente(cuit,zona,razon_social,direccion_entrega) VALUES
 ('30744444446','Ituzaingó Centro','Autoservicio El Timbó','Zona comercial · Ituzaingó'),
 ('30755555555','Villa Olivari','Despensa La Ribera','Zona urbana · Villa Olivari'),
 ('20123456786','Ituzaingó Centro','Almacén Los Lapachos','Zona centro · Ituzaingó'),
 ('30766666664','Virasoro','Comercial San Miguel','Zona comercial · Virasoro');
INSERT INTO busrax_qa_instalacion.vehiculo(activo,patente,descripcion,capacidad_kg) VALUES
 (true,'AE123BC','Utilitario Fiorino',650),
 (true,'AD456FG','Camión liviano 3,5 t',3500),
 (false,'AB789CD','Furgón Sprinter',1500);
INSERT INTO busrax_qa_instalacion.chofer(legajo,nombre,licencia_vencimiento) VALUES
 (1001,'Ramiro Acosta','2027-10-23'),
 (1002,'Lucía Duarte','2027-10-23'),
 (1003,'Hugo Benítez','2026-10-11');
DO $carga$
DECLARE r jsonb; n integer; pedidos jsonb:='{}'; compras jsonb:='{}'; hojas jsonb:='{}';
BEGIN
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-20","estado":"ENTREGADO","nro_pedido":1,"cuit_cliente":"30744444446","fecha_compromiso":"2026-10-21"},{"fecha":"2026-10-22","estado":"PREPARADO","nro_pedido":2,"cuit_cliente":"30755555555","fecha_compromiso":"2026-10-23"},{"fecha":"2026-10-23","estado":"PENDIENTE","nro_pedido":3,"cuit_cliente":"20123456786","fecha_compromiso":"2026-10-24"},{"fecha":"2026-10-21","estado":"PREPARADO","nro_pedido":4,"cuit_cliente":"30766666664","fecha_compromiso":"2026-10-22"}]$datos$::jsonb) LOOP
  INSERT INTO busrax_qa_instalacion.pedido(cuit_cliente,fecha,fecha_compromiso,estado)
   VALUES(r->>'cuit_cliente',(r->>'fecha')::date,(r->>'fecha_compromiso')::date,'PREPARADO') RETURNING nro_pedido INTO n;
   pedidos:=pedidos||jsonb_build_object(r->>'nro_pedido',n);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"sku":"ALM-001","cantidad":10,"nro_pedido":1},{"sku":"BEB-001","cantidad":8,"nro_pedido":1},{"sku":"BEB-002","cantidad":12,"nro_pedido":2},{"sku":"LIM-001","cantidad":5,"nro_pedido":2},{"sku":"ALM-002","cantidad":6,"nro_pedido":3},{"sku":"ALM-001","cantidad":20,"nro_pedido":4},{"sku":"BEB-001","cantidad":15,"nro_pedido":4},{"sku":"LIM-002","cantidad":4,"nro_pedido":4}]$datos$::jsonb) LOOP
  INSERT INTO busrax_qa_instalacion.detalle_pedido(nro_pedido,sku,cantidad)
   VALUES((pedidos->>(r->>'nro_pedido'))::integer,r->>'sku',(r->>'cantidad')::integer);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-18","estado":"RECIBIDA","nro_oc":1,"cuit_proveedor":"30733333337","fecha_recepcion":"2026-10-22"},{"fecha":"2026-10-23","estado":"PENDIENTE","nro_oc":2,"cuit_proveedor":"30733333337","fecha_recepcion":null}]$datos$::jsonb) LOOP
  INSERT INTO busrax_qa_instalacion.orden_compra(cuit_proveedor,fecha)
   VALUES(r->>'cuit_proveedor',(r->>'fecha')::date) RETURNING nro_oc INTO n;
   compras:=compras||jsonb_build_object(r->>'nro_oc',n);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"sku":"LIM-002","nro_oc":2,"cantidad":20},{"sku":"LIM-001","nro_oc":1,"cantidad":50}]$datos$::jsonb) LOOP
  INSERT INTO busrax_qa_instalacion.detalle_orden_compra(nro_oc,sku,cantidad)
   VALUES((compras->>(r->>'nro_oc'))::integer,r->>'sku',(r->>'cantidad')::integer);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-21","estado":"CERRADA","id_hoja":1,"patente":"AD456FG","legajo_chofer":1001,"fecha_hora_salida":"2026-10-21T11:30:00+00:00","fecha_hora_regreso":"2026-10-21T19:00:00+00:00"},{"fecha":"2026-10-23","estado":"PLANIFICADA","id_hoja":3,"patente":"AD456FG","legajo_chofer":1001,"fecha_hora_salida":null,"fecha_hora_regreso":null}]$datos$::jsonb) LOOP
  INSERT INTO busrax_qa_instalacion.hoja_ruta(fecha,patente,legajo_chofer)
   VALUES((r->>'fecha')::date,r->>'patente',(r->>'legajo_chofer')::integer) RETURNING id_hoja INTO n;
   hojas:=hojas||jsonb_build_object(r->>'id_hoja',n);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"sku":"ALM-001","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":60,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":1,"codigo_deposito":"D1"},{"sku":"ALM-002","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":40,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":2,"codigo_deposito":"D1"},{"sku":"BEB-001","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"B","cantidad":70,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":3,"codigo_deposito":"D1"},{"sku":"BEB-002","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":2,"pasillo":"B","cantidad":50,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":4,"codigo_deposito":"D1"},{"sku":"LIM-001","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":30,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":5,"codigo_deposito":"D2"},{"sku":"LIM-002","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":12,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":6,"codigo_deposito":"D2"},{"sku":"ALM-001","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":20,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":7,"codigo_deposito":"D2"},{"sku":"ALM-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":10,"fecha_hora":"2026-10-12T18:00:00+00:00","nro_pedido":1,"observacion":null,"id_movimiento":8,"codigo_deposito":"D1"},{"sku":"BEB-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"B","cantidad":8,"fecha_hora":"2026-10-12T18:00:00+00:00","nro_pedido":1,"observacion":null,"id_movimiento":9,"codigo_deposito":"D1"},{"sku":"BEB-002","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":2,"pasillo":"B","cantidad":12,"fecha_hora":"2026-10-13T12:00:00+00:00","nro_pedido":2,"observacion":null,"id_movimiento":10,"codigo_deposito":"D1"},{"sku":"LIM-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":5,"fecha_hora":"2026-10-13T12:00:00+00:00","nro_pedido":2,"observacion":null,"id_movimiento":11,"codigo_deposito":"D2"},{"sku":"LIM-001","tipo":"INGRESO","nivel":1,"nro_oc":1,"estante":1,"pasillo":"A","cantidad":50,"fecha_hora":"2026-10-22T22:18:10.245174+00:00","nro_pedido":null,"observacion":"Recepción OC 1","id_movimiento":13,"codigo_deposito":"D1"},{"sku":"ALM-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":20,"fecha_hora":"2026-10-22T22:19:23.400954+00:00","nro_pedido":4,"observacion":null,"id_movimiento":14,"codigo_deposito":"D2"},{"sku":"BEB-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"B","cantidad":15,"fecha_hora":"2026-10-22T22:19:24.077055+00:00","nro_pedido":4,"observacion":null,"id_movimiento":15,"codigo_deposito":"D1"},{"sku":"LIM-002","tipo":"EGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":4,"fecha_hora":"2026-10-22T22:19:24.250558+00:00","nro_pedido":4,"observacion":null,"id_movimiento":16,"codigo_deposito":"D2"},{"sku":"ALM-003","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":24,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":36,"codigo_deposito":"D1"},{"sku":"ALM-004","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":18,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":37,"codigo_deposito":"D1"},{"sku":"ALM-005","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"C","cantidad":12,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":38,"codigo_deposito":"D1"},{"sku":"BEB-003","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":2,"pasillo":"B","cantidad":14,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":39,"codigo_deposito":"D1"},{"sku":"LIM-003","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":12,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":40,"codigo_deposito":"D2"},{"sku":"LIM-004","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":9,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":41,"codigo_deposito":"D2"},{"sku":"LIM-002","tipo":"INGRESO","nivel":2,"nro_oc":2,"estante":1,"pasillo":"A","cantidad":5,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Recepción BUSRAX OC 2","id_movimiento":42,"codigo_deposito":"D2"},{"sku":"LIM-001","tipo":"AJUSTE","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":-50,"fecha_hora":"2026-10-23T04:07:43.632551+00:00","nro_pedido":null,"observacion":"Traslado a sector limpieza","id_movimiento":43,"codigo_deposito":"D1"},{"sku":"LIM-001","tipo":"AJUSTE","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":23,"fecha_hora":"2026-10-23T04:07:43.632551+00:00","nro_pedido":null,"observacion":"Traslado desde depósito central","id_movimiento":44,"codigo_deposito":"D2"},{"sku":"LIM-001","tipo":"AJUSTE","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":27,"fecha_hora":"2026-10-23T04:07:43.632551+00:00","nro_pedido":null,"observacion":"Traslado desde depósito central","id_movimiento":45,"codigo_deposito":"D2"}]$datos$::jsonb) LOOP
  INSERT INTO busrax_qa_instalacion.movimiento_stock(fecha_hora,tipo,sku,codigo_deposito,pasillo,estante,nivel,cantidad,nro_pedido,nro_oc,observacion)
   VALUES((r->>'fecha_hora')::timestamptz,r->>'tipo',r->>'sku',r->>'codigo_deposito',r->>'pasillo',
   (r->>'estante')::smallint,(r->>'nivel')::smallint,(r->>'cantidad')::integer,
   (pedidos->>(r->>'nro_pedido'))::integer,(compras->>(r->>'nro_oc'))::integer,r->>'observacion');
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"estado":"ENTREGADA","id_hoja":1,"receptor":"Carlos Molina","id_entrega":1,"nro_pedido":1,"orden_visita":1,"motivo_rechazo":null,"fecha_hora_entrega":"2026-10-21T16:00:00+00:00"},{"estado":"PENDIENTE","id_hoja":3,"receptor":null,"id_entrega":5,"nro_pedido":4,"orden_visita":1,"motivo_rechazo":null,"fecha_hora_entrega":null},{"estado":"PENDIENTE","id_hoja":3,"receptor":null,"id_entrega":6,"nro_pedido":2,"orden_visita":2,"motivo_rechazo":null,"fecha_hora_entrega":null}]$datos$::jsonb) LOOP
  INSERT INTO busrax_qa_instalacion.entrega(nro_pedido,id_hoja,orden_visita)
   VALUES((pedidos->>(r->>'nro_pedido'))::integer,(hojas->>(r->>'id_hoja'))::integer,(r->>'orden_visita')::smallint) RETURNING id_entrega INTO n;
   UPDATE busrax_qa_instalacion.entrega SET estado=r->>'estado',fecha_hora_entrega=(r->>'fecha_hora_entrega')::timestamptz,
   receptor=r->>'receptor',motivo_rechazo=r->>'motivo_rechazo' WHERE id_entrega=n;
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-20","estado":"ENTREGADO","nro_pedido":1,"cuit_cliente":"30744444446","fecha_compromiso":"2026-10-21"},{"fecha":"2026-10-22","estado":"PREPARADO","nro_pedido":2,"cuit_cliente":"30755555555","fecha_compromiso":"2026-10-23"},{"fecha":"2026-10-23","estado":"PENDIENTE","nro_pedido":3,"cuit_cliente":"20123456786","fecha_compromiso":"2026-10-24"},{"fecha":"2026-10-21","estado":"PREPARADO","nro_pedido":4,"cuit_cliente":"30766666664","fecha_compromiso":"2026-10-22"}]$datos$::jsonb) LOOP
  UPDATE busrax_qa_instalacion.pedido SET estado=r->>'estado' WHERE nro_pedido=(pedidos->>(r->>'nro_pedido'))::integer;
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-18","estado":"RECIBIDA","nro_oc":1,"cuit_proveedor":"30733333337","fecha_recepcion":"2026-10-22"},{"fecha":"2026-10-23","estado":"PENDIENTE","nro_oc":2,"cuit_proveedor":"30733333337","fecha_recepcion":null}]$datos$::jsonb) LOOP
  UPDATE busrax_qa_instalacion.orden_compra SET estado=r->>'estado',fecha_recepcion=(r->>'fecha_recepcion')::date WHERE nro_oc=(compras->>(r->>'nro_oc'))::integer;
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-21","estado":"CERRADA","id_hoja":1,"patente":"AD456FG","legajo_chofer":1001,"fecha_hora_salida":"2026-10-21T11:30:00+00:00","fecha_hora_regreso":"2026-10-21T19:00:00+00:00"},{"fecha":"2026-10-23","estado":"PLANIFICADA","id_hoja":3,"patente":"AD456FG","legajo_chofer":1001,"fecha_hora_salida":null,"fecha_hora_regreso":null}]$datos$::jsonb) LOOP
  UPDATE busrax_qa_instalacion.hoja_ruta SET estado=r->>'estado',fecha_hora_salida=(r->>'fecha_hora_salida')::timestamptz,
   fecha_hora_regreso=(r->>'fecha_hora_regreso')::timestamptz WHERE id_hoja=(hojas->>(r->>'id_hoja'))::integer;
 END LOOP;
END; $carga$;

SELECT * FROM busrax_qa_instalacion.v_indicadores;
$bundle$;
  SELECT jsonb_build_object('productos',(SELECT count(*) FROM busrax_qa_instalacion.producto),
   'stock',(SELECT sum(cantidad) FROM busrax_qa_instalacion.stock),
   'pedidos',(SELECT count(*) FROM busrax_qa_instalacion.pedido),
   'entregas',(SELECT count(*) FROM busrax_qa_instalacion.entrega),
   'tablas_con_rls',(SELECT count(*) FROM pg_tables WHERE schemaname='busrax_qa_instalacion' AND rowsecurity)) INTO evidencia;
  IF evidencia->>'stock'<>'352' OR evidencia->>'productos'<>'12' OR evidencia->>'tablas_con_rls'<>'15' THEN
   RAISE EXCEPTION 'La instalación no reproduce el escenario: %',evidencia;
  END IF;
  RAISE EXCEPTION USING ERRCODE='ZX002', MESSAGE='Revertir esquema de comprobación';
 EXCEPTION WHEN SQLSTATE 'ZX002' THEN NULL;
 END;
 RETURN evidencia||jsonb_build_object('resultado','OK','esquema_de_prueba','revertido');
END; $run$;
SELECT pg_temp.busrax_verificar_instalacion() AS instalacion;
