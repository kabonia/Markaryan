// «Смета по документам»: an estimate of any size from drawings (АР, КР), a specification (ТЗ), an existing estimate
// or just a list of works. Several AI agents work like an estimating department:
//   1. two independent «readers» (different models) take quantities off every sheet, with formulas;
//   2. the «lead estimator» merges both readings into one bill of quantities (ВОР) and recalculates disagreements;
//   3. «norm» agents (one per section, in parallel) list materials with consumption norms and waste, and machines;
//   4. market prices of every work, material and machine in the user's city (web search, sources);
//   5. the «auditor» checks for missing works, unit errors, double counting and odd prices; its additions are priced too;
//   6. totals: works, materials, machines, delivery, contingency, VAT, the market range.
// A job runs for minutes, so the app creates it, follows the progress and long-polls for the end (background session).
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { ApiError, mapLimit, newMeter, withCost, isOutOfFunds } from './util.js';
import * as ai from './ai.js';
import { priceEstimate } from './estimate.js';
import { xlsxToText } from './xlsx.js';
import * as billing from './billing.js';

const AI_TIMEOUT = 420_000;
const MAX_PAGES = 100;
const PAGES_PER_READER = 2;
// Who does what — the price and accuracy of an estimate are decided here (env overrides, no app update needed):
//   readers — two independent models of different makers read every sheet (one's mistake is caught by the other);
//     together they cost about one Opus;
//   lead estimator — the strongest model, recalculates every disagreement from the dimensions (one call per estimate);
//   norms, auditors — a mid model; price search — a cheap model with web search (the web results are the costly part).
const env = process.env;
const list = (v, d) => (v || d).split(',').map((x) => x.trim()).filter(Boolean);
const READER_MODELS = list(env.SMETA_READER_MODELS, 'google/gemini-4-carbon,openai/gpt-6.2-sol');
const READERS = Math.min(Math.max(Number.parseInt(env.SMETA_READERS || '2', 10) || 2, 1), 2);
const READER_EFFORT = env.SMETA_READER_EFFORT || 'high'; // arithmetic off the drawings: the readers think thoroughly
const EFFORT = env.SMETA_EFFORT || 'medium';
const MERGE_MODEL = env.SMETA_MERGE_MODEL || 'anthropic/claude-opus-5.5';
const CHECK_MODEL = env.SMETA_CHECK_MODEL || 'anthropic/claude-sonnet-5.5';
/** Price search for estimates from documents: several sources per line, its own cache (prices found once are reused for 7 days). */
const QUALITY = { model: env.SMETA_PRICE_MODEL || 'deepseek/deepseek-v4.1-flash-1017', maxResults: 5, strict: true, cacheTag: 'q:', batch: 8, maxTokens: 8000 };
/** An empty AI balance stops the estimate instead of leaving empty lines; everything else keeps the old «best effort». */
const unlessBroke = (fallback) => (error) => { if (isOutOfFunds(error)) throw error; return typeof fallback === 'function' ? fallback(error) : fallback; };
const KEEP_DAYS = 14;

// ---------- deterministic helpers (tested) ----------

