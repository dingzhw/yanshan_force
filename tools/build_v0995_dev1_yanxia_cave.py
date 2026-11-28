"""v0.9.9.6_dev3 Grand Mountain-Embedded Yanxia Ancient Cave ('烟霞古洞 · 山腹巨窟') Builder.

Upgrades in v0.9.9.6_dev3:
1. Solid non-floating cave floor + beveled bluestone entrance threshold ramp plunging cleanly
   into the Bamboo Maze forecourt ground (ZERO hovering carpet slab or floating floor shadow).
2. Authentic ancestor rock-carved petroglyphs ('《烟山耕读》' & '《烟霞古洞志》'):
   - Curved 20x14 meshes conformed point-by-point onto the real displaced cavern wall (NO picture
     frame, NO protruding box slab, NO white paper background!).
   - Procedurally composites actual dark cave limestone texture underneath incised calligraphy/mural
     strokes with weathered ancient mineral pigment, Sobel-derived 3D chisel Normal Map, and
     organic feathered irregular stone edges so carvings truly live IN the cave rock wall.
3. 100% watertight cave portal & entrance flanks:
   - Arch-matched exterior mountain opening welded cleanly into a thick closed 3D karst stone
     portal collar with grounded layered flank buttresses (ZERO sky cracks, ZERO knife-edge gaps,
     ZERO portal plaque punching down through the tunnel ceiling!).
4. Graceful natural Jiangnan karst hillside silhouette:
   - Lowered & softened from an abrupt 22.8m steep volcanic mound overflowing the west fence into
     a natural 16.6m bamboo-clad mossy-green karst hill ridge harmonized with surrounding meadow.
5. Bonus visual polish:
   - Softer airy skylight sunbeams (never milky walls blocking the Warden or zig-zagging over floor).
   - NW hall pillar shifted cleanly clear of the Jade Spring Pool rim + deeper translucent jade water.
"""
from __future__ import annotations

import json
import math
import random
import struct
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

REPO_ROOT = Path(__file__).resolve().parents[1]
SLICE_DIR = REPO_ROOT / "game" / "assets" / "slice"
OUT_GLB = SLICE_DIR / "v0995_yanxia_grand_cave.glb"
V062_GLB = SLICE_DIR / "v062_bamboo_cave.glb"


# ===========================================================================
# 1. Analytical Cave Spine (Blender coords: +X East, +Y North/Deeper, +Z Up)
#    Note: Godot z_local == -y_blender!
#    Portal mouth at y_blender = -7.0  (Godot z_local = +7.0, world z = -93.0)
#    Deep back cliff at y_blender = +34.8 (Godot z_local = -34.8, world z = -134.8)
# ===========================================================================
SPINE_STATIONS = [
    # (y_b,   cx,    hw,    ch)
    (-7.00,  0.00,  2.12,  3.92),  # 0. Mountain cliff cave mouth (welded cleanly into portal collar)
    (-3.20, -0.18,  2.02,  4.05),  # 1. Narrow throat entry
    ( 0.50, -0.55,  2.18,  4.25),  # 2. Throat gentle west bend
    ( 4.50, -1.40,  3.20,  5.35),  # 3. Throat widening
    ( 8.20, -2.25,  5.40,  7.40),  # 4. Mid-gallery approach
    (10.50, -2.65,  6.65,  8.55),  # 5. Mid-gallery beneath skylight ('洞顶空窗')
    (14.50, -3.25,  9.20, 10.60),  # 6. Cathedral opening arch
    (19.00, -3.50, 11.45, 12.10),  # 7. Grand Hall south expanse
    (23.50, -3.50, 11.85, 12.55),  # 8. Grand Hall widest heart (23.7m wide x 12.55m tall)
    (28.00, -3.50, 10.40, 12.00),  # 9. Grand Hall north expanse (Jade Spring Pool alcove)
    (31.50, -3.50,  6.90, 11.40),  # 10. Taper into '一线天' sanctum
    (34.80, -3.50,  4.35, 12.80),  # 11. Deepest north bedrock cliff behind Dimensional Rift Wall
]

FLOOR_Z = 0.026

# 4 sculpted stalagmite cover columns in Grand Hall outer ring (NW pillar cleanly clear of Jade Spring Pool!)
HALL_PILLARS = [
    (-9.6, 17.6, 1.02, 1.15),   # SW pillar
    ( 2.8, 17.8, 1.00, 1.12),   # SE pillar
    (-10.8, 22.8, 1.04, 1.16),  # NW pillar (shifted south clear of (-9.2, 28.4) pool!)
    ( 3.1, 26.4, 1.02, 1.14),   # NE pillar
]

# Two true sky openings piercing straight through the mountain ridge:
SKY_WINDOW_CTR = (-2.65, 10.50)
SKY_WINDOW_RAD = (2.35, 2.05)  # oval radius (rx, ry)

