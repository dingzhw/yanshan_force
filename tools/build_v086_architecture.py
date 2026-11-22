"""Build handcrafted Jiangnan mountain architecture, scenic micro-props, and 3D distant mountain ring
for Yanshan Force v0.8.6 in Blender 4.5.

Run with Blender 4.5:
  blender --background --python tools/build_v086_architecture.py

Outputs:
  game/assets/slice/v086_architecture.glb
    - watchtower_jiangnan      : Stone-plinth timber watchtower with flying-eave roof & lanterns (Route C compatible!)
    - bamboo_shelter_jiangnan  : Carved-column Jiangnan rest shelter with flying eaves & stone drum bases (Route B compatible!)
    - tea_pavilion_upgraded    : Double-eave hexagonal Jiangnan tea pavilion with lattice benches & lantern
    - wangdao_terrace_trim     : Ashlar pilasters, carved cornice & stone lanterns dressing Wangdao terrace
    - jiangnan_signboard_frame : Roofed dark-timber & tile trail signboard frame
    - stone_lantern            : Carved hexagonal Jiangnan bluestone garden lantern with warm glow
    - mountain_arch_gate       : 5.4m-wide Jiangnan flying-eave trailhead archway
    - tea_terraced_hedge       : Sculpted emerald tea-bush terrace hedgerow
    - mossy_boulder_cluster    : Sculpted Jiangnan mossy limestone outcrop cluster
    - trail_stone_bench        : Carved bluestone wayside rest bench
    - distant_peaks_ring       : True 3D sculpted parallax mountain ridge ring (r=255m, vertex-colored Qinglu mist)
"""
from __future__ import annotations

import math
import random
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "v086_architecture.glb"


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb_lin(rgb: tuple[float, float, float]) -> tuple[float, float, float, float]:
    return (rgb[0] ** 2.2, rgb[1] ** 2.2, rgb[2] ** 2.2, 1.0)