const num = (v) => { const x = Number(String(v ?? '').replace(/\s/g, '').replace(',', '.')); return Number.isFinite(x) && x > 0 && x < 1e9 ? x : 0; };
const str = (v, n = 300) => String(v ?? '').replace(/[\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, n);
const round = (x, unit = '') => {
  if (!x) return 0;
  if (/^(шт|компл|комплект|место|точк|упак|мешок|рулон|лист|т\.|ед)/i.test(unit)) return Math.ceil(x - 1e-9);
  return x >= 100 ? Math.round(x * 10) / 10 : Math.round(x * 100) / 100;
};
const keyOf = (name, unit) => `${String(name).toLowerCase().replace(/ё/g, 'е').replace(/[^a-zа-я0-9]+/g, ' ').trim()}|${String(unit).toLowerCase().replace(/\s/g, '')}`;

/** Material quantity of one work: amount of work × norm per unit × (1 + waste). */
export function materialQuantity(workQuantity, norm, wastePct, unit) {
  const waste = Math.min(Math.max(num(wastePct), 0), 40);
  return round(num(workQuantity) * num(norm) * (1 + waste / 100), unit);
}

/** Sums the same material over all works (one line in the purchase list). */
export function aggregateMaterials(works) {
  const map = new Map();
  for (const work of works) {
    for (const m of work.materials || []) {
      if (!m.quantity) continue;
      const key = keyOf(m.name, m.unit);
      const line = map.get(key) || { key, name: m.name, unit: m.unit, quantity: 0, usedIn: [] };
      line.quantity += m.quantity;
      if (!line.usedIn.includes(work.id)) line.usedIn.push(work.id);
      map.set(key, line);
    }
  }
  return [...map.values()].map((line) => ({ ...line, quantity: round(line.quantity, line.unit) }));
}

/** Totals with surcharges; every sum also as a market range (cheap — expensive offers). */
export function totals(sections, options = {}) {
  const sum = (field, kind) => sections.reduce((t, s) => t + s[kind][field], 0);
  const base = (field) => ({ works: sum(field, 'works'), materials: sum(field, 'materials'), machines: sum(field, 'machines') });
  const make = (field) => {
    const b = base(field);
    const delivery = b.materials * (options.deliveryPct ?? 4) / 100;
    const direct = b.works + b.materials + b.machines + delivery;
    const contingency = direct * (options.contingencyPct ?? 5) / 100;
    const subtotal = direct + contingency;
    const vat = options.vat ? subtotal * (options.vatPct ?? 22) / 100 : 0;
    return { ...b, delivery, contingency, subtotal, vat, total: subtotal + vat };
  };
  return { typical: make('typical'), low: make('low'), high: make('high') };
}

// ---------- agents ----------

const DOC_KINDS = {
  ar: 'АР (архитектурные решения): планы этажей, разрезы, фасады, экспликации помещений, ведомости проёмов, отделки, полов, кровля',
  kr: 'КР / КЖ / КМ (конструктивные решения): фундаменты, каркас, плиты, стены, армирование, спецификации металла и бетона',
  tz: 'ТЗ (техническое задание): состав работ, требования к материалам, классы, площади',
  smeta: 'готовая смета или ВОР: перенести позиции и объёмы, проверить и переоценить по рынку',
  other: 'прочий документ (инженерные разделы ОВ/ВК/ЭОМ, спецификации, фото листов, описание)',
};

const READER_SYSTEM = `Ты — ведущий инженер‑сметчик с 20‑летним опытом (жилые, коммерческие и промышленные объекты, РФ).
Задача: снять с документов ведомость объёмов работ (ВОР) так, как это делает профессионал.
Правила:
• Работай по разделам: Подготовительные; Земляные; Фундаменты; Каркас и несущие конструкции; Стены и перегородки; Перекрытия и покрытия; Кровля; Окна, двери, ворота; Фасад; Внутренняя отделка; Полы; Отопление и вентиляция; Водопровод и канализация; Электроснабжение и освещение; Слаботочные системы; Благоустройство; Прочее.
• По АР: кладка/перегородки — площадь стен за вычетом проёмов (по ведомости проёмов), толщина и материал; отделка — по экспликации помещений и ведомости отделки (стены, потолки, полы по каждому типу); окна и двери — штуки и м² по ведомости; кровля — площадь по скатам с уклоном, примыкания, водосток; фасад — площадь за вычетом проёмов.
• По КР: бетон по маркам (м³), арматура по классам и диаметрам (т) из спецификаций, опалубка (м²), металлоконструкции (т), гидроизоляция, утепление, подготовка, обратная засыпка.
• Объёмы считай по размерам на листах, пиши формулу (например «(12,4+8,2)×2×3,0 − 14,6 проёмы = 108,0 м²»). Спецификации и ведомости переноси как есть, со ссылкой на лист.
• Единицы — как в сметном деле: м³, м², м.п., т, шт, компл.
• Ничего не выдумывай. Если размер не читается — quantity 0 и причина в formula. Если документ — простой перечень работ, оцени объёмы только из данных в тексте.
• В facts выпиши ключевые исходные данные: размеры в осях, высоты этажей, марки бетона, классы арматуры, толщины, материалы стен, кровли, утеплителя.`;

const READ_SCHEMA = {
  type: 'object',
  properties: {
    object: { type: 'string', description: 'что за объект и его основные параметры' },
    facts: { type: 'array', items: { type: 'string' } },
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          section: { type: 'string' }, name: { type: 'string' }, unit: { type: 'string' },
          quantity: { type: 'number' }, formula: { type: 'string' }, source: { type: 'string', description: 'лист / таблица' },
        },
      },
    },
  },
};

const MERGE_SYSTEM = `Ты — главный сметчик. Тебе даны два независимых чтения одних и тех же документов (агенты A и B) и исходные данные.
Сведи их в одну итоговую ВОР:
• объедини одинаковые позиции, убери двойной счёт (одна работа — одна строка в своём разделе);
• если A и B расходятся больше чем на 3 % — пересчитай по исходным размерам и формулам, выбери верное, опиши в discrepancies;
• позиция, которую нашёл только один агент, остаётся, если она обоснована ссылкой на лист или формулой;
• confidence: high — объём из спецификации или чёткой формулы; medium — посчитан по размерам; low — оценка;
• не добавляй работ, которых нет в документах (это сделает аудитор позже);
• name — точная сметная формулировка работы с указанием материала/марки/толщины (например «Кладка наружных стен из газобетонных блоков D500 толщиной 300 мм на клею»);
• id — короткий уникальный код (например «3.2»), раздел.номер.`;

const MERGE_SCHEMA = {
  type: 'object',
  properties: {
    object: {
      type: 'object',
      properties: { name: { type: 'string' }, type: { type: 'string' }, area: { type: 'number' }, floors: { type: 'number' }, summary: { type: 'string' } },
    },
    works: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' }, section: { type: 'string' }, name: { type: 'string' }, unit: { type: 'string' },
          quantity: { type: 'number' }, basis: { type: 'string' }, confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
    assumptions: { type: 'array', items: { type: 'string' } },
    discrepancies: { type: 'array', items: { type: 'string' } },
  },
};

