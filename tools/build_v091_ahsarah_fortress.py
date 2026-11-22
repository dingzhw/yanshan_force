#!/usr/bin/env python3
"""Build v0.9.1 high-craftsmanship multi-story walkable Ahsarah Fortress architecture & MandelBrick stations
in Blender 4.5 LTS:
  game/assets/slice/v091_ahsarah_fortress.glb
    - fortress_interior_wing   : Walkable 2-story Administrative Fortress wing (vaulted corridor + stone stairs + 2F sniper balcony)
    - dam_spillway_tunnel      : Zero Dam 70m concrete floodway shortcut tunnel with ribbed arches, amber lamps & vault alcove
    - brakkesh_grand_bathhouse : Iconic Brakkesh arched colonnade & grand ribbed dome bathhouse
    - cement_elevated_catwalk  : Climbable industrial steel stair tower & +4.2m elevated silo sniper catwalk
    - mandel_decode_station    : G.T.I. MandelBrick decryption terminal rig with hexagonal socket, screens & radar mast
    - mandel_brick_pedestal    : Armored fortress vault pedestal for capturing the MandelBrick

Run with:
  blender --background --python tools/build_v091_ahsarah_fortress.py
"""
from __future__ import annotations

import math
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "v091_ahsarah_fortress.glb"
OUT_GLB.parent.mkdir(parents=True, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb_lin(rgb: tuple[float, float, float]) -> tuple[float, float, float, float]:
    return (rgb[0] ** 2.2, rgb[1] ** 2.2, rgb[2] ** 2.2, 1.0)


def hex_lin(h: str) -> tuple[float, float, float, float]:
    h = h.lstrip("#")
    return srgb_lin((int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0))


def make_mat(name: str, hex_col: str, rough=0.78, metal=0.05, emit_hex: str | None = None, emit_str: float = 0.0, coat: float = 0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = hex_lin(hex_col)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.14
    if emit_hex is not None and emit_str > 0.0:
        bsdf.inputs["Emission Color"].default_value = hex_lin(emit_hex)
        bsdf.inputs["Emission Strength"].default_value = emit_str
    return mat


def gd_to_bl(v: tuple[float, float, float]) -> Vector:
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


def add_cyl(bm: bmesh.types.BMesh, center_gd, r_bot, r_top, height, segs=12, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_bot, radius2=r_top, depth=height)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    xf = Matrix.Translation(gd_to_bl(center_gd)) @ rot
    bmesh.ops.transform(bm, matrix=xf, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl_pts(bm: bmesh.types.BMesh, p0_gd, p1_gd, r0, r1, segs=10, mat_idx=0):
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


def add_dome(bm: bmesh.types.BMesh, center_gd, rx, ry, rz, segs=16, rings=7, mat_idx=0):
    ring_verts = []
    cx, cy, cz = center_gd
    for ri in range(rings):
        phi = (float(ri) / float(rings)) * (math.pi * 0.5)
        r_ring = math.cos(phi)
        y_ring = cy + math.sin(phi) * ry
        row = []
        for si in range(segs):
            ang = (float(si) / float(segs)) * math.tau
            vx = cx + math.cos(ang) * rx * r_ring
            vz = cz + math.sin(ang) * rz * r_ring
            row.append(bm.verts.new(gd_to_bl((vx, y_ring, vz))))
        ring_verts.append(row)
    top_v = bm.verts.new(gd_to_bl((cx, cy + ry, cz)))
    for ri in range(rings - 1):
        for si in range(segs):
            s2 = (si + 1) % segs
            f = bm.faces.new((ring_verts[ri][si], ring_verts[ri][s2], ring_verts[ri + 1][s2], ring_verts[ri + 1][si]))
            f.material_index = mat_idx
    for si in range(segs):
        s2 = (si + 1) % segs
        f = bm.faces.new((ring_verts[-1][si], ring_verts[-1][s2], top_v))
        f.material_index = mat_idx


def add_arch_opening_wall(bm: bmesh.types.BMesh, cx, y0, cz, width, height, depth, arch_w, arch_h, mat_idx, along_z=False):
    pillar_w = max(0.22, (width - arch_w) * 0.5)
    spring_y = y0 + arch_h * 0.58
    arch_r = arch_w * 0.5
    top_y = y0 + height

    def _box(lx, ly, lz, sx, sy, sz, rot=(0.0, 0.0, 0.0)):
        if not along_z:
            add_box(bm, (cx + lx, ly, cz + lz), (sx, sy, sz), mat_idx, rot)
        else:
            add_box(bm, (cx + lz, ly, cz + lx), (sz, sy, sx), mat_idx, (rot[0], rot[1] + 90.0, rot[2]))

    for sgn in (-1.0, 1.0):
        px = sgn * (arch_w * 0.5 + pillar_w * 0.5)
        _box(px, y0 + height * 0.5, 0.0, pillar_w, height, depth)

    n_seg = 10
    for i in range(n_seg):
        t0 = float(i) / float(n_seg)
        t1 = float(i + 1) / float(n_seg)
        tm = 0.5 * (t0 + t1)
        a0 = math.pi * (1.0 - t0)
        a1 = math.pi * (1.0 - t1)
        x0 = math.cos(a0) * arch_r
        x1 = math.cos(a1) * arch_r
        xm = 0.5 * (x0 + x1)
        seg_w = abs(x1 - x0) + 0.06
        arch_y = spring_y + math.sin(math.pi * tm) * (arch_h - (spring_y - y0))
        sp_h = max(0.18, top_y - arch_y)
        _box(xm, arch_y + sp_h * 0.5, 0.0, seg_w, sp_h, depth)


def finalize_obj(name: str, bm: bmesh.types.BMesh, mat_list: list, smooth: bool = False) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    for m in mat_list:
        mesh.materials.append(m)
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_materials() -> tuple[list, dict[str, int]]:
    specs = [
        ("Mat_SandstoneMain", "d8a768", 0.86, 0.02, None, 0.0, 0.0),         # 0
        ("Mat_SandstoneDark", "b27c44", 0.90, 0.02, None, 0.0, 0.0),         # 1
        ("Mat_SandstoneLight", "e8c58c", 0.82, 0.02, None, 0.0, 0.0),        # 2
        ("Mat_Terracotta", "b8643e", 0.84, 0.03, None, 0.0, 0.0),            # 3
        ("Mat_ConcreteMain", "a3a7aa", 0.86, 0.05, None, 0.0, 0.0),          # 4
        ("Mat_ConcreteDark", "6d7378", 0.90, 0.08, None, 0.0, 0.0),          # 5
        ("Mat_SteelDark", "373f47", 0.46, 0.74, None, 0.0, 0.0),             # 6
        ("Mat_SteelLight", "8e979f", 0.40, 0.68, None, 0.0, 0.0),            # 7
        ("Mat_CedarWood", "68472b", 0.82, 0.02, None, 0.0, 0.0),             # 8
        ("Mat_AhsarahRed", "b5362e", 0.82, 0.04, None, 0.0, 0.0),            # 9
        ("Mat_HaavkWhite", "e6ebf0", 0.34, 0.14, None, 0.0, 0.25),           # 10
        ("Mat_HaavkCyan", "38e8ff", 0.18, 0.14, "2ad8ff", 3.0, 0.3),         # 11
        ("Mat_AmberGlow", "ffbd52", 0.22, 0.10, "ffaa33", 2.6, 0.2),         # 12
        ("Mat_Brass", "cc9f46", 0.30, 0.84, None, 0.0, 0.2),                 # 13
        ("Mat_WarningYellow", "e5b32e", 0.62, 0.10, None, 0.0, 0.0),         # 14
        ("Mat_TileTeal", "2d7b7a", 0.32, 0.12, None, 0.0, 0.4),              # 15
        ("Mat_GoldTrim", "e8bd54", 0.24, 0.86, "e0a830", 0.35, 0.25),        # 16
    ]
    mat_list = [make_mat(*s) for s in specs]
    idx = {s[0]: i for i, s in enumerate(specs)}
    return mat_list, idx


def build_fortress_interior_wing(mats, M):
    """Walkable 2-story Administrative Fortress Wing (17.0m wide along X x 7.4m deep along Z x 7.2m tall).
    Front face (+Z) looks directly into the Boss Courtyard!
    - Ground floor (y=0.0..3.65): 3 wide open sandstone arches on front (+Z) + open south/north ends + interior vaulted corridor.
    - Solid stone staircase tucked along back wall (x=-6.4 -> +0.8, z=-2.2) climbing smoothly from y=0.0 up to 2nd floor y=3.65!
    - 2nd floor (y=3.65..6.4): full walkable tactical balcony deck with crenellated sandstone firing embrasures overlooking Boss Courtyard!
    """
    bm = bmesh.new()
    SAND = M["Mat_SandstoneMain"]
    S_DK = M["Mat_SandstoneDark"]
    S_LT = M["Mat_SandstoneLight"]
    CONC = M["Mat_ConcreteMain"]
    C_DK = M["Mat_ConcreteDark"]
    STEEL = M["Mat_SteelDark"]
    WOOD = M["Mat_CedarWood"]
    RED = M["Mat_AhsarahRed"]
    AMBER = M["Mat_AmberGlow"]
    BRASS = M["Mat_Brass"]

    # Deeply grounded foundation slab (y=-1.80..+0.02, flush with courtyard y=0 so players walk straight in!)
    add_box(bm, (0.0, -0.89, 0.0), (17.4, 1.82, 7.8), S_DK)

    # Ground-floor front colonnade (+Z = +3.15): 3 wide walkable sandstone arches opening to Boss Courtyard
    for ax in (-5.0, 0.0, 5.0):
        add_arch_opening_wall(bm, ax, 0.0, 3.15, 5.0, 3.55, 0.72, 3.4, 2.95, SAND, along_z=False)
    # Corner concrete reinforcement pillars
    for sx in (-8.15, 8.15):
        add_box(bm, (sx, 3.2, 3.15), (0.95, 6.4, 0.95), CONC)
        add_box(bm, (sx, 3.2, -3.15), (0.95, 6.4, 0.95), CONC)

    # Rear fortified solid wall (-Z = -3.15) with central tactical doorway arch (walkable from outside flank!)
    add_box(bm, (-5.4, 1.85, -3.15), (6.0, 3.7, 0.72), SAND)
    add_box(bm, (5.4, 1.85, -3.15), (6.0, 3.7, 0.72), SAND)
    add_arch_opening_wall(bm, 0.0, 0.0, -3.15, 4.8, 3.7, 0.72, 2.8, 2.9, SAND, along_z=False)

    # Open side archways on East/West ends (x = ±8.15) so player can breeze through corridor
    for sx in (-8.15, 8.15):
        add_arch_opening_wall(bm, sx, 0.0, 0.0, 5.6, 3.55, 0.72, 3.4, 2.9, SAND, along_z=True)

    # SOLID INTERIOR STONE STAIRCASE rising from x=-6.2 (y=0.0) -> x=+0.4 (y=3.65) along back wall (z=-1.85, width 1.9m)
    n_steps = 14
    for i in range(n_steps):
        t = float(i + 1) / float(n_steps)
        top_y = 3.65 * t
        sx = -6.2 + (6.6 * (float(i) + 0.5) / float(n_steps))
        add_box(bm, (sx, top_y * 0.5, -1.85), (0.56, top_y, 1.95), S_LT)
    # Interior stair handrail along corridor side (z=-0.88)
    add_cyl_pts(bm, (-6.2, 0.95, -0.88), (0.4, 4.60, -0.88), 0.055, 0.055, 6, STEEL)
    for pi in range(5):
        pt = float(pi) / 4.0
        px = -6.2 + 6.6 * pt
        py = 3.65 * pt
        add_cyl(bm, (px, py + 0.48, -0.88), 0.045, 0.045, 0.96, 6, STEEL)

    # 2nd-FLOOR WALKABLE CONCRETE & SANDSTONE DECK (y = 3.45..3.72) with clean stairwell cutout at x∈[-6.4..+0.5], z∈[-2.85..-0.85]!
    # Front balcony strip spanning full width (z = -0.85..+3.55)
    add_box(bm, (0.0, 3.55, 1.35), (17.2, 0.30, 4.40), CONC)
    # East upper landing behind stairwell (x = +0.4..+8.5, z = -3.4..-0.85)
    add_box(bm, (4.45, 3.55, -2.12), (8.2, 0.30, 2.55), CONC)
    # West small upper back landing (x = -8.5..-6.3, z = -3.4..-0.85)
    add_box(bm, (-7.4, 3.55, -2.12), (2.2, 0.30, 2.55), CONC)

    # 2nd-floor front sniper parapet (+Z = +3.35) — chest-high 1.08m wall with 3 wide tactical firing windows + merlons!
    add_box(bm, (0.0, 4.18, 3.32), (16.8, 1.06, 0.42), SAND)
    # Tall tactical pillars flanking 3 sniper embrasures on 2nd floor
    for px in (-8.1, -3.1, 3.1, 8.1):
        add_box(bm, (px, 5.10, 3.28), (1.05, 2.85, 0.56), S_LT)
    # Overhead cedar-beam desert shade pergola covering half the 2F tactical deck
    add_box(bm, (0.0, 6.45, 1.65), (17.0, 0.24, 3.8), S_DK)
    for bx in (-6.5, -4.0, -1.5, 1.5, 4.0, 6.5):
        add_cyl(bm, (bx, 6.32, 3.52), 0.09, 0.09, 0.95, 6, WOOD, (90.0, 0.0, 0.0))
    # Sawtooth crenellations crowning the rooftop
    for mx in range(-7, 8, 2):
        add_box(bm, (float(mx) * 1.08, 6.92, 3.35), (0.66, 0.72, 0.34), SAND)

    # 2nd-floor rear & side safety parapets (h=1.18m)
    add_box(bm, (0.0, 4.30, -3.25), (16.8, 1.24, 0.46), SAND)
    for sx in (-8.25, 8.25):
        add_box(bm, (sx, 4.30, 0.0), (0.46, 1.24, 6.7), SAND)

    # Interior warm amber corridor lanterns + crimson Ahsarah war tapestries
    for lx in (-4.8, 0.0, 4.8):
        add_box(bm, (lx, 3.25, 0.8), (0.34, 0.16, 0.34), STEEL)
        add_box(bm, (lx, 3.14, 0.8), (0.24, 0.10, 0.24), AMBER)
    for bx in (-3.1, 3.1):
        add_box(bm, (bx, 5.0, 3.60), (0.72, 1.85, 0.05), RED)
        add_box(bm, (bx, 5.35, 3.63), (0.32, 0.32, 0.04), BRASS, (0.0, 0.0, 45.0))

    return finalize_obj("fortress_interior_wing", bm, mats, smooth=False)


def build_dam_spillway_tunnel(mats, M):
    """Zero Dam Underground Floodway / Spillway Shortcut Tunnel spanning 68m along X (x=-34..+34, clear interior 4.6m wide x 3.8m tall).
    Connects West Bastion directly beneath the north flank to East Helipad Extraction Zone!"""
    bm = bmesh.new()
    C_MAIN = M["Mat_ConcreteMain"]
    C_DK = M["Mat_ConcreteDark"]
    STEEL = M["Mat_SteelDark"]
    ST_LT = M["Mat_SteelLight"]
    WARN = M["Mat_WarningYellow"]
    AMBER = M["Mat_AmberGlow"]
    CYAN = M["Mat_HaavkCyan"]

    half_len = 34.0
    # Deep solid concrete floor slab with central recessed drainage grate (y=-1.80..+0.02)
    add_box(bm, (0.0, -0.89, 0.0), (half_len * 2.0 + 2.0, 1.82, 6.4), C_DK)
    add_box(bm, (0.0, 0.03, 0.0), (half_len * 2.0, 0.04, 1.15), STEEL)

    # Solid reinforced concrete north & south tunnel walls (z = ±2.75, interior clear width = 4.6m, height = 3.9m)
    for sgn in (-1.0, 1.0):
        # Leave central alcove opening on north side (-Z) at x∈[-3..+3] for emergency loot/cover pocket!
        if sgn < 0.0:
            add_box(bm, (-18.5, 2.0, -2.75), (31.0, 4.0, 0.90), C_MAIN)
            add_box(bm, (18.5, 2.0, -2.75), (31.0, 4.0, 0.90), C_MAIN)
            # Central recessed maintenance vault alcove (x=-3..+3, z=-2.75..-5.4)
            add_box(bm, (0.0, 2.0, -5.45), (6.8, 4.0, 0.80), C_DK)
            add_box(bm, (-3.1, 2.0, -4.1), (0.70, 4.0, 2.6), C_DK)
            add_box(bm, (3.1, 2.0, -4.1), (0.70, 4.0, 2.6), C_DK)
            add_box(bm, (0.0, 4.05, -4.1), (6.8, 0.65, 3.0), C_MAIN)
            add_box(bm, (0.0, -0.89, -4.1), (6.8, 1.82, 3.0), C_DK)
            add_box(bm, (0.0, 3.55, -5.02), (1.8, 0.24, 0.14), CYAN)
        else:
            add_box(bm, (0.0, 2.0, 2.75), (half_len * 2.0, 4.0, 0.90), C_MAIN)
        # Yellow industrial hazard rail stripe along interior walls
        add_box(bm, (0.0, 1.05, sgn * 2.26), (half_len * 2.0 - 1.0, 0.20, 0.08), WARN)

    # Heavy concrete roof slab + angled exterior sand-berm concrete casing so tunnel looks embedded in dam earthwork!
    add_box(bm, (0.0, 4.18, 0.0), (half_len * 2.0 + 1.0, 0.85, 6.6), C_MAIN)
    # 13 massive interior reinforced concrete arch ribs & glowing amber work lamps every 5.2m!
    for i in range(13):
        rx = -31.2 + float(i) * 5.2
        add_box(bm, (rx, 3.72, 0.0), (0.55, 0.42, 4.8), C_DK)
        for sgn in (-1.0, 1.0):
            add_box(bm, (rx, 2.0, sgn * 2.18), (0.55, 3.85, 0.36), C_DK)
        # Overhead waterproof amber industrial tunnel lamp
        if i % 2 == 0:
            add_box(bm, (rx, 3.46, 0.0), (0.88, 0.14, 0.36), STEEL)
            add_box(bm, (rx, 3.38, 0.0), (0.72, 0.10, 0.22), AMBER)

    # Monumental West (x=-34) & East (x=+34) reinforced hydro portal headwalls with steel blast-door frames!
    for sgn in (-1.0, 1.0):
        px = sgn * half_len
        add_box(bm, (px, 4.75, 0.0), (1.6, 1.6, 7.6), C_DK)
        add_box(bm, (px + sgn * 0.82, 4.45, 0.0), (0.14, 0.48, 5.4), WARN)
        for wz in (-3.25, 3.25):
            add_box(bm, (px, 2.4, wz), (1.8, 5.2, 1.25), C_DK)
        # Overhead hydro steel pipe conduit flanking portal
        add_cyl(bm, (px, 3.55, 2.0), 0.14, 0.14, 1.4, 8, ST_LT, (0.0, 0.0, 90.0))

    return finalize_obj("dam_spillway_tunnel", bm, mats, smooth=False)


def build_brakkesh_grand_bathhouse(mats, M):
    """Iconic Brakkesh Sandstone Grand Bathhouse / Royal Arched Dome Arcade (~13.2m x 10.6m x 9.8m).
    Deeply grounded (-1.6m), walkable arched gallery, monumental ribbed dome, twin lantern cupolas & carved central basin."""
    bm = bmesh.new()
    SAND = M["Mat_SandstoneMain"]
    S_DK = M["Mat_SandstoneDark"]
    S_LT = M["Mat_SandstoneLight"]
    TERRA = M["Mat_Terracotta"]
    TILE = M["Mat_TileTeal"]
    BRASS = M["Mat_Brass"]
    RED = M["Mat_AhsarahRed"]
    GOLD = M["Mat_GoldTrim"]
    AMBER = M["Mat_AmberGlow"]

    # Deep stone base terrace (y=-1.60..+0.55) + extended front stair apron (z=+5.2..+7.0)
    add_box(bm, (0.0, -0.52, 0.0), (13.4, 2.16, 10.8), S_DK)
    add_box(bm, (0.0, -0.78, 6.15), (9.6, 1.62, 2.1), S_DK)
    # 3 broad solid marble-sandstone steps rising cleanly from ground (0.0) to gallery terrace (+0.55)
    for st in range(3):
        top_y = 0.20 + st * 0.175
        h_s = top_y + 1.20
        add_box(bm, (0.0, top_y - h_s * 0.5, 5.42 + (2 - st) * 0.40), (5.2, h_s, 0.46), S_LT)

    # Front (+Z) & Rear (-Z) triple-bay scalloped arcade walls (walkable open central bay!)
    for cz in (-4.75, 4.75):
        add_arch_opening_wall(bm, 0.0, 0.55, cz, 5.4, 4.3, 0.78, 3.8, 3.45, SAND, along_z=False)
        for sx in (-4.35, 4.35):
            add_arch_opening_wall(bm, sx, 0.55, cz, 3.6, 4.3, 0.78, 2.1, 3.1, S_LT, along_z=False)
    # West (-X) & East (+X) double-bay arched flanks
    for cx in (-6.05, 6.05):
        add_arch_opening_wall(bm, cx, 0.55, -2.2, 4.6, 4.3, 0.78, 2.8, 3.2, SAND, along_z=True)
        add_arch_opening_wall(bm, cx, 0.55, 2.2, 4.6, 4.3, 0.78, 2.8, 3.2, SAND, along_z=True)

    # Grand rooftop cornice, stepped parapet battlements & teal-gold decorative tile frieze
    add_box(bm, (0.0, 5.02, 0.0), (13.2, 0.42, 10.6), S_LT)
    add_box(bm, (0.0, 4.76, 5.18), (12.8, 0.28, 0.12), TILE)
    add_box(bm, (0.0, 4.76, -5.18), (12.8, 0.28, 0.12), TILE)
    for mx in range(-5, 6):
        add_box(bm, (float(mx) * 1.18, 5.54, 5.05), (0.62, 0.68, 0.34), SAND)
        add_box(bm, (float(mx) * 1.18, 5.54, -5.05), (0.62, 0.68, 0.34), SAND)

    # Monumental central ribbed Moroccan dome (diameter 6.4m, crowned at y=9.8m!)
    add_cyl(bm, (0.0, 5.65, 0.0), 3.45, 3.32, 1.05, 16, S_DK)
    add_cyl(bm, (0.0, 6.22, 0.0), 3.35, 3.35, 0.22, 16, TILE)
    add_dome(bm, (0.0, 6.28, 0.0), 3.20, 2.85, 3.20, 18, 8, S_LT)
    # 8 subtle sandstone dome ribs + golden crescent spire finial
    for ri in range(8):
        ang = ri * (math.tau / 8.0)
        add_box(bm, (math.cos(ang) * 1.8, 7.6, math.sin(ang) * 1.8), (0.16, 2.6, 0.16), S_DK, (0.0, math.degrees(ang), 24.0))
    add_cyl(bm, (0.0, 9.45, 0.0), 0.12, 0.03, 0.95, 8, GOLD)
    add_box(bm, (0.0, 9.55, 0.0), (0.28, 0.28, 0.28), BRASS, (0.0, 45.0, 45.0))

    # Twin flanking domed terracotta lantern cupolas (x = ±4.5)
    for sx in (-4.5, 4.5):
        add_cyl(bm, (sx, 5.55, 0.0), 1.48, 1.42, 0.72, 12, S_DK)
        add_dome(bm, (sx, 5.88, 0.0), 1.38, 1.25, 1.38, 14, 6, TERRA)
        add_cyl(bm, (sx, 7.35, 0.0), 0.06, 0.02, 0.55, 8, BRASS)

    # Carved octagonal teal-tiled dry bathhouse fountain basin centered inside gallery + crimson tapestry & brass lanterns
    add_cyl(bm, (0.0, 0.85, 0.0), 1.65, 1.72, 0.62, 8, S_LT)
    add_cyl(bm, (0.0, 1.12, 0.0), 1.35, 1.35, 0.12, 8, TILE)
    add_cyl(bm, (0.0, 1.55, 0.0), 0.24, 0.18, 0.95, 8, S_DK)
    add_cyl(bm, (0.0, 2.02, 0.0), 0.68, 0.52, 0.18, 8, S_LT)
    for sgn in (-1.0, 1.0):
        add_box(bm, (sgn * 2.4, 3.25, 5.20), (0.85, 2.2, 0.06), RED)
        add_box(bm, (sgn * 2.4, 3.60, 5.24), (0.36, 0.36, 0.04), GOLD, (0.0, 0.0, 45.0))
        add_box(bm, (sgn * 2.15, 2.85, 5.18), (0.22, 0.38, 0.22), AMBER)

    return finalize_obj("brakkesh_grand_bathhouse", bm, mats, smooth=False)


def build_cement_elevated_catwalk(mats, M):
    """Climbable industrial steel stair tower & +4.2m elevated sniper catwalk overlooking Cement Plant yard!
    Local +Z = front stair approach; catwalk spans X = -6.0..+6.0 at Y = +4.20m."""
    bm = bmesh.new()
    C_DK = M["Mat_ConcreteDark"]
    STEEL = M["Mat_SteelDark"]
    ST_LT = M["Mat_SteelLight"]
    WARN = M["Mat_WarningYellow"]
    TERRA = M["Mat_Terracotta"]

    # 4 heavy concrete footing piers deeply grounded to y=-1.80m
    for px in (-5.6, -1.8, 1.8, 5.6):
        for pz in (-1.35, 1.35):
            add_box(bm, (px, -0.60, pz), (0.72, 2.40, 0.72), C_DK)
            add_box(bm, (px, 2.10, pz), (0.24, 4.20, 0.24), STEEL)
    # Cross-bracing steel struts
    for px in (-5.6, 5.6):
        add_cyl_pts(bm, (px, 0.35, -1.35), (px, 4.05, 1.35), 0.06, 0.06, 6, STEEL)
        add_cyl_pts(bm, (px, 0.35, 1.35), (px, 4.05, -1.35), 0.06, 0.06, 6, STEEL)

    # Elevated steel walkway deck (12.4m x 3.2m at y = 4.10..4.28)
    add_box(bm, (0.0, 4.18, 0.0), (12.4, 0.22, 3.2), STEEL)
    add_box(bm, (0.0, 4.22, 1.56), (12.4, 0.16, 0.10), WARN)
    add_box(bm, (0.0, 4.22, -1.56), (12.4, 0.16, 0.10), WARN)

    # Waist-high industrial safety guardrails around top deck (leaving stair entry open at x=-1.8..+0.4, z=+1.55)
    add_box(bm, (0.0, 5.20, -1.52), (12.2, 0.08, 0.08), WARN)
    add_box(bm, (0.0, 4.74, -1.52), (12.2, 0.06, 0.06), ST_LT)
    add_box(bm, (-3.9, 5.20, 1.52), (4.2, 0.08, 0.08), WARN)
    add_box(bm, (3.2, 5.20, 1.52), (5.8, 0.08, 0.08), WARN)
    for sx in (-6.05, 6.05):
        add_box(bm, (sx, 5.20, 0.0), (0.08, 0.08, 3.1), WARN)
        add_box(bm, (sx, 4.74, 0.0), (0.06, 0.06, 3.1), ST_LT)
    for rx in (-6.05, -3.9, -1.8, 0.4, 3.2, 6.05):
        add_box(bm, (rx, 4.72, -1.52), (0.07, 1.05, 0.07), STEEL)
        add_box(bm, (rx, 4.72, 1.52), (0.07, 1.05, 0.07), STEEL)
    # Corrugated tactical steel cover shields bolted to deck rail for high-ground sniping!
    add_box(bm, (-4.1, 4.82, -1.48), (2.4, 1.15, 0.10), TERRA)
    add_box(bm, (3.6, 4.82, -1.48), (2.8, 1.15, 0.10), TERRA)

    # Climbable exterior steel stair flight rising smoothly from z=+8.8 (y=0.0) -> z=+1.55 (y=4.20) centered at x=-0.7!
    n_steps = 16
    for i in range(n_steps):
        t = float(i + 1) / float(n_steps)
        sy = 4.20 * t
        sz = 8.8 - 7.25 * (float(i) + 0.5) / float(n_steps)
        add_box(bm, (-0.7, sy - 0.10, sz), (2.05, 0.18, 0.52), ST_LT)
    # Concrete base pad under stairs (grounded to -1.5m) + twin inclined steel stair stringers & handrails
    add_box(bm, (-0.7, -0.72, 8.95), (2.4, 1.50, 1.15), C_DK)
    for sgn in (-1.0, 1.0):
        lx = -0.7 + sgn * 1.04
        add_cyl_pts(bm, (lx, 0.0, 8.8), (lx, 4.12, 1.55), 0.10, 0.10, 6, STEEL)
        add_cyl_pts(bm, (lx, 1.02, 8.8), (lx, 5.18, 1.55), 0.055, 0.055, 6, WARN)
        for pi in range(5):
            pt = float(pi) / 4.0
            add_cyl(bm, (lx, 4.12 * pt + 0.52, 8.8 - 7.25 * pt), 0.04, 0.04, 1.04, 6, STEEL)

    return finalize_obj("cement_elevated_catwalk", bm, mats, smooth=False)


def build_mandel_decode_station(mats, M):
    """High-tech G.T.I. MandelBrick Decryption Terminal Station (~3.2m x 3.2m x 4.6m, grounded to y=-0.9m)."""
    bm = bmesh.new()
    C_DK = M["Mat_ConcreteDark"]
    STEEL = M["Mat_SteelDark"]
    ST_LT = M["Mat_SteelLight"]
    WHITE = M["Mat_HaavkWhite"]
    CYAN = M["Mat_HaavkCyan"]
    GOLD = M["Mat_GoldTrim"]
    WARN = M["Mat_WarningYellow"]

    # Heavy armored hexagonal concrete/steel base platform grounded down to y=-0.90m
    add_cyl(bm, (0.0, -0.34, 0.0), 1.92, 1.75, 1.12, 6, C_DK)
    add_cyl(bm, (0.0, 0.28, 0.0), 1.76, 1.72, 0.14, 6, WARN)

    # Central hexagonal MandelBrick docking pedestal + 3 armored cooling buttresses
    add_cyl(bm, (0.0, 0.90, 0.0), 0.78, 0.62, 1.16, 6, WHITE)
    add_cyl(bm, (0.0, 1.50, 0.0), 0.56, 0.56, 0.10, 6, GOLD)
    add_cyl(bm, (0.0, 1.58, 0.0), 0.36, 0.36, 0.08, 6, CYAN)
    for bi in range(3):
        ang = bi * (math.tau / 3.0) + 0.5
        bx, bz = math.cos(ang) * 0.92, math.sin(ang) * 0.92
        add_box(bm, (bx, 0.72, bz), (0.32, 0.92, 0.62), STEEL, (0.0, -math.degrees(ang), 14.0))

    # Twin angled holographic telemetry console wings on front-left & front-right
    for sgn in (-1.0, 1.0):
        add_box(bm, (sgn * 1.15, 1.38, 0.62), (0.85, 0.62, 0.10), STEEL, (-22.0, sgn * -28.0, 0.0))
        add_box(bm, (sgn * 1.14, 1.40, 0.66), (0.72, 0.48, 0.06), CYAN, (-22.0, sgn * -28.0, 0.0))
        add_cyl_pts(bm, (sgn * 0.62, 0.72, 0.32), (sgn * 1.12, 1.28, 0.58), 0.06, 0.05, 6, ST_LT)

    # Tall rear tactical encryption relay mast + parabolic dish + pulsing gold-cyan beacon tip
    add_cyl(bm, (0.0, 2.35, -1.05), 0.16, 0.10, 4.2, 8, STEEL)
    add_cyl(bm, (0.0, 3.25, -0.68), 0.78, 0.18, 0.36, 14, WHITE, (62.0, 0.0, 0.0))
    add_cyl_pts(bm, (0.0, 3.25, -0.68), (0.0, 3.55, -0.18), 0.04, 0.025, 6, GOLD)
    add_cyl(bm, (0.0, 4.55, -1.05), 0.18, 0.14, 0.36, 8, CYAN)
    add_cyl(bm, (0.0, 4.78, -1.05), 0.24, 0.04, 0.20, 8, GOLD)

    return finalize_obj("mandel_decode_station", bm, mats, smooth=False)


def build_mandel_brick_pedestal(mats, M):
    """Armored Administrative Fortress Vault pedestal holding the capturable MandelBrick (grounded to y=-0.7m)."""
    bm = bmesh.new()
    STEEL = M["Mat_SteelDark"]
    WHITE = M["Mat_HaavkWhite"]
    GOLD = M["Mat_GoldTrim"]
    CYAN = M["Mat_HaavkCyan"]

    add_cyl(bm, (0.0, -0.25, 0.0), 1.05, 0.92, 0.90, 6, STEEL)
    add_cyl(bm, (0.0, 0.68, 0.0), 0.66, 0.54, 1.05, 6, WHITE)
    add_cyl(bm, (0.0, 1.24, 0.0), 0.58, 0.58, 0.10, 6, GOLD)
    add_cyl(bm, (0.0, 1.31, 0.0), 0.38, 0.38, 0.06, 6, CYAN)
    return finalize_obj("mandel_brick_pedestal", bm, mats, smooth=False)


def main():
    clear_scene()
    mats, M = build_materials()
    built = [
        build_fortress_interior_wing(mats, M),
        build_dam_spillway_tunnel(mats, M),
        build_brakkesh_grand_bathhouse(mats, M),
        build_cement_elevated_catwalk(mats, M),
        build_mandel_decode_station(mats, M),
        build_mandel_brick_pedestal(mats, M),
    ]
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
        export_apply=True,
    )
    print(f"Exported {len(built)} v0.9.1 Ahsarah fortress & MandelBrick assets -> {OUT_GLB} ({OUT_GLB.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
