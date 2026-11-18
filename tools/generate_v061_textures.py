"""Generate v0.6.4 Jiangnan Qinglü (江南青绿水墨) Stylized Botanical Foliage & Bamboo Textures.

Artistic Direction ("不拼写实，做出江南青绿特色，彻底告别一坨绿与塑料感"):
- Bold clustered bouquet silhouettes (5-7 distinct leaf fans per bough with clean sky-gap negative space)
  so foliage reads crisply from 3m to 120m without mipmap mush;
- Built-in Qinglü mineral color-temperature contrast: Deep Ink-Jade / Qingdai (#183832) interior shadow
  -> Lush Malachite-Emerald (#2e6b4c) mid-canopy -> Warm Tea-Sprout Gold (#86bc5e) sunlit tips;
- Species color diversity across Yanshan:
  * camphor_bough.png      : Emerald-jade umbrella clusters + warm amber-coral spring shoots (香樟春梢)
  * willow_curtain.png     : Airy calligraphic weeping strands in celadon-chartreuse (柳浪缃绿)
  * maple_tallow_bough.png : Jiangnan Chinese Tallow & Trident Maple in teal-jade, golden ochre & cinnabar red (乌桕丹枫)
  * bamboo_spray.png       : Crisp ink-wash '个/介' calligraphic bamboo leaf fans (潇湘竹羽)
  * azalea_bough.png       : Deep jade foliage with vivid cinnabar-rose Rhododendron blossoms (映山红)
  * bamboo_culm.png        : Stylized celadon-jade internodes with powdery white bloom & dark ink nodes
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
    """Dilate valid RGB colors outward into alpha==0 pixels to eliminate mipmap halos."""
    arr = np.array(img, dtype=np.uint8)
    rgb = arr[:, :, :3].astype(np.float32)
    alpha = arr[:, :, 3]
    valid = alpha > 32
    if np.any(valid):
        mean_col = rgb[valid].mean(axis=0)
    else:
        mean_col = np.array([42.0, 84.0, 62.0], dtype=np.float32)

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


def _draw_painterly_leaf(
    draw: ImageDraw.ImageDraw,
    base_xy: tuple[float, float],
    angle_rad: float,
    length: float,
    width: float,
    fill_rgb: tuple[int, int, int],
    tip_rgb: tuple[int, int, int] | None = None,
    rim_rgb: tuple[int, int, int] | None = None,
    vein_rgb: tuple[int, int, int] | None = None,
    tip_taper: float = 1.38,
) -> None:
    """Draw a bold stylized brushstroke leaf with subtle ink-jade silhouette rim & sunlit half-blade."""
    bx, by = base_xy
    ca, sa = math.cos(angle_rad), math.sin(angle_rad)
    nx, ny = -sa, ca
    steps = 12
    pts = []
    for i in range(steps + 1):
        t = i / steps
        half_w = 0.5 * width * math.sin(math.pi * (t ** 0.74)) * ((1.0 - t * 0.25) ** (tip_taper - 1.0))
        pts.append((bx + ca * length * t + nx * half_w, by + sa * length * t + ny * half_w))
    for i in range(steps - 1, 0, -1):
        t = i / steps
        half_w = 0.5 * width * math.sin(math.pi * (t ** 0.74)) * ((1.0 - t * 0.25) ** (tip_taper - 1.0))
        pts.append((bx + ca * length * t - nx * half_w, by + sa * length * length * 0.0 + sa * length * t - ny * half_w))

    # Crisp subtle dark ink-jade outline so overlapping leaves keep painterly separation instead of blurring
    if rim_rgb is not None:
        draw.polygon(pts, fill=(*rim_rgb, 255))
        in_pts = []
        cx = bx + ca * length * 0.46
        cy = by + sa * length * 0.46
        for px, py in pts:
            in_pts.append((cx + (px - cx) * 0.90, cy + (py - cy) * 0.90))
        draw.polygon(in_pts, fill=(*fill_rgb, 255))
    else:
        draw.polygon(pts, fill=(*fill_rgb, 255))

    # Sunlit half-blade brushstroke wash
    hi_rgb = (
        min(255, int(fill_rgb[0] * 1.13 + 7)),
        min(255, int(fill_rgb[1] * 1.12 + 8)),
        min(255, int(fill_rgb[2] * 1.06 + 4)),
    )
    draw.polygon(pts[: steps + 1], fill=(*hi_rgb, 255))

    # Warm tip wash (for Qinglü sunlit tips or camphor coral flush)
    if tip_rgb is not None:
        tip_poly = []
        for i in range(5, steps + 1):
            tip_poly.append(pts[i])
        for i in range(steps + 1, len(pts) - 4):
            tip_poly.append(pts[i])
        if len(tip_poly) >= 3:
            draw.polygon(tip_poly, fill=(*tip_rgb, 235))

    if vein_rgb is not None:
        tip_x = bx + ca * length * 0.86
        tip_y = by + sa * length * 0.86
        draw.line([(bx + ca * length * 0.06, by + sa * length * 0.06), (tip_x, tip_y)], fill=(*vein_rgb, 235), width=max(2, int(width * 0.055)))


def _draw_stylized_trilobe(
    draw: ImageDraw.ImageDraw,
    base_xy: tuple[float, float],
    angle_rad: float,
    length: float,
    width: float,
    fill_rgb: tuple[int, int, int],
    tip_rgb: tuple[int, int, int],
    rim_rgb: tuple[int, int, int],
    vein_rgb: tuple[int, int, int],
) -> None:
    bx, by = base_xy
    fork = (bx + math.cos(angle_rad) * length * 0.16, by + math.sin(angle_rad) * length * 0.16)
    for sgn in (-1.0, 1.0):
        _draw_painterly_leaf(
            draw,
            fork,
            angle_rad + sgn * 0.64,
            length * 0.74,
            width * 0.44,
            fill_rgb,
            tip_rgb=tip_rgb,
            rim_rgb=rim_rgb,
            vein_rgb=vein_rgb,
            tip_taper=1.35,
        )
    _draw_painterly_leaf(
        draw,
        base_xy,
        angle_rad,
        length,
        width * 0.54,
        fill_rgb,
        tip_rgb=tip_rgb,
        rim_rgb=rim_rgb,
        vein_rgb=vein_rgb,
        tip_taper=1.32,
    )


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


def _draw_azalea_flower(
    draw: ImageDraw.ImageDraw,
    center_xy: tuple[float, float],
    radius: float,
    rot_rad: float,
    rng: random.Random,
) -> None:
    cx, cy = center_xy
    petal_base = (rng.randint(204, 232), rng.randint(52, 76), rng.randint(74, 98))
    petal_rim = (126, 26, 44)
    for k in range(5):
        a = rot_rad + k * (math.tau / 5.0) + rng.uniform(-0.07, 0.07)
        ca, sa = math.cos(a), math.sin(a)
        nx, ny = -sa, ca
        pts = [(cx, cy)]
        for s in range(1, 9):
            t = s / 8.0
            hw = radius * 0.52 * math.sin(math.pi * (t ** 0.68))
            pts.append((cx + ca * radius * t + nx * hw, cy + sa * radius * t + ny * hw))
        for s in range(7, 0, -1):
            t = s / 8.0
            hw = radius * 0.52 * math.sin(math.pi * (t ** 0.68))
            pts.append((cx + ca * radius * t - nx * hw, cy + sa * radius * t - ny * hw))
        p_col = (
            min(255, petal_base[0] + rng.randint(-8, 8)),
            min(255, petal_base[1] + rng.randint(-6, 8)),
            min(255, petal_base[2] + rng.randint(-6, 8)),
        )
        draw.polygon(pts, fill=(*p_col, 255), outline=(*petal_rim, 255))
    r_in = radius * 0.25
    draw.ellipse((cx - r_in, cy - r_in, cx + r_in, cy + r_in), fill=(152, 24, 46, 255))
    for st in range(5):
        sa_ang = rot_rad + (st - 2.0) * 0.36
        sx = cx + math.cos(sa_ang) * radius * 0.50
        sy = cy + math.sin(sa_ang) * radius * 0.50
        draw.line([(cx, cy), (sx, sy)], fill=(246, 196, 176, 255), width=2)
        draw.ellipse((sx - 3.5, sy - 3.5, sx + 3.5, sy + 3.5), fill=(252, 222, 118, 255))


def build_camphor_bough() -> Path:
    """Jiangnan Qinglü Camphor (香樟): 6 bold cloud-fan bouquets with ink-jade core & spring tea-gold/amber tips."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6401)

    bark_ink = (52, 42, 36)
    branches = [
        [(512, 998), (508, 810), (504, 575), (512, 310)],
        [(509, 855), (345, 710), (225, 555)],
        [(509, 845), (675, 700), (795, 545)],
        [(505, 610), (335, 445), (235, 295)],
        [(505, 600), (680, 435), (780, 290)],
    ]
    for idx, br in enumerate(branches):
        _draw_twig(draw, br, 18 if idx == 0 else 12, 5, bark_ink)

    # 6 distinct, well-spaced cloud-fan bouquets leaving airy sky gaps between clusters!
    bouquets = [
        (512, 765, -math.pi * 0.5, 1.02, False),   # Basal center cushion
        (255, 585, -math.pi * 0.72, 0.98, False),  # Lower-left fan
        (770, 575, -math.pi * 0.28, 0.98, False),  # Lower-right fan
        (260, 320, -math.pi * 0.66, 1.04, True),   # Upper-left sunlit fan
        (762, 315, -math.pi * 0.34, 1.04, True),   # Upper-right sunlit fan
        (512, 245, -math.pi * 0.50, 1.10, True),   # Apex crown fan
    ]

    rim_ink = (20, 46, 40)
    for bx, by, center_ang, sc, is_upper in bouquets:
        # Layer 1: Deep Qingdai Ink-Jade backing fan (cool teal-emerald shadow core)
        for fi in range(5):
            a = center_ang + (fi - 2.0) * 0.44 + rng.uniform(-0.06, 0.06)
            L = rng.uniform(185, 220) * sc
            W = L * 0.54
            col = (rng.randint(24, 34), rng.randint(58, 76), rng.randint(50, 64))
            _draw_painterly_leaf(draw, (bx, by + 26), a, L, W, col, rim_rgb=(16, 36, 32))

        # Layer 2: Mid Malachite-Jade fan (rich Jiangnan camphor green)
        for fi in range(5):
            a = center_ang + (fi - 2.0) * 0.38 + rng.uniform(-0.05, 0.05)
            ox = bx + math.cos(a) * 24
            oy = by + math.sin(a) * 24
            L = rng.uniform(165, 198) * sc
            W = L * 0.50
            col = (rng.randint(42, 58), rng.randint(96, 122), rng.randint(64, 80))
            tip_c = (rng.randint(76, 98), rng.randint(138, 162), rng.randint(72, 86))
            _draw_painterly_leaf(draw, (ox, oy), a, L, W, col, tip_rgb=tip_c, rim_rgb=rim_ink, vein_rgb=(98, 152, 84))

        # Layer 3: Sunlit Spring-Tea Gold & authentic Camphor Amber-Coral young shoots at crown tips
        n_top = 4 if is_upper else 3
        for fi in range(n_top):
            a = center_ang + (fi - (n_top - 1) * 0.5) * 0.36 + rng.uniform(-0.04, 0.04)
            ox = bx + math.cos(a) * 52
            oy = by + math.sin(a) * 52 - 10
            L = rng.uniform(135, 162) * sc
            W = L * 0.48
            if is_upper and fi in (0, n_top - 1) and rng.random() < 0.55:
                # Subtle warm bronze-coral camphor spring flush leaf!
                col = (rng.randint(128, 152), rng.randint(124, 144), rng.randint(58, 70))
                tip_c = (rng.randint(176, 198), rng.randint(118, 138), rng.randint(64, 76))
                vein_c = (196, 158, 86)
            else:
                col = (rng.randint(78, 102), rng.randint(136, 162), rng.randint(66, 80))
                tip_c = (rng.randint(118, 142), rng.randint(172, 194), rng.randint(78, 92))
                vein_c = (146, 192, 98)
            _draw_painterly_leaf(draw, (ox, oy), a, L, W, col, tip_rgb=tip_c, rim_rgb=(28, 62, 48), vein_rgb=vein_c)

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "camphor_bough.png"
    out_img.save(path)
    return path