def make_mat(name: str, rgb: tuple[float, float, float], rough=0.80, metal=0.05, emit=None, emit_str=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = srgb_lin(rgb)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None and emit_str > 0.0:
        bsdf.inputs["Emission Color"].default_value = srgb_lin(emit)
        bsdf.inputs["Emission Strength"].default_value = emit_str
    return mat


def make_vcol_mat(name: str, rough=0.88):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.0
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def gd_to_bl(v: tuple[float, float, float]) -> Vector:
    """Godot (x right, y up, z back) -> Blender (x right, y forward=-z, z up=y)."""
    return Vector((v[0], -v[2], v[1]))


def add_box(bm: bmesh.types.BMesh, center_gd, size_gd, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    scale = Matrix.Diagonal((size_gd[0], size_gd[2], size_gd[1], 1.0))
    xf = Matrix.Translation(gd_to_bl(center_gd)) @ rot @ scale
    bmesh.ops.transform(bm, matrix=xf, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl(bm: bmesh.types.BMesh, center_gd, r_bot, r_top, height, segs=10, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_bot, radius2=r_top, depth=height)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    xf = Matrix.Translation(gd_to_bl(center_gd)) @ rot
    bmesh.ops.transform(bm, matrix=xf, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl_pts(bm: bmesh.types.BMesh, p0_gd, p1_gd, r0, r1, segs=8, mat_idx=0):
    a = gd_to_bl(p0_gd)
    b = gd_to_bl(p1_gd)
    delta = b - a
    length = delta.length
    if length < 1e-4:
        return
    rot = Vector((0, 0, 1)).rotation_difference(delta.normalized()).to_matrix().to_4x4()
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=length)
    verts = ret["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) * 0.5) @ rot, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_lobe(bm: bmesh.types.BMesh, center_gd, radii_gd, seed=0, subdiv=2, amp=0.14, mat_idx=0):
    rng = random.Random(seed)
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    verts = ret["verts"]
    c = gd_to_bl(center_gd)
    rx, ry, rz = radii_gd
    for v in verts:
        n = 1.0 + rng.uniform(-amp, amp) + 0.06 * math.sin(v.co.x * 4.5 + seed) * math.cos(v.co.y * 4.2)
        v.co = Vector((v.co.x * rx * n, v.co.y * rz * n, v.co.z * ry * n)) + c
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_flying_eave_roof(
    bm: bmesh.types.BMesh,
    center_gd: tuple[float, float, float],
    half_x: float,
    half_z: float,
    ridge_h: float,
    eave_flare: float,
    mat_tile: int,
    mat_ridge: int,
    mat_wood: int,
    sides: int = 4,
):
    """Build a 100% SOLID WATERTIGHT concave upward-sweeping Jiangnan flying-eave tiled roof (square or hexagonal).
    Includes thick upper dark-slate tiled shell, warm cedar underside soffit, closed fascia rim, and curved hip ribs
    hugging the exact catenary roof contour (ZERO backface culling holes, ZERO floating sticks!)."""
    cx, cy, cz = center_gd
    rings = 6
    thick = 0.16

    def sample_ring_pts(t: float):
        if sides == 4:
            sx = half_x * (1.0 - t * 0.90)
            sz = half_z * (1.0 - t * 0.90)
            y_base = cy + ridge_h * (t ** 1.38)
            pts = []
            corners = [(-sx, -sz), (sx, -sz), (sx, sz), (-sx, sz)]
            for ci in range(4):
                ax, az = corners[ci]
                bx, bz = corners[(ci + 1) % 4]
                for sub in range(4):
                    u = sub / 4.0
                    px = ax + (bx - ax) * u
                    pz = az + (bz - az) * u
                    # Smooth quadratic corner uplift peaking cleanly at corners (sub==0)
                    d_corner = min(u, 1.0 - u) * 2.0  # 0 at corner, 1 at midpoint
                    corner_f = (1.0 - d_corner) ** 2.0
                    up_sweep = eave_flare * ((1.0 - t) ** 2.0) * (0.14 + 0.86 * corner_f)
                    pts.append((cx + px, y_base + up_sweep, cz + pz))
            return pts
        else:
            rad = half_x * (1.0 - t * 0.92)
            y_base = cy + ridge_h * (t ** 1.42)
            pts = []
            for ci in range(sides):
                a0 = ci * math.tau / sides
                a1 = (ci + 1) * math.tau / sides
                x0, z0 = math.cos(a0) * rad, math.sin(a0) * rad
                x1, z1 = math.cos(a1) * rad, math.sin(a1) * rad
                for sub in range(3):
                    u = sub / 3.0
                    px = x0 + (x1 - x0) * u
                    pz = z0 + (z1 - z0) * u
                    d_corner = min(u, 1.0 - u) * 2.0
                    corner_f = (1.0 - d_corner) ** 2.0
                    up_sweep = eave_flare * ((1.0 - t) ** 2.0) * (0.12 + 0.88 * corner_f)
                    pts.append((cx + px, y_base + up_sweep, cz + pz))
            return pts

    top_loops = []
    bot_loops = []
    top_coords = []
    for ri in range(rings + 1):
        t = ri / float(rings)
        ring_gd = sample_ring_pts(t)
        top_coords.append(ring_gd)
        t_loop = [bm.verts.new(gd_to_bl(p)) for p in ring_gd]
        b_loop = [bm.verts.new(gd_to_bl((p[0], p[1] - thick, p[2]))) for p in ring_gd]
        top_loops.append(t_loop)
        bot_loops.append(b_loop)

    n_per = len(top_loops[0])
    # 1) Upper tiled roof surface (outward upward normals)
    for ri in range(rings):
        a_l, b_l = top_loops[ri], top_loops[ri + 1]
        for j in range(n_per):
            jn = (j + 1) % n_per
            f = bm.faces.new([a_l[j], b_l[j], b_l[jn], a_l[jn]])
            f.material_index = mat_tile

    # 2) Lower cedar soffit surface (outward downward normals — reversed winding!)
    for ri in range(rings):
        a_l, b_l = bot_loops[ri], bot_loops[ri + 1]
        for j in range(n_per):
            jn = (j + 1) % n_per
            f = bm.faces.new([a_l[j], a_l[jn], b_l[jn], b_l[j]])
            f.material_index = mat_wood

    # 3) Solid outer eave fascia edge connecting top_loops[0] & bot_loops[0]
    for j in range(n_per):
        jn = (j + 1) % n_per
        f = bm.faces.new([top_loops[0][j], top_loops[0][jn], bot_loops[0][jn], bot_loops[0][j]])
        f.material_index = mat_ridge

    # 4) Close apex cap on both top and bottom so the roof is a 100% closed watertight manifold!
    apex_top = bm.verts.new(gd_to_bl((cx, cy + ridge_h + 0.08, cz)))
    apex_bot = bm.verts.new(gd_to_bl((cx, cy + ridge_h - thick + 0.04, cz)))
    for j in range(n_per):
        jn = (j + 1) % n_per
        ft = bm.faces.new([top_loops[-1][j], apex_top, top_loops[-1][jn]])
        ft.material_index = mat_tile
        fb = bm.faces.new([bot_loops[-1][j], bot_loops[-1][jn], apex_bot])
        fb.material_index = mat_wood

    # 5) Curved carved stone hip ribs strictly following the catenary roof profile along every corner!
    step_per_side = 4 if sides == 4 else 3
    for ci in range(sides):
        idx = ci * step_per_side
        for ri in range(rings):
            p0 = top_coords[ri][idx]
            p1 = top_coords[ri + 1][idx]
            q0 = (p0[0], p0[1] + 0.055, p0[2])
            q1 = (p1[0], p1[1] + 0.055, p1[2])
            add_cyl_pts(bm, q0, q1, 0.062, 0.052, 6, mat_ridge)
        # Upturned corner horn finial right at the eave corner tip (snug, never floating!)
        tip = top_coords[0][idx]
        dir_x = tip[0] - cx
        dir_z = tip[2] - cz
        d_len = max(0.01, math.hypot(dir_x, dir_z))
        horn_end = (tip[0] + (dir_x / d_len) * 0.14, tip[1] + 0.14, tip[2] + (dir_z / d_len) * 0.14)
        add_cyl_pts(bm, (tip[0], tip[1] + 0.04, tip[2]), horn_end, 0.058, 0.028, 6, mat_ridge)

    # 6) Under-eave timber cornice ring & ornate top ridge + lotus finial
    if sides == 4:
        add_box(bm, (cx, cy - 0.14, cz), (half_x * 1.38, 0.16, half_z * 1.38), mat_wood)
        add_box(bm, (cx, cy + ridge_h + 0.11, cz), (max(0.36, half_x * 0.34), 0.16, 0.16), mat_ridge)
    else:
        add_cyl(bm, (cx, cy - 0.14, cz), half_x * 0.72, half_x * 0.72, 0.16, sides, mat_wood)
    add_cyl(bm, (cx, cy + ridge_h + 0.32, cz), 0.13, 0.03, 0.38, 8, mat_ridge)


def finalize_obj(name: str, bm: bmesh.types.BMesh, mats: list, smooth_all: bool = False):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    if smooth_all:
        for p in mesh.polygons:
            p.use_smooth = True
    for m in mats:
        mesh.materials.append(m)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_watchtower_jiangnan(mats):
    """Handcrafted Jiangnan stone-base & flying-eave timber watchtower ('烟山飞檐望楼').
    Strictly honors Route C spiral parkour decks at y=1.00, 3.44, 5.86 and 4 corner legs at (+-0.90, +-0.90)!"""
    bm = bmesh.new()
    # 0=stone, 1=stone_dark, 2=wood_dark, 3=wood_warm, 4=tile, 5=ridge, 6=gold, 7=lantern_glow, 8=plaster
    # 1) Chamfered carved bluestone masonry ground foundation (y = -0.50 .. 0.96, clears 1st deck y=1.00!)
    add_box(bm, (0.0, 0.18, 0.0), (2.42, 1.38, 2.42), 0)
    add_box(bm, (0.0, 0.90, 0.0), (2.58, 0.14, 2.58), 1)
    # Recessed plastered ground stone tower core with carved doorway & arched timber frame
    add_box(bm, (0.0, 2.22, 0.0), (1.42, 2.38, 1.42), 8)
    add_box(bm, (0.0, 1.85, 0.72), (0.64, 1.30, 0.08), 2)
    add_box(bm, (0.0, 2.54, 0.73), (0.76, 0.12, 0.10), 3)
    # Stone corner pilasters & column drum plinths (柱础)
    for sx in (-0.90, 0.90):
        for sz in (-0.90, 0.90):
            add_cyl(bm, (sx, 1.12, sz), 0.24, 0.19, 0.22, 8, 1)
            # Full-height tapered cedar corner column (y = 0.0 .. 7.52, supporting flying-eave roof above summit!)
            add_cyl(bm, (sx, 3.76, sz), 0.135, 0.115, 7.52, 8, 2)
            # Decorative Dougong corbel brackets under Deck 2 (y=3.44), Summit (y=5.86), and Roof Eaves (y=7.48)
            for by in (3.24, 5.66, 7.36):
                add_box(bm, (sx, by, sz), (0.34, 0.18, 0.34), 3)
                add_box(bm, (sx, by + 0.12, sz), (0.46, 0.10, 0.46), 2)

    # 2) Three carved timber floor decks with perimeter trim beams (exact match y = 1.00, 3.44, 5.86!)
    for y_d, sz_d in ((1.00, 2.24), (3.44, 2.36), (5.86, 2.44)):
        add_box(bm, (0.0, y_d, 0.0), (sz_d, 0.14, sz_d), 3)
        for edge in (-sz_d * 0.5, sz_d * 0.5):
            add_box(bm, (0.0, y_d - 0.08, edge), (sz_d + 0.12, 0.14, 0.12), 2)
            add_box(bm, (edge, y_d - 0.08, 0.0), (0.12, 0.14, sz_d + 0.12), 2)

    # 3) Decorative Jiangnan X-lattice perimeter guardrails on Summit Gallery (leaving South-West step opening clear!)
    # Open on Z=+1.16 (where C6 step enters at (-0.35, 5.32, 2.05) -> summit (-0.15, 5.92, 0.55))
    rail_y = 6.32
    for rx_side in (-1.14, 1.14):
        add_box(bm, (rx_side, rail_y + 0.36, 0.0), (0.09, 0.09, 2.28), 2)
        add_box(bm, (rx_side, rail_y - 0.24, 0.0), (0.07, 0.07, 2.24), 3)
        for kz in (-0.65, 0.0, 0.65):
            add_box(bm, (rx_side, rail_y + 0.06, kz), (0.07, 0.62, 0.07), 3)
    # North side summit railing
    add_box(bm, (0.0, rail_y + 0.36, -1.14), (2.28, 0.09, 0.09), 2)
    add_box(bm, (0.0, rail_y - 0.24, -1.14), (2.24, 0.07, 0.07), 3)
    for kx in (-0.65, 0.0, 0.65):
        add_box(bm, (kx, rail_y + 0.06, -1.14), (0.07, 0.62, 0.07), 3)

    # 4) Crown Flying-Eave Jiangnan Tiled Roof (y = 7.56 .. 9.10m — soaring high above summit crate!)
    add_flying_eave_roof(bm, (0.0, 7.56, 0.0), 2.18, 2.18, 1.48, 0.42, 4, 5, 2, sides=4)
    # Gilded ridge finial & 4 warm glowing corner lanterns hanging from the upturned eaves!
    add_cyl(bm, (0.0, 9.24, 0.0), 0.09, 0.02, 0.32, 8, 6)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            lx, lz = sx * 1.72, sz * 1.72
            add_cyl(bm, (lx, 7.34, lz), 0.015, 0.015, 0.38, 6, 2)
            add_cyl(bm, (lx, 7.04, lz), 0.14, 0.14, 0.26, 8, 7)
            add_cyl(bm, (lx, 7.18, lz), 0.16, 0.08, 0.06, 8, 2)
            add_cyl(bm, (lx, 6.90, lz), 0.08, 0.14, 0.05, 8, 6)

    return finalize_obj("watchtower_jiangnan", bm, mats)


def build_bamboo_shelter_jiangnan(mats):
    """Handcrafted Jiangnan timber & grey-tile rest shelter ('烟山飞檐歇脚棚').
    Matches exact Route B walkable roof deck height at y = 3.485 (5.8 x 3.8m) with ornamental upturned eaves!"""
    bm = bmesh.new()
    # 1) Stone foundation plinth & 4 carved stone drum bases (柱础)
    add_box(bm, (0.0, 0.04, 0.0), (5.55, 0.22, 4.10), 0)
    for sx in (-2.50, 2.50):
        for sz in (-1.80, 1.80):
            add_cyl(bm, (sx, 0.24, sz), 0.26, 0.20, 0.24, 8, 1)
            add_cyl(bm, (sx, 1.80, sz), 0.14, 0.125, 3.28, 8, 2)
            # Carved wooden knee braces (雀替)
            in_x = -0.35 if sx > 0 else 0.35
            in_z = -0.35 if sz > 0 else 0.35
            add_cyl_pts(bm, (sx, 2.74, sz), (sx + in_x, 3.24, sz), 0.06, 0.06, 6, 3)
            add_cyl_pts(bm, (sx, 2.74, sz), (sx, 3.24, sz + in_z), 0.06, 0.06, 6, 3)

    # 2) Perimeter timber tie-beams & back/side low decorative Jiangnan railings (front +Z open!)
    for sx in (-2.50, 2.50):
        add_box(bm, (sx, 3.28, 0.0), (0.18, 0.18, 3.88), 2)
    for sz in (-1.80, 1.80):
        add_box(bm, (0.0, 3.28, sz), (5.26, 0.18, 0.18), 2)
    # Decorative rear lattice screen along z=-1.80
    add_box(bm, (0.0, 0.62, -1.80), (4.84, 0.90, 0.10), 3)
    for bx in (-1.6, -0.8, 0.0, 0.8, 1.6):
        add_box(bm, (bx, 1.65, -1.80), (0.08, 1.18, 0.08), 2)

    # 3) Walkable dark-slate flat timber roof deck at exact y=3.42 (top y=3.485 for Route B crate!)
    # Framed by upturned traditional Jiangnan corner eaves & dark clay tile drip skirt!
    add_box(bm, (0.0, 3.41, 0.0), (5.84, 0.15, 4.04), 4)
    # Sculpted overlapping tiled eave skirts jutting outward and curving upward at corners
    for sz_s in (-1.0, 1.0):
        add_box(bm, (0.0, 3.36, sz_s * 2.26), (6.36, 0.12, 0.56), 4, rot_deg_gd=(sz_s * 14.0, 0.0, 0.0))
    for sx_s in (-1.0, 1.0):
        add_box(bm, (sx_s * 3.16, 3.36, 0.0), (0.56, 0.12, 4.52), 4, rot_deg_gd=(0.0, 0.0, -sx_s * 14.0))
    # Upturned eave ridge ornaments at all 4 corners + hanging lanterns
    for sx_s in (-1.0, 1.0):
        for sz_s in (-1.0, 1.0):
            add_cyl_pts(bm, (sx_s * 2.6, 3.48, sz_s * 1.85), (sx_s * 3.48, 3.74, sz_s * 2.55), 0.075, 0.045, 6, 5)
            add_cyl(bm, (sx_s * 2.86, 2.94, sz_s * 2.08), 0.12, 0.12, 0.22, 8, 7)
            add_cyl(bm, (sx_s * 2.86, 3.16, sz_s * 2.08), 0.015, 0.015, 0.26, 6, 2)

    # 4) Carved dark timber supply workbench inside shelter
    add_box(bm, (0.0, 1.00, -1.25), (3.45, 0.12, 0.84), 3)
    for lx in (-1.42, 1.42):
        add_box(bm, (lx, 0.52, -1.25), (0.14, 0.94, 0.70), 2)
    return finalize_obj("bamboo_shelter_jiangnan", bm, mats)


def build_tea_pavilion_upgraded(mats):
    """Ornate hexagonal double-eave Jiangnan tea-hill pavilion ('东岭飞檐茶亭')."""
    bm = bmesh.new()
    # 1) Two-step carved hexagonal bluestone base
    add_cyl(bm, (0.0, 0.12, 0.0), 3.32, 3.24, 0.30, 6, 0)
    add_cyl(bm, (0.0, 0.34, 0.0), 2.94, 2.88, 0.20, 6, 1)
    # 2) 6 carved cedar columns on stone drum plinths + Meirenkao (美人靠) curved backrest benches on 4 sides
    col_r = 2.48
    for i in range(6):
        ang = i * math.tau / 6.0
        cx, cz = math.cos(ang) * col_r, math.sin(ang) * col_r
        add_cyl(bm, (cx, 0.52, cz), 0.22, 0.17, 0.20, 8, 1)
        add_cyl(bm, (cx, 1.88, cz), 0.125, 0.11, 2.66, 8, 2)
        # Decorative lintel & carved arch bracket to next pillar
        ang2 = (i + 1) * math.tau / 6.0
        nx, nz = math.cos(ang2) * col_r, math.sin(ang2) * col_r
        mx, mz = 0.5 * (cx + nx), 0.5 * (cz + nz)
        yaw_deg = math.degrees(math.atan2(nx - cx, nz - cz))
        edge_len = math.hypot(nx - cx, nz - cz)
        add_box(bm, (mx, 3.14, mz), (0.14, 0.22, edge_len), 2, rot_deg_gd=(0.0, yaw_deg, 0.0))
        # Leave 2 opposite doorways open (i == 0 and i == 3); build curved timber benches + lattice rail on other 4!
        if i not in (0, 3):
            add_box(bm, (mx, 0.84, mz), (0.44, 0.09, edge_len - 0.18), 3, rot_deg_gd=(0.0, yaw_deg, 0.0))
            add_box(bm, (mx, 1.32, mz), (0.10, 0.09, edge_len - 0.12), 2, rot_deg_gd=(0.0, yaw_deg, 0.0))
            for frac in (-0.30, 0.0, 0.30):
                px = mx + (nx - cx) * frac
                pz = mz + (nz - cz) * frac
                add_box(bm, (px, 1.08, pz), (0.07, 0.44, 0.07), 3, rot_deg_gd=(0.0, yaw_deg, 0.0))
    # 3) Double-tier concave hexagonal flying-eave roof!
    add_flying_eave_roof(bm, (0.0, 3.26, 0.0), 3.68, 3.68, 1.38, 0.44, 4, 5, 2, sides=6)
    add_flying_eave_roof(bm, (0.0, 4.46, 0.0), 1.92, 1.92, 1.05, 0.28, 4, 5, 2, sides=6)
    add_cyl(bm, (0.0, 5.72, 0.0), 0.11, 0.02, 0.36, 8, 6)
    # Hanging center warm paper lantern + round carved bluestone tea table & 4 stools
    add_cyl(bm, (0.0, 2.98, 0.0), 0.018, 0.018, 0.48, 6, 2)
    add_cyl(bm, (0.0, 2.66, 0.0), 0.18, 0.18, 0.30, 10, 7)
    add_cyl(bm, (0.0, 0.78, 0.0), 0.32, 0.24, 0.68, 10, 1)
    add_cyl(bm, (0.0, 1.14, 0.0), 0.78, 0.76, 0.11, 12, 0)
    for si in range(4):
        sa = si * math.tau / 4.0 + 0.4
        add_cyl(bm, (math.cos(sa) * 1.18, 0.66, math.sin(sa) * 1.18), 0.24, 0.22, 0.44, 8, 0)
    return finalize_obj("tea_pavilion_upgraded", bm, mats)


def build_wangdao_pavilion_complete(mats):
    """Unified, bug-free Jiangnan Double-Eave Wangdao Overlook Pavilion & Bluestone Terrace ('望稻重檐观景亭台').
    Origin (0, 0, 0) = exact walkable terrace deck center (deck_y); West portal X=-3.20, Z in [-2.65, +0.95] open for stairs;
    South viewing balcony extends seamlessly to Z=+3.65 so wangdao_deck_pos (0, 0, +3.05) sits unobstructed overlooking paddies!"""
    bm = bmesh.new()
    # Materials: 0=bluestone, 1=dark_stone, 2=dark_cedar, 3=warm_timber, 4=clay_tile, 5=ridge, 6=gold, 7=lantern_glow, 8=plaster, 9=tea_dark, 10=tea_bright

    # 1) Unified Solid Bluestone Masonry Platform (X: -3.20..+3.20, Z: -3.10..+3.65, Y: -5.20..0.00)
    # Centered at (0, _, +0.275), size (6.40, _, 6.75)
    plat_cz = 0.275
    add_box(bm, (0.0, -2.69, plat_cz), (6.36, 5.02, 6.72), 0)
    # Recessed decorative masonry plinth moldings (cleanly inset behind corner pilasters)
    for y_band in (-1.30, -2.75):
        add_box(bm, (0.0, y_band, plat_cz), (6.48, 0.14, 6.84), 1)
    # Bevelled top granite cornice & flush walkable deck slab (top y = 0.00!)
    add_box(bm, (0.0, -0.09, plat_cz), (6.64, 0.18, 7.00), 1)
    add_box(bm, (0.0, -0.015, plat_cz), (6.46, 0.03, 6.82), 0)

    # 4 Carved Corner Stone Pilasters strictly at outer terrace corners (100% clear of West stair portal!)
    for sx in (-3.22, 3.22):
        for sz in (-3.12, 3.66):
            add_box(bm, (sx, -2.60, sz), (0.38, 5.20, 0.38), 1)
            add_box(bm, (sx, -0.10, sz), (0.48, 0.22, 0.48), 0)

    # Traditional Wooden Corbel Brackets (斗拱撑木) ornamenting the South Overlook cornice
    for bx in (-2.2, -1.1, 0.0, 1.1, 2.2):
        add_box(bm, (bx, -0.24, 3.62), (0.18, 0.20, 0.28), 2)
        add_box(bm, (bx, -0.38, 3.54), (0.14, 0.18, 0.20), 3)

    # 2) Unified Waist-High Jiangnan Stone-and-Cedar Perimeter Balustrade (y = 0.0..0.88m)
    def add_balustrade_seg(p0, p1):
        dx, dz = p1[0] - p0[0], p1[1] - p0[1]
        length = math.hypot(dx, dz)
        if length < 0.2:
            return
        mx, mz = 0.5 * (p0[0] + p1[0]), 0.5 * (p0[1] + p1[1])
        yaw_deg = math.degrees(math.atan2(dx, dz))
        # Lower stone curb, upper cedar handrail, middle rail & evenly spaced vertical spindles
        add_box(bm, (mx, 0.12, mz), (0.16, 0.24, length), 1, rot_deg_gd=(0.0, yaw_deg, 0.0))
        add_box(bm, (mx, 0.84, mz), (0.14, 0.09, length), 2, rot_deg_gd=(0.0, yaw_deg, 0.0))
        add_box(bm, (mx, 0.50, mz), (0.09, 0.07, length), 3, rot_deg_gd=(0.0, yaw_deg, 0.0))
        n_sp = max(2, int(round(length / 0.55)))
        for k in range(1, n_sp):
            u = k / float(n_sp)
            sx_p = p0[0] + dx * u
            sz_p = p0[1] + dz * u
            add_box(bm, (sx_p, 0.52, sz_p), (0.07, 0.60, 0.07), 3, rot_deg_gd=(0.0, yaw_deg, 0.0))

    # South viewing rail, East rail, North rail, and West South-wing rail (leaving West stair portal Z in [-2.65, +1.15] wide open!)
    add_balustrade_seg((-3.16, 3.56), (3.16, 3.56))
    add_balustrade_seg((3.16, -3.02), (3.16, 3.56))
    add_balustrade_seg((-3.16, -3.02), (3.16, -3.02))
    add_balustrade_seg((-3.16, 1.15), (-3.16, 3.56))

    # Carved stone newel posts around perimeter + 4 integrated corner bluestone lanterns seated flush on corner posts!
    post_coords = [
        (-3.16, 3.56, True), (0.0, 3.56, False), (3.16, 3.56, True),
        (3.16, 0.25, False), (3.16, -3.02, True),
        (0.0, -3.02, False), (-3.16, -3.02, True), (-3.16, 1.15, False),
    ]
    for px, pz, has_lantern in post_coords:
        add_box(bm, (px, 0.48, pz), (0.26, 0.96, 0.26), 1)
        add_box(bm, (px, 0.99, pz), (0.32, 0.08, 0.32), 0)
        if has_lantern:
            add_cyl(bm, (px, 1.14, pz), 0.14, 0.14, 0.24, 6, 7)
            for li in range(6):
                la = li * math.tau / 6.0
                add_cyl(bm, (px + math.cos(la) * 0.16, 1.14, pz + math.sin(la) * 0.16), 0.018, 0.018, 0.26, 5, 1)
            add_cyl(bm, (px, 1.35, pz), 0.26, 0.04, 0.18, 6, 4)

    # 3) Ornate Square Double-Eave Jiangnan Pavilion ('望稻重檐亭') centered at (0.0, 0.0, -0.45)
    pz0 = -0.45
    # Low crisp single-step granite pavilion floor pad (top y = 0.10m, flush step-up!)
    add_box(bm, (0.0, 0.05, pz0), (4.24, 0.10, 4.24), 0)
    # 4 Carved Drum Plinths (柱础), Dark-Cedar Columns, Arch Brackets (雀替) & Overhead Lintels (额枋)
    col_off = 1.72
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            cx, cz = sx * col_off, pz0 + sz * col_off
            add_cyl(bm, (cx, 0.22, cz), 0.24, 0.18, 0.24, 10, 1)
            add_cyl(bm, (cx, 1.66, cz), 0.125, 0.112, 2.74, 10, 2)
            # Carved knee braces (雀替) & Dougong corbel blocks under lower eaves
            add_cyl_pts(bm, (cx, 2.48, cz), (cx - sx * 0.44, 2.94, cz), 0.055, 0.055, 6, 3)
            add_cyl_pts(bm, (cx, 2.48, cz), (cx, 2.94, cz - sz * 0.44), 0.055, 0.055, 6, 3)
            add_box(bm, (cx, 3.04, cz), (0.34, 0.16, 0.34), 3)
            add_box(bm, (cx, 3.16, cz), (0.46, 0.10, 0.46), 2)

    # Perimeter upper lintels + subtle Jiangnan white-plaster fascia band (粉墙黛瓦)
    for sz_s in (-col_off, col_off):
        add_box(bm, (0.0, 2.94, pz0 + sz_s), (3.68, 0.20, 0.16), 2)
        add_box(bm, (0.0, 3.10, pz0 + sz_s), (3.52, 0.12, 0.12), 8)
    for sx_s in (-col_off, col_off):
        add_box(bm, (sx_s, 2.94, pz0), (0.16, 0.20, 3.68), 2)
        add_box(bm, (sx_s, 3.10, pz0), (0.12, 0.12, 3.52), 8)

    # Traditional Jiangnan 美人靠 (curved-backrest timber bench) on North (-Z) side only, keeping West, East & South airy!
    add_box(bm, (0.0, 0.56, pz0 - col_off + 0.14), (3.08, 0.09, 0.44), 3)
    add_box(bm, (0.0, 0.96, pz0 - col_off - 0.04), (3.08, 0.08, 0.09), 2)
    for bx in (-1.15, -0.58, 0.0, 0.58, 1.15):
        add_box(bm, (bx, 0.76, pz0 - col_off - 0.04), (0.06, 0.36, 0.06), 3)
        add_box(bm, (bx, 0.32, pz0 - col_off + 0.14), (0.08, 0.42, 0.36), 2)

    # Carved dark-cedar plaque frames mounted cleanly over West (-X, stair approach) & South (+Z, balcony) lintels!
    add_box(bm, (-col_off - 0.08, 2.66, pz0), (0.09, 0.48, 1.24), 2)
    add_box(bm, (-col_off - 0.11, 2.66, pz0), (0.04, 0.38, 1.12), 6)
    add_box(bm, (0.0, 2.66, pz0 + col_off + 0.08), (1.24, 0.48, 0.09), 2)
    add_box(bm, (0.0, 2.66, pz0 + col_off + 0.11), (1.12, 0.38, 0.04), 6)

    # 4) Grand Watertight Double-Tier Concave Jiangnan Flying-Eave Roof!
    add_flying_eave_roof(bm, (0.0, 3.22, pz0), 3.08, 3.08, 1.16, 0.42, 4, 5, 2, sides=4)
    # Upper clerestory timber & white-plaster drum (重檐腰层)
    add_box(bm, (0.0, 4.18, pz0), (2.14, 0.48, 2.14), 8)
    for sx_c in (-1.06, 1.06):
        for sz_c in (-1.06, 1.06):
            add_box(bm, (sx_c, 4.18, pz0 + sz_c), (0.14, 0.52, 0.14), 2)
    add_box(bm, (0.0, 4.44, pz0), (2.28, 0.10, 2.28), 2)
    add_flying_eave_roof(bm, (0.0, 4.48, pz0), 1.98, 1.98, 1.08, 0.32, 4, 5, 2, sides=4)
    # Ornate Gilded Gourd Roof Finial (鎏金葫芦宝顶)
    add_cyl(bm, (0.0, 5.74, pz0), 0.15, 0.08, 0.20, 10, 6)
    add_lobe(bm, (0.0, 5.94, pz0), (0.12, 0.15, 0.12), seed=17, subdiv=2, amp=0.02, mat_idx=6)
    add_cyl(bm, (0.0, 6.18, pz0), 0.045, 0.012, 0.24, 8, 6)

    # 4 Warm Glowing Hanging Lanterns suspended gracefully from lower eave corners
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            lx, lz = sx * 2.38, pz0 + sz * 2.38
            add_cyl(bm, (lx, 3.06, lz), 0.015, 0.015, 0.44, 6, 2)
            add_cyl(bm, (lx, 2.74, lz), 0.13, 0.13, 0.24, 8, 7)
            add_cyl(bm, (lx, 2.87, lz), 0.15, 0.07, 0.05, 8, 2)
            add_cyl(bm, (lx, 2.60, lz), 0.07, 0.14, 0.05, 8, 6)

    # Center Round Carved Granite Tea Table, 2 Stone Stools & Celadon Teapot
    add_cyl(bm, (0.0, 0.42, pz0), 0.26, 0.20, 0.64, 10, 1)
    add_cyl(bm, (0.0, 0.78, pz0), 0.56, 0.54, 0.10, 14, 0)
    for sx_t in (-0.88, 0.88):
        add_cyl(bm, (sx_t, 0.32, pz0 - 0.18), 0.20, 0.19, 0.44, 10, 0)
    add_lobe(bm, (-0.06, 0.90, pz0 + 0.04), (0.10, 0.08, 0.10), seed=21, subdiv=2, amp=0.03, mat_idx=10)
    add_cyl(bm, (0.16, 0.87, pz0 + 0.06), 0.035, 0.042, 0.07, 8, 10)
    add_cyl(bm, (0.14, 0.87, pz0 - 0.12), 0.035, 0.042, 0.07, 8, 10)

    return finalize_obj("wangdao_pavilion_complete", bm, mats)


def build_jiangnan_signboard_frame(mats):
    """Traditional two-post dark-timber Jiangnan signboard with solid carved plaque backing & grey-tile roof cap."""
    bm = bmesh.new()
    for sx in (-1.38, 1.38):
        add_cyl(bm, (sx, 0.14, 0.0), 0.20, 0.16, 0.28, 8, 1)
        add_cyl(bm, (sx, 1.28, 0.0), 0.095, 0.085, 2.28, 8, 2)
    add_box(bm, (0.0, 2.40, 0.0), (3.12, 0.14, 0.22), 2)
    add_box(bm, (0.0, 1.24, 0.0), (2.78, 0.10, 0.14), 3)
    # Solid dark-slate-and-cedar scenic plaque backing board so white text pops crisply (NEVER hollow/transparent!)
    add_box(bm, (0.0, 1.82, 0.0), (2.68, 1.06, 0.10), 2)
    add_box(bm, (0.0, 1.82, 0.0), (2.54, 0.92, 0.13), 4)
    # Pitched small clay-tile protective roof cap over signboard
    add_box(bm, (0.0, 2.66, 0.26), (3.44, 0.09, 0.62), 4, rot_deg_gd=(22.0, 0.0, 0.0))
    add_box(bm, (0.0, 2.66, -0.26), (3.44, 0.09, 0.62), 4, rot_deg_gd=(-22.0, 0.0, 0.0))
    add_box(bm, (0.0, 2.82, 0.0), (3.52, 0.14, 0.16), 5)
    return finalize_obj("jiangnan_signboard_frame", bm, mats)


def build_stone_lantern(mats):
    """Carved hexagonal Jiangnan bluestone garden lantern ('青石庭院石灯笼')."""
    bm = bmesh.new()
    add_cyl(bm, (0.0, 0.12, 0.0), 0.40, 0.34, 0.24, 6, 0)
    add_cyl(bm, (0.0, 0.68, 0.0), 0.15, 0.12, 0.92, 6, 1)
    add_cyl(bm, (0.0, 1.18, 0.0), 0.30, 0.26, 0.14, 6, 0)
    add_cyl(bm, (0.0, 1.44, 0.0), 0.18, 0.18, 0.36, 6, 7)
    for i in range(6):
        a = i * math.tau / 6.0
        add_cyl(bm, (math.cos(a) * 0.21, 1.44, math.sin(a) * 0.21), 0.028, 0.028, 0.38, 6, 1)
    add_cyl(bm, (0.0, 1.74, 0.0), 0.44, 0.08, 0.28, 6, 4)
    add_cyl(bm, (0.0, 1.94, 0.0), 0.08, 0.02, 0.14, 6, 0)
    return finalize_obj("stone_lantern", bm, mats)


def build_mountain_arch_gate(mats):
    """5.4m-wide Jiangnan timber & stone flying-eave mountain trail archway ('烟山山门牌坊')."""
    bm = bmesh.new()
    for sx in (-2.35, 2.35):
        add_box(bm, (sx, 0.42, 0.0), (0.68, 0.88, 0.68), 0)
        add_box(bm, (sx, 0.88, 0.0), (0.76, 0.12, 0.76), 1)
        add_cyl(bm, (sx, 2.52, 0.0), 0.18, 0.15, 3.60, 10, 2)
        # Side buttress struts
        add_cyl_pts(bm, (sx, 0.80, 0.62), (sx, 2.35, 0.0), 0.09, 0.08, 6, 3)
        add_cyl_pts(bm, (sx, 0.80, -0.62), (sx, 2.35, 0.0), 0.09, 0.08, 6, 3)
    # Upper double crossbeams & carved plaque box
    add_box(bm, (0.0, 3.55, 0.0), (5.55, 0.22, 0.28), 2)
    add_box(bm, (0.0, 4.10, 0.0), (5.85, 0.24, 0.30), 2)
    add_box(bm, (0.0, 3.82, 0.0), (1.95, 0.50, 0.18), 3)
    add_box(bm, (0.0, 3.82, 0.0), (1.76, 0.36, 0.22), 6)
    # Grand upturned flying-eave tile roof spanning the entire archway!
    add_flying_eave_roof(bm, (0.0, 4.24, 0.0), 3.45, 1.05, 0.92, 0.34, 4, 5, 2, sides=4)
    for sx in (-1.85, 1.85):
        add_cyl(bm, (sx, 3.16, 0.0), 0.14, 0.14, 0.26, 8, 7)
        add_cyl(bm, (sx, 3.42, 0.0), 0.015, 0.015, 0.26, 6, 2)
    return finalize_obj("mountain_arch_gate", bm, mats)


def build_tea_terraced_hedge(mats):
    """Sculpted terraced Jiangnan emerald tea-bush hedgerow (~3.8m long, mat 9=tea_dark, 10=tea_bright)."""
    bm = bmesh.new()
    # Rounded overlapping lush tea-bush cushions along X in [-1.8, +1.8]
    for i, (tx, ty, tz, rx, ry, rz, midx) in enumerate([
        (-1.35, 0.42, 0.04, 0.72, 0.48, 0.58, 9),
        (-0.55, 0.50, -0.05, 0.78, 0.54, 0.62, 10),
        (0.28, 0.48, 0.06, 0.76, 0.52, 0.60, 9),
        (1.18, 0.44, -0.03, 0.74, 0.48, 0.58, 10),
        (-0.92, 0.64, 0.02, 0.52, 0.32, 0.44, 10),
        (0.68, 0.62, -0.02, 0.54, 0.32, 0.44, 10),
    ]):
        add_lobe(bm, (tx, ty, tz), (rx, ry, rz), seed=400 + i * 17, subdiv=2, amp=0.14, mat_idx=midx)
    return finalize_obj("tea_terraced_hedge", bm, mats, smooth_all=True)


def build_mossy_boulder_cluster(mats):
    """Sculpted Jiangnan Taihu mossy limestone boulder outcrop cluster."""
    bm = bmesh.new()
    add_lobe(bm, (0.0, 0.68, 0.0), (1.18, 0.92, 0.94), seed=501, subdiv=2, amp=0.22, mat_idx=0)
    add_lobe(bm, (-0.98, 0.38, 0.42), (0.68, 0.52, 0.60), seed=502, subdiv=2, amp=0.20, mat_idx=1)
    add_lobe(bm, (0.92, 0.42, -0.36), (0.74, 0.58, 0.64), seed=503, subdiv=2, amp=0.20, mat_idx=0)
    add_lobe(bm, (0.08, 1.24, -0.06), (0.86, 0.32, 0.68), seed=504, subdiv=2, amp=0.16, mat_idx=9)
    return finalize_obj("mossy_boulder_cluster", bm, mats, smooth_all=True)


def build_trail_stone_bench(mats):
    """Carved bluestone wayside rest bench."""
    bm = bmesh.new()
    add_box(bm, (0.0, 0.48, 0.0), (1.76, 0.13, 0.54), 0)
    add_box(bm, (0.0, 0.42, 0.0), (1.66, 0.07, 0.46), 1)
    for sx in (-0.62, 0.62):
        add_box(bm, (sx, 0.22, 0.0), (0.20, 0.44, 0.42), 1)
        add_box(bm, (sx, 0.04, 0.0), (0.28, 0.09, 0.50), 0)
    return finalize_obj("trail_stone_bench", bm, mats)


def build_distant_peaks_ring(vcol_mat):
    """True 3D sculpted mid-distance Qinglu Jiangnan mountain ridge ring (radius ~268m, centered at origin)
    with vertex-colored peak-to-valley mist gradient for genuine 3D parallax in front of the 355m panorama!"""
    bm = bmesh.new()
    vcol_layer = bm.loops.layers.color.new("Color")

    segs = 96
    rings_v = []
    # 4 vertical profiles: inner foot (r=255, y=-20), lower waist (r=278, y=varies), jagged crest (r=298, y=varies), outer back (r=320, y=-16)
    profile_specs = [
        (255.0, -20.0, 0.0, (0.80, 0.88, 0.91)),   # valley mist foot
        (278.0,  -4.0, 0.45, (0.42, 0.62, 0.62)),  # misty lower slopes
        (298.0,   4.0, 0.82, (0.18, 0.39, 0.42)),  # jade-teal mid-distance foothill ridges (leaves tall sky peaks visible behind!)
        (320.0, -16.0, 0.15, (0.38, 0.56, 0.60)),  # rear skirt
    ]

    # Precompute organic multi-harmonic Jiangnan karst peak heights (lower in South vista so Chengzhuang valley shines!)
    crest_h = []
    for i in range(segs):
        ang = i * math.tau / segs
        # In Godot, South is +Z -> angle where sin(ang) > 0; keep South vista lower & more open, North/West/East majestic!
        south_open = max(0.0, math.sin(ang))
        wave = (
            14.0 * math.sin(ang * 3.0 + 0.6)
            + 9.5 * abs(math.sin(ang * 5.0 + 1.4))
            + 7.5 * math.sin(ang * 8.0 + 2.3)
            + 5.2 * (1.0 - abs(math.sin(ang * 11.0 + 0.9)))
            + 3.4 * math.cos(ang * 17.0 + 1.8)
        )
        h_val = (15.0 + wave) * (1.0 - 0.50 * (south_open ** 1.4))
        crest_h.append(max(4.5, h_val))

    for ri, (rad, base_y, h_mul, _base_col) in enumerate(profile_specs):
        loop = []
        for i in range(segs):
            ang = i * math.tau / segs
            r_jit = rad + (math.sin(ang * 7.0 + ri) * 6.5 if ri in (1, 2) else 0.0)
            gx = math.cos(ang) * r_jit
            gz = math.sin(ang) * r_jit
            gy = base_y + crest_h[i] * h_mul
            loop.append(bm.verts.new(gd_to_bl((gx, gy, gz))))
        rings_v.append(loop)

    for ri in range(len(rings_v) - 1):
        a_l = rings_v[ri]
        b_l = rings_v[ri + 1]
        c_a = profile_specs[ri][3]
        c_b = profile_specs[ri + 1][3]
        for i in range(segs):
            ni = (i + 1) % segs
            f = bm.faces.new([a_l[i], a_l[ni], b_l[ni], b_l[i]])
            # Sunlit warm ochre tint on sun-facing east/south ridges
            sun_f = max(0.0, math.cos(i * math.tau / segs - 0.8)) * (0.14 if ri >= 1 else 0.0)
            col_a = (min(1.0, c_a[0] + sun_f * 0.9), min(1.0, c_a[1] + sun_f * 0.7), min(1.0, c_a[2] + sun_f * 0.2), 1.0)
            col_b = (min(1.0, c_b[0] + sun_f * 1.1), min(1.0, c_b[1] + sun_f * 0.85), min(1.0, c_b[2] + sun_f * 0.25), 1.0)
            for lp in f.loops:
                lp[vcol_layer] = col_a if lp.vert in (a_l[i], a_l[ni]) else col_b

    return finalize_obj("distant_peaks_ring", bm, [vcol_mat], smooth_all=False)


def main():
    clear_scene()
    mats = [
        make_mat("Mat_V86_Bluestone", (0.44, 0.48, 0.47), rough=0.86),           # 0
        make_mat("Mat_V86_DarkStone", (0.31, 0.35, 0.36), rough=0.88),           # 1
        make_mat("Mat_V86_DarkCedar", (0.28, 0.17, 0.11), rough=0.76),           # 2
        make_mat("Mat_V86_WarmTimber", (0.44, 0.28, 0.17), rough=0.74),          # 3
        make_mat("Mat_V86_ClayTile", (0.20, 0.24, 0.27), rough=0.68, metal=0.06),# 4
        make_mat("Mat_V86_RidgeStone", (0.34, 0.38, 0.40), rough=0.74),          # 5
        make_mat("Mat_V86_GildedBronze", (0.76, 0.58, 0.26), rough=0.34, metal=0.78), # 6
        make_mat("Mat_V86_LanternGlow", (1.00, 0.84, 0.48), rough=0.45, emit=(1.0, 0.76, 0.34), emit_str=2.6), # 7
        make_mat("Mat_V86_WhitePlaster", (0.84, 0.82, 0.77), rough=0.90),        # 8
        make_mat("Mat_V86_TeaDark", (0.16, 0.38, 0.20), rough=0.84),             # 9
        make_mat("Mat_V86_TeaBright", (0.28, 0.54, 0.24), rough=0.80),           # 10
    ]
    vcol_mtn = make_vcol_mat("Mat_V86_DistantPeaks", rough=0.92)

    objs = [
        build_watchtower_jiangnan(mats),
        build_bamboo_shelter_jiangnan(mats),
        build_tea_pavilion_upgraded(mats),
        build_wangdao_pavilion_complete(mats),
        build_jiangnan_signboard_frame(mats),
        build_stone_lantern(mats),
        build_mountain_arch_gate(mats),
        build_tea_terraced_hedge(mats),
        build_mossy_boulder_cluster(mats),
        build_trail_stone_bench(mats),
        build_distant_peaks_ring(vcol_mtn),
    ]

    total_polys = 0
    for o in objs:
        p_cnt = len(o.data.polygons)
        total_polys += p_cnt
        print(f"  Built {o.name:26s}: {p_cnt:5d} polys", flush=True)
    print(f"TOTAL v0.8.6 architecture polys = {total_polys}", flush=True)

    bpy.ops.object.select_all(action="SELECT")
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print(f"Exported {OUT_GLB} ({OUT_GLB.stat().st_size} bytes)", flush=True)


if __name__ == "__main__":
    main()