const NORMS_SYSTEM = `Ты — сметчик‑нормировщик. Для каждой работы раздела перечисли все материалы и технику, как в ресурсной смете (ГЭСН/ФЕР и практика рынка РФ).
• materials: name — конкретный материал с маркой/размером/ГОСТ (как его ищут в магазине), unit — единица покупки (м³, т, м², шт, мешок 25 кг, л, кг, м.п., рулон…), norm — расход на ЕДИНИЦУ РАБОТЫ в единицах покупки (например кладка 1 м² стены 300 мм из блоков 600×300×250: 0,3 м³ блоков; клей 25 кг на 1 м³ кладки ⇒ 0,3×25/25 = 0,3 мешка), waste — % отходов и запаса (бетон 1–2, кладка 3–5, плитка 7–12, ламинат 5–8, ГКЛ 10, арматура 1–3);
• учитывай всё: крепёж, клей, грунтовки, сетки, ленты, профили, вязальную проволоку, фиксаторы, плёнки, герметики;
• если позиция сама — материал по спецификации (арматура, т), то norm = 1 с отходом;
• machines: техника и механизмы с единицей (маш.‑ч, смена, рейс) и norm — расход на единицу работы (экскаватор, автобетононасос, автокран, вибратор и т.п.), только где они действительно нужны;
• laborName — как искать на рынке цену самой работы (только работа, без материалов), с той же единицей, что и работа;
• не включай материалы, если работа — монтаж оборудования заказчика.`;

const NORMS_SCHEMA = {
  type: 'object',
  properties: {
    works: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' }, laborName: { type: 'string' },
          materials: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, unit: { type: 'string' }, norm: { type: 'number' }, waste: { type: 'number' } } } },
          machines: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, unit: { type: 'string' }, norm: { type: 'number' } } } },
        },
      },
    },
  },
};

const AUDIT_SYSTEM = `Ты — независимый эксперт‑аудитор смет (проверка для банка и заказчика). Проверь смету:
• пропущенные работы, без которых объект не построить по этим документам (гидроизоляция, утепление, армопояса, перемычки, подготовка, вывоз грунта и мусора, леса, примыкания, временные сети и т.п.) — добавь их в additions с объёмом и обоснованием;
• ошибки единиц и порядков (м² вместо м³, т вместо кг), явно завышенные/заниженные объёмы и цены, двойной счёт работ и материалов;
• severity: critical — сильно искажает итог, warning — стоит проверить, info — замечание;
• verdict — короткий вывод о точности сметы и чего не хватает в исходных данных.
Не повторяй позиции, которые уже есть.`;

const AUDIT_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string' },
    issues: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['critical', 'warning', 'info'] }, text: { type: 'string' } } } },
    additions: {
      type: 'array',
      items: { type: 'object', properties: { section: { type: 'string' }, name: { type: 'string' }, unit: { type: 'string' }, quantity: { type: 'number' }, basis: { type: 'string' } } },
    },
  },
};

/** Agents call the AI through this (replaced in tests). */
let askJSON = (params) => ai.smetaJson({ ...params, timeoutMs: AI_TIMEOUT });
let askPrices = priceEstimate;
export function setAgents({ json, prices } = {}) {
  askJSON = json || ((params) => ai.json({ ...params, timeoutMs: AI_TIMEOUT }));
  askPrices = prices || priceEstimate;
}

const retry = async (fn, times = 2) => {
  let last;
  for (let i = 0; i < times; i += 1) { try { return await fn(); } catch (error) { last = error; if (isOutOfFunds(error)) break; } }
  throw last;
};

/** Pages of all documents in reading chunks (each chunk = a few pages of one document with its text layer). */
export function chunks(input) {
  const result = [];
  for (const doc of input.docs) {
    const kind = DOC_KINDS[doc.kind] || DOC_KINDS.other;
    if (!doc.pages.length) { if (doc.text) result.push({ doc, kind, pages: [], text: doc.text }); continue; }
    for (let i = 0; i < doc.pages.length; i += PAGES_PER_READER) result.push({ doc, kind, pages: doc.pages.slice(i, i + PAGES_PER_READER), first: i + 1 });
  }
  if (input.text) result.push({ doc: { name: 'Описание и перечень работ' }, kind: 'перечень работ / ТЗ от заказчика', pages: [], text: input.text });
  return result;
}

function readerMessages(chunk, input) {
  const head = `Объект: ${input.title || 'не указан'}. Город: ${input.city}.\nДокумент «${chunk.doc.name}» — ${chunk.kind}.`;
  if (!chunk.pages.length) return [{ role: 'user', text: `${head}\n\n${chunk.text.slice(0, 50_000)}` }];
  return chunk.pages.map((page, i) => ({
    role: 'user',
    text: `${i === 0 ? `${head}\n` : ''}Лист ${chunk.first + i}.${page.text ? ` Текстовый слой листа:\n${page.text.slice(0, 12_000)}` : ''}`,
    image: page.image,
  }));
}

const json = (value) => JSON.stringify(value);

