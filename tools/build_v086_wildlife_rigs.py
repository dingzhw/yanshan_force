"""Build 4 new skeletal-animated Jiangnan wildlife species for Yanshan Force v0.8.6 in Blender 4.5:
  - game/assets/slice/wildlife/animal_deer.glb       (梅花鹿 Sika Deer: Idle, Walk, Run)
  - game/assets/slice/wildlife/animal_pheasant.glb   (山雉锦鸡 Golden Pheasant: Idle, Walk, Run, Fly)
  - game/assets/slice/wildlife/animal_turtle.glb     (清溪山龟 Pond Turtle: Idle, Walk, Swim)
  - game/assets/slice/wildlife/animal_butterfly.glb  (山涧彩蝶 Mountain Butterfly: Idle, Fly)

Every GLB carries a real Skeleton3D + vertex-colored painterly mesh + looping NLA tracks matching v0.6.1.1!
Run with:
  blender --background --python tools/build_v086_wildlife_rigs.py
"""
from __future__ import annotations

import math
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "game" / "assets" / "slice" / "wildlife"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def gd_to_bl(v: Vector) -> Vector:
    """Godot (x right, y up, z back; -Z forward) -> Blender Z-up (+Y forward)."""
    return Vector((v.x, -v.z, v.y))


def make_vcol_mat(name: str, roughness: float = 0.68, metallic: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def push_actions_to_nla(arm: bpy.types.Object, keep_actions: list[bpy.types.Action]) -> list[str]:
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = None
    while len(arm.animation_data.nla_tracks) > 0:
        arm.animation_data.nla_tracks.remove(arm.animation_data.nla_tracks[0])
    exported: list[str] = []
    for act in keep_actions:
        act.use_fake_user = True
        track = arm.animation_data.nla_tracks.new()
        track.name = act.name
        start_f = max(0, int(round(act.frame_range[0])))
        strip = track.strips.new(act.name, start_f, act)
        strip.name = act.name
        track.mute = False
        exported.append(act.name)
    arm.animation_data.use_nla = True
    return exported


def set_bone_rot(arm: bpy.types.Object, bname: str, frame: float, deg_x: float = 0.0, deg_y: float = 0.0, deg_z: float = 0.0):
    pb = arm.pose.bones[bname]
    m_bone = arm.data.bones[bname].matrix_local.to_3x3()
    w_rot = Euler((math.radians(deg_x), math.radians(deg_y), math.radians(deg_z)), "XYZ").to_matrix()
    pb.rotation_quaternion = (m_bone.inverted() @ w_rot @ m_bone).to_quaternion()
    pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def export_rig(arm: bpy.types.Object, out_path: Path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_all_influences=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_materials="EXPORT",
        export_normals=True,
        export_attributes=True,
    )


def add_weighted_sphere(bm, dlayer, clayer, bone_idx: int, center_gd, radii_gd, color_fn, rot_deg=(0.0, 0.0, 0.0), sub=2):
    ret = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    eu = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix()
    cx, cy, cz = center_gd
    rx, ry, rz = radii_gd
    for v in ret["verts"]:
        p = eu @ Vector((v.co.x * rx, v.co.y * ry, v.co.z * rz))
        v.co = gd_to_bl(Vector((cx + p.x, cy + p.y, cz + p.z)))
        v[dlayer][bone_idx] = 1.0
    vset = set(ret["verts"])
    for f in bm.faces:
        if f.verts[0] in vset:
            for lp in f.loops:
                gx, gy, gz = lp.vert.co.x, lp.vert.co.z, -lp.vert.co.y
                lp[clayer] = color_fn(gx, gy, gz)
    return ret["verts"]


def add_weighted_cyl(bm, dlayer, clayer, bone_idx: int, p0_gd, p1_gd, r0, r1, col_rgba, segs=8):
    a = gd_to_bl(Vector(p0_gd))
    b = gd_to_bl(Vector(p1_gd))
    delta = b - a
    length = delta.length
    if length < 1e-4:
        return []
    rot = Vector((0, 0, 1)).rotation_difference(delta.normalized()).to_matrix().to_4x4()
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=length)
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) * 0.5) @ rot, verts=ret["verts"])
    for v in ret["verts"]:
        v[dlayer][bone_idx] = 1.0
    vset = set(ret["verts"])
    for f in bm.faces:
        if f.verts[0] in vset:
            for lp in f.loops:
                lp[clayer] = col_rgba
    return ret["verts"]