YIXIANTIAN_X = -3.50
YIXIANTIAN_HW = 1.05
YIXIANTIAN_Y0 = 29.8
YIXIANTIAN_Y1 = 34.1


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / max(1e-6, edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def sample_spine(y: float) -> tuple[float, float, float]:
    """Smooth Hermite-blended interpolation of (cx, hw, ch) along cavern depth y."""
    if y <= SPINE_STATIONS[0][0]:
        return SPINE_STATIONS[0][1], SPINE_STATIONS[0][2], SPINE_STATIONS[0][3]
    if y >= SPINE_STATIONS[-1][0]:
        return SPINE_STATIONS[-1][1], SPINE_STATIONS[-1][2], SPINE_STATIONS[-1][3]
    for i in range(len(SPINE_STATIONS) - 1):
        y0, cx0, hw0, ch0 = SPINE_STATIONS[i]
        y1, cx1, hw1, ch1 = SPINE_STATIONS[i + 1]
        if y0 <= y <= y1:
            t = (y - y0) / max(1e-6, y1 - y0)
            s = t * t * (3.0 - 2.0 * t)
            return (
                cx0 + (cx1 - cx0) * s,
                hw0 + (hw1 - hw0) * s,
                ch0 + (ch1 - ch0) * s,
            )
    return SPINE_STATIONS[-1][1], SPINE_STATIONS[-1][2], SPINE_STATIONS[-1][3]


def rock_noise(x: float, y: float, z: float) -> float:
    """Deterministic multi-octave organic limestone relief displacement."""
    n1 = math.sin(x * 0.42 + y * 0.31 + z * 0.27) * math.cos(y * 0.23 - z * 0.35)
    n2 = math.sin(x * 1.15 - y * 0.88 + z * 0.94) * 0.42
    n3 = math.cos(x * 2.1 + y * 1.9 - z * 1.7) * 0.18
    return n1 + n2 + n3


def in_sky_window(x: float, y: float, pad: float = 0.0) -> bool:
    dx = (x - SKY_WINDOW_CTR[0]) / max(0.2, SKY_WINDOW_RAD[0] + pad)
    dy = (y - SKY_WINDOW_CTR[1]) / max(0.2, SKY_WINDOW_RAD[1] + pad)
    return (dx * dx + dy * dy) < 1.0


def in_yixiantian(x: float, y: float, pad: float = 0.0) -> bool:
    return (
        abs(x - YIXIANTIAN_X) < (YIXIANTIAN_HW + pad)
        and (YIXIANTIAN_Y0 - pad) < y < (YIXIANTIAN_Y1 + pad)
    )


def in_any_skylight(x: float, y: float, pad: float = 0.0) -> bool:
    return in_sky_window(x, y, pad) or in_yixiantian(x, y, pad)


def mountain_surface_z(x: float, y: float) -> float:
    """Graceful natural Jiangnan karst hill massif (16.4m crest, gentle slopes) covering 100% of the cavern
    without bulging abruptly over the western fence or rice paddies!"""
    cx, hw, ch = sample_spine(y)
    # 1) Soft sweeping Jiangnan bamboo-covered hill ridge centered over Grand Hall (-3.5, 22.0)
    dx_peak = (x - (-3.2)) / 24.0
    dy_peak = (y - 21.5) / 28.5
    r2_main = dx_peak * dx_peak + dy_peak * dy_peak
    h_main = 16.4 * math.exp(-r2_main * 1.18)

    # Gentle west shoulder tapering cleanly near the west boundary (does NOT jut abruptly over paddies!)
    dx_w = (x - (-13.5)) / 14.5
    dy_w = (y - 14.5) / 23.0
    h_west = 13.8 * math.exp(-(dx_w * dx_w + dy_w * dy_w) * 1.30)

    # Natural south cliff brow directly above the cave entrance (y = -7.0..+5.0)
    dx_f = (x - (-0.8)) / 12.0
    dy_f = (y - 1.2) / 11.5
    h_front = 10.6 * math.exp(-(dx_f * dx_f + dy_f * dy_f) * 1.15)

    # North crest framing '一线天' gracefully
    dx_n = (x - (-3.5)) / 16.0
    dy_n = (y - 32.5) / 15.5
    h_north = 15.6 * math.exp(-(dx_n * dx_n + dy_n * dy_n) * 1.25)

    h = max(h_main, h_west, h_front, h_north)

    # Guarantee generous solid rock overburden (>= +2.5m) over EVERY point of the interior cavern!
    if -7.4 <= y <= 35.8:
        inside_x = 1.0 - smoothstep(hw + 0.5, hw + 6.8, abs(x - cx))
        inside_y = smoothstep(-8.2, -6.4, y) * (1.0 - smoothstep(34.6, 39.5, y))
        min_cover = ch + 2.6 + 1.2 * inside_x
        h = max(h, min_cover * inside_x * inside_y)

    # Restrained organic karst contour undulation (no harsh spikey crags)
    crag = rock_noise(x * 0.44, y * 0.44, h * 0.28) * 0.72
    strata = math.sin(h * 0.95 + x * 0.12) * 0.22
    h += crag + strata

    # Wide gentle grassy-mossy skirts tapering smoothly below terrain (-3.6m) for seamless hillside blending!
    skirt_w = smoothstep(-22.5, -14.8, x)
    skirt_e = 1.0 - smoothstep(11.5, 22.0, x)
    skirt_n = 1.0 - smoothstep(36.5, 47.0, y)
    skirt_s = smoothstep(-9.2, -6.5, y)
    skirt = skirt_w * skirt_e * skirt_n * skirt_s
    return -3.6 + (h + 3.6) * skirt


# ===========================================================================
# 2. PBR Material & Procedural Rock-Carved Petroglyph Texture Helpers
# ===========================================================================
def load_packed_img(path: Path, colorspace: str = "sRGB", max_size: int = 1024, name_override: str | None = None):
    if not path.exists():
        return None
    im = bpy.data.images.load(str(path), check_existing=False)
    if name_override:
        im.name = name_override
    im.colorspace_settings.name = colorspace
    w, h = int(im.size[0]), int(im.size[1])
    if max(w, h) > max_size and w > 0 and h > 0:
        sc = max_size / float(max(w, h))
        im.scale(max(64, int(round(w * sc))), max(64, int(round(h * sc))))
    im.pack()
    return im


def img_to_np(im: bpy.types.Image, target_wh: tuple[int, int]) -> np.ndarray:
    """Copy a Blender Image resized cleanly to target_wh as float32 RGBA (H, W, 4)."""
    tw, th = target_wh
    cp = im.copy()
    if int(cp.size[0]) != tw or int(cp.size[1]) != th:
        cp.scale(tw, th)
    arr = np.empty(tw * th * 4, dtype=np.float32)
    cp.pixels.foreach_get(arr)
    bpy.data.images.remove(cp)
    return arr.reshape((th, tw, 4))


def np_to_packed_png(name: str, rgba: np.ndarray, colorspace: str = "sRGB") -> bpy.types.Image:
    """Create a fresh packed 8-bit PNG Blender Image from float32 (H, W, 4) array."""
    th, tw, _ = rgba.shape
    im = bpy.data.images.new(name=name, width=tw, height=th, alpha=True, float_buffer=False)
    im.file_format = "PNG"
    im.colorspace_settings.name = colorspace
    im.pixels.foreach_set(np.clip(rgba, 0.0, 1.0).astype(np.float32).ravel())
    im.pack()
    return im


def synthesize_rock_carved_textures(
    art_img: bpy.types.Image,
    cliff_diff_img: bpy.types.Image,
    cliff_norm_img: bpy.types.Image,
    name_prefix: str,
    pigment_rgb: tuple[float, float, float],
    groove_darken: float = 0.78,
    pigment_mix: float = 0.45,
    size_wh: tuple[int, int] = (1024, 512),
) -> tuple[bpy.types.Image, bpy.types.Image]:
    """Synthesize TRUE transparent incised rock-carved petroglyph decal directly onto the living curved cave wall!

    The source v062 carving art ALREADY has a clean transparent background (alpha == 0 outside strokes).
    By extracting crisp carved grooves strictly from (alpha & dark-line core) and keeping ALL non-carved
    area 100% transparent (alpha = 0), the real 3D Cave_Interior_Rock wall shows directly between every
    character & mountain line — ZERO paper, ZERO rectangular frame, ZERO color seam, ZERO blotches!
    """
    tw, th = size_wh
    art = img_to_np(art_img, (tw, th))
    rock = img_to_np(cliff_diff_img, (tw, th))
    rnorm = img_to_np(cliff_norm_img, (tw, th))

    # Match Cave_Interior_Rock Mat_GrandCaveWall tint (0.42, 0.48, 0.52) for recessed stone groove interior
    wall_tint = np.array([0.42, 0.48, 0.52], dtype=np.float32)
    base_stone = rock[:, :, :3] * wall_tint[None, None, :]

    art_alpha = art[:, :, 3]
    art_lum = art[:, :, 0] * 0.299 + art[:, :, 1] * 0.587 + art[:, :, 2] * 0.114
    # Suppress soft outer drop-shadow halo (alpha < 0.32) and isolate ONLY the crisp dark carved grooves!
    # Also handle any non-transparent fallback gracefully via dark-core weighting.
    if float(np.percentile(art_alpha, 10)) < 0.20:
        stroke_core = np.clip((art_alpha - 0.34) / 0.48, 0.0, 1.0) * np.clip((0.78 - art_lum) / 0.45, 0.35, 1.0)
    else:
        bg_lum = float(np.percentile(art_lum, 75))
        stroke_core = np.clip((bg_lum - art_lum) / max(0.12, bg_lum * 0.35), 0.0, 1.0)

    # Gently thicken 1px so delicate calligraphy & mountain ridges read crisply at 3-5m cave distance
    stroke_dil = np.maximum.reduce([
        stroke_core,
        np.roll(stroke_core, 1, axis=0),
        np.roll(stroke_core, -1, axis=0),
        np.roll(stroke_core, 1, axis=1),
        np.roll(stroke_core, -1, axis=1),
    ])
    stroke = np.clip(np.maximum(stroke_core, stroke_dil * 0.68), 0.0, 1.0)

    # Crisp chiseled pale-limestone upper bevel catchlight along every incised edge (looks physically carved into stone!)
    stroke_up = np.roll(stroke, -2, axis=0)
    stroke_dn = np.roll(stroke, 2, axis=0)
    stroke_lt = np.roll(stroke, -2, axis=1)
    chisel_rim = np.clip(np.maximum(stroke_up, stroke_lt * 0.80) - stroke, 0.0, 1.0)
    chisel_shadow = np.clip(stroke - stroke_dn, 0.0, 1.0)

    # Subtle weathered dust halo right around the carved strokes (never fills empty wall!)
    halo = np.maximum.reduce([
        np.roll(stroke, 3, axis=0), np.roll(stroke, -3, axis=0),
        np.roll(stroke, 3, axis=1), np.roll(stroke, -3, axis=1),
    ]) * 0.22

    # Groove color: deeply recessed dark cave rock + aged ochre/mineral pigment trace; rim: pale chiseled limestone!
    pigment = np.array(pigment_rgb, dtype=np.float32)[None, None, :]
    groove_col = base_stone * (1.0 - groove_darken) * (1.0 - pigment_mix) + pigment * pigment_mix
    rim_col = np.clip(base_stone * 2.55 + np.array([0.28, 0.26, 0.22], dtype=np.float32)[None, None, :], 0.0, 1.0)

    # Blend groove interior and pale chiseled bevel smoothly
    w_groove = stroke[:, :, None]
    w_rim = (chisel_rim * 0.92)[:, :, None]
    w_halo = (halo * (1.0 - stroke))[:, :, None]
    w_tot = np.maximum(w_groove + w_rim + w_halo, 1e-5)
    rgb = (
        groove_col * w_groove
        + rim_col * w_rim
        + (base_stone * 1.25) * w_halo
    ) / w_tot
    rgb *= (1.0 - chisel_shadow[:, :, None] * 0.28)

    # Alpha is STRICTLY non-zero ONLY on the carved grooves & chiseled bevel rims — 0.0 everywhere else!
    out_alpha = np.clip(stroke * 0.94 + chisel_rim * 0.82 + halo * 0.30, 0.0, 0.96)

    out_diff = np.empty((th, tw, 4), dtype=np.float32)
    out_diff[:, :, :3] = np.clip(rgb, 0.0, 1.0)
    out_diff[:, :, 3] = out_alpha

    # Synthesize crisp 3D chiseled Normal Map over the cave cliff's own rock normal!
    gx = (np.roll(stroke, -1, axis=1) - np.roll(stroke, 1, axis=1)) * 4.5
    gy = (np.roll(stroke, -1, axis=0) - np.roll(stroke, 1, axis=0)) * 4.5
    rn_x = rnorm[:, :, 0] * 2.0 - 1.0
    rn_y = rnorm[:, :, 1] * 2.0 - 1.0
    rn_z = np.maximum(0.15, rnorm[:, :, 2] * 2.0 - 1.0)
    nx = rn_x * 0.50 + gx
    ny = rn_y * 0.50 + gy
    nz = rn_z
    nlen = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    out_norm = np.empty((th, tw, 4), dtype=np.float32)
    out_norm[:, :, 0] = (nx / nlen) * 0.5 + 0.5
    out_norm[:, :, 1] = (ny / nlen) * 0.5 + 0.5
    out_norm[:, :, 2] = (nz / nlen) * 0.5 + 0.5
    out_norm[:, :, 3] = 1.0

    im_diff = np_to_packed_png(f"{name_prefix}_CarvedDiff", out_diff, "sRGB")
    im_norm = np_to_packed_png(f"{name_prefix}_CarvedNorm", out_norm, "Non-Color")
    return im_diff, im_norm


def make_pbr_mat(
    name: str,
    color_rgba: tuple[float, float, float, float],
    roughness: float = 0.85,
    metallic: float = 0.0,
    albedo_img=None,
    normal_img=None,
    rough_img=None,
    normal_scale: float = 0.85,
    emission_rgba: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
    alpha: float = 1.0,
    use_img_alpha: bool = False,
    double_sided: bool = False,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = not double_sided
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    bsdf.inputs["Base Color"].default_value = color_rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if alpha < 0.999 and not use_img_alpha:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"

    if albedo_img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = albedo_img
        if color_rgba != (1.0, 1.0, 1.0, 1.0):
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = color_rgba
            nt.links.new(tex.outputs["Color"], mix.inputs[6])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if use_img_alpha:
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            if hasattr(mat, "blend_method"):
                mat.blend_method = "BLEND"

    if rough_img is not None:
        rt = nt.nodes.new("ShaderNodeTexImage")
        rt.image = rough_img
        nt.links.new(rt.outputs["Color"], bsdf.inputs["Roughness"])

    if normal_img is not None:
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = normal_img
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = normal_scale
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    if emission_rgba is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = emission_rgba
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def apply_triplanar_uv(bm: bmesh.types.BMesh, scale: float = 0.22):
    """Assign clean non-degenerate box/triplanar UV coordinates on single canonical 'UVMap'."""
    uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    bm.faces.ensure_lookup_table()
    bm.normal_update()
    for f in bm.faces:
        f.normal_update()
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for lp in f.loops:
            v = lp.vert.co
            if az >= ax and az >= ay:
                lp[uv_layer].uv = (v.x * scale, v.y * scale)
            elif ax >= ay:
                lp[uv_layer].uv = (v.y * scale, v.z * scale)
            else:
                lp[uv_layer].uv = (v.x * scale, v.z * scale)


def orient_face_toward(f: bmesh.types.BMFace, target_pt: Vector):
    """Guarantee face normal points toward target_pt (inward for cave shells/chimneys)."""
    f.normal_update()
    if f.normal.dot(target_pt - f.calc_center_median()) < 0.0:
        f.normal_flip()
        f.normal_update()


def orient_face_away(f: bmesh.types.BMFace, ref_dir: Vector):
    """Guarantee face normal aligns positively with ref_dir (outward/upward for mountain)."""
    f.normal_update()
    if f.normal.dot(ref_dir) < 0.0:
        f.normal_flip()
        f.normal_update()


def bm_to_object(name: str, bm: bmesh.types.BMesh, mats: list[bpy.types.Material], parent: bpy.types.Object, uv_scale: float | None = 0.22, smooth: bool = True) -> bpy.types.Object:
    bm.normal_update()
    if uv_scale is not None:
        apply_triplanar_uv(bm, scale=uv_scale)
    for f in bm.faces:
        f.smooth = smooth
    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    me.validate(verbose=False)
    for m in mats:
        me.materials.append(m)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    return obj


def extract_v062_textures() -> dict[str, bpy.types.Image]:
    """Import v062_bamboo_cave.glb briefly to harvest the exact carved mural/chronicle/plaque art."""
    wanted = {
        "plaque_yanxia_cave": "sRGB",
        "mural_yanxia_ancients": "sRGB",
        "mural_yanxia_normal": "Non-Color",
        "inscription_cave_chronicle": "sRGB",
        "chronicle_normal": "Non-Color",
    }
    found: dict[str, bpy.types.Image] = {}
    if not V062_GLB.exists():
        return found
    before_objs = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(V062_GLB))
    for im in bpy.data.images:
        for k, cs in wanted.items():
            if k in im.name and k not in found:
                cp = im.copy()
                cp.name = f"CaveArt_{k}"
                cp.colorspace_settings.name = cs
                cp.pack()
                found[k] = cp
    for o in list(bpy.data.objects):
        if o not in before_objs:
            bpy.data.objects.remove(o, do_unlink=True)
    return found


# ===========================================================================
# 3. Geometry Builders
# ===========================================================================
def build_interior_cavern(parent: bpy.types.Object, mat_wall, mat_floor, mat_stalactite, mat_chimney) -> tuple[bpy.types.Object, list[tuple[Vector, Vector]]]:
    """Build organic 41.8m vaulted subterranean cave + grounded wet limestone floor + entrance stone threshold
    ramp plunging cleanly into forecourt soil + 2 skylight chimneys + BVH-snapped stalactites!
    """
    bm = bmesh.new()
    flora_anchors: list[tuple[Vector, Vector]] = []

    n_rings = 54
    y_min, y_max = -7.00, 34.80
    ys = [y_min + (y_max - y_min) * (i / float(n_rings - 1)) for i in range(n_rings)]

    n_arc = 24
    ring_verts: list[list[bmesh.types.BMVert]] = []
    floor_east: list[bmesh.types.BMVert] = []
    floor_west: list[bmesh.types.BMVert] = []

    for ri, y in enumerate(ys):
        cx, hw, ch = sample_spine(y)
        is_portal = (ri == 0)
        is_back = (ri == n_rings - 1)
        row: list[bmesh.types.BMVert] = []
        for ai in range(n_arc + 1):
            t = ai / float(n_arc)  # 0 = East base, 0.5 = crown, 1.0 = West base
            ang = t * math.pi
            ca = math.cos(ang)
            sa = math.sin(ang)
            rx = hw * math.copysign(abs(ca) ** 0.86, ca)
            rz = ch * (sa ** 0.78)
            px = cx + rx
            pz = FLOOR_Z + rz

            if not is_portal and not is_back:
                n_val = rock_noise(px * 0.58, y * 0.45, pz * 0.58)
                amp = 0.22 if hw < 4.0 else 0.52
                # Smooth fade near mouth (y < -5.5) so entrance arch welds tightly with portal collar
                mouth_fade = smoothstep(-7.0, -4.8, y)
                edge_fade = smoothstep(0.0, 0.14, min(t, 1.0 - t)) * mouth_fade
                disp = (0.16 + n_val * 0.46) * amp * edge_fade
                px += ca * disp
                pz += sa * disp
                if pz < FLOOR_Z + 0.04 and (ai != 0 and ai != n_arc):
                    pz = FLOOR_Z + 0.04

                if ri % 3 == 1 and ri >= 3 and ri <= n_rings - 3 and ai in (3, 5, 7, 17, 19, 21):
                    inward = Vector((-ca, 0.0, -sa * 0.35)).normalized()
                    flora_anchors.append((Vector((px, y, pz)), inward))

            v = bm.verts.new((px, y, pz))
            row.append(v)
        ring_verts.append(row)
        floor_east.append(row[0])
        floor_west.append(row[-1])

    uv_layer = bm.loops.layers.uv.new("UVMap")
    for ri in range(n_rings - 1):
        r0 = ring_verts[ri]
        r1 = ring_verts[ri + 1]
        y0_r, y1_r = ys[ri], ys[ri + 1]
        cx_m, hw_m, ch_m = sample_spine((y0_r + y1_r) * 0.5)
        inward_spine = Vector((cx_m, (y0_r + y1_r) * 0.5, FLOOR_Z + ch_m * 0.36))
        arc_scale = max(1.8, (hw_m + ch_m) * 0.24)
        for ai in range(n_arc):
            v00, v01 = r0[ai], r0[ai + 1]
            v11, v10 = r1[ai + 1], r1[ai]
            cen = (v00.co + v01.co + v11.co + v10.co) * 0.25
            if cen.z > 5.0 and in_any_skylight(cen.x, cen.y, pad=-0.05):
                continue
            try:
                f = bm.faces.new((v00, v01, v11, v10))
                orient_face_toward(f, inward_spine)
                f.material_index = 0
                u0 = (ai / float(n_arc)) * arc_scale
                u1 = ((ai + 1) / float(n_arc)) * arc_scale
                v0 = y0_r * 0.22
                v1 = y1_r * 0.22
                uv_map = {v00: (u0, v0), v01: (u1, v0), v11: (u1, v1), v10: (u0, v1)}
                for lp in f.loops:
                    lp[uv_layer].uv = uv_map[lp.vert]
            except ValueError:
                pass

    # Build flat walkable wet limestone floor strip-by-strip (strictly +Z normals)
    n_fcols = 8
    floor_grid: list[list[bmesh.types.BMVert]] = []
    for ri in range(n_rings):
        ve = floor_east[ri]
        vw = floor_west[ri]
        frow = [vw]
        for ci in range(1, n_fcols):
            u = ci / float(n_fcols)
            co = vw.co.lerp(ve.co, u)
            co.z = FLOOR_Z
            frow.append(bm.verts.new(co))
        frow.append(ve)
        floor_grid.append(frow)
    for ri in range(n_rings - 1):
        for ci in range(n_fcols):
            try:
                f = bm.faces.new((
                    floor_grid[ri][ci],
                    floor_grid[ri][ci + 1],
                    floor_grid[ri + 1][ci + 1],
                    floor_grid[ri + 1][ci],
                ))
                orient_face_away(f, Vector((0.0, 0.0, 1.0)))
                f.material_index = 1
                for lp in f.loops:
                    lp[uv_layer].uv = (lp.vert.co.x * 0.26, lp.vert.co.y * 0.26)
            except ValueError:
                pass

    # Solid grounded stone threshold ramp at cave mouth (y = -7.00 -> -8.45, tapering cleanly from +0.026m
    # smoothly underground to -0.22m so ZERO floating carpet edge or dark shadow seam EVER appears!)
    ramp_specs = [
        (-7.42, 0.014, 1.04),
        (-7.95, -0.045, 1.10),
        (-8.55, -0.24, 1.16),
    ]
    ramp_rows: list[list[bmesh.types.BMVert]] = [floor_grid[0]]
    hw0_r = SPINE_STATIONS[0][2]
    for ry, rz, wscale in ramp_specs:
        rrow = []
        for ci in range(n_fcols + 1):
            u = ci / float(n_fcols)
            rx = (-hw0_r * wscale) + (2.0 * hw0_r * wscale) * u
            # Slightly lower outer corners into soil so side edges never poke above grass!
            corner_drop = -0.10 * (abs(u - 0.5) * 2.0) ** 3
            rrow.append(bm.verts.new((rx, ry, rz + corner_drop)))
        ramp_rows.append(rrow)
    for rri in range(len(ramp_rows) - 1):
        for ci in range(n_fcols):
            try:
                f = bm.faces.new((
                    ramp_rows[rri + 1][ci],
                    ramp_rows[rri + 1][ci + 1],
                    ramp_rows[rri][ci + 1],
                    ramp_rows[rri][ci],
                ))
                orient_face_away(f, Vector((0.0, -0.2, 1.0)))
                f.material_index = 1
                for lp in f.loops:
                    lp[uv_layer].uv = (lp.vert.co.x * 0.26, lp.vert.co.y * 0.26)
            except ValueError:
                pass

    # Deep vertical foundation skirt around interior walls (z = FLOOR_Z -> -0.60) so floor is 100% solid bedrock
    for side_row in (floor_east, floor_west):
        skirt_bot = [bm.verts.new((v.co.x, v.co.y, -0.60)) for v in side_row]
        for ri in range(n_rings - 1):
            try:
                f = bm.faces.new((side_row[ri], side_row[ri + 1], skirt_bot[ri + 1], skirt_bot[ri]))
                f.material_index = 0
                for lp in f.loops:
                    lp[uv_layer].uv = (lp.vert.co.y * 0.24, lp.vert.co.z * 0.24)
            except ValueError:
                pass

    # Seal North Back Cliff cleanly at y = y_max (+34.80)
    back_ring = ring_verts[-1]
    back_cx = SPINE_STATIONS[-1][1]
    back_center = bm.verts.new((back_cx, y_max + 0.35, FLOOR_Z + 5.2))
    back_inward = Vector((back_cx, y_max - 8.0, FLOOR_Z + 4.0))
    for ai in range(n_arc):
        try:
            f = bm.faces.new((back_ring[ai], back_ring[ai + 1], back_center))
            orient_face_toward(f, back_inward)
            f.material_index = 0
            for lp in f.loops:
                lp[uv_layer].uv = (lp.vert.co.x * 0.22, lp.vert.co.z * 0.22)
        except ValueError:
            pass
    back_fl = floor_grid[-1]
    for ci in range(n_fcols):
        try:
            f = bm.faces.new((back_fl[ci], back_center, back_fl[ci + 1]))
            orient_face_toward(f, back_inward)
            f.material_index = 0
            for lp in f.loops:
                lp[uv_layer].uv = (lp.vert.co.x * 0.22, lp.vert.co.z * 0.22)
        except ValueError:
            pass

    # 1) Mid-Gallery Skylight Chimney ('洞顶空窗')
    n_cseg = 24
    c_levels = 7
    chim_rings: list[list[bmesh.types.BMVert]] = []
    for li in range(c_levels):
        u = li / float(c_levels - 1)
        row = []
        for si in range(n_cseg):
            ang = (si / float(n_cseg)) * math.tau
            flare = 1.0 + 0.22 * (1.0 - u) + 0.14 * u
            px = SKY_WINDOW_CTR[0] + math.cos(ang) * SKY_WINDOW_RAD[0] * flare
            py = SKY_WINDOW_CTR[1] + math.sin(ang) * SKY_WINDOW_RAD[1] * flare
            z_bot = sample_spine(py)[2] * 0.86
            z_top = mountain_surface_z(px, py) + 0.55
            pz = z_bot + (z_top - z_bot) * u
            jagged = rock_noise(px * 1.4, py * 1.4, pz * 0.9) * 0.22
            px += math.cos(ang) * jagged
            py += math.sin(ang) * jagged
            row.append(bm.verts.new((px, py, pz)))
        chim_rings.append(row)
    for li in range(c_levels - 1):
        for si in range(n_cseg):
            sn = (si + 1) % n_cseg
            try:
                v00, v01 = chim_rings[li][si], chim_rings[li][sn]
                v11, v10 = chim_rings[li + 1][sn], chim_rings[li + 1][si]
                f = bm.faces.new((v00, v10, v11, v01))
                cen = f.calc_center_median()
                orient_face_toward(f, Vector((SKY_WINDOW_CTR[0], SKY_WINDOW_CTR[1], cen.z)))
                f.material_index = 3
                u0 = (si / float(n_cseg)) * 4.0
                u1 = ((si + 1) / float(n_cseg)) * 4.0
                uv_map = {v00: (u0, v00.co.z * 0.24), v01: (u1, v01.co.z * 0.24), v11: (u1, v11.co.z * 0.24), v10: (u0, v10.co.z * 0.24)}
                for lp in f.loops:
                    lp[uv_layer].uv = uv_map[lp.vert]
            except ValueError:
                pass

    # 2) Deep Sanctum '一线天' Vertical Chasm Sleeve
    chasm_pts = []
    for sy in [YIXIANTIAN_Y0, 31.2, 32.6, YIXIANTIAN_Y1]:
        chasm_pts.append((YIXIANTIAN_X - YIXIANTIAN_HW - 0.12, sy))
    for sx in [YIXIANTIAN_X - 0.4, YIXIANTIAN_X + 0.4]:
        chasm_pts.append((sx, YIXIANTIAN_Y1 + 0.15))
    for sy in [YIXIANTIAN_Y1, 32.6, 31.2, YIXIANTIAN_Y0]:
        chasm_pts.append((YIXIANTIAN_X + YIXIANTIAN_HW + 0.12, sy))
    for sx in [YIXIANTIAN_X + 0.4, YIXIANTIAN_X - 0.4]:
        chasm_pts.append((sx, YIXIANTIAN_Y0 - 0.15))
    n_cp = len(chasm_pts)
    chasm_rings = []
    for li in range(6):
        u = li / 5.0
        row = []
        for px0, py0 in chasm_pts:
            squeeze = 1.0 - 0.34 * u
            px = YIXIANTIAN_X + (px0 - YIXIANTIAN_X) * squeeze
            py = py0
            z_bot = 10.4
            z_top = mountain_surface_z(px, py) + 0.70
            pz = z_bot + (z_top - z_bot) * u
            px += rock_noise(px * 1.6, py * 1.2, pz * 0.7) * 0.15
            row.append(bm.verts.new((px, py, pz)))
        chasm_rings.append(row)
    yxt_cy = 0.5 * (YIXIANTIAN_Y0 + YIXIANTIAN_Y1)
    for li in range(5):
        for si in range(n_cp):
            sn = (si + 1) % n_cp
            try:
                v00, v01 = chasm_rings[li][si], chasm_rings[li][sn]
                v11, v10 = chasm_rings[li + 1][sn], chasm_rings[li + 1][si]
                f = bm.faces.new((v00, v10, v11, v01))
                cen = f.calc_center_median()
                orient_face_toward(f, Vector((YIXIANTIAN_X, yxt_cy, cen.z)))
                f.material_index = 3
                u0 = (si / float(n_cp)) * 4.5
                u1 = ((si + 1) / float(n_cp)) * 4.5
                uv_map = {v00: (u0, v00.co.z * 0.24), v01: (u1, v01.co.z * 0.24), v11: (u1, v11.co.z * 0.24), v10: (u0, v10.co.z * 0.24)}
                for lp in f.loops:
                    lp[uv_layer].uv = uv_map[lp.vert]
            except ValueError:
                pass

    # BVH-snapped hanging limestone stalactites (+0.22m embedded into ceiling rock!)
    bm.faces.ensure_lookup_table()
    bvh_ceiling = BVHTree.FromBMesh(bm)
    rng = random.Random(20260995)
    for _ in range(36):
        sy = rng.uniform(5.5, 31.0)
        cx, hw, ch = sample_spine(sy)
        sx = cx + rng.uniform(-hw * 0.68, hw * 0.68)
        if in_any_skylight(sx, sy, pad=1.2):
            continue
        hit_loc, _, _, _ = bvh_ceiling.ray_cast(Vector((sx, sy, FLOOR_Z + 1.2)), Vector((0.0, 0.0, 1.0)), 22.0)
        if hit_loc is None:
            continue
        roof_z = hit_loc.z + 0.22
        slen = rng.uniform(1.1, 2.7)
        if roof_z - slen < 5.0:
            continue
        rad = rng.uniform(0.16, 0.38)
        m = Matrix.Translation((sx, sy, roof_z - slen * 0.50))
        res = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=True, segments=7,
            radius1=0.03, radius2=rad, depth=slen, matrix=m,
        )
        for v in res["verts"]:
            for f in v.link_faces:
                f.material_index = 2
                for lp in f.loops:
                    d = lp.vert.co - Vector((sx, sy, roof_z))
                    lp[uv_layer].uv = (math.atan2(d.y, d.x) * 0.45, lp.vert.co.z * 0.45)

    obj = bm_to_object("Cave_Interior_Rock", bm, [mat_wall, mat_floor, mat_stalactite, mat_chimney], parent, uv_scale=None, smooth=True)
    return obj, flora_anchors


