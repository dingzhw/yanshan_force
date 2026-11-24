"""Build v0.9.7 Sculpted Rigged Animated NPCs & Yanshan Mistbound Troops in Blender 5.3.

Produces 3 self-contained rigged + skeletally animated GLBs:
  1. game/assets/slice/npc_chen_guide.glb         — Sculpted face + eyes + Jiangnan ranger scout hat + golden scarf + binoculars + Idle_Camp anim
  2. game/assets/slice/v097_mistbound_assault.glb — Qinglu composite armor + Jiangnan eave-visor helm + carbine + Idle_Aim / Walk_Patrol / Run_Advance
  3. game/assets/slice/v097_mistbound_sniper.glb  — Heavy obsidian-bronze marksman armor + crimson optic visor + long rifle + Idle_Aim / Walk_Patrol / Run_Advance
"""
import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

TOOLS_DIR = str(Path(__file__).resolve().parent)
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

import build_v095_shaoyu_refined as s95

ROOT = Path(__file__).resolve().parents[1]
SLICE_DIR = ROOT / "game" / "assets" / "slice"
CC0_DIR = ROOT / "third_party" / "v094_cc0_characters"


def set_smooth_all(obj):
    if obj and obj.type == "MESH":
        for p in obj.data.polygons:
            p.use_smooth = True


def clean_mesh_materials(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.material_index = 0
    set_smooth_all(obj)


def color_swat_body_zones(body_obj, mat_coat, mat_vest, mat_glove, mat_skin=None, mat_trim=None):
    """Assign material slots cleanly by geometric zones on normalized Swat_Body."""
    mats = [mat_coat, mat_vest, mat_glove, mat_skin or mat_glove, mat_trim or mat_vest]
    body_obj.data.materials.clear()
    for m in mats:
        body_obj.data.materials.append(m)
    for p in body_obj.data.polygons:
        c = p.center
        ax = abs(c.x)
        if ax > 0.36:
            p.material_index = 2  # hands / gloves
        elif ax < 0.19 and 0.94 < c.z < 1.38:
            p.material_index = 1  # chest rig / plate carrier
        elif ax < 0.17 and 0.86 < c.z <= 0.94:
            p.material_index = 4  # waist belt / trim
        else:
            p.material_index = 0  # jacket / sleeves
    set_smooth_all(body_obj)


def attach_mesh_to_bone(arm, name, bm, mats, bone_name):
    me = bpy.data.meshes.new(name + "_Mesh")
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add([v.index for v in me.vertices], 1.0, "REPLACE")
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    return obj


def export_rig_glb(arm, meshes, out_path: Path):
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for m in meshes:
        if m and m.name in bpy.data.objects:
            m.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_nla_strips_merged_animation_name="",
        export_optimize_animation_size=True,
        export_materials="EXPORT",
        export_image_format="JPEG",
        export_jpeg_quality=82,
    )
    kb = out_path.stat().st_size / 1024.0
    tris = sum(len(m.data.polygons) for m in meshes if m and m.name in bpy.data.objects)
    n_anims = len(arm.animation_data.nla_tracks) if arm.animation_data else 0
    print(f"EXPORTED_CHAR {out_path.name} ({kb:.0f} KB | {tris} polys | {n_anims} anims)")


def push_actions_to_nla(arm, actions):
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = None
    for tr in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(tr)
    for act in actions:
        if act is None:
            continue
        act.use_fake_user = True
        tr = arm.animation_data.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, int(round(act.frame_range[0])), act)
        st.name = act.name
        tr.mute = True
    s95.reset_pose(arm)


