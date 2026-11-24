"""Build v0.9.9.2 Protagonist '游侠·少羽' (Shaoyu v2 PBR + 69-Bone Rig + 24 Retargeted Animations) in Blender 5.3.

Upgrades `game/assets/slice/player_shaoyu.glb` from the legacy modular hero mesh to the sculpted
`player_shaoyu_v2.glb` (Tripo PBR 2048px -> optimized 1024px Color/Normal/Metallic-Roughness, 10,325 tris),
renaming all 65 Mixamo bones to our exact `player_body.gd` bone convention (+ Root, Weapon_R, Weapon_Back,
Scarf_01..04 = 72 bones), splitting into seamless 1P/3P meshes (`Shaoyu_UpperBody`, `Shaoyu_LowerLegs`,
`Shaoyu_LowerBoots`), and retargeting all 24 production animations from the reference hero rig using
exact world-space T-pose-to-A-pose aligned quaternion retargeting.

Usage (Blender CLI):
  blender --background --python tools/build_v0992_shaoyu_v2.py -- --v2 path/to/player_shaoyu_v2.glb --ref path/to/ref_shaoyu.glb [--preview path/to/preview.png]
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
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "player_shaoyu.glb"
RIFLE_GLB = ROOT / "game" / "assets" / "slice" / "rifle.glb"

MIXAMO_TO_SHAOYU = {
    "mixamorig:Hips": "Hips",
    "mixamorig:Spine": "Abdomen",
    "mixamorig:Spine1": "Torso",
    "mixamorig:Spine2": "Chest",
    "mixamorig:Neck": "Neck",
    "mixamorig:Head": "Head",
    "mixamorig:HeadTop_End": "HeadTop",
    "mixamorig:LeftShoulder": "Shoulder.L",
    "mixamorig:LeftArm": "UpperArm.L",
    "mixamorig:LeftForeArm": "LowerArm.L",
    "mixamorig:LeftHand": "Hand.L",
    "mixamorig:RightShoulder": "Shoulder.R",
    "mixamorig:RightArm": "UpperArm.R",
    "mixamorig:RightForeArm": "LowerArm.R",
    "mixamorig:RightHand": "Hand.R",
    "mixamorig:LeftUpLeg": "UpperLeg.L",
    "mixamorig:LeftLeg": "LowerLeg.L",
    "mixamorig:LeftFoot": "Foot.L",
    "mixamorig:LeftToeBase": "Toe.L",
    "mixamorig:LeftToe_End": "ToeEnd.L",
    "mixamorig:RightUpLeg": "UpperLeg.R",
    "mixamorig:RightLeg": "LowerLeg.R",
    "mixamorig:RightFoot": "Foot.R",
    "mixamorig:RightToeBase": "Toe.R",
    "mixamorig:RightToe_End": "ToeEnd.R",
}
for side_m, side_s in [("Left", "L"), ("Right", "R")]:
    for fing in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
        for idx in (1, 2, 3, 4):
            MIXAMO_TO_SHAOYU[f"mixamorig:{side_m}Hand{fing}{idx}"] = f"{fing}{idx}.{side_s}"

# Bones that receive T-pose-to-A-pose directional alignment when retargeting from T-pose reference rig
ALIGN_LIMB_BONES = {
    "UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R",
    "UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R",
}


def parse_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    ap = argparse.ArgumentParser()
    ap.add_argument("--v2", required=True, help="Path to player_shaoyu_v2.glb")
    ap.add_argument("--ref", required=True, help="Path to reference animated player_shaoyu.glb")
    ap.add_argument("--out", default=str(OUT_GLB), help="Output GLB path")
    ap.add_argument("--preview", default="", help="Optional 2x2 verification sheet PNG path")
    return ap.parse_args(argv)


def sample_reference_animations(ref_glb: Path) -> dict:
    """Load reference animated player_shaoyu.glb and sample world-space bone deltas for every animation frame."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    bpy.ops.import_scene.gltf(filepath=str(ref_glb))

    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        raise RuntimeError(f"No armature in reference {ref_glb}")

    # Capture rest-pose world 3x3 rotations, rest bone direction vectors, and rest hip origin
    mw = arm.matrix_world.copy()
    mw3 = mw.to_3x3()
    rest_rot: dict[str, Matrix] = {}
    rest_dir: dict[str, Vector] = {}
    for b in arm.data.bones:
        rest_rot[b.name] = (mw3 @ b.matrix_local.to_3x3()).normalized()
        v = (mw @ b.tail_local) - (mw @ b.head_local)
        rest_dir[b.name] = v.normalized() if v.length > 1e-5 else Vector((0, 0, 1))

    hips_rest_pos = mw @ arm.data.bones["Hips"].head_local
    src_hip_h = float(hips_rest_pos.z)

    # Compute Weapon_R rest offset relative to Hand.R in world rest pose
    hand_r_rest_pos = mw @ arm.data.bones["Hand.R"].head_local
    weap_r_rest_pos = mw @ arm.data.bones["Weapon_R"].head_local
    weap_r_off_in_hand = rest_rot["Hand.R"].inverted() @ (weap_r_rest_pos - hand_r_rest_pos)

    chest_rest_pos = mw @ arm.data.bones["Chest"].head_local
    weap_b_rest_pos = mw @ arm.data.bones["Weapon_Back"].head_local
    weap_b_off_in_chest = rest_rot["Chest"].inverted() @ (weap_b_rest_pos - chest_rest_pos)

    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.use_nla = False

    sampled_actions: dict[str, dict] = {}
    scene = bpy.context.scene
    for act in sorted(bpy.data.actions, key=lambda a: a.name):
        f0 = int(math.floor(act.frame_range[0]))
        f1 = int(math.ceil(act.frame_range[1]))
        if f1 <= f0:
            f1 = f0 + 1
        arm.animation_data.action = act
        # Determine sampling step: keep every frame for short clips (<=40f), every 2nd frame for long clips
        step = 1 if (f1 - f0) <= 44 else 2
        frames = list(range(f0, f1 + 1, step))
        if frames[-1] != f1:
            frames.append(f1)

        frame_data: dict[int, dict] = {}
        for fr in frames:
            scene.frame_set(fr)
            bpy.context.view_layer.update()
            deltas: dict[str, Matrix] = {}
            world_rots: dict[str, Matrix] = {}
            for pb in arm.pose.bones:
                m_pose_w = (mw3 @ pb.matrix.to_3x3()).normalized()
                world_rots[pb.name] = m_pose_w
                deltas[pb.name] = m_pose_w @ rest_rot[pb.name].inverted()
            h_pos = mw @ arm.pose.bones["Hips"].head
            h_disp = h_pos - hips_rest_pos
            wr_off_w = (mw @ arm.pose.bones["Weapon_R"].head) - (mw @ arm.pose.bones["Hand.R"].head)
            wb_off_w = (mw @ arm.pose.bones["Weapon_Back"].head) - (mw @ arm.pose.bones["Chest"].head)
            frame_data[fr] = {
                "deltas": deltas,
                "world_rots": world_rots,
                "hips_disp": h_disp,
                "wr_off_w": wr_off_w,
                "wb_off_w": wb_off_w,
            }
        sampled_actions[act.name] = {
            "f0": f0,
            "f1": f1,
            "frames": frames,
            "data": frame_data,
        }

    print(f"[REF] Sampled {len(sampled_actions)} animations from {ref_glb.name} (src_hip_h={src_hip_h:.3f}m)")
    return {
        "rest_rot": rest_rot,
        "rest_dir": rest_dir,
        "src_hip_h": src_hip_h,
        "weap_r_off_in_hand": weap_r_off_in_hand,
        "weap_b_off_in_chest": weap_b_off_in_chest,
        "actions": sampled_actions,
    }


