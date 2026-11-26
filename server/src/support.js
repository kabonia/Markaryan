// Поддержка: человек пишет из приложения → менеджер получает в Telegram (бот, чат TELEGRAM_CHAT_ID или SUPPORT_CHAT_ID)
// вместе с номером аккаунта, балансом, пакетами и последними списаниями → отвечает ответом (reply) на сообщение бота →
// ответ появляется в приложении. Команды менеджера в ответе на обращение:
//   /кредиты 25 — начислить кредиты (компенсация), /закрыть — закрыть обращение.
// Хранится в DATA_DIR/support.json. Лимиты: 5 новых обращений и 40 сообщений в сутки на установку.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { config } from './config.js';
import { ApiError, request } from './util.js';
import * as billing from './billing.js';

export const TOPICS = {
  broken: 'Не работает функция',
  paid: 'Оплатил, но не получил результат',
  howto: 'Не разобрался, как пользоваться',
  payment: 'Оплата и возврат',
  idea: 'Предложение',
  other: 'Другое',
};
const MAX_TEXT = 2000;
const MAX_PHOTO = 1_500_000;

let state = null;
const file = () => path.join(config.dataDir, 'support.json');
const clean = (value, max) => String(value ?? '').replace(/[\u0000-\u0008\u000b-\u001f]/g, ' ').trim().slice(0, max);
const chatId = () => process.env.SUPPORT_CHAT_ID || process.env.TELEGRAM_CHAT_ID || '';
const token = () => process.env.TELEGRAM_BOT_TOKEN || '';

function load() {
  if (state) return state;
  try { state = JSON.parse(fs.readFileSync(file(), 'utf8')); } catch { state = {}; }
  state.tickets ||= {}; state.byMessage ||= {}; state.offset ||= 0; state.seq ||= 1000;
  return state;
}
function save() {
  fs.mkdirSync(config.dataDir, { recursive: true });
  fs.writeFileSync(`${file()}.tmp`, JSON.stringify(state));
  fs.renameSync(`${file()}.tmp`, file());
}
/** For tests. */
export function reset() { state = { tickets: {}, byMessage: {}, offset: 0, seq: 1000 }; }

function countToday(installId, pick) {
  const day = Date.now() - 86_400_000;
  return Object.values(load().tickets).filter((t) => t.installId === installId).flatMap(pick).filter((at) => Date.parse(at) > day).length;
}

/** Что видит приложение: без installId и служебных полей. */
function view(t) {
  return {
    id: t.id, number: t.number, topic: t.topic, topicTitle: TOPICS[t.topic] || TOPICS.other, feature: t.feature || null,
    status: t.status, createdAt: t.createdAt, updatedAt: t.updatedAt,
    messages: t.messages.map(({ from, text, at, photo, credits }) => ({ from, text, at, photo: Boolean(photo), credits: credits || null })),
  };
}

export function list(installId) {
  return { tickets: Object.values(load().tickets).filter((t) => t.installId === installId)
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)).slice(0, 30).map(view), topics: TOPICS };
}

function decodePhoto(value) {
  if (!value) return null;
  const buffer = Buffer.from(String(value), 'base64');
  if (buffer.length > MAX_PHOTO) throw new ApiError(413, 'Снимок слишком большой — до 1,5 МБ.');
  if (buffer[0] !== 0xff || buffer[1] !== 0xd8) throw new ApiError(400, 'Снимок должен быть JPEG.');
  return buffer;
}

export async function create(installId, body) {
  const text = clean(body?.text, MAX_TEXT);
  if (text.length < 3) throw new ApiError(400, 'Опишите, что случилось.');
  if (countToday(installId, (t) => [t.createdAt]) >= 5) throw new ApiError(429, 'Сегодня уже 5 обращений — ответим на них, а завтра можно написать снова.');
  const photo = decodePhoto(body?.photo);
  const s = load();
  const now = new Date().toISOString();
  const ticket = {
    id: crypto.randomUUID(), number: ++s.seq, installId, topic: TOPICS[body?.topic] ? body.topic : 'other',
    feature: clean(body?.feature, 80) || null, screen: clean(body?.screen, 80) || null, contact: clean(body?.contact, 120) || null,
    appVersion: clean(body?.appVersion, 30), device: clean(body?.device, 40), language: clean(body?.language, 10),
    status: 'open', createdAt: now, updatedAt: now, messages: [{ from: 'user', text, at: now, photo: Boolean(photo) }],
  };
  s.tickets[ticket.id] = ticket;
  save();
  await forward(ticket, header(ticket) + `\n\n${text}`, photo);
  return view(ticket);
}

export async function reply(installId, id, body) {
  const t = load().tickets[id];
  if (!t || t.installId !== installId) throw new ApiError(404, 'Обращение не найдено.');
  const text = clean(body?.text, MAX_TEXT);
  if (!text) throw new ApiError(400, 'Пустое сообщение.');
  if (countToday(installId, (x) => x.messages.filter((m) => m.from === 'user').map((m) => m.at)) >= 40) throw new ApiError(429, 'Слишком много сообщений за сутки.');
  const photo = decodePhoto(body?.photo);
  const now = new Date().toISOString();
  t.messages.push({ from: 'user', text, at: now, photo: Boolean(photo) });
  if (t.messages.length > 200) t.messages.splice(1, t.messages.length - 200);
  t.status = 'open'; t.updatedAt = now;
  save();
  await forward(t, `💬 Обращение №${t.number} · ${billing.codeFor(t.installId)}\n\n${text}`, photo);
  return view(t);
}

