"""Generate crisp, photorealistic seamless 1024x1024 PBR stone textures for Yanshan Force v0.8.1:
- FB-2: Domain-warped stratified mountain granite / karst rock (granite_rock_albedo/normal/rough.png)
- FB-3: Authentic hand-laid Jiangnan bluestone flagstones (flagstone_albedo/normal/rough.png)
"""
from pathlib import Path
import numpy as np
from PIL import Image

OUT_DIR = Path(__file__).resolve().parent.parent / "game" / "assets" / "slice" / "ink_jiangnan"
SIZE = 1024


def sample_periodic(field: np.ndarray, gx: np.ndarray, gy: np.ndarray) -> np.ndarray:
    """Bilinearly sample a periodic 2D array at floating pixel coordinates (gx, gy)."""
    h, w = field.shape
    x = np.mod(gx, w)
    y = np.mod(gy, h)
    x0 = np.floor(x).astype(np.int32)
    y0 = np.floor(y).astype(np.int32)
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    fx = x - x0
    fy = y - y0
    v00 = field[y0, x0]
    v10 = field[y0, x1]
    v01 = field[y1, x0]
    v11 = field[y1, x1]
    return (v00 * (1.0 - fx) + v10 * fx) * (1.0 - fy) + (v01 * (1.0 - fx) + v11 * fx) * fy


def tileable_fbm(size: int, octaves: list[tuple[int, float]], seed: int) -> np.ndarray:
    """Exact seamless periodic quintic value-noise fBm."""
    rng = np.random.default_rng(seed)
    acc = np.zeros((size, size), dtype=np.float32)
    w_sum = 0.0
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    for freq, amp in octaves:
        grid = rng.random((freq, freq), dtype=np.float32)
        gx = (xx / size) * freq
        gy = (yy / size) * freq
        x0 = np.floor(gx).astype(np.int32) % freq
        y0 = np.floor(gy).astype(np.int32) % freq
        x1 = (x0 + 1) % freq
        y1 = (y0 + 1) % freq
        tx = gx - np.floor(gx)
        ty = gy - np.floor(gy)
        sx = tx * tx * tx * (tx * (tx * 6.0 - 15.0) + 10.0)
        sy = ty * ty * ty * (ty * (ty * 6.0 - 15.0) + 10.0)
        vx0 = grid[y0, x0] * (1.0 - sx) + grid[y0, x1] * sx
        vx1 = grid[y1, x0] * (1.0 - sx) + grid[y1, x1] * sx
        acc += (vx0 * (1.0 - sy) + vx1 * sy) * amp
        w_sum += amp
    return acc / max(w_sum, 1e-6)


def tileable_ridged(size: int, octaves: list[tuple[int, float]], seed: int, power: float = 1.6) -> np.ndarray:
    """Exact seamless periodic ridged multifractal noise for organic rocky strata & ridges."""
    rng = np.random.default_rng(seed)
    acc = np.zeros((size, size), dtype=np.float32)
    w_sum = 0.0
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    for freq, amp in octaves:
        grid = rng.random((freq, freq), dtype=np.float32)
        gx = (xx / size) * freq
        gy = (yy / size) * freq
        x0 = np.floor(gx).astype(np.int32) % freq
        y0 = np.floor(gy).astype(np.int32) % freq
        x1 = (x0 + 1) % freq
        y1 = (y0 + 1) % freq
        tx = gx - np.floor(gx)
        ty = gy - np.floor(gy)
        sx = tx * tx * tx * (tx * (tx * 6.0 - 15.0) + 10.0)
        sy = ty * ty * ty * (ty * (ty * 6.0 - 15.0) + 10.0)
        vx0 = grid[y0, x0] * (1.0 - sx) + grid[y0, x1] * sx
        vx1 = grid[y1, x0] * (1.0 - sx) + grid[y1, x1] * sx
        n = vx0 * (1.0 - sy) + vx1 * sy
        ridge = np.power(np.clip(1.0 - np.abs(n * 2.0 - 1.0), 0.0, 1.0), power)
        acc += ridge * amp
        w_sum += amp
    return acc / max(w_sum, 1e-6)


