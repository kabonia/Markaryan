// Credits and plans: every paid AI function costs credits (always ≥ 2.5× its AI cost), credits come from plans and packs
// bought on the website (ЮKassa: СБП and cards, Russia) or in the app (App Store in‑app purchases, USA and the rest).
// Off until BILLING_ENABLED=1, so the app keeps working while payments are being connected.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { ApiError } from './util.js';

export const enabled = () => process.env.BILLING_ENABLED === '1';
export const WELCOME_CREDITS = Number(process.env.BILLING_WELCOME || 10);
/** Free helper questions per day; after them every question costs 1 credit. */
export const HELPER_FREE_PER_DAY = Number(process.env.BILLING_HELPER_FREE || 20);
/** Welcome credits: at most this many new accounts per IP in 30 days (reinstalling the app is not a credit farm). */
const WELCOME_PER_IP = 3;

/**
 * Credits per use. Правило владельца (26.11): отдельная функция — наценка 230–250 % к обычной себестоимости,
 * пакеты — 170–230 %. Считаем на 1 кредит ≈ 10 ₽ чистыми (сайт; App Store при комиссии 15 % — так же, цены в $ выровнены).
 * Наценка = чистая выручка / обычная себестоимость − 1. Себестоимость: docs/audit/ECONOMICS-2026-11.md.
 * Худший случай (самая дорогая модель, длинный ответ, повтор) у чата, фото и сметы может быть дороже цены — смотрите
 * data/costs.log (`node scripts/cost-report.mjs 7`) и поднимайте цену, если средняя себестоимость вырастет.
 */
export const PRICES = {
  helper: 1,          // помощник после HELPER_FREE_PER_DAY бесплатных (0,05 ₽; меньше 1 кредита нельзя)
  chat: 2,            // вопрос сильной модели: 6 ₽ → 20 ₽, +233 % (худшая 43 ₽)
  material: 1,        // «свой материал»: 2,5 ₽ → 10 ₽, +300 % (меньше 1 кредита нельзя)
  priceEstimate10: 1, // цены по рынку, за каждые 10 строк (0,3 ₽ строка → 3 ₽ → 10 ₽, +233 %)
  imageEdit: 4,       // фотореалистичный кадр: 12 ₽ → 40 ₽, +233 % (худшая 30 ₽)
  image: 4,
  vision: 4,          // счёт и анализ по фото: 12 ₽ → 40 ₽, +233 % (худшая 58 ₽)
  json: 9,            // дизайн‑концепция комнаты: 27 ₽ → 90 ₽, +233 % (худшая 50 ₽)
  smeta: 30,          // смета по документам до 2 листов / 6 000 знаков: ≈ 90 ₽ → 300 ₽, +233 % (худшая 450 ₽)
  smetaPage: 14,      // каждый следующий лист: ≈ 40 ₽ → 140 ₽, +250 %
  houseRoof: 1,       // только прямой вызов API: в приложении крыша по фото входит в «3D‑обмер дома» (2,7 ₽)
  houseScan: 9,       // 3D‑обмер дома с крышей по фото: с GPU ≈ 26 ₽ → 90 ₽, +246 % (без GPU ≈ 3 ₽); при неудаче — возврат
};
export const SMETA_MAX_PAGES = 100;
export const TEXT_PER_PAGE = 6000;

/** Price of one call. units: {pages, textChars} for estimates from documents, {items} for market estimates. */
export function price(kind, units = {}) {
  if (kind === 'smeta') {
    const sheets = Math.min(units.pages || 0, SMETA_MAX_PAGES) + Math.ceil((units.textChars || 0) / TEXT_PER_PAGE);
    return PRICES.smeta + Math.max(0, sheets - 2) * PRICES.smetaPage;
  }
  if (kind === 'priceEstimate') return Math.max(1, Math.ceil((units.items || 0) / 10)) * PRICES.priceEstimate10;
  return PRICES[kind] ?? 0;
}

