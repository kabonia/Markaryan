import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const { config } = await import('../src/config.js');
config.dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'billing-'));
process.env.BILLING_ENABLED = '1';
const billing = await import('../src/billing.js');
const payments = await import('../src/payments.js');
const ID = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

test('наценка: отдельные функции 230–250 %, пакеты 170–230 % (сайт и App Store 15 %)', () => {
  // Обычная себестоимость, ₽ (docs/audit/ECONOMICS-2026-11.md); 1 кредит ≈ 10 ₽ чистыми.
  const cost = { chat: 6, vision: 12, json: 27, imageEdit: 12, image: 12, smeta: 90, smetaPage: 40, houseScan: 26, priceEstimate10: 3 };
  for (const [kind, rub] of Object.entries(cost)) {
    const markup = (billing.PRICES[kind] * 10) / rub - 1;
    assert.ok(markup >= 2.3 && markup <= 2.5, `${kind}: ${Math.round(markup * 100)} %`);
  }
  const unit = { ...cost, material: 2.5, helper: 0.05, priceEstimateItem: 0.3 };
  for (const pack of billing.PACKS) {
    const packCost = Object.entries(pack.grants).reduce((sum, [kind, n]) => sum + unit[kind] * n, 0);
    const site = (pack.rub * 0.905) / packCost - 1, apple = (pack.usd * 82.13 * 0.85 * 0.94) / packCost - 1;
    for (const m of [site, apple]) assert.ok(m >= 1.7 && m <= 2.3, `${pack.id}: ${Math.round(site * 100)} % / ${Math.round(apple * 100)} %`);
  }
});

test('estimates from documents are paid per sheet and per 6 000 characters; 100 sheets max', () => {
  assert.equal(billing.price('smeta', { pages: 2 }), 30);
  assert.equal(billing.price('smeta', { pages: 100 }), 30 + 98 * 14);
  assert.equal(billing.price('smeta', { pages: 500 }), 30 + 98 * 14);
  assert.equal(billing.price('smeta', { textChars: 60_000 }), 30 + 8 * 14);
  assert.equal(billing.price('priceEstimate', { items: 20 }), 2);
  assert.equal(billing.price('priceEstimate', { items: 21 }), 3);
  assert.equal(billing.price('priceEstimate', { items: 0 }), 1);
});

test('credits are taken before the work; a short balance stops it with 402; a failure gives them back', () => {
  billing.reset();
  const id = ID(1);
  billing.account(id, '1.1.1.1');
  assert.equal(billing.account(id).credits, 10);
  assert.equal(billing.charge(id, 'json'), 9);
  assert.throws(() => billing.charge(id, 'json'), (e) => e.status === 402 && /Недостаточно кредитов/.test(e.message));
  billing.refund(id, 'json', 9);
  assert.equal(billing.account(id).credits, 10);
});

test('the helper is free 20 times a day, then 1 credit', () => {
  billing.reset();
  const id = ID(2);
  billing.account(id, '2.2.2.2');
  for (let i = 0; i < 20; i += 1) assert.equal(billing.charge(id, 'helper'), 0);
  assert.equal(billing.charge(id, 'helper'), 1);
  assert.equal(billing.account(id).credits, 9);
});

test('reinstalling is not a credit farm: welcome credits for 3 accounts per IP in 30 days', () => {
  billing.reset();
  const gifts = [1, 2, 3, 4, 5].map((n) => billing.account(ID(100 + n), '9.9.9.9').credits);
  assert.deepEqual(gifts, [10, 10, 10, 0, 0]);
});

test('a purchase counts once (repeated webhook / sync); a refund takes the credits back even below zero', () => {
  billing.reset();
  const id = ID(3);
  billing.account(id, '3.3.3.3');
  assert.equal(billing.grant(id, 'credits_100', 'yookassa', 'yk:1').duplicate, false);
  assert.equal(billing.grant(id, 'credits_100', 'yookassa', 'yk:1').duplicate, true);
  assert.equal(billing.account(id).credits, 110);
  assert.throws(() => billing.charge(id, 'smeta', { pages: 100 }), (e) => e.status === 402); // 1402 > 110
});

