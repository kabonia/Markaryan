// Market prices by the user's city and partner contractors shown after an estimate.
// Prices: server/market-prices/*.json, one file per city (or region / "Россия" as the national fallback),
// built from real observations by scripts/build-price-book.js (median, outliers cut by IQR).
// Partners: DATA_DIR/partners.json, edited through the admin API. Optional advertiser / erid fields
// are stored for ad marking (ФЗ «О рекламе», ст. 18.1); the app does not show them for now.
import fs from 'node:fs';
import path from 'node:path';
import { timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { config } from './config.js';
import { ApiError } from './util.js';

const env = process.env;
const marketDir = env.MARKET_DIR || path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../market-prices');
const adminKey = () => env.PARTNERS_ADMIN_KEY || env.HH_ADMIN_KEY || '';

export const normalizePlace = (value) => String(value ?? '')
  .toLowerCase().replace(/ё/g, 'е')
  .replace(/^(г\.|город|пгт|пос\.|поселок|с\.|республика|респ\.)\s*/u, '')
  .replace(/\s+(край|область|обл\.?|республика|респ\.?)$/u, '')
  .replace(/\s+/g, ' ').trim();

// ---------- statistics ----------

function quantile(sorted, q) {
  if (sorted.length === 0) return NaN;
  const pos = (sorted.length - 1) * q, lo = Math.floor(pos), hi = Math.ceil(pos);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

/**
 * Typical market price from raw observations: drops non-positive values and outliers outside
 * [Q1 − 1.5·IQR, Q3 + 1.5·IQR] (dumping, "от 1 ₽" ads, inflated listings), then returns
 * low = P25, typical = median, high = P75 of what is left.
 */
export function aggregate(values) {
  const clean = values.map(Number).filter((v) => Number.isFinite(v) && v > 0).sort((a, b) => a - b);
  if (clean.length === 0) return null;
  let kept = clean;
  if (clean.length >= 4) {
    const q1 = quantile(clean, 0.25), q3 = quantile(clean, 0.75), iqr = q3 - q1;
    kept = clean.filter((v) => v >= q1 - 1.5 * iqr && v <= q3 + 1.5 * iqr);
  }
  const round = (v) => (v >= 100 ? Math.round(v) : Math.round(v * 100) / 100);
  return { low: round(quantile(kept, 0.25)), typical: round(quantile(kept, 0.5)), high: round(quantile(kept, 0.75)), sources: kept.length, dropped: clean.length - kept.length };
}

function distanceKm(a, b) {
  const rad = Math.PI / 180, dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 12_742 * Math.asin(Math.sqrt(h));
}

// ---------- price books ----------

let books = [], loadedAt = 0;
function loadBooks() {
  if (Date.now() - loadedAt < 60_000) return books;
  loadedAt = Date.now();
  try {
    books = fs.readdirSync(marketDir).filter((f) => f.endsWith('.json')).flatMap((f) => {
      try {
        const book = JSON.parse(fs.readFileSync(path.join(marketDir, f), 'utf8'));
        return Array.isArray(book.lines) && book.lines.length ? [book] : [];
      } catch (error) { console.error(`market-prices/${f}:`, error.message); return []; }
    });
  } catch { books = []; }
  return books;
}

/** Best price book for a place: the city itself, then its region, then the nearest city within 300 km, then national. */
export function resolveBook({ city, region, lat, lon }) {
  const list = loadBooks();
  const c = normalizePlace(city), r = normalizePlace(region);
  const byCity = c && list.find((b) => normalizePlace(b.city) === c);
  if (byCity) return { book: byCity, coverage: 'city' };
  const byRegion = r && list.find((b) => normalizePlace(b.region) === r && (b.scope === 'region' || !b.city));
  if (byRegion) return { book: byRegion, coverage: 'region' };
  if (Number.isFinite(lat) && Number.isFinite(lon)) {
    const near = list.filter((b) => Number.isFinite(b.lat) && Number.isFinite(b.lon))
      .map((b) => ({ b, d: distanceKm({ lat, lon }, { lat: b.lat, lon: b.lon }) }))
      .filter((x) => x.d <= 300).sort((x, y) => x.d - y.d)[0];
    if (near) return { book: near.b, coverage: 'nearby', distanceKm: Math.round(near.d) };
  }
  const national = list.find((b) => b.scope === 'national');
  return national ? { book: national, coverage: 'national' } : null;
}

export function priceBook(url) {
  const lat = Number.parseFloat(url.searchParams.get('lat') ?? ''), lon = Number.parseFloat(url.searchParams.get('lon') ?? '');
  const found = resolveBook({ city: url.searchParams.get('city'), region: url.searchParams.get('region'), lat, lon });
  if (!found) {
    noteMissingCity(url.searchParams.get('city'), url.searchParams.get('region'), lat, lon);
    throw new ApiError(404, 'Рыночных цен для этого города пока нет. Добавим в ближайшее обновление.');
  }
  const { book, coverage, distanceKm: km } = found;
  const updatedAt = String(book.updatedAt || new Date().toISOString()).replace(/\.\d+Z$/, 'Z');
  return { updatedAt, city: book.city || book.region || 'Россия', coverage, distanceKm: km, method: book.method, lines: book.lines };
}

/** Cities users asked for without a price book: the daily price collection picks the most requested ones. */
function noteMissingCity(city, region, lat, lon) {
  const name = String(city || '').trim().slice(0, 60);
  if (!name) return;
  try {
    const file = path.join(config.dataDir, 'requested-cities.json');
    const list = readFile(file, {});
    const key = normalizePlace(name);
    const item = list[key] ?? { city: name, region: String(region || '').slice(0, 80), count: 0 };
    item.count += 1;
    item.lastAt = new Date().toISOString();
    if (Number.isFinite(lat) && Number.isFinite(lon)) { item.lat = Math.round(lat * 100) / 100; item.lon = Math.round(lon * 100) / 100; }
    list[key] = item;
    writeFile(file, list);
  } catch (error) { console.error('requested-cities:', error.message); }
}

// ---------- partners ----------

const partnersFile = () => path.join(config.dataDir, 'partners.json');
const statsFile = () => path.join(config.dataDir, 'partners-stats.json');
const readFile = (file, fallback) => { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; } };
function writeFile(file, value) {
  fs.mkdirSync(config.dataDir, { recursive: true });
  fs.writeFileSync(`${file}.tmp`, JSON.stringify(value, null, 2));
  fs.renameSync(`${file}.tmp`, file);
}

const PUBLIC_FIELDS = ['id', 'name', 'description', 'categories', 'phone', 'whatsapp', 'site', 'rating', 'advertiser', 'erid'];
const publicView = (p) => Object.fromEntries(PUBLIC_FIELDS.filter((k) => p[k] !== undefined && p[k] !== '').map((k) => [k, p[k]]));

/** Up to 3 active partners for the place and work category: city first, then region; higher priority first, ties shuffled. */
export function partnersFor({ city, region, category }) {
  const c = normalizePlace(city), r = normalizePlace(region), cat = String(category || '').trim();
  const active = readFile(partnersFile(), []).filter((p) => p.active !== false);
  const fits = (p) => !cat || !Array.isArray(p.categories) || p.categories.length === 0 || p.categories.includes(cat) || p.categories.includes('all');
  const inCity = active.filter((p) => fits(p) && (p.cities || []).some((x) => normalizePlace(x) === c));
  const pool = inCity.length ? inCity : active.filter((p) => fits(p) && r && (p.regions || []).some((x) => normalizePlace(x) === r));
  return pool
    .map((p) => ({ p, key: (Number(p.priority) || 0) + Math.random() * 0.5 }))
    .sort((a, b) => b.key - a.key).slice(0, 3).map((x) => publicView(x.p));
}

export function recordEvent(id, type) {
  if (!['view', 'click_phone', 'click_whatsapp', 'click_site'].includes(type)) throw new ApiError(400, 'Неизвестное событие.');
  if (!readFile(partnersFile(), []).some((p) => p.id === id)) throw new ApiError(404, 'Партнёр не найден.');
  const stats = readFile(statsFile(), {});
  const day = new Date().toISOString().slice(0, 10);
  stats[id] ??= {}; stats[id][day] ??= {};
  stats[id][day][type] = (stats[id][day][type] || 0) + 1;
  writeFile(statsFile(), stats);
  return { ok: true };
}

export function checkAdmin(req) {
  const expected = adminKey(), given = String(req.headers['x-admin-key'] || '');
  const a = Buffer.from(given), b = Buffer.from(expected);
  if (!expected || a.length !== b.length || !timingSafeEqual(a, b)) throw new ApiError(401, 'Нет доступа.');
}

/** Replaces the whole partner list. Each partner must have id, name and cities or regions. */
export function savePartners(list) {
  if (!Array.isArray(list)) throw new ApiError(400, 'Нужен массив партнёров.');
  const ids = new Set();
  for (const p of list) {
    if (!p || typeof p.id !== 'string' || !/^[a-z0-9-]{2,40}$/.test(p.id)) throw new ApiError(400, 'У партнёра нужен id: латиница, цифры, дефис.');
    if (ids.has(p.id)) throw new ApiError(400, `Повторяется id ${p.id}.`);
    ids.add(p.id);
    if (!p.name) throw new ApiError(400, `Партнёр ${p.id}: нужно name.`);
    if (!(p.cities?.length || p.regions?.length)) throw new ApiError(400, `Партнёр ${p.id}: укажите cities или regions.`);
  }
  writeFile(partnersFile(), list);
  return { ok: true, count: list.length };
}

export const listPartners = () => readFile(partnersFile(), []);
export const partnerStats = () => readFile(statsFile(), {});
