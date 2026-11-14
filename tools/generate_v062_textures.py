"""Generate weathered Jiangnan karst limestone, cliff inscriptions, and ancient mineral cave mural textures for v0.6.2.

Outputs into tools/generated_v062/ (embedded into game/assets/slice/v062_bamboo_cave.glb by build_v062_assets.py):
- limestone_karst.png          : seamless stratified grey-olive Jiangnan karst rock with calcite veins & moss
- plaque_bamboo_maze.png       : carved bluestone archway lintel reading "迷 踪 竹 石 阵"
- plaque_yanxia_cave.png       : deep-cut cliff lintel reading "烟 霞 古 洞" filled with aged cinnabar pigment
- stele_cliff_carving.png      : cliffside Moya carving ("摩崖石刻 · 竹石清音") with vertical couplets
- mural_yanxia_ancients.png    : weathered cinnabar/malachite/azurite/ochre cave mural ("烟山先民耕读图")
- inscription_cave_chronicle.png: carved East Gallery chronicle ("烟 霞 古 洞 志") telling Yanshan's history
"""
from __future__ import annotations

import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "generated_v062"
OUT.mkdir(parents=True, exist_ok=True)


def _pick_font(names: list[str], size: int) -> ImageFont.FreeTypeFont:
    font_dirs = [Path("C:/Windows/Fonts"), Path("/usr/share/fonts")]
    for d in font_dirs:
        if not d.exists():
            continue
        for name in names:
            p = d / name
            if p.exists():
                return ImageFont.truetype(str(p), size=size)
    return ImageFont.load_default()


def _draw_centered_text(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int] | tuple[int, int, int, int],
) -> None:
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = center[0] - tw * 0.5 - bbox[0]
    y = center[1] - th * 0.5 - bbox[1]
    draw.text((x, y), text, font=font, fill=fill)


def _tileable_fbm(w: int, h: int, seed: int, octaves: tuple[int, ...] = (4, 8, 16, 32, 64)) -> np.ndarray:
    """Generate smooth, organic multi-octave tileable rock noise in [-1, 1]."""
    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    for freq in octaves:
        grid = rng.uniform(-1.0, 1.0, size=(freq, freq)).astype(np.float32)
        # Tile 1 extra row/col so bilinear resize wraps seamlessly
        padded = np.pad(grid, ((0, 1), (0, 1)), mode="wrap")
        layer_img = Image.fromarray(((padded * 0.5 + 0.5) * 255.0).astype(np.uint8), mode="L")
        up = np.asarray(layer_img.resize((w, h), resample=Image.Resampling.BICUBIC), dtype=np.float32) / 127.5 - 1.0
        acc += up * amp
        norm += amp
        amp *= 0.52
    return acc / max(norm, 1e-5)


def _karst_canvas(
    w: int,
    h: int,
    seed: int,
    base_rgb: tuple[int, int, int],
    moss_strength: float = 0.42,
) -> Image.Image:
    rng = np.random.default_rng(seed)
    yy, _xx = np.meshgrid(np.linspace(0, 1, h), np.linspace(0, 1, w), indexing="ij")
    n1 = _tileable_fbm(w, h, seed + 11, (3, 7, 15, 31, 63))
    n2 = _tileable_fbm(w, h, seed + 29, (5, 11, 23, 47))
    strata = 8.5 * np.sin((yy * 6.0 + n1 * 0.42) * 2.0 * math.pi)
    fine_grain = rng.normal(0.0, 4.5, size=(h, w))

    # Organic mineral veins & weathered karst pits from ridged multifractal noise
    vein = np.clip(1.0 - np.abs(n1 + 0.35 * n2) / 0.045, 0.0, 1.0) * 18.0
    fissure = np.clip(1.0 - np.abs(n2 - 0.25 * n1) / 0.038, 0.0, 1.0) * 22.0

    delta = (n1 * 15.0 + strata + fine_grain + vein - fissure)[:, :, None]
    arr = np.zeros((h, w, 3), dtype=np.float32)
    arr[:, :, 0] = base_rgb[0]
    arr[:, :, 1] = base_rgb[1]
    arr[:, :, 2] = base_rgb[2]
    arr = np.clip(arr + delta, 18, 238)

    # Organic damp Jiangnan olive-emerald moss patches
    moss_patch = np.clip(n2 * 0.85 + 0.35, 0.0, 1.0)
    moss_bias = np.clip((yy - 0.50) / 0.50, 0.0, 1.0) * 0.65 + 0.35
    moss_t = np.clip(moss_patch * moss_bias * moss_strength, 0.0, 0.62)[:, :, None]
    moss_col = np.array([52, 76, 46], dtype=np.float32)
    arr = arr * (1.0 - moss_t) + moss_col * moss_t
    return Image.fromarray(arr.astype(np.uint8), mode="RGB")