def optimize_v2_textures(tmp_dir: Path):
    """Downscale 2048px PBR maps on disk via ffmpeg -> 1024px (Color JPG, Normal/MR PNG) and repack cleanly."""
    ffmpeg = shutil.which("ffmpeg")
    replaced: dict[str, bpy.types.Image] = {}
    for img in list(bpy.data.images):
        if img.size[0] == 0:
            continue
        low = img.name.lower()
        is_color = ("color" in low or "albedo" in low or "base" in low) and "normal" not in low
        ext = "jpg" if is_color else "png"
        cspace = "sRGB" if is_color else "Non-Color"
        max_dim = 1024
        raw_p = tmp_dir / f"{img.name}_raw.png"
        out_p = tmp_dir / f"{img.name}_1k.{ext}"
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
                cmd += ["-q:v", "2"]
            cmd.append(str(out_p))
            subprocess.run(cmd, check=False)
        final_p = out_p if out_p.exists() and out_p.stat().st_size > 200 else raw_p
        nimg = bpy.data.images.load(str(final_p), check_existing=False)
        nimg.name = f"ShaoyuV2_{img.name}"
        nimg.colorspace_settings.name = cspace
        nimg.pack()
        replaced[img.name] = nimg
        print(f"[TEX] {img.name} -> {nimg.size[0]}x{nimg.size[1]} ({final_p.stat().st_size // 1024} KB, {cspace})")

    for mat in bpy.data.materials:
        if not mat.node_tree:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image and node.image.name in replaced:
                node.image = replaced[node.image.name]


