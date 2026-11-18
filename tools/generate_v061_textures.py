"""Generate Taiping-Village inspired Jiangnan Cloud-Sea & Terraced Mountain (太平村·江南云海梯田山境)
painterly brushstroke botanical textures.

Color Science (empirically sampled from the Taiping Village reference):
- Warm Golden-Olive Sunlit Crowns (R > B: #5c823c -> #809e4a, zero plastic bluish-neon!)
- Cool Cerulean-Teal Sky-Lit Shadows (B >= R: #224246 -> #345b5c, Ghibli/Shinkai hue shift!)
- Airy calligraphic negative space ('疏可走马 · 露枝透云天') + creamy mountain blossoms!
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


def _bleed_rgb_into_alpha(img: Image.Image, iterations: int = 24) -> Image.Image:
    """Dilate valid RGB colors outward into alpha==0 pixels to prevent dark/white mipmap fringes."""
    arr = np.array(img, dtype=np.uint8)
    rgb = arr[:, :, :3].astype(np.float32)
    alpha = arr[:, :, 3]
    valid = alpha > 32
    mean_col = rgb[valid].mean(axis=0) if np.any(valid) else np.array([76.0, 108.0, 62.0], dtype=np.float32)

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


def _draw_sumi_leaf(
    draw: ImageDraw.ImageDraw,
    base_xy: tuple[float, float],
    angle_rad: float,
    length: float,
    width: float,
    fill_rgb: tuple[int, int, int],
    tip_rgb: tuple[int, int, int] | None = None,
    rim_rgb: tuple[int, int, int] | None = None,
    tip_taper: float = 1.42,
    alpha: int = 255,
) -> None:
    """Draw a painterly brushstroke leaf cluster dab (warm sunlit tip, cool teal base)."""
    bx, by = base_xy
    ca, sa = math.cos(angle_rad), math.sin(angle_rad)
    nx, ny = -sa, ca
    steps = 11
    pts = []
    for i in range(steps + 1):
        t = i / steps
        half_w = 0.5 * width * math.sin(math.pi * (t ** 0.72)) * ((1.0 - t * 0.26) ** (tip_taper - 1.0))
        pts.append((bx + ca * length * t + nx * half_w, by + sa * length * t + ny * half_w))
    for i in range(steps - 1, 0, -1):
        t = i / steps
        half_w = 0.5 * width * math.sin(math.pi * (t ** 0.72)) * ((1.0 - t * 0.26) ** (tip_taper - 1.0))
        pts.append((bx + ca * length * t - nx * half_w, by + sa * length * t - ny * half_w))

    if rim_rgb is not None:
        draw.polygon(pts, fill=(*rim_rgb, alpha))
        cx = bx + ca * length * 0.45
        cy = by + sa * length * 0.45
        in_pts = [(cx + (px - cx) * 0.91, cy + (py - cy) * 0.91) for px, py in pts]
        draw.polygon(in_pts, fill=(*fill_rgb, alpha))
    else:
        draw.polygon(pts, fill=(*fill_rgb, alpha))

    if tip_rgb is not None:
        tip_poly = pts[4 : steps + 1] + pts[steps + 1 : len(pts) - 3]
        if len(tip_poly) >= 3:
            draw.polygon(tip_poly, fill=(*tip_rgb, max(195, alpha - 15)))


def _draw_twig(draw: ImageDraw.ImageDraw, pts: list[tuple[float, float]], w0: float, w1: float, col: tuple[int, int, int]) -> None:
    n = len(pts) - 1
    for i in range(n):
        t = i / max(1, n)
        w = max(2, int(w0 * (1.0 - t) + w1 * t))
        draw.line([pts[i], pts[i + 1]], fill=(*col, 255), width=w)


def build_camphor_ink_dab() -> Path:
    """Camera-facing painterly cloud-puff foliage dab calibrated to Taiping Village canopies:
    cool teal-emerald core -> warm golden-sprout sunlit tips!"""
    sz = 512
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6501)

    sub_clusters = [
        (256, 295, -math.pi * 0.50, 1.00, False),
        (148, 268, -math.pi * 0.78, 0.88, False),
        (366, 264, -math.pi * 0.22, 0.88, False),
        (192, 176, -math.pi * 0.64, 0.92, True),
        (324, 174, -math.pi * 0.36, 0.92, True),
        (256, 142, -math.pi * 0.50, 0.95, True),
    ]
    _draw_twig(draw, [(256, 415), (252, 285), (195, 195)], 7, 3, (58, 52, 44))
    _draw_twig(draw, [(252, 295), (318, 202)], 6, 3, (58, 52, 44))

    for cx, cy, c_ang, sc, is_top in sub_clusters:
        # Cool sky-lit teal-pine backing dabs (matches Taiping cool canopy shadow #23464b)
        for k in range(5):
            a = c_ang + (k - 2.0) * 0.48 + rng.uniform(-0.08, 0.08)
            L = rng.uniform(98, 128) * sc
            col = (rng.randint(36, 48), rng.randint(68, 82), rng.randint(66, 76))
            _draw_sumi_leaf(draw, (cx, cy + 12), a, L, L * 0.56, col, rim_rgb=(28, 52, 54))

        # Mid & sunlit warm golden-olive spring-sprout dabs (R > B: #5c843d -> #82a44c!)
        for k in range(5):
            a = c_ang + (k - 2.0) * 0.42 + rng.uniform(-0.07, 0.07)
            ox = cx + math.cos(a) * 14
            oy = cy + math.sin(a) * 14
            L = rng.uniform(84, 114) * sc
            if is_top:
                col = (rng.randint(92, 110), rng.randint(128, 146), rng.randint(62, 74))
                tip = (rng.randint(122, 142), rng.randint(154, 172), rng.randint(72, 84))
            else:
                col = (rng.randint(68, 84), rng.randint(104, 120), rng.randint(56, 68))
                tip = (rng.randint(94, 112), rng.randint(130, 146), rng.randint(64, 76))
            _draw_sumi_leaf(draw, (ox, oy), a, L, L * 0.52, col, tip_rgb=tip, rim_rgb=(44, 74, 52))

    arr = np.array(img)
    rgb_blur = np.array(Image.fromarray(arr[:, :, :3]).filter(ImageFilter.GaussianBlur(1.0)))
    arr[:, :, :3] = rgb_blur
    out_img = _bleed_rgb_into_alpha(Image.fromarray(arr, mode="RGBA"), iterations=20)
    path = OUT / "camphor_ink_dab.png"
    out_img.save(path)
    return path


def build_camphor_bough() -> Path:
    """Painterly Camphor bough with warm timber twigs & golden-sprout spring foliage."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6502)

    bark_warm = (64, 56, 46)
    branches = [
        [(512, 998), (496, 790), (518, 545), (498, 295)],
        [(500, 845), (332, 695), (212, 540)],
        [(502, 825), (685, 685), (805, 525)],
        [(514, 585), (330, 425), (235, 285)],
        [(514, 575), (685, 420), (782, 280)],
    ]
    for idx, br in enumerate(branches):
        _draw_twig(draw, br, 20 if idx == 0 else 13, 5, bark_warm)

    bouquets = [
        (508, 745, -math.pi * 0.50, 0.92, False),
        (235, 555, -math.pi * 0.74, 0.90, False),
        (785, 545, -math.pi * 0.26, 0.90, False),
        (252, 305, -math.pi * 0.66, 0.94, True),
        (768, 298, -math.pi * 0.34, 0.94, True),
        (504, 240, -math.pi * 0.50, 0.98, True),
    ]
    for bx, by, center_ang, sc, is_upper in bouquets:
        for fi in range(5):
            a = center_ang + (fi - 2.0) * 0.45 + rng.uniform(-0.06, 0.06)
            L = rng.uniform(165, 198) * sc
            col = (rng.randint(36, 48), rng.randint(68, 82), rng.randint(66, 76))
            _draw_sumi_leaf(draw, (bx, by + 22), a, L, L * 0.52, col, rim_rgb=(28, 52, 54))
        for fi in range(5):
            a = center_ang + (fi - 2.0) * 0.39 + rng.uniform(-0.05, 0.05)
            ox = bx + math.cos(a) * 28
            oy = by + math.sin(a) * 28
            L = rng.uniform(145, 175) * sc
            if is_upper:
                col = (rng.randint(92, 110), rng.randint(128, 146), rng.randint(62, 74))
                tip_c = (rng.randint(120, 140), rng.randint(152, 170), rng.randint(70, 82))
            else:
                col = (rng.randint(68, 84), rng.randint(104, 120), rng.randint(56, 68))
                tip_c = (rng.randint(92, 110), rng.randint(128, 144), rng.randint(62, 74))
            _draw_sumi_leaf(draw, (ox, oy), a, L, L * 0.48, col, tip_rgb=tip_c, rim_rgb=(42, 72, 50))

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "camphor_bough.png"
    out_img.save(path)
    return path