def _draw_rock_fissures(draw: ImageDraw.ImageDraw, w: int, h: int, seed: int, count: int = 9) -> None:
    rng = np.random.default_rng(seed)
    for _ in range(count):
        x = float(rng.uniform(0, w))
        y = float(rng.uniform(0, h * 0.35)) if rng.random() < 0.6 else float(rng.uniform(0, h))
        ang = float(rng.uniform(0.7, 2.4))
        pts = [(x, y)]
        steps = int(rng.integers(7, 15))
        for _s in range(steps):
            ang += float(rng.uniform(-0.42, 0.42))
            step_len = float(rng.uniform(16.0, 34.0))
            x += math.cos(ang) * step_len
            y += math.sin(ang) * step_len
            pts.append((x, y))
        draw.line(pts, fill=(62, 56, 48), width=2)
        shifted = [(px + 1.2, py + 1.0) for px, py in pts]
        draw.line(shifted, fill=(214, 204, 180), width=1)


def build_limestone_karst() -> Path:
    img = _karst_canvas(512, 512, 6201, (104, 109, 101), moss_strength=0.38)
    path = OUT / "limestone_karst.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.40)).save(path)
    return path


def build_bamboo_maze_plaque() -> Path:
    w, h = 768, 256
    img = _karst_canvas(w, h, 6202, (64, 72, 66), moss_strength=0.34)
    draw = ImageDraw.Draw(img)

    draw.rectangle([10, 10, w - 11, h - 11], outline=(34, 40, 36), width=6)
    draw.rectangle([22, 22, w - 23, h - 23], outline=(144, 158, 142), width=2)
    for cx, cy in [(32, 32), (w - 48, 32), (32, h - 48), (w - 48, h - 48)]:
        draw.rectangle([cx, cy, cx + 16, cy + 16], outline=(136, 150, 134), width=2)

    f_title = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf", "simhei.ttf"], 76)
    f_sub = _pick_font(["STKAITI.TTF", "simkai.ttf", "simhei.ttf"], 25)
    f_seal = _pick_font(["STKAITI.TTF", "simkai.ttf", "simhei.ttf"], 22)

    _draw_centered_text(draw, (w * 0.46 + 3, h * 0.43 + 3), "迷 踪 竹 石 阵", f_title, (20, 26, 22))
    _draw_centered_text(draw, (w * 0.46, h * 0.43), "迷 踪 竹 石 阵", f_title, (230, 238, 214))
    _draw_centered_text(draw, (w * 0.46, h * 0.78), "奇石瘦透 · 翠篁幽径 · 北通烟霞古洞", f_sub, (188, 206, 180))

    draw.rectangle([682, 68, 720, 142], fill=(154, 42, 34), outline=(198, 86, 68), width=2)
    _draw_centered_text(draw, (701, 88), "烟", f_seal, (244, 226, 194))
    _draw_centered_text(draw, (701, 118), "山", f_seal, (244, 226, 194))

    path = OUT / "plaque_bamboo_maze.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


