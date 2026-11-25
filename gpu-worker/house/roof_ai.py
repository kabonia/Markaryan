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

SYSTEM = """Ты — инженер-кровельщик. На фото один частный дом, снятый с земли (несколько ракурсов).
Определи тип крыши (gable|hip|half_hip|mansard|gambrel|shed|flat|pyramid|cross_gable|complex), покрытие, цвет и детали
(трубы, слуховые и мансардные окна, водостоки, снегозадержатели, ендовы; seen=false — если не видно, а предполагаешь).
На КАЖДОМ фото отметь концы конька (верхние вершины фронтонов), которые видны: координаты [x, y] в долях 0..1000
(x слева направо, y сверху вниз). Не выдумывай: не видно — пустой список.
Ответ — только JSON: {"roofType":"","roofTypeRu":"","covering":"","color":"","details":[{"kind":"","ru":"","count":1,"seen":true}],
"photos":[{"ridgeEnds":[[x,y]]}],"hidden":[""]}"""


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

def pick_frames(bundle: Bundle, center: np.ndarray, count: int = 6) -> list[Frame]:
    pool = bundle.stills or [f for f in bundle.frames if f.tier == "roof"] or bundle.frames
    sectors: dict[int, Frame] = {}
    for f in pool:
        pos = f.pose[:3, 3]
        sector = int(((math.atan2(pos[2] - center[2], pos[0] - center[0]) + math.pi) / (2 * math.pi)) * count) % count
        if sector not in sectors or f.sharpness > sectors[sector].sharpness:
            sectors[sector] = f
    return [sectors[k] for k in sorted(sectors)]


# ---------- ИИ ----------

def ask_openrouter(images_b64: list[str], key: str | None = None) -> tuple[dict, float]:
    key = key or os.environ["OPENROUTER_API_KEY"]
    content = [{"type": "text", "text": f"Фото дома: {len(images_b64)} шт."}]
    for i, b in enumerate(images_b64):
        content += [{"type": "text", "text": f"Фото {i + 1}:"}, {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b}"}}]
    body = {"model": MODEL, "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": content}],
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


def analyze(bundle: Bundle, center: np.ndarray, gables: list[tuple[np.ndarray, float]], ground_y: float, ask=ask_openrouter) -> dict:
    """Полный проход: кадры → ИИ → лучи → конёк. `ask` подменяется в тестах."""
    frames = pick_frames(bundle, center)
    images, meta = [], []
    for f in frames:
        turns = upright_turns(f)
        b64, scale = prepare_image(bundle.image_bytes(f), turns)
        images.append(b64)
        meta.append((f, turns, scale))
    ai, cost = ask(images)
    w0, h0 = bundle.manifest["image"]["width"], bundle.manifest["image"]["height"]
    marks = []
    for (f, turns, scale), photo in zip(meta, ai.get("photos", [])):
        w, h = f.width or w0, f.height or h0
        uw, uh = (w, h) if turns % 2 == 0 else (h, w)
        for x, y in photo.get("ridgeEnds", []) or []:
            u, v = from_upright(x / 1000 * uw, y / 1000 * uh, w, h, turns)
            marks.append((f, u, v))
    return {
        "roofType": ai.get("roofType"), "roofTypeRu": ai.get("roofTypeRu"), "covering": ai.get("covering"), "color": ai.get("color"),
        "details": ai.get("details", []), "hidden": ai.get("hidden", []),
        "ridgeEnds": ridge_from_marks(marks, gables, ground_y), "frames": len(frames), "model": MODEL, "cost": round(cost, 4),
    }