def build_willow_curtain() -> Path:
    """Sunlit Jiangnan Spring Weeping Willow ('万条垂下绿丝绦'): warm golden-jade slender wisps + >68% sky air."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6503)

    arch_pts = [(75, 115), (295, 58), (512, 44), (735, 62), (945, 120)]
    _draw_twig(draw, arch_pts, 11, 6, (62, 58, 46))

    n_whips = 7
    for wi in range(n_whips):
        u = (wi + 0.5) / n_whips
        start_x = 105 + u * (sz - 210) + rng.uniform(-16, 16)
        start_y = 66 + 48 * ((2.0 * u - 1.0) ** 2)
        end_y = rng.uniform(810, 965) if (wi % 2 == 0) else rng.uniform(620, 785)
        sway_amp = rng.uniform(22, 42)
        sway_phase = rng.uniform(0, math.tau)
        whip_pts = []
        steps = 16
        for s in range(steps + 1):
            t = s / steps
            wx = start_x + 26.0 * (t ** 1.5) + sway_amp * math.sin(t * 2.6 + sway_phase) * t
            wy = start_y + (end_y - start_y) * t
            whip_pts.append((wx, wy))
        _draw_twig(draw, whip_pts, 5, 2, (68, 84, 52))

        is_fg = (wi % 2 == 0)
        n_leaves = 11
        for li in range(n_leaves):
            lt = (li + 0.2) / n_leaves
            idx_f = lt * steps
            i0 = min(steps - 1, int(idx_f))
            frac = idx_f - i0
            px = whip_pts[i0][0] * (1.0 - frac) + whip_pts[i0 + 1][0] * frac
            py = whip_pts[i0][1] * (1.0 - frac) + whip_pts[i0 + 1][1] * frac
            tang = math.atan2(whip_pts[i0 + 1][1] - whip_pts[i0][1], whip_pts[i0 + 1][0] - whip_pts[i0][0])
            side = -1.0 if (li % 2 == 0) else 1.0
            ang = tang + side * rng.uniform(0.24, 0.46)
            L = rng.uniform(98, 130) * (1.0 - 0.22 * lt)
            W = L * 0.175
            if is_fg:
                col = (rng.randint(98, 116), rng.randint(136, 154), rng.randint(64, 76))
                tip_c = (rng.randint(126, 146), rng.randint(162, 180), rng.randint(74, 88))
            else:
                col = (rng.randint(58, 72), rng.randint(94, 110), rng.randint(66, 76))
                tip_c = (rng.randint(82, 98), rng.randint(118, 134), rng.randint(66, 78))
            _draw_sumi_leaf(draw, (px, py), ang, L, W, col, tip_rgb=tip_c, rim_rgb=(44, 72, 52), tip_taper=1.78)

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "willow_curtain.png"
    out_img.save(path)
    return path


def build_maple_tallow_bough() -> Path:
    """Sunlit golden-amber & coral-apricot mountain broadleaf accent (matching Taiping warm slope highlights)."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6504)

    branches = [
        [(512, 998), (506, 795), (512, 555), (504, 295)],
        [(508, 840), (340, 690), (220, 535)],
        [(508, 830), (680, 685), (798, 530)],
        [(510, 585), (338, 430), (242, 285)],
        [(510, 575), (678, 425), (776, 280)],
    ]
    for idx, br in enumerate(branches):
        _draw_twig(draw, br, 18 if idx == 0 else 12, 4, (62, 54, 45))

    bouquets = [
        (512, 755, -math.pi * 0.50, 0.94, "sprout"),
        (248, 555, -math.pi * 0.72, 0.92, "amber"),
        (775, 550, -math.pi * 0.28, 0.92, "sprout"),
        (262, 310, -math.pi * 0.65, 0.96, "coral"),
        (760, 305, -math.pi * 0.35, 0.96, "amber"),
        (512, 240, -math.pi * 0.50, 1.00, "coral"),
    ]
    for bx, by, c_ang, sc, tone in bouquets:
        for fi in range(4):
            a = c_ang + (fi - 1.5) * 0.46 + rng.uniform(-0.06, 0.06)
            L = rng.uniform(155, 185) * sc
            col = (rng.randint(44, 56), rng.randint(72, 86), rng.randint(66, 76))
            _draw_sumi_leaf(draw, (bx, by + 18), a, L, L * 0.56, col, rim_rgb=(32, 54, 54))
        for fi in range(5):
            a = c_ang + (fi - 2.0) * 0.38 + rng.uniform(-0.05, 0.05)
            ox = bx + math.cos(a) * 28
            oy = by + math.sin(a) * 28 - 6
            L = rng.uniform(135, 165) * sc
            if tone == "coral":
                col = (rng.randint(162, 180), rng.randint(98, 114), rng.randint(76, 88))
                tip_c = (rng.randint(186, 204), rng.randint(122, 138), rng.randint(88, 100))
            elif tone == "amber":
                col = (rng.randint(158, 176), rng.randint(136, 152), rng.randint(68, 82))
                tip_c = (rng.randint(184, 202), rng.randint(160, 176), rng.randint(82, 96))
            else:
                col = (rng.randint(88, 106), rng.randint(124, 140), rng.randint(60, 72))
                tip_c = (rng.randint(118, 136), rng.randint(150, 166), rng.randint(72, 84))
            _draw_sumi_leaf(draw, (ox, oy), a, L, L * 0.54, col, tip_rgb=tip_c, rim_rgb=(46, 62, 48))

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "maple_tallow_bough.png"
    out_img.save(path)
    return path


