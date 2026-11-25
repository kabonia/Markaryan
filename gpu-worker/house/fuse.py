"""Глубина LiDAR + позы ARKit → облако точек и сетка (TSDF). Без SfM: позы уже метрические."""
from __future__ import annotations

import numpy as np
import open3d as o3d

from .bundle import Bundle


def fuse(bundle: Bundle, voxel: float = 0.02, max_depth: float = 5.0, min_conf: int = 1):
    """TSDF-слияние глубин. Возвращает (сетка, облако с нормалями)."""
    d = bundle.manifest["depth"]
    w, h = d["width"], d["height"]
    image = bundle.manifest["image"]
    scale = w / image["width"]
    volume = o3d.pipelines.integration.ScalableTSDFVolume(
        voxel_length=voxel, sdf_trunc=voxel * 4, color_type=o3d.pipelines.integration.TSDFVolumeColorType.NoColor)
    gray = o3d.geometry.Image(np.full((h, w, 3), 128, dtype=np.uint8))
    used = 0
    for frame in bundle.frames:
        data = bundle.depth(frame)
        if data is None:
            continue
        depth, conf = data
        depth = depth.copy()
        if conf is not None:
            depth[conf < min_conf] = 0
        depth[~np.isfinite(depth)] = 0
        fx, fy, cx, cy = frame.K
        intrinsic = o3d.camera.PinholeCameraIntrinsic(w, h, fx * scale, fy * scale, cx * scale, cy * scale)
        rgbd = o3d.geometry.RGBDImage.create_from_color_and_depth(
            gray, o3d.geometry.Image(depth), depth_scale=1.0, depth_trunc=max_depth, convert_rgb_to_intensity=False)
        volume.integrate(rgbd, intrinsic, frame.world_to_cam_cv)
        used += 1
    if used == 0:
        raise ValueError("в скане нет глубины LiDAR")
    mesh = volume.extract_triangle_mesh()
    mesh.compute_vertex_normals()
    cloud = volume.extract_point_cloud()
    cloud = cloud.voxel_down_sample(voxel * 2)
    cloud.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=voxel * 6, max_nn=30))
    return mesh, cloud, used
