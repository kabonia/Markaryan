// Market estimate for a design project: for every material and work — prices in the user's city (low / typical / high
// per unit), a product example and real sources found by web search (OpenRouter web plugin). Answers are cached
// for 7 days per city and item, so repeated estimates cost almost nothing.
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { ApiError, request, readJSON, parseLooseJSON } from './util.js';
import { normalizePlace } from './market.js';

const CACHE_DAYS = 7;
const cacheFile = () => path.join(config.dataDir, 'estimate-cache.json');
const readCache = () => { try { return JSON.parse(fs.readFileSync(cacheFile(), 'utf8')); } catch { return {}; } };
const writeCache = (cache) => { fs.mkdirSync(config.dataDir, { recursive: true }); fs.writeFileSync(cacheFile(), JSON.stringify(cache)); };
const key = (city, item) => `${normalizePlace(city)}|${String(item.name).toLowerCase().trim()}|${String(item.unit || '').toLowerCase()}`;

const clean = (v, n) => String(v ?? '').replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, n);
const num = (v) => { const x = Number(String(v ?? '').replace(/\s/g, '').replace(',', '.')); return Number.isFinite(x) && x > 0 && x < 1e8 ? x : 0; };

/** Keeps only sane numbers and real links. */
export function sanitize(row) {
  let low = num(row.low), typical = num(row.typical), high = num(row.high);
  if (!typical) return null;
  if (!low || low > typical) low = typical;
  if (!high || high < typical) high = typical;
  const sources = (Array.isArray(row.sources) ? row.sources : []).map((s) => ({
    title: clean(s?.title, 80), url: clean(s?.url, 300), price: num(s?.price) || undefined,
  })).filter((s) => /^https?:\/\/\S+$/.test(s.url)).slice(0, 4);
  return { name: clean(row.name, 120), unit: clean(row.unit, 20), quantity: num(row.quantity), low, typical, high,
    example: clean(row.example, 140), kind: row.kind === 'work' ? 'work' : 'material', sources };
}

async function askModel(city, items) {
  const { apiKey, base, helperModels } = config.openrouter;
  if (!apiKey) throw new ApiError(503, 'ИИ не настроен на сервере.');
  const model = `${helperModels[0] || 'anthropic/claude-haiku-5.5'}:online`;
  const list = items.map((it, i) => `${i + 1}. [${it.kind === 'work' ? 'работа' : 'материал'}] ${it.name}${it.amount ? ` — ${it.amount}` : ''}${it.unit ? ` (ед.: ${it.unit})` : ''}${it.quantity ? `, количество ${it.quantity}` : ''}`).join('\n');
  const system = `Ты сметчик. Найди в интернете актуальные цены в рублях в городе ${city} (или ближайшем крупном городе региона).
Для каждой позиции: цена за единицу — low (дёшево), typical (обычная рыночная), high (дорого); единица измерения; количество (возьми из запроса или вычисли из описания);
пример конкретного товара или исполнителя (для материалов — марка/модель); 1–3 источника с прямыми ссылками на страницы с ценой (магазины, маркетплейсы, прайсы мастеров).
Не выдумывай ссылки и цены; отбрасывай акции «−70%», «от 1 ₽» и прошлые годы.
Ответ — только JSON: {"items":[{"name","kind":"material|work","unit","quantity","low","typical","high","example","sources":[{"title","url","price"}]}]} в том же порядке.`;
  const response = await request(`${base}/chat/completions`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages: [{ role: 'system', content: system }, { role: 'user', content: list }],
      max_tokens: 6000, plugins: [{ id: 'web', max_results: 5 }] }),
  }, 240_000);
  const body = await readJSON(response);
  if (!response.ok) throw new ApiError(502, 'Поиск цен не ответил. Попробуйте позже.');
  const text = body?.choices?.[0]?.message?.content ?? '';
  const parsed = parseLooseJSON(text);
  return Array.isArray(parsed?.items) ? parsed.items : [];
}

export async function priceEstimate(body) {
  const city = clean(body?.city, 60) || 'Москва';
  const items = (Array.isArray(body?.items) ? body.items : []).slice(0, 40).map((it) => ({
    name: clean(it?.name, 120), amount: clean(it?.amount, 60), unit: clean(it?.unit, 20), quantity: num(it?.quantity), kind: it?.kind === 'work' ? 'work' : 'material',
  })).filter((it) => it.name);
  if (!items.length) throw new ApiError(400, 'Нет позиций для сметы.');

  const cache = readCache();
  const fresh = (entry) => entry && Date.now() - entry.at < CACHE_DAYS * 86_400_000;
  const missing = items.filter((it) => !fresh(cache[key(city, it)]));
  if (missing.length) {
    const found = await askModel(city, missing);
    missing.forEach((it, i) => {
      const row = sanitize({ ...found[i], name: it.name, kind: it.kind, quantity: it.quantity || found[i]?.quantity });
      if (row) cache[key(city, it)] = { at: Date.now(), row };
    });
    writeCache(cache);
  }
  const rows = items.map((it) => {
    const cached = cache[key(city, it)]?.row;
    if (!cached) return { name: it.name, kind: it.kind, unit: it.unit, quantity: it.quantity, missing: true };
    return { ...cached, quantity: it.quantity || cached.quantity };
  });
  return { city, updatedAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'), items: rows };
}