test('refund below zero blocks further use', () => {
  billing.reset();
  const id = ID(4);
  billing.account(id, '4.4.4.4');
  billing.grant(id, 'credits_100', 'yookassa', 'yk:2');
  // 10 приветственных + 100 − смета на 7 листов (30 + 5 × 14 = 100) = 10.
  billing.charge(id, 'smeta', { pages: 7 });
  assert.equal(billing.account(id).credits, 10);
  billing.revoke('yk:2', 'yookassa');
  assert.equal(billing.account(id).credits, -90);
  assert.throws(() => billing.charge(id, 'material'), (e) => e.status === 402);
});

test('plans: credits at once, the plan until its end; yearly plans top up monthly', () => {
  billing.reset();
  const id = ID(5);
  billing.account(id, '5.5.5.5');
  billing.grant(id, 'pro_year', 'yookassa', 'yk:3');
  const acc = billing.account(id);
  assert.equal(acc.credits, 90);
  assert.equal(acc.plan.id, 'pro');
  acc.plan.monthly.next = new Date(Date.now() - 1000).toISOString();
  billing.monthlyTopUp(id);
  assert.equal(billing.account(id).credits, 170);
});

test('ЮKassa: payment by account number, credits only after ЮKassa itself confirms the payment', async () => {
  billing.reset();
  process.env.YOOKASSA_SHOP_ID = '1'; process.env.YOOKASSA_SECRET_KEY = 'k';
  const id = ID(6);
  const code = billing.account(id, '6.6.6.6').code;
  const calls = [];
  payments.setFetch(async (url, options) => {
    calls.push({ url, body: options.body && JSON.parse(options.body) });
    if (url.endsWith('/payments')) return new Response(JSON.stringify({ id: '2f1e4c5d-000f-5000-9000-1a2b3c4d5e6f', confirmation: { confirmation_url: 'https://yoomoney.ru/pay' } }), { status: 200 });
    return new Response(JSON.stringify({ id: '2f1e4c5d-000f-5000-9000-1a2b3c4d5e6f', status: 'succeeded', paid: true, metadata: { installId: id, product: 'credits_500' } }), { status: 200 });
  });
  const created = await payments.createYookassa({ code, email: 'a@b.ru', product: 'credits_500', method: 'sbp', origin: 'https://x' });
  assert.equal(created.url, 'https://yoomoney.ru/pay');
  assert.equal(calls[0].body.amount.value, '5490.00');
  assert.equal(calls[0].body.payment_method_data.type, 'sbp');
  assert.equal(calls[0].body.receipt.customer.email, 'a@b.ru');
  await payments.yookassaWebhook({ event: 'payment.succeeded', object: { id: '2f1e4c5d-000f-5000-9000-1a2b3c4d5e6f', status: 'succeeded', metadata: { installId: id, product: 'credits_1500' } } });
  await payments.yookassaWebhook({ event: 'payment.succeeded', object: { id: '2f1e4c5d-000f-5000-9000-1a2b3c4d5e6f' } });
  assert.equal(billing.account(id).credits, 510); // 10 welcome + 500 — the forged body (1500) is ignored, the repeat is not paid twice
  await assert.rejects(payments.createYookassa({ code: 'SP-0000-0000', email: 'a@b.ru', product: 'credits_100' }), (e) => e.status === 404);
  payments.setFetch();
});

