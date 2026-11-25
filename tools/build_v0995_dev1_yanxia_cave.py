"""v0.9.9.5_dev1 Grand Mountain-Embedded Yanxia Ancient Cave ('烟霞古洞 · 山腹巨窟') Builder.

Generates a single unified, PBR-textured, watertight subterranean cavern + towering
exterior mountain peak asset at:
  game/assets/slice/v0995_yanxia_grand_cave.glb

Architectural highlights:
- 100% hidden inside a 48m x 55m x 22.5m rugged mossy & grass-crowned mountain massif
  (Cave_Exterior_Mountain), with skirts diving -4.5m below terrain so ZERO cave shell
  is exposed from outside; ONLY the natural cliff mouth opens onto the Bamboo Maze forecourt.
- 3.5x longer (41.3m deep from south mouth to deepest north cliff!) with dramatic
  funnel-to-cathedral spatial progression:
    1. Narrow Entrance Throat (width 4.0-5.4m, ceiling 4.1-5.0m) curving gently west
    2. Expanding Mid-Gallery (width 6.3-13.0m, ceiling 5.3-8.4m) with overhead Skylight
       Window ('洞顶空窗'), West Wall Mural ('《烟山耕读》') & East Chronicle ('《烟霞古洞志》')
    3. Grand Underground Cavern Hall (width 23.6m x depth 18.5m x ceiling 12.8m!) with
       4 sculpted stalagmite cover pillars, West-North Jade Spring Pool ('洞中寒潭'),
       spacious arena for the 2.86m Minecraft-Warden-style Cave Warden
    4. Deepest '一线天' Chasm & North Cliff backing the Dimensional Rift Wall ('次元石壁')
- Bioluminescent Cave Wall Flora (Cave_Glow_Flora): hanging glow-vines with golden-amber
  and aqua glowing berries, clustered turquoise shelf mushrooms, and glowing jade moss/ferns
  growing naturally along walls, ledges, skylight rims, and stalagmite bases.
- Reuses Poly Haven CC0 rock/moss/grass PBR maps and v062 mural/chronicle/plaque art.
- Guarantees single canonical UVMap (TEXCOORD_0) across all exported meshes (0 missing UVs).
"""
from __future__ import annotations

import json
import math
import random
import struct
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parents[1]
SLICE_DIR = REPO_ROOT / "game" / "assets" / "slice"
OUT_GLB = SLICE_DIR / "v0995_yanxia_grand_cave.glb"
V062_GLB = SLICE_DIR / "v062_bamboo_cave.glb"


# ===========================================================================
# 1. Analytical Cave Spine (Blender coords: +X East, +Y North/Deeper, +Z Up)
#    Note: Godot z_local == -y_blender!
#    Portal mouth at y_blender = -6.5  (Godot z_local = +6.5, world z = -93.5)
#    Deep back cliff at y_blender = +34.8 (Godot z_local = -34.8, world z = -134.8)
# ===========================================================================
SPINE_STATIONS = [
    # (y_b,   cx,    hw,    ch)
    (-6.50,  0.00,  2.15,  3.95),  # 0. Mountain cliff cave mouth
    (-3.20, -0.18,  2.02,  4.05),  # 1. Narrow throat entry
    ( 0.50, -0.55,  2.18,  4.25),  # 2. Throat gentle west bend
    ( 4.50, -1.40,  3.20,  5.35),  # 3. Throat widening
    ( 8.20, -2.25,  5.40,  7.40),  # 4. Mid-gallery approach
    (10.50, -2.65,  6.65,  8.55),  # 5. Mid-gallery beneath skylight ('洞顶空窗')
    (14.50, -3.25,  9.20, 10.60),  # 6. Cathedral opening arch
    (19.00, -3.50, 11.45, 12.40),  # 7. Grand Hall south expanse
    (23.50, -3.50, 11.85, 12.90),  # 8. Grand Hall widest heart (23.7m wide x 12.9m tall!)
    (28.00, -3.50, 10.40, 12.30),  # 9. Grand Hall north expanse (Jade Spring Pool alcove)
    (31.50, -3.50,  6.90, 11.80),  # 10. Taper into '一线天' sanctum
    (34.80, -3.50,  4.35, 13.80),  # 11. Deepest north bedrock cliff behind Dimensional Rift Wall
]

FLOOR_Z = 0.026