def height_to_normal(height: np.ndarray, strength: float = 4.0) -> np.ndarray:
    """Periodic Sobel gradient -> Godot tangent-space normal map (R=+X, G=+Y down, B=+Z)."""
    h = height.astype(np.float32)
    hx = (
        np.roll(h, -1, axis=1) * 2.0
        + np.roll(np.roll(h, -1, axis=1), -1, axis=0)
        + np.roll(np.roll(h, -1, axis=1), 1, axis=0)
        - np.roll(h, 1, axis=1) * 2.0
        - np.roll(np.roll(h, 1, axis=1), -1, axis=0)
        - np.roll(np.roll(h, 1, axis=1), 1, axis=0)
    ) / 8.0
    hy = (
        np.roll(h, -1, axis=0) * 2.0
        + np.roll(np.roll(h, -1, axis=0), -1, axis=1)
        + np.roll(np.roll(h, -1, axis=0), 1, axis=1)
        - np.roll(h, 1, axis=0) * 2.0
        - np.roll(np.roll(h, 1, axis=0), -1, axis=1)
        - np.roll(np.roll(h, 1, axis=0), 1, axis=1)
    ) / 8.0
    nx = -hx * strength
    ny = -hy * strength
    nz = np.ones_like(h)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx * inv_len * 0.5 + 0.5, ny * inv_len * 0.5 + 0.5, nz * inv_len * 0.5 + 0.5], axis=-1)
    return np.clip(nrm * 255.0, 0, 255).astype(np.uint8)


def save_rgb(arr01: np.ndarray, path: Path) -> None:
    Image.fromarray(np.clip(arr01 * 255.0, 0, 255).astype(np.uint8), mode="RGB").save(path, optimize=True)


def save_gray(arr01: np.ndarray, path: Path) -> None:
    Image.fromarray(np.clip(arr01 * 255.0, 0, 255).astype(np.uint8), mode="L").save(path, optimize=True)


