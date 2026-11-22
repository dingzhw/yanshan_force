"""Process AI-painted Qinglu misty mountain panorama & cloud-sea mist ribbon into seamless 360-degree
game-ready RGBA textures for Yanshan Force v0.8.6:
  1. game/assets/slice/horizon_mountains.png    (2048x640 RGBA, mathematically seamless 360 wrap,
     100% opaque below uppermost skyline so interior white valley clouds NEVER bleed sky!)
  2. game/assets/slice/horizon_cloud_ribbon.png (2048x512 RGBA, seamless looping drifting mist belt)
"""
from __future__ import annotations
from pathlib import Path
import shutil
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
REF_DIR = ROOT / "美术参考与素材库" / "06_v086_Godot风格化与藏品建筑参考"
REF_DIR.mkdir(parents=True, exist_ok=True)

PANO_ARCHIVE_A = REF_DIR / "19_自绘远山全景原画_3D风格化阳光群峰A.jpg"
PANO_ARCHIVE_B = REF_DIR / "20_自绘远山全景原画_3D风格化云岚峰峦B.jpg"
PANO_ARCHIVE = PANO_ARCHIVE_A
CLOUD_ARCHIVE = REF_DIR / "18_自绘云海雾带原画_水墨飘浮云岚.jpg"

OUT_PANO = ROOT / "game" / "assets" / "slice" / "horizon_mountains.png"
OUT_CLOUD = ROOT / "game" / "assets" / "slice" / "horizon_cloud_ribbon.png"


def make_seamless_wrap(img: Image.Image, target_w: int, target_h: int, blend_frac: float = 0.16) -> Image.Image:
    """Create a completely organic (zero mirror symmetry!) 100% seamless horizontal wrap via cosine overlap-blend."""
    bw = max(64, int(round(target_w * blend_frac)))
    # Resize slightly wider so after overlapping bw pixels, final width is exact target_w
    resized = img.resize((target_w + bw, target_h), Image.Resampling.LANCZOS)
    arr = np.asarray(resized, dtype=np.float32)
    core = arr[:, bw:].copy()           # width = target_w
    left_tail = arr[:, :bw]             # rightmost overlaps smoothly with left_tail!
    # Cosine ramp 0 -> 1 over last bw columns
    t = 0.5 * (1.0 - np.cos(np.pi * np.linspace(0.0, 1.0, bw, dtype=np.float32)))[None, :, None]
    core[:, -bw:] = core[:, -bw:] * (1.0 - t) + left_tail * t
    return Image.fromarray(np.clip(core, 0, 255).astype(np.uint8), mode=img.mode)


def cut_mountain_alpha(rgb: np.ndarray) -> np.ndarray:
    """Detect pure white sky strictly downward from top row -> 100% opaque below skyline."""
    h, w, _ = rgb.shape
    is_white_sky = (rgb.min(axis=2) > 0.945) & ((rgb.max(axis=2) - rgb.min(axis=2)) < 0.045)
    skyline = np.zeros(w, dtype=np.int32)
    for x in range(w):
        non_sky = np.flatnonzero(~is_white_sky[:, x])
        skyline[x] = int(non_sky[0]) if len(non_sky) > 0 else int(h * 0.40)
    y_idx = np.arange(h, dtype=np.float32)[:, None]
    sky_f = skyline[None, :].astype(np.float32)
    alpha = np.clip((y_idx - sky_f + 1.0) / 2.5, 0.0, 1.0)
    rgb_clean = rgb.copy()
    for x in range(w):
        sy = min(h - 1, skyline[x] + 4)
        sample_col = rgb[sy, x]
        for yy in range(max(0, skyline[x] - 2), min(h, skyline[x] + 3)):
            if rgb[yy, x].min() > 0.82:
                rgb_clean[yy, x] = sample_col
    bottom_t = np.clip((y_idx / float(h) - 0.84) / 0.16, 0.0, 1.0)
    mist_base = np.array([0.835, 0.895, 0.920], dtype=np.float32)[None, None, :]
    rgb_clean = rgb_clean * (1.0 - bottom_t[:, :, None] * 0.72) + mist_base * (bottom_t[:, :, None] * 0.72)
    alpha = np.where(y_idx >= h * 0.78, 1.0, alpha)
    return np.concatenate([rgb_clean, alpha[:, :, None]], axis=2)


