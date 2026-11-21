"""Generate a 100% solid, opaque-bodied 360-degree seamless Jiangnan mountain panorama (v0.8.2 V81-8).

Eliminates 'ghost mountains' completely: every pixel below the uppermost mountain skyline has alpha=255
(opaque atmospheric haze + 4 layered teal-jade ink mountain ridges); ONLY the sky above the peaks has alpha=0.
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "game/assets/slice/horizon_mountains.png"
W, H = 2048, 512


def _periodic_ridge(u: np.ndarray, freqs_amps_phases: list[tuple[int, float, float]]) -> np.ndarray:
    """Smooth periodic mountain profile over u in [0, 1) with natural ridged peaks."""
    acc = np.zeros_like(u)
    for freq, amp, phase in freqs_amps_phases:
        wave = np.sin(u * 2.0 * math.pi * freq + phase)
        # Blend rounded hills with sharper ridged peaks (1 - |sin|) for authentic Jiangnan karst silhouettes
        ridged = 1.0 - np.abs(np.sin(u * math.pi * freq + phase * 0.7))
        acc += amp * (0.62 * wave + 0.38 * (ridged * 2.0 - 1.0))
    return acc


def main() -> None:
    u = np.linspace(0.0, 1.0, W, endpoint=False)
    # y_norm: 0.0 at top of texture (sky), 1.0 at bottom of texture (valley base)
    y_grid = np.linspace(0.0, 1.0, H)[:, None]

    # 4 layered mountain ranges from farthest alpine crest to nearest lush Jiangnan foothills
    # Values represent the ridge skyline height in y_norm (smaller = taller peak!)
    r_far = 0.35 + _periodic_ridge(u, [
        (3, 0.068, 0.4), (5, 0.044, 1.9), (9, 0.025, 0.8), (15, 0.012, 2.7), (27, 0.005, 1.1),
    ])
    r_midfar = 0.45 + _periodic_ridge(u, [
        (4, 0.056, 2.2), (7, 0.036, 0.5), (12, 0.020, 3.1), (21, 0.009, 0.9), (35, 0.004, 2.4),
    ])
    r_midnear = 0.55 + _periodic_ridge(u, [
        (5, 0.046, 1.1), (9, 0.030, 2.8), (16, 0.016, 0.4), (29, 0.008, 1.7),
    ])
    r_near = 0.65 + _periodic_ridge(u, [
        (6, 0.038, 3.0), (11, 0.024, 1.2), (19, 0.012, 2.5), (33, 0.006, 0.6),
    ])

    # Subtle directional sunlit slope shading (sun from upper-right / SE)
    def slope_shade(ridge: np.ndarray) -> np.ndarray:
        deriv = np.roll(ridge, -2) - np.roll(ridge, 2)
        return np.clip(-deriv * 22.0, -1.0, 1.0)

    rgb = np.zeros((H, W, 3), dtype=np.float32)
    alpha = np.zeros((H, W), dtype=np.float32)

    # Layer specs: (ridge_y, peak_color, valley_mist_color, mist_depth, sun_boost)
    layers = [
        (r_far,     np.array([0.48, 0.64, 0.75]), np.array([0.82, 0.89, 0.94]), 0.30, 0.06),
        (r_midfar,  np.array([0.36, 0.54, 0.63]), np.array([0.78, 0.86, 0.91]), 0.28, 0.08),
        (r_midnear, np.array([0.27, 0.46, 0.48]), np.array([0.74, 0.83, 0.87]), 0.25, 0.10),
        (r_near,    np.array([0.23, 0.41, 0.36]), np.array([0.78, 0.85, 0.87]), 0.22, 0.11),
    ]

    # Subtle fine ridge-face vertical texture so mountains feel painted & rocky, never flat plastic
    u_2d = np.broadcast_to(u[None, :], (H, W))
    grain = (
        0.5 * np.sin(u_2d * 2.0 * math.pi * 64.0 + y_grid * 14.0)
        + 0.3 * np.sin(u_2d * 2.0 * math.pi * 131.0 - y_grid * 22.0)
        + 0.2 * np.cos(u_2d * 2.0 * math.pi * 247.0 + y_grid * 9.0)
    ) * 0.024

    for ridge, c_peak, c_mist, mist_depth, sun_boost in layers:
        r_2d = ridge[None, :]
        # Crisp 2-pixel anti-aliased upper silhouette, 100% SOLID (1.0) everywhere below the ridge!
        cov = np.clip((y_grid - r_2d) * (H * 0.45) + 0.5, 0.0, 1.0)
        depth = np.clip((y_grid - r_2d) / mist_depth, 0.0, 1.0)
        mist_t = depth ** 0.78
        sun = slope_shade(ridge)[None, :] * sun_boost * (1.0 - mist_t * 0.7)
        layer_col = c_peak[None, None, :] * (1.0 - mist_t[:, :, None]) + c_mist[None, None, :] * mist_t[:, :, None]
        # Warm sunlight highlight on sunward ridges, cooler slate shadow on leeward slopes
        layer_col = np.clip(layer_col + sun[:, :, None] * np.array([1.05, 0.98, 0.82])[None, None, :] + grain[:, :, None], 0.0, 1.0)

        # Standard over compositing: each closer mountain solidly occludes the farther mountain behind it!
        rgb = rgb * (1.0 - cov[:, :, None]) + layer_col * cov[:, :, None]
        alpha = np.clip(alpha + cov * (1.0 - alpha), 0.0, 1.0)

    # Guarantee 100% solid opaque lower skirt (y_norm >= 0.72) blending cleanly into horizon mist
    bottom_mist = np.clip((y_grid - 0.74) / 0.24, 0.0, 1.0)
    horizon_mist_col = np.array([0.84, 0.89, 0.92], dtype=np.float32)
    rgb = rgb * (1.0 - bottom_mist[:, :, None] * 0.85) + horizon_mist_col[None, None, :] * (bottom_mist[:, :, None] * 0.85)
    alpha = np.where(y_grid >= 0.72, 1.0, alpha)

    rgba = np.zeros((H, W, 4), dtype=np.uint8)
    rgba[:, :, :3] = np.clip(rgb * 255.0, 0, 255).astype(np.uint8)
    rgba[:, :, 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, mode="RGBA").save(OUT, optimize=True)
    print(f"Wrote solid Jiangnan horizon mountains panorama: {OUT} ({W}x{H})")


if __name__ == "__main__":
    main()