def split_mesh_for_fp_tp(body_obj: bpy.types.Object, arm_obj: bpy.types.Object) -> list[bpy.types.Object]:
    """Split unified Shaoyu_Body seamlessly into Shaoyu_UpperBody, Shaoyu_LowerLegs & Shaoyu_LowerBoots for clean 1P look-down."""
    # Partition polygon indices by centroid Z (exact clean cut below tactical belt & above boot cuff!)
    # z >= 0.845 -> UpperBody (head, scarf, jacket, belt, arms; hidden in 1P!)
    # 0.27 <= z < 0.845 -> LowerLegs (cargo pants & kneepads; visible in 1P & 3P!)
    # z < 0.27 -> LowerBoots (combat boots; visible in 1P & 3P!)
    mesh = body_obj.data
    parts_spec = [
        ("Shaoyu_UpperBody", lambda cz: cz >= 0.845),
        ("Shaoyu_LowerLegs", lambda cz: 0.27 <= cz < 0.845),
        ("Shaoyu_LowerBoots", lambda cz: cz < 0.27),
    ]
    created: list[bpy.types.Object] = []
    for pname, pred in parts_spec:
        dup = body_obj.copy()
        dup.data = body_obj.data.copy()
        dup.name = pname
        dup.data.name = pname + "_Mesh"
        bpy.context.scene.collection.objects.link(dup)

        bm = bmesh.new()
        bm.from_mesh(dup.data)
        to_del = [f for f in bm.faces if not pred(f.calc_center_median().z)]
        bmesh.ops.delete(bm, geom=to_del, context="FACES")
        # Remove loose verts/edges left after face deletion
        loose_e = [e for e in bm.edges if not e.link_faces]
        if loose_e:
            bmesh.ops.delete(bm, geom=loose_e, context="EDGES")
        loose_v = [v for v in bm.verts if not v.link_faces]
        if loose_v:
            bmesh.ops.delete(bm, geom=loose_v, context="VERTS")
        bm.to_mesh(dup.data)
        bm.free()
        dup.data.update()

        dup.parent = arm_obj
        for m in list(dup.modifiers):
            if m.type == "ARMATURE":
                m.object = arm_obj
        print(f"[SPLIT] {pname:18s}: verts={len(dup.data.vertices):5d}, polys={len(dup.data.polygons):5d}")
        created.append(dup)

    bpy.data.objects.remove(body_obj, do_unlink=True)
    return created


