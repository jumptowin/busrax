-- BUSRAX. Actualización sobre la base existente, sin borrar tablas ni datos.
-- Las operaciones compuestas se confirman en una sola transacción.

CREATE OR REPLACE FUNCTION public.fn_aplicar_movimiento() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE delta integer := CASE WHEN NEW.tipo = 'EGRESO' THEN -NEW.cantidad ELSE NEW.cantidad END;
BEGIN
  -- Serializa las modificaciones de una misma ubicación, incluso de SKU distintos.
  PERFORM 1 FROM public.ubicacion u WHERE u.codigo_deposito=NEW.codigo_deposito
    AND u.pasillo=NEW.pasillo AND u.estante=NEW.estante AND u.nivel=NEW.nivel FOR UPDATE;
  UPDATE public.stock SET cantidad=cantidad+delta WHERE sku=NEW.sku
    AND codigo_deposito=NEW.codigo_deposito AND pasillo=NEW.pasillo
    AND estante=NEW.estante AND nivel=NEW.nivel;
  IF NOT FOUND THEN
    INSERT INTO public.stock(sku,codigo_deposito,pasillo,estante,nivel,cantidad)
    VALUES(NEW.sku,NEW.codigo_deposito,NEW.pasillo,NEW.estante,NEW.nivel,delta);
  END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION public.fn_aplicar_movimiento() FROM PUBLIC, anon, authenticated;

ALTER FUNCTION public.fn_controlar_capacidad_ubicacion() SET search_path=public,pg_temp;
ALTER FUNCTION public.fn_controlar_detalle_oc() SET search_path=public,pg_temp;
ALTER FUNCTION public.fn_controlar_hoja_ruta() SET search_path=public,pg_temp;

CREATE OR REPLACE FUNCTION public.fn_controlar_entrega() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE est text; h_estado text; peso numeric; cap numeric;
BEGIN
  SELECT estado INTO h_estado FROM public.hoja_ruta WHERE id_hoja=NEW.id_hoja FOR UPDATE;
  IF h_estado IS DISTINCT FROM 'PLANIFICADA' THEN RAISE EXCEPTION 'Solo se agregan pedidos a hojas PLANIFICADAS'; END IF;
  SELECT estado INTO est FROM public.pedido WHERE nro_pedido=NEW.nro_pedido FOR UPDATE;
  IF est IS DISTINCT FROM 'PREPARADO' THEN RAISE EXCEPTION 'El pedido no está PREPARADO'; END IF;
  SELECT COALESCE(sum(d.cantidad*p.peso_unitario_kg),0) INTO peso
    FROM public.detalle_pedido d JOIN public.producto p ON p.sku=d.sku
    WHERE d.nro_pedido=NEW.nro_pedido OR d.nro_pedido IN
      (SELECT e.nro_pedido FROM public.entrega e WHERE e.id_hoja=NEW.id_hoja);
  SELECT v.capacidad_kg INTO cap FROM public.hoja_ruta h JOIN public.vehiculo v ON v.patente=h.patente WHERE h.id_hoja=NEW.id_hoja;
  IF peso>cap THEN RAISE EXCEPTION 'La carga de % kg supera la capacidad de % kg',peso,cap; END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.busrax_crear_pedido(p_cliente text,p_fecha date,p_lineas jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE n integer; l jsonb;
BEGIN
  IF p_fecha IS NULL OR p_fecha<CURRENT_DATE THEN RAISE EXCEPTION 'La fecha de entrega debe ser hoy o posterior'; END IF;
  IF jsonb_typeof(p_lineas) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lineas) NOT BETWEEN 1 AND 50
    THEN RAISE EXCEPTION 'El pedido debe tener entre 1 y 50 renglones'; END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(p_lineas)) <>
     (SELECT count(DISTINCT item.value->>'sku') FROM jsonb_array_elements(p_lineas) AS item(value))
    THEN RAISE EXCEPTION 'No se permiten productos repetidos ni vacíos'; END IF;
  INSERT INTO public.pedido(cuit_cliente,fecha_compromiso) VALUES(p_cliente,p_fecha) RETURNING nro_pedido INTO n;
  FOR l IN SELECT value FROM jsonb_array_elements(p_lineas) LOOP
    IF l->>'cantidad' IS NULL OR (l->>'cantidad') !~ '^[1-9][0-9]*$'
      THEN RAISE EXCEPTION 'Las cantidades deben ser enteros positivos'; END IF;
    INSERT INTO public.detalle_pedido(nro_pedido,sku,cantidad) VALUES(n,l->>'sku',(l->>'cantidad')::integer);
  END LOOP;
  RETURN n;