/** What can be bought. Russia: rubles on the website (ЮKassa); App Store: the apple ids (set up in App Store Connect). */
export const PRODUCTS = [
  { id: 'pro_month', title: 'СметаПро Про — 1 месяц', titleEn: 'SmetaPro Pro — monthly', plan: 'pro', days: 31, credits: 80, rub: 990, usd: 12.99, apple: 'smetapro.pro.monthly' },
  { id: 'pro_year', title: 'СметаПро Про — 1 год', titleEn: 'SmetaPro Pro — yearly', plan: 'pro', days: 366, credits: 80, monthly: true, rub: 9490, usd: 119.99, apple: 'smetapro.pro.yearly' },
  { id: 'business_month', title: 'СметаПро Бизнес — 1 месяц', titleEn: 'SmetaPro Business — monthly', plan: 'business', days: 31, credits: 350, rub: 3490, usd: 44.99, apple: 'smetapro.business.monthly' },
  { id: 'credits_100', title: '100 кредитов', titleEn: '100 credits', credits: 100, rub: 1190, usd: 14.99, apple: 'smetapro.credits.100' },
  { id: 'credits_500', title: '500 кредитов', titleEn: '500 credits', credits: 500, rub: 5490, usd: 69.99, apple: 'smetapro.credits.500' },
  { id: 'credits_1500', title: '1500 кредитов', titleEn: '1500 credits', credits: 1500, rub: 14990, usd: 189.99, apple: 'smetapro.credits.1500' },
];
/**
 * Пакеты функций: человек покупает набор под задачу, а не кредиты. Пока в пакете есть единицы функции — кредиты не
 * тратятся; ИИ не справился — единица возвращается. Наценка 170–230 % к обычной себестоимости (сайт и App Store 15 %),
 * для покупателя — на 12–25 % дешевле, чем те же функции за кредиты. Расчёт: docs/audit/ECONOMICS-2026-11.md.
 */
export const PACKS = [
  { id: 'pack_house', title: '3D‑обмер дома', titleEn: '3D house measurement', rub: 390, usd: 5.49, apple: 'smetapro.pack.house',
    grants: { houseScan: 1, imageEdit: 6, chat: 3 },
    includes: '1 3D‑обмер дома (стены, окна и двери, крыша: тип, уклон, высота конька), 6 визуализаций фасада, 3 вопроса ИИ' },
  { id: 'pack_room', title: 'Дизайн комнаты', titleEn: 'Room design', rub: 790, usd: 10.99, apple: 'smetapro.pack.room',
    grants: { json: 3, imageEdit: 10, priceEstimateItem: 30, material: 5 },
    includes: '3 дизайн‑концепции, 10 фотореалистичных кадров, цены рынка на 30 позиций, 5 своих материалов' },
  { id: 'pack_smeta', title: 'Смета по проекту', titleEn: 'Project estimate', rub: 1390, usd: 19.99, apple: 'smetapro.pack.smeta',
    grants: { smeta: 1, smetaPage: 8, priceEstimateItem: 40 },
    includes: '1 смета по документам до 10 листов, цены рынка на 40 позиций' },
  { id: 'pack_smeta3', title: '3 сметы по проектам', titleEn: '3 project estimates', rub: 3890, usd: 54.99, apple: 'smetapro.pack.smeta3',
    grants: { smeta: 3, smetaPage: 24, priceEstimateItem: 120 },
    includes: '3 сметы по документам до 10 листов, цены рынка на 120 позиций' },
  { id: 'pack_renovation', title: 'Ремонт квартиры', titleEn: 'Apartment renovation', rub: 2490, usd: 34.99, apple: 'smetapro.pack.renovation',
    grants: { json: 6, imageEdit: 20, priceEstimateItem: 100, smeta: 1, smetaPage: 4, vision: 5 },
    includes: '6 дизайн‑концепций, 20 кадров, цены на 100 позиций, 1 смета до 6 листов, 5 разборов фото' },
  { id: 'pack_foreman', title: 'Прораб на месяц', titleEn: 'Site manager — month', rub: 1290, usd: 18.99, apple: 'smetapro.pack.foreman',
    grants: { vision: 20, chat: 20, material: 10, helper: 300 },
    includes: '20 счётов и разборов по фото, 20 вопросов ИИ, 10 своих материалов, 300 вопросов помощнику' },
];
for (const pack of PACKS) PRODUCTS.push({ ...pack, credits: 0 });