def retarget_animations(arm: bpy.types.Object, ref: dict) -> list[bpy.types.Action]:
    """World-space T-pose->A-pose aligned quaternion retargeting for all 24 production animations."""
    mw = arm.matrix_world.copy()
    mw3 = mw.to_3x3()
    # Exact armature world scale (e.g. ~1.7609 on Mixamo/Tripo rigs): pose bone local translations scale by arm_scale!
    arm_scale = (mw3 @ Vector((1.0, 0.0, 0.0))).length
    if arm_scale < 1e-5:
        arm_scale = 1.0
    print(f"[RETARGET] arm_scale={arm_scale:.5f}")

    tgt_rest_rot: dict[str, Matrix] = {}
    tgt_rest_dir: dict[str, Vector] = {}
    for b in arm.data.bones:
        tgt_rest_rot[b.name] = (mw3 @ b.matrix_local.to_3x3()).normalized()
        v = (mw @ b.tail_local) - (mw @ b.head_local)
        tgt_rest_dir[b.name] = v.normalized() if v.length > 1e-5 else Vector((0, 0, 1))

    # Compute exact world-space T-pose alignment rotation R_bind_corr for A-pose limbs!
    bind_corr: dict[str, Matrix] = {}
    for bn in arm.data.bones.keys():
        if bn in ALIGN_LIMB_BONES and bn in ref["rest_dir"]:
            v_tgt = tgt_rest_dir[bn]
            v_src = ref["rest_dir"][bn]
            q_align = v_tgt.rotation_difference(v_src)
            bind_corr[bn] = q_align.to_matrix()
            ang_deg = math.degrees(q_align.angle)
            print(f"[ALIGN] {bn:14s}: A->T rest correction = {ang_deg:.1f} deg")
        else:
            bind_corr[bn] = Matrix.Identity(3)

    # Hands & fingers inherit their forearm's A->T alignment so wrists & palms never twist!
    for side in ("L", "R"):
        fa_corr = bind_corr.get(f"LowerArm.{side}", Matrix.Identity(3))
        bind_corr[f"Hand.{side}"] = fa_corr
        for fing in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
            for idx in (1, 2, 3, 4):
                fn = f"{fing}{idx}.{side}"
                if fn in bind_corr:
                    bind_corr[fn] = fa_corr

    # Topological parent->child order of target bones
    topo_bones: list[str] = []
    visited: set[str] = set()
    def visit(bn: str):
        if bn in visited:
            return
        b = arm.data.bones[bn]
        if b.parent is not None:
            visit(b.parent.name)
        visited.add(bn)
        topo_bones.append(bn)
    for b in arm.data.bones:
        visit(b.name)

    tgt_hip_h = float((mw @ arm.data.bones["Hips"].head_local).z)
    hip_scale = tgt_hip_h / max(0.2, float(ref["src_hip_h"]))
    print(f"[RETARGET] hip_scale={hip_scale:.4f} (tgt={tgt_hip_h:.3f}m / src={ref['src_hip_h']:.3f}m)")

    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.use_nla = False

    out_actions: list[bpy.types.Action] = []
    for act_name, ainfo in ref["actions"].items():
        act = bpy.data.actions.new(name=act_name)
        arm.animation_data.action = act
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"

        for fr in ainfo["frames"]:
            fdata = ainfo["data"][fr]
            src_deltas: dict[str, Matrix] = fdata["deltas"]
            src_wrots: dict[str, Matrix] = fdata["world_rots"]
            hips_disp_w: Vector = fdata["hips_disp"] * hip_scale

            # Traverse parent -> child computing exact world pose rotation & local bone quaternion!
            cur_world_rot: dict[str, Matrix] = {}
            for bn in topo_bones:
                b = arm.data.bones[bn]
                pb = arm.pose.bones[bn]
                p_name = b.parent.name if b.parent else None

                if bn in ("Root", "HeadTop", "Toe.L", "Toe.R", "ToeEnd.L", "ToeEnd.R") or bn.startswith("Scarf_"):
                    # Keep clean identity local rotation (follows parent cleanly!)
                    q_loc = Quaternion((1, 0, 0, 0))
                    if p_name:
                        m_rel = tgt_rest_rot[p_name].inverted() @ tgt_rest_rot[bn]
                        cur_world_rot[bn] = cur_world_rot[p_name] @ m_rel
                    else:
                        cur_world_rot[bn] = tgt_rest_rot[bn]
                elif bn == "Weapon_R" and "Weapon_R" in src_wrots:
                    # Match exact reference Weapon_R world orientation so YS-04 barrel aims dead-straight!
                    m_target_w = src_wrots["Weapon_R"]
                    m_rel = tgt_rest_rot[p_name].inverted() @ tgt_rest_rot[bn]
                    m_expected = cur_world_rot[p_name] @ m_rel
                    q_loc = (m_expected.inverted() @ m_target_w).to_quaternion()
                    cur_world_rot[bn] = m_target_w
                elif bn == "Weapon_Back" and "Weapon_Back" in src_wrots:
                    m_target_w = src_wrots["Weapon_Back"]
                    m_rel = tgt_rest_rot[p_name].inverted() @ tgt_rest_rot[bn]
                    m_expected = cur_world_rot[p_name] @ m_rel
                    q_loc = (m_expected.inverted() @ m_target_w).to_quaternion()
                    cur_world_rot[bn] = m_target_w
                elif bn in src_deltas:
                    m_target_w = src_deltas[bn] @ bind_corr[bn] @ tgt_rest_rot[bn]
                    if p_name:
                        m_rel = tgt_rest_rot[p_name].inverted() @ tgt_rest_rot[bn]
                        m_expected = cur_world_rot[p_name] @ m_rel
                        q_loc = (m_expected.inverted() @ m_target_w).to_quaternion()
                    else:
                        q_loc = (tgt_rest_rot[bn].inverted() @ m_target_w).to_quaternion()
                    cur_world_rot[bn] = m_target_w
                else:
                    # Finger segment without exact ref match (e.g. Index1): follow Hand curl smoothly
                    q_loc = Quaternion((1, 0, 0, 0))
                    if p_name:
                        m_rel = tgt_rest_rot[p_name].inverted() @ tgt_rest_rot[bn]
                        cur_world_rot[bn] = cur_world_rot[p_name] @ m_rel
                    else:
                        cur_world_rot[bn] = tgt_rest_rot[bn]

                pb.rotation_quaternion = q_loc
                pb.keyframe_insert(data_path="rotation_quaternion", frame=fr)

                if bn == "Hips":
                    loc_local = (tgt_rest_rot["Hips"].inverted() @ hips_disp_w) / arm_scale
                    pb.location = loc_local
                    pb.keyframe_insert(data_path="location", frame=fr)

            # Second pass after all parent rotations are applied: lock Weapon_R & Weapon_Back EXACT world offsets
            # relative to Hand.R & Chest so YS-04 pistol grip, foregrip & shoulder stock align 100% flush!
            bpy.context.view_layer.update()
            for wbn, pbn, off_key in [
                ("Weapon_R", "Hand.R", "wr_off_w"),
                ("Weapon_Back", "Chest", "wb_off_w"),
            ]:
                if wbn in arm.pose.bones and pbn in arm.pose.bones and off_key in fdata:
                    pb_w = arm.pose.bones[wbn]
                    pb_p = arm.pose.bones[pbn]
                    pb_w.location = Vector((0.0, 0.0, 0.0))
                    bpy.context.view_layer.update()
                    cur_w_pos = mw @ pb_w.head
                    want_w_pos = (mw @ pb_p.head) + fdata[off_key]
                    delta_w = want_w_pos - cur_w_pos
                    m_rel_w = tgt_rest_rot[pbn].inverted() @ tgt_rest_rot[wbn]
                    m_exp_w = cur_world_rot[pbn] @ m_rel_w
                    pb_w.location = (m_exp_w.inverted() @ delta_w) / arm_scale
                    pb_w.keyframe_insert(data_path="location", frame=fr)

        out_actions.append(act)

    # Push all 24 actions to NLA tracks for glTF export
    arm.animation_data.action = None
    while len(arm.animation_data.nla_tracks) > 0:
        arm.animation_data.nla_tracks.remove(arm.animation_data.nla_tracks[0])
    for act in out_actions:
        act.use_fake_user = True
        tr = arm.animation_data.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, int(round(act.frame_range[0])), act)
        st.name = act.name
        tr.mute = False
    arm.animation_data.use_nla = True
    return out_actions