END; $$;

CREATE OR REPLACE FUNCTION public.busrax_reponer(p_sku text)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE p public.producto; n integer; disponible integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('busrax:compra:'||p_sku,0));
  SELECT * INTO p FROM public.producto WHERE sku=p_sku;
  IF NOT FOUND THEN RAISE EXCEPTION 'Producto inexistente'; END IF;
  SELECT COALESCE(sum(cantidad),0) INTO disponible FROM public.stock WHERE sku=p_sku;
  IF disponible>p.stock_minimo THEN RAISE EXCEPTION 'El producto ya está por encima del mínimo'; END IF;
  IF EXISTS(SELECT 1 FROM public.detalle_orden_compra d JOIN public.orden_compra o USING(nro_oc)
    WHERE d.sku=p_sku AND o.estado='PENDIENTE') THEN RAISE EXCEPTION 'Ya hay una compra pendiente para este producto'; END IF;
  INSERT INTO public.orden_compra(cuit_proveedor) VALUES(p.cuit_proveedor) RETURNING nro_oc INTO n;
  INSERT INTO public.detalle_orden_compra(nro_oc,sku,cantidad) VALUES(n,p_sku,p.lote_reposicion);
  RETURN n;
END; $$;

CREATE OR REPLACE FUNCTION public.busrax_recibir_compra(p_compra integer,p_lineas jsonb)
RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE o public.orden_compra; l jsonb; pendiente integer; recibida integer; estado_final text;
BEGIN
  SELECT * INTO o FROM public.orden_compra WHERE nro_oc=p_compra FOR UPDATE;
  IF NOT FOUND OR o.estado<>'PENDIENTE' THEN RAISE EXCEPTION 'La compra ya no está pendiente'; END IF;
  IF jsonb_typeof(p_lineas) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lineas) NOT BETWEEN 1 AND 50
    THEN RAISE EXCEPTION 'Indicá al menos un ingreso'; END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(p_lineas)) <>
     (SELECT count(DISTINCT item.value->>'sku') FROM jsonb_array_elements(p_lineas) AS item(value))
    THEN RAISE EXCEPTION 'No se permiten productos repetidos'; END IF;
  FOR l IN SELECT value FROM jsonb_array_elements(p_lineas) ORDER BY value->>'codigo_deposito',value->>'pasillo',value->>'estante',value->>'nivel' LOOP
    IF l->>'cantidad' IS NULL OR (l->>'cantidad') !~ '^[1-9][0-9]*$' THEN RAISE EXCEPTION 'El ingreso debe ser un entero positivo'; END IF;
    SELECT d.cantidad-COALESCE((SELECT sum(m.cantidad) FROM public.movimiento_stock m
      WHERE m.nro_oc=p_compra AND m.sku=d.sku AND m.tipo='INGRESO'),0)
      INTO pendiente FROM public.detalle_orden_compra d WHERE d.nro_oc=p_compra AND d.sku=l->>'sku';
    IF pendiente IS NULL THEN RAISE EXCEPTION 'El producto no pertenece a esta compra'; END IF;
    recibida:=(l->>'cantidad')::integer;
    IF recibida>pendiente THEN RAISE EXCEPTION 'Solo quedan % unidades por recibir de %',pendiente,l->>'sku'; END IF;
    INSERT INTO public.movimiento_stock(tipo,sku,codigo_deposito,pasillo,estante,nivel,cantidad,nro_oc,observacion)
      VALUES('INGRESO',l->>'sku',l->>'codigo_deposito',l->>'pasillo',(l->>'estante')::smallint,
      (l->>'nivel')::smallint,recibida,p_compra,'Recepción BUSRAX OC '||p_compra);
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM public.detalle_orden_compra d WHERE d.nro_oc=p_compra AND
    d.cantidad>COALESCE((SELECT sum(m.cantidad) FROM public.movimiento_stock m
       WHERE m.nro_oc=p_compra AND m.sku=d.sku AND m.tipo='INGRESO'),0)) THEN
    UPDATE public.orden_compra SET estado='RECIBIDA',fecha_recepcion=CURRENT_DATE WHERE nro_oc=p_compra;
    estado_final:='RECIBIDA';
  ELSE estado_final:='PENDIENTE'; END IF;
  RETURN estado_final;
