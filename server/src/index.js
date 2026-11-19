import crypto from 'node:crypto';
// АртСтрой AI server: the app talks only to this server; all AI keys stay here.
import http from 'node:http';
import { config } from './config.js';
import { ApiError } from './util.js';
import { consume, refund, remaining } from './limits.js';
import * as ai from './ai.js';
import { editEngines, fluxEdit, gptEdit } from './providers/images.js';
import * as hh from './hh.js';
import * as avito from './avito.js';

const INSTALL_ID = /^[A-Za-z0-9-]{16,64}$/;

function send(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(data), 'Cache-Control': 'no-store' });
  res.end(data);
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > config.maxBodyBytes) throw new ApiError(413, 'Слишком большой запрос (фото больше допустимого).');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); } catch { throw new ApiError(400, 'Неверный формат запроса.'); }
}

/** Validates the app's messages: [{role, text, image?(base64 jpeg)}]. */
function cleanMessages(list) {
  if (!Array.isArray(list) || list.length === 0 || list.length > 40) throw new ApiError(400, 'Нет сообщений.');
  return list.map((m) => ({
    role: m?.role === 'assistant' ? 'assistant' : 'user',
    text: String(m?.text ?? '').slice(0, 60_000),
    image: typeof m?.image === 'string' && m.image.length > 100 ? m.image : undefined,
  }));
}

function clientIP(req) {
  return String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
}

async function handle(req, res) {
  const url = new URL(req.url, 'http://local');
  if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true });

  if (url.pathname.startsWith('/v1/auth/hh/') || url.pathname.startsWith('/v1/hh/')) return handleHH(req, res, url);
  if (req.method === 'GET' && url.pathname === '/v1/market/vacancies') return handleMarketSearch(req, res, url);
  if (req.method === 'GET' && (url.pathname === '/v1/market/resumes' || url.pathname === '/v1/market/owner')) return handleResumeSearch(req, res, url);
  if (url.pathname.startsWith('/v1/auth/avito/') || url.pathname.startsWith('/v1/avito/')) return handleMarket(req, res, url, avito, 'avito', 'Avito');
  if (!url.pathname.startsWith('/v1/ai/')) return send(res, 404, { error: 'Не найдено' });
  if (config.appToken && req.headers['x-app-token'] !== config.appToken) return send(res, 401, { error: 'Нет доступа.' });
  const installId = String(req.headers['x-install-id'] || '');
  if (!INSTALL_ID.test(installId)) return send(res, 400, { error: 'Обновите приложение.' });
  const ip = clientIP(req);

  if (req.method === 'GET' && url.pathname === '/v1/ai/capabilities') {
    const providers = ai.activeProviders();
    return send(res, 200, { chat: providers.length > 0, vision: providers.length > 0, imageGenerate: ai.canGenerateImages(), imageEdit: editEngines(), providers, remaining: remaining(installId) });
  }
  if (req.method !== 'POST') return send(res, 405, { error: 'Метод не поддерживается.' });
  const body = await readBody(req);

  if (url.pathname === '/v1/ai/chat') {
    const messages = cleanMessages(body.messages);
    const kind = messages.some((m) => m.image) ? 'vision' : 'chat';
    consume(kind, installId, ip);
    const params = { system: String(body.system || '').slice(0, 40_000), messages, maxTokens: Number(body.maxTokens) || 2000 };
    if (!body.stream) {
      try { return send(res, 200, { text: await ai.chat(params) }); } catch (error) { refund(kind, installId, ip); throw error; }
    }
    // Server‑sent events: data: {"delta":"…"} … data: {"done":true}
    res.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-store', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
    const heartbeat = setInterval(() => res.write(': ping\n\n'), 15_000);
    let started = false;
    try {
      await ai.chat({ ...params, onDelta: (delta) => { started = true; res.write(`data: ${JSON.stringify({ delta })}\n\n`); } });
      res.write(`data: ${JSON.stringify({ done: true })}\n\n`);
    } catch (error) {
      if (!started) refund(kind, installId, ip);
      res.write(`data: ${JSON.stringify({ error: error instanceof ApiError ? error.message : 'Ошибка ИИ. Попробуйте ещё раз.' })}\n\n`);
    } finally {
      clearInterval(heartbeat);
      res.end();
    }
    return;
  }

  if (url.pathname === '/v1/ai/json') {
    const messages = cleanMessages(body.messages);
    const kind = messages.some((m) => m.image) ? 'vision' : 'json';
    if (!body.schema || typeof body.schema !== 'object') throw new ApiError(400, 'Нет схемы ответа.');
    consume(kind, installId, ip);
    try {
      const result = await ai.json({ system: String(body.system || ''), messages, schema: body.schema, name: String(body.name || 'result').replace(/[^A-Za-z0-9_]/g, '_'), description: String(body.description || ''), maxTokens: Number(body.maxTokens) || 8000 });
      return send(res, 200, { json: result });
    } catch (error) { refund(kind, installId, ip); throw error; }
  }

  if (url.pathname === '/v1/ai/image-edit') {
    const engine = body.engine === 'gpt' ? 'gpt' : 'flux';
    if (!editEngines().includes(engine)) throw new ApiError(400, 'Этот генератор не подключён на сервере.');
    if (typeof body.image !== 'string' || body.image.length < 1000) throw new ApiError(400, 'Нет изображения.');
    consume('imageEdit', installId, ip);
    try {
      const image = engine === 'gpt' ? await gptEdit({ image: body.image, prompt: String(body.prompt || ''), size: body.size }) : await fluxEdit({ image: body.image, prompt: String(body.prompt || '') });
      return send(res, 200, { image, engine });
    } catch (error) { refund('imageEdit', installId, ip); throw error; }
  }

  if (url.pathname === '/v1/ai/image') {
    consume('image', installId, ip);
    try { return send(res, 200, { image: await ai.generateImage({ prompt: String(body.prompt || '').slice(0, 3000) }) }); }
    catch (error) { refund('image', installId, ip); throw error; }
  }

  return send(res, 404, { error: 'Не найдено' });
}

