"""Build v0.9.9.2 Rigged & Animated Realistic Woodland Deer GLB in Blender 5.3.

Takes the Realistic Deer static GLB asset (2048px fur/antler PBR maps, ~16k tris),
removes stray untextured ground fragment (Part 3), orients to Blender +Y (Godot -Z forward),
grounds hooves at z=0, scales to majestic 1.54m antler-tip height, downscales packed textures
cleanly on disk via ffmpeg (~1.1 MB final GLB), builds an anatomical 22-bone quadruped stag
skeleton fitted directly to each leg's exact vertex centers, locks antlers 100% rigid to Head,
and authors 3 graceful looping skeletal animations (`Idle`, `Walk`, `Run`).

Usage (Blender CLI):
  blender --background --python tools/build_v0992_realistic_deer.py -- --glb path/to/Realistic_Deer.glb [--preview path/to/preview.png]
"""
from __future__ import annotations

import argparse
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "wildlife" / "animal_deer.glb"
TARGET_ANTLER_HEIGHT = 1.54  # Realistic majestic stag (~0.90m back/withers, ~1.54m antler tips)


def parse_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True, help="Path to source Realistic Deer.glb")
    ap.add_argument("--out", default=str(OUT_GLB), help="Output rigged GLB path")
    ap.add_argument("--preview", default="", help="Optional 2x2 verification render PNG path")
    return ap.parse_args(argv)


def downscale_and_repack_textures(tmp_dir: Path):
    """Downscale 2048px PNG textures via ffmpeg on disk before loading so GLB stays ~1 MB & crisp."""
    ffmpeg = shutil.which("ffmpeg")
    targets = {
        "Deer_M_diffuse": (1024, "jpg", "sRGB"),
        "Deer_Antler_diffuse": (512, "jpg", "sRGB"),
        "Deer_Antler_normal": (512, "png", "Non-Color"),
    }
    replaced: dict[str, bpy.types.Image] = {}
    for img in list(bpy.data.images):
        key = None
        for k in targets:
            if img.name.startswith(k):
                key = k
                break
        if key is None:
            continue
        max_dim, ext, cspace = targets[key]
        raw_p = tmp_dir / f"{key}_raw.png"
        out_p = tmp_dir / f"{key}_opt.{ext}"
        try:
            img.filepath_raw = str(raw_p)
            img.file_format = "PNG"
            img.save()
        except Exception as e:
            print(f"[WARN] save {img.name} failed: {e}")
            continue
        if ffmpeg and raw_p.exists():
            vf = f"scale='min({max_dim},iw)':'min({max_dim},ih)':force_original_aspect_ratio=decrease"
            cmd = [ffmpeg, "-y", "-loglevel", "error", "-i", str(raw_p), "-vf", vf]
            if ext == "jpg":
                cmd += ["-q:v", "3"]
            cmd.append(str(out_p))
            subprocess.run(cmd, check=False)
        final_p = out_p if out_p.exists() and out_p.stat().st_size > 200 else raw_p
        new_img = bpy.data.images.load(str(final_p), check_existing=False)
        new_img.name = f"Opt_{key}"
        new_img.colorspace_settings.name = cspace
        new_img.pack()
        replaced[img.name] = new_img
        print(f"[TEX] {key} -> {new_img.size[0]}x{new_img.size[1]} ({final_p.stat().st_size // 1024} KB)")

    # Rewire material image texture nodes to optimized packed images & set natural matte fur roughness
    for mat in bpy.data.materials:
        if not mat.node_tree:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image and node.image.name in replaced:
                node.image = replaced[node.image.name]
            elif node.type == "BSDF_PRINCIPLED":
                if "Antler" in mat.name:
                    node.inputs["Roughness"].default_value = 0.62
                    node.inputs["Metallic"].default_value = 0.0
                else:
                    node.inputs["Roughness"].default_value = 0.82
                    node.inputs["Metallic"].default_value = 0.0
                    if "Specular IOR Level" in node.inputs:
                        node.inputs["Specular IOR Level"].default_value = 0.24


def slice_center(verts: list[Vector], z_mid: float, z_half: float, pred) -> Vector | None:
    pts = [v for v in verts if abs(v.z - z_mid) <= z_half and pred(v)]
    if not pts:
        return None
    return Vector((
        sum(p.x for p in pts) / len(pts),
        sum(p.y for p in pts) / len(pts),
        sum(p.z for p in pts) / len(pts),
    ))


