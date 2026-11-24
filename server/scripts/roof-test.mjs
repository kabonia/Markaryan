#!/usr/bin/env node
// Этап 0 «Дом снаружи»: прогон «крыша по фото» из командной строки.
//   node scripts/roof-test.mjs фото1.jpg фото2.jpg … [--width 8.2] [--eave 3.1] [--notes "…"] [--effort high]
// Ключ OpenRouter — из окружения (OPENROUTER_API_KEY), как у сервера. Фото уменьшаются до 1600 px по длинной
// стороне, если доступен sharp (SHARP_DIR=/путь/к/node_modules/..), иначе уходят как есть.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { analyze } from '../src/roof.js';

const args = process.argv.slice(2);
const files = [];
const opts = {};
for (let i = 0; i < args.length; i += 1) {
  if (args[i].startsWith('--')) { opts[args[i].slice(2)] = args[i + 1]; i += 1; } else files.push(args[i]);
}
if (!files.length) { console.error('Укажите 1–6 фото дома (JPEG).'); process.exit(1); }

let sharp = null;
try { sharp = createRequire(`${process.env.SHARP_DIR || process.cwd()}/`)('sharp'); } catch { /* без уменьшения */ }

const photos = [];
for (const file of files) {
  let data = fs.readFileSync(file);
  if (sharp) data = await sharp(data).rotate().resize(1600, 1600, { fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 85 }).toBuffer();
  photos.push(data.toString('base64'));
}
const known = { gableWidth: opts.width, eaveHeight: opts.eave, ridgeHeight: opts.ridge };
const result = await analyze({ photos, known, notes: opts.notes, effort: opts.effort, model: opts.model });
const label = { measured: 'измерено', photo: 'по фото', assumption: 'предположение' };
const show = (name, v, unit) => console.log(`${name}: ${v.value ?? '—'}${v.value != null ? unit : ''}  [${label[v.source]}; ${v.note}]`);
console.log(`\nКрыша: ${result.roofTypeRu} (${result.roofType}), уверенность ${result.typeConfidence}`);
console.log(`Покрытие: ${result.covering}; цвет: ${result.color}`);
show('Уклон', result.pitchDeg, '°');
show('Высота конька', result.ridgeHeight, ' м');
show('Высота карниза', result.eaveHeight, ' м');
show('Ширина торца', result.gableWidth, ' м');
show('Свес', result.overhang, ' м');
console.log('Детали:', result.details.map((d) => `${d.ru}${d.count > 1 ? ` ×${d.count}` : ''} [${label[d.source]}]`).join('; ') || '—');
console.log('Не видно:', result.hidden.join('; ') || '—');
console.log('Доснять:', result.advice || '—');
console.log('Геометрия по фото:', JSON.stringify(result.geometry));
console.log(`Модель: ${result.model}; стоимость: $${result.cost}`);
if (opts.json) fs.writeFileSync(opts.json, JSON.stringify(result, null, 2));