def build_exterior_mountain(parent: bpy.types.Object, mat_cliff, mat_grass) -> bpy.types.Object:
    """Build the graceful 16.4m bamboo-forested Jiangnan karst hill massif hiding 100% of Yanxia Cave,
    WITH a 100% WATERTIGHT CLOSED 3D STONE PORTAL COLLAR welded flush to the interior throat (y = -7.00)!
    Zero sky cracks, zero paper-thin knife edges, zero hollow clip-through gaps!
    """
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    nx, ny = 60, 64
    x0, x1 = -22.5, 22.0
    y0, y1 = -9.2, 47.0

    cx0, hw0, ch0 = sample_spine(-7.00)

    grid: list[list[bmesh.types.BMVert]] = []
    for j in range(ny):
        y = y0 + (y1 - y0) * (j / float(ny - 1))
        row = []
        for i in range(nx):
            x = x0 + (x1 - x0) * (i / float(nx - 1))
            z = mountain_surface_z(x, y)
            # Smoothly arch the cliff brow directly ABOVE the cave doorway (z >= 6.0m above y = -6.8..-3.5)
            if -7.8 <= y <= -3.5 and abs(x - cx0) < 4.4:
                brow_u = 1.0 - smoothstep(2.0, 4.4, abs(x - cx0))
                y_u = smoothstep(-7.8, -6.2, y)
                z = max(z, 6.2 * brow_u * y_u + z * (1.0 - brow_u * y_u))
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)

    for j in range(ny - 1):
        for i in range(nx - 1):
            v00 = grid[j][i]
            v10 = grid[j][i + 1]
            v11 = grid[j + 1][i + 1]
            v01 = grid[j + 1][i]
            cen = (v00.co + v10.co + v11.co + v01.co) * 0.25
            if in_any_skylight(cen.x, cen.y, pad=-0.10):
                continue
            # Strictly open ONLY inside the walkable cave doorway opening (y < -5.8 and |x| < 2.18)
            # so solid mountain slope stays 100% closed right up to the thick portal stone collar!
            if cen.y <= -5.85 and abs(cen.x - cx0) <= 2.18:
                continue
            try:
                f = bm.faces.new((v00, v10, v11, v01))
                orient_face_away(f, Vector((0.0, 0.0, 1.0)))
                # Generous lush Jiangnan meadow grass on upper & gentle slopes so hill merges naturally into landscape!
                is_grass = (f.normal.z > 0.48) and (cen.z > 1.8) and (cen.y > -5.5)
                f.material_index = 1 if is_grass else 0
                for lp in f.loops:
                    lp[uv_layer].uv = (lp.vert.co.x * 0.14, lp.vert.co.y * 0.14)
            except ValueError:
                pass

    # -----------------------------------------------------------------------
    # 100% WATERTIGHT CLOSED 3D STONE PORTAL COLLAR & CHEEK WALLS!
    # 4 rings bridging cleanly from interior cave throat (y = -6.20, -7.00)
    # -> sculpted karst front arch lip (y = -8.05) -> wide deep flank anchor (y = -4.20)
    # -> grounded skirts plunging down to z = -2.40m so ZERO gap or sky crack exists anywhere!
    # -----------------------------------------------------------------------
    n_arch = 24
    ring_throat_in: list[bmesh.types.BMVert] = []  # Inside tunnel overlap at y = -6.15
    ring_mouth_in: list[bmesh.types.BMVert] = []   # Exact inner mouth edge at y = -7.02
    ring_front_lip: list[bmesh.types.BMVert] = []  # Sculpted karst outer arch front at y = -8.15
    ring_mtn_weld: list[bmesh.types.BMVert] = []   # Wide outer rock mantle welded deep into mountain at y = -4.20

    for ai in range(n_arch + 1):
        t = ai / float(n_arch)
        ang = t * math.pi
        ca, sa = math.cos(ang), math.sin(ang)

        # Exact match to Cave_Interior_Rock portal ring (slightly tucked +0.03m outward so zero z-fight)
        ix = cx0 + (hw0 + 0.03) * math.copysign(abs(ca) ** 0.86, ca)
        iz = FLOOR_Z + (ch0 + 0.03) * (sa ** 0.78)
        if ai == 0 or ai == n_arch:
            iz = -0.85

        # Wide solid outer karst arch surround (spans |x| up to 5.4m, height up to 6.85m!)
        ox = cx0 + (hw0 + 3.10) * math.copysign(abs(ca) ** 0.80, ca)
        oz = FLOOR_Z + (ch0 + 2.85) * (sa ** 0.74)
        if ai == 0 or ai == n_arch:
            oz = -2.20
        elif ai == 1 or ai == n_arch - 1:
            oz = min(oz, 0.35)

        # Deep back mantle plunging firmly INTO the solid mountain hill (|x| up to 6.6m)
        bx = cx0 + (hw0 + 4.30) * math.copysign(abs(ca) ** 0.78, ca)
        bz_mtn = mountain_surface_z(bx, -4.20)
        bz = max(oz + 1.0, bz_mtn + 0.35) if (ai > 0 and ai < n_arch) else -2.40

        j_front = rock_noise(ox * 0.9, -8.0, oz * 0.9) * 0.24 * smoothstep(0.0, 0.15, min(t, 1.0 - t))
        ring_throat_in.append(bm.verts.new((ix, -6.15, iz)))
        ring_mouth_in.append(bm.verts.new((ix, -7.02, iz)))
        ring_front_lip.append(bm.verts.new((ox, -8.10 + j_front, oz)))
        ring_mtn_weld.append(bm.verts.new((bx, -4.10, bz)))

    for ai in range(n_arch):
        u0 = (ai / float(n_arch)) * 4.0
        u1 = ((ai + 1) / float(n_arch)) * 4.0
        # 1) Inner tunnel transition collar (seals tunnel interior seamlessly to mouth!)
        try:
            f0 = bm.faces.new((ring_throat_in[ai], ring_throat_in[ai + 1], ring_mouth_in[ai + 1], ring_mouth_in[ai]))
            orient_face_toward(f0, Vector((cx0, -6.6, FLOOR_Z + 1.5)))
            f0.material_index = 0
            uv0 = {ring_throat_in[ai]: (u0, 0.0), ring_throat_in[ai + 1]: (u1, 0.0), ring_mouth_in[ai + 1]: (u1, 0.45), ring_mouth_in[ai]: (u0, 0.45)}
            for lp in f0.loops:
                lp[uv_layer].uv = uv0[lp.vert]
        except ValueError:
            pass
        # 2) Thick sculpted front cliff arch face (facing SOUTH into forecourt!)
        try:
            f1 = bm.faces.new((ring_front_lip[ai], ring_mouth_in[ai], ring_mouth_in[ai + 1], ring_front_lip[ai + 1]))
            orient_face_away(f1, Vector((0.0, -1.0, 0.18)))
            f1.material_index = 0
            uv1 = {ring_front_lip[ai]: (u0, 0.0), ring_mouth_in[ai]: (u0, 1.15), ring_mouth_in[ai + 1]: (u1, 1.15), ring_front_lip[ai + 1]: (u1, 0.0)}
            for lp in f1.loops:
                lp[uv_layer].uv = uv1[lp.vert]
        except ValueError:
            pass
        # 3) Deep rock mantle sealing front arch lip solidly BACK into the mountain ridge!
        try:
            f2 = bm.faces.new((ring_front_lip[ai], ring_front_lip[ai + 1], ring_mtn_weld[ai + 1], ring_mtn_weld[ai]))
            cen2 = f2.calc_center_median()
            out2 = Vector((cen2.x - cx0, -0.45, max(0.2, cen2.z - 1.0))).normalized()
            orient_face_away(f2, out2)
            f2.material_index = 0
            uv2 = {ring_front_lip[ai]: (u0, 0.0), ring_front_lip[ai + 1]: (u1, 0.0), ring_mtn_weld[ai + 1]: (u1, 1.45), ring_mtn_weld[ai]: (u0, 1.45)}
            for lp in f2.loops:
                lp[uv_layer].uv = uv2[lp.vert]
        except ValueError:
            pass

    # 4) Close BOTH bottom ground ends (East ai=0 & West ai=n_arch) solidly underground so ZERO open shell!
    for end_i, out_x in ((0, 1.0), (n_arch, -1.0)):
        try:
            fe = bm.faces.new((ring_throat_in[end_i], ring_mouth_in[end_i], ring_front_lip[end_i], ring_mtn_weld[end_i]))
            orient_face_away(fe, Vector((out_x, 0.0, -0.5)))
            fe.material_index = 0
            for lp in fe.loops:
                lp[uv_layer].uv = (lp.vert.co.y * 0.25, lp.vert.co.z * 0.25)
        except ValueError:
            pass

    # Grounded, rugged layered karst cliff shoulders hugging BOTH flanks of the cave mouth
    # (NO tall egg-shaped floating thumbs — low, broad, deeply rooted bedrock outcrops!)
    for side in (-1.0, 1.0):
        for dx, dy, dz, sx, sy, sz in [
            (side * 3.85, -7.65, 1.65, 1.95, 2.05, 3.30),
            (side * 6.20, -7.10, 2.25, 2.55, 2.40, 4.10),
            (side * 8.60, -5.80, 2.75, 2.85, 2.80, 4.65),
            (side * 2.15, -6.70, 5.65, 2.55, 1.45, 1.40),  # sturdy rock brow flush with arch lip, never overhanging mouth!
        ]:
            res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
            for v in res["verts"]:
                p = v.co
                n = rock_noise(p.x * 2.1 + dx, p.y * 2.1 + dy, p.z * 2.1 + dz) * 0.14
                # Flatten bottom slightly and root firmly underground
                vx = dx + p.x * sx * (1.0 + n)
                vy = dy + p.y * sy * (1.0 + n)
                vz = dz + p.z * sz * (1.0 + n)
                # Keep rock strictly OUTSIDE the walkable cave mouth arch (|x| >= 2.22 when z < 4.05)!
                if vz < 4.10 and abs(vx - cx0) < 2.24:
                    vx = cx0 + side * 2.24
                v.co = Vector((vx, vy, vz))
            for v in res["verts"]:
                for f in v.link_faces:
                    f.material_index = 0
                    for lp in f.loops:
                        d = lp.vert.co - Vector((dx, dy, dz))
                        u = (math.atan2(d.y, d.x) / math.tau + 0.5) * 2.2
                        v_uv = (d.z / max(0.5, sz) * 0.5 + 0.5) * 2.2
                        lp[uv_layer].uv = (u, v_uv)

    return bm_to_object("Cave_Exterior_Mountain", bm, [mat_cliff, mat_grass], parent, uv_scale=None, smooth=True)


