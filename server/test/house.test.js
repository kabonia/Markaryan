import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

test('house: quantities follow the geometry, sections and totals add up', async () => {
  const { config } = await import('../src/config.js');
  config.dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'house-'));
  const house = await import('../src/house.js');
  const r = house.estimate({ length: 12, width: 10, floors: 2, walls: 'gasblock', foundation: 'strip', finish: 'rough', city: 'Сочи' });
  const g = house.geometry(house.cleanParams({ length: 12, width: 10, floors: 2 }));
  assert.equal(g.P, 44);
  assert.equal(g.area, 240);
  const strip = r.sections.find((s) => s.title === 'Фундамент').items.find((i) => i.name.startsWith('Устройство ленточного'));
  assert.ok(Math.abs(strip.quantity - (44 + 12) * 0.4 * 1.5 * 1.02) < 0.05); // perimeter + inner bearing wall
  const sum = r.sections.reduce((t, s) => t + s.works.typical + s.materials.typical + s.machines.typical, 0);
  const t = r.totals.typical;
  assert.ok(Math.abs(sum - (t.works + t.materials + t.machines + t.delivery)) < 1);
  assert.ok(r.sections.some((s) => s.title === 'Техника и доставка'));
  assert.equal(r.prices.real, 0); // no weekly book yet — every price is a marked guide
  assert.ok(r.sections.every((s) => s.items.every((i) => i.price.estimated)));
});

test('house: a real weekly price replaces the guide; frame house on piles has no plaster and no screed', async () => {
  const { config } = await import('../src/config.js');
  config.dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'house-'));
  const house = await import('../src/house.js');
  fs.mkdirSync(path.join(config.dataDir, 'house-prices'));
  fs.writeFileSync(path.join(config.dataDir, 'house-prices', 'сочи.json'), JSON.stringify({ city: 'Сочи', lat: 43.59, lon: 39.72, updatedAt: '2026-11-24T00:00:00Z', items: { pile: { low: 3000, typical: 3300, high: 3800, sources: [{ title: 'x', url: 'https://x.ru' }] } } }));
  const r = house.estimate({ length: 9, width: 8, floors: 1, walls: 'frame', foundation: 'piles', finish: 'turnkey', city: 'Сочи' });
  const piles = r.sections.find((s) => s.title === 'Фундамент').items[0].materials[0];
  assert.equal(piles.price.typical, 3300);
  assert.ok(!piles.price.estimated);
  const finish = r.sections.find((s) => s.title === 'Внутренняя отделка').items.map((i) => i.name);
  assert.ok(!finish.some((n) => n.startsWith('Штукатурка')));
  assert.ok(!finish.some((n) => n.startsWith('Стяжка')));
  assert.throws(() => house.estimate({ walls: 'brick', foundation: 'piles' }), /сваи/);
});
