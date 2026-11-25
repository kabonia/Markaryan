"""Крыша по кадрам скана: ИИ отмечает конёк/тип/детали, геометрия — лучи из поз ARKit.

1. Берём 4–6 лучших кадров крыши (снимки 12 Мп, иначе ключевые кадры яруса «крыша»), разнесённых по кругу.
2. Кадры с сенсора лежат «на боку» — поворачиваем так, чтобы небо было сверху (по позе ARKit), иначе ИИ путается.
3. ИИ (Gemini 4 Hydrogen, ≈$0.03) возвращает тип крыши, покрытие, детали и точки концов конька на каждом фото.
4. Каждая точка → луч из камеры → пересечение с плоскостью фронтонной стены, измеренной LiDAR → высота конька.
   Медиана по кадрам; выбросы (ИИ промахнулся) отбрасываются.
"""
from __future__ import annotations

import base64
import io
import json
import math
import os
import urllib.request

import numpy as np

from .bundle import Bundle, Frame

MODEL = os.environ.get("HOUSE_ROOF_MODEL", "google/gemini-4-hydrogen")
WALL_FRAMES = 8  # кадров стен для окон и дверей (в «вертикальном» кадре дом целиком не помещается)

SYSTEM = """Ты — инженер-кровельщик и обмерщик фасадов. На фото один частный дом, снятый с земли (несколько ракурсов).
Определи тип крыши (gable|hip|half_hip|mansard|gambrel|shed|flat|pyramid|cross_gable|complex), покрытие, цвет и детали
(трубы, слуховые и мансардные окна, водостоки, снегозадержатели, ендовы; seen=false — если не видно, а предполагаешь),
материал и цвет стен (facade).
На КАЖДОМ фото (координаты [x, y] в долях 0..1000: x слева направо, y сверху вниз):
- ridgeEnds — концы конька (верхние вершины фронтонов), которые видны;
- openings — окна и двери, видимые целиком: kind (window | door | garage_door | balcony_door), corners — 4 угла проёма
  (по краю рамы/коробки, без наличников и откосов) в порядке: левый верх, правый верх, правый низ, левый низ.
Не выдумывай: не видно или закрыто — не отмечай.
Ответ — только JSON: {"roofType":"","roofTypeRu":"","covering":"","color":"","facade":"","details":[{"kind":"","ru":"","count":1,"seen":true}],
"photos":[{"ridgeEnds":[[x,y]],"openings":[{"kind":"window","corners":[[x,y],[x,y],[x,y],[x,y]]}]}],"hidden":[""]}"""


# ---------- ориентация кадра ----------

def upright_turns(frame: Frame) -> int:
    """Сколько раз повернуть кадр на 90° против часовой, чтобы «вверх» мира смотрел вверх на изображении."""
    up_cam = frame.world_to_cam_cv[:3, :3] @ np.array([0.0, 1.0, 0.0])  # мир-вверх в осях камеры OpenCV
    angle = math.atan2(up_cam[0], -up_cam[1])  # 0 — уже вверх (−y изображения)
    return int(round(angle / (math.pi / 2))) % 4


def to_upright(u: float, v: float, w: int, h: int, turns: int) -> tuple[float, float]:
    """Пиксель сенсорного кадра → пиксель после `turns` поворотов на 90° против часовой."""
    for _ in range(turns):
        u, v, w, h = v, w - u, h, w
    return u, v


def from_upright(u: float, v: float, w: int, h: int, turns: int) -> tuple[float, float]:
    """Обратно: пиксель повёрнутого кадра (w×h — размер СЕНСОРНОГО кадра) → пиксель сенсорного кадра."""
    dims = [(w, h)]
    for _ in range(turns):
        dims.append((dims[-1][1], dims[-1][0]))
    for i in range(turns, 0, -1):
        ww, _ = dims[i - 1]
        u, v = ww - v, u  # обратный шаг одного поворота
    return u, v


# ---------- выбор кадров ----------

def pick_frames(bundle: Bundle, center: np.ndarray, count: int = 6, tier: str = "roof") -> list[Frame]:
    """Самые резкие кадры, по одному на сектор вокруг дома. tier="roof" — снимки 12 Мп/верхний ярус, "wall" — стены."""
    if tier == "roof":
        pool = bundle.stills or [f for f in bundle.frames if f.tier == "roof"] or bundle.frames
    else:
        pool = [f for f in bundle.frames if f.tier == "wall"] or bundle.frames
    sectors: dict[int, Frame] = {}
    for f in pool:
        pos = f.pose[:3, 3]
        sector = int(((math.atan2(pos[2] - center[2], pos[0] - center[0]) + math.pi) / (2 * math.pi)) * count) % count
        if sector not in sectors or f.sharpness > sectors[sector].sharpness:
            sectors[sector] = f
    return [sectors[k] for k in sorted(sectors)]


# ---------- ИИ ----------

LANGUAGE_NAMES = {"en": "English (United States)", "es": "Spanish", "zh": "Simplified Chinese"}


