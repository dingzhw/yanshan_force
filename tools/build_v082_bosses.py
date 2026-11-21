"""Generate museum-grade multi-material PBR Boss models for v0.8.2 in Blender 4.5:
- cave_warden       ("古洞循音石卫" — Yanxia Ancient Cave blind acoustic stone guardian with cyan sonar ribcage & sensor antlers)
- skyfall_overlord  ("雾隐机关王·玄铁词尊" — Confidential Operation giant 3.9m obsidian-iron & gilded mechanical overlord)

Exports to: game/assets/slice/v082_bosses.glb
"""
from pathlib import Path
import math
import random
import bpy
import bmesh
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game/assets/slice/v082_bosses.glb"


def gd_to_bl(v: Vector) -> Vector:
    return Vector((v.x, -v.z, v.y))


def _srgb_to_lin(c: tuple[float, float, float], alpha: float = 1.0):
    return (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, alpha)


def make_mat(name: str, srgb: tuple[float, float, float], metallic=0.1, roughness=0.72, em_srgb=None, em_str=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    bsdf.inputs["Base Color"].default_value = _srgb_to_lin(srgb)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if em_srgb is not None and em_str > 0.0:
        bsdf.inputs["Emission Color"].default_value = _srgb_to_lin(em_srgb)
        bsdf.inputs["Emission Strength"].default_value = em_str
    return mat


def add_box(bm: bmesh.types.BMesh, center_gd, size_gd, rot_deg=(0.0, 0.0, 0.0)):
    sx, sy, sz = size_gd
    rx, ry, rz = (math.radians(a) for a in rot_deg)
    m_rot = Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
    m_scale = Matrix.Diagonal((sx, sz, sy, 1.0))
    m_loc = Matrix.Translation(gd_to_bl(Vector(center_gd)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m_loc @ m_rot @ m_scale)


def add_cyl(bm: bmesh.types.BMesh, p0_gd, p1_gd, r0: float, r1: float, segs: int = 12):
    a = gd_to_bl(Vector(p0_gd))
    b = gd_to_bl(Vector(p1_gd))
    delta = b - a
    length = delta.length
    if length < 1e-4:
        return
    rot = Vector((0, 0, 1)).rotation_difference(delta.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation((a + b) * 0.5) @ rot
    bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=length, matrix=mat
    )


def add_rock_lobe(bm: bmesh.types.BMesh, center_gd, radii_gd, seed: int, subdiv: int = 2, amp: float = 0.16):
    rng = random.Random(seed)
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    verts = res["verts"]
    rx, ry, rz = radii_gd
    c = gd_to_bl(Vector(center_gd))
    for v in verts:
        n = 1.0 + rng.uniform(-amp, amp) + 0.08 * math.sin(v.co.x * 5.0 + seed) * math.cos(v.co.z * 4.5)
        v.co = Vector((v.co.x * rx * n, v.co.y * rz * n, v.co.z * ry * n)) + c


def part_obj(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = smooth
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def join_parts(final_name: str, objs: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    out = bpy.context.view_layer.objects.active
    out.name = final_name
    out.data.name = final_name + "_Mesh"
    return out


def build_cave_warden() -> bpy.types.Object:
    """古洞循音石卫 (~2.45m tall): Ancient craggy karst guardian with glowing cyan acoustic ribcage & sonar antlers."""
    m_stone = make_mat("Mat_WardenStone", (0.16, 0.21, 0.24), metallic=0.14, roughness=0.84)
    m_slate = make_mat("Mat_WardenSlate", (0.09, 0.14, 0.18), metallic=0.22, roughness=0.72)
    m_moss = make_mat("Mat_WardenMoss", (0.18, 0.34, 0.25), metallic=0.05, roughness=0.88)
    m_sonar = make_mat("Mat_WardenSonar", (0.28, 0.94, 0.98), metallic=0.15, roughness=0.18, em_srgb=(0.24, 0.92, 1.0), em_str=3.4)
    m_bone = make_mat("Mat_WardenRib", (0.58, 0.68, 0.66), metallic=0.12, roughness=0.58)

    bm_stone, bm_slate, bm_moss, bm_sonar, bm_bone = (bmesh.new() for _ in range(5))

    # Heavy rooted legs & knee plates (y = 0.0 .. 1.05)
    for sx in (-1.0, 1.0):
        add_rock_lobe(bm_stone, (sx * 0.42, 0.14, 0.04), (0.24, 0.16, 0.30), 101 + int(sx + 2))
        add_cyl(bm_slate, (sx * 0.40, 0.16, 0.0), (sx * 0.42, 0.62, 0.02), 0.18, 0.20, 10)
        add_rock_lobe(bm_stone, (sx * 0.42, 0.58, 0.12), (0.20, 0.18, 0.20), 111 + int(sx + 2))
        add_cyl(bm_stone, (sx * 0.42, 0.60, 0.0), (sx * 0.36, 1.05, -0.02), 0.21, 0.24, 10)

    # Broad hunched karst pelvis & back carapace
    add_rock_lobe(bm_slate, (0.0, 1.08, -0.04), (0.56, 0.26, 0.38), 120)
    add_rock_lobe(bm_stone, (0.0, 1.58, -0.22), (0.76, 0.56, 0.44), 121, subdiv=2, amp=0.18)
    add_rock_lobe(bm_moss, (0.0, 2.02, -0.28), (0.62, 0.22, 0.34), 122, subdiv=1, amp=0.16)

    # Hollow glowing cyan acoustic heart + 3 curved ribcage arcs framing the chest!
    add_rock_lobe(bm_sonar, (0.0, 1.56, 0.16), (0.26, 0.30, 0.18), 130, subdiv=2, amp=0.08)
    for r_i, ry in enumerate([1.36, 1.56, 1.76]):
        for sx in (-1.0, 1.0):
            add_cyl(bm_bone, (sx * 0.62, ry + 0.05, -0.06), (sx * 0.42, ry, 0.24), 0.065, 0.055, 8)
            add_cyl(bm_bone, (sx * 0.42, ry, 0.24), (sx * 0.16, ry - 0.03, 0.30), 0.055, 0.040, 8)

    # Massive stone shoulders & gorilla-like long stone forearms reaching down to y = 0.68
    for sx in (-1.0, 1.0):
        add_rock_lobe(bm_stone, (sx * 0.84, 1.88, -0.04), (0.34, 0.32, 0.32), 140 + int(sx + 2))
        add_rock_lobe(bm_moss, (sx * 0.88, 2.12, -0.06), (0.24, 0.12, 0.24), 145 + int(sx + 2), subdiv=1)
        add_cyl(bm_slate, (sx * 0.86, 1.76, 0.0), (sx * 0.96, 1.24, 0.14), 0.20, 0.18, 10)
        add_rock_lobe(bm_stone, (sx * 0.98, 0.94, 0.24), (0.24, 0.38, 0.24), 150 + int(sx + 2))
        # Glowing cyan acoustic knuckles
        add_rock_lobe(bm_sonar, (sx * 0.98, 0.68, 0.32), (0.14, 0.10, 0.14), 155 + int(sx + 2), subdiv=1, amp=0.08)

    # Eyeless carved stone head (mouth cavity + twin flared glowing acoustic sensor antlers!)
    add_rock_lobe(bm_stone, (0.0, 2.18, 0.14), (0.34, 0.30, 0.32), 160, subdiv=2, amp=0.12)
    add_box(bm_slate, (0.0, 2.08, 0.38), (0.34, 0.14, 0.10))
    add_box(bm_sonar, (0.0, 2.08, 0.41), (0.24, 0.07, 0.05))
    # Flared acoustic listening antlers (left & right)
    for sx in (-1.0, 1.0):
        add_cyl(bm_slate, (sx * 0.28, 2.24, 0.10), (sx * 0.62, 2.48, 0.04), 0.075, 0.055, 8)
        add_cyl(bm_sonar, (sx * 0.62, 2.48, 0.04), (sx * 0.78, 2.74, 0.08), 0.055, 0.025, 8)
        add_cyl(bm_sonar, (sx * 0.48, 2.38, 0.06), (sx * 0.56, 2.68, 0.14), 0.045, 0.020, 8)

    return join_parts("cave_warden", [
        part_obj("WardenStone", bm_stone, m_stone, smooth=True),
        part_obj("WardenSlate", bm_slate, m_slate, smooth=True),
        part_obj("WardenMoss", bm_moss, m_moss, smooth=True),
        part_obj("WardenSonar", bm_sonar, m_sonar, smooth=True),
        part_obj("WardenRib", bm_bone, m_bone, smooth=True),
    ])


def build_skyfall_overlord() -> bpy.types.Object:
    """雾隐机关王·玄铁词尊 (~3.9m giant Confidential Operation Skyfall Boss): Obsidian iron + burnished gold + furnace core."""
    m_iron = make_mat("Mat_OverlordIron", (0.12, 0.14, 0.17), metallic=0.86, roughness=0.32)
    m_armor = make_mat("Mat_OverlordArmor", (0.20, 0.23, 0.27), metallic=0.78, roughness=0.38)
    m_gold = make_mat("Mat_OverlordGold", (0.86, 0.66, 0.24), metallic=0.92, roughness=0.24)
    m_core = make_mat("Mat_OverlordCore", (1.0, 0.36, 0.14), metallic=0.18, roughness=0.20, em_srgb=(1.0, 0.42, 0.12), em_str=4.0)
    m_crimson = make_mat("Mat_OverlordVisor", (1.0, 0.16, 0.22), metallic=0.10, roughness=0.16, em_srgb=(1.0, 0.18, 0.24), em_str=4.5)

    bm_iron, bm_armor, bm_gold, bm_core, bm_crim = (bmesh.new() for _ in range(5))

    # Towering armored piston legs (y = 0.0 .. 1.65)
    for sx in (-1.0, 1.0):
        add_box(bm_iron, (sx * 0.66, 0.14, 0.08), (0.58, 0.28, 0.74))
        add_box(bm_gold, (sx * 0.66, 0.18, 0.42), (0.44, 0.18, 0.14))
        add_cyl(bm_armor, (sx * 0.66, 0.24, 0.0), (sx * 0.64, 0.96, 0.04), 0.26, 0.30, 10)
        add_box(bm_gold, (sx * 0.64, 0.94, 0.28), (0.38, 0.34, 0.16))  # Gilded knee shield
        add_cyl(bm_iron, (sx * 0.64, 0.96, 0.0), (sx * 0.58, 1.66, 0.0), 0.30, 0.34, 10)

    # Heavy armored pelvis & massive faceted iron cuirass (y = 1.65 .. 3.10)
    add_box(bm_iron, (0.0, 1.72, 0.0), (1.52, 0.42, 0.88))
    add_box(bm_gold, (0.0, 1.72, 0.46), (0.52, 0.32, 0.14))
    add_box(bm_armor, (0.0, 2.42, 0.0), (1.88, 1.12, 1.06))
    add_box(bm_gold, (0.0, 2.94, 0.02), (1.96, 0.14, 1.12))  # Gilded collar trim
    add_box(bm_gold, (0.0, 1.92, 0.02), (1.82, 0.12, 1.04))

    # Blazing furnace reactor core embedded in chest
    add_cyl(bm_iron, (0.0, 2.42, 0.48), (0.0, 2.42, 0.62), 0.40, 0.36, 12)
    add_rock_lobe(bm_core, (0.0, 2.42, 0.58), (0.28, 0.28, 0.14), 201, subdiv=2, amp=0.05)

    # Twin skyfall drop thrusters on back
    for sx in (-1.0, 1.0):
        add_cyl(bm_iron, (sx * 0.54, 2.10, -0.66), (sx * 0.58, 3.04, -0.62), 0.24, 0.18, 10)
        add_cyl(bm_core, (sx * 0.54, 1.92, -0.68), (sx * 0.54, 2.12, -0.66), 0.20, 0.22, 10)

    # Massive layered iron pauldrons (Left & Right Shoulder shield mounts) & articulated heavy arms
    for sx in (-1.0, 1.0):
        add_box(bm_armor, (sx * 1.28, 2.86, 0.02), (0.76, 0.64, 0.92), (0.0, 0.0, -sx * 14.0))
        add_box(bm_gold, (sx * 1.38, 3.16, 0.02), (0.78, 0.12, 0.96), (0.0, 0.0, -sx * 14.0))
        add_cyl(bm_iron, (sx * 1.32, 2.58, 0.04), (sx * 1.44, 1.88, 0.16), 0.24, 0.22, 10)
        add_box(bm_armor, (sx * 1.48, 1.60, 0.26), (0.48, 0.72, 0.52))
        add_box(bm_gold, (sx * 1.48, 1.30, 0.32), (0.50, 0.14, 0.54))
        add_cyl(bm_core, (sx * 1.48, 1.24, 0.50), (sx * 1.48, 1.24, 0.64), 0.12, 0.09, 10)

    # Horned Jiangnan warlord iron helm + glowing crimson visor & gold crest (y = 3.10 .. 3.92)
    add_box(bm_iron, (0.0, 3.36, 0.04), (0.68, 0.62, 0.68))
    add_box(bm_crim, (0.0, 3.38, 0.39), (0.54, 0.16, 0.06))
    add_box(bm_gold, (0.0, 3.72, 0.08), (0.14, 0.38, 0.56))  # Central crest
    for sx in (-1.0, 1.0):
        add_cyl(bm_gold, (sx * 0.28, 3.58, 0.12), (sx * 0.72, 3.96, 0.24), 0.08, 0.02, 8)

    return join_parts("skyfall_overlord", [
        part_obj("OverlordIron", bm_iron, m_iron, smooth=False),
        part_obj("OverlordArmor", bm_armor, m_armor, smooth=False),
        part_obj("OverlordGold", bm_gold, m_gold, smooth=False),
        part_obj("OverlordCore", bm_core, m_core, smooth=True),
        part_obj("OverlordVisor", bm_crim, m_crimson, smooth=False),
    ])


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    w = build_cave_warden()
    o = build_skyfall_overlord()
    for obj in (w, o):
        verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
        xs = [v.x for v in verts]
        ys = [v.y for v in verts]
        zs = [v.z for v in verts]
        print(f"Built {obj.name}: {len(obj.data.polygons)} polys, gd_x=[{min(xs):.2f},{max(xs):.2f}] gd_y=[{min(zs):.2f},{max(zs):.2f}] gd_z=[{-max(ys):.2f},{-min(ys):.2f}]")

    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
    )
    print(f"Exported v0.8.2 Boss models -> {OUT_GLB} ({OUT_GLB.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
