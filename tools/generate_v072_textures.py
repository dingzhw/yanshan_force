#!/usr/bin/env python3
"""Generate procedural surface artwork textures for v0.7.2 collectible 3D meshes.

Outputs crisp 512x512 / 512x256 PNG textures into tools/generated_v072/ which are
baked directly into game/assets/slice/v072_collectibles.glb by Blender 4.5.
All textures are 100% locally synthesized with Pillow (CC0 / Original Project).
"""

from __future__ import annotations

import math
import random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "generated_v072"
OUT.mkdir(parents=True, exist_ok=True)
FONT_PATH = ROOT / "game" / "assets" / "font" / "NotoSansSC.ttf"


def get_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    if FONT_PATH.exists():
        try:
            return ImageFont.truetype(str(FONT_PATH), size)
        except Exception:
            pass
    return ImageFont.load_default()


def add_grain(img: Image.Image, strength: int = 8, seed: int = 1) -> Image.Image:
    rng = random.Random(seed)
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            d = rng.randint(-strength, strength)
            px[x, y] = (
                max(0, min(255, r + d)),
                max(0, min(255, g + d)),
                max(0, min(255, b + d)),
            )
    return img


def make_fan_painting():
    w, h = 512, 256
    img = Image.new("RGB", (w, h), (239, 232, 212))
    draw = ImageDraw.Draw(img)
    # Soft misty cyan sky wash at top
    for y in range(h):
        t = y / float(h)
        r = int(226 + 15 * t)
        g = int(234 - 4 * t)
        b = int(226 - 18 * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b))
    # Distant indigo-teal Jiangnan mountain ridges (3 layers)
    layers = [
        (130, 38, (148, 178, 174), 0.014, 0.4),
        (162, 34, (92, 138, 128), 0.019, 1.8),
        (194, 28, (54, 96, 86), 0.025, 3.1),
    ]
    for base_y, amp, col, freq, ph in layers:
        pts = [(0, h)]
        for x in range(0, w + 4, 4):
            yy = base_y - amp * (0.55 * math.sin(x * freq + ph) + 0.35 * math.sin(x * freq * 2.1 + ph * 2.0) + 0.15 * math.cos(x * freq * 0.6))
            pts.append((x, int(yy)))
        pts.append((w, h))
        draw.polygon(pts, fill=col)
    # Mist ribbons
    mist = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    md = ImageDraw.Draw(mist)
    md.ellipse((40, 142, 360, 188), fill=(244, 240, 226, 130))
    md.ellipse((210, 170, 490, 212), fill=(244, 240, 226, 145))
    mist = mist.filter(ImageFilter.GaussianBlur(10))
    img = Image.alpha_composite(img.convert("RGBA"), mist).convert("RGB")
    draw = ImageDraw.Draw(img)
    # Tiny vermilion artist seal + ink bamboo strokes
    draw.rectangle((426, 46, 456, 76), fill=(176, 42, 38), outline=(140, 28, 24), width=2)
    draw.line([(432, 54), (450, 54)], fill=(242, 232, 218), width=2)
    draw.line([(441, 52), (441, 70)], fill=(242, 232, 218), width=2)
    # Subtle vertical pleat shadow lines
    for i in range(1, 16):
        px = int(w * i / 16.0)
        draw.line([(px, 0), (px, h)], fill=(190, 184, 166), width=1)
    # Gold border top/bottom
    draw.rectangle((0, 0, w - 1, 7), fill=(196, 160, 86))
    draw.rectangle((0, h - 8, w - 1, h - 1), fill=(196, 160, 86))
    add_grain(img, 5, 11).save(OUT / "tex_fan_painting.png")