# ---------------------------------------------------------------------------
# 1. Camp Liaison NPC: 陈向导 (npc_chen_guide.glb)
# ---------------------------------------------------------------------------
def build_chen_guide():
    s95.TARGET_HEIGHT = 1.78
    arm, body, legs, feet = s95.build_normalized_shaoyu_base()
    arm.name = "ChenGuideArmature"
    s95.weld_and_subsurf(body, subsurf_level=0, smooth_iters=1, smooth_fac=0.14)
    s95.weld_and_subsurf(legs, subsurf_level=0, smooth_iters=1, smooth_fac=0.14)
    s95.weld_and_subsurf(feet, subsurf_level=0, smooth_iters=1, smooth_fac=0.12)

    pal = s95.create_material_palette()
    # Veteran guide custom warm weathered materials
    fab_n = s95.make_fabric_normal_image("Tex_ChenRipstop", 256, 14, 0.36)
    lth_n = s95.make_leather_normal_image("Tex_ChenLeather", 256)
    m_coat = s95.make_pbr_mat("Chen_RangerCoat", s95.srgb(46, 92, 74), roughness=0.70, normal_img=fab_n, normal_scale=0.34, tex_scale=10.0)
    m_vest = s95.make_pbr_mat("Chen_FieldVest", s95.srgb(58, 52, 44), roughness=0.68, normal_img=fab_n, normal_scale=0.38, tex_scale=12.0)
    m_scarf = s95.make_pbr_mat("Chen_GoldScarf", s95.srgb(220, 168, 66), roughness=0.74, normal_img=fab_n, normal_scale=0.38, tex_scale=14.0)
    m_pants = s95.make_pbr_mat("Chen_FieldPants", s95.srgb(44, 48, 52), roughness=0.76, normal_img=fab_n, normal_scale=0.34, tex_scale=9.0)
    m_boot = s95.make_pbr_mat("Chen_Boots", s95.srgb(74, 52, 38), roughness=0.58, normal_img=lth_n, normal_scale=0.40, tex_scale=8.0)
    m_hat = s95.make_pbr_mat("Chen_ScoutHat", s95.srgb(42, 72, 58), roughness=0.72, normal_img=fab_n, normal_scale=0.32, tex_scale=10.0)
    m_brass = s95.make_pbr_mat("Chen_Brass", s95.srgb(208, 164, 74), roughness=0.30, metallic=0.82)
    m_glass = s95.make_pbr_mat("Chen_OpticLens", s95.srgb(38, 128, 152), roughness=0.10, metallic=0.25)
    m_hair = s95.make_pbr_mat("Chen_VeteranHair", s95.srgb(46, 48, 54), roughness=0.54)
    # Slightly warmer sun-tanned skin for veteran field guide
    pal["skin"] = s95.make_pbr_mat("Chen_Skin", s95.srgb(214, 162, 126), roughness=0.58)
    pal["eyebrow"] = m_hair

    color_swat_body_zones(body, m_coat, m_vest, m_boot, pal["skin"], m_brass)
    clean_mesh_materials(legs, m_pants)
    clean_mesh_materials(feet, m_boot)

    # Real sculpted Blender Studio CC0 stylized face + expressive eyes!
    head_obj, eyes_obj, hinfo = s95.build_sculpted_blender_studio_head(arm, pal)
    head_obj.name = "Chen_Head"
    eyes_obj.name = "Chen_Eyes"

    # Trim hair + sculpted Jiangnan wide-brim ranger scout hat + mustache/stubble ridge
    head_top = hinfo["z_max"]
    head_y = 0.5 * (hinfo["y_min"] + hinfo["y_max"])
    bm_hat = bmesh.new()
    # Hair sideburns & back crown peeking cleanly under scout hat
    s95.add_sphere_mesh(bm_hat, (0.0, head_y + 0.014, head_top - 0.088), (0.096, 0.106, 0.085), segs=16, rings=10, mat_idx=2)
    # Wide-brim Jiangnan ranger hat (slightly tilted back so his sculpted face & eyes read clearly!)
    hat_c = Vector((0.0, head_y + 0.008, head_top - 0.032))
    s95.add_cyl_mesh(bm_hat, hat_c + Vector((0, 0, 0.038)), 0.106, 0.072, 0.092, segs=22, rot_euler=(math.radians(-6), 0, 0), mat_idx=0)
    s95.add_cyl_mesh(bm_hat, hat_c + Vector((0, 0, -0.005)), 0.235, 0.112, 0.036, segs=26, rot_euler=(math.radians(-6), 0, 0), mat_idx=0)
    # Brass hatband & cloud badge at front
    s95.add_cyl_mesh(bm_hat, hat_c + Vector((0, 0, 0.018)), 0.108, 0.104, 0.022, segs=22, rot_euler=(math.radians(-6), 0, 0), mat_idx=1)
    s95.add_box_mesh(bm_hat, hat_c + Vector((0, -0.108, 0.022)), (0.038, 0.012, 0.028), rot_euler=(math.radians(-6), 0, 0), mat_idx=1, bevel=0.004)
    hat_obj = attach_mesh_to_bone(arm, "Chen_ScoutHat", bm_hat, [m_hat, m_brass, m_hair], "Head")

    # Golden collar scarf + chest binoculars + belt field radio + ranger shoulder satchel
    bm_gear = bmesh.new()
    # Warm golden woven collar scarf + trailing front drape
    s95.add_cyl_mesh(bm_gear, (0.0, 0.012, 1.415), 0.118, 0.108, 0.078, segs=20, mat_idx=0)
    s95.add_box_mesh(bm_gear, (0.055, -0.112, 1.315), (0.088, 0.028, 0.21), rot_euler=(0.14, 0.0, -0.15), mat_idx=0, bevel=0.009)
    s95.add_box_mesh(bm_gear, (-0.062, -0.108, 1.335), (0.078, 0.026, 0.16), rot_euler=(0.12, 0.0, 0.18), mat_idx=0, bevel=0.009)
    # Field binoculars hanging on chest
    for bx in (-0.036, 0.036):
        s95.add_cyl_mesh(bm_gear, (bx, -0.152, 1.245), 0.024, 0.020, 0.115, segs=14, rot_euler=(math.radians(78), 0, 0), mat_idx=1)
        s95.add_cyl_mesh(bm_gear, (bx, -0.208, 1.233), 0.018, 0.018, 0.010, segs=12, rot_euler=(math.radians(78), 0, 0), mat_idx=3)
    s95.add_box_mesh(bm_gear, (0.0, -0.148, 1.248), (0.052, 0.042, 0.026), mat_idx=2, bevel=0.005)
    # Rolled topographic map tube + radio pouch on hip/chest
    s95.add_cyl_mesh(bm_gear, (-0.155, 0.025, 1.015), 0.028, 0.028, 0.28, segs=12, rot_euler=(0.2, 0.85, 0.0), mat_idx=2)
    s95.add_box_mesh(bm_gear, (0.145, -0.095, 1.18), (0.058, 0.042, 0.11), mat_idx=1, bevel=0.008)
    s95.add_cyl_mesh(bm_gear, (0.162, -0.095, 1.29), 0.004, 0.003, 0.14, segs=8, mat_idx=2)
    gear_obj = attach_mesh_to_bone(arm, "Chen_RangerGear", bm_gear, [m_scarf, m_vest, m_brass, m_glass], "Chest")

    # Smooth natural breathing & camp-survey Idle animation!
    if arm.animation_data is None:
        arm.animation_data_create()
    acts = s95.retarget_actions_from_file(
        arm,
        str(CC0_DIR / "AnimationLibrary_Godot_Standard.gltf"),
        s95.UAL_BONE_MAP,
        {"Idle_Loop": "Idle_Camp"},
        step=2,
    )
    push_actions_to_nla(arm, acts)

    meshes = [body, legs, feet, head_obj, eyes_obj, hat_obj, gear_obj]
    export_rig_glb(arm, meshes, SLICE_DIR / "npc_chen_guide.glb")


