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

    # Organic variable-width Jiangnan golden-ripening, lush young-rice & flooded sky-reflecting paddy plots
    palette = [
        (124, 162, 68),   # Lush emerald rice
        (158, 178, 72),   # Yellow-green ripening rice
        (192, 170, 74),   # Golden harvest paddy
        (88, 136, 126),   # Flooded mirror water paddy
        (112, 148, 86),   # Mid-season paddy
        (174, 174, 80),   # Sunlit grain terrace
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
            jitter = rng.integers(-10, 11, size=3)
            fill = tuple(int(np.clip(c + j, 22, 232)) for c, j in zip(col, jitter))
            draw.rectangle([x0, y0, x1, y1], fill=fill)

            stripe_col = tuple(max(18, c - 16) for c in fill)
            horiz = ((cx + ry) % 2 == 0)
            if horiz:
                for sy in range(y0 + 7, y1 - 4, 8):
                    draw.line([(x0 + 3, sy), (x1 - 3, sy)], fill=stripe_col, width=2)
            else:
                for sx in range(x0 + 7, x1 - 4, 8):
                    draw.line([(sx, y0 + 3), (sx, y1 - 3)], fill=stripe_col, width=2)

            bund_outer = (84, 74, 52)
            bund_grass = (94, 118, 60)
            draw.rectangle([x0, y0, x1, y1], outline=bund_outer, width=6)
            draw.rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], outline=bund_grass, width=2)
            x0 = x1
        y0 += ch

    # Add fine leaf/soil grain noise so plots feel textured and natural from hillside overlooks
    arr = np.array(img, dtype=np.int16)
    noise = rng.integers(-9, 10, size=(size, size, 1))
    arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
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
        (0.24, 0.14, (132, 152, 150, 215), [(2, 0.08), (5, 0.045), (9, 0.022)], 0.3),
        (0.42, 0.12, (102, 126, 118, 240), [(3, 0.075), (7, 0.042), (13, 0.020)], 1.4),
        (0.58, 0.10, (78, 104, 88, 255),  [(4, 0.068), (8, 0.036), (15, 0.018)], 2.7),
    ]
    ys = np.linspace(0.0, 1.0, h)[:, None]
    for base_y, _, rgba, harmonics, seed_off in layers:
        ridge = np.full(w, base_y, dtype=np.float32)
        for k, amp in harmonics:
            ridge += amp * np.sin(phase * k + seed_off * k)
        mask = ys >= ridge[None, :]
        fade = np.clip((ys - ridge[None, :]) / 0.16, 0.0, 1.0)
        fog_col = np.array([191, 204, 185], dtype=np.float32)
        base_col = np.array(rgba[:3], dtype=np.float32)
        for c in range(3):
            chan = np.clip(base_col[c] * (1.0 - fade * 0.42) + fog_col[c] * (fade * 0.42), 0, 255).astype(np.uint8)
            arr[:, :, c] = np.where(mask, chan[0] if chan.ndim == 1 else chan, arr[:, :, c])
        alpha = np.where(mask, rgba[3], arr[:, :, 3])
        arr[:, :, 3] = np.maximum(arr[:, :, 3], alpha)

    mist_band = np.clip((ys - 0.80) / 0.20, 0.0, 1.0)
    arr[:, :, 0] = np.clip(arr[:, :, 0] * (1 - mist_band) + 191 * mist_band, 0, 255).astype(np.uint8)
    arr[:, :, 1] = np.clip(arr[:, :, 1] * (1 - mist_band) + 204 * mist_band, 0, 255).astype(np.uint8)
    arr[:, :, 2] = np.clip(arr[:, :, 2] * (1 - mist_band) + 185 * mist_band, 0, 255).astype(np.uint8)

    img = Image.fromarray(arr, mode="RGBA").filter(ImageFilter.GaussianBlur(radius=0.8))
    path = OUT / "horizon_mountains.png"
    img.save(path)
    return path


if __name__ == "__main__":
    p1 = build_rural_paddies_texture()
    p2 = build_horizon_mountains_texture()
    print("Generated textures:", p1, p2)
