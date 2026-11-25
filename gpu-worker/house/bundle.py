"""Чтение пакета скана (scan.zip / папка) — формат docs/house-exterior/SPEC-0-1.md §1.3."""
from __future__ import annotations

import io
import json
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

# ARKit: камера смотрит вдоль −z, y вверх. OpenCV/Open3D: смотрит вдоль +z, y вниз.
ARKIT_TO_CV = np.diag([1.0, -1.0, -1.0, 1.0])


@dataclass
class Frame:
    index: int
    image: str
    pose: np.ndarray            # 4×4 камера→мир (ARKit)
    K: tuple                    # fx, fy, cx, cy — для размера JPEG
    tier: str = "wall"
    sharpness: float = 0.0
    depth: str | None = None
    conf: str | None = None

    @property
    def cam_to_world_cv(self) -> np.ndarray:
        return self.pose @ ARKIT_TO_CV

    @property
    def world_to_cam_cv(self) -> np.ndarray:
        return np.linalg.inv(self.cam_to_world_cv)

    def projection(self) -> np.ndarray:
        """P = K [R|t] (OpenCV) для пикселей JPEG."""
        fx, fy, cx, cy = self.K
        k = np.array([[fx, 0, cx], [0, fy, cy], [0, 0, 1.0]])
        return k @ self.world_to_cam_cv[:3, :]


@dataclass
class Bundle:
    manifest: dict
    frames: list[Frame]
    reader: "Reader"
    stills: list[Frame] = field(default_factory=list)

    @property
    def lidar(self) -> bool:
        return bool(self.manifest.get("lidar"))

    def depth(self, frame: Frame) -> tuple[np.ndarray, np.ndarray | None] | None:
        """Глубина (м, float32 H×W) и уверенность (uint8 0/1/2) кадра."""
        if not frame.depth:
            return None
        d = self.manifest["depth"]
        h, w = d["height"], d["width"]
        depth = np.frombuffer(self.reader.read(frame.depth), dtype=np.float16).astype(np.float32).reshape(h, w)
        conf = None
        if frame.conf:
            conf = np.frombuffer(self.reader.read(frame.conf), dtype=np.uint8).reshape(h, w)
        return depth, conf

    def image_bytes(self, frame: Frame) -> bytes:
        return self.reader.read(frame.image)


class Reader:
    def __init__(self, source: Path):
        self.source = Path(source)
        self.zip = zipfile.ZipFile(self.source) if self.source.is_file() else None

    def read(self, name: str) -> bytes:
        if self.zip is not None:
            return self.zip.read(name)
        return (self.source / name).read_bytes()


def _frame(item: dict) -> Frame:
    pose = np.array(item["pose"], dtype=np.float64).reshape(4, 4).T  # по столбцам, как simd_float4x4
    return Frame(index=item["i"], image=item["image"], pose=pose, K=tuple(item["K"]), tier=item.get("tier", "wall"),
                 sharpness=float(item.get("sharpness", 0)), depth=item.get("depth"), conf=item.get("conf"))


def load(source: str | Path) -> Bundle:
    reader = Reader(Path(source))
    manifest = json.loads(reader.read("manifest.json"))
    if manifest.get("format") != "smetapro-house-scan":
        raise ValueError("это не пакет скана СметаПро")
    frames = [_frame(f) for f in manifest.get("frames", [])]
    stills = [_frame(s) for s in manifest.get("stills", [])]
    return Bundle(manifest=manifest, frames=frames, reader=reader, stills=stills)


def write(folder: Path, manifest: dict, files: dict[str, bytes]) -> Path:
    """Пишет пакет scan.zip (для тестов и отладки)."""
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / "scan.zip"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
        z.writestr("manifest.json", json.dumps(manifest))
        for name, data in files.items():
            z.writestr(name, data)
    return path


def tiny_jpeg(width: int = 8, height: int = 6) -> bytes:
    """Пустой серый кадр (тестам изображение не нужно)."""
    from PIL import Image  # noqa: PLC0415
    buffer = io.BytesIO()
    Image.new("RGB", (width, height), (128, 128, 128)).save(buffer, "JPEG")
    return buffer.getvalue()
