#!/usr/bin/env python3
"""Build high-craftsmanship articulated 3D full-body hero '游侠·少羽' (Shaoyu)
for Yanshan Force v0.9.3 (First-Person legs/torso body awareness + seamless Third-Person view).

Hierarchy (Godot coordinates: +Y up, -Z forward, +X right, boots at y = 0.00m, head top ~1.74m):
  player_shaoyu
    └─ hips_pivot (0, 0.92, 0)
         ├─ hips_mesh
         ├─ torso_pivot (0, 0.06, 0)         # world y = 0.98
         │    ├─ torso_mesh                  # ranger jacket, plate carrier, scarf, gold accents
         │    ├─ backpack_mesh               # tactical pack, bedroll, whip antenna, green beacon
         │    ├─ weapon_back_mount           # diagonal rifle holster when knife is active
         │    ├─ head_pivot (0, 0.50, 0)     # world y = 1.48 (hidden in 1P)
         │    │    └─ head_mesh              # face, sculpted hair, comms headset, amber goggles
         │    ├─ arm_l_pivot (-0.215, 0.42, 0)   # hidden in 1P
         │    │    ├─ arm_l_mesh
         │    │    └─ forearm_l_pivot (0, -0.255, 0)
         │    │         └─ forearm_l_mesh
         │    └─ arm_r_pivot (+0.215, 0.42, 0)   # hidden in 1P
         │         ├─ arm_r_mesh
         │         └─ forearm_r_pivot (0, -0.255, 0)
         │              ├─ forearm_r_mesh
         │              └─ weapon_hand_mount (0, -0.24, -0.04)
         ├─ leg_l_pivot (-0.105, -0.02, 0)   # world y = 0.90 (visible in BOTH 1P & 3P!)
         │    ├─ thigh_l_mesh
         │    └─ shin_l_pivot (0, -0.43, 0)  # world y = 0.47
         │         └─ shin_l_mesh            # boot sole at local y = -0.47 (world y = 0.00)
         └─ leg_r_pivot (+0.105, -0.02, 0)   # world y = 0.90 (visible in BOTH 1P & 3P!)
              ├─ thigh_r_mesh
              └─ shin_r_pivot (0, -0.43, 0)  # world y = 0.47
                   └─ shin_r_mesh            # boot sole at local y = -0.47 (world y = 0.00)

Run with Blender 4.5:
  blender --background --python tools/build_v093_player_hero.py

Outputs:
  game/assets/slice/player_shaoyu.glb
"""
from __future__ import annotations

