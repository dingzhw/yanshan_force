"""Build v0.5.5 CC0 3D wildlife, exotic mountain flora, Jiangnan farmhouse & guardrail bays in Blender 4.5.

Generated assets (exported into game/assets/slice/v055_eco_assets.glb):
- animal_rabbit      (Cottontail mountain rabbit facing -Z, grounded at y=0)
- animal_squirrel    (Red-brown bushy-tailed squirrel facing -Z, grounded at y=0)
- animal_fish        (Jade-silver brook trout/minnow facing -Z, centered at y=0)
- animal_crab        (Creek crab with arched shell, pincers & splayed legs facing -Z, grounded at y=0)
- flora_glow_orchid  (Wild bioluminescent mountain orchid cluster, grounded at y=0)
- flora_berry_fern   (Curling woodland fern with scarlet mountain berries, grounded at y=0)
- horizon_farmhouse  (Jiangnan white-walled dark-tile cottage for paddy valley hamlets, grounded at y=0)
- mountain_fence_bay (4.0m timber double-rail mountain perimeter fence bay, grounded at y=0)

Run headless:
  blender.exe --background --factory-startup --python tools/build_v055_assets.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "game" / "assets" / "slice"
DEST.mkdir(parents=True, exist_ok=True)


def gd_to_bl(v: Vector) -> Vector:
    """Map Godot local coords (x, y_up, z) to Blender Z-up before export_yup=True."""
    return Vector((v.x, -v.z, v.y))


def _srgb_to_lin(c: tuple[float, float, float]) -> tuple[float, float, float, float]:
    return (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)


def make_mat(
    name: str,
    srgb: tuple[float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.65,
    emission_srgb: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = _srgb_to_lin(srgb)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission_srgb is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = _srgb_to_lin(emission_srgb)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def add_ellipsoid(bm: bmesh.types.BMesh, center, radii, rot_deg=(0.0, 0.0, 0.0), subdiv=2):
    r = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    verts = r["verts"]
    euler = Euler((math.radians(rot_deg[0]), math.radians(rot_deg[1]), math.radians(rot_deg[2])), "XYZ").to_matrix().to_4x4()
    cx, cy, cz = center
    rx, ry, rz = radii
    for v in verts:
        p = euler @ Vector((v.co.x * rx, v.co.y * ry, v.co.z * rz))
        v.co = gd_to_bl(Vector((cx + p.x, cy + p.y, cz + p.z)))


def add_box(bm: bmesh.types.BMesh, center, size, rot_deg=(0.0, 0.0, 0.0)):
    sx, sy, sz = size
    cx, cy, cz = center
    r = bmesh.ops.create_cube(bm, size=1.0)
    verts = r["verts"]
    euler = Euler((math.radians(rot_deg[0]), math.radians(rot_deg[1]), math.radians(rot_deg[2])), "XYZ").to_matrix().to_4x4()
    for v in verts:
        p = euler @ Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
        v.co = gd_to_bl(Vector((cx + p.x, cy + p.y, cz + p.z)))


def add_cyl(bm: bmesh.types.BMesh, p0, p1, r0: float, r1: float, segs: int = 8):
    v0 = Vector(p0)
    v1 = Vector(p1)
    diff = v1 - v0
    length = diff.length
    if length < 1e-5:
        return
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=r0,
        radius2=r1,
        depth=length,
    )
    mid = (v0 + v1) * 0.5
    up = Vector((0, 0, 1))
    bl_dir = gd_to_bl(diff).normalized()
    q = up.rotation_difference(bl_dir).to_matrix().to_4x4()
    bl_mid = gd_to_bl(mid)
    for v in res["verts"]:
        v.co = (q @ v.co) + bl_mid


def create_part(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, smooth: bool = True):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    mesh.materials.append(mat)
    if smooth:
        for poly in mesh.polygons:
            poly.use_smooth = True
    return obj


def join_parts(name: str, parts: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


def build_rabbit() -> bpy.types.Object:
    m_fur = make_mat("Mat_RabbitFur", (0.76, 0.62, 0.48), roughness=0.82)
    m_cream = make_mat("Mat_RabbitCream", (0.94, 0.90, 0.84), roughness=0.86)
    m_pink = make_mat("Mat_RabbitPink", (0.86, 0.54, 0.56), roughness=0.68)
    m_eye = make_mat("Mat_CritterEye", (0.05, 0.05, 0.06), metallic=0.1, roughness=0.18)

    parts = []
    # Main torso & haunches
    bm_f = bmesh.new()
    add_ellipsoid(bm_f, (0.0, 0.145, 0.04), (0.125, 0.12, 0.165), (-12, 0, 0), subdiv=2)
    add_ellipsoid(bm_f, (0.0, 0.165, -0.07), (0.10, 0.105, 0.12), (-18, 0, 0), subdiv=2)
    add_ellipsoid(bm_f, (0.0, 0.255, -0.175), (0.085, 0.082, 0.098), (-8, 0, 0), subdiv=2)
    # Hind thighs
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_f, (sx * 0.095, 0.105, 0.09), (0.055, 0.095, 0.085), (12, 0, sx * 8), subdiv=1)
        # Tall rabbit ears
        add_ellipsoid(bm_f, (sx * 0.046, 0.405, -0.125), (0.028, 0.125, 0.036), (20, sx * 8, -sx * 10), subdiv=2)
    parts.append(create_part("RabbitFur", bm_f, m_fur))

    bm_c = bmesh.new()
    add_ellipsoid(bm_c, (0.0, 0.13, -0.095), (0.072, 0.070, 0.085), (-10, 0, 0), subdiv=1)  # chest
    add_ellipsoid(bm_c, (0.0, 0.15, 0.215), (0.062, 0.062, 0.062), (0, 0, 0), subdiv=1)    # cotton tail
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_c, (sx * 0.075, 0.025, 0.075), (0.036, 0.024, 0.072), (0, 0, 0), subdiv=1)  # hind paws
        add_ellipsoid(bm_c, (sx * 0.058, 0.026, -0.135), (0.028, 0.026, 0.045), (0, 0, 0), subdiv=1) # fore paws
    parts.append(create_part("RabbitCream", bm_c, m_cream))

    bm_p = bmesh.new()
    add_ellipsoid(bm_p, (0.0, 0.245, -0.272), (0.018, 0.014, 0.014), (0, 0, 0), subdiv=1)  # nose
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_p, (sx * 0.045, 0.405, -0.138), (0.014, 0.090, 0.012), (20, sx * 8, -sx * 10), subdiv=1)
    parts.append(create_part("RabbitPink", bm_p, m_pink))

    bm_e = bmesh.new()
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_e, (sx * 0.062, 0.272, -0.225), (0.016, 0.018, 0.016), (0, 0, 0), subdiv=1)
    parts.append(create_part("RabbitEyes", bm_e, m_eye))

    return join_parts("animal_rabbit", parts)


def build_squirrel() -> bpy.types.Object:
    m_chestnut = make_mat("Mat_SquirrelFur", (0.64, 0.31, 0.14), roughness=0.80)
    m_cream = make_mat("Mat_SquirrelBelly", (0.91, 0.82, 0.68), roughness=0.84)
    m_eye = make_mat("Mat_CritterEye2", (0.05, 0.04, 0.04), roughness=0.20)

    parts = []
    bm_f = bmesh.new()
    add_ellipsoid(bm_f, (0.0, 0.12, 0.02), (0.075, 0.095, 0.115), (-22, 0, 0), subdiv=2)   # torso
    add_ellipsoid(bm_f, (0.0, 0.225, -0.115), (0.064, 0.062, 0.074), (-5, 0, 0), subdiv=2) # head
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_f, (sx * 0.044, 0.295, -0.095), (0.016, 0.036, 0.018), (12, 0, -sx * 12), subdiv=1) # ears
        add_ellipsoid(bm_f, (sx * 0.062, 0.075, 0.075), (0.038, 0.058, 0.055), (0, 0, 0), subdiv=1) # haunches
    # Iconic bushy S-curved squirrel tail arched behind & upward
    tail_pts = [
        ((0.0, 0.115, 0.135), (0.055, 0.060, 0.065), (30, 0, 0)),
        ((0.0, 0.215, 0.195), (0.070, 0.088, 0.072), (18, 0, 0)),
        ((0.0, 0.345, 0.185), (0.078, 0.095, 0.076), (-18, 0, 0)),
        ((0.0, 0.425, 0.115), (0.062, 0.068, 0.068), (-42, 0, 0)),
    ]
    for pos, rad, rot in tail_pts:
        add_ellipsoid(bm_f, pos, rad, rot, subdiv=2)
    parts.append(create_part("SquirrelFur", bm_f, m_chestnut))

    bm_c = bmesh.new()
    add_ellipsoid(bm_c, (0.0, 0.135, -0.045), (0.052, 0.068, 0.062), (-16, 0, 0), subdiv=1) # cream chest
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_c, (sx * 0.048, 0.020, -0.105), (0.020, 0.018, 0.035), (0, 0, 0), subdiv=1)
        add_ellipsoid(bm_c, (sx * 0.056, 0.020, 0.065), (0.024, 0.018, 0.046), (0, 0, 0), subdiv=1)
    parts.append(create_part("SquirrelBelly", bm_c, m_cream))

    bm_e = bmesh.new()
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_e, (sx * 0.048, 0.238, -0.158), (0.013, 0.014, 0.013), (0, 0, 0), subdiv=1)
    add_ellipsoid(bm_e, (0.0, 0.222, -0.188), (0.014, 0.012, 0.012), (0, 0, 0), subdiv=1) # dark nose
    parts.append(create_part("SquirrelEye", bm_e, m_eye))

    return join_parts("animal_squirrel", parts)


def build_fish() -> bpy.types.Object:
    m_body = make_mat("Mat_FishBody", (0.28, 0.56, 0.50), metallic=0.25, roughness=0.28)
    m_fin = make_mat("Mat_FishFin", (0.86, 0.48, 0.30), roughness=0.45)
    m_eye = make_mat("Mat_FishEye", (0.04, 0.05, 0.06), roughness=0.16)

    parts = []
    bm_b = bmesh.new()
    add_ellipsoid(bm_b, (0.0, 0.0, 0.0), (0.044, 0.062, 0.175), (0, 0, 0), subdiv=2)
    parts.append(create_part("FishBody", bm_b, m_body))

    bm_f = bmesh.new()
    # Forked tail fin (+Z), dorsal fin (+Y), side fins
    add_box(bm_f, (0.0, 0.032, 0.195), (0.012, 0.072, 0.088), (28, 0, 0))
    add_box(bm_f, (0.0, -0.032, 0.195), (0.012, 0.072, 0.088), (-28, 0, 0))
    add_box(bm_f, (0.0, 0.072, 0.025), (0.010, 0.055, 0.080), (-18, 0, 0))
    for sx in (-1.0, 1.0):
        add_box(bm_f, (sx * 0.052, -0.012, -0.045), (0.055, 0.010, 0.048), (0, sx * 32, sx * 12))
    parts.append(create_part("FishFins", bm_f, m_fin, smooth=False))

    bm_e = bmesh.new()
    for sx in (-1.0, 1.0):
        add_ellipsoid(bm_e, (sx * 0.034, 0.018, -0.115), (0.012, 0.012, 0.012), (0, 0, 0), subdiv=1)
    parts.append(create_part("FishEyes", bm_e, m_eye))

    return join_parts("animal_fish", parts)


def build_crab() -> bpy.types.Object:
    m_shell = make_mat("Mat_CrabShell", (0.78, 0.28, 0.18), metallic=0.06, roughness=0.42)
    m_claw = make_mat("Mat_CrabClaw", (0.92, 0.44, 0.24), roughness=0.45)
    m_eye = make_mat("Mat_CrabEye", (0.04, 0.04, 0.05), roughness=0.18)

    parts = []
    bm_s = bmesh.new()
    add_ellipsoid(bm_s, (0.0, 0.062, 0.0), (0.115, 0.046, 0.088), (0, 0, 0), subdiv=2)
    # 3 pairs of splayed creek crab legs touching y=0
    for sx in (-1.0, 1.0):
        for i, z_off in enumerate([-0.038, 0.008, 0.052]):
            z_bend = z_off + (i - 1) * 0.032
            hip = (sx * 0.095, 0.056, z_off)
            knee = (sx * 0.165, 0.072, z_bend * 1.15)
            foot = (sx * 0.195, 0.006, z_bend * 1.35)
            add_cyl(bm_s, hip, knee, 0.014, 0.011, segs=6)
            add_cyl(bm_s, knee, foot, 0.011, 0.007, segs=6)
    parts.append(create_part("CrabShell", bm_s, m_shell))

    bm_c = bmesh.new()
    for sx in (-1.0, 1.0):
        arm_mid = (sx * 0.125, 0.068, -0.095)
        add_cyl(bm_c, (sx * 0.075, 0.058, -0.055), arm_mid, 0.016, 0.014, segs=6)
        add_ellipsoid(bm_c, (sx * 0.105, 0.082, -0.145), (0.026, 0.022, 0.045), (-12, sx * 28, 0), subdiv=1)
    parts.append(create_part("CrabClaws", bm_c, m_claw))

    bm_e = bmesh.new()
    for sx in (-1.0, 1.0):
        add_cyl(bm_e, (sx * 0.035, 0.095, -0.062), (sx * 0.042, 0.125, -0.072), 0.008, 0.008, segs=6)
        add_ellipsoid(bm_e, (sx * 0.044, 0.130, -0.074), (0.013, 0.013, 0.013), (0, 0, 0), subdiv=1)
    parts.append(create_part("CrabEyes", bm_e, m_eye))

    return join_parts("animal_crab", parts)


def build_glow_orchid() -> bpy.types.Object:
    m_leaf = make_mat("Mat_OrchidLeaf", (0.16, 0.44, 0.25), roughness=0.58)
    m_petal = make_mat("Mat_OrchidPetal", (0.68, 0.42, 0.96), roughness=0.38, emission_srgb=(0.54, 0.30, 0.92), emission_strength=0.45)
    m_heart = make_mat("Mat_OrchidCore", (1.0, 0.85, 0.36), roughness=0.32, emission_srgb=(1.0, 0.82, 0.30), emission_strength=0.65)

    parts = []
    bm_l = bmesh.new()
    for k in range(6):
        ang = k * (TAU := math.tau) / 6.0
        ca, sa = math.cos(ang), math.sin(ang)
        add_ellipsoid(bm_l, (ca * 0.14, 0.09, sa * 0.14), (0.045, 0.022, 0.17), (-22, -math.degrees(ang) + 90, 0), subdiv=1)
    for sx, sz in [(0.05, 0.02), (-0.06, -0.03), (0.0, -0.06)]:
        add_cyl(bm_l, (sx * 0.4, 0.02, sz * 0.4), (sx * 1.8, 0.56, sz * 1.8), 0.016, 0.009, segs=6)
    parts.append(create_part("OrchidLeaves", bm_l, m_leaf))

    bm_p = bmesh.new()
    bm_h = bmesh.new()
    for sx, sz, h in [(0.09, 0.036, 0.57), (-0.108, -0.054, 0.53), (0.0, -0.108, 0.63)]:
        for p in range(5):
            pa = p * math.tau / 5.0
            add_ellipsoid(bm_p, (sx + math.cos(pa) * 0.058, h + 0.01, sz + math.sin(pa) * 0.058), (0.038, 0.015, 0.048), (15, -math.degrees(pa), 0), subdiv=1)
        add_ellipsoid(bm_h, (sx, h + 0.02, sz), (0.026, 0.024, 0.026), (0, 0, 0), subdiv=1)
    parts.append(create_part("OrchidPetals", bm_p, m_petal))
    parts.append(create_part("OrchidHearts", bm_h, m_heart))

    return join_parts("flora_glow_orchid", parts)


def build_berry_fern() -> bpy.types.Object:
    m_fern = make_mat("Mat_FernBlade", (0.24, 0.52, 0.22), roughness=0.68)
    m_berry = make_mat("Mat_ScarletBerry", (0.95, 0.26, 0.20), roughness=0.35, emission_srgb=(0.90, 0.24, 0.16), emission_strength=0.22)

    parts = []
    bm_f = bmesh.new()
    for k in range(7):
        ang = k * math.tau / 7.0 + 0.2
        ca, sa = math.cos(ang), math.sin(ang)
        add_ellipsoid(bm_f, (ca * 0.17, 0.14, sa * 0.17), (0.048, 0.020, 0.21), (-32, -math.degrees(ang) + 90, 0), subdiv=1)
    add_cyl(bm_f, (0.0, 0.0, 0.0), (0.02, 0.42, -0.02), 0.018, 0.010, segs=6)
    parts.append(create_part("FernBlades", bm_f, m_fern))

    bm_b = bmesh.new()
    for pos in [(0.05, 0.41, 0.03), (-0.04, 0.39, -0.04), (0.02, 0.46, -0.02), (0.06, 0.36, -0.05), (-0.05, 0.44, 0.04)]:
        add_ellipsoid(bm_b, pos, (0.034, 0.036, 0.034), (0, 0, 0), subdiv=1)
    parts.append(create_part("FernBerries", bm_b, m_berry))

    return join_parts("flora_berry_fern", parts)


def build_horizon_farmhouse() -> bpy.types.Object:
    m_wall = make_mat("Mat_WhitePlaster", (0.55, 0.54, 0.49), roughness=0.92)
    m_base = make_mat("Mat_StonePlinth", (0.28, 0.29, 0.26), roughness=0.95)
    m_roof = make_mat("Mat_DarkTileRoof", (0.17, 0.20, 0.23), roughness=0.78)
    m_timber = make_mat("Mat_CottageTimber", (0.30, 0.21, 0.14), roughness=0.84)
    m_window = make_mat("Mat_ShadedWindow", (0.25, 0.28, 0.27), roughness=0.45)

    parts = []
    bm_w = bmesh.new()
    add_box(bm_w, (0.0, 1.50, 0.0), (5.1, 2.30, 3.7))
    parts.append(create_part("HouseWalls", bm_w, m_wall, smooth=False))

    bm_b = bmesh.new()
    add_box(bm_b, (0.0, 0.18, 0.0), (5.35, 0.56, 3.95))
    parts.append(create_part("HousePlinth", bm_b, m_base, smooth=False))

    bm_r = bmesh.new()
    # Two-slope pitched Jiangnan dark roof + ridge beam + deep overhanging eaves
    add_box(bm_r, (0.0, 3.12, 1.05), (5.95, 0.26, 2.60), (26, 0, 0))
    add_box(bm_r, (0.0, 3.12, -1.05), (5.95, 0.26, 2.60), (-26, 0, 0))
    add_box(bm_r, (0.0, 3.72, 0.0), (6.10, 0.24, 0.30))
    parts.append(create_part("HouseRoof", bm_r, m_roof, smooth=False))

    bm_t = bmesh.new()
    add_box(bm_t, (0.0, 0.92, 1.90), (1.02, 1.78, 0.12))  # front wooden door
    parts.append(create_part("HouseDoor", bm_t, m_timber, smooth=False))

    bm_g = bmesh.new()
    for sx in (-1.45, 1.45):
        add_box(bm_g, (sx, 1.52, 1.88), (0.74, 0.60, 0.08))
    parts.append(create_part("HouseWindows", bm_g, m_window, smooth=False))

    return join_parts("horizon_farmhouse", parts)


def build_mountain_fence_bay() -> bpy.types.Object:
    m_cedar = make_mat("Mat_MountainCedar", (0.44, 0.32, 0.21), roughness=0.86)
    m_plank = make_mat("Mat_MountainRail", (0.56, 0.42, 0.27), roughness=0.82)
    m_iron = make_mat("Mat_FenceIron", (0.18, 0.20, 0.22), metallic=0.65, roughness=0.45)

    parts = []
    bm_p = bmesh.new()
    # 4.0m bay along X centered at 0: end-to-end joinable at x=-2.0
    add_box(bm_p, (-2.0, 0.64, 0.0), (0.16, 1.28, 0.16))
    add_box(bm_p, (0.0, 0.61, 0.0), (0.14, 1.22, 0.14))
    parts.append(create_part("FencePosts", bm_p, m_cedar, smooth=False))

    bm_r = bmesh.new()
    add_box(bm_r, (0.0, 1.04, 0.0), (4.04, 0.12, 0.09))
    add_box(bm_r, (0.0, 0.56, 0.0), (4.04, 0.11, 0.08))
    parts.append(create_part("FenceRails", bm_r, m_plank, smooth=False))

    bm_i = bmesh.new()
    for px in (-2.0, 0.0):
        add_box(bm_i, (px, 1.30, 0.0), (0.19, 0.05, 0.19))
        for ry in (1.04, 0.56):
            add_box(bm_i, (px, ry, 0.0), (0.20, 0.14, 0.12))
    parts.append(create_part("FenceIron", bm_i, m_iron, smooth=False))

    return join_parts("mountain_fence_bay", parts)


def main():
    clear_scene()
    objs = [
        build_rabbit(),
        build_squirrel(),
        build_fish(),
        build_crab(),
        build_glow_orchid(),
        build_berry_fern(),
        build_horizon_farmhouse(),
        build_mountain_fence_bay(),
    ]
    out_path = DEST / "v055_eco_assets.glb"
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    meta = {
        "glb": str(out_path.relative_to(ROOT)),
        "bytes": out_path.stat().st_size,
        "meshes": {o.name: {"verts": len(o.data.vertices), "polys": len(o.data.polygons)} for o in objs},
    }
    (ROOT / "docs" / "slice-v055-assets-build.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    print("BUILT_V055_ASSETS", json.dumps(meta, ensure_ascii=False))


if __name__ == "__main__":
    main()
