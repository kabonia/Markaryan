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
