"""Build v0.9.4 Hero Protagonist '游侠·少羽' (Shaoyu) Rigged & Animated Character.

Pipeline (100% CC0 Public Domain bases + Blender 4.5 sculpting/retargeting):
- Base topology & artist-painted 49-bone skin weights:
  * Quaternius Ultimate Modular Men (CC0-1.0): Swat (tactical body/gloves/cargo pants/kneepads/boots)
    + Casual (clean-shaven teenage boy head/face/eyes/brows/hair)
- Animation sources (world-space quaternion retargeted onto normalized 1.75m CharacterArmature):
  * Quaternius Universal Animation Library Godot Standard (CC0-1.0):
    Idle, Walk, Jog, Sprint, Crouch Idle, Crouch Walk, Jump Start/Loop/Land, Sword Idle
  * KayKit Character Animations 1.1 (CC0-1.0):
    Walk Back, Strafe Left/Right, Crawling, Reload, Melee Diagonal/Horizontal Slashes
- Custom Blender 4.5 Sculpting & Hero Details (Plan B — Translucent Amber Goggles over Eyes):
  * Welded smooth-shaded stylized PBR meshes + procedural woven fabric / leather / gold cloud patch textures
  * Layered windswept dark-black hair, Plan B translucent amber tactical goggles, single-ear comms headset
  * Cinnabar-red woven ranger scarf + 4-bone skinned flowing tail (Scarf_01..04 for Godot SpringBoneSimulator3D)
  * Bamboo-teal rolled-sleeve tactical jacket + forearm wraps + MOLLE 3-mag chest rig + radio + bronze knuckle pads
  * Compact ergonomic mountain-ranger daypack (sleek silhouette, zero bulky box)
  * Dedicated Weapon_R & Weapon_Back attachment bones + analytical Blender 2-bone IK rifle poses
    (Rifle_LowReady, Rifle_Aim, Rifle_Fire, Rifle_Reload, Prone_Idle, Shaoyu_GroundSlam)
- Exports clean single GLB -> game/assets/slice/player_shaoyu.glb
- Also renders a 4-panel studio proof sheet to scratch/v094_blender_studio_proof.png (when --preview passed)
"""
import bpy
import bmesh
import math
import os
import sys
import numpy as np
from mathutils import Vector, Matrix, Quaternion, Euler

import tempfile
from pathlib import Path

ROOT = str(Path(__file__).resolve().parents[1])
CC0_DIR = os.path.join(ROOT, "third_party", "v094_cc0_characters")
RIFLE_GLB = os.path.join(ROOT, "game", "assets", "slice", "rifle.glb")
OUT_GLB = os.path.join(ROOT, "game", "assets", "slice", "player_shaoyu.glb")
PREVIEW_PNG = os.path.join(tempfile.gettempdir(), "v094_blender_studio_proof.png")

TARGET_HEIGHT = 1.75


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def remove_icospheres(objs):
    keep = []
    for o in objs:
        if o.name not in bpy.data.objects:
            continue
        if o.type == "MESH" and len(o.data.vertices) == 42 and len(o.data.polygons) == 80:
            bpy.data.objects.remove(o, do_unlink=True)
        else:
            keep.append(o)
    return keep


# ---------------------------------------------------------------------------
# Procedural PBR Textures (numpy -> packed bpy.data.images, zero external deps)
# ---------------------------------------------------------------------------
def make_fabric_normal_image(name="Tex_RipstopNormal", size=256, grid=16, strength=0.35):
    if name in bpy.data.images:
        return bpy.data.images[name]
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    # Fine woven twill + ripstop grid
    h = (
        0.5
        + 0.18 * np.sin(2.0 * np.pi * x / 4.0) * np.cos(2.0 * np.pi * y / 4.0)
        + 0.10 * np.sin(2.0 * np.pi * (x + y) / 6.0)
    )
    rip_x = ((x % grid) < 1.5).astype(np.float32)
    rip_y = ((y % grid) < 1.5).astype(np.float32)
    h += 0.22 * np.maximum(rip_x, rip_y)
    dx = np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)
    dy = np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(h)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    rgba = np.zeros((size, size, 4), dtype=np.float32)
    rgba[..., 0] = 0.5 + 0.5 * nx * inv_len
    rgba[..., 1] = 0.5 + 0.5 * ny * inv_len
    rgba[..., 2] = 0.5 + 0.5 * nz * inv_len
    rgba[..., 3] = 1.0
    img = bpy.data.images.new(name, width=size, height=size, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    return img


def make_leather_normal_image(name="Tex_LeatherNormal", size=256):
    if name in bpy.data.images:
        return bpy.data.images[name]
    rng = np.random.default_rng(9401)
    # Multi-octave smooth grain
    base = rng.random((size // 4, size // 4)).astype(np.float32)
    base = np.repeat(np.repeat(base, 4, axis=0), 4, axis=1)
    fine = rng.random((size, size)).astype(np.float32)
    h = 0.72 * base + 0.28 * fine
    # Simple 3x3 box blur
    h = (
        h + np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1)
    ) * 0.2
    dx = np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)
    dy = np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)
    nx, ny, nz = -dx * 0.65, -dy * 0.65, np.ones_like(h)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    rgba = np.zeros((size, size, 4), dtype=np.float32)
    rgba[..., 0] = 0.5 + 0.5 * nx * inv
    rgba[..., 1] = 0.5 + 0.5 * ny * inv
    rgba[..., 2] = 0.5 + 0.5 * nz * inv
    rgba[..., 3] = 1.0
    img = bpy.data.images.new(name, width=size, height=size, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    return img


def make_cloud_patch_image(name="Tex_CloudEmblem", size=256):
    """Stylized gold Jiangnan cloud emblem on bamboo-teal shield for left shoulder."""
    if name in bpy.data.images:
        return bpy.data.images[name]
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    u = (xx / size) * 2.0 - 1.0
    v = (yy / size) * 2.0 - 1.0
    rgba = np.zeros((size, size, 4), dtype=np.float32)
    # Deep bamboo-teal shield fill
    rgba[..., 0] = 0.08
    rgba[..., 1] = 0.28
    rgba[..., 2] = 0.23
    rgba[..., 3] = 1.0
    # Gold border ring
    rad = np.sqrt(u * u + v * v)
    border = (rad > 0.78) & (rad < 0.93)
    # Stylized auspicious cloud swirls (3 overlapping circles + scroll tail)
    c1 = np.sqrt((u + 0.22) ** 2 + (v + 0.04) ** 2) < 0.26
    c2 = np.sqrt((u - 0.04) ** 2 + (v - 0.14) ** 2) < 0.30
    c3 = np.sqrt((u - 0.28) ** 2 + (v + 0.06) ** 2) < 0.22
    c_in1 = np.sqrt((u + 0.22) ** 2 + (v + 0.04) ** 2) < 0.14
    c_in2 = np.sqrt((u - 0.04) ** 2 + (v - 0.14) ** 2) < 0.17
    c_in3 = np.sqrt((u - 0.28) ** 2 + (v + 0.06) ** 2) < 0.11
    bar = (np.abs(v + 0.20) < 0.065) & (u > -0.46) & (u < 0.48)
    cloud = ((c1 | c2 | c3) & ~(c_in1 | c_in2 | c_in3)) | bar
    gold_mask = border | cloud
    rgba[gold_mask, 0] = 0.88
    rgba[gold_mask, 1] = 0.68
    rgba[gold_mask, 2] = 0.24
    img = bpy.data.images.new(name, width=size, height=size, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    return img


def make_pbr_mat(
    name,
    color,
    roughness=0.65,
    metallic=0.0,
    normal_img=None,
    normal_scale=0.32,
    tex_scale=8.0,
    alpha=1.0,
    emission=None,
    emission_strength=0.0,
    albedo_img=None,
):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if alpha < 0.999:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND" if hasattr(mat, "blend_method") else "OPAQUE"
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if albedo_img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = albedo_img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    if normal_img is not None:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (tex_scale, tex_scale, tex_scale)
        tex_n = nt.nodes.new("ShaderNodeTexImage")
        tex_n.image = normal_img
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = normal_scale
        nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], tex_n.inputs["Vector"])
        nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def create_material_palette():
    fab_n = make_fabric_normal_image("Tex_RipstopNormal", 256, 16, 0.35)
    knit_n = make_fabric_normal_image("Tex_ScarfKnitNormal", 256, 8, 0.45)
    lth_n = make_leather_normal_image("Tex_LeatherNormal", 256)
    cloud_img = make_cloud_patch_image("Tex_CloudEmblem", 256)
    return {
        "skin": make_pbr_mat("Shaoyu_Skin", (0.86, 0.62, 0.46), roughness=0.56),
        "hair": make_pbr_mat("Shaoyu_Hair", (0.025, 0.030, 0.042), roughness=0.46),
        "eyebrow": make_pbr_mat("Shaoyu_Eyebrow", (0.025, 0.028, 0.038), roughness=0.58),
        "eye": make_pbr_mat("Shaoyu_Eye", (0.06, 0.04, 0.03), roughness=0.14),
        "jacket": make_pbr_mat("Shaoyu_BambooJacket", (0.07, 0.25, 0.21), roughness=0.68, normal_img=fab_n, normal_scale=0.35, tex_scale=10.0),
        "jacket_trim": make_pbr_mat("Shaoyu_JacketTrim", (0.04, 0.15, 0.13), roughness=0.72, normal_img=fab_n, normal_scale=0.28, tex_scale=12.0),
        "vest": make_pbr_mat("Shaoyu_CharcoalRig", (0.085, 0.10, 0.12), roughness=0.64, normal_img=fab_n, normal_scale=0.42, tex_scale=14.0),
        "pouch": make_pbr_mat("Shaoyu_RigPouch", (0.11, 0.13, 0.155), roughness=0.60, normal_img=fab_n, normal_scale=0.38, tex_scale=16.0),
        "scarf": make_pbr_mat("Shaoyu_CrimsonScarf", (0.62, 0.11, 0.075), roughness=0.78, normal_img=knit_n, normal_scale=0.42, tex_scale=12.0),
        "wrap": make_pbr_mat("Shaoyu_ForearmWrap", (0.14, 0.16, 0.18), roughness=0.76, normal_img=knit_n, normal_scale=0.32, tex_scale=14.0),
        "glove": make_pbr_mat("Shaoyu_LeatherGlove", (0.13, 0.095, 0.072), roughness=0.52, normal_img=lth_n, normal_scale=0.42, tex_scale=10.0),
        "bronze": make_pbr_mat("Shaoyu_BronzeKnuckle", (0.64, 0.45, 0.19), roughness=0.28, metallic=0.84),
        "pants": make_pbr_mat("Shaoyu_CargoPants", (0.105, 0.125, 0.148), roughness=0.72, normal_img=fab_n, normal_scale=0.36, tex_scale=9.0),
        "kneepad": make_pbr_mat("Shaoyu_Kneepad", (0.055, 0.065, 0.078), roughness=0.48, metallic=0.12),
        "boot_leather": make_pbr_mat("Shaoyu_CombatBoot", (0.18, 0.115, 0.078), roughness=0.54, normal_img=lth_n, normal_scale=0.45, tex_scale=8.0),
        "boot_sole": make_pbr_mat("Shaoyu_BootSole", (0.045, 0.05, 0.055), roughness=0.82),
        "pack_main": make_pbr_mat("Shaoyu_PackMain", (0.12, 0.14, 0.155), roughness=0.68, normal_img=fab_n, normal_scale=0.40, tex_scale=10.0),
        "pack_olive": make_pbr_mat("Shaoyu_PackOlive", (0.16, 0.19, 0.13), roughness=0.72, normal_img=fab_n, normal_scale=0.36, tex_scale=10.0),
        "strap_tan": make_pbr_mat("Shaoyu_StrapTan", (0.34, 0.28, 0.17), roughness=0.74, normal_img=fab_n, normal_scale=0.30, tex_scale=14.0),
        "goggle_frame": make_pbr_mat("Shaoyu_GoggleFrame", (0.055, 0.065, 0.075), roughness=0.42, metallic=0.15),
        "goggle_lens": make_pbr_mat("Shaoyu_AmberLens", (0.92, 0.56, 0.11), roughness=0.10, metallic=0.22, alpha=0.68, emission=(0.85, 0.45, 0.05), emission_strength=0.18),
        "headset": make_pbr_mat("Shaoyu_Headset", (0.07, 0.08, 0.09), roughness=0.38, metallic=0.35),
        "radio_led": make_pbr_mat("Shaoyu_RadioLED", (0.15, 0.95, 0.45), roughness=0.2, emission=(0.15, 0.95, 0.45), emission_strength=2.2),
        "patch": make_pbr_mat("Shaoyu_CloudPatch", (1.0, 1.0, 1.0), roughness=0.65, albedo_img=cloud_img),
    }


