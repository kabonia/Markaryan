// Picture engines through the server, against fake OpenRouter, OpenAI, Black Forest Labs and Yandex APIs.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';

const FAKE = 18_821, PORT = 18_822, PORT_YANDEX = 18_823;
const headers = { 'X-Install-ID': 'a1b2c3d4e5f60718293a', 'Content-Type': 'application/json' };
const seen = [];
const PNG = Buffer.from('fake-image').toString('base64');
const reference = 'R'.repeat(2000);

function fakeAPIs() {
  return http.createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const raw = Buffer.concat(chunks).toString('utf8');
    let body = {};
    try { body = raw ? JSON.parse(raw) : {}; } catch { body = { multipart: raw }; }
    seen.push({ url: req.url, headers: req.headers, body });
    const json = (status, value) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(value)); };

    if (req.url === '/or/images') {
      if (body.model === 'google/broken-image') return json(502, { error: { code: 502, message: 'upstream down' } });
      return json(200, { created: 1, data: [{ b64_json: PNG, media_type: 'image/png' }] });
    }
    if (req.url === '/oa/images/edits' || req.url === '/oa/images/generations') return json(200, { data: [{ b64_json: PNG }] });
    if (req.url === '/bfl/flux-3-image') return json(200, { id: 'task-1', polling_url: `http://127.0.0.1:${FAKE}/bfl/get_result?id=task-1` });
    if (req.url.startsWith('/bfl/get_result')) {
      const polls = seen.filter((s) => s.url.startsWith('/bfl/get_result')).length;
      return json(200, polls < 2 ? { status: 'Pending' } : { status: 'Ready', result: { sample: `http://127.0.0.1:${FAKE}/bfl/sample.jpg` } });
    }
    if (req.url === '/bfl/sample.jpg') { res.end(Buffer.from('fake-image')); return; }
    if (req.url === '/ya/images/generations') return json(200, { data: [{ b64_json: PNG }] });
    return json(404, {});
  }).listen(FAKE);
}

function startServer(port, env) {
  const child = spawn(process.execPath, ['src/index.js'], {
    env: { ...process.env, PORT: String(port), DATA_DIR: `./data-test-images-${port}`, GIGACHAT_AUTH_KEY: '', OPENROUTER_API_KEY: '', OPENAI_API_KEY: '', BFL_API_KEY: '', YANDEX_API_KEY: '', ...env },
    stdio: 'pipe',
  });
  return { child, ready: new Promise((resolve) => child.stdout.once('data', resolve)) };
}