async function read(input, onProgress) {
  const list = chunks(input);
  const [modelA, modelB] = [READER_MODELS[0], READER_MODELS[1] || READER_MODELS[0]];
  // Two readers by default (SMETA_READERS=1 — only the first: half the price of this stage, no cross-check).
  const tasks = list.flatMap((chunk) => [{ chunk, model: modelA, agent: 'A' }, ...(READERS > 1 ? [{ chunk, model: modelB, agent: 'B' }] : [])]);
  let done = 0;
  const results = await mapLimit(tasks, 2, async (task) => {
    try {
      return { agent: task.agent, doc: task.chunk.doc.name, ...(await retry(() => askJSON({ system: READER_SYSTEM, messages: readerMessages(task.chunk, input), schema: READ_SCHEMA, name: 'vor', maxTokens: 16_000, model: task.model, anyModel: true, effort: READER_EFFORT }))) };
    } catch (error) { if (isOutOfFunds(error)) throw error; return { agent: task.agent, doc: task.chunk.doc.name, items: [], facts: [], failed: true }; }
    finally { done += 1; onProgress(done / tasks.length); }
  });
  if (results.every((r) => r.failed || !(r.items || []).length)) throw new ApiError(502, 'Не удалось прочитать документы. Проверьте, что листы читаемы, и попробуйте ещё раз.', { retryable: true });
  return results;
}

async function merge(input, readings) {
  const pack = (agent) => readings.filter((r) => r.agent === agent).map((r) => ({ doc: r.doc, object: r.object, facts: r.facts, items: r.items }));
  const text = `Объект: ${input.title || '—'}, город ${input.city}.${input.text ? `\nПожелания заказчика: ${input.text.slice(0, 4000)}` : ''}\n\nАГЕНТ A:\n${json(pack('A'))}\n\nАГЕНТ B:\n${READERS > 1 ? json(pack('B')) : 'второго чтения нет — сверь объёмы агента A с размерами и фактами сам, явные ошибки исправь и опиши в discrepancies'}`;
  const merged = await retry(() => askJSON({ system: MERGE_SYSTEM, messages: [{ role: 'user', text: text.slice(0, 180_000) }], schema: MERGE_SCHEMA, name: 'vor_final', maxTokens: 32_000, model: MERGE_MODEL, anyModel: true, effort: EFFORT }));
  const works = (merged.works || []).map((w, i) => ({
    id: str(w.id, 12) || String(i + 1), section: str(w.section, 60) || 'Прочее', name: str(w.name, 220), unit: str(w.unit, 20),
    quantity: round(num(w.quantity), w.unit), basis: str(w.basis, 400), confidence: ['high', 'medium', 'low'].includes(w.confidence) ? w.confidence : 'medium',
  })).filter((w) => w.name);
  if (!works.length) throw new ApiError(502, 'В документах не нашлось работ для сметы.');
  return { object: merged.object || {}, works, assumptions: (merged.assumptions || []).map((a) => str(a, 400)), discrepancies: (merged.discrepancies || []).map((a) => str(a, 400)) };
}

async function norms(works, input) {
  const bySection = new Map();
  for (const w of works) bySection.set(w.section, [...(bySection.get(w.section) || []), w]);
  const groups = [...bySection.values()].flatMap((list) => { const out = []; for (let i = 0; i < list.length; i += 12) out.push(list.slice(i, i + 12)); return out; });
  const answers = await mapLimit(groups, 2, (group) => retry(() => askJSON({
    system: NORMS_SYSTEM,
    messages: [{ role: 'user', text: `Город: ${input.city}. Работы раздела «${group[0].section}»:\n${json(group.map(({ id, name, unit, quantity, basis }) => ({ id, name, unit, quantity, basis })))}` }],
    schema: NORMS_SCHEMA, name: 'norms', maxTokens: 16_000, model: CHECK_MODEL, anyModel: true, effort: EFFORT,
  })).catch(unlessBroke({ works: [] })));
  const byId = new Map(answers.flatMap((a) => a.works || []).map((w) => [String(w.id), w]));
  // A work the group answer skipped gets its norms on its own: no work may go without materials by accident.
  const skipped = works.filter((w) => !byId.has(w.id));
  const single = await mapLimit(skipped, 2, (w) => retry(() => askJSON({
    system: NORMS_SYSTEM,
    messages: [{ role: 'user', text: `Город: ${input.city}. Работа раздела «${w.section}»:\n${json([{ id: w.id, name: w.name, unit: w.unit, quantity: w.quantity, basis: w.basis }])}` }],
    schema: NORMS_SCHEMA, name: 'norms', maxTokens: 8_000, model: CHECK_MODEL, anyModel: true, effort: EFFORT,
  })).catch(unlessBroke({ works: [] })));
  single.flatMap((a) => a.works || []).forEach((w) => byId.set(String(w.id), w));
  return works.map((w) => {
    const n = byId.get(w.id) || {};
    return {
      ...w,
      laborName: str(n.laborName, 200) || w.name,
      materials: (n.materials || []).map((m) => ({ name: str(m.name, 160), unit: str(m.unit, 20), norm: num(m.norm), waste: num(m.waste), quantity: materialQuantity(w.quantity, m.norm, m.waste, m.unit) })).filter((m) => m.name && m.quantity),
      machines: (n.machines || []).map((m) => ({ name: str(m.name, 120), unit: str(m.unit, 20), norm: num(m.norm), quantity: materialQuantity(w.quantity, m.norm, 0, m.unit) })).filter((m) => m.name && m.quantity),
      normsMissing: !byId.has(w.id),
    };
  });
}

