-- Pruebas de integración en Supabase. Los datos se revierten al finalizar.
-- El bloque de comprobación funciona con el rol anon usado por la aplicación.
CREATE OR REPLACE FUNCTION pg_temp.busrax_verificar() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb:='[]'; n integer; p1 integer; p2 integer; oc integer; h integer; e integer;
  antes integer; despues integer; estado text; rechazado boolean;
BEGIN
  BEGIN
    INSERT INTO public.proveedor(cuit,razon_social,plazo_entrega_dias) VALUES('30999999001','Proveedor de prueba BUSRAX',2);
    INSERT INTO public.cliente(cuit,razon_social,direccion_entrega,zona) VALUES('20999999001','Cliente de prueba BUSRAX','Dirección de control','Prueba');
    INSERT INTO public.deposito VALUES('TBRX','Depósito de prueba','Dirección de control');
    INSERT INTO public.ubicacion VALUES('TBRX','A',1,1,100),('TBRX','A',2,1,100);
    INSERT INTO public.producto VALUES('TST-BRX-A','Producto de prueba A','UN',1,'30999999001',10,10),('TST-BRX-B','Producto de prueba B','UN',1,'30999999001',10,10);
    INSERT INTO public.vehiculo VALUES('ZZ901ZZ','Vehículo de prueba',40,true),('ZZ902ZZ','Vehículo de 5 kg',5,true);
    INSERT INTO public.chofer VALUES(900001,'Chofer de prueba',CURRENT_DATE+365),(900002,'Chofer vencido de prueba',CURRENT_DATE-1);
    INSERT INTO public.movimiento_stock(tipo,sku,codigo_deposito,pasillo,estante,nivel,cantidad,observacion)
      VALUES('INGRESO','TST-BRX-A','TBRX','A',1,1,3,'Prueba'),('INGRESO','TST-BRX-A','TBRX','A',2,1,4,'Prueba'),('INGRESO','TST-BRX-B','TBRX','A',2,1,2,'Prueba');
    PERFORM set_config('role','anon',true);

    p1:=public.busrax_crear_pedido('20999999001',CURRENT_DATE,'[{"sku":"TST-BRX-A","cantidad":6},{"sku":"TST-BRX-B","cantidad":1}]');
    IF (SELECT count(*) FROM public.detalle_pedido WHERE nro_pedido=p1)<>2 THEN RAISE EXCEPTION 'Falla: pedido incompleto'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Pedido válido con dos renglones','resultado','OK'));

    SELECT count(*) INTO antes FROM public.pedido;
    rechazado:=false;
    BEGIN
      PERFORM public.busrax_crear_pedido('20999999001',CURRENT_DATE,'[{"sku":"SKU_INEXISTENTE","cantidad":1}]');
    EXCEPTION WHEN foreign_key_violation THEN rechazado:=true; END;
    IF NOT rechazado OR (SELECT count(*) FROM public.pedido)<>antes THEN RAISE EXCEPTION 'Falla: quedó una cabecera sin detalle'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','SKU inexistente no deja un pedido huérfano','resultado','OK'));

    n:=public.busrax_preparar_pedido(p1);
    IF n<>3 OR (SELECT sum(cantidad) FROM public.stock WHERE sku='TST-BRX-A')<>1 THEN RAISE EXCEPTION 'Falla: picking repartido'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Picking de 6 unidades desde ubicaciones con 3 y 4','resultado','OK','movimientos',n,'saldo',1));
    rechazado:=false;
    BEGIN PERFORM public.busrax_preparar_pedido(p1); EXCEPTION WHEN raise_exception THEN rechazado:=true; END;
    IF NOT rechazado OR (SELECT sum(cantidad) FROM public.stock WHERE sku='TST-BRX-A')<>1 THEN RAISE EXCEPTION 'Falla: doble picking'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Segundo picking del mismo pedido rechazado','resultado','OK'));

    p2:=public.busrax_crear_pedido('20999999001',CURRENT_DATE,'[{"sku":"TST-BRX-A","cantidad":1},{"sku":"TST-BRX-B","cantidad":99}]');
    rechazado:=false;
    BEGIN PERFORM public.busrax_preparar_pedido(p2); EXCEPTION WHEN raise_exception THEN rechazado:=true; END;
    IF NOT rechazado OR (SELECT sum(cantidad) FROM public.stock WHERE sku='TST-BRX-A')<>1
      OR EXISTS(SELECT 1 FROM public.movimiento_stock WHERE nro_pedido=p2) THEN RAISE EXCEPTION 'Falla: descuento parcial'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Faltante en el segundo renglón revierte el primero','resultado','OK','egresos_persistidos',0));

    oc:=public.busrax_reponer('TST-BRX-A');
    estado:=public.busrax_recibir_compra(oc,'[{"sku":"TST-BRX-A","codigo_deposito":"TBRX","pasillo":"A","estante":1,"nivel":1,"cantidad":3}]');
    IF estado<>'PENDIENTE' THEN RAISE EXCEPTION 'Falla: recepción parcial cerrada'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Recepción de 3 sobre 10 conserva la compra pendiente','resultado','OK','saldo_por_recibir',7));
    rechazado:=false;
    BEGIN PERFORM public.busrax_reponer('TST-BRX-A'); EXCEPTION WHEN raise_exception THEN rechazado:=true; END;
    IF NOT rechazado THEN RAISE EXCEPTION 'Falla: compra duplicada'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Reposición duplicada rechazada','resultado','OK'));
    rechazado:=false;
    BEGIN PERFORM public.busrax_recibir_compra(oc,'[{"sku":"TST-BRX-A","codigo_deposito":"TBRX","pasillo":"A","estante":1,"nivel":1,"cantidad":8}]'); EXCEPTION WHEN raise_exception THEN rechazado:=true; END;
    IF NOT rechazado OR (SELECT sum(cantidad) FROM public.stock WHERE sku='TST-BRX-A')<>4 THEN RAISE EXCEPTION 'Falla: sobre recepción'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Ingreso mayor que el saldo rechazado sin mover stock','resultado','OK'));
    estado:=public.busrax_recibir_compra(oc,'[{"sku":"TST-BRX-A","codigo_deposito":"TBRX","pasillo":"A","estante":1,"nivel":1,"cantidad":7}]');
    IF estado<>'RECIBIDA' THEN RAISE EXCEPTION 'Falla: compra no finalizada'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Recepción del saldo completa la compra','resultado','OK','stock_final',11));

    rechazado:=false;
    BEGIN INSERT INTO public.hoja_ruta(fecha,patente,legajo_chofer) VALUES(CURRENT_DATE,'ZZ901ZZ',900002); EXCEPTION WHEN raise_exception THEN rechazado:=true; END;
    IF NOT rechazado THEN RAISE EXCEPTION 'Falla: licencia vencida'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Hoja de ruta con licencia vencida rechazada','resultado','OK'));
    INSERT INTO public.hoja_ruta(fecha,patente,legajo_chofer) VALUES(CURRENT_DATE,'ZZ902ZZ',900001) RETURNING id_hoja INTO h;
    rechazado:=false;
    BEGIN INSERT INTO public.entrega(nro_pedido,id_hoja,orden_visita) VALUES(p1,h,1); EXCEPTION WHEN raise_exception THEN rechazado:=true; END;
    IF NOT rechazado THEN RAISE EXCEPTION 'Falla: exceso de carga'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Pedido de 7 kg no cabe en vehículo de 5 kg','resultado','OK'));
    INSERT INTO public.hoja_ruta(fecha,patente,legajo_chofer) VALUES(CURRENT_DATE,'ZZ901ZZ',900001) RETURNING id_hoja INTO h;
    INSERT INTO public.entrega(nro_pedido,id_hoja,orden_visita) VALUES(p1,h,1) RETURNING id_entrega INTO e;
    PERFORM public.busrax_iniciar_hoja(h);
    IF (SELECT pe.estado FROM public.pedido pe WHERE pe.nro_pedido=p1)<>'DESPACHADO' THEN RAISE EXCEPTION 'Falla: salida sin despacho'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Salida y despacho de pedido confirmados juntos','resultado','OK'));
    rechazado:=false;
    BEGIN PERFORM public.busrax_cerrar_hoja(h); EXCEPTION WHEN raise_exception THEN rechazado:=true; END;
    IF NOT rechazado THEN RAISE EXCEPTION 'Falla: cierre anticipado'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Cierre con una entrega pendiente rechazado','resultado','OK'));
    PERFORM public.busrax_registrar_entrega(e,'ENTREGADA','Receptor de prueba');
    PERFORM public.busrax_cerrar_hoja(h);
    IF (SELECT pe.estado FROM public.pedido pe WHERE pe.nro_pedido=p1)<>'ENTREGADO' OR (SELECT hr.estado FROM public.hoja_ruta hr WHERE hr.id_hoja=h)<>'CERRADA'
      THEN RAISE EXCEPTION 'Falla: recorrido completo'; END IF;
    r:=r||jsonb_build_array(jsonb_build_object('prueba','Entrega y cierre de viaje completos','resultado','OK'));
    -- Provoca la reversión de todos los registros creados por las pruebas.
    RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='Revertir datos de prueba';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
  END;
  RETURN jsonb_build_object('pruebas',r,'datos_de_prueba','revertidos','fecha',CURRENT_TIMESTAMP);
END; $$;
SELECT pg_temp.busrax_verificar() AS evidencia;
