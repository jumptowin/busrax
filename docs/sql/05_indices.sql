-- Índices para las claves foráneas y los filtros de trazabilidad.
CREATE INDEX IF NOT EXISTS busrax_detalle_oc_sku ON public.detalle_orden_compra(sku);
CREATE INDEX IF NOT EXISTS busrax_detalle_pedido_sku ON public.detalle_pedido(sku);
CREATE INDEX IF NOT EXISTS busrax_mov_ubicacion ON public.movimiento_stock(codigo_deposito,pasillo,estante,nivel);
CREATE INDEX IF NOT EXISTS busrax_mov_compra_sku ON public.movimiento_stock(nro_oc,sku);
CREATE INDEX IF NOT EXISTS busrax_mov_pedido ON public.movimiento_stock(nro_pedido);
CREATE INDEX IF NOT EXISTS busrax_mov_sku ON public.movimiento_stock(sku);
CREATE INDEX IF NOT EXISTS busrax_oc_proveedor ON public.orden_compra(cuit_proveedor);
CREATE INDEX IF NOT EXISTS busrax_pedido_cliente ON public.pedido(cuit_cliente);
CREATE INDEX IF NOT EXISTS busrax_producto_proveedor ON public.producto(cuit_proveedor);
CREATE INDEX IF NOT EXISTS busrax_stock_ubicacion ON public.stock(codigo_deposito,pasillo,estante,nivel);
