#!/usr/bin/env node
// Daily market price collection (run by the artstroy-prices.timer).
// For every city in market-observations/*.csv, plus up to NEW_CITIES_PER_DAY cities users asked for
// without a price book, asks Claude (headless, web search only) for current offers, validates each row,
// appends it with today's date and rebuilds market-prices/<city>.json over a rolling MAX_AGE_DAYS window.
//   node scripts/collect-prices.mjs            — all cities
//   node scripts/collect-prices.mjs sochi      — one city file
//   DRY_RUN=1 node scripts/collect-prices.mjs  — print the prompts only
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { normalizePlace } from '../src/market.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const obsDir = path.join(root, 'market-observations');
const dataDir = process.env.DATA_DIR || path.join(root, 'data');
const claudeBin = process.env.CLAUDE_BIN || 'claude';
const model = process.env.COLLECT_MODEL || 'sonnet';
const newCitiesPerDay = Number.parseInt(process.env.NEW_CITIES_PER_DAY || '2', 10);
const maxAgeDays = process.env.MAX_AGE_DAYS || '30';
const today = new Date().toISOString().slice(0, 10);
const template = JSON.parse(fs.readFileSync(path.join(root, 'market-prices/_lines.template'), 'utf8')).lines;
const known = new Map(template.map((l) => [l.code, l]));
const log = (...a) => console.log(new Date().toISOString(), ...a);

