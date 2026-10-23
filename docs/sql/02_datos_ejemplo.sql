-- BUSRAX. Carga inicial de datos de la operatoria regional.
-- No son clientes, contactos ni empleados reales. No contiene teléfonos.
-- Solo para una base vacía. No borra registros. Fecha de referencia: 23/10/2026.
BEGIN;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM public.producto) THEN RAISE EXCEPTION 'La base ya tiene un catálogo. No repitas la carga inicial'; END IF; END $$;
INSERT INTO public.proveedor(cuit,telefono,razon_social,plazo_entrega_dias) VALUES
 ('30711111119',NULL,'Mayorista San Roque',3),
 ('30722222228',NULL,'Bebidas del Paraná',2),
 ('30733333337',NULL,'Química Santa Rita',2);
INSERT INTO public.producto(sku,descripcion,stock_minimo,unidad_medida,cuit_proveedor,lote_reposicion,peso_unitario_kg) VALUES
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
INSERT INTO public.deposito(codigo,nombre,direccion) VALUES
 ('D1','Depósito central','Sector de abastecimiento · Ituzaingó, Corrientes'),
 ('D2','Sector higiene y limpieza','Sector de reparto · Ituzaingó, Corrientes');
INSERT INTO public.ubicacion(nivel,estante,pasillo,capacidad_unid,codigo_deposito) VALUES
 (1,1,'A',100,'D1'),
 (2,1,'A',100,'D1'),
 (1,1,'B',80,'D1'),
 (1,2,'B',80,'D1'),
 (1,1,'C',60,'D1'),
 (1,1,'A',60,'D2'),
 (2,1,'A',60,'D2');
INSERT INTO public.cliente(cuit,zona,razon_social,direccion_entrega) VALUES
 ('30744444446','Ituzaingó Centro','Autoservicio El Timbó','Zona comercial · Ituzaingó'),
 ('30755555555','Villa Olivari','Despensa La Ribera','Zona urbana · Villa Olivari'),
 ('20123456786','Ituzaingó Centro','Almacén Los Lapachos','Zona centro · Ituzaingó'),
 ('30766666664','Virasoro','Comercial San Miguel','Zona comercial · Virasoro');
INSERT INTO public.vehiculo(activo,patente,descripcion,capacidad_kg) VALUES
 (true,'AE123BC','Utilitario Fiorino',650),
 (true,'AD456FG','Camión liviano 3,5 t',3500),
 (false,'AB789CD','Furgón Sprinter',1500);
INSERT INTO public.chofer(legajo,nombre,licencia_vencimiento) VALUES
 (1001,'Ramiro Acosta','2027-10-23'),
 (1002,'Lucía Duarte','2027-10-23'),
 (1003,'Hugo Benítez','2026-10-11');
