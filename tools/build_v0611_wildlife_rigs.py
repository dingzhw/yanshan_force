"""Build v0.6.1.1 Skeletal Animated Wildlife Rigs (9 GLBs with Skeleton3D + NLA Actions) in Blender 4.5.

Preserves and enriches the full anatomical armatures & animations from Polyfork CC BY 4.0 wildlife
(boar, fox, rabbit, bird, egret, koi fish, river crab, river shrimp) and builds a custom 10-bone
armature + Idle/Run/Climb NLA actions for our sculpted Jiangnan woodland squirrel.

Outputs:
- game/assets/slice/wildlife/animal_boar.glb     (Idle, Walk, Run, Gore)
- game/assets/slice/wildlife/animal_fox.glb      (Idle, Walk, Run)
- game/assets/slice/wildlife/animal_rabbit.glb   (Idle, Walk, Run)
- game/assets/slice/wildlife/animal_squirrel.glb (Idle, Run, Climb)
- game/assets/slice/wildlife/animal_bird.glb     (Idle, Walk, Run, Fly)
- game/assets/slice/wildlife/animal_egret.glb    (Idle, Walk, Run, Fly, Glide)
- game/assets/slice/wildlife/animal_fish.glb     (Idle, Swim, Swim fast)
- game/assets/slice/wildlife/animal_crab.glb     (Idle, Walk, Run, Walk Sideways)
- game/assets/slice/wildlife/animal_shrimp.glb   (Idle, Walk, Swim, Swim fast)
- docs/slice-v0611-wildlife-rigs.json
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
DL_PF = ROOT / "downloads" / "slice-v061" / "polyfork"
OUT_DIR = ROOT / "game" / "assets" / "slice" / "wildlife"
DOCS_DIR = ROOT / "docs"

OUT_DIR.mkdir(parents=True, exist_ok=True)
DOCS_DIR.mkdir(parents=True, exist_ok=True)


def gd_to_bl(v: Vector) -> Vector:
    """Map Godot local coords (x_right, y_up, z_back; -Z forward) to Blender Z-up (+Y forward)."""
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


def add_boar_gore_action(arm: bpy.types.Object, run_act: bpy.types.Action) -> bpy.types.Action:
    """Clone Run leg stride and add fierce downward head-dip + upward tusk-gore whip on Neck & Head."""
    gore = run_act.copy()
    gore.name = "Gore"
    f0, f1 = gore.frame_range[0], gore.frame_range[1]
    span = max(8.0, f1 - f0)

    # Remove existing Neck/Head rotation fcurves in Gore so our head-thrust is crisp and unmistakable
    to_remove = [
        fc for fc in gore.fcurves
        if ('pose.bones["Neck"].rotation' in fc.data_path or 'pose.bones["Head"].rotation' in fc.data_path)
    ]
    for fc in to_remove:
        gore.fcurves.remove(fc)

    arm.animation_data.action = gore
    for bname, dip_deg, whip_deg in [("Neck", 20.0, -28.0), ("Head", 24.0, -38.0)]:
        pb = arm.pose.bones.get(bname)
        if pb is None:
            continue
        pb.rotation_mode = "QUATERNION"
        keys = [
            (f0, 6.0),
            (f0 + span * 0.30, dip_deg),
            (f0 + span * 0.65, whip_deg),
            (f1, 6.0),
        ]
        for frame, deg_x in keys:
            pb.rotation_quaternion = Euler((math.radians(deg_x), 0.0, 0.0), "XYZ").to_quaternion()
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
    arm.animation_data.action = None
    return gore


def add_egret_glide_action(arm: bpy.types.Object, fly_act: bpy.types.Action) -> bpy.types.Action:
    """Create a serene soaring Glide action from the open-wing frame of herring-gull Fly."""
    glide = bpy.data.actions.new(name="Glide")
    arm.animation_data.action = fly_act
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()

    # Snapshot open-wing pose from frame 0 of Fly
    base_pose: dict[str, tuple[Vector, Quaternion, Vector]] = {}
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        base_pose[pb.name] = (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy())

    arm.animation_data.action = glide
    for frame, tip_deg in [(0.0, -3.5), (18.0, 4.5), (36.0, -3.5)]:
        for pb in arm.pose.bones:
            loc, quat, sc = base_pose[pb.name]
            pb.location = loc
            q = quat.copy()
            if "WingTip" in pb.name or "WingElbow" in pb.name:
                sgn = -1.0 if pb.name.startswith("Left") else 1.0
                q = q @ Euler((0.0, math.radians(sgn * tip_deg), 0.0), "XYZ").to_quaternion()
            pb.rotation_quaternion = q
            pb.keyframe_insert(data_path="location", frame=frame)
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
    arm.animation_data.action = None
    return glide


def add_pigeon_fly_action(arm: bpy.types.Object) -> bpy.types.Action:
    """Author a brisk 14-frame wing-spreading + wingbeat Fly action for spotted woodland dove."""
    fly = bpy.data.actions.new(name="Fly")
    arm.animation_data.action = fly
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = Vector((0.0, 0.0, 0.0))
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))

    # Frames: 0 (upstroke), 4 (mid-down), 7 (downstroke), 11 (mid-up), 14 (upstroke loop)
    keyframes = [
        (0.0, -38.0, -24.0, 0.012),
        (4.0, 6.0, -10.0, 0.002),
        (7.0, 36.0, 26.0, -0.012),
        (11.0, -8.0, 12.0, 0.003),
        (14.0, -38.0, -24.0, 0.012),
    ]
    for frame, flap_deg, tip_deg, bob_z in keyframes:
        hips = arm.pose.bones.get("Hips")
        if hips:
            hips.location = Vector((0.0, 0.0, bob_z))
            hips.rotation_quaternion = Euler((math.radians(-8.0), 0.0, 0.0), "XYZ").to_quaternion()
            hips.keyframe_insert(data_path="location", frame=frame)
            hips.keyframe_insert(data_path="rotation_quaternion", frame=frame)

        for side, sgn in [("Left", 1.0), ("Right", -1.0)]:
            w = arm.pose.bones.get(f"{side}Wing")
            wt = arm.pose.bones.get(f"{side}WingTip")
            leg = arm.pose.bones.get(f"{side}UpLeg")
            if w:
                # Spread folded wing (+Y -> +/-X via Z rotation), then flap around Y!
                q_spread = Euler((0.0, 0.0, math.radians(-sgn * 74.0)), "XYZ").to_quaternion()
                q_flap = Euler((0.0, math.radians(sgn * flap_deg), 0.0), "XYZ").to_quaternion()
                w.rotation_quaternion = q_flap @ q_spread
                w.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if wt:
                wt.rotation_quaternion = Euler((0.0, math.radians(sgn * tip_deg), math.radians(-sgn * 12.0)), "XYZ").to_quaternion()
                wt.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if leg:
                # Tuck legs neatly backward during flight
                leg.rotation_quaternion = Euler((math.radians(-52.0), 0.0, 0.0), "XYZ").to_quaternion()
                leg.keyframe_insert(data_path="rotation_quaternion", frame=frame)

        tail = arm.pose.bones.get("Tail")
        if tail:
            tail.rotation_quaternion = Euler((math.radians(8.0 + flap_deg * 0.12), 0.0, 0.0), "XYZ").to_quaternion()
            tail.keyframe_insert(data_path="rotation_quaternion", frame=frame)

    arm.animation_data.action = None
    return fly


def add_boar_tusks_skinned(mesh_obj: bpy.types.Object, arm: bpy.types.Object) -> None:
    """Append two curved pale-ivory tusks in Mesh_0 rest space and weight them 1.0 to 'Head' bone."""
    mesh = mesh_obj.data
    vs = [v.co for v in mesh.vertices]
    ymin = min(v.y for v in vs)  # Snout tip in rest space (-Y)
    head_b = arm.data.bones.get("Head")
    snout_z = head_b.head_local.z * 0.54 if head_b else 0.42
    snout_y = ymin + 0.09

    bm = bmesh.new()
    bm.from_mesh(mesh)
    clayer = bm.loops.layers.color.get("Color") or bm.loops.layers.color.new("Color")
    dlayer = bm.verts.layers.deform.verify()
    head_vg = mesh_obj.vertex_groups.get("Head") or mesh_obj.vertex_groups.new(name="Head")
    h_idx = head_vg.index

    for sgn in (-1.0, 1.0):
        pts = [
            Vector((sgn * 0.095, snout_y + 0.04, snout_z)),
            Vector((sgn * 0.145, snout_y - 0.03, snout_z + 0.055)),
            Vector((sgn * 0.160, snout_y - 0.01, snout_z + 0.145)),
        ]
        radii = [0.026, 0.018, 0.004]
        rings = []
        segs = 6
        for idx, p in enumerate(pts):
            tang = (pts[min(idx + 1, 2)] - pts[max(idx - 1, 0)]).normalized()
            ref = Vector((1.0, 0.0, 0.0)) if abs(tang.x) < 0.9 else Vector((0.0, 1.0, 0.0))
            n1 = (ref - tang * ref.dot(tang)).normalized()
            n2 = tang.cross(n1).normalized()
            ring = []
            for s in range(segs):
                ang = s * math.tau / segs
                v = bm.verts.new(p + n1 * (math.cos(ang) * radii[idx]) + n2 * (math.sin(ang) * radii[idx]))
                v[dlayer][h_idx] = 1.0
                ring.append(v)
            rings.append(ring)
        tip_v = bm.verts.new(pts[-1])
        tip_v[dlayer][h_idx] = 1.0
        new_faces = []
        for i in range(len(rings) - 1):
            for s in range(segs):
                ns = (s + 1) % segs
                new_faces.append(bm.faces.new([rings[i][s], rings[i][ns], rings[i + 1][ns], rings[i + 1][s]]))
        for s in range(segs):
            ns = (s + 1) % segs
            new_faces.append(bm.faces.new([rings[-1][s], rings[-1][ns], tip_v]))
        for f in new_faces:
            for loop in f.loops:
                loop[clayer] = (0.88, 0.84, 0.70, 1.0)

    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()


def export_polyfork_rigged(
    src_stem: str,
    out_name: str,
    target_length_m: float,
    roughness: float = 0.68,
    center_vertically: bool = False,
    decimate_max_tris: int = 1380,
    color_fn=None,
    is_boar: bool = False,
    is_bird: bool = False,
    is_egret: bool = False,
) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    glb_path = DL_PF / f"{src_stem}.glb"
    bpy.ops.import_scene.gltf(filepath=str(glb_path))

    # Remove bone custom-shape widget meshes (e.g., 42-vert icosphere)
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    arm = arms[0]
    for pb in arm.pose.bones:
        pb.custom_shape = None

    skinned_meshes = [
        o for o in bpy.data.objects
        if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)
    ]
    mesh_obj = max(skinned_meshes, key=lambda o: len(o.data.vertices))

    # Delete any unrelated helper objects/empties after unparenting arm & mesh_obj cleanly
    bpy.ops.object.select_all(action="DESELECT")
    for o in list(bpy.data.objects):
        if o not in (arm, mesh_obj):
            if o.type == "EMPTY":
                for ch in list(o.children):
                    mw = ch.matrix_world.copy()
                    ch.parent = None
                    ch.matrix_world = mw
            bpy.data.objects.remove(o, do_unlink=True)

    # Set armature to REST pose while editing vertex positions, colors, tusks, and decimating
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()

    if is_boar:
        for v in mesh_obj.data.vertices:
            v.co.x *= 0.83
            if v.co.y < -0.32:
                t = (-0.32 - v.co.y) / 0.38
                v.co.y -= 0.08 * min(1.5, t)
                v.co.x *= max(0.70, 1.0 - 0.18 * t)

    if color_fn is not None and mesh_obj.data.color_attributes:
        ca = mesh_obj.data.color_attributes[0]
        if ca.domain == "CORNER":
            for poly in mesh_obj.data.polygons:
                for li in poly.loop_indices:
                    vi = mesh_obj.data.loops[li].vertex_index
                    vco = mesh_obj.data.vertices[vi].co
                    c = ca.data[li].color
                    nr, ng, nb = color_fn(vco, (c[0], c[1], c[2]))
                    ca.data[li].color = (nr, ng, nb, 1.0)
        elif ca.domain == "POINT":
            for vi, v in enumerate(mesh_obj.data.vertices):
                c = ca.data[vi].color
                nr, ng, nb = color_fn(v.co, (c[0], c[1], c[2]))
                ca.data[vi].color = (nr, ng, nb, 1.0)

    if is_boar:
        add_boar_tusks_skinned(mesh_obj, arm)

    # Decimate BEFORE Armature modifier so all vertex group skin weights interpolate cleanly!
    cur_tris = sum(max(1, len(p.vertices) - 2) for p in mesh_obj.data.polygons)
    if cur_tris > decimate_max_tris:
        bpy.ops.object.select_all(action="DESELECT")
        mesh_obj.select_set(True)
        bpy.context.view_layer.objects.active = mesh_obj
        dec = mesh_obj.modifiers.new(name="DecimateV0611", type="DECIMATE")
        dec.ratio = max(0.28, decimate_max_tris / float(cur_tris))
        bpy.ops.object.modifier_move_to_index(modifier=dec.name, index=0)
        bpy.ops.object.modifier_apply(modifier=dec.name)

    if mesh_obj.data.color_attributes:
        mesh_obj.data.color_attributes[0].name = "Color"
    mat = make_vcol_mat(f"Mat_{out_name}", roughness=roughness)
    mesh_obj.data.materials.clear()
    mesh_obj.data.materials.append(mat)
    for poly in mesh_obj.data.polygons:
        poly.use_smooth = True

    # Measure rest-pose world bounds to wrap under a clean Root EMPTY (-Z forward in Godot, grounded & scaled)
    vs_world = [mesh_obj.matrix_world @ v.co for v in mesh_obj.data.vertices]
    xmin, xmax = min(v.x for v in vs_world), max(v.x for v in vs_world)
    ymin, ymax = min(v.y for v in vs_world), max(v.y for v in vs_world)
    zmin, zmax = min(v.z for v in vs_world), max(v.z for v in vs_world)
    span_horiz = max(xmax - xmin, ymax - ymin, 1e-4)
    scale_f = target_length_m / span_horiz
    cz = 0.5 * (zmin + zmax) if center_vertically else zmin

    arm.data.pose_position = "POSE"
    keep_acts = [a for a in list(bpy.data.actions)]
    if is_boar:
        run_a = next((a for a in keep_acts if a.name == "Run"), None)
        if run_a is not None:
            keep_acts.append(add_boar_gore_action(arm, run_a))
    if is_egret:
        fly_a = next((a for a in keep_acts if a.name == "Fly"), None)
        if fly_a is not None:
            keep_acts.append(add_egret_glide_action(arm, fly_a))
    if is_bird:
        keep_acts.append(add_pigeon_fly_action(arm))

    exported_clips = push_actions_to_nla(arm, keep_acts)

    # Create wrapper Root EMPTY: rotates 180 deg around Z (-Y head -> +Y Blender = -Z Godot Forward!) and scales!
    root_empty = bpy.data.objects.new(out_name, None)
    bpy.context.collection.objects.link(root_empty)
    arm.name = f"{out_name}_rig"
    mesh_obj.name = f"{out_name}_mesh"

    # Shift arm slightly so in rest pose it is centered horizontally & grounded before Root scale/rot
    cx = 0.5 * (xmin + xmax)
    cy = 0.5 * (ymin + ymax)
    offset = Vector((-cx, -cy, -cz))
    for top in (arm, mesh_obj):
        if top.parent is None:
            top.location = top.location + offset
            top.parent = root_empty
            top.matrix_parent_inverse = Matrix.Identity(4)

    root_empty.rotation_euler = Euler((0.0, 0.0, math.pi), "XYZ")
    root_empty.scale = Vector((scale_f, scale_f, scale_f))
    bpy.context.view_layer.update()

    out_glb = OUT_DIR / f"{out_name}.glb"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
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

    tris = sum(max(1, len(p.vertices) - 2) for p in mesh_obj.data.polygons)
    return {
        "file": f"game/assets/slice/wildlife/{out_name}.glb",
        "bytes": out_glb.stat().st_size,
        "triangles": tris,
        "bones": len(arm.data.bones),
        "animations": exported_clips,
    }


def export_rigged_squirrel() -> dict:
    """Build custom 10-bone rigged Jiangnan Red Squirrel with Idle, Run & vertical Climb NLA animations."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    dlayer = bm.verts.layers.deform.verify()
    clayer = bm.loops.layers.color.new("Color")
    bone_order = [
        "Hips", "Spine", "Head",
        "Tail1", "Tail2", "Tail3",
        "FrontLeg_L", "FrontLeg_R",
        "HindLeg_L", "HindLeg_R",
    ]
    bone_to_idx = {b: i for i, b in enumerate(bone_order)}

    def _part_sphere(bgroup: str, center_gd, radii_gd, rot_deg=(0.0, 0.0, 0.0), sub=2, tag: str = "body"):
        ret = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        eu = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix()
        cx, cy, cz = center_gd
        rx, ry, rz = radii_gd
        bi = bone_to_idx[bgroup]
        for v in ret["verts"]:
            p = eu @ Vector((v.co.x * rx, v.co.y * ry, v.co.z * rz))
            v.co = gd_to_bl(Vector((cx + p.x, cy + p.y, cz + p.z)))
            v[dlayer][bi] = 1.0
            v.tag = (tag == "dark")
        # Paint loop colors immediately on new faces created by this icosphere
        vert_set = set(ret["verts"])
        for f in bm.faces:
            if f.verts[0] in vert_set:
                for loop in f.loops:
                    v = loop.vert
                    if tag == "dark":
                        loop[clayer] = (0.025, 0.022, 0.022, 1.0)
                    elif tag == "tail":
                        gy = v.co.z
                        tip_t = max(0.0, min(1.0, (gy - 0.14) / 0.23))
                        loop[clayer] = (0.28 + 0.18 * tip_t, 0.11 + 0.10 * tip_t, 0.04 + 0.05 * tip_t, 1.0)
                    else:
                        gx, gy, gz = v.co.x, v.co.z, -v.co.y
                        belly = max(0.0, min(1.0, (0.105 - gy) * 9.0 + (0.042 - abs(gx)) * 8.0))
                        if gz > 0.10:
                            belly *= 0.25
                        loop[clayer] = (
                            0.30 * (1.0 - belly) + 0.72 * belly,
                            0.13 * (1.0 - belly) + 0.62 * belly,
                            0.05 * (1.0 - belly) + 0.46 * belly,
                            1.0,
                        )
        return ret["verts"]

    _part_sphere("Spine", (0.0, 0.115, -0.015), (0.066, 0.064, 0.095), (-12.0, 0.0, 0.0), sub=2)
    _part_sphere("Hips", (0.0, 0.105, 0.080), (0.072, 0.072, 0.078), (8.0, 0.0, 0.0), sub=2)
    _part_sphere("Head", (0.0, 0.168, -0.110), (0.056, 0.054, 0.066), (8.0, 0.0, 0.0), sub=2)
    _part_sphere("Head", (0.0, 0.155, -0.170), (0.032, 0.028, 0.038), (12.0, 0.0, 0.0), sub=1)
    _part_sphere("Head", (0.0, 0.158, -0.204), (0.011, 0.010, 0.012), sub=1, tag="dark")
    for sx, side in [(-1.0, "L"), (1.0, "R")]:
        _part_sphere("Head", (sx * 0.036, 0.228, -0.094), (0.014, 0.034, 0.018), (-10.0, 0.0, -sx * 14.0), sub=1)
        _part_sphere("Head", (sx * 0.040, 0.258, -0.092), (0.006, 0.018, 0.007), sub=1)
        _part_sphere("Head", (sx * 0.044, 0.180, -0.142), (0.010, 0.011, 0.011), sub=1, tag="dark")
        # Hind limbs & paws
        _part_sphere(f"HindLeg_{side}", (sx * 0.058, 0.068, 0.072), (0.032, 0.052, 0.046), (18.0, 0.0, 0.0), sub=1)
        _part_sphere(f"HindLeg_{side}", (sx * 0.056, 0.016, 0.040), (0.020, 0.016, 0.046), sub=1)
        # Forelimbs & paws
        _part_sphere(f"FrontLeg_{side}", (sx * 0.046, 0.068, -0.068), (0.020, 0.048, 0.022), (-14.0, 0.0, 0.0), sub=1)
        _part_sphere(f"FrontLeg_{side}", (sx * 0.046, 0.015, -0.090), (0.016, 0.015, 0.032), sub=1)

    tail_specs = [
        ("Tail1", (0.0, 0.115, 0.145), (0.046, 0.048, 0.062), (38.0, 0.0, 0.0)),
        ("Tail1", (0.0, 0.185, 0.195), (0.058, 0.072, 0.064), (16.0, 0.0, 0.0)),
        ("Tail2", (0.0, 0.268, 0.205), (0.064, 0.078, 0.068), (-8.0, 0.0, 0.0)),
        ("Tail2", (0.0, 0.335, 0.172), (0.056, 0.062, 0.065), (-36.0, 0.0, 0.0)),
        ("Tail3", (0.0, 0.358, 0.118), (0.042, 0.040, 0.052), (-62.0, 0.0, 0.0)),
    ]
    for bg, tc, tr, trot in tail_specs:
        _part_sphere(bg, tc, tr, trot, sub=2, tag="tail")

    mesh = bpy.data.meshes.new("animal_squirrel_mesh")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(make_vcol_mat("Mat_animal_squirrel", roughness=0.68))
    for poly in mesh.polygons:
        poly.use_smooth = True

    mesh_obj = bpy.data.objects.new("animal_squirrel_mesh", mesh)
    bpy.context.collection.objects.link(mesh_obj)
    for bname in bone_order:
        mesh_obj.vertex_groups.new(name=bname)

    # Build Armature in Blender Z-up (+Y = Godot -Z Forward!)
    arm_data = bpy.data.armatures.new("animal_squirrel_arm")
    arm = bpy.data.objects.new("animal_squirrel", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")

    def _eb(name: str, head_gd, tail_gd, parent_name: str | None = None):
        eb = arm_data.edit_bones.new(name)
        eb.head = gd_to_bl(Vector(head_gd))
        eb.tail = gd_to_bl(Vector(tail_gd))
        eb.roll = 0.0
        if parent_name:
            eb.parent = arm_data.edit_bones[parent_name]
        return eb

    _eb("Hips", (0.0, 0.105, 0.080), (0.0, 0.112, 0.010))
    _eb("Spine", (0.0, 0.112, 0.010), (0.0, 0.145, -0.085), "Hips")
    _eb("Head", (0.0, 0.145, -0.085), (0.0, 0.165, -0.195), "Spine")
    _eb("Tail1", (0.0, 0.110, 0.125), (0.0, 0.215, 0.198), "Hips")
    _eb("Tail2", (0.0, 0.215, 0.198), (0.0, 0.330, 0.180), "Tail1")
    _eb("Tail3", (0.0, 0.330, 0.180), (0.0, 0.365, 0.110), "Tail2")
    _eb("FrontLeg_L", (-0.046, 0.102, -0.062), (-0.046, 0.012, -0.088), "Spine")
    _eb("FrontLeg_R", (0.046, 0.102, -0.062), (0.046, 0.012, -0.088), "Spine")
    _eb("HindLeg_L", (-0.056, 0.098, 0.072), (-0.056, 0.012, 0.045), "Hips")
    _eb("HindLeg_R", (0.056, 0.098, 0.072), (0.056, 0.012, 0.045), "Hips")
    bpy.ops.object.mode_set(mode="OBJECT")

    mesh_obj.parent = arm
    mod = mesh_obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = arm

    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    def _set_rot_x(act: bpy.types.Action, bname: str, frame: float, deg_x: float, deg_z: float = 0.0):
        pb = arm.pose.bones[bname]
        # Convert world X pitch / Z yaw delta into bone local quaternion cleanly
        m_bone = arm.data.bones[bname].matrix_local.to_3x3()
        w_rot = Euler((math.radians(deg_x), 0.0, math.radians(deg_z)), "XYZ").to_matrix()
        pb.rotation_quaternion = (m_bone.inverted() @ w_rot @ m_bone).to_quaternion()
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)

    # 1. Idle (48 frames): alert head look + S-tail gentle flicks
    act_idle = bpy.data.actions.new(name="Idle")
    arm.animation_data_create()
    arm.animation_data.action = act_idle
    for f, head_yaw, tail_x in [(0, 0.0, 0.0), (12, 14.0, 12.0), (24, -4.0, -8.0), (36, -15.0, 14.0), (48, 0.0, 0.0)]:
        _set_rot_x(act_idle, "Head", f, 4.0, head_yaw)
        _set_rot_x(act_idle, "Tail1", f, tail_x)
        _set_rot_x(act_idle, "Tail2", f, tail_x * 1.2)
        _set_rot_x(act_idle, "Tail3", f, tail_x * 1.4)

    # 2. Run (16 frames): bounding woodland gallop — forelimbs reach forward (+X rot in Blender? Let's check:
    # In Blender +Y forward / +Z up, rotating around +X by +deg tips +Z toward -Y (backward) and -Z (downward leg!) toward +Y (FORWARD!)!
    # Wait: right-hand rule around +X: +Y -> +Z, +Z -> -Y, -Z -> +Y! YES! +deg_x swings a downward (-Z) leg FORWARD (+Y)!
    act_run = bpy.data.actions.new(name="Run")
    arm.animation_data.action = act_run
    run_keys = [
        (0, 44.0, 38.0, -36.0, -42.0, -14.0, -28.0, 0.025),
        (4, -10.0, -16.0, 26.0, 32.0, 12.0, -18.0, 0.052),
        (8, -42.0, -36.0, 44.0, 40.0, 16.0, -10.0, 0.018),
        (12, 18.0, 24.0, -16.0, -22.0, -8.0, -24.0, 0.044),
        (16, 44.0, 38.0, -36.0, -42.0, -14.0, -28.0, 0.025),
    ]
    for f, fl, fr, hl, hr, sp, tl, hz in run_keys:
        arm.pose.bones["Hips"].location = Vector((0.0, 0.0, hz))
        arm.pose.bones["Hips"].keyframe_insert(data_path="location", frame=f)
        _set_rot_x(act_run, "Spine", f, sp)
        _set_rot_x(act_run, "Head", f, -sp * 0.6)
        _set_rot_x(act_run, "FrontLeg_L", f, fl)
        _set_rot_x(act_run, "FrontLeg_R", f, fr)
        _set_rot_x(act_run, "HindLeg_L", f, hl)
        _set_rot_x(act_run, "HindLeg_R", f, hr)
        _set_rot_x(act_run, "Tail1", f, tl)
        _set_rot_x(act_run, "Tail2", f, tl * 0.8)

    # 3. Climb (12 frames): rapid diagonal tree-trunk scramble!
    act_climb = bpy.data.actions.new(name="Climb")
    arm.animation_data.action = act_climb
    climb_keys = [
        (0, 48.0, -42.0, -40.0, 46.0, 8.0),
        (3, 10.0, 12.0, 10.0, -12.0, -6.0),
        (6, -42.0, 48.0, 46.0, -40.0, 8.0),
        (9, -10.0, -12.0, -10.0, 12.0, -6.0),
        (12, 48.0, -42.0, -40.0, 46.0, 8.0),
    ]
    for f, fl, fr, hl, hr, tl in climb_keys:
        _set_rot_x(act_climb, "FrontLeg_L", f, fl)
        _set_rot_x(act_climb, "FrontLeg_R", f, fr)
        _set_rot_x(act_climb, "HindLeg_L", f, hl)
        _set_rot_x(act_climb, "HindLeg_R", f, hr)
        _set_rot_x(act_climb, "Spine", f, tl * 0.6)
        _set_rot_x(act_climb, "Tail1", f, -22.0 + tl)
        _set_rot_x(act_climb, "Tail2", f, -16.0 - tl)

    exported_clips = push_actions_to_nla(arm, [act_idle, act_run, act_climb])
    out_glb = OUT_DIR / "animal_squirrel.glb"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
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
    tris = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
    return {
        "file": "game/assets/slice/wildlife/animal_squirrel.glb",
        "bytes": out_glb.stat().st_size,
        "triangles": tris,
        "bones": len(arm.data.bones),
        "animations": exported_clips,
    }


