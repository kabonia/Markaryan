#!/usr/bin/env node
// Weekly real-price collection for «Смета дома» (systemd smetapro-prices.timer, Monday night).
// Only real offers with links are kept (web search, never prices «from memory»); an item without a fresh offer keeps
// last week's price for up to 5 weeks. Spending is capped: the week's budget is split between
//   1) cities where people actually estimate houses (demand from the app), 2) the core cities, 3) a rotation of the
//   other large cities (the ones priced longest ago first). Cities without a book use the nearest one or the Russian median.
//   node scripts/weekly-prices.mjs                 — the weekly run
//   node scripts/weekly-prices.mjs Сочи Краснодар  — these cities now (ignores «fresh» and rotation, still within budget)
import fs from 'node:fs';
import path from 'node:path';
import { config } from '../src/config.js';
import { priceEstimate } from '../src/estimate.js';
import { CATALOG } from '../src/house-catalog.js';
import { slug } from '../src/house.js';
import { normalizePlace } from '../src/market.js';
import { newMeter, withCost, isOutOfFunds } from '../src/util.js';

const BUDGET = Number(process.env.PRICE_WEEKLY_BUDGET_USD || '6');
const ROTATION = Number.parseInt(process.env.PRICE_ROTATION_PER_WEEK || '6', 10);
const KEEP_DAYS = 35;
const FRESH_DAYS = 6;
const OPTS = { model: process.env.PRICE_MODEL || 'deepseek/deepseek-v4.1-flash-1017', maxResults: 5, strict: true, cacheTag: 'w:', batch: 8, maxTokens: 8000, webOnly: true };

const CORE = ['Москва', 'Санкт-Петербург', 'Краснодар', 'Сочи'];
// Large cities with coordinates (the nearest-city fallback needs them).
const CITIES = {
  'Москва': [55.75, 37.62], 'Санкт-Петербург': [59.94, 30.31], 'Новосибирск': [55.03, 82.92], 'Екатеринбург': [56.84, 60.6],
  'Казань': [55.79, 49.12], 'Нижний Новгород': [56.33, 44.0], 'Челябинск': [55.16, 61.4], 'Красноярск': [56.01, 92.85],
  'Самара': [53.2, 50.15], 'Уфа': [54.73, 55.96], 'Ростов-на-Дону': [47.22, 39.72], 'Омск': [54.99, 73.37],
  'Краснодар': [45.04, 38.98], 'Воронеж': [51.66, 39.2], 'Пермь': [58.01, 56.25], 'Волгоград': [48.71, 44.51],
  'Саратов': [51.53, 46.03], 'Тюмень': [57.15, 65.53], 'Тольятти': [53.51, 49.42], 'Ижевск': [56.85, 53.2],
  'Барнаул': [53.35, 83.78], 'Ульяновск': [54.31, 48.4], 'Иркутск': [52.29, 104.3], 'Хабаровск': [48.48, 135.08],
  'Ярославль': [57.63, 39.87], 'Владивосток': [43.12, 131.89], 'Махачкала': [42.98, 47.5], 'Томск': [56.48, 84.95],
  'Оренбург': [51.77, 55.1], 'Кемерово': [55.35, 86.09], 'Рязань': [54.63, 39.74], 'Астрахань': [46.35, 48.04],
  'Пенза': [53.2, 45.0], 'Липецк': [52.61, 39.59], 'Киров': [58.6, 49.66], 'Чебоксары': [56.15, 47.25],
  'Калининград': [54.71, 20.51], 'Тула': [54.19, 37.62], 'Ставрополь': [45.04, 41.97], 'Сочи': [43.59, 39.72],
  'Севастополь': [44.62, 33.53], 'Симферополь': [44.95, 34.1], 'Белгород': [50.6, 36.59], 'Курск': [51.73, 36.19],
  'Тверь': [56.86, 35.9], 'Брянск': [53.24, 34.36], 'Иваново': [57.0, 40.97], 'Владимир': [56.13, 40.41],
  'Архангельск': [64.54, 40.54], 'Мурманск': [68.97, 33.07], 'Сургут': [61.25, 73.4], 'Якутск': [62.03, 129.73],
  'Калуга': [54.51, 36.26], 'Смоленск': [54.78, 32.05], 'Вологда': [59.22, 39.89], 'Кострома': [57.77, 40.93],
  'Орёл': [52.97, 36.07], 'Тамбов': [52.72, 41.45], 'Набережные Челны': [55.74, 52.4], 'Новороссийск': [44.72, 37.77],
  'Анапа': [44.89, 37.32], 'Геленджик': [44.56, 38.08], 'Пятигорск': [44.04, 43.06], 'Ялта': [44.5, 34.17],
};

const dir = path.join(config.dataDir, 'house-prices');
const log = (...a) => console.log(new Date().toISOString(), ...a);
const readJSON = (file, d) => { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return d; } };
const days = (iso) => (iso ? (Date.now() - Date.parse(iso)) / 86_400_000 : Infinity);
const bookFile = (city) => path.join(dir, `${slug(city)}.json`);