def make_rubbing_scroll():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (218, 206, 180))
    draw = ImageDraw.Draw(img)
    # Brocade silk mounting border
    draw.rectangle((0, 0, w, h), fill=(182, 164, 128))
    draw.rectangle((34, 34, w - 34, h - 34), fill=(44, 46, 44), outline=(140, 118, 78), width=5)
    # Charcoal-ink stone rubbing inner field with weathered speckle
    rng = random.Random(22)
    for _ in range(1800):
        rx = rng.randint(44, w - 44)
        ry = rng.randint(44, h - 44)
        c = rng.randint(52, 86)
        draw.point((rx, ry), fill=(c, c, c - 2))
    # Pale engraved petroglyph lines (mountain, sun, terraced fields, scholar cottage)
    ink_w = (224, 218, 200)
    # Mountain silhouette
    draw.line([(68, 280), (146, 170), (218, 240), (296, 134), (374, 224), (444, 275)], fill=ink_w, width=5)
    # Sun disc
    draw.ellipse((358, 78, 412, 132), outline=ink_w, width=4)
    # Terraced paddy arcs
    for k in range(4):
        yy = 310 + k * 28
        draw.arc((74, yy - 18, 438, yy + 36), 190, 350, fill=ink_w, width=3)
    # Small scholar pavilion silhouette
    draw.line([(178, 270), (256, 244), (334, 270)], fill=ink_w, width=4)
    draw.line([(204, 270), (204, 308)], fill=ink_w, width=4)
    draw.line([(308, 270), (308, 308)], fill=ink_w, width=4)
    # Title calligraphy column + crimson collector seal
    font = get_font(34)
    for idx, ch in enumerate("烟山耕读"):
        draw.text((76, 66 + idx * 42), ch, fill=(235, 228, 210), font=font)
    draw.rectangle((78, 242, 112, 276), fill=(176, 40, 36))
    draw.rectangle((406, 406, 444, 444), fill=(176, 40, 36))
    add_grain(img, 6, 23).save(OUT / "tex_rubbing_scroll.png")


def make_slips_calligraphy():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (192, 152, 86))
    draw = ImageDraw.Draw(img)
    rng = random.Random(31)
    # Vertical bamboo wood fibers
    for x in range(0, w, 2):
        tone = rng.randint(-12, 12)
        draw.line([(x, 0), (x, h)], fill=(186 + tone, 146 + tone, 82 + tone), width=2)
    # 8 slip columns with vertical classical calligraphy
    font = get_font(30)
    cols = ["烟山先民耕读传家", "诚庄溪畔翠竹长青", "勤学善思温故知新", "明德笃行志在千里",
            "春耕夏耘秋收冬藏", "书声琅琅山谷回响", "礼义廉耻古道遗风", "玉璧青瓷千年留韵"]
    col_w = w // 8
    for ci, text in enumerate(cols):
        cx = ci * col_w
        draw.line([(cx, 0), (cx, h)], fill=(96, 66, 32), width=3)
        for ri, ch in enumerate(text):
            draw.text((cx + 16, 44 + ri * 52), ch, fill=(38, 26, 16), font=font)
    # Twin horizontal binding cord bands
    for by in (104, 402):
        draw.rectangle((0, by - 7, w, by + 7), fill=(108, 72, 40))
        for x in range(0, w, 14):
            draw.line([(x, by - 7), (x + 10, by + 7)], fill=(142, 102, 62), width=2)
    add_grain(img, 6, 32).save(OUT / "tex_slips_calligraphy.png")