# ---------------------------------------------------------------------------
# Mesh Welding, Smoothing & Custom Sculpting Helpers
# ---------------------------------------------------------------------------
def weld_and_smooth(obj, merge_dist=0.00035, smooth_iters=1, smooth_fac=0.18):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge_dist)
    if smooth_iters > 0:
        # Gently soften harsh Quaternius facets while keeping boundaries anchored
        interior = [v for v in bm.verts if not v.is_boundary]
        for _ in range(smooth_iters):
            bmesh.ops.smooth_vert(bm, verts=interior, factor=smooth_fac, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()
    me.update()


def add_box_mesh(bm, center, size, rot_euler=(0, 0, 0), mat_idx=0, bevel=0.0):
    m = Matrix.Translation(center) @ Euler(rot_euler, "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    verts = res["verts"]
    faces = list({f for v in verts for f in v.link_faces})
    if bevel > 0.0:
        edges = list({e for f in faces for e in f.edges})
        bev = bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=2, affect="EDGES", clamp_overlap=True)
        verts = bev.get("verts", verts)
        faces = list({f for v in verts for f in v.link_faces})
    for f in faces:
        f.material_index = mat_idx
        f.smooth = True
    return verts


def add_cyl_mesh(bm, center, radius1, radius2, depth, segs=14, rot_euler=(0, 0, 0), mat_idx=0):
    m = Matrix.Translation(center) @ Euler(rot_euler, "XYZ").to_matrix().to_4x4()
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=radius1, radius2=radius2, depth=depth, matrix=m)
    verts = res["verts"]
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_idx
        f.smooth = True
    return verts


def add_sphere_mesh(bm, center, scale, segs=14, rings=10, rot_euler=(0, 0, 0), mat_idx=0):
    m = Matrix.Translation(center) @ Euler(rot_euler, "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    res = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0, matrix=m)
    verts = res["verts"]
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_idx
        f.smooth = True
    return verts


def add_ribbon_strip(bm, points, widths, thicknesses, mat_idx=0, fixed_side=None):
    """Build a smoothly beveled organic ribbon/cloth strip along 3D centerline points."""
    rings = []
    n = len(points)
    for i in range(n):
        p = Vector(points[i])
        if i == 0:
            tang = (Vector(points[1]) - p).normalized()
        elif i == n - 1:
            tang = (p - Vector(points[i - 1])).normalized()
        else:
            tang = (Vector(points[i + 1]) - Vector(points[i - 1])).normalized()
        if fixed_side is not None:
            side = (Vector(fixed_side) - tang * Vector(fixed_side).dot(tang))
            side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
        else:
            up_ref = Vector((0, 0, 1)) if abs(tang.z) < 0.92 else Vector((0, 1, 0))
            side = tang.cross(up_ref).normalized()
        norm = side.cross(tang).normalized()
        w = widths[i] * 0.5
        t = thicknesses[i] * 0.5
        # 6-point rounded ribbon cross-section
        prof = [
            p - side * w,
            p - side * (w * 0.55) + norm * t,
            p + side * (w * 0.55) + norm * t,
            p + side * w,
            p + side * (w * 0.55) - norm * t,
            p - side * (w * 0.55) - norm * t,
        ]
        rings.append([bm.verts.new(pt) for pt in prof])
    for i in range(n - 1):
        r0, r1 = rings[i], rings[i + 1]
        for j in range(6):
            jn = (j + 1) % 6
            f = bm.faces.new((r0[j], r0[jn], r1[jn], r1[j]))
            f.material_index = mat_idx
            f.smooth = True
    # Cap ends
    f0 = bm.faces.new(list(reversed(rings[0])))
    f0.material_index = mat_idx
    f0.smooth = True
    f1 = bm.faces.new(rings[-1])
    f1.material_index = mat_idx
    f1.smooth = True
    return rings


def make_weighted_object(name, bm, mats, arm, bone_weights_fn):
    """Create a mesh object from bmesh, assign materials & skin weights via bone_weights_fn(v.co) -> {bone: w}."""
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    vgroups = {}
    for v in me.vertices:
        wdict = bone_weights_fn(v.co)
        total = sum(wdict.values())
        if total <= 1e-6:
            continue
        for bname, w in wdict.items():
            if w <= 1e-5:
                continue
            if bname not in vgroups:
                vgroups[bname] = obj.vertex_groups.new(name=bname)
            vgroups[bname].add([v.index], w / total, "REPLACE")
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    return obj


# ---------------------------------------------------------------------------
# Step 1: Import & Normalize Quaternius Swat (Body/Legs/Feet) + Casual (Head)
# ---------------------------------------------------------------------------
def build_normalized_shaoyu_base():
    clear_scene()
    # Import Swat
    bpy.ops.import_scene.gltf(filepath=os.path.join(CC0_DIR, "Swat.glb"))
    remove_icospheres(list(bpy.data.objects))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    arm.name = "ShaoyuArmature"
    swat_body = bpy.data.objects["Swat_Body"]
    swat_legs = bpy.data.objects["Swat_Legs"]
    swat_feet = bpy.data.objects["Swat_Feet"]
    if "Swat_Head" in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects["Swat_Head"], do_unlink=True)

    # Import Casual strictly for clean-shaven teenage boy head/face/hair!
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(CC0_DIR, "Casual.glb"))
    casual_objs = remove_icospheres([o for o in bpy.data.objects if o not in before])
    casual_head = next(o for o in casual_objs if o.type == "MESH" and "Head" in o.name)
    casual_head.name = "Casual_Head_Src"
    # Reparent casual_head onto ShaoyuArmature before deleting casual's duplicate armature
    casual_head.parent = None
    for m in list(casual_head.modifiers):
        if m.type == "ARMATURE":
            m.object = arm
    for o in casual_objs:
        if o != casual_head and o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    # Re-attach casual_head to arm with matching local transform
    casual_head.parent = arm
    casual_head.matrix_parent_inverse = Matrix.Identity(4)
    casual_head.matrix_local = swat_body.matrix_local.copy()

    bpy.context.view_layer.update()
    base_meshes = [swat_body, swat_legs, swat_feet, casual_head]

    # Measure world height & center
    all_pts = [o.matrix_world @ v.co for o in base_meshes for v in o.data.vertices]
    min_z = min(p.z for p in all_pts)
    max_z = max(p.z for p in all_pts)
    # Center Y around hip bone world Y so character pivots around natural spine/hips axis
    hips_world = arm.matrix_world @ arm.data.bones["Hips"].head_local
    scale_k = TARGET_HEIGHT / (max_z - min_z)
    m_fix = Matrix.Diagonal((scale_k, scale_k, scale_k, 1.0)) @ Matrix.Translation((-hips_world.x, -hips_world.y, -min_z))

    # Bake transform into every mesh cleanly
    for o in base_meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
        xf = m_fix @ mw
        for v in o.data.vertices:
            v.co = xf @ v.co
        o.data.update()

    # Bake transform into Armature EditBones cleanly
    arm_mw = arm.matrix_world.copy()
    arm_xf = m_fix @ arm_mw
    arm.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    ebones = arm.data.edit_bones
    saved = {}
    for eb in ebones:
        saved[eb.name] = (arm_xf @ eb.head, arm_xf @ eb.tail, eb.roll)
    for eb in ebones:
        h, t, roll = saved[eb.name]
        eb.head = h
        eb.tail = t
        if (eb.tail - eb.head).length < 0.015:
            d = (eb.tail - eb.head)
            if d.length < 1e-6:
                d = Vector((0, 0, 1))
            eb.tail = eb.head + d.normalized() * 0.035
        eb.roll = roll

    # Snap main limb & spine bone tails cleanly to their direct child heads (preserving exact bone roll/axes!)
    # This gives BOTH Blender IK and Godot 4.7.2 native TwoBoneIK3D exact millimeter segment lengths!
    chain_pairs = [
        ("Hips", "Abdomen"), ("Abdomen", "Torso"), ("Torso", "Chest"), ("Chest", "Neck"), ("Neck", "Head"),
        ("Shoulder.L", "UpperArm.L"), ("UpperArm.L", "LowerArm.L"), ("LowerArm.L", "Hand.L"),
        ("Shoulder.R", "UpperArm.R"), ("UpperArm.R", "LowerArm.R"), ("LowerArm.R", "Hand.R"),
        ("UpperLeg.L", "LowerLeg.L"), ("LowerLeg.L", "Foot.L"),
        ("UpperLeg.R", "LowerLeg.R"), ("LowerLeg.R", "Foot.R"),
    ]
    for p_name, c_name in chain_pairs:
        if p_name in ebones and c_name in ebones:
            old_dir = (ebones[p_name].tail - ebones[p_name].head).normalized()
            new_vec = ebones[c_name].head - ebones[p_name].head
            if new_vec.length > 0.02 and old_dir.dot(new_vec.normalized()) > 0.75:
                ebones[p_name].tail = ebones[c_name].head.copy()

    # Add 4 Dynamic Scarf Spring Bones (Scarf_01 -> Scarf_04) parented to Chest
    chest_eb = ebones["Chest"]
    scarf_pts = [
        Vector((0.068, 0.082, 1.385)),
        Vector((0.115, 0.155, 1.295)),
        Vector((0.158, 0.210, 1.185)),
        Vector((0.195, 0.255, 1.065)),
        Vector((0.228, 0.292, 0.945)),
    ]
    prev = chest_eb
    for idx in range(4):
        sb = ebones.new(f"Scarf_0{idx + 1}")
        sb.head = scarf_pts[idx]
        sb.tail = scarf_pts[idx + 1]
        sb.parent = prev
        sb.use_connect = (idx > 0)
        prev = sb

    # Add Weapon_R socket bone (parented to Hand.R) & Weapon_Back holster bone (parented to Chest)
    hand_r = ebones["Hand.R"]
    wb_r = ebones.new("Weapon_R")
    wb_r.head = hand_r.head + Vector((-0.042, -0.008, -0.014))
    # Point along -Y (forward in Blender, -Z in Godot) so identity-mounted rifle aims straight forward along bone +Y?
    # Wait: in glTF/Godot, bone +Y points from head->tail. Let's point tail toward -Y (forward) with roll aligned upright!
    wb_r.tail = wb_r.head + Vector((0.0, -0.14, 0.0))
    wb_r.parent = hand_r
    wb_r.use_connect = False
    wb_r.align_roll(Vector((0.0, 0.0, 1.0)))

    wb_b = ebones.new("Weapon_Back")
    wb_b.head = Vector((0.045, 0.168, 1.245))
    wb_b.tail = Vector((-0.075, 0.172, 1.085))
    wb_b.parent = chest_eb
    wb_b.use_connect = False
    wb_b.align_roll(Vector((0.0, 1.0, 0.0)))

    bpy.ops.object.mode_set(mode="OBJECT")

    # Re-parent meshes cleanly with Armature modifier
    for o in base_meshes:
        o.parent = arm
        o.matrix_parent_inverse = Matrix.Identity(4)
        for m in list(o.modifiers):
            if m.type == "ARMATURE":
                m.object = arm

    bpy.context.view_layer.update()
    return arm, swat_body, swat_legs, swat_feet, casual_head


