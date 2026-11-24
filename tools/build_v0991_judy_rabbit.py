"""Build v0.9.9.1 Rigged Hopping Rabbit GLB (Judy Hopps) for Yanshan Force in Blender 5.3.

Converts a high-poly Blender 2.77 Cycles Rigify Judy.blend asset into a lightweight,
real-time Godot 4.7 game-ready skeletal GLB (`game/assets/slice/wildlife/animal_rabbit.glb`)
facing -Z in Godot (+Y in Blender), grounded at y=0, scaled to 0.96 m ear-tip height,
with clean Principled BSDF PBR materials, downscaled packed textures, a consolidated
29-bone clean game skeleton (with MeshDeform weights transferred from MeshCage), and
3 looping skeletal animations (`Idle`, `Walk` joyful bunny hop, `Run` sprint-bound).

Usage (Blender CLI):
  blender --background --python tools/build_v0991_judy_rabbit.py -- --blend path/to/Judy.blend [--preview path/to/preview.png]
"""
from __future__ import annotations

import argparse
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "wildlife" / "animal_rabbit.glb"
TARGET_EAR_TIP_HEIGHT = 0.96  # ~0.68 m head top, ~0.96 m upright ear tips (cute Zootopia officer scale)

# Clean 29-bone game skeleton (all deform weights from minor facial/finger/pouch/toe bones merge into these)
KEEP_BONES = [
    "DEF-hips",
    "DEF-spine",
    "DEF-chest",
    "DEF-neck",
    "DEF-head",
    "DEF-ear.01.L", "DEF-ear.02.L", "DEF-ear.03.L", "DEF-ear.04.L",
    "DEF-ear.01.R", "DEF-ear.02.R", "DEF-ear.03.R", "DEF-ear.04.R",
    "DEF-shoulder.L", "DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L",
    "DEF-shoulder.R", "DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R",
    "DEF-thigh.L", "DEF-shin.L", "DEF-foot.L",
    "DEF-thigh.R", "DEF-shin.R", "DEF-foot.R",
    "DEF-tail.01", "DEF-tail.02",
]

KEEP_PARENT = {
    "DEF-hips": None,
    "DEF-spine": "DEF-hips",
    "DEF-chest": "DEF-spine",
    "DEF-neck": "DEF-chest",
    "DEF-head": "DEF-neck",
    "DEF-ear.01.L": "DEF-head",
    "DEF-ear.02.L": "DEF-ear.01.L",
    "DEF-ear.03.L": "DEF-ear.02.L",
    "DEF-ear.04.L": "DEF-ear.03.L",
    "DEF-ear.01.R": "DEF-head",
    "DEF-ear.02.R": "DEF-ear.01.R",
    "DEF-ear.03.R": "DEF-ear.02.R",
    "DEF-ear.04.R": "DEF-ear.03.R",
    "DEF-shoulder.L": "DEF-chest",
    "DEF-upper_arm.L": "DEF-shoulder.L",
    "DEF-forearm.L": "DEF-upper_arm.L",
    "DEF-hand.L": "DEF-forearm.L",
    "DEF-shoulder.R": "DEF-chest",
    "DEF-upper_arm.R": "DEF-shoulder.R",
    "DEF-forearm.R": "DEF-upper_arm.R",
    "DEF-hand.R": "DEF-forearm.R",
    "DEF-thigh.L": "DEF-hips",
    "DEF-shin.L": "DEF-thigh.L",
    "DEF-foot.L": "DEF-shin.L",
    "DEF-thigh.R": "DEF-hips",
    "DEF-shin.R": "DEF-thigh.R",
    "DEF-foot.R": "DEF-shin.R",
    "DEF-tail.01": "DEF-hips",
    "DEF-tail.02": "DEF-tail.01",
}

KEEP_MESH_NAMES = [
    "Head", "Eye.L", "Eye.R", "Mouth",
    "UniformMain", "ArmourChest", "ArmourArm", "ArmourKnee", "ArmourFeet",
    "Belt", "BeltBuckle", "Pouches", "Badge", "BadgeBooleans",
    "Hands", "Feet", "Tail",
]


def parse_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    ap = argparse.ArgumentParser()
    ap.add_argument("--blend", required=True, help="Path to extracted Judy.blend")
    ap.add_argument("--out", default=str(OUT_GLB), help="Output GLB path")
    ap.add_argument("--preview", default="", help="Optional path to render 4-view verification sheet PNG")
    return ap.parse_args(argv)


def map_vgroup_to_keep(vg_name: str, valid_bone_names: set[str]) -> str | None:
    """Collapse Rigify deform bone vertex groups onto our 29-bone game rig; return None for non-bone groups (e.g. HairDensity)!"""
    if vg_name not in valid_bone_names:
        return None
    if vg_name in KEEP_BONES:
        return vg_name
    low = vg_name.lower()
    if low.startswith("def-t_") or "toe" in low:
        return "DEF-foot.L" if vg_name.endswith(".L") else "DEF-foot.R"
    if low.startswith("def-f_") or "finger" in low or "thumb" in low or "palm" in low:
        return "DEF-hand.L" if vg_name.endswith(".L") else "DEF-hand.R"
    if "knee" in low:
        return "DEF-shin.L" if vg_name.endswith(".L") else "DEF-shin.R"
    if "collar" in low or "badge" in low:
        return "DEF-chest"
    if any(k in low for k in ("pouch", "spray", "key_ring", "belt")):
        return "DEF-hips"
    if "ear.01.l" in low:
        return "DEF-ear.01.L"
    if "ear.01.r" in low:
        return "DEF-ear.01.R"
    if any(k in low for k in ("eye", "iris", "jaw", "tooth", "tongue", "nose", "lip", "cheek", "head")):
        return "DEF-head"
    if "neck" in low:
        return "DEF-neck"
    if "chest" in low:
        return "DEF-chest"
    if "spine" in low:
        return "DEF-spine"
    if "tail" in low:
        return "DEF-tail.01"
    if "upper_arm" in low:
        return "DEF-upper_arm.L" if vg_name.endswith(".L") else "DEF-upper_arm.R"
    if "forearm" in low:
        return "DEF-forearm.L" if vg_name.endswith(".L") else "DEF-forearm.R"
    if "shoulder" in low:
        return "DEF-shoulder.L" if vg_name.endswith(".L") else "DEF-shoulder.R"
    if "thigh" in low:
        return "DEF-thigh.L" if vg_name.endswith(".L") else "DEF-thigh.R"
    if "shin" in low:
        return "DEF-shin.L" if vg_name.endswith(".L") else "DEF-shin.R"
    if "foot" in low:
        return "DEF-foot.L" if vg_name.endswith(".L") else "DEF-foot.R"
    return "DEF-hips"


