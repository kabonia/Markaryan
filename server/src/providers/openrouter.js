// OpenRouter: one key for Claude, GPT and Gemini through an OpenAI-compatible API.
// The first model in OPENROUTER_MODELS answers; when it fails (outage, rate limit, refusal) OpenRouter itself
// tries the next ones. Docs: https://openrouter.ai/docs (chat completions, structured outputs, model fallbacks).
// Any other OpenAI-compatible gateway works too: set OPENROUTER_BASE; OpenRouter-only fields are then left out.
import { config } from '../config.js';
import { ApiError, request, readJSON, readSSE, parseLooseJSON } from '../util.js';

const url = () => `${config.openrouter.base}/chat/completions`;
const isOpenRouter = () => {
  try { return /(^|\.)openrouter\.ai$/.test(new URL(config.openrouter.base).hostname); } catch { return false; }
};
const headers = () => ({ Authorization: `Bearer ${config.openrouter.apiKey}`, 'Content-Type': 'application/json' });

function toMessages(system, messages) {
  const result = system ? [{ role: 'system', content: system }] : [];
  for (const message of messages) {
    const role = message.role === 'assistant' ? 'assistant' : 'user';
    if (message.image && role === 'user') {
      // Text first, then the picture (OpenRouter's advice for image inputs).
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
  if (status === 401) return new ApiError(502, 'OpenRouter: ключ не подошёл. Проверьте OPENROUTER_API_KEY на сервере.');
  if (status === 402) return new ApiError(502, 'OpenRouter: на счёте закончились кредиты. Пополните баланс.');
  if (status === 403) return new ApiError(502, `OpenRouter отклонил запрос${message ? `: ${message}` : ''}.`);
  if (status === 429) return new ApiError(429, 'ИИ занят: слишком много запросов. Подождите минуту.', { retryable: true });
  if (status === 408 || status >= 500) return new ApiError(502, `ИИ временно недоступен (${status}). Попробуйте через минуту.`, { retryable: true });
  return new ApiError(502, `OpenRouter: ${message || `ошибка ${status}`}`);
}

/**
 * Common request body. All four flagship models think before answering (reasoning cannot be switched off),
 * so the reply gets its own budget on top of the reasoning; the reasoning text itself is not sent back.
 */
function body({ system, messages, maxTokens, effort, requireParameters = false }) {
  const [primary, ...fallbacks] = config.openrouter.models;
  const result = {
    model: primary,
    messages: toMessages(system, messages),
    max_tokens: Math.min(64_000, Math.max(1_000, Number(maxTokens) || 2_000) + 16_000),
  };
  if (isOpenRouter()) {
    if (fallbacks.length) result.models = fallbacks;
    result.reasoning = { effort: config.openrouter.effort || effort, exclude: true };
    const provider = {};
    if (requireParameters) provider.require_parameters = true; // only endpoints that really enforce the JSON schema
    if (config.openrouter.dataCollection === 'deny') provider.data_collection = 'deny';
    if (Object.keys(provider).length) result.provider = provider;
  }
  return result;
}

/** Strict JSON schema (OpenAI style): every object closed and every property required. */
export function strictSchema(schema) {
  if (Array.isArray(schema)) return schema.map(strictSchema);
  if (!schema || typeof schema !== 'object') return schema;
  const copy = {};
  for (const [key, value] of Object.entries(schema)) {
    copy[key] = key === 'properties' && value && typeof value === 'object'
      ? Object.fromEntries(Object.entries(value).map(([name, property]) => [name, strictSchema(property)]))
      : strictSchema(value);
  }
  if (copy.type === 'object' && copy.properties) {
    copy.additionalProperties = false;
    copy.required = Object.keys(copy.properties);
  }
  return copy;
}

export async function chat({ system, messages, maxTokens = 2000, onDelta }) {
  const payload = { ...body({ system, messages, maxTokens, effort: 'medium' }), stream: Boolean(onDelta) };
  const response = await request(url(), { method: 'POST', headers: headers(), body: JSON.stringify(payload) });
  if (!response.ok) throw failure(response.status, await readJSON(response));
  if (!onDelta) return (await readJSON(response))?.choices?.[0]?.message?.content ?? '';
  let full = '';
  await readSSE(response, (data) => {
    if (data === '[DONE]') return false;
    let event;
    try { event = JSON.parse(data); } catch { return true; } // keep-alive comments and partial lines
    if (event?.error) {
      // The model broke off after the headers were sent (OpenRouter sends an error event).
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

/** Structured answer: the JSON schema is enforced by the model; if a route rejects the schema, plain JSON is repaired. */
export async function json({ system, messages, schema, name = 'result', maxTokens = 8000 }) {
  const strictSystem = `${system}\n\nОтветь ТОЛЬКО одним JSON‑объектом по схеме, без текста вокруг.`;
  const strict = {
    ...body({ system: strictSystem, messages, maxTokens, effort: 'high', requireParameters: true }),
    response_format: { type: 'json_schema', json_schema: { name, strict: true, schema: strictSchema(schema) } },
  };
  let response = await request(url(), { method: 'POST', headers: headers(), body: JSON.stringify(strict) });
  if (response.status === 400) {
    await readJSON(response);
    const loose = { ...body({ system: strictSystem, messages, maxTokens, effort: 'high' }), response_format: { type: 'json_object' } };
    response = await request(url(), { method: 'POST', headers: headers(), body: JSON.stringify(loose) });
  }
  const result = await readJSON(response);
  if (!response.ok) throw failure(response.status, result);
  const choice = result?.choices?.[0];
  const content = choice?.message?.content;
  if (!content) {
    throw new ApiError(502, choice?.finish_reason === 'length' ? 'ИИ не успел ответить полностью. Попробуйте ещё раз.' : 'ИИ ответил без данных. Попробуйте ещё раз.', { retryable: true });
  }
  return parseLooseJSON(content);
}

export const supportsVision = () => true;