# ---------------------------------------------------------------------------
# Step 2: Recolor, Smooth-Shade & Sculpt Plan B Shaoyu Hero Outfit & Gear
# ---------------------------------------------------------------------------
def customize_shaoyu_appearance(arm, swat_body, swat_legs, swat_feet, casual_head, pal):
    # 1. Weld & smooth base meshes (removes harsh Quaternius flat-shaded facets!)
    weld_and_smooth(swat_body, merge_dist=0.00035, smooth_iters=1, smooth_fac=0.16)
    weld_and_smooth(swat_legs, merge_dist=0.00035, smooth_iters=1, smooth_fac=0.16)
    weld_and_smooth(swat_feet, merge_dist=0.00035, smooth_iters=1, smooth_fac=0.12)
    weld_and_smooth(casual_head, merge_dist=0.00035, smooth_iters=1, smooth_fac=0.14)

    # 2. Re-assign materials on Swat_Body intelligently (SAVE orig material_index BEFORE clearing!)
    # Original Swat_Body mats: ['Swat_Black', 'Skin', 'Swat']
    orig_body_ids = [p.material_index for p in swat_body.data.polygons]
    orig_names = [m.name if m else "" for m in swat_body.data.materials]
    idx_black = next((i for i, n in enumerate(orig_names) if "Black" in n), 0)
    idx_skin = next((i for i, n in enumerate(orig_names) if "Skin" in n), 1)
    idx_swat = next((i for i, n in enumerate(orig_names) if n == "Swat"), 2)

    sb_mats = [pal["vest"], pal["skin"], pal["jacket"], pal["glove"], pal["wrap"], pal["jacket_trim"]]
    swat_body.data.materials.clear()
    for m in sb_mats:
        swat_body.data.materials.append(m)

    for poly, orig_i in zip(swat_body.data.polygons, orig_body_ids):
        c = poly.center
        ax = abs(c.x)
        if orig_i == idx_skin:
            poly.material_index = 1  # bare fingers/hands/neck
        elif orig_i == idx_black:
            if ax > 0.44:
                poly.material_index = 3  # dark leather fingerless tactical glove!
            elif c.z < 1.045:
                poly.material_index = 5  # dark-bamboo ribbed waist hem
            elif c.y > -0.025:
                poly.material_index = 2  # keep sides & back bamboo-teal (clean front chest rig plate!)
            else:
                poly.material_index = 0  # matte charcoal front MOLLE chest rig vest!
        else:
            # Jacket & Sleeves (orig Swat): rolled-up sleeves exposing forearm skin + charcoal athletic wrist wrap!
            if ax > 0.415 and ax < 0.505:
                poly.material_index = 4  # charcoal forearm athletic wrap
            elif ax > 0.350 and ax <= 0.415:
                poly.material_index = 1  # bare warm forearm skin between rolled sleeve & wrap!
            elif c.z < 1.035:
                poly.material_index = 5  # darker ribbed jacket waist hem
            else:
                poly.material_index = 2  # bamboo-teal tactical windbreaker jacket!

    # 3. Re-assign materials on Swat_Legs (SAVE orig indices BEFORE clearing!)
    orig_leg_ids = [p.material_index for p in swat_legs.data.polygons]
    leg_orig = [m.name if m else "" for m in swat_legs.data.materials]
    l_black = next((i for i, n in enumerate(leg_orig) if "Black" in n), 0)
    swat_legs.data.materials.clear()
    swat_legs.data.materials.append(pal["kneepad"])
    swat_legs.data.materials.append(pal["pants"])
    for poly, orig_i in zip(swat_legs.data.polygons, orig_leg_ids):
        poly.material_index = 0 if orig_i == l_black else 1

    # 4. Re-assign materials on Swat_Feet (dark-brown trail leather combat boots + dark rubber lug sole)
    swat_feet.data.materials.clear()
    swat_feet.data.materials.append(pal["boot_leather"])
    swat_feet.data.materials.append(pal["boot_sole"])
    for poly in swat_feet.data.polygons:
        poly.material_index = 1 if (poly.center.z < 0.042 or poly.center.y < -0.175) else 0

    # 5. Re-assign materials on Casual_Head (SAVE orig indices BEFORE clearing!)
    orig_head_ids = [p.material_index for p in casual_head.data.polygons]
    head_orig = [m.name if m else "" for m in casual_head.data.materials]
    h_map = {}
    for i, n in enumerate(head_orig):
        if "Skin" in n:
            h_map[i] = 0
        elif "Eyebrow" in n:
            h_map[i] = 1
        elif "Eye" in n:
            h_map[i] = 2
        else:
            h_map[i] = 3
    casual_head.data.materials.clear()
    for m in [pal["skin"], pal["eyebrow"], pal["eye"], pal["hair"]]:
        casual_head.data.materials.append(m)
    for poly, orig_i in zip(casual_head.data.polygons, orig_head_ids):
        poly.material_index = h_map.get(orig_i, 0)

    # Measure exact eye/head coordinates from Casual_Head vertices for pinpoint goggles & headset fit
    head_pts = [v.co for v in casual_head.data.vertices]
    head_z_min = min(p.z for p in head_pts)
    head_z_max = max(p.z for p in head_pts)
    head_y_min = min(p.y for p in head_pts)
    head_y_max = max(p.y for p in head_pts)
    # Find eye polygon center directly!
    eye_polys = [p.center for p in casual_head.data.polygons if p.material_index == 2]
    if eye_polys:
        eye_z = sum(p.z for p in eye_polys) / len(eye_polys)
        eye_y = min(p.y for p in eye_polys)
    else:
        eye_z = 1.615
        eye_y = -0.105
    print(f"HEAD_FIT: z=[{head_z_min:.3f},{head_z_max:.3f}] y=[{head_y_min:.3f},{head_y_max:.3f}] eye_z={eye_z:.3f} eye_y={eye_y:.3f}")

    # -----------------------------------------------------------------------
    # Custom Sculpted Head Gear: Extra Layered Spiky Hair + Plan B Amber Goggles + Headset
    # -----------------------------------------------------------------------
    bm_h = bmesh.new()
    h_mats = [pal["hair"], pal["goggle_frame"], pal["goggle_lens"], pal["headset"], pal["radio_led"]]

    # Dynamic tapered windswept raven-black hair locks (sleek anime/stylized locks, zero round spheres!)
    hair_locks = [
        # Swept forehead bangs framing right above the amber goggles
        ([(0.010, -0.045, head_z_max - 0.015), (-0.010, -0.095, head_z_max - 0.045), (-0.028, -0.118, head_z_max - 0.088)], [0.044, 0.030, 0.006], [0.020, 0.014, 0.005]),
        ([(-0.025, -0.040, head_z_max - 0.018), (-0.056, -0.082, head_z_max - 0.050), (-0.072, -0.105, head_z_max - 0.095)], [0.038, 0.026, 0.006], [0.018, 0.012, 0.005]),
        ([(0.035, -0.040, head_z_max - 0.018), (0.064, -0.078, head_z_max - 0.048), (0.080, -0.100, head_z_max - 0.092)], [0.038, 0.026, 0.006], [0.018, 0.012, 0.005]),
        # Windswept top crown spikes sweeping slightly back-right
        ([(0.000, -0.010, head_z_max - 0.018), (0.015, 0.025, head_z_max + 0.018), (0.030, 0.078, head_z_max + 0.024)], [0.052, 0.036, 0.008], [0.024, 0.016, 0.006]),
        ([(-0.042, -0.005, head_z_max - 0.022), (-0.064, 0.032, head_z_max + 0.008), (-0.082, 0.075, head_z_max + 0.004)], [0.042, 0.030, 0.007], [0.020, 0.014, 0.005]),
        ([(0.045, -0.005, head_z_max - 0.022), (0.068, 0.030, head_z_max + 0.006), (0.085, 0.072, head_z_max - 0.002)], [0.042, 0.030, 0.007], [0.020, 0.014, 0.005]),
        # Layered back & nape tufts for sleek, full 3P back haircut!
        ([(0.000, 0.055, head_z_max - 0.045), (0.005, 0.118, head_z_max - 0.085), (0.006, 0.125, head_z_max - 0.165)], [0.068, 0.056, 0.018], [0.024, 0.018, 0.008]),
        ([(-0.048, 0.048, head_z_max - 0.060), (-0.068, 0.102, head_z_max - 0.115), (-0.062, 0.108, head_z_max - 0.185)], [0.056, 0.046, 0.014], [0.022, 0.016, 0.007]),
        ([(0.048, 0.048, head_z_max - 0.060), (0.068, 0.102, head_z_max - 0.115), (0.062, 0.108, head_z_max - 0.185)], [0.056, 0.046, 0.014], [0.022, 0.016, 0.007]),
        ([(0.000, 0.072, head_z_max - 0.115), (0.000, 0.102, head_z_max - 0.175), (0.000, 0.095, head_z_max - 0.228)], [0.092, 0.078, 0.024], [0.022, 0.016, 0.008]),
    ]
    for pts, ws, ts in hair_locks:
        add_ribbon_strip(bm_h, pts, ws, ts, mat_idx=0)

    # Plan B Translucent Amber Tactical Goggles WORN OVER EYES!
    gz = eye_z + 0.002
    gy = eye_y - 0.016
    # Curved goggle frame (wraparound left/right lens housings + brow bridge + nose arch)
    for side in (-1.0, 1.0):
        # Outer rubber housing rim
        add_box_mesh(bm_h, (side * 0.035, gy + 0.008, gz), (0.058, 0.028, 0.044), (0.0, 0.0, side * 0.19), mat_idx=1, bevel=0.006)
        # Translucent amber lens recessed flush at front
        add_box_mesh(bm_h, (side * 0.035, gy - 0.004, gz), (0.050, 0.010, 0.035), (0.0, 0.0, side * 0.19), mat_idx=2, bevel=0.003)
        # Side temple hinge
        add_box_mesh(bm_h, (side * 0.072, gy + 0.024, gz), (0.022, 0.020, 0.028), (0.0, 0.0, side * 0.55), mat_idx=1, bevel=0.003)
    # Center brow bridge
    add_box_mesh(bm_h, (0.0, gy + 0.002, gz + 0.012), (0.028, 0.022, 0.014), (0, 0, 0), mat_idx=1, bevel=0.003)
    # Elastic dark headstrap wrapping smoothly around the back of the head
    strap_pts = []
    for k in range(13):
        ang = math.radians(-165 + k * (330.0 / 12.0))
        rx = 0.092 * math.sin(ang)
        ry = 0.010 + 0.098 * math.cos(ang)
        if ry > gy + 0.015:
            strap_pts.append((rx, ry, gz + 0.004))
    if len(strap_pts) >= 3:
        add_ribbon_strip(bm_h, strap_pts, [0.022] * len(strap_pts), [0.007] * len(strap_pts), mat_idx=1)

    # Single-Ear Tactical Comms Headset (Left ear = +X side in Blender!)
    ear_x = 0.095
    ear_y = 0.004
    ear_z = eye_z - 0.014
    add_cyl_mesh(bm_h, (ear_x, ear_y, ear_z), 0.030, 0.026, 0.024, segs=14, rot_euler=(0, math.pi * 0.5, 0), mat_idx=3)
    add_box_mesh(bm_h, (ear_x + 0.010, ear_y - 0.002, ear_z), (0.012, 0.026, 0.036), (0, 0, 0), mat_idx=3, bevel=0.003)
    # Thin overhead band arcing over top of head
    hb_pts = [
        (ear_x, ear_y, ear_z + 0.022),
        (0.088, 0.008, head_z_max - 0.045),
        (0.042, 0.010, head_z_max - 0.002),
        (-0.042, 0.010, head_z_max - 0.002),
        (-0.088, 0.008, head_z_max - 0.055),
    ]
    add_ribbon_strip(bm_h, hb_pts, [0.014] * len(hb_pts), [0.006] * len(hb_pts), mat_idx=3)
    # Curved boom mic reaching to left cheek corner
    mic_pts = [
        (ear_x + 0.005, ear_y - 0.015, ear_z - 0.016),
        (0.082, -0.058, ear_z - 0.036),
        (0.052, -0.096, ear_z - 0.048),
        (0.026, -0.108, ear_z - 0.050),
    ]
    add_ribbon_strip(bm_h, mic_pts, [0.006, 0.005, 0.005, 0.011], [0.006, 0.005, 0.005, 0.011], mat_idx=3)
    # Tiny green comms LED
    add_sphere_mesh(bm_h, (ear_x + 0.015, ear_y - 0.008, ear_z + 0.008), (0.004, 0.004, 0.004), segs=8, rings=6, mat_idx=4)

    head_gear_obj = make_weighted_object("Shaoyu_HeadGear", bm_h, h_mats, arm, lambda _p: {"Head": 1.0})

    # -----------------------------------------------------------------------
    # Custom Sculpted Tactical Chest Rig + Rolled Cuffs + Bronze Knuckles + Cloud Patch + Scarf
    # -----------------------------------------------------------------------
    bm_u = bmesh.new()
    u_mats = [pal["vest"], pal["pouch"], pal["strap_tan"], pal["bronze"], pal["radio_led"], pal["jacket"], pal["wrap"], pal["patch"], pal["scarf"], pal["jacket_trim"]]

    # 3 Beveled MOLLE Rifle Mag Pouches on front chest (Blender -Y is front!)
    for mx in (-0.064, 0.0, 0.064):
        add_box_mesh(bm_u, (mx, -0.145, 1.155), (0.052, 0.042, 0.118), (0.04, 0, 0), mat_idx=1, bevel=0.006)
        # Retaining flap + bungee tab
        add_box_mesh(bm_u, (mx, -0.162, 1.198), (0.046, 0.014, 0.032), (0.04, 0, 0), mat_idx=0, bevel=0.003)
        add_box_mesh(bm_u, (mx, -0.168, 1.158), (0.016, 0.010, 0.056), (0.04, 0, 0), mat_idx=2, bevel=0.002)

    # Upper MOLLE chest panel + PALS webbing bars
    add_box_mesh(bm_u, (0.0, -0.136, 1.268), (0.195, 0.026, 0.098), (0.05, 0, 0), mat_idx=0, bevel=0.005)
    for wz in (1.240, 1.268, 1.296):
        add_box_mesh(bm_u, (0.0, -0.150, wz), (0.175, 0.008, 0.011), (0.05, 0, 0), mat_idx=1, bevel=0.001)

    # Compact Tactical Chest Radio (upper right chest, -X is right side in Blender!)
    add_box_mesh(bm_u, (-0.088, -0.148, 1.280), (0.042, 0.032, 0.084), (0.05, 0, 0.08), mat_idx=0, bevel=0.004)
    add_box_mesh(bm_u, (-0.088, -0.165, 1.296), (0.026, 0.005, 0.020), (0.05, 0, 0.08), mat_idx=4, bevel=0.001)
    add_cyl_mesh(bm_u, (-0.098, -0.148, 1.368), 0.0045, 0.003, 0.105, segs=8, mat_idx=0)

    # Padded chest-rig shoulder straps & clean horizontal rib cummerbund side straps
    for sx in (-0.095, 0.095):
        add_box_mesh(bm_u, (sx, -0.098, 1.368), (0.046, 0.032, 0.112), (0.42, 0, 0), mat_idx=0, bevel=0.004)
        add_box_mesh(bm_u, (sx, -0.132, 1.318), (0.036, 0.016, 0.026), (0.12, 0, 0), mat_idx=2, bevel=0.002)
    for sx in (-0.156, 0.156):
        add_box_mesh(bm_u, (sx, 0.010, 1.150), (0.018, 0.185, 0.056), (0, 0, 0), mat_idx=0, bevel=0.004)
        add_box_mesh(bm_u, (sx, 0.010, 1.150), (0.022, 0.052, 0.026), (0, 0, 0), mat_idx=2, bevel=0.002)

    # Jacket Center Zipper Placket & Waist Belt Buckle
    add_box_mesh(bm_u, (0.0, -0.126, 1.035), (0.016, 0.018, 0.125), (0, 0, 0), mat_idx=9, bevel=0.002)
    add_box_mesh(bm_u, (0.0, -0.132, 0.992), (0.054, 0.024, 0.042), (0, 0, 0), mat_idx=3, bevel=0.004)

    # Sculpted Rolled Sleeve Cuffs + Forearm Athletic Wrap Rings + Bronze Knuckle Guards!
    for sx in (-1.0, 1.0):
        # Rolled bamboo-teal sleeve cuff near mid-forearm
        add_cyl_mesh(bm_u, (sx * 0.345, -0.006, 1.352), 0.054, 0.056, 0.048, segs=14, rot_euler=(0, math.pi * 0.5, 0), mat_idx=5)
        # Layered charcoal athletic wrist wrap bands
        for rx in (0.435, 0.462, 0.486):
            add_cyl_mesh(bm_u, (sx * rx, -0.012, 1.352), 0.044, 0.043, 0.022, segs=12, rot_euler=(0, math.pi * 0.5, 0), mat_idx=6)
        # 4 Sculpted Metallic-Bronze Knuckle Domes across the back of the fingerless glove!
        for ky_off in (-0.026, -0.009, 0.009, 0.026):
            add_sphere_mesh(bm_u, (sx * 0.592, -0.024 + ky_off, 1.374), (0.013, 0.0095, 0.011), segs=10, rings=7, mat_idx=3)
        add_box_mesh(bm_u, (sx * 0.590, -0.024, 1.370), (0.024, 0.068, 0.010), (0, 0, 0), mat_idx=3, bevel=0.003)

    # Left Shoulder Gold Cloud-Emblem Vanguard Patch (+X is left arm!)
    p_verts = add_box_mesh(bm_u, (0.242, -0.004, 1.366), (0.014, 0.066, 0.066), (0, 0.20, 0), mat_idx=7, bevel=0.003)
    uv_layer = bm_u.loops.layers.uv.verify()
    for f in {f for v in p_verts for f in v.link_faces}:
        for loop in f.loops:
            co = loop.vert.co
            u_coord = 0.5 + (co.y - (-0.004)) / 0.072
            v_coord = 0.5 + (co.z - 1.366) / 0.072
            loop[uv_layer].uv = (max(0.0, min(1.0, u_coord)), max(0.0, min(1.0, v_coord)))

    # Sculpted Cinnabar-Red Woven Ranger Scarf Collar Wrap (organic 2-tier plush ring around neck!)
    collar_pts_1 = []
    collar_pts_2 = []
    for k in range(17):
        ang = math.radians(k * (360.0 / 16.0))
        rx1 = 0.098 * math.sin(ang)
        ry1 = 0.005 + 0.104 * math.cos(ang)
        rz1 = 1.425 + 0.012 * math.cos(ang * 2.0) - 0.016 * max(0.0, -math.cos(ang))
        collar_pts_1.append((rx1, ry1, rz1))
        rx2 = 0.088 * math.sin(ang)
        ry2 = 0.004 + 0.094 * math.cos(ang)
        rz2 = 1.468 + 0.008 * math.sin(ang * 2.0) - 0.010 * max(0.0, -math.cos(ang))
        collar_pts_2.append((rx2, ry2, rz2))
    add_ribbon_strip(bm_u, collar_pts_1, [0.056] * len(collar_pts_1), [0.036] * len(collar_pts_1), mat_idx=8)
    add_ribbon_strip(bm_u, collar_pts_2, [0.048] * len(collar_pts_2), [0.032] * len(collar_pts_2), mat_idx=8)

    def upper_gear_weights(co: Vector):
        ax = abs(co.x)
        if ax > 0.515:
            return {"Hand.L" if co.x > 0 else "Hand.R": 1.0}
        if ax > 0.305:
            return {"LowerArm.L" if co.x > 0 else "LowerArm.R": 1.0}
        if ax > 0.190:
            return {"UpperArm.L" if co.x > 0 else "UpperArm.R": 1.0}
        if co.z > 1.24:
            return {"Chest": 1.0}
        if co.z > 1.06:
            return {"Torso": 0.72, "Chest": 0.28}
        return {"Abdomen": 0.75, "Hips": 0.25}

    upper_gear_obj = make_weighted_object("Shaoyu_TacticalGear", bm_u, u_mats, arm, upper_gear_weights)

    # -----------------------------------------------------------------------
    # Dynamic 4-Bone Flowing Crimson Scarf Tail (SpringBoneSimulator3D target!)
    # -----------------------------------------------------------------------
    bm_s = bmesh.new()
    tail_pts = [
        (0.050, 0.072, 1.430),
        (0.082, 0.118, 1.372),
        (0.115, 0.160, 1.300),
        (0.145, 0.194, 1.220),
        (0.172, 0.222, 1.138),
        (0.194, 0.246, 1.058),
        (0.212, 0.268, 0.985),
        (0.228, 0.288, 0.935),
    ]
    tail_w = [0.084, 0.094, 0.102, 0.108, 0.108, 0.098, 0.078, 0.038]
    tail_t = [0.015, 0.013, 0.012, 0.011, 0.011, 0.010, 0.009, 0.007]
    add_ribbon_strip(bm_s, tail_pts, tail_w, tail_t, mat_idx=0, fixed_side=(0.82, -0.57, 0.0))

    def scarf_tail_weights(co: Vector):
        # Smooth interpolation along Z from Chest(1.41) -> Scarf_01(1.34) -> Scarf_02(1.24) -> Scarf_03(1.12) -> Scarf_04(0.95)
        t = max(0.0, min(1.0, (1.41 - co.z) / (1.41 - 0.94)))
        if t < 0.20:
            a = t / 0.20
            return {"Chest": 1.0 - a, "Scarf_01": a}
        elif t < 0.45:
            a = (t - 0.20) / 0.25
            return {"Scarf_01": 1.0 - a, "Scarf_02": a}
        elif t < 0.72:
            a = (t - 0.45) / 0.27
            return {"Scarf_02": 1.0 - a, "Scarf_03": a}
        else:
            a = (t - 0.72) / 0.28
            return {"Scarf_03": 1.0 - a, "Scarf_04": a}

    scarf_tail_obj = make_weighted_object("Shaoyu_ScarfTail", bm_s, [pal["scarf"]], arm, scarf_tail_weights)

    # -----------------------------------------------------------------------
    # Sleek Compact Ergonomic Mountain-Ranger Daypack (NO bulky green brick!)
    # -----------------------------------------------------------------------
    bm_p = bmesh.new()
    p_mats = [pal["pack_main"], pal["pack_olive"], pal["strap_tan"], pal["bronze"]]
    # Slim curved main shell sitting snugly on back (+Y is back in Blender!)
    add_box_mesh(bm_p, (0.0, 0.140, 1.235), (0.215, 0.092, 0.305), (-0.06, 0, 0), mat_idx=0, bevel=0.024)
    # Tapered top lid + carry handle
    add_box_mesh(bm_p, (0.0, 0.132, 1.375), (0.185, 0.078, 0.072), (-0.18, 0, 0), mat_idx=1, bevel=0.018)
    add_cyl_mesh(bm_p, (0.0, 0.125, 1.418), 0.008, 0.008, 0.080, segs=8, rot_euler=(0, math.pi * 0.5, 0), mat_idx=2)
    # Olive contoured front zip pocket
    add_box_mesh(bm_p, (0.0, 0.186, 1.195), (0.165, 0.036, 0.185), (-0.05, 0, 0), mat_idx=1, bevel=0.014)
    # X-shaped tan/khaki compression straps + center brass buckle
    add_box_mesh(bm_p, (0.0, 0.205, 1.225), (0.022, 0.010, 0.265), (-0.05, 0.42, 0), mat_idx=2, bevel=0.002)
    add_box_mesh(bm_p, (0.0, 0.205, 1.225), (0.022, 0.010, 0.265), (-0.05, -0.42, 0), mat_idx=2, bevel=0.002)
    add_box_mesh(bm_p, (0.0, 0.210, 1.225), (0.032, 0.014, 0.036), (-0.05, 0, 0), mat_idx=3, bevel=0.003)
    # Side mesh bottle pocket (right side -X) & diagonal sling buckle
    add_cyl_mesh(bm_p, (-0.118, 0.145, 1.155), 0.028, 0.026, 0.125, segs=12, mat_idx=0)
    add_box_mesh(bm_p, (0.088, 0.155, 1.345), (0.026, 0.020, 0.032), (0, 0, 0.3), mat_idx=3, bevel=0.003)

    backpack_obj = make_weighted_object("Shaoyu_Backpack", bm_p, p_mats, arm, lambda p: {"Chest": 0.72, "Torso": 0.28} if p.z > 1.22 else {"Torso": 0.80, "Chest": 0.20})

    # Rename core meshes cleanly for Godot 1P/3P visibility control:
    # 1P hides Head + UpperBody + Backpack; ALWAYS keeps LowerBody (legs + boots)!
    casual_head.name = "Shaoyu_Head"
    swat_body.name = "Shaoyu_UpperBody"
    swat_legs.name = "Shaoyu_LowerLegs"
    swat_feet.name = "Shaoyu_LowerBoots"

    return [casual_head, head_gear_obj, swat_body, upper_gear_obj, scarf_tail_obj, backpack_obj, swat_legs, swat_feet]


