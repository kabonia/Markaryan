// Hermes agent: встроенный помощник СметаПро (профиль artstroy на этом же хосте) —
// персона, база знаний по сервису, инструменты (веб-поиск). OpenAI-совместимый API-сервер Hermes.
// HERMES_AI_BASE = адрес зеркала профиля (по умолчанию http://127.0.0.1:8642/p/artstroy/v1),
// HERMES_API_KEY = API_SERVER_KEY хоста. Приложение присылает всю историю — сессии не нужны.
// Используется только для tier 'helper' (см. ai.js); фото/дизайн/чат идут через обычную цепочку.
import { config } from '../config.js';
import { ApiError, request, readJSON, readSSE, parseLooseJSON } from '../util.js';

const url = (path) => `${config.hermes.base}${path}`;
const headers = () => ({ Authorization: `Bearer ${config.hermes.apiKey}`, 'Content-Type': 'application/json' });
const jsonUrl = (path) => `${config.hermesJson.base}${path}`;
const jsonHeaders = () => ({ Authorization: `Bearer ${config.hermesJson.apiKey}`, 'Content-Type': 'application/json' });

function toMessages(system, messages) {
  const result = system ? [{ role: 'system', content: system }] : [];
  for (const message of messages) {
    const role = message.role === 'assistant' ? 'assistant' : 'user';
    if (message.image && role === 'user') {
      result.push({ role, content: [
        { type: 'text', text: message.text || '(без текста)' },
        { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${message.image}` } },
      ] });
    } else {
      result.push({ role, content: message.text || '(без текста)' });
    }
  }
  return result;
}

function failure(status, body) {
  const message = body?.error?.message || body?.message || body?.raw || '';
  if (status === 401) return new ApiError(502, 'Hermes: ключ не подошёл. Проверьте HERMES_API_KEY на сервере.');
  if (status === 429) return new ApiError(429, 'ИИ занят: слишком много запросов. Подождите минуту.', { retryable: true });
  if (status === 408 || status >= 500) return new ApiError(502, `ИИ временно недоступен (${status}). Попробуйте через минуту.`, { retryable: true });
  return new ApiError(502, `Hermes: ${message || `ошибка ${status}`}`);
}

const clampTokens = (maxTokens, cap) => Math.min(cap, Math.max(1_000, Number(maxTokens) || 2_000));

export async function chat({ system, messages, maxTokens = 2000, onDelta }) {
  const payload = {
    model: 'hermes',
    messages: toMessages(system, messages),
    max_tokens: clampTokens(maxTokens, 16_000),
    stream: Boolean(onDelta),
  };
  const response = await request(url('/chat/completions'), { method: 'POST', headers: headers(), body: JSON.stringify(payload) });
  if (!response.ok) throw failure(response.status, await readJSON(response));
  if (!onDelta) return (await readJSON(response))?.choices?.[0]?.message?.content ?? '';
  let full = '';
  await readSSE(response, (data) => {
    if (data === '[DONE]') return false;
    let event;
    try { event = JSON.parse(data); } catch { return true; }
    if (event?.error) {
      const error = new ApiError(502, 'ИИ прервал ответ. Попробуйте ещё раз.', { retryable: true });
      error.streamStarted = full.length > 0;
      throw error;
    }
    const delta = event?.choices?.[0]?.delta?.content;
    if (delta) { full += delta; onDelta(delta); }
    return true;
  });
  return full;
}

/** Structured answer (не используется для helper, но оставляем для полноты). */
export async function json({ system, messages, schema, name = 'result', maxTokens = 8000, model, meta, timeoutMs }) {
  if (model && (config.openrouter.designChoices || []).includes(model)) {
    throw new ApiError(501, 'hermes: пропущен — выбран дизайн-модель OpenRouter');
  }
  if (!config.hermesJson.base || !config.hermesJson.apiKey) throw new ApiError(503, 'Hermes JSON не настроен (HERMES_JSON_BASE).');
  const schemaText = schema ? `\nСхема ответа (JSON Schema):\n${JSON.stringify(schema)}` : '';
  const strictSystem = `${system}${schemaText}\n\nОтветь ТОЛЬКО одним JSON-объектом, полностью соответствующим схеме, без текста вокруг.`;
  const base = { model: 'hermes', messages: toMessages(strictSystem, messages), max_tokens: clampTokens(maxTokens, 32_000) };
  let response = await request(jsonUrl('/chat/completions'), { method: 'POST', headers: jsonHeaders(), body: JSON.stringify({ ...base, response_format: { type: 'json_object' } }) }, timeoutMs);
  const result = await readJSON(response);
  if (!response.ok) throw failure(response.status, result);
  if (meta && typeof result?.model === 'string') meta.model = result.model;
  const choice = result?.choices?.[0];
  const content = choice?.message?.content;
  if (!content) throw new ApiError(502, 'ИИ ответил без данных. Попробуйте ещё раз.', { retryable: true });
  return parseLooseJSON(content);
}

/** Фото в Hermes не направляем: с картинками цепочка идёт дальше (helper с фото не роутится). */
export const supportsVision = () => true;