def build_yanxia_cave_plaque() -> Path:
    w, h = 768, 256
    img = _karst_canvas(w, h, 6203, (78, 82, 75), moss_strength=0.42)
    draw = ImageDraw.Draw(img)

    draw.rectangle([12, 12, w - 13, h - 13], outline=(38, 42, 36), width=7)
    draw.rectangle([24, 24, w - 25, h - 25], outline=(124, 128, 116), width=2)

    f_title = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf", "simhei.ttf"], 104)
    f_side = _pick_font(["STKAITI.TTF", "simkai.ttf", "simhei.ttf"], 25)
    f_seal = _pick_font(["STKAITI.TTF", "simkai.ttf"], 24)

    _draw_centered_text(draw, (w * 0.50 + 4, h * 0.48 + 4), "烟 霞 古 洞", f_title, (26, 20, 18))
    _draw_centered_text(draw, (w * 0.50 - 1, h * 0.48 - 1), "烟 霞 古 洞", f_title, (220, 106, 78))
    _draw_centered_text(draw, (w * 0.50, h * 0.48), "烟 霞 古 洞", f_title, (196, 62, 44))

    for i, ch in enumerate("诚庄古迹"):
        _draw_centered_text(draw, (714, 54 + i * 36), ch, f_side, (224, 216, 190))
    for i, ch in enumerate("丹青寒潭"):
        _draw_centered_text(draw, (54, 54 + i * 36), ch, f_side, (224, 216, 190))

    draw.rectangle([688, 196, 736, 228], fill=(152, 42, 34), outline=(198, 86, 68), width=2)
    _draw_centered_text(draw, (712, 212), "古迹", f_seal, (244, 226, 192))

    path = OUT / "plaque_yanxia_cave.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


def build_cliff_carving_stele() -> Path:
    w, h = 512, 768
    img = _karst_canvas(w, h, 6204, (84, 90, 82), moss_strength=0.42)
    draw = ImageDraw.Draw(img)

    draw.rectangle([20, 20, w - 21, h - 21], outline=(40, 46, 40), width=6)
    draw.rectangle([34, 34, w - 35, h - 35], outline=(142, 148, 136), width=2)
    draw.line([(58, 158), (w - 58, 158)], fill=(46, 52, 46), width=4)

    f_head = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 64)
    f_verse = _pick_font(["STKAITI.TTF", "simkai.ttf", "simfang.ttf"], 42)
    f_sub = _pick_font(["STKAITI.TTF", "simkai.ttf"], 26)

    _draw_centered_text(draw, (w * 0.5 + 3, 96 + 3), "竹 石 清 音", f_head, (26, 22, 20))
    _draw_centered_text(draw, (w * 0.5, 96), "竹 石 清 音", f_head, (200, 68, 48))

    columns = ["清泉洗凡心", "曲径通幽洞", "翠篁引风吟", "瘦石穿云立"]
    xs = [106, 204, 308, 406]
    for cx, line_txt in zip(xs, columns):
        for idx, ch in enumerate(line_txt):
            cy = 224 + idx * 82
            _draw_centered_text(draw, (cx + 2, cy + 2), ch, f_verse, (26, 30, 26))
            _draw_centered_text(draw, (cx, cy), ch, f_verse, (236, 232, 208))

    draw.line([(68, 636), (w - 68, 636)], fill=(58, 66, 58), width=2)
    _draw_centered_text(draw, (w * 0.5, 684), "烟山摩崖石刻 · 按 F 拓读寻踪", f_sub, (224, 218, 184))

    path = OUT / "stele_cliff_carving.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


