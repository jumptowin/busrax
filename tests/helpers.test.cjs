const { test } = require('node:test');
const assert = require('node:assert/strict');
const { planPicking, hoy, csv } = require('../helpers.js');
const stock = [
  { sku:'A', codigo_deposito:'D1', pasillo:'A', estante:2, nivel:1, cantidad:7 },
  { sku:'A', codigo_deposito:'D1', pasillo:'A', estante:1, nivel:1, cantidad:4 }
];
test('prepara un renglón desde varias ubicaciones sin mutar el stock consultado', () => {
  const plan = planPicking([{sku:'A',cantidad:9}],stock);
  assert.deepEqual(plan.lineas.map(x=>[x.estante,x.cantidad]),[[1,4],[2,5]]);
  assert.equal(plan.faltantes.length,0);
  assert.equal(stock[0].cantidad,7);
});
test('informa el faltante por producto y conserva el renglón sin disponibilidad', () => {
  const plan = planPicking([{sku:'A',cantidad:12},{sku:'B',cantidad:3}],stock);
  assert.deepEqual(plan.faltantes,[{sku:'A',cantidad:1},{sku:'B',cantidad:3}]);
});
test('usa la fecha de Argentina en el cambio de día UTC', () => {
  assert.equal(hoy(new Date('2026-10-23T01:00:00Z')),'2026-10-22');
});
test('el CSV conserva comillas y acentos y neutraliza fórmulas', () => {
  const text=csv(['Producto','Cantidad'],[['=HYPERLINK("x")',2],['Bebida "limón"',-1]]);
  assert.ok(text.startsWith('\ufeff'));
  assert.ok(text.includes('"\'=HYPERLINK(""x"")";"2"'));
  assert.ok(text.includes('"Bebida ""limón""";"-1"'));
});