def export_downscaled_textures(tmp_dir: Path) -> dict[str, bpy.types.Image]:
    """Save packed textures to disk, downscale via ffmpeg (avoiding Blender 5.3 img.scale() whitening), and reload."""
    wanted = {
        "Fur_COL": (512, "png"),
        "Eye_COL": (512, "png"),
        "Camo_COL": (512, "jpg"),
        "Spray_COL": (256, "png"),
        "Leather_COL": (512, "jpg"),
    }
    ffmpeg = shutil.which("ffmpeg")
    reloaded: dict[str, bpy.types.Image] = {}
    for img_name, (max_dim, ext) in wanted.items():
        img = bpy.data.images.get(img_name)
        if img is None:
            continue
        raw_path = tmp_dir / f"{img_name}_raw.png"
        out_path = tmp_dir / f"{img_name}_clean.{ext}"
        try:
            img.filepath_raw = str(raw_path)
            img.file_format = "PNG"
            img.save()
        except Exception as e:
            print(f"[WARN] could not save raw {img_name}: {e}")
            continue
        if ffmpeg and raw_path.exists():
            vf = f"scale='min({max_dim},iw)':'min({max_dim},ih)':force_original_aspect_ratio=decrease"
            if img_name == "Eye_COL":
                # CRITICAL: Eye_COL.png has transparent alpha=0 over the sclera (with RGB=0 black);
                # composite onto luminous creamy-white sclera so Judy's white sclera + violet iris shine cleanly!
                cmd = [
                    ffmpeg, "-y", "-loglevel", "error",
                    "-f", "lavfi", "-i", f"color=c=0xF7F8FC:s={max_dim}x{max_dim}:d=1",
                    "-i", str(raw_path),
                    "-filter_complex", f"[1:v]scale={max_dim}:{max_dim}[fg];[0:v][fg]overlay=shortest=1:format=auto",
                    "-frames:v", "1", str(out_path),
                ]
            else:
                cmd = [ffmpeg, "-y", "-loglevel", "error", "-i", str(raw_path), "-vf", vf]
                if ext == "jpg":
                    cmd += ["-q:v", "4"]
                cmd.append(str(out_path))
            subprocess.run(cmd, check=False)
        final_p = out_path if out_path.exists() and out_path.stat().st_size > 200 else raw_path
        clean_img = bpy.data.images.load(str(final_p), check_existing=False)
        clean_img.name = f"Clean_{img_name}"
        clean_img.colorspace_settings.name = "sRGB"
        clean_img.pack()
        reloaded[img_name] = clean_img
        print(f"[TEX] {img_name} -> {clean_img.size[0]}x{clean_img.size[1]} ({final_p.stat().st_size // 1024} KB)")
    return reloaded


def make_principled_mat(
    mat: bpy.types.Material,
    base_color: tuple[float, float, float] | None = None,
    tex_img: bpy.types.Image | None = None,
    roughness: float = 0.65,
    metallic: float = 0.0,
    specular: float = 0.45,
    tint_color: tuple[float, float, float] | None = None,
    tint_fac: float = 0.0,
):
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (400, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if tex_img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.location = (-360, 120)
        tex.image = tex_img
        if tint_color is not None and tint_fac > 0.001:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MIX"
            mix.location = (-120, 120)
            mix.inputs["Factor"].default_value = tint_fac
            mix.inputs[7].default_value = (*tint_color, 1.0)
            nt.links.new(tex.outputs["Color"], mix.inputs[6])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    elif base_color is not None:
        bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)


def rebuild_all_materials(tex: dict[str, bpy.types.Image]):
    """Replace Blender 2.77 Cycles shader graphs with clean Godot-ready Principled BSDF materials."""
    fur = tex.get("Fur_COL")
    eye = tex.get("Eye_COL")
    camo = tex.get("Camo_COL")
    spray = tex.get("Spray_COL")
    leather = tex.get("Leather_COL")

    specs = {
        # Fur & organic face/ears
        "Body": dict(tex_img=fur, roughness=0.84, specular=0.22),
        "BodySSS": dict(tex_img=fur, roughness=0.80, specular=0.25, tint_color=(0.86, 0.56, 0.56), tint_fac=0.22),
        "Hair": dict(tex_img=fur, roughness=0.84, specular=0.22),
        "LooseHairs": dict(tex_img=fur, roughness=0.84, specular=0.22),
        "Nose": dict(tex_img=fur, roughness=0.42, specular=0.45, tint_color=(0.88, 0.42, 0.48), tint_fac=0.42),
        "EyeBorder": dict(base_color=(0.06, 0.04, 0.05), roughness=0.48, specular=0.35),
        "Eyelashes": dict(base_color=(0.015, 0.015, 0.02), roughness=0.55, specular=0.25),
        "Mouth": dict(base_color=(0.56, 0.19, 0.18), roughness=0.48, specular=0.35),
        "Teeth": dict(base_color=(0.94, 0.93, 0.89), roughness=0.28, specular=0.55),
        "Claws": dict(base_color=(0.24, 0.15, 0.14), roughness=0.38, specular=0.45),
        # Sparkling iconic Zootopia purple-violet eyes!
        "Eyes": dict(tex_img=eye, roughness=0.10, specular=0.75),
        "Iris": dict(tex_img=eye, roughness=0.08, specular=0.80),
        "Pupil": dict(base_color=(0.008, 0.008, 0.012), roughness=0.05, specular=0.85),
        # ZPD Officer Uniform (sky-blue shirt + navy trousers)
        "UniformLight": dict(base_color=(0.15, 0.34, 0.78), roughness=0.76, specular=0.25),
        "UniformDark": dict(base_color=(0.032, 0.062, 0.135), roughness=0.78, specular=0.25),
        # Tactical vest, arm/knee/foot guards & belt
        "ChestArmour": dict(base_color=(0.024, 0.032, 0.052), roughness=0.48, metallic=0.08, specular=0.45),
        "ArmArmour": dict(base_color=(0.026, 0.034, 0.056), roughness=0.48, metallic=0.08, specular=0.45),
        "KneeArmour": dict(base_color=(0.030, 0.034, 0.048), roughness=0.44, metallic=0.10, specular=0.48),
        "KneeCap": dict(base_color=(0.045, 0.048, 0.060), roughness=0.38, metallic=0.12, specular=0.50),
        "FeetArmour": dict(base_color=(0.024, 0.028, 0.042), roughness=0.46, metallic=0.08, specular=0.45),
        "FeetArmourLight": dict(base_color=(0.055, 0.060, 0.075), roughness=0.52, metallic=0.05, specular=0.40),
        "Belt": dict(base_color=(0.025, 0.028, 0.036), roughness=0.50, metallic=0.06, specular=0.42),
        "Velcro": dict(base_color=(0.014, 0.015, 0.020), roughness=0.75, specular=0.20),
        "VelcroStrap": dict(base_color=(0.45, 0.46, 0.49), roughness=0.32, metallic=0.75, specular=0.60),
        "Metal": dict(base_color=(0.60, 0.62, 0.66), roughness=0.26, metallic=0.85, specular=0.70),
        # ZPD Gold & Blue Officer Badge
        "BadgeGold": dict(base_color=(0.86, 0.64, 0.18), roughness=0.22, metallic=0.88, specular=0.75),
        "BadgeDetailBump": dict(base_color=(0.80, 0.58, 0.16), roughness=0.26, metallic=0.85, specular=0.70),
        "BadgeBlue": dict(base_color=(0.02, 0.12, 0.36), roughness=0.26, metallic=0.15, specular=0.60),
        # Utility Belt Pouches, Fox Repellent & Walkie-Talkie
        "Camo": dict(tex_img=camo, base_color=(0.08, 0.09, 0.11), roughness=0.68, specular=0.28),
        "CamoRim": dict(base_color=(0.04, 0.045, 0.055), roughness=0.62, specular=0.30),
        "WalkieTalkie": dict(tex_img=leather, base_color=(0.05, 0.05, 0.06), roughness=0.48, specular=0.40),
        "WalkieTalkieR": dict(base_color=(0.022, 0.024, 0.032), roughness=0.52, specular=0.38),
        "Repelant": dict(tex_img=spray, base_color=(0.75, 0.25, 0.18), roughness=0.38, specular=0.50),
        "RepelantCap": dict(base_color=(0.56, 0.045, 0.055), roughness=0.30, specular=0.55),
        "RepelantCapCase": dict(base_color=(0.48, 0.075, 0.22), roughness=0.40, specular=0.48),
    }

    for m_name, cfg in specs.items():
        mat = bpy.data.materials.get(m_name)
        if mat is not None:
            make_principled_mat(mat, **cfg)


