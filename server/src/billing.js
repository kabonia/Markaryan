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
 * Credits per use. 1 credit is sold for 10–12 ₽ / $0.10–0.13; every price is ≥ 3× the WORST AI cost of the call
 * (the most expensive model, retries, the longest answer), so no usage pattern can make a loss.
 */
export const PRICES = {
  helper: 1,          // the in‑app helper after HELPER_FREE_PER_DAY free questions (worst cost ≈ 0.3 ₽)
  chat: 12,           // a question to the strong model (worst ≈ 36 ₽ incl. reasoning; typical 3–5 ₽)
  material: 2,        // «свой материал» recognised (worst ≈ 6 ₽)
  priceEstimateItem: 1, // market price of one line with web search (worst ≈ 2.5 ₽)
  imageEdit: 8,       // one photoreal picture (worst ≈ 25 ₽)
  image: 8,
  vision: 10,         // photo counting and other photo analysis (worst ≈ 30 ₽)
  json: 20,           // design concept of a room (worst ≈ 60 ₽)
  smeta: 200,         // estimate from documents: up to 2 sheets or 6 000 characters of text/Excel (worst ≈ 600 ₽)
  smetaPage: 40,      // every further sheet or 6 000 characters (worst ≈ 75 ₽ per sheet incl. pricing and checks)
};
export const SMETA_MAX_PAGES = 100;
export const TEXT_PER_PAGE = 6000;

/** Price of one call. units: {pages, textChars} for estimates from documents, {items} for market estimates. */
export function price(kind, units = {}) {
  if (kind === 'smeta') {
    const sheets = Math.min(units.pages || 0, SMETA_MAX_PAGES) + Math.ceil((units.textChars || 0) / TEXT_PER_PAGE);
    return PRICES.smeta + Math.max(0, sheets - 2) * PRICES.smetaPage;
  }
  if (kind === 'priceEstimate') return Math.max(3, (units.items || 0) * PRICES.priceEstimateItem);
  return PRICES[kind] ?? 0;
}

/** What can be bought. Russia: rubles on the website (ЮKassa); App Store: the apple ids (set up in App Store Connect). */
export const PRODUCTS = [
  { id: 'pro_month', title: 'СметаПро Про — 1 месяц', titleEn: 'SmetaPro Pro — monthly', plan: 'pro', days: 31, credits: 80, rub: 990, usd: 12.99, apple: 'smetapro.pro.monthly' },
  { id: 'pro_year', title: 'СметаПро Про — 1 год', titleEn: 'SmetaPro Pro — yearly', plan: 'pro', days: 366, credits: 80, monthly: true, rub: 9490, usd: 119.99, apple: 'smetapro.pro.yearly' },
  { id: 'business_month', title: 'СметаПро Бизнес — 1 месяц', titleEn: 'SmetaPro Business — monthly', plan: 'business', days: 31, credits: 350, rub: 3490, usd: 44.99, apple: 'smetapro.business.monthly' },
  { id: 'credits_100', title: '100 кредитов', titleEn: '100 credits', credits: 100, rub: 1190, usd: 11.99, apple: 'smetapro.credits.100' },
  { id: 'credits_500', title: '500 кредитов', titleEn: '500 credits', credits: 500, rub: 5490, usd: 54.99, apple: 'smetapro.credits.500' },
  { id: 'credits_1500', title: '1500 кредитов', titleEn: '1500 credits', credits: 1500, rub: 14990, usd: 149.99, apple: 'smetapro.credits.1500' },
];
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
  const amount = price(kind, units);
  if (!amount) return 0;
  if (acc.credits < amount) {
    throw new ApiError(402, `Недостаточно кредитов: нужно ${amount}, на балансе ${acc.credits}. Пополните баланс в Профиле → «Тарифы и баланс».`);
  }
  acc.credits -= amount;
  log({ installId, type: 'charge', kind, credits: -amount, balance: acc.credits });
  save();
  return amount;
}

/** Gives the credits back when the AI failed. */
export function refund(installId, kind, amount) {
  if (!enabled() || !amount) return;
  const acc = account(installId);
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
    prices: PRICES, helperFreePerDay: HELPER_FREE_PER_DAY, smetaMaxPages: SMETA_MAX_PAGES, textPerPage: TEXT_PER_PAGE, products: PRODUCTS.map(({ id, title, titleEn, plan, credits, rub, usd, apple, days }) => ({ id, title, titleEn, plan: plan || null, credits, rub, usd, apple, days: days || null })),
    payUrl: process.env.PAY_PAGE_URL || null,
  };
}
