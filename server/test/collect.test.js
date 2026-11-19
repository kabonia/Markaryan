import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

test('collect-prices: validates rows from the model, appends with date, rebuilds the book', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'collect-'));
  const fake = path.join(dir, 'fake-claude.sh');
  fs.writeFileSync(fake, `#!/bin/sh
cat <<'OUT'
Вот что нашёл:
concrete,material,6400,Завод А,https://a.example/m300
concrete,material,6500,Завод Б,https://b.example/m350
concrete,material,6300,Завод В,https://c.example/p
concrete,labor,abc,Плохая цена,https://d.example
unknown,material,100,Нет такого кода,https://e.example
rebar,material,50,База,not-a-url
rebar,material,49,База Сочи,https://f.example/a500
concrete,material,6200,sochi.eurobetonplus.ru (М300 В22,5, гранитный щебень),https://g.example/m300
\`\`\`
OUT
`, { mode: 0o755 });
  const city = path.resolve('market-observations/test-collect.csv');
  const book = path.resolve('market-prices/test-collect.json');
  fs.writeFileSync(city, '# city=Тестоград\n# region=Тестовая область\ncode,kind,price,source,url,date\n');
  try {
    execFileSync(process.execPath, ['scripts/collect-prices.mjs', 'test-collect'], { env: { ...process.env, CLAUDE_BIN: fake, DATA_DIR: dir }, encoding: 'utf8' });
    const rows = fs.readFileSync(city, 'utf8').trim().split('\n').filter((l) => !l.startsWith('#') && !l.startsWith('code,'));
    // 3 groups ask the same fake: duplicates of the same url on the same day are kept once.
    assert.equal(rows.length, 5);
    assert.ok(rows.some((r) => r.includes('гранитный щебень') && r.includes('https://g.example/m300')));
    assert.ok(rows.every((r) => r.endsWith(new Date().toISOString().slice(0, 10))));
    const b = JSON.parse(fs.readFileSync(book, 'utf8'));
    assert.equal(b.lines.find((l) => l.code === 'concrete').materialRate, 6350); // median of 6200, 6300, 6400, 6500
    assert.equal(b.lines.find((l) => l.code === 'rebar').materialRate, 49);
  } finally {
    fs.rmSync(city, { force: true }); fs.rmSync(book, { force: true }); fs.rmSync(dir, { recursive: true, force: true });
  }
});
