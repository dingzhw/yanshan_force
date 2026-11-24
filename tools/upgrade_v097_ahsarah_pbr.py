#!/usr/bin/env python3
"""Yanshan Force v0.9.7 — Blender 5.3 Desert PBR & Photogrammetry Upgrade Pipeline.

Upgrades Ahsarah Fortress ('阿萨拉堡垒') architecture, cliffs, boulders, palms & acacias:
1. Applies real Poly Haven CC0 1K PBR textures (Diffuse + OpenGL Normal + Roughness) with
   clean world-scale Box/Cubic UV projection across EVERY architectural surface of:
     - game/assets/slice/v090_ahsarah_architecture.glb
     - game/assets/slice/v091_ahsarah_fortress.glb
   Eliminating all flat untextured pastel plastic boxes!
2. Replaces low-poly flat-shaded orange polyhedron boulders, perimeter rock walls & Zero Dam
   flanking canyon cliffs with genuine decimated Poly Haven CC0 Namaqualand photogrammetry
   rocks/cliffs (namaqualand_boulder_02, namaqualand_boulder_03, namaqualand_cliff_01)
   plus wild_rooibos_bush arid scrub!
3. Refines desert_acacia_tree (layered organic leafy canopy) & oasis_palm_cluster (matte
   realistic date clusters instead of glowing neon-yellow bulbs, rich bark & frond PBR).
"""
from __future__ import annotations

import math
import os
import random
import tempfile
from pathlib import Path
import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
PBR_DIR = ROOT / "game" / "assets" / "pbr_v097"
CACHE_DIR = Path(tempfile.gettempdir()) / "yanshan_v097_cc0_cache"
SLICE_DIR = ROOT / "game" / "assets" / "slice"


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_image(path: Path, non_color: bool = False):
    if not path.exists():
        return None
    key = path.name
    if key in bpy.data.images:
        img = bpy.data.images[key]
    else:
        img = bpy.data.images.load(str(path), check_existing=True)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    try:
        img.pack()
    except Exception:
        pass
    return img


def find_pbr(slug: str, chan: str) -> Path | None:
    for ext in ("jpg", "png"):
        p = PBR_DIR / f"{slug}_{chan}.{ext}"
        if p.exists():
            return p
    return None


