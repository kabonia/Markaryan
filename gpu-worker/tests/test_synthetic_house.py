"""Синтетический дом с известными размерами → пакет скана как с iPhone → обработка → сверка с правдой.

Дом: 10 × 8 м, карниз 3,00 м, конёк 6,00 м (уклон 36,87°), двускатная крыша, конёк вдоль длинной стороны.
Обход: прямоугольник в 3,2 м от стен, шаг 0,6 м, два наклона камеры. LiDAR: 256×192, до 5 м, шум 5 мм + 0,3 % дальности.
"""
from __future__ import annotations

import math
import os

import numpy as np
import open3d as o3d

from house import bundle as bundle_io
from house.run import process
from house.triangulate import robust_triangulate

LENGTH, WIDTH, EAVE, RIDGE = 10.0, 8.0, 3.0, 6.0
PITCH = math.degrees(math.atan((RIDGE - EAVE) / (WIDTH / 2)))
IMG_W, IMG_H, F = 1920, 1440, 1500.0
DEP_W, DEP_H = 256, 192


def house_mesh() -> o3d.geometry.TriangleMesh:
    x, z = LENGTH / 2, WIDTH / 2
    v = [
        # стены: углы у земли и у карниза
        (-x, 0, -z), (x, 0, -z), (x, 0, z), (-x, 0, z),
        (-x, EAVE, -z), (x, EAVE, -z), (x, EAVE, z), (-x, EAVE, z),
        # конёк
        (-x, RIDGE, 0), (x, RIDGE, 0),
        # земля
        (-40, 0, -40), (40, 0, -40), (40, 0, 40), (-40, 0, 40),
    ]
    t = [
        (0, 1, 5), (0, 5, 4), (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7),  # стены
        (4, 5, 9), (4, 9, 8), (6, 7, 8), (6, 8, 9),                                              # скаты
        (4, 8, 7), (5, 6, 9),                                                                     # фронтоны
        (10, 12, 11), (10, 13, 12),                                                               # земля
    ]
    mesh = o3d.geometry.TriangleMesh(o3d.utility.Vector3dVector(np.array(v, float)), o3d.utility.Vector3iVector(np.array(t)))
    return mesh


def look_pose(position, target) -> np.ndarray:
    """Поза ARKit (камера→мир): x вправо, y вверх, смотрит вдоль −z."""
    f = np.asarray(target, float) - position
    f /= np.linalg.norm(f)
    x = np.cross(f, [0, 1, 0])
    x /= np.linalg.norm(x)
    y = np.cross(x, f)
    pose = np.eye(4)
    pose[:3, 0], pose[:3, 1], pose[:3, 2], pose[:3, 3] = x, y, -f, position
    return pose


def walk(offset: float, step: float):
    """Позиции по прямоугольнику вокруг дома и ближайшая точка стены для каждой."""
    hx, hz = LENGTH / 2 + offset, WIDTH / 2 + offset
    corners = [(-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz), (-hx, -hz)]
    for (x0, z0), (x1, z1) in zip(corners, corners[1:]):
        n = int(math.hypot(x1 - x0, z1 - z0) / step)
        for i in range(n):
            px, pz = x0 + (x1 - x0) * i / n, z0 + (z1 - z0) * i / n
            nx, nz = np.clip(px, -LENGTH / 2, LENGTH / 2), np.clip(pz, -WIDTH / 2, WIDTH / 2)
            yield np.array([px, 1.5, pz]), np.array([nx, 0.0, nz])


def render_depth(scene, pose, rng):
    k = F * DEP_W / IMG_W
    u, v = np.meshgrid(np.arange(DEP_W), np.arange(DEP_H))
    dirs_cv = np.stack([(u - DEP_W / 2) / k, (v - DEP_H / 2) / k, np.ones_like(u, float)], -1).reshape(-1, 3)
    cam_cv = pose @ bundle_io.ARKIT_TO_CV
    dirs = dirs_cv @ cam_cv[:3, :3].T
    norms = np.linalg.norm(dirs, axis=1, keepdims=True)
    rays = np.hstack([np.repeat(cam_cv[:3, 3][None], len(dirs), 0), dirs / norms]).astype(np.float32)
    t = scene.cast_rays(o3d.core.Tensor(rays))["t_hit"].numpy()
    depth = (t / norms[:, 0]).reshape(DEP_H, DEP_W)
    depth = depth + rng.normal(0, 1, depth.shape) * (0.005 + 0.003 * depth)
    valid = np.isfinite(depth) & (depth < 5.0)
    conf = np.where(valid, 2, 0).astype(np.uint8)
    depth = np.where(valid, depth, 0).astype(np.float16)
    return depth, conf