def consolidate_vgroups(obj: bpy.types.Object, valid_bone_names: set[str], fallback_bone: str = "DEF-hips"):
    """Merge valid deform bone vertex groups cleanly into our 29 KEEP_BONES groups (ignoring particle/hair groups!)."""
    mesh = obj.data
    old_idx_to_target: dict[int, str] = {}
    for vg in obj.vertex_groups:
        mapped = map_vgroup_to_keep(vg.name, valid_bone_names)
        if mapped is not None:
            old_idx_to_target[vg.index] = mapped

    vert_weights: dict[int, dict[str, float]] = {}
    for v in mesh.vertices:
        acc: dict[str, float] = {}
        for g in v.groups:
            if g.weight <= 1e-6 or g.group not in old_idx_to_target:
                continue
            tgt = old_idx_to_target[g.group]
            acc[tgt] = acc.get(tgt, 0.0) + g.weight
        if not acc:
            # Side-aware fallback for Hands/Feet/ArmourKnee/ArmourArm if any isolated claw/strap vert had zero bone weights
            if fallback_bone.endswith(".AUTO"):
                stem = fallback_bone[:-5]
                acc[f"{stem}.L" if v.co.x >= 0.0 else f"{stem}.R"] = 1.0
            else:
                acc[fallback_bone] = 1.0
        # Keep top 4 weights and normalize
        top = sorted(acc.items(), key=lambda kv: kv[1], reverse=True)[:4]
        tot = sum(w for _, w in top)
        if tot > 1e-6:
            vert_weights[v.index] = {k: w / tot for k, w in top}

    obj.vertex_groups.clear()
    new_vgs = {bn: obj.vertex_groups.new(name=bn) for bn in KEEP_BONES}
    for vi, wmap in vert_weights.items():
        for bn, w in wmap.items():
            new_vgs[bn].add([vi], w, "REPLACE")


def unify_uv_layer(obj: bpy.types.Object):
    """Ensure every mesh has a single cleanly-named primary UV layer 'UVMap' before joining."""
    uvs = obj.data.uv_layers
    if len(uvs) == 0:
        uvs.new(name="UVMap")
        return
    preferred = {"Head": "Main", "UniformMain": "Main", "Pouches": "Color"}.get(obj.name, "UVMap")
    keep = uvs.get(preferred) or uvs.active or uvs[0]
    for u in list(uvs):
        if u != keep:
            uvs.remove(u)
    keep.name = "UVMap"
    uvs.active = keep


