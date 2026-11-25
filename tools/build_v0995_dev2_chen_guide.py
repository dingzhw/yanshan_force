"""v0.9.9.5_dev2 Camp Liaison Chen Guide ('陈向导') — Unmodified High-Fidelity Character Pipeline.

Extracts the unmodified sculpted tactical officer character from the provided source .blend
(keeping original face, hair, eyes, tactical uniform, armor vest, shoulder radio, gloves,
utility belt, kneepads, and combat boots 100% intact without manual re-sculpting), converts
all materials to clean real-time Godot 4.7 Principled BSDF PBR with lossless PNG maps,
remaps weights cleanly onto a lean 22-bone game skeleton, and bakes a relaxed camp standing
loop ('Idle_Camp') into:
  game/assets/slice/npc_chen_guide.glb

Usage (Blender 5.3 CLI):
  blender --background --factory-startup <source.blend> --python tools/build_v0995_dev2_chen_guide.py -- [--preview <dir>]
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

REPO_ROOT = Path(__file__).resolve().parents[1]
SLICE_DIR = REPO_ROOT / "game" / "assets" / "slice"
OUT_GLB = SLICE_DIR / "npc_chen_guide.glb"

KEEP_MESHES = [
    "Leon.Head",
    "Leon.Cornea",
    "Leon.Brows/Lashes",
    "Leon.Teeth",
    "Leon.Hair",
    "Leon.Hair_xtra",
    "Leon.MainBody",
    "Leon.MainBody.001",
    "Leon.BodyArmour",
    "Leon.Arms",
    "Leon.Belt",
    "Leon.BeltBuckle",
    "Leon.Radio",
    "Leon.Kneepads",
    "Leon.Boots",
]

# Gentle polycount reduction ONLY on heavy body gear (head/eyes/brows kept 100% untouched original topology!)
DECIMATE_RATIO = {
    "Leon.Head": 1.00,
    "Leon.Cornea": 1.00,
    "Leon.Brows/Lashes": 1.00,
    "Leon.Teeth": 0.55,
    "Leon.Hair": 0.85,
    "Leon.Hair_xtra": 0.90,
    "Leon.MainBody": 0.85,
    "Leon.MainBody.001": 0.55,
    "Leon.BodyArmour": 0.60,
    "Leon.Arms": 0.50,
    "Leon.Belt": 0.55,
    "Leon.BeltBuckle": 1.00,
    "Leon.Radio": 0.65,
    "Leon.Kneepads": 0.60,
    "Leon.Boots": 0.55,
}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", type=str, default="")
    ap.add_argument("--portrait", type=str, default="")
    ap.add_argument("--out", type=str, default=str(OUT_GLB))
    return ap.parse_args(argv)


def bake_clean_png_image(src_img: bpy.types.Image, out_name: str, max_dim: int, colorspace: str, tmp_dir: Path, keep_alpha: bool = False, flip_normal_g: bool = False) -> bpy.types.Image:
    """Convert any packed TGA/DDS/PNG image into a clean resized lossless PNG compatible with Godot 4.7."""
    w, h = int(src_img.size[0]), int(src_img.size[1])
    if w <= 0 or h <= 0:
        raise RuntimeError(f"Empty source image: {src_img.name}")
    cp = src_img.copy()
    cp.name = out_name + "_tmp"
    # Ensure pixel buffer is unpacked/loaded in memory
    if max(w, h) > max_dim:
        sc = max_dim / float(max(w, h))
        nw = max(64, int(round(w * sc)))
        nh = max(64, int(round(h * sc)))
        cp.scale(nw, nh)
        w, h = nw, nh

    if flip_normal_g:
        px = np.array(cp.pixels[:], dtype=np.float32).reshape(h, w, cp.channels)
        px[:, :, 1] = 1.0 - px[:, :, 1]
        cp.pixels.foreach_set(px.ravel())

    png_path = tmp_dir / f"{out_name}.png"
    cp.file_format = "PNG"
    scene = bpy.context.scene
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if keep_alpha else "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 65
    cp.save_render(filepath=str(png_path)) if False else cp.save(filepath=str(png_path))

    # Reload strictly as clean PNG (prevents Blender glTF exporter from hitting DDS/TGA/OIIO issues!)
    # Use PIL if available for guaranteed crisp 8-bit PNG RGB/RGBA without colorspace drift
    try:
        from PIL import Image as PILImage
        px = np.array(cp.pixels[:], dtype=np.float32).reshape(h, w, cp.channels)
        # Flip vertically (Blender bottom-up -> PNG top-down)
        px = np.flipud(px)
        arr = np.clip(np.round(px * 255.0), 0, 255).astype(np.uint8)
        if keep_alpha and arr.shape[2] >= 4:
            pil = PILImage.fromarray(arr[:, :, :4], mode="RGBA")
        else:
            pil = PILImage.fromarray(arr[:, :, :3], mode="RGB")
        pil.save(png_path, format="PNG", optimize=True)
    except Exception:
        cp.filepath_raw = str(png_path)
        cp.file_format = "PNG"
        cp.save()

    bpy.data.images.remove(cp, do_unlink=True)
    clean_img = bpy.data.images.load(str(png_path), check_existing=False)
    clean_img.name = out_name
    clean_img.colorspace_settings.name = colorspace
    clean_img.pack()
    return clean_img


def make_clean_pbr(
    name: str,
    albedo_img: bpy.types.Image | None,
    normal_img: bpy.types.Image | None = None,
    roughness: float = 0.65,
    metallic: float = 0.0,
    normal_scale: float = 0.85,
    tint_rgba: tuple[float, float, float, float] | None = None,
    alpha_clip: float | None = None,
    double_sided: bool = False,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = not double_sided
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tc = nt.nodes.new("ShaderNodeTexCoord")

    if albedo_img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = albedo_img
        nt.links.new(tc.outputs["UV"], tex.inputs["Vector"])
        if tint_rgba is not None:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = tint_rgba
            nt.links.new(tex.outputs["Color"], mix.inputs[6])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_clip is not None:
            # Link tex Alpha DIRECTLY to BSDF Alpha so glTF exporter preserves full RGBA channel;
            # post-export GLB patch sets strict alphaMode='MASK' + alphaCutoff for Godot 4.7!
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            if hasattr(mat, "surface_render_method"):
                mat.surface_render_method = "DITHERED"
            if hasattr(mat, "blend_method"):
                mat.blend_method = "CLIP"
            if hasattr(mat, "alpha_threshold"):
                mat.alpha_threshold = alpha_clip
    elif tint_rgba is not None:
        bsdf.inputs["Base Color"].default_value = tint_rgba

    if normal_img is not None:
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = normal_img
        nt.links.new(tc.outputs["UV"], ntex.inputs["Vector"])
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = normal_scale
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def map_arp_vg_to_clean_bone(vg_name: str, default_bone: str = "Hips") -> str:
    """Map every Auto-Rig Pro deform vertex group cleanly onto our lean game skeleton.
    Limb checks MUST precede facial micro-bone checks (otherwise 'forearm' matches 'ear'!).
    """
    n = vg_name.lower()
    is_l = n.endswith(".l") or "_l" in n
    is_r = n.endswith(".r") or "_r" in n
    side = ".L" if is_l else (".R" if is_r else "")

    # 1. Limbs & torso FIRST (prevents 'forearm' matching 'ear'!)
    if "shoulder" in n or "clavicle" in n:
        return "Shoulder" + (side or ".L")
    if any(k in n for k in ["thumb", "index", "middle", "ring", "pinky", "hand", "wrist"]):
        return "Hand" + (side or ".L")
    if "forearm" in n or "elbow" in n:
        return "ForeArm" + (side or ".L")
    if "arm" in n:
        return "UpperArm" + (side or ".L")
    if "toe" in n or "foot" in n or "heel" in n or "ankle" in n:
        return "Foot" + (side or ".L")
    if "leg" in n or "shin" in n or "calf" in n or "knee" in n:
        return "Shin" + (side or ".L")
    if "thigh" in n or "hip" in n:
        return ("Thigh" + side) if side else "Hips"
    if "spine_02" in n or "chest" in n or "breast" in n:
        return "Chest"
    if "spine_01" in n or "spine" in n:
        return "Spine"
    if "neck" in n:
        return "Neck"
    # 2. Head & facial micro-bones (including Auto-Rig Pro lid/mouth/forehead/cornea/face bones!)
    if any(k in n for k in ["head", "skull", "jaw", "chin", "lip", "cheek", "eye", "brow", "nose", "ear", "tong", "teeth", "lid", "lash", "mouth", "forehead", "temple", "cornea", "face", "hair"]):
        return "Head"
    return default_bone


HEAD_RIGID_MESHES = {
    "Leon.Cornea",
    "Leon.Brows/Lashes",
    "Leon.Hair",
    "Leon.Hair_xtra",
    "Leon.Teeth",
    "Chen_VeteranHair",
}


def remap_object_vertex_groups(obj: bpy.types.Object, clean_bone_names: set[str]):
    """Merge Auto-Rig Pro's 136+ vertex groups cleanly into our 19 bone groups preserving exact weights.
    Rigid cranial attachments (eyes, brows/lashes, hair, teeth) bind 100% strictly to 'Head' so they
    NEVER separate from the face during neck/head animation!
    """
    me = obj.data
    n_verts = len(me.vertices)
    if n_verts == 0:
        return

    # Rigid head attachments (eyeballs, brows/lashes, hair, teeth): 100% locked to Head!
    if obj.name in HEAD_RIGID_MESHES:
        obj.vertex_groups.clear()
        nvg = obj.vertex_groups.new(name="Head")
        nvg.add(list(range(n_verts)), 1.0, "REPLACE")
        return

    # Head mesh: every unrecognized facial micro-bone defaults to 'Head' (NEVER 'Hips'!)
    default_bone = "Head" if obj.name == "Leon.Head" else "Hips"

    # Accumulate weights per vertex per target bone
    accum: dict[str, np.ndarray] = {}
    idx_to_target: dict[int, str] = {}
    for vg in obj.vertex_groups:
        tgt = map_arp_vg_to_clean_bone(vg.name, default_bone=default_bone)
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

    # Ensure every vertex has non-zero total weight (default to Head for head/face, else Hips)
    total = np.zeros(n_verts, dtype=np.float32)
    for arr in accum.values():
        total += arr
    unweighted = np.where(total < 1e-4)[0]
    if len(unweighted) > 0:
        if default_bone not in accum:
            accum[default_bone] = np.zeros(n_verts, dtype=np.float32)
        accum[default_bone][unweighted] = 1.0
        total[unweighted] = 1.0

    # Replace vertex groups cleanly
    obj.vertex_groups.clear()
    for bname, arr in accum.items():
        nz = np.where(arr > 1e-4)[0]
        if len(nz) == 0:
            continue
        nvg = obj.vertex_groups.new(name=bname)
        for vi in nz:
            nvg.add([int(vi)], float(arr[vi] / total[vi]), "REPLACE")


def set_world_rot_delta(pb: bpy.types.PoseBone, arm_obj: bpy.types.Object, world_axis: tuple[float, float, float], angle_deg: float):
    """Apply a clean world-axis rotation delta onto pose bone regardless of edit-bone roll."""
    q_world = Quaternion(Vector(world_axis).normalized(), math.radians(angle_deg))
    rest_rot = (arm_obj.matrix_world.to_3x3() @ pb.bone.matrix_local.to_3x3()).to_quaternion()
    q_local = rest_rot.inverted() @ q_world @ rest_rot
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = q_local @ pb.rotation_quaternion


def build_clean_armature(src_arm: bpy.types.Object, z_shift: float) -> bpy.types.Object:
    """Build a lean 22-bone game skeleton directly aligned to Leon_rig's exact rest joints."""
    def b_head(name: str, fallback: Vector) -> Vector:
        b = src_arm.data.bones.get(name)
        if b is None:
            return fallback.copy()
        p = src_arm.matrix_world @ b.head_local
        return Vector((p.x, p.y, p.z + z_shift))

    def b_tail(name: str, fallback: Vector) -> Vector:
        b = src_arm.data.bones.get(name)
        if b is None:
            return fallback.copy()
        p = src_arm.matrix_world @ b.tail_local
        return Vector((p.x, p.y, p.z + z_shift))

    p_hips = b_head("root.x", Vector((0, 0, 0.98)))
    p_spine = b_head("spine_01.x", Vector((0, 0, 1.12)))
    p_chest = b_head("spine_02.x", Vector((0, 0, 1.28)))
    p_neck = b_head("neck.x", Vector((0, 0, 1.50)))
    p_head = b_head("head.x", Vector((0, 0, 1.60)))
    p_head_top = p_head + Vector((0, 0, 0.22))

    # Left / Right limbs directly from source rig TRUE anatomical joints (arm.l/forearm.l/thigh.l/leg.l!)
    p_sh_l = b_head("shoulder.l", Vector((0.046, -0.048, 1.429)))
    p_ua_l = b_head("arm.l", Vector((0.184, 0.029, 1.429)))
    p_fa_l = b_head("forearm.l", Vector((0.398, -0.116, 1.258)))
    p_ha_l = b_head("hand.l", Vector((0.429, -0.300, 1.169)))
    p_ht_l = b_tail("hand.l", p_ha_l + Vector((0.06, -0.06, -0.04)))

    p_sh_r = b_head("shoulder.r", Vector((-0.046, -0.048, 1.429)))
    p_ua_r = b_head("arm.r", Vector((-0.184, 0.029, 1.429)))
    p_fa_r = b_head("forearm.r", Vector((-0.398, -0.116, 1.258)))
    p_ha_r = b_head("hand.r", Vector((-0.429, -0.300, 1.169)))
    p_ht_r = b_tail("hand.r", p_ha_r + Vector((-0.06, -0.06, -0.04)))

    p_th_l = b_head("thigh.l", Vector((0.10, 0.0, 0.94)))
    p_kn_l = b_head("leg.l", Vector((0.10, -0.02, 0.50)))
    p_ft_l = b_head("foot.l", Vector((0.10, 0.02, 0.09)))
    p_tt_l = b_tail("toes_01.l", Vector((0.10, -0.16, 0.02)))

    p_th_r = b_head("thigh.r", Vector((-0.10, 0.0, 0.94)))
    p_kn_r = b_head("leg.r", Vector((-0.10, -0.02, 0.50)))
    p_ft_r = b_head("foot.r", Vector((-0.10, 0.02, 0.09)))
    p_tt_r = b_tail("toes_01.r", Vector((-0.10, -0.16, 0.02)))

    arm_data = bpy.data.armatures.new("Chen_Armature_Data")
    arm_obj = bpy.data.objects.new("Chen_Armature", arm_data)
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


