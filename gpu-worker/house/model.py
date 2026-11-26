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
    o3d.utility.random.seed(7)  # один и тот же скан — всегда одни и те же размеры
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
    seen_top = env[:, 1].max()
    # Плато у верха — это предел дальности LiDAR, а не кромка крыши: такие корзины в прямые не берём.
    # Если конёк реально снят, отбрасывается только узкая полоска у вершины — прямые по скатам остаются.
    plateau = env[:, 1] >= seen_top - 0.12
    if (~plateau).sum() >= 6:
        env = env[~plateau]
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
    return {
        "ridge": float(h_apex), "apexOffset": float(s_apex - mid),
        "pitchLeft": math.degrees(math.atan(kl)), "pitchRight": math.degrees(math.atan(-kr)),
        "seenUpTo": float(seen_top), "residual": float(np.std(np.concatenate([
            left[:, 1] - (kl * left[:, 0] + bl), right[:, 1] - (kr * right[:, 0] + br)]))),
    }


def _opposite_slopes(roofs: list[Plane]):
    """Два крупнейших ската, смотрящих в противоположные стороны (по горизонтали)."""
    usable = [r for r in roofs if 0.26 < abs(r.normal[1]) < 0.99 and r.size >= 200]  # 8°…75°
    best, best_size = None, 0
    for i, a in enumerate(usable):
        ha = np.array([a.normal[0], a.normal[2]])
        for b in usable[i + 1:]:
            hb = np.array([b.normal[0], b.normal[2]])
            if ha @ hb / (np.linalg.norm(ha) * np.linalg.norm(hb)) < -0.8 and a.size + b.size > best_size:
                best, best_size = (a, b), a.size + b.size
    return best


def _plane_intersection_near(a: Plane, b: Plane, near: np.ndarray):
    """Точка линии пересечения плоскостей, ближайшая к `near` (по горизонтали)."""
    direction = np.cross(a.normal, b.normal)
    if np.linalg.norm(direction) < 1e-6:
        return None
    A = np.array([a.normal, b.normal, direction])
    rhs = np.array([-a.d, -b.d, direction @ near])
    try:
        return np.linalg.solve(A, rhs)
    except np.linalg.LinAlgError:
        return None


def _footprint_polygon(groups: dict, u: np.ndarray, v: np.ndarray):
    """Контур дома (Г‑образный, с пристройками) — разбиением плана линиями стен на клетки.
    Клетка внутри, если слева от неё нечётное число стен оси A, перекрывающих её по второй оси."""
    def lines(group, axis, other):
        out = []
        for w in group:
            s = w.points @ other
            out.append((float(w.points.mean(axis=0) @ axis), float(np.percentile(s, 1)), float(np.percentile(s, 99))))
        return out
    a_walls, b_walls = lines(groups["A"], u, v), lines(groups["B"], v, u)

    def coords(walls):
        values = sorted(w[0] for w in walls)
        merged = []
        for x in values:
            if merged and x - merged[-1][-1] < 0.2:
                merged[-1].append(x)
            else:
                merged.append([x])
        return [float(np.mean(m)) for m in merged]
    xs, ys = coords(a_walls), coords(b_walls)
    if len(xs) < 2 or len(ys) < 2:
        return None
    nx, ny = len(xs) - 1, len(ys) - 1
    inside = np.zeros((nx, ny), bool)
    for i in range(nx):
        for j in range(ny):
            ac, bc = (xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2
            count = sum(1 for off, lo, hi in a_walls if off < ac and lo - 0.3 <= bc <= hi + 0.3)
            inside[i, j] = count % 2 == 1
    if not inside.any():
        return None
    area = float(sum((xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j]) for i in range(nx) for j in range(ny) if inside[i, j]))

    def cell(i, j):
        return 0 <= i < nx and 0 <= j < ny and inside[i, j]
    # Граничные рёбра с внутренностью слева (обход против часовой в осях a, b).
    edges = {}
    for i in range(nx):
        for j in range(ny):
            if not inside[i, j]:
                continue
            if not cell(i, j - 1): edges[(i, j)] = (i + 1, j)
            if not cell(i + 1, j): edges[(i + 1, j)] = (i + 1, j + 1)
            if not cell(i, j + 1): edges[(i + 1, j + 1)] = (i, j + 1)
            if not cell(i - 1, j): edges[(i, j + 1)] = (i, j)
    start = next(iter(edges))
    loop, point = [start], edges[start]
    while point != start and len(loop) <= len(edges):
        loop.append(point)
        point = edges.get(point)
        if point is None:
            return None
    # Убираем вершины на прямой.
    corners = []
    for k, p in enumerate(loop):
        prev, nxt = loop[k - 1], loop[(k + 1) % len(loop)]
        if (prev[0] == p[0] == nxt[0]) or (prev[1] == p[1] == nxt[1]):
            continue
        corners.append(p)
    pts = [(xs[i], ys[j]) for i, j in corners]
    sides = [math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]) for k in range(len(pts))]
    world = [u * a + v * b for a, b in pts]
    return {
        "corners": [[round(float(c[0]), 3), round(float(c[2]), 3)] for c in world],
        "area": round(area, 3), "perimeter": round(float(sum(sides)), 3), "sides": [round(x, 3) for x in sides],
        "shape": "rectangle" if len(pts) == 4 else ("L" if len(pts) == 6 else "complex"),
    }