END; $$;

CREATE OR REPLACE FUNCTION public.busrax_preparar_pedido(p_pedido integer)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE p public.pedido; d record; s record; falta integer; tomar integer; n integer:=0;
BEGIN
  SELECT * INTO p FROM public.pedido WHERE nro_pedido=p_pedido FOR UPDATE;
  IF NOT FOUND OR p.estado<>'PENDIENTE' THEN RAISE EXCEPTION 'El pedido ya no está pendiente'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.detalle_pedido WHERE nro_pedido=p_pedido) THEN RAISE EXCEPTION 'El pedido no tiene renglones'; END IF;
  IF EXISTS(SELECT 1 FROM public.movimiento_stock WHERE nro_pedido=p_pedido AND tipo='EGRESO')
    THEN RAISE EXCEPTION 'Este pedido tiene egresos anteriores y necesita revisión'; END IF;
  FOR d IN SELECT * FROM public.detalle_pedido WHERE nro_pedido=p_pedido ORDER BY sku LOOP
    falta:=d.cantidad;
    FOR s IN SELECT * FROM public.stock WHERE sku=d.sku AND cantidad>0 ORDER BY codigo_deposito,pasillo,estante,nivel LOOP
      tomar:=least(falta,s.cantidad);
      INSERT INTO public.movimiento_stock(tipo,sku,codigo_deposito,pasillo,estante,nivel,cantidad,nro_pedido,observacion)
        VALUES('EGRESO',d.sku,s.codigo_deposito,s.pasillo,s.estante,s.nivel,tomar,p_pedido,'Picking BUSRAX');
      n:=n+1; falta:=falta-tomar; EXIT WHEN falta=0;
    END LOOP;
    IF falta>0 THEN RAISE EXCEPTION 'Faltan % unidades de %. No se descontó ningún renglón',falta,d.sku; END IF;
  END LOOP;
  UPDATE public.pedido SET estado='PREPARADO' WHERE nro_pedido=p_pedido;
  RETURN n;
END; $$;

CREATE OR REPLACE FUNCTION public.busrax_iniciar_hoja(p_hoja integer)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE h public.hoja_ruta; v public.vehiculo; c public.chofer; peso numeric;
BEGIN
  SELECT * INTO h FROM public.hoja_ruta WHERE id_hoja=p_hoja FOR UPDATE;
  IF NOT FOUND OR h.estado<>'PLANIFICADA' THEN RAISE EXCEPTION 'La hoja ya no está planificada'; END IF;
  IF h.fecha>CURRENT_DATE THEN RAISE EXCEPTION 'La fecha de salida todavía no llegó'; END IF;
  SELECT * INTO v FROM public.vehiculo WHERE patente=h.patente;
  SELECT * INTO c FROM public.chofer WHERE legajo=h.legajo_chofer;
  IF NOT v.activo OR c.licencia_vencimiento<CURRENT_DATE THEN RAISE EXCEPTION 'Revisá el vehículo o la vigencia de la licencia'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.entrega WHERE id_hoja=p_hoja) THEN RAISE EXCEPTION 'La hoja no tiene pedidos'; END IF;
  PERFORM p.nro_pedido FROM public.pedido p JOIN public.entrega e USING(nro_pedido) WHERE e.id_hoja=p_hoja ORDER BY p.nro_pedido FOR UPDATE OF p;
  IF EXISTS(SELECT 1 FROM public.entrega e JOIN public.pedido p USING(nro_pedido) WHERE e.id_hoja=p_hoja AND p.estado<>'PREPARADO')
    THEN RAISE EXCEPTION 'Todos los pedidos deben estar preparados'; END IF;
  SELECT COALESCE(sum(d.cantidad*p.peso_unitario_kg),0) INTO peso FROM public.entrega e
    JOIN public.detalle_pedido d USING(nro_pedido) JOIN public.producto p USING(sku) WHERE e.id_hoja=p_hoja;
  IF peso>v.capacidad_kg THEN RAISE EXCEPTION 'La carga supera la capacidad del vehículo'; END IF;
  UPDATE public.hoja_ruta SET estado='EN_CURSO',fecha_hora_salida=clock_timestamp() WHERE id_hoja=p_hoja;
  UPDATE public.pedido SET estado='DESPACHADO' WHERE nro_pedido IN(SELECT nro_pedido FROM public.entrega WHERE id_hoja=p_hoja);