def build_azalea_bough() -> Path:
    """Taiping Village foreground mountain blossom bush: lush emerald-olive leaves + creamy-ivory & soft coral blossoms!"""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6506)

    branches = [
        [(512, 998), (508, 805), (504, 580), (512, 330)],
        [(508, 860), (345, 710), (225, 545)],
        [(508, 850), (675, 705), (795, 540)],
        [(506, 615), (345, 455), (248, 315)],
        [(506, 605), (675, 450), (772, 310)],
    ]
    for idx, br in enumerate(branches):
        _draw_twig(draw, br, 16 if idx == 0 else 11, 4, (58, 54, 44))

    bouquets = [
        (512, 760, -math.pi * 0.50),
        (248, 565, -math.pi * 0.72),
        (775, 560, -math.pi * 0.28),
        (262, 335, -math.pi * 0.64),
        (760, 330, -math.pi * 0.36),
        (512, 270, -math.pi * 0.50),
    ]
    for bi, (bx, by, c_ang) in enumerate(bouquets):
        for fi in range(5):
            a = c_ang + (fi - 2.0) * 0.42 + rng.uniform(-0.05, 0.05)
            L = rng.uniform(140, 172)
            col = (rng.randint(58, 74), rng.randint(96, 114), rng.randint(58, 70))
            tip_c = (rng.randint(86, 106), rng.randint(126, 144), rng.randint(64, 76))
            _draw_sumi_leaf(draw, (bx, by), a, L, L * 0.48, col, tip_rgb=tip_c, rim_rgb=(34, 62, 54))

        # Luminous creamy-white mountain camellia/pear blossoms + golden stamen heart (just like Taiping bottom-left!)
        if bi >= 1:
            is_blush = (bi == 4)
            petal_col = (242, 198, 194, 250) if is_blush else (246, 242, 228, 252)
            heart_col = (228, 174, 64, 255)
            for fx_off, fy_off, fr in ((-28, -28, 36), (30, -20, 32)):
                cx, cy = bx + fx_off, by + fy_off
                for k in range(5):
                    pa = k * math.tau / 5.0 + rng.uniform(-0.08, 0.08)
                    px = cx + math.cos(pa) * fr * 0.56
                    py = cy + math.sin(pa) * fr * 0.56
                    draw.ellipse((px - fr * 0.44, py - fr * 0.44, px + fr * 0.44, py + fr * 0.44), fill=petal_col)
                draw.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=heart_col)

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "azalea_bough.png"
    out_img.save(path)
    return path


