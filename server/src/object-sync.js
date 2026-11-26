// Совместный доступ к объекту: владелец публикует объект → получает код (8 знаков); супруг или прораб открывает
// объект по коду на своём iPhone; дальше оба синхронизируют правки. Версии: запись с устаревшей версией → 409
// (conflict) с текущим объектом, приложение сливает правки и отправляет снова. DATA_DIR/objects/<code>.json, до 5 МБ.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { config } from './config.js';
import { ApiError } from './util.js';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const dir = () => path.join(config.dataDir, 'objects');
const file = (code) => path.join(dir(), `${code}.json`);
const valid = (code) => typeof code === 'string' && /^[A-HJ-NP-Z2-9]{8}$/.test(code);

function read(code) {
  if (!valid(code)) throw new ApiError(404, 'Неверный код объекта.');
  try { return JSON.parse(fs.readFileSync(file(code), 'utf8')); } catch { throw new ApiError(404, 'Объект с таким кодом не найден.'); }
}
function write(code, entry) {
  fs.mkdirSync(dir(), { recursive: true });
  fs.writeFileSync(`${file(code)}.tmp`, JSON.stringify(entry));
  fs.renameSync(`${file(code)}.tmp`, file(code));
}
function checkWorkspace(workspace) {
  if (!workspace || typeof workspace !== 'object' || typeof workspace.id !== 'string') throw new ApiError(400, 'Нет объекта.');
  if (Buffer.byteLength(JSON.stringify(workspace)) > 5_000_000) throw new ApiError(413, 'Объект слишком большой для совместного доступа.');
}

export function share(installId, body) {
  checkWorkspace(body?.workspace);
  let code;
  do { code = Array.from(crypto.randomBytes(8), (b) => ALPHABET[b % ALPHABET.length]).join(''); } while (fs.existsSync(file(code)));
  const entry = { code, version: 1, workspace: body.workspace, owner: installId, members: [installId], updatedAt: new Date().toISOString(), updatedBy: installId };
  write(code, entry);
  return { code, version: 1 };
}

export function get(installId, code) {
  const entry = read(code);
  if (!entry.members.includes(installId)) {
    if (entry.members.length >= 10) throw new ApiError(403, 'К объекту уже подключено 10 человек.');
    entry.members.push(installId);
    write(code, entry);
  }
  return { code, version: entry.version, workspace: entry.workspace, updatedAt: entry.updatedAt, members: entry.members.length, owner: entry.owner === installId };
}

export function put(installId, code, body) {
  const entry = read(code);
  if (!entry.members.includes(installId)) throw new ApiError(403, 'Сначала откройте объект по коду.');
  checkWorkspace(body?.workspace);
  // Объект изменили на другом iPhone: отдаём текущий — приложение сливает правки и отправляет снова.
  if (Number(body?.baseVersion) !== entry.version) return { code, conflict: true, version: entry.version, workspace: entry.workspace };
  entry.version += 1;
  entry.workspace = body.workspace;
  entry.updatedAt = new Date().toISOString();
  entry.updatedBy = installId;
  write(code, entry);
  return { code, version: entry.version, updatedAt: entry.updatedAt };
}

export function leave(installId, code) {
  const entry = read(code);
  if (entry.owner === installId) { fs.rmSync(file(code), { force: true }); return { ok: true, deleted: true }; }
  entry.members = entry.members.filter((m) => m !== installId);
  write(code, entry);
  return { ok: true };
}