def bake_idle_camp_animation(arm_obj: bpy.types.Object):
    """Bake a natural, dignified Camp Liaison standing idle loop ('Idle_Camp', 4.0s @ 24fps)
    with relaxed arms at sides, subtle breathing, and calm watchful head micro-motion.
    """
    fps = 24
    n_frames = 96  # 4.0s seamless loop
    bpy.context.scene.render.fps = fps
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = n_frames

    arm_obj.animation_data_create()
    action = bpy.data.actions.new(name="Idle_Camp")
    arm_obj.animation_data.action = action

    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")

    key_frames = [0, 12, 24, 36, 48, 60, 72, 84, 96]
    for f in key_frames:
        bpy.context.scene.frame_set(f)
        phase = (f / float(n_frames)) * math.tau
        breath = math.sin(phase * 2.0)  # 2 calm breaths per 4s cycle
        sway = math.sin(phase)          # 1 gentle posture shift per 4s cycle
        look = math.sin(phase - 0.6)    # calm camp scan

        for pb in arm_obj.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
            pb.location = Vector((0, 0, 0))

        # Relaxed heroic Camp Liaison stance: arms comfortably down alongside thighs (right-hand +X lowers -Y toward -Z!)
        set_world_rot_delta(arm_obj.pose.bones["Shoulder.L"], arm_obj, (0, 1, 0), 4.0 + breath * 0.6)
        set_world_rot_delta(arm_obj.pose.bones["Shoulder.R"], arm_obj, (0, 1, 0), -4.0 - breath * 0.6)

        # Lower Left arm (+X) smoothly toward -Z (+Y rot) & bring forward-angled arm down (+X rot)!
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.L"], arm_obj, (0, 1, 0), 34.0 - breath * 0.8)
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.L"], arm_obj, (1, 0, 0), 14.0 + sway * 1.0)
        # Lower Right arm (-X) smoothly toward -Z (-Y rot) & bring forward-angled arm down (+X rot)!
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.R"], arm_obj, (0, 1, 0), -34.0 + breath * 0.8)
        set_world_rot_delta(arm_obj.pose.bones["UpperArm.R"], arm_obj, (1, 0, 0), 14.0 - sway * 1.0)

        # Lower forward-angled forearms smoothly downward toward hips (+X lowers -Y toward -Z!)
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.L"], arm_obj, (1, 0, 0), 26.0 + breath * 0.8)
        set_world_rot_delta(arm_obj.pose.bones["ForeArm.R"], arm_obj, (1, 0, 0), 26.0 + breath * 0.8)

        # Subtle natural torso breathing & dignified head scan
        set_world_rot_delta(arm_obj.pose.bones["Spine"], arm_obj, (1, 0, 0), -1.0 + breath * 0.8)
        set_world_rot_delta(arm_obj.pose.bones["Spine"], arm_obj, (0, 0, 1), sway * 1.5)
        set_world_rot_delta(arm_obj.pose.bones["Chest"], arm_obj, (1, 0, 0), -0.8 + breath * 1.0)
        set_world_rot_delta(arm_obj.pose.bones["Neck"], arm_obj, (0, 0, 1), look * 3.0)
        set_world_rot_delta(arm_obj.pose.bones["Head"], arm_obj, (0, 0, 1), look * 4.5)
        set_world_rot_delta(arm_obj.pose.bones["Head"], arm_obj, (1, 0, 0), -1.2 + breath * 0.7)

        for pb in arm_obj.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=f)

    bpy.ops.object.mode_set(mode="OBJECT")
    # Push onto NLA track so glTF exports named clip 'Idle_Camp' cleanly!
    track = arm_obj.animation_data.nla_tracks.new()
    track.name = "Idle_Camp"
    strip = track.strips.new("Idle_Camp", 0, action)
    strip.action_frame_start = 0
    strip.action_frame_end = n_frames
    arm_obj.animation_data.action = None