# ---------------------------------------------------------------------------
# Step 3: Exact World-Space Quaternion Animation Retargeter (UAL + KayKit)
# ---------------------------------------------------------------------------
UAL_BONE_MAP = {
    "Hips": "DEF-hips",
    "Abdomen": "DEF-spine.001",
    "Torso": "DEF-spine.002",
    "Chest": "DEF-spine.003",
    "Neck": "DEF-neck",
    "Head": "DEF-head",
    "Shoulder.L": "DEF-shoulder.L",
    "UpperArm.L": "DEF-upper_arm.L",
    "LowerArm.L": "DEF-forearm.L",
    "Hand.L": "DEF-hand.L",
    "Index2.L": "DEF-f_index.01.L",
    "Index3.L": "DEF-f_index.02.L",
    "Index4.L": "DEF-f_index.03.L",
    "Middle2.L": "DEF-f_middle.01.L",
    "Middle3.L": "DEF-f_middle.02.L",
    "Middle4.L": "DEF-f_middle.03.L",
    "Ring2.L": "DEF-f_ring.01.L",
    "Ring3.L": "DEF-f_ring.02.L",
    "Ring4.L": "DEF-f_ring.03.L",
    "Pinky2.L": "DEF-f_pinky.01.L",
    "Pinky3.L": "DEF-f_pinky.02.L",
    "Pinky4.L": "DEF-f_pinky.03.L",
    "Thumb2.L": "DEF-thumb.02.L",
    "Thumb3.L": "DEF-thumb.03.L",
    "Shoulder.R": "DEF-shoulder.R",
    "UpperArm.R": "DEF-upper_arm.R",
    "LowerArm.R": "DEF-forearm.R",
    "Hand.R": "DEF-hand.R",
    "Index2.R": "DEF-f_index.01.R",
    "Index3.R": "DEF-f_index.02.R",
    "Index4.R": "DEF-f_index.03.R",
    "Middle2.R": "DEF-f_middle.01.R",
    "Middle3.R": "DEF-f_middle.02.R",
    "Middle4.R": "DEF-f_middle.03.R",
    "Ring2.R": "DEF-f_ring.01.R",
    "Ring3.R": "DEF-f_ring.02.R",
    "Ring4.R": "DEF-f_ring.03.R",
    "Pinky2.R": "DEF-f_pinky.01.R",
    "Pinky3.R": "DEF-f_pinky.02.R",
    "Pinky4.R": "DEF-f_pinky.03.R",
    "Thumb2.R": "DEF-thumb.02.R",
    "Thumb3.R": "DEF-thumb.03.R",
    "UpperLeg.L": "DEF-thigh.L",
    "LowerLeg.L": "DEF-shin.L",
    "Foot.L": "DEF-foot.L",
    "UpperLeg.R": "DEF-thigh.R",
    "LowerLeg.R": "DEF-shin.R",
    "Foot.R": "DEF-foot.R",
}

