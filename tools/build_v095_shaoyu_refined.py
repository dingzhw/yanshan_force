"""Build v0.9.5 Refined Hero Protagonist '游侠·少羽' (Shaoyu) — Sculpted Stylized Face, Zero-Twist Prone & Closed 1P Waist!

Upgrades over v0.9.4:
1. Real sculpted Pixar/Valorant-grade stylized face from Blender Studio CC0 Human Base Meshes Bundle v1.4.1
   (GEO-body_male_stylized head + real 3D stylized eyeballs eye.L/eye.R):
   - Real sculpted nose bridge, nostrils, upper/lower eyelids, expressive chestnut-iris eyes with bright catchlights
     clearly readable through the translucent amber Plan B goggles, defined sculpted eyebrows, lips, jawline & ears!
   - Lush multi-strand dark raven-black hair cap & layered swept bangs/crown/nape locks (zero bald spots!).
2. Catmull-Clark subdivided (level=1) smooth stylized clothing, cargo pants & combat boots + crisp sculpted details
   (zipper placket, rolled cuffs, forearm wraps, MOLLE 3-mag chest rig, radio, bronze knuckles, boot laces & eyelets).
3. Zero-Twist Anatomical Prone Stance (Prone_Idle) & Alternating Low-Crawl (Prone_Crawl):
   - Solved via exact world-space vector aiming (zero 90-deg Euler gimbal leg twist!), thighs/calves/boots extend cleanly
     straight behind with slight natural toe flare resting cleanly atop terrain.
4. Closed 1P Waist-Hem Cap (Shaoyu_LowerWaist) with bamboo-teal jacket hem, dark tactical belt & bronze buckle so
   looking straight down in 1P shows a continuous torso hem -> belt -> cargo pants -> kneepads -> boots (zero floating cut-off pelvis!).
"""
import bpy
import bmesh
import math
import os
import sys
import tempfile
from pathlib import Path
import numpy as np
from mathutils import Vector, Matrix, Quaternion, Euler

ROOT = str(Path(__file__).resolve().parents[1])
CC0_DIR = os.path.join(ROOT, "third_party", "v094_cc0_characters")
BLENDER_STUDIO_BLEND = os.path.join(ROOT, "third_party", "slice-v052", "human_base_meshes_bundle.blend")
RIFLE_GLB = os.path.join(ROOT, "game", "assets", "slice", "rifle.glb")
OUT_GLB = os.path.join(ROOT, "game", "assets", "slice", "player_shaoyu.glb")
PREVIEW_PNG = os.path.join(tempfile.gettempdir(), "v095_shaoyu_studio_proof.png")

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
# Procedural PBR Textures (numpy -> packed bpy.data.images)
# ---------------------------------------------------------------------------
def make_fabric_normal_image(name="Tex_RipstopNormal", size=256, grid=16, strength=0.35):
    if name in bpy.data.images:
        return bpy.data.images[name]
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
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
    nx, ny, nz = -dx * strength, -dy * strength, np.ones_like(h)
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
    rng = np.random.default_rng(9501)
    base = rng.random((size // 4, size // 4)).astype(np.float32)
    base = np.repeat(np.repeat(base, 4, axis=0), 4, axis=1)
    fine = rng.random((size, size)).astype(np.float32)
    h = 0.72 * base + 0.28 * fine
    h = (h + np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1)) * 0.2
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
    if name in bpy.data.images:
        return bpy.data.images[name]
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    u = (xx / size) * 2.0 - 1.0
    v = (yy / size) * 2.0 - 1.0
    rgba = np.zeros((size, size, 4), dtype=np.float32)
    rgba[..., 0] = 0.08
    rgba[..., 1] = 0.28
    rgba[..., 2] = 0.23
    rgba[..., 3] = 1.0
    rad = np.sqrt(u * u + v * v)
    border = (rad > 0.78) & (rad < 0.93)
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
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
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


def srgb(r, g, b):
    """Convert intuitive 0..255 sRGB color into Blender Linear RGB."""
    return ((r / 255.0) ** 2.2, (g / 255.0) ** 2.2, (b / 255.0) ** 2.2)


def create_material_palette():
    fab_n = make_fabric_normal_image("Tex_RipstopNormal", 256, 16, 0.35)
    knit_n = make_fabric_normal_image("Tex_ScarfKnitNormal", 256, 8, 0.45)
    lth_n = make_leather_normal_image("Tex_LeatherNormal", 256)
    cloud_img = make_cloud_patch_image("Tex_CloudEmblem", 256)
    return {
        "skin": make_pbr_mat("Shaoyu_Skin", srgb(232, 180, 146), roughness=0.56),
        "lips": make_pbr_mat("Shaoyu_Lips", srgb(208, 134, 112), roughness=0.46),
        "sclera": make_pbr_mat("Shaoyu_EyeSclera", srgb(246, 244, 240), roughness=0.14),
        "iris": make_pbr_mat("Shaoyu_EyeIris", srgb(112, 60, 24), roughness=0.10),
        "pupil": make_pbr_mat("Shaoyu_EyePupil", srgb(14, 14, 18), roughness=0.06),
        "eye_catch": make_pbr_mat("Shaoyu_EyeCatchlight", (1.0, 1.0, 1.0), roughness=0.04, emission=(1.0, 0.98, 0.94), emission_strength=1.35),
        "hair": make_pbr_mat("Shaoyu_Hair", srgb(28, 34, 48), roughness=0.46),
        "eyebrow": make_pbr_mat("Shaoyu_Eyebrow", srgb(24, 28, 40), roughness=0.54),
        "jacket": make_pbr_mat("Shaoyu_BambooJacket", srgb(38, 126, 112), roughness=0.66, normal_img=fab_n, normal_scale=0.35, tex_scale=10.0),
        "jacket_trim": make_pbr_mat("Shaoyu_JacketTrim", srgb(26, 86, 78), roughness=0.70, normal_img=fab_n, normal_scale=0.28, tex_scale=12.0),
        "vest": make_pbr_mat("Shaoyu_CharcoalRig", srgb(48, 54, 64), roughness=0.62, normal_img=fab_n, normal_scale=0.42, tex_scale=14.0),
        "pouch": make_pbr_mat("Shaoyu_RigPouch", srgb(62, 70, 82), roughness=0.58, normal_img=fab_n, normal_scale=0.38, tex_scale=16.0),
        "scarf": make_pbr_mat("Shaoyu_CrimsonScarf", srgb(202, 52, 40), roughness=0.74, normal_img=knit_n, normal_scale=0.42, tex_scale=12.0),
        "wrap": make_pbr_mat("Shaoyu_ForearmWrap", srgb(62, 70, 78), roughness=0.74, normal_img=knit_n, normal_scale=0.32, tex_scale=14.0),
        "glove": make_pbr_mat("Shaoyu_LeatherGlove", srgb(76, 56, 44), roughness=0.50, normal_img=lth_n, normal_scale=0.42, tex_scale=10.0),
        "bronze": make_pbr_mat("Shaoyu_BronzeKnuckle", srgb(212, 166, 78), roughness=0.26, metallic=0.84),
        "pants": make_pbr_mat("Shaoyu_CargoPants", srgb(52, 62, 74), roughness=0.72, normal_img=fab_n, normal_scale=0.38, tex_scale=9.0),
        "kneepad": make_pbr_mat("Shaoyu_Kneepad", srgb(34, 40, 48), roughness=0.46, metallic=0.14),
        "boot_leather": make_pbr_mat("Shaoyu_CombatBoot", srgb(98, 66, 44), roughness=0.52, normal_img=lth_n, normal_scale=0.45, tex_scale=8.0),
        "boot_sole": make_pbr_mat("Shaoyu_BootSole", srgb(28, 32, 36), roughness=0.82),
        "pack_main": make_pbr_mat("Shaoyu_PackMain", srgb(64, 72, 82), roughness=0.66, normal_img=fab_n, normal_scale=0.40, tex_scale=10.0),
        "pack_olive": make_pbr_mat("Shaoyu_PackOlive", srgb(84, 98, 72), roughness=0.70, normal_img=fab_n, normal_scale=0.36, tex_scale=10.0),
        "strap_tan": make_pbr_mat("Shaoyu_StrapTan", srgb(152, 130, 88), roughness=0.72, normal_img=fab_n, normal_scale=0.30, tex_scale=14.0),
        "goggle_frame": make_pbr_mat("Shaoyu_GoggleFrame", srgb(36, 42, 50), roughness=0.36, metallic=0.22),
        # Ultra-clear crystal-amber Plan B lens (alpha=0.26 so Shaoyu's sculpted eyes shine right through!)
        "goggle_lens": make_pbr_mat("Shaoyu_AmberLens", srgb(252, 178, 44), roughness=0.06, metallic=0.10, alpha=0.26, emission=srgb(240, 148, 28), emission_strength=0.10),
        "headset": make_pbr_mat("Shaoyu_Headset", srgb(44, 50, 58), roughness=0.36, metallic=0.38),
        "radio_led": make_pbr_mat("Shaoyu_RadioLED", srgb(48, 240, 128), roughness=0.2, emission=srgb(48, 240, 128), emission_strength=2.2),
        "patch": make_pbr_mat("Shaoyu_CloudPatch", (1.0, 1.0, 1.0), roughness=0.64, albedo_img=cloud_img),
    }


# ---------------------------------------------------------------------------
# Mesh Welding, Subsurf Smoothing & Sculpting Helpers
# ---------------------------------------------------------------------------
def weld_and_subsurf(obj, merge_dist=0.00035, subsurf_level=1, smooth_iters=1, smooth_fac=0.16):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge_dist)
    if smooth_iters > 0:
        interior = [v for v in bm.verts if not v.is_boundary]
        for _ in range(smooth_iters):
            bmesh.ops.smooth_vert(bm, verts=interior, factor=smooth_fac, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()
    me.update()
    if subsurf_level > 0:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new("SmoothSubsurf", "SUBSURF")
        mod.levels = subsurf_level
        mod.render_levels = subsurf_level
        mod.subdivision_type = "CATMULL_CLARK"
        # Move subsurf ABOVE armature modifier before applying so skin weights smoothly interpolate!
        try:
            bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        except Exception:
            pass
        bpy.ops.object.modifier_apply(modifier=mod.name)
        for p in obj.data.polygons:
            p.use_smooth = True


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
            side = Vector(fixed_side) - tang * Vector(fixed_side).dot(tang)
            side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
        else:
            up_ref = Vector((0, 0, 1)) if abs(tang.z) < 0.92 else Vector((0, 1, 0))
            side = tang.cross(up_ref).normalized()
        norm = side.cross(tang).normalized()
        w = widths[i] * 0.5
        t = thicknesses[i] * 0.5
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
    f0 = bm.faces.new(list(reversed(rings[0])))
    f0.material_index = mat_idx
    f0.smooth = True
    f1 = bm.faces.new(rings[-1])
    f1.material_index = mat_idx
    f1.smooth = True
    return rings


def make_weighted_object(name, bm, mats, arm, bone_weights_fn):
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
# Step 1: Import & Normalize Swat Body + Blender Studio CC0 Stylized Head/Eyes!
# ---------------------------------------------------------------------------
def build_normalized_shaoyu_base():
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=os.path.join(CC0_DIR, "Swat.glb"))
    remove_icospheres(list(bpy.data.objects))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    arm.name = "ShaoyuArmature"
    swat_body = bpy.data.objects["Swat_Body"]
    swat_legs = bpy.data.objects["Swat_Legs"]
    swat_feet = bpy.data.objects["Swat_Feet"]
    if "Swat_Head" in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects["Swat_Head"], do_unlink=True)

    bpy.context.view_layer.update()
    base_meshes = [swat_body, swat_legs, swat_feet]

    # Measure height (approx Swat full height = 1.854m, head top at 1.852m)
    all_pts = [o.matrix_world @ v.co for o in base_meshes for v in o.data.vertices]
    min_z = min(p.z for p in all_pts)
    hips_world = arm.matrix_world @ arm.data.bones["Hips"].head_local
    scale_k = TARGET_HEIGHT / 1.854
    m_fix = Matrix.Diagonal((scale_k, scale_k, scale_k, 1.0)) @ Matrix.Translation((-hips_world.x, -hips_world.y, -min_z))

    for o in base_meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
        xf = m_fix @ mw
        for v in o.data.vertices:
            v.co = xf @ v.co
        o.data.update()

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
            d = eb.tail - eb.head
            if d.length < 1e-6:
                d = Vector((0, 0, 1))
            eb.tail = eb.head + d.normalized() * 0.035
        eb.roll = roll

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

    hand_r = ebones["Hand.R"]
    wb_r = ebones.new("Weapon_R")
    wb_r.head = hand_r.head + Vector((-0.042, -0.008, -0.014))
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

    for o in base_meshes:
        o.parent = arm
        o.matrix_parent_inverse = Matrix.Identity(4)
        for m in list(o.modifiers):
            if m.type == "ARMATURE":
                m.object = arm

    bpy.context.view_layer.update()
    return arm, swat_body, swat_legs, swat_feet