def build_hall_pillars(parent: bpy.types.Object, mat_wall, mat_stalactite) -> tuple[bpy.types.Object, list[tuple[Vector, Vector]]]:
    """Build 4 sculpted floor-to-ceiling stalagmite cover columns with seamless cylindrical UVs."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    pillar_flora: list[tuple[Vector, Vector]] = []
    for px, py, r_base, r_top in HALL_PILLARS:
        cx, hw, ch = sample_spine(py)
        frac_x = abs(px - cx) / max(1.0, hw)
        roof_z = FLOOR_Z + ch * (max(0.25, 1.0 - frac_x * frac_x) ** 0.42) + 0.9
        n_segs = 14
        n_h = 10
        rings = []
        for hi in range(n_h):
            u = hi / float(n_h - 1)
            pz = FLOOR_Z - 0.15 + (roof_z - FLOOR_Z + 0.15) * u
            waist = 1.0 + 0.48 * ((1.0 - u) ** 2.6) + 0.52 * (u ** 2.6) - 0.18 * math.sin(u * math.pi)
            rad = (r_base * (1.0 - u) + r_top * u) * waist
            row = []
            for si in range(n_segs):
                ang = (si / float(n_segs)) * math.tau
                vx = px + math.cos(ang) * rad
                vy = py + math.sin(ang) * rad
                disp = rock_noise(vx * 1.3, vy * 1.3, pz * 0.9) * 0.14
                vx += math.cos(ang) * disp
                vy += math.sin(ang) * disp
                row.append(bm.verts.new((vx, vy, pz)))
            rings.append(row)
            if hi in (2, 4):
                to_cen = Vector((cx - px, 23.0 - py, 0.0)).normalized()
                pillar_flora.append((Vector((px, py, pz)) + to_cen * (rad + 0.04), to_cen))
        for hi in range(n_h - 1):
            for si in range(n_segs):
                sn = (si + 1) % n_segs
                try:
                    v00, v01 = rings[hi][si], rings[hi][sn]
                    v11, v10 = rings[hi + 1][sn], rings[hi + 1][si]
                    f = bm.faces.new((v00, v01, v11, v10))
                    cen = f.calc_center_median()
                    orient_face_away(f, Vector((cen.x - px, cen.y - py, 0.0)))
                    f.material_index = 0 if hi < n_h - 3 else 1
                    u0 = (si / float(n_segs)) * 2.4
                    u1 = ((si + 1) / float(n_segs)) * 2.4
                    uv_m = {v00: (u0, v00.co.z * 0.28), v01: (u1, v01.co.z * 0.28), v11: (u1, v11.co.z * 0.28), v10: (u0, v10.co.z * 0.28)}
                    for lp in f.loops:
                        lp[uv_layer].uv = uv_m[lp.vert]
                except ValueError:
                    pass
    return bm_to_object("Cave_Pillars", bm, [mat_wall, mat_stalactite], parent, uv_scale=None, smooth=True), pillar_flora


def build_jade_spring_pool(parent: bpy.types.Object, mat_water, mat_rim) -> bpy.types.Object:
    """Sculpt serene Jade Spring Pool ('洞中寒潭') in the West-North alcove of the Grand Hall."""
    bm = bmesh.new()
    pcx, pcy = -9.2, 28.4
    rx, ry = 3.2, 2.6
    n_seg = 24
    rim_in, rim_out, rim_top = [], [], []
    for si in range(n_seg):
        ang = (si / float(n_seg)) * math.tau
        ca, sa = math.cos(ang), math.sin(ang)
        wob = 1.0 + 0.08 * math.sin(ang * 3.0 + 0.5)
        ri_x, ri_y = pcx + ca * rx * wob, pcy + sa * ry * wob
        ro_x, ro_y = pcx + ca * (rx + 0.55) * wob, pcy + sa * (ry + 0.55) * wob
        rt_x, rt_y = pcx + ca * (rx + 0.24) * wob, pcy + sa * (ry + 0.24) * wob
        rim_in.append(bm.verts.new((ri_x, ri_y, FLOOR_Z + 0.06)))
        rim_top.append(bm.verts.new((rt_x, rt_y, FLOOR_Z + 0.34 + 0.06 * math.sin(ang * 5.0))))
        rim_out.append(bm.verts.new((ro_x, ro_y, FLOOR_Z - 0.02)))
    for si in range(n_seg):
        sn = (si + 1) % n_seg
        for quad in [
            (rim_in[si], rim_top[si], rim_top[sn], rim_in[sn]),
            (rim_top[si], rim_out[si], rim_out[sn], rim_top[sn]),
        ]:
            try:
                f = bm.faces.new(quad)
                f.material_index = 1
            except ValueError:
                pass
    w_cen = bm.verts.new((pcx, pcy, FLOOR_Z + 0.19))
    w_ring = []
    for si in range(n_seg):
        ang = (si / float(n_seg)) * math.tau
        wob = 1.0 + 0.08 * math.sin(ang * 3.0 + 0.5)
        w_ring.append(bm.verts.new((pcx + math.cos(ang) * (rx + 0.08) * wob, pcy + math.sin(ang) * (ry + 0.08) * wob, FLOOR_Z + 0.19)))
    for si in range(n_seg):
        sn = (si + 1) % n_seg
        try:
            f = bm.faces.new((w_cen, w_ring[si], w_ring[sn]))
            f.material_index = 0
        except ValueError:
            pass
    return bm_to_object("Cave_Spring_Pool", bm, [mat_water, mat_rim], parent, uv_scale=0.45, smooth=True)


def build_bioluminescent_flora(
    parent: bpy.types.Object,
    anchors: list[tuple[Vector, Vector]],
    interior_bvh: BVHTree,
    mat_vine,
    mat_berry_gold,
    mat_berry_cyan,
    mat_fungi_cyan,
    mat_fungi_teal,
    mat_moss_jade,
) -> bpy.types.Object:
    bm = bmesh.new()
    rng = random.Random(20261125)

    def add_shelf_cluster(pos: Vector, inward: Vector, scale: float, use_teal: bool):
        n_dir = Vector((inward.x, inward.y, 0.0))
        if n_dir.length < 0.01:
            n_dir = Vector((1.0, 0.0, 0.0))
        n_dir.normalize()
        side = Vector((-n_dir.y, n_dir.x, 0.0))
        mat_idx = 4 if use_teal else 3
        for _ in range(rng.randint(4, 7)):
            s = scale * rng.uniform(0.55, 1.18)
            off = side * rng.uniform(-0.42, 0.42) * scale + Vector((0, 0, rng.uniform(-0.34, 0.34) * scale)) + n_dir * rng.uniform(0.02, 0.14)
            c = pos + off
            m = Matrix.Translation(c + n_dir * (0.14 * s))
            yaw = math.atan2(n_dir.y, n_dir.x)
            m = m @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Scale(0.24 * s, 4, (1, 0, 0)) @ Matrix.Scale(0.32 * s, 4, (0, 1, 0)) @ Matrix.Scale(0.065 * s, 4, (0, 0, 1))
            res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=m)
            for v in res["verts"]:
                for f in v.link_faces:
                    f.material_index = mat_idx

    def add_glow_moss_fern(pos: Vector, inward: Vector, scale: float):
        n_dir = Vector((inward.x, inward.y, 0.0))
        if n_dir.length < 0.01:
            n_dir = Vector((1.0, 0.0, 0.0))
        n_dir.normalize()
        side = Vector((-n_dir.y, n_dir.x, 0.0))
        for _ in range(3):
            off = side * rng.uniform(-0.35, 0.35) * scale + Vector((0, 0, rng.uniform(-0.22, 0.22) * scale))
            m = Matrix.Translation(pos + off) @ Matrix.Scale(0.28 * scale, 4, (1, 0, 0)) @ Matrix.Scale(0.28 * scale, 4, (0, 1, 0)) @ Matrix.Scale(0.16 * scale, 4, (0, 0, 1))
            res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=m)
            for v in res["verts"]:
                for f in v.link_faces:
                    f.material_index = 5
        for fi in range(5):
            ang = (fi - 2.0) * 0.42
            fdir = (n_dir * math.cos(ang) + side * math.sin(ang) + Vector((0, 0, 0.35 + 0.15 * abs(fi - 2)))).normalized()
            fside = fdir.cross(Vector((0, 0, 1)))
            if fside.length < 0.01:
                fside = side
            fside.normalize()
            blen = 0.52 * scale * rng.uniform(0.8, 1.2)
            bw = 0.095 * scale
            v0 = bm.verts.new(pos + fside * (-bw * 0.4))
            v1 = bm.verts.new(pos + fside * (bw * 0.4))
            mid = pos + fdir * (blen * 0.55) + Vector((0, 0, 0.06 * scale))
            v2 = bm.verts.new(mid + fside * bw)
            v3 = bm.verts.new(mid - fside * bw)
            tip = pos + fdir * blen - Vector((0, 0, 0.06 * scale))
            v4 = bm.verts.new(tip)
            for tri in [(v0, v1, v2, v3), (v3, v2, v4)]:
                try:
                    f = bm.faces.new(tri)
                    f.material_index = 5
                except ValueError:
                    pass

    def add_hanging_glow_vine(top_pos: Vector, length: float, gold_berries: bool):
        n_segs = max(4, int(length / 0.48))
        prev = top_pos
        sway_x = rng.uniform(-0.18, 0.18)
        sway_y = rng.uniform(-0.18, 0.18)
        b_mat = 1 if gold_berries else 2
        for si in range(1, n_segs + 1):
            u = si / float(n_segs)
            cur = top_pos + Vector((
                math.sin(u * math.pi * 1.4) * sway_x,
                math.cos(u * math.pi * 1.2) * sway_y,
                -length * u,
            ))
            mid = (prev + cur) * 0.5
            seg_v = cur - prev
            slen = max(0.05, seg_v.length)
            quat = Vector((0, 0, 1)).rotation_difference(seg_v.normalized())
            m = Matrix.Translation(mid) @ quat.to_matrix().to_4x4()
            res = bmesh.ops.create_cone(bm, cap_ends=False, segments=5, radius1=0.022, radius2=0.026, depth=slen, matrix=m)
            for v in res["verts"]:
                for f in v.link_faces:
                    f.material_index = 0
            if si % 2 == 0 or si == n_segs:
                brad = rng.uniform(0.085, 0.135) if si == n_segs else rng.uniform(0.065, 0.105)
                off = Vector((rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), 0.0))
                res_b = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=brad, matrix=Matrix.Translation(cur + off))
                for v in res_b["verts"]:
                    for f in v.link_faces:
                        f.material_index = b_mat
            prev = cur

    for idx, (pos, inward) in enumerate(anchors):
        # Keep carved ancestor mural & chronicle rock faces 100% unobstructed!
        if 5.2 <= pos.y <= 13.5 and (pos.x < -4.6 or pos.x > 0.8) and 0.3 <= pos.z <= 4.8:
            continue
        sc = rng.uniform(0.55, 0.92) if pos.y > 12.0 else rng.uniform(0.45, 0.72)
        if idx % 3 == 0:
            add_shelf_cluster(pos, inward, sc, use_teal=(idx % 2 == 0))
            if idx % 6 == 0:
                add_glow_moss_fern(pos + Vector((0, 0, -0.32)), inward, sc * 0.85)
        elif idx % 3 == 1:
            add_glow_moss_fern(pos, inward, sc)
        else:
            add_shelf_cluster(pos, inward, sc * 0.95, use_teal=(idx % 4 != 0))

    def snap_ceiling_z(x_q: float, y_q: float, fallback_z: float) -> float:
        hit_loc, _, _, _ = interior_bvh.ray_cast(Vector((x_q, y_q, FLOOR_Z + 1.0)), Vector((0.0, 0.0, 1.0)), 22.0)
        if hit_loc is not None:
            return hit_loc.z + 0.20
        return fallback_z

    for k in range(10):
        ang = (k / 10.0) * math.tau + 0.18
        vx = SKY_WINDOW_CTR[0] + math.cos(ang) * (SKY_WINDOW_RAD[0] + 0.55)
        vy = SKY_WINDOW_CTR[1] + math.sin(ang) * (SKY_WINDOW_RAD[1] + 0.55)
        cx, hw, ch = sample_spine(vy)
        vz = snap_ceiling_z(vx, vy, FLOOR_Z + ch * 0.94)
        add_hanging_glow_vine(Vector((vx, vy, vz)), rng.uniform(1.8, 3.4), gold_berries=(k % 3 != 0))

    for k in range(16):
        vy = rng.uniform(14.5, 31.8)
        cx, hw, ch = sample_spine(vy)
        side = -1.0 if (k % 2 == 0) else 1.0
        vx = cx + side * rng.uniform(hw * 0.56, hw * 0.80)
        vz = snap_ceiling_z(vx, vy, FLOOR_Z + ch * 0.78)
        vlen = rng.uniform(2.0, 4.2)
        if vz - vlen > 3.6:
            add_hanging_glow_vine(Vector((vx, vy, vz)), vlen, gold_berries=(k % 3 == 0))

    for vy, side in [(-3.8, -1.0), (-1.2, 1.0), (2.4, -1.0), (5.4, 1.0)]:
        cx, hw, ch = sample_spine(vy)
        vx = cx + side * (hw * 0.62)
        vz = snap_ceiling_z(vx, vy, FLOOR_Z + ch * 0.88)
        add_hanging_glow_vine(Vector((vx, vy, vz)), rng.uniform(0.95, 1.45), gold_berries=False)

    for k in range(8):
        ang = (k / 8.0) * math.tau
        px = -9.2 + math.cos(ang) * 3.65
        py = 28.4 + math.sin(ang) * 3.05
        inward = Vector((-math.cos(ang), -math.sin(ang), 0.2)).normalized()
        add_glow_moss_fern(Vector((px, py, FLOOR_Z + 0.22)), inward, rng.uniform(0.9, 1.3))
        if k % 2 == 0:
            add_shelf_cluster(Vector((px, py, FLOOR_Z + 0.55)), inward, 1.05, use_teal=False)

    mats = [mat_vine, mat_berry_gold, mat_berry_cyan, mat_fungi_cyan, mat_fungi_teal, mat_moss_jade]
    return bm_to_object("Cave_Glow_Flora", bm, mats, parent, uv_scale=1.6, smooth=True)


def build_rock_carved_petroglyph(
    name: str,
    bvh_target: BVHTree,
    ray_origin: Vector,
    ray_dir_to_wall: Vector,
    size_wh: tuple[float, float],
    mat_carving: bpy.types.Material,
    parent: bpy.types.Object,
    wall_tangent_hint: Vector | None = None,
    nx: int = 20,
    ny: int = 14,
) -> tuple[bpy.types.Object, Vector, Vector]:
    """Build a TRUE curved rock-carved ancestor petroglyph conformed vertex-by-vertex straight onto the
    living displaced cavern wall! ZERO rectangular picture frame, ZERO protruding slab, ZERO backside crate!"""
    d_wall = ray_dir_to_wall.normalized()
    hit_c, hit_n, _, _ = bvh_target.ray_cast(ray_origin, d_wall, 24.0)
    assert hit_c is not None, f"Petroglyph {name} raycast missed cave rock surface!"

    if wall_tangent_hint is not None:
        t_h = Vector((wall_tangent_hint.x, wall_tangent_hint.y, 0.0)).normalized()
        in_n = Vector((-t_h.y, t_h.x, 0.0))
        if in_n.dot(-d_wall) < 0.0:
            in_n = -in_n
    else:
        in_n = Vector((hit_n.x, hit_n.y, 0.0))
        if in_n.length < 0.1:
            in_n = Vector((-d_wall.x, -d_wall.y, 0.0))
        in_n.normalize()
        if in_n.dot(-d_wall) < 0.0:
            in_n = -in_n

    up_v = Vector((0.0, 0.0, 1.0))
    right_v = up_v.cross(in_n).normalized()
    hw_p, hh_p = size_wh[0] * 0.5, size_wh[1] * 0.5

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    vgrid: list[list[bmesh.types.BMVert]] = []
    center_sum = Vector((0.0, 0.0, 0.0))
    center_cnt = 0

    for j in range(ny):
        v_uv = j / float(ny - 1)
        sv = (v_uv - 0.5) * 2.0
        row = []
        for i in range(nx):
            u_uv = i / float(nx - 1)
            su = (u_uv - 0.5) * 2.0
            base_pt = hit_c + right_v * (su * hw_p) + up_v * (sv * hh_p)
            probe_start = base_pt + in_n * 3.8
            h_loc, h_nrm, _, _ = bvh_target.ray_cast(probe_start, -in_n, 10.0)
            if h_loc is None:
                h_loc = base_pt
                surf_n = in_n
            else:
                surf_n = h_nrm.normalized()
                if surf_n.dot(in_n) < 0.0:
                    surf_n = -surf_n
            # Hug the real curved rock surface closely (+2.8cm center tapering down to +0.8cm at feathered alpha rim)
            edge_r = max(abs(su), abs(sv))
            offset_m = 0.032 - 0.022 * smoothstep(0.65, 1.0, edge_r)
            p_final = h_loc + surf_n * offset_m
            row.append(bm.verts.new(p_final))
            if abs(su) < 0.25 and abs(sv) < 0.25:
                center_sum += p_final
                center_cnt += 1
        vgrid.append(row)

    for j in range(ny - 1):
        for i in range(nx - 1):
            v00 = vgrid[j][i]
            v10 = vgrid[j][i + 1]
            v11 = vgrid[j + 1][i + 1]
            v01 = vgrid[j + 1][i]
            try:
                f = bm.faces.new((v00, v10, v11, v01))
                orient_face_away(f, in_n)
                f.material_index = 0
                u0, u1 = i / float(nx - 1), (i + 1) / float(nx - 1)
                vv0, vv1 = j / float(ny - 1), (j + 1) / float(ny - 1)
                uv_m = {v00: (u0, vv0), v10: (u1, vv0), v11: (u1, vv1), v01: (u0, vv1)}
                for lp in f.loops:
                    lp[uv_layer].uv = uv_m[lp.vert]
            except ValueError:
                pass

    front_center = (center_sum / float(center_cnt)) if center_cnt > 0 else hit_c
    obj = bm_to_object(name, bm, [mat_carving], parent, uv_scale=None, smooth=True)
    return obj, front_center, in_n


def build_cliff_lintel_plaque(
    name: str,
    bvh_target: BVHTree,
    ray_origin: Vector,
    ray_dir_to_wall: Vector,
    size_wh: tuple[float, float],
    mat_art: bpy.types.Material,
    mat_frame_rock: bpy.types.Material,
    parent: bpy.types.Object,
) -> tuple[bpy.types.Object, Vector, Vector]:
    """Mount the exterior '烟霞古洞' cliff brow stone inscription high above the arch crown (z=4.95 > 3.92)
    with a shallow 0.55m rock seat so it NEVER punches through into the cave tunnel ceiling!"""
    d_wall = ray_dir_to_wall.normalized()
    hit_c, _, _, _ = bvh_target.ray_cast(ray_origin, d_wall, 24.0)
    assert hit_c is not None, f"Plaque {name} raycast missed cliff brow!"

    in_n = Vector((0.0, -1.0, 0.0))
    up_v = Vector((0.0, 0.0, 1.0))
    right_v = up_v.cross(in_n).normalized()
    hw_p, hh_p = size_wh[0] * 0.5, size_wh[1] * 0.5

    max_proj = -1e9
    for su in (-1.0, -0.5, 0.0, 0.5, 1.0):
        for sv in (-1.0, 0.0, 1.0):
            sp = hit_c + right_v * (su * (hw_p + 0.14)) + up_v * (sv * (hh_p + 0.12))
            hl, _, _, _ = bvh_target.ray_cast(sp + in_n * 3.5, -in_n, 9.0)
            if hl is not None:
                max_proj = max(max_proj, (hl - hit_c).dot(in_n))
    if max_proj < -1e8:
        max_proj = 0.0

    front_center = hit_c + in_n * (max_proj + 0.05)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    art_pts = [
        front_center + right_v * (-hw_p) + up_v * (-hh_p),
        front_center + right_v * ( hw_p) + up_v * (-hh_p),
        front_center + right_v * ( hw_p) + up_v * ( hh_p),
        front_center + right_v * (-hw_p) + up_v * ( hh_p),
    ]
    av = [bm.verts.new(p) for p in art_pts]
    f_art = bm.faces.new((av[0], av[1], av[2], av[3]))
    orient_face_away(f_art, in_n)
    f_art.material_index = 0
    art_uv = {av[0]: (0.0, 0.0), av[1]: (1.0, 0.0), av[2]: (1.0, 1.0), av[3]: (0.0, 1.0)}
    for lp in f_art.loops:
        lp[uv_layer].uv = art_uv[lp.vert]

    # Shallow 0.58m carved stone bezel tucked strictly into the solid upper cliff brow (NEVER into tunnel!)
    fw_f, fh_f = hw_p + 0.14, hh_p + 0.12
    fw_b, fh_b = hw_p + 0.30, hh_p + 0.24
    embed_depth = 0.58
    lip_pts = [
        front_center + in_n * 0.04 + right_v * (-fw_f) + up_v * (-fh_f),
        front_center + in_n * 0.04 + right_v * ( fw_f) + up_v * (-fh_f),
        front_center + in_n * 0.04 + right_v * ( fw_f) + up_v * ( fh_f),
        front_center + in_n * 0.04 + right_v * (-fw_f) + up_v * ( fh_f),
    ]
    back_pts = [
        front_center - in_n * embed_depth + right_v * (-fw_b) + up_v * (-fh_b),
        front_center - in_n * embed_depth + right_v * ( fw_b) + up_v * (-fh_b),
        front_center - in_n * embed_depth + right_v * ( fw_b) + up_v * ( fh_b),
        front_center - in_n * embed_depth + right_v * (-fw_b) + up_v * ( fh_b),
    ]
    lv = [bm.verts.new(p) for p in lip_pts]
    bv = [bm.verts.new(p) for p in back_pts]

    def set_rock_uv(face):
        face.material_index = 1
        for lp in face.loops:
            rel = lp.vert.co - front_center
            lp[uv_layer].uv = (rel.dot(right_v) * 0.35 + rel.dot(in_n) * 0.35, rel.dot(up_v) * 0.35)

    for i in range(4):
        ni = (i + 1) % 4
        f_in = bm.faces.new((av[i], lv[i], lv[ni], av[ni]))
        orient_face_away(f_in, in_n)
        set_rock_uv(f_in)
        f_side = bm.faces.new((lv[i], bv[i], bv[ni], lv[ni]))
        out_side = ((lv[i].co + lv[ni].co) * 0.5 - front_center)
        out_side = out_side - in_n * out_side.dot(in_n)
        orient_face_away(f_side, out_side.normalized())
        set_rock_uv(f_side)
    f_back = bm.faces.new((bv[3], bv[2], bv[1], bv[0]))
    orient_face_away(f_back, -in_n)
    set_rock_uv(f_back)

    obj = bm_to_object(name, bm, [mat_art, mat_frame_rock], parent, uv_scale=None, smooth=False)
    return obj, front_center, in_n


def build_skylight_beams(parent: bpy.types.Object, mat_beam) -> bpy.types.Object:
    """Build 2 subtle airy volumetric skylight shafts (gentle soft glow, grounded cleanly to floor without milky wall)."""
    bm = bmesh.new()
    # 1) Mid-Gallery Skylight soft diagonal shaft
    n_seg = 16
    top_r = [bm.verts.new((SKY_WINDOW_CTR[0] + math.cos(i / n_seg * math.tau) * 1.65, SKY_WINDOW_CTR[1] + math.sin(i / n_seg * math.tau) * 1.40, 12.2)) for i in range(n_seg)]
    bot_r = [bm.verts.new((SKY_WINDOW_CTR[0] + 0.75 + math.cos(i / n_seg * math.tau) * 2.45, SKY_WINDOW_CTR[1] + 0.45 + math.sin(i / n_seg * math.tau) * 2.15, FLOOR_Z - 0.02)) for i in range(n_seg)]
    for i in range(n_seg):
        ni = (i + 1) % n_seg
        bm.faces.new((bot_r[i], bot_r[ni], top_r[ni], top_r[i]))

    # 2) Deep Sanctum '一线天' single gentle smooth elliptical sunbeam column (NO sharp zig-zag sheets!)
    yxt_cy = 0.5 * (YIXIANTIAN_Y0 + YIXIANTIAN_Y1)
    top_y = [bm.verts.new((YIXIANTIAN_X + math.cos(i / n_seg * math.tau) * 0.58, yxt_cy + math.sin(i / n_seg * math.tau) * 1.45, 13.8)) for i in range(n_seg)]
    bot_y = [bm.verts.new((YIXIANTIAN_X + math.cos(i / n_seg * math.tau) * 0.85, yxt_cy + math.sin(i / n_seg * math.tau) * 1.75, FLOOR_Z - 0.02)) for i in range(n_seg)]
    for i in range(n_seg):
        ni = (i + 1) % n_seg
        bm.faces.new((bot_y[i], bot_y[ni], top_y[ni], top_y[i]))

    return bm_to_object("Cave_Skylight_Beams", bm, [mat_beam], parent, uv_scale=0.12, smooth=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    art = extract_v062_textures()

    pbr_dir = REPO_ROOT / "game" / "assets" / "pbr_v097"
    img_rock_diff = load_packed_img(pbr_dir / "cliff_side_diff.jpg", "sRGB", 1024, "CaveCliff_Diff")
    img_rock_norm = load_packed_img(pbr_dir / "cliff_side_nor_gl.jpg", "Non-Color", 1024, "CaveCliff_Norm")
    img_moss_diff = load_packed_img(pbr_dir / "mossy_rock_diff.jpg", "sRGB", 1024, "MtnMossRock_Diff")
    img_moss_norm = load_packed_img(pbr_dir / "mossy_rock_nor_gl.jpg", "Non-Color", 1024, "MtnMossRock_Norm")
    img_grass_diff = load_packed_img(pbr_dir / "aerial_grass_rock_diff.jpg", "sRGB", 1024, "MtnGrass_Diff")
    img_grass_norm = load_packed_img(pbr_dir / "aerial_grass_rock_nor_gl.jpg", "Non-Color", 1024, "MtnGrass_Norm")
    assert img_rock_diff is not None and img_moss_diff is not None and img_grass_diff is not None, "Missing seamless pbr_v097 textures!"

    # Synthesize TRUE transparent rock-carved petroglyph decals directly onto curved cave limestone!
    # Preserves true 2:1 landscape aspect for '烟山耕读' and true 2:3 portrait aspect for '烟霞古洞志'!
    mural_carved_diff, mural_carved_norm = synthesize_rock_carved_textures(
        art["mural_yanxia_ancients"], img_rock_diff, img_rock_norm,
        "CaveCarvedMural", pigment_rgb=(0.54, 0.24, 0.13), groove_darken=0.72, pigment_mix=0.52,
        size_wh=(1024, 512),
    )
    chron_carved_diff, chron_carved_norm = synthesize_rock_carved_textures(
        art["inscription_cave_chronicle"], img_rock_diff, img_rock_norm,
        "CaveCarvedChronicle", pigment_rgb=(0.12, 0.10, 0.08), groove_darken=0.80, pigment_mix=0.45,
        size_wh=(640, 960),
    )

    mat_cave_wall = make_pbr_mat(
        "Mat_GrandCaveWall", (0.42, 0.48, 0.52, 1.0), roughness=0.84,
        albedo_img=img_rock_diff, normal_img=img_rock_norm, normal_scale=0.95,
    )
    mat_cave_floor = make_pbr_mat(
        "Mat_GrandCaveFloor", (0.36, 0.42, 0.46, 1.0), roughness=0.46,
        albedo_img=img_rock_diff, normal_img=img_rock_norm, normal_scale=0.58,
    )
    mat_stalactite = make_pbr_mat(
        "Mat_GrandCaveStalactite", (0.48, 0.54, 0.56, 1.0), roughness=0.76,
        albedo_img=img_rock_diff, normal_img=img_rock_norm, normal_scale=0.85,
    )
    mat_chimney = make_pbr_mat(
        "Mat_GrandCaveChimney", (0.48, 0.55, 0.50, 1.0), roughness=0.86,
        albedo_img=img_moss_diff, normal_img=img_moss_norm, normal_scale=0.85, double_sided=True,
    )
    # Harmonized Jiangnan hillside rock & spring meadow grass (blends naturally into ContinuousGround!)
    mat_mtn_cliff = make_pbr_mat(
        "Mat_MountainCliff", (0.64, 0.70, 0.60, 1.0), roughness=0.88,
        albedo_img=img_moss_diff, normal_img=img_moss_norm, normal_scale=0.74,
    )
    mat_mtn_grass = make_pbr_mat(
        "Mat_MountainGrass", (0.56, 0.72, 0.44, 1.0), roughness=0.92,
        albedo_img=img_grass_diff, normal_img=img_grass_norm, normal_scale=0.58,
    )
    mat_spring_water = make_pbr_mat(
        "Mat_JadeSpringWater", (0.03, 0.22, 0.24, 1.0), roughness=0.24,
        emission_rgba=(0.04, 0.32, 0.35, 1.0), emission_strength=0.10, alpha=0.88,
    )
    mat_vine = make_pbr_mat("Mat_GlowVineStem", (0.09, 0.26, 0.19, 1.0), roughness=0.78, double_sided=True)
    mat_berry_gold = make_pbr_mat(
        "Mat_GlowBerryGold", (1.0, 0.76, 0.24, 1.0), roughness=0.28,
        emission_rgba=(1.0, 0.72, 0.18, 1.0), emission_strength=1.50,
    )
    mat_berry_cyan = make_pbr_mat(
        "Mat_GlowBerryCyan", (0.18, 0.88, 0.88, 1.0), roughness=0.26,
        emission_rgba=(0.14, 0.84, 0.86, 1.0), emission_strength=1.40,
    )
    mat_fungi_cyan = make_pbr_mat(
        "Mat_GlowFungiCyan", (0.06, 0.50, 0.68, 1.0), roughness=0.40,
        emission_rgba=(0.06, 0.58, 0.78, 1.0), emission_strength=0.78, double_sided=True,
    )
    mat_fungi_teal = make_pbr_mat(
        "Mat_GlowFungiTeal", (0.08, 0.58, 0.42, 1.0), roughness=0.42,
        emission_rgba=(0.08, 0.62, 0.44, 1.0), emission_strength=0.68, double_sided=True,
    )
    mat_moss_jade = make_pbr_mat(
        "Mat_GlowMossJade", (0.08, 0.44, 0.34, 1.0), roughness=0.66,
        emission_rgba=(0.08, 0.50, 0.38, 1.0), emission_strength=0.54, double_sided=True,
    )
    # Soft airy sunbeams (no harsh milky cylinder blocking view of Cave Warden!)
    mat_beam = make_pbr_mat(
        "Mat_SkylightMistBeam", (0.76, 0.94, 0.98, 1.0), roughness=1.0,
        emission_rgba=(0.64, 0.88, 0.96, 1.0), emission_strength=0.24, alpha=0.042, double_sided=True,
    )

    mat_plaque = make_pbr_mat(
        "Mat_YanxiaPlaque", (0.90, 0.90, 0.86, 1.0), roughness=0.84,
        albedo_img=art.get("plaque_yanxia_cave"),
    )
    # Authentic dark limestone rock-carved petroglyph materials (organic alpha blend, crisp chiseled normal!)
    mat_mural = make_pbr_mat(
        "Mat_YanxiaMural", (1.0, 1.0, 1.0, 1.0), roughness=0.86,
        albedo_img=mural_carved_diff, normal_img=mural_carved_norm, normal_scale=1.45,
        use_img_alpha=True,
    )
    mat_chronicle = make_pbr_mat(
        "Mat_YanxiaChronicle", (1.0, 1.0, 1.0, 1.0), roughness=0.86,
        albedo_img=chron_carved_diff, normal_img=chron_carved_norm, normal_scale=1.45,
        use_img_alpha=True,
    )

    root = bpy.data.objects.new("YanxiaGrandCave", None)
    bpy.context.scene.collection.objects.link(root)

    interior_obj, wall_anchors = build_interior_cavern(root, mat_cave_wall, mat_cave_floor, mat_stalactite, mat_chimney)
    mountain_obj = build_exterior_mountain(root, mat_mtn_cliff, mat_mtn_grass)
    pillars_obj, pillar_anchors = build_hall_pillars(root, mat_cave_wall, mat_stalactite)
    pool_obj = build_jade_spring_pool(root, mat_spring_water, mat_cave_wall)

    bm_int_bvh = bmesh.new()
    bm_int_bvh.from_mesh(interior_obj.data)
    bvh_interior = BVHTree.FromBMesh(bm_int_bvh)
    bm_ext_bvh = bmesh.new()
    bm_ext_bvh.from_mesh(mountain_obj.data)
    bvh_exterior = BVHTree.FromBMesh(bm_ext_bvh)

    flora_obj = build_bioluminescent_flora(
        root, wall_anchors + pillar_anchors, bvh_interior,
        mat_vine, mat_berry_gold, mat_berry_cyan, mat_fungi_cyan, mat_fungi_teal, mat_moss_jade,
    )
    beams_obj = build_skylight_beams(root, mat_beam)

    # 1) South Cliff Portal Plaque ('烟霞古洞') cleanly ABOVE arch crown (z = 5.18 > 3.92, shallow 0.58m!)
    plaque_obj, p_pos, p_n = build_cliff_lintel_plaque(
        "Cave_Portal_Plaque", bvh_exterior,
        ray_origin=Vector((0.0, -14.0, 5.18)),
        ray_dir_to_wall=Vector((0.0, 1.0, 0.0)),
        size_wh=(2.38, 0.72),
        mat_art=mat_plaque, mat_frame_rock=mat_mtn_cliff, parent=root,
    )
    # 2) West Wall Rock-Carved Petroglyph ('《烟山耕读》') conformed directly into curved cave limestone!
    cx_w0, hw_w0, _ = sample_spine(9.2)
    cx_w1, hw_w1, _ = sample_spine(11.2)
    west_tangent = Vector(((cx_w1 - hw_w1) - (cx_w0 - hw_w0), 2.0, 0.0)).normalized()
    mural_obj, m_pos, m_n = build_rock_carved_petroglyph(
        "Cave_Mural_Slab", bvh_interior,
        ray_origin=Vector((-2.65, 10.20, 2.25)),
        ray_dir_to_wall=Vector((-1.0, -0.45, 0.0)),
        size_wh=(4.05, 2.08),
        mat_carving=mat_mural, parent=root,
        wall_tangent_hint=west_tangent,
    )
    # 3) East Wall Rock-Carved Inscription ('《烟霞古洞志》') conformed directly into curved cave limestone (true 2:3 portrait!)
    cx_e0, hw_e0, _ = sample_spine(8.8)
    cx_e1, hw_e1, _ = sample_spine(10.8)
    east_tangent = Vector(((cx_e1 + hw_e1) - (cx_e0 + hw_e0), 2.0, 0.0)).normalized()
    chron_obj, c_pos, c_n = build_rock_carved_petroglyph(
        "Cave_Chronicle_Slab", bvh_interior,
        ray_origin=Vector((-2.55, 9.80, 2.25)),
        ray_dir_to_wall=Vector((1.0, -0.35, 0.0)),
        size_wh=(1.88, 2.72),
        mat_carving=mat_chronicle, parent=root,
        wall_tangent_hint=east_tangent,
    )
    print(f"PANEL_MOUNT Cave_Portal_Plaque pos=({p_pos.x:.2f},{p_pos.y:.2f},{p_pos.z:.2f}) n=({p_n.x:.2f},{p_n.y:.2f})")
    print(f"PANEL_MOUNT Cave_Mural_Slab    pos=({m_pos.x:.2f},{m_pos.y:.2f},{m_pos.z:.2f}) n=({m_n.x:.2f},{m_n.y:.2f})")
    print(f"PANEL_MOUNT Cave_Chronicle_Slab pos=({c_pos.x:.2f},{c_pos.y:.2f},{c_pos.z:.2f}) n=({c_n.x:.2f},{c_n.y:.2f})")

    # Print exact BVH-grounded Godot local coordinates (x, y_up, z_godot = -y_b) for exterior hill bamboo & ferns!
    bamboo_xy = [
        (-5.8, -3.6), (5.4, -3.4),
        (-10.8, 5.2), (6.5, 5.8),
        (-12.2, 16.0), (7.6, 17.2),
        (-10.5, 23.0), (4.6, 23.5),
        (-10.0, 30.8), (4.5, 31.2),
        (-6.2, 36.2), (-0.4, 35.8),
    ]
    b_strs = []
    for bx, by in bamboo_xy:
        hl, _, _, _ = bvh_exterior.ray_cast(Vector((bx, by, 30.0)), Vector((0.0, 0.0, -1.0)), 40.0)
        gz = (hl.z - 0.24) if hl is not None else (mountain_surface_z(bx, by) - 0.24)
        b_strs.append(f"Vector3({bx:.2f}, {gz:.2f}, {-by:.2f})")
    print("PEAK_BAMBOO_LOCAL:", ", ".join(b_strs))

    f_strs = []
    for k in range(16):
        ang = k * (math.tau / 16.0)
        fx = -3.4 + math.cos(ang) * 9.5
        fy = 21.5 + math.sin(ang) * 11.5
        hl, _, _, _ = bvh_exterior.ray_cast(Vector((fx, fy, 30.0)), Vector((0.0, 0.0, -1.0)), 40.0)
        gz = (hl.z - 0.16) if hl is not None else (mountain_surface_z(fx, fy) - 0.16)
        f_strs.append(f"Vector3({fx:.2f}, {gz:.2f}, {-fy:.2f})")
    print("PEAK_FERNS_LOCAL:", ", ".join(f_strs))

    bm_int_bvh.free()
    bm_ext_bvh.free()

    all_objs = [root, interior_obj, mountain_obj, pillars_obj, pool_obj, flora_obj, beams_obj, plaque_obj, mural_obj, chron_obj]
    total_polys = sum(len(o.data.polygons) for o in all_objs if o.type == "MESH")

    bpy.ops.object.select_all(action="DESELECT")
    for o in all_objs:
        o.select_set(True)
    SLICE_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
    )

    raw_b = OUT_GLB.read_bytes()
    jlen = struct.unpack("<I", raw_b[12:16])[0]
    g = json.loads(raw_b[20 : 20 + jlen])
    tcs = sorted({k for m in g.get("meshes", []) for pr in m.get("primitives", []) for k in pr.get("attributes", {}) if k.startswith("TEXCOORD")})
    miss = sum(1 for m in g.get("meshes", []) for pr in m.get("primitives", []) if "TEXCOORD_0" not in pr.get("attributes", {}))
    print(f"EXPORTED_GRAND_CAVE {OUT_GLB.name} ({len(raw_b)/1048576:.2f} MiB | {total_polys} polys | meshes={len(g.get('meshes', []))} | TEXCOORDS={tcs} | missing_uv0={miss})")


if __name__ == "__main__":
    main()