export const product = (id) => PRODUCTS.find((p) => p.id === id || p.apple === id);

// ---------- storage ----------

const file = () => path.join(config.dataDir, 'billing.json');
const ledgerFile = () => path.join(config.dataDir, 'billing-ledger.log');
let state = null;
function load() {
  if (state) return state;
  try { state = JSON.parse(fs.readFileSync(file(), 'utf8')); } catch { state = { accounts: {}, refs: {}, welcome: {} }; }
  state.accounts ||= {}; state.refs ||= {}; state.welcome ||= {};
  return state;
}
function save() {
  fs.mkdirSync(config.dataDir, { recursive: true });
  fs.writeFileSync(`${file()}.tmp`, JSON.stringify(state));
  fs.renameSync(`${file()}.tmp`, file());
}
function log(entry) {
  fs.mkdirSync(config.dataDir, { recursive: true });
  fs.appendFileSync(ledgerFile(), `${JSON.stringify({ at: new Date().toISOString(), ...entry })}\n`);
}
/** For tests. */
export function reset() { state = { accounts: {}, refs: {}, welcome: {} }; }

/** Account number the person types on the payment page: SP‑XXXX‑XXXX (no personal data). */
export function codeFor(installId) {
  const h = crypto.createHash('sha256').update(`smetapro:${installId}`).digest('hex').toUpperCase().replace(/[^0-9A-F]/g, '');
  return `SP-${h.slice(0, 4)}-${h.slice(4, 8)}`;
}

export function account(installId, ip = '') {
  const s = load();
  if (!s.accounts[installId]) {
    // Welcome credits only for the first few accounts from one address in 30 days.
    const month = Date.now() - 30 * 86_400_000;
    const recent = (s.welcome[ip] || []).filter((t) => t > month);
    const gift = ip && recent.length >= WELCOME_PER_IP ? 0 : WELCOME_CREDITS;
    if (ip && gift) s.welcome[ip] = [...recent, Date.now()];
    s.accounts[installId] = { code: codeFor(installId), credits: gift, createdAt: new Date().toISOString() };
    log({ installId, type: 'welcome', credits: gift, ip });
    save();
  }
  return s.accounts[installId];
}

export function findByCode(code) {
  const wanted = String(code || '').toUpperCase().replace(/\s/g, '');
  const s = load();
  const id = Object.keys(s.accounts).find((k) => s.accounts[k].code === wanted);
  return id ? { installId: id, account: s.accounts[id] } : null;
}

// ---------- spending ----------

/** Takes the credits before the AI runs; throws 402 with a clear message when the balance is short. Returns the amount. */
export function charge(installId, kind, units = {}, ip = '') {
  if (!enabled()) return 0;
  const acc = account(installId, ip);
  if (kind === 'helper') {
    // Free questions to the helper every day, then 1 credit each.
    const day = new Date().toISOString().slice(0, 10);
    if (acc.helperDay !== day) { acc.helperDay = day; acc.helperUsed = 0; }
    acc.helperUsed += 1;
    if (acc.helperUsed <= HELPER_FREE_PER_DAY) { save(); return 0; }
  }
  const fromPack = usePack(acc, kind, units);
  const amount = fromPack ? fromPack.credits : price(kind, units);
  if (fromPack) {
    // Остаток (например, листы сметы сверх пакета) — кредитами; если их не хватает, единицы пакета не тратятся.
    if (acc.credits < amount) throw new ApiError(402, `Недостаточно кредитов: нужно ${amount} сверх пакета, на балансе ${acc.credits}.`);
    for (const [k, n] of Object.entries(fromPack.used)) acc.packs[k] -= n;
    (acc.packUses ||= []).push({ kind, used: fromPack.used, at: Date.now() });
    if (acc.packUses.length > 20) acc.packUses.shift();
    acc.credits -= amount;
    log({ installId, type: 'pack', kind, used: fromPack.used, credits: -amount, balance: acc.credits });
    save();
    return amount;
  }
  if (!amount) return 0;
  if (acc.credits < amount) {
    throw new ApiError(402, `Недостаточно кредитов: нужно ${amount}, на балансе ${acc.credits}. Пополните баланс в Профиле → «Тарифы и баланс».`);
  }
  acc.credits -= amount;
  log({ installId, type: 'charge', kind, credits: -amount, balance: acc.credits });
  save();
  return amount;
}

