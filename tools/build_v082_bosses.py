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
MIRROR_GLB = ROOT / "game/assets/slice/v086_mirror_yanshan.glb"


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
    """古洞循音石卫 (~2.55m tall, v0.8.4 articulated multi-part rig):
    Hierarchy exported inside v082_bosses.glb:
      - cave_warden (Empty root at origin)
        ├── warden_body     (legs, pelvis, torso, moss carapace, 3 curved ribcage arcs, recessed core socket)
        ├── head_crest      (pivoted at neck gd(0, 2.08, 0.08): eyeless carved stone head + twin sonar antlers)
        ├── arm_left_pivot  (pivoted at shoulder gd(-0.84, 1.84, -0.02): pauldron + forearm + heavy beveled青石臂盾)
        └── arm_right_pivot (pivoted at shoulder gd(+0.84, 1.84, -0.02): pauldron + forearm + heavy beveled青石臂盾)
    """
    m_stone = make_mat("Mat_WardenStone", (0.18, 0.24, 0.27), metallic=0.14, roughness=0.82)
    m_slate = make_mat("Mat_WardenSlate", (0.10, 0.15, 0.20), metallic=0.24, roughness=0.68)
    m_moss = make_mat("Mat_WardenMoss", (0.19, 0.37, 0.26), metallic=0.05, roughness=0.88)
    m_sonar = make_mat("Mat_WardenSonar", (0.28, 0.94, 0.98), metallic=0.15, roughness=0.18, em_srgb=(0.24, 0.92, 1.0), em_str=3.2)
    m_bone = make_mat("Mat_WardenRib", (0.60, 0.70, 0.67), metallic=0.12, roughness=0.56)
    m_shield = make_mat("Mat_WardenShieldStone", (0.24, 0.31, 0.34), metallic=0.26, roughness=0.64)

    root_empty = bpy.data.objects.new("cave_warden", None)
    root_empty.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root_empty)

    def _join_under_pivot(part_name: str, pivot_gd: tuple[float, float, float], mesh_parts: list[bpy.types.Object]) -> bpy.types.Object:
        non_empty = [o for o in mesh_parts if len(o.data.vertices) > 0]
        for o in mesh_parts:
            if o not in non_empty:
                bpy.data.objects.remove(o, do_unlink=True)
        joined = join_parts(part_name, non_empty)
        piv_bl = gd_to_bl(Vector(pivot_gd))
        # Shift vertex coordinates into local pivot space, then place object origin at pivot!
        for v in joined.data.vertices:
            v.co -= piv_bl
        joined.data.update()
        joined.location = piv_bl
        joined.parent = root_empty
        return joined

    # ------------------------------------------------------------------
    # 1) warden_body (origin at gd(0, 0, 0))
    # ------------------------------------------------------------------
    bm_stone, bm_slate, bm_moss, bm_sonar, bm_bone = (bmesh.new() for _ in range(5))

    # Heavy rooted legs & knee plates (y = 0.0 .. 1.05)
    for sx in (-1.0, 1.0):
        add_rock_lobe(bm_stone, (sx * 0.42, 0.14, 0.04), (0.25, 0.16, 0.31), 101 + int(sx + 2))
        add_cyl(bm_slate, (sx * 0.40, 0.16, 0.0), (sx * 0.42, 0.62, 0.02), 0.18, 0.20, 10)
        add_rock_lobe(bm_stone, (sx * 0.42, 0.58, 0.13), (0.21, 0.18, 0.21), 111 + int(sx + 2))
        add_cyl(bm_stone, (sx * 0.42, 0.60, 0.0), (sx * 0.36, 1.05, -0.02), 0.21, 0.24, 10)

    # Broad hunched karst pelvis & back carapace
    add_rock_lobe(bm_slate, (0.0, 1.08, -0.04), (0.56, 0.26, 0.38), 120)
    add_rock_lobe(bm_stone, (0.0, 1.58, -0.20), (0.76, 0.56, 0.44), 121, subdiv=2, amp=0.18)
    add_rock_lobe(bm_moss, (0.0, 2.02, -0.26), (0.64, 0.22, 0.34), 122, subdiv=1, amp=0.16)
    # Recessed dark slate socket backing the compact 0.30m chest core (replaces old oversized glowing blob!)
    add_cyl(bm_slate, (0.0, 1.56, 0.08), (0.0, 1.56, 0.24), 0.28, 0.22, 12)
    add_rock_lobe(bm_sonar, (0.0, 1.56, 0.16), (0.11, 0.11, 0.08), 130, subdiv=1, amp=0.05)

    # 3 curved bone-stone ribcage arcs framing the recessed chest core
    for ry in [1.34, 1.56, 1.78]:
        for sx in (-1.0, 1.0):
            add_cyl(bm_bone, (sx * 0.62, ry + 0.05, -0.06), (sx * 0.44, ry, 0.22), 0.068, 0.056, 8)
            add_cyl(bm_bone, (sx * 0.44, ry, 0.22), (sx * 0.21, ry - 0.02, 0.28), 0.056, 0.038, 8)

    _join_under_pivot("warden_body", (0.0, 0.0, 0.0), [
        part_obj("WardenBodyStone", bm_stone, m_stone, smooth=True),
        part_obj("WardenBodySlate", bm_slate, m_slate, smooth=True),
        part_obj("WardenBodyMoss", bm_moss, m_moss, smooth=True),
        part_obj("WardenBodySonar", bm_sonar, m_sonar, smooth=True),
        part_obj("WardenBodyRib", bm_bone, m_bone, smooth=True),
    ])

    # ------------------------------------------------------------------
    # 2) head_crest (pivoted at neck gd(0.0, 2.08, 0.08))
    # ------------------------------------------------------------------
    hb_stone, hb_slate, hb_moss, hb_sonar = (bmesh.new() for _ in range(4))
    add_rock_lobe(hb_stone, (0.0, 2.22, 0.14), (0.34, 0.30, 0.32), 160, subdiv=2, amp=0.12)
    add_rock_lobe(hb_moss, (0.0, 2.46, 0.06), (0.24, 0.10, 0.20), 162, subdiv=1, amp=0.12)
    add_box(hb_slate, (0.0, 2.12, 0.38), (0.34, 0.14, 0.10))
    add_box(hb_sonar, (0.0, 2.12, 0.41), (0.24, 0.06, 0.05))
    # Flared acoustic listening antlers (left & right)
    for sx in (-1.0, 1.0):
        add_cyl(hb_slate, (sx * 0.28, 2.28, 0.10), (sx * 0.62, 2.52, 0.04), 0.075, 0.055, 8)
        add_cyl(hb_sonar, (sx * 0.62, 2.52, 0.04), (sx * 0.80, 2.78, 0.08), 0.055, 0.024, 8)
        add_cyl(hb_sonar, (sx * 0.48, 2.42, 0.06), (sx * 0.58, 2.72, 0.15), 0.045, 0.020, 8)

    _join_under_pivot("head_crest", (0.0, 2.08, 0.08), [
        part_obj("WardenHeadStone", hb_stone, m_stone, smooth=True),
        part_obj("WardenHeadSlate", hb_slate, m_slate, smooth=True),
        part_obj("WardenHeadMoss", hb_moss, m_moss, smooth=True),
        part_obj("WardenHeadSonar", hb_sonar, m_sonar, smooth=True),
    ])

    # ------------------------------------------------------------------
    # 3) arm_left_pivot (-X) & arm_right_pivot (+X) with massive beveled青石臂盾
    # ------------------------------------------------------------------
    for arm_name, sx, seed_off in (("arm_left_pivot", -1.0, 0), ("arm_right_pivot", 1.0, 30)):
        ab_stone, ab_slate, ab_moss, ab_sonar, ab_shield = (bmesh.new() for _ in range(5))
        piv = (sx * 0.84, 1.84, -0.02)

        # Massive layered karst shoulder boulder + mossy top cap
        add_rock_lobe(ab_stone, (sx * 0.86, 1.90, -0.02), (0.34, 0.31, 0.33), 140 + seed_off)
        add_rock_lobe(ab_moss, (sx * 0.89, 2.14, -0.04), (0.24, 0.11, 0.24), 145 + seed_off, subdiv=1)

        # Muscular dark-slate upper arm linking shoulder to forearm shield
        add_cyl(ab_slate, (sx * 0.86, 1.76, 0.02), (sx * 0.94, 1.28, 0.16), 0.20, 0.18, 10)
        add_rock_lobe(ab_stone, (sx * 0.96, 1.24, 0.18), (0.22, 0.20, 0.22), 148 + seed_off)

        # Heavy beveled 青石臂盾 (stone gauntlet shield plate) mounted along forearm!
        # Designed so when both arms fold inward across the chest, the two shields interlock cleanly in front of the 0.30m core!
        add_box(ab_shield, (sx * 0.98, 0.98, 0.32), (0.36, 0.78, 0.24), (8.0, 0.0, sx * 6.0))
        add_box(ab_slate, (sx * 1.02, 0.98, 0.42), (0.26, 0.64, 0.08), (8.0, 0.0, sx * 6.0))
        # Carved horizontal dark-iron/slate reinforcement bands & beveled edge crest
        for band_y in (1.24, 0.98, 0.72):
            add_box(ab_slate, (sx * 0.99, band_y, 0.34), (0.40, 0.08, 0.28), (8.0, 0.0, sx * 6.0))
        # Moss accent on upper shield shoulder & thin glowing cyan acoustic veins on outer shield face
        add_rock_lobe(ab_moss, (sx * 1.04, 1.28, 0.36), (0.18, 0.10, 0.14), 152 + seed_off, subdiv=1)
        add_box(ab_sonar, (sx * 1.03, 0.98, 0.46), (0.06, 0.50, 0.04), (8.0, 0.0, sx * 6.0))
        # Heavy stone fist & glowing acoustic knuckles
        add_rock_lobe(ab_stone, (sx * 0.94, 0.64, 0.30), (0.20, 0.18, 0.22), 154 + seed_off)
        add_rock_lobe(ab_sonar, (sx * 0.94, 0.56, 0.38), (0.13, 0.08, 0.12), 155 + seed_off, subdiv=1, amp=0.08)

        _join_under_pivot(arm_name, piv, [
            part_obj(arm_name + "_Stone", ab_stone, m_stone, smooth=True),
            part_obj(arm_name + "_Slate", ab_slate, m_slate, smooth=False),
            part_obj(arm_name + "_Moss", ab_moss, m_moss, smooth=True),
            part_obj(arm_name + "_Sonar", ab_sonar, m_sonar, smooth=False),
            part_obj(arm_name + "_Shield", ab_shield, m_shield, smooth=False),
        ])

    return root_empty


