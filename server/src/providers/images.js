// Pictures: the photoreal version of the exact 3D render (edit by a reference image) and pictures by description.
// Engines come in IMAGE_ENGINES order: OpenRouter image models (Nano Banana Pro, GPT Image, FLUX…) with one key,
// and OpenAI or Black Forest Labs directly. Every address is configurable, so calls can go through a proxy abroad.
// Engine ids look like "openrouter:google/gemini-3-pro-image", "openai:gpt-image-2.6-sunburst", "bfl:flux-3-image".
import { config } from '../config.js';
import { ApiError, request, readJSON, sleep } from '../util.js';

const TITLES = {
  'gemini-3-pro-image': 'Nano Banana Pro',
  'gemini-nano-banana-2.1': 'Nano Banana 2.1',
  'gemini-3.1-flash-image': 'Nano Banana 2',
  'gpt-image-2.6-sunburst': 'GPT Image 2.6 Sunburst',
  'gpt-image-2.6-flare': 'GPT Image 2.6 Flare',
  'gpt-image-2.5-sunburst': 'GPT Image 2.5 Sunburst',
  'gpt-image-2': 'GPT Image 2',
  'flux-3-image': 'FLUX 3',
  'flux-kontext-max': 'FLUX Kontext Max',
  'flux-kontext-pro': 'FLUX Kontext Pro',
  'seedream-5-0-pro': 'Seedream 5.0 Pro',
  'seedream-5-5': 'Seedream 5.5',
};
const title = (model) => TITLES[model.split('/').pop()] || model.split('/').pop();

/** Engines that have keys, in the configured order. */
export function imageEngines() {
  const list = [];
  for (const vendor of config.images.order) {
    if (vendor === 'openrouter' && config.openrouter.apiKey) {
      for (const model of config.openrouter.imageModels) list.push({ id: `openrouter:${model}`, vendor, model, title: title(model) });
    }
    if (vendor === 'openai' && config.openai.apiKey) list.push({ id: `openai:${config.openai.imageModel}`, vendor, model: config.openai.imageModel, title: title(config.openai.imageModel) });
    if (vendor === 'bfl' && config.bfl.apiKey) list.push({ id: `bfl:${config.bfl.model}`, vendor, model: config.bfl.model, title: title(config.bfl.model) });
  }
  return list;
}

const isFlux = (engine) => /flux/i.test(engine.model);
const isGPT = (engine) => /gpt-image/i.test(engine.model);

/** A render model the app may choose (OPENROUTER_RENDER_CHOICES) even when the server's own list leaves it out. */
function choiceEngine(id) {
  if (!config.openrouter.apiKey || typeof id !== 'string') return null;
  const model = id.startsWith('openrouter:') ? id.slice('openrouter:'.length) : id;
  return config.openrouter.renderChoices.includes(model) ? { id: `openrouter:${model}`, vendor: 'openrouter', model, title: title(model) } : null;
}

/** Render models the app can offer on the «Дизайн» step, with their titles. */
export function renderChoices() {
  return config.openrouter.apiKey ? config.openrouter.renderChoices.map((model) => ({ id: `openrouter:${model}`, title: title(model) })) : [];
}

/** "auto" — every engine in order; an engine id — only that one; "flux" / "gpt" — what app versions up to 1.2 ask for. */
export function resolveEngines(requested) {
  const all = imageEngines();
  if (!requested || requested === 'auto') return all;
  if (requested === 'flux') return all.filter(isFlux);
  if (requested === 'gpt') return all.filter(isGPT);
  const exact = all.filter((engine) => engine.id === requested);
  const choice = exact.length ? null : choiceEngine(requested);
  return choice ? [choice] : exact;
}

/** The engine the user picked first, then the server's engines in order as fallbacks; an unknown pick is ignored. */
export function preferredEngines(prefer) {
  const all = imageEngines();
  if (typeof prefer !== 'string' || !prefer) return all;
  const chosen = all.find((engine) => engine.id === prefer || engine.model === prefer) || choiceEngine(prefer);
  return chosen ? [chosen, ...all.filter((engine) => engine.id !== chosen.id)] : all;
}

/** Capability names app versions up to 1.2 understand. */
export const legacyEditEngines = () => {
  const all = imageEngines();
  return [all.some(isFlux) ? 'flux' : null, all.some(isGPT) ? 'gpt' : null].filter(Boolean);
};

function failure(name, status, body) {
  const message = body?.error?.message || (typeof body?.detail === 'string' ? body.detail : '') || body?.message || '';
  if (status === 401 || status === 403) return new ApiError(502, `${name}: ключ не подошёл или нет доступа${message ? ` (${message})` : ''}.`);
  if (status === 402) return new ApiError(502, `${name}: закончились кредиты.`);
  if (status === 429) return new ApiError(429, `${name} занят. Попробуйте через минуту.`, { retryable: true });
  if (status >= 500 || status === 408) return new ApiError(502, `${name} временно недоступен (${status}).`, { retryable: true });
  return new ApiError(502, `${name}: ${message || `ошибка ${status}`}`);
}

async function download(url, name) {
  const file = await request(url, {}, 60_000);
  if (!file.ok) throw new ApiError(502, `${name}: не удалось скачать картинку.`, { retryable: true });
  return Buffer.from(await file.arrayBuffer()).toString('base64');
}

