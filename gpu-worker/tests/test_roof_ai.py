"""Конёк по фото: ИИ (подменён) отмечает концы конька на кадрах «iPhone вертикально» → лучи → высота."""
from __future__ import annotations

import math

import numpy as np

from house import bundle as bundle_io
from house.roof_ai import analyze, from_upright, to_upright, upright_turns
from test_synthetic_house import EAVE, F, IMG_H, IMG_W, LENGTH, RIDGE, WIDTH, look_pose, notice

APEXES = [np.array([LENGTH / 2, RIDGE, 0.0]), np.array([-LENGTH / 2, RIDGE, 0.0])]


def roll(pose: np.ndarray, degrees: float) -> np.ndarray:
    """Поворот камеры вокруг оси взгляда (iPhone вертикально — сенсор «на боку»)."""
    a = math.radians(degrees)
    r = np.eye(4)
    r[:2, :2] = [[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]]
    return pose @ r


def roof_height(z: float) -> float:
    return EAVE + (RIDGE - EAVE) * (1 - abs(z) / (WIDTH / 2))


def visible(cam: np.ndarray, point: np.ndarray) -> bool:
    for t in np.linspace(0.02, 0.97, 200):
        p = cam + (point - cam) * t
        if abs(p[0]) < LENGTH / 2 - 0.01 and abs(p[2]) < WIDTH / 2 - 0.01 and p[1] < roof_height(p[2]) - 0.01:
            return False
    return True


def test_rotation_roundtrip():
    for turns in range(4):
        u, v = to_upright(100.0, 300.0, IMG_W, IMG_H, turns)
        back = from_upright(u, v, IMG_W, IMG_H, turns)
        assert np.allclose(back, (100.0, 300.0)), (turns, back)


def test_ridge_heights_from_marks(tmp_path):
    rng = np.random.default_rng(11)
    frames, files = [], {}
    jpeg = bundle_io.tiny_jpeg(16, 12)
    i = 0
    for angle in range(0, 360, 20):
        a = math.radians(angle)
        position = np.array([13 * math.cos(a), 1.6, 11 * math.sin(a)])
        i += 1
        pose = roll(look_pose(position, [0, 4.5, 0]), 90 if i % 2 else -90)  # то так, то этак — как держат телефон
        files[f"frames/{i:06d}.jpg"] = jpeg
        frames.append({"i": i, "image": f"frames/{i:06d}.jpg", "pose": pose.T.reshape(-1).tolist(), "K": [F, F, IMG_W / 2, IMG_H / 2],
                       "tier": "roof", "sharpness": float(rng.uniform(50, 100))})
    manifest = {"format": "smetapro-house-scan", "version": 1, "lidar": True, "image": {"width": IMG_W, "height": IMG_H}, "frames": frames}
    bundle = bundle_io.load(bundle_io.write(tmp_path, manifest, files))
    assert all(upright_turns(f) in (1, 3) for f in bundle.frames)

    gables = [(np.array([1.0, 0, 0]), -LENGTH / 2, [LENGTH / 2, 0, 0], WIDTH / 2), (np.array([-1.0, 0, 0]), -LENGTH / 2, [-LENGTH / 2, 0, 0], WIDTH / 2)]
    asked = {}

    def fake_ai(images):
        from house.roof_ai import pick_frames  # noqa: PLC0415
        picked = pick_frames(bundle, np.zeros(3))
        asked["n"] = len(images)
        photos = []
        for k, f in enumerate(picked):
            turns = upright_turns(f)
            uw, uh = (IMG_W, IMG_H) if turns % 2 == 0 else (IMG_H, IMG_W)
            ends = []
            for apex in APEXES:
                p = f.projection() @ np.append(apex, 1)
                if p[2] <= 0 or not visible(f.pose[:3, 3], apex):
                    continue
                u, v = p[0] / p[2], p[1] / p[2]
                if not (0 <= u < IMG_W and 0 <= v < IMG_H):
                    continue
                x, y = to_upright(u, v, IMG_W, IMG_H, turns)
                ends.append([x / uw * 1000 + rng.normal(0, 1.5), y / uh * 1000 + rng.normal(0, 1.5)])
            if k == 0 and ends:
                ends[0][1] += 25  # ИИ промахнулся на одном фото
            photos.append({"ridgeEnds": ends})
        return {"roofType": "gable", "photos": photos}, 0.0

    result = analyze(bundle, np.zeros(3), gables, ground_y=0.0, ask=fake_ai)
    heights = [e["height"] for e in result["ridgeEnds"]]
    notice("Конёк по фото (лучи до стены LiDAR)", f"высоты {heights} м при правде {RIDGE} м; кадров {asked['n']}; "
           f"отброшено {[e['rejected'] for e in result['ridgeEnds']]}")
    assert len(heights) == 2
    assert all(abs(h - RIDGE) < 0.05 for h in heights)