async function price(works, input, onProgress) {
  const materials = aggregateMaterials(works);
  const machines = aggregateMaterials(works.map((w) => ({ id: w.id, materials: w.machines })));
  const items = [
    ...works.map((w) => ({ name: `${w.laborName} — только работа, без материалов`, kind: 'work', unit: w.unit, quantity: w.quantity, ref: { type: 'work', id: w.id } })),
    ...materials.map((m) => ({ name: m.name, kind: 'material', unit: m.unit, quantity: m.quantity, ref: { type: 'material', key: m.key } })),
    ...machines.map((m) => ({ name: `Аренда: ${m.name} (с оператором)`, kind: 'work', unit: m.unit, quantity: m.quantity, ref: { type: 'machine', key: m.key } })),
  ];
  const parts = [];
  for (let i = 0; i < items.length; i += 20) parts.push(items.slice(i, i + 20));
  let done = 0;
  const priced = (await mapLimit(parts, 2, async (part) => {
    try { return (await askPrices({ city: input.city, items: part, maxItems: 20 }, QUALITY)).items; }
    catch (error) { if (isOutOfFunds(error)) throw error; return part.map(() => ({ missing: true })); }
    finally { done += 1; onProgress(done / parts.length); }
  })).flat();
  const prices = new Map(items.map((it, i) => [it.ref.type === 'work' ? `w:${it.ref.id}` : `${it.ref.type}:${it.ref.key}`, priced[i] || { missing: true }]));
  // A price without a single link to an offer is the model's own estimate: marked, and searched again by the price auditor.
  const pick = (p) => {
    const sources = Array.isArray(p?.sources) ? p.sources.slice(0, 3) : [];
    const typical = num(p?.typical);
    return { low: num(p?.low) || typical, typical, high: num(p?.high) || typical, example: str(p?.example, 160), sources, missing: !typical,
      ...(typical && !sources.length ? { estimated: true, note: 'Оценка: ссылка на предложение не найдена' } : {}) };
  };
  return {
    works: works.map((w) => ({ ...w, price: pick(prices.get(`w:${w.id}`)) })),
    materials: materials.map((m) => ({ ...m, price: pick(prices.get(`material:${m.key}`)) })),
    machines: machines.map((m) => ({ ...m, price: pick(prices.get(`machine:${m.key}`)) })),
  };
}

const PRICE_AUDIT_SYSTEM = `Ты — эксперт по ценам строительного рынка РФ (материалы, работы, аренда техники) на текущий год.
Проверь КАЖДУЮ строку: цена за единицу должна соответствовать именно этой единице (м³, м², т, шт, мешок, маш.‑ч…), рынку указанного города,
для работ — только труд без материалов; без ошибок порядка (за упаковку вместо м², за кг вместо т, за весь объём вместо единицы).
Верни ТОЛЬКО проблемные строки и строки без цены (missing): ref как в запросе, problem — что не так по‑русски (коротко, конкретно),
low/typical/high — твоя экспертная рыночная цена за единицу в рублях для этого города. Корректные строки не возвращай.`;

const PRICE_AUDIT_SCHEMA = {
  type: 'object',
  properties: {
    flags: { type: 'array', items: { type: 'object', properties: { ref: { type: 'string' }, problem: { type: 'string' }, low: { type: 'number' }, typical: { type: 'number' }, high: { type: 'number' } } } },
  },
};