def _side(size, ext):
    """Размер стороны дома: измерен по двум стенам или достроен по концам соседних (сторона недоступна)."""
    if ext[4] == "inferred":
        return _value(size, "extrapolated", sigma=ext[3] + 0.01, note="одна сторона недоступна — по концам соседних стен")
    return _value(size, "measured", sigma=ext[3] + 0.01)


def _value(value, source, sigma=None, note=None):
    out = {"value": None if value is None else round(float(value), 3), "source": source}
    if sigma is not None:
        out["sigma"] = round(float(sigma), 3)
    if note:
        out["note"] = note
    return out


def _overhang(cloud_pts: np.ndarray, wall: Plane, center: np.ndarray, from_height: float) -> float | None:
    """Свес над стеной: насколько точки крыши/карнизной подшивы выше `from_height` выходят наружу за плоскость стены."""
    n = wall.normal.copy()
    n[1] = 0
    n /= np.linalg.norm(n)
    w0 = wall.points.mean(axis=0)
    if (w0 - center) @ n < 0:
        n = -n                                  # нормаль — наружу от дома
    along = np.array([-n[2], 0.0, n[0]])
    span = wall.points @ along
    lo, hi = np.percentile(span, 2), np.percentile(span, 98)
    s = cloud_pts @ along
    d = (cloud_pts - w0) @ n
    sel = (cloud_pts[:, 1] > from_height) & (s > lo + 0.3) & (s < hi - 0.3) & (d > 0.03) & (d < 1.6)
    if sel.sum() < 30:
        return None
    return float(np.percentile(d[sel], 99))


