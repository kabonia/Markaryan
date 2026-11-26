#!/usr/bin/env node
// Сводка расходов на ИИ по функциям из data/costs.log: вызовы, $ всего, средний и максимальный ₽ за вызов, кредиты.
//   node scripts/cost-report.mjs [дней=7] [курс ₽ за $=90]
import fs from 'node:fs';
import path from 'node:path';

const days = Number(process.argv[2] || 7);
const rate = Number(process.argv[3] || 90);
const file = path.resolve(process.env.DATA_DIR || 'data', 'costs.log');
const since = Date.now() - days * 86_400_000;
const lines = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\n').filter(Boolean) : [];
const rows = lines.map((line) => { try { return JSON.parse(line); } catch { return null; } }).filter((r) => r && Date.parse(r.t) >= since);

const byKind = {};
for (const r of rows) {
  const k = (byKind[r.kind] ||= { calls: 0, usd: 0, credits: 0, max: 0, estimated: 0, failed: 0 });
  k.calls += 1;
  k.usd += r.usd || 0;
  k.credits += r.credits || 0;
  k.max = Math.max(k.max, r.usd || 0);
  if (r.estimated) k.estimated += 1;
  if (r.ok === false) k.failed += 1;
}

console.log(`Расходы на ИИ за ${days} дн. (курс ${rate} ₽/$), записей: ${rows.length}`);
console.log(['функция'.padEnd(14), 'вызовов'.padStart(7), '$ всего'.padStart(9), '₽ средн.'.padStart(9), '₽ макс.'.padStart(8), 'кредитов'.padStart(9), ' пометки'].join(' '));
let total = 0;
for (const [kind, k] of Object.entries(byKind).sort((a, b) => b[1].usd - a[1].usd)) {
  total += k.usd;
  const notes = [k.estimated ? `оценка ${k.estimated}` : '', k.failed ? `ошибок ${k.failed}` : ''].filter(Boolean).join(', ');
  console.log([kind.padEnd(14), String(k.calls).padStart(7), k.usd.toFixed(3).padStart(9), (k.usd / k.calls * rate).toFixed(2).padStart(9),
    (k.max * rate).toFixed(1).padStart(8), String(k.credits).padStart(9), ` ${notes}`].join(' '));
}
console.log(`Итого: $${total.toFixed(3)} ≈ ${(total * rate).toFixed(0)} ₽`);