def build_skyfall_overlord() -> bpy.types.Object:
    """雾隐机关王·玄铁词尊 (~3.95m tall, v0.8.6 articulated 5-part rig):
    Hierarchy exported inside v082_bosses.glb:
      - skyfall_overlord (Empty root at origin)
        ├── overlord_body      (piston legs, pelvis, obsidian cuirass, chest reactor, skyfall thrusters)
        ├── overlord_head      (pivoted at neck gd(0, 3.12, 0.04): horned helm + visor + gold crest)
        ├── overlord_arm_l     (pivoted at shoulder gd(-1.24, 2.86, 0.02): pauldron + arm + obsidian-gold greatblade)
        ├── overlord_arm_r     (pivoted at shoulder gd(+1.24, 2.86, 0.02): pauldron + arm + obsidian-gold greatblade)
        └── overlord_halo_ring (pivoted at back gd(0, 2.88, -0.78): rotating 8-spoke bronze-gold Dharma-wheel halo)
    """
    m_iron = make_mat("Mat_OverlordIron", (0.12, 0.14, 0.17), metallic=0.86, roughness=0.32)
    m_armor = make_mat("Mat_OverlordArmor", (0.20, 0.23, 0.27), metallic=0.78, roughness=0.38)
    m_gold = make_mat("Mat_OverlordGold", (0.86, 0.66, 0.24), metallic=0.92, roughness=0.24)
    m_core = make_mat("Mat_OverlordCore", (1.0, 0.36, 0.14), metallic=0.18, roughness=0.20, em_srgb=(1.0, 0.42, 0.12), em_str=4.0)
    m_crimson = make_mat("Mat_OverlordVisor", (1.0, 0.16, 0.22), metallic=0.10, roughness=0.16, em_srgb=(1.0, 0.18, 0.24), em_str=4.5)

    root_empty = bpy.data.objects.new("skyfall_overlord", None)
    root_empty.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root_empty)

    def _join_under_pivot(part_name: str, pivot_gd: tuple[float, float, float], mesh_parts: list[bpy.types.Object]) -> bpy.types.Object:
        non_empty = [o for o in mesh_parts if len(o.data.vertices) > 0]
        for o in mesh_parts:
            if o not in non_empty:
                bpy.data.objects.remove(o, do_unlink=True)
        joined = join_parts(part_name, non_empty)
        piv_bl = gd_to_bl(Vector(pivot_gd))
        for v in joined.data.vertices:
            v.co -= piv_bl
        joined.data.update()
        joined.location = piv_bl
        joined.parent = root_empty
        return joined

    # 1) overlord_body (legs, pelvis, cuirass, furnace core, thrusters)
    bm_iron, bm_armor, bm_gold, bm_core = (bmesh.new() for _ in range(4))
    for sx in (-1.0, 1.0):
        add_box(bm_iron, (sx * 0.66, 0.14, 0.08), (0.58, 0.28, 0.74))
        add_box(bm_gold, (sx * 0.66, 0.18, 0.42), (0.44, 0.18, 0.14))
        add_cyl(bm_armor, (sx * 0.66, 0.24, 0.0), (sx * 0.64, 0.96, 0.04), 0.26, 0.30, 10)
        add_box(bm_gold, (sx * 0.64, 0.94, 0.28), (0.38, 0.34, 0.16))
        add_cyl(bm_iron, (sx * 0.64, 0.96, 0.0), (sx * 0.58, 1.66, 0.0), 0.30, 0.34, 10)
    add_box(bm_iron, (0.0, 1.72, 0.0), (1.52, 0.42, 0.88))
    add_box(bm_gold, (0.0, 1.72, 0.46), (0.52, 0.32, 0.14))
    add_box(bm_armor, (0.0, 2.42, 0.0), (1.88, 1.12, 1.06))
    add_box(bm_gold, (0.0, 2.94, 0.02), (1.96, 0.14, 1.12))
    add_box(bm_gold, (0.0, 1.92, 0.02), (1.82, 0.12, 1.04))
    add_cyl(bm_iron, (0.0, 2.42, 0.48), (0.0, 2.42, 0.62), 0.40, 0.36, 12)
    add_rock_lobe(bm_core, (0.0, 2.42, 0.58), (0.28, 0.28, 0.14), 201, subdiv=2, amp=0.05)
    for sx in (-1.0, 1.0):
        add_cyl(bm_iron, (sx * 0.54, 2.10, -0.66), (sx * 0.58, 3.04, -0.62), 0.24, 0.18, 10)
        add_cyl(bm_core, (sx * 0.54, 1.92, -0.68), (sx * 0.54, 2.12, -0.66), 0.20, 0.22, 10)
    _join_under_pivot("overlord_body", (0.0, 0.0, 0.0), [
        part_obj("OvBodyIron", bm_iron, m_iron, smooth=False),
        part_obj("OvBodyArmor", bm_armor, m_armor, smooth=False),
        part_obj("OvBodyGold", bm_gold, m_gold, smooth=False),
        part_obj("OvBodyCore", bm_core, m_core, smooth=True),
    ])

    # 2) overlord_head (pivoted at neck gd(0.0, 3.12, 0.04))
    hm_iron, hm_gold, hm_crim = (bmesh.new() for _ in range(3))
    add_box(hm_iron, (0.0, 3.38, 0.04), (0.70, 0.62, 0.68))
    add_box(hm_crim, (0.0, 3.40, 0.40), (0.56, 0.16, 0.06))
    add_box(hm_gold, (0.0, 3.74, 0.08), (0.14, 0.40, 0.58))
    for sx in (-1.0, 1.0):
        add_cyl(hm_gold, (sx * 0.28, 3.60, 0.12), (sx * 0.78, 4.02, 0.24), 0.085, 0.022, 8)
    _join_under_pivot("overlord_head", (0.0, 3.12, 0.04), [
        part_obj("OvHeadIron", hm_iron, m_iron, smooth=False),
        part_obj("OvHeadGold", hm_gold, m_gold, smooth=False),
        part_obj("OvHeadVisor", hm_crim, m_crimson, smooth=False),
    ])

    # 3) overlord_arm_l (-X) & overlord_arm_r (+X) wielding massive twin obsidian-gold greatblades!
    for arm_name, sx in (("overlord_arm_l", -1.0), ("overlord_arm_r", 1.0)):
        ai, aa, ag, ac = (bmesh.new() for _ in range(4))
        piv = (sx * 1.24, 2.86, 0.02)
        add_box(aa, (sx * 1.28, 2.88, 0.02), (0.76, 0.64, 0.92), (0.0, 0.0, -sx * 14.0))
        add_box(ag, (sx * 1.38, 3.18, 0.02), (0.78, 0.12, 0.96), (0.0, 0.0, -sx * 14.0))
        add_cyl(ai, (sx * 1.32, 2.58, 0.04), (sx * 1.44, 1.88, 0.16), 0.24, 0.22, 10)
        add_box(aa, (sx * 1.48, 1.60, 0.28), (0.48, 0.72, 0.52))
        add_box(ag, (sx * 1.48, 1.30, 0.34), (0.50, 0.14, 0.54))
        # Twin Obsidian-Gold Greatblade ("玄铁双巨刃") extending forward (+Z in Godot!)
        add_cyl(ag, (sx * 1.48, 1.30, 0.22), (sx * 1.48, 1.30, 0.72), 0.11, 0.11, 10)  # Hilt
        add_box(ag, (sx * 1.48, 1.30, 0.76), (0.56, 0.18, 0.14))  # Crossguard
        add_box(ai, (sx * 1.48, 1.30, 1.72), (0.28, 0.07, 1.85))  # Heavy obsidian blade body
        add_box(ac, (sx * 1.48, 1.30, 1.78), (0.09, 0.09, 1.65))  # Glowing molten fuller core
        add_cyl(ag, (sx * 1.48, 1.30, 2.64), (sx * 1.48, 1.30, 3.06), 0.14, 0.015, 4)  # Tapered golden tip
        _join_under_pivot(arm_name, piv, [
            part_obj(arm_name + "_I", ai, m_iron, smooth=False),
            part_obj(arm_name + "_A", aa, m_armor, smooth=False),
            part_obj(arm_name + "_G", ag, m_gold, smooth=False),
            part_obj(arm_name + "_C", ac, m_core, smooth=False),
        ])

    # 4) overlord_halo_ring — rotating 8-spoke floating bronze-gold Dharma-Wheel Halo behind upper back
    ri, rg, rc = (bmesh.new() for _ in range(3))
    piv_h = (0.0, 2.88, -0.78)
    segs = 24
    r_maj = 1.72
    for k in range(segs):
        a0 = 2.0 * math.pi * k / segs
        a1 = 2.0 * math.pi * (k + 1) / segs
        p0 = (r_maj * math.cos(a0), 2.88 + r_maj * math.sin(a0), -0.78)
        p1 = (r_maj * math.cos(a1), 2.88 + r_maj * math.sin(a1), -0.78)
        add_cyl(rg, p0, p1, 0.095, 0.095, 8)
    for k in range(8):
        a = 2.0 * math.pi * k / 8.0
        p_in = (0.92 * math.cos(a), 2.88 + 0.92 * math.sin(a), -0.78)
        p_out = (2.08 * math.cos(a), 2.88 + 2.08 * math.sin(a), -0.78)
        add_cyl(ri, p_in, p_out, 0.065, 0.045, 6)
        add_rock_lobe(rc, (1.72 * math.cos(a), 2.88 + 1.72 * math.sin(a), -0.78), (0.14, 0.14, 0.10), 260 + k, subdiv=1, amp=0.05)
    _join_under_pivot("overlord_halo_ring", piv_h, [
        part_obj("OvHaloI", ri, m_iron, smooth=False),
        part_obj("OvHaloG", rg, m_gold, smooth=False),
        part_obj("OvHaloC", rc, m_core, smooth=True),
    ])

    return root_empty