def build_sculpted_blender_studio_head(arm, pal):
    """Append CC0 Blender Studio 'GEO-body_male_stylized' head + real 3D eyes, fit cleanly onto Neck/Head!"""
    names_to_load = ["GEO-body_male_stylized", "GEO-body_male_stylized.eye.L", "GEO-body_male_stylized.eye.R"]
    with bpy.data.libraries.load(BLENDER_STUDIO_BLEND, link=False) as (data_from, data_to):
        data_to.objects = [n for n in names_to_load if n in data_from.objects]

    loaded = {}
    for o in data_to.objects:
        if o is not None:
            bpy.context.collection.objects.link(o)
            loaded[o.name] = o

    src_body = loaded["GEO-body_male_stylized"]
    eye_l = loaded["GEO-body_male_stylized.eye.L"]
    eye_r = loaded["GEO-body_male_stylized.eye.R"]
    bpy.context.view_layer.update()

    # Exact alignment transform: center X at -0.2705 (midline of eye.L/R!), match Shaoyu head height & neck seat
    eye_l_pts = [eye_l.matrix_world @ v.co for v in eye_l.data.vertices]
    eye_r_pts = [eye_r.matrix_world @ v.co for v in eye_r.data.vertices]
    mid_x = 0.5 * (sum(p.x for p in eye_l_pts) / len(eye_l_pts) + sum(p.x for p in eye_r_pts) / len(eye_r_pts))
    eye_z_src = sum(p.z for p in eye_l_pts) / len(eye_l_pts)
    body_pts = [src_body.matrix_world @ v.co for v in src_body.data.vertices]
    top_z_src = max(p.z for p in body_pts)
    # Athletic teen hero proportions (head_scale=0.86 -> crisp 1:6.6 head-to-body ratio, centered over Neck/Head!)
    head_scale = 0.86
    neck_bone_head = arm.data.bones["Neck"].head_local  # (0, +0.016, 1.426)
    head_bone_head = arm.data.bones["Head"].head_local  # (0, +0.016, 1.498)
    target_top_z = 1.744
    target_y_shift = head_bone_head.y + 0.008

    def xform_pt(p: Vector) -> Vector:
        return Vector((
            (p.x - mid_x) * head_scale,
            (p.y - (-0.025)) * head_scale + target_y_shift,
            (p.z - top_z_src) * head_scale + target_top_z,
        ))

    # Pre-compute transformed eyeball centers for precise facial refinement
    eye_l_xformed = [xform_pt(p) for p in eye_l_pts]
    eye_r_xformed = [xform_pt(p) for p in eye_r_pts]
    eye_l_c = sum(eye_l_xformed, Vector((0, 0, 0))) / len(eye_l_xformed)
    eye_r_c = sum(eye_r_xformed, Vector((0, 0, 0))) / len(eye_r_xformed)
    eye_center_z = 0.5 * (eye_l_c.z + eye_r_c.z)
    eye_front_y = min(min(p.y for p in eye_l_xformed), min(p.y for p in eye_r_xformed))
    eye_l_cx = eye_l_c.x
    eye_r_cx = eye_r_c.x

    # Slice head + upper neck smoothly from GEO-body_male_stylized (keep z_src > top_z_src - 0.365)
    cut_z_src = top_z_src - 0.362
    mw_b = src_body.matrix_world.copy()
    bm = bmesh.new()
    bm.from_mesh(src_body.data)
    bm.verts.ensure_lookup_table()
    del_verts = []
    for v in bm.verts:
        wp = mw_b @ v.co
        if wp.z < cut_z_src or abs(wp.x - mid_x) > 0.145:
            del_verts.append(v)
        else:
            pt = xform_pt(wp)
            # Youthful East Asian nose & jaw refinement (slim broad cartoon nose bulb gently!)
            if abs(pt.x) < 0.024 and pt.y < eye_front_y - 0.004 and (eye_center_z - 0.040) < pt.z < (eye_center_z - 0.004):
                w_nose = max(0.0, 1.0 - abs(pt.x) / 0.024)
                pt.x *= (1.0 - 0.24 * w_nose)
                pt.y += 0.0045 * w_nose
            v.co = pt
    bmesh.ops.delete(bm, geom=del_verts, context="VERTS")
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True

    head_me = bpy.data.meshes.new("Shaoyu_Head_Mesh")
    bm.to_mesh(head_me)
    bm.free()
    head_obj = bpy.data.objects.new("Shaoyu_Head", head_me)
    bpy.context.collection.objects.link(head_obj)
    # Clean gentle decimate (ratio=0.58) keeps EVERY nose/nostril/eyelid/lip/ear detail razor-sharp!
    bpy.ops.object.select_all(action="DESELECT")
    head_obj.select_set(True)
    bpy.context.view_layer.objects.active = head_obj
    dec = head_obj.modifiers.new("CleanDecimate", "DECIMATE")
    dec.ratio = 0.58
    dec.use_symmetry = True
    dec.symmetry_axis = "X"
    bpy.ops.object.modifier_apply(modifier=dec.name)
    for p in head_obj.data.polygons:
        p.use_smooth = True

    # Assign clean seamless sculpted skin across the whole head (zero polygonal lip-seam rectangle!)
    head_obj.data.materials.clear()
    head_obj.data.materials.append(pal["skin"])
    for p in head_obj.data.polygons:
        p.material_index = 0

    # Weight Shaoyu_Head smoothly to Head + Neck + Chest transition
    vg_head = head_obj.vertex_groups.new(name="Head")
    vg_neck = head_obj.vertex_groups.new(name="Neck")
    vg_chest = head_obj.vertex_groups.new(name="Chest")
    for v in head_obj.data.vertices:
        z = v.co.z
        if z >= 1.505:
            vg_head.add([v.index], 1.0, "REPLACE")
        elif z >= 1.445:
            t = (z - 1.445) / 0.060
            vg_head.add([v.index], t, "REPLACE")
            vg_neck.add([v.index], 1.0 - t, "REPLACE")
        else:
            t = max(0.0, min(1.0, (z - 1.405) / 0.040))
            vg_neck.add([v.index], t, "REPLACE")
            vg_chest.add([v.index], 1.0 - t, "REPLACE")
    head_obj.parent = arm
    mod = head_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

    # Build Crisp Expressive 3D Stylized Eyes (sclera + rich chestnut iris + jet-black pupil + upper lash line + catchlights!)
    bm_e = bmesh.new()
    e_mats = [pal["sclera"], pal["iris"], pal["pupil"], pal["eye_catch"], pal["eyebrow"]]
    for ec in (eye_l_c, eye_r_c):
        cx = ec.x
        eyeball_c = Vector((cx, ec.y - 0.001, ec.z))
        evs = add_sphere_mesh(bm_e, eyeball_c, (0.0146, 0.0146, 0.0146), segs=20, rings=14, mat_idx=0)
        for f in {f for v in evs for f in v.link_faces}:
            d = (f.calc_center_median() - eyeball_c).normalized()
            if d.y < -0.70:
                dist_axis = math.sqrt(d.x * d.x + d.z * d.z)
                if dist_axis < 0.28:
                    f.material_index = 2  # crisp jet-black pupil
                elif dist_axis < 0.56:
                    f.material_index = 1  # rich warm chestnut iris!
        # Crisp bright specular catchlight glint (upper-left of iris!)
        add_sphere_mesh(bm_e, (cx + 0.0036, eyeball_c.y - 0.0145, ec.z + 0.0036), (0.0024, 0.0016, 0.0024), segs=8, rings=6, mat_idx=3)
        # Subtle dark upper eyelid lashline arc for instant expressive "有神" readability!
        sgn = 1.0 if cx > 0 else -1.0
        lash_pts = [
            (cx - sgn * 0.011, eyeball_c.y - 0.0135, ec.z + 0.0055),
            (cx, eyeball_c.y - 0.0155, ec.z + 0.0095),
            (cx + sgn * 0.013, eyeball_c.y - 0.0115, ec.z + 0.0050),
        ]
        add_ribbon_strip(bm_e, lash_pts, [0.0035, 0.0042, 0.0032], [0.0032, 0.0038, 0.0030], mat_idx=4)
        # Sculpted confident teen eyebrows cleanly arcing ABOVE the goggle top rim!
        brow_pts = [
            (sgn * 0.012, eye_front_y - 0.007, eye_center_z + 0.023),
            (sgn * 0.032, eye_front_y - 0.006, eye_center_z + 0.027),
            (sgn * 0.050, eye_front_y + 0.002, eye_center_z + 0.023),
        ]
        add_ribbon_strip(bm_e, brow_pts, [0.0075, 0.0072, 0.0038], [0.0055, 0.0055, 0.0038], mat_idx=4)

    eyes_obj = make_weighted_object("Shaoyu_EyesBrows", bm_e, e_mats, arm, lambda _p: {"Head": 1.0})

    # Delete temporary Blender Studio source objects
    for o in loaded.values():
        bpy.data.objects.remove(o, do_unlink=True)

    # Measure final sculpted head bounds
    hpts = [v.co for v in head_obj.data.vertices]
    hinfo = {
        "z_min": min(p.z for p in hpts),
        "z_max": max(p.z for p in hpts),
        "y_min": min(p.y for p in hpts),
        "y_max": max(p.y for p in hpts),
        "x_max": max(abs(p.x) for p in hpts),
        "eye_z": eye_center_z,
        "eye_y": eye_front_y,
        "eye_l_x": eye_l_cx,
        "eye_r_x": eye_r_cx,
    }
    print(f"SCULPTED_HEAD_FIT: verts={len(head_obj.data.vertices)} polys={len(head_obj.data.polygons)} z=[{hinfo['z_min']:.3f},{hinfo['z_max']:.3f}] y=[{hinfo['y_min']:.3f},{hinfo['y_max']:.3f}] eye_z={eye_center_z:.3f} eye_y={eye_front_y:.3f}")
    return head_obj, eyes_obj, hinfo