def set_only_active(obj: bpy.types.Object):
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.hide_viewport = False
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def build_clean_armature(src_rig: bpy.types.Object, scale_factor: float) -> bpy.types.Object:
    """Create a fresh clean 29-bone game armature rotated 180 deg around Z (+Y forward) and scaled."""
    # Capture rest head/tail/roll from source rig (already rotated 180 around Z & scaled)
    rot_z_180 = Matrix.Rotation(math.pi, 4, "Z")
    xf = Matrix.Scale(scale_factor, 4) @ rot_z_180

    bone_specs: dict[str, tuple[Vector, Vector, float]] = {}
    for bn in KEEP_BONES:
        b = src_rig.data.bones.get(bn)
        if b is None:
            raise RuntimeError(f"Missing expected deform bone {bn} in Judy_Rig")
        h = xf @ b.head_local
        t = xf @ b.tail_local
        # Compute aligned roll via transformed Z axis
        z_world = (rot_z_180.to_3x3() @ (b.matrix_local.to_3x3() @ Vector((0, 0, 1)))).normalized()
        bone_specs[bn] = (h, t, z_world)

    arm_data = bpy.data.armatures.new("JudyHoppsRig")
    arm_obj = bpy.data.objects.new("JudyHoppsRig", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    set_only_active(arm_obj)
    bpy.ops.object.mode_set(mode="EDIT")

    eb_map: dict[str, bpy.types.EditBone] = {}
    for bn in KEEP_BONES:
        h, t, z_axis = bone_specs[bn]
        eb = arm_data.edit_bones.new(bn)
        eb.head = h
        eb.tail = t
        eb.use_deform = True
        eb.align_roll(z_axis)
        eb_map[bn] = eb

    for bn, parent_name in KEEP_PARENT.items():
        if parent_name and parent_name in eb_map:
            eb_map[bn].parent = eb_map[parent_name]
            eb_map[bn].use_connect = False

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def world_rot_to_bone_local_quat(arm: bpy.types.Object, bone_name: str, world_rot_mat3: Matrix) -> Quaternion:
    """Convert a character-space 3x3 rotation matrix (+Y forward, +Z up, +X right) into bone-local rest quaternion."""
    b = arm.data.bones[bone_name]
    r_rest = b.matrix_local.to_3x3()
    q_mat = r_rest.inverted() @ world_rot_mat3 @ r_rest
    return q_mat.to_quaternion()


def world_vec_to_bone_local(arm: bpy.types.Object, bone_name: str, world_vec: Vector) -> Vector:
    """Convert a character-space translation vector into bone-local space."""
    b = arm.data.bones[bone_name]
    return b.matrix_local.to_3x3().inverted() @ world_vec


def world_euler_mat(pitch_x_deg: float = 0.0, roll_y_deg: float = 0.0, yaw_z_deg: float = 0.0) -> Matrix:
    """Character-space rotation (+Y fwd, +Z up, +X right).
    +pitch_x: swings downward leg/arm FORWARD (+Y), tilts upward spine/ears BACKWARD (-Y).
    -pitch_x: bends knee BACKWARD (-Y), leans torso FORWARD (+Y), perks ears FORWARD (+Y).
    +roll_y: lowers RIGHT arm (+X->-Z), lifts LEFT arm (-X->+Z).
    -roll_y: lowers LEFT arm (-X->-Z), lifts RIGHT arm (+X->+Z).
    """
    return Euler(
        (math.radians(pitch_x_deg), math.radians(roll_y_deg), math.radians(yaw_z_deg)),
        "XYZ",
    ).to_matrix()


def set_pose_world(
    arm: bpy.types.Object,
    frame: float,
    bone_eulers: dict[str, tuple[float, float, float]],
    hips_world_offset: Vector | None = None,
):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        e = bone_eulers.get(pb.name, (0.0, 0.0, 0.0))
        m3 = world_euler_mat(e[0], e[1], e[2])
        pb.rotation_quaternion = world_rot_to_bone_local_quat(arm, pb.name, m3)
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if pb.name == "DEF-hips":
            off = hips_world_offset if hips_world_offset is not None else Vector((0.0, 0.0, 0.0))
            pb.location = world_vec_to_bone_local(arm, "DEF-hips", off)
            pb.keyframe_insert(data_path="location", frame=frame)


def build_base_stance() -> dict[str, tuple[float, float, float]]:
    """Relaxed Officer Judy standing pose (lowers A-pose arms neatly to her sides/utility belt!)."""
    return {
        "DEF-shoulder.L": (0.0, -10.0, 0.0),
        "DEF-upper_arm.L": (10.0, -56.0, 6.0),
        "DEF-forearm.L": (34.0, 4.0, -14.0),
        "DEF-hand.L": (6.0, 0.0, -8.0),
        "DEF-shoulder.R": (0.0, 10.0, 0.0),
        "DEF-upper_arm.R": (10.0, 56.0, -6.0),
        "DEF-forearm.R": (34.0, -4.0, 14.0),
        "DEF-hand.R": (6.0, 0.0, 8.0),
        "DEF-ear.01.L": (3.0, -8.0, 0.0),
        "DEF-ear.02.L": (2.0, -3.0, 0.0),
        "DEF-ear.01.R": (3.0, 8.0, 0.0),
        "DEF-ear.02.R": (2.0, 3.0, 0.0),
    }


def add_pose(base: dict[str, tuple[float, float, float]], overrides: dict[str, tuple[float, float, float]]) -> dict[str, tuple[float, float, float]]:
    out = dict(base)
    for k, v in overrides.items():
        if k in out:
            b = out[k]
            out[k] = (b[0] + v[0], b[1] + v[1], b[2] + v[2])
        else:
            out[k] = v
    return out


def author_animations(arm: bpy.types.Object) -> list[bpy.types.Action]:
    """Author 3 lively looping skeletal animations: Idle, Walk (joyful bunny hop!), Run (sprint-bound!)."""
    if arm.animation_data is None:
        arm.animation_data_create()
    base = build_base_stance()
    actions: list[bpy.types.Action] = []

    # 1. Idle (48 frames @ 24 fps = 2.0s): alert ZPD officer breathing, playful bunny ear twitches & gentle glance
    act_idle = bpy.data.actions.new(name="Idle")
    arm.animation_data.action = act_idle
    idle_keys = [
        (0.0, Vector((0, 0, 0.0)), {
            "DEF-spine": (-2.0, 0, 0), "DEF-head": (0, 0, 0),
            "DEF-ear.01.L": (0, 0, 0), "DEF-ear.02.L": (0, 0, 0),
            "DEF-ear.01.R": (0, 0, 0), "DEF-ear.02.R": (0, 0, 0),
        }),
        (12.0, Vector((0, 0, 0.008)), {
            "DEF-spine": (2.5, 0, 2.0), "DEF-chest": (2.0, 0, 2.0),
            "DEF-head": (-3.0, 2.0, 7.0),
            "DEF-ear.01.L": (-10.0, -5.0, 0), "DEF-ear.02.L": (-8.0, -4.0, 0), "DEF-ear.03.L": (-6.0, 0, 0),
            "DEF-ear.01.R": (8.0, 4.0, 0), "DEF-ear.02.R": (6.0, 3.0, 0),
            "DEF-tail.01": (6.0, 0, 6.0),
        }),
        (24.0, Vector((0, 0, -0.004)), {
            "DEF-spine": (-2.0, 0, 0.0), "DEF-head": (2.0, 0, -2.0),
            "DEF-ear.01.L": (4.0, 2.0, 0), "DEF-ear.02.L": (5.0, 0, 0),
            "DEF-ear.01.R": (-12.0, 6.0, 0), "DEF-ear.02.R": (-10.0, 4.0, 0), "DEF-ear.03.R": (-6.0, 0, 0),
            "DEF-tail.01": (-4.0, 0, -6.0),
        }),
        (36.0, Vector((0, 0, 0.007)), {
            "DEF-spine": (2.0, 0, -2.0), "DEF-chest": (1.5, 0, -2.0),
            "DEF-head": (-2.0, -2.0, -8.0),
            "DEF-ear.01.L": (-5.0, -3.0, 0), "DEF-ear.01.R": (4.0, 3.0, 0),
            "DEF-upper_arm.L": (4.0, 0, 0), "DEF-upper_arm.R": (-3.0, 0, 0),
            "DEF-tail.01": (5.0, 0, 5.0),
        }),
        (48.0, Vector((0, 0, 0.0)), {
            "DEF-spine": (-2.0, 0, 0), "DEF-head": (0, 0, 0),
            "DEF-ear.01.L": (0, 0, 0), "DEF-ear.02.L": (0, 0, 0),
            "DEF-ear.01.R": (0, 0, 0), "DEF-ear.02.R": (0, 0, 0),
        }),
    ]
    for fr, hoff, ov in idle_keys:
        set_pose_world(arm, fr, add_pose(base, ov), hoff)
    actions.append(act_idle)

    # 2. Walk (20 frames @ 24 fps = 0.83s): Signature joyful bouncy "蹦蹦跳跳" rabbit hop!
    act_walk = bpy.data.actions.new(name="Walk")
    arm.animation_data.action = act_walk
    walk_keys = [
        # Frame 0: Springy crouch anticipation (ready to leap!)
        (0.0, Vector((0.0, -0.01, -0.068)), {
            "DEF-hips": (-8.0, 0, 0),
            "DEF-spine": (-8.0, 0, 0), "DEF-chest": (-6.0, 0, 0), "DEF-head": (12.0, 0, 0),
            "DEF-thigh.L": (36.0, 0, 0), "DEF-shin.L": (-58.0, 0, 0), "DEF-foot.L": (24.0, 0, 0),
            "DEF-thigh.R": (32.0, 0, 0), "DEF-shin.R": (-54.0, 0, 0), "DEF-foot.R": (22.0, 0, 0),
            "DEF-upper_arm.L": (-26.0, 4.0, 0), "DEF-forearm.L": (28.0, 0, 0),
            "DEF-upper_arm.R": (-22.0, -4.0, 0), "DEF-forearm.R": (26.0, 0, 0),
            "DEF-ear.01.L": (-14.0, -4.0, 0), "DEF-ear.02.L": (-10.0, 0, 0), "DEF-ear.03.L": (-6.0, 0, 0),
            "DEF-ear.01.R": (-14.0, 4.0, 0), "DEF-ear.02.R": (-10.0, 0, 0), "DEF-ear.03.R": (-6.0, 0, 0),
            "DEF-tail.01": (-12.0, 0, 0),
        }),
        # Frame 4: Explosive springy push-off!
        (4.0, Vector((0.0, 0.02, 0.055)), {
            "DEF-hips": (-12.0, 0, 0),
            "DEF-spine": (-6.0, 0, 0), "DEF-chest": (4.0, 0, 0), "DEF-head": (8.0, 0, 0),
            "DEF-thigh.L": (-16.0, 0, 0), "DEF-shin.L": (-10.0, 0, 0), "DEF-foot.L": (-28.0, 0, 0),
            "DEF-thigh.R": (-12.0, 0, 0), "DEF-shin.R": (-14.0, 0, 0), "DEF-foot.R": (-26.0, 0, 0),
            "DEF-upper_arm.L": (24.0, 10.0, 0), "DEF-forearm.L": (36.0, 0, 0),
            "DEF-upper_arm.R": (28.0, -10.0, 0), "DEF-forearm.R": (36.0, 0, 0),
            "DEF-ear.01.L": (16.0, -6.0, 0), "DEF-ear.02.L": (14.0, 0, 0), "DEF-ear.03.L": (10.0, 0, 0),
            "DEF-ear.01.R": (16.0, 6.0, 0), "DEF-ear.02.R": (14.0, 0, 0), "DEF-ear.03.R": (10.0, 0, 0),
            "DEF-tail.01": (16.0, 0, 0),
        }),
        # Frame 9: Mid-air joyful bunny hop apex! (hips +0.22m, knees tucked playfully high, ears flopping back!)
        (9.0, Vector((0.0, 0.03, 0.220)), {
            "DEF-hips": (-10.0, 0, 0),
            "DEF-spine": (-8.0, 0, 0), "DEF-chest": (4.0, 0, 0), "DEF-head": (10.0, 0, 0),
            "DEF-thigh.L": (54.0, 0, 0), "DEF-shin.L": (-94.0, 0, 0), "DEF-foot.L": (-28.0, 0, 0),
            "DEF-thigh.R": (44.0, 0, 0), "DEF-shin.R": (-84.0, 0, 0), "DEF-foot.R": (-26.0, 0, 0),
            "DEF-upper_arm.L": (42.0, 12.0, 0), "DEF-forearm.L": (52.0, 0, 0),
            "DEF-upper_arm.R": (36.0, -12.0, 0), "DEF-forearm.R": (48.0, 0, 0),
            "DEF-ear.01.L": (32.0, -10.0, 0), "DEF-ear.02.L": (26.0, -4.0, 0), "DEF-ear.03.L": (18.0, 0, 0), "DEF-ear.04.L": (12.0, 0, 0),
            "DEF-ear.01.R": (32.0, 10.0, 0), "DEF-ear.02.R": (26.0, 4.0, 0), "DEF-ear.03.R": (18.0, 0, 0), "DEF-ear.04.R": (12.0, 0, 0),
            "DEF-tail.01": (24.0, 0, 0), "DEF-tail.02": (14.0, 0, 0),
        }),
        # Frame 14: Descent reaching forward for cushioned landing
        (14.0, Vector((0.0, 0.01, 0.045)), {
            "DEF-hips": (-10.0, 0, 0),
            "DEF-spine": (-6.0, 0, 0), "DEF-head": (10.0, 0, 0),
            "DEF-thigh.L": (22.0, 0, 0), "DEF-shin.L": (-20.0, 0, 0), "DEF-foot.L": (8.0, 0, 0),
            "DEF-thigh.R": (26.0, 0, 0), "DEF-shin.R": (-24.0, 0, 0), "DEF-foot.R": (10.0, 0, 0),
            "DEF-upper_arm.L": (6.0, 6.0, 0), "DEF-forearm.L": (22.0, 0, 0),
            "DEF-upper_arm.R": (10.0, -6.0, 0), "DEF-forearm.R": (22.0, 0, 0),
            "DEF-ear.01.L": (10.0, -5.0, 0), "DEF-ear.02.L": (6.0, 0, 0),
            "DEF-ear.01.R": (10.0, 5.0, 0), "DEF-ear.02.R": (6.0, 0, 0),
            "DEF-tail.01": (-6.0, 0, 0),
        }),
        # Frame 17: Cushioned squash landing + cute forward ear flop follow-through!
        (17.0, Vector((0.0, -0.01, -0.078)), {
            "DEF-hips": (-10.0, 0, 0),
            "DEF-spine": (-10.0, 0, 0), "DEF-chest": (-8.0, 0, 0), "DEF-head": (14.0, 0, 0),
            "DEF-thigh.L": (40.0, 0, 0), "DEF-shin.L": (-64.0, 0, 0), "DEF-foot.L": (26.0, 0, 0),
            "DEF-thigh.R": (38.0, 0, 0), "DEF-shin.R": (-62.0, 0, 0), "DEF-foot.R": (26.0, 0, 0),
            "DEF-upper_arm.L": (-30.0, 5.0, 0), "DEF-forearm.L": (30.0, 0, 0),
            "DEF-upper_arm.R": (-28.0, -5.0, 0), "DEF-forearm.R": (30.0, 0, 0),
            "DEF-ear.01.L": (-20.0, -6.0, 0), "DEF-ear.02.L": (-16.0, 0, 0), "DEF-ear.03.L": (-10.0, 0, 0),
            "DEF-ear.01.R": (-20.0, 6.0, 0), "DEF-ear.02.R": (-16.0, 0, 0), "DEF-ear.03.R": (-10.0, 0, 0),
            "DEF-tail.01": (-16.0, 0, 0),
        }),
        # Frame 20: Loop back cleanly to Frame 0
        (20.0, Vector((0.0, -0.01, -0.068)), {
            "DEF-hips": (-8.0, 0, 0),
            "DEF-spine": (-8.0, 0, 0), "DEF-chest": (-6.0, 0, 0), "DEF-head": (12.0, 0, 0),
            "DEF-thigh.L": (36.0, 0, 0), "DEF-shin.L": (-58.0, 0, 0), "DEF-foot.L": (24.0, 0, 0),
            "DEF-thigh.R": (32.0, 0, 0), "DEF-shin.R": (-54.0, 0, 0), "DEF-foot.R": (22.0, 0, 0),
            "DEF-upper_arm.L": (-26.0, 4.0, 0), "DEF-forearm.L": (28.0, 0, 0),
            "DEF-upper_arm.R": (-22.0, -4.0, 0), "DEF-forearm.R": (26.0, 0, 0),
            "DEF-ear.01.L": (-14.0, -4.0, 0), "DEF-ear.02.L": (-10.0, 0, 0), "DEF-ear.03.L": (-6.0, 0, 0),
            "DEF-ear.01.R": (-14.0, 4.0, 0), "DEF-ear.02.R": (-10.0, 0, 0), "DEF-ear.03.R": (-6.0, 0, 0),
            "DEF-tail.01": (-12.0, 0, 0),
        }),
    ]
    for fr, hoff, ov in walk_keys:
        set_pose_world(arm, fr, add_pose(base, ov), hoff)
    actions.append(act_walk)

    # 3. Run (16 frames @ 24 fps = 0.67s): High-energy Zootopia athletic bunny sprint-bound!
    act_run = bpy.data.actions.new(name="Run")
    arm.animation_data.action = act_run
    run_keys = [
        # Frame 0: Left leg drive forward, right leg push back, airborne lift
        (0.0, Vector((0.0, 0.02, 0.140)), {
            "DEF-hips": (-14.0, 0, -6.0),
            "DEF-spine": (-10.0, 0, 5.0), "DEF-chest": (-8.0, 0, 8.0), "DEF-head": (22.0, 0, -4.0),
            "DEF-thigh.L": (50.0, 0, 0), "DEF-shin.L": (-48.0, 0, 0), "DEF-foot.L": (-10.0, 0, 0),
            "DEF-thigh.R": (-38.0, 0, 0), "DEF-shin.R": (-28.0, 0, 0), "DEF-foot.R": (-24.0, 0, 0),
            "DEF-upper_arm.L": (-42.0, 6.0, 0), "DEF-forearm.L": (56.0, 0, 0),
            "DEF-upper_arm.R": (48.0, -6.0, 0), "DEF-forearm.R": (64.0, 0, 0),
            "DEF-ear.01.L": (34.0, -8.0, 0), "DEF-ear.02.L": (24.0, 0, 0), "DEF-ear.03.L": (14.0, 0, 0),
            "DEF-ear.01.R": (34.0, 8.0, 0), "DEF-ear.02.R": (24.0, 0, 0), "DEF-ear.03.R": (14.0, 0, 0),
            "DEF-tail.01": (18.0, 0, -6.0),
        }),
        # Frame 4: Left foot ground contact & compression
        (4.0, Vector((0.0, 0.0, -0.055)), {
            "DEF-hips": (-16.0, 0, 0.0),
            "DEF-spine": (-12.0, 0, 0.0), "DEF-chest": (-8.0, 0, 0.0), "DEF-head": (24.0, 0, 0.0),
            "DEF-thigh.L": (28.0, 0, 0), "DEF-shin.L": (-44.0, 0, 0), "DEF-foot.L": (18.0, 0, 0),
            "DEF-thigh.R": (-8.0, 0, 0), "DEF-shin.R": (-68.0, 0, 0), "DEF-foot.R": (-14.0, 0, 0),
            "DEF-upper_arm.L": (-10.0, 4.0, 0), "DEF-forearm.L": (52.0, 0, 0),
            "DEF-upper_arm.R": (10.0, -4.0, 0), "DEF-forearm.R": (52.0, 0, 0),
            "DEF-ear.01.L": (22.0, -6.0, 0), "DEF-ear.02.L": (16.0, 0, 0),
            "DEF-ear.01.R": (22.0, 6.0, 0), "DEF-ear.02.R": (16.0, 0, 0),
            "DEF-tail.01": (-8.0, 0, 0),
        }),
        # Frame 8: Right leg drive forward, left leg push back, airborne lift
        (8.0, Vector((0.0, 0.02, 0.140)), {
            "DEF-hips": (-14.0, 0, 6.0),
            "DEF-spine": (-10.0, 0, -5.0), "DEF-chest": (-8.0, 0, -8.0), "DEF-head": (22.0, 0, 4.0),
            "DEF-thigh.L": (-38.0, 0, 0), "DEF-shin.L": (-28.0, 0, 0), "DEF-foot.L": (-24.0, 0, 0),
            "DEF-thigh.R": (50.0, 0, 0), "DEF-shin.R": (-48.0, 0, 0), "DEF-foot.R": (-10.0, 0, 0),
            "DEF-upper_arm.L": (48.0, 6.0, 0), "DEF-forearm.L": (64.0, 0, 0),
            "DEF-upper_arm.R": (-42.0, -6.0, 0), "DEF-forearm.R": (56.0, 0, 0),
            "DEF-ear.01.L": (34.0, -8.0, 0), "DEF-ear.02.L": (24.0, 0, 0), "DEF-ear.03.L": (14.0, 0, 0),
            "DEF-ear.01.R": (34.0, 8.0, 0), "DEF-ear.02.R": (24.0, 0, 0), "DEF-ear.03.R": (14.0, 0, 0),
            "DEF-tail.01": (18.0, 0, 6.0),
        }),
        # Frame 12: Right foot ground contact & compression
        (12.0, Vector((0.0, 0.0, -0.055)), {
            "DEF-hips": (-16.0, 0, 0.0),
            "DEF-spine": (-12.0, 0, 0.0), "DEF-chest": (-8.0, 0, 0.0), "DEF-head": (24.0, 0, 0.0),
            "DEF-thigh.L": (-8.0, 0, 0), "DEF-shin.L": (-68.0, 0, 0), "DEF-foot.L": (-14.0, 0, 0),
            "DEF-thigh.R": (28.0, 0, 0), "DEF-shin.R": (-44.0, 0, 0), "DEF-foot.R": (18.0, 0, 0),
            "DEF-upper_arm.L": (10.0, 4.0, 0), "DEF-forearm.L": (52.0, 0, 0),
            "DEF-upper_arm.R": (-10.0, -4.0, 0), "DEF-forearm.R": (52.0, 0, 0),
            "DEF-ear.01.L": (22.0, -6.0, 0), "DEF-ear.02.L": (16.0, 0, 0),
            "DEF-ear.01.R": (22.0, 6.0, 0), "DEF-ear.02.R": (16.0, 0, 0),
            "DEF-tail.01": (-8.0, 0, 0),
        }),
        # Frame 16: Loop cleanly to Frame 0
        (16.0, Vector((0.0, 0.02, 0.140)), {
            "DEF-hips": (-14.0, 0, -6.0),
            "DEF-spine": (-10.0, 0, 5.0), "DEF-chest": (-8.0, 0, 8.0), "DEF-head": (22.0, 0, -4.0),
            "DEF-thigh.L": (50.0, 0, 0), "DEF-shin.L": (-48.0, 0, 0), "DEF-foot.L": (-10.0, 0, 0),
            "DEF-thigh.R": (-38.0, 0, 0), "DEF-shin.R": (-28.0, 0, 0), "DEF-foot.R": (-24.0, 0, 0),
            "DEF-upper_arm.L": (-42.0, 6.0, 0), "DEF-forearm.L": (56.0, 0, 0),
            "DEF-upper_arm.R": (48.0, -6.0, 0), "DEF-forearm.R": (64.0, 0, 0),
            "DEF-ear.01.L": (34.0, -8.0, 0), "DEF-ear.02.L": (24.0, 0, 0), "DEF-ear.03.L": (14.0, 0, 0),
            "DEF-ear.01.R": (34.0, 8.0, 0), "DEF-ear.02.R": (24.0, 0, 0), "DEF-ear.03.R": (14.0, 0, 0),
            "DEF-tail.01": (18.0, 0, -6.0),
        }),
    ]
    for fr, hoff, ov in run_keys:
        set_pose_world(arm, fr, add_pose(base, ov), hoff)
    actions.append(act_run)

    # Push all 3 actions onto NLA tracks for clean glTF multi-clip export
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


def render_verification_sheet(arm: bpy.types.Object, actions: list[bpy.types.Action], out_png: Path):
    """Render a 2x2 verification sheet (Front Idle, Face Close-up, Side Hop Apex, 3/4 Run Bound) via EEVEE."""
    scene = bpy.context.scene
    # CRITICAL: disable Judy.blend's legacy 2.77 Cycles compositor tree so EEVEE renders true PBR colors!
    scene.render.use_compositing = False
    if hasattr(scene, "use_nodes"):
        scene.use_nodes = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = 0.0
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.image_settings.file_format = "PNG"
    scene.world = bpy.data.worlds.new("PreviewWorld")
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.28, 0.36, 0.42, 1.0)
        bg.inputs[1].default_value = 1.4

    # Key + front fill + rim sun lights (Judy faces +Y, so illuminate from +Y!)
    for name, rot_deg, energy in [
        ("KeySun", (-52, 0, 28), 3.4),
        ("FillSun", (-45, 0, -40), 1.8),
        ("RimSun", (55, 0, 15), 1.2),
    ]:
        ld = bpy.data.lights.new(name, type="SUN")
        ld.energy = energy
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = tuple(math.radians(a) for a in rot_deg)
        scene.collection.objects.link(lo)

    cam_d = bpy.data.cameras.new("PrevCam")
    cam_d.lens = 50.0
    cam_o = bpy.data.objects.new("PrevCam", cam_d)
    scene.collection.objects.link(cam_o)
    scene.camera = cam_o

    def aim_cam(pos, target, lens=50.0):
        cam_d.lens = lens
        cam_o.location = Vector(pos)
        direction = Vector(target) - cam_o.location
        cam_o.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    act_map = {a.name: a for a in actions}
    # Temporarily disable NLA so single-action preview evaluates crisply
    arm.animation_data.use_nla = False
    tmp_imgs = []
    shots = [
        ("Idle", 0, (0.0, 1.75, 0.56), (0.0, 0.0, 0.48), 52.0),         # Front full Idle (+Y is front!)
        ("Idle", 12, (0.12, 0.72, 0.62), (0.0, 0.0, 0.60), 65.0),       # Face close-up!
        ("Walk", 9, (1.65, 0.25, 0.64), (0.0, 0.0, 0.56), 50.0),        # Side Hop Apex!
        ("Run", 0, (1.35, 1.25, 0.62), (0.0, 0.0, 0.50), 48.0),         # 3/4 Sprint Bound!
    ]
    tmp_dir = out_png.parent
    for idx, (aname, fr, cpos, ctgt, lens) in enumerate(shots):
        arm.animation_data.action = act_map[aname]
        scene.frame_set(fr)
        bpy.context.view_layer.update()
        aim_cam(cpos, ctgt, lens)
        p = tmp_dir / f"_judy_shot_{idx}.png"
        scene.render.filepath = str(p)
        bpy.ops.render.render(write_still=True)
        tmp_imgs.append(p)

    # Combine 2x2 using ffmpeg xstack
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
        print(f"[PREVIEW] Saved 2x2 sheet: {out_png}")


