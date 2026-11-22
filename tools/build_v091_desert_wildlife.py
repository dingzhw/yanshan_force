#!/usr/bin/env python3
"""Build 4 brand-new skeletal-animated North African desert wildlife species for Yanshan Force v0.9.1
("Ahsarah Fortress") in Blender 4.5 LTS:
  - game/assets/slice/wildlife/animal_fennec.glb  (荒漠耳廓狐 Fennec Fox: Idle, Walk, Run)
  - game/assets/slice/wildlife/animal_camel.glb   (北非单峰驼 Dromedary Camel: Idle, Walk)
  - game/assets/slice/wildlife/animal_falcon.glb  (阿萨拉荒漠猎隼 Desert Falcon: Idle, Fly)
  - game/assets/slice/wildlife/animal_scarab.glb  (金色沙丘圣甲虫 Golden Dune Scarab: Idle, Walk)

Every GLB carries a real Skeleton3D + vertex-colored sunlit PBR mesh + looping NLA tracks matching wildlife.gd!
Run with:
  blender --background --python tools/build_v091_desert_wildlife.py
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
    return Vector((v.x, -v.z, v.y))


def make_vcol_mat(name: str, roughness: float = 0.70, metallic: float = 0.0) -> bpy.types.Material:
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
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    sc = Matrix.Diagonal((radii_gd[0], radii_gd[2], radii_gd[1], 1.0))
    xf = Matrix.Translation(gd_to_bl(Vector(center_gd))) @ rot @ sc
    for v in verts:
        p_local = v.co.copy()
        v.co = xf @ p_local
        v[dlayer][bone_idx] = 1.0
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            for lp in f.loops:
                p = lp.vert.co
                lp[clayer] = color_fn(p.x, p.z, -p.y)


def add_weighted_cone(bm, dlayer, clayer, bone_idx: int, p0_gd, p1_gd, r0, r1, color_fn, segs=8):
    a = gd_to_bl(Vector(p0_gd))
    b = gd_to_bl(Vector(p1_gd))
    d = b - a
    L = d.length
    if L < 1e-4:
        return
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=L)
    verts = ret["verts"]
    xf = Matrix.Translation((a + b) * 0.5) @ rot
    for v in verts:
        v.co = xf @ v.co
        v[dlayer][bone_idx] = 1.0
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            for lp in f.loops:
                p = lp.vert.co
                lp[clayer] = color_fn(p.x, p.z, -p.y)


def create_armature_and_mesh(name: str, bone_defs: list[tuple], bm: bmesh.types.BMesh, mat: bpy.types.Material):
    arm_data = bpy.data.armatures.new(name + "_Arm")
    arm_obj = bpy.data.objects.new(name + "_Rig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    ebones = {}
    for bname, parent_name, head_gd, tail_gd in bone_defs:
        eb = arm_data.edit_bones.new(bname)
        eb.head = gd_to_bl(Vector(head_gd))
        eb.tail = gd_to_bl(Vector(tail_gd))
        if parent_name:
            eb.parent = ebones[parent_name]
        ebones[bname] = eb
    bpy.ops.object.mode_set(mode="OBJECT")

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for p in mesh.polygons:
        p.use_smooth = True
    mesh_obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(mesh_obj)
    for bname, _, _, _ in bone_defs:
        mesh_obj.vertex_groups.new(name=bname)
    mesh_obj.parent = arm_obj
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    return arm_obj, mesh_obj


def make_action(arm: bpy.types.Object, act_name: str, end_frame: int, key_fn):
    act = bpy.data.actions.new(name=act_name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    key_fn(arm)
    for fcu in act.fcurves:
        for kp in fcu.keyframe_points:
            kp.interpolation = "BEZIER"
    return act


def build_fennec():
    """荒漠耳廓狐 (Fennec Fox): Iconic giant ears, pale cream-sand coat, bushy dark-tipped tail."""
    clear_scene()
    bones = [
        ("Root", None, (0.0, 0.24, 0.0), (0.0, 0.24, -0.20)),
        ("Head", "Root", (0.0, 0.30, -0.22), (0.0, 0.36, -0.44)),
        ("Tail", "Root", (0.0, 0.25, 0.22), (0.0, 0.22, 0.56)),
        ("LegFL", "Root", (-0.08, 0.21, -0.15), (-0.08, 0.0, -0.15)),
        ("LegFR", "Root", (0.08, 0.21, -0.15), (0.08, 0.0, -0.15)),
        ("LegBL", "Root", (-0.09, 0.21, 0.16), (-0.09, 0.0, 0.16)),
        ("LegBR", "Root", (0.09, 0.21, 0.16), (0.09, 0.0, 0.16)),
    ]
    bm = bmesh.new()
    dl = bm.verts.layers.deform.new()
    cl = bm.loops.layers.color.new("Color")

    def coat_col(x, y, z):
        if y < 0.22:
            return (0.94, 0.86, 0.72, 1.0)
        return (0.86, 0.72, 0.50, 1.0)

    def head_col(x, y, z):
        if z < -0.46:
            return (0.14, 0.12, 0.12, 1.0)  # Black button nose
        if y > 0.44 and abs(x) > 0.05:
            return (0.95, 0.74, 0.62, 1.0)  # Warm peach inner giant ears!
        return (0.90, 0.78, 0.58, 1.0)

    def tail_col(x, y, z):
        if z > 0.48:
            return (0.20, 0.16, 0.14, 1.0)  # Dark tail tip
        return (0.88, 0.74, 0.52, 1.0)

    # Lithe torso & chest
    add_weighted_sphere(bm, dl, cl, 0, (0.0, 0.25, 0.01), (0.115, 0.105, 0.24), coat_col)
    # Head, slender pointed fox snout, dark eyes & HUGE signature triangular fennec ears!
    add_weighted_sphere(bm, dl, cl, 1, (0.0, 0.34, -0.28), (0.105, 0.092, 0.115), head_col)
    add_weighted_cone(bm, dl, cl, 1, (0.0, 0.32, -0.34), (0.0, 0.30, -0.49), 0.068, 0.018, head_col, 8)
    for sgn in (-1.0, 1.0):
        # Iconic oversized upright fennec ears
        add_weighted_cone(bm, dl, cl, 1, (sgn * 0.065, 0.39, -0.26), (sgn * 0.165, 0.64, -0.24), 0.062, 0.012, head_col, 6)
        add_weighted_sphere(bm, dl, cl, 1, (sgn * 0.055, 0.36, -0.36), (0.020, 0.020, 0.020), lambda *_: (0.08, 0.07, 0.07, 1.0), sub=1)
    # Bushy desert tail
    add_weighted_cone(bm, dl, cl, 2, (0.0, 0.25, 0.20), (0.0, 0.20, 0.58), 0.045, 0.075, tail_col, 8)
    add_weighted_sphere(bm, dl, cl, 2, (0.0, 0.19, 0.57), (0.072, 0.068, 0.09), tail_col, sub=1)
    # 4 agile desert legs
    for bi, lx, lz in ((3, -0.08, -0.15), (4, 0.08, -0.15), (5, -0.09, 0.16), (6, 0.09, 0.16)):
        add_weighted_cone(bm, dl, cl, bi, (lx, 0.22, lz), (lx, 0.0, lz), 0.038, 0.024, coat_col, 6)

    mat = make_vcol_mat("Mat_Fennec", 0.78)
    arm, _ = create_armature_and_mesh("animal_fennec", bones, bm, mat)

    def k_idle(a):
        for f, hx, hy, tz in ((0, 0, -10, -8), (15, 4, 12, 10), (30, 0, -10, -8)):
            set_bone_rot(a, "Head", f, hx, hy, 0)
            set_bone_rot(a, "Tail", f, 0, tz, 0)

    def k_walk(a):
        for f, ang in ((0, 22), (8, -22), (16, 22)):
            set_bone_rot(a, "LegFL", f, ang)
            set_bone_rot(a, "LegBR", f, ang)
            set_bone_rot(a, "LegFR", f, -ang)
            set_bone_rot(a, "LegBL", f, -ang)
            set_bone_rot(a, "Tail", f, 0, ang * 0.6, 0)

    def k_run(a):
        for f, ang in ((0, 42), (6, -42), (12, 42)):
            set_bone_rot(a, "LegFL", f, ang)
            set_bone_rot(a, "LegFR", f, ang * 0.85)
            set_bone_rot(a, "LegBL", f, -ang)
            set_bone_rot(a, "LegBR", f, -ang * 0.85)
            set_bone_rot(a, "Root", f, ang * 0.16)
            set_bone_rot(a, "Tail", f, -ang * 0.25)

    acts = [make_action(arm, "Idle", 30, k_idle), make_action(arm, "Walk", 16, k_walk), make_action(arm, "Run", 12, k_run)]
    push_actions_to_nla(arm, acts)
    export_rig(arm, OUT_DIR / "animal_fennec.glb")


def build_camel():
    """北非单峰驼 (Dromedary Camel): Iconic sunlit desert camel silhouette (~2.2m tall) with hump & long neck."""
    clear_scene()
    bones = [
        ("Root", None, (0.0, 1.32, 0.0), (0.0, 1.32, -0.55)),
        ("Neck", "Root", (0.0, 1.38, -0.68), (0.0, 1.98, -1.12)),
        ("Head", "Neck", (0.0, 1.98, -1.12), (0.0, 1.92, -1.56)),
        ("Tail", "Root", (0.0, 1.28, 0.72), (0.0, 0.78, 0.84)),
        ("LegFL", "Root", (-0.28, 1.12, -0.54), (-0.28, 0.0, -0.54)),
        ("LegFR", "Root", (0.28, 1.12, -0.54), (0.28, 0.0, -0.54)),
        ("LegBL", "Root", (-0.28, 1.12, 0.56), (-0.28, 0.0, 0.56)),
        ("LegBR", "Root", (0.28, 1.12, 0.56), (0.28, 0.0, 0.56)),
    ]
    bm = bmesh.new()
    dl = bm.verts.layers.deform.new()
    cl = bm.loops.layers.color.new("Color")

    def camel_col(x, y, z):
        if y > 1.78 and abs(z) < 0.55:
            return (0.68, 0.48, 0.28, 1.0)  # Darker sun-baked wool atop hump
        if y < 0.25:
            return (0.58, 0.44, 0.30, 1.0)  # Dusty hooves/pads
        return (0.82, 0.65, 0.42, 1.0)

    def blanket_col(x, y, z):
        return (0.72, 0.20, 0.18, 1.0) if (abs(z) < 0.34 and y > 1.38) else (0.88, 0.68, 0.26, 1.0)

    # Muscular torso + signature single Saharan hump + crimson/gold Berber woven saddle blanket accent!
    add_weighted_sphere(bm, dl, cl, 0, (0.0, 1.32, 0.0), (0.46, 0.42, 0.82), camel_col)
    add_weighted_sphere(bm, dl, cl, 0, (0.0, 1.82, -0.02), (0.34, 0.42, 0.44), camel_col)
    add_weighted_sphere(bm, dl, cl, 0, (0.0, 1.56, 0.0), (0.48, 0.22, 0.46), blanket_col, sub=1)
    # Sweeping U-curved camel neck
    add_weighted_cone(bm, dl, cl, 1, (0.0, 1.32, -0.64), (0.0, 1.48, -0.98), 0.22, 0.17, camel_col, 8)
    add_weighted_cone(bm, dl, cl, 1, (0.0, 1.48, -0.98), (0.0, 1.98, -1.14), 0.17, 0.13, camel_col, 8)
    # Expressive camel head, long muzzle & small round ears
    add_weighted_sphere(bm, dl, cl, 2, (0.0, 2.02, -1.24), (0.14, 0.15, 0.20), camel_col)
    add_weighted_cone(bm, dl, cl, 2, (0.0, 1.98, -1.32), (0.0, 1.92, -1.62), 0.12, 0.085, camel_col, 8)
    for sgn in (-1.0, 1.0):
        add_weighted_sphere(bm, dl, cl, 2, (sgn * 0.11, 2.13, -1.16), (0.04, 0.055, 0.035), camel_col, sub=1)
        add_weighted_sphere(bm, dl, cl, 2, (sgn * 0.11, 2.05, -1.34), (0.026, 0.026, 0.026), lambda *_: (0.09, 0.08, 0.07, 1.0), sub=1)
    # Tufted tail
    add_weighted_cone(bm, dl, cl, 3, (0.0, 1.28, 0.72), (0.0, 0.74, 0.85), 0.045, 0.032, camel_col, 6)
    # 4 tall slender desert legs with broad sand-cushion feet
    for bi, lx, lz in ((4, -0.28, -0.54), (5, 0.28, -0.54), (6, -0.28, 0.56), (7, 0.28, 0.56)):
        add_weighted_cone(bm, dl, cl, bi, (lx, 1.14, lz), (lx, 0.55, lz), 0.115, 0.082, camel_col, 7)
        add_weighted_cone(bm, dl, cl, bi, (lx, 0.55, lz), (lx, 0.04, lz), 0.078, 0.068, camel_col, 7)
        add_weighted_sphere(bm, dl, cl, bi, (lx, 0.06, lz - 0.03), (0.10, 0.06, 0.13), camel_col, sub=1)

    mat = make_vcol_mat("Mat_Camel", 0.86)
    arm, _ = create_armature_and_mesh("animal_camel", bones, bm, mat)

    def k_idle(a):
        for f, nx, ny in ((0, -3, -6), (20, 4, 8), (40, -3, -6)):
            set_bone_rot(a, "Neck", f, nx, ny, 0)
            set_bone_rot(a, "Tail", f, 0, 0, ny * 1.4)

    def k_walk(a):
        # Authentic camel pacing gait (same-side legs swing together!)
        for f, ang in ((0, 18), (12, -18), (24, 18)):
            set_bone_rot(a, "LegFL", f, ang)
            set_bone_rot(a, "LegBL", f, ang)
            set_bone_rot(a, "LegFR", f, -ang)
            set_bone_rot(a, "LegBR", f, -ang)
            set_bone_rot(a, "Neck", f, ang * 0.22)
            set_bone_rot(a, "Root", f, 0, 0, ang * 0.12)

    acts = [make_action(arm, "Idle", 40, k_idle), make_action(arm, "Walk", 24, k_walk)]
    push_actions_to_nla(arm, acts)
    export_rig(arm, OUT_DIR / "animal_camel.glb")


def build_falcon():
    """阿萨拉荒漠猎隼 (Desert Falcon): Crisp swept raptor wings, rufous-brown & cream plumage, soaring Fly animation."""
    clear_scene()
    bones = [
        ("Root", None, (0.0, 0.24, 0.0), (0.0, 0.24, -0.32)),
        ("WingL", "Root", (-0.10, 0.26, -0.05), (-0.85, 0.28, 0.08)),
        ("WingR", "Root", (0.10, 0.26, -0.05), (0.85, 0.28, 0.08)),
        ("Tail", "Root", (0.0, 0.22, 0.22), (0.0, 0.20, 0.58)),
    ]
    bm = bmesh.new()
    dl = bm.verts.layers.deform.new()
    cl = bm.loops.layers.color.new("Color")

    def body_col(x, y, z):
        if z < -0.34:
            return (0.90, 0.72, 0.24, 1.0)  # Hooked golden-amber raptor beak
        if y < 0.23:
            return (0.92, 0.84, 0.70, 1.0)  # Cream spotted belly
        return (0.52, 0.34, 0.20, 1.0)      # Deep rufous falcon back

    def wing_col(x, y, z):
        if abs(x) > 0.62:
            return (0.20, 0.16, 0.14, 1.0)  # Dark swept primary flight tips
        return (0.62, 0.40, 0.24, 1.0)

    # Streamlined raptor torso, head & hooked beak
    add_weighted_sphere(bm, dl, cl, 0, (0.0, 0.24, -0.02), (0.11, 0.095, 0.24), body_col)
    add_weighted_sphere(bm, dl, cl, 0, (0.0, 0.29, -0.25), (0.082, 0.078, 0.095), body_col)
    add_weighted_cone(bm, dl, cl, 0, (0.0, 0.28, -0.32), (0.0, 0.25, -0.44), 0.036, 0.008, body_col, 6)
    # Swept falcate wings (left & right)
    for bi, sgn in ((1, -1.0), (2, 1.0)):
        add_weighted_sphere(bm, dl, cl, bi, (sgn * 0.36, 0.26, -0.04), (0.34, 0.032, 0.16), wing_col, (0.0, sgn * -10.0, 0.0), sub=2)
        add_weighted_cone(bm, dl, cl, bi, (sgn * 0.56, 0.26, -0.02), (sgn * 1.04, 0.28, 0.14), 0.12, 0.018, wing_col, 6)
    # Fanned falcon tail feathers
    add_weighted_sphere(bm, dl, cl, 3, (0.0, 0.22, 0.38), (0.14, 0.025, 0.22), wing_col, sub=1)

    mat = make_vcol_mat("Mat_Falcon", 0.68)
    arm, _ = create_armature_and_mesh("animal_falcon", bones, bm, mat)

    def k_idle(a):
        for f, w in ((0, -8), (14, 4), (28, -8)):
            set_bone_rot(a, "WingL", f, 0, 0, w)
            set_bone_rot(a, "WingR", f, 0, 0, -w)

    def k_fly(a):
        for f, w, tx in ((0, 34, -4), (7, -28, 6), (14, 24, -2), (22, 6, 0), (28, 34, -4)):
            set_bone_rot(a, "WingL", f, 0, 0, w)
            set_bone_rot(a, "WingR", f, 0, 0, -w)
            set_bone_rot(a, "Tail", f, tx, 0, 0)

    acts = [make_action(arm, "Idle", 28, k_idle), make_action(arm, "Fly", 28, k_fly)]
    push_actions_to_nla(arm, acts)
    export_rig(arm, OUT_DIR / "animal_falcon.glb")


def build_scarab():
    """金色沙丘圣甲虫 (Golden Dune Scarab): Iridescent emerald-gold desert beetle (~0.45m stylized)."""
    clear_scene()
    bones = [
        ("Root", None, (0.0, 0.12, 0.0), (0.0, 0.12, -0.18)),
        ("LegsL", "Root", (-0.12, 0.10, 0.0), (-0.28, 0.02, 0.0)),
        ("LegsR", "Root", (0.12, 0.10, 0.0), (0.28, 0.02, 0.0)),
    ]
    bm = bmesh.new()
    dl = bm.verts.layers.deform.new()
    cl = bm.loops.layers.color.new("Color")

    def shell_col(x, y, z):
        if z < -0.14:
            return (0.86, 0.68, 0.22, 1.0)  # Golden thoracic shield & horn
        if abs(x) < 0.025:
            return (0.12, 0.24, 0.20, 1.0)  # Wing-case seam
        return (0.24, 0.66, 0.48, 1.0) if y > 0.14 else (0.76, 0.56, 0.18, 1.0)  # Iridescent emerald-gold!

    def leg_col(x, y, z):
        return (0.22, 0.18, 0.12, 1.0)

    # Domed iridescent scarab elytra + pronotum + horned clypeus
    add_weighted_sphere(bm, dl, cl, 0, (0.0, 0.13, 0.03), (0.16, 0.105, 0.20), shell_col)
    add_weighted_sphere(bm, dl, cl, 0, (0.0, 0.12, -0.17), (0.125, 0.085, 0.10), shell_col)
    add_weighted_cone(bm, dl, cl, 0, (0.0, 0.12, -0.24), (0.0, 0.18, -0.34), 0.035, 0.010, shell_col, 6)
    # 6 articulated desert scuttling legs (3 left, 3 right)
    for bi, sgn in ((1, -1.0), (2, 1.0)):
        for lz in (-0.12, 0.0, 0.12):
            add_weighted_cone(bm, dl, cl, bi, (sgn * 0.11, 0.10, lz), (sgn * 0.25, 0.12, lz - 0.02), 0.022, 0.016, leg_col, 5)
            add_weighted_cone(bm, dl, cl, bi, (sgn * 0.25, 0.12, lz - 0.02), (sgn * 0.30, 0.01, lz + 0.01), 0.016, 0.010, leg_col, 5)

    mat = make_vcol_mat("Mat_Scarab", roughness=0.26, metallic=0.62)
    arm, _ = create_armature_and_mesh("animal_scarab", bones, bm, mat)

    def k_idle(a):
        for f, rx in ((0, -2), (12, 3), (24, -2)):
            set_bone_rot(a, "Root", f, rx, 0, 0)

    def k_walk(a):
        for f, ang in ((0, 18), (5, -18), (10, 18)):
            set_bone_rot(a, "LegsL", f, 0, ang, ang * 0.3)
            set_bone_rot(a, "LegsR", f, 0, -ang, -ang * 0.3)
            set_bone_rot(a, "Root", f, 0, 0, ang * 0.18)

    acts = [make_action(arm, "Idle", 24, k_idle), make_action(arm, "Walk", 10, k_walk)]
    push_actions_to_nla(arm, acts)
    export_rig(arm, OUT_DIR / "animal_scarab.glb")


def main():
    build_fennec()
    build_camel()
    build_falcon()
    build_scarab()
    print("Exported 4 v0.9.1 skeletal desert wildlife GLBs (fennec/camel/falcon/scarab) ->", OUT_DIR)


if __name__ == "__main__":
    main()
