import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, execFileSync } from 'node:child_process';

test('aggregate drops outliers and returns quartiles', async () => {
  const { aggregate } = await import('../src/market.js');
  const r = aggregate([7600, 7800, 7900, 8000, 8100, 7700, 1, 95000, 0, -5]);
  assert.equal(r.typical, 7850);
  assert.equal(r.sources, 6);
  assert.equal(r.dropped, 2);
  assert.ok(r.low < r.typical && r.typical < r.high);
});

test('normalizePlace', async () => {
  const { normalizePlace } = await import('../src/market.js');
  assert.equal(normalizePlace('г. Сочи'), 'сочи');
  assert.equal(normalizePlace('Краснодарский край'), 'краснодарский');
  assert.equal(normalizePlace('Орёл'), 'орел');
  assert.equal(normalizePlace('Республика Татарстан'), 'татарстан');
});

test('price book by city / nearby, partners', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'market-'));
  const prices = path.join(dir, 'prices'), data = path.join(dir, 'data');
  fs.mkdirSync(prices);
  fs.writeFileSync(path.join(prices, 'sochi.json'), JSON.stringify({ city: 'Сочи', region: 'Краснодарский край', lat: 43.585, lon: 39.723, updatedAt: '2026-11-19T00:00:00Z', lines: [{ code: 'concrete', materialRate: 7850 }] }));
  const PORT = 18_766;
  const child = spawn(process.execPath, ['src/index.js'], { env: { ...process.env, PORT: String(PORT), DATA_DIR: data, MARKET_DIR: prices, PARTNERS_ADMIN_KEY: 'secret-key', GIGACHAT_AUTH_KEY: '', YANDEX_API_KEY: '' }, stdio: 'pipe' });
  t.after(() => { child.kill(); fs.rmSync(dir, { recursive: true, force: true }); });
  await new Promise((resolve) => child.stdout.once('data', resolve));
  const base = `http://127.0.0.1:${PORT}`;

  const byCity = await (await fetch(`${base}/v1/market/price-book?city=${encodeURIComponent('г. Сочи')}`)).json();
  assert.equal(byCity.coverage, 'city');
  const near = await (await fetch(`${base}/v1/market/price-book?city=Адлер&lat=43.43&lon=39.92`)).json();
  assert.equal(near.coverage, 'nearby');
  assert.equal((await fetch(`${base}/v1/market/price-book?city=Мурманск&lat=68.97&lon=33.07`)).status, 404);

  assert.equal((await fetch(`${base}/v1/admin/partners`)).status, 401);
  const bad = await fetch(`${base}/v1/admin/partners`, { method: 'PUT', headers: { 'x-admin-key': 'secret-key' }, body: JSON.stringify({ partners: [{ id: 'p1', name: 'Без города' }] }) });
  assert.equal(bad.status, 400);
  const ok = await fetch(`${base}/v1/admin/partners`, { method: 'PUT', headers: { 'x-admin-key': 'secret-key' }, body: JSON.stringify({ partners: [
    { id: 'beton-sochi', name: 'Бетон-Юг', advertiser: 'ООО «Бетон-Юг»', erid: '2VtzqvXXXXX', cities: ['Сочи'], categories: ['house'], phone: '+7 900 000-00-00', inn: '2300000000' },
    { id: 'krovlya-kuban', name: 'Кровля Кубани', advertiser: 'ИП Петров', erid: '2VtzqwYYYYY', regions: ['Краснодарский край'], categories: ['all'] },
  ] }) });
  assert.equal(ok.status, 200);

  const sochi = await (await fetch(`${base}/v1/partners?city=Сочи&region=Краснодарский край&category=house`)).json();
  assert.deepEqual(sochi.partners.map((p) => p.id), ['beton-sochi']);
  assert.equal(sochi.partners[0].inn, undefined); // internal fields are not public
  const anapa = await (await fetch(`${base}/v1/partners?city=Анапа&region=${encodeURIComponent('Краснодарский край')}&category=metal`)).json();
  assert.deepEqual(anapa.partners.map((p) => p.id), ['krovlya-kuban']);
  const moscow = await (await fetch(`${base}/v1/partners?city=Москва&region=Москва`)).json();
  assert.equal(moscow.partners.length, 0);

  assert.equal((await fetch(`${base}/v1/partners/beton-sochi/events`, { method: 'POST', body: JSON.stringify({ type: 'click_phone' }) })).status, 200);
  const admin = await (await fetch(`${base}/v1/admin/partners`, { headers: { 'x-admin-key': 'secret-key' } })).json();
  assert.equal(Object.values(admin.stats['beton-sochi'])[0].click_phone, 1);
});

test('build-price-book: median, outliers, duplicates, old offers', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'obs-'));
  const csv = path.join(dir, 'test-city.csv');
  const today = new Date().toISOString().slice(0, 10);
  fs.writeFileSync(csv, [
    '# city=Тестград', '# region=Тестовая область', '# lat=50', '# lon=40',
    'code,kind,price,source,url,date',
    ...[7600, 7700, 7800, 7900, 8000].map((p, i) => `concrete,material,${p},Завод ${i},https://x/${i},${today}`),
    `concrete,material,99000,Фейк,https://x/fake,${today}`,
    `concrete,material,7800,Завод 0,https://x/0,${today}`,
    'concrete,material,5000,Старое,https://x/old,2020-01-01',
    `concrete,labor,1500,Avito Услуги,https://a/1,${today}`,
    `nonsense,material,1,?,,${today}`,
  ].join('\n'));
  const out = path.resolve('market-prices/test-city.json');
  try {
    execFileSync(process.execPath, ['scripts/build-price-book.js', csv]);
    const book = JSON.parse(fs.readFileSync(out, 'utf8'));
    assert.equal(book.lines.length, 1);
    const c = book.lines[0];
    assert.equal(c.materialRate, 7800);
    assert.equal(c.materialSources, 5);
    assert.equal(c.laborRate, 1500);
    assert.equal(c.lowData, true); // one labor offer only
    assert.equal(c.unit, 'м³');
  } finally { fs.rmSync(out, { force: true }); fs.rmSync(dir, { recursive: true, force: true }); }
});
