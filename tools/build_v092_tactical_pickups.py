#!/usr/bin/env python3
"""Build high-craftsmanship sculpted PBR tactical pickups, Ahsarah desert stashes & Boss ordnance
for Yanshan Force v0.9.2 in Blender 4.5 LTS:
  1. pickup_ammo_crate     — NATO 5.56mm ribbed steel ammo box with latches, carry handle, yellow stencil & exposed brass rounds
  2. pickup_medkit         — Rugged crimson/ivory IFAK trauma hardcase with raised medical cross, clasps & top handle
  3. pickup_smoke_emp      — Detailed cylindrical EMP/smoke grenade with ribbed armor casing, safety spoon, pull-ring pin & glowing cyan core
  4. pickup_energy_stim    — Sleek aluminum tactical energy drink can + combat auto-injector stim pen on coaster pad
  5. ahsarah_desert_stash  — Sculpted Saharan sandstone rock outcrop + half-buried terracotta amphora jar + desert scarf + brass lamp glint
  6. ahsarah_loot_table    — Weathered military desert wooden supply footlocker table (exact flat top y=0.44m, deeply grounded)
  7. boss_incendiary_bolt  — Captain Saeed's glowing thermite incendiary crossbow bolt with steel broadhead & crimson fletching
  8. boss_frag_grenade     — Warlord Reis's heavy ribbed fragmentation grenade with brass spoon & armed red fuse light

Run with Blender 4.5:
  blender --background --python tools/build_v092_tactical_pickups.py

Outputs:
  game/assets/slice/v092_tactical_pickups.glb
"""
from __future__ import annotations

import math
import random
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "v092_tactical_pickups.glb"
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


def make_mat(name: str, hex_col: str, rough=0.62, metal=0.15, emit_hex: str | None = None, emit_str: float = 0.0, coat: float = 0.0):
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