def upgrade_material_with_pbr(
    mat: bpy.types.Material,
    slug: str,
    tint_rgba: tuple[float, float, float, float] | None = None,
    uv_scale: float = 0.25,
    normal_strength: float = 0.85,
    rough_mult: float = 1.0,
    metallic: float | None = None,
):
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return
    # Remove any old texture/mapping nodes we might replace
    for n in list(nt.nodes):
        if n.type in {"TEX_IMAGE", "MAPPING", "TEX_COORD", "NORMAL_MAP", "MIX", "MATH"}:
            nt.nodes.remove(n)

    orig_col = tuple(bsdf.inputs["Base Color"].default_value)
    use_tint = tint_rgba if tint_rgba is not None else orig_col

    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (uv_scale, uv_scale, uv_scale)
    nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])

    diff_p = find_pbr(slug, "diff")
    if diff_p:
        tex_d = nt.nodes.new("ShaderNodeTexImage")
        tex_d.image = load_image(diff_p, non_color=False)
        nt.links.new(mp.outputs["Vector"], tex_d.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 0.58
        mix.inputs[7].default_value = use_tint
        nt.links.new(tex_d.outputs["Color"], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = use_tint

    nor_p = find_pbr(slug, "nor_gl")
    if nor_p:
        tex_n = nt.nodes.new("ShaderNodeTexImage")
        tex_n.image = load_image(nor_p, non_color=True)
        nt.links.new(mp.outputs["Vector"], tex_n.inputs["Vector"])
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = normal_strength
        nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    rgh_p = find_pbr(slug, "rough")
    if rgh_p:
        tex_r = nt.nodes.new("ShaderNodeTexImage")
        tex_r.image = load_image(rgh_p, non_color=True)
        nt.links.new(mp.outputs["Vector"], tex_r.inputs["Vector"])
        if abs(rough_mult - 1.0) > 0.02:
            mnode = nt.nodes.new("ShaderNodeMath")
            mnode.operation = "MULTIPLY"
            mnode.use_clamp = True
            mnode.inputs[1].default_value = rough_mult
            nt.links.new(tex_r.outputs["Color"], mnode.inputs[0])
            nt.links.new(mnode.outputs["Value"], bsdf.inputs["Roughness"])
        else:
            nt.links.new(tex_r.outputs["Color"], bsdf.inputs["Roughness"])

    if metallic is not None:
        bsdf.inputs["Metallic"].default_value = metallic


def apply_world_box_uv(obj: bpy.types.Object, tex_density: float = 0.28):
    """Assign clean seam-free world-space triplanar/box UVs to architectural geometry."""
    if obj.type != "MESH" or not obj.data or len(obj.data.polygons) == 0:
        return
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data
    verts = mesh.vertices
    for poly in mesh.polygons:
        n = poly.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for li in poly.loop_indices:
            co = verts[mesh.loops[li].vertex_index].co
            if az >= ax and az >= ay:
                u, v = co.x * tex_density, co.y * tex_density
            elif ax >= ay and ax >= az:
                u, v = co.y * tex_density, co.z * tex_density
            else:
                u, v = co.x * tex_density, co.z * tex_density
            uv_layer[li].uv = (u, v)


def import_cc0_gltf_mesh(slug: str, target_tris: int = 750) -> bpy.types.Object | None:
    mdir = CACHE_DIR / slug
    if not mdir.exists():
        print(f"WARN cache missing {mdir}")
        return None
    gltfs = list(mdir.glob("*.gltf")) + list(mdir.glob("*.glb"))
    if not gltfs:
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(gltfs[0]))
    added = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in added if o.type == "MESH" and len(o.data.polygons) > 0]
    empties = [o for o in added if o.type != "MESH"]
    if not meshes:
        for o in added:
            bpy.data.objects.remove(o, do_unlink=True)
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for e in empties:
        if e.name in bpy.data.objects:
            bpy.data.objects.remove(e, do_unlink=True)

    # Decimate cleanly while preserving photogrammetry UVs & normals!
    cur_tris = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    if cur_tris > target_tris:
        mod = obj.modifiers.new("DecimateV097", "DECIMATE")
        mod.ratio = max(0.03, float(target_tris) / float(cur_tris))
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)

    # Ensure smooth shading & packed textures
    for poly in obj.data.polygons:
        poly.use_smooth = True
    for mat in obj.data.materials:
        if mat and mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    try:
                        node.image.pack()
                    except Exception:
                        pass
    return obj


