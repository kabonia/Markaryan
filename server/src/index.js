import crypto from 'node:crypto';
// АртСтрой AI server: the app talks only to this server; all AI keys stay here.
import fs from 'node:fs';
import http from 'node:http';
import zlib from 'node:zlib';
import { config } from './config.js';
import { ApiError } from './util.js';
import { consume as limitConsume, refund as limitRefund, remaining } from './limits.js';
import * as billing from './billing.js';
import * as payments from './payments.js';
import { payPage, donePage } from './paypage.js';
import * as ai from './ai.js';
import { imageEngines, legacyEditEngines, preferredEngines, renderChoices, renderWithFallback, resolveEngines } from './providers/images.js';
import { designChoices } from './providers/openrouter.js';
import * as hh from './hh.js';
import * as avito from './avito.js';
import * as market from './market.js';
import * as house from './house.js';
import * as metal from './metal.js';
import * as reports from './reports.js';
import * as estimate from './estimate.js';
import * as smeta from './smeta.js';
import { xlsxToText } from './xlsx.js';
import * as materials from './materials.js';
import * as roof from './roof.js';
import * as houseScans from './house-scans.js';

const INSTALL_ID = /^[A-Za-z0-9-]{16,64}$/;

function send(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(data), 'Cache-Control': 'no-store' });
  res.end(data);
}

async function readBody(req, limit = config.maxBodyBytes) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limit) throw new ApiError(413, 'Слишком большой запрос (фото больше допустимого).');
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

// Daily limits + credits (when billing is on): credits are taken before the AI runs and given back when it fails.
function consume(kind, installId, ip, units, billingKind) {
  limitConsume(kind, installId, ip);
  try { return billing.charge(installId, billingKind ?? kind, units, ip); } catch (error) { limitRefund(kind, installId, ip); throw error; }
}
function refund(kind, installId, ip, amount) {
  limitRefund(kind, installId, ip);
  billing.refund(installId, kind, amount);
}
function html(res, page) {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(page);
}

function clientIP(req) {
  return String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
}