# ---------------------------------------------------------------------------
# 2 & 3. Yanshan Mistbound Assault & Sniper Rigged Animated Troopers
# ---------------------------------------------------------------------------
def build_mistbound_rifle_mesh(arm, is_sniper: bool, mat_gun, mat_bronze, mat_optic):
    """Build a crisp compact tactical carbine (or long sniper marksman rifle) weighted 100% to Weapon_R!"""
    bm = bmesh.new()
    wb = arm.data.bones["Weapon_R"]
    origin = wb.head_local
    # Weapon_R points along -Y (forward barrel) and +Z (up) in Blender space!
    def p(dx, dy, dz):
        return origin + Vector((dx, dy, dz))

    if is_sniper:
        # Receiver + extended fluted sniper barrel + suppressor + high-zoom scope + folding stock
        s95.add_box_mesh(bm, p(0.0, -0.14, 0.055), (0.052, 0.42, 0.088), mat_idx=0, bevel=0.006)
        s95.add_cyl_mesh(bm, p(0.0, -0.56, 0.068), 0.015, 0.013, 0.56, segs=12, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=0)
        s95.add_cyl_mesh(bm, p(0.0, -0.82, 0.068), 0.022, 0.022, 0.16, segs=12, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=1)
        s95.add_box_mesh(bm, p(0.0, 0.18, 0.048), (0.042, 0.28, 0.072), mat_idx=0, bevel=0.005)
        s95.add_box_mesh(bm, p(0.0, -0.02, -0.032), (0.034, 0.065, 0.115), rot_euler=(-0.22, 0, 0), mat_idx=0, bevel=0.004)
        s95.add_box_mesh(bm, p(0.0, -0.18, -0.055), (0.032, 0.088, 0.14), mat_idx=1, bevel=0.004)
        # Sniper optic scope
        s95.add_cyl_mesh(bm, p(0.0, -0.15, 0.138), 0.024, 0.020, 0.28, segs=12, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=0)
        s95.add_cyl_mesh(bm, p(0.0, -0.295, 0.138), 0.021, 0.021, 0.012, segs=12, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=2)
    else:
        # Compact Qinglu Mistbound tactical carbine with bronze rail trim & reflex sight
        s95.add_box_mesh(bm, p(0.0, -0.12, 0.052), (0.052, 0.36, 0.086), mat_idx=0, bevel=0.006)
        s95.add_box_mesh(bm, p(0.0, -0.34, 0.058), (0.044, 0.22, 0.062), mat_idx=1, bevel=0.005)
        s95.add_cyl_mesh(bm, p(0.0, -0.52, 0.062), 0.015, 0.014, 0.24, segs=10, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=0)
        s95.add_box_mesh(bm, p(0.0, 0.14, 0.045), (0.040, 0.22, 0.068), mat_idx=0, bevel=0.005)
        s95.add_box_mesh(bm, p(0.0, -0.01, -0.030), (0.034, 0.058, 0.110), rot_euler=(-0.22, 0, 0), mat_idx=0, bevel=0.004)
        s95.add_box_mesh(bm, p(0.0, -0.16, -0.058), (0.030, 0.068, 0.155), rot_euler=(0.14, 0, 0), mat_idx=0, bevel=0.004)
        s95.add_box_mesh(bm, p(0.0, -0.12, 0.115), (0.038, 0.095, 0.044), mat_idx=0, bevel=0.004)
        s95.add_box_mesh(bm, p(0.0, -0.168, 0.115), (0.028, 0.010, 0.028), mat_idx=2, bevel=0.002)

    return attach_mesh_to_bone(arm, "Mistbound_Rifle", bm, [mat_gun, mat_bronze, mat_optic], "Weapon_R")