import math
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "player_shaoyu.glb"
OUT_GLB.parent.mkdir(parents=True, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def hex_lin(h: str) -> tuple[float, float, float, float]:
    h = h.lstrip("#")
    return (
        (int(h[0:2], 16) / 255.0) ** 2.2,
        (int(h[2:4], 16) / 255.0) ** 2.2,
        (int(h[4:6], 16) / 255.0) ** 2.2,
        1.0,
    )


def make_mat(name: str, hex_col: str, rough=0.68, metal=0.06, emit_hex: str | None = None, emit_str: float = 0.0, coat: float = 0.0):
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


def add_cyl(bm, center_gd, r_bot, r_top, height, segs=14, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_bot, radius2=r_top, depth=height)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(gd_to_bl(center_gd)) @ rot, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl_pts(bm, p0_gd, p1_gd, r0, r1, segs=12, mat_idx=0):
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


def add_sphere(bm, center_gd, radii_gd, segs=14, rings=10, mat_idx=0):
    ret = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    verts = ret["verts"]
    scale = Matrix.Diagonal((radii_gd[0], radii_gd[2], radii_gd[1], 1.0))
    bmesh.ops.transform(bm, matrix=Matrix.Translation(gd_to_bl(center_gd)) @ scale, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def make_empty(name: str, parent=None, loc_gd=(0.0, 0.0, 0.0), rot_deg_gd=(0.0, 0.0, 0.0)):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    obj.location = gd_to_bl(loc_gd)
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    obj.rotation_euler = Euler((rx, -rz, ry), "XYZ")
    return obj


def make_mesh_part(name: str, bm: bmesh.types.BMesh, mats: list, parent=None, loc_gd=(0.0, 0.0, 0.0), smooth=True):
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
    obj.location = gd_to_bl(loc_gd)
    return obj


def build_materials():
    specs = [
        ("Mat_RangerJade", "255248", 0.72, 0.04, None, 0.0, 0.0),         # 0: Jiangnan tactical jade-green jacket
        ("Mat_SlateDark", "252d34", 0.62, 0.14, None, 0.0, 0.0),          # 1: Dark charcoal vest / kneepads / trim
        ("Mat_CargoPants", "384540", 0.78, 0.02, None, 0.0, 0.0),         # 2: Deep moss-grey tactical trousers
        ("Mat_LeatherBoot", "473021", 0.54, 0.06, None, 0.0, 0.12),       # 3: Tough brown leather boots & straps
        ("Mat_RubberSole", "191d21", 0.85, 0.02, None, 0.0, 0.0),         # 4: Boot sole & glove palms
        ("Mat_ScarfCrimson", "b7352c", 0.76, 0.03, None, 0.0, 0.0),       # 5: Iconic warm crimson-vermilion scarf
        ("Mat_GoldAccent", "dfad44", 0.28, 0.84, None, 0.0, 0.25),        # 6: Shaoyu gilded brass emblem & buckle
        ("Mat_PackCanvas", "345448", 0.80, 0.02, None, 0.0, 0.0),         # 7: Tactical backpack body
        ("Mat_RollKhaki", "b8a37d", 0.84, 0.0, None, 0.0, 0.0),           # 8: Rolled field tarp on pack
        ("Mat_Skin", "e2b48f", 0.64, 0.0, None, 0.0, 0.0),                # 9: Warm healthy skin tone
        ("Mat_HairDark", "1b1e24", 0.56, 0.05, None, 0.0, 0.10),          # 10: Stylized layered dark hair
        ("Mat_AmberLens", "f6a533", 0.12, 0.25, "ff9e24", 1.8, 0.7),      # 11: Forehead tactical goggles lens
        ("Mat_BeaconMint", "54f2b8", 0.16, 0.20, "4ef5b8", 3.2, 0.5),     # 12: Friendly GTI/Yanshan green telemetry LED
        ("Mat_Gunmetal", "343c44", 0.36, 0.80, None, 0.0, 0.10),          # 13: Headset / clips / metal hardware
        ("Mat_EyeWhite", "f4f5f2", 0.30, 0.0, None, 0.0, 0.2),            # 14: Eyes white
        ("Mat_GloveDark", "22282d", 0.64, 0.08, None, 0.0, 0.0),          # 15: Tactical gloves
    ]
    mats = [make_mat(*s) for s in specs]
    M = {s[0]: i for i, s in enumerate(specs)}
    return mats, M


def build_hero():
    mats, M = build_materials()
    JADE = M["Mat_RangerJade"]
    SLATE = M["Mat_SlateDark"]
    PANTS = M["Mat_CargoPants"]
    BOOT = M["Mat_LeatherBoot"]
    SOLE = M["Mat_RubberSole"]
    SCARF = M["Mat_ScarfCrimson"]
    GOLD = M["Mat_GoldAccent"]
    PACK = M["Mat_PackCanvas"]
    ROLL = M["Mat_RollKhaki"]
    SKIN = M["Mat_Skin"]
    HAIR = M["Mat_HairDark"]
    AMBER = M["Mat_AmberLens"]
    BEACON = M["Mat_BeaconMint"]
    METAL = M["Mat_Gunmetal"]
    EYE = M["Mat_EyeWhite"]
    GLOVE = M["Mat_GloveDark"]

    root = make_empty("player_shaoyu", None, (0.0, 0.0, 0.0))

    # 1. HIPS PIVOT (world y = 0.92)
    hips_pivot = make_empty("hips_pivot", root, (0.0, 0.92, 0.0))
    bm = bmesh.new()
    # Pelvis block + jacket skirt hem
    add_box(bm, (0.0, 0.01, 0.0), (0.31, 0.17, 0.20), PANTS)
    add_box(bm, (0.0, 0.07, 0.0), (0.33, 0.06, 0.22), JADE)
    # Heavy leather tactical duty belt + brass Ranger buckle
    add_box(bm, (0.0, 0.055, 0.0), (0.345, 0.055, 0.232), BOOT)
    add_box(bm, (0.0, 0.055, -0.120), (0.072, 0.058, 0.018), GOLD)
    # Side & rear utility pouches
    add_box(bm, (-0.175, 0.035, -0.02), (0.048, 0.095, 0.085), SLATE)
    add_box(bm, (0.175, 0.035, 0.02), (0.048, 0.105, 0.088), SLATE)
    add_box(bm, (0.0, 0.035, 0.125), (0.17, 0.088, 0.055), PACK)
    add_box(bm, (0.0, 0.055, 0.152), (0.045, 0.022, 0.014), GOLD)
    make_mesh_part("hips_mesh", bm, mats, hips_pivot)

    # 2. TORSO PIVOT (world y = 0.98, local y = 0.06 above hips)
    torso_pivot = make_empty("torso_pivot", hips_pivot, (0.0, 0.06, 0.0))
    bm = bmesh.new()
    # Athletic tapered ranger jacket torso (local y = 0.0..0.48)
    add_box(bm, (0.0, 0.12, 0.0), (0.32, 0.22, 0.205), JADE)
    add_box(bm, (0.0, 0.32, 0.0), (0.37, 0.24, 0.225), JADE)
    # Shoulder yoke reinforcement
    add_box(bm, (0.0, 0.425, 0.0), (0.40, 0.065, 0.235), SLATE)
    # Tactical chest plate carrier (front & back panels + shoulder straps)
    add_box(bm, (0.0, 0.25, -0.118), (0.28, 0.30, 0.042), SLATE)
    add_box(bm, (0.0, 0.26, 0.118), (0.28, 0.30, 0.040), SLATE)
    for sx in (-0.11, 0.11):
        add_box(bm, (sx, 0.435, 0.0), (0.068, 0.045, 0.245), SLATE)
        add_box(bm, (sx * 1.48, 0.435, 0.0), (0.065, 0.032, 0.145), GOLD)  # Warm gold shoulder rank tabs
    # Front 3 triple 5.56 mag pouches + Ranger brass badge
    for mx in (-0.075, 0.0, 0.075):
        add_box(bm, (mx, 0.18, -0.148), (0.058, 0.115, 0.036), PACK)
        add_box(bm, (mx, 0.242, -0.148), (0.052, 0.020, 0.030), BOOT)
    add_box(bm, (0.075, 0.345, -0.144), (0.062, 0.044, 0.012), GOLD)
    add_box(bm, (-0.075, 0.345, -0.144), (0.060, 0.042, 0.014), METAL)
    # Iconic crimson-vermilion tactical collar scarf with golden trim + trailing back tail!
    add_cyl(bm, (0.0, 0.465, 0.0), 0.112, 0.105, 0.075, 16, SCARF)
    add_cyl(bm, (0.0, 0.432, 0.0), 0.120, 0.116, 0.018, 16, GOLD)
    add_box(bm, (-0.04, 0.34, 0.142), (0.095, 0.19, 0.024), SCARF, rot_deg_gd=(10.0, 0.0, -8.0))
    add_box(bm, (-0.05, 0.245, 0.158), (0.090, 0.025, 0.026), GOLD, rot_deg_gd=(10.0, 0.0, -8.0))
    make_mesh_part("torso_mesh", bm, mats, torso_pivot)

    # 2B. TACTICAL BACKPACK (child of torso_pivot, hidden in 1P!)
    bm = bmesh.new()
    # Main sculpted pack body (behind back z = +0.16..+0.30)
    add_box(bm, (0.0, 0.25, 0.215), (0.27, 0.32, 0.135), PACK)
    add_box(bm, (0.0, 0.38, 0.215), (0.255, 0.065, 0.125), SLATE)
    # Rear secondary zip pouch + twin leather compression straps + brass buckles
    add_box(bm, (0.0, 0.20, 0.292), (0.21, 0.17, 0.048), SLATE)
    for sx in (-0.075, 0.075):
        add_box(bm, (sx, 0.25, 0.312), (0.026, 0.28, 0.014), BOOT)
        add_box(bm, (sx, 0.26, 0.322), (0.032, 0.028, 0.014), GOLD)
    # Rolled field tarp strapped below pack
    add_cyl(bm, (0.0, 0.085, 0.225), 0.046, 0.046, 0.26, 12, ROLL, rot_deg_gd=(0.0, 0.0, 90.0))
    for sx in (-0.08, 0.08):
        add_cyl(bm, (sx, 0.085, 0.225), 0.050, 0.050, 0.020, 12, BOOT, rot_deg_gd=(0.0, 0.0, 90.0))
    # Friendly GTI / Yanshan telemetry green LED badge & compact whip radio antenna on left shoulder of pack
    add_box(bm, (0.085, 0.385, 0.282), (0.042, 0.024, 0.018), METAL)
    add_box(bm, (0.085, 0.385, 0.294), (0.028, 0.012, 0.010), BEACON)
    add_cyl_pts(bm, (-0.115, 0.40, 0.22), (-0.145, 0.64, 0.25), 0.010, 0.004, 8, METAL)
    add_sphere(bm, (-0.145, 0.645, 0.25), (0.010, 0.010, 0.010), 8, 6, BEACON)
    make_mesh_part("backpack_mesh", bm, mats, torso_pivot)

    # Diagonal back weapon holster mount (visible when knife is equipped)
    make_empty("weapon_back_mount", torso_pivot, (0.04, 0.28, 0.335), (0.0, 180.0, -34.0))

    # 3. HEAD PIVOT (child of torso_pivot at y = 0.50 -> world y = 1.48; hidden in 1P!)
    head_pivot = make_empty("head_pivot", torso_pivot, (0.0, 0.50, 0.0))
    bm = bmesh.new()
    # Neck
    add_cyl(bm, (0.0, 0.035, 0.0), 0.056, 0.052, 0.085, 12, SKIN)
    # Stylized sculpted head & jaw (centered y = 0.145 -> top ~0.255 -> world 1.735m!)
    add_sphere(bm, (0.0, 0.148, 0.0), (0.095, 0.112, 0.104), 16, 12, SKIN)
    add_box(bm, (0.0, 0.092, -0.025), (0.112, 0.068, 0.095), SKIN)
    # Subtle ears & nose bridge
    add_box(bm, (0.0, 0.132, -0.104), (0.022, 0.034, 0.024), SKIN)
    for sx in (-0.095, 0.095):
        add_sphere(bm, (sx, 0.142, 0.005), (0.018, 0.030, 0.022), 8, 6, SKIN)
    # Expressive eyebrows & eyes
    for sx in (-0.036, 0.036):
        add_box(bm, (sx, 0.154, -0.095), (0.024, 0.016, 0.012), EYE)
        add_box(bm, (sx, 0.154, -0.100), (0.013, 0.013, 0.008), HAIR)
        add_box(bm, (sx, 0.174, -0.098), (0.034, 0.009, 0.012), HAIR, rot_deg_gd=(0.0, 0.0, -8.0 if sx < 0 else 8.0))
    # Layered windswept dark hair crown & back locks (looks awesome from behind in 3P!)
    add_sphere(bm, (0.0, 0.182, 0.014), (0.106, 0.092, 0.114), 16, 10, HAIR)
    add_box(bm, (0.0, 0.145, 0.068), (0.175, 0.125, 0.085), HAIR)
    add_box(bm, (0.0, 0.095, 0.078), (0.148, 0.065, 0.062), HAIR, rot_deg_gd=(-14.0, 0.0, 0.0))
    # Dynamic front hair spikes
    add_box(bm, (-0.042, 0.218, -0.072), (0.062, 0.042, 0.065), HAIR, rot_deg_gd=(18.0, 12.0, -10.0))
    add_box(bm, (0.038, 0.222, -0.074), (0.068, 0.044, 0.068), HAIR, rot_deg_gd=(15.0, -14.0, 10.0))
    # Tactical forehead goggles (amber lenses + dark strap wrapping around hair!)
    add_cyl(bm, (0.0, 0.194, 0.008), 0.109, 0.109, 0.032, 18, SLATE)
    for sx in (-0.042, 0.042):
        add_box(bm, (sx, 0.196, -0.102), (0.066, 0.046, 0.028), SLATE)
        add_box(bm, (sx, 0.196, -0.114), (0.052, 0.034, 0.012), AMBER)
    add_box(bm, (0.0, 0.196, -0.102), (0.026, 0.022, 0.022), METAL)
    # Tactical comms earcups + headband + boom mic
    for sx in (-0.106, 0.106):
        add_cyl(bm, (sx, 0.145, 0.008), 0.034, 0.034, 0.030, 12, METAL, rot_deg_gd=(0.0, 0.0, 90.0))
        add_cyl(bm, (sx * 1.12, 0.145, 0.008), 0.022, 0.022, 0.012, 10, GOLD, rot_deg_gd=(0.0, 0.0, 90.0))
    add_cyl_pts(bm, (-0.108, 0.130, -0.01), (-0.035, 0.095, -0.108), 0.006, 0.005, 6, METAL)
    add_sphere(bm, (-0.032, 0.095, -0.112), (0.010, 0.009, 0.012), 8, 6, SLATE)
    make_mesh_part("head_mesh", bm, mats, head_pivot)

    # 4. ARMS (Left & Right, upper + forearm pivots; hidden in 1P!)
    for side_tag, sx in (("l", -1.0), ("r", 1.0)):
        arm_p = make_empty(f"arm_{side_tag}_pivot", torso_pivot, (sx * 0.215, 0.415, 0.0))
        bm = bmesh.new()
        # Rounded shoulder cap + tactical pauldrons
        add_sphere(bm, (0.0, -0.01, 0.0), (0.068, 0.068, 0.068), 12, 8, JADE)
        add_box(bm, (sx * 0.015, -0.03, 0.0), (0.095, 0.088, 0.110), SLATE)
        # Upper arm cylinder
        add_cyl_pts(bm, (0.0, -0.03, 0.0), (0.0, -0.255, 0.0), 0.056, 0.048, 12, JADE)
        # Vanguard gold armband on right upper arm
        if side_tag == "r":
            add_cyl(bm, (0.0, -0.14, 0.0), 0.055, 0.056, 0.036, 12, GOLD)
            add_cyl(bm, (0.0, -0.14, 0.0), 0.057, 0.057, 0.014, 12, SCARF)
        make_mesh_part(f"arm_{side_tag}_mesh", bm, mats, arm_p)

        fore_p = make_empty(f"forearm_{side_tag}_pivot", arm_p, (0.0, -0.255, 0.0))
        bm = bmesh.new()
        add_sphere(bm, (0.0, 0.0, 0.0), (0.048, 0.048, 0.048), 10, 8, SLATE)  # Elbow pad
        add_cyl_pts(bm, (0.0, 0.0, 0.0), (0.0, -0.215, 0.0), 0.046, 0.038, 12, JADE)
        # Tactical cuff & wrist computer on left wrist
        add_cyl(bm, (0.0, -0.195, 0.0), 0.042, 0.040, 0.038, 12, SLATE)
        if side_tag == "l":
            add_box(bm, (-0.034, -0.185, -0.015), (0.020, 0.042, 0.032), METAL)
            add_box(bm, (-0.045, -0.185, -0.015), (0.005, 0.030, 0.022), BEACON)
        # Gloved tactical hand (palm + thumb + knuckle guard)
        add_box(bm, (0.0, -0.248, -0.006), (0.048, 0.072, 0.062), GLOVE)
        add_box(bm, (0.0, -0.238, -0.036), (0.046, 0.024, 0.016), SLATE)
        add_box(bm, (-sx * 0.028, -0.244, -0.025), (0.020, 0.038, 0.022), GLOVE)
        make_mesh_part(f"forearm_{side_tag}_mesh", bm, mats, fore_p)

        if side_tag == "r":
            make_empty("weapon_hand_mount", fore_p, (0.0, -0.245, -0.035), (0.0, 0.0, 0.0))

    # 5. LEGS (Left & Right, thigh + shin pivots; VISIBLE IN BOTH 1P AND 3P!)
    # Hips at y = 0.92; leg_pivot at local y = -0.02 (world y = 0.90);
    # shin_pivot at local y = -0.43 (world y = 0.47); boot sole at local y = -0.47 (world y = 0.00m EXACTLY!)
    for side_tag, sx in (("l", -1.0), ("r", 1.0)):
        leg_p = make_empty(f"leg_{side_tag}_pivot", hips_pivot, (sx * 0.105, -0.02, 0.0))
        bm = bmesh.new()
        add_sphere(bm, (0.0, 0.0, 0.0), (0.078, 0.078, 0.078), 12, 8, PANTS)
        add_cyl_pts(bm, (0.0, 0.0, 0.0), (0.0, -0.43, 0.0), 0.080, 0.062, 14, PANTS)
        # Cargo thigh pocket + tactical strap
        add_box(bm, (sx * 0.076, -0.18, 0.005), (0.036, 0.14, 0.095), SLATE if side_tag == "r" else PACK)
        add_cyl(bm, (0.0, -0.17, 0.0), 0.074, 0.072, 0.024, 12, BOOT)
        make_mesh_part(f"thigh_{side_tag}_mesh", bm, mats, leg_p)

        shin_p = make_empty(f"shin_{side_tag}_pivot", leg_p, (0.0, -0.43, 0.0))
        bm = bmesh.new()
        # Tactical hard-shell kneepad right at knee joint!
        add_sphere(bm, (0.0, 0.0, -0.052), (0.056, 0.062, 0.034), 10, 8, SLATE)
        add_box(bm, (0.0, 0.0, -0.076), (0.064, 0.072, 0.016), METAL)
        # Calf trouser tapered into boot cuff
        add_cyl_pts(bm, (0.0, 0.0, 0.0), (0.0, -0.32, 0.0), 0.062, 0.048, 14, PANTS)
        # Rugged laced leather combat boot (y = -0.29..-0.47, toe forward -Z)
        add_cyl_pts(bm, (0.0, -0.29, 0.0), (0.0, -0.425, 0.0), 0.056, 0.052, 12, BOOT)
        add_box(bm, (0.0, -0.415, -0.050), (0.096, 0.078, 0.195), BOOT)
        # Rounded toe cap
        add_sphere(bm, (0.0, -0.422, -0.140), (0.047, 0.034, 0.042), 10, 8, BOOT)
        # Thick black rubber tread sole touching EXACTLY y = -0.470 (world y = 0.000m!)
        add_box(bm, (0.0, -0.456, -0.052), (0.104, 0.028, 0.215), SOLE)
        # Brass boot lace eyelets
        for ly in (-0.315, -0.345, -0.375):
            add_box(bm, (0.0, ly, -0.054), (0.038, 0.010, 0.012), GOLD)
        make_mesh_part(f"shin_{side_tag}_mesh", bm, mats, shin_p)

    return root


def main():
    clear_scene()
    build_hero()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_materials="EXPORT",
    )
    print(f"Exported {OUT_GLB} ({OUT_GLB.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
