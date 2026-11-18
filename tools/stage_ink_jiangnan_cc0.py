"""Stage Poly Haven CC0 1K Jiangnan architectural/stone textures into game/assets/slice/ink_jiangnan/
(optimized 512x512 seamless maps for fast VRAM footprint on both dGPUs and iGPUs) and synthesize
a subtle seamless Xuan-paper fiber texture (xuan_paper_grain.jpg)."""
from __future__ import annotations
from pathlib import Path
import random
import math
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
PH_DIR = ROOT / "美术参考与素材库" / "04_CC0开源纹理与模型_PolyHaven"
OUT_DIR = ROOT / "game" / "assets" / "slice" / "ink_jiangnan"
OUT_DIR.mkdir(parents=True, exist_ok=True)

COPY_SPECS = [
    ("粉墙_斑驳白灰泥_painted_plaster_wall", "painted_plaster_wall", "plaster_albedo.jpg", "plaster_normal.jpg", "plaster_rough.jpg", 512),
    ("粉墙_雨痕剥落老墙_damaged_plaster", "damaged_plaster", "plaster_weathered_albedo.jpg", "plaster_weathered_normal.jpg", "plaster_weathered_rough.jpg", 512),
    ("黛瓦_江南小青瓦_grey_roof_tiles", "grey_roof_tiles", "tile_albedo.jpg", "tile_normal.jpg", "tile_rough.jpg", 512),
    ("青石板_湿润石坪_slate_floor", "slate_floor", "bluestone_albedo.jpg", "bluestone_normal.jpg", "bluestone_rough.jpg", 512),
    ("溪滩过渡_泥卵石_brown_mud_rocks_01", "brown_mud_rocks_01", "mud_cobble_albedo.jpg", "mud_cobble_normal.jpg", "mud_cobble_rough.jpg", 512),
    ("太湖苍石_苔岩_mossy_rock", "mossy_rock", "moss_rock_albedo.jpg", "moss_rock_normal.jpg", "moss_rock_rough.jpg", 512),
]

for folder, prefix, out_c, out_n, out_r, sz in COPY_SPECS:
    src_d = PH_DIR / folder
    for map_tag, out_name in [("Diffuse", out_c), ("nor_gl", out_n), ("Rough", out_r)]:
        candidates = list(src_d.glob(f"{prefix}_{map_tag}_1k.*"))
        if not candidates:
            raise FileNotFoundError(f"Missing {prefix}_{map_tag}_1k in {src_d}")
        im = Image.open(candidates[0]).convert("RGB")
        im = im.resize((sz, sz), Image.Resampling.LANCZOS)
        im.save(OUT_DIR / out_name, quality=88)
        print("Staged", out_name, sz)

# Generate seamless subtle Xuan-paper (宣纸纤维) tileable grayscale texture (512x512)
S = 512
rng = random.Random(20261118)
paper = Image.new("L", (S, S), 236)
px = paper.load()
for y in range(S):
    for x in range(S):
        # Periodic seamlessly wrapping multi-octave cloud + fine deckle grain
        n1 = math.sin(x * math.tau / S * 3.0 + math.cos(y * math.tau / S * 2.0) * 1.4)
        n2 = math.cos(y * math.tau / S * 5.0 - math.sin(x * math.tau / S * 4.0) * 1.3)
        grain = rng.randint(-9, 9)
        v = int(max(195, min(255, 236 + n1 * 7.0 + n2 * 5.0 + grain)))
        px[x, y] = v

paper = paper.filter(ImageFilter.GaussianBlur(0.65))
draw = ImageDraw.Draw(paper)
# Fine organic mulberry bark fibers (檀皮宣纸纤维丝, wrapped across torus boundaries)
for _ in range(420):
    fx = rng.uniform(0, S)
    fy = rng.uniform(0, S)
    ang = rng.uniform(0, math.tau)
    flen = rng.uniform(8.0, 26.0)
    shade = rng.randint(206, 226)
    ex = fx + math.cos(ang) * flen
    ey = fy + math.sin(ang) * flen
    for ox in (-S, 0, S):
        for oy in (-S, 0, S):
            draw.line([(fx + ox, fy + oy), (ex + ox, ey + oy)], fill=shade, width=1)

paper.convert("RGB").save(OUT_DIR / "xuan_paper_grain.jpg", quality=90)
print("Generated xuan_paper_grain.jpg")
