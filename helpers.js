(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.Busrax = api;
})(typeof globalThis === 'object' ? globalThis : this, function () {
  'use strict';
  const ubicacion = (s) => [s.codigo_deposito, s.pasillo, s.estante, s.nivel].join('-');
  function hoy(date = new Date()) {
    return new Intl.DateTimeFormat('sv-SE', { timeZone: 'America/Argentina/Cordoba' }).format(date);
  }
  function planPicking(detalles, stock) {
    const lineas = [], faltantes = [];
    for (const d of [...detalles].sort((a, b) => a.sku.localeCompare(b.sku))) {
      let falta = d.cantidad;
      for (const s of stock.filter((s) => s.sku === d.sku && s.cantidad > 0).sort((a, b) =>
        a.codigo_deposito.localeCompare(b.codigo_deposito) || a.pasillo.localeCompare(b.pasillo) || a.estante-b.estante || a.nivel-b.nivel)) {
        const tomar = Math.min(falta, s.cantidad);
        if (tomar) lineas.push({ ...s, cantidad: tomar });
        falta -= tomar;
        if (!falta) break;
      }
      if (falta > 0) faltantes.push({ sku: d.sku, cantidad: falta });
    }
    return { lineas, faltantes };
  }
  function csvCell(value) {
    let s = String(value ?? '');
    if (typeof value !== 'number' && /^[\s]*[=+@-]/.test(s)) s = "'" + s;
    return '"' + s.replace(/"/g, '""') + '"';
  }
  function csv(headers, rows) {
    return '\ufeff' + [headers, ...rows].map((r) => r.map(csvCell).join(';')).join('\r\n');
  }
  return { hoy, ubicacion, planPicking, csv };
});