test('App Store: only transactions signed by the Apple chain count; forged ones are rejected', () => {
  billing.reset();
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ca-'));
  const sh = (args) => execFileSync('openssl', args, { cwd: dir, stdio: 'pipe' });
  const ec = (name) => sh(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', `${name}.key`]);
  ec('root'); ec('mid'); ec('leaf');
  sh(['req', '-new', '-x509', '-key', 'root.key', '-subj', '/CN=Root', '-days', '30', '-out', 'root.pem']);
  fs.writeFileSync(path.join(dir, 'ca.ext'), 'basicConstraints=critical,CA:TRUE\n');
  sh(['req', '-new', '-key', 'mid.key', '-subj', '/CN=Mid', '-out', 'mid.csr']);
  sh(['x509', '-req', '-in', 'mid.csr', '-CA', 'root.pem', '-CAkey', 'root.key', '-CAcreateserial', '-days', '30', '-extfile', 'ca.ext', '-out', 'mid.pem']);
  sh(['req', '-new', '-key', 'leaf.key', '-subj', '/CN=Leaf', '-out', 'leaf.csr']);
  sh(['x509', '-req', '-in', 'leaf.csr', '-CA', 'mid.pem', '-CAkey', 'mid.key', '-CAcreateserial', '-days', '30', '-out', 'leaf.pem']);
  const der = (name) => new crypto.X509Certificate(fs.readFileSync(path.join(dir, `${name}.pem`))).raw.toString('base64');
  const root = new crypto.X509Certificate(fs.readFileSync(path.join(dir, 'root.pem')));
  const sign = (payload, key = 'leaf') => {
    const head = Buffer.from(JSON.stringify({ alg: 'ES256', x5c: [der('leaf'), der('mid'), der('root')] })).toString('base64url');
    const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key: fs.readFileSync(path.join(dir, `${key}.key`)), dsaEncoding: 'ieee-p1363' }).toString('base64url');
    return `${head}.${body}.${sig}`;
  };
  const id = ID(7);
  const tx = { bundleId: 'com.sochiart.markaryan', productId: 'smetapro.credits.100', transactionId: '2000001', appAccountToken: id.toLowerCase() };
  const payload = payments.verifyAppleJWS(sign(tx), { rootFingerprint: root.fingerprint256 });
  assert.equal(payload.transactionId, '2000001');
  assert.throws(() => payments.verifyAppleJWS(sign(tx)), /не от Apple/); // the real Apple root is required by default
  assert.throws(() => payments.verifyAppleJWS(sign(tx, 'mid'), { rootFingerprint: root.fingerprint256 }), /не сходится/);
  billing.account(id, '7.7.7.7');
  assert.equal(payments.applyAppleTransaction(id, payload).status, 'ok');
  assert.equal(payments.applyAppleTransaction(id, payload).duplicate, true);
  assert.equal(billing.account(id).credits, 110);
  assert.throws(() => payments.applyAppleTransaction(ID(8), payload), (e) => e.status === 403); // another person's purchase
});

test('пакеты функций: сначала пакет, потом кредиты; возврат единицы при сбое; остаток листов сметы — кредитами', () => {
  billing.reset();
  const id = ID(9);
  billing.account(id, '9.9.9.9');
  billing.grant(id, 'pack_room', 'yookassa', 'yk:pack1');
  const acc = billing.account(id);
  assert.equal(acc.packs.json, 3);
  assert.equal(billing.charge(id, 'json'), 0);
  assert.equal(acc.packs.json, 2);
  assert.equal(acc.credits, 10); // кредиты не тронуты
  billing.refund(id, 'json', 0);
  assert.equal(acc.packs.json, 3); // ИИ не справился — единица вернулась
  assert.equal(billing.charge(id, 'priceEstimate', { items: 35 }), 1); // 30 из пакета + 5 строк = 1 кредит
  assert.equal(acc.packs.priceEstimateItem, 0);
  billing.grant(id, 'pack_smeta', 'yookassa', 'yk:pack2');
  // 12 листов: 2 входят в смету, 8 — листы пакета, 2 сверх — 28 кредитов, а на балансе 9 → отказ, пакет не тронут.
  assert.throws(() => billing.charge(id, 'smeta', { pages: 12 }), (e) => e.status === 402);
  assert.equal(billing.account(id).packs.smeta, 1);
  assert.equal(billing.charge(id, 'smeta', { pages: 10 }), 0);
  assert.equal(billing.account(id).packs.smeta, 0);
});
