#!/usr/bin/env python3
"""Build high-detail articulated stylized 3D PBR characters for Yanshan Force v0.9.0 "Ahsarah Fortress"
in Blender 4.5 LTS:
  - boss_saeed       ("赤枭·赛伊德" — Normal Mode Boss: ragged crimson desert cloak, amber goggles, owl shoulder crest, tactical carbine/crossbow)
  - boss_reis        ("阿萨拉军阀·雷斯" — Confidential Mode Boss: armored obsidian-gold greatcoat, dark sunglasses, drum-mag shotgun & antique brass gramophone!)
  - ahsarah_guard    ("阿萨拉卫队步兵" — Desert khaki fatigues, crimson patterned shemagh scarf & headwrap, tactical vest, carbine)
  - haavk_trooper    ("哈夫克科技护卫" — Matte-white angular composite armor, glowing electric-cyan visor & Mandel telemetry pack, pulse rifle)

Run with Blender 4.5:
  blender --background --python tools/build_v090_ahsarah_characters.py

Outputs:
  game/assets/slice/v090_ahsarah_characters.glb
"""
from __future__ import annotations

import math
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "v090_ahsarah_characters.glb"
OUT_GLB.parent.mkdir(parents=True, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def hex_lin(h: str) -> tuple[float, float, float, float]:
    h = h.lstrip("#")
    return ((int(h[0:2], 16) / 255.0) ** 2.2, (int(h[2:4], 16) / 255.0) ** 2.2, (int(h[4:6], 16) / 255.0) ** 2.2, 1.0)


def make_mat(name: str, hex_col: str, rough=0.68, metal=0.08, emit_hex: str | None = None, emit_str: float = 0.0, coat: float = 0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    bsdf.inputs["Base Color"].default_value = hex_lin(hex_col)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
    if emit_hex is not None and emit_str > 0.0:
        bsdf.inputs["Emission Color"].default_value = hex_lin(emit_hex)
        bsdf.inputs["Emission Strength"].default_value = emit_str
    return mat


def gd_to_bl(v: tuple[float, float, float]) -> Vector:
    return Vector((v[0], -v[2], v[1]))


def add_box(bm, center_gd, size_gd, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    scale = Matrix.Diagonal((size_gd[0], size_gd[2], size_gd[1], 1.0))
    bmesh.ops.transform(bm, matrix=Matrix.Translation(gd_to_bl(center_gd)) @ rot @ scale, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl(bm, center_gd, r_bot, r_top, height, segs=12, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_bot, radius2=r_top, depth=height)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(gd_to_bl(center_gd)) @ rot, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl_pts(bm, p0_gd, p1_gd, r0, r1, segs=10, mat_idx=0):
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


def add_sphere(bm, center_gd, radii_gd, segs=12, rings=8, mat_idx=0):
    ret = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    verts = ret["verts"]
    scale = Matrix.Diagonal((radii_gd[0], radii_gd[2], radii_gd[1], 1.0))
    bmesh.ops.transform(bm, matrix=Matrix.Translation(gd_to_bl(center_gd)) @ scale, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def make_part(name: str, bm: bmesh.types.BMesh, mats: list, parent=None, pivot_gd=(0.0, 0.0, 0.0), smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    for m in mats:
        mesh.materials.append(m)
    for p in mesh.polygons:
        p.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    obj.location = gd_to_bl(pivot_gd)
    return obj


def build_materials():
    specs = [
        ("Mat_DesertKhaki", "c9a875", 0.84, 0.02, None, 0.0, 0.0),       # 0
        ("Mat_SandCloth", "dfd0b2", 0.88, 0.0, None, 0.0, 0.0),          # 1
        ("Mat_CrimsonCloak", "9d2622", 0.80, 0.04, None, 0.0, 0.0),      # 2
        ("Mat_CrimsonBright", "c9342c", 0.72, 0.05, None, 0.0, 0.0),     # 3
        ("Mat_TacDark", "2b3036", 0.66, 0.25, None, 0.0, 0.0),           # 4
        ("Mat_LeatherBrown", "593b25", 0.76, 0.05, None, 0.0, 0.0),      # 5
        ("Mat_Gunmetal", "343a42", 0.36, 0.82, None, 0.0, 0.1),          # 6
        ("Mat_GoldTrim", "d8a83e", 0.26, 0.88, None, 0.0, 0.25),         # 7
        ("Mat_Bronze", "9e6d36", 0.38, 0.78, None, 0.0, 0.1),            # 8
        ("Mat_SkinWarm", "c9956c", 0.70, 0.0, None, 0.0, 0.0),           # 9
        ("Mat_AmberVisor", "ffaa22", 0.16, 0.20, "ff9e18", 2.8, 0.6),    # 10
        ("Mat_HaavkWhite", "eaf0f5", 0.30, 0.15, None, 0.0, 0.35),       # 11
        ("Mat_HaavkGraphite", "262d36", 0.45, 0.35, None, 0.0, 0.1),     # 12
        ("Mat_CyanVisor", "36e8ff", 0.14, 0.18, "28e2ff", 3.4, 0.6),     # 13
        ("Mat_SunGlass", "12161c", 0.08, 0.35, None, 0.0, 0.9),          # 14
        ("Mat_WoodWalnut", "4e2b18", 0.40, 0.05, None, 0.0, 0.35),       # 15
        ("Mat_IncendiaryRed", "e5482e", 0.38, 0.22, "ff5522", 1.2, 0.2), # 16
    ]
    mats = [make_mat(*s) for s in specs]
    M = {s[0]: i for i, s in enumerate(specs)}
    return mats, M


def build_boss_saeed(mats, M):
    """「赤枭·赛伊德」(Captain Saeed, ~2.32m commanding boss height, facing -Z forward)."""
    root = bpy.data.objects.new("boss_saeed", None)
    bpy.context.collection.objects.link(root)

    KHAKI = M["Mat_DesertKhaki"]
    CRIMSON = M["Mat_CrimsonCloak"]
    RED_HI = M["Mat_CrimsonBright"]
    DARK = M["Mat_TacDark"]
    LEATH = M["Mat_LeatherBrown"]
    GUN = M["Mat_Gunmetal"]
    BRONZE = M["Mat_Bronze"]
    GOLD = M["Mat_GoldTrim"]
    SKIN = M["Mat_SkinWarm"]
    AMBER = M["Mat_AmberVisor"]
    INCEN = M["Mat_IncendiaryRed"]

    # 1) Body (legs, tactical rig, chest armor, owl pauldron, hooded head & amber goggles)
    bm = bmesh.new()
    for sgn in (-1.0, 1.0):
        lx = sgn * 0.22
        # Heavy desert combat boots + knee pads + tactical trousers
        add_box(bm, (lx, 0.11, -0.04), (0.20, 0.22, 0.34), LEATH)
        add_cyl(bm, (lx, 0.42, 0.0), 0.11, 0.13, 0.46, 10, KHAKI)
        add_box(bm, (lx, 0.64, -0.11), (0.16, 0.17, 0.08), DARK)
        add_cyl(bm, (lx, 0.88, 0.0), 0.13, 0.15, 0.46, 10, KHAKI)
    # Pelvis & utility belt with glowing red incendiary canisters!
    add_box(bm, (0.0, 1.12, 0.0), (0.60, 0.22, 0.34), KHAKI)
    add_box(bm, (0.0, 1.14, 0.0), (0.64, 0.10, 0.38), LEATH)
    for cx in (-0.28, -0.14, 0.24):
        add_cyl(bm, (cx, 1.12, -0.21), 0.045, 0.045, 0.16, 8, INCEN)
    # Muscular torso jacket + ballistic plate carrier + magazine pouches
    add_box(bm, (0.0, 1.48, 0.0), (0.66, 0.56, 0.36), KHAKI)
    add_box(bm, (0.0, 1.50, -0.02), (0.58, 0.46, 0.42), DARK)
    for px in (-0.16, 0.0, 0.16):
        add_box(bm, (px, 1.38, -0.24), (0.11, 0.18, 0.09), LEATH)
    # Draped crimson desert shemagh scarf wrapping neck & left shoulder
    add_cyl(bm, (0.0, 1.82, 0.0), 0.28, 0.24, 0.18, 12, CRIMSON)
    add_box(bm, (-0.18, 1.62, -0.22), (0.24, 0.36, 0.10), RED_HI, (10.0, 0.0, -14.0))
    # Sculpted Fiery Owl bronze/gold shoulder crest on left pauldron!
    add_sphere(bm, (-0.42, 1.74, 0.0), (0.19, 0.16, 0.20), 10, 7, DARK)
    add_box(bm, (-0.48, 1.76, -0.05), (0.08, 0.20, 0.26), BRONZE, (0.0, 0.0, 12.0))
    add_box(bm, (-0.51, 1.82, -0.05), (0.05, 0.10, 0.34), GOLD, (0.0, 0.0, 22.0))
    add_sphere(bm, (0.42, 1.74, 0.0), (0.18, 0.15, 0.19), 10, 7, CRIMSON)
    # Head + crimson desert hood + respirator mask + glowing amber tactical goggles!
    add_sphere(bm, (0.0, 2.04, 0.0), (0.20, 0.23, 0.21), 12, 8, SKIN)
    add_box(bm, (0.0, 1.98, -0.17), (0.22, 0.15, 0.14), DARK)  # Tactical half-mask
    add_box(bm, (0.0, 2.09, -0.18), (0.28, 0.10, 0.10), GUN)   # Goggle frame
    for gx in (-0.075, 0.075):
        add_box(bm, (gx, 2.09, -0.23), (0.10, 0.07, 0.04), AMBER)
    # Hood cowl crowning head
    add_sphere(bm, (0.0, 2.08, 0.04), (0.25, 0.26, 0.26), 12, 8, CRIMSON)
    add_box(bm, (0.0, 2.26, -0.06), (0.42, 0.09, 0.34), RED_HI, (12.0, 0.0, 0.0))
    make_part("saeed_body", bm, mats, parent=root)

    # 2) Flowing tattered crimson desert cloak (pivoted at upper back for roll/sprint billow!)
    bm_c = bmesh.new()
    add_box(bm_c, (0.0, -0.58, 0.12), (0.76, 1.24, 0.07), CRIMSON, (-8.0, 0.0, 0.0))
    add_box(bm_c, (-0.28, -1.16, 0.19), (0.24, 0.36, 0.06), RED_HI, (-10.0, 0.0, -8.0))
    add_box(bm_c, (0.02, -1.24, 0.21), (0.26, 0.44, 0.06), CRIMSON, (-12.0, 0.0, 3.0))
    add_box(bm_c, (0.30, -1.12, 0.18), (0.22, 0.32, 0.06), RED_HI, (-9.0, 0.0, 10.0))
    make_part("saeed_cloak_pivot", bm_c, mats, parent=root, pivot_gd=(0.0, 1.78, 0.22))

    # 3) Left arm (incendiary throw / crossbow brace arm)
    bm_l = bmesh.new()
    add_cyl_pts(bm_l, (0.0, 0.0, 0.0), (-0.08, -0.34, -0.10), 0.10, 0.085, 8, KHAKI)
    add_cyl_pts(bm_l, (-0.08, -0.34, -0.10), (0.06, -0.44, -0.38), 0.085, 0.07, 8, DARK)
    add_sphere(bm_l, (0.08, -0.45, -0.44), (0.08, 0.08, 0.08), 8, 6, LEATH)
    # Incendiary grenade gripped on forearm clip
    add_cyl(bm_l, (-0.04, -0.40, -0.26), 0.05, 0.05, 0.16, 8, INCEN)
    make_part("saeed_arm_l", bm_l, mats, parent=root, pivot_gd=(-0.44, 1.66, 0.0))

    # 4) Right arm + Saeed's iconic tactical crossbow-carbine weapon!
    bm_r = bmesh.new()
    add_cyl_pts(bm_r, (0.0, 0.0, 0.0), (0.06, -0.34, -0.08), 0.10, 0.085, 8, KHAKI)
    add_cyl_pts(bm_r, (0.06, -0.34, -0.08), (-0.04, -0.40, -0.38), 0.085, 0.07, 8, DARK)
    add_sphere(bm_r, (-0.04, -0.40, -0.44), (0.08, 0.08, 0.08), 8, 6, LEATH)
    # Heavy M249/Crossbow-hybrid weapon pointing -Z forward
    add_box(bm_r, (-0.04, -0.36, -0.78), (0.12, 0.16, 0.88), GUN)
    add_box(bm_r, (-0.04, -0.48, -0.70), (0.16, 0.18, 0.22), BRONZE)  # Box mag
    add_cyl(bm_r, (-0.04, -0.34, -1.32), 0.032, 0.028, 0.42, 8, GUN, (90.0, 0.0, 0.0))
    # Crossbow prod limbs accented in bronze/red!
    add_box(bm_r, (-0.04, -0.32, -1.08), (0.68, 0.04, 0.07), BRONZE, (0.0, 12.0, 0.0))
    add_box(bm_r, (-0.04, -0.24, -0.74), (0.07, 0.08, 0.24), RED_HI)
    make_part("saeed_arm_r", bm_r, mats, parent=root, pivot_gd=(0.44, 1.66, 0.0))
    return root


def build_boss_reis(mats, M):
    """「阿萨拉军阀·雷斯」(Warlord Reis, ~2.62m towering heavy warlord with greatcoat, gold epaulettes, shotgun & brass gramophone!)."""
    root = bpy.data.objects.new("boss_reis", None)
    bpy.context.collection.objects.link(root)

    DARK = M["Mat_TacDark"]
    GOLD = M["Mat_GoldTrim"]
    BRONZE = M["Mat_Bronze"]
    CRIMSON = M["Mat_CrimsonCloak"]
    GUN = M["Mat_Gunmetal"]
    SKIN = M["Mat_SkinWarm"]
    SUN = M["Mat_SunGlass"]
    WALNUT = M["Mat_WoodWalnut"]
    LEATH = M["Mat_LeatherBrown"]

    # 1) Massive heavy-armored body + long gold-trimmed dark greatcoat
    bm = bmesh.new()
    for sgn in (-1.0, 1.0):
        lx = sgn * 0.28
        add_box(bm, (lx, 0.13, -0.05), (0.24, 0.26, 0.40), DARK)
        add_cyl(bm, (lx, 0.50, 0.0), 0.14, 0.16, 0.58, 10, DARK)
        add_box(bm, (lx, 0.78, -0.14), (0.19, 0.20, 0.09), GOLD)  # Gold armored greave guard
        add_cyl(bm, (lx, 1.04, 0.0), 0.16, 0.18, 0.52, 10, DARK)
    # Flared dark officer greatcoat lower skirt with gold trim hem
    add_box(bm, (0.0, 0.92, 0.16), (0.94, 0.92, 0.24), DARK, (-6.0, 0.0, 0.0))
    add_box(bm, (-0.42, 0.92, 0.0), (0.14, 0.90, 0.46), DARK)
    add_box(bm, (0.42, 0.92, 0.0), (0.14, 0.90, 0.46), DARK)
    add_box(bm, (0.0, 0.48, 0.21), (0.96, 0.08, 0.08), GOLD)

    # Broad heavy torso + ceramic ballistic breastplate + gold warlord belt & buckle
    add_box(bm, (0.0, 1.66, 0.0), (0.92, 0.72, 0.48), DARK)
    add_box(bm, (0.0, 1.68, -0.04), (0.78, 0.58, 0.52), GUN)
    add_box(bm, (0.0, 1.28, 0.0), (0.88, 0.14, 0.52), LEATH)
    add_box(bm, (0.0, 1.28, -0.28), (0.22, 0.16, 0.06), GOLD)
    # Crimson upturned officer coat collar + ornate gold epaulette shoulder plates!
    add_cyl(bm, (0.0, 2.06, 0.04), 0.34, 0.38, 0.22, 12, CRIMSON)
    for sgn in (-1.0, 1.0):
        add_box(bm, (sgn * 0.54, 1.98, 0.0), (0.34, 0.18, 0.40), DARK, (0.0, 0.0, -sgn * 14.0))
        add_box(bm, (sgn * 0.56, 2.08, 0.0), (0.30, 0.07, 0.34), GOLD, (0.0, 0.0, -sgn * 14.0))
    # Stern bearded head + aviator dark sunglasses + gold-banded beret/cap
    add_sphere(bm, (0.0, 2.30, -0.02), (0.23, 0.25, 0.23), 12, 8, SKIN)
    add_box(bm, (0.0, 2.18, -0.17), (0.24, 0.14, 0.14), DARK)  # Thick beard
    add_box(bm, (0.0, 2.34, -0.22), (0.30, 0.09, 0.07), SUN)   # Aviator sunglasses
    add_box(bm, (0.0, 2.35, -0.23), (0.32, 0.03, 0.04), GOLD)  # Gold brow bar
    add_cyl(bm, (0.0, 2.50, 0.0), 0.25, 0.27, 0.16, 12, CRIMSON, (0.0, 0.0, 8.0))
    add_cyl(bm, (0.0, 2.43, 0.0), 0.26, 0.26, 0.05, 12, GOLD)
    make_part("reis_body", bm, mats, parent=root)

    # 2) Left heavy armored arm (shield/gesture arm)
    bm_l = bmesh.new()
    add_cyl_pts(bm_l, (0.0, 0.0, 0.0), (-0.10, -0.44, -0.10), 0.14, 0.12, 8, DARK)
    add_cyl_pts(bm_l, (-0.10, -0.44, -0.10), (0.04, -0.52, -0.44), 0.12, 0.10, 8, GUN)
    add_sphere(bm_l, (0.06, -0.54, -0.50), (0.10, 0.10, 0.10), 8, 6, GOLD)
    make_part("reis_arm_l", bm_l, mats, parent=root, pivot_gd=(-0.58, 1.88, 0.0))

    # 3) Right arm + massive S12K-style drum-magazine tactical heavy shotgun!
    bm_r = bmesh.new()
    add_cyl_pts(bm_r, (0.0, 0.0, 0.0), (0.10, -0.44, -0.08), 0.14, 0.12, 8, DARK)
    add_cyl_pts(bm_r, (0.10, -0.44, -0.08), (-0.04, -0.48, -0.44), 0.12, 0.10, 8, GUN)
    add_sphere(bm_r, (-0.04, -0.48, -0.50), (0.10, 0.10, 0.10), 8, 6, GOLD)
    # Heavy drum-mag tactical shotgun
    add_box(bm_r, (-0.04, -0.44, -0.88), (0.14, 0.18, 0.96), GUN)
    add_cyl(bm_r, (-0.04, -0.60, -0.80), 0.15, 0.15, 0.14, 12, DARK, (90.0, 0.0, 0.0))  # Iconic drum mag!
    add_cyl(bm_r, (-0.04, -0.42, -1.48), 0.045, 0.042, 0.44, 10, GUN, (90.0, 0.0, 0.0))
    add_box(bm_r, (-0.04, -0.33, -0.84), (0.10, 0.06, 0.36), GOLD)
    make_part("reis_arm_r", bm_r, mats, parent=root, pivot_gd=(0.58, 1.88, 0.0))

    # 4) Signature back/shoulder-mounted miniature antique brass gramophone (plays Reis's battle symphony!)
    bm_g = bmesh.new()
    add_box(bm_g, (0.0, 0.0, 0.0), (0.34, 0.22, 0.34), WALNUT)
    add_cyl(bm_g, (0.0, 0.13, 0.0), 0.14, 0.14, 0.03, 12, DARK)
    add_cyl_pts(bm_g, (0.0, 0.12, 0.10), (0.08, 0.42, -0.02), 0.04, 0.08, 8, BRONZE)
    add_cyl(bm_g, (0.14, 0.56, -0.14), 0.07, 0.26, 0.34, 14, GOLD, (48.0, -24.0, 0.0))
    make_part("reis_gramophone", bm_g, mats, parent=root, pivot_gd=(-0.38, 2.22, 0.24))
    return root


def build_ahsarah_guard(mats, M):
    """阿萨拉卫队步兵 (~1.90m, desert khaki fatigues + crimson shemagh headwrap & scarf + carbine)."""
    bm = bmesh.new()
    KHAKI = M["Mat_DesertKhaki"]
    SAND = M["Mat_SandCloth"]
    CRIMSON = M["Mat_CrimsonCloak"]
    RED_HI = M["Mat_CrimsonBright"]
    DARK = M["Mat_TacDark"]
    LEATH = M["Mat_LeatherBrown"]
    GUN = M["Mat_Gunmetal"]
    SKIN = M["Mat_SkinWarm"]

    for sgn in (-1.0, 1.0):
        lx = sgn * 0.18
        add_box(bm, (lx, 0.09, -0.03), (0.16, 0.18, 0.28), LEATH)
        add_cyl(bm, (lx, 0.36, 0.0), 0.09, 0.10, 0.40, 8, KHAKI)
        add_cyl(bm, (lx, 0.74, 0.0), 0.10, 0.115, 0.40, 8, KHAKI)
    add_box(bm, (0.0, 0.96, 0.0), (0.48, 0.18, 0.26), KHAKI)
    add_box(bm, (0.0, 1.28, 0.0), (0.52, 0.48, 0.30), SAND)
    add_box(bm, (0.0, 1.29, -0.02), (0.46, 0.38, 0.34), DARK)  # Chest rig
    # Crimson shemagh neck wrap + headwrap + face mask
    add_cyl(bm, (0.0, 1.56, 0.0), 0.22, 0.20, 0.14, 10, RED_HI)
    add_sphere(bm, (0.0, 1.74, 0.0), (0.17, 0.19, 0.18), 10, 7, SKIN)
    add_cyl(bm, (0.0, 1.82, 0.01), 0.19, 0.17, 0.16, 10, CRIMSON)
    add_box(bm, (0.0, 1.68, -0.14), (0.19, 0.11, 0.10), CRIMSON)
    add_box(bm, (0.0, 1.77, -0.16), (0.20, 0.06, 0.06), DARK)
    # Arms & desert carbine
    add_cyl_pts(bm, (-0.32, 1.44, 0.0), (-0.22, 1.16, -0.26), 0.075, 0.06, 8, SAND)
    add_cyl_pts(bm, (0.32, 1.44, 0.0), (0.22, 1.18, -0.28), 0.075, 0.06, 8, SAND)
    add_box(bm, (0.16, 1.18, -0.48), (0.09, 0.12, 0.68), GUN)
    add_cyl(bm, (0.16, 1.19, -0.88), 0.024, 0.022, 0.28, 8, GUN, (90.0, 0.0, 0.0))

    return make_part("ahsarah_guard", bm, mats, smooth=True)


def build_haavk_trooper(mats, M):
    """哈夫克集团科技护卫 (~1.94m, sleek white composite armor + glowing electric-cyan visor + pulse rifle)."""
    bm = bmesh.new()
    WHITE = M["Mat_HaavkWhite"]
    GRAPH = M["Mat_HaavkGraphite"]
    CYAN = M["Mat_CyanVisor"]
    GUN = M["Mat_Gunmetal"]

    for sgn in (-1.0, 1.0):
        lx = sgn * 0.18
        add_box(bm, (lx, 0.10, -0.03), (0.16, 0.20, 0.29), GRAPH)
        add_cyl(bm, (lx, 0.37, 0.0), 0.095, 0.105, 0.42, 8, WHITE)
        add_cyl(bm, (lx, 0.76, 0.0), 0.105, 0.12, 0.42, 8, GRAPH)
        add_box(bm, (lx, 0.74, -0.10), (0.13, 0.22, 0.06), WHITE)
    add_box(bm, (0.0, 0.98, 0.0), (0.48, 0.18, 0.28), GRAPH)
    # Sleek angular Haavk composite chest armor + glowing cyan chest core bar
    add_box(bm, (0.0, 1.32, 0.0), (0.54, 0.50, 0.32), WHITE)
    add_box(bm, (0.0, 1.38, -0.17), (0.28, 0.08, 0.04), CYAN)
    # Back-mounted Haavk Mandel telemetry pack with cyan strips
    add_box(bm, (0.0, 1.38, 0.23), (0.36, 0.42, 0.18), WHITE)
    add_box(bm, (0.0, 1.42, 0.33), (0.22, 0.26, 0.03), CYAN)
    # Angular shoulder pauldrons
    for sgn in (-1.0, 1.0):
        add_box(bm, (sgn * 0.36, 1.50, 0.0), (0.18, 0.18, 0.26), WHITE, (0.0, 0.0, -sgn * 14.0))
    # Full-sealed matte-white helmet + luminous electric-cyan visor!
    add_sphere(bm, (0.0, 1.76, 0.0), (0.19, 0.21, 0.20), 12, 8, WHITE)
    add_box(bm, (0.0, 1.76, -0.17), (0.26, 0.11, 0.08), CYAN)
    # Arms & white-cyan Haavk pulse rifle
    add_cyl_pts(bm, (-0.34, 1.44, 0.0), (-0.22, 1.18, -0.28), 0.075, 0.065, 8, GRAPH)
    add_cyl_pts(bm, (0.34, 1.44, 0.0), (0.22, 1.20, -0.30), 0.075, 0.065, 8, GRAPH)
    add_box(bm, (0.16, 1.20, -0.52), (0.10, 0.14, 0.72), WHITE)
    add_box(bm, (0.16, 1.22, -0.54), (0.11, 0.04, 0.46), CYAN)
    add_cyl(bm, (0.16, 1.20, -0.94), 0.025, 0.022, 0.26, 8, GUN, (90.0, 0.0, 0.0))

    return make_part("haavk_trooper", bm, mats, smooth=True)


def main():
    clear_scene()
    mats, M = build_materials()
    build_boss_saeed(mats, M)
    build_boss_reis(mats, M)
    build_ahsarah_guard(mats, M)
    build_haavk_trooper(mats, M)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
        export_apply=True,
    )
    print(f"Exported 4 Ahsarah character models -> {OUT_GLB} ({OUT_GLB.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