def build_granite_rock() -> None:
    """Organic, domain-warped stratified Jiangnan cliff rock & crystalline granite (FB-2)."""
    s = SIZE
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)

    # Strong organic domain warp eliminates any artificial grid / polygonal artifacts
    wx1 = (tileable_fbm(s, [(4, 0.55), (8, 0.30), (16, 0.15)], seed=501) - 0.5) * 145.0
    wy1 = (tileable_fbm(s, [(4, 0.55), (8, 0.30), (16, 0.15)], seed=502) - 0.5) * 145.0

    # Broad cliff blockiness + organic fracture ridges (sampled with domain warp)
    raw_ridge_lg = tileable_ridged(s, [(4, 0.42), (8, 0.32), (16, 0.18), (32, 0.08)], seed=503, power=1.8)
    raw_ridge_md = tileable_ridged(s, [(12, 0.38), (24, 0.32), (48, 0.20), (96, 0.10)], seed=504, power=1.5)
    ridge_lg = sample_periodic(raw_ridge_lg, xx + wx1, yy + wy1)
    ridge_md = sample_periodic(raw_ridge_md, xx - wy1 * 0.55, yy + wx1 * 0.55)

    # Natural sedimentary bedding ledges broken irregularly by rock weathering (zero continuous sine ribbons!)
    strata_raw = tileable_fbm(s, [(4, 0.45), (8, 0.35), (16, 0.20)], seed=505)
    strata_break = sample_periodic(tileable_fbm(s, [(6, 0.50), (14, 0.32), (28, 0.18)], seed=511), xx - wx1 * 0.4, yy + wy1 * 0.4)
    strata_phase = ((yy + xx * 0.22) / s) * 7.0 * np.pi * 2.0 + (strata_raw - 0.5) * 11.0 + (wy1 / s) * 16.0
    strata_ledge = 0.5 + 0.5 * np.sin(strata_phase)
    # Broken short erosion pockets along weak strata shelves
    strata_seam = np.power(np.clip(1.0 - np.abs(np.sin(strata_phase * 0.5)) * 5.2, 0.0, 1.0), 2.2) * np.clip((strata_break - 0.46) * 3.0, 0.0, 1.0)

    # Sharp jagged natural rock crevices (from high-contrast ridged fractures broken by macro noise)
    fissure_field = sample_periodic(
        tileable_ridged(s, [(6, 0.46), (12, 0.34), (24, 0.20)], seed=506, power=3.6),
        xx + wx1 * 0.85,
        yy + wy1 * 0.85,
    )
    deep_cracks = np.clip((fissure_field - 0.52) * 3.4, 0.0, 1.0) * np.clip((strata_raw - 0.22) * 2.0, 0.25, 1.0)
    cracks = np.clip(deep_cracks * 0.90 + strata_seam * 0.65, 0.0, 1.0)

    # Crisp high-frequency granite mineral pitting & crystalline grain (reads razor-sharp up close!)
    grain_med = tileable_fbm(s, [(32, 0.36), (64, 0.32), (128, 0.20), (256, 0.12)], seed=507)
    rng = np.random.default_rng(508)
    quartz_fleck = np.clip(rng.normal(0.5, 0.18, (s, s)).astype(np.float32), 0.0, 1.0)
    biotite_pits = (rng.random((s, s)) < 0.08).astype(np.float32) * 0.18

    # Combined natural cliff heightfield
    height = (
        0.34 * ridge_lg
        + 0.24 * ridge_md
        + 0.16 * strata_ledge
        + 0.20 * grain_med
        + 0.08 * quartz_fleck
        - 0.36 * cracks
        - biotite_pits * 0.22
    )
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)

    # Natural Jiangnan mountain granite / limestone color palette
    color_macro = sample_periodic(tileable_fbm(s, [(4, 0.5), (8, 0.3), (16, 0.2)], seed=509), xx + wx1 * 0.5, yy + wy1 * 0.5)
    cool_granite = np.array([0.42, 0.46, 0.48], dtype=np.float32)
    warm_ochre_stone = np.array([0.56, 0.53, 0.46], dtype=np.float32)
    sunlit_edge = np.array([0.70, 0.71, 0.68], dtype=np.float32)
    deep_fissure = np.array([0.15, 0.18, 0.19], dtype=np.float32)
    mineral_vein = np.array([0.77, 0.78, 0.74], dtype=np.float32)
    dry_lichen = np.array([0.34, 0.41, 0.28], dtype=np.float32)

    albedo = cool_granite * (1.0 - color_macro[..., None]) + warm_ochre_stone * color_macro[..., None]

    # Protruding rock edges catch lighter bleached mineral tone
    protrude = np.clip((height - 0.54) * 2.1, 0.0, 1.0)[..., None]
    albedo = albedo * (1.0 - protrude * 0.44) + sunlit_edge * (protrude * 0.44)

    # Subtle natural white calcite / quartz mineral veins
    vein_f = sample_periodic(tileable_ridged(s, [(8, 0.6), (16, 0.4)], seed=510, power=5.5), xx - wx1 * 0.6, yy + wy1 * 0.7)
    vein_mask = np.clip((vein_f - 0.68) * 3.8, 0.0, 0.45)[..., None]
    albedo = albedo * (1.0 - vein_mask) + mineral_vein * vein_mask

    # Crisp granite salt-and-pepper mineral crystals
    crystal_mod = (grain_med - 0.5) * 0.24 + (quartz_fleck - 0.5) * 0.14 - biotite_pits * 0.45
    albedo = np.clip(albedo + crystal_mod[..., None], 0.0, 1.0)

    # Sparse mountain lichen tucked in weathered hollows
    lichen_m = np.clip((color_macro - 0.66) * 3.0, 0.0, 0.28) * (1.0 - protrude[..., 0] * 0.6)
    albedo = albedo * (1.0 - lichen_m[..., None]) + dry_lichen * lichen_m[..., None]

    # Deep dark occlusion inside jagged crevices & bedding seams
    albedo = albedo * (1.0 - cracks[..., None] * 0.74) + deep_fissure * (cracks[..., None] * 0.74)

    rough = np.clip(0.86 - protrude[..., 0] * 0.16 + cracks * 0.12 + (grain_med - 0.5) * 0.10, 0.58, 0.97)
    normal = height_to_normal(height, strength=5.6)

    save_rgb(albedo, OUT_DIR / "granite_rock_albedo.png")
    Image.fromarray(normal, mode="RGB").save(OUT_DIR / "granite_rock_normal.png", optimize=True)
    save_gray(rough, OUT_DIR / "granite_rock_rough.png")
    print("Generated natural granite_rock_{albedo,normal,rough}.png")