def _blend_seam_strip(left_rgba: np.ndarray, right_rgba: np.ndarray, bw: int) -> np.ndarray:
    """Seamlessly stitch two RGBA horizon strips with crisp non-ghostly skyline blending across bw overlap pixels."""
    t = 0.5 * (1.0 - np.cos(np.pi * np.linspace(0.0, 1.0, bw, dtype=np.float32)))[None, :, None]
    out = left_rgba[:, :-bw].copy()
    a1 = left_rgba[:, -bw:, 3:4]
    a2 = right_rgba[:, :bw, 3:4]
    w1 = a1 * (1.0 - t)
    w2 = a2 * t
    wsum = np.maximum(w1 + w2, 1e-5)
    rgb_b = (left_rgba[:, -bw:, :3] * w1 + right_rgba[:, :bw, :3] * w2) / wsum
    a_b = np.clip((a1 * (1.0 - t) + a2 * t - 0.38) * 6.5, 0.0, 1.0)
    seam = np.concatenate([np.where(a_b > 0.01, rgb_b, left_rgba[:, -bw:, :3]), a_b], axis=2)
    return np.concatenate([out, seam, right_rgba[:, bw:]], axis=1)


def build_horizon_mountains():
    # Stitch both unified lineless 3D-game stylized panoramas (A + B) into a single zero-repetition 360-degree horizon!
    target_h = 640
    half_w = 1536
    bw = 128

    def load_strip(path: Path, x0: float, x1: float) -> np.ndarray:
        raw = Image.open(path).convert("RGB")
        rw, rh = raw.size
        cropped = raw.crop((int(rw * x0), int(rh * 0.06), int(rw * x1), int(rh * 0.96)))
        resized = cropped.resize((half_w + bw, target_h), Image.Resampling.LANCZOS)
        return cut_mountain_alpha(np.asarray(resized, dtype=np.float32) / 255.0)

    rgba_a = load_strip(PANO_ARCHIVE_A, 0.04, 0.95)
    rgba_b = load_strip(PANO_ARCHIVE_B, 0.08, 0.91)
    # 1) Stitch A -> B seamlessly in the middle
    ab = _blend_seam_strip(rgba_a, rgba_b, bw)
    # 2) Close the 360 loop: wrap tail of B back onto head of A seamlessly!
    core = ab[:, bw:].copy()
    tail = ab[:, :bw]
    t = 0.5 * (1.0 - np.cos(np.pi * np.linspace(0.0, 1.0, bw, dtype=np.float32)))[None, :, None]
    a1 = core[:, -bw:, 3:4]
    a2 = tail[:, :, 3:4]
    w1 = a1 * (1.0 - t)
    w2 = a2 * t
    wsum = np.maximum(w1 + w2, 1e-5)
    rgb_blend = (core[:, -bw:, :3] * w1 + tail[:, :, :3] * w2) / wsum
    a_blend = np.clip((a1 * (1.0 - t) + a2 * t - 0.38) * 6.5, 0.0, 1.0)
    core[:, -bw:, :3] = np.where(a_blend > 0.01, rgb_blend, core[:, -bw:, :3])
    core[:, -bw:, 3:4] = a_blend

    out_u8 = np.clip(core * 255.0, 0, 255).astype(np.uint8)
    OUT_PANO.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out_u8, mode="RGBA").save(OUT_PANO, optimize=True)
    print(f"Wrote v0.8.6 unified stylized 360 misty mountains: {OUT_PANO} ({core.shape[1]}x{core.shape[0]}, {OUT_PANO.stat().st_size} B)")


def build_cloud_ribbon():
    raw = Image.open(CLOUD_ARCHIVE).convert("RGB")
    tiled = make_seamless_wrap(raw, 2048, 512, 0.16)
    arr = np.asarray(tiled, dtype=np.float32) / 255.0
    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]

    # Soft vertical fade at top & bottom 10% so cloud ribbon never hits hard quad border
    h, w = lum.shape
    y_norm = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    v_fade = np.clip(y_norm / 0.14, 0.0, 1.0) * np.clip((1.0 - y_norm) / 0.14, 0.0, 1.0)
    alpha = np.clip((lum - 0.035) / 0.86, 0.0, 1.0) ** 0.88 * v_fade

    # Luminous sunlit-ivory to soft cool-mist silver tint for authentic Jiangnan mountain cloud sea
    c_shadow = np.array([0.82, 0.89, 0.94], dtype=np.float32)[None, None, :]
    c_bright = np.array([0.99, 0.985, 0.96], dtype=np.float32)[None, None, :]
    rgb = c_shadow * (1.0 - lum[:, :, None]) + c_bright * lum[:, :, None]

    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[:, :, :3] = np.clip(rgb * 255.0, 0, 255).astype(np.uint8)
    rgba[:, :, 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)
    OUT_CLOUD.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, mode="RGBA").save(OUT_CLOUD, optimize=True)
    print(f"Wrote v0.8.6 seamless cloud mist ribbon: {OUT_CLOUD} ({w}x{h}, {OUT_CLOUD.stat().st_size} B)")


if __name__ == "__main__":
    build_horizon_mountains()
    build_cloud_ribbon()
