// Market estimate for a design project: for every material and work — prices in the user's city (low / typical / high
// per unit), a product example and real sources found by web search (OpenRouter web plugin). Answers are cached
// for 7 days per city and item, so repeated estimates cost almost nothing.
import fs from 'node:fs';
import path from 'node:path';
import { config, hasHermesJson } from './config.js';
import * as hermes from './providers/hermes.js';
import { ApiError, request, readJSON, parseLooseJSON, mapLimit, addCost, outOfFunds, isOutOfFunds } from './util.js';
import { normalizePlace } from './market.js';

const CACHE_DAYS = 7;
const BATCH = 5;
/** Replaced in tests. */
let ask = (city, items, opts) => askModel(city, items, opts);
export function setAsk(fn) { ask = fn || ((city, items, opts) => askModel(city, items, opts)); }
const cacheFile = () => path.join(config.dataDir, 'estimate-cache.json');
const readCache = () => { try { return JSON.parse(fs.readFileSync(cacheFile(), 'utf8')); } catch { return {}; } };
const writeCache = (cache) => { fs.mkdirSync(config.dataDir, { recursive: true }); fs.writeFileSync(cacheFile(), JSON.stringify(cache)); };
const key = (city, item) => `${normalizePlace(city)}|${String(item.name).toLowerCase().trim()}|${String(item.unit || '').toLowerCase()}`;

const clean = (v, n) => String(v ?? '').replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, n);
const num = (v) => { const x = Number(String(v ?? '').replace(/\s/g, '').replace(',', '.')); return Number.isFinite(x) && x > 0 && x < 1e8 ? x : 0; };

// OpenRouter liveness check (10-minute cache): while the account accepts requests — web prices with links; otherwise — Hermes.
let orLiveCache = { at: 0, live: false, inFlight: null };
export function orAliveReset() { orLiveCache = { at: 0, live: false, inFlight: null }; }
async function orAlive() {
  if (Date.now() - orLiveCache.at < 10 * 60_000) return orLiveCache.live;
  if (!orLiveCache.inFlight) {
    orLiveCache.inFlight = (async () => {
      let live = false;
      try {
        const auth = { Authorization: `Bearer ${config.openrouter.apiKey}` };
        const res = await fetch(`${config.openrouter.base}/auth/balance`, { headers: auth, signal: AbortSignal.timeout(15_000) });
        if (res.ok) {
          const data = await res.json();
          const bal = Number(data?.data?.total_balance ?? 0);
          live = Number.isFinite(bal) && bal > 0;
        } else {
          // The proxy may not expose the balance endpoint: a cheap 1-token request decides.
          const probe = await fetch(`${config.openrouter.base}/chat/completions`, {
            method: 'POST',
            headers: { ...auth, 'Content-Type': 'application/json' },
            body: JSON.stringify({ model: config.openrouter.helperModels[0], messages: [{ role: 'user', content: '.' }], max_tokens: 1 }),
            signal: AbortSignal.timeout(30_000),
          });
          live = probe.ok;
        }
      } catch { live = false; }
      orLiveCache = { at: Date.now(), live, inFlight: null };
      return live;
    })();
  }
  return orLiveCache.inFlight;
}

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