def build_mistbound_trooper(variant: str):
    is_sniper = (variant == "sniper")
    s95.TARGET_HEIGHT = 1.84 if is_sniper else 1.76
    arm, body, legs, feet = s95.build_normalized_shaoyu_base()
    arm.name = f"Mistbound_{variant.title()}_Armature"
    s95.weld_and_subsurf(body, subsurf_level=0, smooth_iters=1, smooth_fac=0.12)
    s95.weld_and_subsurf(legs, subsurf_level=0, smooth_iters=1, smooth_fac=0.12)
    s95.weld_and_subsurf(feet, subsurf_level=0, smooth_iters=1, smooth_fac=0.10)

    fab_n = s95.make_fabric_normal_image(f"Tex_MistRip_{variant}", 256, 16, 0.36)
    lth_n = s95.make_leather_normal_image(f"Tex_MistLth_{variant}", 256)

    if is_sniper:
        m_armor = s95.make_pbr_mat("MistSniper_Armor", s95.srgb(52, 48, 46), roughness=0.58, metallic=0.16, normal_img=fab_n, normal_scale=0.32, tex_scale=10.0)
        m_plate = s95.make_pbr_mat("MistSniper_Plate", s95.srgb(36, 38, 42), roughness=0.46, metallic=0.28)
        m_bronze = s95.make_pbr_mat("MistSniper_Bronze", s95.srgb(196, 146, 68), roughness=0.30, metallic=0.80)
        m_visor = s95.make_pbr_mat("MistSniper_Visor", s95.srgb(255, 76, 92), roughness=0.12, emission=s95.srgb(255, 64, 82), emission_strength=2.2)
        m_undersuit = s95.make_pbr_mat("MistSniper_Suit", s95.srgb(28, 32, 36), roughness=0.76, normal_img=fab_n, normal_scale=0.30, tex_scale=12.0)
    else:
        m_armor = s95.make_pbr_mat("MistAssault_Armor", s95.srgb(58, 96, 86), roughness=0.58, metallic=0.14, normal_img=fab_n, normal_scale=0.34, tex_scale=10.0)
        m_plate = s95.make_pbr_mat("MistAssault_Plate", s95.srgb(36, 56, 54), roughness=0.48, metallic=0.26)
        m_bronze = s95.make_pbr_mat("MistAssault_Bronze", s95.srgb(202, 158, 76), roughness=0.30, metallic=0.78)
        m_visor = s95.make_pbr_mat("MistAssault_Visor", s95.srgb(112, 240, 198), roughness=0.12, emission=s95.srgb(96, 236, 192), emission_strength=2.0)
        m_undersuit = s95.make_pbr_mat("MistAssault_Suit", s95.srgb(30, 40, 42), roughness=0.76, normal_img=fab_n, normal_scale=0.30, tex_scale=12.0)

    m_boot = s95.make_pbr_mat(f"Mist_{variant}_Boot", s95.srgb(30, 34, 38), roughness=0.62, normal_img=lth_n, normal_scale=0.36, tex_scale=8.0)
    m_gun = s95.make_pbr_mat(f"Mist_{variant}_Gun", s95.srgb(34, 38, 44), roughness=0.38, metallic=0.62)

    color_swat_body_zones(body, m_armor, m_plate, m_boot, m_undersuit, m_bronze)
    clean_mesh_materials(legs, m_undersuit)
    clean_mesh_materials(feet, m_boot)

    # Sculpted Jiangnan Eave-Visor Tactical Helmet ('斗笠飞檐盔') weighted cleanly to Head bone
    head_b = arm.data.bones["Head"]
    hc = head_b.head_local + Vector((0.0, 0.005, 0.105))
    bm_helm = bmesh.new()
    # Enclosed neck gaiter + ballistic cranium shell + angular jaw respirator mask
    s95.add_cyl_mesh(bm_helm, hc + Vector((0, 0, -0.105)), 0.068, 0.062, 0.095, segs=14, mat_idx=3)
    s95.add_sphere_mesh(bm_helm, hc, (0.102, 0.114, 0.116), segs=18, rings=12, mat_idx=1)
    s95.add_box_mesh(bm_helm, hc + Vector((0, -0.072, -0.048)), (0.116, 0.088, 0.086), rot_euler=(0.14, 0, 0), mat_idx=1, bevel=0.014)
    # Recessed glowing tactical visor strip
    s95.add_box_mesh(bm_helm, hc + Vector((0, -0.106, 0.012)), (0.138, 0.036, 0.034), mat_idx=4, bevel=0.006)
    # Signature Jiangnan conical eave-brim crest ('斗笠飞檐') with bronze rim & finial!
    brim_r = 0.255 if is_sniper else 0.228
    s95.add_cyl_mesh(bm_helm, hc + Vector((0, 0.006, 0.118)), brim_r, 0.042, 0.115, segs=18, mat_idx=0)
    s95.add_cyl_mesh(bm_helm, hc + Vector((0, 0.006, 0.062)), brim_r + 0.010, brim_r + 0.004, 0.016, segs=18, mat_idx=2)
    s95.add_cyl_mesh(bm_helm, hc + Vector((0, 0.006, 0.184)), 0.030, 0.010, 0.034, segs=12, mat_idx=2)
    helm_obj = attach_mesh_to_bone(arm, "Mistbound_Helmet", bm_helm, [m_armor, m_plate, m_bronze, m_undersuit, m_visor], "Head")

    # Sculpted lamellar shoulder pauldrons + chest plate rig + bronze waist clasp + sniper shoulder capelet
    chest_z = arm.data.bones["Chest"].head_local.z
    bm_rig = bmesh.new()
    # Front lamellar chest plate + bronze central medallion + 3 mag pouches
    s95.add_box_mesh(bm_rig, (0.0, -0.125, chest_z + 0.06), (0.28, 0.072, 0.29), mat_idx=1, bevel=0.016)
    s95.add_box_mesh(bm_rig, (0.0, -0.162, chest_z + 0.12), (0.072, 0.020, 0.072), rot_euler=(0, math.radians(45), 0), mat_idx=2, bevel=0.005)
    for mx in (-0.078, 0.0, 0.078):
        s95.add_box_mesh(bm_rig, (mx, -0.165, chest_z - 0.035), (0.058, 0.044, 0.105), mat_idx=0, bevel=0.008)
    # Back tactical power/comms pack
    s95.add_box_mesh(bm_rig, (0.0, 0.155, chest_z + 0.05), (0.24, 0.10, 0.30), mat_idx=1, bevel=0.018)
    s95.add_cyl_mesh(bm_rig, (-0.095, 0.165, chest_z + 0.28), 0.006, 0.004, 0.24, segs=8, mat_idx=2)
    if is_sniper:
        # Asymmetric tactical half-cape & shoulder rangefinder rail on sniper
        s95.add_box_mesh(bm_rig, (0.0, 0.195, chest_z - 0.10), (0.42, 0.025, 0.56), rot_euler=(0.12, 0, 0), mat_idx=0, bevel=0.008)
        s95.add_box_mesh(bm_rig, (-0.195, -0.02, chest_z + 0.22), (0.068, 0.22, 0.068), mat_idx=2, bevel=0.008)
    rig_obj = attach_mesh_to_bone(arm, "Mistbound_ChestArmor", bm_rig, [m_armor, m_plate, m_bronze], "Chest")

    # Sculpted Left & Right Lamellar Shoulder Pauldrons weighted to UpperArm.L / UpperArm.R!
    p_objs = []
    for side, sgn in (("L", 1.0), ("R", -1.0)):
        ub = arm.data.bones[f"UpperArm.{side}"]
        pc = ub.head_local + Vector((sgn * 0.045, 0.0, 0.015))
        bm_p = bmesh.new()
        s95.add_box_mesh(bm_p, pc, (0.145, 0.185, 0.155), rot_euler=(0, sgn * 0.28, 0), mat_idx=0, bevel=0.018)
        s95.add_box_mesh(bm_p, pc + Vector((sgn * 0.025, 0, -0.062)), (0.155, 0.195, 0.026), rot_euler=(0, sgn * 0.28, 0), mat_idx=1, bevel=0.006)
        p_objs.append(attach_mesh_to_bone(arm, f"Mistbound_Pauldron_{side}", bm_p, [m_armor, m_bronze], f"UpperArm.{side}"))

    # Attached weapon mesh weighted to Weapon_R!
    rifle_obj = build_mistbound_rifle_mesh(arm, is_sniper, m_gun, m_bronze, m_visor)

    # Bake 3 super-clean tactical animations: Idle_Aim, Walk_Patrol, Run_Advance!
    if arm.animation_data is None:
        arm.animation_data_create()
    acts = []
    acts.append(
        s95.pose_and_key_rifle_stance(
            arm,
            "Idle_Aim",
            (-0.085, -0.310, 1.335 if is_sniper else 1.295),
            (0.0, 0.0, -2.0),
            hips_drop=0.05,
            torso_yaw_deg=26.0,
            torso_pitch_deg=5.0,
            head_tilt_deg=-5.0,
            breath_amp=0.008,
            frames=28,
        )
    )
    acts += s95.retarget_actions_from_file(
        arm,
        str(CC0_DIR / "AnimationLibrary_Godot_Standard.gltf"),
        s95.UAL_BONE_MAP,
        {"Walk_Loop": "Walk_Patrol", "Jog_Fwd_Loop": "Run_Advance"},
        step=2,
    )
    push_actions_to_nla(arm, acts)

    meshes = [body, legs, feet, helm_obj, rig_obj, rifle_obj] + p_objs
    out_name = "v097_mistbound_sniper.glb" if is_sniper else "v097_mistbound_assault.glb"
    export_rig_glb(arm, meshes, SLICE_DIR / out_name)


def main():
    build_chen_guide()
    build_mistbound_trooper("assault")
    build_mistbound_trooper("sniper")
    print("V097_CHARACTER_RIGS_COMPLETE")


if __name__ == "__main__":
    main()