KAYKIT_BONE_MAP = {
    "Hips": "hips",
    "Abdomen": "spine",
    "Chest": "chest",
    "Head": "head",
    "UpperArm.L": "upperarm.l",
    "LowerArm.L": "lowerarm.l",
    "Hand.L": "hand.l",
    "UpperArm.R": "upperarm.r",
    "LowerArm.R": "lowerarm.r",
    "Hand.R": "hand.r",
    "UpperLeg.L": "upperleg.l",
    "LowerLeg.L": "lowerleg.l",
    "Foot.L": "foot.l",
    "UpperLeg.R": "upperleg.r",
    "LowerLeg.R": "lowerleg.r",
    "Foot.R": "foot.r",
}


def topological_bone_order(arm):
    order = []
    visited = set()

    def visit(b):
        if b.name in visited:
            return
        if b.parent:
            visit(b.parent)
        visited.add(b.name)
        order.append(b.name)

    for b in arm.data.bones:
        visit(b)
    return order


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = Vector((0, 0, 0))
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.scale = Vector((1, 1, 1))


def retarget_actions_from_file(dst_arm, src_path, bone_map, clip_renames, step=1):
    """Exact world-space rest-pose quaternion retargeter (zero roll/twist drift!)."""
    before_objs = set(bpy.data.objects)
    before_acts = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=src_path)
    src_objs = [o for o in bpy.data.objects if o not in before_objs]
    src_acts = [a for a in bpy.data.actions if a not in before_acts]
    src_arm = next(o for o in src_objs if o.type == "ARMATURE")

    # Precompute rest world rotations for source & destination bones
    src_arm_rot = src_arm.matrix_world.to_quaternion()
    dst_arm_rot = dst_arm.matrix_world.to_quaternion()

    src_rest_q = {}
    for b in src_arm.data.bones:
        src_rest_q[b.name] = (src_arm_rot @ b.matrix_local.to_quaternion()).normalized()

    dst_rest_q = {}
    dst_local_rest_q = {}
    for b in dst_arm.data.bones:
        dst_rest_q[b.name] = (dst_arm_rot @ b.matrix_local.to_quaternion()).normalized()
        if b.parent:
            dst_local_rest_q[b.name] = (b.parent.matrix_local.to_quaternion().inverted() @ b.matrix_local.to_quaternion()).normalized()
        else:
            dst_local_rest_q[b.name] = b.matrix_local.to_quaternion().normalized()

    dst_order = topological_bone_order(dst_arm)
    src_hips_name = bone_map["Hips"]
    src_hips_rest_w = src_arm.matrix_world @ src_arm.data.bones[src_hips_name].head_local
    dst_hips_rest_w = dst_arm.matrix_world @ dst_arm.data.bones["Hips"].head_local
    hip_scale = dst_hips_rest_w.z / max(0.2, src_hips_rest_w.z)
    dst_hips_rest_mat_inv = dst_arm.data.bones["Hips"].matrix_local.to_3x3().inverted()

    created_actions = []
    if dst_arm.animation_data is None:
        dst_arm.animation_data_create()
    if src_arm.animation_data is None:
        src_arm.animation_data_create()

    for src_name, dst_name in clip_renames.items():
        # Find action by exact or suffix match
        src_act = next((a for a in src_acts if a.name == src_name or a.name.endswith("|" + src_name) or a.name.startswith(src_name + ".")), None)
        if src_act is None:
            print(f"  WARN: clip {src_name} not found in {os.path.basename(src_path)}")
            continue

        src_arm.animation_data.action = src_act
        f_start = int(round(src_act.frame_range[0]))
        f_end = int(round(src_act.frame_range[1]))
        if f_end <= f_start:
            f_end = f_start + 1

        dst_act = bpy.data.actions.new(name=dst_name)
        dst_arm.animation_data.action = dst_act
        reset_pose(dst_arm)

        frames = list(range(f_start, f_end + 1, step))
        if frames[-1] != f_end:
            frames.append(f_end)

        prev_quats = {}
        for out_idx, f in enumerate(frames):
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            out_frame = out_idx * step

            # Compute world-space rotation for every destination bone top-down
            dst_posed_world_q = {}
            for bname in dst_order:
                pb = dst_arm.pose.bones[bname]
                pb.rotation_mode = "QUATERNION"
                parent = pb.parent
                parent_world_q = dst_posed_world_q[parent.name] if parent else dst_arm_rot

                if bname in bone_map and bone_map[bname] in src_arm.pose.bones:
                    sb_name = bone_map[bname]
                    spb = src_arm.pose.bones[sb_name]
                    src_world_q = (src_arm_rot @ spb.matrix.to_quaternion()).normalized()
                    delta_world_q = (src_world_q @ src_rest_q[sb_name].inverted()).normalized()
                    target_world_q = (delta_world_q @ dst_rest_q[bname]).normalized()
                    expected_rest_world_q = (parent_world_q @ dst_local_rest_q[bname]).normalized()
                    local_q = (expected_rest_world_q.inverted() @ target_world_q).normalized()
                    # Ensure quaternion hemisphere continuity (prevents 360-deg slerp flips!)
                    if bname in prev_quats and prev_quats[bname].dot(local_q) < 0.0:
                        local_q = -local_q
                    prev_quats[bname] = local_q.copy()
                    pb.rotation_quaternion = local_q
                    dst_posed_world_q[bname] = target_world_q
                    pb.keyframe_insert(data_path="rotation_quaternion", frame=out_frame)
                else:
                    # Keep unmapped bones (e.g. Torso/Neck in KayKit, Scarf, Weapon) in clean rest local rot
                    pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
                    dst_posed_world_q[bname] = (parent_world_q @ dst_local_rest_q[bname]).normalized()

            # Retarget Hips translation (vertical bounce + crouch/crawl drop, zero X/Y root drift!)
            sh_pb = src_arm.pose.bones[src_hips_name]
            src_hips_cur_w = src_arm.matrix_world @ sh_pb.head
            delta_w = (src_hips_cur_w - src_hips_rest_w) * hip_scale
            # Keep horizontal drift clamped to small natural sway so in-place locomotion stays centered
            delta_w.x = max(-0.08, min(0.08, delta_w.x))
            delta_w.y = max(-0.08, min(0.08, delta_w.y))
            dst_hips_pb = dst_arm.pose.bones["Hips"]
            dst_hips_pb.location = dst_hips_rest_mat_inv @ delta_w
            dst_hips_pb.keyframe_insert(data_path="location", frame=out_frame)

        created_actions.append(dst_act)
        print(f"  RETARGETED: {src_name} -> {dst_name} ({len(frames)} keys)")

    # Clean up temporary imported source objects & actions
    for o in src_objs:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in src_acts:
        if a.name in bpy.data.actions and a.users == 0:
            bpy.data.actions.remove(a)
    return created_actions