def make_compass_dial():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (14, 34, 38))
    draw = ImageDraw.Draw(img)
    cx, cy = w // 2, h // 2
    draw.ellipse((14, 14, w - 14, h - 14), fill=(16, 40, 44), outline=(214, 178, 92), width=10)
    draw.ellipse((42, 42, w - 42, h - 42), outline=(108, 224, 188), width=3)
    # 72 degree ticks
    for deg in range(0, 360, 5):
        rad = math.radians(deg)
        r_out = 212
        r_in = 176 if deg % 30 == 0 else (190 if deg % 15 == 0 else 200)
        col = (242, 212, 126) if deg % 90 == 0 else (126, 232, 198)
        draw.line(
            [(cx + r_in * math.cos(rad), cy + r_in * math.sin(rad)),
             (cx + r_out * math.cos(rad), cy + r_out * math.sin(rad))],
            fill=col,
            width=4 if deg % 30 == 0 else 2,
        )
    # Compass rose star
    for deg in range(0, 360, 45):
        rad = math.radians(deg - 90)
        r_tip = 132 if deg % 90 == 0 else 92
        r_side = 22
        p_tip = (cx + r_tip * math.cos(rad), cy + r_tip * math.sin(rad))
        p_l = (cx + r_side * math.cos(rad + 1.2), cy + r_side * math.sin(rad + 1.2))
        p_r = (cx + r_side * math.cos(rad - 1.2), cy + r_side * math.sin(rad - 1.2))
        col = (232, 76, 68) if deg == 0 else ((226, 194, 108) if deg % 90 == 0 else (90, 176, 152))
        draw.polygon([(cx, cy), p_l, p_tip], fill=col)
        draw.polygon([(cx, cy), p_r, p_tip], fill=(col[0] // 2 + 30, col[1] // 2 + 30, col[2] // 2 + 30))
    font = get_font(44)
    draw.text((cx - 16, 56), "N", fill=(255, 92, 84), font=font)
    draw.text((cx - 14, h - 106), "S", fill=(238, 224, 178), font=font)
    draw.text((w - 94, cy - 26), "E", fill=(238, 224, 178), font=font)
    draw.text((60, cy - 26), "W", fill=(238, 224, 178), font=font)
    draw.ellipse((cx - 18, cy - 18, cx + 18, cy + 18), fill=(218, 182, 92))
    img.save(OUT / "tex_compass_dial.png")


def make_ration_label():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (138, 126, 94))
    draw = ImageDraw.Draw(img)
    # Olive-tan foil pouch gradient + subtle crinkle bands
    for y in range(h):
        shade = int(12 * math.sin(y * 0.06))
        draw.line([(0, y), (w, y)], fill=(134 + shade, 124 + shade, 90 + shade))
    # Dark tactical label block
    draw.rectangle((48, 86, w - 48, h - 86), fill=(62, 74, 52), outline=(218, 196, 134), width=6)
    draw.rectangle((66, 104, w - 66, 176), fill=(196, 146, 54))
    f_big = get_font(42)
    f_mid = get_font(30)
    f_sm = get_font(24)
    draw.text((92, 114), "FIELD RATION", fill=(26, 30, 22), font=f_big)
    draw.text((130, 206), "烟山单兵压缩干粮", fill=(240, 232, 200), font=f_mid)
    draw.text((112, 266), "HIGH ENERGY · 700 KCAL", fill=(188, 214, 162), font=f_sm)
    # Wheat emblem bars
    for i in range(6):
        bx = 96 + i * 54
        draw.rectangle((bx, 336, bx + 32, 376), fill=(218, 182, 96))
    add_grain(img, 7, 41).save(OUT / "tex_ration_label.png")


def make_tea_wrapper():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (54, 66, 38))
    draw = ImageDraw.Draw(img)
    rng = random.Random(51)
    # Compressed dried spring tea leaves mosaic
    for _ in range(2600):
        x = rng.randint(0, w)
        y = rng.randint(0, h)
        r = rng.randint(4, 14)
        ang = rng.uniform(0, math.pi)
        dx, dy = int(r * math.cos(ang)), int(r * math.sin(ang))
        col = rng.choice([(42, 58, 32), (58, 76, 40), (74, 88, 48), (34, 46, 26), (92, 104, 58)])
        draw.line([(x - dx, y - dy), (x + dx, y + dy)], fill=col, width=rng.randint(2, 4))
    # Warm antique parchment wrapper ring in center (no highlight blow-out!)
    draw.ellipse((106, 106, w - 106, h - 106), fill=(208, 192, 154), outline=(124, 94, 52), width=8)
    draw.ellipse((128, 128, w - 128, h - 128), outline=(168, 44, 38), width=4)
    f1 = get_font(46)
    f2 = get_font(26)
    draw.text((164, 168), "诚庄春茶", fill=(28, 38, 24), font=f1)
    draw.text((178, 236), "烟山明前嫩芽", fill=(74, 62, 42), font=f2)
    draw.rectangle((224, 286, 288, 348), fill=(172, 36, 32))
    draw.text((236, 296), "贡", fill=(238, 224, 196), font=get_font(38))
    add_grain(img, 5, 52).save(OUT / "tex_tea_wrapper.png")