/** Every price line checked by an expert agent; doubtful lines searched again with the reason, still doubtful — expert price. */
export async function verifyPrices(priced, input, onProgress = () => {}) {
  const lines = [
    ...priced.works.map((w) => ({ ref: `w:${w.id}`, kind: 'work', name: `${w.laborName || w.name} — только работа`, unit: w.unit, quantity: w.quantity, target: w })),
    ...priced.materials.map((m, i) => ({ ref: `m:${i}`, kind: 'material', name: m.name, unit: m.unit, quantity: m.quantity, target: m })),
    ...priced.machines.map((m, i) => ({ ref: `t:${i}`, kind: 'work', name: `Аренда: ${m.name} (с оператором)`, unit: m.unit, quantity: m.quantity, target: m })),
  ];
  const byRef = new Map(lines.map((l) => [l.ref, l]));
  const groups = [];
  for (let i = 0; i < lines.length; i += 50) groups.push(lines.slice(i, i + 50));
  const flags = (await mapLimit(groups, 2, (group) => retry(() => askJSON({
    system: PRICE_AUDIT_SYSTEM,
    messages: [{ role: 'user', text: `Город: ${input.city}.\n${json(group.map((l) => ({ ref: l.ref, name: l.name, unit: l.unit, quantity: l.quantity, low: l.target.price.low, typical: l.target.price.typical, high: l.target.price.high, missing: l.target.price.missing, example: l.target.price.example, sources: l.target.price.sources.length })))}` }],
    schema: PRICE_AUDIT_SCHEMA, name: 'price_audit', maxTokens: 16_000, model: CHECK_MODEL, anyModel: true, effort: EFFORT,
  })).then((a) => a.flags || []).catch(unlessBroke([])))).flat().filter((f) => byRef.has(f.ref));
  // Prices without a link are searched again too (the auditor's own price stays if nothing better turns up).
  const flaggedRefs = new Set(flags.map((f) => f.ref));
  for (const l of lines) {
    const p = l.target.price;
    if (!flaggedRefs.has(l.ref) && !p.missing && p.typical && !p.sources.length) {
      flags.push({ ref: l.ref, problem: `нет ссылки на предложение — найди магазин или прайс в г. ${input.city} со ссылкой на страницу с ценой`, low: p.low, typical: p.typical, high: p.high });
    }
  }
  onProgress(0.5);
  if (!flags.length) return { checked: lines.length, flagged: 0 };
  // Search again with the reason as a hint.
  const again = await askPrices({ city: input.city, maxItems: flags.length, items: flags.map((f) => { const l = byRef.get(f.ref); return { name: l.name, kind: l.kind, unit: l.unit, quantity: l.quantity, hint: f.problem }; }) }, QUALITY).catch(unlessBroke({ items: [] }));
  flags.forEach((f, i) => {
    const line = byRef.get(f.ref);
    const expert = { low: num(f.low) || num(f.typical), typical: num(f.typical), high: num(f.high) || num(f.typical) };
    const found = again.items?.[i];
    const foundTypical = num(found?.typical);
    // The new market price is taken when it agrees with the expert (within ×2); otherwise the expert price, marked.
    if (foundTypical && (!expert.typical || (foundTypical >= expert.typical / 2 && foundTypical <= expert.typical * 2))) {
      line.target.price = { low: num(found.low) || foundTypical, typical: foundTypical, high: num(found.high) || foundTypical, example: str(found.example, 160), sources: (found.sources || []).slice(0, 3), missing: false, rechecked: true, estimated: !(found.sources || []).length, note: str(f.problem, 200) };
    } else if (expert.typical) {
      line.target.price = { ...line.target.price, ...expert, missing: false, estimated: true, note: `Экспертная цена: ${str(f.problem, 200)}` };
    }
  });
  onProgress(1);
  return { checked: lines.length, flagged: flags.length };
}

async function audit(input, vor, priced) {
  const brief = {
    object: vor.object,
    works: priced.works.map((w) => ({ id: w.id, section: w.section, name: w.name, unit: w.unit, quantity: w.quantity, price: w.price.typical, materials: w.materials.map((m) => `${m.name} ${m.quantity} ${m.unit}`) })),
    materials: priced.materials.map((m) => ({ name: m.name, unit: m.unit, quantity: m.quantity, price: m.price.typical })),
  };
  try {
    return await retry(() => askJSON({ system: AUDIT_SYSTEM, messages: [{ role: 'user', text: `Город ${input.city}.\n${json(brief).slice(0, 180_000)}` }], schema: AUDIT_SCHEMA, name: 'audit', maxTokens: 16_000, model: CHECK_MODEL, anyModel: true, effort: EFFORT }));
  } catch (error) { if (isOutOfFunds(error)) throw error; return { verdict: 'Автоматическая проверка не выполнилась — смету стоит просмотреть вручную.', issues: [], additions: [] }; }
}

/** Sections with sums: works, the materials of those works (share of every purchase line), machines. */
export function assemble(priced) {
  const materialByKey = new Map(priced.materials.map((m) => [m.key, m]));
  const machineByKey = new Map(priced.machines.map((m) => [m.key, m]));
  const zero = () => ({ low: 0, typical: 0, high: 0 });
  const add = (t, p, q) => { t.low += p.low * q; t.typical += p.typical * q; t.high += p.high * q; };
  const sections = new Map();
  for (const w of priced.works) {
    const s = sections.get(w.section) || { title: w.section, works: zero(), materials: zero(), machines: zero(), items: [] };
    add(s.works, w.price, w.quantity);
    const mats = w.materials.map((m) => { const line = materialByKey.get(keyOf(m.name, m.unit)); add(s.materials, line.price, m.quantity); return { ...m, price: line.price, sum: line.price.typical * m.quantity }; });
    const machs = w.machines.map((m) => { const line = machineByKey.get(keyOf(m.name, m.unit)); add(s.machines, line.price, m.quantity); return { ...m, price: line.price, sum: line.price.typical * m.quantity }; });
    s.items.push({ ...w, materials: mats, machines: machs, laborSum: w.price.typical * w.quantity, sum: w.price.typical * w.quantity + mats.reduce((t, m) => t + m.sum, 0) + machs.reduce((t, m) => t + m.sum, 0) });
    sections.set(w.section, s);
  }
  return [...sections.values()];
}

// ---------- jobs ----------

const jobs = new Map();
const jobDir = () => path.join(config.dataDir, 'smeta-jobs');
const jobFile = (id) => path.join(jobDir(), `${id}.json`);
const save = (job) => { fs.mkdirSync(jobDir(), { recursive: true }); fs.writeFileSync(jobFile(job.id), JSON.stringify(job)); };
const waiters = new Map();

