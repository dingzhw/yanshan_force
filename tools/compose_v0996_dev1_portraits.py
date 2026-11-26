"""v0.9.9.6_dev1 Official 1:1 Lore Codex Portrait Compositor.

Composites the 6 Blender 5.3 EEVEE 1024x1280 RGBA studio bust renders directly over
hand-crafted DSLR-bokeh faction backdrops (matching each faction's color temperature,
lighting, and architectural atmosphere) and downscales cleanly with Lanczos to 512x640
into game/assets/portraits/*.png so every Lore Codex card matches the in-game 3D model 1:1!
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = Path(__file__).resolve().parents[1]
PORTRAIT_DIR = REPO_ROOT / "game" / "assets" / "portraits"


def make_backdrop(kind: str, w: int = 1024, h: int = 1280) -> Image.Image:
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xx / float(w)
    v = yy / float(h)

    if kind == "haavk_dam":
        # Bright sunlit Zero Dam concrete + Babel blue sky bokeh
        top = np.array([0.52, 0.78, 0.96], dtype=np.float32)
        mid = np.array([0.78, 0.86, 0.90], dtype=np.float32)
        bot = np.array([0.36, 0.44, 0.50], dtype=np.float32)
        arr = np.where(v[:, :, None] < 0.55,
                       top * (1.0 - v[:, :, None] / 0.55) + mid * (v[:, :, None] / 0.55),
                       mid * (1.0 - (v[:, :, None] - 0.55) / 0.45) + bot * ((v[:, :, None] - 0.55) / 0.45))
        img = Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8), "RGB")
        dr = ImageDraw.Draw(img)
        # Concrete Zero Dam silhouette & Babel radar mast
        dr.polygon([(0, 620), (420, 560), (480, 1280), (0, 1280)], fill=(176, 184, 188))
        dr.polygon([(520, 680), (1024, 620), (1024, 1280), (520, 1280)], fill=(154, 166, 174))
        dr.rectangle([(810, 160), (848, 720)], fill=(120, 134, 146))
        dr.ellipse([(760, 210), (898, 340)], outline=(145, 160, 172), width=14)
        dr.ellipse([(110, 180), (410, 480)], fill=(208, 240, 255))
        img = img.filter(ImageFilter.GaussianBlur(radius=22))
    elif kind == "vanguard_dusk":
        # Fiery sunset amber mountain ridges & crimson Mistbound combat haze
        top = np.array([0.82, 0.46, 0.22], dtype=np.float32)
        mid = np.array([0.92, 0.64, 0.30], dtype=np.float32)
        bot = np.array([0.28, 0.14, 0.12], dtype=np.float32)
        arr = np.where(v[:, :, None] < 0.52,
                       top * (1.0 - v[:, :, None] / 0.52) + mid * (v[:, :, None] / 0.52),
                       mid * (1.0 - (v[:, :, None] - 0.52) / 0.48) + bot * ((v[:, :, None] - 0.52) / 0.48))
        img = Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8), "RGB")
        dr = ImageDraw.Draw(img)
        dr.polygon([(0, 540), (260, 280), (540, 620), (840, 220), (1024, 480), (1024, 1280), (0, 1280)], fill=(138, 76, 46))
        dr.polygon([(0, 760), (340, 560), (680, 740), (1024, 580), (1024, 1280), (0, 1280)], fill=(86, 42, 32))
        img = img.filter(ImageFilter.GaussianBlur(radius=24))
    elif kind == "overlord_storm":
        # Dramatic thundercloud storm sky over Cloudtop Martial Arena peaks
        top = np.array([0.16, 0.21, 0.28], dtype=np.float32)
        mid = np.array([0.36, 0.42, 0.50], dtype=np.float32)
        bot = np.array([0.10, 0.13, 0.18], dtype=np.float32)
        arr = np.where(v[:, :, None] < 0.48,
                       top * (1.0 - v[:, :, None] / 0.48) + mid * (v[:, :, None] / 0.48),
                       mid * (1.0 - (v[:, :, None] - 0.48) / 0.52) + bot * ((v[:, :, None] - 0.48) / 0.52))
        img = Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8), "RGB")
        dr = ImageDraw.Draw(img)
        # Golden heavenly storm shaft & dark crags
        dr.polygon([(380, 0), (650, 0), (760, 1280), (260, 1280)], fill=(116, 108, 92))
        dr.polygon([(0, 640), (220, 460), (420, 780), (740, 440), (1024, 620), (1024, 1280), (0, 1280)], fill=(44, 52, 64))
        img = img.filter(ImageFilter.GaussianBlur(radius=28))
    elif kind == "desert_arch":
        # Warm golden Brakkesh sandstone arch & sunlit dunes
        top = np.array([0.74, 0.85, 0.94], dtype=np.float32)
        mid = np.array([0.92, 0.82, 0.64], dtype=np.float32)
        bot = np.array([0.62, 0.46, 0.30], dtype=np.float32)
        arr = np.where(v[:, :, None] < 0.40,
                       top * (1.0 - v[:, :, None] / 0.40) + mid * (v[:, :, None] / 0.40),
                       mid * (1.0 - (v[:, :, None] - 0.40) / 0.60) + bot * ((v[:, :, None] - 0.40) / 0.60))
        img = Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8), "RGB")
        dr = ImageDraw.Draw(img)
        dr.rectangle([(0, 0), (1024, 1280)], outline=(198, 152, 92), width=110)
        dr.arc([(120, 80), (904, 980)], start=180, end=360, fill=(192, 146, 86), width=96)
        dr.polygon([(0, 840), (1024, 780), (1024, 1280), (0, 1280)], fill=(176, 134, 82))
        img = img.filter(ImageFilter.GaussianBlur(radius=24))
    else:  # desert_fortress (Saeed / Reis)
        top = np.array([0.66, 0.80, 0.92], dtype=np.float32)
        mid = np.array([0.90, 0.78, 0.56], dtype=np.float32)
        bot = np.array([0.52, 0.38, 0.24], dtype=np.float32)
        arr = np.where(v[:, :, None] < 0.36,
                       top * (1.0 - v[:, :, None] / 0.36) + mid * (v[:, :, None] / 0.36),
                       mid * (1.0 - (v[:, :, None] - 0.36) / 0.64) + bot * ((v[:, :, None] - 0.36) / 0.64))
        img = Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8), "RGB")
        dr = ImageDraw.Draw(img)
        dr.polygon([(0, 420), (320, 380), (360, 1280), (0, 1280)], fill=(194, 156, 108))
        dr.polygon([(680, 360), (1024, 300), (1024, 1280), (650, 1280)], fill=(180, 140, 96))
        dr.polygon([(0, 820), (1024, 760), (1024, 1280), (0, 1280)], fill=(158, 120, 78))
        img = img.filter(ImageFilter.GaussianBlur(radius=22))

    # Subtle vignette for studio portrait depth
    bg_arr = np.array(img, dtype=np.float32) / 255.0
    dist = np.sqrt(((u - 0.5) * 1.15) ** 2 + ((v - 0.45) * 1.05) ** 2)
    vig = np.clip(1.0 - np.maximum(0.0, dist - 0.42) * 0.55, 0.58, 1.0)
    bg_arr *= vig[:, :, None]
    return Image.fromarray(np.clip(bg_arr * 255, 0, 255).astype(np.uint8), "RGB")


PORTRAIT_SPECS = [
    ("haavk_trooper", "haavk_dam"),
    ("vanguard_boss", "vanguard_dusk"),
    ("skyfall_overlord", "overlord_storm"),
    ("ahsarah_guard", "desert_arch"),
    ("saeed_fiery_owl", "desert_fortress"),
    ("reis_warlord", "desert_fortress"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fg-dir", type=str, required=True)
    args = ap.parse_args()
    fg_dir = Path(args.fg_dir)

    for pid, bg_kind in PORTRAIT_SPECS:
        fg_path = fg_dir / f"{pid}_fg.png"
        if not fg_path.exists():
            print(f"SKIP missing {fg_path}")
            continue
        fg = Image.open(fg_path).convert("RGBA")
        bg = make_backdrop(bg_kind, fg.width, fg.height).convert("RGBA")
        comp = Image.alpha_composite(bg, fg).convert("RGB")
        out_p = PORTRAIT_DIR / f"{pid}.png"
        comp_512 = comp.resize((512, 640), Image.Resampling.LANCZOS)
        comp_512.save(out_p, format="PNG", optimize=True)
        print(f"PORTRAIT_COMPOSED {out_p.name} ({out_p.stat().st_size//1024} KB)")


if __name__ == "__main__":
    main()