def make_scan(tmp_path):
    rng = np.random.default_rng(7)
    scene = o3d.t.geometry.RaycastingScene()
    scene.add_triangles(o3d.t.geometry.TriangleMesh.from_legacy(house_mesh()))
    frames, files = [], {}
    jpeg = bundle_io.tiny_jpeg()
    i = 0
    for position, wall in walk(3.2, 0.6):
        for aim_height, tier in ((2.0, "wall"), (4.6, "roof")):
            i += 1
            pose = look_pose(position, wall + [0, aim_height, 0])
            depth, conf = render_depth(scene, pose, rng)
            name = f"{i:06d}"
            files[f"frames/{name}.jpg"] = jpeg
            files[f"depth/{name}.f16"] = depth.tobytes()
            files[f"conf/{name}.u8"] = conf.tobytes()
            frames.append({"i": i, "t": i * 0.4, "image": f"frames/{name}.jpg", "depth": f"depth/{name}.f16", "conf": f"conf/{name}.u8",
                           "pose": pose.T.reshape(-1).tolist(), "K": [F, F, IMG_W / 2, IMG_H / 2], "tracking": "normal",
                           "exposure": 0.008, "tier": tier, "sharpness": 100.0})
    manifest = {
        "format": "smetapro-house-scan", "version": 1, "kind": "house", "createdAt": "2026-11-25T00:00:00Z",
        "device": "synthetic", "lidar": True, "ios": "26", "image": {"width": IMG_W, "height": IMG_H},
        "depth": {"width": DEP_W, "height": DEP_H, "format": "f16", "units": "m"},
        "world": {"alignment": "gravityAndHeading", "up": [0, 1, 0], "units": "m"},
        "coverage": {"sectors": 36, "walls": 1.0, "roof": 1.0},
        "control": [{"kind": "wall_length", "meters": 10.0, "note": "рулетка"}], "frames": frames,
    }
    return bundle_io.write(tmp_path, manifest, files)


def notice(title, text):
    if os.environ.get("GITHUB_ACTIONS"):
        print(f"::notice title={title}::{text}")
    print(title, text)


def test_house_dimensions(tmp_path):
    scan = make_scan(tmp_path)
    house = process(scan, tmp_path / "out")
    fp = house["footprint"]
    roof = house["roof"]
    width, length = fp["gableWidth"]["value"], fp["length"]["value"]
    eave = house["eaveHeight"]["value"]
    ridge = roof["ridgeHeight"]["value"]
    pitch = roof["pitchDeg"]["value"]
    notice("Синтетический дом — правда 8.00 × 10.00 м; карниз 3.00; конёк 6.00; 36.87°",
           f"ширина {width:.3f} м, длина {length:.3f} м, карниз {eave:.3f} м, конёк {ridge:.3f} м ({roof['ridgeHeight']['source']}), "
           f"уклон {pitch:.2f}°, по кромке фронтона {roof.get('ridgeByGableEdge')} м, рулетка Δ {house['control']['deltaCm']} см, {house['quality']['seconds']} с")
    assert abs(width - WIDTH) < 0.03
    assert abs(length - LENGTH) < 0.03
    assert abs(eave - EAVE) < 0.04
    assert roof["type"] == "gable"
    assert abs(ridge - RIDGE) < 0.10
    assert abs(pitch - PITCH) < 1.5
    assert abs(house["control"]["deltaCm"]) < 3
    assert (tmp_path / "out" / "house.glb").stat().st_size > 1000


def test_ridge_by_triangulation():
    """Конёк по разметке на фото (ИИ отмечает точку) с известными позами ARKit — даже вне дальности LiDAR."""
    rng = np.random.default_rng(3)
    apex = np.array([LENGTH / 2, RIDGE, 0.0])
    projections, pixels = [], []
    for position, wall in walk(9.0, 2.5):
        if position[0] < LENGTH / 2:          # торец виден только с этой стороны
            continue
        frame = bundle_io.Frame(index=0, image="", pose=look_pose(position, [LENGTH / 2, 4.5, 0]), K=(F, F, IMG_W / 2, IMG_H / 2))
        P = frame.projection()
        p = P @ np.append(apex, 1)
        u, v = p[0] / p[2], p[1] / p[2]
        if 0 <= u < IMG_W and 0 <= v < IMG_H and p[2] > 0:
            projections.append(P)
            pixels.append((u + rng.normal(0, 2), v + rng.normal(0, 2)))
    # Один кадр с грубой ошибкой разметки (ИИ промахнулся на 60 px) — должен отброситься.
    pixels[0] = (pixels[0][0] + 60, pixels[0][1] - 40)
    point, error, used = robust_triangulate(projections, pixels)
    notice("Конёк триангуляцией", f"ошибка {np.linalg.norm(point - apex) * 100:.1f} см по {used} кадрам из {len(pixels)}, перепроекция {error:.1f} px")
    assert np.linalg.norm(point - apex) < 0.05
    assert used < len(pixels)
