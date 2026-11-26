// «Дом снаружи»: очередь обработки сканов. По одному скану за раз (сервер 2 vCPU / 4 ГБ), в отдельном процессе Python
// с ограничением памяти — ИИ-сервер не тормозит. Обработчик: gpu-worker/house (python -m house.run scan.zip out/).
// Позже тот же обработчик запускается на арендованном GPU (immers.cloud) — меняется только способ запуска.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { record } from './costs.js';
import * as billing from './billing.js';

const PYTHON = () => process.env.HOUSE_WORKER_PYTHON || '/opt/smetapro-worker/venv/bin/python';
const WORKER_DIR = () => process.env.HOUSE_WORKER_DIR || '/opt/smetapro-worker';
const MEMORY_MAX = () => process.env.HOUSE_WORKER_MEMORY || '2400M';
const TIMEOUT_MS = () => Number(process.env.HOUSE_WORKER_TIMEOUT_MIN || 40) * 60_000;

let hooks = null; // { load(id), save(meta), dir(id) } — из house-scans.js, чтобы не было циклического импорта
const queue = [];
let running = null;

export function init(api) {
  hooks = api;
}

export const enabled = () => process.env.HOUSE_WORKER !== 'off' && fs.existsSync(PYTHON());

export function enqueue(id) {
  if (!queue.includes(id) && running !== id) queue.push(id);
  setImmediate(next);
}

export const position = (id) => (running === id ? 0 : queue.indexOf(id) + 1);

function update(id, patch) {
  const meta = hooks.load(id);
  if (!meta) return null;
  Object.assign(meta, patch);
  hooks.save(meta);
  return meta;
}

/** Команда запуска: systemd-run с лимитом памяти (если есть), пониженный приоритет, 2 потока. */
function command(zip, out) {
  const python = [PYTHON(), '-m', 'house.run', zip, out];
  const useSystemd = process.getuid?.() === 0 && fs.existsSync('/usr/bin/systemd-run') && process.env.HOUSE_WORKER_SYSTEMD !== 'off';
  return useSystemd
    ? ['/usr/bin/systemd-run', ['--scope', '--quiet', '-p', `MemoryMax=${MEMORY_MAX()}`, '-p', 'MemorySwapMax=0', 'nice', '-n', '10', ...python]]
    : ['nice', ['-n', '10', ...python]];
}

function next() {
  if (running || queue.length === 0 || !hooks) return;
  const id = queue.shift();
  const meta = hooks.load(id);
  if (!meta || meta.status !== 'queued') return setImmediate(next);
  running = id;
  const dir = hooks.dir(id);
  const out = path.join(dir, 'result');
  const started = Date.now();
  update(id, { status: 'processing', progress: 0.01, message: 'Начинаем обработку', startedAt: new Date().toISOString() });
  const [bin, args] = command(path.join(dir, 'scan.zip'), out);
  const child = spawn(bin, args, {
    cwd: WORKER_DIR(),
    env: { ...process.env, OMP_NUM_THREADS: '2', PYTHONUNBUFFERED: '1' },
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  let failure = '';
  let tail = '';
  child.stderr.on('data', (chunk) => {
    tail = (tail + chunk.toString()).slice(-4000);
    for (const line of chunk.toString().split('\n')) {
      const stage = line.match(/^STAGE ([0-9.]+) (.+)$/);
      if (stage) update(id, { progress: Number(stage[1]), message: stage[2] });
      const fail = line.match(/^FAIL (.+)$/);
      if (fail) failure = fail[1];
    }
  });
  const timer = setTimeout(() => { failure = 'обработка заняла слишком долго'; child.kill('SIGKILL'); }, TIMEOUT_MS());
  let finished = false;
  const finish = (code) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    const seconds = Math.round((Date.now() - started) / 1000);
    let result = null;
    try { result = JSON.parse(fs.readFileSync(path.join(out, 'house.json'), 'utf8')); } catch { /* нет результата */ }
    if (code === 0 && result) {
      update(id, { status: 'ready', progress: 1, message: 'Макет готов', result, readyAt: new Date().toISOString(), seconds });
      record({ kind: 'houseScan', usd: Number(result?.roof?.byPhoto?.cost || 0), calls: result?.roof?.byPhoto ? 1 : 0, credits: 0, ok: true, seconds });
      console.log(`[house] скан ${id} готов за ${seconds} с: ${result.footprint?.gableWidth?.value}×${result.footprint?.length?.value} м`);
    } else {
      const reason = failure || (code === 137 || code === null ? 'не хватило памяти сервера' : 'ошибка обработки');
      // Не получилось — кредиты за обмер возвращаются.
      const failedMeta = hooks.load(id);
      if (failedMeta?.credits) { billing.refund(failedMeta.installId, 'houseScan', failedMeta.credits); update(id, { credits: 0, refunded: failedMeta.credits }); }
      update(id, { status: 'failed', progress: null, message: `Не удалось собрать макет: ${reason}. Попробуйте снять дом ещё раз — медленнее и со всех сторон.`, seconds });
      console.warn(`[house] скан ${id}: код ${code}, ${reason}\n${tail.split('\n').slice(-8).join('\n')}`);
    }
    running = null;
    setImmediate(next);
  };
  child.on('close', finish);
  child.on('error', (error) => {
    failure = `обработчик не запустился (${error.code || error.message})`;
    finish(-1);
  });
}
