#!/usr/bin/env python3
"""Generate seamless 1024x1024 sunlit stylized PBR textures for v0.9.0 Ahsarah Fortress:
  - game/assets/slice/ahsarah_sand_albedo.jpg      (warm sunlit rippled Saharan desert sand)
  - game/assets/slice/ahsarah_sandstone_albedo.jpg (warm ochre North African ashlar sandstone)
  - game/assets/slice/ahsarah_concrete_albedo.jpg  (weathered Zero Dam reinforced concrete panels)
  - game/assets/slice/ahsarah_road_albedo.jpg      (compacted desert gravel & tire-track road)
"""
from __future__ import annotations

import math
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "game" / "assets" / "slice"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def tile_noise(h: int, w: int, freq_x: int, freq_y: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    grid = rng.random((freq_y, freq_x), dtype=np.float32)
    ys = np.linspace(0, freq_y, h, endpoint=False, dtype=np.float32)
    xs = np.linspace(0, freq_x, w, endpoint=False, dtype=np.float32)
    y0 = np.floor(ys).astype(np.int32) % freq_y
    x0 = np.floor(xs).astype(np.int32) % freq_x
    y1 = (y0 + 1) % freq_y
    x1 = (x0 + 1) % freq_x
    fy = ys - np.floor(ys)
    fx = xs - np.floor(xs)
    sy = fy * fy * (3.0 - 2.0 * fy)
    sx = fx * fx * (3.0 - 2.0 * fx)
    v00 = grid[np.ix_(y0, x0)]
    v10 = grid[np.ix_(y0, x1)]
    v01 = grid[np.ix_(y1, x0)]
    v11 = grid[np.ix_(y1, x1)]
    top = v00 * (1.0 - sx[None, :]) + v10 * sx[None, :]
    bot = v01 * (1.0 - sx[None, :]) + v11 * sx[None, :]
    return top * (1.0 - sy[:, None]) + bot * sy[:, None]


def fbm(size: int, base_seed: int, octaves=((4, 0.45), (8, 0.28), (16, 0.16), (32, 0.08), (64, 0.03))) -> np.ndarray:
    acc = np.zeros((size, size), dtype=np.float32)
    wsum = 0.0
    for idx, (f, wt) in enumerate(octaves):
        acc += tile_noise(size, size, f, f, base_seed + idx * 97) * wt
        wsum += wt
    return acc / max(wsum, 1e-6)


def save_rgb(arr: np.ndarray, path: Path, quality: int = 90):
    img = Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), mode="RGB")
    img.save(path, quality=quality, optimize=True)
    print(f"Wrote {path} ({path.stat().st_size // 1024} KB)")


def build_sand(size: int = 1024):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / float(size)
    n1 = fbm(size, 101)
    n2 = fbm(size, 211, ((8, 0.5), (24, 0.35), (64, 0.15)))
    # Wind-swept sand ripples gently warped by low-frequency dunes
    phase = (yy * 14.0 + xx * 3.0 + n1 * 1.8) * math.tau
    ripples = 0.5 + 0.5 * np.sin(phase)
    grain = tile_noise(size, size, 128, 128, 307)
    base = np.array([0.85, 0.71, 0.49], dtype=np.float32)
    shadow = np.array([0.74, 0.57, 0.36], dtype=np.float32)
    hi = np.array([0.93, 0.82, 0.62], dtype=np.float32)
    t = np.clip(0.45 * n1 + 0.35 * ripples + 0.20 * n2, 0.0, 1.0)
    rgb = shadow[None, None, :] * (1.0 - t[:, :, None]) + hi[None, None, :] * t[:, :, None]
    rgb = rgb * (0.95 + 0.08 * (grain[:, :, None] - 0.5))
    rgb = rgb * 0.82 + base[None, None, :] * 0.18
    save_rgb(rgb, OUT_DIR / "ahsarah_sand_albedo.jpg")