def build_willow_curtain() -> Path:
    """Calligraphic Jiangnan Weeping Willow (垂柳): 9 airy silk-brush strands in celadon & chartreuse."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6402)

    # Top leafy arch crown (airy clusters, never a solid bar)
    for ci in range(6):
        cx = 120 + (ci / 5.0) * (sz - 240)
        cy = 96 - 28 * math.sin(math.pi * (ci / 5.0))
        for k in range(4):
            ang = math.pi * 0.5 + (k - 1.5) * 0.52
            L = rng.uniform(118, 148)
            col = (rng.randint(62, 84), rng.randint(118, 146), rng.randint(62, 76))
            tip_c = (rng.randint(108, 132), rng.randint(164, 188), rng.randint(78, 92))
            _draw_painterly_leaf(draw, (cx, cy), ang, L, L * 0.28, col, tip_rgb=tip_c, rim_rgb=(28, 60, 48), tip_taper=1.55)

    # 9 well-separated graceful weeping whips so sky & water shimmer cleanly between strands!
    n_whips = 9
    for wi in range(n_whips):
        u = (wi + 0.5) / n_whips
        start_x = 86 + u * (sz - 172) + rng.uniform(-10, 10)
        start_y = 92 - 26 * math.sin(math.pi * u)
        end_y = rng.uniform(820, 985) if (wi % 2 == 0) else rng.uniform(700, 865)
        sway_amp = rng.uniform(16, 30)
        sway_phase = rng.uniform(0, math.tau)
        whip_pts = []
        steps = 16
        for s in range(steps + 1):
            t = s / steps
            wx = start_x + sway_amp * math.sin(t * 3.0 + sway_phase) * t
            wy = start_y + (end_y - start_y) * t
            whip_pts.append((wx, wy))
        _draw_twig(draw, whip_pts, 5, 2, (88, 118, 56))

        is_foreground_whip = (wi % 2 == 0)
        n_leaves = 14
        for li in range(n_leaves):
            lt = (li + 0.25) / n_leaves
            idx_f = lt * steps
            i0 = min(steps - 1, int(idx_f))
            frac = idx_f - i0
            px = whip_pts[i0][0] * (1.0 - frac) + whip_pts[i0 + 1][0] * frac
            py = whip_pts[i0][1] * (1.0 - frac) + whip_pts[i0 + 1][1] * frac
            tang = math.atan2(whip_pts[i0 + 1][1] - whip_pts[i0][1], whip_pts[i0 + 1][0] - whip_pts[i0][0])
            side = -1.0 if (li % 2 == 0) else 1.0
            ang = tang + side * rng.uniform(0.28, 0.52)
            L = rng.uniform(118, 152) * (1.0 - 0.18 * lt)
            W = L * 0.25
            if is_foreground_whip:
                col = (rng.randint(78, 102), rng.randint(138, 166), rng.randint(64, 78))
                tip_c = (rng.randint(124, 148), rng.randint(178, 202), rng.randint(82, 96))
                vein_c = (148, 196, 98)
            else:
                col = (rng.randint(42, 62), rng.randint(96, 122), rng.randint(58, 72))
                tip_c = (rng.randint(76, 98), rng.randint(136, 158), rng.randint(68, 82))
                vein_c = (98, 152, 82)
            _draw_painterly_leaf(draw, (px, py), ang, L, W, col, tip_rgb=tip_c, rim_rgb=(24, 54, 44), vein_rgb=vein_c, tip_taper=1.62)

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "willow_curtain.png"
    out_img.save(path)
    return path


def build_maple_tallow_bough() -> Path:
    """Jiangnan Chinese Tallow & Trident Maple (乌桕丹枫): Teal-jade base + golden-ochre & cinnabar-red crown!"""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6403)

    branches = [
        [(512, 998), (514, 800), (504, 565), (512, 295)],
        [(512, 845), (345, 695), (225, 535)],
        [(512, 835), (678, 690), (798, 530)],
        [(506, 595), (338, 430), (242, 285)],
        [(506, 585), (678, 425), (776, 280)],
    ]
    for idx, br in enumerate(branches):
        _draw_twig(draw, br, 17 if idx == 0 else 11, 4, (58, 44, 38))

    bouquets = [
        (512, 760, -math.pi * 0.50, 0.98, "jade_gold"),
        (250, 560, -math.pi * 0.72, 0.96, "ochre"),
        (775, 555, -math.pi * 0.28, 0.96, "jade_gold"),
        (262, 310, -math.pi * 0.65, 1.04, "crimson"),
        (760, 305, -math.pi * 0.35, 1.04, "ochre"),
        (512, 235, -math.pi * 0.50, 1.08, "crimson"),
    ]

    for bx, by, c_ang, sc, tone in bouquets:
        # Deep cool teal-umber shadow backing leaves (keeps Qinglü harmony!)
        for fi in range(4):
            a = c_ang + (fi - 1.5) * 0.48 + rng.uniform(-0.06, 0.06)
            L = rng.uniform(170, 205) * sc
            col = (rng.randint(36, 52), rng.randint(62, 80), rng.randint(48, 60))
            _draw_stylized_trilobe(draw, (bx, by + 22), a, L, L * 0.88, col, (58, 88, 58), (20, 38, 34), (72, 102, 64))

        # Mid & Upper Warm Jiangnan Autumn Tallow/Maple Bouquets
        for fi in range(5):
            a = c_ang + (fi - 2.0) * 0.38 + rng.uniform(-0.05, 0.05)
            ox = bx + math.cos(a) * 34
            oy = by + math.sin(a) * 34 - 8
            L = rng.uniform(145, 178) * sc
            if tone == "crimson":
                col = (rng.randint(168, 196), rng.randint(72, 94), rng.randint(52, 66))
                tip_c = (rng.randint(208, 232), rng.randint(106, 132), rng.randint(64, 78))
                rim_c = (68, 30, 28)
                vein_c = (228, 148, 86)
            elif tone == "ochre":
                col = (rng.randint(172, 198), rng.randint(128, 152), rng.randint(54, 68))
                tip_c = (rng.randint(214, 236), rng.randint(168, 192), rng.randint(74, 90))
                rim_c = (62, 46, 28)
                vein_c = (234, 198, 104)
            else:
                col = (rng.randint(76, 104), rng.randint(124, 148), rng.randint(58, 72))
                tip_c = (rng.randint(164, 190), rng.randint(146, 168), rng.randint(66, 80))
                rim_c = (28, 54, 42)
                vein_c = (186, 176, 88)
            _draw_stylized_trilobe(draw, (ox, oy), a, L, L * 0.86, col, tip_c, rim_c, vein_c)

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "maple_tallow_bough.png"
    out_img.save(path)
    return path


def build_azalea_bough() -> Path:
    """Stylized Jiangnan Mountain Azalea (映山红): Deep ink-emerald bouquets + vivid cinnabar blossoms."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6406)

    branches = [
        [(512, 998), (508, 805), (504, 580), (512, 330)],
        [(508, 860), (345, 710), (225, 545)],
        [(508, 850), (675, 705), (795, 540)],
        [(506, 615), (345, 455), (248, 315)],
        [(506, 605), (675, 450), (772, 310)],
    ]
    for idx, br in enumerate(branches):
        _draw_twig(draw, br, 16 if idx == 0 else 11, 4, (62, 46, 38))

    bouquets = [
        (512, 760, -math.pi * 0.50),
        (248, 565, -math.pi * 0.72),
        (775, 560, -math.pi * 0.28),
        (262, 335, -math.pi * 0.64),
        (760, 330, -math.pi * 0.36),
        (512, 270, -math.pi * 0.50),
    ]
    for bx, by, c_ang in bouquets:
        for fi in range(5):
            a = c_ang + (fi - 2.0) * 0.42 + rng.uniform(-0.05, 0.05)
            L = rng.uniform(145, 178)
            col = (rng.randint(32, 48), rng.randint(78, 104), rng.randint(54, 68))
            tip_c = (rng.randint(62, 84), rng.randint(122, 146), rng.randint(66, 80))
            _draw_painterly_leaf(draw, (bx, by), a, L, L * 0.50, col, tip_rgb=tip_c, rim_rgb=(18, 42, 36), vein_rgb=(88, 142, 76))

        # Vivid Cinnabar-Rose blossom cluster crowning each bouquet
        for fx_off, fy_off, fr in ((-32, -32, 54), (32, -28, 52), (0, -64, 58)):
            _draw_azalea_flower(draw, (bx + fx_off, by + fy_off), fr, rng.uniform(0, math.tau), rng)

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "azalea_bough.png"
    out_img.save(path)
    return path