DO $carga$
DECLARE r jsonb; n integer; pedidos jsonb:='{}'; compras jsonb:='{}'; hojas jsonb:='{}';
BEGIN
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-20","estado":"ENTREGADO","nro_pedido":1,"cuit_cliente":"30744444446","fecha_compromiso":"2026-10-21"},{"fecha":"2026-10-22","estado":"PREPARADO","nro_pedido":2,"cuit_cliente":"30755555555","fecha_compromiso":"2026-10-23"},{"fecha":"2026-10-23","estado":"PENDIENTE","nro_pedido":3,"cuit_cliente":"20123456786","fecha_compromiso":"2026-10-24"},{"fecha":"2026-10-21","estado":"PREPARADO","nro_pedido":4,"cuit_cliente":"30766666664","fecha_compromiso":"2026-10-22"}]$datos$::jsonb) LOOP
  INSERT INTO public.pedido(cuit_cliente,fecha,fecha_compromiso,estado)
   VALUES(r->>'cuit_cliente',(r->>'fecha')::date,(r->>'fecha_compromiso')::date,'PREPARADO') RETURNING nro_pedido INTO n;
   pedidos:=pedidos||jsonb_build_object(r->>'nro_pedido',n);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"sku":"ALM-001","cantidad":10,"nro_pedido":1},{"sku":"BEB-001","cantidad":8,"nro_pedido":1},{"sku":"BEB-002","cantidad":12,"nro_pedido":2},{"sku":"LIM-001","cantidad":5,"nro_pedido":2},{"sku":"ALM-002","cantidad":6,"nro_pedido":3},{"sku":"ALM-001","cantidad":20,"nro_pedido":4},{"sku":"BEB-001","cantidad":15,"nro_pedido":4},{"sku":"LIM-002","cantidad":4,"nro_pedido":4}]$datos$::jsonb) LOOP
  INSERT INTO public.detalle_pedido(nro_pedido,sku,cantidad)
   VALUES((pedidos->>(r->>'nro_pedido'))::integer,r->>'sku',(r->>'cantidad')::integer);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-18","estado":"RECIBIDA","nro_oc":1,"cuit_proveedor":"30733333337","fecha_recepcion":"2026-10-22"},{"fecha":"2026-10-23","estado":"PENDIENTE","nro_oc":2,"cuit_proveedor":"30733333337","fecha_recepcion":null}]$datos$::jsonb) LOOP
  INSERT INTO public.orden_compra(cuit_proveedor,fecha)
   VALUES(r->>'cuit_proveedor',(r->>'fecha')::date) RETURNING nro_oc INTO n;
   compras:=compras||jsonb_build_object(r->>'nro_oc',n);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"sku":"LIM-002","nro_oc":2,"cantidad":20},{"sku":"LIM-001","nro_oc":1,"cantidad":50}]$datos$::jsonb) LOOP
  INSERT INTO public.detalle_orden_compra(nro_oc,sku,cantidad)
   VALUES((compras->>(r->>'nro_oc'))::integer,r->>'sku',(r->>'cantidad')::integer);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-21","estado":"CERRADA","id_hoja":1,"patente":"AD456FG","legajo_chofer":1001,"fecha_hora_salida":"2026-10-21T11:30:00+00:00","fecha_hora_regreso":"2026-10-21T19:00:00+00:00"},{"fecha":"2026-10-23","estado":"PLANIFICADA","id_hoja":3,"patente":"AD456FG","legajo_chofer":1001,"fecha_hora_salida":null,"fecha_hora_regreso":null}]$datos$::jsonb) LOOP
  INSERT INTO public.hoja_ruta(fecha,patente,legajo_chofer)
   VALUES((r->>'fecha')::date,r->>'patente',(r->>'legajo_chofer')::integer) RETURNING id_hoja INTO n;
   hojas:=hojas||jsonb_build_object(r->>'id_hoja',n);
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"sku":"ALM-001","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":60,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":1,"codigo_deposito":"D1"},{"sku":"ALM-002","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":40,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":2,"codigo_deposito":"D1"},{"sku":"BEB-001","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"B","cantidad":70,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":3,"codigo_deposito":"D1"},{"sku":"BEB-002","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":2,"pasillo":"B","cantidad":50,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":4,"codigo_deposito":"D1"},{"sku":"LIM-001","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":30,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":5,"codigo_deposito":"D2"},{"sku":"LIM-002","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":12,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":6,"codigo_deposito":"D2"},{"sku":"ALM-001","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":20,"fecha_hora":"2026-10-01T11:00:00+00:00","nro_pedido":null,"observacion":"Stock inicial","id_movimiento":7,"codigo_deposito":"D2"},{"sku":"ALM-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":10,"fecha_hora":"2026-10-12T18:00:00+00:00","nro_pedido":1,"observacion":null,"id_movimiento":8,"codigo_deposito":"D1"},{"sku":"BEB-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"B","cantidad":8,"fecha_hora":"2026-10-12T18:00:00+00:00","nro_pedido":1,"observacion":null,"id_movimiento":9,"codigo_deposito":"D1"},{"sku":"BEB-002","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":2,"pasillo":"B","cantidad":12,"fecha_hora":"2026-10-13T12:00:00+00:00","nro_pedido":2,"observacion":null,"id_movimiento":10,"codigo_deposito":"D1"},{"sku":"LIM-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":5,"fecha_hora":"2026-10-13T12:00:00+00:00","nro_pedido":2,"observacion":null,"id_movimiento":11,"codigo_deposito":"D2"},{"sku":"LIM-001","tipo":"INGRESO","nivel":1,"nro_oc":1,"estante":1,"pasillo":"A","cantidad":50,"fecha_hora":"2026-10-22T22:18:10.245174+00:00","nro_pedido":null,"observacion":"Recepción OC 1","id_movimiento":13,"codigo_deposito":"D1"},{"sku":"ALM-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":20,"fecha_hora":"2026-10-22T22:19:23.400954+00:00","nro_pedido":4,"observacion":null,"id_movimiento":14,"codigo_deposito":"D2"},{"sku":"BEB-001","tipo":"EGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"B","cantidad":15,"fecha_hora":"2026-10-22T22:19:24.077055+00:00","nro_pedido":4,"observacion":null,"id_movimiento":15,"codigo_deposito":"D1"},{"sku":"LIM-002","tipo":"EGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":4,"fecha_hora":"2026-10-22T22:19:24.250558+00:00","nro_pedido":4,"observacion":null,"id_movimiento":16,"codigo_deposito":"D2"},{"sku":"ALM-003","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":24,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":36,"codigo_deposito":"D1"},{"sku":"ALM-004","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":18,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":37,"codigo_deposito":"D1"},{"sku":"ALM-005","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"C","cantidad":12,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":38,"codigo_deposito":"D1"},{"sku":"BEB-003","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":2,"pasillo":"B","cantidad":14,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":39,"codigo_deposito":"D1"},{"sku":"LIM-003","tipo":"INGRESO","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":12,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":40,"codigo_deposito":"D2"},{"sku":"LIM-004","tipo":"INGRESO","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":9,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Carga de escenario BUSRAX","id_movimiento":41,"codigo_deposito":"D2"},{"sku":"LIM-002","tipo":"INGRESO","nivel":2,"nro_oc":2,"estante":1,"pasillo":"A","cantidad":5,"fecha_hora":"2026-10-23T04:03:44.75661+00:00","nro_pedido":null,"observacion":"Recepción BUSRAX OC 2","id_movimiento":42,"codigo_deposito":"D2"},{"sku":"LIM-001","tipo":"AJUSTE","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":-50,"fecha_hora":"2026-10-23T04:07:43.632551+00:00","nro_pedido":null,"observacion":"Traslado a sector limpieza","id_movimiento":43,"codigo_deposito":"D1"},{"sku":"LIM-001","tipo":"AJUSTE","nivel":1,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":23,"fecha_hora":"2026-10-23T04:07:43.632551+00:00","nro_pedido":null,"observacion":"Traslado desde depósito central","id_movimiento":44,"codigo_deposito":"D2"},{"sku":"LIM-001","tipo":"AJUSTE","nivel":2,"nro_oc":null,"estante":1,"pasillo":"A","cantidad":27,"fecha_hora":"2026-10-23T04:07:43.632551+00:00","nro_pedido":null,"observacion":"Traslado desde depósito central","id_movimiento":45,"codigo_deposito":"D2"}]$datos$::jsonb) LOOP
  INSERT INTO public.movimiento_stock(fecha_hora,tipo,sku,codigo_deposito,pasillo,estante,nivel,cantidad,nro_pedido,nro_oc,observacion)
   VALUES((r->>'fecha_hora')::timestamptz,r->>'tipo',r->>'sku',r->>'codigo_deposito',r->>'pasillo',
   (r->>'estante')::smallint,(r->>'nivel')::smallint,(r->>'cantidad')::integer,
   (pedidos->>(r->>'nro_pedido'))::integer,(compras->>(r->>'nro_oc'))::integer,r->>'observacion');
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"estado":"ENTREGADA","id_hoja":1,"receptor":"Carlos Molina","id_entrega":1,"nro_pedido":1,"orden_visita":1,"motivo_rechazo":null,"fecha_hora_entrega":"2026-10-21T16:00:00+00:00"},{"estado":"PENDIENTE","id_hoja":3,"receptor":null,"id_entrega":5,"nro_pedido":4,"orden_visita":1,"motivo_rechazo":null,"fecha_hora_entrega":null},{"estado":"PENDIENTE","id_hoja":3,"receptor":null,"id_entrega":6,"nro_pedido":2,"orden_visita":2,"motivo_rechazo":null,"fecha_hora_entrega":null}]$datos$::jsonb) LOOP
  INSERT INTO public.entrega(nro_pedido,id_hoja,orden_visita)
   VALUES((pedidos->>(r->>'nro_pedido'))::integer,(hojas->>(r->>'id_hoja'))::integer,(r->>'orden_visita')::smallint) RETURNING id_entrega INTO n;
   UPDATE public.entrega SET estado=r->>'estado',fecha_hora_entrega=(r->>'fecha_hora_entrega')::timestamptz,
   receptor=r->>'receptor',motivo_rechazo=r->>'motivo_rechazo' WHERE id_entrega=n;
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-20","estado":"ENTREGADO","nro_pedido":1,"cuit_cliente":"30744444446","fecha_compromiso":"2026-10-21"},{"fecha":"2026-10-22","estado":"PREPARADO","nro_pedido":2,"cuit_cliente":"30755555555","fecha_compromiso":"2026-10-23"},{"fecha":"2026-10-23","estado":"PENDIENTE","nro_pedido":3,"cuit_cliente":"20123456786","fecha_compromiso":"2026-10-24"},{"fecha":"2026-10-21","estado":"PREPARADO","nro_pedido":4,"cuit_cliente":"30766666664","fecha_compromiso":"2026-10-22"}]$datos$::jsonb) LOOP
  UPDATE public.pedido SET estado=r->>'estado' WHERE nro_pedido=(pedidos->>(r->>'nro_pedido'))::integer;
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-18","estado":"RECIBIDA","nro_oc":1,"cuit_proveedor":"30733333337","fecha_recepcion":"2026-10-22"},{"fecha":"2026-10-23","estado":"PENDIENTE","nro_oc":2,"cuit_proveedor":"30733333337","fecha_recepcion":null}]$datos$::jsonb) LOOP
  UPDATE public.orden_compra SET estado=r->>'estado',fecha_recepcion=(r->>'fecha_recepcion')::date WHERE nro_oc=(compras->>(r->>'nro_oc'))::integer;
 END LOOP;
 FOR r IN SELECT value FROM jsonb_array_elements($datos$[{"fecha":"2026-10-21","estado":"CERRADA","id_hoja":1,"patente":"AD456FG","legajo_chofer":1001,"fecha_hora_salida":"2026-10-21T11:30:00+00:00","fecha_hora_regreso":"2026-10-21T19:00:00+00:00"},{"fecha":"2026-10-23","estado":"PLANIFICADA","id_hoja":3,"patente":"AD456FG","legajo_chofer":1001,"fecha_hora_salida":null,"fecha_hora_regreso":null}]$datos$::jsonb) LOOP
  UPDATE public.hoja_ruta SET estado=r->>'estado',fecha_hora_salida=(r->>'fecha_hora_salida')::timestamptz,
   fecha_hora_regreso=(r->>'fecha_hora_regreso')::timestamptz WHERE id_hoja=(hojas->>(r->>'id_hoja'))::integer;
 END LOOP;
END; $carga$;
COMMIT;
SELECT * FROM public.v_indicadores;
