// Yandex AI Studio: YandexGPT through the OpenAI‑compatible API, Qwen for photos, Alice AI ART for pictures.
// Docs: https://aistudio.yandex.ru/docs/ru/ai-studio/
import { config } from '../config.js';
import { ApiError, request, readJSON, readSSE, parseLooseJSON } from '../util.js';

let workingBase = null;
const modelURI = (name) => (name.includes('://') ? name : `gpt://${config.yandex.folderId}/${name}`);
const headers = (extra = {}) => ({
  Authorization: `Api-Key ${config.yandex.apiKey}`,
  'OpenAI-Project': config.yandex.folderId,
  'x-folder-id': config.yandex.folderId,
  'Content-Type': 'application/json',
  ...extra,
});

async function call(path, body, accept = 'application/json') {
  const bases = workingBase ? [workingBase, ...config.yandex.bases.filter((b) => b !== workingBase)] : config.yandex.bases;
  let last;
  for (const base of bases) {
    const response = await request(`${base}${path}`, { method: 'POST', headers: headers({ Accept: accept }), body: JSON.stringify(body) });
    if (response.status === 404) { last = response; continue; }
    workingBase = base;
    return response;
  }
  return last;
}

function failure(status, body) {
  const message = body?.error?.message || body?.message || body?.raw || '';
  if (status === 401 || status === 403) return new ApiError(502, 'YandexGPT: доступ отклонён. Проверьте API‑ключ, folder id и роль ai.languageModels.user.');
  if (status === 429) return new ApiError(429, 'YandexGPT: слишком много запросов. Подождите минуту.', { retryable: true });
  if (status >= 500) return new ApiError(502, `YandexGPT временно недоступен (${status}).`, { retryable: true });
  return new ApiError(502, `YandexGPT: ${message || `ошибка ${status}`}`);
}

function toMessages(system, messages) {
  const result = system ? [{ role: 'system', content: system }] : [];
  for (const message of messages) {
    const role = message.role === 'assistant' ? 'assistant' : 'user';
    if (message.image) {
      result.push({ role, content: [
        { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${message.image}` } },
        { type: 'text', text: message.text || '(без текста)' },
      ] });
    } else {
      result.push({ role, content: message.text || '(без текста)' });
    }
  }
  return result;
}

const pickModel = (messages) => modelURI(messages.some((m) => m.image) ? config.yandex.visionModel : config.yandex.model);

export async function chat({ system, messages, maxTokens = 2000, onDelta }) {
  const body = { model: pickModel(messages), messages: toMessages(system, messages), max_tokens: Math.min(maxTokens, 8000), temperature: 0.4, stream: Boolean(onDelta) };
  const response = await call('/chat/completions', body, onDelta ? 'text/event-stream' : 'application/json');
  if (!response.ok) throw failure(response.status, await readJSON(response));
  if (!onDelta) return (await readJSON(response))?.choices?.[0]?.message?.content ?? '';
  let full = '';
  await readSSE(response, (payload) => {
    if (payload === '[DONE]') return false;
    try {
      const delta = JSON.parse(payload)?.choices?.[0]?.delta?.content;
      if (delta) { full += delta; onDelta(delta); }
    } catch { /* ignore */ }
    return true;
  });
  return full;
}

export async function json({ system, messages, schema, name = 'result', maxTokens = 8000 }) {
  const base = { model: pickModel(messages), messages: toMessages(`${system}\n\nОтветь ТОЛЬКО одним JSON‑объектом по схеме, без текста вокруг.`, messages), max_tokens: Math.min(maxTokens, 8000), temperature: 0.3 };
  let response = await call('/chat/completions', { ...base, response_format: { type: 'json_schema', json_schema: { name, schema } } });
  if (response.status === 400) response = await call('/chat/completions', { ...base, response_format: { type: 'json_object' } });
  const result = await readJSON(response);
  if (!response.ok) throw failure(response.status, result);
  return parseLooseJSON(result?.choices?.[0]?.message?.content ?? '');
}

/** Alice AI ART through the OpenAI-compatible Images API (synchronous; the old async Image Generation API is retired). */
export async function generateImage({ prompt, size = '1024x1024' }) {
  const model = config.yandex.artModel.includes('://') ? config.yandex.artModel : `art://${config.yandex.folderId}/${config.yandex.artModel}`;
  const response = await call('/images/generations', { model, prompt: String(prompt).slice(0, 500), size });
  const result = await readJSON(response);
  if (!response.ok) throw failure(response.status, result);
  const image = result?.data?.[0]?.b64_json;
  if (!image) throw new ApiError(502, 'Alice AI ART не вернул изображение. Попробуйте изменить описание.');
  return image;
}

export const supportsVision = () => Boolean(config.yandex.visionModel);