def build_bamboo_spray() -> Path:
    """Calligraphic Ink-Wash Moso Bamboo (潇湘翠竹) '个/介' leaf fans with razor-sharp silhouettes."""
    sz = 1024
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    rng = random.Random(6404)

    stems = [
        [(512, 995), (508, 760), (502, 505), (512, 255)],
        [(509, 815), (345, 635), (225, 455)],
        [(509, 800), (675, 625), (795, 445)],
        [(504, 565), (350, 395), (255, 245)],
        [(504, 555), (665, 390), (765, 240)],
    ]
    for st in stems:
        _draw_twig(draw, st, 10, 3, (66, 104, 56))

    # Crisp 4-blade '介' calligraphic fans at stem nodes (clean gaps, zero noisy overlap)
    fan_nodes = [
        (235, 465, -math.pi * 0.72, False),
        (785, 455, -math.pi * 0.28, False),
        (505, 585, -math.pi * 0.50, False),
        (262, 255, -math.pi * 0.65, True),
        (758, 250, -math.pi * 0.35, True),
        (512, 245, -math.pi * 0.50, True),
    ]
    for nx, ny, base_ang, is_sun in fan_nodes:
        # 2 shaded jade-ink backing blades
        for sgn in (-0.52, 0.52):
            L = rng.uniform(235, 275)
            col = (rng.randint(28, 42), rng.randint(72, 94), rng.randint(54, 68))
            _draw_painterly_leaf(draw, (nx, ny + 12), base_ang + sgn, L, L * 0.17, col, rim_rgb=(16, 40, 34), tip_taper=1.72)

        # 4 foreground calligraphic '介' blades
        for fi in range(4):
            fa = base_ang + (fi - 1.5) * 0.44 + rng.uniform(-0.04, 0.04)
            L = rng.uniform(225, 285)
            W = L * 0.175
            if is_sun:
                col = (rng.randint(66, 88), rng.randint(132, 158), rng.randint(68, 82))
                tip_c = (rng.randint(112, 138), rng.randint(174, 198), rng.randint(82, 96))
                vein_c = (142, 196, 102)
            else:
                col = (rng.randint(46, 66), rng.randint(106, 132), rng.randint(62, 76))
                tip_c = (rng.randint(84, 108), rng.randint(148, 172), rng.randint(74, 88))
                vein_c = (112, 168, 90)
            _draw_painterly_leaf(draw, (nx, ny), fa, L, W, col, tip_rgb=tip_c, rim_rgb=(20, 48, 40), vein_rgb=vein_c, tip_taper=1.75)

    out_img = _bleed_rgb_into_alpha(img, iterations=24)
    path = OUT / "bamboo_spray.png"
    out_img.save(path)
    return path