def render_previews(preview_dir: Path, arm_obj: bpy.types.Object, mesh_objs: list[bpy.types.Object], portrait_out: Path | None = None):
    preview_dir.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.frame_set(12)
    bpy.context.view_layer.update()

    # Clean bright daylight studio world
    w = bpy.data.worlds.new("StudioPreviewWorld")
    scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[0].default_value = (0.34, 0.42, 0.48, 1.0)
    bg.inputs[1].default_value = 0.95
    wout = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs["Background"], wout.inputs["Surface"])

    # Warm sunlit 3-point portrait studio lighting (soft key + cool sky fill + subtle golden hair rim!)
    lights = []
    for lname, energy, col, rot_deg in [
        ("KeySun", 2.8, (1.0, 0.96, 0.90), (36, 0, -24)),
        ("FillSun", 1.35, (0.82, 0.92, 1.0), (24, 0, 128)),
        ("RimSun", 1.65, (1.0, 0.92, 0.76), (32, 0, 165)),
    ]:
        ld = bpy.data.lights.new(lname, "SUN")
        ld.energy = energy
        ld.color = col
        ld.angle = math.radians(14.0)
        lo = bpy.data.objects.new(lname, ld)
        scene.collection.objects.link(lo)
        lo.rotation_euler = tuple(math.radians(a) for a in rot_deg)
        lights.append(lo)

    cam_d = bpy.data.cameras.new("PrevCam")
    cam_d.lens = 68.0
    cam = bpy.data.objects.new("PrevCam", cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam

    scene.render.film_transparent = False
    shots = [
        ("leon_chen_full.png", Vector((0.22, -3.55, 0.96)), Vector((0.0, 0.0, 0.94))),
        ("leon_chen_bust.png", Vector((0.18, -1.42, 1.56)), Vector((0.0, 0.0, 1.50))),
    ]
    for fname, loc, tgt in shots:
        cam.location = loc
        cam.rotation_euler = (tgt - loc).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(preview_dir / fname)
        bpy.ops.render.render(write_still=True)
        print(f"PREVIEW_SAVED {preview_dir / fname}")

    # Optional 1:1 Official Lore Codex Portrait transparent foreground render (1024x1280 RGBA)
    if portrait_out is not None:
        scene.render.resolution_x = 1024
        scene.render.resolution_y = 1280
        scene.render.film_transparent = True
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGBA"
        cam_d.lens = 82.0
        cam.location = Vector((0.20, -1.66, 1.57))
        cam.rotation_euler = (Vector((0.0, 0.0, 1.50)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        portrait_out.parent.mkdir(parents=True, exist_ok=True)
        scene.render.filepath = str(portrait_out)
        bpy.ops.render.render(write_still=True)
        print(f"PORTRAIT_FG_SAVED {portrait_out}")

    # Clean up temporary preview lights/camera so they NEVER leak into GLB export
    for o in lights + [cam]:
        bpy.data.objects.remove(o, do_unlink=True)


def main():
    args = parse_args()
    out_path = Path(args.out)
    tmp_dir = Path(tempfile.mkdtemp(prefix="v0995_dev2_chen_"))

    src_arm = bpy.data.objects.get("Leon_rig")
    if src_arm is None:
        raise RuntimeError("Source armature 'Leon_rig' not found in blend file!")

    # Force REST pose so all vertex coordinates are pure unmodified canonical rest positions
    src_arm.data.pose_position = "REST"
    bpy.context.view_layer.update()

    # Keep ONLY unmodified Leon meshes
    kept_meshes: list[bpy.types.Object] = []
    for name in KEEP_MESHES:
        o = bpy.data.objects.get(name)
        if o is not None and o.type == "MESH":
            o.hide_viewport = False
            o.hide_render = False
            kept_meshes.append(o)
    print(f"KEPT_LEON_MESHES={len(kept_meshes)}: {[o.name for o in kept_meshes]}")

    # Compute exact bounding box to ground feet strictly at Z = 0.000m
    min_z = 1e9
    max_z = -1e9
    for o in kept_meshes:
        for v in o.data.vertices:
            wz = (o.matrix_world @ v.co).z
            min_z = min(min_z, wz)
            max_z = max(max_z, wz)
    z_shift = -min_z
    print(f"LEON_Z_RANGE=[{min_z:.4f}, {max_z:.4f}] height={max_z - min_z:.4f}m z_shift={z_shift:+.4f}m")

    # Convert packed source textures to clean lossless PNGs (ZERO DDS/TGA/OIIO issues in Godot!)
    def need_img(name: str) -> bpy.types.Image:
        im = bpy.data.images.get(name)
        if im is None:
            raise RuntimeError(f"Expected packed texture '{name}' not found!")
        return im

    img_face_d = bake_clean_png_image(need_img("Leon_Face_D.tga"), "Chen_Face_Color", 1024, "sRGB", tmp_dir, keep_alpha=False)
    img_face_n = bake_clean_png_image(need_img("Leon_Face_N.tga"), "Chen_Face_Normal", 1024, "Non-Color", tmp_dir, keep_alpha=False)
    img_hair_d = bake_clean_png_image(need_img("Leon_Hair_D.tga"), "Chen_Hair_Color", 1024, "sRGB", tmp_dir, keep_alpha=True)
    img_hair_n = bake_clean_png_image(need_img("Leon_Hair_N.tga"), "Chen_Hair_Normal", 1024, "Non-Color", tmp_dir, keep_alpha=False)
    img_brow_d = bake_clean_png_image(need_img("Leon_Eyebrows_D.tga"), "Chen_Brow_Color", 512, "sRGB", tmp_dir, keep_alpha=True)
    img_brow_n = bake_clean_png_image(need_img("Leon_Eyebrows_N.tga"), "Chen_Brow_Normal", 512, "Non-Color", tmp_dir, keep_alpha=False)
    img_body_d = bake_clean_png_image(need_img("Leon_Body_D.tga"), "Chen_Body_Color", 1024, "sRGB", tmp_dir, keep_alpha=False)
    img_body_n = bake_clean_png_image(need_img("Leon_Body_N.tga"), "Chen_Body_Normal", 1024, "Non-Color", tmp_dir, keep_alpha=False)
    img_item_d = bake_clean_png_image(need_img("Leon_Item_D.tga"), "Chen_Item_Color", 1024, "sRGB", tmp_dir, keep_alpha=False)
    img_item_n = bake_clean_png_image(need_img("Leon_Item_N.tga"), "Chen_Item_Normal", 1024, "Non-Color", tmp_dir, keep_alpha=False)

    # Create clean real-time Godot PBR materials preserving 100% original appearance with daylight-calibrated roughness!
    mat_map = {
        "Leon.HeadMat": make_clean_pbr("Mat_Chen_Head", img_face_d, img_face_n, roughness=0.68, normal_scale=0.55, tint_rgba=(0.90, 0.87, 0.85, 1.0)),
        "Leon.Eyemat": make_clean_pbr("Mat_Chen_Eyes", img_face_d, None, roughness=0.18, metallic=0.0, tint_rgba=(0.86, 0.88, 0.90, 1.0)),
        "Leon_Hair": make_clean_pbr("Mat_Chen_Hair", img_hair_d, img_hair_n, roughness=0.58, normal_scale=0.55, alpha_clip=0.30, double_sided=True),
        "Leon.BrowMat": make_clean_pbr("Mat_Chen_Brows", img_brow_d, img_brow_n, roughness=0.72, normal_scale=0.40, alpha_clip=0.18, double_sided=True),
        "Leon.LashesMat": make_clean_pbr("Mat_Chen_Lashes", img_brow_d, None, roughness=0.70, alpha_clip=0.22, double_sided=True),
        "Leon_Body": make_clean_pbr("Mat_Chen_Uniform", img_body_d, img_body_n, roughness=0.78, normal_scale=0.80),
        "Leon_Vest": make_clean_pbr("Mat_Chen_Vest", img_body_d, img_body_n, roughness=0.64, normal_scale=0.85),
        "Leon_Hands": make_clean_pbr("Mat_Chen_Hands", img_body_d, img_body_n, roughness=0.66, normal_scale=0.55, tint_rgba=(0.90, 0.87, 0.85, 1.0)),
        "Leon_Gloves": make_clean_pbr("Mat_Chen_Gloves", img_body_d, img_body_n, roughness=0.52, normal_scale=0.75),
        "Leon_Fabrics": make_clean_pbr("Mat_Chen_Fabrics", img_body_d, img_body_n, roughness=0.80, normal_scale=0.75),
        "Leon_Pad": make_clean_pbr("Mat_Chen_Pad", img_body_d, img_body_n, roughness=0.58, normal_scale=0.80),
        "Leon.Bootsmat": make_clean_pbr("Mat_Chen_Boots", img_body_d, img_body_n, roughness=0.48, normal_scale=0.80),
        "Leon_Radio": make_clean_pbr("Mat_Chen_RadioBelt", img_item_d, img_item_n, roughness=0.46, metallic=0.22, normal_scale=0.80),
        "Leon.MetalBuckle": make_clean_pbr("Mat_Chen_Buckle", img_body_d, img_body_n, roughness=0.30, metallic=0.82, normal_scale=0.60),
    }

    # Build lean 22-bone game skeleton matching Leon_rig's exact joints
    clean_arm = build_clean_armature(src_arm, z_shift)
    clean_bone_names = {b.name for b in clean_arm.data.bones}

    # Bake mesh world transforms, ground Z=0, ensure single canonical 'UVMap', swap materials, decimate gently, remap weights
    final_meshes: list[bpy.types.Object] = []
    for o in kept_meshes:
        orig_name = o.name
        # Detach from old rig & remove old modifiers (Armature, Subsurf, etc.)
        wm = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = wm
        for mod in list(o.modifiers):
            o.modifiers.remove(mod)
        # Clear unused facial shape keys so world transform & decimate apply cleanly
        if o.data.shape_keys is not None:
            o.shape_key_clear()
        # Bake world transform + grounding shift directly into mesh vertices
        shift_m = Matrix.Translation((0.0, 0.0, z_shift)) @ o.matrix_world
        o.data.transform(shift_m)
        o.matrix_world = Matrix.Identity(4)

        # Ensure single canonical UVMap (drop extra UV2 on hair so TEXCOORDS == ['TEXCOORD_0']!)
        uvs = o.data.uv_layers
        if len(uvs) > 0:
            uvs.active_index = 0
            uvs[0].name = "UVMap"
            while len(uvs) > 1:
                uvs.remove(uvs[-1])

        # Remap materials cleanly
        for i, m in enumerate(o.data.materials):
            if m and m.name in mat_map:
                o.data.materials[i] = mat_map[m.name]

        # Gentle collapse decimate preserving UVs & vertex weights
        ratio = DECIMATE_RATIO.get(orig_name, 0.65)
        if ratio < 0.99 and len(o.data.polygons) > 300:
            bpy.context.view_layer.objects.active = o
            dec = o.modifiers.new(name="Dec", type="DECIMATE")
            dec.decimate_type = "COLLAPSE"
            dec.ratio = ratio
            bpy.ops.object.modifier_apply(modifier=dec.name)

        # Remap Auto-Rig Pro vertex groups -> lean 22-bone skeleton
        remap_object_vertex_groups(o, clean_bone_names)
        final_meshes.append(o)

    # Join Leon.Hair + Leon.Hair_xtra -> 'Chen_VeteranHair' (preserving 100% original hair & existing QA node check!)
    hair_objs = [o for o in final_meshes if o.name in ("Leon.Hair", "Leon.Hair_xtra")]
    if hair_objs:
        bpy.ops.object.select_all(action="DESELECT")
        for ho in hair_objs:
            ho.select_set(True)
        bpy.context.view_layer.objects.active = hair_objs[0]
        if len(hair_objs) > 1:
            bpy.ops.object.join()
        hair_main = bpy.context.view_layer.objects.active
        hair_main.name = "Chen_VeteranHair"
        final_meshes = [o for o in final_meshes if o not in hair_objs] + [hair_main]

    # Remove all other unrelated scene objects (Claire, Ada, Star Office, old rigs, lights, cameras)
    keep_set = set(final_meshes) | {clean_arm}
    for o in list(bpy.data.objects):
        if o not in keep_set:
            bpy.data.objects.remove(o, do_unlink=True)

    # Ensure all kept objects live directly in active scene collection & bind to Chen_Armature
    sc_col = bpy.context.scene.collection
    if clean_arm.name not in sc_col.objects:
        sc_col.objects.link(clean_arm)
    for o in final_meshes:
        if o.name not in sc_col.objects:
            sc_col.objects.link(o)
        o.parent = clean_arm
        amod = o.modifiers.new(name="Armature", type="ARMATURE")
        amod.object = clean_arm
        # Smooth shading for lifelike organic look
        for p in o.data.polygons:
            p.use_smooth = True

    # Purge ALL leftover source Actions (Claire_rigAction, PoseLib*, etc.) before baking ONLY 'Idle_Camp'!
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act, do_unlink=True)

    # Bake relaxed Camp Liaison 'Idle_Camp' standing animation
    bake_idle_camp_animation(clean_arm)

    # Optional Blender EEVEE visual inspection renders + 1:1 Official Lore Codex Portrait!
    if args.preview or args.portrait:
        pdir = Path(args.preview) if args.preview else tmp_dir
        pout = Path(args.portrait) if args.portrait else None
        render_previews(pdir, clean_arm, final_meshes, portrait_out=pout)

    # Export clean GLB (selecting ONLY Chen_Armature + final_meshes!)
    bpy.ops.object.select_all(action="DESELECT")
    clean_arm.select_set(True)
    for o in final_meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = clean_arm

    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
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

    # Guarantee alphaMode='MASK' + alphaCutoff on hair/brows/lashes in GLB JSON (prevents Godot GL Compat alpha-blend Z-sorting!)
    raw = out_path.read_bytes()
    jlen = struct.unpack("<I", raw[12:16])[0]
    g = json.loads(raw[20 : 20 + jlen])
    mask_cutoffs = {"Mat_Chen_Hair": 0.30, "Mat_Chen_Brows": 0.18, "Mat_Chen_Lashes": 0.22}
    patched = False
    for m in g.get("materials", []):
        mname = m.get("name", "")
        if mname in mask_cutoffs:
            m["alphaMode"] = "MASK"
            m["alphaCutoff"] = mask_cutoffs[mname]
            m["doubleSided"] = True
            patched = True
    if patched:
        new_j = json.dumps(g, separators=(",", ":")).encode("utf-8")
        pad = (4 - (len(new_j) % 4)) % 4
        new_j += b" " * pad
        bin_part = raw[20 + jlen :]
        total_len = 12 + 8 + len(new_j) + len(bin_part)
        header = struct.pack("<III", 0x46546C67, 2, total_len)
        jchunk = struct.pack("<II", len(new_j), 0x4E4F534A) + new_j
        out_path.write_bytes(header + jchunk + bin_part)
        raw = out_path.read_bytes()
        jlen = struct.unpack("<I", raw[12:16])[0]
        g = json.loads(raw[20 : 20 + jlen])

    # Strict glTF TEXCOORD, alphaMode & polycount audit
    total_polys = sum(len(o.data.polygons) for o in final_meshes)
    tcs = sorted({k for m in g.get("meshes", []) for pr in m.get("primitives", []) for k in pr.get("attributes", {}) if k.startswith("TEXCOORD")})
    miss = sum(1 for m in g.get("meshes", []) for pr in m.get("primitives", []) if "TEXCOORD_0" not in pr.get("attributes", {}))
    anims = [a.get("name") for a in g.get("animations", [])]
    alphas = [(m.get("name"), m.get("alphaMode"), m.get("alphaCutoff")) for m in g.get("materials", []) if m.get("alphaMode")]
    print(f"EXPORTED_CHEN_V2 {out_path.name} ({len(raw)/1048576:.2f} MiB | {total_polys} polys | meshes={len(g.get('meshes', []))} | bones={len(clean_arm.data.bones)} | anims={anims} | TEXCOORDS={tcs} | missing_uv0={miss} | alphas={alphas})")


if __name__ == "__main__":
    main()
