#!/usr/bin/env python3
"""Build seamless 360-degree sunlit desert canyon horizon texture (3072x640 RGBA)
for Yanshan Force v0.9.0 "Ahsarah Fortress" from the two custom stylized 3D PBR matte paintings.

Outputs:
  game/assets/slice/horizon_ahsarah.png (3072x640 RGBA, seamless wrap, sky faded to transparent)
"""
from __future__ import annotations

from pathlib import Path
import argparse
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REF_DIR = ROOT / "美术参考与素材库" / "07_v090_阿萨拉堡垒世界观与建筑参考"
OUT_PNG = ROOT / "game" / "assets" / "slice" / "horizon_ahsarah.png"

ARCH_A = REF_DIR / "10_自绘远景原画_阿萨拉红岩峡谷A.jpg"
ARCH_B = REF_DIR / "11_自绘远景原画_阿萨拉金色沙丘B.jpg"


def load_panel(src: Path, w: int, h: int) -> np.ndarray:
    if not src.exists():
        raise FileNotFoundError(f"Missing horizon panel source: {src}")
    img = Image.open(src).convert("RGB")
    # Crop slightly top/bottom so the mesa & dune ridges sit cleanly at vertical mid-upper third
    iw, ih = img.size
    crop = img.crop((0, int(ih * 0.14), iw, int(ih * 0.96)))
    resized = crop.resize((w, h), Image.Resampling.LANCZOS)
    return np.asarray(resized, dtype=np.float32) / 255.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--panel-a", type=Path, default=ARCH_A)
    parser.add_argument("--panel-b", type=Path, default=ARCH_B)
    args = parser.parse_args()

    W, H = 3072, 640
    overlap = 256
    # Total source coverage = W + 2 * overlap -> each panel has width = W//2 + overlap
    half = W // 2
    panel_w = half + overlap

    a = load_panel(args.panel_a, panel_w, H)
    b = load_panel(args.panel_b, panel_w, H)

    # Exact seam-free circular stitch:
    # - Segment 1: a[overlap : half]                 -> canvas[overlap : half]
    # - Seam AB:   blend a[half : half+overlap] -> b[0 : overlap] -> canvas[half : half+overlap]
    # - Segment 2: b[overlap : half]                 -> canvas[half+overlap : W]
    # - Seam BA:   blend b[half : half+overlap] -> a[0 : overlap] -> canvas[0 : overlap]
    canvas = np.zeros((H, W, 3), dtype=np.float32)
    t = np.linspace(0.0, 1.0, overlap, dtype=np.float32)
    w_blend = (0.5 - 0.5 * np.cos(t * np.pi))[None, :, None]

    canvas[:, 0:overlap, :] = b[:, half:panel_w, :] * (1.0 - w_blend) + a[:, 0:overlap, :] * w_blend
    canvas[:, overlap:half, :] = a[:, overlap:half, :]
    canvas[:, half : half + overlap, :] = a[:, half:panel_w, :] * (1.0 - w_blend) + b[:, 0:overlap, :] * w_blend
    canvas[:, half + overlap : W, :] = b[:, overlap:half, :]

    # Crisp sky transparency mask: azure sky has low warmth (R - B < 0.08), warm sandstone/dunes have R - B > 0.14
    r = canvas[:, :, 0]
    b_ch = canvas[:, :, 2]
    warmth = r - b_ch
    yy = np.linspace(0.0, 1.0, H, dtype=np.float32)[:, None]

    sky_score = np.clip((0.125 - warmth) / 0.10, 0.0, 1.0)
    upper_gate = np.clip((0.58 - yy) / 0.18, 0.0, 1.0)
    # Strictly fade top 18% of panorama to pure alpha=0.0 so ZERO sky hairline ever appears!
    top_fade = np.clip((yy - 0.18) / 0.16, 0.0, 1.0)
    alpha = (1.0 - sky_score * upper_gate) * top_fade
    alpha = np.clip(alpha, 0.0, 1.0)

    # Smoothly blend bottom 14% into warm desert floor gold (#c89f68) to marry seamlessly with outer terrain skirt!
    bot_t = np.clip((yy - 0.84) / 0.16, 0.0, 1.0)
    sand_floor = np.array([0.785, 0.625, 0.408], dtype=np.float32)
    canvas = canvas * (1.0 - bot_t[:, :, None] * 0.72) + sand_floor[None, None, :] * (bot_t[:, :, None] * 0.72)

    # Warm-gold premultiply edge clean so zero grey/blue halo appears against bright desert sky
    haze = np.array([0.92, 0.78, 0.56], dtype=np.float32)
    edge_fix = np.clip((1.0 - alpha) * 0.75, 0.0, 0.75)
    rgb = canvas * (1.0 - edge_fix[:, :, None]) + haze[None, None, :] * edge_fix[:, :, None]

    rgba = np.concatenate([rgb, alpha[:, :, None]], axis=2)
    out_img = Image.fromarray(np.clip(rgba * 255.0, 0, 255).astype(np.uint8), mode="RGBA")
    OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
    out_img.save(OUT_PNG, optimize=True)
    print(f"Wrote seamless 360 desert horizon -> {OUT_PNG} ({OUT_PNG.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