// MARK: OpenRouter Image API (https://openrouter.ai/docs/guides/overview/multimodal/image-generation)

async function openrouterImage(model, { image, prompt, aspectRatio }) {
  const vendor = model.split('/')[0];
  const body = { model, prompt: String(prompt).slice(0, 30_000), n: 1, aspect_ratio: aspectRatio };
  if (vendor === 'openai') body.quality = 'high';
  else if (['google', 'black-forest-labs', 'bytedance-seed'].includes(vendor)) body.resolution = config.images.resolution;
  if (image) body.input_references = [{ type: 'image_url', image_url: { url: `data:image/jpeg;base64,${image}` } }];
  if (config.openrouter.dataCollection === 'deny') body.provider = { data_collection: 'deny' };
  const response = await request(`${config.openrouter.base}/images`, {
    method: 'POST', headers: { Authorization: `Bearer ${config.openrouter.apiKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }, 300_000);
  const result = await readJSON(response);
  if (!response.ok) throw failure(title(model), response.status, result);
  const first = result?.data?.[0];
  if (first?.b64_json) return first.b64_json;
  if (first?.url) return download(first.url, title(model));
  throw new ApiError(502, `${title(model)} не вернул картинку.`, { retryable: true });
}

// MARK: OpenAI Images API (edits with the reference, generations without it)

async function openaiImage(model, { image, prompt, size }) {
  const name = title(model);
  const headers = { Authorization: `Bearer ${config.openai.apiKey}` };
  let response;
  if (image) {
    const form = new FormData();
    form.append('model', model);
    form.append('prompt', String(prompt).slice(0, 30_000));
    form.append('size', size || '1536x1152');
    form.append('quality', 'high');
    form.append('output_format', 'jpeg');
    form.append('n', '1');
    form.append('image[]', new Blob([Buffer.from(image, 'base64')], { type: 'image/jpeg' }), 'render.jpg');
    response = await request(`${config.openai.base}/images/edits`, { method: 'POST', headers, body: form }, 300_000);
  } else {
    response = await request(`${config.openai.base}/images/generations`, {
      method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, prompt: String(prompt).slice(0, 30_000), size: size || '1536x1024', quality: 'high', output_format: 'jpeg', n: 1 }),
    }, 300_000);
  }
  const result = await readJSON(response);
  if (!response.ok) throw failure(name, response.status, result);
  const b64 = result?.data?.[0]?.b64_json;
  if (!b64) throw new ApiError(502, `${name} не вернул картинку.`, { retryable: true });
  return b64;
}

// MARK: Black Forest Labs (FLUX 3 Image; FLUX.1 Kontext for older keys)

async function bflImage(model, { image, prompt, aspectRatio }) {
  const name = title(model);
  const body = /kontext/i.test(model)
    ? { prompt: String(prompt).slice(0, 2500), ...(image ? { input_image: image } : {}), output_format: 'jpeg', safety_tolerance: 2, prompt_upsampling: false }
    : { prompt: String(prompt).slice(0, 10_000), ...(image ? { images: [image], resolution: 'match_input' } : { aspect_ratio: aspectRatio, resolution: config.images.resolution.toLowerCase() }), safety_tolerance: 2, grounding: false };
  const start = await request(`${config.bfl.base}/${model}`, {
    method: 'POST', headers: { 'x-key': config.bfl.apiKey, 'Content-Type': 'application/json', accept: 'application/json' }, body: JSON.stringify(body),
  }, 60_000);
  const created = await readJSON(start);
  if (!start.ok || !created.polling_url) throw failure(name, start.status, created);
  const deadline = Date.now() + 240_000;
  while (Date.now() < deadline) {
    await sleep(config.bfl.pollMs);
    const poll = await request(created.polling_url, { headers: { 'x-key': config.bfl.apiKey, accept: 'application/json' } }, 30_000);
    const state = await readJSON(poll);
    if (!poll.ok) throw failure(name, poll.status, state);
    if (state.status === 'Ready') {
      const sample = state.result?.sample;
      if (!sample) throw new ApiError(502, `${name} не вернул картинку.`, { retryable: true });
      return download(sample, name); // signed link, valid for minutes: download right away
    }
    if (['Request Moderated', 'Content Moderated'].includes(state.status)) throw new ApiError(422, `${name} отклонил запрос модерацией.`);
    if (['Error', 'Failed', 'Task not found'].includes(state.status)) throw new ApiError(502, `${name} не смог создать изображение (${state.status}).`, { retryable: true });
  }
  throw new ApiError(504, `${name} не успел за 4 минуты.`, { retryable: true });
}

/** One engine: edit when `image` (base64 JPEG) is given, otherwise a picture by description. Returns base64. */
export function render(engine, params) {
  if (engine.vendor === 'openrouter') return openrouterImage(engine.model, params);
  if (engine.vendor === 'openai') return openaiImage(engine.model, params);
  return bflImage(engine.model, params);
}

/** Tries the engines in order: a failure or a refusal moves on to the next one. */
export async function renderWithFallback(engines, params) {
  let last;
  for (const engine of engines) {
    try {
      return { image: await render(engine, params), engine };
    } catch (error) {
      last = error;
      console.warn(`[images] ${engine.id} failed: ${error.message}`);
    }
  }
  throw last ?? new ApiError(400, 'Этот генератор не подключён на сервере.');
}