def build_mural_yanxia_ancients() -> Path:
    """Paint an authentic Tang/Song blue-green mineral cave mural ('烟山先民耕读图') on weathered limestone."""
    w, h = 1024, 512
    rng = np.random.default_rng(6205)
    yy, xx = np.meshgrid(np.linspace(0, 1, h), np.linspace(0, 1, w), indexing="ij")
    n_lime = _tileable_fbm(w, h, 6255, (4, 8, 16, 32, 64))
    n_fine = _tileable_fbm(w, h, 6277, (9, 19, 39))

    # 1) Warm mineral lime-plaster ground over cave stone
    base = np.zeros((h, w, 3), dtype=np.float32)
    mott = n_lime * 18.0 + n_fine * 8.0 + rng.normal(0.0, 3.8, size=(h, w))
    base[:, :, 0] = 204 + mott * 0.95
    base[:, :, 1] = 190 + mott * 0.88
    base[:, :, 2] = 156 + mott * 0.78
    img = Image.fromarray(np.clip(base, 24, 244).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img, "RGBA")

    # 2) Layered Blue-Green Mountain Peaks ("石青远峰 & 石绿奇峰") with ink-contour brushwork
    far_peaks = [
        (40, 286), (140, 188), (225, 134), (318, 192), (420, 122),
        (528, 178), (620, 146), (736, 206), (856, 136), (984, 232), (984, 340), (40, 340),
    ]
    draw.polygon(far_peaks, fill=(52, 92, 124, 185))
    draw.line(far_peaks[:-2], fill=(38, 52, 62, 220), width=3)

    mid_peaks = [
        (40, 330), (156, 236), (258, 196), (354, 266), (470, 214),
        (586, 268), (712, 208), (828, 244), (984, 312), (984, 410), (40, 410),
    ]
    draw.polygon(mid_peaks, fill=(58, 128, 96, 195))
    draw.line(mid_peaks[:-2], fill=(36, 56, 44, 225), width=4)
    # Traditional vertical/diagonal "皴法" rock texture strokes on the peaks
    for px, py in [(225, 152), (258, 216), (420, 144), (470, 232), (712, 228), (856, 160)]:
        for k in range(-2, 3):
            draw.line([(px + k * 12, py), (px + k * 14 - 8, py + 44)], fill=(38, 62, 52, 135), width=2)

    # Drifting mineral mist & cloud scrolls across mid-valley (softly blurred ink-wash mist)
    mist_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mdraw = ImageDraw.Draw(mist_layer, "RGBA")
    for cx, cy, rx, ry in [(260, 276, 165, 28), (535, 258, 200, 30), (760, 270, 145, 26), (410, 188, 125, 20)]:
        mdraw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(228, 218, 192, 185))
    mist_layer = mist_layer.filter(ImageFilter.GaussianBlur(radius=11.0))
    img = Image.alpha_composite(img.convert("RGBA"), mist_layer).convert("RGB")
    draw = ImageDraw.Draw(img, "RGBA")

    # Warm ochre & sage paddy-terrace foreground ("诚庄稻畴")
    draw.polygon([(40, 338), (560, 326), (984, 352), (984, 474), (40, 474)], fill=(186, 154, 96, 150))

    # Cinnabar morning sun ("朱砂朝日")
    draw.ellipse([634, 72, 706, 144], fill=(188, 66, 46, 235), outline=(138, 44, 32, 220), width=2)

    # Smooth S-curve jade mountain creek flowing down through a single-arch stone bridge
    creek_left = []
    creek_right = []
    for i in range(36):
        t = i / 35.0
        cy = 212.0 + t * 256.0
        cx = 478.0 + math.sin(t * 5.2) * 34.0 + t * 24.0
        half_w = 5.5 + t * 13.5
        creek_left.append((cx - half_w, cy))
        creek_right.append((cx + half_w, cy))
    draw.polygon(creek_left + list(reversed(creek_right)), fill=(76, 142, 156, 220))
    creek_mid = [((a[0] + b[0]) * 0.5, a[1]) for a, b in zip(creek_left, creek_right)]
    draw.line(creek_mid, fill=(214, 230, 222, 185), width=3)

    # Single-arch bluestone bridge across the painted creek
    bx, by = 486, 356
    draw.polygon([(bx - 42, by + 6), (bx - 24, by - 10), (bx + 24, by - 10), (bx + 42, by + 6)], fill=(86, 82, 74, 245), outline=(44, 40, 36, 255))
    draw.pieslice([bx - 20, by - 4, bx + 20, by + 22], start=180, end=360, fill=(52, 108, 122, 245))

    # Curved paddy dikes & rice shoots on lower-left valley
    for ty in (362, 398, 434):
        pts = [(132, ty + 8), (228, ty - 5), (336, ty + 6), (446, ty - 4)]
        draw.line(pts, fill=(92, 72, 48, 215), width=3)
        for rx in range(156, 436, 24):
            draw.line([(rx, ty - 2), (rx - 3, ty - 11)], fill=(68, 122, 74, 195), width=2)
            draw.line([(rx, ty - 2), (rx + 4, ty - 11)], fill=(68, 122, 74, 195), width=2)

    # Flying-eave cliff pavilion ("古望稻亭") on upper-left malachite crag
    px, py = 258, 194
    draw.polygon([(px - 48, py + 2), (px - 22, py - 8), (px, py - 24), (px + 22, py - 8), (px + 48, py + 2)], fill=(172, 62, 44, 240), outline=(48, 34, 28, 255))
    draw.line([(px - 52, py + 2), (px - 38, py - 5)], fill=(48, 34, 28, 255), width=3)
    draw.line([(px + 52, py + 2), (px + 38, py - 5)], fill=(48, 34, 28, 255), width=3)
    for sx in (-24, 24):
        draw.line([(px + sx, py + 2), (px + sx, py + 34)], fill=(82, 44, 34, 245), width=4)
    draw.rectangle([px - 34, py + 34, px + 34, py + 41], fill=(78, 76, 68, 245))

    # Right-side depiction of «烟霞古洞» limestone grotto with stalactites, glowing oil lamp & reading ancestors!
    gx, gy = 786, 356
    crag_poly = [
        (gx - 118, gy + 64), (gx - 104, gy - 42), (gx - 66, gy - 98),
        (gx + 4, gy - 114), (gx + 76, gy - 92), (gx + 108, gy - 34), (gx + 116, gy + 64),
    ]
    draw.polygon(crag_poly, fill=(78, 86, 76, 238), outline=(42, 46, 40, 255))
    draw.pieslice([gx - 78, gy - 78, gx + 78, gy + 68], start=180, end=360, fill=(38, 44, 42, 248))
    # Tiny stalactites hanging inside painted cave arch
    for sx, slen in [(-42, 18), (-18, 24), (8, 16), (34, 22)]:
        draw.polygon([(gx + sx - 4, gy - 68), (gx + sx + 4, gy - 68), (gx + sx, gy - 68 + slen)], fill=(132, 136, 124, 230))
    # Warm pine-oil lamp halo inside the painted cave
    draw.ellipse([gx - 28, gy - 42, gx + 20, gy + 6], fill=(232, 174, 84, 140))
    draw.ellipse([gx - 12, gy - 26, gx + 4, gy - 10], fill=(252, 232, 158, 240))

    def _draw_robed_villager(fx: int, fy: int, robe_rgba: tuple[int, int, int, int], hat: bool = False, seated: bool = False):
        draw.ellipse([fx - 8, fy - 35, fx + 8, fy - 19], fill=(224, 196, 160, 255), outline=(48, 36, 30, 255), width=2)
        draw.ellipse([fx - 4, fy - 41, fx + 4, fy - 34], fill=(40, 34, 30, 255))
        if hat:
            draw.polygon([(fx - 19, fy - 30), (fx, fy - 44), (fx + 19, fy - 30)], fill=(166, 134, 78, 255), outline=(54, 40, 28, 255))
        if seated:
            draw.polygon([(fx - 20, fy + 10), (fx - 11, fy - 18), (fx + 11, fy - 18), (fx + 22, fy + 10)], fill=robe_rgba, outline=(42, 34, 28, 255))
            draw.line([(fx - 11, fy - 6), (fx + 12, fy - 6)], fill=(226, 210, 178, 220), width=2)
        else:
            draw.polygon([(fx - 16, fy + 28), (fx - 9, fy - 18), (fx + 9, fy - 18), (fx + 17, fy + 28)], fill=robe_rgba, outline=(42, 34, 28, 255))
            draw.line([(fx - 10, fy - 2), (fx + 10, fy - 2)], fill=(226, 210, 178, 220), width=2)

    # Left: Mountain herb/tea gatherer with woven basket & bamboo staff
    _draw_robed_villager(196, 314, (58, 112, 92, 255), hat=True)
    draw.rectangle([175, 296, 190, 320], fill=(150, 114, 64, 255), outline=(54, 40, 28, 255), width=2)
    draw.line([(212, 278), (220, 344)], fill=(74, 52, 34, 255), width=3)

    # Center: Chengzhuang farmer tending paddy terrace channel
    _draw_robed_villager(368, 392, (62, 92, 122, 255), hat=True)
    draw.line([(352, 382), (326, 418)], fill=(74, 52, 34, 255), width=3)

    # Right (inside painted Yanxia Cavern): Scholar & child reading bamboo slips at stone table
    _draw_robed_villager(gx + 28, gy + 12, (172, 70, 52, 255), hat=False, seated=True)
    _draw_robed_villager(gx - 34, gy + 16, (72, 126, 104, 255), hat=False, seated=True)
    draw.rectangle([gx - 18, gy + 2, gx + 14, gy + 14], fill=(134, 138, 128, 255), outline=(44, 46, 42, 255), width=2)
    # Tiny golden bamboo scroll open on the stone table
    draw.rectangle([gx - 12, gy - 4, gx + 8, gy + 2], fill=(218, 188, 122, 255), outline=(92, 68, 38, 255), width=1)

    # Gliding white egrets ("白鹭掠烟")
    for ex, ey in [(534, 132), (574, 114), (608, 140), (366, 148)]:
        draw.arc([ex - 16, ey - 8, ex, ey + 8], start=200, end=350, fill=(246, 242, 230, 245), width=3)
        draw.arc([ex, ey - 8, ex + 16, ey + 8], start=190, end=340, fill=(246, 242, 230, 245), width=3)

    # Framing Moso bamboo stalks on far right & lower left
    for bx in (922, 948):
        draw.line([(bx, 468), (bx - 8, 86)], fill=(44, 76, 54, 235), width=5)
        for by_n in range(126, 446, 54):
            draw.line([(bx - 6, by_n), (bx + 6, by_n)], fill=(28, 46, 34, 245), width=2)
            for dx, dy in [(-24, -10), (-18, 8), (20, -8)]:
                draw.line([(bx, by_n), (bx + dx, by_n + dy)], fill=(46, 98, 68, 230), width=3)

    # Classical cinnabar + azurite double mural frame
    draw.rectangle([14, 14, w - 15, h - 15], outline=(58, 48, 40, 255), width=8)
    draw.rectangle([26, 26, w - 27, h - 27], outline=(168, 64, 46, 245), width=4)
    draw.rectangle([36, 36, w - 37, h - 37], outline=(54, 90, 116, 235), width=2)

    # Vertical cartouche ("烟山先民耕读图") with plenty of room above red seal "诚"
    draw.rectangle([52, 48, 114, 352], fill=(220, 206, 174, 248), outline=(154, 56, 42, 255), width=3)
    f_cart = _pick_font(["STKAITI.TTF", "SIMLI.TTF", "simkai.ttf"], 30)
    f_seal = _pick_font(["STKAITI.TTF", "simkai.ttf"], 20)
    for idx, ch in enumerate("烟山先民耕读图"):
        _draw_centered_text(draw, (83, 72 + idx * 33), ch, f_cart, (48, 34, 28, 255))
    draw.rectangle([67, 308, 99, 340], fill=(164, 46, 36, 255))
    _draw_centered_text(draw, (83, 324), "诚", f_seal, (246, 230, 198, 255))

    # Natural jagged rock fissures + stone-plaster pigment patina
    _draw_rock_fissures(draw, w, h, 6291, count=6)
    arr = np.array(img, dtype=np.float32)
    arr += (n_lime * 10.5 + n_fine * 5.5)[:, :, None]
    edge_dist = np.minimum(np.minimum(xx, 1.0 - xx) * 2.4, np.minimum(yy, 1.0 - yy) * 1.9)
    edge_wear = np.clip(1.0 - edge_dist / 0.22, 0.0, 1.0) * np.clip(0.62 + 0.38 * n_lime, 0.2, 1.0)
    rock_col = np.array([86, 90, 80], dtype=np.float32)
    arr = arr * (1.0 - edge_wear[:, :, None] * 0.62) + rock_col * (edge_wear[:, :, None] * 0.62)

    out_img = Image.fromarray(np.clip(arr, 16, 246).astype(np.uint8), mode="RGB")
    path = OUT / "mural_yanxia_ancients.png"
    out_img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


