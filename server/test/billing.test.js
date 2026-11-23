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

test('every price is at least 3× the worst AI cost (no usage can make a loss)', () => {
  const worstRub = { helper: 0.3, chat: 36, material: 6, priceEstimateItem: 2.5, imageEdit: 25, image: 25, vision: 30, json: 60, smeta: 600, smetaPage: 75 };
  const cheapestCreditRub = Math.min(...billing.PRODUCTS.map((p) => p.rub / p.credits)); // the biggest pack
  for (const [kind, worst] of Object.entries(worstRub)) assert.ok(billing.PRICES[kind] * cheapestCreditRub >= worst * 3, kind);
});

test('estimates from documents are paid per sheet and per 6 000 characters; 100 sheets max', () => {
  assert.equal(billing.price('smeta', { pages: 2 }), 200);
  assert.equal(billing.price('smeta', { pages: 100 }), 200 + 98 * 40);
  assert.equal(billing.price('smeta', { pages: 500 }), 200 + 98 * 40);
  assert.equal(billing.price('smeta', { textChars: 60_000 }), 200 + 8 * 40);
  assert.equal(billing.price('priceEstimate', { items: 20 }), 20);
});

test('credits are taken before the work; a short balance stops it with 402; a failure gives them back', () => {
  billing.reset();
  const id = ID(1);
  billing.account(id, '1.1.1.1');
  assert.equal(billing.account(id).credits, 10);
  assert.equal(billing.charge(id, 'imageEdit'), 8);
  assert.throws(() => billing.charge(id, 'imageEdit'), (e) => e.status === 402 && /Недостаточно кредитов/.test(e.message));
  billing.refund(id, 'imageEdit', 8);
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
  assert.throws(() => billing.charge(id, 'smeta', { pages: 2 }), (e) => e.status === 402); // 200 > 110
});

test('refund below zero blocks further use', () => {
  billing.reset();
  const id = ID(4);
  billing.account(id, '4.4.4.4');
  billing.grant(id, 'credits_100', 'yookassa', 'yk:2');
  billing.charge(id, 'json'); billing.charge(id, 'json'); billing.charge(id, 'json'); billing.charge(id, 'json'); billing.charge(id, 'json');
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