async function askModel(city, items, opts = {}) {
  const { apiKey, base, helperModels } = config.openrouter;
  // «quality» (estimates from documents): a strong model and more sources per line.
  const model = `${opts.model || helperModels[0] || 'anthropic/claude-haiku-5.5'}:online`;
  const list = items.map((it, i) => `${i + 1}. [${it.kind === 'work' ? 'работа' : 'материал'}] ${it.name}${it.amount ? ` — ${it.amount}` : ''}${it.unit ? ` (ед.: ${it.unit})` : ''}${it.quantity ? `, количество ${it.quantity}` : ''}${it.hint ? ` — ВНИМАНИЕ: ${it.hint}` : ''}`).join('\n');
  const unitRule = 'Цена строго за указанную единицу (если продавец даёт за другую — пересчитай: за упаковку → за м², за мешок → за кг и т.д.). Для работ — только стоимость труда без материалов, если не сказано иначе.';
  const webSystem = `Ты сметчик. Найди в интернете актуальные цены в рублях в городе ${city} (или ближайшем крупном городе региона).
Для каждой позиции: цена за единицу — low (дёшево), typical (обычная рыночная), high (дорого); единица измерения; количество (возьми из запроса или вычисли из описания);
пример конкретного товара или исполнителя (для материалов — марка/модель); 1–3 источника с прямыми ссылками на страницы с ценой (магазины, маркетплейсы, прайсы мастеров).
Не выдумывай ссылки и цены; отбрасывай акции «−70%», «от 1 ₽» и прошлые годы.
${unitRule}${opts.strict ? '\nМинимум 2 независимых источников на позицию; typical — медиана реальных предложений города, а не минимальная цена.' : ''}
Ответ — только JSON: {"items":[{"name","kind":"material|work","unit","quantity","low","typical","high","example","sources":[{"title","url","price"}]}]} в том же порядке.`;
  // Hermes: цены из знания рынка (батч ~1 мин, без лимита 300 с на веб-агента); веб с ссылками — путь OpenRouter.
  const knowledgeSystem = `Ты сметчик. Оцени актуальные рыночные цены в рублях в городе ${city} (или ближайшем крупном городе региона) на текущий год по своему знанию рынка — без веб-поиска.
Для каждой позиции: цена за единицу — low (дёшево), typical (обычная рыночная), high (дорого); единица измерения; количество (возьми из запроса или вычисли из описания);
пример конкретного товара или исполнителя (марка/тип). Ссылки не нужны — поле sources оставь пустым.
${unitRule}${opts.strict ? '\ntypical — реалистичная рыночная медиана города, а не минимальная цена.' : ''}
Ответ — только JSON: {"items":[{"name","kind":"material|work","unit","quantity","low","typical","high","example","sources":[]}]} в том же порядке.`;
  // Money on OpenRouter — web prices with links; otherwise — market knowledge via Hermes.
  const useHermes = opts.hermes === true || (hasHermesJson() && !(await orAlive()));
  const system = useHermes ? knowledgeSystem : webSystem;
  // Hermes (профиль smeta-json): цены из знания рынка; при сбое — OpenRouter (веб, если живой).
  if (useHermes) {
    try {
      const result = await hermes.json({ system, messages: [{ role: 'user', text: list }], maxTokens: 8_000, timeoutMs: 420_000 });
      const items = Array.isArray(result) ? result : result?.items;
      if (Array.isArray(items) && items.length) return items.filter((it) => it && it.name);
      console.warn(`[estimate] hermes prices: пустой или неверный ответ: ${JSON.stringify(result).slice(0, 200)}`);
    } catch (error) { console.warn(`[estimate] hermes prices failed: ${error.message}`); }
  }
  if (!apiKey) throw new ApiError(503, 'ИИ не настроен на сервере.');
  const response = await request(`${base}/chat/completions`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, messages: [{ role: 'system', content: system }, { role: 'user', content: list }],
      max_tokens: opts.maxTokens || 6000, plugins: [{ id: 'web', max_results: opts.maxResults || 5 }], usage: { include: true } }),
  }, 240_000);
  const body = await readJSON(response);
  addCost(body?.usage);
  if (response.status === 402) throw outOfFunds('OpenRouter: на счёте закончились кредиты. Пополните баланс.');
  if (response.status === 403 && /limit/i.test(body?.error?.message || '')) throw outOfFunds('OpenRouter: ключ сервера исчерпал свой лимит расходов.');
  if (!response.ok) throw new ApiError(502, 'Поиск цен не ответил. Попробуйте позже.');
  const text = body?.choices?.[0]?.message?.content ?? '';
  const parsed = parseLooseJSON(text);
  return Array.isArray(parsed?.items) ? parsed.items : [];
}

