"""Generate tileable Jiangnan terraced rice-paddy valley albedo and 360-degree mountain horizon backdrop textures."""
from __future__ import annotations

import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "assets" / "slice"
OUT.mkdir(parents=True, exist_ok=True)


def build_rural_paddies_texture() -> Path:
    size = 1024
    img = Image.new("RGB", (size, size), (104, 134, 68))
    draw = ImageDraw.Draw(img)
    rng = np.random.default_rng(20261113)

    # Grounded Jiangnan terraced rice-paddy palette calibrated to match hillside grass exposure (no neon highlight wash)
    palette = [
        (68, 96, 48),     # Deep emerald young rice
        (84, 108, 52),    # Lush mid-season rice
        (108, 112, 54),   # Olive-gold ripening grain
        (122, 112, 56),   # Earthy harvest amber paddy
        (56, 84, 80),     # Calm slate-teal flooded mirror paddy
        (74, 96, 54),     # Fresh hillside seedling terrace
    ]

    row_heights = [96, 128, 112, 144, 96, 128, 160, 160]  # sum == 1024
    y0 = 0
    for ry, ch in enumerate(row_heights):
        # Partition each terrace strip into staggered organic plot widths summing to 1024
        widths = [128, 192, 160, 144, 176, 224] if ry % 2 == 0 else [176, 144, 224, 128, 160, 192]
        if ry % 3 == 1:
            widths = list(reversed(widths))
        x0 = 0
        for cx, cw in enumerate(widths):
            x1 = x0 + cw
            y1 = y0 + ch
            col = palette[int(rng.integers(0, len(palette)))]
            jitter = rng.integers(-8, 9, size=3)
            fill = tuple(int(np.clip(c + j, 22, 175)) for c, j in zip(col, jitter))
            draw.rectangle([x0, y0, x1, y1], fill=fill)

            stripe_col = tuple(max(18, c - 13) for c in fill)
            horiz = ((cx + ry) % 2 == 0)
            if horiz:
                for sy in range(y0 + 7, y1 - 4, 8):
                    draw.line([(x0 + 3, sy), (x1 - 3, sy)], fill=stripe_col, width=2)
            else:
                for sx in range(x0 + 7, x1 - 4, 8):
                    draw.line([(sx, y0 + 3), (sx, y1 - 3)], fill=stripe_col, width=2)

            bund_outer = (52, 46, 34)
            bund_grass = (64, 80, 42)
            draw.rectangle([x0, y0, x1, y1], outline=bund_outer, width=5)
            draw.rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], outline=bund_grass, width=2)
            x0 = x1
        y0 += ch

    # Add fine leaf/soil grain noise + subtle low-frequency cloud-dappled variation
    yy_i, xx_i = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")
    dapple = 0.94 + 0.09 * np.sin(xx_i / size * math.tau * 2.0 + 0.7) * np.cos(yy_i / size * math.tau * 2.0 - 0.4)
    arr = np.array(img, dtype=np.float32) * dapple[:, :, None]
    noise = rng.integers(-7, 8, size=(size, size, 1))
    arr = np.clip(arr + noise, 0, 220).astype(np.uint8)
    img = Image.fromarray(arr, mode="RGB")

    # Gentle organic domain-warp along X/Y so terraced bunds bend like contoured hillside terraces!
    src = np.array(img, dtype=np.uint8)
    yy, xx = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")
    dx = (10.0 * np.sin(yy / size * math.tau * 2.0 + xx / size * math.tau * 1.0)).astype(np.int32)
    dy = (8.0 * np.sin(xx / size * math.tau * 2.0 - yy / size * math.tau * 1.0)).astype(np.int32)
    warped = src[(yy + dy) % size, (xx + dx) % size]
    img = Image.fromarray(warped, mode="RGB").filter(ImageFilter.GaussianBlur(radius=0.55))

    path = OUT / "rural_paddies_albedo.png"
    img.save(path)
    return path


def build_horizon_mountains_texture() -> Path:
    w, h = 2048, 384
    arr = np.zeros((h, w, 4), dtype=np.uint8)
    xs = np.linspace(0.0, 1.0, w, endpoint=False)
    phase = xs * 2.0 * np.pi

    layers = [
        (0.24, 0.14, (154, 176, 170, 255), [(2, 0.08), (5, 0.045), (9, 0.022)], 0.3),
        (0.42, 0.12, (118, 144, 130, 255), [(3, 0.075), (7, 0.042), (13, 0.020)], 1.4),
        (0.58, 0.10, (86, 112, 94, 255),   [(4, 0.068), (8, 0.036), (15, 0.018)], 2.7),
    ]
    ys = np.linspace(0.0, 1.0, h)[:, None]
    mist_col = np.array([150, 168, 152], dtype=np.float32)
    for base_y, _, rgba, harmonics, seed_off in layers:
        ridge = np.full(w, base_y, dtype=np.float32)
        for k, amp in harmonics:
            ridge += amp * np.sin(phase * k + seed_off * k)
        mask = ys >= ridge[None, :]
        fade = np.clip((ys - ridge[None, :]) / 0.18, 0.0, 1.0)
        base_col = np.array(rgba[:3], dtype=np.float32)
        for c in range(3):
            chan = np.clip(base_col[c] * (1.0 - fade * 0.22) + mist_col[c] * (fade * 0.22), 0, 255).astype(np.uint8)
            arr[:, :, c] = np.where(mask, chan, arr[:, :, c])
        alpha = np.where(mask, rgba[3], arr[:, :, 3])
        arr[:, :, 3] = np.maximum(arr[:, :, 3], alpha)

    # Blend lower foothill skirt cleanly into valley mist band (0.64..0.88) before Godot distance fog applies
    mist_band = np.clip((ys - 0.64) / 0.24, 0.0, 1.0)
    arr[:, :, 0] = np.clip(arr[:, :, 0] * (1 - mist_band * 0.65) + 148 * (mist_band * 0.65), 0, 255).astype(np.uint8)
    arr[:, :, 1] = np.clip(arr[:, :, 1] * (1 - mist_band * 0.65) + 166 * (mist_band * 0.65), 0, 255).astype(np.uint8)
    arr[:, :, 2] = np.clip(arr[:, :, 2] * (1 - mist_band * 0.65) + 150 * (mist_band * 0.65), 0, 255).astype(np.uint8)

    img = Image.fromarray(arr, mode="RGBA").filter(ImageFilter.GaussianBlur(radius=0.8))
    path = OUT / "horizon_mountains.png"
    img.save(path)
    return path


if __name__ == "__main__":
    p1 = build_rural_paddies_texture()
    p2 = build_horizon_mountains_texture()
    print("Generated textures:", p1, p2)
