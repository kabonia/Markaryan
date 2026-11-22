// Error reports from the app: what broke, on which screen, app version. Forwarded to the owner's Telegram chat
// (TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID) and kept in DATA_DIR/reports.log. No personal data is accepted.
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { ApiError, request } from './util.js';

const env = process.env;
const recent = new Map(); // ip -> timestamps, max 20 reports per hour per device network
const clean = (value, max) => String(value ?? '').replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, max);

export async function report(body, ip) {
  const now = Date.now();
  const list = (recent.get(ip) || []).filter((t) => now - t < 3_600_000);
  if (list.length >= 20) throw new ApiError(429, 'Слишком много отчётов.');
  list.push(now); recent.set(ip, list);

  const item = {
    at: new Date().toISOString(),
    screen: clean(body?.screen, 80),
    action: clean(body?.action, 120),
    error: clean(body?.error, 600),
    autoFixed: Boolean(body?.autoFixed),
    appVersion: clean(body?.appVersion, 30),
    device: clean(body?.device, 40),
  };
  if (!item.error) throw new ApiError(400, 'Нет описания ошибки.');
  fs.mkdirSync(config.dataDir, { recursive: true });
  fs.appendFileSync(path.join(config.dataDir, 'reports.log'), JSON.stringify(item) + '\n');

  const token = env.TELEGRAM_BOT_TOKEN, chat = env.TELEGRAM_CHAT_ID;
  let telegram = false;
  if (token && chat) {
    const text = [
      `⚠️ СметаПро: ошибка${item.autoFixed ? ' (исправлена автоматически)' : ''}`,
      `Экран: ${item.screen || '—'}`,
      item.action ? `Действие: ${item.action}` : '',
      `Ошибка: ${item.error}`,
      `Версия: ${item.appVersion || '—'} · ${item.device || 'iPhone'}`,
    ].filter(Boolean).join('\n');
    try {
      const response = await request(`https://api.telegram.org/bot${token}/sendMessage`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: chat, text, disable_web_page_preview: true }),
      }, 15_000);
      telegram = response.ok;
    } catch { telegram = false; }
  }
  return { ok: true, telegram };
}
