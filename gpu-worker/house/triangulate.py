"""Триангуляция точки по нескольким кадрам с известными позами ARKit (конёк, углы карниза по фото)."""
from __future__ import annotations

import numpy as np


def triangulate(projections: list[np.ndarray], pixels: list[tuple[float, float]]) -> tuple[np.ndarray, float]:
    """DLT по ≥2 кадрам: P (3×4) и пиксель (u, v). Возвращает точку и среднюю ошибку перепроекции, px."""
    if len(projections) < 2:
        raise ValueError("нужно хотя бы 2 кадра")
    rows = []
    for P, (u, v) in zip(projections, pixels):
        rows.append(u * P[2] - P[0])
        rows.append(v * P[2] - P[1])
    A = np.asarray(rows)
    # Нормировка строк — устойчивее при разных расстояниях.
    A /= np.linalg.norm(A[:, :3], axis=1, keepdims=True)
    _, _, vt = np.linalg.svd(A)
    X = vt[-1]
    X = X[:3] / X[3]
    errors = []
    for P, (u, v) in zip(projections, pixels):
        p = P @ np.append(X, 1)
        errors.append(np.hypot(p[0] / p[2] - u, p[1] / p[2] - v))
    return X, float(np.mean(errors))


def robust_triangulate(projections, pixels, max_error_px: float = 8.0):
    """Отбрасывает худший кадр, пока средняя ошибка больше порога (ошибка ИИ в разметке одного фото)."""
    P, px = list(projections), list(pixels)
    X, err = triangulate(P, px)
    while err > max_error_px and len(P) > 2:
        residuals = []
        for Pi, (u, v) in zip(P, px):
            p = Pi @ np.append(X, 1)
            residuals.append(np.hypot(p[0] / p[2] - u, p[1] / p[2] - v))
        worst = int(np.argmax(residuals))
        P.pop(worst)
        px.pop(worst)
        X, err = triangulate(P, px)
    return X, err, len(P)
