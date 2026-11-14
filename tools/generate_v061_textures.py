"""Generate high-resolution Jiangnan botanical foliage, Azalea & Moso bamboo textures for v0.6.1.

Outputs into tools/generated_v061/ (embedded into GLB assets by build_v061_assets.py):
- camphor_bough.png      (1024x1024 RGBA: glossy Cinnamomum camphora twig & 3-veined leaves)
- willow_curtain.png     (1024x1024 RGBA: weeping Salix babylonica cascading whips & leaves)
- maple_tallow_bough.png (1024x1024 RGBA: Southern Chinese Triadica/Acer rhomboid & trilobed bough)
- bamboo_spray.png       (1024x1024 RGBA: feathery lanceolate Moso bamboo leaf spray)
- azalea_bough.png       (1024x1024 RGBA: Jiangnan Rhododendron simsii 映山红 leaves & crimson blossoms)
- bamboo_culm.png        (512x1024 RGB: tileable Moso bamboo culm with internode grain & node ring)

Every RGBA cutout texture performs multi-pass RGB edge dilation into transparent pixels so
mipmap downsampling in Godot never produces dark or white fringes!
"""
from __future__ import annotations

import math
from pathlib import Path
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "generated_v061"
OUT.mkdir(parents=True, exist_ok=True)