export async function priceEstimate(body, opts = {}) {
  const city = clean(body?.city, 60) || 'Москва';
  const items = (Array.isArray(body?.items) ? body.items : []).slice(0, body?.maxItems || 40).map((it) => ({
    name: clean(it?.name, 200), amount: clean(it?.amount, 60), unit: clean(it?.unit, 20), quantity: num(it?.quantity), kind: it?.kind === 'work' ? 'work' : 'material',
    hint: clean(it?.hint, 300),
  })).filter((it) => it.name);
  // The quality search keeps its own cache: quick estimates must not reuse it and vice versa; a hint means «search again».
  const keyOf = (it) => `${opts.cacheTag || ''}${key(city, it)}`;
  const fresh = (entry) => entry && Date.now() - entry.at < CACHE_DAYS * 86_400_000;
  if (!items.length) throw new ApiError(400, 'Нет позиций для сметы.');

  const cache = readCache();
  const missing = items.filter((it) => it.hint || !fresh(cache[keyOf(it)]));
  if (missing.length) {
    // Small batches in parallel: a long list makes the web-search model answer with prose instead of JSON.
    // A batch that fails twice only leaves its lines without a price; the rest of the estimate still comes back.
    const batches = [];
    // Hermes-агент ищет по каждой позиции: мелкие батчи стабильнее и быстрее (250–430 с батч по 5).
    let useHermes = hasHermesJson() && !(await orAlive());
    let size = opts.batch || BATCH;
    if (useHermes) size = Math.min(size, 4); // Hermes без веба: батч до 4 позиций ≈ 1 мин
    for (let i = 0; i < missing.length; i += size) batches.push(missing.slice(i, i + size));
    const errors = [];
    // No money: the remaining batches are not even sent (each would fail the same way).
    const tryAsk = async (batch) => {
      if (errors.some(isOutOfFunds) && !useHermes) return [];
      try { return await ask(city, batch, useHermes ? { ...opts, hermes: true } : opts); } catch (error) {
        // Funds ran out mid-run: drop the «OpenRouter is alive» cache, the rest goes via Hermes.
        if (isOutOfFunds(error) && hasHermesJson()) { orAliveReset(); useHermes = true; }
        errors.push(error);
        return [];
      }
    };
    let priced = 0;
    const left = [];
    const keep = (batch, found) => batch.forEach((it, i) => {
      const row = found[i] && sanitize({ ...found[i], name: it.name, kind: it.kind, quantity: it.quantity || found[i].quantity });
      if (row) { cache[keyOf(it)] = { at: Date.now(), row }; priced += 1; } else left.push(it);
    });
    (await mapLimit(batches, useHermes ? 1 : 6, tryAsk)).forEach((found, b) => keep(batches[b], found));
    // Second pass: every line still without a price on its own — a single item is found far more reliably.
    const retry = left.splice(0, left.length);
    (await mapLimit(retry, useHermes ? 1 : 8, (it) => tryAsk([it]))).forEach((found, i) => keep([retry[i]], found));
    if (priced) writeCache(cache);
    // What was found stays in the cache (a rerun does not pay for it again); the estimate itself stops, no empty lines.
    const broke = errors.find(isOutOfFunds);
    if (broke) throw broke;
    if (priced) { /* saved above */ } else if (!items.some((it) => fresh(cache[keyOf(it)]))) throw errors.find((e) => e instanceof ApiError) || new ApiError(502, 'Поиск цен не ответил. Попробуйте позже.', { retryable: true });
  }
  const rows = items.map((it) => {
    const cached = cache[keyOf(it)]?.row;
    if (!cached) return { name: it.name, kind: it.kind, unit: it.unit, quantity: it.quantity, missing: true };
    return { ...cached, quantity: it.quantity || cached.quantity };
  });
  return { city, updatedAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'), items: rows };
}
