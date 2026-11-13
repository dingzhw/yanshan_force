"""Build v0.5.3 CC0 3D tactical weapons, attachments, and pickups in Blender 4.5.

Generated assets (exported into game/assets/slice/):
- tactical_knife.glb      (Bone-local hand.R aligned combat knife for BoneAttachment3D)
- rifle_attachments.glb (att_scope_2x, att_suppressor, att_compensator, att_angled_grip)
- tactical_pickups.glb    (pickup_ammo_crate, pickup_smoke_emp, pickup_energy_drink)

Run headless:
  blender.exe --background --factory-startup --python tools/build_v053_assets.py
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
    """Map Godot local coords (x, y_up, -z_fwd) to Blender Z-up before export_yup=True."""
    return Vector((v.x, -v.z, v.y))


def _srgb_to_lin(c: tuple[float, float, float]) -> tuple[float, float, float, float]:
    return (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)


def make_mat(
    name: str,
    srgb: tuple[float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.5,
    alpha: float = 1.0,
    emission_srgb: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = _srgb_to_lin(srgb)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 0.999:
        mat.blend_method = "BLEND"
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
    if emission_srgb is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = _srgb_to_lin(emission_srgb)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def create_mesh_obj(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, smooth: bool = False) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    return obj


def join_with_materials(name: str, parts: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


def export_objects(objs: list[bpy.types.Object], out_path: Path) -> int:
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
    return out_path.stat().st_size


# ---------------------------------------------------------------------------
# 1. Tactical Combat Knife (hand.R Bone-Local Coordinates)
# ---------------------------------------------------------------------------

def build_tactical_knife() -> dict:
    clear_scene()
    m_grip = make_mat("Mat_KnifeGrip", (0.14, 0.18, 0.14), metallic=0.05, roughness=0.82)
    m_guard = make_mat("Mat_KnifeGuard", (0.19, 0.22, 0.24), metallic=0.78, roughness=0.36)
    m_dark = make_mat("Mat_KnifeDark", (0.20, 0.24, 0.28), metallic=0.88, roughness=0.30)
    m_edge = make_mat("Mat_KnifeEdge", (0.78, 0.82, 0.86), metallic=0.95, roughness=0.18)
    m_brass = make_mat("Mat_KnifeBrass", (0.76, 0.60, 0.28), metallic=0.88, roughness=0.28)

    # Measured in Blender from hand.R in pose_knife_idle:
    # Pinky ring center = (+0.038, +0.082, -0.020), Index ring center = (-0.015, +0.089, -0.020)
    p_pinky = Vector((0.038, 0.082, -0.020))
    p_index = Vector((-0.015, 0.089, -0.020))
    grip_center = p_pinky.lerp(p_index, 0.50)
    grip_u = (p_index - p_pinky).normalized()       # Pinky -> Index (handle axis)
    grip_w = Vector((0.0, 0.0, 1.0))                # Dorsal (+Z) vs Palmar (-Z)
    grip_v = grip_w.cross(grip_u).normalized()      # Edge forward direction (+knuckles ~+Y)
    grip_w = grip_u.cross(grip_v).normalized()

    # Convert a handle-frame point (s along handle, v forward-knuckle, w dorsal-side) -> Blender coords for export_yup
    def hpt(s: float, v: float, w: float) -> Vector:
        p_gd = grip_center + grip_u * s + grip_v * v + grip_w * w
        return gd_to_bl(p_gd)

    # 1A. Ergonomic Handle with finger-swell oval rings + G10 taper
    bm_h = bmesh.new()
    rings_def = [
        (-0.056, 0.0115, 0.0082),
        (-0.044, 0.0132, 0.0098),
        (-0.026, 0.0118, 0.0102),
        (-0.004, 0.0138, 0.0108),
        (+0.018, 0.0124, 0.0105),
        (+0.038, 0.0142, 0.0108),
        (+0.054, 0.0155, 0.0104),
    ]
    n_seg = 14
    prev_ring = None
    first_ring = None
    last_ring = None
    for s, rv, rw in rings_def:
        ring = []
        for k in range(n_seg):
            ang = 2.0 * math.pi * k / n_seg
            v_off = math.cos(ang) * rv
            w_off = math.sin(ang) * rw
            ring.append(bm_h.verts.new(hpt(s, v_off, w_off)))
        if first_ring is None:
            first_ring = ring
        if prev_ring is not None:
            for k in range(n_seg):
                nk = (k + 1) % n_seg
                bm_h.faces.new((prev_ring[k], prev_ring[nk], ring[nk], ring[k]))
        prev_ring = ring
        last_ring = ring
    bm_h.faces.new(list(reversed(first_ring)))
    bm_h.faces.new(last_ring)
    obj_handle = create_mesh_obj("KnifeHandle", bm_h, m_grip, smooth=True)

    # 1B. Steel Pommel Striker + Brass Torx Hardware Pins
    bm_p = bmesh.new()
    p_ring0 = [bm_p.verts.new(hpt(-0.068, math.cos(a) * 0.0085, math.sin(a) * 0.0068)) for a in (2.0 * math.pi * k / 10 for k in range(10))]
    p_ring1 = [bm_p.verts.new(hpt(-0.055, math.cos(a) * 0.0118, math.sin(a) * 0.0085)) for a in (2.0 * math.pi * k / 10 for k in range(10))]
    for k in range(10):
        nk = (k + 1) % 10
        bm_p.faces.new((p_ring0[k], p_ring0[nk], p_ring1[nk], p_ring1[k]))
    bm_p.faces.new(list(reversed(p_ring0)))
    bm_p.faces.new(p_ring1)
    # Crossguard bolster at s = +0.054 .. +0.064 (protects index knuckle)
    g0 = [bm_p.verts.new(hpt(+0.053, vx, wx)) for vx, wx in ((0.022, -0.011), (0.022, 0.011), (-0.018, 0.011), (-0.018, -0.011))]
    g1 = [bm_p.verts.new(hpt(+0.063, vx, wx)) for vx, wx in ((0.024, -0.010), (0.024, 0.010), (-0.016, 0.010), (-0.016, -0.010))]
    for k in range(4):
        nk = (k + 1) % 4
        bm_p.faces.new((g0[k], g0[nk], g1[nk], g1[k]))
    bm_p.faces.new(list(reversed(g0)))
    bm_p.faces.new(g1)
    obj_guard = create_mesh_obj("KnifeGuard", bm_p, m_guard, smooth=False)

    # Brass scale pins
    bm_pin = bmesh.new()
    for s_pin in (-0.026, +0.022):
        for w_sign in (-1.0, 1.0):
            c = hpt(s_pin, 0.0, w_sign * 0.0107)
            mat_p = Matrix.Translation(c)
            bmesh.ops.create_icosphere(bm_pin, subdivisions=1, radius=0.0022, matrix=mat_p)
    obj_pins = create_mesh_obj("KnifePins", bm_pin, m_brass, smooth=True)

    # 1C. Tactical Tanto / Drop-Point Blade angled +22 deg toward knuckles (+grip_v) for aggressive first-person silhouette
    tilt = math.radians(22.0)
    blade_u = (grip_u * math.cos(tilt) + grip_v * math.sin(tilt)).normalized()
    blade_v = grip_w.cross(blade_u).normalized()  # +edge / -spine
    blade_w = blade_u.cross(blade_v).normalized()
    blade_origin = grip_center + grip_u * 0.061

    def bpt(b_len: float, b_v: float, b_w: float) -> Vector:
        p_gd = blade_origin + blade_u * b_len + blade_v * b_v + blade_w * b_w
        return gd_to_bl(p_gd)

    # Blade cross-section at each station: spine top (-v), bevel shoulder (dark-flat to satin-edge transition), sharp edge (+v)
    # (length, spine_v, bevel_v, edge_v, spine_half_w)
    stations = [
        (0.000, -0.0145, +0.0020, +0.0165, 0.0024),
        (0.014, -0.0145, +0.0010, +0.0155, 0.0024),
        (0.092, -0.0138, -0.0005, +0.0145, 0.0022),
        (0.132, -0.0105, -0.0015, +0.0120, 0.0018),
        (0.158, -0.0030, +0.0015, +0.0060, 0.0011),
        (0.172, +0.0012, +0.0012, +0.0014, 0.0002),
    ]

    # Build Dark Fuller Spine Flats (spine <-> bevel_shoulder)
    bm_flat = bmesh.new()
    prev = None
    for idx, (bl, sv, bv, _ev, hw) in enumerate(stations):
        sec = [
            bm_flat.verts.new(bpt(bl, sv, +hw)),
            bm_flat.verts.new(bpt(bl, sv, -hw)),
            bm_flat.verts.new(bpt(bl, bv, -hw * 0.92)),
            bm_flat.verts.new(bpt(bl, bv, +hw * 0.92)),
        ]
        if idx == 0:
            bm_flat.faces.new(list(reversed(sec)))
        if prev is not None:
            for k in range(4):
                nk = (k + 1) % 4
                bm_flat.faces.new((prev[k], prev[nk], sec[nk], sec[k]))
        prev = sec
    bm_flat.faces.new(prev)
    obj_flat = create_mesh_obj("KnifeFlat", bm_flat, m_dark, smooth=False)

    # Build Bright Satin Hollow-Grind Bevel Edge (bevel_shoulder <-> keen edge)
    bm_edge = bmesh.new()
    prev_e = None
    for idx, (bl, _sv, bv, ev, hw) in enumerate(stations):
        sec = [
            bm_edge.verts.new(bpt(bl, bv, +hw * 0.92)),
            bm_edge.verts.new(bpt(bl, bv, -hw * 0.92)),
            bm_edge.verts.new(bpt(bl, ev, -0.00018)),
            bm_edge.verts.new(bpt(bl, ev, +0.00018)),
        ]
        if idx == 0:
            bm_edge.faces.new(list(reversed(sec)))
        if prev_e is not None:
            for k in range(4):
                nk = (k + 1) % 4
                bm_edge.faces.new((prev_e[k], prev_e[nk], sec[nk], sec[k]))
        prev_e = sec
    bm_edge.faces.new(prev_e)
    obj_edge = create_mesh_obj("KnifeEdge", bm_edge, m_edge, smooth=False)

    knife_obj = join_with_materials("YS_Tactical_Knife", [obj_handle, obj_guard, obj_pins, obj_flat, obj_edge])
    out_path = DEST / "tactical_knife.glb"
    sz = export_objects([knife_obj], out_path)
    return {"glb": str(out_path.relative_to(ROOT)), "bytes": sz, "polys": len(knife_obj.data.polygons)}


# ---------------------------------------------------------------------------
# 2. Rifle Attachments (YS-04 Normalized WeaponView Coordinates)
# ---------------------------------------------------------------------------

def build_box_bm(bm: bmesh.types.BMesh, center_gd: Vector, size_gd: Vector, rot_gd: Euler | None = None):
    mat = Matrix.Translation(gd_to_bl(center_gd))
    if rot_gd is not None:
        # Approximate pitch/yaw/roll in Blender coords via basis transform
        R_gd = rot_gd.to_matrix().to_4x4()
        P = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        mat = mat @ (P @ R_gd @ P.inverted())
    ret = bmesh.ops.create_cube(bm, size=1.0)
    scale_bl = Matrix.Diagonal((size_gd.x, size_gd.z, size_gd.y, 1.0))
    bmesh.ops.transform(bm, matrix=mat @ scale_bl, verts=ret["verts"])


def build_cyl_z_gd(bm: bmesh.types.BMesh, x: float, y: float, z0: float, z1: float, r0: float, r1: float, segs: int = 24, hollow_r: float = 0.0):
    c = gd_to_bl(Vector((x, y, (z0 + z1) * 0.5)))
    length = abs(z1 - z0)
    mat = Matrix.Translation(c) @ Euler((math.radians(90.0), 0.0, 0.0)).to_matrix().to_4x4()
    if hollow_r <= 0.0:
        bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=segs,
            radius1=r0, radius2=r1, depth=length, matrix=mat
        )
    else:
        # Hollow open tube along Godot Z (= Blender -Y)
        z_a, z_b = min(z0, z1), max(z0, z1)
        out_a, out_b, in_a, in_b = [], [], [], []
        for k in range(segs):
            ang = 2.0 * math.pi * k / segs
            ca, sa = math.cos(ang), math.sin(ang)
            out_a.append(bm.verts.new(gd_to_bl(Vector((x + ca * r0, y + sa * r0, z_a)))))
            out_b.append(bm.verts.new(gd_to_bl(Vector((x + ca * r1, y + sa * r1, z_b)))))
            in_a.append(bm.verts.new(gd_to_bl(Vector((x + ca * hollow_r, y + sa * hollow_r, z_a)))))
            in_b.append(bm.verts.new(gd_to_bl(Vector((x + ca * hollow_r, y + sa * hollow_r, z_b)))))
        for k in range(segs):
            nk = (k + 1) % segs
            bm.faces.new((out_a[k], out_a[nk], out_b[nk], out_b[k]))
            bm.faces.new((in_b[k], in_b[nk], in_a[nk], in_a[k]))
            bm.faces.new((out_b[k], out_b[nk], in_b[nk], in_b[k]))
            bm.faces.new((in_a[k], in_a[nk], out_a[nk], out_a[k]))


def build_rifle_attachments() -> dict:
    clear_scene()
    m_dark = make_mat("Mat_AttDark", (0.12, 0.14, 0.15), metallic=0.72, roughness=0.35)
    m_steel = make_mat("Mat_AttSteel", (0.22, 0.25, 0.28), metallic=0.85, roughness=0.28)
    m_grip = make_mat("Mat_AttGrip", (0.16, 0.20, 0.17), metallic=0.05, roughness=0.78)
    m_glass = make_mat("Mat_OpticGlass", (0.28, 0.92, 0.78), metallic=0.05, roughness=0.06, alpha=0.08)

    # --- A. 2x Tactical Prism Scope (att_scope_2x) centered on rail y=0.212, optical axis y=0.234 ---
    bm_sc = bmesh.new()
    build_box_bm(bm_sc, Vector((0.0, 0.210, 0.020)), Vector((0.028, 0.012, 0.078)))        # Picatinny clamp rail mount
    build_box_bm(bm_sc, Vector((0.0, 0.218, 0.020)), Vector((0.020, 0.010, 0.062)))        # Riser saddle
    build_cyl_z_gd(bm_sc, 0.0, 0.234, -0.025, +0.068, 0.0195, 0.0195, segs=24, hollow_r=0.0160)   # Main housing tube
    build_cyl_z_gd(bm_sc, 0.0, 0.234, -0.055, -0.025, 0.0220, 0.0195, segs=24, hollow_r=0.0175)   # Objective bell front
    build_cyl_z_gd(bm_sc, 0.0, 0.234, +0.068, +0.092, 0.0195, 0.0210, segs=24, hollow_r=0.0165)   # Ocular eyepiece
    build_box_bm(bm_sc, Vector((0.0, 0.255, 0.016)), Vector((0.012, 0.008, 0.014)))        # Top elevation turret
    build_box_bm(bm_sc, Vector((0.022, 0.234, 0.016)), Vector((0.008, 0.012, 0.014)))      # Right windage turret
    obj_sc_body = create_mesh_obj("ScopeBody", bm_sc, m_dark, smooth=False)

    bm_gl = bmesh.new()
    build_cyl_z_gd(bm_gl, 0.0, 0.234, -0.044, -0.042, 0.0172, 0.0172, segs=20)
    build_cyl_z_gd(bm_gl, 0.0, 0.234, +0.079, +0.081, 0.0162, 0.0162, segs=20)
    obj_sc_glass = create_mesh_obj("ScopeGlass", bm_gl, m_glass, smooth=True)
    att_scope = join_with_materials("att_scope_2x", [obj_sc_body, obj_sc_glass])

    # --- B. Titanium Fluted Suppressor (att_suppressor) extending barrel y=0.158, z=-0.342..-0.490 ---
    bm_sup = bmesh.new()
    build_cyl_z_gd(bm_sup, 0.0, 0.158, -0.354, -0.336, 0.0145, 0.0155, segs=20)  # QD locking collar
    build_cyl_z_gd(bm_sup, 0.0, 0.158, -0.484, -0.354, 0.0175, 0.0175, segs=22)  # Main baffle tube
    build_cyl_z_gd(bm_sup, 0.0, 0.158, -0.492, -0.484, 0.0160, 0.0175, segs=22, hollow_r=0.0055)  # Front endcap bore
    for ring_z in (-0.378, -0.408, -0.438, -0.468):
        build_cyl_z_gd(bm_sup, 0.0, 0.158, ring_z - 0.004, ring_z + 0.004, 0.0186, 0.0186, segs=22)
    att_suppressor = create_mesh_obj("att_suppressor", bm_sup, m_dark, smooth=True)

    # --- C. Twin-Baffle Tactical Compensator (att_compensator) z=-0.342..-0.402 ---
    bm_comp = bmesh.new()
    build_cyl_z_gd(bm_comp, 0.0, 0.158, -0.354, -0.340, 0.0135, 0.0140, segs=16)
    build_box_bm(bm_comp, Vector((0.0, 0.158, -0.366)), Vector((0.026, 0.022, 0.014)))
    build_box_bm(bm_comp, Vector((0.0, 0.158, -0.386)), Vector((0.025, 0.021, 0.014)))
    build_cyl_z_gd(bm_comp, 0.0, 0.158, -0.404, -0.354, 0.0110, 0.0110, segs=16, hollow_r=0.0052)
    att_compensator = create_mesh_obj("att_compensator", bm_comp, m_steel, smooth=False)

    # --- D. M-LOK Angled Foregrip (att_angled_grip) flush on bottom rail y=0.094..0.132, z=-0.195..-0.105 ---
    bm_ag = bmesh.new()
    build_box_bm(bm_ag, Vector((0.0, 0.128, -0.150)), Vector((0.024, 0.008, 0.092)))  # Rail interface bar
    build_box_bm(bm_ag, Vector((0.0, 0.108, -0.148)), Vector((0.025, 0.026, 0.056)), Euler((math.radians(-26.0), 0.0, 0.0)))
    build_box_bm(bm_ag, Vector((0.0, 0.095, -0.184)), Vector((0.024, 0.018, 0.018)))  # Front handstop lip
    att_grip = create_mesh_obj("att_angled_grip", bm_ag, m_grip, smooth=False)

    out_path = DEST / "rifle_attachments.glb"
    sz = export_objects([att_scope, att_suppressor, att_compensator, att_grip], out_path)
    return {"glb": str(out_path.relative_to(ROOT)), "bytes": sz}


# ---------------------------------------------------------------------------
# 3. Tactical World Pickups (Ammo Crate, Smoke/EMP Canister, Adrenaline Drink)
# ---------------------------------------------------------------------------

def build_tactical_pickups() -> dict:
    clear_scene()
    m_olive = make_mat("Mat_CrateOlive", (0.24, 0.30, 0.21), metallic=0.25, roughness=0.64)
    m_amber = make_mat("Mat_AmmoAmber", (0.86, 0.66, 0.18), metallic=0.35, roughness=0.45)
    m_can_body = make_mat("Mat_EmpBody", (0.16, 0.20, 0.23), metallic=0.65, roughness=0.42)
    m_emp_glow = make_mat("Mat_EmpCyan", (0.20, 0.85, 0.95), metallic=0.1, roughness=0.3, emission_srgb=(0.20, 0.88, 1.0), emission_strength=1.4)
    m_can_lime = make_mat("Mat_EnergyLime", (0.18, 0.72, 0.42), metallic=0.45, roughness=0.32)
    m_alu = make_mat("Mat_AluCap", (0.78, 0.82, 0.85), metallic=0.90, roughness=0.25)

    # A. 5.56mm Ammo Crate (y in 0..0.22m, width 0.34m, depth 0.20m)
    bm_a0 = bmesh.new()
    build_box_bm(bm_a0, Vector((0.0, 0.085, 0.0)), Vector((0.32, 0.17, 0.19)))
    build_box_bm(bm_a0, Vector((0.0, 0.182, 0.0)), Vector((0.34, 0.032, 0.21)))   # Lid overhang
    build_box_bm(bm_a0, Vector((0.0, 0.208, 0.0)), Vector((0.12, 0.018, 0.026)))  # Carry handle
    obj_a0 = create_mesh_obj("AmmoBoxBody", bm_a0, m_olive)
    bm_a1 = bmesh.new()
    build_box_bm(bm_a1, Vector((0.0, 0.095, 0.0)), Vector((0.325, 0.034, 0.195)))  # Hazard stencil band
    build_box_bm(bm_a1, Vector((-0.165, 0.13, 0.0)), Vector((0.018, 0.045, 0.036)))  # Latch
    obj_a1 = create_mesh_obj("AmmoBoxBand", bm_a1, m_amber)
    pickup_ammo = join_with_materials("pickup_ammo_crate", [obj_a0, obj_a1])

    # B. M18 Smoke / EMP Grenade Canister (y in 0..0.19m)
    bm_e0 = bmesh.new()
    bmesh.ops.create_cone(
        bm_e0, cap_ends=True, segments=18, radius1=0.052, radius2=0.052, depth=0.16,
        matrix=Matrix.Translation(gd_to_bl(Vector((0.0, 0.08, 0.0))))
    )
    build_box_bm(bm_e0, Vector((0.0, 0.172, 0.0)), Vector((0.030, 0.024, 0.030)))   # Fuse head
    build_box_bm(bm_e0, Vector((0.042, 0.115, 0.0)), Vector((0.014, 0.110, 0.018))) # Spoon lever
    obj_e0 = create_mesh_obj("EmpBody", bm_e0, m_can_body, smooth=True)
    bm_e1 = bmesh.new()
    bmesh.ops.create_cone(
        bm_e1, cap_ends=True, segments=18, radius1=0.0545, radius2=0.0545, depth=0.036,
        matrix=Matrix.Translation(gd_to_bl(Vector((0.0, 0.112, 0.0))))
    )
    obj_e1 = create_mesh_obj("EmpBand", bm_e1, m_emp_glow, smooth=True)
    pickup_emp = join_with_materials("pickup_smoke_emp", [obj_e0, obj_e1])

    # C. Combat Energy Adrenaline Drink Can (y in 0..0.16m)
    bm_d0 = bmesh.new()
    bmesh.ops.create_cone(
        bm_d0, cap_ends=True, segments=18, radius1=0.044, radius2=0.044, depth=0.135,
        matrix=Matrix.Translation(gd_to_bl(Vector((0.0, 0.075, 0.0))))
    )
    obj_d0 = create_mesh_obj("DrinkBody", bm_d0, m_can_lime, smooth=True)
    bm_d1 = bmesh.new()
    bmesh.ops.create_cone(
        bm_d1, cap_ends=True, segments=18, radius1=0.040, radius2=0.044, depth=0.016,
        matrix=Matrix.Translation(gd_to_bl(Vector((0.0, 0.148, 0.0))))
    )
    bmesh.ops.create_cone(
        bm_d1, cap_ends=True, segments=18, radius1=0.044, radius2=0.040, depth=0.014,
        matrix=Matrix.Translation(gd_to_bl(Vector((0.0, 0.007, 0.0))))
    )
    obj_d1 = create_mesh_obj("DrinkCap", bm_d1, m_alu, smooth=True)
    pickup_drink = join_with_materials("pickup_energy_drink", [obj_d0, obj_d1])

    out_path = DEST / "tactical_pickups.glb"
    sz = export_objects([pickup_ammo, pickup_emp, pickup_drink], out_path)
    return {"glb": str(out_path.relative_to(ROOT)), "bytes": sz}


def main():
    knife_info = build_tactical_knife()
    att_info = build_rifle_attachments()
    pick_info = build_tactical_pickups()
    report = {"tactical_knife": knife_info, "rifle_attachments": att_info, "tactical_pickups": pick_info}
    out_json = ROOT / "docs" / "slice-v053-assets-build.json"
    out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("V053_ASSETS_BUILT", json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
