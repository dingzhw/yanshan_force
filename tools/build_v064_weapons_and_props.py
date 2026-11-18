"""Build v0.6.4 Jiangnan Qinglü-Tactical Weapons & Sculpted World Loot Props in Blender 4.5.

Eliminates flat untextured plastic primitives across:
1. game/assets/slice/rifle.glb          — Multi-surface YS-04 Qinglü-Tactical Carbine (5 materials + baked cavity AO)
2. game/assets/slice/tactical_knife.glb — '竹影青锋' Cord-Wrapped Bronze-Guard Celadon-Edge Combat Knife (hand.R local)
3. game/assets/slice/v064_world_props.glb:
   - prop_stone_pedestal  (Octagonal mossy Jiangnan Sumidero waisted stone altar, top y = 0.44m)
   - prop_bird_nest       (Interwoven multi-twig nest on gnarled mossy root-rock with 3 eggs)
   - prop_karst_crevice   (Layered perforated Taihu karst rock formation with treasure cleft)
   - prop_squad_drop_case (Chamfered tactical armored loot case with corner bumpers & bronze latches)
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
SRC_V040 = ROOT / "third_party" / "slice-v040"
GEN_V061 = ROOT / "tools" / "generated_v061"
GEN_V062 = ROOT / "tools" / "generated_v062"
DEST = ROOT / "game" / "assets" / "slice"
DOCS = ROOT / "docs"
DEST.mkdir(parents=True, exist_ok=True)


def gd_to_bl(v: Vector) -> Vector:
    """Map Godot local coords (x_right, y_up, z_back; -Z forward) to Blender Z-up (+Y forward)."""
    return Vector((v.x, -v.z, v.y))


def _srgb_to_lin(c: tuple[float, float, float]) -> tuple[float, float, float, float]:
    return (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)


def make_vcol_pbr_mat(
    name: str,
    srgb: tuple[float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.68,
    tex_path: Path | None = None,
    emission_srgb: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = _srgb_to_lin(srgb)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.22

    if tex_path is not None and tex_path.exists():
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(tex_path), check_existing=True)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    if emission_srgb is not None and emission_strength > 0.0 and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = _srgb_to_lin(emission_srgb)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def bake_cavity_and_height_vcol(mesh: bpy.types.Mesh, min_ao: float = 0.58) -> None:
    """Bake stylized cavity + underside ambient occlusion into vertex Color so flat faces gain crisp depth."""
    if len(mesh.vertices) == 0:
        return
    ca = mesh.color_attributes.get("Color") or mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
    adj: list[list[int]] = [[] for _ in range(len(mesh.vertices))]
    for e in mesh.edges:
        a, b = e.vertices[0], e.vertices[1]
        adj[a].append(b)
        adj[b].append(a)

    zs = [v.co.z for v in mesh.vertices]
    z_min, z_max = min(zs), max(zs)
    z_span = max(0.02, z_max - z_min)

    for vi, v in enumerate(mesh.vertices):
        nbs = adj[vi]
        concavity = 0.0
        if nbs:
            avg_nb = sum((mesh.vertices[j].co for j in nbs), Vector((0.0, 0.0, 0.0))) / len(nbs)
            # If average neighbor sticks out along vertex normal, this vertex sits in a recessed groove/crevice!
            concavity = max(0.0, min(1.0, (avg_nb - v.co).dot(v.normal) * 85.0))
        h_t = (v.co.z - z_min) / z_span
        up_bias = 0.86 + 0.14 * max(0.0, v.normal.z)
        ao = max(min_ao, min(1.04, (0.76 + 0.24 * h_t) * (1.0 - 0.34 * concavity) * up_bias))
        ca.data[vi].color = (ao, ao, ao, 1.0)


def create_mesh_obj(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, smooth: bool = False) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = smooth
    bake_cavity_and_height_vcol(obj.data)
    return obj


def join_objs(name: str, parts: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name + "_Mesh"
    return obj


# ---------------------------------------------------------------------------
# 1. Multi-Surface YS-04 Qinglü-Tactical Carbine (rifle.glb)
# ---------------------------------------------------------------------------

def build_ys04_rifle() -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(SRC_V040 / "m4.blend"), load_ui=False, use_scripts=False)
    src_obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    coords = [src_obj.matrix_world @ v.co for v in src_obj.data.vertices]
    low = Vector(tuple(min(v[k] for v in coords) for k in range(3)))
    high = Vector(tuple(max(v[k] for v in coords) for k in range(3)))
    center = (low + high) / 2.0
    length = high.x - low.x

    def _thickness(end: int) -> float:
        band = [v for v in coords if (v.x < low.x + length * 0.08 if end == 0 else v.x > high.x - length * 0.08)]
        return max(v.z for v in band) - min(v.z for v in band)

    barrel_pos = _thickness(1) < _thickness(0)
    angle = math.pi / 2.0 if barrel_pos else -math.pi / 2.0
    turn = Matrix.Rotation(angle, 4, "Z")
    for v, p in zip(src_obj.data.vertices, coords):
        v.co = turn @ ((p - center) * (0.86 / length))
    src_obj.matrix_world = Matrix.Identity(4)

    parts_json = json.loads((DOCS / "slice-v040-gun-parts.json").read_text(encoding="utf-8"))
    magazine_ids = set(min(parts_json, key=lambda p: p["bounds"][0][2])["indices"])
    source = src_obj.data

    raw_verts = [tuple(v.co) for v in source.vertices]
    raw_polys = [tuple(p.vertices) for p in source.polygons]

    ys = [v[1] for v in raw_verts]
    zs = [v[2] for v in raw_verts]
    y_min, y_max = min(ys), max(ys)
    z_min, z_max = min(zs), max(zs)

    def _classify_poly_verts(p_vids: tuple[int, ...], is_mag: bool) -> int:
        if is_mag:
            cz = sum(raw_verts[i][2] for i in p_vids) / len(p_vids)
            return 4 if cz < z_min + 0.018 else 5
        pts = [raw_verts[i] for i in p_vids]
        cy = sum(p[1] for p in pts) / len(pts)
        cz = sum(p[2] for p in pts) / len(pts)
        cx = sum(abs(p[0]) for p in pts) / len(pts)
        ny = (cy - y_min) / max(1e-4, y_max - y_min)
        nz = (cz - z_min) / max(1e-4, z_max - z_min)

        if ny > 0.77 or (ny > 0.54 and cx < 0.011 and 0.52 < nz < 0.74):
            return 2  # Mat_YS04_BarrelSteel
        if (0.03 < ny < 0.25 and nz < 0.76) or (0.53 < ny <= 0.77 and nz < 0.80):
            return 1  # Mat_YS04_HandguardStock (Qinglü Polymer)
        if ny <= 0.03 or (0.24 <= ny < 0.43 and nz < 0.43):
            return 3  # Mat_YS04_Grip
        if (0.34 < ny < 0.47 and 0.64 < nz < 0.76 and cx > 0.013) or (0.28 < ny < 0.52 and nz > 0.83 and int(ny * 60) % 2 == 0):
            return 4  # Mat_YS04_BronzeTrim
        return 0  # Mat_YS04_Receiver

    bpy.ops.wm.read_factory_settings(use_empty=True)

    m_receiver = make_vcol_pbr_mat("Mat_YS04_Receiver", (0.175, 0.215, 0.242), metallic=0.58, roughness=0.46)
    m_polymer = make_vcol_pbr_mat("Mat_YS04_HandguardStock", (0.195, 0.305, 0.272), metallic=0.06, roughness=0.76)
    m_barrel = make_vcol_pbr_mat("Mat_YS04_BarrelSteel", (0.115, 0.138, 0.155), metallic=0.78, roughness=0.38)
    m_grip = make_vcol_pbr_mat("Mat_YS04_Grip", (0.125, 0.140, 0.145), metallic=0.04, roughness=0.88)
    m_bronze = make_vcol_pbr_mat("Mat_YS04_BronzeTrim", (0.745, 0.595, 0.310), metallic=0.82, roughness=0.32)
    m_mag = make_vcol_pbr_mat("Mat_YS04_Magazine", (0.155, 0.225, 0.205), metallic=0.22, roughness=0.66)
    rifle_mats = [m_receiver, m_polymer, m_barrel, m_grip, m_bronze, m_mag]

    def _part_mesh(keep: set[int], mname: str, is_mag: bool) -> bpy.types.Mesh:
        ids = sorted(keep)
        remap = {old: new for new, old in enumerate(ids)}
        faces = [pv for pv in raw_polys if all(i in keep for i in pv)]
        mesh = bpy.data.meshes.new(mname)
        mesh.from_pydata([raw_verts[i] for i in ids], [], [[remap[i] for i in pv] for pv in faces])
        mesh.update()
        for mat in rifle_mats:
            mesh.materials.append(mat)
        for new_p, old_pv in zip(mesh.polygons, faces):
            new_p.material_index = _classify_poly_verts(old_pv, is_mag)
        return mesh

    rec_mesh = _part_mesh(set(range(len(raw_verts))) - magazine_ids, "YS04_ReceiverMesh", False)
    mag_mesh = _part_mesh(magazine_ids, "YS04_MagazineMesh", True)

    rec_obj = bpy.data.objects.new("YS04_receiver", rec_mesh)
    mag_obj = bpy.data.objects.new("YS04_magazine", mag_mesh)
    bpy.context.scene.collection.objects.link(rec_obj)
    bpy.context.scene.collection.objects.link(mag_obj)

    for part in (rec_obj, mag_obj):
        bpy.ops.object.select_all(action="DESELECT")
        part.select_set(True)
        bpy.context.view_layer.objects.active = part
        bev = part.modifiers.new("MachinedBevel", "BEVEL")
        bev.width = 0.0018
        bev.segments = 2
        bpy.ops.object.modifier_apply(modifier=bev.name)
        bake_cavity_and_height_vcol(part.data, min_ao=0.52)

    out_path = DEST / "rifle.glb"
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = rec_obj
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=True,
        export_attributes=True,
    )
    return {"file": "game/assets/slice/rifle.glb", "bytes": out_path.stat().st_size, "receiver_polys": len(rec_obj.data.polygons)}


# ---------------------------------------------------------------------------
# 2. '竹影青锋' Cord-Wrapped Qinglü Combat Knife (tactical_knife.glb)
# ---------------------------------------------------------------------------

def build_qinglu_knife() -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)

    m_cord_jade = make_vcol_pbr_mat("Mat_KnifeCordJade", (0.145, 0.275, 0.235), metallic=0.02, roughness=0.84)
    m_cord_core = make_vcol_pbr_mat("Mat_KnifeCordCore", (0.095, 0.115, 0.120), metallic=0.10, roughness=0.78)
    m_bronze = make_vcol_pbr_mat("Mat_KnifeBronze", (0.76, 0.60, 0.30), metallic=0.85, roughness=0.30)
    m_fuller = make_vcol_pbr_mat("Mat_KnifeSlateSpine", (0.13, 0.17, 0.19), metallic=0.82, roughness=0.34)
    m_edge = make_vcol_pbr_mat("Mat_KnifeCeladonEdge", (0.74, 0.86, 0.83), metallic=0.92, roughness=0.20)

    p_pinky = Vector((0.038, 0.082, -0.020))
    p_index = Vector((-0.015, 0.089, -0.020))
    grip_center = p_pinky.lerp(p_index, 0.50)
    grip_u = (p_index - p_pinky).normalized()
    grip_w = Vector((0.0, 0.0, 1.0))
    grip_v = grip_w.cross(grip_u).normalized()
    grip_w = grip_u.cross(grip_v).normalized()

    def hpt(s: float, v: float, w: float) -> Vector:
        return gd_to_bl(grip_center + grip_u * s + grip_v * v + grip_w * w)

    # 2A. Inner dark tang core + 6 sculpted Tsuka-style pine-jade paracord wrap ridges!
    bm_core = bmesh.new()
    bm_cord = bmesh.new()
    n_seg = 14
    prev_r = None
    first_r = None
    for s, rv, rw in [(-0.058, 0.0105, 0.0076), (0.0, 0.0118, 0.0086), (+0.054, 0.0132, 0.0088)]:
        ring = [bm_core.verts.new(hpt(s, math.cos(2 * math.pi * k / n_seg) * rv, math.sin(2 * math.pi * k / n_seg) * rw)) for k in range(n_seg)]
        if first_r is None:
            first_r = ring
        if prev_r is not None:
            for k in range(n_seg):
                nk = (k + 1) % n_seg
                bm_core.faces.new((prev_r[k], prev_r[nk], ring[nk], ring[k]))
        prev_r = ring
    bm_core.faces.new(list(reversed(first_r)))
    bm_core.faces.new(prev_r)
    obj_core = create_mesh_obj("KnifeCore", bm_core, m_cord_core, smooth=True)

    for band_i in range(6):
        s_mid = -0.044 + band_i * 0.0175
        for tilt_sgn in (-1.0, 1.0):
            r0, r1 = [], []
            for k in range(n_seg):
                ang = 2 * math.pi * k / n_seg
                s_shift = tilt_sgn * 0.0038 * math.sin(ang)
                rv = 0.0138
                rw = 0.0106
                r0.append(bm_cord.verts.new(hpt(s_mid - 0.0032 + s_shift, math.cos(ang) * rv, math.sin(ang) * rw)))
                r1.append(bm_cord.verts.new(hpt(s_mid + 0.0032 + s_shift, math.cos(ang) * rv, math.sin(ang) * rw)))
            for k in range(n_seg):
                nk = (k + 1) % n_seg
                bm_cord.faces.new((r0[k], r0[nk], r1[nk], r1[k]))
            bm_cord.faces.new(list(reversed(r0)))
            bm_cord.faces.new(r1)
    obj_cord = create_mesh_obj("KnifeCord", bm_cord, m_cord_jade, smooth=True)

    # 2B. Sculpted Antique-Bronze Cloud Crossguard + Tactical Pommel Ring!
    bm_br = bmesh.new()
    g0 = [bm_br.verts.new(hpt(+0.053, vx, wx)) for vx, wx in ((0.025, -0.0115), (0.025, 0.0115), (-0.020, 0.0115), (-0.020, -0.0115))]
    g1 = [bm_br.verts.new(hpt(+0.065, vx, wx)) for vx, wx in ((0.028, -0.0100), (0.028, 0.0100), (-0.017, 0.0100), (-0.017, -0.0100))]
    for k in range(4):
        nk = (k + 1) % 4
        bm_br.faces.new((g0[k], g0[nk], g1[nk], g1[k]))
    bm_br.faces.new(list(reversed(g0)))
    bm_br.faces.new(g1)

    # Pommel lanyard/finger ring at s = -0.072
    ring_c = grip_center + grip_u * (-0.072)
    n_maj, n_min = 16, 8
    tor_rings = []
    for i in range(n_maj):
        th = 2 * math.pi * i / n_maj
        maj_p = ring_c + (grip_u * math.cos(th) + grip_v * math.sin(th)) * 0.0135
        rad_dir = (grip_u * math.cos(th) + grip_v * math.sin(th)).normalized()
        sub = []
        for j in range(n_min):
            ph = 2 * math.pi * j / n_min
            pt = maj_p + rad_dir * (math.cos(ph) * 0.0032) + grip_w * (math.sin(ph) * 0.0032)
            sub.append(bm_br.verts.new(gd_to_bl(pt)))
        tor_rings.append(sub)
    for i in range(n_maj):
        ni = (i + 1) % n_maj
        for j in range(n_min):
            nj = (j + 1) % n_min
            bm_br.faces.new((tor_rings[i][j], tor_rings[ni][j], tor_rings[ni][nj], tor_rings[i][nj]))
    obj_guard = create_mesh_obj("KnifeBronzeGuard", bm_br, m_bronze, smooth=False)

    # 2C. Sleek 20.5cm Qinglü Fullered Combat Blade (dark slate spine + luminous celadon-silver bevel)
    tilt = math.radians(20.0)
    blade_u = (grip_u * math.cos(tilt) + grip_v * math.sin(tilt)).normalized()
    blade_v = grip_w.cross(blade_u).normalized()
    blade_w = blade_u.cross(blade_v).normalized()
    blade_origin = grip_center + grip_u * 0.064

    def bpt(b_len: float, b_v: float, b_w: float) -> Vector:
        return gd_to_bl(blade_origin + blade_u * b_len + blade_v * b_v + blade_w * b_w)

    stations = [
        (0.000, -0.0155, +0.0015, +0.0175, 0.0026),
        (0.020, -0.0155, +0.0005, +0.0168, 0.0026),
        (0.115, -0.0145, -0.0010, +0.0158, 0.0023),
        (0.162, -0.0108, -0.0015, +0.0132, 0.0018),
        (0.192, -0.0032, +0.0012, +0.0065, 0.0010),
        (0.208, +0.0014, +0.0014, +0.0016, 0.0002),
    ]

    bm_flat = bmesh.new()
    prev = None
    for idx, (bl, sv, bv, _ev, hw) in enumerate(stations):
        sec = [
            bm_flat.verts.new(bpt(bl, sv, +hw)),
            bm_flat.verts.new(bpt(bl, sv, -hw)),
            bm_flat.verts.new(bpt(bl, bv, -hw * 0.90)),
            bm_flat.verts.new(bpt(bl, bv, +hw * 0.90)),
        ]
        if idx == 0:
            bm_flat.faces.new(list(reversed(sec)))
        if prev is not None:
            for k in range(4):
                nk = (k + 1) % 4
                bm_flat.faces.new((prev[k], prev[nk], sec[nk], sec[k]))
        prev = sec
    bm_flat.faces.new(prev)
    obj_flat = create_mesh_obj("KnifeSpine", bm_flat, m_fuller, smooth=False)

    bm_edge = bmesh.new()
    prev_e = None
    for idx, (bl, _sv, bv, ev, hw) in enumerate(stations):
        sec = [
            bm_edge.verts.new(bpt(bl, bv, +hw * 0.90)),
            bm_edge.verts.new(bpt(bl, bv, -hw * 0.90)),
            bm_edge.verts.new(bpt(bl, ev, -0.00018)),
            bm_edge.verts.new(bpt(bl, ev, +0.00018)),
        ]
        if idx == 0:
            bm_edge.faces.new(list(reversed(sec)))
        if prev_e is not None:
            for k in range(4):
                nk = (k + 1) % 4
                bm_edge.faces.new((prev_e[k], prev_e[nk], sec[nk], sec[k]))
        prev_e = sec
    bm_edge.faces.new(prev_e)
    obj_edge = create_mesh_obj("KnifeEdge", bm_edge, m_edge, smooth=False)

    knife = join_objs("tactical_knife", [obj_core, obj_cord, obj_guard, obj_flat, obj_edge])
    out_path = DEST / "tactical_knife.glb"
    bpy.ops.object.select_all(action="DESELECT")
    knife.select_set(True)
    bpy.context.view_layer.objects.active = knife
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=True,
        export_attributes=True,
    )
    return {"file": "game/assets/slice/tactical_knife.glb", "bytes": out_path.stat().st_size, "polys": len(knife.data.polygons)}


# ---------------------------------------------------------------------------
# 3. Sculpted Open-World Looting Props (v064_world_props.glb)
# ---------------------------------------------------------------------------

def _add_oct_frustum_uv(bm: bmesh.types.BMesh, y0: float, y1: float, r0: float, r1: float, segs: int = 8) -> None:
    uv_layer = bm.loops.layers.uv.verify()
    ring0, ring1 = [], []
    for k in range(segs):
        ang = (k + 0.5) * math.tau / segs
        ca, sa = math.cos(ang), math.sin(ang)
        ring0.append(bm.verts.new(gd_to_bl(Vector((ca * r0, y0, sa * r0)))))
        ring1.append(bm.verts.new(gd_to_bl(Vector((ca * r1, y1, sa * r1)))))
    for k in range(segs):
        nk = (k + 1) % segs
        f = bm.faces.new((ring0[k], ring0[nk], ring1[nk], ring1[k]))
        for lp, uv in zip(f.loops, [(k / segs, y0 * 1.5), ((k + 1) / segs, y0 * 1.5), ((k + 1) / segs, y1 * 1.5), (k / segs, y1 * 1.5)]):
            lp[uv_layer].uv = uv
    f_bot = bm.faces.new(list(reversed(ring0)))
    for lp in f_bot.loops:
        lp[uv_layer].uv = (0.5 + lp.vert.co.x, 0.5 + lp.vert.co.y)
    f_top = bm.faces.new(ring1)
    for lp in f_top.loops:
        lp[uv_layer].uv = (0.5 + lp.vert.co.x, 0.5 + lp.vert.co.y)


def build_world_props() -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    limestone_tex = GEN_V062 / "limestone_karst.png"
    bark_tex = GEN_V061 / "japanese_camphor_bark_diff_512.jpg"

    m_bluestone = make_vcol_pbr_mat("Mat_V064_Bluestone", (0.44, 0.49, 0.46), roughness=0.86, tex_path=limestone_tex if limestone_tex.exists() else None)
    m_moss = make_vcol_pbr_mat("Mat_V064_MossRock", (0.28, 0.42, 0.30), roughness=0.90, tex_path=limestone_tex if limestone_tex.exists() else None)
    m_twig = make_vcol_pbr_mat("Mat_V064_WovenTwig", (0.38, 0.28, 0.19), roughness=0.92, tex_path=bark_tex if bark_tex.exists() else None)
    m_straw = make_vcol_pbr_mat("Mat_V064_DryStraw", (0.58, 0.48, 0.30), roughness=0.90)
    m_egg = make_vcol_pbr_mat("Mat_V064_BirdEgg", (0.86, 0.84, 0.76), roughness=0.62)
    m_case_body = make_vcol_pbr_mat("Mat_V064_CaseArmor", (0.16, 0.22, 0.23), metallic=0.45, roughness=0.52)
    m_case_bumper = make_vcol_pbr_mat("Mat_V064_CaseBumper", (0.11, 0.13, 0.14), metallic=0.15, roughness=0.78)
    m_case_bronze = make_vcol_pbr_mat("Mat_V064_CaseBronze", (0.76, 0.60, 0.30), metallic=0.82, roughness=0.34)

    # 3A. prop_stone_pedestal: Jiangnan Octagonal Sumidero Waisted Stone Altar (top strictly at y = 0.44m!)
    bm_ped = bmesh.new()
    _add_oct_frustum_uv(bm_ped, -0.14, 0.10, 0.48, 0.44, segs=8)   # Grounded mossy plinth
    _add_oct_frustum_uv(bm_ped, 0.10, 0.17, 0.43, 0.32, segs=8)    # Lower lotus bevel
    _add_oct_frustum_uv(bm_ped, 0.17, 0.29, 0.30, 0.30, segs=8)    # Recessed carved waist (束腰)
    _add_oct_frustum_uv(bm_ped, 0.29, 0.37, 0.32, 0.43, segs=8)    # Upper lotus flare
    _add_oct_frustum_uv(bm_ped, 0.37, 0.44, 0.44, 0.42, segs=8)    # Carved top slab at exact y = 0.44m!
    bm_ped_moss = bmesh.new()
    for mi, ang in enumerate((0.4, 2.5, 4.7)):
        c = gd_to_bl(Vector((math.cos(ang) * 0.41, 0.04, math.sin(ang) * 0.41)))
        bmesh.ops.create_icosphere(bm_ped_moss, subdivisions=1, radius=0.11, matrix=Matrix.Translation(c) @ Matrix.Scale(0.55, 4, (0, 0, 1)))
    p_ped_s = create_mesh_obj("PedStone", bm_ped, m_bluestone, smooth=False)
    p_ped_m = create_mesh_obj("PedMoss", bm_ped_moss, m_moss, smooth=True)
    obj_pedestal = join_objs("prop_stone_pedestal", [p_ped_s, p_ped_m])

    # 3B. prop_bird_nest: Interwoven Multi-Twig Nest on Gnarled Mossy Root-Rock + 3 Eggs
    rng = random.Random(6410)
    bm_rock = bmesh.new()
    for rx, ry, rz, rr, sx, sz in (
        (0.0, 0.09, 0.0, 0.36, 1.15, 0.52),
        (-0.18, 0.16, 0.12, 0.22, 1.0, 0.65),
        (0.20, 0.15, -0.10, 0.20, 1.05, 0.60),
    ):
        m_xf = Matrix.Translation(gd_to_bl(Vector((rx, ry, rz)))) @ Matrix.Diagonal((sx, sx, sz, 1.0))
        res = bmesh.ops.create_icosphere(bm_rock, subdivisions=2, radius=rr, matrix=m_xf)
        for v in res["verts"]:
            v.co += Vector((rng.uniform(-0.022, 0.022), rng.uniform(-0.022, 0.022), rng.uniform(-0.015, 0.015)))

    bm_twigs = bmesh.new()
    # 28 overlapping criss-crossed woven twigs forming an authentic rustic bird nest cup!
    for ti in range(28):
        a0 = (ti / 28.0) * math.tau + rng.uniform(-0.12, 0.12)
        span = rng.uniform(1.15, 1.85)
        h_ring = 0.24 + (ti % 4) * 0.032 + rng.uniform(-0.01, 0.01)
        r_ring = 0.19 + (ti % 3) * 0.028
        pts = []
        for s in range(4):
            ang = a0 + span * (s / 3.0)
            rad = r_ring + rng.uniform(-0.018, 0.018)
            pts.append(gd_to_bl(Vector((math.cos(ang) * rad, h_ring + 0.018 * math.sin(s * 2.0), math.sin(ang) * rad))))
        # 4-sided rustic twig stick along pts
        rings_t = []
        for idx_p, pt in enumerate(pts):
            tang = (pts[min(3, idx_p + 1)] - pts[max(0, idx_p - 1)]).normalized()
            up_v = Vector((0, 0, 1))
            r_v = tang.cross(up_v).normalized()
            u_v = r_v.cross(tang).normalized()
            tr = 0.014 if idx_p in (1, 2) else 0.008
            rings_t.append([bm_twigs.verts.new(pt + r_v * (math.cos(k * math.pi * 0.5) * tr) + u_v * (math.sin(k * math.pi * 0.5) * tr)) for k in range(4)])
        for idx_p in range(3):
            for k in range(4):
                nk = (k + 1) % 4
                bm_twigs.faces.new((rings_t[idx_p][k], rings_t[idx_p][nk], rings_t[idx_p + 1][nk], rings_t[idx_p + 1][k]))

    # Soft dry straw lining inside the nest cup
    bm_lining = bmesh.new()
    bmesh.ops.create_icosphere(bm_lining, subdivisions=1, radius=0.17, matrix=Matrix.Translation(gd_to_bl(Vector((0.0, 0.24, 0.0)))) @ Matrix.Diagonal((1.0, 1.0, 0.32, 1.0)))

    # 3 oval bird eggs nestled in the straw
    bm_eggs = bmesh.new()
    for ex, ez, yaw_e in ((-0.055, 0.025, 0.4), (0.052, 0.032, -0.6), (0.005, -0.048, 1.2)):
        m_e = Matrix.Translation(gd_to_bl(Vector((ex, 0.305, ez)))) @ Euler((0.18, 0.12, yaw_e), "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((0.82, 0.82, 1.16, 1.0))
        bmesh.ops.create_icosphere(bm_eggs, subdivisions=2, radius=0.046, matrix=m_e)

    obj_nest = join_objs("prop_bird_nest", [
        create_mesh_obj("NestRock", bm_rock, m_moss, smooth=False),
        create_mesh_obj("NestStraw", bm_lining, m_straw, smooth=True),
        create_mesh_obj("NestTwigs", bm_twigs, m_twig, smooth=False),
        create_mesh_obj("NestEggs", bm_eggs, m_egg, smooth=True),
    ])

    # 3C. prop_karst_crevice: Jagged Eroded Taihu Limestone Rock Formation with Treasure Cleft
    bm_karst = bmesh.new()
    for kx, ky, kz, kr, sx, sy, sz in (
        (-0.18, 0.22, 0.02, 0.28, 0.85, 0.95, 1.35),
        (0.19, 0.20, -0.02, 0.26, 0.82, 0.92, 1.25),
        (0.0, 0.06, 0.16, 0.22, 1.25, 0.80, 0.55),
    ):
        m_k = Matrix.Translation(gd_to_bl(Vector((kx, ky, kz)))) @ Matrix.Diagonal((sx, sy, sz, 1.0))
        res = bmesh.ops.create_icosphere(bm_karst, subdivisions=2, radius=kr, matrix=m_k)
        for v in res["verts"]:
            v.co += Vector((rng.uniform(-0.028, 0.028), rng.uniform(-0.028, 0.028), rng.uniform(-0.025, 0.025)))
    bm_kmoss = bmesh.new()
    bmesh.ops.create_icosphere(bm_kmoss, subdivisions=1, radius=0.38, matrix=Matrix.Translation(gd_to_bl(Vector((0.0, 0.03, 0.0)))) @ Matrix.Diagonal((1.1, 0.95, 0.28, 1.0)))
    obj_crevice = join_objs("prop_karst_crevice", [
        create_mesh_obj("KarstStones", bm_karst, m_bluestone, smooth=False),
        create_mesh_obj("KarstMoss", bm_kmoss, m_moss, smooth=True),
    ])

    # 3D. prop_squad_drop_case: Chamfered Tactical Armored Loot Case with Bumpers & Bronze Latches
    bm_cb = bmesh.new()
    bmesh.ops.create_cube(bm_cb, size=1.0, matrix=Matrix.Translation(gd_to_bl(Vector((0.0, 0.16, 0.0)))) @ Matrix.Diagonal((0.68, 0.46, 0.30, 1.0)))
    for rib_x in (-0.20, 0.0, 0.20):
        bmesh.ops.create_cube(bm_cb, size=1.0, matrix=Matrix.Translation(gd_to_bl(Vector((rib_x, 0.315, 0.0)))) @ Matrix.Diagonal((0.07, 0.42, 0.03, 1.0)))
    p_cb = create_mesh_obj("CaseBody", bm_cb, m_case_body, smooth=False)

    bm_bump = bmesh.new()
    for sx in (-0.33, 0.33):
        for sz in (-0.22, 0.22):
            bmesh.ops.create_cube(bm_bump, size=1.0, matrix=Matrix.Translation(gd_to_bl(Vector((sx, 0.165, sz)))) @ Matrix.Diagonal((0.09, 0.09, 0.33, 1.0)))
    p_bump = create_mesh_obj("CaseBumpers", bm_bump, m_case_bumper, smooth=False)

    bm_lat = bmesh.new()
    for lx in (-0.18, 0.18):
        for sz in (-0.238, 0.238):
            bmesh.ops.create_cube(bm_lat, size=1.0, matrix=Matrix.Translation(gd_to_bl(Vector((lx, 0.21, sz)))) @ Matrix.Diagonal((0.065, 0.025, 0.09, 1.0)))
    p_lat = create_mesh_obj("CaseLatches", bm_lat, m_case_bronze, smooth=False)
    obj_case = join_objs("prop_squad_drop_case", [p_cb, p_bump, p_lat])

    for o in (obj_pedestal, obj_nest, obj_crevice, obj_case):
        o.location = (0.0, 0.0, 0.0)

    out_path = DEST / "v064_world_props.glb"
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = obj_pedestal
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=True,
        export_attributes=True,
    )
    return {
        "file": "game/assets/slice/v064_world_props.glb",
        "bytes": out_path.stat().st_size,
        "props": {o.name: len(o.data.polygons) for o in (obj_pedestal, obj_nest, obj_crevice, obj_case)},
    }


if __name__ == "__main__":
    r_info = build_ys04_rifle()
    k_info = build_qinglu_knife()
    p_info = build_world_props()
    summary = {"rifle": r_info, "knife": k_info, "world_props": p_info}
    (DOCS / "slice-v064-assets-build.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print("V064_ASSETS_BUILT", json.dumps(summary, ensure_ascii=False), flush=True)