def normalize_mesh_to_bbox(obj: bpy.types.Object, target_size_bl: tuple[float, float, float], sink_z: float = 0.0):
    """Scale & re-center mesh so X/Y are centered and bottom sits at z = -sink_z."""
    verts = obj.data.vertices
    xs = [v.co.x for v in verts]
    ys = [v.co.y for v in verts]
    zs = [v.co.z for v in verts]
    cx, cy, min_z = (min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5, min(zs)
    sx = max(1e-4, max(xs) - min(xs))
    sy = max(1e-4, max(ys) - min(ys))
    sz = max(1e-4, max(zs) - min(zs))
    kx, ky, kz = target_size_bl[0] / sx, target_size_bl[1] / sy, target_size_bl[2] / sz
    for v in verts:
        v.co.x = (v.co.x - cx) * kx
        v.co.y = (v.co.y - cy) * ky
        v.co.z = (v.co.z - min_z) * kz - sink_z
    obj.data.update()


def remap_ahsarah_materials():
    """Upgrade flat untextured Ahsarah materials with rich Poly Haven CC0 PBR maps."""
    rules = {
        "Mat_SandstoneMain":  ("old_sandstone_02", (0.94, 0.78, 0.54, 1.0), 0.36, 0.95, 1.02, 0.0),
        "Mat_SandstoneDark":  ("old_sandstone_02", (0.76, 0.54, 0.34, 1.0), 0.42, 1.05, 1.05, 0.0),
        "Mat_SandstoneLight": ("clay_plaster",     (0.98, 0.86, 0.66, 1.0), 0.38, 0.80, 0.96, 0.0),
        "Mat_Terracotta":     ("clay_plaster",     (0.84, 0.48, 0.30, 1.0), 0.46, 0.90, 0.98, 0.0),
        "Mat_ConcreteMain":   ("plaster_grey_04",  (0.82, 0.80, 0.76, 1.0), 0.24, 0.95, 1.04, 0.02),
        "Mat_ConcreteDark":   ("plaster_grey_04",  (0.56, 0.56, 0.55, 1.0), 0.28, 1.05, 1.08, 0.05),
        "Mat_Sandbag":        ("clay_plaster",     (0.88, 0.78, 0.58, 1.0), 1.35, 0.95, 1.06, 0.0),
        "Mat_CanvasTan":      ("clay_plaster",     (0.92, 0.84, 0.68, 1.0), 0.95, 0.55, 1.05, 0.0),
        "Mat_DesertRock":     ("cliff_side",       (0.86, 0.58, 0.38, 1.0), 0.22, 1.15, 1.06, 0.0),
        "Mat_DesertRockDark": ("cliff_side",       (0.68, 0.42, 0.26, 1.0), 0.20, 1.20, 1.08, 0.0),
        "Mat_DesertRockLight":("cliff_side",       (0.96, 0.72, 0.48, 1.0), 0.24, 1.10, 1.02, 0.0),
        "Mat_PalmTrunk":      ("old_sandstone_02", (0.58, 0.40, 0.26, 1.0), 1.40, 1.10, 1.08, 0.0),
        "Mat_CedarWood":      ("old_sandstone_02", (0.48, 0.33, 0.20, 1.0), 1.10, 0.85, 1.02, 0.0),
        "Mat_PalmFrond":      ("aerial_grass_rock",(0.36, 0.62, 0.28, 1.0), 1.20, 0.55, 0.92, 0.0),
        "Mat_PalmFrondSun":   ("aerial_grass_rock",(0.52, 0.78, 0.34, 1.0), 1.20, 0.50, 0.88, 0.0),
        "Mat_KarstDark":      ("cliff_side",       (0.32, 0.36, 0.38, 1.0), 0.35, 1.10, 1.02, 0.04),
    }
    for mat in bpy.data.materials:
        base_name = mat.name.split(".")[0]
        if base_name in rules:
            upgrade_material_with_pbr(mat, *rules[base_name])
        elif base_name == "Mat_AmberGlow":
            # Keep amber beacons glowing for dam lights, but create a matte date material separately for palms
            pass


def fix_palm_dates_and_acacia():
    """Remove glowing neon-yellow eggs on oasis palms & sculpt richer organic desert acacia canopy!"""
    palm = bpy.data.objects.get("oasis_palm_cluster")
    if palm and palm.type == "MESH":
        # Replace Mat_AmberGlow slot on palm with warm matte realistic ripe dates!
        date_mat = bpy.data.materials.new("Mat_RipeDates")
        date_mat.use_nodes = True
        bsdf = next(n for n in date_mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (0.42, 0.20, 0.04, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.55
        for idx, m in enumerate(palm.data.materials):
            if m and m.name.split(".")[0] == "Mat_AmberGlow":
                palm.data.materials[idx] = date_mat
        apply_world_box_uv(palm, 0.65)

    acacia = bpy.data.objects.get("desert_acacia_tree")
    if acacia and acacia.type == "MESH":
        # Rebuild desert acacia with gnarled realistic branching + 18 layered arid olive-sage foliage clusters!
        m_trunk = next((m for m in bpy.data.materials if m.name.startswith("Mat_CedarWood")), None)

        def make_acacia_leaf_mat(mname, rgba):
            mat = bpy.data.materials.new(mname)
            mat.use_nodes = True
            nt = mat.node_tree
            bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            bs.inputs["Base Color"].default_value = rgba
            bs.inputs["Roughness"].default_value = 0.76
            nor_p = find_pbr("aerial_grass_rock", "nor_gl")
            if nor_p:
                tc = nt.nodes.new("ShaderNodeTexCoord")
                mp = nt.nodes.new("ShaderNodeMapping")
                mp.inputs["Scale"].default_value = (1.6, 1.6, 1.6)
                nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
                tn = nt.nodes.new("ShaderNodeTexImage")
                tn.image = load_image(nor_p, non_color=True)
                nt.links.new(mp.outputs["Vector"], tn.inputs["Vector"])
                nm = nt.nodes.new("ShaderNodeNormalMap")
                nm.inputs["Strength"].default_value = 0.72
                nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
                nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
            return mat

        m_leaf_a = make_acacia_leaf_mat("Mat_AcaciaOliveDark", (0.11, 0.21, 0.068, 1.0))
        m_leaf_b = make_acacia_leaf_mat("Mat_AcaciaOliveSun", (0.18, 0.29, 0.095, 1.0))
        # Also tint oasis palms back to crisp emerald date-palm green!
        if palm and palm.type == "MESH":
            m_palm_dk = make_acacia_leaf_mat("Mat_OasisPalmDeep", (0.068, 0.22, 0.062, 1.0))
            m_palm_sun = make_acacia_leaf_mat("Mat_OasisPalmSun", (0.135, 0.30, 0.085, 1.0))
            for idx, pm in enumerate(palm.data.materials):
                if pm and "PalmFrondSun" in pm.name:
                    palm.data.materials[idx] = m_palm_sun
                elif pm and "PalmFrond" in pm.name:
                    palm.data.materials[idx] = m_palm_dk
        bm = bmesh.new()
        rng = random.Random(9707)

        def add_limb(p0, p1, r0, r1, segs=8):
            a, b = Vector(p0), Vector(p1)
            d = b - a
            if d.length < 1e-4:
                return
            rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
            ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=d.length)
            bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) * 0.5) @ rot, verts=ret["verts"])
            for f in bm.faces:
                if all(v in ret["verts"] for v in f.verts):
                    f.material_index = 0

        def add_foliage_tuft(center, rad_xy, rad_z, midx, seed_i):
            r2 = random.Random(seed_i)
            ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
            for v in ret["verts"]:
                p = v.co
                n = 1.0 + 0.28 * math.sin(p.x * 5.2 + seed_i) * math.cos(p.y * 4.8) + r2.uniform(-0.14, 0.14)
                # Slightly flattened umbrella underside, airy scalloped crown top
                zf = 0.62 if p.z < 0.0 else 1.05
                v.co = Vector((
                    center[0] + p.x * rad_xy * n,
                    center[1] + p.y * rad_xy * n,
                    center[2] + p.z * rad_z * zf * n,
                ))
            for f in bm.faces:
                if all(v in ret["verts"] for v in f.verts):
                    f.material_index = midx
                    f.smooth = True

        # Blender coords: X right, Y forward, Z up
        add_limb((0, 0, -1.2), (0.08, 0.04, 1.3), 0.44, 0.30, 9)
        add_limb((0.08, 0.04, 1.2), (0.18, -0.06, 2.5), 0.30, 0.22, 8)
        boughs = [
            ((0.18, -0.06, 2.4), (-1.9, -0.8, 4.4)),
            ((0.18, -0.06, 2.4), (2.1, 0.5, 4.5)),
            ((0.18, -0.06, 2.4), (0.3, -1.8, 4.8)),
            ((0.18, -0.06, 2.4), (-0.7, 1.9, 4.6)),
            ((0.18, -0.06, 2.4), (1.3, 1.6, 4.9)),
            ((0.18, -0.06, 2.4), (-1.5, 1.2, 4.7)),
        ]
        for bi, (p0, p1) in enumerate(boughs):
            mid = ((p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5, (p0[2] + p1[2]) * 0.5 + 0.25)
            add_limb(p0, mid, 0.16, 0.11, 7)
            add_limb(mid, p1, 0.11, 0.06, 6)
            # 3 organic scalloped canopy tufts per bough -> rich airy African umbrella silhouette!
            for sub in range(3):
                ang = bi * 1.1 + sub * 2.1
                off_x = math.cos(ang) * rng.uniform(0.4, 1.1)
                off_y = math.sin(ang) * rng.uniform(0.4, 1.1)
                off_z = rng.uniform(0.15, 0.55)
                add_foliage_tuft(
                    (p1[0] + off_x, p1[1] + off_y, p1[2] + off_z),
                    rng.uniform(1.05, 1.55),
                    rng.uniform(0.32, 0.48),
                    1 if (bi + sub) % 2 == 0 else 2,
                    900 + bi * 13 + sub * 7,
                )
        add_foliage_tuft((0.1, 0.0, 5.25), 1.75, 0.48, 2, 999)

        mesh = acacia.data
        mesh.clear_geometry()
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.clear()
        for m in (m_trunk, m_leaf_a, m_leaf_b):
            if m:
                mesh.materials.append(m)
        apply_world_box_uv(acacia, 0.72)


def strip_lowpoly_dam_rocks_and_replace_rocks():
    """Strip flat orange low-poly rocks off Zero Dam and replace ALL desert boulders/rockwalls with real CC0 photogrammetry!"""
    # 1. Remove low-poly rock faces (Mat_DesertRock*) from zero_dam_wall_monolith so clean concrete meets real photogrammetry cliffs!
    dam = bpy.data.objects.get("zero_dam_wall_monolith")
    if dam and dam.type == "MESH":
        rock_idxs = {
            i for i, m in enumerate(dam.data.materials)
            if m and m.name.split(".")[0] in {"Mat_DesertRock", "Mat_DesertRockDark", "Mat_DesertRockLight"}
        }
        if rock_idxs:
            bm = bmesh.new()
            bm.from_mesh(dam.data)
            del_faces = [f for f in bm.faces if f.material_index in rock_idxs]
            bmesh.ops.delete(bm, geom=del_faces, context="FACES")
            bm.to_mesh(dam.data)
            bm.free()
            dam.data.update()
        apply_world_box_uv(dam, 0.16)

    # 2. Import photogrammetry Namaqualand boulder/cliff templates
    b2 = import_cc0_gltf_mesh("namaqualand_boulder_02", target_tris=680)
    b3 = import_cc0_gltf_mesh("namaqualand_boulder_03", target_tris=720)
    cliff = import_cc0_gltf_mesh("namaqualand_cliff_01", target_tris=1450)

    if b2:
        normalize_mesh_to_bbox(b2, (3.8, 3.2, 2.2), sink_z=0.35)
        old_a = bpy.data.objects.get("desert_boulder_a")
        if old_a:
            bpy.data.objects.remove(old_a, do_unlink=True)
        b2.name = "desert_boulder_a"
        b2.data.name = "desert_boulder_a"

    if b3:
        normalize_mesh_to_bbox(b3, (4.4, 3.8, 3.4), sink_z=0.45)
        old_b = bpy.data.objects.get("desert_boulder_b")
        if old_b:
            bpy.data.objects.remove(old_b, do_unlink=True)
        b3.name = "desert_boulder_b"
        b3.data.name = "desert_boulder_b"

    # Replace desert_perimeter_rockwall with a 10.6m interlocking photogrammetry boulder cluster!
    if b2 and b3:
        old_pw = bpy.data.objects.get("desert_perimeter_rockwall")
        if old_pw:
            bpy.data.objects.remove(old_pw, do_unlink=True)
        parts = []
        specs = [
            (b2, (-3.6, 0.15, -0.35), (1.18, 1.08, 1.48), 18.0),
            (b3, (0.0, -0.20, -0.45), (1.12, 1.05, 1.38), 142.0),
            (b2, (3.6, 0.18, -0.35), (1.16, 1.12, 1.42), -34.0),
        ]
        for tpl, loc, sc, yaw in specs:
            dup = tpl.copy()
            dup.data = tpl.data.copy()
            dup.location = Vector(loc)
            dup.scale = Vector(sc)
            dup.rotation_euler = Euler((0.0, 0.0, math.radians(yaw)), "XYZ")
            bpy.context.collection.objects.link(dup)
            parts.append(dup)
        bpy.ops.object.select_all(action="DESELECT")
        for p in parts:
            p.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        pw = bpy.context.view_layer.objects.active
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        pw.name = "desert_perimeter_rockwall"
        pw.data.name = "desert_perimeter_rockwall"

    # Replace oasis_spring_head with a grounded photogrammetry boulder cluster!
    if b2:
        old_sh = bpy.data.objects.get("oasis_spring_head")
        if old_sh:
            bpy.data.objects.remove(old_sh, do_unlink=True)
        sh = b2.copy()
        sh.data = b2.data.copy()
        bpy.context.collection.objects.link(sh)
        normalize_mesh_to_bbox(sh, (3.4, 2.5, 1.75), sink_z=0.35)
        sh.name = "oasis_spring_head"
        sh.data.name = "oasis_spring_head"

    # Keep namaqualand_cliff_01 as dedicated Zero Dam flanking canyon cliff buttress!
    if cliff:
        normalize_mesh_to_bbox(cliff, (42.0, 26.0, 38.0), sink_z=6.0)
        cliff.name = "desert_cliff_abutment"
        cliff.data.name = "desert_cliff_abutment"


def upgrade_glb(glb_path: Path, is_v090: bool):
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(glb_path))
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            # Apply clean world-scale box UVs to all architectural meshes so PBR textures never stretch!
            if obj.name not in {"desert_mesa_ring"}:
                apply_world_box_uv(obj, 0.24 if "zero_dam" not in obj.name else 0.16)
    remap_ahsarah_materials()
    if is_v090:
        fix_palm_dates_and_acacia()
        strip_lowpoly_dam_rocks_and_replace_rocks()
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_image_quality=85,
        export_yup=True,
    )
    print(f"EXPORTED_PBR_UPGRADED {glb_path.name} ({glb_path.stat().st_size // 1024} KB)")