def render_verification_sheet(arm: bpy.types.Object, actions: list[bpy.types.Action], out_png: Path):
    """Render 2x2 verification sheet (Front Rifle_LowReady, Side Rifle_Aim, Prone_Idle, Sprint_Fwd) with YS-04 rifle!"""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world = bpy.data.worlds.new("HeroPrevW")
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.22, 0.28, 0.34, 1.0)
        bg.inputs[1].default_value = 1.4
    for nm, rot, en in [("Sun1", (50, 0, 28), 3.4), ("Sun2", (50, 0, -145), 2.0)]:
        ld = bpy.data.lights.new(nm, type="SUN")
        ld.energy = en
        lo = bpy.data.objects.new(nm, ld)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(lo)
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 50.0
    co = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(co)
    scene.camera = co

    def aim(pos, tgt):
        co.location = Vector(pos)
        co.rotation_euler = (Vector(tgt) - co.location).to_track_quat("-Z", "Y").to_euler()

    act_map = {a.name: a for a in actions}
    arm.animation_data.use_nla = False
    shots = [
        ("Rifle_LowReady", 0, (-0.7, -2.55, 1.08), (0.0, 0.0, 0.92)),
        ("Rifle_Aim", 0, (-1.85, -1.65, 1.15), (0.0, -0.1, 0.98)),
        ("Prone_Idle", 0, (-2.35, -0.5, 0.72), (0.0, 0.15, 0.24)),
        ("Sprint_Fwd", 6, (-1.95, -1.55, 1.05), (0.0, 0.0, 0.88)),
    ]
    tmp_imgs = []
    for idx, (aname, fr, cpos, ctgt) in enumerate(shots):
        act = act_map.get(aname) or actions[0]
        arm.animation_data.action = act
        scene.frame_set(fr)
        bpy.context.view_layer.update()
        aim(cpos, ctgt)
        p = out_png.parent / f"_shaoyu_shot_{idx}.png"
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
        print(f"[PREVIEW] Saved Shaoyu v2 2x2 sheet: {out_png}")