def build_bamboo_culm() -> Path:
    """Stylized Qinglü celadon-jade Moso bamboo culm with powdery node bloom & crisp ink rings."""
    w, h = 512, 1024
    rng = np.random.default_rng(6405)
    yy, xx = np.meshgrid(np.linspace(0.0, 1.0, h, endpoint=False), np.linspace(0.0, 1.0, w, endpoint=False), indexing="ij")

    fibers = 3.2 * np.sin(xx * math.tau * 28.0) + rng.normal(0.0, 1.4, size=(h, w))
    node_phase = (yy * 4.0) % 1.0
    dist_to_node = np.minimum(node_phase, 1.0 - node_phase)

    # Subtle vertical celadon-to-warm-jade gradient within each internode
    grad = node_phase
    arr = np.zeros((h, w, 3), dtype=np.float32)
    arr[:, :, 0] = 68.0 + 22.0 * grad + fibers * 0.6
    arr[:, :, 1] = 116.0 + 24.0 * grad + fibers * 0.8
    arr[:, :, 2] = 74.0 + 10.0 * grad + fibers * 0.5

    # Powdery white-jade waxy bloom right below each node ring (竹节白霜)
    bloom = np.exp(-((node_phase - 0.045) / 0.030) ** 2) * 0.42
    arr = arr * (1.0 - bloom[:, :, None]) + np.array([182.0, 204.0, 180.0])[None, None, :] * bloom[:, :, None]

    # Crisp dark ink-green nodal line + warm highlight lip
    dark_ring = np.exp(-(dist_to_node / 0.010) ** 2) * 0.76
    arr = arr * (1.0 - dark_ring[:, :, None]) + np.array([26.0, 48.0, 36.0])[None, None, :] * dark_ring[:, :, None]

    ridge = np.exp(-((node_phase - 0.982) / 0.009) ** 2) * 0.40
    arr = arr * (1.0 - ridge[:, :, None]) + np.array([148.0, 176.0, 116.0])[None, None, :] * ridge[:, :, None]

    img = Image.fromarray(np.clip(arr, 16, 236).astype(np.uint8), mode="RGB")
    path = OUT / "bamboo_culm.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.30)).save(path)
    return path