# 4 sculpted stalagmite cover columns in Grand Hall outer ring (clear of central boss floor!)
HALL_PILLARS = [
    (-9.6, 17.6, 1.02, 1.15),   # SW pillar
    ( 2.8, 17.8, 1.00, 1.12),   # SE pillar
    (-10.0, 26.8, 1.08, 1.18),  # NW pillar
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
    """Continuous sculpted mountain peak surface covering the ENTIRE 41.3m cavern!"""
    cx, hw, ch = sample_spine(y)
    # 1) Base sweeping Jiangnan peak massif spanning x in [-29..+21], y in [-7.2..+49]
    #    Centered near Grand Hall (-3.5, 22.5), rising up to 22.8m above cave floor!
    dx_peak = (x - (-3.5)) / 25.5
    dy_peak = (y - 21.5) / 27.0
    r2_main = dx_peak * dx_peak + dy_peak * dy_peak
    h_main = 22.8 * math.exp(-r2_main * 1.35)

    # Secondary west ridge shoulder seamlessly linking into western map border
    dx_w = (x - (-17.5)) / 18.0
    dy_w = (y - 11.0) / 24.0
    h_west = 17.5 * math.exp(-(dx_w * dx_w + dy_w * dy_w) * 1.45)

    # Front craggy cliff brow directly over narrow throat (y = -6.5..+6.0)
    dx_f = (x - (-1.2)) / 12.5
    dy_f = (y - 1.5) / 11.0
    h_front = 13.8 * math.exp(-(dx_f * dx_f + dy_f * dy_f) * 1.25)

    # North ridge crest framing the '一线天' chasm dramatically high!
    dx_n = (x - (-3.5)) / 16.5
    dy_n = (y - 33.5) / 14.5
    h_north = 19.6 * math.exp(-(dx_n * dx_n + dy_n * dy_n) * 1.35)

    h = max(h_main, h_west, h_front, h_north)

    # Guarantee generous thick rock overburden (>= +3.4m) over EVERY point of the interior cavern!
    if -6.6 <= y <= 35.6:
        inside_x = 1.0 - smoothstep(hw + 0.8, hw + 7.5, abs(x - cx))
        inside_y = smoothstep(-7.4, -5.8, y) * (1.0 - smoothstep(34.6, 39.0, y))
        min_cover = ch + 3.8 + 1.8 * inside_x
        h = max(h, min_cover * inside_x * inside_y)

    # Organic stratified mountain ledges & karst crags
    crag = rock_noise(x * 0.55, y * 0.55, h * 0.35) * 1.15
    strata = math.sin(h * 1.15 + x * 0.14) * 0.32
    h += crag + strata

    # Smooth outer skirt diving down to z = -4.5m at perimeter so ZERO terrain gap exists anywhere!
    skirt_w = smoothstep(-28.5, -21.5, x)
    skirt_e = 1.0 - smoothstep(13.5, 20.5, x)
    skirt_n = 1.0 - smoothstep(40.5, 48.5, y)
    # South face stays steep right up to the cave mouth cliff at y = -6.5..-7.3!
    skirt_s = smoothstep(-8.8, -6.4, y)
    skirt = skirt_w * skirt_e * skirt_n * skirt_s
    return -4.5 + (h + 4.5) * skirt


# ===========================================================================
# 2. PBR Material Helpers (reusing existing Poly Haven & v062 game textures!)
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
    if alpha < 0.999:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND" if hasattr(mat, "blend_method") else "OPAQUE"

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
    # Clean imported v062 objects immediately
    for o in list(bpy.data.objects):
        if o not in before_objs:
            bpy.data.objects.remove(o, do_unlink=True)
    return found


# ===========================================================================
# 3. Geometry Builders
# ===========================================================================
def build_interior_cavern(parent: bpy.types.Object, mat_wall, mat_floor, mat_stalactite, mat_chimney) -> tuple[bpy.types.Object, list[tuple[Vector, Vector]]]:
    """Build organic 41.3m vaulted subterranean cave + wet limestone floor + 2 skylight chimneys + stalactites.
    Returns (interior_obj, wall_flora_anchors) where each anchor is (pos, inward_normal).
    """
    bm = bmesh.new()
    flora_anchors: list[tuple[Vector, Vector]] = []

    # Longitudinal samples from portal mouth (-6.50) to deepest back cliff (+34.80)
    n_rings = 52
    y_min, y_max = -6.50, 34.80
    ys = [y_min + (y_max - y_min) * (i / float(n_rings - 1)) for i in range(n_rings)]

    # Cross-section profile: 26 points around an arch from East floor -> Vault top -> West floor!
    # Floor is flat walkable limestone at z = FLOOR_Z across bottom [-hw .. +hw].
    n_arc = 24  # angles from 0 (East floor) -> pi (West floor)
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
            # Super-elliptic natural karst vault: slightly steeper lower walls + broad vaulted roof
            ca = math.cos(ang)
            sa = math.sin(ang)
            rx = hw * math.copysign(abs(ca) ** 0.86, ca)
            rz = ch * (sa ** 0.78)
            px = cx + rx
            pz = FLOOR_Z + rz

            # Organic craggy limestone wall relief (strictly OUTWARD near floor so min clearance stays clean;
            # pinned smooth at portal mouth so it welds cleanly into mountain cliff!)
            if not is_portal and not is_back:
                n_val = rock_noise(px * 0.58, y * 0.45, pz * 0.58)
                amp = 0.24 if hw < 4.0 else 0.55
                # Keep bottom floor edge grounded at exact FLOOR_Z
                edge_fade = smoothstep(0.0, 0.14, min(t, 1.0 - t))
                # Expand slightly outward so crags feel carved into solid rock
                out_dir_x = ca
                out_dir_z = sa
                disp = (0.18 + n_val * 0.48) * amp * edge_fade
                px += out_dir_x * disp
                pz += out_dir_z * disp
                if pz < FLOOR_Z + 0.04 and (ai != 0 and ai != n_arc):
                    pz = FLOOR_Z + 0.04

                # Harvest lush wall/ledge flora anchor points on mid-walls (z = 1.4..7.5m)!
                if ri % 3 == 1 and ri >= 2 and ri <= n_rings - 3 and ai in (3, 5, 7, 17, 19, 21):
                    inward = Vector((-ca, 0.0, -sa * 0.35)).normalized()
                    flora_anchors.append((Vector((px, y, pz)), inward))

            v = bm.verts.new((px, y, pz))
            row.append(v)
        ring_verts.append(row)
        floor_east.append(row[0])
        floor_west.append(row[-1])

    # Loft interior cave vault faces — strictly INWARD-FACING normals + seamless parametric UVs!
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
            # Punch the two true skylight openings ONLY in the upper vault crown!
            if cen.z > 5.0 and in_any_skylight(cen.x, cen.y, pad=-0.05):
                continue
            try:
                f = bm.faces.new((v00, v01, v11, v10))  # Strictly INWARD winding!
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

    # Build flat walkable wet limestone floor strip-by-strip (strictly +Z normals + world XY UV!)
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

    # Seal North Back Cliff cleanly at y = y_max (+34.80) with strictly INWARD (-Y) normals!
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
    # Close bottom of back cliff to floor
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

    # Build 2 rugged vertical rock skylight chimney sleeves connecting cavern vault -> exterior mountain top!
    # 1) Mid-Gallery Skylight Chimney ('洞顶空窗') — strictly INWARD normals facing shaft center!
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
            z_top = mountain_surface_z(px, py) + 0.65
            pz = z_bot + (z_top - z_bot) * u
            jagged = rock_noise(px * 1.4, py * 1.4, pz * 0.9) * 0.24
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

    # 2) Deep Sanctum '一线天' Vertical Chasm Sleeve — strictly INWARD normals facing chasm center!
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
            z_bot = 10.6
            z_top = mountain_surface_z(px, py) + 0.85
            pz = z_bot + (z_top - z_bot) * u
            px += rock_noise(px * 1.6, py * 1.2, pz * 0.7) * 0.16
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

    # Add sculpted hanging limestone stalactites along high vault ceilings (always > 5.0m above floor!)
    rng = random.Random(20260995)
    for _ in range(36):
        sy = rng.uniform(5.5, 31.0)
        cx, hw, ch = sample_spine(sy)
        sx = cx + rng.uniform(-hw * 0.68, hw * 0.68)
        if in_any_skylight(sx, sy, pad=1.2):
            continue
        frac_x = abs(sx - cx) / max(0.5, hw)
        roof_z = FLOOR_Z + ch * (max(0.15, 1.0 - frac_x * frac_x) ** 0.42)
        slen = rng.uniform(1.1, 2.7)
        if roof_z - slen < 5.0:
            continue
        rad = rng.uniform(0.16, 0.38)
        m = Matrix.Translation((sx, sy, roof_z - slen * 0.45))
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
    """Build the towering 48m x 56m x 22.5m forested mountain massif hiding 100% of Yanxia Cave!
    Opens cleanly ONLY at the wide-open walkable South Cliff Mouth (y = -6.5, |x| < 2.25) and the 2 sky chimneys!
    Uses continuous non-degenerate parametric UVs so ZERO black NaN-tangent quads ever occur.
    """
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    nx, ny = 56, 62
    x0, x1 = -28.5, 20.5
    y0, y1 = -8.6, 48.5

    grid: list[list[bmesh.types.BMVert]] = []
    for j in range(ny):
        y = y0 + (y1 - y0) * (j / float(ny - 1))
        row = []
        for i in range(nx):
            x = x0 + (x1 - x0) * (i / float(nx - 1))
            z = mountain_surface_z(x, y)
            # Lift overhanging craggy cliff brow cleanly ABOVE cave mouth arch (z >= 5.2m at y >= -6.6)
            if -7.4 <= y <= -4.4 and abs(x) < 3.4:
                brow_u = 1.0 - smoothstep(1.8, 3.4, abs(x))
                y_u = smoothstep(-7.4, -6.2, y)
                z = max(z, 5.4 * brow_u * y_u + z * (1.0 - brow_u * y_u))
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)

    for j in range(ny - 1):
        for i in range(nx - 1):
            v00 = grid[j][i]
            v10 = grid[j][i + 1]
            v11 = grid[j + 1][i + 1]
            v01 = grid[j + 1][i]
            cen = (v00.co + v10.co + v11.co + v01.co) * 0.25
            # Skip roof quads directly over the 2 true skylight openings!
            if in_any_skylight(cen.x, cen.y, pad=-0.10):
                continue
            # Cleanly open the entire cave mouth entrance corridor (|x| <= 2.35, y <= -5.2) so ZERO rock blocks doorway!
            if cen.y <= -5.2 and abs(cen.x) <= 2.40:
                continue
            try:
                f = bm.faces.new((v00, v10, v11, v01))
                orient_face_away(f, Vector((0.0, 0.0, 1.0)))
                is_grass = (f.normal.z > 0.62) and (cen.z > 4.0) and (cen.y > -4.8)
                f.material_index = 1 if is_grass else 0
                # Strictly continuous monotonic heightfield UVs — ZERO degenerate tangents!
                for lp in f.loops:
                    lp[uv_layer].uv = (lp.vert.co.x * 0.14, lp.vert.co.y * 0.14)
            except ValueError:
                pass

    # Build monumental sculpted South Cliff Portal Arch & Brow framing the open 4.3m cave mouth at y = -6.5!
    # Connects exterior mountain cliff face cleanly to interior portal ring with ZERO blocking quads in the doorway!
    n_arch = 24
    portal_outer: list[bmesh.types.BMVert] = []
    portal_inner: list[bmesh.types.BMVert] = []
    portal_back: list[bmesh.types.BMVert] = []
    cx0, hw0, ch0 = sample_spine(-6.50)
    for ai in range(n_arch + 1):
        ang = (ai / float(n_arch)) * math.pi
        ca, sa = math.cos(ang), math.sin(ang)
        ix = cx0 + (hw0 + 0.04) * math.copysign(abs(ca) ** 0.86, ca)
        iz = FLOOR_Z + (ch0 + 0.04) * (sa ** 0.78)
        ox = cx0 + (hw0 + 2.35) * math.copysign(abs(ca) ** 0.82, ca)
        oz = FLOOR_Z + (ch0 + 2.55) * (sa ** 0.76)
        if ai == 0 or ai == n_arch:
            oz = -1.6
            iz = -0.35
        vi = bm.verts.new((ix, -6.12, iz))
        vo = bm.verts.new((ox, -7.52 + rock_noise(ox, -7.2, oz) * 0.22, oz))
        vb = bm.verts.new((ox * 1.12, -5.05, max(oz + 1.2, mountain_surface_z(ox * 1.12, -5.05))))
        portal_inner.append(vi)
        portal_outer.append(vo)
        portal_back.append(vb)
    for ai in range(n_arch):
        u0 = (ai / float(n_arch)) * 3.8
        u1 = ((ai + 1) / float(n_arch)) * 3.8
        # Front bevel ring facing SOUTH (-Y) into the Bamboo Forecourt
        try:
            f = bm.faces.new((portal_outer[ai], portal_inner[ai], portal_inner[ai + 1], portal_outer[ai + 1]))
            orient_face_away(f, Vector((0.0, -1.0, 0.25)))
            f.material_index = 0
            uv_m = {portal_outer[ai]: (u0, 0.0), portal_inner[ai]: (u0, 0.9), portal_inner[ai + 1]: (u1, 0.9), portal_outer[ai + 1]: (u1, 0.0)}
            for lp in f.loops:
                lp[uv_layer].uv = uv_m[lp.vert]
        except ValueError:
            pass
        # Top/outer rock collar sealing cleanly back into the mountain heightfield!
        try:
            f2 = bm.faces.new((portal_outer[ai], portal_outer[ai + 1], portal_back[ai + 1], portal_back[ai]))
            orient_face_away(f2, Vector((0.0, -0.35, 1.0)))
            f2.material_index = 0
            uv_m2 = {portal_outer[ai]: (u0, 0.0), portal_outer[ai + 1]: (u1, 0.0), portal_back[ai + 1]: (u1, 1.1), portal_back[ai]: (u0, 1.1)}
            for lp in f2.loops:
                lp[uv_layer].uv = uv_m2[lp.vert]
        except ValueError:
            pass

    # Add sculpted craggy cliff flank buttresses strictly OUTSIDE |x| >= 2.45m (NEVER obstructing cave mouth!)
    for side in (-1.0, 1.0):
        for dx, dy, dz, sx, sy, sz in [
            (side * 4.9, -6.8, 2.8, 2.1, 2.0, 5.0),
            (side * 7.2, -6.2, 3.8, 2.8, 2.5, 6.8),
            (side * 9.8, -5.2, 4.6, 3.2, 3.0, 8.2),
            (side * 1.9, -6.7, 6.2, 2.8, 1.8, 1.8),  # high craggy rock brow safely ABOVE z=4.4m doorway!
        ]:
            res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
            for v in res["verts"]:
                p = v.co
                n = rock_noise(p.x * 2.2 + dx, p.y * 2.2 + dy, p.z * 2.2 + dz) * 0.14
                v.co = Vector((
                    dx + p.x * sx * (1.0 + n),
                    dy + p.y * sy * (1.0 + n),
                    dz + p.z * sz * (1.0 + n),
                ))
            for v in res["verts"]:
                for f in v.link_faces:
                    f.material_index = 0
                    # Non-degenerate spherical UV mapping around rock center
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
    # Low natural carved stone pool rim
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
    # Glowing emerald-jade spring water disk
    w_cen = bm.verts.new((pcx, pcy, FLOOR_Z + 0.20))
    w_ring = []
    for si in range(n_seg):
        ang = (si / float(n_seg)) * math.tau
        wob = 1.0 + 0.08 * math.sin(ang * 3.0 + 0.5)
        w_ring.append(bm.verts.new((pcx + math.cos(ang) * (rx + 0.08) * wob, pcy + math.sin(ang) * (ry + 0.08) * wob, FLOOR_Z + 0.20)))
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
    mat_vine,
    mat_berry_gold,
    mat_berry_cyan,
    mat_fungi_cyan,
    mat_fungi_teal,
    mat_moss_jade,
) -> bpy.types.Object:
    """Build rich glowing cave wall plants across ALL 3 cave zones:
      - Hanging glow-vines with warm gold & aqua berries draping from skylight rims & high ledges
      - Clustered bioluminescent turquoise/teal shelf mushrooms sprouting from damp cave walls & pillars
      - Glowing jade rock moss pads & crystal fern fronds lining ledges & path edges
    """
    bm = bmesh.new()
    rng = random.Random(20261125)

    def add_shelf_cluster(pos: Vector, inward: Vector, scale: float, use_teal: bool):
        """Tiered organic fan-shaped bioluminescent bracket mushrooms growing out from rock wall."""
        n_dir = Vector((inward.x, inward.y, 0.0))
        if n_dir.length < 0.01:
            n_dir = Vector((1.0, 0.0, 0.0))
        n_dir.normalize()
        side = Vector((-n_dir.y, n_dir.x, 0.0))
        mat_idx = 4 if use_teal else 3
        for k in range(rng.randint(4, 7)):
            s = scale * rng.uniform(0.55, 1.18)
            off = side * rng.uniform(-0.42, 0.42) * scale + Vector((0, 0, rng.uniform(-0.34, 0.34) * scale)) + n_dir * rng.uniform(0.02, 0.14)
            c = pos + off
            # Flattened organic mushroom shelf cap protruding outward along n_dir
            m = Matrix.Translation(c + n_dir * (0.14 * s))
            yaw = math.atan2(n_dir.y, n_dir.x)
            m = m @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Scale(0.24 * s, 4, (1, 0, 0)) @ Matrix.Scale(0.32 * s, 4, (0, 1, 0)) @ Matrix.Scale(0.065 * s, 4, (0, 0, 1))
            res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=m)
            for v in res["verts"]:
                for f in v.link_faces:
                    f.material_index = mat_idx

    def add_glow_moss_fern(pos: Vector, inward: Vector, scale: float):
        """Glowing jade cave moss mat + radiating glowing crystal-fern blades on wall/ledge."""
        n_dir = Vector((inward.x, inward.y, 0.0))
        if n_dir.length < 0.01:
            n_dir = Vector((1.0, 0.0, 0.0))
        n_dir.normalize()
        side = Vector((-n_dir.y, n_dir.x, 0.0))
        # Moss pad clinging to rock
        for _ in range(3):
            off = side * rng.uniform(-0.35, 0.35) * scale + Vector((0, 0, rng.uniform(-0.22, 0.22) * scale))
            m = Matrix.Translation(pos + off) @ Matrix.Scale(0.28 * scale, 4, (1, 0, 0)) @ Matrix.Scale(0.28 * scale, 4, (0, 1, 0)) @ Matrix.Scale(0.16 * scale, 4, (0, 0, 1))
            res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=m)
            for v in res["verts"]:
                for f in v.link_faces:
                    f.material_index = 5
        # Radiating luminous fern blades arching gracefully outward
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
        """Hanging cave vine with softly swaying segments & glowing amber/aqua berries."""
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
            # Thin vine stem segment
            mid = (prev + cur) * 0.5
            seg_v = cur - prev
            slen = max(0.05, seg_v.length)
            quat = Vector((0, 0, 1)).rotation_difference(seg_v.normalized())
            m = Matrix.Translation(mid) @ quat.to_matrix().to_4x4()
            res = bmesh.ops.create_cone(bm, cap_ends=False, segments=5, radius1=0.022, radius2=0.026, depth=slen, matrix=m)
            for v in res["verts"]:
                for f in v.link_faces:
                    f.material_index = 0
            # Glowing berry cluster every 1-2 segments + tip!
            if si % 2 == 0 or si == n_segs:
                brad = rng.uniform(0.085, 0.135) if si == n_segs else rng.uniform(0.065, 0.105)
                off = Vector((rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), 0.0))
                res_b = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=brad, matrix=Matrix.Translation(cur + off))
                for v in res_b["verts"]:
                    for f in v.link_faces:
                        f.material_index = b_mat
            prev = cur

    # 1) Populate wall & pillar flora anchors with tasteful sculptural mushroom clusters & luminous moss/ferns
    for idx, (pos, inward) in enumerate(anchors):
        # Keep mural & chronicle panels unobstructed on Mid-Gallery walls!
        if 7.5 <= pos.y <= 13.0 and (pos.x < -6.2 or pos.x > 1.5) and 1.0 <= pos.z <= 3.8:
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

    # 2) Drape 26 lush hanging glow-vines around Mid-Gallery Skylight, Throat Arch, Grand Hall perimeter & '一线天'!
    # Around Mid-Gallery Skylight rim (warm golden glow berries catching daylight!)
    for k in range(10):
        ang = (k / 10.0) * math.tau + 0.18
        vx = SKY_WINDOW_CTR[0] + math.cos(ang) * (SKY_WINDOW_RAD[0] + 0.35)
        vy = SKY_WINDOW_CTR[1] + math.sin(ang) * (SKY_WINDOW_RAD[1] + 0.35)
        cx, hw, ch = sample_spine(vy)
        vz = FLOOR_Z + ch * 0.90
        add_hanging_glow_vine(Vector((vx, vy, vz)), rng.uniform(1.8, 3.4), gold_berries=(k % 3 != 0))

    # Along Grand Cavern Hall high walls & outer vault (mix of aqua & gold glow-vines!)
    for k in range(16):
        vy = rng.uniform(14.5, 31.8)
        cx, hw, ch = sample_spine(vy)
        side = -1.0 if (k % 2 == 0) else 1.0
        vx = cx + side * rng.uniform(hw * 0.58, hw * 0.84)
        frac_x = abs(vx - cx) / max(1.0, hw)
        vz = FLOOR_Z + ch * (max(0.25, 1.0 - frac_x * frac_x) ** 0.42)
        vlen = rng.uniform(2.0, 4.2)
        if vz - vlen > 3.6:
            add_hanging_glow_vine(Vector((vx, vy, vz)), vlen, gold_berries=(k % 3 == 0))

    # Subtle glowing vines framing the Entrance Throat ceiling arch (inviting players deeper!)
    for vy, side in [(-3.8, -1.0), (-1.2, 1.0), (2.4, -1.0), (5.4, 1.0)]:
        cx, hw, ch = sample_spine(vy)
        vx = cx + side * (hw * 0.65)
        vz = FLOOR_Z + ch * 0.84
        add_hanging_glow_vine(Vector((vx, vy, vz)), rng.uniform(0.95, 1.45), gold_berries=False)

    # Extra dense bioluminescent mushrooms & jade moss around the Jade Spring Pool & '一线天' sanctum!
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