def main():
    args = parse_args()
    blend_path = Path(args.blend).resolve()
    out_glb = Path(args.out).resolve()
    out_glb.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    bpy.context.scene.render.fps = 24

    # 0. Recursively un-exclude & unhide ALL collections and objects so Blender 2.77 hidden layers are fully selectable!
    def _reveal_lc(lc):
        lc.exclude = False
        lc.hide_viewport = False
        lc.collection.hide_viewport = False
        lc.collection.hide_render = False
        lc.collection.hide_select = False
        for ch in lc.children:
            _reveal_lc(ch)

    _reveal_lc(bpy.context.view_layer.layer_collection)
    for o in bpy.data.objects:
        o.hide_select = False
        o.hide_viewport = False
        o.hide_set(False)
    bpy.context.view_layer.update()

    # 1. Reset Judy_Rig to clean Rest Pose so MeshCage and all meshes align 100%
    src_rig = bpy.data.objects["Judy_Rig"]
    src_rig.hide_set(False)
    src_rig.hide_viewport = False
    for pb in src_rig.pose.bones:
        pb.location = Vector((0, 0, 0))
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.rotation_euler = Euler((0, 0, 0))
        pb.scale = Vector((1, 1, 1))
    bpy.context.view_layer.update()

    # 2. Extract & downscale packed textures on disk BEFORE replacing Cycles shaders
    tmp_dir = Path(tempfile.mkdtemp(prefix="judy_tex_"))
    try:
        clean_tex = export_downscaled_textures(tmp_dir)
        rebuild_all_materials(clean_tex)

        mesh_cage = bpy.data.objects["MeshCage"]
        mesh_cage.hide_set(False)
        mesh_cage.hide_viewport = False
        # Disable armature modifier on MeshCage during transfer
        for m in mesh_cage.modifiers:
            if m.type == "ARMATURE":
                m.show_viewport = False

        # Valid deform bone names from Judy_Rig so non-bone groups (e.g. HairDensity/Particle masks) NEVER pollute skin weights!
        valid_bone_names = {b.name for b in src_rig.data.bones if b.use_deform}
        fallback_map = {
            "Head": "DEF-head", "Eye.L": "DEF-head", "Eye.R": "DEF-head", "Mouth": "DEF-head",
            "Badge": "DEF-chest", "BadgeBooleans": "DEF-chest", "ArmourChest": "DEF-chest",
            "Hands": "DEF-hand.AUTO", "ArmourArm": "DEF-forearm.AUTO",
            "Feet": "DEF-foot.AUTO", "ArmourFeet": "DEF-foot.AUTO",
            "ArmourKnee": "DEF-shin.AUTO", "Tail": "DEF-tail.01",
        }

        # 3. Unhide all kept meshes, bake Mirror / Boolean / selective Subsurf / Decimate, transfer MeshDeform -> VGroups!
        kept_objs: list[bpy.types.Object] = []
        for mname in KEEP_MESH_NAMES:
            obj = bpy.data.objects.get(mname)
            if obj is None:
                print(f"[WARN] Missing mesh {mname}")
                continue
            obj.hide_set(False)
            obj.hide_viewport = False
            obj.hide_render = False
            # Make sure it is linked to scene collection so ops work cleanly
            if obj.name not in bpy.context.scene.collection.objects:
                bpy.context.scene.collection.objects.link(obj)
            set_only_active(obj)

            # Remove particle systems cleanly
            while len(obj.particle_systems) > 0:
                bpy.ops.object.particle_system_remove()

            # Remove shape keys cleanly (keeping clean rest Basis geometry so Subsurf/Mirror/Boolean apply cleanly)
            if obj.data.shape_keys is not None:
                obj.shape_key_clear()

            uses_mesh_deform = any(m.type == "MESH_DEFORM" for m in obj.modifiers)

            # Remove non-baking modifiers first (Armature, VertexWeightMix, MeshDeform, Particle)
            for mod in list(obj.modifiers):
                if mod.type in ("ARMATURE", "VERTEX_WEIGHT_MIX", "MESH_DEFORM", "PARTICLE_SYSTEM"):
                    obj.modifiers.remove(mod)

            # Apply Mirror & Boolean cleanly
            for mod in list(obj.modifiers):
                if mod.type == "MIRROR":
                    mod.use_mirror_vertex_groups = True
                    bpy.ops.object.modifier_apply(modifier=mod.name)
                elif mod.type == "BOOLEAN":
                    try:
                        bpy.ops.object.modifier_apply(modifier=mod.name)
                    except Exception as e:
                        print(f"[WARN] Boolean apply failed on {mname}: {e}")
                        obj.modifiers.remove(mod)

            # Apply gentle Subsurf ONLY on Head & Tail (keeps face/ears silky smooth while staying fast ~24k tris total!)
            for mod in list(obj.modifiers):
                if mod.type == "SUBSURF":
                    if mname in ("Head", "Tail"):
                        mod.levels = 1
                        mod.render_levels = 1
                        bpy.ops.object.modifier_apply(modifier=mod.name)
                    else:
                        obj.modifiers.remove(mod)

            # Decimate high-poly tiny accessories so total triangle budget stays super lean & crisp (~28k tris!)
            dec_ratios = {
                "BadgeBooleans": 0.04,
                "Pouches": 0.24,
                "ArmourChest": 0.24,
                "ArmourFeet": 0.26,
                "Belt": 0.24,
                "ArmourArm": 0.42,
            }
            if mname in dec_ratios:
                dm = obj.modifiers.new("Decimate", "DECIMATE")
                dm.ratio = dec_ratios[mname]
                bpy.ops.object.modifier_apply(modifier=dm.name)

            # Transfer MeshCage weights onto MeshDeform clothing/armor & ArmourKnee for 100% seamless joint motion!
            if uses_mesh_deform or mname in ("UniformMain", "ArmourFeet", "Belt", "BeltBuckle", "ArmourChest", "ArmourArm", "ArmourKnee"):
                obj.vertex_groups.clear()
                dt = obj.modifiers.new("TransferCageWeights", "DATA_TRANSFER")
                dt.object = mesh_cage
                dt.use_vert_data = True
                dt.data_types_verts = {"VGROUP_WEIGHTS"}
                dt.vert_mapping = "POLYINTERP_NEAREST"
                bpy.ops.object.datalayout_transfer(modifier=dt.name)
                bpy.ops.object.modifier_apply(modifier=dt.name)

            # Lock Badge & BadgeBooleans firmly onto DEF-chest so it never floats!
            if mname in ("Badge", "BadgeBooleans"):
                obj.vertex_groups.clear()
                vg = obj.vertex_groups.new(name="DEF-chest")
                vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")

            # Lock Eye.L / Eye.R & Mouth firmly onto DEF-head!
            if mname in ("Eye.L", "Eye.R", "Mouth"):
                obj.vertex_groups.clear()
                vg = obj.vertex_groups.new(name="DEF-head")
                vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")

            # Unify UV layer name before joining & consolidate valid deform bone groups -> 29 clean bones!
            unify_uv_layer(obj)
            consolidate_vgroups(obj, valid_bone_names, fallback_map.get(mname, "DEF-hips"))
            # Clear parent keeping world transform
            mw = obj.matrix_world.copy()
            obj.parent = None
            obj.matrix_world = mw
            kept_objs.append(obj)

        # 4. Measure true height & ground min-Z across kept meshes
        all_z = []
        for o in kept_objs:
            for v in o.data.vertices:
                w = o.matrix_world @ v.co
                all_z.append(w.z)
        min_z = min(all_z)
        max_z = max(all_z)
        raw_height = max(0.01, max_z - min_z)
        scale_factor = TARGET_EAR_TIP_HEIGHT / raw_height
        print(f"[GEO] raw Z={min_z:.4f}..{max_z:.4f} (H={raw_height:.4f}m) -> scale={scale_factor:.4f} -> H={TARGET_EAR_TIP_HEIGHT:.2f}m")

        # 5. Join all character parts into ONE clean single-draw-call-per-material skinned mesh!
        bpy.ops.object.select_all(action="DESELECT")
        for o in kept_objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = kept_objs[0]
        bpy.ops.object.join()
        judy_mesh = bpy.context.view_layer.objects.active
        judy_mesh.name = "JudyHoppsMesh"

        # Ground at z=0, rotate 180° around Z so she faces +Y (Godot -Z), and scale cleanly!
        rot_z_180 = Matrix.Rotation(math.pi, 4, "Z")
        xf_mesh = Matrix.Scale(scale_factor, 4) @ rot_z_180 @ Matrix.Translation((0.0, 0.0, -min_z))
        judy_mesh.data.transform(xf_mesh @ judy_mesh.matrix_world)
        judy_mesh.matrix_world = Matrix.Identity(4)
        bpy.ops.object.shade_smooth()

        # Verify grounded bounds
        zs = [v.co.z for v in judy_mesh.data.vertices]
        ys = [v.co.y for v in judy_mesh.data.vertices]
        tris = sum(len(p.vertices) - 2 for p in judy_mesh.data.polygons)
        print(f"[MESH] {judy_mesh.name}: verts={len(judy_mesh.data.vertices)}, polys={len(judy_mesh.data.polygons)}, tris={tris}, Z={min(zs):.4f}..{max(zs):.4f}, Y={min(ys):.4f}..{max(ys):.4f}")
        if min(zs) > 0.02:
            raise RuntimeError(f"Expected full grounded Judy mesh starting near z=0, got min_z={min(zs):.4f}")

        # 6. Build clean 29-bone game armature (offset by -min_z before scale/rot!)
        # Shift src_rig bones temporarily by -min_z for exact match
        set_only_active(src_rig)
        bpy.ops.object.mode_set(mode="EDIT")
        for eb in src_rig.data.edit_bones:
            eb.head.z -= min_z
            eb.tail.z -= min_z
        bpy.ops.object.mode_set(mode="OBJECT")

        clean_arm = build_clean_armature(src_rig, scale_factor)

        # 7. Delete all old scene objects (widgets, lights, cameras, old rig, MeshCage, Cornea, EyeBoolean, Ground)
        keep_set = {judy_mesh, clean_arm}
        for o in list(bpy.data.objects):
            if o not in keep_set:
                bpy.data.objects.remove(o, do_unlink=True)

        # Parent mesh to clean armature with ARMATURE modifier
        judy_mesh.parent = clean_arm
        amod = judy_mesh.modifiers.new("Armature", "ARMATURE")
        amod.object = clean_arm

        # 8. Author Idle, Walk (joyful bunny hop!), Run (athletic sprint-bound!)
        actions = author_animations(clean_arm)

        # 9. Export clean game-ready GLB!
        bpy.ops.object.select_all(action="DESELECT")
        clean_arm.select_set(True)
        judy_mesh.select_set(True)
        bpy.context.view_layer.objects.active = clean_arm

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
        print(f"[EXPORT] Wrote {out_glb} ({kb:.1f} KB, {len(KEEP_BONES)} bones, {tris} tris, anims={[a.name for a in actions]})")

        # 10. Optional 2x2 Blender visual verification sheet
        if args.preview:
            render_verification_sheet(clean_arm, actions, Path(args.preview))
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
