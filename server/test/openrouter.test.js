// OpenRouter through the server, against a fake OpenRouter: fallbacks, strict JSON schema, streaming, errors.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { config } from '../src/config.js';
import * as openrouter from '../src/providers/openrouter.js';

const { strictSchema } = openrouter;

const FAKE = 18_811, PORT = 18_812;
const headers = { 'X-Install-ID': 'fedcba9876543210fedc', 'Content-Type': 'application/json' };
const seen = [];

function fakeOpenRouter() {
  return http.createServer(async (req, res) => {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    const body = raw ? JSON.parse(raw) : {};
    seen.push({ url: req.url, headers: req.headers, body });
    if (req.url === '/ya/chat/completions') { res.end(JSON.stringify({ choices: [{ message: { content: 'yandex-answer' } }] })); return; }
    if (req.url !== '/or/chat/completions') { res.writeHead(404); res.end('{}'); return; }
    const last = body.messages.at(-1);
    const text = typeof last.content === 'string' ? last.content : last.content.find((part) => part.type === 'text').text;
    if (text === 'NOCREDIT') { res.writeHead(402); res.end(JSON.stringify({ error: { code: 402, message: 'Insufficient credits' } })); return; }
    if (body.response_format?.type === 'json_schema' && body.response_format.json_schema.name === 'loose_only') {
      res.writeHead(400); res.end(JSON.stringify({ error: { code: 400, message: 'schema not supported' } })); return;
    }
    if (body.response_format) {
      res.end(JSON.stringify({ model: body.model, choices: [{ finish_reason: 'stop', message: { content: '```json\n{"title":"Студия","items":[{"name":"Диван"}]}\n```' } }] }));
      return;
    }
    if (body.stream) {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      res.write(': OPENROUTER PROCESSING\n\n');
      res.write('data: {"choices":[{"delta":{"content":"Здрав"}}]}\n\n');
      if (text === 'BREAK') { res.end('data: {"error":{"code":502,"message":"Provider disconnected mid-stream"}}\n\n'); return; }
      res.write('data: {"choices":[{"delta":{"content":"ствуйте"}}]}\n\n');
      res.end('data: [DONE]\n\n');
      return;
    }
    res.end(JSON.stringify({ model: body.model, choices: [{ finish_reason: 'stop', message: { content: `openrouter:${Array.isArray(last.content) ? 'with-photo' : 'text'}` } }] }));
  }).listen(FAKE);
}

test('strict schema closes every object and requires every property', () => {
  const schema = strictSchema({ type: 'object', properties: { items: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, kind: { type: 'string', enum: ['sofa', 'bed'] } } } }, title: { type: 'string' } } });
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required, ['items', 'title']);
  assert.equal(schema.properties.items.items.additionalProperties, false);
  assert.deepEqual(schema.properties.items.items.required, ['name', 'kind']);
  assert.deepEqual(schema.properties.items.items.properties.kind.enum, ['sofa', 'bed']);
});