# ---------------------------------------------------------------------------
# Step 4: Analytical 2-Bone IK Solver inside Blender for Exact Rifle & Slam Poses!
# ---------------------------------------------------------------------------
def set_bone_world_delta(arm, bname, euler_xyz_deg):
    """Apply an intuitive world-space Euler XYZ delta rotation (degrees) onto a pose bone."""
    pb = arm.pose.bones[bname]
    pb.rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()
    # Parent posed world rotation
    if pb.parent:
        parent_wq = pb.parent.matrix.to_quaternion()
    else:
        parent_wq = Quaternion((1, 0, 0, 0))
    local_rest = (pb.bone.parent.matrix_local.to_quaternion().inverted() @ pb.bone.matrix_local.to_quaternion()) if pb.bone.parent else pb.bone.matrix_local.to_quaternion()
    rest_wq = pb.bone.matrix_local.to_quaternion()
    delta_wq = Euler(tuple(math.radians(a) for a in euler_xyz_deg), "XYZ").to_quaternion()
    target_wq = (delta_wq @ rest_wq).normalized()
    expected_wq = (parent_wq @ local_rest).normalized()
    pb.rotation_quaternion = (expected_wq.inverted() @ target_wq).normalized()


def aim_bone_at_world_dir(arm, bname, target_dir_world, up_hint_world=None):
    """Rotate bone so its head->tail axis (+Y in bone space) aligns cleanly with target_dir_world."""
    pb = arm.pose.bones[bname]
    pb.rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()
    cur_mat = pb.matrix.to_3x3()
    cur_y = (cur_mat @ Vector((0, 1, 0))).normalized()
    tgt = target_dir_world.normalized()
    rot_q = cur_y.rotation_difference(tgt)
    new_world_q = (rot_q @ pb.matrix.to_quaternion()).normalized()
    if up_hint_world is not None:
        new_z = (new_world_q @ Vector((0, 0, 1))).normalized()
        proj_cur = (new_z - tgt * new_z.dot(tgt))
        proj_hint = (up_hint_world - tgt * up_hint_world.dot(tgt))
        if proj_cur.length > 1e-4 and proj_hint.length > 1e-4:
            twist = proj_cur.normalized().rotation_difference(proj_hint.normalized())
            new_world_q = (twist @ new_world_q).normalized()
    parent_wq = pb.parent.matrix.to_quaternion() if pb.parent else Quaternion((1, 0, 0, 0))
    local_rest = (pb.bone.parent.matrix_local.to_quaternion().inverted() @ pb.bone.matrix_local.to_quaternion()) if pb.bone.parent else pb.bone.matrix_local.to_quaternion()
    expected_wq = (parent_wq @ local_rest).normalized()
    pb.rotation_quaternion = (expected_wq.inverted() @ new_world_q).normalized()
    bpy.context.view_layer.update()


def solve_arm_2bone_ik_blender(arm, upper_name, lower_name, hand_name, target_pos, pole_pos, hand_forward_dir=None, hand_up_dir=None):
    """Exact analytical 2-bone IK solver in Blender world space (zero gimbal/twist issues!)."""
    bpy.context.view_layer.update()
    pb_u = arm.pose.bones[upper_name]
    pb_l = arm.pose.bones[lower_name]
    pb_h = arm.pose.bones[hand_name]

    shoulder_pos = pb_u.head.copy()
    len1 = (pb_l.head - pb_u.head).length
    len2 = (pb_h.head - pb_l.head).length

    to_tgt = target_pos - shoulder_pos
    min_d = abs(len1 - len2) + 0.012
    max_d = (len1 + len2) - 0.004
    dist = max(min_d, min(max_d, to_tgt.length))
    dir_st = to_tgt.normalized()

    # Law of cosines for shoulder angle
    cos_a = max(-1.0, min(1.0, (len1 * len1 + dist * dist - len2 * len2) / (2.0 * len1 * dist)))
    ang_a = math.acos(cos_a)

    # Bend plane normal from pole vector
    to_pole = pole_pos - shoulder_pos
    bend_dir = to_pole - dir_st * to_pole.dot(dir_st)
    if bend_dir.length < 1e-4:
        bend_dir = Vector((0, 0, -1))
    bend_dir.normalize()

    elbow_pos = shoulder_pos + dir_st * (len1 * math.cos(ang_a)) + bend_dir * (len1 * math.sin(ang_a))
    # Aim upper arm shoulder -> elbow, forearm elbow -> target_pos
    aim_bone_at_world_dir(arm, upper_name, elbow_pos - shoulder_pos, up_hint_world=bend_dir)
    aim_bone_at_world_dir(arm, lower_name, target_pos - elbow_pos, up_hint_world=bend_dir)
    if hand_forward_dir is not None:
        aim_bone_at_world_dir(arm, hand_name, hand_forward_dir, up_hint_world=hand_up_dir)


def curl_fingers(arm, side="R", grip_amount=0.85, trigger_index=False):
    """Curl all 5 articulated fingers cleanly INWARD into the palm using verified local bone Z flexion axes!"""
    # Verified from Swat.glb bone local axes:
    # Right fingers: +X = back of hand (+Z world), +Y = along finger (-X world), +Z = thumb edge (-Y world).
    #   Right-hand rotation +angle around local Z bends +Y -> -X (curling cleanly into palm!).
    # Left fingers:  +X = palm side (-Z world), +Y = along finger (+X world), +Z = thumb edge (-Y world).
    #   Right-hand rotation -angle around local Z bends +Y -> +X (curling cleanly into palm!).
    sgn = 1.0 if side == "R" else -1.0
    for f_prefix in ("Index", "Middle", "Ring", "Pinky"):
        amt = grip_amount * (0.28 if (trigger_index and f_prefix == "Index") else 1.0)
        for seg, deg in (("2", 52.0), ("3", 74.0), ("4", 58.0)):
            bname = f"{f_prefix}{seg}.{side}"
            if bname in arm.pose.bones:
                pb = arm.pose.bones[bname]
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = Euler((0.0, 0.0, math.radians(amt * deg * sgn)), "XYZ").to_quaternion()
    # Oppose thumb cleanly INWARD across palm / pistol grip (negated Z flexes thumb into palm!)
    for seg, rx, rz in (("2", -18.0, -42.0), ("3", -10.0, -48.0)):
        bname = f"Thumb{seg}.{side}"
        if bname in arm.pose.bones:
            pb = arm.pose.bones[bname]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Euler((math.radians(rx * sgn), 0.0, math.radians(rz * sgn)), "XYZ").to_quaternion()


