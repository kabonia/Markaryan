// Chooses the provider: the first in AI_PROVIDERS that is configured; on a temporary failure — the next one.
import { config, hasGigaChat, hasHermes, hasHermesJson, hasOpenRouter, hasYandex } from './config.js';
import { ApiError } from './util.js';
import * as gigachat from './providers/gigachat.js';
import * as hermes from './providers/hermes.js';
import * as openrouter from './providers/openrouter.js';
import * as yandex from './providers/yandex.js';

const registry = {
  hermes: { api: hermes, ready: hasHermes },
  openrouter: { api: openrouter, ready: hasOpenRouter },
  gigachat: { api: gigachat, ready: hasGigaChat },
  yandex: { api: yandex, ready: hasYandex },
};
const draws = (name) => typeof registry[name].api.generateImage === 'function';

export function activeProviders() {
  return config.providers.filter((name) => registry[name]?.ready());
}

/** Some providers answer in text only: pictures come from GigaChat (Kandinsky) or YandexART. */
export const canGenerateImages = () => activeProviders().some(draws);

async function withFallback(task, { needsVision = false, needsImages = false, forceHermes = false } = {}) {
  const names = [...(forceHermes && hasHermesJson() ? ['hermes'] : []), ...activeProviders().filter((name) => (!needsVision || registry[name].api.supportsVision()) && (!needsImages || draws(name)))];
  if (names.length === 0) throw new ApiError(503, 'ИИ на сервере не настроен. Добавьте ключ OpenRouter, GigaChat или YandexGPT в .env.');
  let lastError;
  for (const name of names) {
    try {
      return await task(registry[name].api, name);
    } catch (error) {
      lastError = error;
      console.warn(`[ai] ${name} failed: ${error.message}`);
      // Streaming that already sent text cannot switch providers mid‑answer.
      if (error.streamStarted) break;
    }
  }
  throw lastError;
}

export const chat = async (params) => {
  // Встроенный помощник (tier helper, текст) отвечает агент Hermes; при сбое — обычная цепочка.
  if (params.tier === 'helper' && hasHermes()) {
    try {
      return await hermes.chat(params);
    } catch (error) {
      if (error?.streamStarted) throw error; // стрим уже шёл — цепочку не переключаем
      console.warn(`[ai] hermes failed: ${error.message}`);
    }
  }
  return withFallback((api) => api.chat(params), { needsVision: params.messages.some((m) => m.image) });
};
/** `params.model` — the model the app picked (OpenRouter only); `params.meta` receives the provider and the model that answered. */
export const json = (params) => withFallback((api, name) => {
  if (params.meta) params.meta.provider = name;
  return api.json(params);
}, { needsVision: params.messages.some((m) => m.image) });
/** Смета по документам и цены: Hermes (профиль smeta-json) первым, при сбое — обычная цепочка. */
export const smetaJson = (params) =>
  hasHermesJson()
    ? withFallback((api, name) => {
        if (params.meta) params.meta.provider = name;
        // Модель, выбранная в приложении, относится к OpenRouter: Hermes отвечает своей моделью.
        return api.json(name === 'hermes' ? { ...params, model: undefined } : params);
      }, { forceHermes: true })
    : json(params);
export const generateImage = (params) => withFallback((api) => api.generateImage(params), { needsImages: true });