def build_sandstone(size: int = 1024):
    n1 = fbm(size, 409)
    n2 = fbm(size, 521, ((16, 0.5), (48, 0.35), (96, 0.15)))
    # Ashlar North African sandstone block courses
    rows = 8
    cols = 4
    yy, xx = np.mgrid[0:size, 0:size]
    row_h = size // rows
    col_w = size // cols
    row_idx = yy // row_h
    x_shift = (xx + (row_idx % 2) * (col_w // 2)) % size
    fy = (yy % row_h) / float(row_h)
    fx = (x_shift % col_w) / float(col_w)
    mortar = ((fy < 0.045) | (fy > 0.955) | (fx < 0.025) | (fx > 0.975)).astype(np.float32)
    rng = np.random.default_rng(601)
    block_tint = rng.uniform(-0.05, 0.05, size=(rows, cols)).astype(np.float32)
    b_col = (x_shift // col_w) % cols
    bt = block_tint[row_idx % rows, b_col]
    stone = np.array([0.84, 0.66, 0.43], dtype=np.float32)
    warm = np.array([0.75, 0.52, 0.31], dtype=np.float32)
    mortar_col = np.array([0.64, 0.51, 0.36], dtype=np.float32)
    rgb = warm[None, None, :] * (1.0 - n1[:, :, None]) + stone[None, None, :] * n1[:, :, None]
    rgb += bt[:, :, None] + (n2[:, :, None] - 0.5) * 0.10
    rgb = rgb * (1.0 - 0.55 * mortar[:, :, None]) + mortar_col[None, None, :] * (0.55 * mortar[:, :, None])
    save_rgb(rgb, OUT_DIR / "ahsarah_sandstone_albedo.jpg")


def build_concrete(size: int = 1024):
    n1 = fbm(size, 709)
    n2 = fbm(size, 823, ((12, 0.45), (32, 0.35), (80, 0.20)))
    yy, xx = np.mgrid[0:size, 0:size]
    # Formwork panel seams + tie-rod holes + subtle warm desert dust at panel bottoms
    panel_h = size // 4
    panel_w = size // 4
    fy = (yy % panel_h) / float(panel_h)
    fx = (xx % panel_w) / float(panel_w)
    seam = ((fy < 0.018) | (fx < 0.014)).astype(np.float32)
    # Dust streaks along vertical edges
    dust = np.clip((1.0 - fy) * 0.25 + n1 * 0.35, 0.0, 1.0)
    c_light = np.array([0.67, 0.68, 0.67], dtype=np.float32)
    c_dark = np.array([0.52, 0.53, 0.54], dtype=np.float32)
    c_dust = np.array([0.74, 0.65, 0.50], dtype=np.float32)
    rgb = c_dark[None, None, :] * (1.0 - n1[:, :, None]) + c_light[None, None, :] * n1[:, :, None]
    rgb += (n2[:, :, None] - 0.5) * 0.09
    rgb = rgb * (1.0 - 0.22 * dust[:, :, None]) + c_dust[None, None, :] * (0.22 * dust[:, :, None])
    rgb *= (1.0 - 0.24 * seam[:, :, None])
    save_rgb(rgb, OUT_DIR / "ahsarah_concrete_albedo.jpg")


def build_road(size: int = 1024):
    n1 = fbm(size, 919)
    n2 = fbm(size, 1031, ((16, 0.4), (48, 0.35), (128, 0.25)))
    base = np.array([0.68, 0.58, 0.43], dtype=np.float32)
    pebble = np.array([0.55, 0.46, 0.35], dtype=np.float32)
    rgb = pebble[None, None, :] * (1.0 - n1[:, :, None]) + base[None, None, :] * n1[:, :, None]
    rgb += (n2[:, :, None] - 0.5) * 0.14
    save_rgb(rgb, OUT_DIR / "ahsarah_road_albedo.jpg")


if __name__ == "__main__":
    build_sand()
    build_sandstone()
    build_concrete()
    build_road()
    print("DONE v0.9.0 desert PBR textures!")