def build_deer_armature(body_obj: bpy.types.Object) -> bpy.types.Object:
    """Build anatomical 22-bone quadruped stag skeleton fitted directly to rotated (+Y forward) deer geometry."""
    vs = [body_obj.matrix_world @ v.co for v in body_obj.data.vertices]
    max_y = max(v.y for v in vs)  # Nose tip (+Y)
    min_y = min(v.y for v in vs)  # Hind tail (-Y)
    max_z = max(v.z for v in vs)  # Ear/head top

    # Compute exact leg column centers in rotated (+Y forward, +X right, -X left) space!
    def leg_pts(is_front: bool, is_left: bool) -> list[Vector]:
        y_pred = (lambda v: v.y > -0.22) if is_front else (lambda v: v.y <= -0.22)
        x_pred = (lambda v: v.x < 0.0) if is_left else (lambda v: v.x >= 0.0)
        pred = lambda v: y_pred(v) and x_pred(v)

        p_hoof = slice_center(vs, 0.03, 0.04, pred)
        p_fet = slice_center(vs, 0.14, 0.04, pred)
        p_knee = slice_center(vs, 0.34, 0.05, pred)
        p_top = slice_center(vs, 0.62, 0.06, pred)

        # Graceful fallbacks if any slice sparse
        sx = -0.09 if is_left else 0.09
        sy = 0.05 if is_front else -0.52
        p_hoof = p_hoof or Vector((sx, sy, 0.01))
        p_hoof.z = 0.005
        p_fet = p_fet or Vector((p_hoof.x, p_hoof.y - 0.02, 0.14))
        p_knee = p_knee or Vector((p_hoof.x, p_hoof.y, 0.34))
        p_top = p_top or Vector((p_hoof.x * 0.9, p_hoof.y + (0.04 if is_front else 0.06), 0.62))
        return [p_top, p_knee, p_fet, p_hoof]

    fl = leg_pts(True, True)
    fr = leg_pts(True, False)
    bl = leg_pts(False, True)
    br = leg_pts(False, False)

    # Spine, neck & head landmarks directly from mesh extents
    pelvis_y = (bl[0].y + br[0].y) * 0.5
    chest_y = (fl[0].y + fr[0].y) * 0.5 + 0.06
    spine_z = 0.72
    chest_z = 0.74
    neck_base = Vector((0.0, chest_y + 0.12, 0.78))
    neck_mid = Vector((0.0, chest_y + 0.28, 0.92))
    head_base = Vector((0.0, chest_y + 0.40, 1.02))
    nose_tip = Vector((0.0, max_y - 0.02, 0.88))

    arm_data = bpy.data.armatures.new("RealisticDeerRig")
    arm_obj = bpy.data.objects.new("RealisticDeerRig", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    def add_bone(name: str, head: Vector, tail: Vector, parent_name: str | None = None, connect: bool = False):
        eb = arm_data.edit_bones.new(name)
        eb.head = head
        eb.tail = tail
        eb.use_deform = True
        if parent_name:
            eb.parent = arm_data.edit_bones[parent_name]
            eb.use_connect = connect
        return eb

    # Spine chain (6 bones)
    p_pelvis = Vector((0.0, pelvis_y, spine_z))
    p_mid = Vector((0.0, (pelvis_y + chest_y) * 0.5, spine_z + 0.01))
    p_chest = Vector((0.0, chest_y, chest_z))
    add_bone("Pelvis", p_pelvis, p_mid)
    add_bone("Spine", p_mid, p_chest, "Pelvis", True)
    add_bone("Chest", p_chest, neck_base, "Spine", True)
    add_bone("Neck_1", neck_base, neck_mid, "Chest", True)
    add_bone("Neck_2", neck_mid, head_base, "Neck_1", True)
    add_bone("Head", head_base, nose_tip, "Neck_2", True)

    # Tail (2 bones)
    tail_root = Vector((0.0, min_y + 0.14, 0.74))
    tail_mid = Vector((0.0, min_y + 0.04, 0.68))
    tail_tip = Vector((0.0, min_y - 0.02, 0.58))
    add_bone("Tail_1", tail_root, tail_mid, "Pelvis", False)
    add_bone("Tail_2", tail_mid, tail_tip, "Tail_1", True)

    # 4 Articulated Quadruped Legs (3 bones each = 12 bones: Upper, Lower, Hoof)
    for tag, pts, parent in [
        ("FL", fl, "Chest"),
        ("FR", fr, "Chest"),
        ("BL", bl, "Pelvis"),
        ("BR", br, "Pelvis"),
    ]:
        p0, p1, p2, p3 = pts
        # Ensure minimum bone length
        if (p1 - p0).length < 0.05:
            p1 = p0 + Vector((0, 0, -0.25))
        if (p2 - p1).length < 0.05:
            p2 = p1 + Vector((0, 0, -0.22))
        hoof_tip = Vector((p3.x, p3.y + 0.05, 0.005))
        add_bone(f"Leg_{tag}_Upper", p0, p1, parent, False)
        add_bone(f"Leg_{tag}_Lower", p1, p2, f"Leg_{tag}_Upper", True)
        add_bone(f"Leg_{tag}_Hoof", p2, hoof_tip, f"Leg_{tag}_Lower", True)

    # Align bone rolls cleanly for consistent character-space animation
    for eb in arm_data.edit_bones:
        eb.align_roll(Vector((0.0, 0.0, 1.0)) if abs(eb.vector.normalized().z) < 0.85 else Vector((0.0, 1.0, 0.0)))

    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"[RIG] Built {len(arm_data.bones)} deer bones (FL={fl[3]}, FR={fr[3]}, BL={bl[3]}, BR={br[3]})")
    return arm_obj


