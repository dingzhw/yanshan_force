"""v0.9.9.6_dev1 High-Fidelity Armored Characters & Bosses Pipeline (Blender 5.3).

Extracts ONLY strictly SFW, 100% fully-armored battle exosuit & weapon sets from the local
armored exosuit source blend, converts packed maps to optimized real-time Godot 4.7 Principled
BSDF PBR with faction-calibrated palettes, remaps Rigify DEF-* weights cleanly onto a lean
19-bone game skeleton, and bakes Idle_Aim / Walk_Patrol / Run_Advance loops into:
  1. game/assets/slice/v0996_haavk_trooper.glb    (1.82m HAAVK Elite Operative — crisp white/silver sci-fi armor + cyan visor + rifle)
  2. game/assets/slice/v0996_vanguard_boss.glb    (2.46m Ironface Vanguard Boss — obsidian-iron & crimson horned juggernaut + chest core + heavy cannon)
  3. game/assets/slice/v0996_skyfall_overlord.glb (3.68m Skyfall Overlord Colossus — obsidian & gold Anubis winged mech + spinning Dharma halo + twin blades)

Also outputs optional preview stills and 1024x1280 RGBA studio bust foregrounds for 1:1 Lore Codex portraits!

Usage:
  blender --background --factory-startup --python tools/build_v0996_dev1_armored_units.py -- \
    --source <pharah-bodyhack.blend> [--preview <dir>] [--portraits <dir>]
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

REPO_ROOT = Path(__file__).resolve().parents[1]
SLICE_DIR = REPO_ROOT / "game" / "assets" / "slice"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=str, required=True)
    ap.add_argument("--preview", type=str, default="")
    ap.add_argument("--portraits", type=str, default="")
    ap.add_argument("--only", type=str, default="")
    return ap.parse_args(argv)


def bake_processed_image(
    src_img: bpy.types.Image,
    out_name: str,
    max_dim: int,
    colorspace: str,
    tmp_dir: Path,
    mode: str = "passthrough",
    fmt: str = "JPEG",
) -> bpy.types.Image:
    """Convert packed source texture to clean Godot-compatible JPG/PNG with optional faction palette grading."""
    w, h = int(src_img.size[0]), int(src_img.size[1])
    if w <= 0 or h <= 0:
        raise RuntimeError(f"Empty image: {src_img.name}")
    cp = src_img.copy()
    cp.name = out_name + "_tmp"
    if max(w, h) > max_dim:
        sc = max_dim / float(max(w, h))
        nw = max(64, int(round(w * sc)))
        nh = max(64, int(round(h * sc)))
        cp.scale(nw, nh)
        w, h = nw, nh

    px = np.array(cp.pixels[:], dtype=np.float32).reshape(h, w, cp.channels)
    rgb = px[:, :, :3].copy()

    if mode == "haavk_white":
        # Transform brown/tan security armor -> crisp HAAVK tactical snow-white / cool titanium silver!
        lum = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]
        # Keep dark straps/undersuit dark charcoal while lifting armor plates to crisp matte white-silver
        plate = np.clip((lum - 0.16) / 0.42, 0.0, 1.0)
        white_r = 0.14 + plate * 0.76
        white_g = 0.16 + plate * 0.78
        white_b = 0.19 + plate * 0.79
        # Preserve ONLY crisp LED accents as cyan (avoid false-positive brown straps!)
        sat = np.max(rgb, axis=2) - np.min(rgb, axis=2)
        accent = np.clip((sat - 0.36) * 4.0, 0.0, 1.0) * (lum > 0.38)
        rgb[:, :, 0] = white_r * (1.0 - accent) + 0.16 * accent
        rgb[:, :, 1] = white_g * (1.0 - accent) + 0.86 * accent
        rgb[:, :, 2] = white_b * (1.0 - accent) + 0.98 * accent
        rgb = np.clip(rgb, 0.0, 1.0)
    elif mode == "vanguard_obsidian_crimson":
        # Transform Asp golden armor -> cool dark forged iron-gunmetal steel with crisp crimson accents (zero pink tint!)
        lum = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]
        is_cyan = ((rgb[:, :, 2] - rgb[:, :, 0]) > 0.10) & (rgb[:, :, 1] > 0.22)
        steel_r = np.clip(lum * 0.34 + 0.045, 0.045, 0.34)
        steel_g = np.clip(lum * 0.37 + 0.050, 0.050, 0.37)
        steel_b = np.clip(lum * 0.43 + 0.060, 0.060, 0.43)
        out_r = np.where(is_cyan, 0.68, steel_r)
        out_g = np.where(is_cyan, 0.08, steel_g)
        out_b = np.where(is_cyan, 0.09, steel_b)
        rgb = np.clip(np.stack([out_r, out_g, out_b], axis=2), 0.0, 1.0)
    elif mode == "vanguard_tasset_cloth":
        # Replace Egyptian Ankh banner cleanly with Mistbound obsidian-crimson war banner!
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        u = xx / max(1.0, w - 1.0)
        v = yy / max(1.0, h - 1.0)
        rgb[:, :, 0] = 0.13
        rgb[:, :, 1] = 0.14
        rgb[:, :, 2] = 0.16
        # Vertical crimson border bands & subtle iron weave
        weave = 0.015 * np.sin(xx * 0.8) * np.sin(yy * 0.8)
        border = (u < 0.14) | (u > 0.86) | (v < 0.12)
        gold_line = ((u >= 0.14) & (u < 0.18)) | ((u > 0.82) & (u <= 0.86))
        rgb[:, :, 0] = np.where(border, 0.58, np.where(gold_line, 0.68, rgb[:, :, 0] + weave))
        rgb[:, :, 1] = np.where(border, 0.10, np.where(gold_line, 0.52, rgb[:, :, 1] + weave))
        rgb[:, :, 2] = np.where(border, 0.12, np.where(gold_line, 0.22, rgb[:, :, 2] + weave))
        rgb = np.clip(rgb, 0.0, 1.0)
    elif mode == "overlord_obsidian_gold":
        # Deepen Anubis/Jackal armor into dramatic obsidian charcoal + gleaming antique burnished gold!
        r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        warmth = (r - b)
        is_gold = (warmth > 0.10) & (r > 0.30) & (g > 0.20)
        # Obsidian plates: rich dark charcoal-titanium; Gold filigree: vivid burnished gold
        obs_r = np.clip(lum * 0.38 + 0.035, 0.035, 0.26)
        obs_g = np.clip(lum * 0.40 + 0.040, 0.040, 0.28)
        obs_b = np.clip(lum * 0.46 + 0.048, 0.048, 0.33)
        gold_r = np.clip(r * 1.15 + 0.05, 0.0, 1.0)
        gold_g = np.clip(g * 1.04 + 0.02, 0.0, 0.88)
        gold_b = np.clip(b * 0.62, 0.0, 0.36)
        rgb = np.clip(np.stack([
            np.where(is_gold, gold_r, obs_r),
            np.where(is_gold, gold_g, obs_g),
            np.where(is_gold, gold_b, obs_b),
        ], axis=2), 0.0, 1.0)
    elif mode == "dark_bodysuit":
        # Crisp matte charcoal-black tactical exo-undersuit
        lum = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]
        rgb[:, :, 0] = np.clip(lum * 0.30 + 0.055, 0.05, 0.20)
        rgb[:, :, 1] = np.clip(lum * 0.32 + 0.060, 0.055, 0.22)
        rgb[:, :, 2] = np.clip(lum * 0.36 + 0.070, 0.065, 0.25)

    px[:, :, :3] = rgb
    if cp.channels == 4:
        px[:, :, 3] = 1.0
    cp.pixels.foreach_set(px.ravel())

    # ALWAYS write genuine 8-bit PNG bytes (Godot 4.7.2 rejects Blender 5.3's cp.save() JPEG bufferViews!)
    out_file = tmp_dir / f"{out_name}.png"
    cp.filepath_raw = str(out_file)
    cp.file_format = "PNG"
    sc = bpy.context.scene
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.image_settings.color_depth = "8"
    cp.save()
    bpy.data.images.remove(cp, do_unlink=True)

    clean_img = bpy.data.images.load(str(out_file), check_existing=False)
    clean_img.name = out_name
    clean_img.colorspace_settings.name = colorspace
    clean_img.pack()
    return clean_img


def make_pbr_mat(
    name: str,
    albedo_img: bpy.types.Image | None = None,
    normal_img: bpy.types.Image | None = None,
    rough_img: bpy.types.Image | None = None,
    metal_img: bpy.types.Image | None = None,
    base_color: tuple[float, float, float, float] = (0.8, 0.8, 0.8, 1.0),
    roughness: float = 0.45,
    metallic: float = 0.25,
    normal_scale: float = 0.80,
    emission_rgba: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission_rgba is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = emission_rgba
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tc = nt.nodes.new("ShaderNodeTexCoord")

    if albedo_img is not None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = albedo_img
        nt.links.new(tc.outputs["UV"], t.inputs["Vector"])
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])

    if rough_img is not None:
        tr = nt.nodes.new("ShaderNodeTexImage")
        tr.image = rough_img
        nt.links.new(tc.outputs["UV"], tr.inputs["Vector"])
        nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])

    if metal_img is not None:
        tm = nt.nodes.new("ShaderNodeTexImage")
        tm.image = metal_img
        nt.links.new(tc.outputs["UV"], tm.inputs["Vector"])
        nt.links.new(tm.outputs["Color"], bsdf.inputs["Metallic"])

    if normal_img is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = normal_img
        nt.links.new(tc.outputs["UV"], tn.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_scale
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def map_rigify_vg(vg_name: str, default_bone: str = "Chest") -> str | None:
    """Strictly map ONLY Rigify deform vertex groups onto our clean 19-bone game skeleton.
    Returns None for Blender helper/mask groups (MSK-*, MOD-*, ORG-*, PRT-*, Temp, Group)!
    """
    if vg_name.startswith(("MSK-", "MOD-", "ORG-", "PRT-")) or vg_name in ("Temp", "Group", "Genitals_interior"):
        return None
    n = vg_name.lower()
    is_l = ".l" in n
    is_r = ".r" in n
    side = ".L" if is_l else (".R" if is_r else "")

    if "shoulder" in n or "pauldron" in n:
        return "Shoulder" + (side or ".L")
    if any(k in n for k in ["hand", "palm", "thumb", "index", "middle", "ring", "pinky"]):
        return "Hand" + (side or ".L")
    if "forearm" in n:
        return "ForeArm" + (side or ".L")
    if "upper_arm" in n:
        return "UpperArm" + (side or ".L")
    if "foot" in n or "toe" in n:
        return "Foot" + (side or ".L")
    if "shin" in n or "kneepad" in n:
        return "Shin" + (side or ".L")
    if "thigh" in n:
        return "Thigh" + (side or ".L")
    if "pelvis" in n or "butt" in n or "asp-cloth" in n or n == "def-spine":
        return "Hips"
    if "spine.006" in n or any(k in n for k in ["brow", "cheek", "chin", "ear", "forehead", "jaw", "lid", "lip", "nose", "temple", "head"]):
        return "Head"
    if "spine.004" in n or "spine.005" in n:
        return "Neck"
    if "spine.003" in n or "breast" in n or "wing" in n or "back" in n:
        return "Chest"
    if "spine.001" in n or "spine.002" in n:
        return "Spine"
    return default_bone


def remap_rigify_weights(obj: bpy.types.Object, clean_bone_names: set[str], rigid_bone: str | None = None):
    me = obj.data
    n_verts = len(me.vertices)
    if n_verts == 0:
        return
    if rigid_bone is not None:
        obj.vertex_groups.clear()
        nvg = obj.vertex_groups.new(name=rigid_bone)
        nvg.add(list(range(n_verts)), 1.0, "REPLACE")
        return

    on_l = obj.name.lower()
    if "head" in on_l or "helmet" in on_l or "crown" in on_l or "wires" in on_l or "chinstrap" in on_l:
        obj.vertex_groups.clear()
        nvg = obj.vertex_groups.new(name="Head")
        nvg.add(list(range(n_verts)), 1.0, "REPLACE")
        return
    if "jetpack" in on_l or "back-wings" in on_l:
        obj.vertex_groups.clear()
        nvg = obj.vertex_groups.new(name="Chest")
        nvg.add(list(range(n_verts)), 1.0, "REPLACE")
        return

    default_bone = "Chest"
    if "legs" in on_l:
        default_bone = "Hips"
    elif "forearm.l" in on_l:
        default_bone = "ForeArm.L"
    elif "forearm.r" in on_l:
        default_bone = "ForeArm.R"

    accum: dict[str, np.ndarray] = {}
    idx_to_target: dict[int, str] = {}
    for vg in obj.vertex_groups:
        tgt = map_rigify_vg(vg.name, default_bone=default_bone)
        if tgt is None:
            continue
        if tgt not in clean_bone_names:
            tgt = default_bone
        idx_to_target[vg.index] = tgt
        if tgt not in accum:
            accum[tgt] = np.zeros(n_verts, dtype=np.float32)

    for v in me.vertices:
        vi = v.index
        for g in v.groups:
            tgt = idx_to_target.get(g.group)
            if tgt is not None and g.weight > 1e-5:
                accum[tgt][vi] += g.weight

    total = np.zeros(n_verts, dtype=np.float32)
    for arr in accum.values():
        total += arr
    unweighted = np.where(total < 1e-4)[0]
    if len(unweighted) > 0:
        if default_bone not in accum:
            accum[default_bone] = np.zeros(n_verts, dtype=np.float32)
        accum[default_bone][unweighted] = 1.0
        total[unweighted] = 1.0

    obj.vertex_groups.clear()
    for bname, arr in accum.items():
        nz = np.where(arr > 1e-4)[0]
        if len(nz) == 0:
            continue
        nvg = obj.vertex_groups.new(name=bname)
        for vi in nz:
            nvg.add([int(vi)], float(arr[vi] / total[vi]), "REPLACE")


def set_world_rot_delta(pb: bpy.types.PoseBone, arm_obj: bpy.types.Object, world_axis: tuple[float, float, float], angle_deg: float):
    q_world = Quaternion(Vector(world_axis).normalized(), math.radians(angle_deg))
    rest_rot = (arm_obj.matrix_world.to_3x3() @ pb.bone.matrix_local.to_3x3()).to_quaternion()
    q_local = rest_rot.inverted() @ q_world @ rest_rot
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = q_local @ pb.rotation_quaternion


def build_clean_19_skeleton(src_arm: bpy.types.Object, scale: float, z_shift: float, arm_name: str) -> bpy.types.Object:
    def bh(bname: str, fb: Vector) -> Vector:
        b = src_arm.data.bones.get(bname)
        p = (src_arm.matrix_world @ b.head_local) if b is not None else fb.copy()
        return Vector((p.x * scale, p.y * scale, (p.z + z_shift) * scale))

    p_hips = bh("DEF-spine", Vector((0, 0.05, 0.96)))
    p_spine = bh("DEF-spine.001", Vector((0, 0.01, 1.14)))
    p_chest = bh("DEF-spine.003", Vector((0, 0.03, 1.37)))
    p_neck = bh("DEF-spine.004", Vector((0, 0.07, 1.46)))
    p_head = bh("DEF-spine.006", Vector((0, 0.04, 1.65)))
    p_head_top = p_head + Vector((0, 0, 0.22 * scale))

    p_sh_l = bh("DEF-shoulder.L", Vector((0.02, 0.03, 1.51)))
    p_ua_l = bh("DEF-upper_arm.L", Vector((0.17, 0.05, 1.51)))
    p_fa_l = bh("DEF-forearm.L", Vector((0.43, 0.03, 1.50)))
    p_ha_l = bh("DEF-hand.L", Vector((0.66, -0.03, 1.50)))
    p_ht_l = p_ha_l + Vector((0.12 * scale, 0, 0))

    p_sh_r = bh("DEF-shoulder.R", Vector((-0.03, 0.03, 1.51)))
    p_ua_r = bh("DEF-upper_arm.R", Vector((-0.18, 0.05, 1.51)))
    p_fa_r = bh("DEF-forearm.R", Vector((-0.44, 0.03, 1.50)))
    p_ha_r = bh("DEF-hand.R", Vector((-0.67, -0.03, 1.50)))
    p_ht_r = p_ha_r + Vector((-0.12 * scale, 0, 0))

    p_th_l = bh("DEF-thigh.L", Vector((0.09, 0.02, 1.01)))
    p_kn_l = bh("DEF-shin.L", Vector((0.10, 0.01, 0.57)))
    p_ft_l = bh("DEF-foot.L", Vector((0.11, 0.05, 0.11)))
    p_tt_l = bh("DEF-toe.L", Vector((0.13, -0.06, 0.05)))

    p_th_r = bh("DEF-thigh.R", Vector((-0.10, 0.02, 1.01)))
    p_kn_r = bh("DEF-shin.R", Vector((-0.11, 0.01, 0.57)))
    p_ft_r = bh("DEF-foot.R", Vector((-0.12, 0.05, 0.11)))
    p_tt_r = bh("DEF-toe.R", Vector((-0.14, -0.06, 0.05)))

    arm_data = bpy.data.armatures.new(arm_name + "_Data")
    arm_obj = bpy.data.objects.new(arm_name, arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    specs = [
        ("Hips", None, p_hips, p_spine),
        ("Spine", "Hips", p_spine, p_chest),
        ("Chest", "Spine", p_chest, p_neck),
        ("Neck", "Chest", p_neck, p_head),
        ("Head", "Neck", p_head, p_head_top),
        ("Shoulder.L", "Chest", p_sh_l, p_ua_l),
        ("UpperArm.L", "Shoulder.L", p_ua_l, p_fa_l),
        ("ForeArm.L", "UpperArm.L", p_fa_l, p_ha_l),
        ("Hand.L", "ForeArm.L", p_ha_l, p_ht_l),
        ("Shoulder.R", "Chest", p_sh_r, p_ua_r),
        ("UpperArm.R", "Shoulder.R", p_ua_r, p_fa_r),
        ("ForeArm.R", "UpperArm.R", p_fa_r, p_ha_r),
        ("Hand.R", "ForeArm.R", p_ha_r, p_ht_r),
        ("Thigh.L", "Hips", p_th_l, p_kn_l),
        ("Shin.L", "Thigh.L", p_kn_l, p_ft_l),
        ("Foot.L", "Shin.L", p_ft_l, p_tt_l),
        ("Thigh.R", "Hips", p_th_r, p_kn_r),
        ("Shin.R", "Thigh.R", p_kn_r, p_ft_r),
        ("Foot.R", "Shin.R", p_ft_r, p_tt_r),
    ]
    created = {}
    for bname, parent_n, h_co, t_co in specs:
        b = eb.new(bname)
        b.head = h_co
        b.tail = t_co if (t_co - h_co).length > 0.02 else (h_co + Vector((0, 0, 0.1)))
        if parent_n:
            b.parent = created[parent_n]
            b.use_connect = False
        created[bname] = b

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def pose_tactical_stance(arm_obj: bpy.types.Object, style: str, phase: float, gait_amp: float = 0.0, run_lean: float = 0.0):
    """Apply clean world-space tactical combat pose on T-pose skeleton (+X left, -X right, -Y forward)."""
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = Vector((0, 0, 0))

    breath = math.sin(phase * 2.0)
    sway = math.sin(phase)
    stride = math.sin(phase) * gait_amp
    opp_stride = -stride

    # Base torso breathing & tactical forward lean
    set_world_rot_delta(arm_obj.pose.bones["Spine"], arm_obj, (1, 0, 0), -(2.5 + run_lean) + breath * 1.2)
    set_world_rot_delta(arm_obj.pose.bones["Chest"], arm_obj, (1, 0, 0), -(1.5 + run_lean * 0.5) + breath * 1.5)
    set_world_rot_delta(arm_obj.pose.bones["Spine"], arm_obj, (0, 0, 1), sway * (2.0 + gait_amp * 5.0))
    set_world_rot_delta(arm_obj.pose.bones["Head"], arm_obj, (0, 0, 1), -sway * (2.5 + gait_amp * 3.0))
    set_world_rot_delta(arm_obj.pose.bones["Head"], arm_obj, (1, 0, 0), (2.0 + run_lean * 0.7))

    if style == "overlord_blades":
        # Heroic menacing twin-blade colossus stance: forearms flared outward-forward so golden energy glaives frame chest/flanks!
        set_world_rot_delta(arm_obj.pose.bones["Shoulder.L"], arm_obj, (0, 1, 0), 6.0 + breath * 1.5)
        set_world_rot_delta(arm_obj.pose.bones["Shoulder.R"], arm_obj, (0, 1, 0), -6.0 - breath * 1.5)
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.L"], arm_obj, (0, 1, 0), 32.0 + breath * 2.0)
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.L"], arm_obj, (0, 0, 1), -(28.0 + opp_stride * 16.0))
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.L"], arm_obj, (0, 0, 1), -36.0)
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.L"], arm_obj, (1, 0, 0), 28.0)

        set_world_rot_delta(arm_obj.pose.bones["UpperArm.R"], arm_obj, (0, 1, 0), -32.0 - breath * 2.0)
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.R"], arm_obj, (0, 0, 1), (28.0 + stride * 16.0))
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.R"], arm_obj, (0, 0, 1), 36.0)
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.R"], arm_obj, (1, 0, 0), 28.0)
    else:
        # Two-handed tactical rifle / heavy cannon combat ready stance!
        # Right arm grips weapon stock/receiver angled forward along -Y; left arm supports foregrip!
        set_world_rot_delta(arm_obj.pose.bones["Shoulder.R"], arm_obj, (0, 1, 0), -8.0)
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.R"], arm_obj, (0, 1, 0), -58.0 + breath * 1.2)
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.R"], arm_obj, (0, 0, 1), 46.0 + stride * 6.0)
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.R"], arm_obj, (0, 0, 1), 44.0)
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.R"], arm_obj, (1, 0, 0), 14.0)

        set_world_rot_delta(arm_obj.pose.bones["Shoulder.L"], arm_obj, (0, 1, 0), 10.0)
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.L"], arm_obj, (0, 1, 0), 54.0 - breath * 1.2)
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.L"], arm_obj, (0, 0, 1), -64.0 + opp_stride * 6.0)
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.L"], arm_obj, (0, 0, 1), -52.0)
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.L"], arm_obj, (1, 0, 0), 16.0)

    # Legs: BOTH boots solidly planted on ground in Idle_Aim, crisp knee-lift stride in Walk/Run!
    if gait_amp < 0.01:
        set_world_rot_delta(arm_obj.pose.bones["Thigh.L"], arm_obj, (0, 1, 0), -2.5)
        set_world_rot_delta(arm_obj.pose.bones["Thigh.R"], arm_obj, (0, 1, 0), 2.5)
    else:
        # Left leg forward (+X rot lifts leg toward -Y!)
        l_hip = stride * 28.0
        l_knee = -max(0.0, math.cos(phase)) * gait_amp * 34.0 - 8.0
        r_hip = opp_stride * 28.0
        r_knee = -max(0.0, -math.cos(phase)) * gait_amp * 34.0 - 8.0
        set_world_rot_delta(arm_obj.pose.bones["Thigh.L"], arm_obj, (1, 0, 0), l_hip)
        set_world_rot_delta(arm_obj.pose.bones["Shin.L"], arm_obj, (1, 0, 0), l_knee)
        set_world_rot_delta(arm_obj.pose.bones["Foot.L"], arm_obj, (1, 0, 0), -l_hip * 0.35 - l_knee * 0.35)
        set_world_rot_delta(arm_obj.pose.bones["Thigh.R"], arm_obj, (1, 0, 0), r_hip)
        set_world_rot_delta(arm_obj.pose.bones["Shin.R"], arm_obj, (1, 0, 0), r_knee)
        set_world_rot_delta(arm_obj.pose.bones["Foot.R"], arm_obj, (1, 0, 0), -r_hip * 0.35 - r_knee * 0.35)


def bake_combat_clips(arm_obj: bpy.types.Object, style: str):
    """Bake seamless Idle_Aim, Walk_Patrol, and Run_Advance NLA strips cleanly."""
    bpy.context.scene.render.fps = 24
    arm_obj.animation_data_create()
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")

    clips = [
        ("Idle_Aim", 48, 0.0, 0.0),
        ("Walk_Patrol", 24, 0.72, 4.0),
        ("Run_Advance", 16, 1.12, 10.0),
    ]
    for clip_name, n_frames, gait_amp, run_lean in clips:
        act = bpy.data.actions.new(name=clip_name)
        arm_obj.animation_data.action = act
        step = max(2, n_frames // 8)
        frames = list(range(0, n_frames, step)) + [n_frames]
        for f in frames:
            bpy.context.scene.frame_set(f)
            phase = (f / float(n_frames)) * math.tau
            pose_tactical_stance(arm_obj, style, phase, gait_amp=gait_amp, run_lean=run_lean)
            for pb in arm_obj.pose.bones:
                pb.keyframe_insert(data_path="rotation_quaternion", frame=f)
        track = arm_obj.animation_data.nla_tracks.new()
        track.name = clip_name
        strip = track.strips.new(clip_name, 0, act)
        strip.action_frame_start = 0
        strip.action_frame_end = n_frames
        track.mute = True
        arm_obj.animation_data.action = None

    bpy.ops.object.mode_set(mode="OBJECT")


def create_dharma_halo_mesh(name: str, radius: float, mat_gold: bpy.types.Material, mat_glow: bpy.types.Material) -> bpy.types.Object:
    """Build sculpted glowing golden Dharma Gear Halo Ring ('overlord_halo_ring') centered at local origin in X-Z plane."""
    bm = bmesh.new()
    # Main octagonal/24-seg gear ring
    n_seg = 24
    r_in = radius * 0.80
    r_out = radius
    half_t = radius * 0.075
    ring_verts_f = []
    ring_verts_b = []
    for i in range(n_seg):
        a = (i / float(n_seg)) * math.tau
        ca, sa = math.cos(a), math.sin(a)
        v_fi = bm.verts.new((ca * r_in, -half_t, sa * r_in))
        v_fo = bm.verts.new((ca * r_out, -half_t, sa * r_out))
        v_bi = bm.verts.new((ca * r_in, half_t, sa * r_in))
        v_bo = bm.verts.new((ca * r_out, half_t, sa * r_out))
        ring_verts_f.append((v_fi, v_fo))
        ring_verts_b.append((v_bi, v_bo))
    for i in range(n_seg):
        j = (i + 1) % n_seg
        fi0, fo0 = ring_verts_f[i]; fi1, fo1 = ring_verts_f[j]
        bi0, bo0 = ring_verts_b[i]; bi1, bo1 = ring_verts_b[j]
        bm.faces.new((fi0, fo0, fo1, fi1))
        bm.faces.new((bo0, bi0, bi1, bo1))
        bm.faces.new((fo0, bo0, bo1, fo1))
        bm.faces.new((bi0, fi0, fi1, bi1))

    # 8 radial gear teeth around the halo perimeter
    for k in range(8):
        ang = (k / 8.0) * math.tau
        rot = Matrix.Rotation(ang, 4, "Y")
        res = bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(radius * 0.22, half_t * 2.2, radius * 0.24), verts=res["verts"])
        bmesh.ops.translate(bm, vec=(0.0, 0.0, radius * 1.07), verts=res["verts"])
        bmesh.ops.transform(bm, matrix=rot, verts=res["verts"])

    # Assign clean UV coordinates to all loops so missing_uv0 == 0!
    # Main sculpted gear body = gleaming antique metallic gold (mat 0); inner bevel ring = subtle amber-gold glow (mat 1)!
    uv_lay = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        c = f.calc_center_median()
        dist = math.hypot(c.x, c.z)
        f.material_index = 1 if dist < (r_in + (r_out - r_in) * 0.28) else 0
        for l in f.loops:
            l[uv_lay].uv = (l.vert.co.x * 0.5 + 0.5, l.vert.co.z * 0.5 + 0.5)

    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat_gold)
    me.materials.append(mat_glow)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def create_energy_blade_mesh(name: str, length: float, side_sign: float, mat_obs: bpy.types.Material, mat_glow: bpy.types.Material) -> bpy.types.Object:
    """Create sleek obsidian-and-gold forearm energy glaive blade for Skyfall Overlord."""
    bm = bmesh.new()
    # Blade spine (along +X for Left / -X for Right in T-pose forearm space, offset slightly outside wrist!)
    w = length * 0.14
    t = length * 0.045
    pts = [
        (0.0, -w * 0.6, 0.0),
        (length * 0.72, -w, 0.0),
        (length, 0.0, 0.0),
        (length * 0.72, w * 0.7, 0.0),
        (0.0, w * 0.4, 0.0),
    ]
    top_v = [bm.verts.new((side_sign * x, y, t)) for x, y, _ in pts]
    bot_v = [bm.verts.new((side_sign * x, y, -t)) for x, y, _ in pts]
    tip = bm.verts.new((side_sign * length * 1.12, -w * 0.15, 0.0))
    bm.faces.new(top_v if side_sign > 0 else list(reversed(top_v)))
    bm.faces.new(list(reversed(bot_v)) if side_sign > 0 else bot_v)
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((top_v[i], bot_v[i], bot_v[j], top_v[j]))
    bm.faces.new((top_v[1], top_v[2], tip))
    bm.faces.new((bot_v[2], bot_v[1], tip))
    bm.faces.new((top_v[2], top_v[3], tip))
    bm.faces.new((bot_v[3], bot_v[2], tip))

    uv_lay = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        f.material_index = 1 if abs(f.calc_center_median().x) > length * 0.45 else 0
        for l in f.loops:
            l[uv_lay].uv = (abs(l.vert.co.x) / max(0.01, length), l.vert.co.y / max(0.01, w) * 0.5 + 0.5)

    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat_obs)
    me.materials.append(mat_glow)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def create_chest_core_mesh(name: str, pos: Vector, radius: float, mat_frame: bpy.types.Material, mat_glow: bpy.types.Material) -> bpy.types.Object:
    """Create sleek recessed glowing hexagonal chest core flush on boss cuirass."""
    bm = bmesh.new()
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=radius, radius2=radius * 0.86, depth=radius * 0.36)
    bmesh.ops.rotate(bm, matrix=Matrix.Rotation(math.radians(90.0), 3, "X"), verts=res["verts"])
    bmesh.ops.translate(bm, vec=pos, verts=res["verts"])
    uv_lay = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        f.material_index = 1 if f.normal.y < -0.5 else 0
        for l in f.loops:
            l[uv_lay].uv = (0.5, 0.5)
    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat_frame)
    me.materials.append(mat_glow)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def create_face_armored_mask(name: str, head_pos: Vector, scale: float, mat_dark: bpy.types.Material) -> bpy.types.Object:
    """Sleek angular stealth-faceted armored lower-face respirator jawplate beneath visor (ZERO round sphere chin!)."""
    bm = bmesh.new()
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    bmesh.ops.scale(bm, vec=(0.115 * scale, 0.110 * scale, 0.105 * scale), verts=verts)
    for v in verts:
        # Taper downward cleanly toward angular tactical chin & sweep front nose-bridge slightly forward
        if v.co.z < 0:
            v.co.x *= 0.62
            v.co.y *= 0.85
        if v.co.y < 0:
            v.co.x *= 0.78
            v.co.y -= 0.014 * scale
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.014 * scale, segments=1, affect="EDGES")
    bmesh.ops.translate(bm, vec=head_pos + Vector((0.0, -0.044 * scale, -0.008 * scale)), verts=bm.verts[:])
    uv_lay = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for l in f.loops:
            l[uv_lay].uv = (0.5, 0.5)
    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat_dark)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render_unit_preview_and_portrait(
    arm_obj: bpy.types.Object,
    height: float,
    preview_path: Path | None,
    portrait_path: Path | None,
    key_col: tuple[float, float, float],
    rim_col: tuple[float, float, float],
    style: str,
):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0

    # Disable NLA while posing heroic Idle_Aim so Run_Advance NEVER lifts the left boot!
    if arm_obj.animation_data:
        arm_obj.animation_data.use_nla = False
        arm_obj.animation_data.action = None
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    pose_tactical_stance(arm_obj, style, phase=0.4, gait_amp=0.0, run_lean=0.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()

    w = bpy.data.worlds.new("StudioW")
    sc.world = w
    w.use_nodes = True
    wnt = w.node_tree
    wnt.nodes.clear()
    wbg = wnt.nodes.new("ShaderNodeBackground")
    wbg.inputs[0].default_value = (0.20, 0.24, 0.30, 1.0)
    wbg.inputs[1].default_value = 0.95
    wout = wnt.nodes.new("ShaderNodeOutputWorld")
    wnt.links.new(wbg.outputs[0], wout.inputs[0])

    lights = []
    for ln, en, col, rot in [
        ("Key", 2.9, key_col, (36, 0, -26)),
        ("Fill", 1.35, (0.78, 0.88, 1.0), (24, 0, 128)),
        ("Rim", 2.0, rim_col, (32, 0, 162)),
    ]:
        ld = bpy.data.lights.new(ln, "SUN")
        ld.energy = en
        ld.color = col
        lo = bpy.data.objects.new(ln, ld)
        sc.collection.objects.link(lo)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        lights.append(lo)

    cd = bpy.data.cameras.new("SCam")
    cam = bpy.data.objects.new("SCam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam

    if preview_path is not None:
        preview_path.parent.mkdir(parents=True, exist_ok=True)
        sc.render.resolution_x = 640
        sc.render.resolution_y = 800
        sc.render.film_transparent = False
        sc.render.image_settings.color_mode = "RGB"
        cd.lens = 56.0
        cam.location = Vector((0.36 * height, -2.18 * height, 0.56 * height))
        cam.rotation_euler = (Vector((0, 0, 0.52 * height)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = str(preview_path)
        bpy.ops.render.render(write_still=True)
        print(f"PREVIEW_SAVED {preview_path}")

    if portrait_path is not None:
        portrait_path.parent.mkdir(parents=True, exist_ok=True)
        sc.render.resolution_x = 1024
        sc.render.resolution_y = 1280
        sc.render.film_transparent = True
        sc.render.image_settings.file_format = "PNG"
        sc.render.image_settings.color_mode = "RGBA"
        cd.lens = 74.0
        # Generous bust framing with full helmet/horns/halo headroom matching Lore Codex 4:5 cards!
        if style == "overlord_blades":
            cam.location = Vector((0.26 * height, -1.24 * height, 0.72 * height))
            cam.rotation_euler = (Vector((0, 0, 0.68 * height)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        else:
            cam.location = Vector((0.28 * height, -1.36 * height, 0.86 * height))
            cam.rotation_euler = (Vector((0, 0, 0.81 * height)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = str(portrait_path)
        bpy.ops.render.render(write_still=True)
        print(f"PORTRAIT_FG_SAVED {portrait_path}")

    # Reset pose to identity & re-enable NLA strips before glTF export so all 3 clips export cleanly!
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm_obj.pose.bones:
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
    bpy.ops.object.mode_set(mode="OBJECT")
    if arm_obj.animation_data:
        arm_obj.animation_data.use_nla = True
    for o in lights + [cam]:
        bpy.data.objects.remove(o, do_unlink=True)


def build_unit(source_blend: Path, spec: dict, preview_dir: Path | None, portrait_dir: Path | None):
    bpy.ops.wm.open_mainfile(filepath=str(source_blend))
    tmp_dir = Path(tempfile.mkdtemp(prefix=f"v0996_{spec['id']}_"))

    src_arm = bpy.data.objects.get("rig.pharah")
    if src_arm is None:
        raise RuntimeError("rig.pharah not found in source blend!")
    src_arm.data.pose_position = "REST"
    bpy.context.view_layer.update()

    # Keep ONLY explicit SFW armored allowlist meshes
    kept_meshes: list[bpy.types.Object] = []
    for mn in spec["meshes"]:
        o = bpy.data.objects.get(mn)
        if o is not None and o.type == "MESH":
            o.hide_viewport = False
            o.hide_render = False
            kept_meshes.append(o)

    # Compute exact boot-sole Z and helmet-crown Z strictly from legs & helmet/torso (ignore any parked off-body parts!)
    min_z, max_z = 1e9, -1e9
    valid_kept: list[bpy.types.Object] = []
    for o in kept_meshes:
        zs = [(o.matrix_world @ v.co).z for v in o.data.vertices]
        if not zs:
            continue
        oz_min, oz_max = min(zs), max(zs)
        # Skip any detached spare mesh parked below the floor (z_max < -0.25)
        if oz_max < -0.25:
            print(f"  SKIP_PARKED {o.name} z=[{oz_min:.3f},{oz_max:.3f}]")
            continue
        valid_kept.append(o)
        if "wings" in o.name.lower() or "jetpack" in o.name.lower() or "bodysuit" in o.name.lower():
            continue
        if oz_min > -0.30:
            min_z = min(min_z, oz_min)
        if oz_max < 2.60:
            max_z = max(max_z, oz_max)
    kept_meshes = valid_kept
    src_h = max(0.5, max_z - min_z)
    scale = spec["target_height"] / src_h
    z_shift = -min_z
    print(f"[{spec['id']}] kept={len(kept_meshes)} src_z=[{min_z:.3f},{max_z:.3f}] src_h={src_h:.3f} -> scale={scale:.3f} target={spec['target_height']:.2f}m")

    def need_img(name: str) -> bpy.types.Image:
        im = bpy.data.images.get(name)
        if im is None:
            raise RuntimeError(f"Missing image '{name}' in {source_blend}")
        return im

    # Build faction-calibrated PBR materials
    mat_map: dict[str, bpy.types.Material] = {}
    dark_body_img = bake_processed_image(need_img("ARMR--security-bodysuit__D.jpg"), f"{spec['id']}_BodySuit", 512, "sRGB", tmp_dir, mode="dark_bodysuit", fmt="JPEG")
    mat_undersuit = make_pbr_mat(f"Mat_{spec['id']}_Undersuit", albedo_img=dark_body_img, roughness=0.72, metallic=0.12)
    mat_visor = make_pbr_mat(
        f"Mat_{spec['id']}_Visor",
        base_color=spec["visor_rgba"],
        roughness=0.14,
        metallic=0.15,
        emission_rgba=spec["visor_rgba"],
        emission_strength=0.72 if spec["visor_rgba"][0] > 0.8 else 1.05,
    )
    mat_visor_edge = make_pbr_mat(f"Mat_{spec['id']}_VisorEdge", base_color=(0.11, 0.13, 0.16, 1.0), roughness=0.36, metallic=0.68)
    mat_core_glow = make_pbr_mat(
        f"Mat_{spec['id']}_ChestCore",
        base_color=spec["core_rgba"],
        roughness=0.14,
        metallic=0.10,
        emission_rgba=spec["core_rgba"],
        emission_strength=1.35,
    )

    if spec["id"] == "haavk_trooper":
        img_d = bake_processed_image(need_img("ARMR--security__D.jpg"), "Haavk_Armor_D", 1024, "sRGB", tmp_dir, mode="haavk_white", fmt="JPEG")
        img_n = bake_processed_image(need_img("ARMR--security__N.jpg"), "Haavk_Armor_N", 1024, "Non-Color", tmp_dir, fmt="JPEG")
        img_r = bake_processed_image(need_img("ARMR--security__R.jpg"), "Haavk_Armor_R", 512, "Non-Color", tmp_dir, fmt="JPEG")
        img_m = bake_processed_image(need_img("ARMR--security__M.jpg"), "Haavk_Armor_M", 512, "Non-Color", tmp_dir, fmt="JPEG")
        mat_main = make_pbr_mat("Mat_Haavk_Armor", img_d, img_n, img_r, img_m, normal_scale=0.75)
        img_pd = bake_processed_image(need_img("ARMR--security-pants__D.jpg"), "Haavk_Pants_D", 512, "sRGB", tmp_dir, mode="dark_bodysuit", fmt="JPEG")
        mat_pants = make_pbr_mat("Mat_Haavk_Pants", img_pd, img_n, roughness=0.74, metallic=0.08, normal_scale=0.60)
        mat_map = {
            "ARMR--security": mat_main,
            "ARMR--security__bodysuit": mat_undersuit,
            "OTFT--bodysuit": mat_undersuit,
            "OTFT--bodysuit__leather": mat_undersuit,
            "ARMR--security__pants": mat_pants,
            "ARMR--security_helmet-visor": mat_visor,
            "ARMR--security_helmet-visor-edge": mat_visor_edge,
        }
        img_wd = bake_processed_image(need_img("WEAP--security__D.jpg"), "Haavk_Weap_D", 512, "sRGB", tmp_dir, mode="haavk_white", fmt="JPEG")
        img_wn = bake_processed_image(need_img("WEAP--security__N.jpg"), "Haavk_Weap_N", 512, "Non-Color", tmp_dir, fmt="JPEG")
        mat_weap = make_pbr_mat("Mat_Haavk_Rifle", img_wd, img_wn, roughness=0.38, metallic=0.55, normal_scale=0.75)
    elif spec["id"] == "vanguard_boss":
        img_d = bake_processed_image(need_img("ARMR__asp-D.jpg"), "Vanguard_Armor_D", 1024, "sRGB", tmp_dir, mode="vanguard_obsidian_crimson", fmt="JPEG")
        img_n = bake_processed_image(need_img("ARMR__asp-N.jpg"), "Vanguard_Armor_N", 1024, "Non-Color", tmp_dir, fmt="JPEG")
        img_r = bake_processed_image(need_img("ARMR__asp-R.jpg"), "Vanguard_Armor_R", 512, "Non-Color", tmp_dir, fmt="JPEG")
        img_m = bake_processed_image(need_img("ARMR__asp-M.jpg"), "Vanguard_Armor_M", 512, "Non-Color", tmp_dir, fmt="JPEG")
        img_c = bake_processed_image(need_img("ARMR__asp-cloth-D.png"), "Vanguard_Cloth_D", 512, "sRGB", tmp_dir, mode="vanguard_tasset_cloth", fmt="JPEG")
        mat_main = make_pbr_mat("Mat_Vanguard_Armor", img_d, img_n, img_r, img_m, normal_scale=0.85)
        mat_cloth = make_pbr_mat("Mat_Vanguard_Cloth", img_c, roughness=0.82, metallic=0.05)
        mat_helm = make_pbr_mat("Mat_Vanguard_Helm", base_color=(0.14, 0.16, 0.19, 1.0), roughness=0.38, metallic=0.72)
        mat_map = {
            "ARMR--asp": mat_main,
            "ARMR--asp__jewel": mat_helm,
            "ARMR--asp__jewel-cloth": mat_cloth,
            "ARMR--security": mat_helm,
            "ARMR--security__bodysuit": mat_undersuit,
            "OTFT--bodysuit": mat_undersuit,
            "OTFT--bodysuit__leather": mat_undersuit,
            "ARMR--security_helmet-visor": mat_visor,
            "ARMR--security_helmet-visor-edge": mat_visor_edge,
        }
        img_wd = bake_processed_image(need_img("WEAP--asp__D.jpg"), "Vanguard_Weap_D", 512, "sRGB", tmp_dir, mode="vanguard_obsidian_crimson", fmt="JPEG")
        img_wn = bake_processed_image(need_img("WEAP--asp__N.jpg"), "Vanguard_Weap_N", 512, "Non-Color", tmp_dir, fmt="JPEG")
        mat_weap = make_pbr_mat("Mat_Vanguard_Cannon", img_wd, img_wn, roughness=0.35, metallic=0.68, normal_scale=0.80)
    else:  # skyfall_overlord
        img_d = bake_processed_image(need_img("ARMR__anubis-D.jpg"), "Overlord_Armor_D", 1024, "sRGB", tmp_dir, mode="overlord_obsidian_gold", fmt="JPEG")
        img_n = bake_processed_image(need_img("ARMR__anubis-N.jpg"), "Overlord_Armor_N", 1024, "Non-Color", tmp_dir, fmt="JPEG")
        img_r = bake_processed_image(need_img("ARMR__anubis-R.jpg"), "Overlord_Armor_R", 512, "Non-Color", tmp_dir, fmt="JPEG")
        img_m = bake_processed_image(need_img("ARMR__anubis-M.jpg"), "Overlord_Armor_M", 512, "Non-Color", tmp_dir, fmt="JPEG")
        img_hd = bake_processed_image(need_img("ARMR--helmet__anubis-D.jpg"), "Overlord_Helm_D", 1024, "sRGB", tmp_dir, mode="overlord_obsidian_gold", fmt="JPEG")
        img_hn = bake_processed_image(need_img("ARMR--helmet__anubis-N.jpg"), "Overlord_Helm_N", 1024, "Non-Color", tmp_dir, fmt="JPEG")
        img_hr = bake_processed_image(need_img("ARMR--helmet__anubis-R.jpg"), "Overlord_Helm_R", 512, "Non-Color", tmp_dir, fmt="JPEG")
        img_hm = bake_processed_image(need_img("ARMR--helmet__anubis-M.jpg"), "Overlord_Helm_M", 512, "Non-Color", tmp_dir, fmt="JPEG")
        mat_main = make_pbr_mat("Mat_Overlord_Armor", img_d, img_n, img_r, img_m, normal_scale=0.85)
        mat_helm = make_pbr_mat("Mat_Overlord_Helm", img_hd, img_hn, img_hr, img_hm, normal_scale=0.85)
        mat_map = {
            "ARMR--default": mat_main,
            "ARMR--jackal-helmet": mat_helm,
            "ARMR--security__bodysuit": mat_undersuit,
            "OTFT--bodysuit": mat_undersuit,
            "OTFT--bodysuit__leather": mat_undersuit,
            "ARMR--security": mat_helm,
            "ARMR--security_helmet-visor": mat_visor,
            "ARMR--security_helmet-visor-edge": mat_visor_edge,
        }
        mat_weap = None

    clean_arm = build_clean_19_skeleton(src_arm, scale, z_shift, spec["arm_name"])
    clean_bone_names = {b.name for b in clean_arm.data.bones}

    sc_col = bpy.context.scene.collection
    # Unlink kept meshes from hidden source collections & link straight into active root scene collection FIRST
    # so MIRROR/DECIMATE modifier_apply & glTF selection export 100% of all meshes cleanly!
    def move_to_root_col(obj: bpy.types.Object):
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        if obj.name not in sc_col.objects:
            sc_col.objects.link(obj)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.hide_select = False
        obj.hide_set(False)

    final_meshes: list[bpy.types.Object] = []
    for o in kept_meshes:
        orig_name = o.name
        move_to_root_col(o)
        if o.data.users > 1:
            o.data = o.data.copy()
        wm = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = wm
        if o.data.shape_keys is not None:
            o.shape_key_clear()
        # APPLY MIRROR modifiers FIRST (restores full symmetric chestplates & forearms!) while removing Armature/Mask/Subsurf!
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            if mod.type == "MIRROR":
                try:
                    bpy.ops.object.modifier_apply(modifier=mod.name)
                except Exception:
                    o.modifiers.remove(mod)
            else:
                o.modifiers.remove(mod)

        # Ground & scale into canonical meters (Z=0 at soles, facing -Y)
        xform = Matrix.Diagonal((scale, scale, scale, 1.0)) @ Matrix.Translation((0.0, 0.0, z_shift)) @ o.matrix_world
        o.data.transform(xform)
        o.matrix_world = Matrix.Identity(4)

        # Enforce single canonical UVMap (TEXCOORDS=['TEXCOORD_0'], missing_uv0=0)
        uvs = o.data.uv_layers
        if len(uvs) == 0:
            uvs.new(name="UVMap")
        else:
            uvs.active_index = 0
            uvs[0].name = "UVMap"
            while len(uvs) > 1:
                uvs.remove(uvs[-1])

        # Replace materials cleanly (force slot.link='DATA' + substring fallback so ZERO brown skin/bodysuit leaks!)
        for i in range(len(o.material_slots)):
            slot = o.material_slots[i]
            m = slot.material or (o.data.materials[i] if i < len(o.data.materials) else None)
            mname = m.name if m is not None else ""
            ml = mname.lower()
            if mname in mat_map:
                new_m = mat_map[mname]
            elif "visor-edge" in ml or "visor_edge" in ml:
                new_m = mat_visor_edge
            elif "visor" in ml:
                new_m = mat_visor
            elif "bodysuit" in ml or "skin" in ml or "body" in ml:
                new_m = mat_undersuit
            elif "pants" in ml and "ARMR--security__pants" in mat_map:
                new_m = mat_map["ARMR--security__pants"]
            elif "jewel" in ml and "ARMR--asp__jewel" in mat_map:
                new_m = mat_map["ARMR--asp__jewel"]
            else:
                new_m = mat_main
            slot.link = "DATA"
            o.data.materials[i] = new_m

        # Gentle decimate to keep real-time GLB super fast (~14k–22k polys per character!)
        ratio = spec.get("decimate", 0.55)
        if "helmet" in orig_name.lower() or "crown" in orig_name.lower():
            ratio = min(1.0, ratio + 0.25)
        if ratio < 0.98 and len(o.data.polygons) > 350:
            bpy.context.view_layer.objects.active = o
            dec = o.modifiers.new(name="Dec", type="DECIMATE")
            dec.decimate_type = "COLLAPSE"
            dec.ratio = ratio
            bpy.ops.object.modifier_apply(modifier=dec.name)

        remap_rigify_weights(o, clean_bone_names)
        final_meshes.append(o)

    # Optional Weapon attachment for HAAVK Trooper & Vanguard Boss (bound rigidly to Hand.R!)
    if spec.get("weapon_obj") and mat_weap is not None:
        wo = bpy.data.objects.get(spec["weapon_obj"])
        if wo is not None and wo.type == "MESH":
            move_to_root_col(wo)
            if wo.data.users > 1:
                wo.data = wo.data.copy()
            wm = wo.matrix_world.copy()
            wo.parent = None
            wo.matrix_world = wm
            for mod in list(wo.modifiers):
                wo.modifiers.remove(mod)
            if wo.data.shape_keys is not None:
                wo.shape_key_clear()
            wo.data.transform(wo.matrix_world)
            wo.matrix_world = Matrix.Identity(4)
            # Center weapon at origin, align longest barrel axis (+Z in source) along -Y (forward!), scale cleanly
            verts = [v.co for v in wo.data.vertices]
            cen = sum(verts, Vector((0, 0, 0))) / max(1, len(verts))
            wo.data.transform(Matrix.Translation(-cen))
            # Source Pharah launchers point along +Z (height ~0.65m); rotate -90 deg X so barrel aims along -Y (forward)!
            # In rest T-pose, Hand.R extends along -X; when Hand.R swings forward (+46+44 = +90 deg around +Z) & down (-58 deg around +Y),
            # a weapon aligned along local Hand.R axis needs to point in rest space along +X/-Y so in combat pose it aims straight forward!
            # Even cleaner: place weapon directly relative to Hand.R in rest pose computed via the EXACT inverse of Idle_Aim Hand.R transform!
            wlen = max(v.co.z for v in wo.data.vertices) - min(v.co.z for v in wo.data.vertices)
            w_sc = (spec["weapon_len"] / max(0.1, wlen))
            wo.data.transform(Matrix.Diagonal((w_sc, w_sc, w_sc, 1.0)))
            # Rotate so barrel aims cleanly forward-left across chest (awesome hero silhouette in both gameplay & portrait!)
            wo.data.transform(Matrix.Rotation(math.radians(-90.0), 4, "X"))
            yaw_deg = 36.0 if spec["id"] == "vanguard_boss" else 22.0
            wo.data.transform(Matrix.Rotation(math.radians(yaw_deg), 4, "Z"))
            # Single UVMap & material
            uvs = wo.data.uv_layers
            if len(uvs) == 0:
                uvs.new(name="UVMap")
            else:
                uvs.active_index = 0
                uvs[0].name = "UVMap"
                while len(uvs) > 1:
                    uvs.remove(uvs[-1])
            wo.data.materials.clear()
            wo.data.materials.append(mat_weap)
            if len(wo.data.polygons) > 1800:
                bpy.context.view_layer.objects.active = wo
                dec = wo.modifiers.new(name="Dec", type="DECIMATE")
                dec.decimate_type = "COLLAPSE"
                dec.ratio = 0.28
                bpy.ops.object.modifier_apply(modifier=dec.name)
            wo.name = f"{spec['id']}_Weapon"
            # Compute exact inverse of Idle_Aim Hand.R world matrix so weapon sits squarely aimed forward at chest height in Idle_Aim!
            bpy.context.view_layer.objects.active = clean_arm
            bpy.ops.object.mode_set(mode="POSE")
            pose_tactical_stance(clean_arm, spec["style"], phase=0.0, gait_amp=0.0, run_lean=0.0)
            bpy.context.view_layer.update()
            pb_hr = clean_arm.pose.bones["Hand.R"]
            m_posed = clean_arm.matrix_world @ pb_hr.matrix
            m_rest = clean_arm.matrix_world @ pb_hr.bone.matrix_local
            delta_m = m_posed @ m_rest.inverted()
            # Desired posed world position of weapon: right in front of posed Hand.R aiming straight forward (-Y)!
            # Keep Vanguard heavy cannon carried slightly lower across hip/lower-chest so glowing ChestCore shines unobstructed!
            hand_pos_posed = (m_posed @ Vector((0, 0, 0)))
            z_off = -0.105 * scale if spec["id"] == "vanguard_boss" else -0.02 * scale
            desired_wpos = Vector((hand_pos_posed.x + 0.04 * scale, hand_pos_posed.y - 0.14 * scale, hand_pos_posed.z + z_off))
            wo.data.transform(Matrix.Translation(desired_wpos))
            # Transform back into rest space so skinning 100% to Hand.R brings it EXACTLY to desired_wpos when posed!
            wo.data.transform(delta_m.inverted())
            for pb in clean_arm.pose.bones:
                pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
            bpy.ops.object.mode_set(mode="OBJECT")
            remap_rigify_weights(wo, clean_bone_names, rigid_bone="Hand.R")
            final_meshes.append(wo)

    # Sealed dark armored lower-face respirator plate (replaces exposed lips under helmet visor -> 100% armored tactical knight/trooper!)
    head_bone_pos = clean_arm.data.bones["Head"].head_local
    mask_obj = create_face_armored_mask(f"{spec['id']}_FacePlate", head_bone_pos, scale, mat_visor_edge)
    remap_rigify_weights(mask_obj, clean_bone_names, rigid_bone="Head")
    final_meshes.append(mask_obj)

    # Special boss attachments!
    extra_static_nodes: list[bpy.types.Object] = []
    if spec["id"] == "vanguard_boss":
        core_obj = create_chest_core_mesh(
            "Vanguard_ChestCore",
            Vector((0.0, -0.175 * scale, 1.38 * scale)),
            0.068 * scale,
            mat_visor_edge,
            mat_core_glow,
        )
        remap_rigify_weights(core_obj, clean_bone_names, rigid_bone="Chest")
        final_meshes.append(core_obj)

    if spec["id"] == "skyfall_overlord":
        # Glowing chest core + Twin obsidian-gold forearm energy blades + Spinning Golden Dharma Halo Ring!
        core_obj = create_chest_core_mesh(
            "Overlord_ChestCore",
            Vector((0.0, -0.185 * scale, 1.39 * scale)),
            0.072 * scale,
            mat_visor_edge,
            mat_core_glow,
        )
        remap_rigify_weights(core_obj, clean_bone_names, rigid_bone="Chest")
        final_meshes.append(core_obj)

        mat_obs_blade = make_pbr_mat("Mat_Overlord_BladeMetal", base_color=(0.09, 0.10, 0.13, 1.0), roughness=0.24, metallic=0.88)
        mat_gold_glow = make_pbr_mat("Mat_Overlord_GoldGlow", base_color=(1.0, 0.68, 0.14, 1.0), roughness=0.18, metallic=0.72, emission_rgba=(1.0, 0.62, 0.08, 1.0), emission_strength=1.25)

        for side_lbl, sgn, bname in [("L", 1.0, "ForeArm.L"), ("R", -1.0, "ForeArm.R")]:
            b_rest = clean_arm.data.bones[bname]
            anchor = b_rest.head_local.lerp(b_rest.tail_local, 0.55)
            bl = create_energy_blade_mesh(f"Overlord_Blade_{side_lbl}", 0.56 * scale, sgn, mat_obs_blade, mat_gold_glow)
            bl.data.transform(Matrix.Translation(anchor + Vector((0.0, -0.05 * scale, -0.04 * scale))))
            remap_rigify_weights(bl, clean_bone_names, rigid_bone=bname)
            final_meshes.append(bl)

        # Articulated unskinned 'overlord_halo_ring' hovering cleanly behind upper back so word_soldier.gd spins ov_halo.rotation.z!
        mat_gold_ring = make_pbr_mat("Mat_Overlord_HaloMetal", base_color=(0.88, 0.64, 0.18, 1.0), roughness=0.26, metallic=0.88)
        halo = create_dharma_halo_mesh("overlord_halo_ring", 0.38 * scale, mat_gold_ring, mat_gold_glow)
        halo.location = Vector((0.0, 0.34 * scale, 1.66 * scale))
        extra_static_nodes.append(halo)

    # Purge all unrelated objects from scene (keeps file 100% SFW, tiny, and clean!)
    keep_set = set(final_meshes) | set(extra_static_nodes) | {clean_arm}
    for o in list(bpy.data.objects):
        if o not in keep_set:
            bpy.data.objects.remove(o, do_unlink=True)

    sc_col = bpy.context.scene.collection
    if clean_arm.name not in sc_col.objects:
        sc_col.objects.link(clean_arm)
    for o in final_meshes:
        if o.name not in sc_col.objects:
            sc_col.objects.link(o)
        o.parent = clean_arm
        amod = o.modifiers.new(name="Armature", type="ARMATURE")
        amod.object = clean_arm
        for p in o.data.polygons:
            p.use_smooth = True
    for o in extra_static_nodes:
        if o.name not in sc_col.objects:
            sc_col.objects.link(o)

    # Purge all source Actions before baking ONLY our 3 clean clips!
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act, do_unlink=True)
    bake_combat_clips(clean_arm, spec["style"])

    # Render preview & transparent studio portrait foreground
    if preview_dir or portrait_dir:
        render_unit_preview_and_portrait(
            clean_arm,
            spec["target_height"],
            (preview_dir / f"{spec['id']}_preview.png") if preview_dir else None,
            (portrait_dir / f"{spec['portrait_id']}_fg.png") if portrait_dir else None,
            spec["key_col"],
            spec["rim_col"],
            spec["style"],
        )

    # Export clean GLB (use_selection=False since ALL non-kept objects were purged from the scene!)
    bpy.ops.object.select_all(action="DESELECT")
    clean_arm.hide_select = False
    clean_arm.select_set(True)
    for o in final_meshes + extra_static_nodes:
        o.hide_select = False
        o.select_set(True)
    bpy.context.view_layer.objects.active = clean_arm

    out_glb = SLICE_DIR / spec["glb_name"]
    out_glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
        export_format="GLB",
        use_selection=False,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_skins=True,
        export_animations=True,
        export_nla_strips=True,
        export_bake_animation=True,
        export_def_bones=False,
    )

    raw = out_glb.read_bytes()
    jlen = struct.unpack("<I", raw[12:16])[0]
    g = json.loads(raw[20 : 20 + jlen])
    bin_off = 20 + jlen + 8
    bad_imgs = []
    for im_i, im_d in enumerate(g.get("images", [])):
        bv = g["bufferViews"][im_d["bufferView"]]
        hdr = raw[bin_off + bv.get("byteOffset", 0) : bin_off + bv.get("byteOffset", 0) + 8]
        if im_d.get("mimeType") != "image/png" or hdr != b"\x89PNG\r\n\x1a\n":
            bad_imgs.append((im_d.get("name"), im_d.get("mimeType"), hdr))
    assert not bad_imgs, f"Invalid embedded PNG images in {out_glb.name}: {bad_imgs}"
    polys = sum(len(o.data.polygons) for o in final_meshes + extra_static_nodes)
    tcs = sorted({k for m in g.get("meshes", []) for pr in m.get("primitives", []) for k in pr.get("attributes", {}) if k.startswith("TEXCOORD")})
    miss = sum(1 for m in g.get("meshes", []) for pr in m.get("primitives", []) if "TEXCOORD_0" not in pr.get("attributes", {}))
    anims = [a.get("name") for a in g.get("animations", [])]
    print(f"EXPORTED {out_glb.name}: {len(raw)/1048576:.2f} MiB | {polys} polys | meshes={len(g.get('meshes', []))} | bones={len(clean_arm.data.bones)} | anims={anims} | TEXCOORDS={tcs} | missing_uv0={miss}")
    assert miss == 0 and tcs == ["TEXCOORD_0"], f"UV check failed on {out_glb.name}!"


SPECS = [
    {
        "id": "haavk_trooper",
        "portrait_id": "haavk_trooper",
        "glb_name": "v0996_haavk_trooper.glb",
        "arm_name": "Haavk_Armature",
        "target_height": 1.82,
        "decimate": 0.45,
        "style": "rifle",
        "visor_rgba": (0.21, 0.91, 1.0, 1.0),
        "core_rgba": (0.21, 0.91, 1.0, 1.0),
        "key_col": (0.98, 0.99, 1.0),
        "rim_col": (0.45, 0.92, 1.0),
        "weapon_obj": "WEAP--security",
        "weapon_len": 0.74,
        "meshes": [
            "ARMR--security__arms-forearm.R", "ARMR--security__arms-hands",
            "ARMR--security__arms-pauldrons", "ARMR--security__arms-upper", "ARMR--security__bodysuit",
            "ARMR--security__head-chinstrap", "ARMR--security__head-headgear", "ARMR--security__head-helmet",
            "ARMR--security__legs", "ARMR--security__legs-armor",
            "ARMR--security__torso", "ARMR--security__torso-chestpiece",
        ],
    },
    {
        "id": "vanguard_boss",
        "portrait_id": "vanguard_boss",
        "glb_name": "v0996_vanguard_boss.glb",
        "arm_name": "Vanguard_Armature",
        "target_height": 2.46,
        "decimate": 0.65,
        "style": "rifle",
        "visor_rgba": (0.95, 0.08, 0.08, 1.0),
        "core_rgba": (1.0, 0.18, 0.08, 1.0),
        "key_col": (1.0, 0.90, 0.80),
        "rim_col": (1.0, 0.32, 0.20),
        "weapon_obj": "WEAP--asp",
        "weapon_len": 1.12,
        "meshes": [
            "ARMR--asp__arms-forearm.L", "ARMR--asp__arms-forearm.R", "ARMR--asp__arms-hands",
            "ARMR--asp__arms-pauldrons", "ARMR--asp__arms-upper", "ARMR--asp__belt",
            "ARMR--asp__belt-jewel", "ARMR--asp__head-crown",
            "ARMR--asp__legs", "ARMR--asp__torso", "ARMR--asp__torso-chestpiece",
            "ARMR--security__bodysuit", "ARMR--security__head-helmet",
        ],
    },
    {
        "id": "skyfall_overlord",
        "portrait_id": "skyfall_overlord",
        "glb_name": "v0996_skyfall_overlord.glb",
        "arm_name": "Overlord_Armature",
        "target_height": 3.68,
        "decimate": 0.58,
        "style": "overlord_blades",
        "visor_rgba": (0.96, 0.06, 0.08, 1.0),
        "core_rgba": (1.0, 0.42, 0.08, 1.0),
        "key_col": (1.0, 0.94, 0.80),
        "rim_col": (1.0, 0.78, 0.28),
        "weapon_obj": None,
        "weapon_len": 0.0,
        "meshes": [
            "ARMR--default__arms-forearm.L", "ARMR--default__arms-forearm.R", "ARMR--default__arms-hands",
            "ARMR--default__arms-pauldrons", "ARMR--default__arms-upper", "ARMR--default__back-jetpack",
            "ARMR--default__back-wings", "ARMR--jackal__head-helmet", "ARMR--default__legs",
            "ARMR--default__torso", "ARMR--default__torso-chestpiece",
            "ARMR--security__bodysuit", "ARMR--security__head-helmet",
        ],
    },
]


def main():
    args = parse_args()
    src = Path(args.source)
    pdir = Path(args.preview) if args.preview else None
    fgdir = Path(args.portraits) if args.portraits else None
    only = {s.strip() for s in args.only.split(",") if s.strip()}
    for sp in SPECS:
        if only and sp["id"] not in only:
            continue
        build_unit(src, sp, pdir, fgdir)


if __name__ == "__main__":
    main()
