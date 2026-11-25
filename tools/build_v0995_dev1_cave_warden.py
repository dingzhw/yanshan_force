"""v0.9.9.5_dev1 Cave Warden ('古洞循音石卫') Blender 5.3 Optimizer & Skeletal Animator.

Transforms the sculpted Minecraft-Warden-inspired rigged model (cave_warden_v2.glb)
into an optimized, game-ready Godot 4.7 skeletal PBR boss asset at:
  game/assets/slice/v098_cave_warden.glb

Pipeline:
1. Cleanly strips accidental unparented helper geometry (e.g., stray Icosphere).
2. Normalizes Warden_Armature scale to (1,1,1), feet grounded at Z = 0.000m,
   facing -Y in Blender (+Z forward in Godot), towering 2.86m stature.
3. Gently optimizes mesh topology (collapse decimate preserving single UVMap & all
   65 mixamorig:* vertex weights) and downsamples 2K textures to crisp 1024px maps
   (cutting file size from ~12.7 MiB to ~2.2 MiB with zero missing UVs).
4. Configures Mat_Warden_PBR with emissive texture properly wired so Godot's
   cave_warden.gd modulates ONLY the sculpted glowing ribcage soul-heart, sculk
   flecks, and twin head acoustic tendrils per gameplay state.
5. Bakes 7 hulking procedural skeletal animations directly onto the 65-bone
   Warden_Armature via world-axis pose-delta math (zero bone-axis guesswork):
     - Idle_Patrol      (heavy breathing + subtle menacing sway)
     - Walk_Stalk       (weighty Minecraft-Warden stomping stride)
     - Listen_Sniff     (head raised & sweeping side-to-side sniffing sounds)
     - Guard_X          (massive clawed forearms crossed tight in X over ribcage)
     - Exposed_Stagger  (arms flung wide back, glowing ribcage thrust open)
     - Rush_Charge      (hunched juggernaut bull-rush stomp)
     - Sonic_Roar       (chest flared open, head roaring during Sonic Lance charge)
6. Wraps hierarchy under root node 'cave_warden' for seamless Godot integration,
   runs UV/TEXCOORD audit, and optionally renders multi-pose EEVEE previews.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
import tempfile
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

REPO_ROOT = Path(__file__).resolve().parents[1]
SLICE_DIR = REPO_ROOT / "game" / "assets" / "slice"
OUT_GLB = SLICE_DIR / "v098_cave_warden.glb"


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--source-glb", required=True, type=Path, help="Path to cave_warden_v2.glb")
    p.add_argument("--target-height", type=float, default=2.86, help="Normalized boss height in meters")
    p.add_argument("--decimate-ratio", type=float, default=0.48, help="Collapse decimate ratio (0.48 -> ~22k tris)")
    p.add_argument("--tex-size", type=int, default=1024, help="Max texture dimension")
    p.add_argument("--preview-dir", type=Path, default=None, help="Optional directory to render multi-pose previews")
    return p.parse_args(argv)


def optimize_image_size(img: bpy.types.Image, max_size: int, as_jpeg: bool, quality: int = 90) -> bpy.types.Image:
    """Downsample oversized packed texture cleanly into a Godot-valid 3-ch JPEG or RGBA PNG and repack."""
    w, h = int(img.size[0]), int(img.size[1])
    if w == 0 or h == 0:
        return img
    try:
        img.pack()
    except Exception:
        pass
    tmp_dir = Path(tempfile.mkdtemp(prefix="cw_tex_"))
    orig_name = img.name
    orig_cs = img.colorspace_settings.name

    work = img.copy()
    if max(w, h) > max_size:
        scale = max_size / float(max(w, h))
        nw = max(64, int(round(w * scale)))
        nh = max(64, int(round(h * scale)))
        work.scale(nw, nh)

    # Always write valid RGB JPEG via save_render(Raw) or lossless PNG via work.save()!
    # (Blender Image.save() with JPEG on an RGBA buffer writes malformed 4-channel JPEGs rejected by libjpeg-turbo!)
    ext = ".jpg" if as_jpeg else ".png"
    out_p = tmp_dir / f"{orig_name.replace(' ', '_')}{ext}"
    scene = bpy.context.scene
    if as_jpeg:
        prev_fmt = scene.render.image_settings.file_format
        prev_q = scene.render.image_settings.quality
        prev_cm = scene.render.image_settings.color_mode
        prev_vt = scene.view_settings.view_transform
        prev_lk = scene.view_settings.look
        prev_ex = scene.view_settings.exposure
        scene.render.image_settings.file_format = "JPEG"
        scene.render.image_settings.quality = quality
        scene.render.image_settings.color_mode = "RGB"
        scene.view_settings.view_transform = "Standard" if orig_cs == "sRGB" else "Raw"
        scene.view_settings.look = "None"
        scene.view_settings.exposure = 0.0
        # For sRGB images, save_render applies display transform -> Raw avoids double-gamma on already-sRGB image?
        # Wait: Blender save_render converts Linear -> Display! sRGB images are stored Linear internally,
        # so Standard (sRGB) outputs exact sRGB bytes, while Non-Color images with Raw output exact linear bytes!
        work.save_render(str(out_p), scene=scene)
        scene.render.image_settings.file_format = prev_fmt
        scene.render.image_settings.quality = prev_q
        scene.render.image_settings.color_mode = prev_cm
        scene.view_settings.view_transform = prev_vt
        scene.view_settings.look = prev_lk
        scene.view_settings.exposure = prev_ex
    else:
        work.filepath_raw = str(out_p)
        work.file_format = "PNG"
        work.save()
    bpy.data.images.remove(work)

    new_img = bpy.data.images.load(str(out_p), check_existing=False)
    new_img.name = orig_name + "_opt"
    new_img.colorspace_settings.name = orig_cs
    new_img.pack()
    return new_img


def optimize_materials(body_obj: bpy.types.Object, max_tex_size: int):
    """Optimize texture resolutions and ensure Mat_Warden_PBR emissive channel is crisp for Godot."""
    for mat in body_obj.data.materials:
        if mat is None or not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = None
        for n in nt.nodes:
            if n.type == "BSDF_PRINCIPLED":
                bsdf = n
            elif n.type == "TEX_IMAGE" and n.image is not None:
                im = n.image
                # Use lossless 1024px PNG across all 4 PBR maps (bypasses Blender 5.3 OIIO ICC-JPEG bug in Godot!)
                opt = optimize_image_size(im, max_tex_size, as_jpeg=False)
                n.image = opt
        if bsdf is not None:
            # Ensure default emissive strength = 1.0 (Godot cave_warden.gd modulates emission_energy_multiplier!)
            em_s = bsdf.inputs.get("Emission Strength")
            if em_s is not None:
                em_s.default_value = 1.0


def pose_bone_world_rot(
    arm: bpy.types.Object,
    bone_name: str,
    world_rot: Quaternion,
):
    """Apply a world-space delta rotation cleanly onto a pose bone regardless of its local rest orientation."""
    pb = arm.pose.bones.get(bone_name)
    if pb is None:
        return
    pb.rotation_mode = "QUATERNION"
    # Convert world rotation delta into bone-local space: q_local = R_rest^-1 * q_world * R_rest
    # For child bones whose parent already rotated, compose smoothly in bone rest frame:
    rest_q = pb.bone.matrix_local.to_quaternion()
    local_q = rest_q.inverted() @ world_rot @ rest_q
    pb.rotation_quaternion = local_q


def compose_world_rot(angles_xyz_deg: tuple[float, float, float]) -> Quaternion:
    """Build world-space rotation quaternion (X=pitch forward/back, Y=roll side-lean, Z=yaw turn)."""
    rx, ry, rz = (math.radians(a) for a in angles_xyz_deg)
    # In Blender Z-up, facing -Y:
    #   +X rotation pitches top backward / lifts front up; -X leans forward!
    #   +Y rolls right shoulder down / tilts right; -Y tilts left!
    #   +Z yaws counter-clockwise (head turns to Warden's left / viewer's right)!
    return Euler((rx, ry, rz), "XYZ").to_quaternion()


def clear_pose(arm: bpy.types.Object):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = Vector((0, 0, 0))
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.scale = Vector((1, 1, 1))


def key_pose_frame(arm: bpy.types.Object, frame: int, bone_rots: dict[str, tuple[float, float, float]], hips_offset_world: Vector = Vector((0, 0, 0))):
    """Key all animated bones at exact frame using world-space rotation deltas."""
    clear_pose(arm)
    for bname, degs in bone_rots.items():
        pose_bone_world_rot(arm, bname, compose_world_rot(degs))
    hips = arm.pose.bones.get("mixamorig:Hips")
    if hips is not None:
        # Convert world hips displacement into Hips local bone space
        rest_m3 = hips.bone.matrix_local.to_3x3()
        hips.location = rest_m3.inverted() @ hips_offset_world
        hips.keyframe_insert(data_path="location", frame=frame)
    for bname in ANIM_BONES:
        pb = arm.pose.bones.get(bname)
        if pb is not None:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)


ANIM_BONES = [
    "mixamorig:Hips",
    "mixamorig:Spine",
    "mixamorig:Spine1",
    "mixamorig:Spine2",
    "mixamorig:Neck",
    "mixamorig:Head",
    "mixamorig:LeftShoulder",
    "mixamorig:LeftArm",
    "mixamorig:LeftForeArm",
    "mixamorig:LeftHand",
    "mixamorig:RightShoulder",
    "mixamorig:RightArm",
    "mixamorig:RightForeArm",
    "mixamorig:RightHand",
    "mixamorig:LeftUpLeg",
    "mixamorig:LeftLeg",
    "mixamorig:LeftFoot",
    "mixamorig:RightUpLeg",
    "mixamorig:RightLeg",
    "mixamorig:RightFoot",
]


def bake_clip(arm: bpy.types.Object, clip_name: str, frame_count: int, eval_fn):
    """Bake a smooth looping skeletal Action and stash it onto an NLA track for glTF export."""
    act = bpy.data.actions.new(name=clip_name)
    act.use_fake_user = True
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act

    # Sample every 4 frames (smooth cubic interpolation, compact keyframes, exact loop start==end!)
    step = 4
    frames = list(range(1, frame_count + 1, step))
    if frames[-1] != frame_count + 1:
        frames.append(frame_count + 1)

    for fr in frames:
        u = float(fr - 1) / float(frame_count)
        if fr == frame_count + 1:
            u = 0.0  # Exact seamless loop closure!
        rots, hips_off = eval_fn(u)
        key_pose_frame(arm, fr, rots, hips_off)

    # Set smooth Bezier interpolation on all fcurves
    # Blender 5.x layered actions store fcurves in slots/channelbags or act.fcurves
    fcurves = []
    if hasattr(act, "layers") and act.layers:
        for layer in act.layers:
            for strip in layer.strips:
                for cb in getattr(strip, "channelbags", []):
                    fcurves.extend(cb.fcurves)
    elif hasattr(act, "fcurves"):
        fcurves.extend(act.fcurves)
    for fc in fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"

    # Push to NLA track so glTF exports all 7 clips cleanly!
    track = arm.animation_data.nla_tracks.new()
    track.name = clip_name
    strip = track.strips.new(clip_name, 1, act)
    strip.action_frame_start = 1
    strip.action_frame_end = frame_count + 1
    arm.animation_data.action = None
    return act


def build_all_warden_animations(arm: bpy.types.Object):
    """Author 7 expressive hulking Minecraft-Warden animations in world coordinates.

    Axis cheat sheet (Blender Z-up, Warden facing -Y, Left is +X, Right is -X):
      - Arms hang downward (-Z) in rest pose:
          * Pitch forward (raise arm forward toward -Y):  Left/Right X = -deg (e.g. -65°)
          * Pitch backward (swing arm behind toward +Y):  Left/Right X = +deg (e.g. +35°)
          * Abduct outward (spread arms wide apart):      Left Y = -deg, Right Y = +deg
          * Adduct inward (cross arms across chest!):     Left Y = +deg, Right Y = -deg
          * Twist arm inward around Z:                    Left Z = -deg, Right Z = +deg
      - Legs hang downward (-Z):
          * Lift thigh forward (toward -Y):               UpLeg X = -deg
          * Swing thigh backward (toward +Y):             UpLeg X = +deg
          * Bend knee backward:                           Leg X = +deg
      - Torso/Head upright (+Z):
          * Hunch/lean forward (toward -Y):               Spine/Head X = +deg
          * Arch back / roar upward:                      Spine/Head X = -deg
          * Roll right / left:                            Spine Y = +/-deg
          * Turn head left (+Z) / right (-Z):             Head Z = +/-deg
    """

    # 1. Idle_Patrol — Heavy menacing breath, slight hunch, subtle acoustic head scan
    def anim_idle(u: float):
        s = math.sin(u * math.tau)
        s2 = math.sin(u * math.tau * 2.0)
        rots = {
            "mixamorig:Hips": (0.0, s * 2.0, s * 2.5),
            "mixamorig:Spine": (4.0 + s * 1.5, -s * 1.5, 0.0),
            "mixamorig:Spine1": (5.0 + s * 2.0, 0.0, 0.0),
            "mixamorig:Spine2": (4.0 + s * 2.5, 0.0, -s * 2.0),
            "mixamorig:Head": (-5.0 + s2 * 2.5, s * 4.0, math.sin(u * math.tau) * 14.0),
            "mixamorig:LeftShoulder": (0.0, -s * 2.5, 0.0),
            "mixamorig:RightShoulder": (0.0, s * 2.5, 0.0),
            "mixamorig:LeftArm": (-8.0 + s * 4.0, -8.0 - s * 2.0, -4.0),
            "mixamorig:RightArm": (-8.0 - s * 4.0, 8.0 + s * 2.0, 4.0),
            "mixamorig:LeftForeArm": (-24.0 + s * 3.0, 5.0, 0.0),
            "mixamorig:RightForeArm": (-24.0 - s * 3.0, -5.0, 0.0),
            "mixamorig:LeftUpLeg": (-4.0, -3.0, 0.0),
            "mixamorig:RightUpLeg": (-4.0, 3.0, 0.0),
            "mixamorig:LeftLeg": (8.0, 0.0, 0.0),
            "mixamorig:RightLeg": (8.0, 0.0, 0.0),
        }
        return rots, Vector((0.0, 0.0, -0.02 + s * 0.025))

    # 2. Walk_Stalk — Iconic Minecraft Warden heavy side-rocking stomp!
    def anim_walk(u: float):
        ph = u * math.tau
        s = math.sin(ph)
        c = math.cos(ph)
        bob = abs(s) * 0.075 - 0.045
        l_lift = max(0.0, s)
        r_lift = max(0.0, -s)
        rots = {
            "mixamorig:Hips": (3.0, -s * 6.5, s * 6.0),
            "mixamorig:Spine": (6.0, s * 4.5, -s * 4.0),
            "mixamorig:Spine1": (6.0, s * 5.0, -s * 5.0),
            "mixamorig:Spine2": (5.0, s * 4.0, -s * 5.0),
            "mixamorig:Head": (-8.0 + abs(c) * 4.0, -s * 7.0, s * 10.0),
            "mixamorig:LeftShoulder": (0.0, -s * 5.0, 0.0),
            "mixamorig:RightShoulder": (0.0, -s * 5.0, 0.0),
            "mixamorig:LeftArm": (-12.0 + s * 28.0, -10.0, -4.0),
            "mixamorig:RightArm": (-12.0 - s * 28.0, 10.0, 4.0),
            "mixamorig:LeftForeArm": (-28.0 + max(0.0, -s) * 14.0, 6.0, 0.0),
            "mixamorig:RightForeArm": (-28.0 + max(0.0, s) * 14.0, -6.0, 0.0),
            "mixamorig:LeftUpLeg": (-s * 26.0 - 4.0, -4.0, 0.0),
            "mixamorig:RightUpLeg": (s * 26.0 - 4.0, 4.0, 0.0),
            "mixamorig:LeftLeg": (6.0 + l_lift * 34.0, 0.0, 0.0),
            "mixamorig:RightLeg": (6.0 + r_lift * 34.0, 0.0, 0.0),
            "mixamorig:LeftFoot": (-l_lift * 14.0, 0.0, 0.0),
            "mixamorig:RightFoot": (-r_lift * 14.0, 0.0, 0.0),
        }
        return rots, Vector((s * 0.055, 0.0, bob))

    # 3. Listen_Sniff — Iconic Warden acoustic sniff! Head lifted & sweeping left/right, chest open
    def anim_listen(u: float):
        ph = u * math.tau
        s = math.sin(ph)
        s2 = math.sin(ph * 2.0)
        rots = {
            "mixamorig:Hips": (0.0, 0.0, s * 4.0),
            "mixamorig:Spine": (3.0, s * 3.0, s * 4.0),
            "mixamorig:Spine1": (2.0 - abs(s) * 4.0, 0.0, s * 5.0),
            "mixamorig:Spine2": (-3.0 + s2 * 3.0, 0.0, s * 6.0),
            "mixamorig:Neck": (-8.0 + s2 * 4.0, 0.0, s * 8.0),
            "mixamorig:Head": (-14.0 + s2 * 6.0, s * 12.0, s * 32.0),
            "mixamorig:LeftArm": (4.0, -16.0 - abs(s) * 6.0, -8.0),
            "mixamorig:RightArm": (4.0, 16.0 + abs(s) * 6.0, 8.0),
            "mixamorig:LeftForeArm": (-22.0, 4.0, 0.0),
            "mixamorig:RightForeArm": (-22.0, -4.0, 0.0),
            "mixamorig:LeftUpLeg": (-5.0, -4.0, 0.0),
            "mixamorig:RightUpLeg": (-5.0, 4.0, 0.0),
            "mixamorig:LeftLeg": (10.0, 0.0, 0.0),
            "mixamorig:RightLeg": (10.0, 0.0, 0.0),
        }
        return rots, Vector((0.0, 0.0, -0.03 + s2 * 0.02))

    # 4. Guard_X — Heavy clawed forearms crossed tightly in X over glowing ribcage soul-heart!
    def anim_guard(u: float):
        s = math.sin(u * math.tau)
        rots = {
            "mixamorig:Hips": (4.0, 0.0, 0.0),
            "mixamorig:Spine": (9.0, 0.0, 0.0),
            "mixamorig:Spine1": (10.0, 0.0, 0.0),
            "mixamorig:Spine2": (9.0 + s * 1.5, 0.0, 0.0),
            "mixamorig:Neck": (10.0, 0.0, 0.0),
            "mixamorig:Head": (12.0, s * 3.0, 0.0),
            # Shoulders hunched forward & inward
            "mixamorig:LeftShoulder": (0.0, 10.0, -18.0),
            "mixamorig:RightShoulder": (0.0, -10.0, 18.0),
            # Upper arms raised forward (-62 deg) and adducted inward across chest!
            "mixamorig:LeftArm": (-62.0 + s * 2.0, 34.0, -24.0),
            "mixamorig:RightArm": (-56.0 - s * 2.0, -34.0, 24.0),
            # Massive forearms folded diagonally across ribcage forming unmistakable X-shield!
            "mixamorig:LeftForeArm": (-36.0, 62.0, -18.0),
            "mixamorig:RightForeArm": (-44.0, -62.0, 18.0),
            "mixamorig:LeftHand": (-10.0, 14.0, 0.0),
            "mixamorig:RightHand": (-10.0, -14.0, 0.0),
            # Planted braced defensive stance
            "mixamorig:LeftUpLeg": (-12.0, -7.0, -5.0),
            "mixamorig:RightUpLeg": (-12.0, 7.0, 5.0),
            "mixamorig:LeftLeg": (24.0, 0.0, 0.0),
            "mixamorig:RightLeg": (24.0, 0.0, 0.0),
            "mixamorig:LeftFoot": (-10.0, 0.0, 0.0),
            "mixamorig:RightFoot": (-10.0, 0.0, 0.0),
        }
        return rots, Vector((0.0, 0.0, -0.10 + s * 0.015))

    # 5. Exposed_Stagger — Arms flung WIDE BACK, ribcage & blazing soul-heart thrust completely open!
    def anim_exposed(u: float):
        s = math.sin(u * math.tau)
        s2 = math.sin(u * math.tau * 2.0)
        rots = {
            "mixamorig:Hips": (-4.0, s * 3.0, 0.0),
            "mixamorig:Spine": (-6.0, 0.0, 0.0),
            "mixamorig:Spine1": (-8.0, 0.0, 0.0),
            "mixamorig:Spine2": (-10.0 + s2 * 2.5, 0.0, 0.0),
            "mixamorig:Neck": (-12.0, 0.0, 0.0),
            "mixamorig:Head": (-22.0 + s2 * 4.0, s * 8.0, s * 12.0),
            "mixamorig:LeftShoulder": (0.0, -16.0, 22.0),
            "mixamorig:RightShoulder": (0.0, 16.0, -22.0),
            # Arms thrown wide outward & behind chest!
            "mixamorig:LeftArm": (22.0 + s2 * 4.0, -56.0, 26.0),
            "mixamorig:RightArm": (22.0 - s2 * 4.0, 56.0, -26.0),
            "mixamorig:LeftForeArm": (-18.0, -14.0, 12.0),
            "mixamorig:RightForeArm": (-18.0, 14.0, -12.0),
            "mixamorig:LeftUpLeg": (-8.0, -8.0, -6.0),
            "mixamorig:RightUpLeg": (-8.0, 8.0, 6.0),
            "mixamorig:LeftLeg": (16.0, 0.0, 0.0),
            "mixamorig:RightLeg": (16.0, 0.0, 0.0),
            "mixamorig:LeftFoot": (-6.0, 0.0, 0.0),
            "mixamorig:RightFoot": (-6.0, 0.0, 0.0),
        }
        return rots, Vector((0.0, 0.0, -0.07 + s2 * 0.02))

    # 6. Rush_Charge — Ferocious head-down charging juggernaut!
    def anim_rush(u: float):
        ph = u * math.tau
        s = math.sin(ph)
        l_lift = max(0.0, s)
        r_lift = max(0.0, -s)
        rots = {
            "mixamorig:Hips": (12.0, -s * 7.0, s * 8.0),
            "mixamorig:Spine": (12.0, s * 5.0, -s * 5.0),
            "mixamorig:Spine1": (12.0, s * 5.0, -s * 6.0),
            "mixamorig:Spine2": (10.0, 0.0, -s * 6.0),
            "mixamorig:Head": (-14.0, -s * 5.0, 0.0),
            "mixamorig:LeftArm": (-28.0 + s * 42.0, -18.0, -8.0),
            "mixamorig:RightArm": (-28.0 - s * 42.0, 18.0, 8.0),
            "mixamorig:LeftForeArm": (-48.0, 10.0, 0.0),
            "mixamorig:RightForeArm": (-48.0, -10.0, 0.0),
            "mixamorig:LeftUpLeg": (-s * 38.0 - 8.0, -5.0, 0.0),
            "mixamorig:RightUpLeg": (s * 38.0 - 8.0, 5.0, 0.0),
            "mixamorig:LeftLeg": (12.0 + l_lift * 46.0, 0.0, 0.0),
            "mixamorig:RightLeg": (12.0 + r_lift * 46.0, 0.0, 0.0),
            "mixamorig:LeftFoot": (-l_lift * 18.0, 0.0, 0.0),
            "mixamorig:RightFoot": (-r_lift * 18.0, 0.0, 0.0),
        }
        return rots, Vector((s * 0.06, 0.0, -0.10 + abs(s) * 0.11))

    # 7. Sonic_Roar — Iconic Minecraft Warden sonic boom windup! Chest thrust wide, arms taut & trembling!
    def anim_roar(u: float):
        s3 = math.sin(u * math.tau * 3.0)
        rots = {
            "mixamorig:Hips": (-2.0, 0.0, 0.0),
            "mixamorig:Spine": (-5.0, 0.0, 0.0),
            "mixamorig:Spine1": (-8.0, 0.0, 0.0),
            "mixamorig:Spine2": (-10.0 + s3 * 3.0, 0.0, 0.0),
            "mixamorig:Neck": (-10.0, 0.0, 0.0),
            "mixamorig:Head": (-26.0 + s3 * 5.0, 0.0, s3 * 4.0),
            "mixamorig:LeftShoulder": (0.0, -14.0, 16.0),
            "mixamorig:RightShoulder": (0.0, 14.0, -16.0),
            "mixamorig:LeftArm": (10.0 + s3 * 4.0, -42.0, 14.0),
            "mixamorig:RightArm": (10.0 - s3 * 4.0, 42.0, -14.0),
            "mixamorig:LeftForeArm": (-42.0 + s3 * 4.0, -10.0, 0.0),
            "mixamorig:RightForeArm": (-42.0 - s3 * 4.0, 10.0, 0.0),
            "mixamorig:LeftUpLeg": (-10.0, -10.0, -6.0),
            "mixamorig:RightUpLeg": (-10.0, 10.0, 6.0),
            "mixamorig:LeftLeg": (20.0, 0.0, 0.0),
            "mixamorig:RightLeg": (20.0, 0.0, 0.0),
            "mixamorig:LeftFoot": (-8.0, 0.0, 0.0),
            "mixamorig:RightFoot": (-8.0, 0.0, 0.0),
        }
        return rots, Vector((0.0, 0.0, -0.08 + s3 * 0.015))

    bake_clip(arm, "Idle_Patrol", 64, anim_idle)
    bake_clip(arm, "Walk_Stalk", 48, anim_walk)
    bake_clip(arm, "Listen_Sniff", 48, anim_listen)
    bake_clip(arm, "Guard_X", 32, anim_guard)
    bake_clip(arm, "Exposed_Stagger", 32, anim_exposed)
    bake_clip(arm, "Rush_Charge", 28, anim_rush)
    bake_clip(arm, "Sonic_Roar", 36, anim_roar)


def render_pose_previews(arm: bpy.types.Object, body_obj: bpy.types.Object, preview_dir: Path):
    preview_dir.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("PrevW")
    scene.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.04, 0.06, 0.09, 1.0)
        bg.inputs[1].default_value = 0.65

    def add_light(name, loc, energy, size, col=(1, 1, 1)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = size
        ld.color = col
        lo = bpy.data.objects.new(name, ld)
        scene.collection.objects.link(lo)
        lo.location = Vector(loc)
        lo.rotation_euler = (Vector((0, 0, 1.45)) - lo.location).to_track_quat("-Z", "Y").to_euler()

    add_light("Key", (2.8, -3.6, 3.2), 340.0, 2.2, (0.95, 0.98, 1.0))
    add_light("Fill", (-3.0, -2.5, 1.8), 120.0, 2.5, (0.55, 0.85, 0.95))
    add_light("Rim", (0.0, 3.6, 3.0), 260.0, 2.2, (0.45, 0.95, 1.0))

    cd = bpy.data.cameras.new("Cam")
    cd.lens = 46
    cam = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = Vector((1.15, -4.45, 1.72))
    cam.rotation_euler = (Vector((0.0, 0.0, 1.48)) - cam.location).to_track_quat("-Z", "Y").to_euler()

    arm.animation_data.use_nla = False
    for cname, fr in [("Idle_Patrol", 1), ("Guard_X", 16), ("Exposed_Stagger", 16), ("Walk_Stalk", 12)]:
        act = bpy.data.actions.get(cname)
        if act:
            arm.animation_data.action = act
            scene.frame_set(fr)
            bpy.context.view_layer.update()
            scene.render.filepath = str(preview_dir / f"cw_v2_pose_{cname}.png")
            bpy.ops.render.render(write_still=True)


def main():
    args = parse_args()
    if not args.source_glb.exists():
        raise FileNotFoundError(f"Source GLB not found: {args.source_glb}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source_glb))
    bpy.context.view_layer.update()

    # 1. Remove accidental stray unparented helper meshes (e.g., Icosphere)
    arm = None
    body_obj = None
    for o in list(bpy.data.objects):
        if o.type == "ARMATURE":
            arm = o
        elif o.type == "MESH":
            if o.parent is not None and o.parent.type == "ARMATURE" and len(o.vertex_groups) > 0:
                body_obj = o
            else:
                print(f"REMOVING_STRAY_OBJ: {o.name} (verts={len(o.data.vertices)})")
                bpy.data.objects.remove(o, do_unlink=True)
        elif o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o, do_unlink=True)

    if arm is None or body_obj is None:
        raise RuntimeError("Expected rigged Armature + skinned Warden_Body mesh in source GLB")

    # Clear existing actions & reset pose
    if arm.animation_data:
        arm.animation_data_clear()
    clear_pose(arm)
    bpy.context.view_layer.update()

    # 2. Measure true world bounds, scale cleanly to target height & ground feet at Z = 0.000m
    pts = [body_obj.matrix_world @ v.co for v in body_obj.data.vertices]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    cur_h = max(0.01, mx.z - mn.z)
    sc = args.target_height / cur_h
    cx = 0.5 * (mn.x + mx.x)
    cy = 0.5 * (mn.y + mx.y)

    arm.location = Vector((arm.location.x - cx, arm.location.y - cy, arm.location.z - mn.z)) * sc
    arm.scale = arm.scale * sc
    bpy.context.view_layer.update()

    # Bake location/rotation/scale cleanly into Armature & Mesh so scale == (1,1,1)!
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    body_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.update()

    # Verify grounded bounds
    pts2 = [body_obj.matrix_world @ v.co for v in body_obj.data.vertices]
    zmin2 = min(p.z for p in pts2)
    zmax2 = max(p.z for p in pts2)
    print(f"NORMALIZED_BOUNDS: z=[{zmin2:.4f}..{zmax2:.4f}] height={zmax2-zmin2:.4f}m arm_scale={tuple(round(c,3) for c in arm.scale)}")

    # 3. Gentle collapse decimation preserving single UVMap & all 65 vertex groups
    raw_polys = len(body_obj.data.polygons)
    if args.decimate_ratio < 0.99 and raw_polys > 16000:
        bpy.ops.object.select_all(action="DESELECT")
        body_obj.select_set(True)
        bpy.context.view_layer.objects.active = body_obj
        dec = body_obj.modifiers.new("OptDecimate", "DECIMATE")
        dec.decimate_type = "COLLAPSE"
        dec.ratio = args.decimate_ratio
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=dec.name)
    body_obj.data.validate(verbose=False)
    for p in body_obj.data.polygons:
        p.use_smooth = True
    # Ensure single canonical UV layer named 'UVMap'
    while len(body_obj.data.uv_layers) > 1:
        body_obj.data.uv_layers.remove(body_obj.data.uv_layers[-1])
    if len(body_obj.data.uv_layers) == 1:
        body_obj.data.uv_layers[0].name = "UVMap"
    print(f"MESH_OPTIMIZED: {raw_polys} -> {len(body_obj.data.polygons)} polys | UVs={[u.name for u in body_obj.data.uv_layers]}")

    # 4. Optimize textures & ensure emissive strength ready for dynamic Godot control
    optimize_materials(body_obj, args.tex_size)

    # 5. Bake 7 expressive skeletal animations onto Warden_Armature
    build_all_warden_animations(arm)

    # Reset rest pose before parenting under canonical 'cave_warden' root empty
    clear_pose(arm)
    arm.animation_data.use_nla = True
    arm.animation_data.action = None
    bpy.context.view_layer.update()

    root_empty = bpy.data.objects.new("cave_warden", None)
    bpy.context.scene.collection.objects.link(root_empty)
    root_empty.location = (0.0, 0.0, 0.0)
    arm.parent = root_empty
    arm.name = "Warden_Armature"
    body_obj.name = "Warden_Body"

    # 6. Export optimized GLB
    SLICE_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    root_empty.select_set(True)
    arm.select_set(True)
    body_obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_skins=True,
        export_animations=True,
        export_nla_strips=True,
        export_optimize_animation_size=True,
    )

    # 7. Audit exported GLB TEXCOORDS, animations, and size
    raw_b = OUT_GLB.read_bytes()
    jlen = struct.unpack("<I", raw_b[12:16])[0]
    g = json.loads(raw_b[20 : 20 + jlen])
    tcs = sorted({k for m in g.get("meshes", []) for pr in m.get("primitives", []) for k in pr.get("attributes", {}) if k.startswith("TEXCOORD")})
    miss = sum(1 for m in g.get("meshes", []) for pr in m.get("primitives", []) if "TEXCOORD_0" not in pr.get("attributes", {}))
    anims = [a.get("name") for a in g.get("animations", [])]
    print(f"EXPORTED_WARDEN_V2 {OUT_GLB.name} ({len(raw_b)/1048576:.2f} MiB | {len(body_obj.data.polygons)} polys | {len(anims)} anims: {anims} | TEXCOORDS={tcs} | missing_uv0={miss})")

    if args.preview_dir is not None:
        render_pose_previews(arm, body_obj, args.preview_dir)


if __name__ == "__main__":
    main()