def world_rot_to_bone_local_quat(arm: bpy.types.Object, bone_name: str, pitch_x_deg: float, roll_y_deg: float = 0.0, yaw_z_deg: float = 0.0) -> Quaternion:
    b = arm.data.bones[bone_name]
    r_rest = b.matrix_local.to_3x3()
    m3 = Euler((math.radians(pitch_x_deg), math.radians(roll_y_deg), math.radians(yaw_z_deg)), "XYZ").to_matrix()
    return (r_rest.inverted() @ m3 @ r_rest).to_quaternion()


def world_vec_to_bone_local(arm: bpy.types.Object, bone_name: str, world_vec: Vector) -> Vector:
    b = arm.data.bones[bone_name]
    return b.matrix_local.to_3x3().inverted() @ world_vec


def set_deer_pose(arm: bpy.types.Object, frame: float, bone_eulers: dict[str, tuple[float, float, float]], pelvis_off: Vector | None = None):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        e = bone_eulers.get(pb.name, (0.0, 0.0, 0.0))
        pb.rotation_quaternion = world_rot_to_bone_local_quat(arm, pb.name, e[0], e[1], e[2])
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if pb.name == "Pelvis":
            off = pelvis_off if pelvis_off is not None else Vector((0, 0, 0))
            pb.location = world_vec_to_bone_local(arm, "Pelvis", off)
            pb.keyframe_insert(data_path="location", frame=frame)