def build_mirror_yanshan() -> bpy.types.Object:
    """v0.8.6 Ultimate「天地万象」Inverted Mirror Yanshan Mountain Peak!
    Origin sits at the sharp downward-pointing summit tip (gd_y = 0.0), extending UPWARD to gd_y = +24.0m
    with 28m broad inverted cliff base, dark cloud-wreathed flanks, and blazing golden Daoist array rings!
    """
    m_cliff = make_mat("Mat_MirrorCliff", (0.14, 0.21, 0.24), metallic=0.18, roughness=0.76)
    m_jade_rock = make_mat("Mat_MirrorQing", (0.18, 0.34, 0.36), metallic=0.22, roughness=0.62)
    m_gold_array = make_mat("Mat_MirrorArrayGold", (1.0, 0.78, 0.24), metallic=0.88, roughness=0.20, em_srgb=(1.0, 0.74, 0.18), em_str=3.8)
    m_crimson_seal = make_mat("Mat_MirrorCrimson", (1.0, 0.22, 0.18), metallic=0.12, roughness=0.18, em_srgb=(1.0, 0.24, 0.16), em_str=4.5)

    bm_cliff, bm_qing, bm_gold, bm_crim = (bmesh.new() for _ in range(4))
    rng = random.Random(2026086)

    # Main sculpted inverted mountain spire (sharp peak at y=0, broad rugged base at y=24m, r~14m)
    rings = [
        (0.0, 0.22), (2.2, 2.6), (5.5, 5.4), (9.5, 8.6),
        (14.0, 11.4), (18.8, 13.8), (22.5, 14.6), (24.2, 11.2)
    ]
    segs = 20
    ring_verts = []
    for ri_idx, (y_gd, rad) in enumerate(rings):
        rv = []
        for s in range(segs):
            a = 2.0 * math.pi * s / segs
            ridge = 1.0 + 0.18 * math.sin(a * 5.0 + ri_idx * 0.7) + 0.10 * math.cos(a * 3.0 - ri_idx * 0.5) + rng.uniform(-0.06, 0.06)
            rr = rad * (1.0 if ri_idx == 0 else ridge)
            p_bl = gd_to_bl(Vector((rr * math.cos(a), y_gd, rr * math.sin(a))))
            rv.append(bm_cliff.verts.new(p_bl))
        ring_verts.append(rv)
    for k in range(len(ring_verts) - 1):
        r1, r2 = ring_verts[k], ring_verts[k + 1]
        for s in range(segs):
            sn = (s + 1) % segs
            bm_cliff.faces.new((r1[s], r2[s], r2[sn], r1[sn]))
    bm_cliff.faces.new(list(reversed(ring_verts[0])))
    bm_cliff.faces.new(ring_verts[-1])

    # Flanking subsidiary inverted crag spires & upside-down Qinglü peak ridges
    for k in range(6):
        a = 2.0 * math.pi * k / 6.0 + 0.35
        dist = 8.4 + (k % 2) * 2.2
        bx, bz = dist * math.cos(a), dist * math.sin(a)
        add_cyl(bm_qing, (bx, 5.8 + (k % 3) * 1.4, bz), (bx * 1.15, 22.8, bz * 1.15), 0.28, 3.6, 7)

    # Two massive blazing golden Daoist formation rings encircling the inverted mountain waist!
    for y_ring, r_ring, thick in [(4.2, 9.5, 0.28), (11.5, 15.6, 0.34)]:
        r_segs = 32
        for k in range(r_segs):
            a0 = 2.0 * math.pi * k / r_segs
            a1 = 2.0 * math.pi * (k + 1) / r_segs
            add_cyl(bm_gold, (r_ring * math.cos(a0), y_ring, r_ring * math.sin(a0)), (r_ring * math.cos(a1), y_ring, r_ring * math.sin(a1)), thick, thick, 6)
        # 8 cardinal glowing rune pillars around the golden ring
        for k in range(8):
            a = 2.0 * math.pi * k / 8.0
            add_box(bm_crim, (r_ring * math.cos(a), y_ring, r_ring * math.sin(a)), (0.95, 1.25, 0.95), (0, math.degrees(a), 0))

    # Radiant crimson-gold descending apex seal core at the downward tip!
    add_rock_lobe(bm_crim, (0.0, 0.85, 0.0), (1.15, 1.35, 1.15), 312, subdiv=2, amp=0.06)

    return join_parts("mirror_yanshan_peak", [
        part_obj("MirrorCliff", bm_cliff, m_cliff, smooth=False),
        part_obj("MirrorQing", bm_qing, m_jade_rock, smooth=False),
        part_obj("MirrorArrayGold", bm_gold, m_gold_array, smooth=False),
        part_obj("MirrorSealCore", bm_crim, m_crimson_seal, smooth=True),
    ])


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    w = build_cave_warden()
    o = build_skyfall_overlord()
    bpy.context.view_layer.update()
    for obj in list(w.children) + list(o.children):
        if obj.type != "MESH":
            continue
        verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
        xs = [v.x for v in verts]
        ys = [v.y for v in verts]
        zs = [v.z for v in verts]
        loc = obj.location
        print(
            f"Built {obj.name:20s} (pivot gd=({loc.x:.2f},{loc.z:.2f},{-loc.y:.2f})): "
            f"{len(obj.data.polygons):4d} polys, gd_x=[{min(xs):.2f},{max(xs):.2f}] "
            f"gd_y=[{min(zs):.2f},{max(zs):.2f}] gd_z=[{-max(ys):.2f},{-min(ys):.2f}]"
        )

    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
    )
    print(f"Exported v0.8.6 articulated Boss models -> {OUT_GLB} ({OUT_GLB.stat().st_size} bytes)")

    # Export standalone Inverted Mirror Yanshan Mountain Peak for Ultimate「天地万象」
    bpy.ops.wm.read_factory_settings(use_empty=True)
    my = build_mirror_yanshan()
    bpy.context.view_layer.update()
    print(f"Built {my.name}: {len(my.data.polygons)} polys")
    bpy.ops.export_scene.gltf(
        filepath=str(MIRROR_GLB),
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
    )
    print(f"Exported Inverted Mirror Yanshan -> {MIRROR_GLB} ({MIRROR_GLB.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