def make_radio_screen():
    w, h = 512, 256
    img = Image.new("RGB", (w, h), (16, 46, 34))
    draw = ImageDraw.Draw(img)
    draw.rectangle((10, 10, w - 10, h - 10), fill=(20, 62, 44), outline=(92, 224, 162), width=6)
    f_big = get_font(62)
    f_sm = get_font(26)
    draw.text((34, 30), "CH-04  ENC-AES", fill=(122, 248, 188), font=f_sm)
    draw.text((34, 86), "146.520 MHz", fill=(168, 255, 210), font=f_big)
    # Signal strength bars
    for i in range(6):
        bh = 18 + i * 10
        draw.rectangle((34 + i * 28, 220 - bh, 52 + i * 28, 220), fill=(128, 250, 186))
    draw.text((230, 184), "YANSHAN TAC-NET", fill=(244, 214, 118), font=f_sm)
    img.save(OUT / "tex_radio_screen.png")


def make_quantum_screen():
    w, h = 512, 320
    img = Image.new("RGB", (w, h), (10, 26, 42))
    draw = ImageDraw.Draw(img)
    draw.rectangle((8, 8, w - 8, h - 8), fill=(12, 34, 54), outline=(102, 238, 255), width=6)
    # Audio waveform across middle
    pts = []
    for x in range(28, w - 28, 4):
        amp = 46 * math.sin((x - 28) * 0.06) * math.sin((x - 28) * 0.012)
        pts.append((x, int(156 + amp)))
    draw.line(pts, fill=(108, 246, 255), width=4)
    # Gold grid & bilingual readout
    for y in (92, 220):
        draw.line([(24, y), (w - 24, y)], fill=(40, 106, 134), width=2)
    draw.text((30, 28), "QUANTUM LEXICON · MK-V", fill=(250, 212, 104), font=get_font(28))
    draw.text((32, 240), "PHONETIC LOCK: 99.8%  [EN-CN]", fill=(142, 248, 206), font=get_font(24))
    img.save(OUT / "tex_quantum_screen.png")


def make_chip_pcb():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (16, 62, 48))
    draw = ImageDraw.Draw(img)
    # Gold PCB circuit traces
    trace = (212, 174, 72)
    for k in range(18, w - 18, 28):
        draw.line([(k, 16), (k, 130)], fill=trace, width=4)
        draw.line([(k, h - 130), (k, h - 16)], fill=trace, width=4)
        draw.line([(16, k), (130, k)], fill=trace, width=4)
        draw.line([(w - 130, k), (w - 16, k)], fill=trace, width=4)
        draw.ellipse((k - 5, 126, k + 5, 136), fill=(244, 212, 118))
        draw.ellipse((k - 5, h - 136, k + 5, h - 126), fill=(244, 212, 118))
    # Central silicon die plate
    draw.rectangle((136, 136, w - 136, h - 136), fill=(24, 30, 38), outline=(228, 190, 92), width=8)
    draw.rectangle((164, 164, w - 164, h - 164), fill=(32, 44, 58), outline=(92, 232, 224), width=3)
    draw.text((186, 216), "YS-AI", fill=(244, 210, 108), font=get_font(48))
    draw.text((190, 274), "NPU-9", fill=(118, 242, 230), font=get_font(34))
    img.save(OUT / "tex_chip_pcb.png")


