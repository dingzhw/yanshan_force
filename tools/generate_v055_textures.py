"""Generate Taiping-Village style Jiangnan Cloud-Sea & Terraced Valley textures
(太平村·江南云海梯田山境):
1) rural_paddies_albedo.png : Sunlit golden-green rice paddies (#6e7f41 ~ #869c48) interwoven
   with sky-mirror water plots (#98b4bf) and warm earthen field bunds.
2) horizon_mountains.png    : 4-layer towering Jiangnan crags with sunward golden-green/cliff
   highlights, cool cerulean-teal shadows (#285364 ~ #568cb2), and billowing cloud-sea ribbons!
"""
from __future__ import annotations

import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "assets" / "slice"
OUT.mkdir(parents=True, exist_ok=True)


def build_rural_paddies_texture() -> Path:
    """Taiping Village sunlit golden-green terraced rice paddies + sky-mirror flooded plots."""
    size = 1024
    img = Image.new("RGB", (size, size), (118, 138, 68))
    draw = ImageDraw.Draw(img)
    rng = np.random.default_rng(20261118)

    # Calibrated directly to Taiping Village valley floor (#6e7f41 sunlit paddies + #91a4a2 water mirrors)
    palette = [
        (114, 136, 64),   # Classic Taiping sunlit golden-olive paddy A
        (132, 154, 72),   # Bright sunlit tender rice wave B
        (98, 124, 58),    # Lush spring jade rice plot C
        (124, 146, 68),   # Warm chartreuse-olive terrace D
        (86, 114, 58),    # Deeper emerald terrace E
        (152, 178, 186),  # Sky-reflecting flooded mirror water paddy (水田映晴云)
    ]

    row_heights = [96, 128, 112, 144, 96, 128, 160, 160]
    y0 = 0
    for ry, ch in enumerate(row_heights):
        widths = [128, 192, 160, 144, 176, 224] if ry % 2 == 0 else [176, 144, 224, 128, 160, 192]
        if ry % 3 == 1:
            widths = list(reversed(widths))
        x0 = 0
        for cx, cw in enumerate(widths):
            x1 = x0 + cw
            y1 = y0 + ch
            col = palette[int(rng.integers(0, len(palette)))]
            jitter = rng.integers(-6, 7, size=3)
            fill = tuple(int(np.clip(c + j, 40, 212)) for c, j in zip(col, jitter))
            draw.rectangle([x0, y0, x1, y1], fill=fill)

            is_mirror = fill[2] > 130
            stripe_col = (
                tuple(min(230, c + 12) for c in fill)
                if is_mirror
                else (max(36, fill[0] - 11), max(48, fill[1] - 10), max(32, fill[2] - 8))
            )
            step_px = 15 if is_mirror else 9
            if (cx + ry) % 2 == 0:
                for sy in range(y0 + 8, y1 - 5, step_px):
                    draw.line([(x0 + 5, sy), (x1 - 5, sy)], fill=stripe_col, width=1)
            else:
                for sx in range(x0 + 8, x1 - 5, step_px):
                    draw.line([(sx, y0 + 5), (sx, y1 - 5)], fill=stripe_col, width=1)

            # Crisp dark-emerald grassy bunds + occasional warm sunlit country footpath
            bund_grass = (52, 76, 44)
            bund_path = (136, 124, 94) if (cx + ry) % 4 == 0 else (72, 96, 52)
            draw.rectangle([x0, y0, x1, y1], outline=bund_grass, width=5)
            draw.rectangle([x0 + 3, y0 + 3, x1 - 3, y1 - 3], outline=bund_path, width=2)
            x0 = x1
        y0 += ch

    yy_i, xx_i = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")
    wash = 0.94 + 0.08 * np.sin(xx_i / size * math.tau * 2.0 + 0.6) * np.cos(yy_i / size * math.tau * 2.0 - 0.3)
    arr = np.array(img, dtype=np.float32) * wash[:, :, None]
    noise = rng.integers(-4, 5, size=(size, size, 1))
    arr = np.clip(arr + noise, 28, 224).astype(np.uint8)

    yy, xx = np.meshgrid(np.arange(size), np.arange(size), indexing="ij")
    dx = (12.0 * np.sin(yy / size * math.tau * 2.0 + xx / size * math.tau * 1.0)).astype(np.int32)
    dy = (9.0 * np.sin(xx / size * math.tau * 2.0 - yy / size * math.tau * 1.0)).astype(np.int32)
    warped = arr[(yy + dy) % size, (xx + dx) % size]
    img = Image.fromarray(warped, mode="RGB").filter(ImageFilter.GaussianBlur(radius=0.60))

    path = OUT / "rural_paddies_albedo.png"
    img.save(path)
    return path