function page(res, status, title, text) {
  const html = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>`
    + `<body style="font-family:-apple-system,system-ui,sans-serif;max-width:560px;margin:15vh auto;padding:0 20px;color:#222">`
    + `<h2>${title}</h2><p style="font-size:17px;line-height:1.5">${text}</p></body>`;
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(html);
}

async function handleHH(req, res, url) {
  const parts = url.pathname.split('/').filter(Boolean); // v1, hh, ...
  // Owner connects the employer account: open /v1/auth/hh/start?key=ADMIN_KEY in a browser.
  if (req.method === 'GET' && url.pathname === '/v1/auth/hh/start') {
    res.writeHead(302, { Location: hh.startURL(url.searchParams.get('key')) });
    return res.end();
  }
  if (req.method === 'GET' && url.pathname === '/v1/auth/hh/callback') {
    if (url.searchParams.get('error')) return page(res, 400, 'Подключение отменено', 'hh.ru не дал доступ. Откройте ссылку подключения ещё раз.');
    try {
      const result = await hh.finishOAuth(url.searchParams.get('code') || '', url.searchParams.get('state') || '');
      return page(res, 200, 'hh.ru подключён ✓', `Аккаунт работодателя «${result.employer}» подключён к приложению АртСтрой. Новые заявки будут публиковаться на hh.ru, отклики и чат — в приложении. Это окно можно закрыть.`);
    } catch (error) {
      return page(res, error.status || 500, 'Не получилось', error.message || 'Ошибка подключения.');
    }
  }
  if (req.method === 'POST' && parts[2] === 'webhook' && parts[3]) {
    const event = await readBody(req).catch(() => ({}));
    const result = hh.webhook(parts[3], event);
    return send(res, result.duplicate ? 409 : 200, { ok: true });
  }
  if (req.method === 'GET' && url.pathname === '/v1/hh/status') return send(res, 200, await hh.status(url.searchParams.get('key')));

  // App requests
  if (config.appToken && req.headers['x-app-token'] !== config.appToken) return send(res, 401, { error: 'Нет доступа.' });
  const installId = String(req.headers['x-install-id'] || '');
  if (!INSTALL_ID.test(installId)) return send(res, 400, { error: 'Обновите приложение.' });
  const orderToken = String(req.headers['x-hh-order-token'] || '');

  if (req.method === 'GET' && url.pathname === '/v1/hh/enabled') return send(res, 200, { enabled: hh.hhEnabled() });
  if (req.method === 'POST' && url.pathname === '/v1/hh/vacancies') {
    const body = await readBody(req);
    return send(res, 200, await hh.publishOrder(installId, {
      orderId: body.orderId, category: String(body.category || '').slice(0, 100), city: String(body.city || '').slice(0, 100),
      details: String(body.details || '').slice(0, 4000), budget: String(body.budget || '').slice(0, 100),
    }));
  }
  // /v1/hh/orders/{orderId}/responses  and  /v1/hh/orders/{orderId}/chats/{chatId}/messages
  if (parts[2] === 'orders' && parts[3]) {
    const orderId = decodeURIComponent(parts[3]);
    if (req.method === 'GET' && parts[4] === 'responses') return send(res, 200, await hh.responses(orderId, orderToken));
    if (parts[4] === 'chats' && parts[5] && parts[6] === 'messages') {
      if (req.method === 'GET') return send(res, 200, await hh.messages(orderId, orderToken, parts[5]));
      if (req.method === 'POST') { const body = await readBody(req); return send(res, 200, await hh.sendMessage(orderId, orderToken, parts[5], body.text)); }
    }
  }
  return send(res, 404, { error: 'Не найдено' });
}

const searchCache = new Map();
/** Vacancies of other employers on hh.ru and Avito (construction, the chosen city) — one merged list for the app. */
async function handleMarketSearch(req, res, url) {
  if (config.appToken && req.headers['x-app-token'] !== config.appToken) return send(res, 401, { error: 'Нет доступа.' });
  const installId = String(req.headers['x-install-id'] || '');
  if (!INSTALL_ID.test(installId)) return send(res, 400, { error: 'Обновите приложение.' });
  const text = String(url.searchParams.get('text') || '').slice(0, 100);
  const city = String(url.searchParams.get('city') || 'Сочи').slice(0, 60);
  const board = url.searchParams.get('board') || 'all';
  const page = Math.max(0, Math.min(10, Number.parseInt(url.searchParams.get('page') || '0', 10) || 0));
  const key = `${board}|${text}|${city}|${page}`;
  const hit = searchCache.get(key);
  if (hit && Date.now() - hit.at < 10 * 60_000) return send(res, 200, hit.value);
  consume('search', installId, clientIP(req));
  const [fromHH, fromAvito] = await Promise.all([
    board === 'avito' ? [] : hh.searchVacancies({ text, city, page }).catch((e) => { console.warn('[market] hh:', e.message); return null; }),
    board === 'hh' || page > 0 ? [] : avito.searchVacancies({ text, city }).catch((e) => { console.warn('[market] avito:', e.message); return null; }),
  ]);
  const items = [];
  const a = fromHH || [], b = fromAvito || [];
  for (let i = 0; i < Math.max(a.length, b.length); i += 1) { if (a[i]) items.push(a[i]); if (b[i]) items.push(b[i]); }
  const value = { items, sources: { hh: fromHH !== null, avito: fromAvito !== null } };
  searchCache.set(key, { at: Date.now(), value });
  if (searchCache.size > 300) searchCache.delete(searchCache.keys().next().value);
  return send(res, 200, value);
}

/** Resume search with photos — only for the owner (resume data must not reach clients of the app). */
async function handleResumeSearch(req, res, url) {
  const key = String(req.headers['x-admin-key'] || '');
  const admin = process.env.HH_ADMIN_KEY || '';
  const a = Buffer.from(key), b = Buffer.from(admin);
  if (!admin || a.length !== b.length || !crypto.timingSafeEqual(a, b)) return send(res, 403, { error: 'Раздел только для владельца АртСтроя. Неверный ключ.' });
  if (url.pathname === '/v1/market/owner') return send(res, 200, { ok: true });
  const text = String(url.searchParams.get('text') || '').slice(0, 100);
  const city = String(url.searchParams.get('city') || 'Сочи').slice(0, 60);
  const board = url.searchParams.get('board') || 'all';
  const page = Math.max(0, Math.min(20, Number.parseInt(url.searchParams.get('page') || '0', 10) || 0));
  const errors = {};
  const [fromHH, fromAvito] = await Promise.all([
    board === 'avito' ? [] : hh.searchResumes({ text, city, page }).catch((e) => { errors.hh = e.message; return []; }),
    board === 'hh' ? [] : avito.searchResumes({ text, city, page }).catch((e) => { errors.avito = e.message; return []; }),
  ]);
  const items = [];
  for (let i = 0; i < Math.max(fromHH.length, fromAvito.length); i += 1) { if (fromHH[i]) items.push(fromHH[i]); if (fromAvito[i]) items.push(fromAvito[i]); }
  return send(res, 200, { items, errors });
}

/** Same flow as hh.ru for another job board (Avito): connect, webhook, publish, responses, chat. */
async function handleMarket(req, res, url, provider, slug, title) {
  const parts = url.pathname.split('/').filter(Boolean);
  if (req.method === 'GET' && url.pathname === `/v1/auth/${slug}/start`) {
    res.writeHead(302, { Location: provider.startURL(url.searchParams.get('key')) });
    return res.end();
  }
  if (req.method === 'GET' && url.pathname === `/v1/auth/${slug}/callback`) {
    if (url.searchParams.get('error')) return page(res, 400, 'Подключение отменено', `${title} не дал доступ. Откройте ссылку подключения ещё раз.`);
    try {
      const result = await provider.finishOAuth(url.searchParams.get('code') || '', url.searchParams.get('state') || '');
      return page(res, 200, `${title} подключён ✓`, `Аккаунт «${result.name}» подключён к приложению АртСтрой. Новые заявки будут публиковаться на ${title}, отклики и чат — в приложении. Это окно можно закрыть.`);
    } catch (error) {
      return page(res, error.status || 500, 'Не получилось', error.message || 'Ошибка подключения.');
    }
  }
  if (req.method === 'POST' && parts[2] === 'webhook' && parts[3]) {
    const event = await readBody(req).catch(() => ({}));
    try { provider.webhook(parts[3], event); } catch (error) { return send(res, error.status || 404, { ok: false }); }
    return send(res, 200, { ok: true });
  }
  if (req.method === 'GET' && url.pathname === `/v1/${slug}/status`) return send(res, 200, await provider.status(url.searchParams.get('key')));

  if (config.appToken && req.headers['x-app-token'] !== config.appToken) return send(res, 401, { error: 'Нет доступа.' });
  const installId = String(req.headers['x-install-id'] || '');
  if (!INSTALL_ID.test(installId)) return send(res, 400, { error: 'Обновите приложение.' });
  const orderToken = String(req.headers['x-hh-order-token'] || req.headers['x-order-token'] || '');
  if (req.method === 'POST' && url.pathname === `/v1/${slug}/vacancies`) {
    const body = await readBody(req);
    return send(res, 200, await provider.publishOrder(installId, {
      orderId: body.orderId, category: String(body.category || '').slice(0, 100), city: String(body.city || '').slice(0, 100),
      details: String(body.details || '').slice(0, 4000), budget: String(body.budget || '').slice(0, 100),
    }));
  }
  if (parts[2] === 'orders' && parts[3]) {
    const orderId = decodeURIComponent(parts[3]);
    if (req.method === 'GET' && parts[4] === 'responses') return send(res, 200, await provider.responses(orderId, orderToken));
    if (parts[4] === 'chats' && parts[5] && parts[6] === 'messages') {
      const chatId = decodeURIComponent(parts[5]);
      if (req.method === 'GET') return send(res, 200, await provider.messages(orderId, orderToken, chatId));
      if (req.method === 'POST') { const body = await readBody(req); return send(res, 200, await provider.sendMessage(orderId, orderToken, chatId, body.text)); }
    }
  }
  return send(res, 404, { error: 'Не найдено' });
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((error) => {
    const status = error instanceof ApiError ? error.status : 500;
    if (!(error instanceof ApiError)) console.error(error);
    if (!res.headersSent) send(res, status, { error: error instanceof ApiError ? error.message : 'Внутренняя ошибка сервера.' });
    else res.end();
  });
});
server.requestTimeout = 300_000;
server.headersTimeout = 60_000;
server.listen(config.port, () => console.log(`АртСтрой server on :${config.port}, AI: ${ai.activeProviders().join(', ') || 'нет ключей'}; image edit: ${editEngines().join(', ') || 'нет'}; hh.ru: ${hh.hhEnabled() ? 'настроен' : 'нет'}; Avito: ${avito.avitoEnabled() ? 'настроен' : 'нет'}`));