def make_celadon_glaze():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (96, 168, 146))
    draw = ImageDraw.Draw(img)
    # Authentic Yue-ware "千峰翠色" rich jade-celadon gradient
    for y in range(h):
        t = y / float(h)
        r = int(78 + 50 * (1.0 - t))
        g = int(146 + 44 * (1.0 - t))
        b = int(126 + 38 * (1.0 - t))
        draw.line([(0, y), (w, y)], fill=(r, g, b))
    # Subtle ice-crackle ("开片") network
    rng = random.Random(66)
    pts = [(rng.randint(0, w), rng.randint(0, h)) for _ in range(48)]
    for i, p1 in enumerate(pts):
        for p2 in pts[i + 1:]:
            d = math.hypot(p1[0] - p2[0], p1[1] - p2[1])
            if 50 < d < 126:
                draw.line([p1, p2], fill=(154, 212, 194), width=1)
    img = img.filter(ImageFilter.GaussianBlur(0.5))
    add_grain(img, 3, 67).save(OUT / "tex_celadon_glaze.png")


def make_jade_cloud():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (176, 206, 188))
    draw = ImageDraw.Draw(img)
    cx, cy = w // 2, h // 2
    # Warm luminous celadon-white antique jade (no highlight clipping!)
    for rad in range(256, 20, -4):
        t = rad / 256.0
        col = (int(164 + 34 * (1 - t)), int(198 + 26 * (1 - t)), int(176 + 24 * (1 - t)))
        draw.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=col)
    # Crisp carved archaic swirling cloud-grain scrolls (谷纹/云纹)
    for ring_r in (110, 154, 198):
        n = int(ring_r / 11)
        for i in range(n):
            a = 2.0 * math.pi * i / n
            sx = int(cx + ring_r * math.cos(a))
            sy = int(cy + ring_r * math.sin(a))
            draw.arc((sx - 15, sy - 15, sx + 15, sy + 15), 20, 290, fill=(96, 138, 118), width=4)
            draw.ellipse((sx - 5, sy - 5, sx + 5, sy + 5), fill=(224, 240, 228))
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    add_grain(img, 3, 72).save(OUT / "tex_jade_cloud.png")


def make_silver_lock():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (156, 168, 180))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((24, 48, w - 24, h - 48), radius=54, fill=(172, 184, 196), outline=(82, 96, 112), width=12)
    draw.rounded_rectangle((50, 74, w - 50, h - 74), radius=38, outline=(228, 236, 244), width=5)
    # Deep oxidized antique silver chasing for crisp legibility
    font = get_font(78)
    draw.text((98, 184), "长命百岁", fill=(42, 52, 66), font=font)
    draw.text((94, 180), "长命百岁", fill=(232, 240, 248), font=font)
    for cx, cy in ((102, 122), (410, 122), (102, 390), (410, 390)):
        draw.ellipse((cx - 20, cy - 20, cx + 20, cy + 20), outline=(66, 78, 92), width=5)
        draw.ellipse((cx - 8, cy - 8, cx + 8, cy + 8), fill=(236, 242, 248))
    add_grain(img, 4, 81).save(OUT / "tex_silver_lock.png")


def make_battery_wrap():
    w, h = 512, 256
    img = Image.new("RGB", (w, h), (58, 86, 68))
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, w, 46), fill=(218, 164, 48))
    draw.rectangle((0, h - 38, w, h), fill=(36, 44, 42))
    draw.text((34, 72), "YS-18650  LI-ION", fill=(238, 240, 224), font=get_font(46))
    draw.text((34, 142), "3.7V  3400mAh  PATROL CELL", fill=(182, 226, 194), font=get_font(28))
    draw.text((412, 6), "+  +", fill=(32, 24, 14), font=get_font(34))
    add_grain(img, 5, 91).save(OUT / "tex_battery_wrap.png")


def make_blackbox_label():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (222, 74, 26))
    draw = ImageDraw.Draw(img)
    # Twin white high-vis reflective stripes
    draw.rectangle((0, 48, w, 96), fill=(242, 242, 238))
    draw.rectangle((0, h - 96, w, h - 48), fill=(242, 242, 238))
    draw.rectangle((26, 124, w - 26, h - 124), outline=(44, 20, 12), width=6)
    draw.text((54, 162), "FLIGHT RECORDER", fill=(250, 244, 230), font=get_font(44))
    draw.text((76, 236), "DO NOT OPEN", fill=(252, 224, 96), font=get_font(48))
    draw.text((92, 314), "YANSHAN AVIONICS", fill=(248, 240, 224), font=get_font(30))
    add_grain(img, 6, 95).save(OUT / "tex_blackbox_label.png")


