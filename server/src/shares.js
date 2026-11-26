// «Отправить подрядчику ссылкой»: приложение публикует сводку объекта (текст + до 4 картинок) —
// подрядчик открывает её в браузере без приложения: /s/<id>. Хранится 30 дней в DATA_DIR/shares/<id>/.
// Лимиты: 20 ссылок в сутки на установку, текст до 20 000 знаков, картинки JPEG до 1,5 МБ.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { config } from './config.js';
import { ApiError } from './util.js';

const DAYS = 30;
const dir = () => path.join(config.dataDir, 'shares');
const recent = new Map();
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

export function create(installId, body) {
  const now = Date.now();
  const list = (recent.get(installId) || []).filter((t) => now - t < 86_400_000);
  if (list.length >= 20) throw new ApiError(429, 'Сегодня уже 20 ссылок — попробуйте завтра.');
  const title = String(body?.title ?? '').trim().slice(0, 120) || 'Объект';
  const text = String(body?.text ?? '').trim().slice(0, 20_000);
  if (!text) throw new ApiError(400, 'Нечего отправлять.');
  const images = (Array.isArray(body?.images) ? body.images : []).slice(0, 4).map((b64) => Buffer.from(String(b64), 'base64'))
    .filter((b) => b.length > 100 && b.length <= 1_500_000 && b[0] === 0xff && b[1] === 0xd8);
  const id = crypto.randomBytes(9).toString('base64url');
  const folder = path.join(dir(), id);
  fs.mkdirSync(folder, { recursive: true });
  images.forEach((b, i) => fs.writeFileSync(path.join(folder, `${i}.jpg`), b));
  fs.writeFileSync(path.join(folder, 'share.json'), JSON.stringify({ title, text, images: images.length, createdAt: new Date().toISOString() }));
  list.push(now); recent.set(installId, list);
  const base = (process.env.PUBLIC_URL || '').replace(/\/$/, '');
  return { id, url: `${base}/s/${id}`, days: DAYS };
}

function read(id) {
  if (!/^[A-Za-z0-9_-]{12}$/.test(id)) return null;
  const file = path.join(dir(), id, 'share.json');
  try {
    const share = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (Date.now() - Date.parse(share.createdAt) > DAYS * 86_400_000) return null;
    return share;
  } catch { return null; }
}

export function image(id, index) {
  if (!read(id) || !/^[0-3]$/.test(String(index))) return null;
  const file = path.join(dir(), id, `${index}.jpg`);
  return fs.existsSync(file) ? fs.readFileSync(file) : null;
}

export function page(id) {
  const share = read(id);
  if (!share) return null;
  const lines = esc(share.text).split('\n').map((l) => {
    const linked = l.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" rel="nofollow noopener">$1</a>');
    return /^[A-ZА-ЯЁ0-9 ·«»—().,:-]{6,}$/.test(l.trim()) ? `<h2>${linked}</h2>` : `<p>${linked || '&nbsp;'}</p>`;
  }).join('');
  const pictures = Array.from({ length: share.images }, (_, i) => `<img src="/s/${id}/${i}.jpg" alt="">`).join('');
  return `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${esc(share.title)} — СметаПро</title>
<style>body{margin:0;font:16px/1.5 -apple-system,system-ui,sans-serif;background:#F3F0E8;color:#16241F}
header{background:linear-gradient(160deg,#116651,#07312A);color:#fff;padding:28px 20px}header small{color:#E6C888;letter-spacing:2px}
h1{margin:6px 0 0;font:700 26px Georgia,serif}main{max-width:760px;margin:0 auto;padding:16px 20px 40px}
h2{font:700 15px/1.3 -apple-system,sans-serif;color:#946F28;letter-spacing:1px;margin:22px 0 6px}p{margin:2px 0}
img{width:100%;border-radius:14px;margin:10px 0}a{color:#0F6B55;word-break:break-all}footer{color:#66645C;font-size:13px;margin-top:30px}</style></head>
<body><header><small>СМЕТАПРО · ОБЪЕКТ</small><h1>${esc(share.title)}</h1></header><main>${pictures}${lines}
<footer>Подготовлено в приложении СметаПро ${esc(share.createdAt.slice(0, 10))}. Ссылка действует ${DAYS} дней.</footer></main></body></html>`;
}