def language_note(lang: str | None) -> str:
    """Описание крыши, деталей и фасада — на языке приложения (поля JSON не переводить)."""
    if not lang or lang.lower().startswith("ru"):
        return ""
    name = LANGUAGE_NAMES.get(lang.split("-")[0].lower(), lang)
    return (f"\nIMPORTANT: write all descriptive text values (roofTypeRu, covering, color, facade, details.ru, hidden) in {name}; "
            "keep JSON keys and enum values (roofType, kind) exactly as specified.")


def ask_openrouter(images_b64: list[str], key: str | None = None, note: str = "") -> tuple[dict, float]:
    key = key or os.environ["OPENROUTER_API_KEY"]
    content = [{"type": "text", "text": f"Фото дома: {len(images_b64)} шт."}]
    for i, b in enumerate(images_b64):
        content += [{"type": "text", "text": f"Фото {i + 1}:"}, {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b}"}}]
    body = {"model": MODEL, "messages": [{"role": "system", "content": SYSTEM + note}, {"role": "user", "content": content}],
            "max_tokens": 8000, "response_format": {"type": "json_object"}, "reasoning": {"effort": "medium", "exclude": True},
            "usage": {"include": True}}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=240) as r:
        result = json.loads(r.read())
    text = result["choices"][0]["message"]["content"]
    start, end = text.find("{"), text.rfind("}")
    return json.loads(text[start:end + 1]), float(result.get("usage", {}).get("cost") or 0)


def prepare_image(data: bytes, turns: int, long_side: int = 1600) -> tuple[str, float]:
    """JPEG → повёрнутый и уменьшенный JPEG (base64) и коэффициент уменьшения."""
    from PIL import Image  # noqa: PLC0415
    image = Image.open(io.BytesIO(data)).convert("RGB")
    for _ in range(turns):
        image = image.transpose(Image.Transpose.ROTATE_90)
    scale = min(1.0, long_side / max(image.size))
    if scale < 1:
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=88)
    return base64.b64encode(buffer.getvalue()).decode(), scale


# ---------- геометрия ----------

def ray(frame: Frame, u: float, v: float) -> tuple[np.ndarray, np.ndarray]:
    fx, fy, cx, cy = frame.K
    cam = frame.cam_to_world_cv
    d = cam[:3, :3] @ np.array([(u - cx) / fx, (v - cy) / fy, 1.0])
    return cam[:3, 3], d / np.linalg.norm(d)


def hit_plane(origin, direction, normal, d) -> np.ndarray | None:
    denom = normal @ direction
    if abs(denom) < 0.15:  # почти параллельно стене — неточно
        return None
    t = -(normal @ origin + d) / denom
    return origin + t * direction if t > 0 else None


def ridge_from_marks(marks: list[tuple[Frame, float, float]], gables: list[tuple], ground_y: float):
    """gables: (нормаль, d[, центр стены, полуширина]) — фронтонные стены, измеренные LiDAR."""
    per_gable: dict[int, list[float]] = {}
    for frame, u, v in marks:
        origin, direction = ray(frame, u, v)
        best = None
        for gi, gable in enumerate(gables):
            normal, d = gable[0], gable[1]
            p = hit_plane(origin, direction, normal, d)
            if p is None:
                continue
            # Только в пределах самой стены (центр и полуширина), а не её бесконечного продолжения.
            if len(gable) >= 4:
                center, half = np.asarray(gable[2]), float(gable[3])
                offset = p - center
                offset[1] = 0
                if np.linalg.norm(offset) > half + 0.5:
                    continue
            dist = np.linalg.norm(p - origin)
            if best is None or dist < best[0]:
                best = (dist, gi, p)
        if best:
            per_gable.setdefault(best[1], []).append(float(best[2][1] - ground_y))
    out = []
    for gi, heights in sorted(per_gable.items()):
        h = np.array(heights)
        med = np.median(h)
        keep = h[np.abs(h - med) < max(0.15, 2.5 * np.median(np.abs(h - med)))]
        out.append({"gable": gi, "height": round(float(np.median(keep)), 3), "frames": int(len(keep)), "rejected": int(len(h) - len(keep)),
                    "spread": round(float(np.std(keep)), 3) if len(keep) > 1 else None})
    return out


def _wall_hit(frame: Frame, u: float, v: float, walls: list[tuple]):
    """Ближайшая стена (в пределах её ширины), в которую попадает луч пикселя: (индекс, точка)."""
    origin, direction = ray(frame, u, v)
    best = None
    for wi, wall in enumerate(walls):
        normal, d = wall[0], wall[1]
        p = hit_plane(origin, direction, normal, d)
        if p is None:
            continue
        if len(wall) >= 4:
            offset = p - np.asarray(wall[2])
            offset[1] = 0
            if np.linalg.norm(offset) > float(wall[3]) + 0.3:
                continue
        dist = np.linalg.norm(p - origin)
        if best is None or dist < best[0]:
            best = (dist, wi, p)
    return None if best is None else (best[1], best[2])