function load(id) {
  if (jobs.has(id)) return jobs.get(id);
  try {
    const job = JSON.parse(fs.readFileSync(jobFile(id), 'utf8'));
    // A job that was running when the server restarted cannot continue.
    if (job.status === 'running') Object.assign(job, { status: 'failed', error: 'Сервер перезапускался во время расчёта. Запустите смету ещё раз.' });
    return job;
  } catch { return null; }
}

function update(job, patch) {
  Object.assign(job, patch, { updatedAt: new Date().toISOString() });
  if (job.status !== 'running') { save(job); for (const resolve of waiters.get(job.id) || []) resolve(); waiters.delete(job.id); }
}

/** Cleans the app's upload: documents with page pictures and text, the list of works, the city and options. */
export function cleanInput(body) {
  let pages = 0;
  const docs = (Array.isArray(body?.docs) ? body.docs : []).slice(0, 12).map((d) => ({
    name: str(d?.name, 120) || 'Документ',
    kind: DOC_KINDS[d?.kind] ? d.kind : 'other',
    // Excel (.xlsx) comes as the file itself: every sheet becomes text with tab-separated cells.
    text: typeof d?.xlsx === 'string' && d.xlsx.length > 100 ? xlsxToText(d.xlsx) : String(d?.text ?? '').slice(0, 120_000),
    pages: (Array.isArray(d?.pages) ? d.pages : []).filter((p) => typeof p?.image === 'string' && p.image.length > 100).filter(() => (pages += 1) <= MAX_PAGES)
      .map((p) => ({ image: p.image, text: String(p?.text ?? '').slice(0, 12_000) })),
  })).filter((d) => d.pages.length || d.text.trim());
  const text = String(body?.text ?? '').slice(0, 60_000).trim();
  if (!docs.length && !text) throw new ApiError(400, 'Добавьте документы или перечень работ.');
  const o = body?.options || {};
  const pct = (v, d, max) => (Number.isFinite(Number(v)) ? Math.min(Math.max(Number(v), 0), max) : d);
  return {
    title: str(body?.title, 120), city: str(body?.city, 60) || 'Москва', docs, text,
    options: { vat: Boolean(o.vat), vatPct: 22, deliveryPct: pct(o.deliveryPct, 4, 20), contingencyPct: pct(o.contingencyPct, 5, 30) },
  };
}

// Volumes and norms of a job that stopped (no AI balance, a failure later on) are kept: the same documents sent again
// continue from the prices, without paying for reading the sheets a second time.
const stageDir = () => path.join(config.dataDir, 'smeta-stages');
const inputKey = (input) => crypto.createHash('sha256').update(JSON.stringify({ city: input.city, text: input.text, docs: input.docs })).digest('hex').slice(0, 32);
function loadStages(key) {
  try {
    const saved = JSON.parse(fs.readFileSync(path.join(stageDir(), `${key}.json`), 'utf8'));
    return Date.now() - Date.parse(saved.at) < 7 * 86_400_000 ? saved : null;
  } catch { return null; }
}
const saveStages = (key, data) => { fs.mkdirSync(stageDir(), { recursive: true }); fs.writeFileSync(path.join(stageDir(), `${key}.json`), JSON.stringify({ ...data, at: new Date().toISOString() })); };
const dropStages = (key) => fs.rmSync(path.join(stageDir(), `${key}.json`), { force: true });

const usd = (x) => Math.round(x * 10_000) / 10_000;

/** Runs a job; every AI answer inside is counted (job.cost, $ by stage — for the owner, not shown in the app). */
export async function run(job, input) {
  const meter = newMeter();
  try {
    await withCost(meter, () => runJob(job, input, meter));
  } finally {
    job.cost = { usd: usd(meter.total), calls: meter.calls, stages: Object.fromEntries(Object.entries(meter.stages).map(([k, v]) => [k, usd(v)])) };
    save(job);
    console.log(`[smeta] ${job.id} «${job.title || ''}» ${job.status}: $${job.cost.usd} за ${meter.calls} запросов ${JSON.stringify(job.cost.stages)}`);
  }
}

