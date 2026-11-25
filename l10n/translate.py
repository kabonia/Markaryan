#!/usr/bin/env python3
"""Перевод интерфейса СметаПро: l10n/en.xliff (выгрузка Xcode) + строки из кода → Markaryan/Localizable.xcstrings.

  OPENROUTER_API_KEY=… python3 -I l10n/translate.py en [es zh-Hans]

Шаги: перевод сильной моделью (словарь терминов, контекст приложения) → проверка шаблонов (%@, %lld, \\n) →
вычитка второй моделью → кэш l10n/cache-<язык>.json (повторный запуск переводит только новое) → String Catalog.
Только стандартная библиотека Python.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
XLIFF = ROOT / "l10n" / "en.xliff"
CATALOG = ROOT / "Markaryan" / "Localizable.xcstrings"
TRANSLATOR = os.environ.get("L10N_MODEL", "anthropic/claude-sonnet-5.5")
REVIEWER = os.environ.get("L10N_REVIEW_MODEL", "openai/gpt-6.2-sol")
BATCH = 70

LANGS = {
    "en": "English (United States). Audience: US homeowners, contractors and builders. Use natural US construction terms, "
          "sentence case for buttons, short labels. Address the user as \"you\".",
    "es": "Spanish (neutral Latin American, understandable in the US and Spain). Audience: homeowners and builders. "
          "Use natural construction terms (tejado/techo según contexto, alero, cumbrera). Address the user as \"tú\".",
    "zh-Hans": "Simplified Chinese. Audience: homeowners and builders. Natural, concise construction terminology.",
}

GLOSSARY = """Термины (RU → смысл; переводи так, как говорят строители в целевой стране):
смета — cost estimate; сметчик — estimator; объект — project/site; прораб — site foreman;
3D‑обмер дома — 3D house measurement; обмер — measurement survey; макет — model; скан — scan; обход — walk-around;
лидар — LiDAR; кольцо покрытия — coverage ring;
крыша/кровля — roof; скат — roof plane/slope; конёк — ridge; карниз — eave; свес — overhang; фронтон — gable;
вальмовая — hip roof; полувальмовая — half-hip (Dutch hip) roof; двускатная — gable roof; односкатная — shed roof;
мансардная (ломаная) — gambrel/mansard roof; уклон — pitch; водосток/жёлоб — gutter; водосточная труба — downspout;
снегозадержатель — snow guard; ендова — valley; отмостка — foundation apron (perimeter walkway); цоколь — plinth/base;
фасад — facade/siding area; проём — opening; подоконник (низ окна) — sill;
участок — lot/plot; кадастр — cadastre (Russian land registry); кадастровый номер — cadastral number;
ВРИ (вид разрешённого использования) — permitted land use; ЕГРН — Russian state real estate register (USRN);
ИЖС — individual housing construction; СП — Russian building code (SP); ПЗЗ — zoning rules; Росреестр — Rosreestr;
НСПД — Rosreestr public map (NSPD); отступ — setback; пятно застройки — building footprint;
кредиты (баланс) — credits; тариф — plan; ИИ — AI; ИИ‑помощник — AI assistant; калькулятор — calculator;
арматура — rebar; стяжка — screed; кладка — masonry; штукатурка — plaster; гипсокартон — drywall; керамогранит — porcelain tile;
КП (коммерческое предложение) — quote/proposal; КС‑2/КС‑3 — Russian acceptance forms (KS-2/KS-3);
м/м²/м³ — оставляй метрические числа как есть (m, m², m³); приложение само переводит размеры в футы, где нужно."""

RULES = """Правила:
1. Переводи смысл, а не слова: живой, понятный, профессиональный интерфейс. Без канцелярита.
2. Шаблоны %@ %lld %d %lf %f %1$@ %2$lld и т.п., \\n, «%%», эмодзи, коды и бренды (СметаПро → SmetaPro, НСПД, iPhone, LiDAR, Pro) — сохраняй точно, в том же количестве.
3. Длина: кнопки и заголовки — не длиннее оригинала по смыслу; подсказки — естественно.
4. Российские реалии (Росреестр, ЕГРН, СП, ВРИ, ИЖС, КС‑2) не выдумывай заменами — переводи с пояснением в 1–3 слова, если иначе непонятно.
5. Если строка — не текст интерфейса (идентификатор, формат даты, промпт для ИИ на русском), верни её без изменений.
Ответ — только JSON: {"items":[{"id":N,"t":"перевод"}]} для КАЖДОГО id."""

SPEC = re.compile(r"%(?:\d+\$)?(?:lld|ld|llu|lu|d|i|u|@|lf|f|\.\d+f|\.\d+lf|s|%)")


def specs(text: str) -> list[str]:
    return sorted(SPEC.findall(text)) + [str(text.count("\n"))]


def call(model: str, system: str, user: str, key: str) -> tuple[dict, float]:
    body = {"model": model, "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            "max_tokens": 16000, "response_format": {"type": "json_object"}, "usage": {"include": True},
            "reasoning": {"effort": "low", "exclude": True}}
    for attempt in range(4):
        try:
            req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                         headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=300) as r:
                result = json.loads(r.read())
            text = result["choices"][0]["message"]["content"]
            data = json.loads(text[text.find("{"): text.rfind("}") + 1])
            return data, float(result.get("usage", {}).get("cost") or 0)
        except Exception as error:  # noqa: BLE001 — сеть/ИИ: повтор с паузой
            if attempt == 3:
                raise
            print(f"  повтор ({error})", flush=True)
            time.sleep(5 * (attempt + 1))
    raise RuntimeError("unreachable")


def from_xliff() -> dict[str, str]:
    """Ключ → комментарий из выгрузки Xcode."""
    if not XLIFF.exists():
        return {}
    ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
    out = {}
    for unit in ET.parse(XLIFF).getroot().iterfind(".//x:trans-unit", ns):
        source = unit.find("x:source", ns)
        note = unit.find("x:note", ns)
        key = unit.get("id") or (source.text if source is not None else None)
        if key and re.search(r"[А-Яа-яЁё]", key):
            out[key] = (note.text or "") if note is not None else ""
    return out


def from_code() -> dict[str, str]:
    """Русские строки без подстановок из кода — их показывают компоненты, принимающие String (кнопки, карточки…)."""
    out = {}
    for path in (ROOT / "Markaryan").rglob("*.swift"):
        text = path.read_text(encoding="utf8")
        for m in re.finditer(r'"((?:[^"\\\n]|\\.)*)"', text):
            s = m.group(1)
            if "\\(" in s or not re.search(r"[А-Яа-яЁё]", s) or len(s) > 600:
                continue
            s = s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
            out.setdefault(s, f"из {path.name}")
    return out


def translate(lang: str, keys: dict[str, str], key: str) -> tuple[dict[str, str], float]:
    cache_path = ROOT / "l10n" / f"cache-{lang}.json"
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    todo = [k for k in keys if k not in cache]
    cost = 0.0
    print(f"{lang}: всего {len(keys)}, перевести {len(todo)}", flush=True)
    system = (f"Ты — профессиональный переводчик интерфейсов iOS‑приложений и строительный инженер. Приложение СметаПро: "
              f"сметы по документам, 3D‑обмер дома лидаром iPhone, дизайн по фото, калькуляторы материалов, AR‑рулетка, "
              f"ИИ‑помощник. Переводи с русского на: {LANGS[lang]}\n\n{GLOSSARY}\n\n{RULES}")
    for start in range(0, len(todo), BATCH):
        chunk = todo[start:start + BATCH]
        items = [{"id": i, "ru": k, "context": keys[k][:120]} for i, k in enumerate(chunk)]
        data, c = call(TRANSLATOR, system, json.dumps({"items": items}, ensure_ascii=False), key)
        cost += c
        got = {int(x["id"]): str(x.get("t", "")) for x in data.get("items", []) if str(x.get("id", "")).isdigit()}
        bad = []
        for i, k in enumerate(chunk):
            t = got.get(i, "")
            if t and specs(t) == specs(k):
                cache[k] = t
            else:
                bad.append(k)
        # Шаблоны не совпали — по одной, с явным указанием.
        for k in bad:
            data, c = call(TRANSLATOR, system + "\nВНИМАНИЕ: сохрани все шаблоны и переводы строк в точности.",
                           json.dumps({"items": [{"id": 0, "ru": k, "context": keys[k][:120]}]}, ensure_ascii=False), key)
            cost += c
            t = str((data.get("items") or [{}])[0].get("t", ""))
            if t and specs(t) == specs(k):
                cache[k] = t
            else:
                print(f"  ✗ шаблоны: {k[:60]!r}", flush=True)
        cache_path.write_text(json.dumps(cache, ensure_ascii=False, indent=0, sort_keys=True))
        print(f"  {min(start + BATCH, len(todo))}/{len(todo)} · ${cost:.3f}", flush=True)
    return cache, cost


def review(lang: str, keys: dict[str, str], cache: dict[str, str], key: str) -> float:
    """Вычитка второй моделью: возвращает только исправления (смысл, термины, естественность, длина кнопок)."""
    done_path = ROOT / "l10n" / f"reviewed-{lang}.json"
    done = set(json.loads(done_path.read_text())) if done_path.exists() else set()
    todo = [k for k in keys if k in cache and k not in done]
    cost = 0.0
    system = (f"Ты — редактор локализации iOS‑приложения (стройка, сметы, 3D‑обмер дома). Язык: {LANGS[lang]}\n{GLOSSARY}\n"
              f"Проверь пары «русский → перевод». Верни ТОЛЬКО то, что нужно исправить (ошибка смысла, неверный термин, "
              f"неестественно, слишком длинно для кнопки, потеряны шаблоны). Хорошие — не возвращай.\n"
              f'Ответ — только JSON: {{"fixes":[{{"id":N,"t":"исправленный перевод","why":"кратко"}}]}}')
    fixed = 0
    for start in range(0, len(todo), BATCH):
        chunk = todo[start:start + BATCH]
        items = [{"id": i, "ru": k, "t": cache[k]} for i, k in enumerate(chunk)]
        data, c = call(REVIEWER, system, json.dumps({"items": items}, ensure_ascii=False), key)
        cost += c
        for f in data.get("fixes", []) or []:
            try:
                k = chunk[int(f["id"])]
            except (KeyError, ValueError, IndexError):
                continue
            t = str(f.get("t", ""))
            if t and specs(t) == specs(k):
                cache[k] = t
                fixed += 1
        done.update(chunk)
        (ROOT / "l10n" / f"cache-{lang}.json").write_text(json.dumps(cache, ensure_ascii=False, indent=0, sort_keys=True))
        done_path.write_text(json.dumps(sorted(done), ensure_ascii=False, indent=0))
        print(f"  вычитка {min(start + BATCH, len(todo))}/{len(todo)} · исправлено {fixed} · ${cost:.3f}", flush=True)
    return cost


def write_catalog(langs: list[str], keys: dict[str, str]) -> None:
    catalog = json.loads(CATALOG.read_text()) if CATALOG.exists() else {"sourceLanguage": "ru", "strings": {}, "version": "1.0"}
    strings = catalog.setdefault("strings", {})
    caches = {lang: json.loads((ROOT / "l10n" / f"cache-{lang}.json").read_text()) for lang in langs}
    for k in sorted(keys):
        entry = strings.setdefault(k, {})
        if keys[k].startswith("из "):
            entry["extractionState"] = "manual"  # строка из кода (String), Xcode её сам не находит
        locs = entry.setdefault("localizations", {})
        for lang in langs:
            if k in caches[lang]:
                locs[lang] = {"stringUnit": {"state": "translated", "value": caches[lang][k]}}
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print(f"каталог: {CATALOG.relative_to(ROOT)} — {len(strings)} строк, языки {', '.join(langs)}")


def main() -> None:
    langs = sys.argv[1:] or ["en"]
    key = os.environ["OPENROUTER_API_KEY"]
    keys = {**from_code(), **from_xliff()}
    total = 0.0
    for lang in langs:
        cache, cost = translate(lang, keys, key)
        total += cost
        total += review(lang, keys, cache, key)
    write_catalog(langs, keys)
    print(f"Итого на ИИ: ${total:.2f}")


if __name__ == "__main__":
    main()