def build_house(planes: list[Plane], cloud: o3d.geometry.PointCloud | None = None) -> dict:
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

    ceilings = [g for g in grounds if np.median(g.points[:, 1]) - ground_y > 1.9 and g.size > 300]
    indoor = bool(ceilings)
    theta = _dominant_axis(walls)
    u = np.array([math.cos(theta), 0.0, math.sin(theta)])   # ось A
    v = np.array([-math.sin(theta), 0.0, math.cos(theta)])  # ось B
    groups = {"A": [], "B": []}
    for w in walls:
        along_a = abs(w.normal @ u) > abs(w.normal @ v)
        groups["A" if along_a else "B"].append(w)

    def extent(group, axis, others):
        """Габарит вдоль оси: (размер, (смещение, стена|None) низ, верх, σ, None|"inferred")."""
        offsets = sorted(((float(w.points.mean(axis=0) @ axis), w) for w in group), key=lambda t: t[0])
        if len(offsets) >= 2 and offsets[-1][0] - offsets[0][0] >= 2.0:
            lo, hi = offsets[0], offsets[-1]
            # Расстояние между плоскостями — по точкам обеих стен (усреднение снимает шум LiDAR).
            sigma = math.hypot(np.std(lo[1].points @ axis), np.std(hi[1].points @ axis)) / math.sqrt(min(lo[1].size, hi[1].size))
            return hi[0] - lo[0], lo, hi, sigma, None
        # Сторона недоступна (впритык к соседу, забору): её положение — по концам перпендикулярных стен,
        # они доходят до угла дома. Точность — чуть ниже, метка «extrapolated».
        if not others:
            return None
        proj = np.concatenate([w.points @ axis for w in others])
        if len(proj) < 50:
            return None
        end_lo, end_hi = float(np.percentile(proj, 0.2)), float(np.percentile(proj, 99.8))
        if not offsets:
            lo, hi = (end_lo, None), (end_hi, None)
        else:
            off, wall = offsets[0] if len(offsets) == 1 else max(offsets, key=lambda t: t[1].size)
            lo, hi = ((off, wall), (end_hi, None)) if abs(off - end_lo) < abs(off - end_hi) else ((end_lo, None), (off, wall))
        if hi[0] - lo[0] < 2.0:
            return None
        return hi[0] - lo[0], lo, hi, 0.03, "inferred"

    ext_a, ext_b = extent(groups["A"], u, groups["B"]), extent(groups["B"], v, groups["A"])
    if ext_a is None or ext_b is None:
        raise ValueError("не хватает стен — снимите хотя бы три стороны дома или отметьте недоступную сторону")

    def tops(group):
        return [float(np.percentile(w.points[:, 1], 98) - ground_y) for w in group]

    tops_a, tops_b = tops(groups["A"]), tops(groups["B"])
    warnings: list[dict] = []
    if not groups["A"] or not groups["B"]:
        warnings.append({"code": "few_walls", "text": "Сняты стены только одного направления — размеры поперёк достроены. Обойдите дом со всех сторон."})
    # Фронтонные стены выше карнизных: по ним определяем направление конька.
    if tops_a and tops_b:
        gable_axis = "A" if max(tops_a) > max(tops_b) + 0.3 else "B" if max(tops_b) > max(tops_a) + 0.3 else None
    else:
        gable_axis = None
    # Без фронтонов (вальмовая, плоская) — все стены карнизные.
    eave_group = walls if gable_axis is None else (groups["B"] if gable_axis == "A" else groups["A"])
    eave_tops = [float(np.percentile(w.points[:, 1], 99) - ground_y) for w in eave_group]
    eave = float(np.median(eave_tops))
    eave_sigma = float(np.std(eave_tops)) if len(eave_tops) > 1 else 0.03

    if gable_axis:
        width_gable = ext_b[0] if gable_axis == "A" else ext_a[0]   # ширина торца (под фронтоном)
        length = ext_a[0] if gable_axis == "A" else ext_b[0]
    else:
        # Без фронтонов: ширина — короткая сторона, длина — длинная.
        width_gable, length = sorted((ext_a[0], ext_b[0]))

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
        # Самое точное: скаты, снятые LiDAR у карниза (тысячи точек → уклон до десятых градуса),
        # конёк — линия пересечения двух противоположных скатов.
        center = np.array([np.mean([c for c in (ext_a[1][0], ext_a[2][0])]), 0.0, np.mean([c for c in (ext_b[1][0], ext_b[2][0])])])
        center = u * center[0] + v * center[2]
        pair = _opposite_slopes(roofs)
        if pair is not None:
            r1, r2 = pair
            ridge_point = _plane_intersection_near(r1, r2, center)
            s1, s2 = (math.degrees(math.acos(min(1.0, abs(r.normal[1])))) for r in pair)
            if ridge_point is not None:
                ridge_h = float(ridge_point[1] - ground_y)
                profile_ridge = roof.get("ridgeHeight", {}).get("value")
                roof.update({
                    "type": "gable",
                    "ridgeHeight": _value(ridge_h, "measured", sigma=0.03, note="пересечение скатов, снятых LiDAR"),
                    "pitchDeg": _value((s1 + s2) / 2, "measured", sigma=0.3),
                    "pitchLeftDeg": round(s1, 2), "pitchRightDeg": round(s2, 2), "symmetric": abs(s1 - s2) < 3,
                })
                if profile_ridge is not None:
                    roof["ridgeByGableEdge"] = round(profile_ridge, 3)  # сверка: кромка фронтона
                # Скаты и поперёк конька → вальмовая (без фронтонов) или полувальмовая (фронтон есть, но со скатом сверху).
                ridge_dir = np.cross(r1.normal, r2.normal)
                ridge_dir[1] = 0
                if np.linalg.norm(ridge_dir) > 1e-6:
                    ridge_dir /= np.linalg.norm(ridge_dir)
                    hips = [r for r in roofs if 0.26 < abs(r.normal[1]) < 0.99 and r.size >= 150
                            and abs(np.array([r.normal[0], 0, r.normal[2]]) @ ridge_dir) / max(1e-6, math.hypot(r.normal[0], r.normal[2])) > 0.8]
                    if hips:
                        roof["type"] = "half_hip" if gable_axis else "hip"
                        roof["hipPitchDeg"] = round(float(np.median([math.degrees(math.acos(min(1.0, abs(h.normal[1])))) for h in hips])), 2)

    # Карниз точнее — как линия пересечения ската со стеной: верх стены под свесом лидару часто не виден.
    if roofs and eave_group:
        mid0 = u * ((ext_a[1][0] + ext_a[2][0]) / 2) + v * ((ext_b[1][0] + ext_b[2][0]) / 2)
        lines = []
        for w in eave_group:
            out = w.points.mean(axis=0) - mid0
            out[1] = 0
            # Скат над этой стеной: его горизонтальная нормаль смотрит наружу, туда же, куда стена.
            same = [r for r in roofs if 0.26 < abs(r.normal[1]) < 0.99 and np.array([r.normal[0], 0, r.normal[2]]) @ out > 0]
            if not same:
                continue
            r = max(same, key=lambda p_: p_.size)
            point = _plane_intersection_near(w, r, w.points.mean(axis=0))
            if point is not None:
                lines.append(float(point[1] - ground_y))
        if lines and abs(np.median(lines) - eave) < 0.6:
            eave = float(np.median(lines))
            house_eave = _value(eave, "measured", sigma=0.02, note="пересечение ската и стены")
        else:
            house_eave = None
    else:
        house_eave = None

    # Свесы — по точкам выше карниза за плоскостью стены (лидар видит подшиву и скаты снизу).
    if cloud is not None:
        pts = np.asarray(cloud.points)
        mid = u * ((ext_a[1][0] + ext_a[2][0]) / 2) + v * ((ext_b[1][0] + ext_b[2][0]) / 2)
        mid[1] = ground_y
        def over(group):
            values = [o for o in (_overhang(pts, w, mid, ground_y + eave - 0.35) for w in group) if o is not None]
            return _value(float(np.median(values)), "measured", sigma=0.03) if values else _value(None, "assumption", note="свес не снят")
        roof["overhangEave"] = over(eave_group)
        if gable_axis:
            roof["overhangGable"] = over(groups[gable_axis])

    # Углы футпринта в мире (по пересечениям крайних стен).
    a_lo, a_hi = ext_a[1][0], ext_a[2][0]
    b_lo, b_hi = ext_b[1][0], ext_b[2][0]
    corners = [(u * a + v * b) for a, b in ((a_lo, b_lo), (a_hi, b_lo), (a_hi, b_hi), (a_lo, b_hi))]
    # Потолок над большей частью плана — помещение; навес или подшитый свес столько не закрывают.
    # Облако прорежено с шагом ~4 см → одна точка ≈ 0,0016 м².
    ceiling_area = sum(c.size for c in ceilings) * 0.0016
    indoor = indoor and ceiling_area > 0.4 * width_gable * length
    if indoor:
        warnings.append({"code": "indoor", "text": "Похоже, обмер сделан внутри помещения (лидар видит потолок). Для комнат используйте «Скан комнаты», для дома — обход снаружи."})
    poly = _footprint_polygon(groups, u, v) if groups["A"] and groups["B"] else None
    if poly and poly["area"] < 0.6 * width_gable * length:
        # Контур противоречит габаритам (стены сняты частично) — не показываем его, чтобы не вводить в заблуждение.
        warnings.append({"code": "outline", "text": "Контур дома собран не полностью — показаны габариты. Доснимите углы дома."})
        poly = None
    return {
        "warnings": warnings,
        "footprint": {
            "gableWidth": _side(width_gable, (ext_b if gable_axis == "A" else ext_a) if gable_axis else min(ext_a, ext_b, key=lambda e: e[0])),
            "length": _side(length, (ext_a if gable_axis == "A" else ext_b) if gable_axis else max(ext_a, ext_b, key=lambda e: e[0])),
            "corners": [[round(float(c[0]), 3), round(float(c[2]), 3)] for c in corners],
            "axisDeg": round(math.degrees(theta), 2),
            "polygon": poly,
        },
        "groundY": round(ground_y, 3),
        "eaveHeight": house_eave or _value(eave, "measured", sigma=eave_sigma + 0.01),
        "roof": roof,
        "planes": {"walls": len(walls), "roof": len(roofs), "ground": len(grounds)},
        # Все стены (для окон и дверей по фото): нормаль, d, центр, полуширина вдоль стены.
        "walls": [
            {"normal": [round(float(x), 5) for x in w.normal], "d": round(float(w.d), 4),
             "center": [round(float(x), 3) for x in w.points.mean(axis=0)],
             "halfWidth": round(float(np.ptp(w.points @ np.array([-w.normal[2], 0.0, w.normal[0]])) / 2), 3)}
            for w in walls],
        # Фронтонные стены (для конька по фото): нормаль, d, центр, полуширина.
        "gableWalls": [] if not gable_axis else [
            {"normal": [round(float(x), 5) for x in w.normal], "d": round(float(w.d), 4),
             "center": [round(float(x), 3) for x in w.points.mean(axis=0)],
             "halfWidth": round(float(np.ptp(w.points @ (v if gable_axis == "A" else u)) / 2), 3)}
            for w in groups[gable_axis]],
    }