def build_deer():
    """梅花鹿 (Sika Deer, ~1.25m tall at antlers, graceful spotted chestnut coat & white rump)."""
    clear_scene()
    bones = ["Hips", "Spine", "Neck", "Head", "Tail", "FrontLeg_L", "FrontLeg_R", "HindLeg_L", "HindLeg_R"]
    bidx = {b: i for i, b in enumerate(bones)}
    bm = bmesh.new()
    dlayer = bm.verts.layers.deform.new()
    clayer = bm.loops.layers.color.new("Color")

    def coat_col(gx, gy, gz):
        # Spotted sika deer chestnut coat + creamy spots along dorsal flanks + pale belly/rump
        belly = max(0.0, min(1.0, (0.64 - gy) * 5.0))
        rump = max(0.0, min(1.0, (gz - 0.34) * 5.5))
        spot = 0.0
        if gy > 0.68 and abs(gx) > 0.08 and -0.25 < gz < 0.34:
            s_val = math.sin(gz * 26.0 + abs(gx) * 14.0) * math.cos(gy * 28.0 - gz * 12.0)
            if s_val > 0.62:
                spot = 0.85
        r = 0.42 * (1.0 - belly) + 0.82 * belly
        g = 0.23 * (1.0 - belly) + 0.74 * belly
        b = 0.11 * (1.0 - belly) + 0.58 * belly
        w = max(rump * 0.85, spot)
        return (r * (1 - w) + 0.92 * w, g * (1 - w) + 0.86 * w, b * (1 - w) + 0.72 * w, 1.0)

    dark_col = lambda _x, _y, _z: (0.04, 0.03, 0.03, 1.0)
    antler_col = (0.62, 0.53, 0.38, 1.0)
    hoof_col = (0.06, 0.05, 0.04, 1.0)
    leg_col = (0.36, 0.20, 0.09, 1.0)

    # Torso, chest & rump
    add_weighted_sphere(bm, dlayer, clayer, bidx["Spine"], (0.0, 0.76, -0.06), (0.21, 0.22, 0.34), coat_col, (-4.0, 0.0, 0.0), 2)
    add_weighted_sphere(bm, dlayer, clayer, bidx["Hips"], (0.0, 0.78, 0.28), (0.21, 0.22, 0.24), coat_col, (6.0, 0.0, 0.0), 2)
    # Graceful upright neck & head
    add_weighted_cyl(bm, dlayer, clayer, bidx["Neck"], (0.0, 0.82, -0.28), (0.0, 1.18, -0.44), 0.125, 0.088, (0.42, 0.24, 0.11, 1.0), 10)
    add_weighted_sphere(bm, dlayer, clayer, bidx["Head"], (0.0, 1.24, -0.48), (0.085, 0.088, 0.12), coat_col, (10.0, 0.0, 0.0), 2)
    add_weighted_sphere(bm, dlayer, clayer, bidx["Head"], (0.0, 1.20, -0.61), (0.048, 0.046, 0.085), coat_col, (14.0, 0.0, 0.0), 1)
    add_weighted_sphere(bm, dlayer, clayer, bidx["Head"], (0.0, 1.19, -0.685), (0.022, 0.018, 0.020), dark_col, sub=1)
    # Ears, eyes & branching antlers!
    for sx in (-1.0, 1.0):
        add_weighted_sphere(bm, dlayer, clayer, bidx["Head"], (sx * 0.068, 1.26, -0.53), (0.014, 0.015, 0.014), dark_col, sub=1)
        add_weighted_sphere(bm, dlayer, clayer, bidx["Head"], (sx * 0.095, 1.32, -0.44), (0.032, 0.075, 0.022), coat_col, (-12.0, 0.0, -sx * 36.0), 1)
        # Main antler beam + 2 tines
        add_weighted_cyl(bm, dlayer, clayer, bidx["Head"], (sx * 0.042, 1.32, -0.46), (sx * 0.12, 1.54, -0.40), 0.014, 0.010, antler_col, 6)
        add_weighted_cyl(bm, dlayer, clayer, bidx["Head"], (sx * 0.12, 1.54, -0.40), (sx * 0.19, 1.72, -0.46), 0.010, 0.005, antler_col, 6)
        add_weighted_cyl(bm, dlayer, clayer, bidx["Head"], (sx * 0.09, 1.44, -0.43), (sx * 0.13, 1.56, -0.56), 0.009, 0.004, antler_col, 6)
        add_weighted_cyl(bm, dlayer, clayer, bidx["Head"], (sx * 0.15, 1.62, -0.42), (sx * 0.24, 1.68, -0.34), 0.008, 0.004, antler_col, 6)

    # Short tufted white tail
    add_weighted_sphere(bm, dlayer, clayer, bidx["Tail"], (0.0, 0.80, 0.50), (0.045, 0.065, 0.055), lambda _x, _y, _z: (0.94, 0.90, 0.82, 1.0), (24.0, 0.0, 0.0), 1)
    # 4 slender legs + dark hooves
    for sx, side in ((-1.0, "L"), (1.0, "R")):
        add_weighted_cyl(bm, dlayer, clayer, bidx[f"FrontLeg_{side}"], (sx * 0.13, 0.68, -0.24), (sx * 0.13, 0.34, -0.25), 0.056, 0.036, leg_col, 8)
        add_weighted_cyl(bm, dlayer, clayer, bidx[f"FrontLeg_{side}"], (sx * 0.13, 0.34, -0.25), (sx * 0.13, 0.05, -0.24), 0.034, 0.028, leg_col, 8)
        add_weighted_cyl(bm, dlayer, clayer, bidx[f"FrontLeg_{side}"], (sx * 0.13, 0.06, -0.24), (sx * 0.13, 0.0, -0.25), 0.030, 0.032, hoof_col, 6)

        add_weighted_cyl(bm, dlayer, clayer, bidx[f"HindLeg_{side}"], (sx * 0.14, 0.70, 0.28), (sx * 0.14, 0.36, 0.34), 0.068, 0.038, leg_col, 8)
        add_weighted_cyl(bm, dlayer, clayer, bidx[f"HindLeg_{side}"], (sx * 0.14, 0.36, 0.34), (sx * 0.14, 0.05, 0.30), 0.036, 0.028, leg_col, 8)
        add_weighted_cyl(bm, dlayer, clayer, bidx[f"HindLeg_{side}"], (sx * 0.14, 0.06, 0.30), (sx * 0.14, 0.0, 0.29), 0.030, 0.032, hoof_col, 6)

    mesh = bpy.data.meshes.new("animal_deer_mesh")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(make_vcol_mat("Mat_animal_deer", roughness=0.72))
    for p in mesh.polygons:
        p.use_smooth = True
    mesh_obj = bpy.data.objects.new("animal_deer_mesh", mesh)
    bpy.context.collection.objects.link(mesh_obj)
    for b in bones:
        mesh_obj.vertex_groups.new(name=b)

    arm_d = bpy.data.armatures.new("animal_deer_arm")
    arm = bpy.data.objects.new("animal_deer", arm_d)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")

    def eb(n, h, t, par=None):
        e = arm_d.edit_bones.new(n)
        e.head, e.tail = gd_to_bl(Vector(h)), gd_to_bl(Vector(t))
        if par:
            e.parent = arm_d.edit_bones[par]

    eb("Hips", (0, 0.78, 0.26), (0, 0.76, 0.04))
    eb("Spine", (0, 0.76, 0.04), (0, 0.80, -0.28), "Hips")
    eb("Neck", (0, 0.80, -0.28), (0, 1.18, -0.44), "Spine")
    eb("Head", (0, 1.18, -0.44), (0, 1.22, -0.68), "Neck")
    eb("Tail", (0, 0.80, 0.44), (0, 0.80, 0.56), "Hips")
    eb("FrontLeg_L", (-0.13, 0.68, -0.24), (-0.13, 0.0, -0.24), "Spine")
    eb("FrontLeg_R", (0.13, 0.68, -0.24), (0.13, 0.0, -0.24), "Spine")
    eb("HindLeg_L", (-0.14, 0.70, 0.28), (-0.14, 0.0, 0.30), "Hips")
    eb("HindLeg_R", (0.14, 0.70, 0.28), (0.14, 0.0, 0.30), "Hips")
    bpy.ops.object.mode_set(mode="OBJECT")

    mesh_obj.parent = arm
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    arm.animation_data_create()
    # Idle (48f): gentle head scan & graze dip
    act_idle = bpy.data.actions.new("Idle")
    arm.animation_data.action = act_idle
    for f, ny, hy, nx in [(0, 0, 0, 0), (14, 10, 14, 12), (26, -6, -8, 22), (38, -12, -16, 4), (48, 0, 0, 0)]:
        set_bone_rot(arm, "Neck", f, nx, 0, ny)
        set_bone_rot(arm, "Head", f, nx * 0.4, 0, hy)
        set_bone_rot(arm, "Tail", f, math.sin(f * 0.3) * 14.0)

    # Walk (24f): diagonal deer trot
    act_walk = bpy.data.actions.new("Walk")
    arm.animation_data.action = act_walk
    for f, fl, fr, hl, hr in [(0, 22, -20, -20, 22), (6, 0, 0, 0, 0), (12, -20, 22, 22, -20), (18, 0, 0, 0, 0), (24, 22, -20, -20, 22)]:
        set_bone_rot(arm, "FrontLeg_L", f, fl)
        set_bone_rot(arm, "FrontLeg_R", f, fr)
        set_bone_rot(arm, "HindLeg_L", f, hl)
        set_bone_rot(arm, "HindLeg_R", f, hr)
        set_bone_rot(arm, "Neck", f, 6.0 if f in (0, 12, 24) else 0.0)

    # Run (16f): graceful bounding gallop!
    act_run = bpy.data.actions.new("Run")
    arm.animation_data.action = act_run
    for f, fl, fr, hl, hr, sp, hz in [
        (0, 46, 38, -40, -46, -12, 0.04),
        (4, -8, -14, 22, 28, 10, 0.14),
        (8, -42, -36, 44, 38, 14, 0.03),
        (12, 16, 22, -18, -24, -6, 0.11),
        (16, 46, 38, -40, -46, -12, 0.04),
    ]:
        arm.pose.bones["Hips"].location = Vector((0, 0, hz))
        arm.pose.bones["Hips"].keyframe_insert("location", frame=f)
        set_bone_rot(arm, "Spine", f, sp)
        set_bone_rot(arm, "Neck", f, -sp * 0.7)
        set_bone_rot(arm, "FrontLeg_L", f, fl)
        set_bone_rot(arm, "FrontLeg_R", f, fr)
        set_bone_rot(arm, "HindLeg_L", f, hl)
        set_bone_rot(arm, "HindLeg_R", f, hr)
        set_bone_rot(arm, "Tail", f, -32.0)

    push_actions_to_nla(arm, [act_idle, act_walk, act_run])
    export_rig(arm, OUT_DIR / "animal_deer.glb")
    print(f"Exported animal_deer.glb ({len(mesh.polygons)} polys)")


