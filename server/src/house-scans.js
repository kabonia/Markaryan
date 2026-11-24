// «Дом снаружи», этап 1: приём пакета скана (zip: кадры, глубина, позиции камеры ARKit, manifest.json).
// Пакет идёт частями по 8 МБ (докачка после обрыва связи: приложение спрашивает, какие части уже есть).
// Сервер слабый — он только хранит пакет и отдаёт его GPU-обработчику; сам ничего тяжёлого не считает.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { ApiError } from './util.js';

export const PART_BYTES = 8 * 1024 * 1024;
const MAX_SCAN_BYTES = Number(process.env.HOUSE_SCAN_MAX_MB || 600) * 1024 * 1024;
const MAX_TOTAL_BYTES = Number(process.env.HOUSE_SCANS_TOTAL_GB || 6) * 1024 ** 3;
const ID = /^[0-9a-f-]{36}$/;

const root = () => path.join(config.dataDir, 'house-scans');
const dir = (id) => path.join(root(), id);
const metaPath = (id) => path.join(dir(id), 'scan.json');

function load(id, installId) {
  if (!ID.test(id)) throw new ApiError(404, 'Скан не найден.');
  let meta;
  try { meta = JSON.parse(fs.readFileSync(metaPath(id), 'utf8')); } catch { throw new ApiError(404, 'Скан не найден.'); }
  if (meta.installId !== installId) throw new ApiError(404, 'Скан не найден.');
  return meta;
}
const save = (meta) => fs.writeFileSync(metaPath(meta.id), JSON.stringify(meta, null, 1));

function usedBytes() {
  let total = 0;
  try {
    for (const id of fs.readdirSync(root())) {
      try { for (const f of fs.readdirSync(dir(id))) total += fs.statSync(path.join(dir(id), f)).size; } catch { /* удалён */ }
    }
  } catch { /* папки ещё нет */ }
  return total;
}

const view = (meta) => ({
  id: meta.id, status: meta.status, bytes: meta.bytes, parts: meta.parts, partBytes: PART_BYTES,
  received: meta.received, progress: meta.progress ?? null, message: meta.message ?? null, result: meta.result ?? null,
  createdAt: meta.createdAt,
});

/** Новый скан: { bytes, sha256, manifest: {frames, device, lidar, …} } → id и размер части. */
export function create(body, installId) {
  const bytes = Number(body?.bytes);
  if (!(bytes > 0) || bytes > MAX_SCAN_BYTES) throw new ApiError(400, `Скан слишком большой (больше ${Math.round(MAX_SCAN_BYTES / 1024 / 1024)} МБ).`);
  if (usedBytes() + bytes > MAX_TOTAL_BYTES) throw new ApiError(503, 'Хранилище сканов заполнено. Попробуйте позже.', { retryable: true });
  const id = crypto.randomUUID();
  fs.mkdirSync(dir(id), { recursive: true });
  const manifest = body?.manifest && typeof body.manifest === 'object' ? body.manifest : {};
  const meta = {
    id, installId, status: 'uploading', bytes, parts: Math.ceil(bytes / PART_BYTES), received: [],
    sha256: typeof body?.sha256 === 'string' ? body.sha256.slice(0, 64) : null,
    summary: { frames: Number(manifest.frames) || 0, device: String(manifest.device || '').slice(0, 60), lidar: Boolean(manifest.lidar), kind: String(manifest.kind || 'house').slice(0, 20) },
    createdAt: new Date().toISOString(),
  };
  save(meta);
  return view(meta);
}

/** Одна часть пакета (сырые байты). */
export async function putPart(req, id, index, installId) {
  const meta = load(id, installId);
  if (meta.status !== 'uploading') throw new ApiError(409, 'Скан уже загружен.');
  if (!(index >= 0 && index < meta.parts)) throw new ApiError(400, 'Неверный номер части.');
  const expected = index === meta.parts - 1 ? meta.bytes - PART_BYTES * (meta.parts - 1) : PART_BYTES;
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > expected) throw new ApiError(413, 'Часть больше ожидаемой.');
    chunks.push(chunk);
  }
  if (size !== expected) throw new ApiError(400, `Часть оборвалась: ${size} из ${expected} байт.`, { retryable: true });
  const file = path.join(dir(id), `part-${String(index).padStart(4, '0')}`);
  fs.writeFileSync(`${file}.tmp`, Buffer.concat(chunks));
  fs.renameSync(`${file}.tmp`, file);
  const fresh = load(id, installId);
  if (!fresh.received.includes(index)) fresh.received.push(index);
  fresh.received.sort((a, b) => a - b);
  save(fresh);
  return view(fresh);
}

/** Все части на месте → собираем scan.zip, сверяем SHA-256 и ставим в очередь GPU. */
export async function complete(id, installId) {
  const meta = load(id, installId);
  if (meta.status !== 'uploading') return view(meta);
  const missing = Array.from({ length: meta.parts }, (_, i) => i).filter((i) => !meta.received.includes(i));
  if (missing.length) throw new ApiError(409, `Не хватает частей: ${missing.slice(0, 10).join(', ')}.`);
  const out = path.join(dir(id), 'scan.zip');
  const hash = crypto.createHash('sha256');
  const fd = fs.openSync(out, 'w');
  try {
    for (let i = 0; i < meta.parts; i += 1) {
      const part = path.join(dir(id), `part-${String(i).padStart(4, '0')}`);
      const data = fs.readFileSync(part);
      hash.update(data);
      fs.writeSync(fd, data);
      fs.unlinkSync(part);
    }
  } finally { fs.closeSync(fd); }
  const digest = hash.digest('hex');
  if (meta.sha256 && meta.sha256 !== digest) {
    meta.status = 'failed'; meta.message = 'Пакет повреждён при загрузке. Отправьте скан ещё раз.';
    save(meta);
    throw new ApiError(400, meta.message);
  }
  meta.status = 'queued';
  meta.message = 'Скан получен. Обработка на GPU подключается — макет появится, когда она заработает.';
  meta.uploadedAt = new Date().toISOString();
  save(meta);
  console.log(`[house] скан ${id}: ${(meta.bytes / 1024 / 1024).toFixed(1)} МБ, кадров ${meta.summary.frames}, LiDAR ${meta.summary.lidar}`);
  return view(meta);
}

export const status = (id, installId) => view(load(id, installId));
