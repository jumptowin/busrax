# BUSRAX Documento descriptivo del negocio

## Contexto

BUSRAX representa un centro de distribución de Ituzaingó, Corrientes, que compra productos de almacén, bebidas y limpieza y abastece comercios de la localidad y de la zona. Opera por cajas, packs y bultos cerrados. El catálogo tiene doce referencias; cada descripción indica el contenido del bulto y el peso unitario corresponde a ese bulto completo. La información combina un depósito central y un sector de higiene y limpieza para evitar mezclar ambos grupos en el almacenamiento.

El problema que se busca resolver es seguir la operación desde la compra hasta la entrega: saber cuánto queda disponible, qué está pendiente de recibir, qué se preparó y qué viaja en cada vehículo. Una confirmación incompleta no debe dejar cantidades descontadas sin que cambie el estado del pedido.

## Actores y responsabilidades

Compras decide la reposición y sigue las órdenes al proveedor. Depósito cuenta lo recibido, elige la ubicación y prepara pedidos. Planificación agrupa pedidos preparados, asigna vehículo y chofer y ordena las visitas. Reparto informa la entrega o el rechazo. La persona responsable de la operación consulta los indicadores. En esta versión estas son responsabilidades del proceso; la aplicación todavía no las separa con usuarios y permisos individuales.

## Datos

El modelo de BUSRAX tiene quince tablas: proveedor, producto, depósito, ubicación, stock, cliente, pedido, detalle de pedido, orden de compra, detalle de compra, movimiento de stock, vehículo, chofer, hoja de ruta y entrega. Las ubicaciones usan la clave compuesta depósito, pasillo, estante y nivel. El stock se identifica por producto y ubicación. Un pedido contiene renglones y tiene como máximo una entrega; cada hoja puede reunir varias entregas.

## Funciones logísticas

La reposición compara el stock total de cada producto con su mínimo. Si está en ese mínimo o por debajo, y no existe una compra pendiente del mismo producto, propone el lote de reposición. La orden y su detalle se crean juntos.

La recepción permite ingresar parte de lo comprado. Los ingresos se acumulan por orden y producto. La compra sigue pendiente hasta completar todos sus renglones y nunca se admite una cantidad mayor que el saldo. El stock aumenta por movimientos, no por una edición directa.

La preparación toma los renglones de un pedido pendiente y propone un recorrido por depósito, pasillo, estante y nivel. Si un producto está repartido entre ubicaciones, puede retirarse de varias. Todos los egresos y el cambio a PREPARADO se confirman juntos. Si falta un producto, la operación completa se revierte.

La distribución reúne pedidos preparados, controla el peso de la carga y verifica que el vehículo esté activo y la licencia vigente. Al iniciar la hoja, los pedidos pasan a DESPACHADO en la misma transacción. Cada resultado de entrega también actualiza su pedido. La hoja no se cierra con entregas sin resolver.

El panel muestra pedidos abiertos, entregas a tiempo, rechazos, compras pendientes, productos por reponer y ocupación. Agrega una alerta de pedidos cuya fecha comprometida ya pasó. El stock y los movimientos se pueden exportar a CSV.

## Reglas del negocio

Las cantidades de pedidos e ingresos son enteros positivos; los ajustes pueden ser negativos, con motivo obligatorio. Ningún movimiento puede dejar stock negativo ni superar la capacidad de la ubicación. En este ejercicio esa capacidad se aproxima en bultos; no reemplaza un cálculo volumétrico del depósito.

Cada producto conserva un proveedor principal. No se admiten compras duplicadas pendientes desde la función de reposición. No se cancela una compra con recepciones registradas ni un pedido ya preparado. El pedido no se prepara dos veces. No se agregan pedidos a una hoja que salió o cerró.

La licencia se vuelve a verificar al salir. No se permiten dos hojas en curso para un mismo vehículo o chofer. Una entrega conforme necesita receptor y un rechazo necesita motivo. El rechazo no es una devolución física automática: el reingreso debe controlarse y registrarse aparte.

El stock es un saldo operativo actualizado por un trigger; se conserva además el historial de movimientos para explicar cómo se llegó a ese saldo. El peso de los pedidos y los porcentajes se calculan mediante consultas.

## Pantallas y reportes

Panel, Stock, Compras, Pedidos, Rutas, Movimientos y Flota. La búsqueda de stock considera SKU, descripción, proveedor y ubicación. La exportación de movimientos incluye los últimos quinientos registros y conserva su referencia de pedido o compra. Los errores de la base se muestran en el formulario sin dar la operación por completada.

## Situación operativa actual

Tres proveedores, doce productos, dos sectores de depósito con siete ubicaciones, cuatro clientes, tres vehículos y tres choferes. Hay cuatro pedidos: uno entregado, dos preparados para un reparto y uno pendiente. Una compra de veinte cajas tiene cinco recibidas y quince pendientes. Uno de los pedidos preparados está atrasado. La hoja abierta lleva 614,8 kg.

## Requisitos técnicos

HTML, CSS y JavaScript, PostgreSQL en Supabase y una función breve de configuración para Vercel. La clave publicable se toma de variables de entorno y no se guarda en los archivos fuente. Se usa supabase-js 2.118.0 incluido con su licencia. Las operaciones compuestas se realizan con funciones SQL llamadas por RPC, con permisos del invocador y las políticas RLS del proyecto. El sitio se revisó en escritorio y en un marco de 390 píxeles para celular.