async function handle(req, res) {
  const url = new URL(req.url, 'http://local');
  if (req.method === 'GET' && url.pathname === '/health') return send(res, 200, { ok: true });

  if (req.method === 'GET' && url.pathname === '/v1/market/price-book') return send(res, 200, market.priceBook(url));
  // «Смета дома»: geometry + the city's weekly price book, no AI per request — free and instant. The city counts as demand.
  if (req.method === 'POST' && url.pathname === '/v1/house/estimate') {
    const body = await readBody(req);
    const lat = Number.parseFloat(body?.lat), lon = Number.parseFloat(body?.lon);
    house.noteDemand(body?.city, lat, lon);
    return send(res, 200, house.estimate(body, { lat, lon }));
  }
  if (req.method === 'POST' && url.pathname === '/v1/metal/estimate') {
    const body = await readBody(req);
    const lat = Number.parseFloat(body?.lat), lon = Number.parseFloat(body?.lon);
    house.noteDemand(body?.city, lat, lon);
    return send(res, 200, metal.estimate(body, { lat, lon }));
  }
  if (url.pathname.startsWith('/v1/partners') || url.pathname.startsWith('/v1/admin/partners')) return handlePartners(req, res, url);
  if (req.method === 'POST' && url.pathname === '/v1/report') return send(res, 200, await reports.report(await readBody(req), clientIP(req)));
  if (url.pathname.startsWith('/v1/auth/hh/') || url.pathname.startsWith('/v1/hh/')) return handleHH(req, res, url);
  if (req.method === 'GET' && url.pathname === '/v1/market/vacancies') return handleMarketSearch(req, res, url);
  if (req.method === 'GET' && (url.pathname === '/v1/market/resumes' || url.pathname === '/v1/market/owner')) return handleResumeSearch(req, res, url);
  if (url.pathname.startsWith('/v1/auth/avito/') || url.pathname.startsWith('/v1/avito/')) return handleMarket(req, res, url, avito, 'avito', 'Avito');
  // Payments: the page (Russia), ЮKassa and App Store notifications — no app token, every payment is checked with its provider.
  if (req.method === 'GET' && url.pathname === '/pay') return html(res, payPage());
  if (req.method === 'GET' && url.pathname === '/pay/done') return html(res, donePage());
  if (req.method === 'POST' && url.pathname === '/v1/pay/yookassa/create') return send(res, 200, await payments.createYookassa(await readBody(req, 64 * 1024)));
  if (req.method === 'POST' && url.pathname === '/v1/pay/yookassa/webhook') return send(res, 200, await payments.yookassaWebhook(await readBody(req, 256 * 1024)));
  if (req.method === 'POST' && url.pathname === '/v1/pay/apple/notify') return send(res, 200, payments.appleNotification(await readBody(req, 512 * 1024)));
  if (!url.pathname.startsWith('/v1/ai/') && !url.pathname.startsWith('/v1/billing/')) return send(res, 404, { error: 'Не найдено' });
  if (config.appToken && req.headers['x-app-token'] !== config.appToken) return send(res, 401, { error: 'Нет доступа.' });
  const installId = String(req.headers['x-install-id'] || '');
  if (!INSTALL_ID.test(installId)) return send(res, 400, { error: 'Обновите приложение.' });
  const ip = clientIP(req);

  // Balance, plan and purchases of this installation.
  if (req.method === 'GET' && url.pathname === '/v1/billing/me') return send(res, 200, billing.me(installId));
  if (req.method === 'POST' && url.pathname === '/v1/billing/apple') return send(res, 200, { ...payments.appleSync(installId, await readBody(req, 1024 * 1024)), me: billing.me(installId) });
  if (req.method === 'POST' && url.pathname === '/v1/billing/autopay') { billing.setAutopay(installId, (await readBody(req, 4096)).on); return send(res, 200, billing.me(installId)); }
  if (url.pathname.startsWith('/v1/billing/')) return send(res, 404, { error: 'Не найдено' });

  if (req.method === 'GET' && url.pathname === '/v1/ai/capabilities') {
    const providers = ai.activeProviders();
    const engines = imageEngines().map(({ id, title }) => ({ id, title }));
    return send(res, 200, {
      chat: providers.length > 0, vision: providers.length > 0, imageGenerate: engines.length > 0 || ai.canGenerateImages(),
      imageEdit: legacyEditEngines(), imageEngines: engines, providers, remaining: remaining(installId),
      // What the app offers to choose on the «Дизайн» step.
      designModels: providers.includes('openrouter') ? designChoices() : [], renderModels: renderChoices(),
    });
  }
  // «Смета по документам»: create a job (drawings as page pictures — a bigger body), follow it, long-poll for the end.
  const smetaPath = url.pathname.match(/^\/v1\/ai\/smeta(?:\/([0-9a-f-]{36}))?(\/wait)?$/);
  if (smetaPath) {
    if (req.method === 'POST' && !smetaPath[1]) {
      const input = await readBody(req, 60 * 1024 * 1024);
      const docs = Array.isArray(input?.docs) ? input.docs : [];
      const pages = docs.reduce((t, d) => t + (Array.isArray(d?.pages) ? d.pages.length : 0), 0);
      if (pages > billing.SMETA_MAX_PAGES) throw new ApiError(400, `Не больше ${billing.SMETA_MAX_PAGES} листов в одной смете — разделите проект на части.`);
      // Text and Excel are paid by size too: every 6 000 characters count as a sheet.
      const textChars = String(input?.text || '').length + docs.reduce((t, d) => t + String(d?.text || '').length + (typeof d?.xlsx === 'string' ? (() => { try { return xlsxToText(d.xlsx).length; } catch { return 0; } })() : 0), 0);
      const credits = consume('smeta', installId, ip, { pages, textChars });
      try { return send(res, 200, smeta.create(input, installId, { credits })); } catch (error) { refund('smeta', installId, ip, credits); throw error; }
    }
    if (req.method === 'GET' && smetaPath[1] && !smetaPath[2]) return send(res, 200, smeta.status(smetaPath[1], installId));
    if (smetaPath[1] && smetaPath[2]) return send(res, 200, await smeta.wait(smetaPath[1], installId));
    return send(res, 404, { error: 'Не найдено' });
  }
  // «Дом снаружи»: пакет скана частями (PUT …/parts/N — сырые байты), затем …/complete; GET — статус обработки.
  const scanPath = url.pathname.match(/^\/v1\/ai\/house\/scans(?:\/([0-9a-f-]{36}))?(?:\/(parts\/(\d+)|complete|model\.obj))?$/);
  if (scanPath) {
    const [, id, action, part] = scanPath;
    if (req.method === 'POST' && !id) return send(res, 200, houseScans.create(await readBody(req, 256 * 1024), installId));
    if (req.method === 'PUT' && id && part !== undefined) return send(res, 200, await houseScans.putPart(req, id, Number(part), installId));
    if (req.method === 'POST' && id && action === 'complete') return send(res, 200, await houseScans.complete(id, installId));
    if (req.method === 'GET' && id && !action) return send(res, 200, houseScans.status(id, installId));
    if (req.method === 'GET' && !id) return send(res, 200, houseScans.list(installId));
    if (req.method === 'GET' && id && action === 'model.obj') {
      // 3D-модель (OBJ, 5–10 МБ текста) — сжатой: приложение разжимает само.
      const file = houseScans.modelPath(id, installId);
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Content-Encoding': 'gzip', 'Cache-Control': 'private, max-age=86400' });
      fs.createReadStream(file).pipe(zlib.createGzip({ level: 6 })).pipe(res);
      return;
    }
    return send(res, 404, { error: 'Не найдено' });
  }
  if (req.method !== 'POST') return send(res, 405, { error: 'Метод не поддерживается.' });
  const body = await readBody(req);

  if (url.pathname === '/v1/ai/chat') {
    const messages = cleanMessages(body.messages);
    const kind = messages.some((m) => m.image) ? 'vision' : 'chat';
    const paid = consume(kind, installId, ip, undefined, kind === 'vision' ? 'vision' : body.tier === 'helper' ? 'helper' : 'chat');
    const params = { system: String(body.system || '').slice(0, 40_000), messages, maxTokens: Number(body.maxTokens) || 2000, tier: body.tier === 'helper' ? 'helper' : undefined };
    if (!body.stream) {
      try { return send(res, 200, { text: await ai.chat(params) }); } catch (error) { refund(kind, installId, ip, paid); throw error; }
    }
    // Server‑sent events: data: {"delta":"…"} … data: {"done":true}
    res.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-store', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
    const heartbeat = setInterval(() => res.write(': ping\n\n'), 15_000);
    let started = false;
    try {
      await ai.chat({ ...params, onDelta: (delta) => { started = true; res.write(`data: ${JSON.stringify({ delta })}\n\n`); } });
      res.write(`data: ${JSON.stringify({ done: true })}\n\n`);
    } catch (error) {
      if (!started) refund(kind, installId, ip, paid);
      res.write(`data: ${JSON.stringify({ error: error instanceof ApiError ? error.message : 'Ошибка ИИ. Попробуйте ещё раз.' })}\n\n`);
    } finally {
      clearInterval(heartbeat);
      res.end();
    }
    return;
  }

  if (url.pathname === '/v1/ai/price-estimate') {
    const items = Math.min(40, Array.isArray(body.items) ? body.items.length : 0);
    const paid = consume('chat', installId, ip, { items }, 'priceEstimate');
    try { return send(res, 200, await estimate.priceEstimate(body)); } catch (error) { refund('chat', installId, ip, paid); throw error; }
  }

  if (url.pathname === '/v1/ai/json') {
    const messages = cleanMessages(body.messages);
    const kind = messages.some((m) => m.image) ? 'vision' : 'json';
    if (!body.schema || typeof body.schema !== 'object') throw new ApiError(400, 'Нет схемы ответа.');
    const paid = consume(kind, installId, ip);
    // `model` — the model the user picked on the «Дизайн» step; the answer says which model really answered.
    const meta = {};
    const model = typeof body.model === 'string' ? body.model.slice(0, 120) : undefined;
    try {
      const result = await ai.json({ system: String(body.system || ''), messages, schema: body.schema, name: String(body.name || 'result').replace(/[^A-Za-z0-9_]/g, '_'), description: String(body.description || ''), maxTokens: Number(body.maxTokens) || 8000, model, meta });
      return send(res, 200, { json: result, model: meta.model || meta.provider || null });
    } catch (error) { refund(kind, installId, ip, paid); throw error; }
  }

  if (url.pathname === '/v1/ai/material-identify') {
    if (typeof body.image !== 'string' || body.image.length < 1000) throw new ApiError(400, 'Нет изображения.');
    const paid = consume('vision', installId, ip, undefined, 'material');
    try { return send(res, 200, await materials.identify(body)); } catch (error) { refund('vision', installId, ip, paid); throw error; }
  }

  // «Дом снаружи», этап 0: крыша по 3–5 фото (тип, детали, уклон, конёк, метки достоверности).
  if (url.pathname === '/v1/ai/house/roof') {
    const paid = consume('vision', installId, ip, undefined, 'houseRoof');
    try { return send(res, 200, await roof.analyze(body)); } catch (error) { refund('vision', installId, ip, paid); throw error; }
  }

  if (url.pathname === '/v1/ai/image-edit') {
    // "auto" (or nothing) — the engines in order with fallback, `prefer` (the model picked on the «Дизайн» step) first;
    // an engine id — only that one (comparing engines).
    const requested = typeof body.engine === 'string' ? body.engine : 'auto';
    const engines = requested === 'auto' ? preferredEngines(body.prefer) : resolveEngines(requested);
    if (engines.length === 0) throw new ApiError(400, 'Этот генератор не подключён на сервере.');
    if (typeof body.image !== 'string' || body.image.length < 1000) throw new ApiError(400, 'Нет изображения.');
    const paid = consume('imageEdit', installId, ip);
    try {
      const references = (Array.isArray(body.references) ? body.references : []).filter((r) => typeof r === 'string' && r.length > 1000).slice(0, 4);
      const params = { image: body.image, prompt: String(body.prompt || ''), size: body.size, aspectRatio: aspectRatio(body.aspectRatio), references };
      const { image, engine } = await renderWithFallback(engines, params);
      return send(res, 200, { image, engine: engine.id, title: engine.title });
    } catch (error) { refund('imageEdit', installId, ip, paid); throw error; }
  }

  if (url.pathname === '/v1/ai/image') {
    const paid = consume('image', installId, ip);
    const prompt = String(body.prompt || '').slice(0, 3000);
    try {
      // The photoreal engines draw best (the one picked in the app first); Kandinsky or Alice AI ART when none is set up or all fail.
      const engines = preferredEngines(body.prefer);
      if (engines.length > 0) {
        try {
          const { image, engine } = await renderWithFallback(engines, { prompt, aspectRatio: aspectRatio(body.aspectRatio) });
          return send(res, 200, { image, engine: engine.id, title: engine.title });
        } catch (error) {
          if (!ai.canGenerateImages()) throw error;
        }
      }
      return send(res, 200, { image: await ai.generateImage({ prompt }) });
    } catch (error) { refund('image', installId, ip, paid); throw error; }
  }

  return send(res, 404, { error: 'Не найдено' });
}