def build_textured_panel(name: str, center: Vector, size_wh: tuple[float, float], yaw_deg: float, mat: bpy.types.Material, parent: bpy.types.Object) -> bpy.types.Object:
    """Create a recessed carved stone tablet/mural panel with clean [0..1] planar UVs facing normal."""
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    w, h = size_wh[0] * 0.5, size_wh[1] * 0.5
    t = 0.14
    rot = Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
    # Front face lies on y_local = -t/2 facing -Y (rotated by yaw_deg)
    corners = [
        Vector((-w, -t * 0.5, -h)),
        Vector(( w, -t * 0.5, -h)),
        Vector(( w, -t * 0.5,  h)),
        Vector((-w, -t * 0.5,  h)),
    ]
    back = [
        Vector((-w - 0.06, t * 0.5, -h - 0.06)),
        Vector(( w + 0.06, t * 0.5, -h - 0.06)),
        Vector(( w + 0.06, t * 0.5,  h + 0.06)),
        Vector((-w - 0.06, t * 0.5,  h + 0.06)),
    ]
    fv = [bm.verts.new(center + rot @ p) for p in corners]
    bv = [bm.verts.new(center + rot @ p) for p in back]
    f_front = bm.faces.new((fv[0], fv[1], fv[2], fv[3]))
    uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    for lp, uv in zip(f_front.loops, uvs):
        lp[uv_layer].uv = uv
    # Side bevel frame
    for i in range(4):
        ni = (i + 1) % 4
        fs = bm.faces.new((fv[ni], fv[i], bv[i], bv[ni]))
        for lp in fs.loops:
            lp[uv_layer].uv = (0.04, 0.04)
    return bm_to_object(name, bm, [mat], parent, uv_scale=None, smooth=False)


