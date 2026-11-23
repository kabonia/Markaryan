import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

test('material quantity = work × norm × (1 + waste), pieces rounded up', async () => {
  const { materialQuantity } = await import('../src/smeta.js');
  assert.equal(materialQuantity(100, 0.3, 5, 'м³'), 31.5);
  assert.equal(materialQuantity(10, 1.25, 10, 'шт'), 14);
  assert.equal(materialQuantity(10, 0, 10, 'м²'), 0);
  assert.equal(materialQuantity(10, 1, 400, 'м²'), 14); // waste is capped at 40 %
});

test('same material over several works becomes one purchase line', async () => {
  const { aggregateMaterials } = await import('../src/smeta.js');
  const lines = aggregateMaterials([
    { id: '1', materials: [{ name: 'Бетон B25', unit: 'м³', quantity: 10.2 }, { name: 'Арматура А500С Ø12', unit: 'т', quantity: 1.1 }] },
    { id: '2', materials: [{ name: 'бетон  B25', unit: 'м³', quantity: 5.1 }] },
  ]);
  assert.equal(lines.length, 2);
  const concrete = lines.find((l) => l.unit === 'м³');
  assert.equal(concrete.quantity, 15.3);
  assert.deepEqual(concrete.usedIn, ['1', '2']);
});

test('totals: delivery on materials, contingency on direct costs, VAT 22 % on top', async () => {
  const { totals } = await import('../src/smeta.js');
  const p = (x) => ({ low: x, typical: x, high: x });
  const t = totals([{ works: p(100_000), materials: p(200_000), machines: p(50_000) }], { vat: true, deliveryPct: 5, contingencyPct: 10 });
  assert.equal(t.typical.delivery, 10_000);
  assert.equal(t.typical.contingency, 36_000);
  assert.equal(t.typical.subtotal, 396_000);
  assert.equal(Math.round(t.typical.vat), 87_120);
  assert.equal(Math.round(t.typical.total), 483_120);
});

test('whole job: two readers, merge, norms, prices, audit additions, sections and totals', async () => {
  const { config } = await import('../src/config.js');
  config.dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'smeta-'));
  const smeta = await import('../src/smeta.js');
  const calls = [];
  smeta.setAgents({
    json: async ({ name, messages }) => {
      calls.push(name);
      if (name === 'vor') return { object: 'Дом', facts: ['стены 300 мм'], items: [{ section: 'Стены', name: 'Кладка', unit: 'м²', quantity: 100, formula: '', source: 'АР‑3' }] };
      if (name === 'vor_final') return { object: { name: 'Дом 10×10' }, works: [{ id: '1.1', section: 'Стены', name: 'Кладка газобетон D500 300 мм', unit: 'м²', quantity: 100, basis: 'АР‑3', confidence: 'high' }], assumptions: [], discrepancies: [] };
      if (name === 'norms') {
        const ids = [...messages[0].text.matchAll(/"id":"([^"]+)"/g)].map((m) => m[1]);
        return { works: ids.map((id) => ({ id, laborName: 'Кладка газобетона', materials: [{ name: 'Блок газобетон D500 600×300×250', unit: 'м³', norm: 0.3, waste: 5 }], machines: [] })) };
      }
      if (name === 'audit') return { verdict: 'Не хватает перемычек', issues: [{ severity: 'warning', text: 'Нет перемычек' }], additions: [{ section: 'Стены', name: 'Монтаж перемычек', unit: 'шт', quantity: 6, basis: 'проёмы АР‑5' }] };
      throw new Error(name);
    },
    prices: async ({ items }) => ({ items: items.map((it) => (it.kind === 'work' ? { typical: 1000, low: 800, high: 1500 } : { typical: 7000, low: 6500, high: 8000 })) }),
  });
  const input = smeta.cleanInput({ title: 'Дом', city: 'Сочи', docs: [{ name: 'АР.pdf', kind: 'ar', pages: [{ image: 'x'.repeat(200), text: 'план' }] }], options: { vat: false } });
  const job = { id: 'test', status: 'running' };
  await smeta.run(job, input);
  assert.equal(job.status, 'done', job.error);
  assert.equal(calls.filter((c) => c === 'vor').length, 2); // agents A and B
  const r = job.result;
  const walls = r.sections.find((s) => s.title === 'Стены');
  assert.equal(walls.items.length, 2);
  assert.equal(walls.items[0].materials[0].quantity, 31.5);
  assert.equal(Math.round(walls.works.typical), 100 * 1000 + 6 * 1000);
  assert.equal(Math.round(walls.materials.typical), Math.round((31.5 + 1.89) * 7000)); // the added lintels use blocks too in this mock
  assert.equal(r.audit.added, 1);
  assert.ok(r.totals.typical.total > r.totals.typical.subtotal - 1);
  smeta.setAgents();
});

test('xlsx: sheets become tab-separated text (shared, inline and rich strings, numbers, gaps)', async () => {
  const { xlsxToText } = await import('../src/xlsx.js');
  const text = xlsxToText(fs.readFileSync(new URL('./fixture.xlsx.b64', import.meta.url), 'utf8'));
  assert.equal(text, '## Смета\nНаименование\t\tКол-во\nБетон B25 & доставка\tм³\t12.5');
});
