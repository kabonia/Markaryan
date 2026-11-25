import { AsyncLocalStorage } from 'node:async_hooks';

export class ApiError extends Error {
  /** @param {number} status HTTP status for the app  @param {string} message Russian text shown to the user */
  constructor(status, message, { retryable = false } = {}) {
    super(message);
    this.status = status;
    this.retryable = retryable;
  }
}

/** fetch with a timeout; network failures become retryable ApiErrors. */
export async function request(url, options = {}, timeoutMs = 170_000) {
  try {
    return await fetch(url, { ...options, signal: AbortSignal.timeout(timeoutMs) });
  } catch (error) {
    const reason = error?.cause?.code || error?.name || error?.message || 'network';
    throw new ApiError(502, `Сервис ИИ недоступен (${reason}).`, { retryable: true });
  }
}

export async function readJSON(response) {
  const text = await response.text();
  try { return JSON.parse(text); } catch { return { raw: text.slice(0, 500) }; }
}

/** Reads server-sent events: calls onData(payloadString) for every `data:` line. */
export async function readSSE(response, onData) {
  const decoder = new TextDecoder();
  let buffer = '';
  for await (const chunk of response.body) {
    buffer += decoder.decode(chunk, { stream: true });
    let index;
    while ((index = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, index).replace(/\r$/, '');
      buffer = buffer.slice(index + 1);
      if (line.startsWith('data:')) {
        const payload = line.slice(5).trim();
        if (payload) { if (onData(payload) === false) return; }
      }
    }
  }
  const rest = buffer.trim();
  if (rest.startsWith('data:')) onData(rest.slice(5).trim());
}

/**
 * Extracts a JSON object from model text: code fences, text around it, and a cut‑off end
 * (closes open strings, arrays and objects) are all handled.
 */
export function parseLooseJSON(text) {
  if (text && typeof text === 'object') return text;
  let source = String(text ?? '').trim().replace(/^```(?:json)?/i, '').replace(/```\s*$/, '').trim();
  const start = source.indexOf('{');
  if (start < 0) throw new ApiError(502, 'ИИ ответил без данных. Попробуйте ещё раз.', { retryable: true });
  source = source.slice(start);
  try { return JSON.parse(source.slice(0, source.lastIndexOf('}') + 1)); } catch { /* repair below */ }
  // Repair a truncated answer.
  const stack = [];
  let inString = false, escaped = false, lastSafe = 0;
  for (let i = 0; i < source.length; i += 1) {
    const ch = source[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === '\\') escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === '{' || ch === '[') stack.push(ch === '{' ? '}' : ']');
    else if (ch === '}' || ch === ']') { stack.pop(); if (stack.length === 0) { lastSafe = i + 1; break; } }
    else if (ch === ',') lastSafe = i;
  }
  let candidate = lastSafe > 0 && stack.length === 0 ? source.slice(0, lastSafe) : source;
  if (stack.length > 0) {
    candidate = candidate.replace(/,\s*$/, '');
    if (inString) candidate += '"';
    candidate = candidate.replace(/,\s*"[^"]*"\s*:?\s*"?$/, '').replace(/,\s*$/, '');
    candidate += stack.reverse().join('');
  }
  try { return JSON.parse(candidate); } catch {
    throw new ApiError(502, 'ИИ ответил не полностью. Попробуйте ещё раз.', { retryable: true });
  }
}

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Promise.all with at most `limit` tasks running at once (the order of results matches the input). */
export async function mapLimit(list, limit, fn) {
  const results = new Array(list.length);
  let next = 0;
  const worker = async () => { while (next < list.length) { const i = next++; results[i] = await fn(list[i], i); } };
  await Promise.all(Array.from({ length: Math.min(limit, list.length) }, worker));
  return results;
}

// ---------- AI spending ----------
// A long job (an estimate) runs inside withCost(meter, fn): every AI answer adds its price (OpenRouter usage.cost, $)
// to the meter, by the job's current stage. Outside a meter nothing is counted.
const costScope = new AsyncLocalStorage();
export const newMeter = () => ({ total: 0, calls: 0, stage: 'start', stages: {} });
export const withCost = (meter, fn) => costScope.run(meter, fn);
export function addCost(usage) {
  const meter = costScope.getStore();
  const cost = Number(usage?.cost);
  if (!meter || !Number.isFinite(cost)) return;
  meter.total += cost;
  meter.calls += 1;
  meter.stages[meter.stage] = (meter.stages[meter.stage] || 0) + cost;
}

/** The AI account has no money (or the server key hit its limit): retrying or switching models will not help. */
export const isOutOfFunds = (error) => Boolean(error?.outOfFunds);
export function outOfFunds(message = 'На сервере закончился баланс ИИ.') {
  const error = new ApiError(503, message);
  error.outOfFunds = true;
  return error;
}

// ---------- язык ответа ИИ ----------
const LANGUAGE_NAMES = { en: 'English (United States)', es: 'Spanish', zh: 'Simplified Chinese', de: 'German', fr: 'French', pt: 'Portuguese', it: 'Italian' };
/** Язык приложения из заголовка X-App-Language (en, es, zh-Hans…); null — русский (по умолчанию). */
export function appLanguage(req) {
  const raw = String(req?.headers?.['x-app-language'] || '').toLowerCase().slice(0, 12);
  if (!raw || raw.startsWith('ru')) return null;
  return raw.split(/[-_]/)[0];
}
/** Приписка к системной подсказке: отвечать на языке пользователя (поля JSON не переводить). */
export function languageNote(lang) {
  if (!lang) return '';
  const name = LANGUAGE_NAMES[lang] || lang;
  return `\n\nIMPORTANT: the user's app language is ${name}. Write ALL user-facing text of the answer in ${name}, `
    + 'using the construction terms and units customary in that country. Keep JSON keys and enum values exactly as specified.';
}
