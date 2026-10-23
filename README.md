# BUSRAX

Sistema de operaciones de un centro de distribución de productos de almacén, bebidas y limpieza en Ituzaingó, Corrientes. El proyecto desarrolla cinco funciones logísticas: reposición, recepción y trazabilidad, preparación de pedidos, distribución e indicadores.

## Integrantes

- Sala Santiago
- Salinas Maximiliano
- Rivero Federico

## Funciones del sistema

- La recepción conserva el saldo de una compra parcialmente recibida y rechaza un ingreso mayor que ese saldo.
- El picking puede tomar un renglón desde varias ubicaciones y confirma todos los descuentos juntos.
- El alta de pedidos, la salida de un viaje y el resultado de una entrega se guardan en una transacción por operación.
- El panel identifica pedidos atrasados. El stock se puede buscar y exportar a CSV; también se exportan los últimos 500 movimientos.
- La interfaz se adaptó al celular, con navegación accesible, foco en los formularios y mensajes de error concretos.
- La clave publicable de Supabase se obtiene de la configuración del servidor. El repositorio no lleva valores de claves.

## Ejecutar en la computadora

Requiere Node.js 22 o posterior. No hay dependencias que instalar.

1. Copiar `.env.example` como `.env`.
2. Completar `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` con los datos del proyecto.
3. Ejecutar `npm run dev` y abrir `http://localhost:4173`.
4. Ejecutar `npm test` para las pruebas de los cálculos y de la exportación.

La copia de supabase-js incluida en `vendor` es la versión 2.118.0 y conserva su licencia MIT.

## Base de datos

Los scripts de creación y carga inicial se ejecutan solamente en una base vacía. No se debe repetir su ejecución en una base que ya contiene datos.

En una base nueva y vacía, ejecutar en este orden:

1. `docs/sql/01_crear_base.sql`
2. `docs/sql/03_seguridad_rls.sql`
3. `docs/sql/04_mejoras_busrax.sql`
4. `docs/sql/05_indices.sql`
5. `docs/sql/02_datos_ejemplo.sql`

La instalación completa fue comprobada en un esquema aislado que se revirtió al terminar. Reproduce 15 tablas con RLS, 12 productos y 352 bultos de stock.

`tests/integracion.sql` ejecuta 14 comprobaciones con el mismo rol `anon` de la app y revierte sus datos de prueba. `tests/instalacion.sql` comprueba la instalación completa y revierte el esquema de verificación. Las secuencias de PostgreSQL pueden dejar huecos de numeración tras las pruebas; no indican pedidos perdidos.

## Publicar en Vercel

Importar el código como proyecto de tipo Other, sin comando de compilación y con la raíz como directorio del proyecto. Configurar en Vercel `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`. La función `api/config.js` devuelve solo estos datos públicos. Nunca configurar una clave `service_role` o `sb_secret_` en ese campo.

## Alcance de la versión actual

La base usa una política de acceso compartida: lectura y operaciones con el rol público, sin borrar registros y sin editar stock directamente. RLS está activo en las 15 tablas. No hay cuentas separadas ni permisos distintos por operador; esos roles se describen como responsabilidades del proceso. Como próximo paso se prevé incorporar autenticación y autorización por usuario.

No se optimizan recorridos geográficos automáticamente. Las hojas organizan la carga y el orden de visita y controlan peso, vehículo y licencia. Un rechazo no vuelve a sumar mercadería al stock: el reingreso requiere control físico y un movimiento justificado.

## Carpetas

- `docs/documento_descriptivo.md`: contexto, funciones y reglas del negocio.
- `docs/diagramas`: modelos y proceso en PNG, SVG y draw.io editable.
- `docs/sql`: instalación y actualización de la base.
- `docs/etapa1`: modelo y pruebas correspondientes a la primera etapa del proyecto.
- `docs/evidencias`: pruebas y capturas de la versión actual.
- `tests`: comprobaciones reproducibles.