def build_pheasant():
    """山雉锦鸡 (Golden Pheasant — golden crest, crimson breast, emerald cape, long sweeping tail!)."""
    clear_scene()
    bones = ["Root", "Neck", "Head", "Wing_L", "Wing_R", "Tail", "Leg_L", "Leg_R"]
    bidx = {b: i for i, b in enumerate(bones)}
    bm = bmesh.new()
    dlayer = bm.verts.layers.deform.new()
    clayer = bm.loops.layers.color.new("Color")

    def body_col(gx, gy, gz):
        if gy < 0.25 or gz < -0.02:
            return (0.78, 0.12, 0.09, 1.0)  # royal crimson breast
        return (0.12, 0.42, 0.28, 1.0)      # emerald back mantle

    gold_col = lambda _x, _y, _z: (0.94, 0.74, 0.14, 1.0)
    wing_col = lambda _x, _y, _z: (0.48, 0.24, 0.11, 1.0)
    tail_col = lambda gx, gy, gz: (0.74, 0.52, 0.20, 1.0) if int(gz * 18) % 2 == 0 else (0.28, 0.16, 0.08, 1.0)
    leg_col = (0.78, 0.62, 0.22, 1.0)

    add_weighted_sphere(bm, dlayer, clayer, bidx["Root"], (0.0, 0.26, 0.02), (0.115, 0.11, 0.19), body_col, (-14.0, 0.0, 0.0), 2)
    add_weighted_cyl(bm, dlayer, clayer, bidx["Neck"], (0.0, 0.30, -0.11), (0.0, 0.44, -0.18), 0.062, 0.045, (0.90, 0.62, 0.14, 1.0), 8)
    add_weighted_sphere(bm, dlayer, clayer, bidx["Head"], (0.0, 0.46, -0.20), (0.046, 0.048, 0.056), gold_col, sub=2)
    add_weighted_sphere(bm, dlayer, clayer, bidx["Head"], (0.0, 0.50, -0.16), (0.024, 0.022, 0.075), gold_col, (20.0, 0.0, 0.0), 1)  # golden crest!
    add_weighted_cyl(bm, dlayer, clayer, bidx["Head"], (0.0, 0.45, -0.25), (0.0, 0.44, -0.31), 0.016, 0.003, (0.92, 0.76, 0.22, 1.0), 6)
    # Long sweeping pheasant tail feathers (0.62m!)
    add_weighted_sphere(bm, dlayer, clayer, bidx["Tail"], (0.0, 0.25, 0.44), (0.048, 0.026, 0.32), tail_col, (-8.0, 0.0, 0.0), 2)
    # Wings & legs
    for sx, side in ((-1.0, "L"), (1.0, "R")):
        add_weighted_sphere(bm, dlayer, clayer, bidx[f"Wing_{side}"], (sx * 0.125, 0.27, 0.04), (0.036, 0.088, 0.175), wing_col, (-10.0, 0.0, sx * 12.0), 2)
        add_weighted_cyl(bm, dlayer, clayer, bidx[f"Leg_{side}"], (sx * 0.055, 0.18, 0.02), (sx * 0.055, 0.01, 0.01), 0.018, 0.014, leg_col, 6)
        add_weighted_cyl(bm, dlayer, clayer, bidx[f"Leg_{side}"], (sx * 0.055, 0.012, 0.01), (sx * 0.055, 0.012, -0.055), 0.012, 0.006, leg_col, 6)

    mesh = bpy.data.meshes.new("animal_pheasant_mesh")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(make_vcol_mat("Mat_animal_pheasant", roughness=0.62))
    for p in mesh.polygons:
        p.use_smooth = True
    mesh_obj = bpy.data.objects.new("animal_pheasant_mesh", mesh)
    bpy.context.collection.objects.link(mesh_obj)
    for b in bones:
        mesh_obj.vertex_groups.new(name=b)

    arm_d = bpy.data.armatures.new("animal_pheasant_arm")
    arm = bpy.data.objects.new("animal_pheasant", arm_d)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")

    def eb(n, h, t, par=None):
        e = arm_d.edit_bones.new(n)
        e.head, e.tail = gd_to_bl(Vector(h)), gd_to_bl(Vector(t))
        if par:
            e.parent = arm_d.edit_bones[par]

    eb("Root", (0, 0.25, 0.02), (0, 0.28, -0.10))
    eb("Neck", (0, 0.28, -0.10), (0, 0.44, -0.18), "Root")
    eb("Head", (0, 0.44, -0.18), (0, 0.45, -0.30), "Neck")
    eb("Wing_L", (-0.10, 0.28, -0.02), (-0.30, 0.28, 0.06), "Root")
    eb("Wing_R", (0.10, 0.28, -0.02), (0.30, 0.28, 0.06), "Root")
    eb("Tail", (0, 0.26, 0.16), (0, 0.24, 0.72), "Root")
    eb("Leg_L", (-0.055, 0.18, 0.02), (-0.055, 0.0, 0.01), "Root")
    eb("Leg_R", (0.055, 0.18, 0.02), (0.055, 0.0, 0.01), "Root")
    bpy.ops.object.mode_set(mode="OBJECT")

    mesh_obj.parent = arm
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    arm.animation_data_create()

    act_idle = bpy.data.actions.new("Idle")
    arm.animation_data.action = act_idle
    for f, hy, hx in [(0, 0, 0), (12, 18, 12), (24, -14, -6), (36, 0, 0)]:
        set_bone_rot(arm, "Head", f, hx, 0, hy)
        set_bone_rot(arm, "Tail", f, math.sin(f * 0.25) * 6.0)

    act_walk = bpy.data.actions.new("Walk")
    arm.animation_data.action = act_walk
    for f, ll, lr, hx in [(0, 28, -28, 8), (6, 0, 0, -4), (12, -28, 28, 8), (18, 0, 0, -4), (24, 28, -28, 8)]:
        set_bone_rot(arm, "Leg_L", f, ll)
        set_bone_rot(arm, "Leg_R", f, lr)
        set_bone_rot(arm, "Neck", f, hx)

    act_run = bpy.data.actions.new("Run")
    arm.animation_data.action = act_run
    for f, ll, lr, wl in [(0, 45, -42, 22), (4, -42, 45, 36), (8, 45, -42, 22)]:
        set_bone_rot(arm, "Leg_L", f, ll)
        set_bone_rot(arm, "Leg_R", f, lr)
        set_bone_rot(arm, "Wing_L", f, 0, wl, 0)
        set_bone_rot(arm, "Wing_R", f, 0, -wl, 0)

    act_fly = bpy.data.actions.new("Fly")
    arm.animation_data.action = act_fly
    for f, wdeg in [(0, -58.0), (4, 54.0), (8, -58.0)]:
        set_bone_rot(arm, "Wing_L", f, 0, wdeg, 0)
        set_bone_rot(arm, "Wing_R", f, 0, -wdeg, 0)
        set_bone_rot(arm, "Tail", f, -12.0 if f == 4 else 6.0)

    push_actions_to_nla(arm, [act_idle, act_walk, act_run, act_fly])
    export_rig(arm, OUT_DIR / "animal_pheasant.glb")
    print(f"Exported animal_pheasant.glb ({len(mesh.polygons)} polys)")