def pose_and_key_rifle_stance(arm, action_name, rifle_pos, rifle_euler_deg, hips_drop=0.0, torso_yaw_deg=20.0, torso_pitch_deg=4.0, head_tilt_deg=0.0, breath_amp=0.008, frames=32, recoil=False, crouched=False, prone=False):
    """Build crisp athletic two-handed rifle poses solved directly to exact YS-04 grip & handguard points!"""
    act = bpy.data.actions.new(name=action_name)
    arm.animation_data.action = act

    # Exact YS-04 Carbine grip points in rifle local space (scaled 0.78 => 0.67m crisp compact carbine!):
    # Hand.R wrist sits ~6cm behind pistol grip (y=+0.12) so palm wraps DEAD ON the black pistol grip & index finger reaches trigger!
    # Hand.L wrist sits just below/left of forward handguard (y=-0.14) so left palm cradles the green foregrip tightly!
    grip_r_wrist_local = Vector((-0.012, 0.175, -0.048))
    foregrip_l_wrist_local = Vector((0.020, -0.115, -0.022))
    dst_hips_inv = arm.data.bones["Hips"].matrix_local.to_3x3().inverted()

    key_frames = [0, 2, 5, 9] if recoil else [0, frames // 4, frames // 2, (3 * frames) // 4, frames]
    for kf in key_frames:
        reset_pose(arm)
        t = kf / max(1.0, float(frames))
        breath = math.sin(t * 2.0 * math.pi) * breath_amp
        kick_z = 0.0
        kick_pitch = 0.0
        if recoil:
            if kf == 2:
                kick_z = 0.035
                kick_pitch = 7.5
            elif kf == 5:
                kick_z = 0.010
                kick_pitch = 2.0

        if prone:
            # Verified right-hand rule around +X in Blender: +angle tilts +Z torso FORWARD (-Y) and -Z legs BACKWARD (+Y)!
            # Result: authentic belly-down tactical sniper prone with chest propped on elbows & legs extended cleanly behind!
            arm.pose.bones["Hips"].location = dst_hips_inv @ Vector((0.0, 0.12, -0.685 + breath * 0.3))
            set_bone_world_delta(arm, "Hips", (82.0, 0.0, 0.0))
            set_bone_world_delta(arm, "Abdomen", (72.0, 0.0, 0.0))
            set_bone_world_delta(arm, "Torso", (58.0, 0.0, -8.0))
            set_bone_world_delta(arm, "Chest", (44.0, 0.0, -14.0))
            set_bone_world_delta(arm, "Neck", (16.0, 0.0, -6.0))
            set_bone_world_delta(arm, "Head", (4.0, 0.0, 0.0))
            # Legs extended straight BACKWARD (+Y) resting cleanly on top of desert sand, heels slightly splayed!
            set_bone_world_delta(arm, "UpperLeg.L", (88.0, 0.0, 12.0))
            set_bone_world_delta(arm, "LowerLeg.L", (84.0, 0.0, 12.0))
            set_bone_world_delta(arm, "Foot.L", (55.0, 0.0, 18.0))
            set_bone_world_delta(arm, "UpperLeg.R", (88.0, 0.0, -14.0))
            set_bone_world_delta(arm, "LowerLeg.R", (82.0, 0.0, -14.0))
            set_bone_world_delta(arm, "Foot.R", (52.0, 0.0, -20.0))
        elif crouched:
            arm.pose.bones["Hips"].location = dst_hips_inv @ Vector((0.0, 0.02, -0.34 + breath))
            set_bone_world_delta(arm, "Hips", (10.0, 0.0, -torso_yaw_deg * 0.55))
            set_bone_world_delta(arm, "Abdomen", (12.0, 0.0, -torso_yaw_deg * 0.7))
            set_bone_world_delta(arm, "Torso", (14.0, 0.0, -torso_yaw_deg * 0.85))
            set_bone_world_delta(arm, "Chest", (15.0 + kick_pitch * 0.3, 0.0, -torso_yaw_deg))
            set_bone_world_delta(arm, "Neck", (4.0, 0.0, -torso_yaw_deg * 0.35))
            set_bone_world_delta(arm, "Head", (2.0, head_tilt_deg, 0.0))
            # Left knee up forward, right knee down supporting crouch
            set_bone_world_delta(arm, "UpperLeg.L", (72.0, 0.0, 10.0))
            set_bone_world_delta(arm, "LowerLeg.L", (-18.0, 0.0, 8.0))
            set_bone_world_delta(arm, "Foot.L", (2.0, 0.0, 8.0))
            set_bone_world_delta(arm, "UpperLeg.R", (22.0, 0.0, -18.0))
            set_bone_world_delta(arm, "LowerLeg.R", (-76.0, 0.0, -16.0))
            set_bone_world_delta(arm, "Foot.R", (-24.0, 0.0, -16.0))
        else:
            # Authentic athletic staggered tactical combat stance (NO stiff parallel wooden legs!)
            arm.pose.bones["Hips"].location = dst_hips_inv @ Vector((0.0, 0.015, -hips_drop + breath))
            set_bone_world_delta(arm, "Hips", (4.0, 0.0, -torso_yaw_deg * 0.60))
            set_bone_world_delta(arm, "Abdomen", (torso_pitch_deg * 0.5, 0.0, -torso_yaw_deg * 0.72))
            set_bone_world_delta(arm, "Torso", (torso_pitch_deg * 0.8, 0.0, -torso_yaw_deg * 0.88))
            set_bone_world_delta(arm, "Chest", (torso_pitch_deg + kick_pitch * 0.35, 0.0, -torso_yaw_deg))
            set_bone_world_delta(arm, "Neck", (2.0, 0.0, -torso_yaw_deg * 0.32))
            set_bone_world_delta(arm, "Head", (0.0, head_tilt_deg, 0.0))
            # Athletic staggered feet: Left leg forward & slightly bent, Right leg back-angled ~22 deg!
            set_bone_world_delta(arm, "UpperLeg.L", (16.0, 2.0, 8.0))
            set_bone_world_delta(arm, "LowerLeg.L", (-10.0, 0.0, 8.0))
            set_bone_world_delta(arm, "Foot.L", (0.0, 0.0, 8.0))
            set_bone_world_delta(arm, "UpperLeg.R", (-14.0, -3.0, -24.0))
            set_bone_world_delta(arm, "LowerLeg.R", (-22.0, 0.0, -22.0))
            set_bone_world_delta(arm, "Foot.R", (2.0, 0.0, -24.0))

        bpy.context.view_layer.update()
        # Rifle target transform in character world space
        r_pos = Vector(rifle_pos) + Vector((0.0, kick_z, breath * 0.85))
        r_euler = Euler((math.radians(rifle_euler_deg[0] + kick_pitch), math.radians(rifle_euler_deg[1]), math.radians(rifle_euler_deg[2])), "XYZ")
        r_mat = Matrix.Translation(r_pos) @ r_euler.to_matrix().to_4x4()

        target_hand_r = r_mat @ grip_r_wrist_local
        target_hand_l = r_mat @ foregrip_l_wrist_local
        rifle_fwd = (r_mat.to_3x3() @ Vector((0, -1, 0))).normalized()
        rifle_up = (r_mat.to_3x3() @ Vector((0, 0, 1))).normalized()
        rifle_right = (r_mat.to_3x3() @ Vector((-1, 0, 0))).normalized()

        # Subtle shoulder forward pull
        set_bone_world_delta(arm, "Shoulder.R", (6.0, 0.0, -12.0))
        set_bone_world_delta(arm, "Shoulder.L", (6.0, 0.0, 16.0))

        # Exact 2-bone IK for Right Arm (holding pistol grip) & Left Arm (cradling handguard from below!)
        pole_r = Vector((-0.34, 0.08, r_pos.z - 0.34))
        pole_l = Vector((0.24, -0.04, r_pos.z - 0.38))
        if prone:
            pole_r = Vector((-0.36, -0.18, 0.04))
            pole_l = Vector((0.30, -0.22, 0.04))

        # Hand.R: +Y along rifle forward, +Z (thumb edge!) pointing UP (rifle_up) so palm clamps pistol grip inward!
        solve_arm_2bone_ik_blender(arm, "UpperArm.R", "LowerArm.R", "Hand.R", target_hand_r, pole_r, hand_forward_dir=(rifle_fwd * 0.92 - rifle_up * 0.28).normalized(), hand_up_dir=rifle_up)
        # Hand.L: +Y pointing forward-right across underside of handguard, +Z (thumb edge!) pointing forward-up so palm cradles up!
        l_hand_dir = (rifle_fwd * 0.55 + rifle_right * 0.72 + rifle_up * 0.32).normalized()
        l_hand_thumb_up = (rifle_fwd * 0.72 - rifle_right * 0.45 + rifle_up * 0.50).normalized()
        solve_arm_2bone_ik_blender(arm, "UpperArm.L", "LowerArm.L", "Hand.L", target_hand_l, pole_l, hand_forward_dir=l_hand_dir, hand_up_dir=l_hand_thumb_up)

        # Curl realistic fingers around pistol grip (with trigger finger) and handguard!
        curl_fingers(arm, "R", grip_amount=0.92, trigger_index=True)
        curl_fingers(arm, "L", grip_amount=0.80, trigger_index=False)

        # Orient Weapon_R socket bone directly to the exact rifle matrix so Godot BoneAttachment3D matches 100%!
        bpy.context.view_layer.update()
        wb_pb = arm.pose.bones["Weapon_R"]
        wb_pb.rotation_mode = "QUATERNION"
        # Convert target rifle world matrix into Weapon_R local pose matrix
        parent_mat = wb_pb.parent.matrix
        rest_local = wb_pb.bone.parent.matrix_local.inverted() @ wb_pb.bone.matrix_local
        # Weapon_R bone +Y aligns with rifle forward (-Y in r_mat), bone +Z aligns with rifle up (+Z in r_mat)
        # In Edit Mode, Weapon_R head->tail points along -Y (0,-1,0) with roll +Z, so identity matrix == r_mat at head!
        # Let's place Weapon_R origin at r_pos and align its world rotation with r_euler:
        rest_world_rot = wb_pb.bone.matrix_local.to_quaternion()
        tgt_world_rot = (r_euler.to_quaternion() @ rest_world_rot).normalized()
        expected_rot = (parent_mat.to_quaternion() @ rest_local.to_quaternion()).normalized()
        wb_pb.rotation_quaternion = (expected_rot.inverted() @ tgt_world_rot).normalized()
        # Local position offset to place rifle center exactly at r_pos
        expected_mat = parent_mat @ rest_local
        wb_pb.location = expected_mat.inverted() @ r_pos

        # Keyframe every bone
        for pb in arm.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=kf)
            if pb.name in ("Hips", "Weapon_R"):
                pb.keyframe_insert(data_path="location", frame=kf)

    return act


def build_shaoyu_ground_slam_action(arm):
    """Heroic [V] '天生神力' Ground-Slam Punch (rifle holstered on back; explosive bronze-knuckle impact!)."""
    act = bpy.data.actions.new(name="Shaoyu_GroundSlam")
    arm.animation_data.action = act
    dst_hips_inv = arm.data.bones["Hips"].matrix_local.to_3x3().inverted()

    # Keyframes at 30fps: 0 (ready), 5 (leap/windup), 10 (violent earth impact), 15 (impact hold), 22 (heroic rise)
    stages = [
        # (frame, hip_drop, torso_pitch, torso_yaw, r_hand_target, l_hand_target, legL_u, legL_l, legR_u, legR_l)
        (0,  0.04, 6.0,  -15.0, Vector((-0.24, -0.22, 1.24)), Vector((0.24, -0.22, 1.24)), 14.0, -10.0, -10.0, -16.0),
        (5, -0.10, -14.0, -48.0, Vector((-0.34,  0.14, 1.66)), Vector((0.26, -0.34, 1.32)), 36.0, -42.0, 12.0, -34.0),
        (10, 0.56, 56.0,  34.0, Vector((-0.06, -0.44, 0.08)), Vector((0.38,  0.22, 0.96)), 88.0, -16.0, 26.0, -96.0),
        (15, 0.54, 52.0,  30.0, Vector((-0.06, -0.42, 0.10)), Vector((0.36,  0.20, 0.98)), 86.0, -18.0, 26.0, -94.0),
        (22, 0.04, 6.0,  -15.0, Vector((-0.24, -0.22, 1.24)), Vector((0.24, -0.22, 1.24)), 14.0, -10.0, -10.0, -16.0),
    ]
    for kf, hdrop, tpitch, tyaw, rh_tgt, lh_tgt, llu, lll, lru, lrl in stages:
        reset_pose(arm)
        arm.pose.bones["Hips"].location = dst_hips_inv @ Vector((0.0, -0.04 if kf in (10, 15) else 0.0, -hdrop))
        set_bone_world_delta(arm, "Hips", (tpitch * 0.35, 0.0, tyaw * 0.45))
        set_bone_world_delta(arm, "Abdomen", (tpitch * 0.65, 0.0, tyaw * 0.65))
        set_bone_world_delta(arm, "Torso", (tpitch * 0.85, 0.0, tyaw * 0.85))
        set_bone_world_delta(arm, "Chest", (tpitch, 0.0, tyaw))
        set_bone_world_delta(arm, "Neck", (tpitch * 0.25, 0.0, tyaw * 0.25))
        set_bone_world_delta(arm, "Head", (max(-6.0, tpitch * 0.15), 0.0, 0.0))

        set_bone_world_delta(arm, "UpperLeg.L", (llu, 0.0, 12.0))
        set_bone_world_delta(arm, "LowerLeg.L", (lll, 0.0, 10.0))
        set_bone_world_delta(arm, "Foot.L", (0.0, 0.0, 10.0))
        set_bone_world_delta(arm, "UpperLeg.R", (lru, 0.0, -18.0))
        set_bone_world_delta(arm, "LowerLeg.R", (lrl, 0.0, -16.0))
        set_bone_world_delta(arm, "Foot.R", (-18.0 if kf in (10, 15) else 0.0, 0.0, -16.0))

        pole_r = Vector((-0.48, 0.12, 1.30 if kf == 5 else 0.62))
        pole_l = Vector((0.46, 0.28, 1.15))
        r_fist_dir = Vector((0.0, -0.35, -0.94)).normalized() if kf in (10, 15) else Vector((0.0, -0.7, 0.7)).normalized()
        solve_arm_2bone_ik_blender(arm, "UpperArm.R", "LowerArm.R", "Hand.R", rh_tgt, pole_r, hand_forward_dir=r_fist_dir, hand_up_dir=Vector((0, -1, 0)))
        solve_arm_2bone_ik_blender(arm, "UpperArm.L", "LowerArm.L", "Hand.L", lh_tgt, pole_l, hand_forward_dir=Vector((0.6, 0.5, -0.5)).normalized(), hand_up_dir=Vector((0, 0, 1)))
        curl_fingers(arm, "R", grip_amount=1.08, trigger_index=False)
        curl_fingers(arm, "L", grip_amount=0.95, trigger_index=False)

        for pb in arm.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=kf)
            if pb.name == "Hips":
                pb.keyframe_insert(data_path="location", frame=kf)
    return act