def build_horizon_mountains_texture() -> Path:
    """Taiping Village 4-layer towering cloud-sea crags:
    Cerulean-blue distant peaks -> lush teal-emerald crags with warm sunlit cliff facets ->
    billowing golden-white & sky-blue cloud sea ('云海缠山腰 · 上实下虚')!"""
    w, h = 2048, 512
    cloud_cool = np.array([214.0, 228.0, 238.0], dtype=np.float32)
    cloud_warm = np.array([246.0, 239.0, 225.0], dtype=np.float32)

    xs = np.linspace(0.0, 1.0, w, endpoint=False)
    phase = xs * 2.0 * np.pi
    ys = np.linspace(0.0, 1.0, h)[:, None]

    # Sun direction glow across azimuth so one side of the horizon has warm golden cloud rims
    sun_az = 0.5 + 0.5 * np.cos(phase - 1.15)
    cloud_base = cloud_cool[None, None, :] * (1.0 - 0.58 * sun_az[None, :, None]) + cloud_warm[None, None, :] * (0.58 * sun_az[None, :, None])

    arr = np.zeros((h, w, 4), dtype=np.float32)
    arr[:, :, :3] = cloud_base

    # (base_y, shadow_rgb, sunlit_rgb, cliff_rgb, span, max_a, harmonics, seed_off)
    layers = [
        (0.28, (88, 140, 178), (116, 158, 182), (146, 168, 178), 0.24, 0.78, [(3, 0.062), (7, 0.038), (15, 0.018), (25, 0.008)], 0.4),
        (0.40, (62, 114, 150), (92, 136, 134),  (148, 152, 140), 0.22, 0.88, [(4, 0.068), (9, 0.040), (19, 0.018), (29, 0.008)], 1.6),
        (0.51, (44, 88, 106),  (88, 124, 74),   (174, 158, 128), 0.20, 0.95, [(5, 0.062), (11, 0.036), (21, 0.016), (33, 0.007)], 2.9),
        (0.61, (36, 76, 84),   (98, 134, 68),   (182, 162, 126), 0.18, 0.98, [(4, 0.052), (10, 0.032), (18, 0.015), (31, 0.006)], 4.2),
    ]

    # Fluffy cumulus cloud-ribbon billows wrapping mid-mountain waists
    billow1 = 0.5 + 0.5 * np.sin(phase[None, :] * 7.0 + np.cos(ys * 11.0) * 1.6)
    billow2 = 0.5 + 0.5 * np.cos(phase[None, :] * 13.0 - np.sin(ys * 15.0) * 1.4)
    cloud_puff = 0.6 * billow1 + 0.4 * billow2

    for base_y, shd_rgb, sun_rgb, clf_rgb, span, max_a, harmonics, seed_off in layers:
        ridge = np.full(w, base_y, dtype=np.float32)
        for k, amp in harmonics:
            ridge += amp * np.sin(phase * k + seed_off * k)
        # Slope derivative -> sunward facet vs cool sky-shadow facet (Taiping crag lighting!)
        slope = np.gradient(ridge) * float(w)
        sun_face = np.clip(0.5 + slope * 0.22, 0.0, 1.0)[None, :]
        steep_cliff = np.clip((np.abs(slope) - 1.35) * 0.55, 0.0, 1.0)[None, :]

        mask = ys >= ridge[None, :]
        depth_below = np.clip((ys - ridge[None, :]) / span, 0.0, 1.0)
        crest_soft = np.clip((ys - ridge[None, :]) / 0.008, 0.0, 1.0)

        shd = np.array(shd_rgb, dtype=np.float32)[None, None, :]
        sun = np.array(sun_rgb, dtype=np.float32)[None, None, :]
        clf = np.array(clf_rgb, dtype=np.float32)[None, None, :]

        rock_veg = shd * (1.0 - sun_face[:, :, None]) + sun * sun_face[:, :, None]
        # Exposed sunlit granite cliff vertical streaks near upper peak (just like Taiping crags!)
        cliff_zone = steep_cliff * sun_face * np.clip(1.0 - depth_below * 2.2, 0.0, 1.0) * 0.65
        mtn_rgb = rock_veg * (1.0 - cliff_zone[:, :, None]) + clf * cliff_zone[:, :, None]

        # Billowing cloud-sea waist ('云海缠山腰')
        cloud_swallow = np.clip((depth_below ** 0.80) + (cloud_puff - 0.45) * 0.28 * depth_below, 0.0, 1.0)
        layer_rgb = mtn_rgb * (1.0 - cloud_swallow[:, :, None]) + cloud_base * cloud_swallow[:, :, None]
        layer_a = crest_soft * max_a * (1.0 - 0.48 * (depth_below ** 1.5))

        blend = np.where(mask, layer_a, 0.0)[:, :, None]
        arr[:, :, :3] = arr[:, :, :3] * (1.0 - blend) + layer_rgb * blend
        arr[:, :, 3] = np.clip(arr[:, :, 3] + blend[:, :, 0] * (1.0 - arr[:, :, 3]), 0.0, 1.0)

    skirt_fade = 1.0 - np.clip((ys - 0.80) / 0.18, 0.0, 1.0)
    arr[:, :, 3] *= skirt_fade[:, 0][:, None] if skirt_fade.ndim > 2 else skirt_fade

    out_u8 = np.zeros((h, w, 4), dtype=np.uint8)
    out_u8[:, :, :3] = np.clip(arr[:, :, :3], 0, 255).astype(np.uint8)
    out_u8[:, :, 3] = np.clip(arr[:, :, 3] * 255.0, 0, 255).astype(np.uint8)
    img = Image.fromarray(out_u8, mode="RGBA").filter(ImageFilter.GaussianBlur(radius=0.75))
    path = OUT / "horizon_mountains.png"
    img.save(path)
    return path


if __name__ == "__main__":
    p1 = build_rural_paddies_texture()
    p2 = build_horizon_mountains_texture()
    print("Generated Taiping-Village cloud-sea & paddy valley textures:", p1.name, p2.name)
