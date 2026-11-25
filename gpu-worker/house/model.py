"""Облако точек → плоскости → параметрический дом: футпринт, высота карниза, уклон, конёк.

Мир ARKit: y — вверх (гравитация), x/z — горизонталь. Все размеры в метрах.
У каждого числа — источник: measured (LiDAR), extrapolated (LiDAR + продолжение прямой кромки фронтона),
photo (триангуляция по кадрам) или assumption.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import open3d as o3d


@dataclass
class Plane:
    normal: np.ndarray      # единичная
    d: float                # n·x + d = 0
    points: np.ndarray      # N×3 inliers
    kind: str               # ground | wall | roof | other

    @property
    def size(self) -> int:
        return len(self.points)


def extract_planes(cloud: o3d.geometry.PointCloud, max_planes: int = 16, distance: float = 0.03,
                   min_points: int = 150) -> list[Plane]:
    """Последовательный RANSAC; каждая плоскость дополнительно режется на связные куски (DBSCAN)."""
    rest = cloud
    planes: list[Plane] = []
    for _ in range(max_planes * 2):
        if len(rest.points) < min_points or len(planes) >= max_planes:
            break
        model, inliers = rest.segment_plane(distance_threshold=distance, ransac_n=3, num_iterations=2000)
        if len(inliers) < min_points:
            break
        a, b, c, d = model
        n = np.array([a, b, c])
        norm = np.linalg.norm(n)
        n, d = n / norm, d / norm
        part = rest.select_by_index(inliers)
        rest = rest.select_by_index(inliers, invert=True)
        # Одна математическая плоскость может пройти через разные стены: берём связные куски.
        labels = np.asarray(part.cluster_dbscan(eps=0.25, min_points=8))
        pts = np.asarray(part.points)
        for label in set(labels.tolist()) - {-1}:
            chunk = pts[labels == label]
            if len(chunk) < min_points:
                continue
            nn = n if n[1] >= 0 or abs(n[1]) < 0.1 else -n
            kind = "ground" if abs(nn[1]) > 0.97 else "wall" if abs(nn[1]) < 0.12 else "roof"
            planes.append(Plane(normal=nn, d=float(-nn @ chunk.mean(axis=0)), points=chunk, kind=kind))
    return planes


def _dominant_axis(walls: list[Plane]) -> float:
    """Главное направление стен (угол по модулю 90°), взвешенное числом точек."""
    angles = np.array([math.atan2(w.normal[2], w.normal[0]) % (math.pi / 2) for w in walls])
    weights = np.array([w.size for w in walls], dtype=float)
    # Среднее на окружности с периодом 90°.
    s = (weights * np.sin(angles * 4)).sum()
    c = (weights * np.cos(angles * 4)).sum()
    return math.atan2(s, c) / 4


def _gable_profile(points2d: np.ndarray, eave: float, bin_size: float = 0.1):
    """Кромка фронтона: верхняя огибающая (s, h) → две прямые → конёк и уклоны (даже если верх не снят)."""
    upper = points2d[points2d[:, 1] > eave + 0.15]
    if len(upper) < 30:
        return None
    s_min, s_max = points2d[:, 0].min(), points2d[:, 0].max()
    bins = np.arange(s_min, s_max + bin_size, bin_size)
    env = []
    for lo in bins:
        sel = upper[(upper[:, 0] >= lo) & (upper[:, 0] < lo + bin_size)]
        if len(sel) >= 3:
            env.append((lo + bin_size / 2, np.percentile(sel[:, 1], 95)))
    if len(env) < 6:
        return None
    env = np.array(env)
    mid = (s_min + s_max) / 2
    left, right = env[env[:, 0] < mid], env[env[:, 0] >= mid]
    if len(left) < 3 or len(right) < 3:
        return None
    kl, bl = np.polyfit(left[:, 0], left[:, 1], 1)
    kr, br = np.polyfit(right[:, 0], right[:, 1], 1)
    if kl <= 0.05 or kr >= -0.05:
        return None
    s_apex = (br - bl) / (kl - kr)
    h_apex = kl * s_apex + bl
    seen_top = env[:, 1].max()
    return {
        "ridge": float(h_apex), "apexOffset": float(s_apex - mid),
        "pitchLeft": math.degrees(math.atan(kl)), "pitchRight": math.degrees(math.atan(-kr)),
        "seenUpTo": float(seen_top), "residual": float(np.std(np.concatenate([
            left[:, 1] - (kl * left[:, 0] + bl), right[:, 1] - (kr * right[:, 0] + br)]))),
    }


def _value(value, source, sigma=None, note=None):
    out = {"value": None if value is None else round(float(value), 3), "source": source}
    if sigma is not None:
        out["sigma"] = round(float(sigma), 3)
    if note:
        out["note"] = note
    return out


def build_house(planes: list[Plane]) -> dict:
    grounds = [p for p in planes if p.kind == "ground"]
    walls = [p for p in planes if p.kind == "wall"]
    roofs = [p for p in planes if p.kind == "roof"]
    if not walls:
        raise ValueError("стены не найдены — скан слишком короткий или без глубины")
    ground_y = None
    if grounds:
        # Земля — самая нижняя крупная горизонталь (не потолок навеса и не подоконник).
        biggest = max(g.size for g in grounds)
        candidates = [g for g in grounds if g.size > biggest * 0.25]
        ground_y = float(min(np.median(g.points[:, 1]) for g in candidates))
    else:
        ground_y = float(min(np.percentile(w.points[:, 1], 1) for w in walls))

    theta = _dominant_axis(walls)
    u = np.array([math.cos(theta), 0.0, math.sin(theta)])   # ось A
    v = np.array([-math.sin(theta), 0.0, math.cos(theta)])  # ось B
    groups = {"A": [], "B": []}
    for w in walls:
        along_a = abs(w.normal @ u) > abs(w.normal @ v)
        groups["A" if along_a else "B"].append(w)

    def extent(group, axis):
        if len(group) < 2:
            return None
        offsets = [(float(w.points.mean(axis=0) @ axis), w) for w in group]
        offsets.sort(key=lambda t: t[0])
        lo, hi = offsets[0], offsets[-1]
        if hi[0] - lo[0] < 2.0:
            return None
        # Расстояние между плоскостями — по точкам обеих стен (усреднение снимает шум LiDAR).
        sigma = math.hypot(np.std(lo[1].points @ axis), np.std(hi[1].points @ axis)) / math.sqrt(min(lo[1].size, hi[1].size))
        return hi[0] - lo[0], lo, hi, sigma

    ext_a, ext_b = extent(groups["A"], u), extent(groups["B"], v)
    if ext_a is None or ext_b is None:
        raise ValueError("не хватает противоположных стен — обойдите дом целиком")

    def tops(group):
        return [float(np.percentile(w.points[:, 1], 98) - ground_y) for w in group]

    tops_a, tops_b = tops(groups["A"]), tops(groups["B"])
    # Фронтонные стены выше карнизных: по ним определяем направление конька.
    gable_axis = "A" if max(tops_a) > max(tops_b) + 0.3 else "B" if max(tops_b) > max(tops_a) + 0.3 else None
    eave_group = groups["B"] if gable_axis == "A" else groups["A"]
    eave_tops = [float(np.percentile(w.points[:, 1], 99) - ground_y) for w in eave_group]
    eave = float(np.median(eave_tops))
    eave_sigma = float(np.std(eave_tops)) if len(eave_tops) > 1 else 0.03

    width_gable = ext_b[0] if gable_axis == "A" else ext_a[0]   # ширина торца (под фронтоном)
    length = ext_a[0] if gable_axis == "A" else ext_b[0]

    roof = {"type": "flat_or_unknown"}
    if gable_axis:
        gable_walls = groups[gable_axis]
        along = v if gable_axis == "A" else u
        profiles = []
        for w in gable_walls:
            p2 = np.column_stack([w.points @ along, w.points[:, 1] - ground_y])
            prof = _gable_profile(p2, eave)
            if prof:
                profiles.append(prof)
        if profiles:
            ridge = float(np.median([p["ridge"] for p in profiles]))
            pitch_l = float(np.median([p["pitchLeft"] for p in profiles]))
            pitch_r = float(np.median([p["pitchRight"] for p in profiles]))
            seen = max(p["seenUpTo"] for p in profiles)
            measured = seen >= ridge - 0.15
            roof = {
                "type": "gable",
                "ridgeHeight": _value(ridge, "measured" if measured else "extrapolated", sigma=max(0.02, np.median([p["residual"] for p in profiles]) * 3),
                                      note=None if measured else f"LiDAR достал до {seen:.2f} м; конёк — продолжение кромок фронтона"),
                "pitchDeg": _value((pitch_l + pitch_r) / 2, "measured" if measured else "extrapolated"),
                "pitchLeftDeg": round(pitch_l, 2), "pitchRightDeg": round(pitch_r, 2),
                "symmetric": abs(pitch_l - pitch_r) < 3,
                "ridgeDirection": "A" if gable_axis == "B" else "B",
            }
        else:
            roof = {"type": "gable", "ridgeHeight": _value(None, "assumption", note="кромка фронтона не снята — нужна триангуляция по фото")}
    if roofs:
        slopes = [math.degrees(math.acos(min(1.0, abs(r.normal[1])))) for r in roofs]
        roof["planesSeen"] = [{"pitchDeg": round(s, 2), "points": r.size} for s, r in zip(slopes, roofs)]

    # Углы футпринта в мире (по пересечениям крайних стен).
    a_lo, a_hi = ext_a[1][0], ext_a[2][0]
    b_lo, b_hi = ext_b[1][0], ext_b[2][0]
    corners = [(u * a + v * b) for a, b in ((a_lo, b_lo), (a_hi, b_lo), (a_hi, b_hi), (a_lo, b_hi))]
    return {
        "footprint": {
            "gableWidth": _value(width_gable, "measured", sigma=(ext_b if gable_axis == "A" else ext_a)[3] + 0.01),
            "length": _value(length, "measured", sigma=(ext_a if gable_axis == "A" else ext_b)[3] + 0.01),
            "corners": [[round(float(c[0]), 3), round(float(c[2]), 3)] for c in corners],
            "axisDeg": round(math.degrees(theta), 2),
        },
        "groundY": round(ground_y, 3),
        "eaveHeight": _value(eave, "measured", sigma=eave_sigma + 0.01),
        "roof": roof,
        "planes": {"walls": len(walls), "roof": len(roofs), "ground": len(grounds)},
    }