def build_cave_chronicle_inscription() -> Path:
    w, h = 512, 768
    img = _karst_canvas(w, h, 6206, (76, 82, 76), moss_strength=0.40)
    draw = ImageDraw.Draw(img)

    draw.rectangle([20, 20, w - 21, h - 21], outline=(38, 44, 40), width=6)
    draw.rectangle([32, 32, w - 33, h - 33], outline=(136, 146, 136), width=2)
    draw.line([(56, 148), (w - 56, 148)], fill=(44, 50, 46), width=4)

    f_head = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 56)
    f_col = _pick_font(["STKAITI.TTF", "simkai.ttf", "simfang.ttf"], 33)
    f_sub = _pick_font(["STKAITI.TTF", "simkai.ttf"], 25)

    _draw_centered_text(draw, (w * 0.5 + 2, 88 + 2), "烟 霞 古 洞 志", f_head, (24, 28, 26))
    _draw_centered_text(draw, (w * 0.5, 88), "烟 霞 古 洞 志", f_head, (236, 228, 198))

    cols = [
        "留丹青石刻传后世",
        "山人煮茗夜读于此",
        "洞有寒泉冬温夏冽",
        "遂名此山曰烟山焉",
        "暮霭竹烟常绕石壁",
        "昔诚庄先民辟山畴",
    ]
    xs = [74, 146, 218, 290, 362, 434]
    for cx, txt in zip(xs, cols):
        for idx, ch in enumerate(txt):
            cy = 196 + idx * 56
            _draw_centered_text(draw, (cx + 2, cy + 2), ch, f_col, (24, 28, 26))
            _draw_centered_text(draw, (cx, cy), ch, f_col, (228, 226, 202))

    draw.line([(58, 650), (w - 58, 650)], fill=(54, 62, 56), width=2)
    _draw_centered_text(draw, (w * 0.5, 694), "内室石灶寒潭 · 可寻先民竹简遗珍", f_sub, (194, 218, 192))

    path = OUT / "inscription_cave_chronicle.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


if __name__ == "__main__":
    generated = [
        build_limestone_karst(),
        build_bamboo_maze_plaque(),
        build_yanxia_cave_plaque(),
        build_cliff_carving_stele(),
        build_mural_yanxia_ancients(),
        build_cave_chronicle_inscription(),
    ]
    print("Generated v0.6.2 textures:")
    for p in generated:
        print(" -", p)
