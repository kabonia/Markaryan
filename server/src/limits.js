// Daily quotas per installation and per IP + a per‑minute burst limit. Saved to disk so a restart does not reset them.
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { ApiError } from './util.js';

const file = path.join(config.dataDir, 'usage.json');
let state = { day: today(), counts: {} };
const minute = new Map(); // key → [timestamps]

function today() { return new Date().toISOString().slice(0, 10); }

try {
  fs.mkdirSync(config.dataDir, { recursive: true });
  const saved = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (saved.day === today()) state = saved;
} catch { /* first start */ }

let dirty = false;
setInterval(() => {
  if (!dirty) return;
  dirty = false;
  fs.writeFile(file, JSON.stringify(state), () => {});
}, 15_000).unref();

const LABELS = { search: 'поисков вакансий', chat: 'вопросов ИИ', json: 'проектов дизайна', vision: 'анализов фото', imageEdit: 'фотореалистичных визуализаций', image: 'картинок', smeta: 'смет по документам' };

/** Throws 429 with a clear Russian message when a quota is used up; otherwise counts the request. */
export function consume(kind, installId, ip) {
  if (state.day !== today()) state = { day: today(), counts: {} };
  const limit = config.limits[kind] ?? 50;
  const now = Date.now();
  const recent = (minute.get(installId) || []).filter((t) => now - t < 60_000);
  if (recent.length >= config.limits.perMinute) throw new ApiError(429, 'Слишком много запросов подряд. Подождите минуту.');
  recent.push(now);
  minute.set(installId, recent);

  const byInstall = `${kind}:i:${installId}`;
  const byIP = `${kind}:ip:${ip}`;
  if ((state.counts[byInstall] || 0) >= limit) {
    throw new ApiError(429, `Дневной лимит ${LABELS[kind] || 'запросов'} исчерпан (${limit}). Попробуйте завтра.`);
  }
  if ((state.counts[byIP] || 0) >= limit * config.limits.ipMultiplier) {
    throw new ApiError(429, 'С этой сети сегодня слишком много запросов. Попробуйте завтра.');
  }
  state.counts[byInstall] = (state.counts[byInstall] || 0) + 1;
  state.counts[byIP] = (state.counts[byIP] || 0) + 1;
  dirty = true;
}

/** Gives the quota back when the AI itself failed (the user should not pay for our errors). */
export function refund(kind, installId, ip) {
  for (const key of [`${kind}:i:${installId}`, `${kind}:ip:${ip}`]) {
    if (state.counts[key] > 0) state.counts[key] -= 1;
  }
  dirty = true;
}

export function remaining(installId) {
  const result = {};
  for (const kind of Object.keys(LABELS)) result[kind] = Math.max(0, (config.limits[kind] ?? 0) - (state.counts[`${kind}:i:${installId}`] || 0));
  return result;
}
