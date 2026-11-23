// Payments: ЮKassa (Russia — СБП and cards, autopay for plans, 54‑ФЗ receipts) and the App Store (USA and the rest —
// in‑app purchases paid with Apple Pay / the Apple ID card). Both only add credits through billing.grant (idempotent).
import crypto from 'node:crypto';
import { ApiError, request, readJSON } from './util.js';
import * as billing from './billing.js';

// ---------- ЮKassa ----------

const yk = () => ({
  shopId: process.env.YOOKASSA_SHOP_ID || '', secret: process.env.YOOKASSA_SECRET_KEY || '',
  vat: Number(process.env.YOOKASSA_VAT_CODE || 1), // 1 — без НДС (УСН); for ОСН set the code of your VAT rate
  recurring: process.env.YOOKASSA_RECURRING === '1', returnUrl: process.env.PAY_RETURN_URL || '',
});
export const yookassaReady = () => Boolean(yk().shopId && yk().secret);

let fetchImpl = (url, options) => request(url, options, 30_000);
export function setFetch(fn) { fetchImpl = fn || ((url, options) => request(url, options, 30_000)); }

async function ykApi(method, pathName, body) {
  const { shopId, secret } = yk();
  if (!shopId || !secret) throw new ApiError(503, 'Оплата ещё не подключена.');
  const response = await fetchImpl(`https://api.yookassa.ru/v3/${pathName}`, {
    method,
    headers: { Authorization: `Basic ${Buffer.from(`${shopId}:${secret}`).toString('base64')}`, 'Content-Type': 'application/json', 'Idempotence-Key': crypto.randomUUID() },
    body: body ? JSON.stringify(body) : undefined,
  });
  const result = await readJSON(response);
  if (!response.ok) throw new ApiError(502, `ЮKassa: ${result?.description || `ошибка ${response.status}`}`);
  return result;
}

const receipt = (p, email) => ({
  customer: { email },
  items: [{ description: p.title.slice(0, 128), quantity: '1.00', amount: { value: p.rub.toFixed(2), currency: 'RUB' }, vat_code: yk().vat, payment_subject: 'service', payment_mode: 'full_payment' }],
});

/** The payment page sends the account number, e‑mail (for the receipt), product and method; answer — where to pay. */
export async function createYookassa(body) {
  const found = billing.findByCode(body?.code);
  if (!found) throw new ApiError(404, 'Аккаунт не найден. Номер — в приложении: Профиль → «Тарифы и баланс».');
  const p = billing.product(String(body?.product || ''));
  if (!p?.rub) throw new ApiError(400, 'Выберите тариф.');
  const email = String(body?.email || '').trim().slice(0, 120);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new ApiError(400, 'Укажите почту — на неё придёт чек.');
  const method = body?.method === 'card' ? 'bank_card' : 'sbp';
  const payment = await ykApi('POST', 'payments', {
    amount: { value: p.rub.toFixed(2), currency: 'RUB' },
    capture: true,
    payment_method_data: { type: method },
    confirmation: { type: 'redirect', return_url: yk().returnUrl || `${String(body?.origin || '').replace(/\/$/, '')}/pay/done` },
    description: `${p.title}, аккаунт ${found.account.code}`.slice(0, 128),
    save_payment_method: Boolean(p.plan && yk().recurring),
    receipt: receipt(p, email),
    metadata: { installId: found.installId, product: p.id, email },
  });
  return { id: payment.id, url: payment.confirmation?.confirmation_url };
}

/** Applies a payment after checking it with ЮKassa itself (the webhook body is never trusted on its own). */
export async function applyYookassa(paymentId) {
  const payment = await ykApi('GET', `payments/${encodeURIComponent(paymentId)}`);
  if (payment.status !== 'succeeded' || !payment.paid) return { status: payment.status };
  const { installId, product, email } = payment.metadata || {};
  if (!installId || !product) return { status: 'ignored' };
  const result = billing.grant(installId, product, 'yookassa', `yk:${payment.id}`);
  if (payment.payment_method?.saved && billing.product(product)?.plan) {
    const card = payment.payment_method.card;
    billing.setPaymentMethod(installId, { id: payment.payment_method.id, product, email, title: card ? `${card.card_type || 'Карта'} •${card.last4}` : 'СБП' });
  }
  return { status: 'succeeded', duplicate: result.duplicate };
}

export async function yookassaWebhook(body) {
  // A refund: the credits of that payment are taken back (checked with ЮKassa).
  if (String(body?.event || '').startsWith('refund.')) {
    const refund = await ykApi('GET', `refunds/${encodeURIComponent(String(body?.object?.id || ''))}`);
    if (refund.status === 'succeeded') return billing.revoke(`yk:${refund.payment_id}`, 'yookassa');
    return { status: refund.status };
  }
  const id = body?.object?.id;
  if (typeof id !== 'string' || !/^[0-9a-f-]{20,50}$/i.test(id)) throw new ApiError(400, 'Неверное уведомление.');
  return applyYookassa(id);
}