def add_box(bm, center_gd, size_gd, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0), bevel_amt=0.0):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    scale = Matrix.Diagonal((size_gd[0], size_gd[2], size_gd[1], 1.0))
    bmesh.ops.transform(bm, matrix=Matrix.Translation(gd_to_bl(center_gd)) @ rot @ scale, verts=verts)
    if bevel_amt > 0.0:
        edges = list({e for v in verts for e in v.link_edges})
        res = bmesh.ops.bevel(bm, geom=edges, offset=bevel_amt, segments=2, affect="EDGES", clamp_overlap=True)
        verts = list(set(verts) | set(res.get("verts", [])))
    vset = set(verts)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def add_cyl(bm, center_gd, r_bot, r_top, height, segs=16, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_bot, radius2=r_top, depth=height)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(gd_to_bl(center_gd)) @ rot, verts=verts)
    vset = set(verts)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
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
    vset = set(verts)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def add_sphere(bm, center_gd, radii_gd, segs=14, rings=10, mat_idx=0):
    ret = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    verts = ret["verts"]
    scale = Matrix.Diagonal((radii_gd[0], radii_gd[2], radii_gd[1], 1.0))
    bmesh.ops.transform(bm, matrix=Matrix.Translation(gd_to_bl(center_gd)) @ scale, verts=verts)
    vset = set(verts)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def add_torus(bm, center_gd, major_r, minor_r, maj_segs=18, min_segs=8, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    trans = Matrix.Translation(gd_to_bl(center_gd)) @ rot
    ring_verts = []
    for i in range(maj_segs):
        a = math.tau * float(i) / float(maj_segs)
        ca, sa = math.cos(a), math.sin(a)
        row = []
        for j in range(min_segs):
            b = math.tau * float(j) / float(min_segs)
            cb, sb = math.cos(b), math.sin(b)
            rr = major_r + minor_r * cb
            # Local torus in XY plane of Blender (= XZ in Godot before rot)
            p_local = Vector((rr * ca, rr * sa, minor_r * sb))
            row.append(bm.verts.new(trans @ p_local))
        ring_verts.append(row)
    for i in range(maj_segs):
        i2 = (i + 1) % maj_segs
        for j in range(min_segs):
            j2 = (j + 1) % min_segs
            f = bm.faces.new((ring_verts[i][j], ring_verts[i2][j], ring_verts[i2][j2], ring_verts[i][j2]))
            f.material_index = mat_idx


def add_sculpted_rock(bm, center_gd, radii_gd, seed: int, mat_idx=0):
    rng = random.Random(seed)
    ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    verts = ret["verts"]
    cx, cy, cz = center_gd
    rx, ry, rz = radii_gd
    pa = rng.uniform(0.0, math.tau)
    pb = rng.uniform(0.0, math.tau)
    for v in verts:
        p = v.co.copy()
        strata = math.sin(p.z * 6.5 + pa) * 0.16 + math.cos(p.x * 3.2 + p.y * 2.8 + pb) * 0.12
        r_m = 1.0 + strata
        gx = cx + p.x * rx * r_m
        gy = cy + p.z * ry * r_m
        gz = cz - p.y * rz * r_m
        if p.z < -0.25:
            gx = cx + (gx - cx) * 1.15
            gz = cz + (gz - cz) * 1.15
        v.co = gd_to_bl((gx, gy, gz))
    vset = set(verts)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def finalize_obj(name: str, bm: bmesh.types.BMesh, mats: list, smooth=True):
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
    return obj


def build_materials():
    specs = [
        ("Mat_OliveSteel", "435334", 0.56, 0.42, None, 0.0, 0.12),         # 0
        ("Mat_OliveDark", "2c3824", 0.64, 0.35, None, 0.0, 0.05),          # 1
        ("Mat_Gunmetal", "2b323a", 0.36, 0.80, None, 0.0, 0.15),           # 2
        ("Mat_SteelSilver", "aeb6bf", 0.28, 0.88, None, 0.0, 0.25),        # 3
        ("Mat_Brass", "d9a942", 0.26, 0.90, None, 0.0, 0.25),              # 4
        ("Mat_Copper", "c47240", 0.30, 0.86, None, 0.0, 0.20),             # 5
        ("Mat_StencilYellow", "f0be38", 0.52, 0.08, None, 0.0, 0.0),       # 6
        ("Mat_RubberBlack", "1b1e22", 0.84, 0.04, None, 0.0, 0.0),         # 7
        ("Mat_MedRed", "d12c2c", 0.38, 0.08, None, 0.0, 0.35),             # 8
        ("Mat_MedIvory", "f0f2ee", 0.36, 0.04, None, 0.0, 0.28),           # 9
        ("Mat_EmpCyan", "3aeaff", 0.14, 0.15, "28e6ff", 3.6, 0.45),        # 10
        ("Mat_StimGreen", "2ec97d", 0.26, 0.68, None, 0.0, 0.45),          # 11
        ("Mat_StimGlow", "58ff9a", 0.14, 0.10, "46ff90", 3.4, 0.45),       # 12
        ("Mat_StimDark", "1d2824", 0.40, 0.55, None, 0.0, 0.20),           # 13
        ("Mat_Sandstone", "d49f62", 0.90, 0.02, None, 0.0, 0.0),           # 14
        ("Mat_SandstoneDark", "a66f3a", 0.94, 0.02, None, 0.0, 0.0),       # 15
        ("Mat_Terracotta", "bf613c", 0.80, 0.04, None, 0.0, 0.05),         # 16
        ("Mat_DesertCloth", "9e2c26", 0.86, 0.02, None, 0.0, 0.0),         # 17
        ("Mat_WoodTan", "8b6944", 0.84, 0.02, None, 0.0, 0.0),             # 18
        ("Mat_WoodDark", "5c4228", 0.88, 0.02, None, 0.0, 0.0),            # 19
        ("Mat_FireOrange", "ff661a", 0.16, 0.10, "ff5a14", 4.2, 0.30),     # 20
        ("Mat_AlarmRed", "ff2a2a", 0.16, 0.10, "ff2424", 3.6, 0.35),       # 21
    ]
    mats = [make_mat(*s) for s in specs]
    M = {s[0]: i for i, s in enumerate(specs)}
    return mats, M


def build_pickup_ammo_crate(mats, M):
    """NATO 5.56mm ribbed steel ammo crate (~0.68m x 0.38m x 0.40m) with clasps, handle & visible brass rounds!"""
    bm = bmesh.new()
    OLV = M["Mat_OliveSteel"]
    ODK = M["Mat_OliveDark"]
    GUN = M["Mat_Gunmetal"]
    SLV = M["Mat_SteelSilver"]
    BRS = M["Mat_Brass"]
    COP = M["Mat_Copper"]
    YLW = M["Mat_StencilYellow"]
    RBR = M["Mat_RubberBlack"]

    # Rubber base pads + main beveled steel ammo box body
    for sx in (-0.27, 0.27):
        for sz in (-0.15, 0.15):
            add_box(bm, (sx, 0.015, sz), (0.10, 0.03, 0.08), RBR)
    add_box(bm, (0.0, 0.175, 0.0), (0.64, 0.30, 0.36), OLV, bevel_amt=0.014)
    # Recessed horizontal reinforcement ribs along front & back
    for ry in (0.10, 0.18, 0.26):
        add_box(bm, (0.0, ry, 0.182), (0.52, 0.022, 0.016), ODK)
        add_box(bm, (0.0, ry, -0.182), (0.52, 0.022, 0.016), ODK)
    # Yellow 5.56mm NATO stencil stripe band wrapping side & front corner
    add_box(bm, (-0.16, 0.18, 0.184), (0.20, 0.065, 0.010), YLW)
    add_box(bm, (-0.323, 0.18, 0.0), (0.012, 0.065, 0.24), YLW)
    # Overhanging hinged steel lid with beveled rim
    add_box(bm, (0.0, 0.345, 0.0), (0.67, 0.055, 0.39), ODK, bevel_amt=0.010)
    # Dual front chrome toggle draw-latches + side hinge knuckles
    for lx in (-0.18, 0.18):
        add_box(bm, (lx, 0.30, 0.198), (0.055, 0.11, 0.026), GUN)
        add_box(bm, (lx, 0.28, 0.210), (0.036, 0.06, 0.016), SLV)
        add_cyl(bm, (lx, 0.33, -0.195), 0.014, 0.014, 0.08, 8, GUN, (0.0, 0.0, 90.0))
    # Top folding steel carry handle & bracket
    add_box(bm, (0.0, 0.382, 0.0), (0.28, 0.020, 0.06), GUN)
    add_cyl_pts(bm, (-0.12, 0.385, 0.0), (-0.10, 0.455, 0.0), 0.011, 0.011, 8, SLV)
    add_cyl_pts(bm, (0.12, 0.385, 0.0), (0.10, 0.455, 0.0), 0.011, 0.011, 8, SLV)
    add_cyl_pts(bm, (-0.10, 0.455, 0.0), (0.10, 0.455, 0.0), 0.014, 0.014, 10, RBR)
    # Exposed linked 5.56mm brass cartridge strip resting proudly on lid corner so players recognize ammo instantly!
    for i in range(6):
        bx = 0.11 + i * 0.030
        add_cyl(bm, (bx, 0.392, 0.08), 0.010, 0.009, 0.075, 10, BRS, (90.0, 0.0, 0.0))
        add_cyl(bm, (bx, 0.392, 0.132), 0.008, 0.002, 0.032, 10, COP, (90.0, 0.0, 0.0))
    add_box(bm, (0.185, 0.385, 0.08), (0.18, 0.012, 0.035), GUN)

    return finalize_obj("pickup_ammo_crate", bm, mats, smooth=False)


def build_pickup_medkit(mats, M):
    """Rugged crimson/ivory tactical trauma IFAK hardcase (~0.48m x 0.36m x 0.24m) with raised cross emblem!"""
    bm = bmesh.new()
    RED = M["Mat_MedRed"]
    IVR = M["Mat_MedIvory"]
    GUN = M["Mat_Gunmetal"]
    SLV = M["Mat_SteelSilver"]
    RBR = M["Mat_RubberBlack"]

    # Slightly reclined upright trauma hardcase so BOTH front emblem and top silhouette read crisp from FPS height!
    # Molded rubber stand feet
    for sx in (-0.16, 0.16):
        add_box(bm, (sx, 0.022, 0.0), (0.09, 0.044, 0.24), RBR)
    # Main rugged ivory medical shell + crimson lid frame
    add_box(bm, (0.0, 0.20, 0.0), (0.46, 0.33, 0.21), IVR, bevel_amt=0.020)
    add_box(bm, (0.0, 0.20, 0.0), (0.48, 0.055, 0.225), RED)  # Perimeter gasket band
    # 4 heavy corner shock bumpers
    for sx in (-0.215, 0.215):
        for sy in (0.055, 0.345):
            add_box(bm, (sx, sy, 0.0), (0.055, 0.065, 0.225), RBR, bevel_amt=0.008)
    # Raised crisp crimson medical cross emblem on BOTH front (+Z) and back (-Z) faces!
    for fz in (-0.112, 0.112):
        add_box(bm, (0.0, 0.205, fz), (0.20, 0.19, 0.012), RED, bevel_amt=0.004)
        add_box(bm, (0.0, 0.205, fz + (0.009 if fz > 0 else -0.009)), (0.14, 0.046, 0.012), IVR)
        add_box(bm, (0.0, 0.205, fz + (0.009 if fz > 0 else -0.009)), (0.046, 0.14, 0.012), IVR)
    # Top medical cross badge on lid too for looking straight down
    add_box(bm, (0.0, 0.369, 0.0), (0.11, 0.012, 0.036), RED)
    add_box(bm, (0.0, 0.369, 0.0), (0.036, 0.012, 0.11), RED)
    # Dual silver locking clasps on top corners + ergonomic black carry handle
    for lx in (-0.15, 0.15):
        add_box(bm, (lx, 0.368, 0.065), (0.045, 0.032, 0.055), SLV)
    add_cyl_pts(bm, (-0.09, 0.365, 0.0), (-0.08, 0.435, 0.0), 0.014, 0.014, 8, GUN)
    add_cyl_pts(bm, (0.09, 0.365, 0.0), (0.08, 0.435, 0.0), 0.014, 0.014, 8, GUN)
    add_cyl_pts(bm, (-0.08, 0.435, 0.0), (0.08, 0.435, 0.0), 0.018, 0.018, 10, RBR)

    return finalize_obj("pickup_medkit", bm, mats, smooth=False)


def build_pickup_smoke_emp(mats, M):
    """High-detail Delta-Force tactical EMP / Smoke grenade canister (~0.26m x 0.40m x 0.26m) with spoon, pin & glowing cyan capacitor!"""
    bm = bmesh.new()
    GUN = M["Mat_Gunmetal"]
    SLV = M["Mat_SteelSilver"]
    BRS = M["Mat_Brass"]
    RBR = M["Mat_RubberBlack"]
    CYN = M["Mat_EmpCyan"]

    # Tactical base coaster pad so it sits cleanly grounded on terrain
    add_cyl(bm, (0.0, 0.018, 0.0), 0.135, 0.125, 0.036, 18, RBR)
    # Lower armored grenade skirt & heavy bevel ring
    add_cyl(bm, (0.0, 0.082, 0.0), 0.092, 0.096, 0.092, 18, GUN)
    add_torus(bm, (0.0, 0.052, 0.0), 0.096, 0.014, 18, 8, RBR)
    # Glowing electric-cyan EMP capacitor core band + 4 protective armor ribs!
    add_cyl(bm, (0.0, 0.175, 0.0), 0.084, 0.084, 0.105, 18, CYN)
    for k in range(4):
        ang = k * (math.tau / 4.0) + math.pi * 0.25
        rx, rz = math.cos(ang) * 0.088, math.sin(ang) * 0.088
        add_box(bm, (rx, 0.175, rz), (0.026, 0.115, 0.026), GUN, (0.0, math.degrees(ang), 0.0))
    # Upper ribbed steel body + tapered shoulder + brass fuse collar
    add_cyl(bm, (0.0, 0.268, 0.0), 0.096, 0.088, 0.086, 18, GUN)
    add_torus(bm, (0.0, 0.238, 0.0), 0.098, 0.012, 18, 8, SLV)
    add_cyl(bm, (0.0, 0.328, 0.0), 0.084, 0.044, 0.038, 16, SLV)
    add_cyl(bm, (0.0, 0.365, 0.0), 0.040, 0.036, 0.044, 14, BRS)
    # Fuse striker head cap
    add_box(bm, (0.018, 0.395, 0.0), (0.075, 0.034, 0.042), GUN, bevel_amt=0.005)
    # Curved metallic safety spoon lever hugging the +X side of the grenade!
    add_box(bm, (0.078, 0.375, 0.0), (0.060, 0.018, 0.032), SLV, (0.0, 0.0, -28.0))
    add_box(bm, (0.115, 0.255, 0.0), (0.018, 0.220, 0.034), SLV, (0.0, 0.0, 6.0))
    # Iconic brass safety pull-ring pin sticking out the -X side!
    add_cyl(bm, (-0.038, 0.392, 0.0), 0.008, 0.008, 0.055, 8, BRS, (0.0, 0.0, 90.0))
    add_torus(bm, (-0.088, 0.392, 0.0), 0.032, 0.007, 16, 8, BRS, (90.0, 0.0, 0.0))

    return finalize_obj("pickup_smoke_emp", bm, mats, smooth=True)


def build_pickup_energy_stim(mats, M):
    """Tactical aluminum energy drink can + combat epinephrine auto-injector stim pen (~0.32m x 0.38m x 0.24m)!"""
    bm = bmesh.new()
    GRN = M["Mat_StimGreen"]
    GLW = M["Mat_StimGlow"]
    SDK = M["Mat_StimDark"]
    SLV = M["Mat_SteelSilver"]
    RBR = M["Mat_RubberBlack"]
    YLW = M["Mat_StencilYellow"]

    # Compact rubberized tactical carry tray base
    add_box(bm, (0.0, 0.015, 0.0), (0.30, 0.030, 0.20), RBR, bevel_amt=0.008)

    # 1) Sleek Combat Energy Drink Can on left (-0.065, y, 0.0)
    cx = -0.065
    add_cyl(bm, (cx, 0.045, 0.0), 0.060, 0.070, 0.032, 20, SLV)      # Tapered aluminum base
    add_cyl(bm, (cx, 0.175, 0.0), 0.072, 0.072, 0.232, 20, SDK)      # Matte-black tactical grip body
    add_cyl(bm, (cx, 0.185, 0.0), 0.0735, 0.0735, 0.135, 20, GRN)    # Emerald anodized label band
    add_cyl(bm, (cx, 0.256, 0.0), 0.074, 0.074, 0.022, 20, GLW)      # Glowing lime accent ring
    add_cyl(bm, (cx, 0.114, 0.0), 0.074, 0.074, 0.016, 20, GLW)      # Lower neon trim ring
    # Sculpted lightning-bolt badge on front (+Z) of can!
    add_box(bm, (cx - 0.008, 0.205, 0.074), (0.022, 0.048, 0.010), YLW, (0.0, 0.0, 22.0))
    add_box(bm, (cx + 0.008, 0.168, 0.074), (0.022, 0.048, 0.010), YLW, (0.0, 0.0, 22.0))
    # Tapered aluminum can shoulder + rim + pull-tab!
    add_cyl(bm, (cx, 0.308, 0.0), 0.072, 0.060, 0.036, 20, SLV)
    add_torus(bm, (cx, 0.326, 0.0), 0.058, 0.007, 18, 8, SLV)
    add_box(bm, (cx + 0.012, 0.330, 0.0), (0.036, 0.006, 0.022), SLV)

    # 2) Combat Epinephrine Auto-Injector Stim Pen leaning slightly on right (+0.085, y, 0.0)
    sx = 0.088
    add_cyl(bm, (sx, 0.065, 0.01), 0.026, 0.026, 0.075, 14, YLW, (0.0, 0.0, -8.0))     # Safety needle cap
    add_cyl(bm, (sx - 0.012, 0.165, 0.01), 0.024, 0.024, 0.135, 14, GLW, (0.0, 0.0, -8.0))  # Glowing serum chamber
    add_cyl(bm, (sx - 0.025, 0.265, 0.01), 0.028, 0.028, 0.085, 14, SLV, (0.0, 0.0, -8.0))  # Titanium injector barrel
    add_cyl(bm, (sx - 0.033, 0.325, 0.01), 0.022, 0.022, 0.038, 12, M["Mat_MedRed"], (0.0, 0.0, -8.0))  # Trigger plunger

    return finalize_obj("pickup_energy_stim", bm, mats, smooth=True)


def build_ahsarah_desert_stash(mats, M):
    """Authentic North African sandstone alcove + terracotta amphora jar + crimson desert cloth stash (~1.15m x 0.78m x 1.05m).
    Deeply grounded down to y=-0.24m so ZERO buried or floating edges on desert terrain!"""
    bm = bmesh.new()
    SAND = M["Mat_Sandstone"]
    SDK = M["Mat_SandstoneDark"]
    TER = M["Mat_Terracotta"]
    CLT = M["Mat_DesertCloth"]
    BRS = M["Mat_Brass"]
    GLD = M["Mat_StencilYellow"]

    # Sculpted sunlit desert sandstone outcrop boulders cradling the stash (grounded deep to y=-0.24m!)
    add_sculpted_rock(bm, (-0.28, 0.18, -0.18), (0.48, 0.36, 0.42), 9201, SAND)
    add_sculpted_rock(bm, (0.30, 0.14, -0.22), (0.42, 0.32, 0.36), 9207, SDK)
    add_sculpted_rock(bm, (0.02, 0.08, 0.24), (0.44, 0.20, 0.30), 9213, SAND)
    # Tilted sculpted Moroccan ribbed terracotta amphora jar nestled proudly in open view!
    add_cyl(bm, (-0.06, 0.34, 0.02), 0.15, 0.26, 0.34, 14, TER, (14.0, 18.0, -18.0))
    add_cyl(bm, (-0.12, 0.56, 0.06), 0.26, 0.12, 0.22, 14, TER, (14.0, 18.0, -18.0))
    add_cyl(bm, (-0.16, 0.70, 0.09), 0.11, 0.15, 0.12, 14, SDK, (14.0, 18.0, -18.0))
    add_torus(bm, (-0.17, 0.75, 0.10), 0.145, 0.022, 14, 8, TER, (14.0, 18.0, -18.0))
    # Small companion brass desert lantern / oil vessel peeking out beside the jar!
    add_cyl(bm, (0.28, 0.22, 0.14), 0.10, 0.12, 0.14, 12, BRS)
    add_cyl(bm, (0.28, 0.34, 0.14), 0.11, 0.05, 0.11, 12, GLD)
    # Draped folded crimson desert cloth cover partially hiding the cache
    add_box(bm, (0.04, 0.36, -0.14), (0.64, 0.08, 0.36), CLT, (16.0, -12.0, 8.0), bevel_amt=0.015)

    return finalize_obj("ahsarah_desert_stash", bm, mats, smooth=True)


def build_ahsarah_loot_table(mats, M):
    """Weathered desert military wooden supply footlocker table (exact flat top y=0.44m, grounded down to y=-0.22m)."""
    bm = bmesh.new()
    WOD = M["Mat_WoodTan"]
    WDK = M["Mat_WoodDark"]
    GUN = M["Mat_Gunmetal"]
    YLW = M["Mat_StencilYellow"]
    SDK = M["Mat_SandstoneDark"]

    # Heavy sandstone base blocks deeply anchored to y=-0.22m so never floats on slopes
    for sx in (-0.42, 0.42):
        add_box(bm, (sx, -0.06, 0.0), (0.20, 0.32, 0.68), SDK)
    # Main rugged slatted desert supply chest body (y=0.06..0.44m -> exact top at 0.44m!)
    add_box(bm, (0.0, 0.24, 0.0), (1.06, 0.36, 0.68), WOD, bevel_amt=0.012)
    add_box(bm, (0.0, 0.425, 0.0), (1.10, 0.032, 0.72), WDK, bevel_amt=0.008)
    # Steel reinforcement corner straps & yellow stencil bar
    for sx in (-0.49, 0.49):
        add_box(bm, (sx, 0.24, 0.0), (0.09, 0.38, 0.70), GUN)
    add_box(bm, (0.0, 0.24, 0.345), (0.48, 0.075, 0.012), YLW)
    add_box(bm, (0.0, 0.24, -0.345), (0.48, 0.075, 0.012), YLW)
    # Dual front latches
    for lx in (-0.26, 0.26):
        add_box(bm, (lx, 0.34, 0.352), (0.06, 0.12, 0.025), GUN)

    return finalize_obj("ahsarah_loot_table", bm, mats, smooth=False)


def build_boss_incendiary_bolt(mats, M):
    """Captain Saeed's blazing thermite incendiary crossbow bolt (~1.10m long along +Z)."""
    bm = bmesh.new()
    GUN = M["Mat_Gunmetal"]
    SLV = M["Mat_SteelSilver"]
    FIR = M["Mat_FireOrange"]
    CLT = M["Mat_DesertCloth"]

    add_cyl(bm, (0.0, 0.0, 0.0), 0.028, 0.028, 0.88, 10, GUN, (90.0, 0.0, 0.0))
    # Glowing thermite incendiary warhead collar near front tip (+Z)
    add_cyl(bm, (0.0, 0.0, 0.32), 0.058, 0.054, 0.22, 12, FIR, (90.0, 0.0, 0.0))
    add_cyl(bm, (0.0, 0.0, 0.52), 0.052, 0.006, 0.20, 10, SLV, (90.0, 0.0, 0.0))
    # 3 crimson fletching vanes at rear (-Z)
    for k in range(3):
        ang = k * 120.0
        add_box(bm, (0.0, 0.0, -0.36), (0.012, 0.18, 0.22), CLT, (0.0, 0.0, ang))

    return finalize_obj("boss_incendiary_bolt", bm, mats, smooth=True)


def build_boss_frag_grenade(mats, M):
    """Warlord Reis's heavy ribbed fragmentation grenade (~0.28m x 0.36m x 0.28m) with armed crimson fuse light!"""
    bm = bmesh.new()
    ODK = M["Mat_OliveDark"]
    GUN = M["Mat_Gunmetal"]
    BRS = M["Mat_Brass"]
    RED = M["Mat_AlarmRed"]

    add_sphere(bm, (0.0, 0.16, 0.0), (0.12, 0.15, 0.12), 14, 10, ODK)
    for ry in (0.10, 0.16, 0.22):
        add_torus(bm, (0.0, ry, 0.0), 0.118 if ry == 0.16 else 0.104, 0.015, 14, 6, GUN)
    add_cyl(bm, (0.0, 0.31, 0.0), 0.042, 0.036, 0.06, 12, BRS)
    add_sphere(bm, (0.0, 0.355, 0.0), (0.032, 0.032, 0.032), 10, 8, RED)
    add_box(bm, (0.09, 0.24, 0.0), (0.022, 0.18, 0.038), BRS, (0.0, 0.0, 14.0))

    return finalize_obj("boss_frag_grenade", bm, mats, smooth=True)


def main():
    clear_scene()
    mats, M = build_materials()
    objs = [
        build_pickup_ammo_crate(mats, M),
        build_pickup_medkit(mats, M),
        build_pickup_smoke_emp(mats, M),
        build_pickup_energy_stim(mats, M),
        build_ahsarah_desert_stash(mats, M),
        build_ahsarah_loot_table(mats, M),
        build_boss_incendiary_bolt(mats, M),
        build_boss_frag_grenade(mats, M),
    ]
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        export_materials="EXPORT",
        export_yup=True,
    )
    print(f"Exported {len(objs)} sculpted v0.9.2 tactical pickup/stash/ordnance models -> {OUT_GLB} ({OUT_GLB.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