def _bleed_rgb_into_alpha(img: Image.Image, iterations: int = 20) -> Image.Image:
    """Dilate valid RGB colors outward into alpha==0 pixels to eliminate mipmap halos."""
    arr = np.array(img, dtype=np.uint8)
    rgb = arr[:, :, :3].astype(np.float32)
    alpha = arr[:, :, 3]
    valid = alpha > 24
    if np.any(valid):
        mean_col = rgb[valid].mean(axis=0)
    else:
        mean_col = np.array([48.0, 82.0, 38.0], dtype=np.float32)

    cur_rgb = rgb.copy()
    cur_mask = valid.copy()
    for _ in range(iterations):
        inv = ~cur_mask
        if not np.any(inv):
            break
        acc = np.zeros_like(cur_rgb)
        cnt = np.zeros(cur_mask.shape, dtype=np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            s_rgb = np.roll(np.roll(cur_rgb, dy, axis=0), dx, axis=1)
            s_msk = np.roll(np.roll(cur_mask, dy, axis=0), dx, axis=1)
            acc += s_rgb * s_msk[:, :, None]
            cnt += s_msk.astype(np.float32)
        fill = inv & (cnt > 0)
        cur_rgb[fill] = acc[fill] / cnt[fill, None]
        cur_mask[fill] = True

    cur_rgb[~cur_mask] = mean_col
    out = np.zeros_like(arr)
    out[:, :, :3] = np.clip(cur_rgb, 0, 255).astype(np.uint8)
    out[:, :, 3] = alpha
    return Image.fromarray(out, mode="RGBA")


def _draw_pointed_leaf(
    draw: ImageDraw.ImageDraw,
    base_xy: tuple[float, float],
    angle_rad: float,
    length: float,
    width: float,
    fill_rgb: tuple[int, int, int],
    vein_rgb: tuple[int, int, int],
    tip_taper: float = 1.45,
    three_vein: bool = False,
) -> None:
    bx, by = base_xy
    ca, sa = math.cos(angle_rad), math.sin(angle_rad)
    nx, ny = -sa, ca
    pts = []
    steps = 12
    for i in range(steps + 1):
        t = i / steps
        half_w = 0.5 * width * math.sin(math.pi * (t ** 0.78)) * ((1.0 - t * 0.28) ** (tip_taper - 1.0))
        pts.append((bx + ca * length * t + nx * half_w, by + sa * length * t + ny * half_w))
    for i in range(steps - 1, 0, -1):
        t = i / steps
        half_w = 0.5 * width * math.sin(math.pi * (t ** 0.78)) * ((1.0 - t * 0.28) ** (tip_taper - 1.0))
        pts.append((bx + ca * length * t - nx * half_w, by + sa * length * t - ny * half_w))
    draw.polygon(pts, fill=(*fill_rgb, 255))
    hi_rgb = (
        min(255, int(fill_rgb[0] * 1.10 + 5)),
        min(255, int(fill_rgb[1] * 1.09 + 6)),
        min(255, int(fill_rgb[2] * 1.05 + 3)),
    )
    draw.polygon(pts[: steps + 1], fill=(*hi_rgb, 255))
    tip_x = bx + ca * length * 0.90
    tip_y = by + sa * length * 0.90
    draw.line([(bx, by), (tip_x, tip_y)], fill=(*vein_rgb, 255), width=max(1, int(width * 0.06)))
    if three_vein:
        vx = bx + ca * length * 0.18
        vy = by + sa * length * 0.18
        for sgn in (-1.0, 1.0):
            lx = bx + ca * length * 0.68 + nx * width * 0.25 * sgn
            ly = by + sa * length * 0.68 + ny * width * 0.25 * sgn
            draw.line([(vx, vy), (lx, ly)], fill=(*vein_rgb, 235), width=max(1, int(width * 0.04)))


def _draw_trilobed_leaf(
    draw: ImageDraw.ImageDraw,
    base_xy: tuple[float, float],
    angle_rad: float,
    length: float,
    width: float,
    fill_rgb: tuple[int, int, int],
    vein_rgb: tuple[int, int, int],
) -> None:
    _draw_pointed_leaf(draw, base_xy, angle_rad, length, width * 0.56, fill_rgb, vein_rgb, tip_taper=1.35)
    bx, by = base_xy
    fork = (bx + math.cos(angle_rad) * length * 0.16, by + math.sin(angle_rad) * length * 0.16)
    for sgn in (-1.0, 1.0):
        _draw_pointed_leaf(
            draw,
            fork,
            angle_rad + sgn * 0.66,
            length * 0.72,
            width * 0.44,
            fill_rgb,
            vein_rgb,
            tip_taper=1.40,
        )


def _draw_azalea_flower(
    draw: ImageDraw.ImageDraw,
    center_xy: tuple[float, float],
    radius: float,
    rot_rad: float,
    rng: random.Random,
) -> None:
    """Draw a 5-petaled Jiangnan Rhododendron simsii (映山红) crimson-rose blossom."""
    cx, cy = center_xy
    petal_base = (rng.randint(186, 218), rng.randint(42, 68), rng.randint(68, 96))
    petal_throat = (148, 22, 46)
    for k in range(5):
        a = rot_rad + k * (math.tau / 5.0) + rng.uniform(-0.08, 0.08)
        ca, sa = math.cos(a), math.sin(a)
        nx, ny = -sa, ca
        pts = [(cx, cy)]
        for s in range(1, 9):
            t = s / 8.0
            hw = radius * 0.50 * math.sin(math.pi * (t ** 0.68))
            pts.append((cx + ca * radius * t + nx * hw, cy + sa * radius * t + ny * hw))
        for s in range(7, 0, -1):
            t = s / 8.0
            hw = radius * 0.50 * math.sin(math.pi * (t ** 0.68))
            pts.append((cx + ca * radius * t - nx * hw, cy + sa * radius * t - ny * hw))
        p_col = (
            min(255, petal_base[0] + rng.randint(-10, 10)),
            min(255, petal_base[1] + rng.randint(-6, 8)),
            min(255, petal_base[2] + rng.randint(-8, 8)),
        )
        draw.polygon(pts, fill=(*p_col, 255))
    # Deep crimson throat speckles on upper petal + golden-pink stamens
    r_in = radius * 0.24
    draw.ellipse((cx - r_in, cy - r_in, cx + r_in, cy + r_in), fill=(*petal_throat, 255))
    for st in range(6):
        sa_ang = rot_rad + (st - 2.5) * 0.34
        sx = cx + math.cos(sa_ang) * radius * 0.48
        sy = cy + math.sin(sa_ang) * radius * 0.48
        draw.line([(cx, cy), (sx, sy)], fill=(238, 175, 168, 255), width=2)
        draw.ellipse((sx - 3, sy - 3, sx + 3, sy + 3), fill=(246, 214, 118, 255))


def _draw_twig(
    draw: ImageDraw.ImageDraw,
    pts: list[tuple[float, float]],
    w0: float,
    w1: float,
    col: tuple[int, int, int],
) -> None:
    n = len(pts) - 1
    for i in range(n):
        t = i / max(1, n)
        w = max(2, int(w0 * (1.0 - t) + w1 * t))
        draw.line([pts[i], pts[i + 1]], fill=(*col, 255), width=w)


def build_camphor_bough() -> Path:
    """Lush, deeply layered Jiangnan Camphor (香樟) bough with full basal & mid foliage."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6101)

    bark_col = (64, 50, 38)
    twig_col = (72, 84, 46)

    main_branches = [
        [(512, 1005), (506, 835), (494, 635), (498, 415), (512, 175)],
        [(510, 915), (375, 785), (245, 635), (145, 475)],
        [(510, 900), (650, 770), (780, 620), (878, 465)],
        [(498, 695), (350, 540), (218, 360), (148, 205)],
        [(498, 680), (655, 528), (785, 350), (862, 198)],
        [(498, 465), (378, 300), (288, 138)],
        [(500, 455), (632, 295), (722, 138)],
    ]

    # Pass 1: dense shaded interior camphor leaves (rich deep woodland olive-emerald)
    for br in main_branches:
        for seg_i in range(len(br) - 1):
            x0, y0 = br[seg_i]
            x1, y1 = br[seg_i + 1]
            seg_ang = math.atan2(y1 - y0, x1 - x0)
            for k in range(7):
                u = (k + 0.2) / 7.0
                px = x0 + (x1 - x0) * u + rng.uniform(-28, 28)
                py = y0 + (y1 - y0) * u + rng.uniform(-28, 28)
                ang = seg_ang + rng.choice([-1.0, 1.0]) * rng.uniform(0.35, 1.25)
                L = rng.uniform(128, 172)
                W = L * rng.uniform(0.48, 0.58)
                col = (rng.randint(30, 46), rng.randint(64, 88), rng.randint(28, 42))
                _draw_pointed_leaf(draw, (px, py), ang, L, W, col, (48, 92, 40), three_vein=True)

    # Pass 2: twigs
    for idx, br in enumerate(main_branches):
        _draw_twig(draw, br, 16 if idx == 0 else 11, 4, bark_col if idx == 0 else twig_col)

    # Pass 3: rich natural Jiangnan camphor emerald leaves + subtle spring-flush tips
    for br in main_branches:
        for seg_i in range(len(br) - 1):
            x0, y0 = br[seg_i]
            x1, y1 = br[seg_i + 1]
            seg_ang = math.atan2(y1 - y0, x1 - x0)
            for k in range(7):
                u = (k + 0.38) / 7.0
                px = x0 + (x1 - x0) * u + rng.uniform(-16, 16)
                py = y0 + (y1 - y0) * u + rng.uniform(-16, 16)
                side = -1.0 if (k % 2 == 0) else 1.0
                ang = seg_ang + side * rng.uniform(0.32, 0.96)
                is_tip = seg_i == len(br) - 2 and k >= 4
                L = rng.uniform(112, 152) if not is_tip else rng.uniform(96, 130)
                W = L * rng.uniform(0.46, 0.56)
                if is_tip:
                    col = (rng.randint(68, 92), rng.randint(114, 142), rng.randint(40, 56))
                    vein = (106, 152, 64)
                else:
                    col = (rng.randint(44, 66), rng.randint(86, 116), rng.randint(34, 50))
                    vein = (78, 126, 56)
                _draw_pointed_leaf(draw, (px, py), ang, L, W, col, vein, three_vein=True)
        tx, ty = br[-1]
        base_a = math.atan2(ty - br[-2][1], tx - br[-2][0])
        for da in (-0.52, 0.0, 0.52):
            col = (rng.randint(72, 96), rng.randint(118, 146), rng.randint(42, 58))
            _draw_pointed_leaf(draw, (tx, ty), base_a + da, rng.uniform(102, 130), 58, col, (112, 158, 68), three_vein=True)

    out_img = _bleed_rgb_into_alpha(img, iterations=20)
    path = OUT / "camphor_bough.png"
    out_img.save(path)
    return path


def build_willow_curtain() -> Path:
    """Soft cascading Jiangnan Weeping Willow (垂柳) frond curtain without heavy dark top bar."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6102)

    # Soft leafy top crown cluster along y=55..135 (NO heavy dark brown crossbar so top views look leafy & natural!)
    for tx_i in range(28):
        tx = 85 + (tx_i / 27.0) * (sz - 170) + rng.uniform(-16, 16)
        ty = 88 - 32 * math.sin(math.pi * (tx_i / 27.0)) + rng.uniform(-14, 18)
        ang = math.pi * 0.5 + rng.uniform(-1.05, 1.05)
        L = rng.uniform(86, 122)
        g_v = rng.randint(96, 132)
        r_v = int(g_v * rng.uniform(0.54, 0.68))
        b_v = rng.randint(38, 54)
        _draw_pointed_leaf(draw, (tx, ty), ang, L, L * 0.22, (r_v, g_v, b_v), (r_v + 20, g_v + 24, b_v + 10), tip_taper=1.6)

    # 13 slender olive-green willow whips drooping gracefully down to y = 800..990
    n_whips = 13
    for wi in range(n_whips):
        u = (wi + 0.5) / n_whips
        start_x = 76 + u * (sz - 152) + rng.uniform(-14, 14)
        start_y = 92 - 32 * math.sin(math.pi * u)
        end_y = rng.uniform(815, 990)
        sway_amp = rng.uniform(14, 32)
        sway_phase = rng.uniform(0, math.tau)
        whip_pts = []
        steps = 18
        for s in range(steps + 1):
            t = s / steps
            wx = start_x + sway_amp * math.sin(t * 3.4 + sway_phase) * t
            wy = start_y + (end_y - start_y) * t
            whip_pts.append((wx, wy))
        _draw_twig(draw, whip_pts, 4, 2, (86, 108, 48))

        n_leaves = 26
        for li in range(n_leaves):
            lt = (li + 0.3) / n_leaves
            idx_f = lt * steps
            i0 = min(steps - 1, int(idx_f))
            frac = idx_f - i0
            px = whip_pts[i0][0] * (1.0 - frac) + whip_pts[i0 + 1][0] * frac
            py = whip_pts[i0][1] * (1.0 - frac) + whip_pts[i0 + 1][1] * frac
            tang = math.atan2(whip_pts[i0 + 1][1] - whip_pts[i0][1], whip_pts[i0 + 1][0] - whip_pts[i0][0])
            side = -1.0 if (li % 2 == 0) else 1.0
            ang = tang + side * rng.uniform(0.32, 0.68)
            L = rng.uniform(82, 118) * (1.0 - 0.20 * lt)
            W = L * rng.uniform(0.18, 0.24)
            # Authentic Jiangnan river-willow jade green (not neon!)
            g_val = rng.randint(100, 138)
            r_val = int(g_val * rng.uniform(0.55, 0.68))
            b_val = rng.randint(38, 56)
            _draw_pointed_leaf(draw, (px, py), ang, L, W, (r_val, g_val, b_val), (r_val + 22, min(255, g_val + 24), b_val + 12), tip_taper=1.65)

    out_img = _bleed_rgb_into_alpha(img, iterations=20)
    path = OUT / "willow_curtain.png"
    out_img.save(path)
    return path


def build_maple_tallow_bough() -> Path:
    """Southern Chinese Trident Maple / Chinese Tallow (三角枫/乌桕) bough."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6103)

    branches = [
        [(512, 1002), (516, 815), (502, 600), (510, 385), (514, 175)],
        [(514, 890), (370, 745), (238, 580), (152, 420)],
        [(514, 880), (660, 740), (788, 575), (870, 415)],
        [(504, 635), (348, 480), (222, 305)],
        [(504, 625), (662, 475), (790, 300)],
        [(508, 420), (385, 255), (305, 140)],
        [(508, 415), (635, 250), (718, 140)],
    ]

    for br in branches:
        for seg_i in range(len(br) - 1):
            x0, y0 = br[seg_i]
            x1, y1 = br[seg_i + 1]
            seg_ang = math.atan2(y1 - y0, x1 - x0)
            for k in range(6):
                u = (k + 0.25) / 6.0
                px = x0 + (x1 - x0) * u + rng.uniform(-22, 22)
                py = y0 + (y1 - y0) * u + rng.uniform(-22, 22)
                ang = seg_ang + rng.choice([-1.0, 1.0]) * rng.uniform(0.35, 1.10)
                L = rng.uniform(110, 148)
                col = (rng.randint(38, 58), rng.randint(74, 100), rng.randint(32, 46))
                _draw_trilobed_leaf(draw, (px, py), ang, L, L * 0.86, col, (66, 110, 48))

    for idx, br in enumerate(branches):
        _draw_twig(draw, br, 15 if idx == 0 else 10, 4, (66, 52, 40))

    for br in branches:
        for seg_i in range(len(br) - 1):
            x0, y0 = br[seg_i]
            x1, y1 = br[seg_i + 1]
            seg_ang = math.atan2(y1 - y0, x1 - x0)
            for k in range(6):
                u = (k + 0.42) / 6.0
                px = x0 + (x1 - x0) * u + rng.uniform(-15, 15)
                py = y0 + (y1 - y0) * u + rng.uniform(-15, 15)
                side = -1.0 if (k % 2 == 0) else 1.0
                ang = seg_ang + side * rng.uniform(0.32, 0.94)
                is_sun_tip = (seg_i == len(br) - 2 and k >= 4) or rng.random() < 0.16
                L = rng.uniform(102, 138)
                if is_sun_tip:
                    col = (rng.randint(114, 148), rng.randint(108, 132), rng.randint(40, 54))
                    vein = (148, 142, 66)
                else:
                    col = (rng.randint(52, 78), rng.randint(94, 124), rng.randint(36, 52))
                    vein = (88, 136, 60)
                _draw_trilobed_leaf(draw, (px, py), ang, L, L * 0.85, col, vein)

    out_img = _bleed_rgb_into_alpha(img, iterations=20)
    path = OUT / "maple_tallow_bough.png"
    out_img.save(path)
    return path


def build_azalea_bough() -> Path:
    """Authentic Jiangnan Mountain Azalea (映山红 / 杜鹃 Rhododendron simsii) leafy flowering bough."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6106)

    branches = [
        [(512, 1002), (506, 825), (498, 615), (510, 405), (512, 215)],
        [(508, 895), (355, 748), (218, 575), (145, 420)],
        [(508, 885), (665, 742), (798, 570), (875, 415)],
        [(500, 660), (345, 505), (225, 335)],
        [(500, 650), (658, 500), (785, 330)],
        [(506, 445), (380, 285), (298, 175)],
        [(508, 440), (636, 280), (720, 175)],
    ]

    # Deep leathery dark-emerald azalea leaf clusters
    for br in branches:
        for seg_i in range(len(br) - 1):
            x0, y0 = br[seg_i]
            x1, y1 = br[seg_i + 1]
            seg_ang = math.atan2(y1 - y0, x1 - x0)
            for k in range(7):
                u = (k + 0.25) / 7.0
                px = x0 + (x1 - x0) * u + rng.uniform(-24, 24)
                py = y0 + (y1 - y0) * u + rng.uniform(-24, 24)
                ang = seg_ang + rng.choice([-1.0, 1.0]) * rng.uniform(0.30, 1.18)
                L = rng.uniform(98, 138)
                W = L * rng.uniform(0.46, 0.56)
                col = (rng.randint(32, 54), rng.randint(68, 98), rng.randint(28, 44))
                _draw_pointed_leaf(draw, (px, py), ang, L, W, col, (58, 108, 46), tip_taper=1.35)

    for idx, br in enumerate(branches):
        _draw_twig(draw, br, 15 if idx == 0 else 10, 4, (72, 54, 40))

    # Glossy upper whorls of azalea leaves + clusters of crimson-rose 映山红 flowers at branch tips!
    for br in branches:
        for seg_i in range(len(br) - 1):
            x0, y0 = br[seg_i]
            x1, y1 = br[seg_i + 1]
            seg_ang = math.atan2(y1 - y0, x1 - x0)
            for k in range(6):
                u = (k + 0.4) / 6.0
                px = x0 + (x1 - x0) * u + rng.uniform(-14, 14)
                py = y0 + (y1 - y0) * u + rng.uniform(-14, 14)
                side = -1.0 if (k % 2 == 0) else 1.0
                ang = seg_ang + side * rng.uniform(0.35, 0.95)
                L = rng.uniform(92, 126)
                W = L * rng.uniform(0.45, 0.55)
                col = (rng.randint(42, 66), rng.randint(84, 114), rng.randint(34, 48))
                _draw_pointed_leaf(draw, (px, py), ang, L, W, col, (76, 126, 54), tip_taper=1.35)

        # Terminal blossom umbel of 2-3 crimson-magenta Rhododendron flowers
        tx, ty = br[-1]
        mx, my = (br[-1][0] + br[-2][0]) * 0.5, (br[-1][1] + br[-2][1]) * 0.5
        for fx, fy, fr in (
            (tx - 24, ty + 10, rng.uniform(46, 58)),
            (tx + 24, ty + 14, rng.uniform(44, 56)),
            (mx + rng.uniform(-22, 22), my + rng.uniform(-18, 18), rng.uniform(40, 52)),
        ):
            _draw_azalea_flower(draw, (fx, fy), fr, rng.uniform(0, math.tau), rng)

    out_img = _bleed_rgb_into_alpha(img, iterations=20)
    path = OUT / "azalea_bough.png"
    out_img.save(path)
    return path


def build_bamboo_spray() -> Path:
    """Feathery lanceolate Moso bamboo (毛竹) leaf spray fanning from bottom-center."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6104)

    stems = [
        [(512, 995), (508, 760), (496, 510), (508, 260)],
        [(509, 820), (365, 650), (235, 455)],
        [(509, 800), (655, 635), (790, 445)],
        [(500, 580), (355, 405), (245, 240)],
        [(500, 565), (650, 395), (765, 235)],
    ]

    for st in stems:
        _draw_twig(draw, st, 9, 3, (74, 102, 48))
        for idx in range(1, len(st)):
            nx, ny = st[idx]
            prev_x, prev_y = st[idx - 1]
            base_ang = math.atan2(ny - prev_y, nx - prev_x)
            n_fan = 6 if idx == len(st) - 1 else 5
            spread = 1.28
            for fi in range(n_fan):
                fa = base_ang + ((fi / max(1, n_fan - 1)) - 0.5) * 2.0 * spread + rng.uniform(-0.08, 0.08)
                L = rng.uniform(175, 248)
                W = L * rng.uniform(0.13, 0.17)
                g_val = rng.randint(96, 138)
                r_val = int(g_val * rng.uniform(0.50, 0.64))
                b_val = rng.randint(36, 54)
                _draw_pointed_leaf(
                    draw,
                    (nx, ny),
                    fa,
                    L,
                    W,
                    (r_val, g_val, b_val),
                    (r_val + 24, min(255, g_val + 26), b_val + 12),
                    tip_taper=1.75,
                )

    out_img = _bleed_rgb_into_alpha(img, iterations=20)
    path = OUT / "bamboo_spray.png"
    out_img.save(path)
    return path


def build_bamboo_culm() -> Path:
    """Seamless 512x1024 Moso bamboo culm texture with 4 internodes, nodal rings, and white waxy bloom."""
    w, h = 512, 1024
    rng = np.random.default_rng(6105)
    yy, xx = np.meshgrid(np.linspace(0.0, 1.0, h, endpoint=False), np.linspace(0.0, 1.0, w, endpoint=False), indexing="ij")

    fibers = (
        4.5 * np.sin(xx * math.tau * 38.0)
        + 2.8 * np.cos(xx * math.tau * 97.0 + yy * math.tau * 2.0)
        + rng.normal(0.0, 2.2, size=(h, w))
    )
    node_phase = (yy * 4.0) % 1.0
    dist_to_node = np.minimum(node_phase, 1.0 - node_phase)

    arr = np.zeros((h, w, 3), dtype=np.float32)
    mottle = 7.0 * np.sin(xx * math.tau * 3.0 + yy * math.tau * 2.0)
    arr[:, :, 0] = 82.0 + mottle * 0.9 + fibers * 0.7
    arr[:, :, 1] = 118.0 + mottle * 1.0 + fibers * 0.9
    arr[:, :, 2] = 58.0 + mottle * 0.5 + fibers * 0.5

    bloom = np.exp(-((node_phase - 0.048) / 0.032) ** 2) * 0.34
    arr = arr * (1.0 - bloom[:, :, None]) + np.array([172.0, 186.0, 154.0])[None, None, :] * bloom[:, :, None]

    dark_ring = np.exp(-(dist_to_node / 0.011) ** 2) * 0.70
    arr = arr * (1.0 - dark_ring[:, :, None]) + np.array([38.0, 48.0, 26.0])[None, None, :] * dark_ring[:, :, None]

    ridge = np.exp(-((node_phase - 0.982) / 0.009) ** 2) * 0.34
    arr = arr * (1.0 - ridge[:, :, None]) + np.array([142.0, 156.0, 102.0])[None, None, :] * ridge[:, :, None]

    img = Image.fromarray(np.clip(arr, 16, 230).astype(np.uint8), mode="RGB")
    path = OUT / "bamboo_culm.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


def _stage_bark_diffuse(src: Path, dst: Path, mul_rgb: tuple[float, float, float]) -> None:
    """Resize and tone bright studio-scanned bark to rich, humid Jiangnan mountain bark."""
    im = Image.open(src).convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    arr = np.array(im, dtype=np.float32)
    arr[:, :, 0] *= mul_rgb[0]
    arr[:, :, 1] *= mul_rgb[1]
    arr[:, :, 2] *= mul_rgb[2]
    Image.fromarray(np.clip(arr, 12, 235).astype(np.uint8), mode="RGB").save(dst, quality=88, optimize=True)


if __name__ == "__main__":
    dl_ph = ROOT / "downloads" / "slice-v061" / "polyhaven"
    slice_dir = ROOT / "game" / "assets" / "slice"
    slice_dir.mkdir(parents=True, exist_ok=True)
    staged = []
    if dl_ph.exists():
        bark_tones = {
            "japanese_camphor_bark": (0.54, 0.50, 0.45),
            "bark_willow": (0.64, 0.62, 0.56),
            "trident_maple_bark": (0.62, 0.58, 0.54),
        }
        for bark, tone in bark_tones.items():
            src_d = dl_ph / f"{bark}_diffuse.jpg"
            if src_d.exists():
                dst_d = OUT / f"{bark}_diff_512.jpg"
                _stage_bark_diffuse(src_d, dst_d, tone)
                staged.append(dst_d.name)
            src_n = dl_ph / f"{bark}_nor_gl.jpg"
            if src_n.exists():
                dst_n = OUT / f"{bark}_norm_512.jpg"
                Image.open(src_n).convert("RGB").resize((512, 512), Image.Resampling.LANCZOS).save(dst_n, quality=88, optimize=True)
                staged.append(dst_n.name)
        for ch, dst_name in (
            ("diffuse", "river_pebbles_color.jpg"),
            ("nor_gl", "river_pebbles_normal.jpg"),
            ("rough", "river_pebbles_rough.jpg"),
        ):
            src = dl_ph / f"river_small_rocks_{ch}.jpg"
            if src.exists():
                dst = slice_dir / dst_name
                Image.open(src).convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS).save(dst, quality=88, optimize=True)
                staged.append(dst_name)

    paths = [
        build_camphor_bough(),
        build_willow_curtain(),
        build_maple_tallow_bough(),
        build_azalea_bough(),
        build_bamboo_spray(),
        build_bamboo_culm(),
    ]
    print("Generated v0.6.1 botanical textures:", [p.name for p in paths], "staged PBR:", staged)