test('picture engines through the server', async (t) => {
  const fake = fakeAPIs();
  const server = startServer(PORT, {
    OPENROUTER_API_KEY: 'sk-or-test', OPENROUTER_BASE: `http://127.0.0.1:${FAKE}/or`,
    OPENROUTER_IMAGE_MODELS: 'google/broken-image,google/gemini-3-pro-image,black-forest-labs/flux-3-image',
    OPENAI_API_KEY: 'sk-test', OPENAI_BASE: `http://127.0.0.1:${FAKE}/oa`,
    BFL_API_KEY: 'bfl-test', BFL_BASE: `http://127.0.0.1:${FAKE}/bfl`, BFL_POLL_MS: '20',
    IMAGE_ENGINES: 'openrouter,openai,bfl', IMAGE_RESOLUTION: '2k',
  });
  t.after(() => { server.child.kill(); fake.close(); });
  await server.ready;
  const base = `http://127.0.0.1:${PORT}`;
  const post = (path, body) => fetch(`${base}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });

  // Engines in the configured order; old apps still see "flux" and "gpt".
  const caps = await (await fetch(`${base}/v1/ai/capabilities`, { headers })).json();
  assert.deepEqual(caps.imageEngines.map((e) => e.id), [
    'openrouter:google/broken-image', 'openrouter:google/gemini-3-pro-image', 'openrouter:black-forest-labs/flux-3-image',
    'openai:gpt-image-2.6-sunburst', 'bfl:flux-3-image',
  ]);
  assert.equal(caps.imageEngines[1].title, 'Nano Banana Pro');
  assert.deepEqual(caps.imageEdit, ['flux', 'gpt']);
  assert.equal(caps.imageGenerate, true);

  // "auto": the first engine fails, the next one answers; the reference goes as a data URL.
  let r = await (await post('/v1/ai/image-edit', { image: reference, prompt: 'фотореализм', engine: 'auto', aspectRatio: '4:3' })).json();
  assert.equal(r.image, PNG);
  assert.equal(r.engine, 'openrouter:google/gemini-3-pro-image');
  assert.equal(r.title, 'Nano Banana Pro');
  const orCall = seen.filter((s) => s.url === '/or/images').at(-1);
  assert.equal(orCall.headers.authorization, 'Bearer sk-or-test');
  assert.equal(orCall.body.model, 'google/gemini-3-pro-image');
  assert.equal(orCall.body.resolution, '2K');
  assert.equal(orCall.body.aspect_ratio, '4:3');
  assert.match(orCall.body.input_references[0].image_url.url, /^data:image\/jpeg;base64,RRRR/);

  // A chosen engine: only that one (owner comparison). OpenAI edits get the reference as a file.
  r = await (await post('/v1/ai/image-edit', { image: reference, prompt: 'фотореализм', engine: 'openai:gpt-image-2.6-sunburst' })).json();
  assert.equal(r.engine, 'openai:gpt-image-2.6-sunburst');
  const oaCall = seen.filter((s) => s.url === '/oa/images/edits').at(-1);
  assert.equal(oaCall.headers.authorization, 'Bearer sk-test');
  assert.match(oaCall.body.multipart, /name="model"\r\n\r\ngpt-image-2.6-sunburst/);
  assert.match(oaCall.body.multipart, /name="image\[\]"; filename="render.jpg"/);

  // FLUX 3 directly: reference in `images`, no web grounding, result polled and downloaded.
  r = await (await post('/v1/ai/image-edit', { image: reference, prompt: 'фотореализм', engine: 'bfl:flux-3-image' })).json();
  assert.equal(r.image, PNG);
  const bflCall = seen.find((s) => s.url === '/bfl/flux-3-image');
  assert.equal(bflCall.headers['x-key'], 'bfl-test');
  assert.deepEqual(bflCall.body.images, [reference]);
  assert.equal(bflCall.body.grounding, false);
  assert.equal(bflCall.body.resolution, 'match_input');

  // Old app versions ask for "flux": the first FLUX engine in order answers.
  r = await (await post('/v1/ai/image-edit', { image: reference, prompt: 'фотореализм', engine: 'flux' })).json();
  assert.equal(r.engine, 'openrouter:black-forest-labs/flux-3-image');

  // An engine that is not set up.
  const missing = await post('/v1/ai/image-edit', { image: reference, prompt: 'x', engine: 'openai:dall-e-2' });
  assert.equal(missing.status, 400);

  // Render models offered in the app: Seedream works with the same key even though the server's list leaves it out.
  assert.deepEqual(caps.renderModels.map((m) => m.id), [
    'openrouter:google/gemini-3-pro-image', 'openrouter:openai/gpt-image-2.6-sunburst', 'openrouter:bytedance-seed/seedream-5-0-pro',
  ]);
  assert.deepEqual(caps.renderModels.map((m) => m.title), ['Nano Banana Pro', 'GPT Image 2.6 Sunburst', 'Seedream 5.0 Pro']);
  r = await (await post('/v1/ai/image-edit', { image: reference, prompt: 'фотореализм', prefer: 'openrouter:bytedance-seed/seedream-5-0-pro' })).json();
  assert.equal(r.engine, 'openrouter:bytedance-seed/seedream-5-0-pro');
  assert.equal(r.title, 'Seedream 5.0 Pro');
  let picked = seen.filter((s) => s.url === '/or/images').at(-1);
  assert.equal(picked.body.model, 'bytedance-seed/seedream-5-0-pro');
  assert.equal(picked.body.resolution, '2K');
  assert.match(picked.body.input_references[0].image_url.url, /^data:image\/jpeg;base64,RRRR/);
  // A picked engine from the server's own list goes first, too.
  r = await (await post('/v1/ai/image-edit', { image: reference, prompt: 'фотореализм', prefer: 'openai:gpt-image-2.6-sunburst' })).json();
  assert.equal(r.engine, 'openai:gpt-image-2.6-sunburst');
  // An unknown pick is ignored: the engines in order (the broken one, then Nano Banana Pro).
  r = await (await post('/v1/ai/image-edit', { image: reference, prompt: 'фотореализм', prefer: 'openrouter:someone/expensive-model' })).json();
  assert.equal(r.engine, 'openrouter:google/gemini-3-pro-image');
  assert.equal(seen.filter((s) => s.url === '/or/images' && s.body.model === 'someone/expensive-model').length, 0);
  // The owner's comparison can run a choice that is not in the server's list.
  r = await (await post('/v1/ai/image-edit', { image: reference, prompt: 'фотореализм', engine: 'openrouter:bytedance-seed/seedream-5-0-pro' })).json();
  assert.equal(r.engine, 'openrouter:bytedance-seed/seedream-5-0-pro');

  // A picture by description goes to the same engines, without a reference.
  r = await (await post('/v1/ai/image', { prompt: 'дом у моря' })).json();
  assert.equal(r.engine, 'openrouter:google/gemini-3-pro-image');
  assert.equal(seen.filter((s) => s.url === '/or/images').at(-1).body.input_references, undefined);
  // …and the model picked in the app draws it first.
  r = await (await post('/v1/ai/image', { prompt: 'дом у моря', prefer: 'openrouter:bytedance-seed/seedream-5-0-pro' })).json();
  assert.equal(r.engine, 'openrouter:bytedance-seed/seedream-5-0-pro');
});

test('pictures by description fall back to Alice AI ART', async (t) => {
  const fake = fakeAPIs();
  const server = startServer(PORT_YANDEX, {
    AI_PROVIDERS: 'yandex', YANDEX_API_KEY: 'k', YANDEX_FOLDER_ID: 'b1folder', YANDEX_BASE: `http://127.0.0.1:${FAKE}/missing,http://127.0.0.1:${FAKE}/ya`,
  });
  t.after(() => { server.child.kill(); fake.close(); });
  await server.ready;
  const base = `http://127.0.0.1:${PORT_YANDEX}`;
  const caps = await (await fetch(`${base}/v1/ai/capabilities`, { headers })).json();
  assert.deepEqual(caps.imageEngines, []);
  assert.deepEqual(caps.renderModels, [], 'nothing to choose without OpenRouter');
  assert.deepEqual(caps.designModels, []);
  assert.equal(caps.imageGenerate, true);
  const r = await (await fetch(`${base}/v1/ai/image`, { method: 'POST', headers, body: JSON.stringify({ prompt: 'д'.repeat(800) }) })).json();
  assert.equal(r.image, PNG);
  const call = seen.filter((s) => s.url === '/ya/images/generations').at(-1);
  assert.equal(call.headers.authorization, 'Api-Key k');
  assert.equal(call.headers['openai-project'], 'b1folder');
  assert.equal(call.body.model, 'art://b1folder/aliceai-image-art-3.0');
  assert.equal(call.body.prompt.length, 500);
});