def build_turtle():
    """清溪山龟 (Chinese Pond Turtle — domed moss-olive shell, amber rim, swimming/crawling legs)."""
    clear_scene()
    bones = ["Shell", "Head", "Tail", "FrontLeg_L", "FrontLeg_R", "HindLeg_L", "HindLeg_R"]
    bidx = {b: i for i, b in enumerate(bones)}
    bm = bmesh.new()
    dlayer = bm.verts.layers.deform.new()
    clayer = bm.loops.layers.color.new("Color")

    def shell_col(gx, gy, gz):
        if gy < 0.055:
            return (0.68, 0.56, 0.34, 1.0)  # amber plastron rim
        scute = 0.08 * math.sin(gx * 34.0) * math.cos(gz * 28.0)
        return (0.16 + scute, 0.28 + scute, 0.14 + scute * 0.5, 1.0)

    skin_col = lambda _x, _y, _z: (0.24, 0.36, 0.20, 1.0)
    add_weighted_sphere(bm, dlayer, clayer, bidx["Shell"], (0.0, 0.09, 0.0), (0.17, 0.082, 0.21), shell_col, sub=2)
    add_weighted_sphere(bm, dlayer, clayer, bidx["Head"], (0.0, 0.085, -0.25), (0.044, 0.040, 0.068), skin_col, sub=1)
    add_weighted_cyl(bm, dlayer, clayer, bidx["Head"], (0.0, 0.075, -0.17), (0.0, 0.085, -0.24), 0.032, 0.030, (0.24, 0.36, 0.20, 1.0), 8)
    add_weighted_cyl(bm, dlayer, clayer, bidx["Tail"], (0.0, 0.055, 0.18), (0.0, 0.042, 0.28), 0.022, 0.006, (0.22, 0.32, 0.18, 1.0), 6)
    for sx, side in ((-1.0, "L"), (1.0, "R")):
        add_weighted_sphere(bm, dlayer, clayer, bidx[f"FrontLeg_{side}"], (sx * 0.16, 0.042, -0.12), (0.052, 0.026, 0.068), skin_col, (0.0, sx * 24.0, 0.0), 1)
        add_weighted_sphere(bm, dlayer, clayer, bidx[f"HindLeg_{side}"], (sx * 0.15, 0.040, 0.12), (0.048, 0.024, 0.064), skin_col, (0.0, -sx * 24.0, 0.0), 1)

    mesh = bpy.data.meshes.new("animal_turtle_mesh")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(make_vcol_mat("Mat_animal_turtle", roughness=0.52))
    for p in mesh.polygons:
        p.use_smooth = True
    mesh_obj = bpy.data.objects.new("animal_turtle_mesh", mesh)
    bpy.context.collection.objects.link(mesh_obj)
    for b in bones:
        mesh_obj.vertex_groups.new(name=b)

    arm_d = bpy.data.armatures.new("animal_turtle_arm")
    arm = bpy.data.objects.new("animal_turtle", arm_d)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")

    def eb(n, h, t, par=None):
        e = arm_d.edit_bones.new(n)
        e.head, e.tail = gd_to_bl(Vector(h)), gd_to_bl(Vector(t))
        if par:
            e.parent = arm_d.edit_bones[par]

    eb("Shell", (0, 0.08, 0.06), (0, 0.08, -0.06))
    eb("Head", (0, 0.08, -0.16), (0, 0.085, -0.30), "Shell")
    eb("Tail", (0, 0.055, 0.18), (0, 0.042, 0.29), "Shell")
    eb("FrontLeg_L", (-0.12, 0.045, -0.11), (-0.22, 0.035, -0.15), "Shell")
    eb("FrontLeg_R", (0.12, 0.045, -0.11), (0.22, 0.035, -0.15), "Shell")
    eb("HindLeg_L", (-0.12, 0.042, 0.11), (-0.21, 0.032, 0.15), "Shell")
    eb("HindLeg_R", (0.12, 0.042, 0.11), (0.21, 0.032, 0.15), "Shell")
    bpy.ops.object.mode_set(mode="OBJECT")

    mesh_obj.parent = arm
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    arm.animation_data_create()

    act_idle = bpy.data.actions.new("Idle")
    arm.animation_data.action = act_idle
    for f, hy in [(0, 0), (16, 16), (32, -14), (48, 0)]:
        set_bone_rot(arm, "Head", f, 0, 0, hy)

    act_walk = bpy.data.actions.new("Walk")
    arm.animation_data.action = act_walk
    for f, s in [(0, 26), (10, -26), (20, 26)]:
        set_bone_rot(arm, "FrontLeg_L", f, 0, 0, s)
        set_bone_rot(arm, "FrontLeg_R", f, 0, 0, -s)
        set_bone_rot(arm, "HindLeg_L", f, 0, 0, -s)
        set_bone_rot(arm, "HindLeg_R", f, 0, 0, s)

    act_swim = bpy.data.actions.new("Swim")
    arm.animation_data.action = act_swim
    for f, s in [(0, 38), (6, -34), (12, 38)]:
        set_bone_rot(arm, "FrontLeg_L", f, 0, 12, s)
        set_bone_rot(arm, "FrontLeg_R", f, 0, -12, -s)
        set_bone_rot(arm, "HindLeg_L", f, 0, -10, -s)
        set_bone_rot(arm, "HindLeg_R", f, 0, 10, s)

    push_actions_to_nla(arm, [act_idle, act_walk, act_swim])
    export_rig(arm, OUT_DIR / "animal_turtle.glb")
    print(f"Exported animal_turtle.glb ({len(mesh.polygons)} polys)")