# Окна и двери «виртуального дома»: (стена: нормаль, d, центр, полуширина), вид, центр вдоль стены, низ, ширина, высота.
WALLS = [
    (np.array([0.0, 0, -1.0]), -WIDTH / 2, [0, 0, -WIDTH / 2], LENGTH / 2),   # длинная стена z = −4
    (np.array([-1.0, 0, 0.0]), -LENGTH / 2, [-LENGTH / 2, 0, 0], WIDTH / 2),  # торец x = −5
    (np.array([0.0, 0, 1.0]), -WIDTH / 2, [0, 0, WIDTH / 2], LENGTH / 2),     # длинная стена z = +4
    (np.array([1.0, 0, 0.0]), -LENGTH / 2, [LENGTH / 2, 0, 0], WIDTH / 2),    # торец x = +5
]
OPENINGS = [
    ("window", 0, -2.5, 0.9, 1.20, 1.40), ("window", 0, 2.5, 0.9, 1.50, 1.40),
    ("door", 1, 0.0, 0.0, 0.90, 2.10), ("window", 2, 0.0, 0.9, 1.20, 1.40),
]


def opening_corners(wall_index, along, bottom, width, height):
    normal, _, center, _ = WALLS[wall_index]
    a = np.array([-normal[2], 0.0, normal[0]])
    c = np.array(center, float) + a * along
    left, right = c - a * width / 2, c + a * width / 2
    # Вид снаружи: «лево» на изображении — со стороны −a, если смотреть на стену снаружи.
    return [left + [0, bottom + height, 0], right + [0, bottom + height, 0], right + [0, bottom, 0], left + [0, bottom, 0]]


def test_openings_from_marks(tmp_path):
    rng = np.random.default_rng(5)
    frames, files = [], {}
    jpeg = bundle_io.tiny_jpeg(16, 12)
    for i, angle in enumerate(range(0, 360, 15), start=1):
        a = math.radians(angle)
        position = np.array([13 * math.cos(a), 1.5, 11.5 * math.sin(a)])
        pose = roll(look_pose(position, [0.6 * position[0] / 2, 1.6, 0.6 * position[2] / 2]), 90 if i % 2 else -90)
        files[f"frames/{i:06d}.jpg"] = jpeg
        frames.append({"i": i, "image": f"frames/{i:06d}.jpg", "pose": pose.T.reshape(-1).tolist(), "K": [F, F, IMG_W / 2, IMG_H / 2],
                       "tier": "wall", "sharpness": float(rng.uniform(50, 100))})
    manifest = {"format": "smetapro-house-scan", "version": 1, "lidar": True, "image": {"width": IMG_W, "height": IMG_H}, "frames": frames}
    bundle = bundle_io.load(bundle_io.write(tmp_path, manifest, files))

    def fake_ai(images):
        from house.roof_ai import pick_frames  # noqa: PLC0415
        picked = pick_frames(bundle, np.zeros(3))
        from house.roof_ai import WALL_FRAMES  # noqa: PLC0415
        picked += [f for f in pick_frames(bundle, np.zeros(3), count=WALL_FRAMES, tier="wall") if all(f is not g for g in picked)]
        assert len(picked) == len(images)
        photos = []
        for f in picked:
            turns = upright_turns(f)
            uw, uh = (IMG_W, IMG_H) if turns % 2 == 0 else (IMG_H, IMG_W)
            cam = f.pose[:3, 3]
            marks = []
            for kind, wi, along, bottom, width, height in OPENINGS:
                normal = WALLS[wi][0]
                corners3 = opening_corners(wi, along, bottom, width, height)
                if (cam - np.array(WALLS[wi][2])) @ normal <= 0.5:   # стену видно только снаружи
                    continue
                pix = []
                for p3 in corners3:
                    p = f.projection() @ np.append(p3, 1)
                    u, v = p[0] / p[2], p[1] / p[2]
                    if p[2] <= 0 or not (0 <= u < IMG_W and 0 <= v < IMG_H):
                        break
                    x, y = to_upright(u, v, IMG_W, IMG_H, turns)
                    pix.append([x / uw * 1000 + rng.normal(0, 1.2), y / uh * 1000 + rng.normal(0, 1.2)])
                if len(pix) == 4:
                    marks.append({"kind": kind, "corners": pix})
            photos.append({"ridgeEnds": [], "openings": marks})
        return {"roofType": "gable", "photos": photos}, 0.0

    result = analyze(bundle, np.zeros(3), [], ground_y=0.0, ask=fake_ai, walls=WALLS)
    found = result["openings"]
    lines = "; ".join(f"{o['kind']} {o['width']:.2f}×{o['height']:.2f} низ {o['sill']:.2f} ({o['frames']} фото)" for o in found)
    notice("Окна и двери по фото — правда 1.20×1.40 ×2; 1.50×1.40; дверь 0.90×2.10", lines)
    assert len(found) == len(OPENINGS)
    for kind, wi, along, bottom, width, height in OPENINGS:
        match = [o for o in found if o["kind"] == kind and o["wall"] == wi and abs(o["width"] - width) < 0.04 and abs(o["height"] - height) < 0.04]
        assert match, (kind, wi, width, height, found)
        assert abs(match[0]["sill"] - bottom) < 0.04