const RATIOS = new Set(['1:1', '4:3', '3:4', '3:2', '2:3', '16:9', '9:16', '5:4', '4:5']);
const aspectRatio = (value) => (RATIOS.has(value) ? value : '4:3');

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

async function handlePartners(req, res, url) {
  if (url.pathname === '/v1/admin/partners') {
    market.checkAdmin(req);
    if (req.method === 'GET') return send(res, 200, { partners: market.listPartners(), stats: market.partnerStats() });
    if (req.method === 'PUT') return send(res, 200, market.savePartners((await readBody(req)).partners));
  }
  if (req.method === 'GET' && url.pathname === '/v1/partners') {
    const q = (k) => url.searchParams.get(k);
    return send(res, 200, { partners: market.partnersFor({ city: q('city'), region: q('region'), category: q('category') }) });
  }
  const event = url.pathname.match(/^\/v1\/partners\/([a-z0-9-]{2,40})\/events$/);
  if (req.method === 'POST' && event) return send(res, 200, market.recordEvent(event[1], (await readBody(req)).type));
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
// ЮKassa autopay of plans: checked every hour.
setInterval(() => payments.renewPlans().catch((error) => console.warn('[pay]', error.message)), 3_600_000).unref();
server.requestTimeout = 300_000;
server.headersTimeout = 60_000;
server.listen(config.port, () => console.log(`АртСтрой server on :${config.port}, AI: ${ai.activeProviders().join(', ') || 'нет ключей'}; pictures: ${imageEngines().map((e) => e.title).join(', ') || 'нет'}; hh.ru: ${hh.hhEnabled() ? 'настроен' : 'нет'}; Avito: ${avito.avitoEnabled() ? 'настроен' : 'нет'}`));
// «Дом снаружи»: вернуть в очередь сканы, прерванные перезапуском; уборка старых пакетов раз в 6 часов.
houseScans.resume();
setInterval(() => houseScans.cleanup(), 6 * 3600_000).unref();
