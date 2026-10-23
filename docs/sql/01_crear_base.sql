-- BUSRAX. Solo para una base nueva y vacía. No elimina datos existentes.
BEGIN;
SET LOCAL search_path=public;
DO $$ BEGIN IF to_regclass('public.producto') IS NOT NULL THEN RAISE EXCEPTION 'La base ya existe. Aplicá solo 04_mejoras_busrax.sql'; END IF; END $$;
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


COMMIT;