def make_ganoderma_cap():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (92, 26, 42))
    draw = ImageDraw.Draw(img)
    cx, cy = w // 2, int(h * 0.54)
    # Concentric glossy lacquered crimson-purple to golden-rim rings
    for r in range(256, 8, -3):
        t = r / 256.0
        if t > 0.86:
            col = (232, 174, 72)  # Golden luminous growing margin!
        elif t > 0.72:
            col = (182, 62, 54)
        else:
            wave = int(20 * math.sin(r * 0.19))
            col = (
                max(36, min(220, 118 + wave)),
                max(14, min(90, 28 + wave // 3)),
                max(26, min(120, 52 + wave // 2)),
            )
        draw.ellipse((cx - r, cy - int(r * 0.85), cx + r, cy + int(r * 0.85)), fill=col)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    add_grain(img, 4, 99).save(OUT / "tex_ganoderma_cap.png")


def make_bamboo_ruler():
    w, h = 512, 128
    img = Image.new("RGB", (w, h), (196, 158, 92))
    draw = ImageDraw.Draw(img)
    rng = random.Random(101)
    for y in range(0, h, 2):
        d = rng.randint(-8, 8)
        draw.line([(0, y), (w, y)], fill=(192 + d, 154 + d, 88 + d), width=2)
    draw.rectangle((0, 0, w - 1, h - 1), outline=(108, 76, 36), width=4)
    f = get_font(22)
    for i in range(1, 32):
        x = int(i * (w - 32) / 32.0) + 16
        tick_h = 44 if i % 5 == 0 else 24
        draw.line([(x, 4), (x, 4 + tick_h)], fill=(46, 32, 18), width=3 if i % 5 == 0 else 2)
        if i % 5 == 0:
            draw.text((x - 10, 52), str(i), fill=(46, 32, 18), font=f)
    draw.text((170, 86), "烟山老竹尺 · 1尺", fill=(78, 50, 24), font=get_font(24))
    add_grain(img, 4, 102).save(OUT / "tex_bamboo_ruler.png")


def make_blue_porcelain():
    w, h = 512, 256
    img = Image.new("RGB", (w, h), (232, 236, 242))
    draw = ImageDraw.Draw(img)
    cobalt = (34, 72, 152)
    cobalt_lt = (74, 118, 194)
    draw.rectangle((0, 10, w, 24), fill=cobalt)
    draw.rectangle((0, 32, w, 38), fill=cobalt_lt)
    draw.rectangle((0, h - 24, w, h - 10), fill=cobalt)
    # Continuous cobalt lotus-vine scroll around cup body
    for k in range(6):
        cx = 42 + k * 84
        cy = 128
        draw.ellipse((cx - 26, cy - 26, cx + 26, cy + 26), outline=cobalt, width=5)
        draw.ellipse((cx - 12, cy - 12, cx + 12, cy + 12), fill=cobalt_lt)
        draw.arc((cx + 22, cy - 42, cx + 70, cy + 42), 110, 290, fill=cobalt, width=4)
        for dy in (-38, 38):
            draw.ellipse((cx - 8, cy + dy - 8, cx + 8, cy + dy + 8), fill=cobalt)
    add_grain(img, 3, 103).save(OUT / "tex_blue_porcelain.png")


def make_herb_specimen():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (222, 212, 184))
    draw = ImageDraw.Draw(img)
    draw.rectangle((16, 16, w - 16, h - 16), outline=(112, 86, 52), width=8)
    # Pressed Jiangnan fern & ginkgo specimen leaf
    draw.line([(256, 440), (256, 84)], fill=(54, 92, 46), width=8)
    for i in range(9):
        y = 112 + i * 34
        span = 118 - abs(i - 4) * 18
        draw.polygon([(256, y), (256 - span, y - 18), (256 - int(span * 0.7), y + 10)], fill=(62, 114, 52))
        draw.polygon([(256, y), (256 + span, y - 18), (256 + int(span * 0.7), y + 10)], fill=(72, 126, 58))
    draw.rectangle((312, 396, 474, 474), fill=(238, 232, 212), outline=(92, 74, 50), width=3)
    draw.text((326, 412), "烟山草本", fill=(46, 56, 38), font=get_font(28))
    draw.text((326, 444), "HERB #08", fill=(96, 80, 54), font=get_font(20))
    add_grain(img, 5, 104).save(OUT / "tex_herb_specimen.png")


def make_pocket_watch():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (232, 224, 202))
    draw = ImageDraw.Draw(img)
    cx, cy = 256, 256
    draw.ellipse((14, 14, w - 14, h - 14), fill=(234, 226, 204), outline=(172, 134, 56), width=12)
    draw.ellipse((44, 44, w - 44, h - 44), outline=(52, 44, 34), width=3)
    romans = ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
    f = get_font(34)
    for i, rm in enumerate(romans):
        a = math.radians(i * 30 - 90)
        x = int(cx + 164 * math.cos(a))
        y = int(cy + 164 * math.sin(a))
        draw.text((x - 16, y - 18), rm, fill=(36, 30, 24), font=f)
        draw.line(
            [(cx + 202 * math.cos(a), cy + 202 * math.sin(a)), (cx + 220 * math.cos(a), cy + 220 * math.sin(a))],
            fill=(44, 38, 30), width=4
        )
    # Ornate blued-steel clock hands (10:10)
    draw.line([(cx, cy), (cx - 88, cy - 56)], fill=(28, 42, 74), width=10)
    draw.line([(cx, cy), (cx + 116, cy - 68)], fill=(28, 42, 74), width=7)
    draw.ellipse((cx - 14, cy - 14, cx + 14, cy + 14), fill=(192, 150, 58))
    add_grain(img, 3, 105).save(OUT / "tex_pocket_watch.png")


def make_bronze_mirror():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (108, 102, 78))
    draw = ImageDraw.Draw(img)
    cx, cy = 256, 256
    for rad, col in ((244, (132, 120, 82)), (214, (86, 82, 62)), (164, (124, 114, 78)), (118, (76, 72, 54)), (60, (176, 152, 88))):
        draw.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=col, outline=(218, 212, 194), width=5)
    # Tang grapevine & silver-inlaid bosses around ring
    for i in range(16):
        a = 2.0 * math.pi * i / 16.0
        for rr, br in ((188, 10), (140, 8), (88, 7)):
            px, py = int(cx + rr * math.cos(a)), int(cy + rr * math.sin(a))
            draw.ellipse((px - br, py - br, px + br, py + br), fill=(214, 222, 226), outline=(58, 54, 42), width=2)
    add_grain(img, 4, 106).save(OUT / "tex_bronze_mirror.png")