def build_all_animations(arm):
    if arm.animation_data is None:
        arm.animation_data_create()
    all_acts = []

    # 1. Retarget Quaternius UAL (CC0) locomotion & sword clips
    ual_clips = {
        "Idle_Loop": "Idle_Stance",
        "Walk_Loop": "Walk_Fwd",
        "Jog_Fwd_Loop": "Jog_Fwd",
        "Sprint_Loop": "Sprint_Fwd",
        "Crouch_Idle_Loop": "Crouch_Idle",
        "Crouch_Fwd_Loop": "Crouch_Walk",
        "Jump_Start": "Jump_Start",
        "Jump_Loop": "Jump_Loop",
        "Jump_Land": "Jump_Land",
        "Sword_Idle": "Knife_Idle",
        "Sword_Attack": "Knife_Slash_1",
        "Hit_Chest": "Hit_React",
    }
    all_acts += retarget_actions_from_file(
        arm,
        os.path.join(CC0_DIR, "AnimationLibrary_Godot_Standard.gltf"),
        UAL_BONE_MAP,
        ual_clips,
        step=2,
    )

    # 2. Retarget KayKit MovementAdvanced (CC0): Backpedal, Strafe L/R, Real Prone Crawl!
    kk_move = {
        "Walking_Backwards": "Walk_Back",
        "Running_Strafe_Left": "Strafe_Left",
        "Running_Strafe_Right": "Strafe_Right",
        "Crawling": "Prone_Crawl",
    }
    all_acts += retarget_actions_from_file(
        arm,
        os.path.join(CC0_DIR, "Rig_Medium_MovementAdvanced.glb"),
        KAYKIT_BONE_MAP,
        kk_move,
        step=2,
    )

    # 3. Retarget KayKit CombatRanged & CombatMelee (CC0): Reload + Reverse Slash!
    all_acts += retarget_actions_from_file(
        arm,
        os.path.join(CC0_DIR, "Rig_Medium_CombatRanged.glb"),
        KAYKIT_BONE_MAP,
        {"Ranged_2H_Reload": "Rifle_Reload"},
        step=2,
    )
    all_acts += retarget_actions_from_file(
        arm,
        os.path.join(CC0_DIR, "Rig_Medium_CombatMelee.glb"),
        KAYKIT_BONE_MAP,
        {"Melee_1H_Attack_Slice_Horizontal": "Knife_Slash_2"},
        step=2,
    )

    # 4. Precision Blender 2-Bone IK Tactical Rifle Poses & Prone Aim & Shaoyu [V] GroundSlam!
    # Low-Ready: authentic Delta Force tactical carry across chest, muzzle angled naturally DOWN-LEFT (+18 deg X!)
    all_acts.append(
        pose_and_key_rifle_stance(
            arm,
            "Rifle_LowReady",
            rifle_pos=(-0.035, -0.295, 1.155),
            rifle_euler_deg=(18.0, 4.0, -28.0),
            hips_drop=0.042,
            torso_yaw_deg=24.0,
            torso_pitch_deg=4.0,
            head_tilt_deg=0.0,
            breath_amp=0.009,
            frames=36,
        )
    )
    # ADS Aiming: buttstock firmly seated into right shoulder pocket, barrel dead straight forward (-Y)!
    all_acts.append(
        pose_and_key_rifle_stance(
            arm,
            "Rifle_Aim",
            rifle_pos=(-0.095, -0.315, 1.320),
            rifle_euler_deg=(0.0, 0.0, -2.0),
            hips_drop=0.055,
            torso_yaw_deg=28.0,
            torso_pitch_deg=6.0,
            head_tilt_deg=-7.0,
            breath_amp=0.004,
            frames=32,
        )
    )
    # Crisp Shoulder Recoil Fire Kick
    all_acts.append(
        pose_and_key_rifle_stance(
            arm,
            "Rifle_Fire",
            rifle_pos=(-0.095, -0.315, 1.320),
            rifle_euler_deg=(0.0, 0.0, -2.0),
            hips_drop=0.055,
            torso_yaw_deg=28.0,
            torso_pitch_deg=6.0,
            head_tilt_deg=-7.0,
            breath_amp=0.0,
            frames=9,
            recoil=True,
        )
    )
    # Crouched Tactical Rifle Aim
    all_acts.append(
        pose_and_key_rifle_stance(
            arm,
            "Rifle_Crouch_Aim",
            rifle_pos=(-0.092, -0.325, 0.995),
            rifle_euler_deg=(0.0, 0.0, -2.0),
            hips_drop=0.34,
            torso_yaw_deg=26.0,
            torso_pitch_deg=12.0,
            head_tilt_deg=-6.0,
            breath_amp=0.004,
            frames=32,
            crouched=True,
        )
    )
    # Belly-Down Prone Rifle Stance (chest propped on elbows, legs extended cleanly backward!)
    all_acts.append(
        pose_and_key_rifle_stance(
            arm,
            "Prone_Idle",
            rifle_pos=(-0.065, -0.585, 0.435),
            rifle_euler_deg=(0.0, 0.0, -2.0),
            breath_amp=0.004,
            frames=32,
            prone=True,
        )
    )
    # Heroic [V] 天生神力 Ground-Slam Punch!
    all_acts.append(build_shaoyu_ground_slam_action(arm))

    # Push every action onto an NLA strip so glTF 2.0 exports ALL animations reliably!
    arm.animation_data.action = None
    for tr in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(tr)
    for act in all_acts:
        act.use_fake_user = True
        tr = arm.animation_data.nla_tracks.new()
        tr.name = act.name
        f0 = int(round(act.frame_range[0]))
        st = tr.strips.new(act.name, f0, act)
        st.name = act.name
        tr.mute = True

    reset_pose(arm)
    return all_acts


# ---------------------------------------------------------------------------
# Step 5: Export GLB & Render 4-Panel Studio Proof Sheet with Real YS-04 Rifle!
# ---------------------------------------------------------------------------
def export_shaoyu_glb(arm, meshes):
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
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
        export_image_format="AUTO",
    )
    sz = os.path.getsize(OUT_GLB)
    total_polys = sum(len(m.data.polygons) for m in meshes)
    total_verts = sum(len(m.data.vertices) for m in meshes)
    print(f"EXPORTED: {OUT_GLB} ({sz:,} bytes | {total_verts:,} verts | {total_polys:,} polys | {len(arm.data.bones)} bones | {len(arm.animation_data.nla_tracks)} anims)")


def render_studio_proof(arm):
    """Render 4 views side-by-side: Front Bust/Body | Back 3P View | 3/4 Rifle Aim w/ real YS-04 | [V] Ground Slam!"""
    # Import real YS-04 rifle scaled to real carbine size (0.85x => 0.73m) and attach to Weapon_R
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=RIFLE_GLB)
    rifle_objs = [o for o in bpy.data.objects if o not in before]
    rifle_root = bpy.data.objects.new("PreviewRifleRoot", None)
    bpy.context.collection.objects.link(rifle_root)
    for ro in rifle_objs:
        if ro.parent is None:
            ro.parent = rifle_root
    # Flip rifle so muzzle (+Y in rifle.glb) points along -Y (character forward) and scale 0.85
    rifle_root.scale = (0.85, 0.85, 0.85)
    rifle_root.rotation_euler = (0.0, 0.0, math.pi)

    # Studio lighting
    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
    bpy.context.scene.render.resolution_x = 1280
    bpy.context.scene.render.resolution_y = 720
    world = bpy.data.worlds.new("StudioW")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.76, 0.80, 0.84, 1.0)
    bg.inputs[1].default_value = 0.85

    sun = bpy.data.objects.new("KeySun", bpy.data.lights.new("KeySun", "SUN"))
    sun.data.energy = 3.6
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(42), math.radians(18), math.radians(-32))

    fill = bpy.data.objects.new("FillLight", bpy.data.lights.new("FillLight", "AREA"))
    fill.data.energy = 120.0
    fill.data.size = 3.0
    bpy.context.collection.objects.link(fill)
    fill.location = (2.4, -2.4, 2.2)
    fill.rotation_euler = (math.radians(55), 0.0, math.radians(45))

    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 52
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    def aim_cam(loc, target):
        cam.location = Vector(loc)
        d = Vector(target) - Vector(loc)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()

    def set_pose_action(aname, frame=0, show_rifle="hand"):
        for tr in arm.animation_data.nla_tracks:
            tr.mute = True
        act = bpy.data.actions.get(aname)
        arm.animation_data.action = act
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        if show_rifle == "hand":
            rifle_root.hide_render = False
            pb = arm.pose.bones["Weapon_R"]
            m = arm.matrix_world @ pb.matrix
            # Weapon_R +Y points along rifle forward (-Y in rifle_root), so align rifle_root
            r_loc = m.to_translation()
            # Reconstruct exact world orientation from bone matrix (head->tail = -Y in rest)
            q = (m.to_quaternion() @ arm.data.bones["Weapon_R"].matrix_local.to_quaternion().inverted()).normalized()
            rifle_root.matrix_world = Matrix.Translation(r_loc) @ q.to_matrix().to_4x4() @ Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Diagonal((0.78, 0.78, 0.78, 1.0))
        elif show_rifle == "back":
            rifle_root.hide_render = False
            pb = arm.pose.bones["Weapon_Back"]
            m = arm.matrix_world @ pb.matrix
            rifle_root.matrix_world = Matrix.Translation(m.to_translation()) @ m.to_quaternion().to_matrix().to_4x4() @ Matrix.Rotation(math.radians(90), 4, "X") @ Matrix.Diagonal((0.82, 0.82, 0.82, 1.0))
        else:
            rifle_root.hide_render = True

    shots = [
        ("front", "Rifle_LowReady", 0, "hand", (-0.55, -2.55, 1.18), (0.0, 0.0, 1.02)),
        ("back3p", "Rifle_Aim", 0, "hand", (-0.36, 2.25, 1.38), (-0.08, -0.25, 1.15)),
        ("aim34", "Rifle_Aim", 0, "hand", (-1.55, -1.65, 1.28), (-0.05, -0.15, 1.15)),
        ("slam", "Shaoyu_GroundSlam", 10, "back", (-1.65, -1.95, 1.05), (0.0, -0.15, 0.65)),
    ]
    bpy.context.scene.render.resolution_x = 640
    bpy.context.scene.render.resolution_y = 480
    panels = []
    for tag, aname, fr, rmode, cloc, ctgt in shots:
        set_pose_action(aname, fr, rmode)
        aim_cam(cloc, ctgt)
        tmp = PREVIEW_PNG.replace(".png", f"_{tag}.png")
        bpy.context.scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        arr = np.array(img.pixels[:], dtype=np.float32).reshape((480, 640, 4))
        panels.append(arr)
        bpy.data.images.remove(img)
        try:
            os.remove(tmp)
        except OSError:
            pass

    # Stitch 2x2 composite (1280x960)
    top = np.concatenate([panels[0], panels[1]], axis=1)
    bot = np.concatenate([panels[2], panels[3]], axis=1)
    grid = np.concatenate([bot, top], axis=0)  # Blender pixels are bottom-up!
    out_img = bpy.data.images.new("ProofGrid", width=1280, height=960, alpha=False)
    out_img.pixels.foreach_set(grid.ravel())
    out_img.filepath_raw = PREVIEW_PNG
    out_img.file_format = "PNG"
    out_img.save()
    print("RENDERED_PROOF:", PREVIEW_PNG)


def main():
    arm, swat_body, swat_legs, swat_feet, casual_head = build_normalized_shaoyu_base()
    pal = create_material_palette()
    meshes = customize_shaoyu_appearance(arm, swat_body, swat_legs, swat_feet, casual_head, pal)
    acts = build_all_animations(arm)
    export_shaoyu_glb(arm, meshes)
    if "--preview" in sys.argv:
        render_studio_proof(arm)


if __name__ == "__main__":
    main()
