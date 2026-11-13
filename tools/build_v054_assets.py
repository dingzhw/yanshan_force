"""Build v0.5.4 CC0 3D parkour cargo containers, intel terminals, recon radio, airdrop beacon & cave lantern in Blender 4.5.

Generated assets (exported into game/assets/slice/parkour_intel_assets.glb):
- prop_cargo_container  (4.20m x 1.14m x 2.00m corrugated olive ISO crate-container for Parkour Route A)
- prop_intel_board      (Field tripod intel clipboard with glowing cyan tactical map display)
- prop_recon_radio      (Field reconnaissance transceiver tripod with dish reflector & telemetry screen)
- prop_airdrop_beacon   (Armored satellite airdrop uplink beacon with solar wings & amber beacon strobe)
- prop_cave_lantern     (Expedition iron-cage warm amber cave lantern)

Run headless:
  blender.exe --background --factory-startup --python tools/build_v054_assets.py
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


def add_box(
    bm: bmesh.types.BMesh,
    center_gd: tuple[float, float, float],
    size_gd: tuple[float, float, float],
    rot_gd: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> None:
    c = gd_to_bl(Vector(center_gd))
    rot = Euler((rot_gd[0], -rot_gd[2], rot_gd[1]), "XYZ").to_matrix().to_4x4()
    mat = Matrix.Translation(c) @ rot @ Matrix.Diagonal((size_gd[0], size_gd[2], size_gd[1], 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat)


def add_cyl(
    bm: bmesh.types.BMesh,
    p0_gd: tuple[float, float, float],
    p1_gd: tuple[float, float, float],
    r0: float,
    r1: float,
    segs: int = 12,
) -> None:
    a = gd_to_bl(Vector(p0_gd))
    b = gd_to_bl(Vector(p1_gd))
    vec = b - a
    length = vec.length
    if length < 1e-6:
        return
    mid = (a + b) * 0.5
    q = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(mid) @ q
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=r0,
        radius2=r1,
        depth=length,
        matrix=mat,
    )


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


def build_cargo_container() -> bpy.types.Object:
    m_olive = make_mat("Mat_ContainerOlive", (0.21, 0.28, 0.21), metallic=0.35, roughness=0.68)
    m_steel = make_mat("Mat_ContainerFrame", (0.14, 0.17, 0.18), metallic=0.72, roughness=0.42)
    m_gold = make_mat("Mat_ContainerStencil", (0.82, 0.66, 0.26), metallic=0.25, roughness=0.52)

    parts = []
    # Main ISO container hull: 4.10 x 1.04 x 1.92 resting on steel bottom skids -> top deck at y = 1.14m
    bm_hull = bmesh.new()
    add_box(bm_hull, (0.0, 0.59, 0.0), (4.06, 1.04, 1.88))
    # Corrugated vertical side ribs
    for ix in range(-9, 10):
        rx = ix * 0.20
        add_box(bm_hull, (rx, 0.59, 0.96), (0.09, 0.94, 0.06))
        add_box(bm_hull, (rx, 0.59, -0.96), (0.09, 0.94, 0.06))
    # Top roof tread plate ribs slightly recessed inside 1.14 cap
    for rz in (-0.62, 0.0, 0.62):
        add_box(bm_hull, (0.0, 1.125, rz), (3.92, 0.03, 0.42))
    parts.append(create_mesh_obj("ContainerHull", bm_hull, m_olive))

    # Structural corner columns, top rails & bottom skids (exact 1.14m top rail height)
    bm_fr = bmesh.new()
    for sx in (-2.04, 2.04):
        for sz in (-0.95, 0.95):
            add_box(bm_fr, (sx, 0.57, sz), (0.12, 1.14, 0.12))
    for sz in (-0.95, 0.95):
        add_box(bm_fr, (0.0, 0.06, sz), (4.20, 0.12, 0.10))
        add_box(bm_fr, (0.0, 1.09, sz), (4.20, 0.10, 0.10))
    for sx in (-2.04, 2.04):
        add_box(bm_fr, (sx, 0.06, 0.0), (0.12, 0.12, 2.00))
        add_box(bm_fr, (sx, 1.09, 0.0), (0.12, 0.10, 2.00))
    # End cargo door lock bars on +X end
    for dz in (-0.35, 0.35):
        add_cyl(bm_fr, (2.09, 0.18, dz), (2.09, 0.98, dz), 0.022, 0.022, segs=8)
    parts.append(create_mesh_obj("ContainerFrame", bm_fr, m_steel))

    # Yellow-gold tactical stencil bands on corners & side placard
    bm_st = bmesh.new()
    for sz in (-0.97, 0.97):
        add_box(bm_st, (-1.35, 0.88, sz), (0.72, 0.11, 0.025))
        add_box(bm_st, (1.50, 0.88, sz), (0.45, 0.11, 0.025))
    parts.append(create_mesh_obj("ContainerStencil", bm_st, m_gold))

    return join_with_materials("prop_cargo_container", parts)


def build_intel_board() -> bpy.types.Object:
    m_steel = make_mat("Mat_IntelSteel", (0.18, 0.21, 0.23), metallic=0.78, roughness=0.38)
    m_olive = make_mat("Mat_IntelOlive", (0.24, 0.30, 0.22), metallic=0.25, roughness=0.65)
    m_paper = make_mat("Mat_IntelPaper", (0.86, 0.84, 0.72), metallic=0.0, roughness=0.85)
    m_cyan = make_mat("Mat_IntelCyan", (0.28, 0.90, 0.78), roughness=0.2, emission_srgb=(0.30, 0.95, 0.82), emission_strength=2.2)
    m_gold = make_mat("Mat_IntelGold", (0.88, 0.72, 0.28), metallic=0.7, roughness=0.32)

    parts = []
    # Compact tactical field tripod + hub
    bm_st = bmesh.new()
    for k in range(3):
        ang = math.radians(k * 120.0 + 30.0)
        add_cyl(bm_st, (math.cos(ang) * 0.32, 0.0, math.sin(ang) * 0.32), (0.0, 0.82, 0.0), 0.024, 0.018, segs=8)
    add_cyl(bm_st, (0.0, 0.78, 0.0), (0.0, 0.98, 0.0), 0.042, 0.036, segs=12)
    # Slim whip antenna on back corner
    add_cyl(bm_st, (0.24, 0.98, -0.18), (0.24, 1.56, -0.22), 0.014, 0.004, segs=8)
    parts.append(create_mesh_obj("IntelTripod", bm_st, m_steel, smooth=True))

    # Tilted armored case & table tray
    bm_ol = bmesh.new()
    add_box(bm_ol, (0.0, 1.02, 0.0), (0.68, 0.07, 0.48), (-0.42, 0.0, 0.0))
    add_box(bm_ol, (0.0, 1.05, -0.02), (0.60, 0.04, 0.40), (-0.42, 0.0, 0.0))
    parts.append(create_mesh_obj("IntelCase", bm_ol, m_olive))

    # Paper field note + glowing cyan scanner strip
    bm_pa = bmesh.new()
    add_box(bm_pa, (-0.11, 1.07, 0.03), (0.28, 0.015, 0.30), (-0.42, 0.04, 0.0))
    parts.append(create_mesh_obj("IntelPaper", bm_pa, m_paper))

    bm_cy = bmesh.new()
    add_box(bm_cy, (0.14, 1.08, 0.02), (0.20, 0.016, 0.28), (-0.42, 0.0, 0.0))
    add_cyl(bm_cy, (0.24, 1.56, -0.22), (0.24, 1.60, -0.22), 0.012, 0.012, segs=8)
    parts.append(create_mesh_obj("IntelGlow", bm_cy, m_cyan, smooth=True))

    bm_gd = bmesh.new()
    add_box(bm_gd, (-0.11, 1.09, -0.10), (0.14, 0.02, 0.04), (-0.42, 0.04, 0.0))
    parts.append(create_mesh_obj("IntelClip", bm_gd, m_gold))

    return join_with_materials("prop_intel_board", parts)


def build_recon_radio() -> bpy.types.Object:
    m_steel = make_mat("Mat_RadioSteel", (0.15, 0.18, 0.20), metallic=0.80, roughness=0.36)
    m_olive = make_mat("Mat_RadioOlive", (0.22, 0.29, 0.23), metallic=0.35, roughness=0.58)
    m_cyan = make_mat("Mat_RadioCyan", (0.26, 0.92, 0.86), roughness=0.18, emission_srgb=(0.26, 0.95, 0.88), emission_strength=2.4)
    m_gold = make_mat("Mat_RadioGold", (0.90, 0.72, 0.28), metallic=0.75, roughness=0.28)

    parts = []
    bm_st = bmesh.new()
    for k in range(3):
        ang = math.radians(k * 120.0)
        add_cyl(bm_st, (math.cos(ang) * 0.42, 0.0, math.sin(ang) * 0.42), (0.0, 0.72, 0.0), 0.032, 0.024, segs=10)
    add_cyl(bm_st, (0.0, 0.65, 0.0), (0.0, 1.48, 0.0), 0.045, 0.032, segs=12)
    # Dish ring & feed horn support
    add_cyl(bm_st, (0.0, 1.56, -0.05), (0.0, 1.66, 0.28), 0.36, 0.08, segs=16)
    add_cyl(bm_st, (0.0, 1.62, 0.14), (0.0, 1.72, 0.44), 0.015, 0.012, segs=8)
    parts.append(create_mesh_obj("RadioFrame", bm_st, m_steel, smooth=True))

    bm_ol = bmesh.new()
    add_box(bm_ol, (0.0, 0.92, 0.04), (0.64, 0.40, 0.38))
    add_box(bm_ol, (0.0, 1.15, 0.04), (0.58, 0.06, 0.34))
    parts.append(create_mesh_obj("RadioChassis", bm_ol, m_olive))

    bm_cy = bmesh.new()
    # Glowing waveform monitor & beacon ring
    add_box(bm_cy, (-0.10, 0.96, 0.24), (0.30, 0.20, 0.02))
    add_cyl(bm_cy, (0.0, 1.70, 0.42), (0.0, 1.76, 0.47), 0.025, 0.018, segs=10)
    parts.append(create_mesh_obj("RadioScreen", bm_cy, m_cyan, smooth=True))

    bm_gd = bmesh.new()
    for ky in (0.88, 0.98, 1.06):
        add_box(bm_gd, (0.16, ky, 0.24), (0.12, 0.05, 0.02))
    parts.append(create_mesh_obj("RadioDial", bm_gd, m_gold))

    return join_with_materials("prop_recon_radio", parts)


def build_airdrop_beacon() -> bpy.types.Object:
    m_dark = make_mat("Mat_BeaconDark", (0.14, 0.16, 0.19), metallic=0.82, roughness=0.35)
    m_solar = make_mat("Mat_BeaconSolar", (0.10, 0.18, 0.34), metallic=0.55, roughness=0.22)
    m_gold = make_mat("Mat_BeaconGold", (0.86, 0.68, 0.24), metallic=0.82, roughness=0.28)
    m_amber = make_mat("Mat_BeaconAmber", (1.0, 0.56, 0.16), roughness=0.18, emission_srgb=(1.0, 0.58, 0.14), emission_strength=3.0)

    parts = []
    bm_dk = bmesh.new()
    add_cyl(bm_dk, (0.0, 0.0, 0.0), (0.0, 0.14, 0.0), 0.42, 0.32, segs=8)
    add_box(bm_dk, (0.0, 0.54, 0.0), (0.38, 0.78, 0.38))
    add_cyl(bm_dk, (0.0, 0.94, 0.0), (0.0, 1.48, 0.0), 0.08, 0.06, segs=10)
    parts.append(create_mesh_obj("BeaconBody", bm_dk, m_dark, smooth=True))

    bm_sol = bmesh.new()
    for sx in (-0.54, 0.54):
        add_box(bm_sol, (sx, 0.86, 0.0), (0.64, 0.04, 0.40), (0.28, 0.0, -0.35 if sx > 0 else 0.35))
    parts.append(create_mesh_obj("BeaconSolar", bm_sol, m_solar))

    bm_gd = bmesh.new()
    add_box(bm_gd, (0.0, 0.94, 0.0), (0.44, 0.08, 0.44))
    add_cyl(bm_gd, (0.0, 1.44, 0.0), (0.0, 1.52, 0.0), 0.16, 0.16, segs=12)
    parts.append(create_mesh_obj("BeaconTrim", bm_gd, m_gold, smooth=True))

    bm_am = bmesh.new()
    add_cyl(bm_am, (0.0, 1.52, 0.0), (0.0, 1.72, 0.0), 0.11, 0.08, segs=12)
    add_box(bm_am, (0.0, 0.56, 0.20), (0.22, 0.28, 0.02))
    parts.append(create_mesh_obj("BeaconStrobe", bm_am, m_amber, smooth=True))

    return join_with_materials("prop_airdrop_beacon", parts)


def build_cave_lantern() -> bpy.types.Object:
    m_iron = make_mat("Mat_LanternIron", (0.16, 0.18, 0.19), metallic=0.82, roughness=0.44)
    m_glow = make_mat("Mat_LanternGlow", (1.0, 0.78, 0.36), roughness=0.2, emission_srgb=(1.0, 0.74, 0.30), emission_strength=3.2)

    parts = []
    bm_ir = bmesh.new()
    add_cyl(bm_ir, (0.0, 0.0, 0.0), (0.0, 0.08, 0.0), 0.17, 0.15, segs=8)
    add_cyl(bm_ir, (0.0, 0.36, 0.0), (0.0, 0.44, 0.0), 0.18, 0.09, segs=8)
    add_cyl(bm_ir, (0.0, 0.44, 0.0), (0.0, 0.52, 0.0), 0.05, 0.05, segs=8)
    for k in range(4):
        ang = math.radians(k * 90.0 + 45.0)
        add_cyl(bm_ir, (math.cos(ang) * 0.14, 0.08, math.sin(ang) * 0.14), (math.cos(ang) * 0.14, 0.36, math.sin(ang) * 0.14), 0.012, 0.012, segs=6)
    parts.append(create_mesh_obj("LanternCage", bm_ir, m_iron, smooth=True))

    bm_gl = bmesh.new()
    add_cyl(bm_gl, (0.0, 0.09, 0.0), (0.0, 0.35, 0.0), 0.10, 0.11, segs=8)
    parts.append(create_mesh_obj("LanternCore", bm_gl, m_glow, smooth=True))

    return join_with_materials("prop_cave_lantern", parts)


def main():
    clear_scene()
    objs = [
        build_cargo_container(),
        build_intel_board(),
        build_recon_radio(),
        build_airdrop_beacon(),
        build_cave_lantern(),
    ]
    out_path = DEST / "parkour_intel_assets.glb"
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
    (ROOT / "docs" / "slice-v054-assets-build.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    print("BUILT_V054_ASSETS", json.dumps(meta, ensure_ascii=False))


if __name__ == "__main__":
    main()