END; $$;

CREATE OR REPLACE FUNCTION public.busrax_registrar_entrega(p_entrega integer,p_estado text,p_texto text)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE e public.entrega; h public.hoja_ruta; n integer;
BEGIN
  IF p_estado IS NULL OR p_estado NOT IN('ENTREGADA','RECHAZADA') OR nullif(btrim(p_texto),'') IS NULL
    OR length(p_texto)>120 THEN RAISE EXCEPTION 'Indicá un resultado y un receptor o motivo de hasta 120 caracteres'; END IF;
  SELECT id_hoja INTO n FROM public.entrega WHERE id_entrega=p_entrega;
  SELECT * INTO h FROM public.hoja_ruta WHERE id_hoja=n FOR UPDATE;
  IF NOT FOUND OR h.estado<>'EN_CURSO' THEN RAISE EXCEPTION 'La hoja debe estar en curso'; END IF;
  SELECT * INTO e FROM public.entrega WHERE id_entrega=p_entrega FOR UPDATE;
  IF NOT FOUND OR e.estado<>'PENDIENTE' THEN RAISE EXCEPTION 'Esta entrega ya fue registrada'; END IF;
  PERFORM 1 FROM public.pedido WHERE nro_pedido=e.nro_pedido AND estado='DESPACHADO' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'El pedido no está despachado'; END IF;
  UPDATE public.entrega SET estado=p_estado,fecha_hora_entrega=clock_timestamp(),
    receptor=CASE WHEN p_estado='ENTREGADA' THEN btrim(p_texto) END,
    motivo_rechazo=CASE WHEN p_estado='RECHAZADA' THEN btrim(p_texto) END WHERE id_entrega=p_entrega;
  UPDATE public.pedido SET estado=CASE WHEN p_estado='ENTREGADA' THEN 'ENTREGADO' ELSE 'RECHAZADO' END WHERE nro_pedido=e.nro_pedido;
END; $$;

CREATE OR REPLACE FUNCTION public.busrax_cerrar_hoja(p_hoja integer)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE h public.hoja_ruta;
BEGIN
  SELECT * INTO h FROM public.hoja_ruta WHERE id_hoja=p_hoja FOR UPDATE;
  IF NOT FOUND OR h.estado<>'EN_CURSO' THEN RAISE EXCEPTION 'La hoja debe estar en curso'; END IF;
  IF EXISTS(SELECT 1 FROM public.entrega WHERE id_hoja=p_hoja AND estado='PENDIENTE') THEN RAISE EXCEPTION 'Todavía hay entregas sin resolver'; END IF;
  UPDATE public.hoja_ruta SET estado='CERRADA',fecha_hora_regreso=clock_timestamp() WHERE id_hoja=p_hoja;
END; $$;

CREATE OR REPLACE FUNCTION public.busrax_cancelar_pedido(p_pedido integer)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM public.pedido WHERE nro_pedido=p_pedido AND estado='PENDIENTE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solo se cancela un pedido pendiente'; END IF;
  IF EXISTS(SELECT 1 FROM public.movimiento_stock WHERE nro_pedido=p_pedido AND tipo='EGRESO') THEN RAISE EXCEPTION 'El pedido ya tiene egresos'; END IF;
  UPDATE public.pedido SET estado='CANCELADO' WHERE nro_pedido=p_pedido;
END; $$;

CREATE OR REPLACE FUNCTION public.busrax_cancelar_compra(p_compra integer)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM public.orden_compra WHERE nro_oc=p_compra AND estado='PENDIENTE' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solo se cancela una compra pendiente'; END IF;
  IF EXISTS(SELECT 1 FROM public.movimiento_stock WHERE nro_oc=p_compra AND tipo='INGRESO') THEN RAISE EXCEPTION 'La compra tiene recepciones parciales. Completá el saldo pendiente'; END IF;
  UPDATE public.orden_compra SET estado='CANCELADA' WHERE nro_oc=p_compra;
END; $$;

-- Permisos explícitos. Se conserva el acceso compartido del proyecto.
DO $$ DECLARE f record; BEGIN
  FOR f IN SELECT p.oid::regprocedure firma FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname LIKE 'busrax_%' LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.firma);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon,authenticated',f.firma);
  END LOOP;
END $$;
NOTIFY pgrst,'reload schema';