def make_pencil_tin():
    w, h = 512, 256
    img = Image.new("RGB", (w, h), (54, 116, 118))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((12, 12, w - 12, h - 12), radius=24, fill=(62, 128, 128), outline=(228, 198, 124), width=8)
    draw.rectangle((36, 44, w - 36, h - 44), fill=(236, 228, 204), outline=(182, 140, 62), width=4)
    draw.text((88, 66), "烟山小学 · 文具盒", fill=(42, 74, 72), font=get_font(42))
    draw.text((112, 134), "GOOD STUDY · DAY DAY UP", fill=(168, 64, 48), font=get_font(24))
    add_grain(img, 5, 107).save(OUT / "tex_pencil_tin.png")


def make_suzhou_silk():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (26, 98, 86))
    draw = ImageDraw.Draw(img)
    gold = (228, 190, 92)
    for y in range(32, h, 64):
        for x in range(32, w, 64):
            draw.polygon([(x, y - 22), (x + 22, y), (x, y + 22), (x - 22, y)], outline=gold, width=3)
            draw.ellipse((x - 6, y - 6, x + 6, y + 6), fill=(242, 212, 126))
    draw.ellipse((156, 156, 356, 356), fill=(18, 72, 64), outline=gold, width=8)
    draw.text((206, 224), "苏绣", fill=(244, 214, 122), font=get_font(54))
    add_grain(img, 4, 108).save(OUT / "tex_suzhou_silk.png")