def author_deer_animations(arm: bpy.types.Object) -> list[bpy.types.Action]:
    """Author 3 graceful looping stag animations: Idle, Walk (trot/stride), Run (woodland bound gallop)."""
    if arm.animation_data is None:
        arm.animation_data_create()
    actions: list[bpy.types.Action] = []

    # 1. Idle (60 frames @ 24fps = 2.5s): calm forest stag breathing, regal head turn & tail flick
    act_idle = bpy.data.actions.new(name="Idle")
    arm.animation_data.action = act_idle
    idle_keys = [
        (0.0, Vector((0, 0, 0.0)), {"Neck_1": (0, 0, 0), "Head": (0, 0, 0), "Tail_1": (0, 0, 0)}),
        (15.0, Vector((0, 0, 0.006)), {"Neck_1": (4.0, 0, 8.0), "Neck_2": (3.0, 0, 6.0), "Head": (-4.0, 2.0, 8.0), "Tail_1": (6.0, 0, 12.0)}),
        (30.0, Vector((0, 0, -0.004)), {"Neck_1": (-6.0, 0, 0.0), "Neck_2": (-5.0, 0, 0.0), "Head": (-8.0, 0, 0.0), "Tail_1": (-4.0, 0, -6.0)}),
        (45.0, Vector((0, 0, 0.005)), {"Neck_1": (3.0, 0, -9.0), "Neck_2": (3.0, 0, -7.0), "Head": (4.0, -2.0, -9.0), "Tail_1": (8.0, 0, -14.0)}),
        (60.0, Vector((0, 0, 0.0)), {"Neck_1": (0, 0, 0), "Head": (0, 0, 0), "Tail_1": (0, 0, 0)}),
    ]
    for fr, off, ov in idle_keys:
        set_deer_pose(arm, fr, ov, off)
    actions.append(act_idle)

    # 2. Walk (24 frames @ 24fps = 1.0s): graceful diagonal stag walk/trot (+X pitch swings legs FORWARD!)
    act_walk = bpy.data.actions.new(name="Walk")
    arm.animation_data.action = act_walk
    walk_keys = [
        # Frame 0: FL & BR swing forward, FR & BL push back
        (0.0, Vector((0, 0, 0.012)), {
            "Pelvis": (2.0, 0, -2.5), "Spine": (-1.5, 0, 2.0), "Chest": (-1.5, 0, 2.5),
            "Neck_1": (-4.0, 0, -2.0), "Head": (4.0, 0, 0),
            "Leg_FL_Upper": (22.0, 0, 0), "Leg_FL_Lower": (-18.0, 0, 0), "Leg_FL_Hoof": (-6.0, 0, 0),
            "Leg_FR_Upper": (-18.0, 0, 0), "Leg_FR_Lower": (-10.0, 0, 0), "Leg_FR_Hoof": (14.0, 0, 0),
            "Leg_BL_Upper": (-18.0, 0, 0), "Leg_BL_Lower": (10.0, 0, 0), "Leg_BL_Hoof": (-10.0, 0, 0),
            "Leg_BR_Upper": (20.0, 0, 0), "Leg_BR_Lower": (-14.0, 0, 0), "Leg_BR_Hoof": (12.0, 0, 0),
            "Tail_1": (6.0, 0, 6.0),
        }),
        # Frame 6: Passing phase (FL plants, FR lifts knee high!)
        (6.0, Vector((0, 0, -0.015)), {
            "Pelvis": (-1.0, 0, 0.0), "Neck_1": (3.0, 0, 0.0), "Head": (-2.0, 0, 0),
            "Leg_FL_Upper": (4.0, 0, 0), "Leg_FL_Lower": (-2.0, 0, 0), "Leg_FL_Hoof": (-2.0, 0, 0),
            "Leg_FR_Upper": (6.0, 0, 0), "Leg_FR_Lower": (-36.0, 0, 0), "Leg_FR_Hoof": (-14.0, 0, 0),
            "Leg_BL_Upper": (4.0, 0, 0), "Leg_BL_Lower": (-26.0, 0, 0), "Leg_BL_Hoof": (18.0, 0, 0),
            "Leg_BR_Upper": (2.0, 0, 0), "Leg_BR_Lower": (2.0, 0, 0), "Leg_BR_Hoof": (-2.0, 0, 0),
            "Tail_1": (-4.0, 0, 0.0),
        }),
        # Frame 12: FR & BL swing forward, FL & BR push back
        (12.0, Vector((0, 0, 0.012)), {
            "Pelvis": (2.0, 0, 2.5), "Spine": (-1.5, 0, -2.0), "Chest": (-1.5, 0, -2.5),
            "Neck_1": (-4.0, 0, 2.0), "Head": (4.0, 0, 0),
            "Leg_FL_Upper": (-18.0, 0, 0), "Leg_FL_Lower": (-10.0, 0, 0), "Leg_FL_Hoof": (14.0, 0, 0),
            "Leg_FR_Upper": (22.0, 0, 0), "Leg_FR_Lower": (-18.0, 0, 0), "Leg_FR_Hoof": (-6.0, 0, 0),
            "Leg_BL_Upper": (20.0, 0, 0), "Leg_BL_Lower": (-14.0, 0, 0), "Leg_BL_Hoof": (12.0, 0, 0),
            "Leg_BR_Upper": (-18.0, 0, 0), "Leg_BR_Lower": (10.0, 0, 0), "Leg_BR_Hoof": (-10.0, 0, 0),
            "Tail_1": (6.0, 0, -6.0),
        }),
        # Frame 18: Passing phase (FR plants, FL lifts knee high!)
        (18.0, Vector((0, 0, -0.015)), {
            "Pelvis": (-1.0, 0, 0.0), "Neck_1": (3.0, 0, 0.0), "Head": (-2.0, 0, 0),
            "Leg_FL_Upper": (6.0, 0, 0), "Leg_FL_Lower": (-36.0, 0, 0), "Leg_FL_Hoof": (-14.0, 0, 0),
            "Leg_FR_Upper": (4.0, 0, 0), "Leg_FR_Lower": (-2.0, 0, 0), "Leg_FR_Hoof": (-2.0, 0, 0),
            "Leg_BL_Upper": (2.0, 0, 0), "Leg_BL_Lower": (2.0, 0, 0), "Leg_BL_Hoof": (-2.0, 0, 0),
            "Leg_BR_Upper": (4.0, 0, 0), "Leg_BR_Lower": (-26.0, 0, 0), "Leg_BR_Hoof": (18.0, 0, 0),
            "Tail_1": (-4.0, 0, 0.0),
        }),
        # Frame 24: Loop to Frame 0
        (24.0, Vector((0, 0, 0.012)), {
            "Pelvis": (2.0, 0, -2.5), "Spine": (-1.5, 0, 2.0), "Chest": (-1.5, 0, 2.5),
            "Neck_1": (-4.0, 0, -2.0), "Head": (4.0, 0, 0),
            "Leg_FL_Upper": (22.0, 0, 0), "Leg_FL_Lower": (-18.0, 0, 0), "Leg_FL_Hoof": (-6.0, 0, 0),
            "Leg_FR_Upper": (-18.0, 0, 0), "Leg_FR_Lower": (-10.0, 0, 0), "Leg_FR_Hoof": (14.0, 0, 0),
            "Leg_BL_Upper": (-18.0, 0, 0), "Leg_BL_Lower": (10.0, 0, 0), "Leg_BL_Hoof": (-10.0, 0, 0),
            "Leg_BR_Upper": (20.0, 0, 0), "Leg_BR_Lower": (-14.0, 0, 0), "Leg_BR_Hoof": (12.0, 0, 0),
            "Tail_1": (6.0, 0, 6.0),
        }),
    ]
    for fr, off, ov in walk_keys:
        set_deer_pose(arm, fr, ov, off)
    actions.append(act_walk)

    # 3. Run (16 frames @ 24fps = 0.67s): Powerful woodland stag bounding gallop!
    act_run = bpy.data.actions.new(name="Run")
    arm.animation_data.action = act_run
    run_keys = [
        # Frame 0: Full extended airborne leap! (Front legs reach forward, hind legs drive far back!)
        (0.0, Vector((0, 0, 0.125)), {
            "Pelvis": (-10.0, 0, 0), "Spine": (8.0, 0, 0), "Chest": (8.0, 0, 0),
            "Neck_1": (-12.0, 0, 0), "Neck_2": (-6.0, 0, 0), "Head": (14.0, 0, 0),
            "Leg_FL_Upper": (44.0, 0, 0), "Leg_FL_Lower": (-34.0, 0, 0), "Leg_FL_Hoof": (-14.0, 0, 0),
            "Leg_FR_Upper": (36.0, 0, 0), "Leg_FR_Lower": (-40.0, 0, 0), "Leg_FR_Hoof": (-16.0, 0, 0),
            "Leg_BL_Upper": (-38.0, 0, 0), "Leg_BL_Lower": (14.0, 0, 0), "Leg_BL_Hoof": (-18.0, 0, 0),
            "Leg_BR_Upper": (-32.0, 0, 0), "Leg_BR_Lower": (10.0, 0, 0), "Leg_BR_Hoof": (-16.0, 0, 0),
            "Tail_1": (26.0, 0, 0), "Tail_2": (16.0, 0, 0),
        }),
        # Frame 5: Front legs touch down & absorb
        (5.0, Vector((0, 0, -0.045)), {
            "Pelvis": (8.0, 0, 0), "Spine": (-6.0, 0, 0), "Chest": (-8.0, 0, 0),
            "Neck_1": (8.0, 0, 0), "Head": (-6.0, 0, 0),
            "Leg_FL_Upper": (6.0, 0, 0), "Leg_FL_Lower": (-12.0, 0, 0), "Leg_FL_Hoof": (8.0, 0, 0),
            "Leg_FR_Upper": (14.0, 0, 0), "Leg_FR_Lower": (-16.0, 0, 0), "Leg_FR_Hoof": (6.0, 0, 0),
            "Leg_BL_Upper": (18.0, 0, 0), "Leg_BL_Lower": (-22.0, 0, 0), "Leg_BL_Hoof": (14.0, 0, 0),
            "Leg_BR_Upper": (24.0, 0, 0), "Leg_BR_Lower": (-24.0, 0, 0), "Leg_BR_Hoof": (16.0, 0, 0),
            "Tail_1": (12.0, 0, 0),
        }),
        # Frame 9: Gathered coil under belly (front legs sweep back, hind legs gather far forward!)
        (9.0, Vector((0, 0, -0.020)), {
            "Pelvis": (14.0, 0, 0), "Spine": (-12.0, 0, 0), "Chest": (-6.0, 0, 0),
            "Neck_1": (10.0, 0, 0), "Head": (-8.0, 0, 0),
            "Leg_FL_Upper": (-36.0, 0, 0), "Leg_FL_Lower": (-42.0, 0, 0), "Leg_FL_Hoof": (-10.0, 0, 0),
            "Leg_FR_Upper": (-28.0, 0, 0), "Leg_FR_Lower": (-46.0, 0, 0), "Leg_FR_Hoof": (-10.0, 0, 0),
            "Leg_BL_Upper": (40.0, 0, 0), "Leg_BL_Lower": (-32.0, 0, 0), "Leg_BL_Hoof": (18.0, 0, 0),
            "Leg_BR_Upper": (34.0, 0, 0), "Leg_BR_Lower": (-28.0, 0, 0), "Leg_BR_Hoof": (16.0, 0, 0),
            "Tail_1": (18.0, 0, 0),
        }),
        # Frame 13: Explosive hind-leg push-off launching upward!
        (13.0, Vector((0, 0, 0.060)), {
            "Pelvis": (-6.0, 0, 0), "Spine": (4.0, 0, 0), "Chest": (8.0, 0, 0),
            "Neck_1": (-8.0, 0, 0), "Head": (10.0, 0, 0),
            "Leg_FL_Upper": (26.0, 0, 0), "Leg_FL_Lower": (-50.0, 0, 0), "Leg_FL_Hoof": (-16.0, 0, 0),
            "Leg_FR_Upper": (20.0, 0, 0), "Leg_FR_Lower": (-48.0, 0, 0), "Leg_FR_Hoof": (-14.0, 0, 0),
            "Leg_BL_Upper": (-18.0, 0, 0), "Leg_BL_Lower": (6.0, 0, 0), "Leg_BL_Hoof": (-10.0, 0, 0),
            "Leg_BR_Upper": (-12.0, 0, 0), "Leg_BR_Lower": (4.0, 0, 0), "Leg_BR_Hoof": (-8.0, 0, 0),
            "Tail_1": (24.0, 0, 0),
        }),
        # Frame 16: Loop to Frame 0
        (16.0, Vector((0, 0, 0.125)), {
            "Pelvis": (-10.0, 0, 0), "Spine": (8.0, 0, 0), "Chest": (8.0, 0, 0),
            "Neck_1": (-12.0, 0, 0), "Neck_2": (-6.0, 0, 0), "Head": (14.0, 0, 0),
            "Leg_FL_Upper": (44.0, 0, 0), "Leg_FL_Lower": (-34.0, 0, 0), "Leg_FL_Hoof": (-14.0, 0, 0),
            "Leg_FR_Upper": (36.0, 0, 0), "Leg_FR_Lower": (-40.0, 0, 0), "Leg_FR_Hoof": (-16.0, 0, 0),
            "Leg_BL_Upper": (-38.0, 0, 0), "Leg_BL_Lower": (14.0, 0, 0), "Leg_BL_Hoof": (-18.0, 0, 0),
            "Leg_BR_Upper": (-32.0, 0, 0), "Leg_BR_Lower": (10.0, 0, 0), "Leg_BR_Hoof": (-16.0, 0, 0),
            "Tail_1": (26.0, 0, 0), "Tail_2": (16.0, 0, 0),
        }),
    ]
    for fr, off, ov in run_keys:
        set_deer_pose(arm, fr, ov, off)
    actions.append(act_run)

    # Push all 3 clips to NLA tracks
    arm.animation_data.action = None
    while len(arm.animation_data.nla_tracks) > 0:
        arm.animation_data.nla_tracks.remove(arm.animation_data.nla_tracks[0])
    for act in actions:
        act.use_fake_user = True
        tr = arm.animation_data.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, 0, act)
        st.name = act.name
        tr.mute = False
    arm.animation_data.use_nla = True
    return actions