function header(t) {
  const acc = billing.account(t.installId);
  const packs = Object.entries(acc.packs || {}).filter(([, n]) => n > 0).map(([k, n]) => `${k}×${n}`).join(', ');
  const recent = billing.history(t.installId, 5).map((e) => `  ${e.at.slice(5, 16).replace('T', ' ')} ${e.type}${e.kind ? ' ' + e.kind : ''}${e.credits ? ' ' + e.credits : ''}`);
  return [
    `🆘 Обращение №${t.number}: ${TOPICS[t.topic]}`,
    `Аккаунт: ${acc.code} · баланс ${acc.credits} кр.${packs ? ` · пакеты: ${packs}` : ''}${acc.plan?.until ? ` · тариф до ${acc.plan.until.slice(0, 10)}` : ''}`,
    t.feature ? `Функция: ${t.feature}` : '', t.screen ? `Экран: ${t.screen}` : '',
    `Версия ${t.appVersion || '—'} · ${t.device || 'iPhone'} · язык ${t.language || 'ru'}`,
    t.contact ? `Контакт: ${t.contact}` : '',
    recent.length ? `Последние операции:\n${recent.join('\n')}` : '',
    '↩️ Ответьте на это сообщение — ответ придёт в приложение. /кредиты 25 — начислить, /закрыть — закрыть.',
  ].filter(Boolean).join('\n');
}

async function forward(t, text, photo) {
  if (!token() || !chatId()) { console.warn('[support] Telegram не настроен — обращение только сохранено', t.number); return; }
  try {
    let response;
    if (photo) {
      const form = new FormData();
      form.append('chat_id', chatId());
      form.append('caption', text.slice(0, 1000));
      form.append('photo', new Blob([photo], { type: 'image/jpeg' }), 'screen.jpg');
      response = await request(`https://api.telegram.org/bot${token()}/sendPhoto`, { method: 'POST', body: form }, 30_000);
      if (text.length > 1000) await send(text.slice(1000));
    } else {
      response = await send(text);
    }
    const json = await response.json().catch(() => ({}));
    if (json?.result?.message_id) { load().byMessage[json.result.message_id] = t.id; save(); }
  } catch (error) { console.warn('[support] Telegram:', error.message); }
}

function send(text) {
  return request(`https://api.telegram.org/bot${token()}/sendMessage`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId(), text: text.slice(0, 4000), disable_web_page_preview: true }),
  }, 15_000);
}

/** Сообщение менеджера из Telegram: ответ на сообщение бота → в обращение. Возвращает true, если обработано. */
export async function managerMessage(message) {
  if (!message || String(message.chat?.id) !== String(chatId())) return false;
  const repliedTo = message.reply_to_message?.message_id;
  const id = repliedTo && load().byMessage[repliedTo];
  const t = id && state.tickets[id];
  if (!t) return false;
  const text = clean(message.text || message.caption, MAX_TEXT);
  if (!text) return false;
  const now = new Date().toISOString();
  const credits = /^\/(кредиты|credits)\s+(\d{1,4})/i.exec(text);
  if (credits) {
    const n = Number(credits[2]);
    billing.compensate(t.installId, n, `support-${t.number}`);
    t.messages.push({ from: 'manager', text: `Начислили ${n} кредитов — извините за неудобства.`, at: now, credits: n });
    await send(`✅ №${t.number}: начислено ${n} кр., баланс ${billing.account(t.installId).credits}`);
  } else if (/^\/(закрыть|close)/i.test(text)) {
    t.status = 'closed';
    t.messages.push({ from: 'manager', text: 'Обращение закрыто. Если вопрос остался — просто напишите сюда.', at: now });
    await send(`☑️ №${t.number} закрыто`);
  } else {
    t.messages.push({ from: 'manager', text, at: now });
    t.status = 'answered';
  }
  t.updatedAt = now;
  load().byMessage[message.message_id] = t.id; // ответ на ответ менеджера тоже попадёт в это обращение
  save();
  return true;
}

/** Получение ответов менеджера: long polling getUpdates (вебхука у бота нет, бот только у этого сервера). */
export function startPolling() {
  if (!token() || !chatId() || process.env.SUPPORT_POLL === 'off') return;
  let stopped = false;
  const loop = async () => {
    while (!stopped) {
      try {
        const s = load();
        const response = await request(`https://api.telegram.org/bot${token()}/getUpdates?timeout=25&offset=${s.offset}&allowed_updates=%5B%22message%22%5D`, {}, 35_000);
        const json = await response.json();
        if (!json.ok) { await new Promise((r) => setTimeout(r, 30_000)); continue; }
        for (const update of json.result || []) {
          s.offset = update.update_id + 1;
          await managerMessage(update.message).catch((error) => console.warn('[support]', error.message));
        }
        if (json.result?.length) save();
      } catch { await new Promise((r) => setTimeout(r, 15_000)); }
    }
  };
  loop();
  return () => { stopped = true; };
}