def build_bluestone_flagstone() -> None:
    """Authentic smooth-worn yet crisp hand-laid Jiangnan bluestone flagstones (FB-3)."""
    s = SIZE
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)

    # Natural hand-cut edge irregularity
    wobble_x = (tileable_fbm(s, [(8, 0.55), (16, 0.30), (32, 0.15)], seed=601) - 0.5) * 11.0
    wobble_y = (tileable_fbm(s, [(8, 0.55), (16, 0.30), (32, 0.15)], seed=602) - 0.5) * 9.5
    wx = (xx + wobble_x) % s
    wy = (yy + wobble_y) % s

    row_bounds = [0.0, 240.0, 512.0, 760.0, 1024.0]
    row_splits = [
        [0.0, 315.0, 675.0, 1024.0],
        [0.0, 185.0, 545.0, 845.0, 1024.0],
        [0.0, 385.0, 715.0, 1024.0],
        [0.0, 235.0, 595.0, 875.0, 1024.0],
    ]

    rng = np.random.default_rng(605)
    slab_dist = np.full((s, s), 999.0, dtype=np.float32)
    slab_tint = np.zeros((s, s), dtype=np.float32)
    slab_hue = np.zeros((s, s), dtype=np.float32)
    slab_h_off = np.zeros((s, s), dtype=np.float32)
    slab_seed_x = np.zeros((s, s), dtype=np.float32)
    slab_seed_y = np.zeros((s, s), dtype=np.float32)

    for r_i in range(len(row_bounds) - 1):
        y0, y1 = row_bounds[r_i], row_bounds[r_i + 1]
        in_row = (wy >= y0) & (wy < y1)
        splits = row_splits[r_i]
        for c_i in range(len(splits) - 1):
            x0, x1 = splits[c_i], splits[c_i + 1]
            mask = in_row & (wx >= x0) & (wx < x1)
            dx_edge = np.minimum(wx - x0, x1 - wx)
            dy_edge = np.minimum(wy - y0, y1 - wy)
            d_edge = np.minimum(dx_edge, dy_edge)
            slab_dist = np.where(mask, d_edge, slab_dist)
            slab_tint = np.where(mask, float(rng.uniform(0.0, 1.0)), slab_tint)
            slab_hue = np.where(mask, float(rng.uniform(0.0, 1.0)), slab_hue)
            slab_h_off = np.where(mask, float(rng.uniform(-0.045, 0.045)), slab_h_off)
            slab_seed_x = np.where(mask, float(rng.uniform(0.0, 512.0)), slab_seed_x)
            slab_seed_y = np.where(mask, float(rng.uniform(0.0, 512.0)), slab_seed_y)

    # Organic stone clouding, fine limestone pitting & calcite mineral veins (NO corduroy stripes!)
    warp_a = (tileable_fbm(s, [(6, 0.6), (12, 0.4)], seed=608) - 0.5) * 90.0
    warp_b = (tileable_fbm(s, [(6, 0.6), (12, 0.4)], seed=609) - 0.5) * 90.0
    base_cloud = tileable_fbm(s, [(8, 0.35), (16, 0.30), (32, 0.22), (64, 0.13)], seed=610)
    stone_cloud = sample_periodic(base_cloud, xx + slab_seed_x + warp_a * 0.4, yy + slab_seed_y + warp_b * 0.4)
    fine_grain = tileable_fbm(s, [(32, 0.30), (64, 0.32), (128, 0.24), (256, 0.14)], seed=611)
    micro_grain = np.clip(rng.normal(0.5, 0.11, (s, s)).astype(np.float32), 0.0, 1.0)

    # Natural calcite veins & tiny weathered hairline fissures inside individual flagstones
    vein_src = tileable_ridged(s, [(6, 0.55), (12, 0.30), (24, 0.15)], seed=612, power=5.2)
    calcite_vein = sample_periodic(vein_src, xx + slab_seed_x + warp_a, yy + slab_seed_y + warp_b)
    calcite_mask = np.clip((calcite_vein - 0.64) * 3.2, 0.0, 0.52)

    # Very subtle micro-pits in weathered limestone
    pits = np.clip((0.28 - fine_grain) * 3.8, 0.0, 1.0)

    # Crisp recessed mortar joints + natural chipped bevel edge
    edge_chip = (fine_grain - 0.5) * 5.2 + (stone_cloud - 0.5) * 3.5
    eff_d = slab_dist + edge_chip
    mortar_mask = np.clip(1.0 - (eff_d - 4.5) / 5.5, 0.0, 1.0)
    bevel = np.clip((eff_d - 5.5) / 16.0, 0.0, 1.0)
    bevel_s = bevel * bevel * (3.0 - 2.0 * bevel)
    center_wear = np.clip((eff_d - 16.0) / 56.0, 0.0, 1.0)

    # Subtle irregular stone surface height (flat & walkable in the center, chiseled drop at edges)
    height = (
        (0.14 + 0.12 * fine_grain) * mortar_mask
        + (0.64 + 0.22 * bevel_s + slab_h_off + (stone_cloud - 0.5) * 0.11 + (fine_grain - 0.5) * 0.075 + (micro_grain - 0.5) * 0.032 - pits * 0.08) * (1.0 - mortar_mask)
    )
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)

    # Authentic Jiangnan Qing-Shi-Ban ('江南青石板') palette: cool slate blue-gray + warm mineral ash + worn sheen
    blue_slate = np.array([0.36, 0.42, 0.46], dtype=np.float32)
    charcoal_slate = np.array([0.29, 0.34, 0.37], dtype=np.float32)
    warm_ash = np.array([0.48, 0.49, 0.46], dtype=np.float32)
    worn_silver = np.array([0.58, 0.62, 0.63], dtype=np.float32)
    calcite_col = np.array([0.74, 0.76, 0.74], dtype=np.float32)
    mortar_soil = np.array([0.16, 0.17, 0.14], dtype=np.float32)
    mortar_moss = np.array([0.20, 0.31, 0.16], dtype=np.float32)

    base_stone = charcoal_slate * (1.0 - slab_tint[..., None]) + blue_slate * slab_tint[..., None]
    base_stone = base_stone * (1.0 - slab_hue[..., None] * 0.48) + warm_ash * (slab_hue[..., None] * 0.48)

    # Foot-worn smoother pale center & chipped lighter arris bevel rim
    base_stone = base_stone * (1.0 - center_wear[..., None] * 0.24) + worn_silver * (center_wear[..., None] * 0.24)
    edge_catch = np.clip(bevel_s * (1.0 - bevel_s) * 4.0, 0.0, 1.0)[..., None]
    base_stone = base_stone * (1.0 - edge_catch * 0.32) + worn_silver * (edge_catch * 0.32)

    # Organic stone clouding + calcite veining + dark weathered limestone pores
    base_stone = base_stone * (1.0 - calcite_mask[..., None] * 0.34) + calcite_col * (calcite_mask[..., None] * 0.34)
    mod = (stone_cloud - 0.5) * 0.18 + (fine_grain - 0.5) * 0.12 + (micro_grain - 0.5) * 0.07 - pits * 0.14
    base_stone = np.clip(base_stone + mod[..., None], 0.0, 1.0)

    # Damp mortar & subtle natural moss creeping strictly inside seams
    moss_var = np.clip((base_cloud - 0.38) * 2.2, 0.0, 1.0)[..., None]
    joint_col = mortar_soil * (1.0 - moss_var) + mortar_moss * moss_var
    moss_edge = np.clip(1.0 - (eff_d - 6.0) / 13.0, 0.0, 1.0) * moss_var[..., 0] * 0.34

    albedo = base_stone * (1.0 - mortar_mask[..., None]) + joint_col * mortar_mask[..., None]
    albedo = albedo * (1.0 - moss_edge[..., None]) + mortar_moss * moss_edge[..., None]

    # Roughness: worn smooth bluestone center (0.44), textured border (0.74), earthy mortar (0.94)
    rough = np.clip(
        (0.74 - center_wear * 0.28 + pits * 0.15 + (fine_grain - 0.5) * 0.08) * (1.0 - mortar_mask) + 0.94 * mortar_mask,
        0.38,
        0.96,
    )

    normal = height_to_normal(height, strength=4.8)

    save_rgb(albedo, OUT_DIR / "flagstone_albedo.png")
    Image.fromarray(normal, mode="RGB").save(OUT_DIR / "flagstone_normal.png", optimize=True)
    save_gray(rough, OUT_DIR / "flagstone_rough.png")
    print("Generated natural flagstone_{albedo,normal,rough}.png")


if __name__ == "__main__":
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    build_granite_rock()
    build_bluestone_flagstone()
    print("Done! All v0.8.1 photorealistic stone textures generated.")
