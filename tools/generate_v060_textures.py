"""Generate weathered Jiangnan calligraphy plaque and stone-stele textures for v0.6.0.

Outputs into tools/generated_v060/ (embedded into v060_jiangnan_assets.glb by build_v060_assets.py):
- plaque_wangdao.png   : dark cedar pavilion plaque reading "望稻亭" in gilded Lishu script
- stele_poem.png       : weathered Jiangnan bluestone verse tablet reading "烟山诗碑"
- stele_boundary.png   : moss-dappled stone trail marker reading "烟山古道 · 诚庄界"
"""
from __future__ import annotations

from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "generated_v060"
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


def _stone_canvas(w: int, h: int, seed: int, base_rgb: tuple[int, int, int]) -> Image.Image:
    rng = np.random.default_rng(seed)
    yy, xx = np.meshgrid(np.linspace(0, 1, h), np.linspace(0, 1, w), indexing="ij")
    noise = rng.normal(0.0, 7.5, size=(h, w, 1))
    streak = 6.0 * np.sin(yy * 28.0 + np.sin(xx * 9.0) * 1.4)[:, :, None]
    grain = 4.5 * np.cos(xx * 42.0 - yy * 19.0)[:, :, None]
    arr = np.zeros((h, w, 3), dtype=np.float32)
    arr[:, :, 0] = base_rgb[0]
    arr[:, :, 1] = base_rgb[1]
    arr[:, :, 2] = base_rgb[2]
    arr = np.clip(arr + noise + streak + grain, 18, 235)
    # Subtle lichen/moss mottling near edges and lower base
    moss_mask = np.clip((yy - 0.62) / 0.38, 0.0, 1.0) * (
        0.5 + 0.5 * np.sin(xx * 21.0 + yy * 17.0)
    )
    moss_col = np.array([58, 76, 46], dtype=np.float32)
    t = (moss_mask * 0.45)[:, :, None]
    arr = arr * (1.0 - t) + moss_col * t
    return Image.fromarray(arr.astype(np.uint8), mode="RGB")