async function runJob(job, input, meter) {
  const stage = (name, title, progress = 0) => { meter.stage = name; update(job, { stage: name, stageTitle: title, progress }); };
  const key = inputKey(input);
  try {
    const saved = loadStages(key);
    let vor;
    let works;
    if (saved) {
      stage('resume', 'Продолжаем: объёмы и нормы уже посчитаны в прошлый раз', 0.5);
      ({ vor, works } = saved);
    } else {
      stage('read', READERS > 1 ? 'Два агента читают документы и снимают объёмы' : 'Сметчик читает документы и снимает объёмы');
      const readings = await read(input, (p) => update(job, { progress: p }));
      stage('merge', 'Главный сметчик сводит ведомость объёмов', 0.5);
      vor = await merge(input, readings);
      stage('norms', 'Нормы расхода материалов и техника по каждой работе', 0.5);
      works = await norms(vor.works, input);
      saveStages(key, { vor, works });
    }
    stage('prices', `Рыночные цены в г. ${input.city}: работы, материалы, техника`);
    let priced = await price(works, input, (p) => update(job, { progress: p }));
    stage('audit', 'Аудитор проверяет смету', 0.5);
    const check = await audit(input, vor, priced);
    const additions = (check.additions || []).map((a, i) => ({
      id: `A${i + 1}`, section: str(a.section, 60) || 'Прочее', name: str(a.name, 220), unit: str(a.unit, 20), quantity: round(num(a.quantity), a.unit),
      basis: `Добавлено проверкой: ${str(a.basis, 300)}`, confidence: 'low', added: true,
    })).filter((a) => a.name && a.quantity);
    if (additions.length) {
      stage('additions', 'Считаем работы, добавленные аудитором', 0.3);
      works = [...works, ...(await norms(additions, input))];
      priced = await price(works, input, () => {});
    }
    stage('verify', 'Ценовой аудитор проверяет каждую цену', 0);
    const priceCheck = await verifyPrices(priced, input, (p) => update(job, { progress: p }));
    const sections = assemble(priced);
    const result = {
      title: input.title || vor.object?.name || 'Смета', city: input.city, createdAt: new Date().toISOString(),
      object: vor.object, sections, materials: priced.materials, machines: priced.machines,
      totals: totals(sections, input.options), options: input.options,
      assumptions: vor.assumptions, discrepancies: vor.discrepancies,
      audit: { verdict: str(check.verdict, 1200), issues: (check.issues || []).map((x) => ({ severity: x.severity, text: str(x.text, 600) })), added: additions.length, pricesChecked: priceCheck.checked, pricesFixed: priceCheck.flagged },
      sources: input.docs.map((d) => ({ name: d.name, kind: d.kind, pages: d.pages.length })),
      unpriced: priced.works.filter((w) => w.price.missing).length + priced.materials.filter((m) => m.price.missing).length,
    };
    dropStages(key);
    update(job, { status: 'done', stage: 'done', stageTitle: 'Готово', progress: 1, result });
  } catch (error) {
    const failedAt = job.stage;
    const broke = isOutOfFunds(error);
    if (broke) console.warn(`[smeta] ${job.id}: остановлена на этапе ${failedAt} — ${error.message}`);
    update(job, { status: 'failed', error: broke
      ? 'ИИ на сервере временно без баланса, поэтому смета остановлена, а не выдана с пустыми строками. Всё уже посчитанное сохранено: запустите эту смету ещё раз с теми же файлами чуть позже — расчёт продолжится с того же места.'
      : error instanceof ApiError ? error.message : 'Не удалось посчитать смету. Попробуйте ещё раз.' });
    // The credits come back when the estimate could not be made.
    // Before the expensive stages — everything back; after them — half (the AI work was already paid for); our empty balance — everything.
    if (job.credits) billing.refund(job.installId, 'smeta', broke || ['queued', 'read', 'merge'].includes(failedAt) ? job.credits : Math.floor(job.credits / 2));
    if (!(error instanceof ApiError)) console.error('[smeta]', error);
  }
}

export function create(body, installId, { credits = 0 } = {}) {
  const input = cleanInput(body);
  const job = { id: crypto.randomUUID(), installId, status: 'running', stage: 'queued', stageTitle: 'В очереди', progress: 0, createdAt: new Date().toISOString(), credits, title: input.title, pages: input.docs.reduce((t, d) => t + d.pages.length, 0) };
  jobs.set(job.id, job);
  run(job, input);
  return view(job);
}

const view = (job) => ({ id: job.id, status: job.status, stage: job.stage, stageTitle: job.stageTitle, progress: Math.round((job.progress || 0) * 100) / 100, error: job.error, result: job.status === 'done' ? job.result : undefined });

export function status(id, installId) {
  const job = load(String(id));
  if (!job || job.installId !== installId) throw new ApiError(404, 'Смета не найдена.');
  return view(job);
}

/** Long poll: answers when the job ends or after `ms` (the app asks again; the background session keeps the request). */
export async function wait(id, installId, ms = 240_000) {
  const job = load(String(id));
  if (!job || job.installId !== installId) throw new ApiError(404, 'Смета не найдена.');
  if (job.status === 'running') {
    await new Promise((resolve) => {
      const timer = setTimeout(resolve, ms);
      waiters.set(job.id, [...(waiters.get(job.id) || []), () => { clearTimeout(timer); resolve(); }]);
    });
  }
  return view(job);
}

// Old finished jobs are removed.
setInterval(() => {
  try {
    for (const file of fs.readdirSync(jobDir())) {
      const full = path.join(jobDir(), file);
      if (Date.now() - fs.statSync(full).mtimeMs > KEEP_DAYS * 86_400_000) fs.unlinkSync(full);
    }
  } catch { /* no jobs yet */ }
  try {
    for (const file of fs.readdirSync(stageDir())) {
      const full = path.join(stageDir(), file);
      if (Date.now() - fs.statSync(full).mtimeMs > 7 * 86_400_000) fs.rmSync(full, { force: true });
    }
  } catch { /* nothing kept */ }
  for (const [id, job] of jobs) if (job.status !== 'running' && Date.now() - Date.parse(job.updatedAt || job.createdAt) > 3_600_000) jobs.delete(id);
}, 3_600_000).unref();