test('OpenRouter through the server', async (t) => {
  const fake = fakeOpenRouter();
  const child = spawn(process.execPath, ['src/index.js'], {
    env: { ...process.env, PORT: String(PORT), DATA_DIR: './data-test3', AI_PROVIDERS: 'openrouter,yandex', GIGACHAT_AUTH_KEY: '',
      OPENROUTER_API_KEY: 'sk-or-test', OPENROUTER_BASE: `http://127.0.0.1:${FAKE}/or`, OPENROUTER_EFFORT: '',
      OPENROUTER_MODELS: 'anthropic/claude-opus-5.5, openai/gpt-6.2-astra ,google/gemini-4-carbon',
      YANDEX_API_KEY: 'k', YANDEX_FOLDER_ID: 'b1folder', YANDEX_BASE: `http://127.0.0.1:${FAKE}/ya` },
    stdio: 'pipe',
  });
  t.after(() => { child.kill(); fake.close(); });
  await new Promise((resolve) => child.stdout.once('data', resolve));
  const base = `http://127.0.0.1:${PORT}`;
  const post = (path, body) => fetch(`${base}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });
  const lastCall = () => seen.filter((s) => s.url === '/or/chat/completions').at(-1);

  // Plain answer: the first model answers, the rest are OpenRouter fallbacks; reasoning stays on the server side.
  let r = await (await post('/v1/ai/chat', { system: 's', messages: [{ role: 'user', text: 'Привет' }] })).json();
  assert.equal(r.text, 'openrouter:text');
  let call = lastCall();
  assert.equal(call.headers.authorization, 'Bearer sk-or-test');
  assert.equal(call.body.model, 'anthropic/claude-opus-5.5');
  assert.deepEqual(call.body.models, undefined, 'OpenRouter-only fields are not sent to another gateway');
  assert.equal(call.body.messages[0].role, 'system');

  // Photo goes as a data URL after the text.
  r = await (await post('/v1/ai/chat', { messages: [{ role: 'user', text: 'Что на фото', image: 'A'.repeat(200) }] })).json();
  assert.equal(r.text, 'openrouter:with-photo');
  assert.match(lastCall().body.messages[0].content[1].image_url.url, /^data:image\/jpeg;base64,AAAA/);

  // Streaming: keep-alive comments are skipped.
  const stream = await (await post('/v1/ai/chat', { stream: true, messages: [{ role: 'user', text: 'Привет' }] })).text();
  assert.match(stream, /"delta":"Здрав"/);
  assert.match(stream, /"delta":"ствуйте"/);
  assert.match(stream, /"done":true/);

  // A break in the middle of the answer is reported, not hidden.
  const broken = await (await post('/v1/ai/chat', { stream: true, messages: [{ role: 'user', text: 'BREAK' }] })).text();
  assert.match(broken, /"delta":"Здрав"/);
  assert.match(broken, /"error":"ИИ прервал ответ/);

  // Structured JSON: strict schema, only endpoints that enforce it, code fences removed.
  const schema = { type: 'object', properties: { title: { type: 'string' }, items: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' } } } } } };
  r = await (await post('/v1/ai/json', { name: 'design proposal', schema, maxTokens: 16000, messages: [{ role: 'user', text: 'план' }] })).json();
  assert.deepEqual(r.json, { title: 'Студия', items: [{ name: 'Диван' }] });
  call = lastCall();
  assert.equal(call.body.response_format.type, 'json_schema');
  assert.equal(call.body.response_format.json_schema.name, 'design_proposal');
  assert.equal(call.body.response_format.json_schema.strict, true);
  assert.equal(call.body.response_format.json_schema.schema.properties.items.items.additionalProperties, false);
  assert.equal(call.body.max_tokens, 32000, 'reply budget on top of the reasoning');

  // A route that rejects the schema: plain JSON is asked and repaired.
  r = await (await post('/v1/ai/json', { name: 'loose_only', schema, messages: [{ role: 'user', text: 'план' }] })).json();
  assert.deepEqual(r.json, { title: 'Студия', items: [{ name: 'Диван' }] });
  assert.equal(lastCall().body.response_format.type, 'json_object');

  // The model picked in the app answers first and the server says which model answered. On another gateway only
  // its own configured models can be picked; anything else is ignored.
  r = await (await post('/v1/ai/json', { name: 'design', schema, model: 'openai/gpt-6.2-astra', messages: [{ role: 'user', text: 'план' }] })).json();
  assert.equal(lastCall().body.model, 'openai/gpt-6.2-astra');
  assert.equal(r.model, 'openai/gpt-6.2-astra');
  r = await (await post('/v1/ai/json', { name: 'design', schema, model: 'anthropic/claude-sonnet-5.5', messages: [{ role: 'user', text: 'план' }] })).json();
  assert.equal(lastCall().body.model, 'anthropic/claude-opus-5.5');
  assert.equal(r.model, 'anthropic/claude-opus-5.5');

  // No credits on OpenRouter: the next provider (Yandex) answers.
  r = await (await post('/v1/ai/chat', { messages: [{ role: 'user', text: 'NOCREDIT' }] })).json();
  assert.equal(r.text, 'yandex-answer');

  // Capabilities: OpenRouter is listed; pictures still come from Yandex.
  const caps = await (await fetch(`${base}/v1/ai/capabilities`, { headers })).json();
  assert.deepEqual(caps.providers, ['openrouter', 'yandex']);
  assert.equal(caps.imageGenerate, true);
  assert.deepEqual(caps.designModels, [], 'model ids of openrouter.ai are not offered for another gateway');
});

test('OpenRouter-only fields go to openrouter.ai', async (t) => {
  const original = { fetch: globalThis.fetch, base: config.openrouter.base, models: config.openrouter.models, effort: config.openrouter.effort };
  const sent = [];
  globalThis.fetch = async (url, options) => {
    const body = JSON.parse(options.body);
    sent.push({ url, body });
    return new Response(JSON.stringify({ model: body.model, choices: [{ finish_reason: 'stop', message: { content: '{"ok":true}' } }] }), { status: 200 });
  };
  t.after(() => {
    globalThis.fetch = original.fetch;
    Object.assign(config.openrouter, { base: original.base, models: original.models, effort: original.effort, dataCollection: '' });
  });
  Object.assign(config.openrouter, { base: 'https://openrouter.ai/api/v1', models: ['anthropic/claude-opus-5.5', 'openai/gpt-6.2-astra', 'google/gemini-4-carbon'], effort: '', dataCollection: 'deny' });

  assert.equal(await openrouter.chat({ system: 's', messages: [{ role: 'user', text: 'x' }] }), '{"ok":true}');
  let call = sent.at(-1);
  assert.equal(call.url, 'https://openrouter.ai/api/v1/chat/completions');
  assert.equal(call.body.model, 'anthropic/claude-opus-5.5');
  assert.deepEqual(call.body.models, ['openai/gpt-6.2-astra', 'google/gemini-4-carbon']);
  assert.deepEqual(call.body.reasoning, { effort: 'medium', exclude: true });
  assert.deepEqual(call.body.provider, { data_collection: 'deny' });

  const schema = { type: 'object', properties: { ok: { type: 'boolean' } } };
  assert.deepEqual(await openrouter.json({ system: 's', messages: [{ role: 'user', text: 'x' }], schema, name: 'result' }), { ok: true });
  call = sent.at(-1);
  assert.deepEqual(call.body.reasoning, { effort: 'high', exclude: true });
  assert.deepEqual(call.body.provider, { require_parameters: true, data_collection: 'deny' });

  // A design model picked in the app: first, the configured chain behind it (at most three fallbacks).
  const meta = {};
  assert.deepEqual(await openrouter.json({ system: 's', messages: [{ role: 'user', text: 'x' }], schema, model: 'anthropic/claude-sonnet-5.5', meta }), { ok: true });
  call = sent.at(-1);
  assert.equal(call.body.model, 'anthropic/claude-sonnet-5.5');
  assert.deepEqual(call.body.models, ['anthropic/claude-opus-5.5', 'openai/gpt-6.2-astra', 'google/gemini-4-carbon']);
  assert.equal(meta.model, 'anthropic/claude-sonnet-5.5', 'the model that answered is reported');
  assert.deepEqual(openrouter.modelOrder('google/gemini-4-carbon'), ['google/gemini-4-carbon', 'anthropic/claude-opus-5.5', 'openai/gpt-6.2-astra']);
  assert.deepEqual(openrouter.modelOrder('someone/expensive-model'), ['anthropic/claude-opus-5.5', 'openai/gpt-6.2-astra', 'google/gemini-4-carbon'], 'only allowed models can be picked');
  assert.deepEqual(openrouter.modelOrder(undefined), ['anthropic/claude-opus-5.5', 'openai/gpt-6.2-astra', 'google/gemini-4-carbon']);
});

test('design models offered to the app', (t) => {
  const original = { base: config.openrouter.base, apiKey: config.openrouter.apiKey };
  t.after(() => Object.assign(config.openrouter, original));
  Object.assign(config.openrouter, { base: 'https://openrouter.ai/api/v1', apiKey: 'sk-or-test' });
  assert.deepEqual(openrouter.designChoices().map((m) => m.title), ['Claude Opus 5.5', 'Claude Sonnet 5.5', 'GPT‑6.2 Astra', 'Gemini 4 Carbon']);
  assert.equal(openrouter.designChoices()[1].id, 'anthropic/claude-sonnet-5.5');
  Object.assign(config.openrouter, { apiKey: '' });
  assert.deepEqual(openrouter.designChoices(), []);
});