def _draw_centered_text(draw: ImageDraw.ImageDraw, center: tuple[float, float], text: str, font, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = center[0] - tw * 0.5 - bbox[0]
    y = center[1] - th * 0.5 - bbox[1]
    draw.text((x, y), text, font=font, fill=fill)


def build_wangdao_plaque() -> Path:
    w, h = 512, 256
    rng = np.random.default_rng(6001)
    yy, xx = np.meshgrid(np.linspace(0, 1, h), np.linspace(0, 1, w), indexing="ij")
    wood = np.zeros((h, w, 3), dtype=np.float32)
    grain = 8.0 * np.sin(yy * 74.0 + np.sin(xx * 8.0) * 1.6) + rng.normal(0.0, 3.0, size=(h, w))
    wood[:, :, 0] = 52 + grain * 0.8
    wood[:, :, 1] = 28 + grain * 0.5
    wood[:, :, 2] = 20 + grain * 0.4
    img = Image.fromarray(np.clip(wood, 12, 160).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(img)

    # Outer carved frame & warm gilt inner border
    draw.rectangle([8, 8, w - 9, h - 9], outline=(168, 124, 52), width=6)
    draw.rectangle([20, 20, w - 21, h - 21], outline=(118, 78, 34), width=3)

    f_title = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf", "simhei.ttf"], 96)
    f_seal = _pick_font(["STKAITI.TTF", "simkai.ttf", "simhei.ttf"], 26)
    _draw_centered_text(draw, (w * 0.5 + 3, h * 0.49 + 3), "望 稻 亭", f_title, (24, 12, 8))
    _draw_centered_text(draw, (w * 0.5, h * 0.49), "望 稻 亭", f_title, (236, 198, 108))

    # Small vermilion seal stamp
    draw.rectangle([422, 168, 466, 214], fill=(156, 40, 34), outline=(196, 80, 62), width=2)
    _draw_centered_text(draw, (444, 191), "诚", f_seal, (244, 218, 176))

    path = OUT / "plaque_wangdao.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


def build_poem_stele() -> Path:
    w, h = 512, 768
    img = _stone_canvas(w, h, 6002, (74, 80, 76))
    draw = ImageDraw.Draw(img)

    draw.rectangle([22, 22, w - 23, h - 23], outline=(46, 52, 48), width=5)
    draw.rectangle([34, 34, w - 35, h - 35], outline=(138, 146, 138), width=2)
    draw.line([(68, 146), (w - 68, 146)], fill=(48, 54, 50), width=4)

    f_head = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 54)
    f_verse = _pick_font(["STKAITI.TTF", "simkai.ttf", "simfang.ttf"], 42)
    f_sub = _pick_font(["STKAITI.TTF", "simkai.ttf"], 28)

    _draw_centered_text(draw, (w * 0.5 + 2, 90 + 2), "烟 山 诗 碑", f_head, (28, 32, 30))
    _draw_centered_text(draw, (w * 0.5, 90), "烟 山 诗 碑", f_head, (240, 236, 210))

    # Classical vertical-style four-column couplets etched right-to-left
    columns = ["春风稻满洲", "千载读书处", "溪水绕村流", "山烟浮竹翠"]
    xs = [110, 204, 308, 402]
    for cx, line_txt in zip(xs, columns):
        for idx, ch in enumerate(line_txt):
            cy = 216 + idx * 78
            _draw_centered_text(draw, (cx + 2, cy + 2), ch, f_verse, (28, 32, 30))
            _draw_centered_text(draw, (cx, cy), ch, f_verse, (232, 228, 202))

    _draw_centered_text(draw, (w * 0.5, 676), "诚庄烟山古迹 · 按 E 研读", f_sub, (226, 220, 184))

    path = OUT / "stele_poem.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


def build_boundary_stele() -> Path:
    w, h = 512, 768
    img = _stone_canvas(w, h, 6003, (78, 82, 74))
    draw = ImageDraw.Draw(img)

    draw.rectangle([26, 26, w - 27, h - 27], outline=(46, 50, 44), width=5)
    draw.rectangle([38, 38, w - 39, h - 39], outline=(136, 142, 132), width=2)
    draw.line([(60, 198), (w - 60, 198)], fill=(48, 52, 46), width=4)

    f_title = _pick_font(["SIMLI.TTF", "STKAITI.TTF", "simkai.ttf"], 66)
    f_body = _pick_font(["SIMLI.TTF", "simkai.ttf", "simhei.ttf"], 48)
    f_note = _pick_font(["STKAITI.TTF", "simkai.ttf"], 32)

    _draw_centered_text(draw, (w * 0.5 + 2, 114 + 2), "烟 山 古 道", f_title, (26, 30, 24))
    _draw_centered_text(draw, (w * 0.5, 114), "烟 山 古 道", f_title, (242, 236, 206))

    _draw_centered_text(draw, (w * 0.5 + 2, 312), "东 望 诚 庄 稻 田", f_body, (28, 32, 26))
    _draw_centered_text(draw, (w * 0.5, 310), "东 望 诚 庄 稻 田", f_body, (232, 228, 198))
    _draw_centered_text(draw, (w * 0.5 + 2, 424), "西 入 竹 石 深 林", f_body, (28, 32, 26))
    _draw_centered_text(draw, (w * 0.5, 422), "西 入 竹 石 深 林", f_body, (232, 228, 198))
    _draw_centered_text(draw, (w * 0.5, 592), "青 石 单 拱 古 桥 界", f_note, (214, 218, 192))

    path = OUT / "stele_boundary.png"
    img.filter(ImageFilter.GaussianBlur(radius=0.35)).save(path)
    return path


if __name__ == "__main__":
    p1 = build_wangdao_plaque()
    p2 = build_poem_stele()
    p3 = build_boundary_stele()
    print("Generated v0.6.0 textures:", p1, p2, p3)