def _stage_bark_diffuse(src: Path, dst: Path, mul_rgb: tuple[float, float, float]) -> None:
    """Soften high-frequency bark noise slightly and tint toward warm-cool Qinglü mountain bark."""
    im = Image.open(src).convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)
    im = im.filter(ImageFilter.GaussianBlur(radius=0.45))
    arr = np.array(im, dtype=np.float32)
    arr[:, :, 0] *= mul_rgb[0]
    arr[:, :, 1] *= mul_rgb[1]
    arr[:, :, 2] *= mul_rgb[2]
    Image.fromarray(np.clip(arr, 16, 230).astype(np.uint8), mode="RGB").save(dst, quality=90, optimize=True)


if __name__ == "__main__":
    dl_ph = ROOT / "downloads" / "slice-v061" / "polyhaven"
    slice_dir = ROOT / "game" / "assets" / "slice"
    slice_dir.mkdir(parents=True, exist_ok=True)
    staged = []
    if dl_ph.exists():
        bark_tones = {
            "japanese_camphor_bark": (0.52, 0.50, 0.48),
            "bark_willow": (0.60, 0.60, 0.56),
            "trident_maple_bark": (0.58, 0.54, 0.52),
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
    print("Generated v0.6.4 Qinglu botanical textures:", [p.name for p in paths], "staged PBR:", staged)