const translit = (s) => normalizePlace(s).replace(/[а-яё]/g, (ch) => ({ а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'e', ж: 'zh', з: 'z', и: 'i', й: 'y', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'h', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sch', ъ: '', ы: 'y', ь: '', э: 'e', ю: 'yu', я: 'ya' })[ch] ?? ch)
  .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

function readMeta(file) {
  const meta = {};
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^#\s*(\w+)\s*=\s*(.*)$/);
    if (m) meta[m[1]] = m[2].trim();
  }
  return meta;
}

/** Existing city files plus the most requested cities that have no file yet. */
function citiesToCollect(only) {
  fs.mkdirSync(obsDir, { recursive: true });
  const files = fs.readdirSync(obsDir).filter((f) => f.endsWith('.csv'));
  if (only) return files.filter((f) => f === `${only}.csv`).map((f) => path.join(obsDir, f));
  const covered = new Set(files.map((f) => normalizePlace(readMeta(path.join(obsDir, f)).city)));
  let requested = {};
  try { requested = JSON.parse(fs.readFileSync(path.join(dataDir, 'requested-cities.json'), 'utf8')); } catch { /* none yet */ }
  const fresh = Object.values(requested).filter((c) => !covered.has(normalizePlace(c.city)))
    .sort((a, b) => b.count - a.count).slice(0, newCitiesPerDay);
  for (const c of fresh) {
    const slug = translit(c.city) || `city-${Date.now()}`;
    const meta = [`# city=${c.city}`, `# region=${c.region || ''}`, c.lat != null ? `# lat=${c.lat}` : '', c.lon != null ? `# lon=${c.lon}` : '', '# scope=city', 'code,kind,price,source,url,date'].filter(Boolean);
    fs.writeFileSync(path.join(obsDir, `${slug}.csv`), meta.join('\n') + '\n');
    files.push(`${slug}.csv`);
    log(`новый город: ${c.city} (запросов: ${c.count})`);
  }
  return files.map((f) => path.join(obsDir, f));
}

function prompt(meta, lines) {
  const place = meta.region ? `${meta.city} (${meta.region})` : meta.city;
  const list = lines.map((l) => `- ${l.code} | ${l.section}: ${l.title} | единица: ${l.unit}`).join('\n');
  return `Ты собираешь реальные рыночные цены для строительной сметы. Город: ${place}. Дата: ${today}.

Найди веб-поиском актуальные предложения продавцов и исполнителей ЭТОГО города или ближайших городов его региона:
заводы и базы (бетон, щебень, металлопрокат), строительные магазины и маркетплейсы, сервисы аренды техники,
биржи мастеров (Профи.ру, Яндекс Услуги, YouDo), прайсы строительных компаний на работы.

Позиции (код | название | единица):
${list}

Для каждой позиции дай отдельно цену материала (kind=material) и цену работы (kind=labor), где это применимо, в рублях ЗА ЕДИНИЦУ позиции.
Пересчитывай единицы: тонна → кг, упаковка → м², цена «за м² дома» для инженерии и отделки — по прайсам «за м²».
Правила:
- одна строка — одно реальное предложение с прямой ссылкой; не выдумывай цены и ссылки;
- пропускай страницы с ценами прошлых лет, очевидно устаревшие прайсы, объявления «от 1 ₽», акции «−70%», другие регионы;
- если по позиции нет надёжных данных, пропусти её;
- не больше 6 предложений на позицию, не больше 40 поисковых запросов всего.

Ответ: ТОЛЬКО строки CSV без заголовка и без пояснений, формат:
code,kind,price,source,url
где price — число без пробелов и знака ₽, source — короткое название продавца без запятых.`;
}

function askClaude(text) {
  const run = spawnSync(claudeBin, ['-p', text, '--model', model, '--allowedTools', 'WebSearch', '--output-format', 'text'], {
    encoding: 'utf8', timeout: 30 * 60_000, maxBuffer: 10 * 1024 * 1024, env: process.env,
  });
  if (run.error || run.status !== 0) throw new Error(run.error?.message || run.stderr?.slice(0, 500) || `код ${run.status}`);
  return run.stdout;
}

function validRows(output, existing) {
  const rows = [];
  for (const raw of output.split(/\r?\n/)) {
    // The model often puts commas inside the seller name («М300 В22,5, гранит»): the url is the last field
    // that starts with http, everything between the price and the url is the source.
    const parts = raw.trim().replace(/^`+|`+$/g, '').split(',').map((p) => p.trim().replace(/^"|"$/g, ''));
    if (parts.length < 5) continue;
    const urlIndex = parts.findLastIndex((p) => /^https?:\/\//.test(p));
    if (urlIndex < 4) continue;
    const [code, kind, priceText] = parts;
    const source = parts.slice(3, urlIndex).join(', ');
    const url = parts[urlIndex];
    const price = Number(priceText.replace(/\s/g, '').replace(',', '.'));
    if (!known.has(code) || !['material', 'labor'].includes(kind)) continue;
    if (!Number.isFinite(price) || price <= 0 || price > 10_000_000) continue;
    if (!/^https?:\/\/[^\s]+$/.test(url)) continue;
    const key = `${code}|${kind}|${url}|${today}`;
    if (existing.has(key)) continue;
    existing.add(key);
    rows.push([code, kind, price, source.replace(/[",\n]/g, ' ').slice(0, 80), url, today].join(','));
  }
  return rows;
}

const only = process.argv[2];
const groups = [['house'], ['gazebo'], ['metal']];
let failures = 0;
for (const file of citiesToCollect(only)) {
  const meta = readMeta(file);
  if (!meta.city) { log(`${path.basename(file)}: нет # city=, пропуск`); continue; }
  const existing = new Set(fs.readFileSync(file, 'utf8').split(/\r?\n/).map((l) => { const p = l.split(','); return p.length >= 6 ? `${p[0]}|${p[1]}|${p.slice(4, -1).join(',')}|${p.at(-1)}` : ''; }));
  let added = 0;
  for (const scopes of groups) {
    const lines = template.filter((l) => (l.appliesTo ?? ['house']).some((s) => scopes.includes(s)));
    const text = prompt(meta, lines);
    if (process.env.DRY_RUN) { console.log(text); continue; }
    try {
      const rows = validRows(askClaude(text), existing);
      if (rows.length) fs.appendFileSync(file, (fs.readFileSync(file, 'utf8').endsWith('\n') ? '' : '\n') + rows.join('\n') + '\n');
      added += rows.length;
      log(`${meta.city} / ${scopes.join(',')}: +${rows.length} предложений`);
    } catch (error) { failures++; log(`${meta.city} / ${scopes.join(',')}: ошибка: ${error.message}`); }
  }
  if (process.env.DRY_RUN) continue;
  try {
    const out = execFileSync(process.execPath, [path.join(root, 'scripts/build-price-book.js'), file], { encoding: 'utf8', env: { ...process.env, MAX_AGE_DAYS: maxAgeDays } });
    log(`${meta.city}: добавлено ${added}; ${out.trim()}`);
  } catch (error) { failures++; log(`${meta.city}: прайс не собран: ${error.message}`); }
}
process.exit(failures ? 1 : 0);
