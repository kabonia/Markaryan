import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';

const PORT = 18_765;
const headers = { 'X-Install-ID': '0123456789abcdef0123', 'Content-Type': 'application/json' };

test('server: health, auth headers, no providers configured', async (t) => {
  const child = spawn(process.execPath, ['src/index.js'], { env: { ...process.env, PORT: String(PORT), DATA_DIR: './data-test', GIGACHAT_AUTH_KEY: '', YANDEX_API_KEY: '', OPENROUTER_API_KEY: '' }, stdio: 'pipe' });
  t.after(() => child.kill());
  await new Promise((resolve) => child.stdout.once('data', resolve));
  const base = `http://127.0.0.1:${PORT}`;
  assert.equal((await fetch(`${base}/health`)).status, 200);
  assert.equal((await fetch(`${base}/v1/ai/capabilities`)).status, 400); // no install id
  const caps = await (await fetch(`${base}/v1/ai/capabilities`, { headers })).json();
  assert.equal(caps.chat, false);
  const chat = await fetch(`${base}/v1/ai/chat`, { method: 'POST', headers, body: JSON.stringify({ messages: [{ role: 'user', text: 'Привет' }] }) });
  assert.equal(chat.status, 503);
  assert.match((await chat.json()).error, /не настроен/);
});

test('server: скан дома частями с докачкой', async (t) => {
  const port = PORT + 3;
  const child = spawn(process.execPath, ['src/index.js'], { env: { ...process.env, PORT: String(port), DATA_DIR: './data-test', OPENROUTER_API_KEY: '', HOUSE_WORKER: 'off' }, stdio: 'pipe' });
  t.after(() => child.kill());
  await new Promise((resolve) => child.stdout.once('data', resolve));
  t.after(async () => (await import('node:fs')).rmSync('./data-test/house-scans', { recursive: true, force: true }));
  const base = `http://127.0.0.1:${port}/v1/ai/house/scans`;
  const data = Buffer.alloc(9 * 1024 * 1024, 7);
  const sha256 = (await import('node:crypto')).createHash('sha256').update(data).digest('hex');
  const scan = await (await fetch(base, { method: 'POST', headers, body: JSON.stringify({ bytes: data.length, sha256, manifest: { frames: 3, lidar: true } }) })).json();
  assert.equal(scan.parts, 2);
  // Сначала вторая часть, потом первая — порядок не важен.
  for (const i of [1, 0]) {
    const chunk = data.subarray(i * scan.partBytes, (i + 1) * scan.partBytes);
    const r = await fetch(`${base}/${scan.id}/parts/${i}`, { method: 'PUT', headers: { ...headers, 'Content-Type': 'application/octet-stream' }, body: chunk });
    assert.equal(r.status, 200);
  }
  const done = await (await fetch(`${base}/${scan.id}/complete`, { method: 'POST', headers, body: '{}' })).json();
  assert.equal(done.status, 'queued');
  const other = await fetch(`${base}/${scan.id}`, { headers: { ...headers, 'X-Install-ID': 'ffffffffffffffffffff' } });
  assert.equal(other.status, 404);
  // Чужой не удалит, владелец — удалит.
  assert.equal((await fetch(`${base}/${scan.id}`, { method: 'DELETE', headers: { ...headers, 'X-Install-ID': 'ffffffffffffffffffff' } })).status, 404);
  assert.equal((await fetch(`${base}/${scan.id}`, { method: 'DELETE', headers })).status, 200);
  assert.equal((await fetch(`${base}/${scan.id}`, { headers })).status, 404);
});
