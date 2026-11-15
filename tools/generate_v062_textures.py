"""Generate weathered Jiangnan karst limestone, cliff inscriptions, and ancient rock-chiseled petroglyph textures for v0.6.2.1.

Outputs into tools/generated_v062/ (embedded into game/assets/slice/v062_bamboo_cave.glb by build_v062_assets.py):
- limestone_karst.png           : seamless stratified grey-olive Jiangnan karst rock with calcite veins & moss
- plaque_bamboo_maze.png        : carved bluestone archway lintel reading "迷 踪 竹 石 阵"
- plaque_yanxia_cave.png        : deep-cut cliff lintel reading "烟 霞 古 洞" with weathered cinnabar trace
- stele_cliff_carving.png       : cliffside Moya carving ("摩崖石刻 · 竹石清音") chiseled into rock
- mural_yanxia_ancients.png     : frameless ancient rock-chiseled cavern petroglyph ("烟山耕读岩画")
- mural_yanxia_normal.png       : tangent-space normal map for chiseled cavern petroglyph grooves & cracks
- inscription_cave_chronicle.png: frameless chiseled East Gallery rock chronicle ("烟 霞 古 洞 志")
- chronicle_normal.png          : tangent-space normal map for East Gallery rock chronicle grooves
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
    fill: int | tuple[int, ...],
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

    vein = np.clip(1.0 - np.abs(n1 + 0.35 * n2) / 0.045, 0.0, 1.0) * 18.0
    fissure = np.clip(1.0 - np.abs(n2 - 0.25 * n1) / 0.038, 0.0, 1.0) * 22.0

    delta = (n1 * 15.0 + strata + fine_grain + vein - fissure)[:, :, None]
    arr = np.zeros((h, w, 3), dtype=np.float32)
    arr[:, :, 0] = base_rgb[0]
    arr[:, :, 1] = base_rgb[1]
    arr[:, :, 2] = base_rgb[2]
    arr = np.clip(arr + delta, 18, 238)

    moss_patch = np.clip(n2 * 0.85 + 0.35, 0.0, 1.0)
    moss_bias = np.clip((yy - 0.50) / 0.50, 0.0, 1.0) * 0.65 + 0.35
    moss_t = np.clip(moss_patch * moss_bias * moss_strength, 0.0, 0.62)[:, :, None]
    moss_col = np.array([52, 76, 46], dtype=np.float32)
    arr = arr * (1.0 - moss_t) + moss_col * moss_t
    return Image.fromarray(arr.astype(np.uint8), mode="RGB")


def _peck_polyline(
    draw: ImageDraw.ImageDraw,
    rng: np.random.Generator,
    pts: list[tuple[float, float]],
    width: float = 5.5,
    depth_val: int = 225,
    wobble: float = 2.0,
) -> None:
    """Chisel a hand-pecked groove along pts using irregular stone-chisel gouges & spall chips."""
    if len(pts) < 2:
        return
    wx, wy = 0.0, 0.0
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        seg_len = math.hypot(x1 - x0, y1 - y0)
        steps = max(2, int(seg_len / 2.2))
        for s in range(steps + 1):
            t = s / float(steps)
            wx = np.clip(wx + float(rng.normal(0.0, 0.55)), -wobble, wobble)
            wy = np.clip(wy + float(rng.normal(0.0, 0.55)), -wobble, wobble)
            cx = x0 + (x1 - x0) * t + wx
            cy = y0 + (y1 - y0) * t + wy
            rx = width * float(rng.uniform(0.42, 0.72))
            ry = width * float(rng.uniform(0.38, 0.68))
            ang_base = float(rng.uniform(0.0, math.tau))
            gouge_pts = []
            for k in range(5):
                a = ang_base + k * (math.tau / 5.0) + float(rng.uniform(-0.25, 0.25))
                rr = 1.0 + float(rng.uniform(-0.22, 0.25))
                gouge_pts.append((cx + math.cos(a) * rx * rr, cy + math.sin(a) * ry * rr))
            val = int(np.clip(depth_val * float(rng.uniform(0.72, 1.04)), 40, 255))
            draw.polygon(gouge_pts, fill=val)
            # Occasional tiny chipped stone spall beside chisel stroke
            if rng.random() < 0.22:
                sx = cx + float(rng.uniform(-width * 0.95, width * 0.95))
                sy = cy + float(rng.uniform(-width * 0.95, width * 0.95))
                sr = width * float(rng.uniform(0.20, 0.40))
                draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=int(val * 0.58))


def _peck_ring(
    draw: ImageDraw.ImageDraw,
    rng: np.random.Generator,
    cx: float,
    cy: float,
    radius: float,
    width: float = 5.0,
    depth_val: int = 220,
    segs: int = 22,
) -> None:
    pts = []
    for i in range(segs + 1):
        a = (i / float(segs)) * math.tau
        r_jit = radius * (1.0 + 0.06 * math.sin(a * 3.0 + 0.7) + float(rng.uniform(-0.04, 0.04)))
        pts.append((cx + math.cos(a) * r_jit, cy + math.sin(a) * r_jit))
    _peck_polyline(draw, rng, pts, width=width, depth_val=depth_val, wobble=1.5)


def _carve_relief_region(
    groove_arr: np.ndarray,
    rng: np.random.Generator,
    draw_fn,
    depth_scale: float = 0.78,
) -> np.ndarray:
    """Carve a recessed, chisel-pecked stone silhouette (汉代减地平钑/敲击岩画法) with rough fractured edges."""
    h, w = groove_arr.shape
    mask_img = Image.new("L", (w, h), 0)
    mdraw = ImageDraw.Draw(mask_img)
    draw_fn(mdraw)
    raw = np.asarray(mask_img, dtype=np.float32) / 255.0

    # Domain-warp silhouette edges with rock fracture noise so NO computer-clean silhouette survives
    jx = _tileable_fbm(w, h, int(rng.integers(1000, 9999)), (12, 28, 64)) * 3.2
    jy = _tileable_fbm(w, h, int(rng.integers(1000, 9999)), (12, 28, 64)) * 3.2
    yy, xx = np.meshgrid(np.arange(h, dtype=np.float32), np.arange(w, dtype=np.float32), indexing="ij")
    sx = np.clip(np.round(xx + jx).astype(np.int32), 0, w - 1)
    sy = np.clip(np.round(yy + jy).astype(np.int32), 0, h - 1)
    warped = raw[sy, sx]

    # Inside the recessed silhouette, apply dense uneven stone-chisel peck pits + deeper contour trench
    blur_inner = np.asarray(
        Image.fromarray((warped * 255.0).astype(np.uint8), mode="L").filter(ImageFilter.GaussianBlur(radius=2.4)),
        dtype=np.float32,
    ) / 255.0
    rim = np.clip(warped - blur_inner * 0.78, 0.0, 1.0) * 1.45
    peck_tex = 0.56 + 0.44 * _tileable_fbm(w, h, int(rng.integers(1000, 9999)), (24, 52, 96))
    stipple = np.clip(peck_tex + rng.normal(0.0, 0.16, size=(h, w)).astype(np.float32), 0.28, 1.05)
    carved = np.clip(warped * stipple * depth_scale + rim * 0.35, 0.0, 1.0)
    np.maximum(groove_arr, carved, out=groove_arr)
    return warped


def _synthesize_chiseled_rock_wall(
    w: int,
    h: int,
    seed: int,
    base_rgb: tuple[int, int, int],
    groove_norm: np.ndarray,
    ochre_mask: np.ndarray | None = None,
    edge_feather: float = 0.13,
) -> tuple[Image.Image, Image.Image]:
    """Convert a 2D chisel-depth map into weathered chiseled cavern limestone albedo + tangent-space normal map."""
    rng = np.random.default_rng(seed)
    yy, xx = np.meshgrid(np.linspace(0.0, 1.0, h), np.linspace(0.0, 1.0, w), indexing="ij")

    # 1) Base rough cavern limestone sampled directly from limestone_karst.png × (0.74, 0.78, 0.73)
    # so rock color & veins match Mat_KarstCaveInterior 100% seamlessly!
    karst_path = OUT / "limestone_karst.png"
    if karst_path.exists():
        src_k = np.asarray(Image.open(karst_path).convert("RGB"), dtype=np.float32)
        kh, kw, _ = src_k.shape
        tile_x = 1.45 if w > h else 0.72
        tile_y = 0.78 if w > h else 0.92
        ix = (np.mod(xx * tile_x + 0.17, 1.0) * (kw - 1)).astype(np.int32)
        iy = (np.mod(yy * tile_y + 0.23, 1.0) * (kh - 1)).astype(np.int32)
        arr = src_k[iy, ix] * np.array([0.74, 0.78, 0.73], dtype=np.float32)
    else:
        rock_img = _karst_canvas(w, h, seed, base_rgb, moss_strength=0.40)
        arr = np.asarray(rock_img, dtype=np.float32).copy()

    n_macro = _tileable_fbm(w, h, seed + 101, (3, 6, 13, 27))
    n_mid = _tileable_fbm(w, h, seed + 203, (8, 19, 41, 83))
    n_micro = _tileable_fbm(w, h, seed + 307, (32, 68, 128))

    # 2) Irregular perimeter vignette so zero carving or discontinuity ever reaches the mesh edge
    if edge_feather > 0.0:
        edge_noise = n_macro * 0.045 + n_mid * 0.022
        dx = np.minimum(xx, 1.0 - xx) + edge_noise
        dy = np.minimum(yy, 1.0 - yy) + edge_noise
        vignette = np.clip(np.minimum(dx / edge_feather, dy / (edge_feather * 1.15)), 0.0, 1.0)
        vignette = vignette * vignette * (3.0 - 2.0 * vignette)
    else:
        vignette = np.ones((h, w), dtype=np.float32)

    # 3) Natural stone spalling & centuries of erosion flaking small patches of the carving
    spall = np.clip((n_mid * 0.65 + n_micro * 0.35) - 0.34, 0.0, 1.0) * 1.35
    groove = groove_norm * vignette * (1.0 - spall * 0.58)
    groove = np.asarray(
        Image.fromarray(np.clip(groove * 255.0, 0, 255).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=0.75)
        ),
        dtype=np.float32,
    ) / 255.0

    # 4) Geological limestone bedding fissures & fine branching cracks along natural strata
    crack_img = Image.new("L", (w, h), 0)
    cdraw = ImageDraw.Draw(crack_img)
    for _ in range(5):
        cx = float(rng.uniform(w * 0.06, w * 0.88))
        cy = float(rng.uniform(h * 0.08, h * 0.82))
        ang = float(rng.choice([rng.uniform(0.28, 0.78), rng.uniform(2.35, 2.85)]))
        cpts = [(cx, cy)]
        for _s in range(int(rng.integers(7, 14))):
            ang += float(rng.uniform(-0.32, 0.32))
            step = float(rng.uniform(16.0, 32.0))
            cx += math.cos(ang) * step
            cy += math.sin(ang) * step
            cpts.append((cx, cy))
        cdraw.line(cpts, fill=int(rng.integers(95, 155)), width=int(rng.integers(1, 3)))
    crack_depth = (
        np.asarray(crack_img.filter(ImageFilter.GaussianBlur(radius=0.80)), dtype=np.float32) / 255.0
    ) * vignette

    # 5) Combined heightfield (positive = outward stone surface, negative = chiseled/cracked recess)
    rock_relief = n_macro * 0.24 + n_mid * 0.14 + n_micro * 0.07
    carve_depth = np.clip(groove * 0.98 + crack_depth * 0.55, 0.0, 1.15)
    height_field = rock_relief - carve_depth

    # Finite-difference gradients (y increases downward):
    # For an INCISED groove (carve_depth > 0), top lip has dh_dy < 0 (faces downward -> IN SHADOW),
    # bottom lip has dh_dy > 0 (faces upward toward overhead cave light -> CATCHES HIGHLIGHT)!
    dh_dy, dh_dx = np.gradient(height_field)
    raking = np.clip((dh_dx * 0.42 + dh_dy * 0.90) * 10.5, -1.0, 1.0)

    # 6) Physically grounded INCISED stone-chisel coloration (阴刻凹槽深色凿影 + 下唇凿白亮边):
    groove_ao = np.clip(groove * 1.18, 0.0, 1.0)[:, :, None]
    trench_stone = np.array([25.0, 29.0, 25.0], dtype=np.float32)
    arr = arr * (1.0 - groove_ao * 0.68) + trench_stone * (groove_ao * 0.68)

    # Very subtle, patchy, 1000-year-old weathered dark iron-ochre trace ONLY in deep sheltered pits
    if ochre_mask is not None:
        ochre_survive = np.clip(n_macro * 0.75 + n_mid * 0.55 + 0.10, 0.0, 1.0)
        ochre_t = np.clip(ochre_mask * groove * ochre_survive * 0.55, 0.0, 0.45)[:, :, None]
        aged_ochre = np.array([108.0, 54.0, 38.0], dtype=np.float32)
        arr = arr * (1.0 - ochre_t) + aged_ochre * ochre_t

    # Crack shadow + crisp top-lip shadow & bottom-lip crushed-calcite chisel highlight
    crack_ao = np.clip(crack_depth * 30.0, 0.0, 34.0)[:, :, None]
    lip_weight = 12.0 + 54.0 * np.clip(carve_depth * 1.50, 0.0, 1.0)
    bevel_light = (raking * lip_weight)[:, :, None]
    arr = arr - crack_ao + bevel_light

    # 7) Organic carving-halo RGBA alpha: 100% opaque on chiseled grooves & weathered stone halo,
    # feathering organically to 0.0 before any mesh boundary so ZERO rectangular edge can ever exist!
    active_u8 = np.clip((groove * 2.4 + crack_depth * 0.85) * 255.0, 0, 255).astype(np.uint8)
    active_pil = Image.fromarray(active_u8, mode="L")
    halo_near = np.asarray(active_pil.filter(ImageFilter.GaussianBlur(radius=18.0)), dtype=np.float32) / 255.0
    halo_wide = np.asarray(active_pil.filter(ImageFilter.GaussianBlur(radius=42.0)), dtype=np.float32) / 255.0
    alpha_f = np.clip(
        (active_u8.astype(np.float32) / 255.0) * 1.45
        + halo_near * 1.35
        + halo_wide * (0.52 + 0.18 * n_macro),
        0.0,
        1.0,
    ) * vignette
    alpha_f = alpha_f * alpha_f * (3.0 - 2.0 * alpha_f)

    rgb_u8 = np.clip(arr, 14, 235).astype(np.uint8)
    alpha_u8 = np.clip(alpha_f * 255.0, 0, 255).astype(np.uint8)
    rgba = np.dstack([rgb_u8, alpha_u8])
    albedo_img = Image.fromarray(rgba, mode="RGBA")

    # 8) Tangent-space normal map (OpenGL +Y up: nx = -dh_dx * s, ny = dh_dy * s, nz = 1.0)
    n_strength = 4.2
    nx = -dh_dx * n_strength
    ny = dh_dy * n_strength
    nz = np.ones_like(nx)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    n_rgb = np.stack(
        [
            (nx * inv_len * 0.5 + 0.5) * 255.0,
            (ny * inv_len * 0.5 + 0.5) * 255.0,
            (nz * inv_len * 0.5 + 0.5) * 255.0,
        ],
        axis=-1,
    )
    normal_img = Image.fromarray(np.clip(n_rgb, 0, 255).astype(np.uint8), mode="RGB")
    return albedo_img, normal_img


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
    _draw_centered_text(draw, (w * 0.50 - 1, h * 0.48 - 1), "烟 霞 古 洞", f_title, (196, 98, 74))
    _draw_centered_text(draw, (w * 0.50, h * 0.48), "烟 霞 古 洞", f_title, (176, 62, 46))

    for i, ch in enumerate("诚庄古迹"):
        _draw_centered_text(draw, (714, 54 + i * 36), ch, f_side, (214, 206, 184))
    for i, ch in enumerate("岩刻寒潭"):
        _draw_centered_text(draw, (54, 54 + i * 36), ch, f_side, (214, 206, 184))

    draw.rectangle([688, 196, 736, 228], fill=(138, 42, 34), outline=(182, 82, 66), width=2)
    _draw_centered_text(draw, (712, 212), "古迹", f_seal, (236, 220, 188))

    path = OUT / "plaque_yanxia_cave.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


def build_cliff_carving_stele() -> Path:
    w, h = 512, 768
    img = _karst_canvas(w, h, 6204, (84, 90, 82), moss_strength=0.42)
    draw = ImageDraw.Draw(img)

    f_head = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 64)
    f_verse = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 42)
    f_sub = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 25)

    _draw_centered_text(draw, (w * 0.5 + 3, 98 + 3), "竹 石 清 音", f_head, (26, 22, 20))
    _draw_centered_text(draw, (w * 0.5, 98), "竹 石 清 音", f_head, (186, 68, 48))

    columns = ["清泉洗凡心", "曲径通幽洞", "翠篁引风吟", "瘦石穿云立"]
    xs = [106, 204, 308, 406]
    for cx, line_txt in zip(xs, columns):
        for idx, ch in enumerate(line_txt):
            cy = 224 + idx * 82
            _draw_centered_text(draw, (cx + 2, cy + 2), ch, f_verse, (24, 28, 24))
            _draw_centered_text(draw, (cx, cy), ch, f_verse, (224, 220, 198))

    _draw_centered_text(draw, (w * 0.5, 684), "烟山摩崖石刻 · 按 F 拓读寻踪", f_sub, (206, 202, 174))

    path = OUT / "stele_cliff_carving.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


def build_mural_yanxia_ancients() -> tuple[Path, Path]:
    """Chisel an authentic ancient rock petroglyph & Han-style cliff relief ('烟山耕读岩画') directly into rough cavern stone."""
    w, h = 1024, 512
    rng = np.random.default_rng(6205)

    groove_img = Image.new("L", (w, h), 0)
    gdraw = ImageDraw.Draw(groove_img)
    ochre_img = Image.new("L", (w, h), 0)
    odraw = ImageDraw.Draw(ochre_img)

    # 1) Chiseled Ancient Mountain Crags ("凿刻重峦叠嶂 + 斧劈石纹")
    ridge_far = [(96, 232), (178, 152), (258, 118), (344, 174), (442, 108), (542, 168), (642, 128), (748, 178), (854, 126), (928, 198)]
    ridge_mid = [(108, 276), (198, 204), (294, 178), (388, 236), (492, 188), (596, 238), (696, 192), (812, 214), (918, 268)]
    _peck_polyline(gdraw, rng, ridge_far, width=6.2, depth_val=215, wobble=2.8)
    _peck_polyline(gdraw, rng, ridge_mid, width=7.0, depth_val=235, wobble=2.6)
    # Archaic stone-chisel hatching ("岩刻山皴") below ridge crests
    for px, py in [(258, 132), (294, 192), (442, 124), (492, 202), (642, 144), (854, 142)]:
        for k in range(-2, 3):
            p0 = (px + k * 14, py + abs(k) * 4)
            p1 = (px + k * 17 - 10, py + 38 + abs(k) * 3)
            _peck_polyline(gdraw, rng, [p0, p1], width=4.0, depth_val=165, wobble=1.8)

    # 2) Archaic Chiseled Sun Petroglyph ("先民日轮岩画": concentric pecked stone circles + 12 uneven rays)
    sx, sy = 602.0, 96.0
    _peck_ring(gdraw, rng, sx, sy, 23.0, width=5.6, depth_val=238, segs=20)
    _peck_ring(gdraw, rng, sx, sy, 9.0, width=4.8, depth_val=225, segs=12)
    odraw.ellipse([sx - 34, sy - 34, sx + 34, sy + 34], fill=210)
    for r_i in range(12):
        ang = r_i * (math.tau / 12.0) + 0.15
        r0 = 28.0
        r1 = 42.0 + (6.0 if r_i % 2 == 0 else 0.0)
        _peck_polyline(
            gdraw,
            rng,
            [(sx + math.cos(ang) * r0, sy + math.sin(ang) * r0), (sx + math.cos(ang) * r1, sy + math.sin(ang) * r1)],
            width=4.2,
            depth_val=205,
            wobble=1.4,
        )

    # Archaic chiseled flying egrets ("岩刻翔鹭")
    for ex, ey in [(362, 118), (398, 102), (518, 114), (712, 108)]:
        _peck_polyline(gdraw, rng, [(ex - 16, ey + 5), (ex - 5, ey - 5), (ex, ey + 1), (ex + 6, ey - 6), (ex + 17, ey + 4)], width=4.2, depth_val=200, wobble=1.2)

    # 3) Winding Chiseled Mountain Creek & Rough Stone Slab Bridge ("凿石涧水与古石梁")
    for lane, off_x in enumerate([-9.0, 0.0, 9.0]):
        creek_pts = []
        for i in range(16):
            t = i / 15.0
            cy = 216.0 + t * 218.0
            cx = 504.0 + math.sin(t * 4.8 + lane * 0.3) * 28.0 + t * 18.0 + off_x * (0.65 + t * 0.55)
            creek_pts.append((cx, cy))
        _peck_polyline(gdraw, rng, creek_pts, width=4.4 if lane != 1 else 5.4, depth_val=210, wobble=1.8)
    # Archaic stone slab bridge across creek
    _peck_polyline(gdraw, rng, [(468, 344), (496, 334), (534, 334), (560, 344)], width=7.5, depth_val=242, wobble=1.6)
    _peck_polyline(gdraw, rng, [(482, 338), (482, 356)], width=6.0, depth_val=220, wobble=1.2)
    _peck_polyline(gdraw, rng, [(546, 338), (546, 356)], width=6.0, depth_val=220, wobble=1.2)

    # Stepped chiseled paddy terraces & rice-shoot notches on left-lower rock face ("辟畴刻痕")
    _peck_polyline(gdraw, rng, [(164, 344), (258, 336), (358, 340), (454, 334)], width=4.8, depth_val=200, wobble=2.0)
    _peck_polyline(gdraw, rng, [(164, 386), (262, 382)], width=4.8, depth_val=200, wobble=1.8)
    _peck_polyline(gdraw, rng, [(164, 424), (264, 418), (366, 424), (460, 418)], width=5.2, depth_val=215, wobble=2.0)
    for rx, ty in [(188, 342), (228, 339), (188, 384), (232, 383), (192, 422), (242, 420), (312, 422), (382, 422), (434, 419)]:
        _peck_polyline(gdraw, rng, [(rx, ty - 3), (rx - 5, ty - 13)], width=3.2, depth_val=175, wobble=1.0)
        _peck_polyline(gdraw, rng, [(rx, ty - 3), (rx + 5, ty - 13)], width=3.2, depth_val=175, wobble=1.0)

    # Chiseled Moso bamboo stalks framing left cliff & right grotto ("摩崖修竹")
    for bx, top_y, bot_y in [(138, 138, 434), (904, 122, 432), (930, 154, 428)]:
        _peck_polyline(gdraw, rng, [(bx, bot_y), (bx - 4, (bot_y + top_y) * 0.5), (bx - 9, top_y)], width=5.4, depth_val=215, wobble=1.5)
        for ny in range(top_y + 42, bot_y - 24, 56):
            _peck_polyline(gdraw, rng, [(bx - 10, ny), (bx + 6, ny)], width=3.8, depth_val=220, wobble=0.8)
            _peck_polyline(gdraw, rng, [(bx - 4, ny), (bx - 24, ny - 11)], width=3.6, depth_val=190, wobble=1.0)
            _peck_polyline(gdraw, rng, [(bx - 2, ny), (bx + 19, ny - 9)], width=3.6, depth_val=190, wobble=1.0)

    groove_arr = np.asarray(groove_img, dtype=np.float32) / 255.0

    # 4) Han-Relief / Petroglyph Recessed Stone Silhouettes ("减地平钑人物牛耕与石室夜读")
    # 4A: Mountain Tea/Herb Gatherer with Conical Bamboo Hat, Basket & Staff on Left Slope
    def _draw_tea_gatherer(d: ImageDraw.ImageDraw) -> None:
        gx, gy = 224, 294
        d.polygon([(gx - 18, gy - 32), (gx, gy - 46), (gx + 18, gy - 32)], fill=255)  # conical hat
        d.ellipse([gx - 7, gy - 33, gx + 7, gy - 19], fill=255)  # head
        d.polygon([(gx - 13, gy - 18), (gx + 11, gy - 18), (gx + 16, gy + 18), (gx - 15, gy + 18)], fill=255)  # coarse robe
        d.rectangle([gx - 25, gy - 14, gx - 12, gy + 8], fill=255)  # back basket
        d.line([(gx - 9, gy + 18), (gx - 13, gy + 36)], fill=255, width=6)
        d.line([(gx + 7, gy + 18), (gx + 12, gy + 36)], fill=255, width=6)
        d.line([(gx + 10, gy - 10), (gx + 24, gy - 18)], fill=255, width=5)
        d.line([(gx + 24, gy - 30), (gx + 28, gy + 38)], fill=255, width=4)  # walking staff

    _carve_relief_region(groove_arr, rng, _draw_tea_gatherer, depth_scale=0.84)

    # 4B: Classic Ancient Jiangnan Ox-Ploughing Scene ("先民驱牛扶犁岩刻") in Valley Terraces!
    def _draw_ox_and_ploughman(d: ImageDraw.ImageDraw) -> None:
        # Horned Water Buffalo / Ox moving right at (392, 378)
        ox, oy = 396, 376
        d.polygon([(ox - 28, oy - 12), (ox + 22, oy - 14), (ox + 28, oy + 6), (ox - 26, oy + 8)], fill=255)  # ox body
        d.polygon([(ox + 20, oy - 16), (ox + 40, oy - 12), (ox + 38, oy + 2), (ox + 22, oy + 2)], fill=255)  # ox head
        # Curved water-buffalo horns!
        d.arc([ox + 16, oy - 32, ox + 46, oy - 8], start=195, end=345, fill=255, width=5)
        for lx in (-22, -10, 12, 22):
            d.line([(ox + lx, oy + 7), (ox + lx + (3 if lx > 0 else -3), oy + 28)], fill=255, width=5)
        d.line([(ox - 27, oy - 8), (ox - 38, oy + 8)], fill=255, width=4)  # tail
        # Curved wooden plough ("曲辕犁") & drawbeam connecting ox to ploughman
        px, py = 304, 374
        d.line([(px + 22, py - 2), (ox - 18, oy - 6)], fill=255, width=4)  # drawbeam
        d.line([(px + 16, py - 12), (px + 34, py + 24), (px + 54, py + 26)], fill=255, width=5)  # ploughshare
        # Ploughman in conical hat leaning forward gripping plough
        d.polygon([(px - 15, py - 30), (px + 1, py - 43), (px + 17, py - 30)], fill=255)
        d.ellipse([px - 6, py - 31, px + 8, py - 17], fill=255)
        d.polygon([(px - 11, py - 16), (px + 9, py - 16), (px + 14, py + 14), (px - 13, py + 14)], fill=255)
        d.line([(px + 6, py - 10), (px + 22, py - 6)], fill=255, width=5)
        d.line([(px - 8, py + 14), (px - 16, py + 32)], fill=255, width=6)
        d.line([(px + 8, py + 14), (px + 16, py + 32)], fill=255, width=6)

    _carve_relief_region(groove_arr, rng, _draw_ox_and_ploughman, depth_scale=0.88)

    # 4C: Right Cavern Recess ("烟霞石室挑灯展简") — Chiseled Cave Arch + Two Kneeling Ancestors + Stone Lamp!
    cx_g, cy_g = 762, 344
    arch_pts = [
        (cx_g - 106, cy_g + 68),
        (cx_g - 100, cy_g - 18),
        (cx_g - 74, cy_g - 78),
        (cx_g - 18, cy_g - 106),
        (cx_g + 46, cy_g - 96),
        (cx_g + 92, cy_g - 48),
        (cx_g + 104, cy_g + 68),
    ]
    g2_img = Image.new("L", (w, h), 0)
    g2_draw = ImageDraw.Draw(g2_img)
    _peck_polyline(g2_draw, rng, arch_pts, width=8.5, depth_val=248, wobble=2.8)
    # Stalactite teeth chiseled under cave arch
    for st_x, st_l in [(-48, 20), (-18, 26), (14, 18), (44, 24)]:
        _peck_polyline(g2_draw, rng, [(cx_g + st_x, cy_g - 92), (cx_g + st_x, cy_g - 92 + st_l)], width=5.2, depth_val=220, wobble=1.2)
    # Chiseled flame rays above stone lamp
    for fa in (-0.5, 0.0, 0.5):
        _peck_polyline(
            g2_draw,
            rng,
            [(cx_g - 4, cy_g - 26), (cx_g - 4 + math.sin(fa) * 16, cy_g - 46)],
            width=3.8,
            depth_val=215,
            wobble=1.0,
        )
    odraw.ellipse([cx_g - 28, cy_g - 52, cx_g + 22, cy_g + 4], fill=220)
    np.maximum(groove_arr, np.asarray(g2_img, dtype=np.float32) / 255.0, out=groove_arr)

    def _draw_cave_scholars(d: ImageDraw.ImageDraw) -> None:
        # Left kneeling elder ("席地长者")
        lx, ly = cx_g - 48, cy_g + 24
        d.ellipse([lx - 8, ly - 38, lx + 8, ly - 22], fill=255)
        d.ellipse([lx - 5, ly - 45, lx + 4, ly - 36], fill=255)  # topknot
        d.polygon([(lx - 18, ly + 22), (lx - 12, ly - 20), (lx + 10, ly - 20), (lx + 22, ly + 22)], fill=255)
        d.line([(lx + 8, ly - 8), (lx + 26, ly - 2)], fill=255, width=6)  # wide sleeve holding bamboo scroll
        # Right kneeling youth ("夜读童子")
        rx, ry = cx_g + 46, cy_g + 26
        d.ellipse([rx - 7, ry - 34, rx + 7, ry - 20], fill=255)
        d.polygon([(rx - 19, ry + 20), (rx - 9, ry - 18), (rx + 11, ry - 18), (rx + 17, ry + 20)], fill=255)
        d.line([(rx - 7, ry - 7), (rx - 24, ry - 2)], fill=255, width=5)
        # Low stone slab table + tall-stemmed ancient stone oil lamp ("高柄石豆灯") + bamboo slip marks
        d.rectangle([cx_g - 24, cy_g + 6, cx_g + 22, cy_g + 16], fill=255)
        d.line([(cx_g - 16, cy_g + 16), (cx_g - 16, cy_g + 42)], fill=255, width=6)
        d.line([(cx_g + 14, cy_g + 16), (cx_g + 14, cy_g + 42)], fill=255, width=6)
        d.line([(cx_g - 4, cy_g + 6), (cx_g - 4, cy_g - 16)], fill=255, width=4)
        d.polygon([(cx_g - 14, cy_g - 16), (cx_g + 6, cy_g - 16), (cx_g + 10, cy_g - 23), (cx_g - 18, cy_g - 23)], fill=255)

    _carve_relief_region(groove_arr, rng, _draw_cave_scholars, depth_scale=0.86)

    # 5) Frameless Archaic Clerical Cliff Characters ("烟 山 耕 读") chiseled directly into upper-left bare stone!
    def _draw_archaic_inscription(d: ImageDraw.ImageDraw) -> None:
        f_clerical = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 46)
        for idx, ch in enumerate("烟山耕读"):
            _draw_centered_text(d, (88, 126 + idx * 58), ch, f_clerical, 255)

    inscr_mask = _carve_relief_region(groove_arr, rng, _draw_archaic_inscription, depth_scale=0.92)
    ochre_arr = np.maximum(np.asarray(ochre_img, dtype=np.float32) / 255.0, inscr_mask * 0.85)

    albedo_img, normal_img = _synthesize_chiseled_rock_wall(
        w,
        h,
        6255,
        base_rgb=(80, 87, 76),
        groove_norm=groove_arr,
        ochre_mask=ochre_arr,
        edge_feather=0.11,
    )

    albedo_path = OUT / "mural_yanxia_ancients.png"
    normal_path = OUT / "mural_yanxia_normal.png"
    albedo_img.save(albedo_path)
    normal_img.save(normal_path)
    return albedo_path, normal_path


def build_cave_chronicle_inscription() -> tuple[Path, Path]:
    """Frameless ancient chiseled rock chronicle ('烟霞古洞志') carved directly into East Cavern limestone wall."""
    w, h = 512, 768
    rng = np.random.default_rng(6206)
    groove_arr = np.zeros((h, w), dtype=np.float32)

    def _draw_chronicle_glyphs(d: ImageDraw.ImageDraw) -> None:
        f_head = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 54)
        f_col = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 34)
        _draw_centered_text(d, (w * 0.5, 118), "烟 霞 古 洞 志", f_head, 255)
        cols = [
            "凿岩画石志传后世",
            "山人煮茗夜读于此",
            "洞有寒泉冬温夏冽",
            "遂名此山曰烟山焉",
            "暮霭竹烟常绕石壁",
            "昔诚庄先民辟山畴",
        ]
        xs = [86, 154, 222, 290, 358, 426]
        for cx, txt in zip(xs, cols):
            for idx, ch in enumerate(txt):
                cy = 224 + idx * 58
                _draw_centered_text(d, (cx, cy), ch, f_col, 255)

    glyph_mask = _carve_relief_region(groove_arr, rng, _draw_chronicle_glyphs, depth_scale=0.92)
    ochre_head = np.zeros((h, w), dtype=np.float32)
    ochre_head[:165, :] = glyph_mask[:165, :] * 0.75

    albedo_img, normal_img = _synthesize_chiseled_rock_wall(
        w,
        h,
        6266,
        base_rgb=(79, 86, 76),
        groove_norm=groove_arr,
        ochre_mask=ochre_head,
        edge_feather=0.12,
    )
    albedo_path = OUT / "inscription_cave_chronicle.png"
    normal_path = OUT / "chronicle_normal.png"
    albedo_img.save(albedo_path)
    normal_img.save(normal_path)
    return albedo_path, normal_path


if __name__ == "__main__":
    mural_a, mural_n = build_mural_yanxia_ancients()
    chron_a, chron_n = build_cave_chronicle_inscription()
    generated = [
        build_limestone_karst(),
        build_bamboo_maze_plaque(),
        build_yanxia_cave_plaque(),
        build_cliff_carving_stele(),
        mural_a,
        mural_n,
        chron_a,
        chron_n,
    ]
    print("Generated v0.6.2.1 textures:")
    for p in generated:
        print(" -", p)
