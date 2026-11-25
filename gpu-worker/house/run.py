"""Обработка одного скана: python -m house.run scan.zip out/

Шаги этапа 1b (без нейросетей): глубина LiDAR + позы ARKit → TSDF-сетка → плоскости → house.json + house.glb.
Сегментация, крыша по фото (ИИ + триангуляция) и splatting подключаются следующими шагами (SPEC §1.5).
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import open3d as o3d

from . import bundle as bundle_io
from .fuse import fuse
from .model import build_house, extract_planes


def process(scan: Path, out: Path) -> dict:
    started = time.time()
    out.mkdir(parents=True, exist_ok=True)
    bundle = bundle_io.load(scan)
    if not bundle.lidar:
        raise SystemExit("скан без LiDAR: нужен путь монокулярной глубины (SPEC §1.5 шаг 2)")
    mesh, cloud, used = fuse(bundle)
    planes = extract_planes(cloud)
    house = build_house(planes)
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
    house["geo"] = {"location": bundle.manifest.get("world", {}).get("location"), "alignment": bundle.manifest.get("world", {}).get("alignment")}
    if bundle.manifest.get("parcel"):
        house["parcel"] = {"cadNumber": bundle.manifest["parcel"].get("cadNumber")}
    o3d.io.write_triangle_mesh(str(out / "house.glb"), mesh.simplify_quadric_decimation(200_000))
    (out / "house.json").write_text(json.dumps(house, ensure_ascii=False, indent=1))
    return house


if __name__ == "__main__":
    result = process(Path(sys.argv[1]), Path(sys.argv[2] if len(sys.argv) > 2 else "out"))
    print(json.dumps(result, ensure_ascii=False, indent=1))