# ---------------------------------------------------------------------------
# Step 2: Subsurf-Smooth Body, Sculpt Full Hair, Plan B Goggles, Gear & Closed 1P Waist!
# ---------------------------------------------------------------------------
def customize_shaoyu_appearance(arm, swat_body, swat_legs, swat_feet, head_obj, eyes_obj, hinfo, pal):
    # 1. Assign material zones on Swat_Body BEFORE subsurf so Catmull-Clark subdivides smoothly along clean borders!
    orig_body_ids = [p.material_index for p in swat_body.data.polygons]
    orig_names = [m.name if m else "" for m in swat_body.data.materials]
    idx_black = next((i for i, n in enumerate(orig_names) if "Black" in n), 0)
    idx_skin = next((i for i, n in enumerate(orig_names) if "Skin" in n), 1)
    sb_mats = [pal["vest"], pal["skin"], pal["jacket"], pal["glove"], pal["wrap"], pal["jacket_trim"]]
    swat_body.data.materials.clear()
    for m in sb_mats:
        swat_body.data.materials.append(m)
    for poly, orig_i in zip(swat_body.data.polygons, orig_body_ids):
        c = poly.center
        ax = abs(c.x)
        if orig_i == idx_skin:
            poly.material_index = 1
        elif orig_i == idx_black:
            if ax > 0.44:
                poly.material_index = 3
            elif c.z < 1.045:
                poly.material_index = 5
            elif c.y > -0.025:
                poly.material_index = 2
            else:
                poly.material_index = 0
        else:
            if ax > 0.415 and ax < 0.505:
                poly.material_index = 4
            elif ax > 0.350 and ax <= 0.415:
                poly.material_index = 1
            elif c.z < 1.035:
                poly.material_index = 5
            else:
                poly.material_index = 2

    orig_leg_ids = [p.material_index for p in swat_legs.data.polygons]
    leg_orig = [m.name if m else "" for m in swat_legs.data.materials]
    l_black = next((i for i, n in enumerate(leg_orig) if "Black" in n), 0)
    swat_legs.data.materials.clear()
    swat_legs.data.materials.append(pal["kneepad"])
    swat_legs.data.materials.append(pal["pants"])
    for poly, orig_i in zip(swat_legs.data.polygons, orig_leg_ids):
        poly.material_index = 0 if orig_i == l_black else 1

    swat_feet.data.materials.clear()
    swat_feet.data.materials.append(pal["boot_leather"])
    swat_feet.data.materials.append(pal["boot_sole"])

    # 2. Weld + Catmull-Clark Subdivision Level 1 on Body, Legs & Boots (silky-smooth Valorant/Overwatch surfaces!)
    weld_and_subsurf(swat_body, merge_dist=0.00035, subsurf_level=1, smooth_iters=1, smooth_fac=0.14)
    weld_and_subsurf(swat_legs, merge_dist=0.00035, subsurf_level=1, smooth_iters=1, smooth_fac=0.14)
    weld_and_subsurf(swat_feet, merge_dist=0.00035, subsurf_level=1, smooth_iters=1, smooth_fac=0.10)
    # Assign dark rubber boot sole AFTER subdivision for razor-clean non-jagged sole trim!
    for poly in swat_feet.data.polygons:
        poly.material_index = 1 if poly.center.z < 0.030 else 0

    # -----------------------------------------------------------------------
    # Form-Fitting Scalp Hair Shell (ZERO BALD SPOTS 360 deg!) + Lush Layered Swept Anime Hair + Sleek Plan B Goggles + Headset
    # -----------------------------------------------------------------------
    bm_h = bmesh.new()
    h_mats = [pal["hair"], pal["goggle_frame"], pal["goggle_lens"], pal["headset"], pal["radio_led"]]

    head_top = hinfo["z_max"]
    head_y_max = hinfo["y_max"]
    eye_z = hinfo["eye_z"]
    eye_y = hinfo["eye_y"]
    head_cy = 0.5 * (eye_y + head_y_max)

    # 1. Exact Form-Fitting Scalp Shell extruded from actual head_obj cranium/occiput/temple polygons!
    #    Guarantees 100% seamless full hair coverage from front, sides, top AND rear 3P view!
    bm_scalp = bmesh.new()
    bm_scalp.from_mesh(head_obj.data)
    bm_scalp.verts.ensure_lookup_table()
    bm_scalp.faces.ensure_lookup_table()
    keep_faces = set()
    for f in bm_scalp.faces:
        c = f.calc_center_median()
        # Exclude ears (sticking out wide at |x| > 0.072 & eye_z - 0.032 < z < eye_z + 0.015)
        is_ear = (abs(c.x) > 0.070 and (eye_z - 0.038) < c.z < (eye_z + 0.018) and abs(c.y - head_cy) < 0.038)
        if is_ear:
            continue
        # Crown + forehead hairline (above brow) + temples + FULL rear skull & nape!
        in_crown = c.z > (eye_z + 0.032)
        in_back = (c.y > head_cy - 0.008) and (c.z > eye_z - 0.088)
        in_temple = (abs(c.x) > 0.056) and (c.y > eye_y + 0.022) and (c.z > eye_z - 0.008)
        if in_crown or in_back or in_temple:
            keep_faces.add(f)
    del_f = [f for f in bm_scalp.faces if f not in keep_faces]
    bmesh.ops.delete(bm_scalp, geom=del_f, context="FACES")
    bm_scalp.normal_update()
    # Smooth & puff scalp shell outward 1.3..2.0cm along vertex normals to give lush stylized hair volume!
    for _ in range(2):
        bmesh.ops.smooth_vert(bm_scalp, verts=list(bm_scalp.verts), factor=0.35, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm_scalp.normal_update()
    for v in bm_scalp.verts:
        thick = 0.018 if v.co.z > eye_z + 0.055 else (0.015 if v.co.y > head_cy else 0.012)
        v.co += v.normal * thick
    # Give the scalp shell clean thickness via solidify extrude inward slightly so edges never look paper-thin
    res_ext = bmesh.ops.extrude_face_region(bm_scalp, geom=list(bm_scalp.faces))
    ext_verts = [g for g in res_ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    for v in ext_verts:
        v.co -= v.normal * 0.012
    for f in bm_scalp.faces:
        f.material_index = 0
        f.smooth = True
    # Merge scalp shell cleanly into bm_h
    scalp_tmp = bpy.data.meshes.new("_scalp_tmp")
    bm_scalp.to_mesh(scalp_tmp)
    bm_scalp.free()
    bm_h.from_mesh(scalp_tmp)
    bpy.data.meshes.remove(scalp_tmp)

    # 2. 16 Bold Stylized Anime Hair Locks (swept forehead bangs, sideburns, windswept crown spikes, layered nape!)
    hair_locks = [
        # Swept forehead bangs arching right above the amber goggles (clean gap over eyes!)
        ([(0.010, head_cy - 0.032, head_top + 0.008), (-0.010, eye_y - 0.022, head_top - 0.026), (-0.026, eye_y - 0.036, eye_z + 0.026)], [0.048, 0.036, 0.008], [0.022, 0.016, 0.006]),
        ([(-0.022, head_cy - 0.028, head_top + 0.004), (-0.050, eye_y - 0.014, head_top - 0.032), (-0.064, eye_y - 0.024, eye_z + 0.020)], [0.044, 0.032, 0.007], [0.020, 0.014, 0.006]),
        ([(0.030, head_cy - 0.028, head_top + 0.004), (0.054, eye_y - 0.012, head_top - 0.030), (0.068, eye_y - 0.020, eye_z + 0.020)], [0.044, 0.032, 0.007], [0.020, 0.014, 0.006]),
        ([(-0.004, head_cy - 0.038, head_top - 0.006), (0.016, eye_y - 0.026, head_top - 0.038), (0.026, eye_y - 0.034, eye_z + 0.024)], [0.038, 0.028, 0.007], [0.018, 0.012, 0.005]),
        # Cheekbone sideburns in front of ears
        ([(-0.072, head_cy - 0.024, eye_z + 0.032), (-0.076, eye_y + 0.022, eye_z - 0.004), (-0.068, eye_y + 0.014, eye_z - 0.032)], [0.024, 0.018, 0.005], [0.012, 0.009, 0.004]),
        ([(0.072, head_cy - 0.024, eye_z + 0.032), (0.076, eye_y + 0.022, eye_z - 0.004), (0.068, eye_y + 0.014, eye_z - 0.032)], [0.024, 0.018, 0.005], [0.012, 0.009, 0.004]),
        # Dynamic swept-back hero crown spikes (clean tapered anime silhouette, matching Shaoyu's portrait!)
        ([(0.000, head_cy - 0.018, head_top + 0.004), (0.018, head_cy + 0.025, head_top + 0.032), (0.036, head_y_max + 0.006, head_top + 0.022)], [0.056, 0.040, 0.009], [0.026, 0.018, 0.007]),
        ([(-0.038, head_cy - 0.012, head_top - 0.002), (-0.062, head_cy + 0.026, head_top + 0.020), (-0.078, head_y_max - 0.002, head_top + 0.004)], [0.048, 0.034, 0.008], [0.022, 0.015, 0.006]),
        ([(0.040, head_cy - 0.012, head_top - 0.002), (0.064, head_cy + 0.024, head_top + 0.018), (0.080, head_y_max - 0.004, head_top + 0.002)], [0.048, 0.034, 0.008], [0.022, 0.015, 0.006]),
        ([(-0.014, head_cy + 0.008, head_top + 0.010), (-0.028, head_y_max - 0.010, head_top + 0.016), (-0.042, head_y_max + 0.024, head_top - 0.018)], [0.052, 0.038, 0.009], [0.024, 0.016, 0.006]),
        # Rich overlapping layered rear & nape tufts (full dynamic anime back hair!)
        ([(0.000, head_y_max - 0.018, head_top - 0.028), (0.004, head_y_max + 0.024, eye_z + 0.016), (0.006, head_y_max + 0.022, eye_z - 0.064)], [0.078, 0.064, 0.018], [0.026, 0.020, 0.008]),
        ([(-0.048, head_y_max - 0.028, head_top - 0.042), (-0.068, head_y_max + 0.010, eye_z + 0.002), (-0.060, head_y_max + 0.006, eye_z - 0.072)], [0.062, 0.050, 0.015], [0.022, 0.016, 0.007]),
        ([(0.048, head_y_max - 0.028, head_top - 0.042), (0.068, head_y_max + 0.010, eye_z + 0.002), (0.060, head_y_max + 0.006, eye_z - 0.072)], [0.062, 0.050, 0.015], [0.022, 0.016, 0.007]),
        ([(0.000, head_y_max - 0.008, eye_z - 0.012), (0.000, head_y_max + 0.012, eye_z - 0.058), (0.000, head_y_max - 0.002, eye_z - 0.105)], [0.094, 0.076, 0.022], [0.022, 0.016, 0.008]),
        ([(-0.042, head_y_max - 0.016, eye_z - 0.028), (-0.052, head_y_max + 0.004, eye_z - 0.072), (-0.042, head_y_max - 0.008, eye_z - 0.108)], [0.048, 0.036, 0.012], [0.016, 0.012, 0.006]),
        ([(0.042, head_y_max - 0.016, eye_z - 0.028), (0.052, head_y_max + 0.004, eye_z - 0.072), (0.042, head_y_max - 0.008, eye_z - 0.108)], [0.048, 0.036, 0.012], [0.016, 0.012, 0.006]),
    ]
    for pts, ws, ts in hair_locks:
        add_ribbon_strip(bm_h, pts, ws, ts, mat_idx=0)

    # Plan B Sleek Sporty Wrap-Around Crystal-Amber Tactical Goggles (matching Shaoyu's portrait!)
    gz = eye_z + 0.000
    gy = eye_y - 0.018
    for side in (-1.0, 1.0):
        rot_g = (0.0, 0.0, side * 0.22)
        cx_g = side * 0.033
        # Sleek low-profile open-rim visor frame (NO bulky center vertical pillars blocking his eyes!)
        add_box_mesh(bm_h, (cx_g, gy + 0.005, gz + 0.017), (0.056, 0.018, 0.0055), rot_g, mat_idx=1, bevel=0.0018)
        add_box_mesh(bm_h, (cx_g, gy + 0.005, gz - 0.016), (0.052, 0.018, 0.0050), rot_g, mat_idx=1, bevel=0.0018)
        add_box_mesh(bm_h, (cx_g + side * 0.027, gy + 0.010, gz), (0.007, 0.020, 0.035), rot_g, mat_idx=1, bevel=0.0018)
        # Ultra-clear warm crystal-amber translucent lens (alpha=0.26 -> chestnut eyes & catchlights shine clearly!)
        add_box_mesh(bm_h, (cx_g, gy - 0.001, gz), (0.052, 0.0022, 0.029), rot_g, mat_idx=2, bevel=0.0008)
        # Sleek swept temple hinge wrapping back toward headset
        add_box_mesh(bm_h, (side * 0.068, gy + 0.022, gz + 0.001), (0.016, 0.018, 0.020), (0.0, 0.0, side * 0.58), mat_idx=1, bevel=0.0025)
    # Sleek center nose bridge bar (curved right above nose bridge)
    add_box_mesh(bm_h, (0.0, gy - 0.001, gz + 0.013), (0.022, 0.012, 0.007), (0, 0, 0), mat_idx=1, bevel=0.0018)
    strap_pts = []
    for k in range(13):
        ang = math.radians(-165 + k * (330.0 / 12.0))
        rx = (hinfo["x_max"] * 0.96) * math.sin(ang)
        ry = head_cy + (head_y_max - head_cy + 0.018) * math.cos(ang)
        if ry > gy + 0.016:
            strap_pts.append((rx, ry, gz + 0.004))
    if len(strap_pts) >= 3:
        add_ribbon_strip(bm_h, strap_pts, [0.018] * len(strap_pts), [0.006] * len(strap_pts), mat_idx=1)

    # Single-Ear Tactical Comms Headset (Left ear = +X, cleanly fitted onto sculpted head!)
    ear_x = hinfo["x_max"] * 0.94
    ear_y = head_cy - 0.004
    ear_z = eye_z - 0.012
    add_cyl_mesh(bm_h, (ear_x, ear_y, ear_z), 0.025, 0.022, 0.018, segs=14, rot_euler=(0, math.pi * 0.5, 0), mat_idx=3)
    add_box_mesh(bm_h, (ear_x + 0.008, ear_y - 0.002, ear_z), (0.009, 0.020, 0.030), (0, 0, 0), mat_idx=3, bevel=0.0025)
    hb_pts = [
        (ear_x, ear_y, ear_z + 0.018),
        (ear_x - 0.006, ear_y + 0.004, head_top - 0.028),
        (0.042, ear_y + 0.004, head_top + 0.020),
        (-0.042, ear_y + 0.004, head_top + 0.020),
        (-(ear_x - 0.006), ear_y + 0.004, head_top - 0.038),
    ]
    add_ribbon_strip(bm_h, hb_pts, [0.012] * len(hb_pts), [0.005] * len(hb_pts), mat_idx=3)
    mic_pts = [
        (ear_x + 0.004, ear_y - 0.014, ear_z - 0.012),
        (ear_x - 0.010, eye_y + 0.005, ear_z - 0.032),
        (0.048, eye_y - 0.022, ear_z - 0.044),
        (0.024, eye_y - 0.030, ear_z - 0.046),
    ]
    add_ribbon_strip(bm_h, mic_pts, [0.005, 0.0045, 0.0045, 0.009], [0.005, 0.0045, 0.0045, 0.009], mat_idx=3)
    add_sphere_mesh(bm_h, (ear_x + 0.012, ear_y - 0.006, ear_z + 0.006), (0.0035, 0.0035, 0.0035), segs=8, rings=6, mat_idx=4)

    head_gear_obj = make_weighted_object("Shaoyu_HeadGear", bm_h, h_mats, arm, lambda _p: {"Head": 1.0})

    # -----------------------------------------------------------------------
    # Sculpted Tactical Chest Rig + Rolled Cuffs + Bronze Knuckles + Cloud Patch + Scarf
    # -----------------------------------------------------------------------
    bm_u = bmesh.new()
    u_mats = [pal["vest"], pal["pouch"], pal["strap_tan"], pal["bronze"], pal["radio_led"], pal["jacket"], pal["wrap"], pal["patch"], pal["scarf"], pal["jacket_trim"]]

    for mx in (-0.064, 0.0, 0.064):
        add_box_mesh(bm_u, (mx, -0.145, 1.155), (0.052, 0.042, 0.118), (0.04, 0, 0), mat_idx=1, bevel=0.006)
        add_box_mesh(bm_u, (mx, -0.162, 1.198), (0.046, 0.014, 0.032), (0.04, 0, 0), mat_idx=0, bevel=0.003)
        add_box_mesh(bm_u, (mx, -0.168, 1.158), (0.016, 0.010, 0.056), (0.04, 0, 0), mat_idx=2, bevel=0.002)

    add_box_mesh(bm_u, (0.0, -0.136, 1.268), (0.195, 0.026, 0.098), (0.05, 0, 0), mat_idx=0, bevel=0.005)
    for wz in (1.240, 1.268, 1.296):
        add_box_mesh(bm_u, (0.0, -0.150, wz), (0.175, 0.008, 0.011), (0.05, 0, 0), mat_idx=1, bevel=0.001)

    add_box_mesh(bm_u, (-0.088, -0.148, 1.280), (0.042, 0.032, 0.084), (0.05, 0, 0.08), mat_idx=0, bevel=0.004)
    add_box_mesh(bm_u, (-0.088, -0.165, 1.296), (0.026, 0.005, 0.020), (0.05, 0, 0.08), mat_idx=4, bevel=0.001)
    add_cyl_mesh(bm_u, (-0.098, -0.148, 1.368), 0.0045, 0.003, 0.105, segs=8, mat_idx=0)

    for sx in (-0.095, 0.095):
        add_box_mesh(bm_u, (sx, -0.098, 1.368), (0.046, 0.032, 0.112), (0.42, 0, 0), mat_idx=0, bevel=0.004)
        add_box_mesh(bm_u, (sx, -0.132, 1.318), (0.036, 0.016, 0.026), (0.12, 0, 0), mat_idx=2, bevel=0.002)
    for sx in (-0.156, 0.156):
        add_box_mesh(bm_u, (sx, 0.010, 1.150), (0.018, 0.185, 0.056), (0, 0, 0), mat_idx=0, bevel=0.004)
        add_box_mesh(bm_u, (sx, 0.010, 1.150), (0.022, 0.052, 0.026), (0, 0, 0), mat_idx=2, bevel=0.002)

    add_box_mesh(bm_u, (0.0, -0.126, 1.035), (0.016, 0.018, 0.125), (0, 0, 0), mat_idx=9, bevel=0.002)

    for sx in (-1.0, 1.0):
        add_cyl_mesh(bm_u, (sx * 0.345, -0.006, 1.352), 0.054, 0.056, 0.048, segs=16, rot_euler=(0, math.pi * 0.5, 0), mat_idx=5)
        for rx in (0.435, 0.462, 0.486):
            add_cyl_mesh(bm_u, (sx * rx, -0.012, 1.352), 0.044, 0.043, 0.022, segs=14, rot_euler=(0, math.pi * 0.5, 0), mat_idx=6)
        for ky_off in (-0.026, -0.009, 0.009, 0.026):
            add_sphere_mesh(bm_u, (sx * 0.592, -0.024 + ky_off, 1.374), (0.013, 0.0095, 0.011), segs=10, rings=7, mat_idx=3)
        add_box_mesh(bm_u, (sx * 0.590, -0.024, 1.370), (0.024, 0.068, 0.010), (0, 0, 0), mat_idx=3, bevel=0.003)

    p_verts = add_box_mesh(bm_u, (0.242, -0.004, 1.366), (0.014, 0.066, 0.066), (0, 0.20, 0), mat_idx=7, bevel=0.003)
    uv_layer = bm_u.loops.layers.uv.verify()
    for f in {f for v in p_verts for f in v.link_faces}:
        for loop in f.loops:
            co = loop.vert.co
            u_coord = 0.5 + (co.y - (-0.004)) / 0.072
            v_coord = 0.5 + (co.z - 1.366) / 0.072
            loop[uv_layer].uv = (max(0.0, min(1.0, u_coord)), max(0.0, min(1.0, v_coord)))

    collar_pts_1, collar_pts_2 = [], []
    for k in range(17):
        ang = math.radians(k * (360.0 / 16.0))
        collar_pts_1.append((0.098 * math.sin(ang), 0.005 + 0.104 * math.cos(ang), 1.425 + 0.012 * math.cos(ang * 2.0) - 0.016 * max(0.0, -math.cos(ang))))
        collar_pts_2.append((0.088 * math.sin(ang), 0.004 + 0.094 * math.cos(ang), 1.468 + 0.008 * math.sin(ang * 2.0) - 0.010 * max(0.0, -math.cos(ang))))
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
    # Closed 1P Waist-Hem Cap + Tactical Belt + Bronze Buckle (ALWAYS VISIBLE IN 1P & 3P -> ZERO HOLLOW PELVIS!)
    # -----------------------------------------------------------------------
    bm_w = bmesh.new()
    w_mats = [pal["jacket_trim"], pal["vest"], pal["bronze"], pal["pouch"]]
    # Closed dark bamboo-teal jacket waist hem ring smoothly capping top of cargo pants!
    add_cyl_mesh(bm_w, (0.0, 0.002, 1.010), 0.150, 0.140, 0.075, segs=20, mat_idx=0)
    # Matte charcoal tactical duty belt wrapping waist
    add_cyl_mesh(bm_w, (0.0, 0.002, 0.985), 0.156, 0.156, 0.042, segs=20, mat_idx=1)
    # Sculpted front bronze tactical belt buckle + 2 compact hip pouches
    add_box_mesh(bm_w, (0.0, -0.148, 0.985), (0.056, 0.024, 0.044), (0, 0, 0), mat_idx=2, bevel=0.004)
    add_box_mesh(bm_w, (-0.158, -0.020, 0.970), (0.036, 0.078, 0.072), (0, 0, 0), mat_idx=3, bevel=0.005)
    add_box_mesh(bm_w, (0.158, -0.020, 0.970), (0.036, 0.078, 0.072), (0, 0, 0), mat_idx=3, bevel=0.005)
    # Sculpted boot lace cross-straps on lower boots for high-detail 1P look-down!
    for sx in (-0.114, 0.114):
        for lz in (0.095, 0.125, 0.155, 0.185):
            add_box_mesh(bm_w, (sx, -0.078, lz), (0.042, 0.012, 0.009), (0, 0, 0), mat_idx=1, bevel=0.002)

    def waist_and_lace_weights(co: Vector):
        if co.z < 0.30:
            return {"Foot.L" if co.x > 0 else "Foot.R": 0.45, "LowerLeg.L" if co.x > 0 else "LowerLeg.R": 0.55}
        return {"Hips": 0.72, "Abdomen": 0.28}

    lower_waist_obj = make_weighted_object("Shaoyu_LowerWaist", bm_w, w_mats, arm, waist_and_lace_weights)

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
    tail_w = [0.096, 0.112, 0.122, 0.126, 0.120, 0.104, 0.082, 0.040]
    tail_t = [0.017, 0.015, 0.014, 0.013, 0.012, 0.011, 0.010, 0.008]
    add_ribbon_strip(bm_s, tail_pts, tail_w, tail_t, mat_idx=0, fixed_side=(0.94, -0.34, 0.0))

    def scarf_tail_weights(co: Vector):
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
    # Sleek Compact Ergonomic Mountain-Ranger Daypack
    # -----------------------------------------------------------------------
    bm_p = bmesh.new()
    p_mats = [pal["pack_main"], pal["pack_olive"], pal["strap_tan"], pal["bronze"]]
    add_box_mesh(bm_p, (0.0, 0.140, 1.235), (0.215, 0.092, 0.305), (-0.06, 0, 0), mat_idx=0, bevel=0.024)
    add_box_mesh(bm_p, (0.0, 0.132, 1.375), (0.185, 0.078, 0.072), (-0.18, 0, 0), mat_idx=1, bevel=0.018)
    add_cyl_mesh(bm_p, (0.0, 0.125, 1.418), 0.008, 0.008, 0.080, segs=8, rot_euler=(0, math.pi * 0.5, 0), mat_idx=2)
    add_box_mesh(bm_p, (0.0, 0.186, 1.195), (0.165, 0.036, 0.185), (-0.05, 0, 0), mat_idx=1, bevel=0.014)
    add_box_mesh(bm_p, (0.0, 0.205, 1.225), (0.022, 0.010, 0.265), (-0.05, 0.42, 0), mat_idx=2, bevel=0.002)
    add_box_mesh(bm_p, (0.0, 0.205, 1.225), (0.022, 0.010, 0.265), (-0.05, -0.42, 0), mat_idx=2, bevel=0.002)
    add_box_mesh(bm_p, (0.0, 0.210, 1.225), (0.032, 0.014, 0.036), (-0.05, 0, 0), mat_idx=3, bevel=0.003)
    add_cyl_mesh(bm_p, (-0.118, 0.145, 1.155), 0.028, 0.026, 0.125, segs=12, mat_idx=0)
    add_box_mesh(bm_p, (0.088, 0.155, 1.345), (0.026, 0.020, 0.032), (0, 0, 0.3), mat_idx=3, bevel=0.003)
    backpack_obj = make_weighted_object("Shaoyu_Backpack", bm_p, p_mats, arm, lambda p: {"Chest": 0.72, "Torso": 0.28} if p.z > 1.22 else {"Torso": 0.80, "Chest": 0.20})

    swat_body.name = "Shaoyu_UpperBody"
    swat_legs.name = "Shaoyu_LowerLegs"
    swat_feet.name = "Shaoyu_LowerBoots"

    return [head_obj, eyes_obj, head_gear_obj, swat_body, upper_gear_obj, scarf_tail_obj, backpack_obj, swat_legs, swat_feet, lower_waist_obj]


# ---------------------------------------------------------------------------
# Step 3: Exact World-Space Quaternion Retargeter + Zero-Twist IK Animations
# ---------------------------------------------------------------------------
UAL_BONE_MAP = {
    "Hips": "DEF-hips", "Abdomen": "DEF-spine.001", "Torso": "DEF-spine.002", "Chest": "DEF-spine.003",
    "Neck": "DEF-neck", "Head": "DEF-head",
    "Shoulder.L": "DEF-shoulder.L", "UpperArm.L": "DEF-upper_arm.L", "LowerArm.L": "DEF-forearm.L", "Hand.L": "DEF-hand.L",
    "Index2.L": "DEF-f_index.01.L", "Index3.L": "DEF-f_index.02.L", "Index4.L": "DEF-f_index.03.L",
    "Middle2.L": "DEF-f_middle.01.L", "Middle3.L": "DEF-f_middle.02.L", "Middle4.L": "DEF-f_middle.03.L",
    "Ring2.L": "DEF-f_ring.01.L", "Ring3.L": "DEF-f_ring.02.L", "Ring4.L": "DEF-f_ring.03.L",
    "Pinky2.L": "DEF-f_pinky.01.L", "Pinky3.L": "DEF-f_pinky.02.L", "Pinky4.L": "DEF-f_pinky.03.L",
    "Thumb2.L": "DEF-thumb.02.L", "Thumb3.L": "DEF-thumb.03.L",
    "Shoulder.R": "DEF-shoulder.R", "UpperArm.R": "DEF-upper_arm.R", "LowerArm.R": "DEF-forearm.R", "Hand.R": "DEF-hand.R",
    "Index2.R": "DEF-f_index.01.R", "Index3.R": "DEF-f_index.02.R", "Index4.R": "DEF-f_index.03.R",
    "Middle2.R": "DEF-f_middle.01.R", "Middle3.R": "DEF-f_middle.02.R", "Middle4.R": "DEF-f_middle.03.R",
    "Ring2.R": "DEF-f_ring.01.R", "Ring3.R": "DEF-f_ring.02.R", "Ring4.R": "DEF-f_ring.03.R",
    "Pinky2.R": "DEF-f_pinky.01.R", "Pinky3.R": "DEF-f_pinky.02.R", "Pinky4.R": "DEF-f_pinky.03.R",
    "Thumb2.R": "DEF-thumb.02.R", "Thumb3.R": "DEF-thumb.03.R",
    "UpperLeg.L": "DEF-thigh.L", "LowerLeg.L": "DEF-shin.L", "Foot.L": "DEF-foot.L",
    "UpperLeg.R": "DEF-thigh.R", "LowerLeg.R": "DEF-shin.R", "Foot.R": "DEF-foot.R",
}

KAYKIT_BONE_MAP = {
    "Hips": "hips", "Abdomen": "spine", "Chest": "chest", "Head": "head",
    "UpperArm.L": "upperarm.l", "LowerArm.L": "lowerarm.l", "Hand.L": "hand.l",
    "UpperArm.R": "upperarm.r", "LowerArm.R": "lowerarm.r", "Hand.R": "hand.r",
    "UpperLeg.L": "upperleg.l", "LowerLeg.L": "lowerleg.l", "Foot.L": "foot.l",
    "UpperLeg.R": "upperleg.r", "LowerLeg.R": "lowerleg.r", "Foot.R": "foot.r",
}


def topological_bone_order(arm):
    order, visited = [], set()
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
    before_objs, before_acts = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=src_path)
    src_objs = [o for o in bpy.data.objects if o not in before_objs]
    src_acts = [a for a in bpy.data.actions if a not in before_acts]
    src_arm = next(o for o in src_objs if o.type == "ARMATURE")

    src_arm_rot = src_arm.matrix_world.to_quaternion()
    dst_arm_rot = dst_arm.matrix_world.to_quaternion()
    src_rest_q = {b.name: (src_arm_rot @ b.matrix_local.to_quaternion()).normalized() for b in src_arm.data.bones}
    dst_rest_q = {b.name: (dst_arm_rot @ b.matrix_local.to_quaternion()).normalized() for b in dst_arm.data.bones}
    dst_local_rest_q = {
        b.name: ((b.parent.matrix_local.to_quaternion().inverted() @ b.matrix_local.to_quaternion()).normalized() if b.parent else b.matrix_local.to_quaternion().normalized())
        for b in dst_arm.data.bones
    }

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
        src_act = next((a for a in src_acts if a.name == src_name or a.name.endswith("|" + src_name) or a.name.startswith(src_name + ".")), None)
        if src_act is None:
            continue
        src_arm.animation_data.action = src_act
        f_start, f_end = int(round(src_act.frame_range[0])), int(round(src_act.frame_range[1]))
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
                    if bname in prev_quats and prev_quats[bname].dot(local_q) < 0.0:
                        local_q = -local_q
                    prev_quats[bname] = local_q.copy()
                    pb.rotation_quaternion = local_q
                    dst_posed_world_q[bname] = target_world_q
                    pb.keyframe_insert(data_path="rotation_quaternion", frame=out_frame)
                else:
                    pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
                    dst_posed_world_q[bname] = (parent_world_q @ dst_local_rest_q[bname]).normalized()

            sh_pb = src_arm.pose.bones[src_hips_name]
            src_hips_cur_w = src_arm.matrix_world @ sh_pb.head
            delta_w = (src_hips_cur_w - src_hips_rest_w) * hip_scale
            delta_w.x = max(-0.08, min(0.08, delta_w.x))
            delta_w.y = max(-0.08, min(0.08, delta_w.y))
            dst_hips_pb = dst_arm.pose.bones["Hips"]
            dst_hips_pb.location = dst_hips_rest_mat_inv @ delta_w
            dst_hips_pb.keyframe_insert(data_path="location", frame=out_frame)

        created_actions.append(dst_act)
        print(f"  RETARGETED: {src_name} -> {dst_name} ({len(frames)} keys)")

    for o in src_objs:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in src_acts:
        if a.name in bpy.data.actions and a.users == 0:
            bpy.data.actions.remove(a)
    return created_actions


def set_bone_world_delta(arm, bname, euler_xyz_deg):
    pb = arm.pose.bones[bname]
    pb.rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()
    parent_wq = pb.parent.matrix.to_quaternion() if pb.parent else Quaternion((1, 0, 0, 0))
    local_rest = (pb.bone.parent.matrix_local.to_quaternion().inverted() @ pb.bone.matrix_local.to_quaternion()) if pb.bone.parent else pb.bone.matrix_local.to_quaternion()
    rest_wq = pb.bone.matrix_local.to_quaternion()
    delta_wq = Euler(tuple(math.radians(a) for a in euler_xyz_deg), "XYZ").to_quaternion()
    target_wq = (delta_wq @ rest_wq).normalized()
    expected_wq = (parent_wq @ local_rest).normalized()
    pb.rotation_quaternion = (expected_wq.inverted() @ target_wq).normalized()


def aim_bone_at_world_dir(arm, bname, target_dir_world, up_hint_world=None, align_local_axis="Z"):
    """Rotate bone so +Y aligns cleanly with target_dir_world and align_local_axis aligns with up_hint_world (ZERO gimbal twist!)."""
    pb = arm.pose.bones[bname]
    pb.rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()
    cur_mat = pb.matrix.to_3x3()
    cur_y = (cur_mat @ Vector((0, 1, 0))).normalized()
    tgt = target_dir_world.normalized()
    rot_q = cur_y.rotation_difference(tgt)
    new_world_q = (rot_q @ pb.matrix.to_quaternion()).normalized()
    if up_hint_world is not None:
        ref_vec = Vector((0, 0, 1)) if align_local_axis == "Z" else (Vector((1, 0, 0)) if align_local_axis == "X" else Vector((0, 0, -1)))
        cur_up = (new_world_q @ ref_vec).normalized()
        proj_cur = cur_up - tgt * cur_up.dot(tgt)
        proj_hint = up_hint_world - tgt * up_hint_world.dot(tgt)
        if proj_cur.length > 1e-4 and proj_hint.length > 1e-4:
            twist = proj_cur.normalized().rotation_difference(proj_hint.normalized())
            new_world_q = (twist @ new_world_q).normalized()
    parent_wq = pb.parent.matrix.to_quaternion() if pb.parent else Quaternion((1, 0, 0, 0))
    local_rest = (pb.bone.parent.matrix_local.to_quaternion().inverted() @ pb.bone.matrix_local.to_quaternion()) if pb.bone.parent else pb.bone.matrix_local.to_quaternion()
    expected_wq = (parent_wq @ local_rest).normalized()
    pb.rotation_quaternion = (expected_wq.inverted() @ new_world_q).normalized()
    bpy.context.view_layer.update()


def solve_2bone_ik_blender(arm, upper_name, lower_name, end_name, target_pos, pole_pos, end_fwd=None, end_up=None, limb_up_axis="Z"):
    """Analytical 2-bone IK solver working cleanly for BOTH arms AND legs (zero gimbal/twist artifacts!)."""
    bpy.context.view_layer.update()
    pb_u = arm.pose.bones[upper_name]
    pb_l = arm.pose.bones[lower_name]
    pb_e = arm.pose.bones[end_name]

    root_pos = pb_u.head.copy()
    len1 = (pb_l.head - pb_u.head).length
    len2 = (pb_e.head - pb_l.head).length

    to_tgt = target_pos - root_pos
    min_d = abs(len1 - len2) + 0.012
    max_d = (len1 + len2) - 0.004
    dist = max(min_d, min(max_d, to_tgt.length))
    dir_st = to_tgt.normalized()

    cos_a = max(-1.0, min(1.0, (len1 * len1 + dist * dist - len2 * len2) / (2.0 * len1 * dist)))
    ang_a = math.acos(cos_a)

    to_pole = pole_pos - root_pos
    bend_dir = to_pole - dir_st * to_pole.dot(dir_st)
    if bend_dir.length < 1e-4:
        bend_dir = Vector((0, 0, -1))
    bend_dir.normalize()

    mid_pos = root_pos + dir_st * (len1 * math.cos(ang_a)) + bend_dir * (len1 * math.sin(ang_a))
    aim_bone_at_world_dir(arm, upper_name, mid_pos - root_pos, up_hint_world=bend_dir, align_local_axis=limb_up_axis)
    aim_bone_at_world_dir(arm, lower_name, target_pos - mid_pos, up_hint_world=bend_dir, align_local_axis=limb_up_axis)
    if end_fwd is not None:
        aim_bone_at_world_dir(arm, end_name, end_fwd, up_hint_world=end_up)


def curl_fingers(arm, side="R", grip_amount=0.85, trigger_index=False):
    sgn = 1.0 if side == "R" else -1.0
    for f_prefix in ("Index", "Middle", "Ring", "Pinky"):
        amt = grip_amount * (0.28 if (trigger_index and f_prefix == "Index") else 1.0)
        for seg, deg in (("2", 52.0), ("3", 74.0), ("4", 58.0)):
            bname = f"{f_prefix}{seg}.{side}"
            if bname in arm.pose.bones:
                pb = arm.pose.bones[bname]
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = Euler((0.0, 0.0, math.radians(amt * deg * sgn)), "XYZ").to_quaternion()
    for seg, rx, rz in (("2", -18.0, -42.0), ("3", -10.0, -48.0)):
        bname = f"Thumb{seg}.{side}"
        if bname in arm.pose.bones:
            pb = arm.pose.bones[bname]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Euler((math.radians(rx * sgn), 0.0, math.radians(rz * sgn)), "XYZ").to_quaternion()


def apply_clean_prone_legs(arm, l_stride=0.0, r_stride=0.0):
    """ZERO-TWIST anatomical prone legs: knee caps face cleanly downward (-Z), calves face UP (+Z), boots naturally resting!"""
    # Check Swat leg rest orientation: UpperLeg +Y = DOWN (-Z), +Z = BACK (+Y) or FRONT (-Y)?
    # Let's rotate cleanly using exact pure-X pitch (no Z-gimbal twist!) + gentle hip abduction!
    # In rest pose: UpperLeg head->tail is -Z; rotating +86 deg around X moves -Z -> +Y (STRAIGHT BACK) with knee cap facing -Z (DOWN!)!
    # Wait: adding gentle OUTWARD splay MUST rotate around WORLD Z (yaw) AFTER X pitch (i.e. Quaternion(Z) @ Quaternion(X)), NOT XYZ Euler!
    for side, sgn, stride in (("L", 1.0, l_stride), ("R", -1.0, r_stride)):
        # Stride > 0 draws knee slightly outward-forward for authentic military low crawl!
        u_pb = arm.pose.bones[f"UpperLeg.{side}"]
        l_pb = arm.pose.bones[f"LowerLeg.{side}"]
        f_pb = arm.pose.bones[f"Foot.{side}"]
        # Pure anatomical composition: first lay leg flat back (+86 deg X), then gently splay hip outward around WORLD Z!
        # Wait: because World Z yaw runs AFTER X pitch, it NEVER twists the knee sideways!
        hip_pitch = math.radians(86.0 - stride * 26.0)
        hip_splay = math.radians(sgn * (7.0 + stride * 28.0))
        q_thigh_w = (Quaternion((0, 0, 1), hip_splay) @ Quaternion((1, 0, 0), hip_pitch)).normalized()

        # Shin: straight back along sand (slightly bent up/inward when crawling)
        shin_pitch = math.radians(84.0 - stride * 8.0)
        shin_splay = math.radians(sgn * (4.0 - stride * 12.0))
        q_shin_w = (Quaternion((0, 0, 1), shin_splay) @ Quaternion((1, 0, 0), shin_pitch)).normalized()

        # Foot: relaxed tactical prone ankle (toes angled gently outward-downward, zero twisted heels!)
        foot_pitch = math.radians(38.0)
        foot_splay = math.radians(sgn * 14.0)
        q_foot_w = (Quaternion((0, 0, 1), foot_splay) @ Quaternion((1, 0, 0), foot_pitch)).normalized()

        for pb, q_delta_w in ((u_pb, q_thigh_w), (l_pb, q_shin_w), (f_pb, q_foot_w)):
            bpy.context.view_layer.update()
            parent_wq = pb.parent.matrix.to_quaternion() if pb.parent else Quaternion((1, 0, 0, 0))
            local_rest = pb.bone.parent.matrix_local.to_quaternion().inverted() @ pb.bone.matrix_local.to_quaternion()
            rest_wq = pb.bone.matrix_local.to_quaternion()
            target_wq = (q_delta_w @ rest_wq).normalized()
            expected_wq = (parent_wq @ local_rest).normalized()
            pb.rotation_quaternion = (expected_wq.inverted() @ target_wq).normalized()


def pose_and_key_rifle_stance(arm, action_name, rifle_pos, rifle_euler_deg, hips_drop=0.0, torso_yaw_deg=20.0, torso_pitch_deg=4.0, head_tilt_deg=0.0, breath_amp=0.008, frames=32, recoil=False, crouched=False, prone=False, prone_crawl=False):
    act = bpy.data.actions.new(name=action_name)
    arm.animation_data.action = act

    grip_r_wrist_local = Vector((-0.012, 0.175, -0.048))
    foregrip_l_wrist_local = Vector((0.020, -0.115, -0.022))
    dst_hips_inv = arm.data.bones["Hips"].matrix_local.to_3x3().inverted()

    if recoil:
        key_frames = [0, 2, 5, 9]
    elif prone_crawl:
        key_frames = [0, 6, 12, 18, 24]
    else:
        key_frames = [0, frames // 4, frames // 2, (3 * frames) // 4, frames]

    for kf in key_frames:
        reset_pose(arm)
        t = kf / max(1.0, float(24 if prone_crawl else frames))
        breath = math.sin(t * 2.0 * math.pi) * breath_amp
        kick_z = 0.0
        kick_pitch = 0.0
        if recoil:
            if kf == 2:
                kick_z, kick_pitch = 0.035, 7.5
            elif kf == 5:
                kick_z, kick_pitch = 0.010, 2.0

        if prone or prone_crawl:
            crawl_s = math.sin(t * 2.0 * math.pi) if prone_crawl else 0.0
            l_st = max(0.0, crawl_s)
            r_st = max(0.0, -crawl_s)
            hip_sway_x = crawl_s * 0.035
            arm.pose.bones["Hips"].location = dst_hips_inv @ Vector((hip_sway_x, 0.12, -0.665 + breath * 0.3))
            # Pure spine arch upward from belly-down hips -> chest propped on elbows -> head level!
            set_bone_world_delta(arm, "Hips", (82.0, 0.0, crawl_s * 6.0))
            set_bone_world_delta(arm, "Abdomen", (72.0, 0.0, -crawl_s * 4.0))
            set_bone_world_delta(arm, "Torso", (58.0, 0.0, -6.0 - crawl_s * 5.0))
            set_bone_world_delta(arm, "Chest", (42.0, 0.0, -10.0))
            set_bone_world_delta(arm, "Neck", (16.0, 0.0, -4.0))
            set_bone_world_delta(arm, "Head", (4.0, 0.0, 0.0))
            apply_clean_prone_legs(arm, l_stride=l_st, r_stride=r_st)
        elif crouched:
            arm.pose.bones["Hips"].location = dst_hips_inv @ Vector((0.0, 0.02, -0.34 + breath))
            set_bone_world_delta(arm, "Hips", (10.0, 0.0, -torso_yaw_deg * 0.55))
            set_bone_world_delta(arm, "Abdomen", (12.0, 0.0, -torso_yaw_deg * 0.7))
            set_bone_world_delta(arm, "Torso", (14.0, 0.0, -torso_yaw_deg * 0.85))
            set_bone_world_delta(arm, "Chest", (15.0 + kick_pitch * 0.3, 0.0, -torso_yaw_deg))
            set_bone_world_delta(arm, "Neck", (4.0, 0.0, -torso_yaw_deg * 0.35))
            set_bone_world_delta(arm, "Head", (2.0, head_tilt_deg, 0.0))
            set_bone_world_delta(arm, "UpperLeg.L", (72.0, 0.0, 10.0))
            set_bone_world_delta(arm, "LowerLeg.L", (-18.0, 0.0, 8.0))
            set_bone_world_delta(arm, "Foot.L", (2.0, 0.0, 8.0))
            set_bone_world_delta(arm, "UpperLeg.R", (22.0, 0.0, -18.0))
            set_bone_world_delta(arm, "LowerLeg.R", (-76.0, 0.0, -16.0))
            set_bone_world_delta(arm, "Foot.R", (-24.0, 0.0, -16.0))
        else:
            arm.pose.bones["Hips"].location = dst_hips_inv @ Vector((0.0, 0.015, -hips_drop + breath))
            set_bone_world_delta(arm, "Hips", (4.0, 0.0, -torso_yaw_deg * 0.60))
            set_bone_world_delta(arm, "Abdomen", (torso_pitch_deg * 0.5, 0.0, -torso_yaw_deg * 0.72))
            set_bone_world_delta(arm, "Torso", (torso_pitch_deg * 0.8, 0.0, -torso_yaw_deg * 0.88))
            set_bone_world_delta(arm, "Chest", (torso_pitch_deg + kick_pitch * 0.35, 0.0, -torso_yaw_deg))
            set_bone_world_delta(arm, "Neck", (2.0, 0.0, -torso_yaw_deg * 0.32))
            set_bone_world_delta(arm, "Head", (0.0, head_tilt_deg, 0.0))
            set_bone_world_delta(arm, "UpperLeg.L", (16.0, 2.0, 8.0))
            set_bone_world_delta(arm, "LowerLeg.L", (-10.0, 0.0, 8.0))
            set_bone_world_delta(arm, "Foot.L", (0.0, 0.0, 8.0))
            set_bone_world_delta(arm, "UpperLeg.R", (-14.0, -3.0, -24.0))
            set_bone_world_delta(arm, "LowerLeg.R", (-22.0, 0.0, -22.0))
            set_bone_world_delta(arm, "Foot.R", (2.0, 0.0, -24.0))

        bpy.context.view_layer.update()
        crawl_bob = Vector((math.sin(t * 2.0 * math.pi) * 0.025, math.cos(t * 2.0 * math.pi) * 0.028, 0.0)) if prone_crawl else Vector((0, 0, 0))
        r_pos = Vector(rifle_pos) + Vector((0.0, kick_z, breath * 0.85)) + crawl_bob
        r_euler = Euler((math.radians(rifle_euler_deg[0] + kick_pitch), math.radians(rifle_euler_deg[1]), math.radians(rifle_euler_deg[2])), "XYZ")
        r_mat = Matrix.Translation(r_pos) @ r_euler.to_matrix().to_4x4()

        target_hand_r = r_mat @ grip_r_wrist_local
        target_hand_l = r_mat @ foregrip_l_wrist_local
        rifle_fwd = (r_mat.to_3x3() @ Vector((0, -1, 0))).normalized()
        rifle_up = (r_mat.to_3x3() @ Vector((0, 0, 1))).normalized()
        rifle_right = (r_mat.to_3x3() @ Vector((-1, 0, 0))).normalized()

        set_bone_world_delta(arm, "Shoulder.R", (6.0, 0.0, -12.0))
        set_bone_world_delta(arm, "Shoulder.L", (6.0, 0.0, 16.0))

        pole_r = Vector((-0.34, 0.08, r_pos.z - 0.34))
        pole_l = Vector((0.24, -0.04, r_pos.z - 0.38))
        if prone or prone_crawl:
            pole_r = Vector((-0.38, -0.18, 0.08))
            pole_l = Vector((0.32, -0.22, 0.08))

        solve_2bone_ik_blender(arm, "UpperArm.R", "LowerArm.R", "Hand.R", target_hand_r, pole_r, end_fwd=(rifle_fwd * 0.92 - rifle_up * 0.28).normalized(), end_up=rifle_up)
        l_hand_dir = (rifle_fwd * 0.55 + rifle_right * 0.72 + rifle_up * 0.32).normalized()
        l_hand_thumb_up = (rifle_fwd * 0.72 - rifle_right * 0.45 + rifle_up * 0.50).normalized()
        solve_2bone_ik_blender(arm, "UpperArm.L", "LowerArm.L", "Hand.L", target_hand_l, pole_l, end_fwd=l_hand_dir, end_up=l_hand_thumb_up)
        curl_fingers(arm, "R", grip_amount=0.92, trigger_index=True)
        curl_fingers(arm, "L", grip_amount=0.80, trigger_index=False)

        bpy.context.view_layer.update()
        wb_pb = arm.pose.bones["Weapon_R"]
        wb_pb.rotation_mode = "QUATERNION"
        parent_mat = wb_pb.parent.matrix
        rest_local = wb_pb.bone.parent.matrix_local.inverted() @ wb_pb.bone.matrix_local
        rest_world_rot = wb_pb.bone.matrix_local.to_quaternion()
        tgt_world_rot = (r_euler.to_quaternion() @ rest_world_rot).normalized()
        expected_rot = (parent_mat.to_quaternion() @ rest_local.to_quaternion()).normalized()
        wb_pb.rotation_quaternion = (expected_rot.inverted() @ tgt_world_rot).normalized()
        expected_mat = parent_mat @ rest_local
        wb_pb.location = expected_mat.inverted() @ r_pos

        for pb in arm.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=kf)
            if pb.name in ("Hips", "Weapon_R"):
                pb.keyframe_insert(data_path="location", frame=kf)

    return act


def build_shaoyu_ground_slam_action(arm):
    act = bpy.data.actions.new(name="Shaoyu_GroundSlam")
    arm.animation_data.action = act
    dst_hips_inv = arm.data.bones["Hips"].matrix_local.to_3x3().inverted()
    stages = [
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
        solve_2bone_ik_blender(arm, "UpperArm.R", "LowerArm.R", "Hand.R", rh_tgt, pole_r, end_fwd=r_fist_dir, end_up=Vector((0, -1, 0)))
        solve_2bone_ik_blender(arm, "UpperArm.L", "LowerArm.L", "Hand.L", lh_tgt, pole_l, end_fwd=Vector((0.6, 0.5, -0.5)).normalized(), end_up=Vector((0, 0, 1)))
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
    all_acts += retarget_actions_from_file(
        arm,
        os.path.join(CC0_DIR, "AnimationLibrary_Godot_Standard.gltf"),
        UAL_BONE_MAP,
        {
            "Idle_Loop": "Idle_Stance", "Walk_Loop": "Walk_Fwd", "Jog_Fwd_Loop": "Jog_Fwd",
            "Sprint_Loop": "Sprint_Fwd", "Crouch_Idle_Loop": "Crouch_Idle", "Crouch_Fwd_Loop": "Crouch_Walk",
            "Jump_Start": "Jump_Start", "Jump_Loop": "Jump_Loop", "Jump_Land": "Jump_Land",
            "Sword_Idle": "Knife_Idle", "Sword_Attack": "Knife_Slash_1", "Hit_Chest": "Hit_React",
        },
        step=2,
    )
    all_acts += retarget_actions_from_file(
        arm,
        os.path.join(CC0_DIR, "Rig_Medium_MovementAdvanced.glb"),
        KAYKIT_BONE_MAP,
        {"Walking_Backwards": "Walk_Back", "Running_Strafe_Left": "Strafe_Left", "Running_Strafe_Right": "Strafe_Right"},
        step=2,
    )
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

    all_acts.append(pose_and_key_rifle_stance(arm, "Rifle_LowReady", (-0.035, -0.295, 1.155), (18.0, 4.0, -28.0), hips_drop=0.042, torso_yaw_deg=24.0, torso_pitch_deg=4.0, breath_amp=0.009, frames=36))
    all_acts.append(pose_and_key_rifle_stance(arm, "Rifle_Aim", (-0.095, -0.315, 1.320), (0.0, 0.0, -2.0), hips_drop=0.055, torso_yaw_deg=28.0, torso_pitch_deg=6.0, head_tilt_deg=-7.0, breath_amp=0.004, frames=32))
    all_acts.append(pose_and_key_rifle_stance(arm, "Rifle_Fire", (-0.095, -0.315, 1.320), (0.0, 0.0, -2.0), hips_drop=0.055, torso_yaw_deg=28.0, torso_pitch_deg=6.0, head_tilt_deg=-7.0, breath_amp=0.0, frames=9, recoil=True))
    all_acts.append(pose_and_key_rifle_stance(arm, "Rifle_Crouch_Aim", (-0.092, -0.325, 0.995), (0.0, 0.0, -2.0), hips_drop=0.34, torso_yaw_deg=26.0, torso_pitch_deg=12.0, head_tilt_deg=-6.0, breath_amp=0.004, frames=32, crouched=True))
    # ZERO-TWIST anatomical Prone Idle & alternating Low-Crawl!
    all_acts.append(pose_and_key_rifle_stance(arm, "Prone_Idle", (-0.065, -0.585, 0.435), (0.0, 0.0, -2.0), breath_amp=0.004, frames=32, prone=True))
    all_acts.append(pose_and_key_rifle_stance(arm, "Prone_Crawl", (-0.065, -0.585, 0.425), (2.0, 0.0, -2.0), breath_amp=0.004, frames=24, prone_crawl=True))
    all_acts.append(build_shaoyu_ground_slam_action(arm))

    arm.animation_data.action = None
    for tr in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(tr)
    for act in all_acts:
        act.use_fake_user = True
        tr = arm.animation_data.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, int(round(act.frame_range[0])), act)
        st.name = act.name
        tr.mute = True
    reset_pose(arm)
    return all_acts


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
    """4-panel proof: (1) Sculpted Face/Eyes/Goggles Close-Up | (2) 3/4 Rifle Aim | (3) Zero-Twist Prone Legs Rear-Side | (4) 3P Back View!"""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=RIFLE_GLB)
    rifle_objs = [o for o in bpy.data.objects if o not in before]
    rifle_root = bpy.data.objects.new("PreviewRifleRoot", None)
    bpy.context.collection.objects.link(rifle_root)
    for ro in rifle_objs:
        if ro.parent is None:
            ro.parent = rifle_root

    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
    world = bpy.data.worlds.new("StudioW")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.76, 0.80, 0.85, 1.0)
    bg.inputs[1].default_value = 0.85

    sun = bpy.data.objects.new("KeySun", bpy.data.lights.new("KeySun", "SUN"))
    sun.data.energy = 3.6
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(40), math.radians(18), math.radians(-30))

    fill = bpy.data.objects.new("FillLight", bpy.data.lights.new("FillLight", "AREA"))
    fill.data.energy = 110.0
    fill.data.size = 2.6
    bpy.context.collection.objects.link(fill)
    fill.location = (1.8, -2.2, 2.0)
    fill.rotation_euler = (math.radians(60), 0.0, math.radians(38))

    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 58
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    def aim_cam(loc, target):
        cam.location = Vector(loc)
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()

    def set_pose(aname, frame=0):
        for tr in arm.animation_data.nla_tracks:
            tr.mute = True
        arm.animation_data.action = bpy.data.actions.get(aname)
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        pb = arm.pose.bones["Weapon_R"]
        m = arm.matrix_world @ pb.matrix
        q = (m.to_quaternion() @ arm.data.bones["Weapon_R"].matrix_local.to_quaternion().inverted()).normalized()
        rifle_root.matrix_world = Matrix.Translation(m.to_translation()) @ q.to_matrix().to_4x4() @ Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Diagonal((0.78, 0.78, 0.78, 1.0))

    shots = [
        ("face", "Rifle_LowReady", 0, (-0.18, -0.95, 1.62), (0.0, -0.02, 1.56)),
        ("aim34", "Rifle_Aim", 0, (-1.45, -1.55, 1.32), (-0.04, -0.14, 1.24)),
        ("prone", "Prone_Idle", 0, (-1.15, 1.85, 0.85), (0.0, 0.35, 0.20)),
        ("back3p", "Rifle_LowReady", 0, (-0.36, 2.25, 1.36), (-0.04, -0.20, 1.10)),
    ]
    bpy.context.scene.render.resolution_x = 640
    bpy.context.scene.render.resolution_y = 480
    panels = []
    for tag, aname, fr, cloc, ctgt in shots:
        set_pose(aname, fr)
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

    top = np.concatenate([panels[0], panels[1]], axis=1)
    bot = np.concatenate([panels[2], panels[3]], axis=1)
    grid = np.concatenate([bot, top], axis=0)
    out_img = bpy.data.images.new("ProofGrid95", width=1280, height=960, alpha=False)
    out_img.pixels.foreach_set(grid.ravel())
    out_img.filepath_raw = PREVIEW_PNG
    out_img.file_format = "PNG"
    out_img.save()
    print("RENDERED_PROOF:", PREVIEW_PNG)


def main():
    arm, swat_body, swat_legs, swat_feet = build_normalized_shaoyu_base()
    pal = create_material_palette()
    head_obj, eyes_obj, hinfo = build_sculpted_blender_studio_head(arm, pal)
    meshes = customize_shaoyu_appearance(arm, swat_body, swat_legs, swat_feet, head_obj, eyes_obj, hinfo, pal)
    build_all_animations(arm)
    export_shaoyu_glb(arm, meshes)
    if "--preview" in sys.argv:
        render_studio_proof(arm)


if __name__ == "__main__":
    main()