function demandCities() {
  const recent = (x) => days(x.lastAt) <= 30;
  const list = [...Object.values(readJSON(path.join(config.dataDir, 'house-demand.json'), {})), ...Object.values(readJSON(path.join(config.dataDir, 'requested-cities.json'), {}))]
    .filter((x) => x?.city && recent(x));
  const byKey = new Map();
  for (const x of list) {
    const k = normalizePlace(x.city);
    const prev = byKey.get(k);
    byKey.set(k, { city: prev?.city || x.city, count: (prev?.count || 0) + (x.count || 1), lat: prev?.lat ?? x.lat, lon: prev?.lon ?? x.lon });
  }
  return [...byKey.values()].sort((a, b) => b.count - a.count);
}

function plan(only) {
  if (only.length) return only.map((city) => ({ city, why: 'вручную', force: true }));
  const out = [], seen = new Set();
  const push = (city, why, lat, lon) => {
    const k = normalizePlace(city);
    if (seen.has(k)) return;
    seen.add(k);
    const [la, lo] = CITIES[city] || [lat, lon];
    out.push({ city, why, lat: la, lon: lo });
  };
  for (const d of demandCities()) push(d.city, `спрос ×${d.count}`, d.lat, d.lon);
  for (const c of CORE) push(c, 'ядро');
  Object.keys(CITIES).filter((c) => !seen.has(normalizePlace(c)))
    .sort((a, b) => (readJSON(bookFile(a), {}).updatedAt || '').localeCompare(readJSON(bookFile(b), {}).updatedAt || ''))
    .slice(0, ROTATION).forEach((c) => push(c, 'ротация'));
  return out;
}

const hintFor = (item) => item.kind === 'machine'
  ? `аренда с оператором: 3+ реальных предложения (Авито, частники, компании аренды), медиана; цена за ${item.unit}`
  : item.kind === 'delivery' ? `грузоперевозка по городу: 3+ реальных предложения (Авито, перевозчики), медиана за рейс` : '';

async function collect(target, meter) {
  const items = CATALOG.map((it) => ({ name: it.name, unit: it.unit, kind: it.kind === 'material' ? 'material' : 'work', hint: hintFor(it) }));
  const { items: rows } = await priceEstimate({ city: target.city, items, maxItems: items.length }, OPTS);
  const prev = readJSON(bookFile(target.city), null);
  const now = new Date().toISOString();
  const out = {};
  let fresh = 0, kept = 0;
  CATALOG.forEach((it, i) => {
    const row = rows[i];
    // Real only: an offer with a link, and not absurd against the guide (×3 either way — wrong unit or a wholesale lot).
    const sane = row && row.typical > 0 && row.typical >= it.base / 3 && row.typical <= it.base * 3;
    if (sane && !row.missing && Array.isArray(row.sources) && row.sources.length) {
      out[it.code] = { low: row.low, typical: row.typical, high: row.high, example: row.example || '', sources: row.sources.slice(0, 3), at: now };
      fresh += 1;
    } else if (prev?.items?.[it.code] && days(prev.items[it.code].at) <= KEEP_DAYS) {
      out[it.code] = prev.items[it.code];
      kept += 1;
    }
  });
  const book = {
    city: target.city, lat: target.lat ?? prev?.lat, lon: target.lon ?? prev?.lon, updatedAt: now,
    method: 'Реальные предложения магазинов, маркетплейсов, Авито и подрядчиков города со ссылками; цена без свежего предложения держится до 5 недель.',
    items: out, stats: { fresh, kept, missing: CATALOG.length - fresh - kept, usd: Math.round(meter.total * 1000) / 1000 },
  };
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(`${bookFile(target.city)}.tmp`, JSON.stringify(book, null, 1));
  fs.renameSync(`${bookFile(target.city)}.tmp`, bookFile(target.city));
  return { fresh, kept };
}

async function main() {
  const only = process.argv.slice(2);
  const targets = plan(only);
  const meter = newMeter();
  log(`План: ${targets.map((t) => `${t.city} (${t.why})`).join(', ')}; бюджет $${BUDGET}`);
  await withCost(meter, async () => {
    for (const t of targets) {
      const book = readJSON(bookFile(t.city), null);
      if (!t.force && book && days(book.updatedAt) < FRESH_DAYS) { log(`${t.city}: обновлён ${Math.round(days(book.updatedAt))} дн. назад — пропуск`); continue; }
      if (meter.total >= BUDGET) { log(`Бюджет недели $${BUDGET} исчерпан — остальные города в следующий раз`); break; }
      const before = meter.total;
      try {
        const r = await collect(t, meter);
        log(`${t.city}: ${r.fresh} свежих цен, ${r.kept} с прошлой недели, $${(meter.total - before).toFixed(3)}`);
      } catch (error) {
        log(`${t.city}: ошибка — ${error.message}`);
        if (isOutOfFunds(error)) { log('На OpenRouter нет денег — сбор остановлен, цены прошлой недели остаются'); break; }
      }
    }
  });
  log(`Готово: потрачено $${meter.total.toFixed(3)} за ${meter.calls} запросов`);
}

main().catch((error) => { console.error(error); process.exit(1); });