def main():
    args = parse_args()
    v2_glb = Path(args.v2).resolve()
    ref_glb = Path(args.ref).resolve()
    out_glb = Path(args.out).resolve()
    out_glb.parent.mkdir(parents=True, exist_ok=True)

    # 1. Sample all 24 production animations from current reference hero rig BEFORE replacing it!
    ref = sample_reference_animations(ref_glb)

    # 2. Load clean Shaoyu v2 GLB
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    bpy.ops.import_scene.gltf(filepath=str(v2_glb))

    # Delete glTF bone display Icosphere dummy
    for o in list(bpy.data.objects):
        if o.name.startswith("Icosphere") or o.type not in ("ARMATURE", "MESH"):
            bpy.data.objects.remove(o, do_unlink=True)

    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = next(o for o in bpy.data.objects if o.type == "MESH")
    arm.name = "Shaoyu_Armature"

    tmp_dir = Path(tempfile.mkdtemp(prefix="shaoyu_v2_tex_"))
    try:
        optimize_v2_textures(tmp_dir)

        # 3. Rename all 65 Mixamo bones -> exact player_body.gd names + add Root, Weapon_R, Weapon_Back & Scarf_01..04!
        # Rename vertex groups on mesh FIRST (before or alongside bones — Blender syncs when renaming bones on active armature,
        # so renaming bone.name automatically renames matching vertex groups!)
        for old_n, new_n in MIXAMO_TO_SHAOYU.items():
            b = arm.data.bones.get(old_n)
            if b is not None:
                b.name = new_n

        bpy.ops.object.select_all(action="DESELECT")
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        ebs = arm.data.edit_bones

        # Add Root bone at ground origin (0,0,0) -> Hips.head
        hips_eb = ebs["Hips"]
        root_eb = ebs.new("Root")
        root_eb.head = Vector((0.0, 0.0, 0.0))
        root_eb.tail = hips_eb.head.copy()
        root_eb.use_deform = False
        hips_eb.parent = root_eb
        hips_eb.use_connect = False

        # Add Weapon_R socket bone inside Right Hand palm (child of Hand.R)
        hand_r = ebs["Hand.R"]
        wr = ebs.new("Weapon_R")
        # Place right inside palm (slightly forward/down along hand direction)
        palm_center = hand_r.head.lerp(hand_r.tail, 0.75) + Vector((-0.020, -0.025, -0.018))
        wr.head = palm_center
        wr.tail = palm_center + Vector((0.0, -0.055, 0.0))
        wr.use_deform = False
        wr.parent = hand_r
        wr.use_connect = False

        # Add Weapon_Back diagonal holster socket (child of Chest)
        chest_eb = ebs["Chest"]
        wb = ebs.new("Weapon_Back")
        wb.head = Vector((0.045, 0.165, 1.245))
        wb.tail = Vector((-0.013, 0.168, 1.168))
        wb.use_deform = False
        wb.parent = chest_eb
        wb.use_connect = False

        # Add Scarf_01..04 chain behind left shoulder so SpringBoneSimulator3D mounts cleanly
        scarf_pts = [
            Vector((0.068, 0.095, 1.385)),
            Vector((0.105, 0.145, 1.280)),
            Vector((0.130, 0.160, 1.160)),
            Vector((0.142, 0.155, 1.040)),
            Vector((0.148, 0.148, 0.935)),
        ]
        prev_s = chest_eb
        for si in range(4):
            sb = ebs.new(f"Scarf_0{si + 1}")
            sb.head = scarf_pts[si]
            sb.tail = scarf_pts[si + 1]
            sb.use_deform = True
            sb.parent = prev_s
            sb.use_connect = (si > 0)
            prev_s = sb

        bpy.ops.object.mode_set(mode="OBJECT")
        print(f"[RIG] Shaoyu v2 skeleton ready: {len(arm.data.bones)} bones")

        # 4. Split Shaoyu_Body into seamless 1P/3P meshes (Shaoyu_UpperBody, Shaoyu_LowerLegs, Shaoyu_LowerBoots)
        split_meshes = split_mesh_for_fp_tp(body, arm)

        # 5. Retarget all 24 production animations with exact A-pose <-> T-pose world alignment!
        actions = retarget_animations(arm, ref)

        # 6. Export final game-ready player_shaoyu.glb!
        bpy.ops.object.select_all(action="DESELECT")
        arm.select_set(True)
        for m in split_meshes:
            m.select_set(True)
        bpy.context.view_layer.objects.active = arm

        bpy.ops.export_scene.gltf(
            filepath=str(out_glb),
            export_format="GLB",
            use_selection=True,
            export_apply=False,
            export_yup=True,
            export_skins=True,
            export_def_bones=False,  # Keep Root, Weapon_R, Weapon_Back & Scarf sockets!
            export_animations=True,
            export_animation_mode="NLA_TRACKS",
            export_bake_animation=True,
            export_nla_strips=True,
            export_optimize_animation_size=True,
            export_materials="EXPORT",
            export_image_format="AUTO",
        )
        kb = out_glb.stat().st_size / 1024.0
        print(f"[EXPORT] Wrote {out_glb} ({kb:.1f} KB, {len(arm.data.bones)} bones, {len(actions)} anims)")

        if args.preview:
            render_verification_sheet(arm, actions, Path(args.preview))
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