/** Сколько единиц пакета покроет вызов: {used: {вид: n}, credits: остаток кредитами} или null — пакета нет. */
function usePack(acc, kind, units = {}) {
  const packs = acc.packs || {};
  if (kind === 'smeta') {
    if (!(packs.smeta > 0)) return null;
    const sheets = Math.min(units.pages || 0, SMETA_MAX_PAGES) + Math.ceil((units.textChars || 0) / TEXT_PER_PAGE);
    const extra = Math.max(0, sheets - 2);
    const pages = Math.min(extra, packs.smetaPage || 0);
    return { used: pages ? { smeta: 1, smetaPage: pages } : { smeta: 1 }, credits: (extra - pages) * PRICES.smetaPage };
  }
  if (kind === 'priceEstimate') {
    const items = units.items || 0;
    const covered = Math.min(items, packs.priceEstimateItem || 0);
    if (!covered) return null;
    return { used: { priceEstimateItem: covered }, credits: Math.ceil((items - covered) / 10) * PRICES.priceEstimate10 };
  }
  return packs[kind] > 0 ? { used: { [kind]: 1 }, credits: 0 } : null;
}

/** Gives the credits back when the AI failed; единицы пакета последнего такого вызова — тоже. */
export function refund(installId, kind, amount) {
  if (!enabled()) return;
  const acc = account(installId);
  const uses = acc.packUses || [];
  const index = uses.map((u) => u.kind).lastIndexOf(kind);
  if (index >= 0 && Date.now() - uses[index].at < 3_600_000) {
    const [use] = uses.splice(index, 1);
    for (const [k, n] of Object.entries(use.used)) acc.packs[k] = (acc.packs[k] || 0) + n;
    log({ installId, type: 'pack-refund', kind, used: use.used, balance: acc.credits });
  }
  if (!amount) { save(); return; }
  acc.credits += amount;
  log({ installId, type: 'refund', kind, credits: amount, balance: acc.credits });
  save();
}

// ---------- buying ----------

/**
 * Credits and the plan for a paid product. `ref` (payment or transaction id) makes it idempotent: a repeated webhook
 * or a repeated App Store sync never pays twice. `until` — for App Store subscriptions, their own expiry date.
 */
export function grant(installId, productId, source, ref, { until } = {}) {
  const p = product(productId);
  if (!p) throw new ApiError(400, 'Неизвестный тариф.');
  const s = load();
  if (s.refs[ref]) return { duplicate: true, account: s.accounts[installId] };
  const acc = account(installId);
  acc.credits += p.credits;
  if (p.grants) {
    acc.packs ||= {};
    for (const [kind, count] of Object.entries(p.grants)) acc.packs[kind] = (acc.packs[kind] || 0) + count;
  }
  if (p.plan) {
    const from = acc.plan && Date.parse(acc.plan.until) > Date.now() && acc.plan.id === p.plan ? Date.parse(acc.plan.until) : Date.now();
    const end = until ? Date.parse(until) : from + p.days * 86_400_000;
    acc.plan = { id: p.plan, product: p.id, until: new Date(end).toISOString(), source, monthly: p.monthly ? { credits: p.credits, next: new Date(Date.now() + 30 * 86_400_000).toISOString() } : undefined };
  }
  s.refs[ref] = { installId, product: p.id, source, at: new Date().toISOString() };
  log({ installId, type: 'grant', product: p.id, source, ref, credits: p.credits, balance: acc.credits });
  save();
  return { duplicate: false, account: acc };
}