def make_crypto_drive():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (38, 46, 54))
    draw = ImageDraw.Draw(img)
    draw.rectangle((18, 18, w - 18, h - 18), fill=(46, 56, 66), outline=(222, 180, 74), width=10)
    draw.rectangle((48, 56, w - 48, 146), fill=(26, 32, 38), outline=(242, 198, 82), width=4)
    draw.text((68, 78), "AES-512 VAULT", fill=(248, 206, 92), font=get_font(44))
    draw.text((76, 184), "YANSHAN SECURE SSD", fill=(188, 220, 212), font=get_font(30))
    # Fingerprint scanner ring
    cx, cy = 256, 344
    for r in (68, 52, 36, 20):
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(92, 232, 214), width=4)
    add_grain(img, 4, 109).save(OUT / "tex_crypto_drive.png")


def make_imperial_bowl():
    w, h = 512, 256
    img = Image.new("RGB", (w, h), (238, 240, 244))
    draw = ImageDraw.Draw(img)
    cobalt = (22, 56, 144)
    gold = (216, 174, 68)
    draw.rectangle((0, 0, w, 16), fill=gold)
    draw.rectangle((0, 20, w, 34), fill=cobalt)
    draw.rectangle((0, h - 26, w, h - 12), fill=cobalt)
    # Intricate imperial blue-and-white cloud & ruyi petals
    for k in range(8):
        cx = 32 + k * 64
        draw.arc((cx - 28, 42, cx + 28, 104), 0, 180, fill=cobalt, width=5)
        draw.ellipse((cx - 18, 112, cx + 18, 148), outline=cobalt, width=5)
        draw.ellipse((cx - 7, 123, cx + 7, 137), fill=cobalt)
        draw.arc((cx - 30, 152, cx + 30, 224), 180, 360, fill=(56, 98, 184), width=4)
    add_grain(img, 2, 110).save(OUT / "tex_imperial_bowl.png")


def make_inkstone_carving():
    w, h = 512, 512
    img = Image.new("RGB", (w, h), (54, 46, 58))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((22, 22, w - 22, h - 22), radius=36, fill=(62, 52, 68), outline=(104, 88, 112), width=10)
    # Recessed ink grinding surface & deep crescent ink well at top
    draw.rounded_rectangle((64, 168, w - 64, h - 64), radius=24, fill=(40, 34, 46), outline=(92, 78, 98), width=4)
    draw.ellipse((96, 62, w - 96, 174), fill=(24, 22, 30), outline=(118, 98, 124), width=5)
    add_grain(img, 4, 111).save(OUT / "tex_inkstone_carving.png")


def main():
    make_fan_painting()
    make_rubbing_scroll()
    make_slips_calligraphy()
    make_compass_dial()
    make_ration_label()
    make_tea_wrapper()
    make_radio_screen()
    make_quantum_screen()
    make_chip_pcb()
    make_celadon_glaze()
    make_jade_cloud()
    make_silver_lock()
    make_battery_wrap()
    make_blackbox_label()
    make_ganoderma_cap()
    make_bamboo_ruler()
    make_blue_porcelain()
    make_herb_specimen()
    make_pocket_watch()
    make_bronze_mirror()
    make_pencil_tin()
    make_suzhou_silk()
    make_crypto_drive()
    make_imperial_bowl()
    make_inkstone_carving()
    files = sorted(OUT.glob("tex_*.png"))
    print(f"GENERATED_V080_TEXTURES={len(files)}")
    for f in files:
        print(f"  {f.name}: {f.stat().st_size} bytes")


if __name__ == "__main__":
    main()