def build_bamboo_spray() -> Path:
    """Sunlit Spring Moso Bamboo ('翠竹介字叶'): cool teal-jade backing + sunlit golden-bamboo blades."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6505)

    stems = [
        [(512, 995), (508, 760), (502, 505), (512, 255)],
        [(509, 815), (345, 635), (225, 455)],
        [(509, 800), (675, 625), (795, 445)],
        [(504, 565), (350, 395), (255, 245)],
        [(504, 555), (665, 390), (765, 240)],
    ]
    for st in stems:
        _draw_twig(draw, st, 9, 3, (66, 86, 56))

    fan_nodes = [
        (235, 465, -math.pi * 0.72, False),
        (785, 455, -math.pi * 0.28, False),
        (505, 585, -math.pi * 0.50, False),
        (262, 255, -math.pi * 0.65, True),
        (758, 250, -math.pi * 0.35, True),
        (512, 245, -math.pi * 0.50, True),
    ]
    for nx, ny, base_ang, is_sun in fan_nodes:
        for sgn in (-0.50, 0.50):
            L = rng.uniform(225, 265)
            col = (rng.randint(38, 50), rng.randint(70, 84), rng.randint(64, 74))
            _draw_sumi_leaf(draw, (nx, ny + 10), base_ang + sgn, L, L * 0.155, col, rim_rgb=(28, 52, 52), tip_taper=1.78)
        for fi in range(4):
            fa = base_ang + (fi - 1.5) * 0.44 + rng.uniform(-0.04, 0.04)
            L = rng.uniform(215, 275)
            W = L * 0.16
            if is_sun:
                col = (rng.randint(88, 104), rng.randint(124, 142), rng.randint(60, 72))
                tip_c = (rng.randint(114, 132), rng.randint(150, 168), rng.randint(70, 82))
            else:
                col = (rng.randint(62, 78), rng.randint(98, 114), rng.randint(60, 70))
                tip_c = (rng.randint(86, 102), rng.randint(122, 138), rng.randint(64, 76))
            _draw_sumi_leaf(draw, (nx, ny), fa, L, W, col, tip_rgb=tip_c, rim_rgb=(38, 66, 50), tip_taper=1.80)

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "bamboo_spray.png"
    out_img.save(path)
    return path


def build_bamboo_culm() -> Path:
    """Sunlit spring jade-celadon Moso bamboo culm + powdery white nodal frost + crisp olive-ink rings."""
    w, h = 512, 1024
    rng = np.random.default_rng(6507)
    yy, xx = np.meshgrid(np.linspace(0.0, 1.0, h, endpoint=False), np.linspace(0.0, 1.0, w, endpoint=False), indexing="ij")

    fibers = 2.8 * np.sin(xx * math.tau * 26.0) + rng.normal(0.0, 1.2, size=(h, w))
    node_phase = (yy * 4.0) % 1.0
    dist_to_node = np.minimum(node_phase, 1.0 - node_phase)

    grad = node_phase
    arr = np.zeros((h, w, 3), dtype=np.float32)
    arr[:, :, 0] = 96.0 + 18.0 * grad + fibers * 0.5
    arr[:, :, 1] = 128.0 + 20.0 * grad + fibers * 0.6
    arr[:, :, 2] = 82.0 + 14.0 * grad + fibers * 0.5

    bloom = np.exp(-((node_phase - 0.042) / 0.028) ** 2) * 0.48
    arr = arr * (1.0 - bloom[:, :, None]) + np.array([206.0, 218.0, 198.0])[None, None, :] * bloom[:, :, None]

    dark_ring = np.exp(-(dist_to_node / 0.010) ** 2) * 0.78
    arr = arr * (1.0 - dark_ring[:, :, None]) + np.array([38.0, 54.0, 42.0])[None, None, :] * dark_ring[:, :, None]

    img = Image.fromarray(np.clip(arr, 22, 235).astype(np.uint8), mode="RGB")
    path = OUT / "bamboo_culm.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.30)).save(path)
    return path


def _stage_bark_diffuse(src: Path, dst: Path, mul_rgb: tuple[float, float, float]) -> None:
    """Warm natural sunlit mountain bark (never pitch-black charcoal!)."""
    im = Image.open(src).convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    im = im.filter(ImageFilter.GaussianBlur(radius=0.45))
    arr = np.array(im, dtype=np.float32)
    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
    arr = lum[:, :, None] * 0.45 + arr * 0.55
    arr[:, :, 0] *= mul_rgb[0]
    arr[:, :, 1] *= mul_rgb[1]
    arr[:, :, 2] *= mul_rgb[2]
    Image.fromarray(np.clip(arr, 26, 205).astype(np.uint8), mode="RGB").save(dst, quality=90, optimize=True)


if __name__ == "__main__":
    dl_ph = ROOT / "downloads" / "slice-v061" / "polyhaven"
    slice_dir = ROOT / "game" / "assets" / "slice"
    slice_dir.mkdir(parents=True, exist_ok=True)
    staged = []
    if dl_ph.exists():
        bark_tones = {
            "japanese_camphor_bark": (0.58, 0.53, 0.46),
            "bark_willow": (0.60, 0.56, 0.48),
            "trident_maple_bark": (0.62, 0.55, 0.48),
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

    paths = [
        build_camphor_ink_dab(),
        build_camphor_bough(),
        build_willow_curtain(),
        build_maple_tallow_bough(),
        build_azalea_bough(),
        build_bamboo_spray(),
        build_bamboo_culm(),
    ]
    print("Generated Taiping-style Jiangnan botanical textures:", [p.name for p in paths], "staged bark:", staged)
