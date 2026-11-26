// Учёт расходов на ИИ по функциям: каждая платная функция пишет строку в data/costs.log
// {t, kind, usd, calls, credits, estimated}. Отчёт: node scripts/cost-report.mjs [дней].
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { newMeter, withCost } from './util.js';

const file = () => path.join(config.dataDir, 'costs.log');

export function record(entry) {
  try {
    fs.mkdirSync(config.dataDir, { recursive: true });
    fs.appendFileSync(file(), `${JSON.stringify({ t: new Date().toISOString(), ...entry })}\n`);
  } catch { /* учёт не должен ломать ответ */ }
}

/** Выполняет `fn`, считая стоимость всех вызовов ИИ внутри (usage.cost OpenRouter), и пишет строку учёта. */
export async function metered(kind, credits, fn) {
  const meter = newMeter();
  let ok = false;
  try {
    const result = await withCost(meter, fn);
    ok = true;
    return result;
  } finally {
    record({ kind, usd: Number(meter.total.toFixed(5)), calls: meter.calls, credits: credits || 0, ok, estimated: Boolean(meter.estimated) });
  }
}