def build_desert_nature_pack():
    """Export standalone desert photogrammetry scrub bush + small scatter rock pack."""
    clear_scene()
    bush = import_cc0_gltf_mesh("wild_rooibos_bush", target_tris=520)
    if bush:
        normalize_mesh_to_bbox(bush, (1.55, 1.55, 1.05), sink_z=0.06)
        bush.name = "desert_scrub_bush"
        bush.data.name = "desert_scrub_bush"
    rock_sm = import_cc0_gltf_mesh("namaqualand_boulder_02", target_tris=320)
    if rock_sm:
        normalize_mesh_to_bbox(rock_sm, (1.15, 0.95, 0.58), sink_z=0.14)
        rock_sm.name = "desert_scatter_stone"
        rock_sm.data.name = "desert_scatter_stone"
    out = SLICE_DIR / "v097_desert_nature.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_image_quality=84,
        export_yup=True,
    )
    print(f"EXPORTED_DESERT_NATURE {out.name} ({out.stat().st_size // 1024} KB)")


def main():
    upgrade_glb(SLICE_DIR / "v090_ahsarah_architecture.glb", is_v090=True)
    upgrade_glb(SLICE_DIR / "v091_ahsarah_fortress.glb", is_v090=False)
    build_desert_nature_pack()
    print("V097_AHSARAH_BLENDER_PIPELINE_DONE")


if __name__ == "__main__":
    main()