def openings_from_marks(marks: list[tuple[Frame, str, list]], walls: list[tuple], ground_y: float) -> list[dict]:
    """Отметки проёмов (кадр, вид, 4 угла в пикселях сенсорного кадра) → размеры в метрах на плоскости стены.
    Одно окно с нескольких фото сводится в одно (медиана); выбросы по размеру отбрасываются."""
    found = []
    for frame, kind, corners in marks:
        cu = sum(c[0] for c in corners) / 4
        cv = sum(c[1] for c in corners) / 4
        hit = _wall_hit(frame, cu, cv, walls)
        if hit is None:
            continue
        wi, _ = hit
        normal, d = walls[wi][0], walls[wi][1]
        pts = []
        for u, v in corners:
            origin, direction = ray(frame, u, v)
            p = hit_plane(origin, direction, normal, d)
            if p is None:
                break
            pts.append(p)
        if len(pts) != 4:
            continue
        pts = np.array(pts)
        along = np.array([-normal[2], 0.0, normal[0]])
        along /= np.linalg.norm(along)
        s = pts @ along
        y = pts[:, 1] - ground_y
        width = (abs(s[1] - s[0]) + abs(s[2] - s[3])) / 2
        height = (abs(y[3] - y[0]) + abs(y[2] - y[1])) / 2
        if not (0.25 < width < 6 and 0.25 < height < 4):
            continue
        found.append({"wall": wi, "kind": kind, "s": float(s.mean()), "y": float(y.mean()), "width": width, "height": height,
                      "sill": float(min(y[2], y[3])), "center": pts.mean(axis=0)})
    # Сведение: тот же вид, та же стена, центры ближе 35 см.
    groups: list[list[dict]] = []
    for item in found:
        for g in groups:
            if g[0]["wall"] == item["wall"] and g[0]["kind"] == item["kind"] and abs(g[0]["s"] - item["s"]) < 0.35 and abs(g[0]["y"] - item["y"]) < 0.35:
                g.append(item)
                break
        else:
            groups.append([item])
    out = []
    for g in groups:
        w = np.array([x["width"] for x in g])
        h = np.array([x["height"] for x in g])
        keep = [x for x in g if abs(x["width"] - np.median(w)) < 0.15 and abs(x["height"] - np.median(h)) < 0.15] or g
        width = float(np.median([x["width"] for x in keep]))
        height = float(np.median([x["height"] for x in keep]))
        out.append({
            "wall": g[0]["wall"], "kind": g[0]["kind"], "width": round(width, 3), "height": round(height, 3),
            "sill": round(float(np.median([x["sill"] for x in keep])), 3), "area": round(width * height, 3),
            "frames": len(keep), "source": "photo" if len(keep) >= 2 else "assumption",
            "center": [round(float(c), 3) for c in np.median([x["center"] for x in keep], axis=0)],
        })
    return sorted(out, key=lambda o: (o["wall"], o["center"][0], o["center"][2]))


def analyze(bundle: Bundle, center: np.ndarray, gables: list[tuple[np.ndarray, float]], ground_y: float, ask=ask_openrouter,
            walls: list[tuple] | None = None) -> dict:
    """Полный проход: кадры → ИИ → лучи → конёк, окна и двери. `ask` подменяется в тестах."""
    frames = pick_frames(bundle, center)
    if walls:
        # Для окон и дверей — ещё кадры стен (по одному на сектор), без повторов.
        frames += [f for f in pick_frames(bundle, center, count=WALL_FRAMES, tier="wall") if all(f is not g for g in frames)]
    images, meta = [], []
    for f in frames:
        turns = upright_turns(f)
        b64, scale = prepare_image(bundle.image_bytes(f), turns)
        images.append(b64)
        meta.append((f, turns, scale))
    note = language_note(bundle.manifest.get("language"))
    ai, cost = ask(images, note=note) if note and ask is ask_openrouter else ask(images)
    w0, h0 = bundle.manifest["image"]["width"], bundle.manifest["image"]["height"]
    marks, opening_marks = [], []
    for (f, turns, scale), photo in zip(meta, ai.get("photos", [])):
        w, h = f.width or w0, f.height or h0
        uw, uh = (w, h) if turns % 2 == 0 else (h, w)
        for x, y in photo.get("ridgeEnds", []) or []:
            u, v = from_upright(x / 1000 * uw, y / 1000 * uh, w, h, turns)
            marks.append((f, u, v))
        for opening in photo.get("openings", []) or []:
            corners = opening.get("corners") or []
            if len(corners) == 4 and all(isinstance(c, (list, tuple)) and len(c) == 2 for c in corners):
                opening_marks.append((f, str(opening.get("kind") or "window"),
                                      [from_upright(x / 1000 * uw, y / 1000 * uh, w, h, turns) for x, y in corners]))
    return {
        "roofType": ai.get("roofType"), "roofTypeRu": ai.get("roofTypeRu"), "covering": ai.get("covering"), "color": ai.get("color"),
        "details": ai.get("details", []), "hidden": ai.get("hidden", []),
        "facade": ai.get("facade"),
        "ridgeEnds": ridge_from_marks(marks, gables, ground_y), "frames": len(frames), "model": MODEL, "cost": round(cost, 4),
        "openings": openings_from_marks(opening_marks, walls, ground_y) if walls else [],
    }