/** Money returned (App Store refund, ЮKassa refund): the credits of that purchase are taken back, even below zero. */
export function revoke(ref, source) {
  const s = load();
  const entry = s.refs[ref];
  if (!entry || entry.revoked) return { status: 'unknown' };
  const acc = s.accounts[entry.installId];
  const p = product(entry.product);
  entry.revoked = new Date().toISOString();
  if (acc && p) {
    acc.credits -= p.credits;
    if (p.grants && acc.packs) for (const [kind, count] of Object.entries(p.grants)) acc.packs[kind] = Math.max(0, (acc.packs[kind] || 0) - count);
    if (p.plan && acc.plan?.product === p.id) acc.plan.until = new Date().toISOString();
    log({ installId: entry.installId, type: 'revoke', ref, source, credits: -p.credits, balance: acc.credits });
  }
  save();
  return { status: 'revoked' };
}

/** Yearly plans give their credits every month. Called on every request of the person (cheap). */
export function monthlyTopUp(installId) {
  const acc = load().accounts[installId];
  const m = acc?.plan?.monthly;
  if (!m || Date.parse(acc.plan.until) < Date.now() || Date.parse(m.next) > Date.now()) return;
  acc.credits += m.credits;
  m.next = new Date(Date.parse(m.next) + 30 * 86_400_000).toISOString();
  log({ installId, type: 'monthly', credits: m.credits, balance: acc.credits });
  save();
}

export function setPaymentMethod(installId, method) {
  const acc = account(installId);
  acc.autopay = method ? { ...method, on: true } : undefined;
  save();
}

export function setAutopay(installId, on) {
  const acc = account(installId);
  if (acc.autopay) acc.autopay.on = Boolean(on);
  save();
  return acc;
}

/** Последние операции аккаунта из журнала (для поддержки): списания, возвраты, покупки. Читает только хвост файла. */
export function history(installId, limit = 5) {
  try {
    const fd = fs.openSync(ledgerFile(), 'r');
    const size = fs.fstatSync(fd).size, length = Math.min(size, 2_000_000);
    const buffer = Buffer.alloc(length);
    fs.readSync(fd, buffer, 0, length, size - length);
    fs.closeSync(fd);
    return buffer.toString('utf8').split('\n').reverse().flatMap((line) => {
      if (!line.includes(installId)) return [];
      try { const e = JSON.parse(line); return e.installId === installId ? [e] : []; } catch { return []; }
    }).slice(0, limit);
  } catch { return []; }
}

/** Компенсация от поддержки: кредиты на баланс (работает и при выключенной оплате). */
export function compensate(installId, credits, ref) {
  const n = Math.max(0, Math.min(5000, Math.floor(Number(credits) || 0)));
  if (!n) return 0;
  const acc = account(installId);
  acc.credits += n;
  log({ installId, type: 'support', credits: n, ref, balance: acc.credits });
  save();
  return n;
}

export function allAccounts() { return Object.entries(load().accounts); }
export function persist() { save(); }

/** What the app shows: balance, plan, prices of functions and products. */
export function me(installId) {
  monthlyTopUp(installId);
  const acc = account(installId);
  const active = acc.plan && Date.parse(acc.plan.until) > Date.now() ? acc.plan : null;
  return {
    enabled: enabled(), code: acc.code, credits: acc.credits, plan: active,
    autopay: acc.autopay ? { on: acc.autopay.on, title: acc.autopay.title } : null,
    packs: Object.fromEntries(Object.entries(acc.packs || {}).filter(([, n]) => n > 0)),
    prices: PRICES, helperFreePerDay: HELPER_FREE_PER_DAY, smetaMaxPages: SMETA_MAX_PAGES, textPerPage: TEXT_PER_PAGE,
    products: PRODUCTS.map(({ id, title, titleEn, plan, credits, rub, usd, apple, days, grants, includes }) => ({ id, title, titleEn, plan: plan || null, credits, rub, usd, apple, days: days || null, grants: grants || null, includes: includes || null })),
    payUrl: process.env.PAY_PAGE_URL || null,
  };
}
