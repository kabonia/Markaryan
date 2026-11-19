# Сервер ИИ для приложения «АртСтрой»

Приложение больше не хранит ключи ИИ. Оно обращается только к этому серверу, а ключи OpenRouter / GigaChat / YandexGPT лежат в файле `.env` на сервере. Сервер ставит дневные лимиты на каждую установку приложения, поэтому чужие люди не смогут потратить ваш баланс.

## Что умеет
| Запрос приложения | Что делает |
|---|---|
| `POST /v1/ai/chat` | СтройПомощник, перевод, ответы (с потоковой выдачей текста) |
| `POST /v1/ai/json` | Дизайн по планировке, счёт предметов по фото (JSON по схеме) |
| `POST /v1/ai/image-edit` | Фотореализм по точной 3D‑модели: `engine` — `auto` (движки по порядку, при сбое следующий) или id движка |
| `POST /v1/ai/image` | Картинка по описанию: те же движки, в резерве Kandinsky (GigaChat) или Alice AI ART (Яндекс) |
| `GET /v1/ai/capabilities` | Что сейчас подключено + остаток лимитов |

Если первый ИИ недоступен, сервер сам отвечает через следующий (порядок — `AI_PROVIDERS`).

## OpenRouter: Claude, GPT и Gemini по одному ключу
Дизайн по планировке, счёт по фото и СтройПомощник лучше всего работают на сильной модели. Через OpenRouter сервер обращается к Claude Opus 5.5 (тот же Claude, что у Anthropic, по той же цене за токены; OpenRouter берёт 5,5 % при пополнении), а если он недоступен — сам переходит на GPT‑6.2 Astra и Gemini 4 Carbon.
1. openrouter.ai → Keys → создайте ключ, впишите в `.env`: `OPENROUTER_API_KEY=...`.
2. Модели и их порядок — `OPENROUTER_MODELS` (первая отвечает, остальные запасные). Названия — на openrouter.ai/models.
3. `docker compose up -d --force-recreate ai`, затем `https://ваш-домен/v1/ai/capabilities` (с заголовком `X-Install-ID`) — в `providers` должен быть `openrouter`.

Ответы для дизайна идут строго по JSON‑схеме приложения: OpenRouter отправляет запрос только тем провайдерам, которые эту схему соблюдают.

## Картинки: фотореализм по 3D‑модели
Тот же ключ OpenRouter даёт и модели картинок. По умолчанию первой отвечает Nano Banana Pro (`google/gemini-3-pro-image`), при её сбое — GPT Image 2.6 Sunburst, затем FLUX 3 (`OPENROUTER_IMAGE_MODELS`). Можно подключить и напрямую: `OPENAI_API_KEY` (GPT Image) и `BFL_API_KEY` (FLUX 3), порядок — `IMAGE_ENGINES`, адреса — `OPENAI_BASE` и `BFL_BASE` (например, через прокси за рубежом).
- `GET /v1/ai/capabilities` возвращает `imageEngines` — список движков с названиями; владелец в приложении может сравнить их на одном плане.
- Ориентир цены за кадр при 2K: Nano Banana Pro ≈ $0,13, FLUX 3 ≈ $0,10, GPT Image 2.6 Sunburst — по токенам, обычно дороже; Seedream 5.0 Pro (`bytedance-seed/seedream-5-0-pro`) ≈ $0,05, если добавить её в список.
- Картинки по описанию рисуют те же движки; без них — Kandinsky (GigaChat) или Alice AI ART (Яндекс, новый API картинок).

Оплата: по сообщениям пользователей, с мая 2026 года OpenRouter не принимает платежи с российских аккаунтов — нужна зарубежная карта или компания. Если сервер стоит в России и запросы к openrouter.ai не проходят, поставьте рядом прокси за рубежом или укажите в `OPENROUTER_BASE` другой шлюз с таким же API.

## Установка на VPS (Timeweb Cloud, Selectel, REG.RU — Ubuntu 22/24)
1. Купите VPS (1 vCPU, 1–2 ГБ RAM достаточно) и домен или поддомен, например `ai.sochi-art.com`. В DNS сделайте A‑запись домена на IP сервера.
2. Подключитесь по SSH и установите Docker:
   ```
   curl -fsSL https://get.docker.com | sh
   ```