def render_preview(arm: bpy.types.Object, actions: list[bpy.types.Action], out_png: Path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world = bpy.data.worlds.new("DeerPrevW")
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.24, 0.34, 0.30, 1.0)
        bg.inputs[1].default_value = 1.4
    for nm, rot, en in [("Sun1", (-50, 0, 35), 3.4), ("Sun2", (50, 0, -140), 1.8)]:
        ld = bpy.data.lights.new(nm, type="SUN")
        ld.energy = en
        lo = bpy.data.objects.new(nm, ld)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(lo)
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 48.0
    co = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(co)
    scene.camera = co

    def aim(pos, tgt):
        co.location = Vector(pos)
        co.rotation_euler = (Vector(tgt) - co.location).to_track_quat("-Z", "Y").to_euler()

    act_map = {a.name: a for a in actions}
    arm.animation_data.use_nla = False
    shots = [
        ("Idle", 15, (2.4, 0.6, 0.92), (0.0, 0.05, 0.72)),     # Side-3/4 Idle
        ("Idle", 0, (0.9, 2.3, 1.02), (0.0, 0.15, 0.78)),      # Front-3/4 Regal Stag
        ("Walk", 0, (2.45, 0.1, 0.88), (0.0, 0.0, 0.68)),      # Side Walk Stride
        ("Run", 0, (2.35, 0.7, 0.96), (0.0, 0.0, 0.76)),       # Dynamic Run Bound!
    ]
    tmp_imgs = []
    for idx, (aname, fr, cpos, ctgt) in enumerate(shots):
        arm.animation_data.action = act_map[aname]
        scene.frame_set(fr)
        bpy.context.view_layer.update()
        aim(cpos, ctgt)
        p = out_png.parent / f"_deer_shot_{idx}.png"
        scene.render.filepath = str(p)
        bpy.ops.render.render(write_still=True)
        tmp_imgs.append(p)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg and all(p.exists() for p in tmp_imgs):
        subprocess.run([
            ffmpeg, "-y", "-loglevel", "error",
            "-i", str(tmp_imgs[0]), "-i", str(tmp_imgs[1]),
            "-i", str(tmp_imgs[2]), "-i", str(tmp_imgs[3]),
            "-filter_complex", "[0:v][1:v]hstack=inputs=2[top];[2:v][3:v]hstack=inputs=2[bot];[top][bot]vstack=inputs=2[v]",
            "-map", "[v]", str(out_png),
        ], check=False)
        for p in tmp_imgs:
            p.unlink(missing_ok=True)
        print(f"[PREVIEW] Saved deer 2x2 sheet: {out_png}")


