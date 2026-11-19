#!/usr/bin/env node
// Builds a city price book from real price observations.
//   node scripts/build-price-book.js market-observations/sochi.csv   → market-prices/sochi.json
//
// CSV: first lines "# key=value" describe the place (city, region, lat, lon, scope=city|region|national),
// then a header row: code,kind,price,source,url,date
//   code   — line code from market-prices/_lines.template (concrete, rebar, ...)
//   kind   — material | labor (price per the line's unit, in rubles)
//   source — store, marketplace or labour site (Лемана ПРО, Ozon, Avito Услуги, Profi.ru, hh.ru, ...)
//   url    — the offer itself; the same url is counted once
//   date   — YYYY-MM-DD; observations older than MAX_AGE_DAYS (default 120) are ignored
// Outliers (dumping, «от 1 ₽», inflated ads) are cut by the IQR rule in aggregate().
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { aggregate } from '../src/market.js';

const input = process.argv[2];
if (!input) { console.error('Использование: node scripts/build-price-book.js market-observations/<город>.csv'); process.exit(1); }
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const maxAgeDays = Number.parseInt(process.env.MAX_AGE_DAYS || '120', 10);
const MIN_SOURCES = 3;

function parseCSV(text) {
  const rows = []; let row = [], cell = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { cell += '"'; i++; } else if (ch === '"') quoted = false; else cell += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { row.push(cell); cell = ''; }
    else if (ch === '\n' || ch === '\r') { if (ch === '\r' && text[i + 1] === '\n') i++; row.push(cell); rows.push(row); row = []; cell = ''; }
    else cell += ch;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows.filter((r) => r.some((c) => c.trim() !== ''));
}

const text = fs.readFileSync(input, 'utf8').replace(/^﻿/, '');
const meta = {};
const body = text.split(/\r?\n/).filter((line) => {
  const m = line.match(/^#\s*(\w+)\s*=\s*(.*)$/);
  if (m) meta[m[1]] = m[2].trim();
  return !line.startsWith('#');
}).join('\n');
const [header, ...rows] = parseCSV(body);
const col = Object.fromEntries(header.map((h, i) => [h.trim(), i]));
for (const k of ['code', 'kind', 'price', 'source']) if (col[k] === undefined) { console.error(`Нет колонки ${k}`); process.exit(1); }

const template = JSON.parse(fs.readFileSync(path.join(root, 'market-prices/_lines.template'), 'utf8')).lines;
const known = new Map(template.map((l) => [l.code, l]));
const cutoff = Date.now() - maxAgeDays * 86_400_000;
const seen = new Set(), obs = new Map(), skipped = { unknown: 0, old: 0, duplicate: 0 };
for (const r of rows) {
  const get = (k) => (col[k] === undefined ? '' : String(r[col[k]] ?? '').trim());
  const code = get('code'), kind = get('kind'), price = Number(get('price').replace(/\s/g, '').replace(',', '.'));
  if (!known.has(code) || !['material', 'labor'].includes(kind)) { skipped.unknown++; continue; }
  const date = Date.parse(get('date'));
  if (Number.isFinite(date) && date < cutoff) { skipped.old++; continue; }
  const key = `${code}|${kind}|${get('url') || `${get('source')}|${price}`}`;
  if (seen.has(key)) { skipped.duplicate++; continue; }
  seen.add(key);
  const k = `${code}|${kind}`;
  if (!obs.has(k)) obs.set(k, { values: [], sources: new Set() });
  obs.get(k).values.push(price); obs.get(k).sources.add(get('source'));
}

const lines = [];
for (const t of template) {
  const m = obs.has(`${t.code}|material`) ? aggregate(obs.get(`${t.code}|material`).values) : null;
  const l = obs.has(`${t.code}|labor`) ? aggregate(obs.get(`${t.code}|labor`).values) : null;
  if (!m && !l) continue;
  const line = { ...t, materialRate: m?.typical ?? 0, laborRate: l?.typical ?? 0 };
  if (m) Object.assign(line, { materialLow: m.low, materialHigh: m.high, materialSources: m.sources });
  if (l) Object.assign(line, { laborLow: l.low, laborHigh: l.high, laborSources: l.sources });
  // A material-only or labor-only line keeps the other side as "no data", the app shows it as such.
  line.marketData = [m ? 'material' : null, l ? 'labor' : null].filter(Boolean);
  line.lowData = (m && m.sources < MIN_SOURCES) || (l && l.sources < MIN_SOURCES) || false;
  lines.push(line);
}

const book = {
  city: meta.city || '', region: meta.region || '', scope: meta.scope || 'city',
  lat: meta.lat ? Number(meta.lat) : undefined, lon: meta.lon ? Number(meta.lon) : undefined,
  updatedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'), // the app reads ISO 8601 without milliseconds
  method: `Медиана предложений магазинов, маркетплейсов и бирж труда; выбросы отсечены по межквартильному размаху; предложения старше ${maxAgeDays} дней не учитываются.`,
  lines,
};
const out = path.join(root, 'market-prices', path.basename(input).replace(/\.csv$/i, '.json'));
fs.writeFileSync(out, JSON.stringify(book, null, 1));
console.log(`${out}: строк ${lines.length} из ${template.length}; мало данных: ${lines.filter((l) => l.lowData).length}; пропущено: неизвестный код ${skipped.unknown}, старые ${skipped.old}, дубли ${skipped.duplicate}`);
