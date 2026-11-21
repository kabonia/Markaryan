// Settings come only from environment variables (.env on the server). Keys never go into the app.
const env = process.env;
const int = (name, fallback) => {
  const value = Number.parseInt(env[name] ?? '', 10);
  return Number.isFinite(value) ? value : fallback;
};

export const config = {
  port: int('PORT', 8080),
  /** Optional shared token the app sends in X-App-Token (filters random bots; real protection = limits below). */
  appToken: env.APP_TOKEN || '',
  /** Order of text providers: the first that works answers, the next is the fallback. Providers without keys are skipped. */
  providers: (env.AI_PROVIDERS || 'openrouter,gigachat,yandex').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean),
  dataDir: env.DATA_DIR || './data',

  /** OpenRouter (or another OpenAI-compatible gateway): the first model answers, the others are automatic fallbacks. */
  openrouter: {
    apiKey: env.OPENROUTER_API_KEY || '',
    base: (env.OPENROUTER_BASE || 'https://openrouter.ai/api/v1').trim().replace(/\/$/, ''),
    models: (env.OPENROUTER_MODELS || 'anthropic/claude-opus-5.5,openai/gpt-6.2-astra,google/gemini-4-carbon')
      .split(',').map((s) => s.trim()).filter(Boolean),
    /** low | medium | high | xhigh | max; empty — high for designs and photo counting, medium for chat. */
    effort: env.OPENROUTER_EFFORT || '',
    /** deny — only providers that do not store prompts (photos and plans of clients). */
    dataCollection: (env.OPENROUTER_DATA_COLLECTION || '').toLowerCase(),
    /** Image models for the photoreal render, in order: the first answers, the next ones step in when it fails. */
    imageModels: (env.OPENROUTER_IMAGE_MODELS || 'google/gemini-3-pro-image,openai/gpt-image-2.6-sunburst,black-forest-labs/flux-3-image')
      .split(',').map((s) => s.trim()).filter(Boolean),
    /** Models the app offers on the «Дизайн» step for the concept and the layout: the chosen one answers first,
     *  the models above stay as fallbacks. All of them work with the same OpenRouter key. */
    designChoices: (env.OPENROUTER_DESIGN_CHOICES || 'anthropic/claude-opus-5.5,anthropic/claude-sonnet-5.5,openai/gpt-6.2-astra,google/gemini-4-carbon')
      .split(',').map((s) => s.trim()).filter(Boolean),
    /** Image models the app offers for the 3D render: the chosen one draws first, the engines below stay as fallbacks. */
    renderChoices: (env.OPENROUTER_RENDER_CHOICES || 'google/gemini-3-pro-image,openai/gpt-image-2.6-sunburst,bytedance-seed/seedream-5-0-pro')
      .split(',').map((s) => s.trim()).filter(Boolean),
  },

  /** Picture engines in order: openrouter (its image models), openai, bfl — each only when its key is set. */
  images: {
    order: (env.IMAGE_ENGINES || 'openrouter,openai,bfl').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean),
    /** 1K, 2K or 4K for models that take a resolution (Nano Banana: the same price for 1K and 2K). */
    resolution: (env.IMAGE_RESOLUTION || '2K').toUpperCase(),
  },

  gigachat: {
    authKey: env.GIGACHAT_AUTH_KEY || '',
    scope: env.GIGACHAT_SCOPE || 'GIGACHAT_API_PERS',
    model: env.GIGACHAT_MODEL || 'GigaChat-2-Max',
    oauthURL: env.GIGACHAT_OAUTH_URL || 'https://ngw.devices.sberbank.ru:9443/api/v2/oauth',
    /** Several base URLs are documented; the first that answers is remembered. */
    bases: (env.GIGACHAT_BASE || 'https://api.giga.chat/api/v1,https://api.giga.chat/v1,https://gigachat.devices.sberbank.ru/api/v1')
      .split(',').map((s) => s.trim().replace(/\/$/, '')).filter(Boolean),
  },

  yandex: {
    apiKey: env.YANDEX_API_KEY || '',
    folderId: env.YANDEX_FOLDER_ID || '',
    model: env.YANDEX_MODEL || 'yandexgpt/latest',
    visionModel: env.YANDEX_VISION_MODEL || 'qwen3.6-35b-a3b',
    artModel: env.YANDEX_ART_MODEL || 'aliceai-image-art-3.0',
    bases: (env.YANDEX_BASE || 'https://ai.api.cloud.yandex.net/v1,https://llm.api.cloud.yandex.net/v1')
      .split(',').map((s) => s.trim().replace(/\/$/, '')).filter(Boolean),
  },

  /** Optional direct picture engines (without OpenRouter). Addresses can point to a proxy abroad. */
  bfl: {
    apiKey: env.BFL_API_KEY || '',
    model: env.BFL_MODEL || 'flux-3-image',
    base: (env.BFL_BASE || 'https://api.bfl.ai/v1').trim().replace(/\/$/, ''),
    pollMs: int('BFL_POLL_MS', 1500),
  },
  openai: {
    apiKey: env.OPENAI_API_KEY || '',
    imageModel: env.OPENAI_IMAGE_MODEL || 'gpt-image-2.6-sunburst',
    base: (env.OPENAI_BASE || 'https://api.openai.com/v1').trim().replace(/\/$/, ''),
  },

  /** Daily limits per installation (X-Install-ID) and per IP address. */
  limits: {
    search: int('LIMIT_SEARCH', 200),
    chat: int('LIMIT_CHAT', 150),
    json: int('LIMIT_JSON', 25),
    vision: int('LIMIT_VISION', 40),
    imageEdit: int('LIMIT_IMAGE_EDIT', 24),
    image: int('LIMIT_IMAGE', 15),
    ipMultiplier: int('LIMIT_IP_MULTIPLIER', 4),
    /** Requests per minute per installation, all kinds together. */
    perMinute: int('LIMIT_PER_MINUTE', 20),
  },
  maxBodyBytes: int('MAX_BODY_MB', 16) * 1024 * 1024,
};

export const hasOpenRouter = () => Boolean(config.openrouter.apiKey && config.openrouter.models.length);
export const hasGigaChat = () => Boolean(config.gigachat.authKey);
export const hasYandex = () => Boolean(config.yandex.apiKey && config.yandex.folderId);