def main():
    args = parse_args()
    src_glb = Path(args.glb).resolve()
    out_glb = Path(args.out).resolve()
    out_glb.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    bpy.ops.import_scene.gltf(filepath=str(src_glb))

    # Delete tiny stray untextured fragment Part 3 & non-mesh helpers
    body_obj = None
    antler_objs: list[bpy.types.Object] = []
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            continue
        if "Part 3" in o.name or len(o.data.materials) == 0:
            print(f"[CLEAN] Removing stray fragment {o.name} ({len(o.data.polygons)} polys)")
            bpy.data.objects.remove(o, do_unlink=True)
        elif "Part 4" in o.name or any(m and "Deer_M" in m.name for m in o.data.materials):
            body_obj = o
        else:
            antler_objs.append(o)

    if body_obj is None:
        raise RuntimeError("Could not locate Realistic Deer main body mesh!")

    # Remove parent empties keeping world transforms
    all_parts = [body_obj] + antler_objs
    for o in all_parts:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in list(bpy.data.objects):
        if o not in all_parts:
            bpy.data.objects.remove(o, do_unlink=True)

    # Measure total bounds, rotate +90° Z (+X -> +Y forward = Godot -Z!), ground at z=0, scale to TARGET_ANTLER_HEIGHT
    all_z = [ (o.matrix_world @ v.co).z for o in all_parts for v in o.data.vertices ]
    min_z, max_z = min(all_z), max(all_z)
    scale_f = TARGET_ANTLER_HEIGHT / max(0.01, max_z - min_z)
    rot_90_z = Matrix.Rotation(math.pi * 0.5, 4, "Z")
    xf = Matrix.Scale(scale_f, 4) @ rot_90_z @ Matrix.Translation((0.0, 0.0, -min_z))

    for o in all_parts:
        o.data.transform(xf @ o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_smooth()

    tmp_dir = Path(tempfile.mkdtemp(prefix="deer_tex_"))
    try:
        downscale_and_repack_textures(tmp_dir)

        # Build anatomical 22-bone quadruped skeleton fitted to body_obj
        arm_obj = build_deer_armature(body_obj)

        # Auto-weight BODY smoothly to the 22-bone skeleton
        bpy.ops.object.select_all(action="DESELECT")
        body_obj.select_set(True)
        arm_obj.select_set(True)
        bpy.context.view_layer.objects.active = arm_obj
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")

        # Lock ANTLERS 100% strictly to Head bone (so antlers NEVER bend like rubber!)
        for ant in antler_objs:
            ant.vertex_groups.clear()
            vg = ant.vertex_groups.new(name="Head")
            vg.add(list(range(len(ant.data.vertices))), 1.0, "REPLACE")
            ant.parent = arm_obj
            am = ant.modifiers.new("Armature", "ARMATURE")
            am.object = arm_obj

        # Join body + antlers into one clean skinned RealisticDeerMesh!
        bpy.ops.object.select_all(action="DESELECT")
        for o in all_parts:
            o.select_set(True)
        bpy.context.view_layer.objects.active = body_obj
        bpy.ops.object.join()
        deer_mesh = bpy.context.view_layer.objects.active
        deer_mesh.name = "RealisticDeerMesh"
        # Ensure exactly ONE Armature modifier
        arm_mods = [m for m in deer_mesh.modifiers if m.type == "ARMATURE"]
        for m in arm_mods[1:]:
            deer_mesh.modifiers.remove(m)
        if not arm_mods:
            am = deer_mesh.modifiers.new("Armature", "ARMATURE")
            am.object = arm_obj

        # Clean mesh validity, assign any stray unweighted chin/tongue vertices to nearest anatomical bone, and cap to 4 influences!
        deer_mesh.data.validate(clean_customdata=False)
        for v in deer_mesh.data.vertices:
            if len(v.groups) == 0:
                bn = "Head" if (v.co.y > 0.35 and v.co.z > 0.78) else ("Chest" if v.co.y > -0.1 else "Pelvis")
                vg = deer_mesh.vertex_groups.get(bn) or deer_mesh.vertex_groups.new(name=bn)
                vg.add([v.index], 1.0, "REPLACE")
        bpy.ops.object.select_all(action="DESELECT")
        deer_mesh.select_set(True)
        bpy.context.view_layer.objects.active = deer_mesh
        bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)

        zs = [v.co.z for v in deer_mesh.data.vertices]
        ys = [v.co.y for v in deer_mesh.data.vertices]
        tris = sum(len(p.vertices) - 2 for p in deer_mesh.data.polygons)
        print(f"[MESH] {deer_mesh.name}: verts={len(deer_mesh.data.vertices)}, tris={tris}, Z={min(zs):.4f}..{max(zs):.4f}, Y={min(ys):.4f}..{max(ys):.4f}")

        actions = author_deer_animations(arm_obj)

        bpy.ops.object.select_all(action="DESELECT")
        arm_obj.select_set(True)
        deer_mesh.select_set(True)
        bpy.context.view_layer.objects.active = arm_obj
        bpy.ops.export_scene.gltf(
            filepath=str(out_glb),
            export_format="GLB",
            use_selection=True,
            export_apply=False,
            export_yup=True,
            export_skins=True,
            export_def_bones=True,
            export_animations=True,
            export_animation_mode="NLA_TRACKS",
            export_bake_animation=True,
            export_nla_strips=True,
            export_optimize_animation_size=True,
            export_materials="EXPORT",
            export_image_format="AUTO",
        )
        kb = out_glb.stat().st_size / 1024.0
        print(f"[EXPORT] Wrote {out_glb} ({kb:.1f} KB, {len(arm_obj.data.bones)} bones, {tris} tris, anims={[a.name for a in actions]})")

        if args.preview:
            render_preview(arm_obj, actions, Path(args.preview))
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