def _boar_pelage(vco: Vector, rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = rgb
    if r < 0.06 and g < 0.06 and b < 0.06:
        return (r, g, b)
    stripe = 0.5 + 0.5 * math.sin(abs(vco.x) * 26.0 + vco.z * 9.0)
    dorsal = max(0.0, min(1.0, (vco.z - 0.55) / 0.48))
    return (
        0.11 + 0.08 * stripe * (1.0 - 0.55 * dorsal),
        0.075 + 0.055 * stripe * (1.0 - 0.60 * dorsal),
        0.045 + 0.025 * stripe * (1.0 - 0.65 * dorsal),
    )


def _dove_plumage(vco: Vector, rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = rgb
    if r < 0.06 and g < 0.06 and b < 0.06:
        return (r, g, b)
    # Note: in rest space before Root 180-Z, front breast is at -Y!
    breast = max(0.0, min(1.0, (-vco.y + 0.02) * 6.0)) * max(0.0, min(1.0, (0.22 - vco.z) * 6.0))
    nr = (r * 0.95 + 0.06) * (1.0 - breast) + 0.46 * breast
    ng = (g * 1.05 + 0.06) * (1.0 - breast) + 0.31 * breast
    nb = (b * 1.15 + 0.08) * (1.0 - breast) + 0.24 * breast
    return (min(1.0, nr), min(1.0, ng), min(1.0, nb))


def _egret_plumage(vco: Vector, rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = rgb
    if r < 0.08 and g < 0.08 and b < 0.08:
        return (r, g, b)  # dark eyes/wingtips/feet
    # Preserve golden-yellow beak/legs where red+green >> blue
    if r > 0.45 and g > 0.30 and (r - b) > 0.20:
        return (min(1.0, r * 1.05), min(1.0, g * 0.98), b * 0.65)
    # Brighten grey seagull mantle into snowy Jiangnan White Egret plumage!
    lum = max(r, g, b)
    w = min(0.96, 0.78 + 0.20 * lum)
    return (w, w, min(0.98, w * 1.01))


def _jade_shrimp(vco: Vector, rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = rgb
    if r < 0.08 and g < 0.08 and b < 0.08:
        return (0.02, 0.02, 0.02)
    lum = 0.35 * r + 0.45 * g + 0.20 * b
    return (0.18 + 0.24 * lum, 0.34 + 0.32 * lum, 0.22 + 0.22 * lum)


def main() -> None:
    manifest: dict[str, dict] = {}
    manifest["animal_boar"] = export_polyfork_rigged(
        "pig-base", "animal_boar", target_length_m=0.92, color_fn=_boar_pelage, is_boar=True, decimate_max_tris=1450
    )
    manifest["animal_fox"] = export_polyfork_rigged(
        "red-fox-5c3bc0", "animal_fox", target_length_m=0.86, decimate_max_tris=1420
    )
    manifest["animal_rabbit"] = export_polyfork_rigged(
        "forest-rabbit-ea2da0", "animal_rabbit", target_length_m=0.46, decimate_max_tris=1320
    )
    manifest["animal_squirrel"] = export_rigged_squirrel()
    manifest["animal_bird"] = export_polyfork_rigged(
        "pigeon-base", "animal_bird", target_length_m=0.38, color_fn=_dove_plumage, is_bird=True, decimate_max_tris=1280
    )
    manifest["animal_egret"] = export_polyfork_rigged(
        "herring-gull-base", "animal_egret", target_length_m=0.58, color_fn=_egret_plumage, is_egret=True, decimate_max_tris=1520
    )
    manifest["animal_fish"] = export_polyfork_rigged(
        "koi-base", "animal_fish", target_length_m=0.44, roughness=0.30, center_vertically=True, decimate_max_tris=1320
    )
    manifest["animal_crab"] = export_polyfork_rigged(
        "shore-crab-base", "animal_crab", target_length_m=0.38, roughness=0.34, decimate_max_tris=1320
    )
    manifest["animal_shrimp"] = export_polyfork_rigged(
        "cleaner-shrimp-base", "animal_shrimp", target_length_m=0.36, roughness=0.30, center_vertically=True, color_fn=_jade_shrimp, decimate_max_tris=1250
    )

    total_kb = sum(v["bytes"] for v in manifest.values()) / 1024.0
    (DOCS_DIR / "slice-v0611-wildlife-rigs.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(f"V0611_WILDLIFE_RIGS_OK count={len(manifest)} total_kb={total_kb:.1f}")
    for k, v in manifest.items():
        print(f"  {k}: {v['bytes']/1024:.1f} KB, tris={v['triangles']}, bones={v['bones']}, clips={v['animations']}")


if __name__ == "__main__":
    main()