def build_butterfly():
    """山涧彩蝶 (Jiangnan Swallowtail Butterfly — luminous jade-cyan & sunlit gold wings!)."""
    clear_scene()
    bones = ["Body", "Wing_L", "Wing_R"]
    bidx = {b: i for i, b in enumerate(bones)}
    bm = bmesh.new()
    dlayer = bm.verts.layers.deform.new()
    clayer = bm.loops.layers.color.new("Color")

    add_weighted_cyl(bm, dlayer, clayer, bidx["Body"], (0, 0.05, 0.09), (0, 0.05, -0.09), 0.014, 0.016, (0.08, 0.08, 0.10, 1.0), 8)
    for sx, side in ((-1.0, "L"), (1.0, "R")):
        # Upper broad wing + lower swallowtail wing as sculpted thin dual-faced plates
        add_weighted_sphere(
            bm, dlayer, clayer, bidx[f"Wing_{side}"],
            (sx * 0.14, 0.055, -0.03), (0.14, 0.008, 0.095),
            lambda gx, _gy, gz: (0.18, 0.86, 0.78, 1.0) if abs(gx) < 0.20 else (0.98, 0.78, 0.24, 1.0),
            (0.0, -sx * 14.0, 0.0), 2
        )
        add_weighted_sphere(
            bm, dlayer, clayer, bidx[f"Wing_{side}"],
            (sx * 0.105, 0.050, 0.085), (0.095, 0.007, 0.080),
            lambda gx, _gy, gz: (0.96, 0.74, 0.22, 1.0) if abs(gx) < 0.14 else (0.12, 0.26, 0.34, 1.0),
            (0.0, sx * 18.0, 0.0), 2
        )

    mesh = bpy.data.meshes.new("animal_butterfly_mesh")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(make_vcol_mat("Mat_animal_butterfly", roughness=0.40))
    for p in mesh.polygons:
        p.use_smooth = True
    mesh_obj = bpy.data.objects.new("animal_butterfly_mesh", mesh)
    bpy.context.collection.objects.link(mesh_obj)
    for b in bones:
        mesh_obj.vertex_groups.new(name=b)

    arm_d = bpy.data.armatures.new("animal_butterfly_arm")
    arm = bpy.data.objects.new("animal_butterfly", arm_d)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")

    def eb(n, h, t, par=None):
        e = arm_d.edit_bones.new(n)
        e.head, e.tail = gd_to_bl(Vector(h)), gd_to_bl(Vector(t))
        if par:
            e.parent = arm_d.edit_bones[par]

    eb("Body", (0, 0.05, 0.08), (0, 0.05, -0.08))
    eb("Wing_L", (-0.015, 0.052, 0.0), (-0.22, 0.052, 0.0), "Body")
    eb("Wing_R", (0.015, 0.052, 0.0), (0.22, 0.052, 0.0), "Body")
    bpy.ops.object.mode_set(mode="OBJECT")

    mesh_obj.parent = arm
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    arm.animation_data_create()

    act_idle = bpy.data.actions.new("Idle")
    arm.animation_data.action = act_idle
    for f, a in [(0, 14), (10, 48), (20, 14)]:
        set_bone_rot(arm, "Wing_L", f, 0, -a, 0)
        set_bone_rot(arm, "Wing_R", f, 0, a, 0)

    act_fly = bpy.data.actions.new("Fly")
    arm.animation_data.action = act_fly
    for f, a in [(0, -56), (4, 62), (8, -56)]:
        set_bone_rot(arm, "Wing_L", f, 0, a, 0)
        set_bone_rot(arm, "Wing_R", f, 0, -a, 0)

    push_actions_to_nla(arm, [act_idle, act_fly])
    export_rig(arm, OUT_DIR / "animal_butterfly.glb")
    print(f"Exported animal_butterfly.glb ({len(mesh.polygons)} polys)")


def main():
    build_deer()
    build_pheasant()
    build_turtle()
    build_butterfly()
    print("DONE: All 4 new v0.8.6 skeletal wildlife GLBs built!")


if __name__ == "__main__":
    main()