def build_skylight_beams(parent: bpy.types.Object, mat_beam) -> bpy.types.Object:
    """Build 2 dramatic volumetric translucent light shafts for Mid-Gallery Skylight & Deep '一线天'."""
    bm = bmesh.new()
    # 1) Mid-Gallery Skylight slanted sunbeam cone
    n_seg = 16
    top_r = [bm.verts.new((SKY_WINDOW_CTR[0] + math.cos(i / n_seg * math.tau) * 1.95, SKY_WINDOW_CTR[1] + math.sin(i / n_seg * math.tau) * 1.65, 13.5)) for i in range(n_seg)]
    bot_r = [bm.verts.new((SKY_WINDOW_CTR[0] + 0.9 + math.cos(i / n_seg * math.tau) * 3.15, SKY_WINDOW_CTR[1] + 0.6 + math.sin(i / n_seg * math.tau) * 2.70, FLOOR_Z + 0.05)) for i in range(n_seg)]
    for i in range(n_seg):
        ni = (i + 1) % n_seg
        bm.faces.new((bot_r[i], bot_r[ni], top_r[ni], top_r[i]))

    # 2) Deep Sanctum '一线天' towering vertical light curtain descending onto Dimensional Rift Wall!
    for dx in (-0.42, 0.0, 0.42):
        v0 = bm.verts.new((YIXIANTIAN_X + dx, YIXIANTIAN_Y0 + 0.2, FLOOR_Z + 0.08))
        v1 = bm.verts.new((YIXIANTIAN_X + dx, YIXIANTIAN_Y1 - 0.1, FLOOR_Z + 0.08))
        v2 = bm.verts.new((YIXIANTIAN_X + dx * 0.6, YIXIANTIAN_Y1 - 0.1, 16.5))
        v3 = bm.verts.new((YIXIANTIAN_X + dx * 0.6, YIXIANTIAN_Y0 + 0.2, 16.5))
        bm.faces.new((v0, v1, v2, v3))

    return bm_to_object("Cave_Skylight_Beams", bm, [mat_beam], parent, uv_scale=0.12, smooth=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # Extract original carved mural/chronicle/plaque textures from v062_bamboo_cave.glb
    art = extract_v062_textures()

    # Load TRUE SEAMLESS tileable Poly Haven CC0 PBR cliff, mossy rock & alpine grass textures from assets/pbr_v097/
    pbr_dir = REPO_ROOT / "game" / "assets" / "pbr_v097"
    img_rock_diff = load_packed_img(pbr_dir / "cliff_side_diff.jpg", "sRGB", 1024, "CaveCliff_Diff")
    img_rock_norm = load_packed_img(pbr_dir / "cliff_side_nor_gl.jpg", "Non-Color", 1024, "CaveCliff_Norm")
    img_moss_diff = load_packed_img(pbr_dir / "mossy_rock_diff.jpg", "sRGB", 1024, "MtnMossRock_Diff")
    img_moss_norm = load_packed_img(pbr_dir / "mossy_rock_nor_gl.jpg", "Non-Color", 1024, "MtnMossRock_Norm")
    img_grass_diff = load_packed_img(pbr_dir / "aerial_grass_rock_diff.jpg", "sRGB", 1024, "MtnGrass_Diff")
    img_grass_norm = load_packed_img(pbr_dir / "aerial_grass_rock_nor_gl.jpg", "Non-Color", 1024, "MtnGrass_Norm")
    assert img_rock_diff is not None and img_moss_diff is not None and img_grass_diff is not None, "Missing seamless pbr_v097 textures!"

    # Materials (rich subterranean dark limestone + restrained sculptural bioluminescence!)
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
    mat_mtn_cliff = make_pbr_mat(
        "Mat_MountainCliff", (0.76, 0.80, 0.74, 1.0), roughness=0.88,
        albedo_img=img_moss_diff, normal_img=img_moss_norm, normal_scale=0.78,
    )
    mat_mtn_grass = make_pbr_mat(
        "Mat_MountainGrass", (0.68, 0.76, 0.60, 1.0), roughness=0.90,
        albedo_img=img_grass_diff, normal_img=img_grass_norm, normal_scale=0.65,
    )
    mat_spring_water = make_pbr_mat(
        "Mat_JadeSpringWater", (0.10, 0.56, 0.58, 1.0), roughness=0.14,
        emission_rgba=(0.14, 0.72, 0.70, 1.0), emission_strength=0.45, alpha=0.88,
    )
    # Bioluminescent Cave Wall Flora materials (rich saturated jade/cyan/gold without GL whiteout!)
    mat_vine = make_pbr_mat("Mat_GlowVineStem", (0.09, 0.26, 0.19, 1.0), roughness=0.78, double_sided=True)
    mat_berry_gold = make_pbr_mat(
        "Mat_GlowBerryGold", (1.0, 0.76, 0.24, 1.0), roughness=0.28,
        emission_rgba=(1.0, 0.72, 0.18, 1.0), emission_strength=1.55,
    )
    mat_berry_cyan = make_pbr_mat(
        "Mat_GlowBerryCyan", (0.18, 0.88, 0.88, 1.0), roughness=0.26,
        emission_rgba=(0.14, 0.84, 0.86, 1.0), emission_strength=1.45,
    )
    mat_fungi_cyan = make_pbr_mat(
        "Mat_GlowFungiCyan", (0.06, 0.50, 0.68, 1.0), roughness=0.40,
        emission_rgba=(0.06, 0.58, 0.78, 1.0), emission_strength=0.82, double_sided=True,
    )
    mat_fungi_teal = make_pbr_mat(
        "Mat_GlowFungiTeal", (0.08, 0.58, 0.42, 1.0), roughness=0.42,
        emission_rgba=(0.08, 0.62, 0.44, 1.0), emission_strength=0.72, double_sided=True,
    )
    mat_moss_jade = make_pbr_mat(
        "Mat_GlowMossJade", (0.08, 0.44, 0.34, 1.0), roughness=0.66,
        emission_rgba=(0.08, 0.50, 0.38, 1.0), emission_strength=0.58, double_sided=True,
    )
    mat_beam = make_pbr_mat(
        "Mat_SkylightMistBeam", (0.76, 0.94, 0.98, 1.0), roughness=1.0,
        emission_rgba=(0.64, 0.88, 0.96, 1.0), emission_strength=0.45, alpha=0.10, double_sided=True,
    )

    # Reused art panels (plaque, mural, chronicle)
    mat_plaque = make_pbr_mat(
        "Mat_YanxiaPlaque", (0.95, 0.95, 0.92, 1.0), roughness=0.80,
        albedo_img=art.get("plaque_yanxia_cave"),
    )
    mat_mural = make_pbr_mat(
        "Mat_YanxiaMural", (0.96, 0.94, 0.88, 1.0), roughness=0.82,
        albedo_img=art.get("mural_yanxia_ancients"), normal_img=art.get("mural_yanxia_normal"), normal_scale=0.85,
        emission_rgba=(0.75, 0.85, 0.78, 1.0), emission_strength=0.22,
    )
    mat_chronicle = make_pbr_mat(
        "Mat_YanxiaChronicle", (0.95, 0.93, 0.88, 1.0), roughness=0.80,
        albedo_img=art.get("inscription_cave_chronicle"), normal_img=art.get("chronicle_normal"), normal_scale=0.85,
        emission_rgba=(0.82, 0.80, 0.72, 1.0), emission_strength=0.22,
    )

    # Build canonical hierarchy under root 'YanxiaGrandCave'
    root = bpy.data.objects.new("YanxiaGrandCave", None)
    bpy.context.scene.collection.objects.link(root)

    interior_obj, wall_anchors = build_interior_cavern(root, mat_cave_wall, mat_cave_floor, mat_stalactite, mat_chimney)
    mountain_obj = build_exterior_mountain(root, mat_mtn_cliff, mat_mtn_grass)
    pillars_obj, pillar_anchors = build_hall_pillars(root, mat_cave_wall, mat_stalactite)
    pool_obj = build_jade_spring_pool(root, mat_spring_water, mat_cave_wall)
    flora_obj = build_bioluminescent_flora(
        root, wall_anchors + pillar_anchors,
        mat_vine, mat_berry_gold, mat_berry_cyan, mat_fungi_cyan, mat_fungi_teal, mat_moss_jade,
    )
    beams_obj = build_skylight_beams(root, mat_beam)

    # Mount ancient plaques/murals cleanly on South Cave Mouth brow & Mid-Gallery walls!
    plaque_obj = build_textured_panel("Cave_Portal_Plaque", Vector((0.0, -7.78, 4.25)), (2.55, 0.82), 0.0, mat_plaque, root)
    # West wall of Mid-Gallery (y = 10.2, x_wall ~ -2.65 - 6.5 = -9.15 -> mount cleanly proud at -8.45 facing East/+X!)
    mural_obj = build_textured_panel("Cave_Mural_Slab", Vector((-8.45, 10.20, 2.35)), (3.30, 2.10), 82.0, mat_mural, root)
    # East wall of Mid-Gallery (y = 9.8, x_wall ~ -2.65 + 6.4 = +3.75 -> mount cleanly proud at +3.10 facing West/-X!)
    chron_obj = build_textured_panel("Cave_Chronicle_Slab", Vector((3.10, 9.80, 2.25)), (2.50, 1.65), -82.0, mat_chronicle, root)

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

    # Audit exported GLB TEXCOORDS & size
    raw_b = OUT_GLB.read_bytes()
    jlen = struct.unpack("<I", raw_b[12:16])[0]
    g = json.loads(raw_b[20 : 20 + jlen])
    tcs = sorted({k for m in g.get("meshes", []) for pr in m.get("primitives", []) for k in pr.get("attributes", {}) if k.startswith("TEXCOORD")})
    miss = sum(1 for m in g.get("meshes", []) for pr in m.get("primitives", []) if "TEXCOORD_0" not in pr.get("attributes", {}))
    print(f"EXPORTED_GRAND_CAVE {OUT_GLB.name} ({len(raw_b)/1048576:.2f} MiB | {total_polys} polys | meshes={len(g.get('meshes', []))} | TEXCOORDS={tcs} | missing_uv0={miss})")


if __name__ == "__main__":
    main()
