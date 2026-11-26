import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const { config } = await import('../src/config.js');
config.dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'support-'));
process.env.BILLING_ENABLED = '1';
process.env.TELEGRAM_BOT_TOKEN = 'test-token';
process.env.TELEGRAM_CHAT_ID = '42';
process.env.SUPPORT_POLL = 'off';
const billing = await import('../src/billing.js');
const support = await import('../src/support.js');
const ID = '00000000-0000-4000-8000-000000000077';

const sent = [];
let nextMessageId = 500;
globalThis.fetch = async (url, options) => {
  const body = options?.body instanceof FormData ? Object.fromEntries([...options.body.entries()].filter(([k]) => k !== 'photo')) : JSON.parse(options.body);
  sent.push({ url: String(url), body });
  return new Response(JSON.stringify({ ok: true, result: { message_id: ++nextMessageId } }), { status: 200 });
};

test('обращение уходит менеджеру с аккаунтом и балансом, ответ менеджера приходит в приложение', async () => {
  billing.reset(); support.reset();
  billing.account(ID, '7.7.7.7');
  billing.charge(ID, 'json');
  const ticket = await support.create(ID, { topic: 'paid', feature: 'Дизайн‑проект комнаты', text: 'Оплатил дизайн, а картинки нет', appVersion: '1.4' });
  assert.equal(ticket.topicTitle, 'Оплатил, но не получил результат');
  const first = sent.at(-1).body.text;
  assert.match(first, /Обращение №1001/);
  assert.match(first, new RegExp(billing.codeFor(ID)));
  assert.match(first, /баланс 1 кр\./);
  assert.match(first, /charge json -?9|json/);

  // Менеджер отвечает ответом на сообщение бота.
  assert.equal(await support.managerMessage({ message_id: 900, chat: { id: 42 }, reply_to_message: { message_id: 501 }, text: 'Проверим за 10 минут' }), true);
  let [mine] = support.list(ID).tickets;
  assert.equal(mine.status, 'answered');
  assert.equal(mine.messages.at(-1).from, 'manager');
  assert.equal(mine.messages.at(-1).text, 'Проверим за 10 минут');

  // Компенсация и закрытие.
  await support.managerMessage({ message_id: 901, chat: { id: 42 }, reply_to_message: { message_id: 900 }, text: '/кредиты 9' });
  assert.equal(billing.account(ID).credits, 10);
  await support.managerMessage({ message_id: 902, chat: { id: 42 }, reply_to_message: { message_id: 501 }, text: '/закрыть' });
  [mine] = support.list(ID).tickets;
  assert.equal(mine.status, 'closed');

  // Человек пишет снова — обращение открывается.
  mine = await support.reply(ID, mine.id, { text: 'Картинка пришла, спасибо' });
  assert.equal(mine.status, 'open');
  assert.match(sent.at(-1).body.text, /№1001/);
});

test('чужое обращение и чужой чат не принимаются; лимит 5 обращений в сутки', async () => {
  support.reset();
  const t = await support.create(ID, { topic: 'broken', text: 'Не открывается обмер' });
  await assert.rejects(support.reply('00000000-0000-4000-8000-000000000078', t.id, { text: 'чужое' }), (e) => e.status === 404);
  assert.equal(await support.managerMessage({ message_id: 1, chat: { id: 13 }, reply_to_message: { message_id: nextMessageId }, text: 'не тот чат' }), false);
  for (let i = 0; i < 4; i += 1) await support.create(ID, { topic: 'other', text: `вопрос ${i}` });
  await assert.rejects(support.create(ID, { topic: 'other', text: 'шестой' }), (e) => e.status === 429);
  await assert.rejects(support.create(ID, { text: '' }), (e) => e.status === 400);
});
