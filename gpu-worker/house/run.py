"""Обработка одного скана: python -m house.run scan.zip out/

Шаги этапа 1b (без нейросетей): глубина LiDAR + позы ARKit → TSDF-сетка → плоскости → house.json + house.glb.
Крыша по фото — если задан OPENROUTER_API_KEY. Сегментация и splatting — следующие шаги (SPEC §1.5).
"""
from __future__ import annotations

import json
import math
import os
import sys
import time
from pathlib import Path

import numpy as np
import open3d as o3d

from . import bundle as bundle_io
from . import roof_ai
from .fuse import fuse
from .model import build_house, extract_planes


def stage(text: str, share: float) -> None:
    """Ход работы для сервера: строка «STAGE доля текст» в stderr."""
    print(f"STAGE {share:.2f} {text}", file=sys.stderr, flush=True)


def footprint_latlon(corners, location) -> list | None:
    """Углы дома (мир ARKit gravityAndHeading: x — восток, −z — север) → широта/долгота от точки старта скана."""
    if not location:
        return None
    lat0, lon0 = location["lat"], location["lon"]
    m_lat = 111_132.954 - 559.822 * math.cos(2 * math.radians(lat0)) + 1.175 * math.cos(4 * math.radians(lat0))
    m_lon = 111_412.84 * math.cos(math.radians(lat0)) - 93.5 * math.cos(3 * math.radians(lat0))
    return [[round(lat0 + (-z) / m_lat, 8), round(lon0 + x / m_lon, 8)] for x, z in corners]


def process(scan: Path, out: Path) -> dict:
    started = time.time()
    out.mkdir(parents=True, exist_ok=True)
    stage("Читаем скан", 0.02)
    bundle = bundle_io.load(scan)
    if not bundle.lidar:
        raise SystemExit("скан без LiDAR: нужен путь монокулярной глубины (SPEC §1.5 шаг 2)")
    stage("Собираем 3D-сетку по лидару", 0.1)
    mesh, cloud, used = fuse(bundle)
    stage("Находим стены, землю и скаты", 0.5)
    planes = extract_planes(cloud)
    house = build_house(planes)
    # Крыша по фото (тип, покрытие, детали; конёк — лучами до фронтонов LiDAR). Нужен ключ OpenRouter, ≈ $0.03.
    if os.environ.get("OPENROUTER_API_KEY") and house.get("gableWalls") and os.environ.get("HOUSE_NO_AI") != "1" \
            and bundle.manifest.get("device") != "synthetic":
        try:
            stage("Крыша по фото", 0.7)
            corners = np.array(house["footprint"]["corners"])
            center = np.array([corners[:, 0].mean(), 0.0, corners[:, 1].mean()])
            gables = [(np.array(g["normal"]), g["d"], np.array(g["center"]), g["halfWidth"]) for g in house["gableWalls"]]
            photo = roof_ai.analyze(bundle, center, gables, house["groundY"])
            house["roof"]["byPhoto"] = photo
            ends = [e["height"] for e in photo["ridgeEnds"] if e["frames"] >= 2]
            ridge = house["roof"].get("ridgeHeight", {})
            if ends and ridge.get("source") != "measured":
                house["roof"]["ridgeHeight"] = {"value": round(float(np.median(ends)), 3), "source": "photo",
                                                "note": "конёк отмечен ИИ на фото, высота — лучами из поз ARKit до фронтона LiDAR"}
            if photo.get("roofType"):
                house["roof"]["typeByPhoto"] = photo["roofType"]
        except Exception as error:  # ИИ недоступен — геометрия LiDAR остаётся
            house["roof"]["byPhotoError"] = str(error)[:300]
    # Контрольный размер (рулетка): сравнение с измеренной стороной футпринта.
    control = [c for c in bundle.manifest.get("control", []) if c.get("kind") == "wall_length"]
    if control:
        measured = [house["footprint"]["gableWidth"]["value"], house["footprint"]["length"]["value"]]
        target = control[0]["meters"]
        nearest = min(measured, key=lambda m: abs(m - target))
        house["control"] = {"tape": target, "model": nearest, "deltaCm": round((nearest - target) * 100, 1)}
    house["quality"] = {
        "framesWithDepth": used, "frames": len(bundle.frames), "rejectedBlurry": bundle.manifest.get("rejectedBlurry", 0),
        "coverage": bundle.manifest.get("coverage"), "seconds": round(time.time() - started, 1),
    }
    world = bundle.manifest.get("world", {})
    house["geo"] = {"location": world.get("location"), "alignment": world.get("alignment")}
    if world.get("alignment") == "gravityAndHeading":
        # Предварительно: точность = GPS (5–15 м) и компас (5–10°); точно — после привязки по углам участка.
        house["geo"]["footprintLatLon"] = footprint_latlon(house["footprint"]["corners"], world.get("location"))
    if bundle.manifest.get("parcel"):
        house["parcel"] = {"cadNumber": bundle.manifest["parcel"].get("cadNumber")}
    stage("Сохраняем модель", 0.9)
    light = mesh.simplify_quadric_decimation(120_000)
    light.compute_vertex_normals()
    o3d.io.write_triangle_mesh(str(out / "house.glb"), light)
    # OBJ — его открывает iPhone (ModelIO/SceneKit) без сторонних библиотек.
    o3d.io.write_triangle_mesh(str(out / "house.obj"), light, write_vertex_colors=False, write_triangle_uvs=False)
    (out / "house.json").write_text(json.dumps(house, ensure_ascii=False, indent=1))
    return house


if __name__ == "__main__":
    target = Path(sys.argv[2] if len(sys.argv) > 2 else "out")
    try:
        result = process(Path(sys.argv[1]), target)
    except (ValueError, SystemExit) as error:
        # Понятная причина для приложения (короткий скан, нет стен, нет LiDAR).
        print(f"FAIL {error}", file=sys.stderr, flush=True)
        sys.exit(2)
    stage("Готово", 1.0)
    print(json.dumps(result, ensure_ascii=False, indent=1))