3. Скопируйте папку `server` на VPS (например, `scp -r server root@IP:/opt/artstroy-ai`).
4. На сервере:
   ```
   cd /opt/artstroy-ai
   cp .env.example .env
   nano .env            # вставьте ключи
   nano Caddyfile       # замените ai.example.ru на свой домен
   docker compose up -d --build
   ```
5. Проверка: откройте `https://ваш-домен/health` — должно быть `{"ok":true}`.
6. В Xcode откройте `AIServer.plist` и впишите `https://ваш-домен` (и `APP_TOKEN`, если задали). Соберите приложение.

Логи: `docker compose logs -f ai`. Обновление: заменить файлы и `docker compose up -d --build`.

## Ключи
- **GigaChat**: developers.sber.ru → проект GigaChat API → «Ключ авторизации» (Authorization key). Для ИП/компании выберите scope `GIGACHAT_API_B2B` или `GIGACHAT_API_CORP`.
- **YandexGPT**: console.yandex.cloud → каталог (его ID = `YANDEX_FOLDER_ID`) → сервисный аккаунт с ролями `ai.languageModels.user` и `ai.imageGeneration.user` → «Создать API‑ключ».

## Проверка кода
`npm test` — тесты с имитацией OpenRouter, GigaChat и Yandex (без реальных ключей).

## hh.ru: заявки → вакансии, отклики и чат в приложении
1. В `.env` заполните блок hh.ru: `HH_CLIENT_ID`, `HH_CLIENT_SECRET` (из dev.hh.ru), `HH_ADMIN_KEY` (любой длинный пароль), `PUBLIC_URL`.
2. `HH_REDIRECT_URI` должен совпадать с Redirect URI в dev.hh.ru: `https://pastura.2-26-100-30.sslip.io/v1/auth/hh/callback`. Значит запросы `/v1/auth/hh/*` и `/v1/hh/*` на этом домене должны попадать в этот сервер (см. ниже).
3. Подключение аккаунта (один раз): откройте в браузере `https://ваш-домен/v1/auth/hh/start?key=HH_ADMIN_KEY`, войдите на hh.ru как работодатель «АртСтрой» и разрешите доступ.
4. Проверка: `https://ваш-домен/v1/hh/status?key=HH_ADMIN_KEY` — покажет аккаунт и доступные публикации.

Как работает: клиент создаёт заявку в приложении → сервер публикует вакансию «проектная работа» на hh.ru (только бесплатной публикацией, если не задано `HH_PUBLICATION=any`; не больше `HH_MAX_PER_DAY` в день) → отклики и чат с соискателями видны в заявке в приложении. Контакты, фото и возраст соискателей в приложение не передаются.

hh.ru требует, чтобы сервер работал в России.

### Если на домене уже работает другой сервер
Caddy (маршруты hh и ИИ — сюда, всё остальное — в старый сервер на порту 3000, замените на свой):
```
pastura.2-26-100-30.sslip.io {
	@new path /v1/ai/* /v1/hh/* /v1/auth/hh/* /v1/avito/* /v1/auth/avito/* /v1/market/*
	reverse_proxy @new 127.0.0.1:8080 { flush_interval -1 }
	reverse_proxy 127.0.0.1:3000
}
```
nginx:
```
location ~ ^/v1/(ai|hh|avito|market|auth/hh|auth/avito)/ { proxy_pass http://127.0.0.1:8080; proxy_buffering off; proxy_read_timeout 300s; }
```

## Avito: заявки → вакансии Avito Работа, отклики и чат в приложении
1. В приложении Avito (developers.avito.ru) укажите Redirect URL `https://ваш-домен/v1/auth/avito/callback`.
2. В `.env` впишите `AVITO_CLIENT_ID` и `AVITO_CLIENT_SECRET`, затем `docker compose up -d --force-recreate ai`.
3. Подключение (ключ администратора тот же, что для hh.ru): `https://ваш-домен/v1/auth/avito/start?key=HH_ADMIN_KEY`.
4. Проверка: `https://ваш-домен/v1/avito/status?key=HH_ADMIN_KEY`.

Вакансии публикуются только из купленного пакета размещений Avito Работа (`AVITO_BILLING=package`). Для Messenger API у Avito может требоваться тариф для бизнеса.