/** Autopay: a day before a plan ends, its saved card / СБП account is charged again (only when autopay is on). */
export async function renewPlans(now = Date.now()) {
  if (!yookassaReady()) return 0;
  let started = 0;
  for (const [installId, acc] of billing.allAccounts()) {
    const plan = acc.plan, pay = acc.autopay;
    if (!plan || !pay?.on || plan.source !== 'yookassa') continue;
    const until = Date.parse(plan.until);
    if (until - now > 86_400_000 || now - until > 3 * 86_400_000) continue;
    if (pay.lastTry && now - Date.parse(pay.lastTry) < 12 * 3_600_000) continue;
    const p = billing.product(pay.product);
    if (!p) continue;
    pay.lastTry = new Date(now).toISOString();
    billing.persist();
    try {
      const payment = await ykApi('POST', 'payments', {
        amount: { value: p.rub.toFixed(2), currency: 'RUB' }, capture: true, payment_method_id: pay.id,
        description: `${p.title}, продление, аккаунт ${acc.code}`.slice(0, 128), receipt: receipt(p, pay.email),
        metadata: { installId, product: p.id, email: pay.email },
      });
      if (payment.status === 'succeeded') billing.grant(installId, p.id, 'yookassa', `yk:${payment.id}`);
      started += 1;
    } catch (error) { console.warn('[pay] renew', acc.code, error.message); }
  }
  return started;
}

// ---------- App Store (StoreKit 2 signed transactions) ----------

const APPLE_ROOT_G3_SHA256 = '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';
const bundleId = () => process.env.APPLE_BUNDLE_ID || 'com.sochiart.markaryan';

/** Verifies a JWS signed by the App Store: the chain up to Apple Root CA G3 and the ES256 signature. Returns the payload. */
export function verifyAppleJWS(jws, { rootFingerprint = APPLE_ROOT_G3_SHA256 } = {}) {
  const parts = String(jws || '').split('.');
  if (parts.length !== 3) throw new ApiError(400, 'Неверная покупка.');
  const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
  const chain = (header.x5c || []).map((der) => new crypto.X509Certificate(Buffer.from(der, 'base64')));
  if (header.alg !== 'ES256' || chain.length < 3) throw new ApiError(400, 'Неверная подпись покупки.');
  const [leaf, intermediate, root] = chain;
  const now = Date.now();
  const valid = (c) => Date.parse(c.validFrom) <= now && now <= Date.parse(c.validTo);
  if (root.fingerprint256 !== rootFingerprint || !chain.every(valid)
    || !leaf.verify(intermediate.publicKey) || !intermediate.verify(root.publicKey)) throw new ApiError(400, 'Подпись покупки не от Apple.');
  const ok = crypto.verify('sha256', Buffer.from(`${parts[0]}.${parts[1]}`), { key: leaf.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(parts[2], 'base64url'));
  if (!ok) throw new ApiError(400, 'Подпись покупки не сходится.');
  return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
}

/** One App Store transaction → credits (and the plan until its expiry). Each renewal is a new transaction id. */
export function applyAppleTransaction(installId, tx) {
  if (tx.bundleId !== bundleId()) throw new ApiError(400, 'Покупка из другого приложения.');
  if (tx.revocationDate) return { status: 'revoked' };
  if (tx.appAccountToken && tx.appAccountToken.toLowerCase() !== String(installId).toLowerCase()) throw new ApiError(403, 'Покупка другого аккаунта.');
  if (tx.expiresDate && tx.expiresDate < Date.now()) return { status: 'expired' };
  const p = billing.product(tx.productId);
  if (!p) return { status: 'unknown-product' };
  const result = billing.grant(installId, p.id, 'appstore', `as:${tx.transactionId}`, { until: tx.expiresDate ? new Date(tx.expiresDate).toISOString() : undefined });
  return { status: 'ok', duplicate: result.duplicate };
}

/** The app sends the signed transactions after a purchase and at launch (renewals while the app was closed). */
export function appleSync(installId, body) {
  const list = (Array.isArray(body?.transactions) ? body.transactions : []).slice(0, 50);
  return { results: list.map((jws) => { try { return applyAppleTransaction(installId, verifyAppleJWS(jws)); } catch (error) { return { status: 'error', error: error.message }; } }) };
}

/** App Store Server Notifications V2: renewals arrive even when the app is never opened. */
export function appleNotification(body) {
  const payload = verifyAppleJWS(body?.signedPayload);
  const signed = payload?.data?.signedTransactionInfo;
  if (!signed) return { status: 'ignored' };
  const tx = verifyAppleJWS(signed);
  // Apple returned the money: the credits of that purchase are taken back.
  if (payload.notificationType === 'REFUND' || payload.notificationType === 'REVOKE') return billing.revoke(`as:${tx.transactionId}`, 'appstore');
  if (!tx.appAccountToken) return { status: 'no-account' };
  return applyAppleTransaction(tx.appAccountToken.toUpperCase(), tx);
}
