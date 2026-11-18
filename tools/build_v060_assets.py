"""Build v0.6.0 CC0 3D Jiangnan rural heritage & mountain trail landmarks in Blender 4.5.

Generated assets (exported into game/assets/slice/v060_jiangnan_assets.glb):
- wangdao_pavilion      (Jiangnan timber flying-eave lookout pavilion with tea table & gilded plaque)
- stone_arch_bridge     (Walkable 10.4m carved Jiangnan single-arch bluestone creek bridge)
- boundary_stele        (Carved bluestone wayside trail marker between Chengzhuang & Yanshan)
- poem_stele_pavilion   (Carved bluestone poetry stele on molded plinth under tiled eave canopy)
- ancient_camphor       (Gnarled multi-root century camphor tree with blessing silk ribbons)
- wayside_shrine        (Mossy grey-brick earth-god wayside shrine with niche & incense burner)
- bluestone_flagstone   (Beveled weathered slate paver stone for MultiMesh ancient footpath trails)

Run headless:
  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --factory-startup --python tools/build_v060_assets.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import random
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
TEX_DIR = ROOT / "tools" / "generated_v060"
DEST = ROOT / "game" / "assets" / "slice"
DOCS = ROOT / "docs"
DEST.mkdir(parents=True, exist_ok=True)
DOCS.mkdir(parents=True, exist_ok=True)


def gd_to_bl(v: Vector) -> Vector:
    """Map Godot local coords (x_right, y_up, z_back) to Blender Z-up before export_yup=True."""
    return Vector((v.x, -v.z, v.y))


def _srgb_to_lin(c: tuple[float, float, float]) -> tuple[float, float, float, float]:
    return (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)


def make_mat(
    name: str,
    srgb: tuple[float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.72,
    emission_srgb: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = _srgb_to_lin(srgb)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission_srgb is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = _srgb_to_lin(emission_srgb)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def make_tex_mat(name: str, image_path: Path, roughness: float = 0.78) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    tex_node = nt.nodes.new("ShaderNodeTexImage")
    tex_node.image = bpy.data.images.load(str(image_path))
    nt.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def add_box(
    bm: bmesh.types.BMesh,
    center_gd: tuple[float, float, float],
    size_gd: tuple[float, float, float],
    rot_deg_gd: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> None:
    c = gd_to_bl(Vector(center_gd))
    rx, ry, rz = (math.radians(rot_deg_gd[0]), math.radians(rot_deg_gd[1]), math.radians(rot_deg_gd[2]))
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    mat = Matrix.Translation(c) @ rot @ Matrix.Diagonal((size_gd[0], size_gd[2], size_gd[1], 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat)


def add_cyl(
    bm: bmesh.types.BMesh,
    p0_gd: tuple[float, float, float],
    p1_gd: tuple[float, float, float],
    r0: float,
    r1: float,
    segs: int = 10,
) -> None:
    a = gd_to_bl(Vector(p0_gd))
    b = gd_to_bl(Vector(p1_gd))
    vec = b - a
    length = vec.length
    if length < 1e-6:
        return
    mid = (a + b) * 0.5
    q = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(mid) @ q
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=r0,
        radius2=r1,
        depth=length,
        matrix=mat,
    )


def add_ellipsoid(
    bm: bmesh.types.BMesh,
    center_gd: tuple[float, float, float],
    radii_gd: tuple[float, float, float],
    rot_deg_gd: tuple[float, float, float] = (0.0, 0.0, 0.0),
    subdiv: int = 2,
    wobble_seed: int = 0,
    wobble_amp: float = 0.0,
) -> None:
    c = gd_to_bl(Vector(center_gd))
    rx, ry, rz = (math.radians(rot_deg_gd[0]), math.radians(rot_deg_gd[1]), math.radians(rot_deg_gd[2]))
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    verts = ret["verts"]
    rng = random.Random(wobble_seed) if wobble_amp > 0.0 else None
    scale = Matrix.Diagonal((radii_gd[0], radii_gd[2], radii_gd[1], 1.0))
    xf = Matrix.Translation(c) @ rot @ scale
    for v in verts:
        p = v.co.copy()
        if rng is not None:
            p *= 1.0 + rng.uniform(-wobble_amp, wobble_amp)
        v.co = xf @ p


def add_prism(
    bm: bmesh.types.BMesh,
    p_quad0: list[Vector],
    p_quad1: list[Vector],
) -> None:
    """Create a 6-faced hexahedron between two 4-vertex Godot loops [BL, BR, TR, TL]."""
    v0 = [bm.verts.new(gd_to_bl(p)) for p in p_quad0]
    v1 = [bm.verts.new(gd_to_bl(p)) for p in p_quad1]
    bm.faces.new(v0)
    bm.faces.new(list(reversed(v1)))
    for i in range(4):
        ni = (i + 1) % 4
        bm.faces.new([v0[i], v0[ni], v1[ni], v1[i]])


def add_uv_quad_gd(
    bm: bmesh.types.BMesh,
    center_gd: tuple[float, float, float],
    right_gd: tuple[float, float, float],
    up_gd: tuple[float, float, float],
    width: float,
    height: float,
) -> None:
    """Create a single UV-mapped front quad (0..1) in Godot coords with normal = right x up? Wait check winding."""
    uv_layer = bm.loops.layers.uv.verify()
    c = Vector(center_gd)
    r = Vector(right_gd).normalized() * (width * 0.5)
    u = Vector(up_gd).normalized() * (height * 0.5)
    corners_gd = [c - r - u, c + r - u, c + r + u, c - r + u]
    uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    verts = [bm.verts.new(gd_to_bl(p)) for p in corners_gd]
    face = bm.faces.new(verts)
    for loop, uv in zip(face.loops, uvs):
        loop[uv_layer].uv = uv


def auto_box_uv(bm: bmesh.types.BMesh, uv_scale: float = 0.62) -> None:
    """Assign clean world/object-scale box-projected UVs in Godot meter space."""
    uv_layer = bm.loops.layers.uv.verify()
    bm.normal_update()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for lp in f.loops:
            # Blender coords: x = gd_x, y = -gd_z, z = gd_y (height)
            co = lp.vert.co
            if az >= ax and az >= ay:
                lp[uv_layer].uv = (co.x * uv_scale, -co.y * uv_scale)
            elif ax >= ay:
                lp[uv_layer].uv = (-co.y * uv_scale, co.z * uv_scale)
            else:
                lp[uv_layer].uv = (co.x * uv_scale, co.z * uv_scale)


def create_part(
    name: str,
    bm: bmesh.types.BMesh,
    mat: bpy.types.Material,
    smooth: bool = False,
    recalc_normals: bool = True,
    uv_scale: float | None = 0.62,
) -> bpy.types.Object:
    if recalc_normals and len(bm.faces) > 0:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if uv_scale is not None and len(bm.faces) > 0:
        auto_box_uv(bm, uv_scale=uv_scale)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    if len(mesh.vertices) > 0 and mesh.color_attributes.get("Color") is None:
        ca = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
        zs = [v.co.z for v in mesh.vertices]
        z_min, z_max = min(zs), max(zs)
        z_span = max(0.25, z_max - z_min)
        for vi, v in enumerate(mesh.vertices):
            # R: height normalized (0 at plinth base -> 1 under roof eave), G: grounding AO
            h_norm = max(0.0, min(1.0, (v.co.z - z_min) / z_span))
            ao = 0.72 + 0.28 * min(1.0, max(0.0, (v.co.z + 0.15) / 0.85))
            ca.data[vi].color = (h_norm, ao, 1.0, 1.0)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def join_parts(target_name: str, parts: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = target_name
    obj.data.name = target_name + "_Mesh"
    return obj


def _eave_roof_height(u: float, v: float, half_span: float, eave_y: float, peak_y: float, upturn: float) -> float:
    """Traditional Chinese curved pyramidal roof height y(u, v) with concave sag and upturned corner eaves."""
    r = max(abs(u), abs(v)) / max(half_span, 1e-4)
    # Concave sweeping profile from spire (r=0 -> 1.0) down to eaves (r=1 -> 0.0)
    sag = max(0.0, 1.0 - r) ** 1.48
    corner = min(abs(u), abs(v)) / max(half_span, 1e-4)
    # Corners sweep upward as both |u| and |v| approach half_span
    wing_lift = upturn * (corner ** 1.7) * (r ** 1.6)
    return eave_y + (peak_y - eave_y) * sag + wing_lift


def _build_jiangnan_roof_into_bms(
    bm_tile: bmesh.types.BMesh,
    bm_plaster: bmesh.types.BMesh,
    bm_rib: bmesh.types.BMesh,
    half_span: float,
    eave_y: float,
    peak_y: float,
    upturn: float,
    grid_n: int = 8,
    thickness: float = 0.085,
) -> None:
    """Build sweeping double-layered Chinese flying-eave roof shell, whitewashed soffit fascia, and ridge ribs."""
    # Grid of vertices across [-half_span, half_span]^2 split by diagonals
    top_v: list[list[bmesh.types.BMVert]] = []
    bot_v: list[list[bmesh.types.BMVert]] = []
    p_top_v: list[list[bmesh.types.BMVert]] = []
    p_bot_v: list[list[bmesh.types.BMVert]] = []
    step = (2.0 * half_span) / grid_n
    for ix in range(grid_n + 1):
        row_t, row_b = [], []
        prow_t, prow_b = [], []
        x = -half_span + ix * step
        for iz in range(grid_n + 1):
            z = -half_span + iz * step
            h = _eave_roof_height(x, z, half_span, eave_y, peak_y, upturn)
            row_t.append(bm_tile.verts.new(gd_to_bl(Vector((x, h + thickness, z)))))
            row_b.append(bm_tile.verts.new(gd_to_bl(Vector((x, h, z)))))
            prow_t.append(bm_plaster.verts.new(gd_to_bl(Vector((x, h + 0.01, z)))))
            prow_b.append(bm_plaster.verts.new(gd_to_bl(Vector((x, h - 0.055, z)))))
        top_v.append(row_t)
        bot_v.append(row_b)
        p_top_v.append(prow_t)
        p_bot_v.append(prow_b)

    for ix in range(grid_n):
        for iz in range(grid_n):
            bm_tile.faces.new([top_v[ix][iz], top_v[ix][iz + 1], top_v[ix + 1][iz + 1], top_v[ix + 1][iz]])
            bm_tile.faces.new([bot_v[ix][iz], bot_v[ix + 1][iz], bot_v[ix + 1][iz + 1], bot_v[ix][iz + 1]])
            bm_plaster.faces.new([p_bot_v[ix][iz], p_bot_v[ix + 1][iz], p_bot_v[ix + 1][iz + 1], p_bot_v[ix][iz + 1]])

    # Rim edges
    for ix in range(grid_n):
        for z_idx in (0, grid_n):
            a, b = top_v[ix][z_idx], top_v[ix + 1][z_idx]
            c, d = bot_v[ix + 1][z_idx], bot_v[ix][z_idx]
            bm_tile.faces.new([a, b, c, d] if z_idx == 0 else [b, a, d, c])
            pa, pb = p_top_v[ix][z_idx], p_top_v[ix + 1][z_idx]
            pc, pd = p_bot_v[ix + 1][z_idx], p_bot_v[ix][z_idx]
            bm_plaster.faces.new([pa, pb, pc, pd] if z_idx == 0 else [pb, pa, pd, pc])
    for iz in range(grid_n):
        for x_idx in (0, grid_n):
            a, b = top_v[x_idx][iz], top_v[x_idx][iz + 1]
            c, d = bot_v[x_idx][iz + 1], bot_v[x_idx][iz]
            bm_tile.faces.new([b, a, d, c] if x_idx == 0 else [a, b, c, d])
            pa, pb = p_top_v[x_idx][iz], p_top_v[x_idx][iz + 1]
            pc, pd = p_bot_v[x_idx][iz + 1], p_bot_v[x_idx][iz]
            bm_plaster.faces.new([pb, pa, pd, pc] if x_idx == 0 else [pa, pb, pc, pd])

    # 4 corner hip ridge ribs (垂脊) + sculpted barrel-tile ribs along major facets
    steps_r = 7
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            for k in range(steps_r):
                t0 = k / steps_r
                t1 = (k + 1) / steps_r
                u0, v0 = sx * half_span * t0, sz * half_span * t0
                u1, v1 = sx * half_span * t1, sz * half_span * t1
                y0 = _eave_roof_height(u0, v0, half_span, eave_y, peak_y, upturn) + thickness + 0.035
                y1 = _eave_roof_height(u1, v1, half_span, eave_y, peak_y, upturn) + thickness + 0.035
                add_cyl(bm_rib, (u0, y0, v0), (u1, y1, v1), 0.055 if k < 6 else 0.068, 0.052 if k < 6 else 0.038, segs=6)
            # Corner upturned horn finial
            tip_x, tip_z = sx * half_span * 1.04, sz * half_span * 1.04
            tip_y = _eave_roof_height(sx * half_span, sz * half_span, half_span, eave_y, peak_y, upturn) + thickness + 0.14
            add_cyl(
                bm_rib,
                (sx * half_span * 0.94, tip_y - 0.08, sz * half_span * 0.94),
                (tip_x, tip_y, tip_z),
                0.055,
                0.022,
                segs=6,
            )

    # Radial tile ribs along North/South/East/West slopes
    for side in range(4):
        for off in (-0.62, -0.31, 0.0, 0.31, 0.62):
            for k in range(1, steps_r):
                t0, t1 = k / steps_r, (k + 1) / steps_r
                r0, r1 = half_span * t0, half_span * t1
                if side == 0:
                    p0, p1 = (r0, r0 * off), (r1, r1 * off)
                elif side == 1:
                    p0, p1 = (-r0, r0 * off), (-r1, r1 * off)
                elif side == 2:
                    p0, p1 = (r0 * off, r0), (r1 * off, r1)
                else:
                    p0, p1 = (r0 * off, -r0), (r1 * off, -r1)
                y0 = _eave_roof_height(p0[0], p0[1], half_span, eave_y, peak_y, upturn) + thickness + 0.014
                y1 = _eave_roof_height(p1[0], p1[1], half_span, eave_y, peak_y, upturn) + thickness + 0.014
                add_cyl(bm_tile, (p0[0], y0, p0[1]), (p1[0], y1, p1[1]), 0.022, 0.022, segs=5)


def build_wangdao_pavilion() -> bpy.types.Object:
    m_stone = make_mat("Mat_JN_Bluestone", (0.34, 0.37, 0.36), roughness=0.86)
    m_stone_light = make_mat("Mat_JN_Granite", (0.50, 0.52, 0.49), roughness=0.82)
    m_wood = make_mat("Mat_JN_AgedCedar", (0.28, 0.14, 0.09), roughness=0.68)
    m_beam = make_mat("Mat_JN_BeamRed", (0.38, 0.13, 0.09), roughness=0.62)
    m_tile = make_mat("Mat_JN_SlateTile", (0.14, 0.16, 0.18), roughness=0.72)
    m_plaster = make_mat("Mat_JN_LimePlaster", (0.86, 0.85, 0.80), roughness=0.88)
    m_gold = make_mat("Mat_JN_GiltFinial", (0.76, 0.56, 0.22), metallic=0.62, roughness=0.34)
    m_porcelain = make_mat("Mat_JN_Celadon", (0.54, 0.72, 0.65), roughness=0.28)
    m_plaque = make_tex_mat("Mat_JN_WangdaoPlaque", TEX_DIR / "plaque_wangdao.png", roughness=0.52)

    parts = []
    bm_stone = bmesh.new()
    bm_granite = bmesh.new()
    bm_wood = bmesh.new()
    bm_beam = bmesh.new()
    bm_tile = bmesh.new()
    bm_plaster = bmesh.new()
    bm_gold = bmesh.new()
    bm_tea = bmesh.new()
    bm_plaque = bmesh.new()

    # Grounded 2-tier bluestone terrace with underground skirt down to y=-0.52
    add_box(bm_stone, (0.0, -0.18, 0.0), (4.45, 0.68, 4.45))
    add_box(bm_granite, (0.0, 0.21, 0.0), (3.92, 0.14, 3.92))
    # Wide West (-X) and South (+Z) entry stone steps
    add_box(bm_granite, (-2.34, 0.07, 0.0), (0.62, 0.22, 1.95))
    add_box(bm_granite, (0.0, 0.07, 2.34), (1.95, 0.22, 0.62))

    # 4 corner carved drum plinths (柱础) & aged cedar columns
    col_off = 1.60
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            px, pz = sx * col_off, sz * col_off
            add_cyl(bm_granite, (px, 0.28, pz), (px, 0.44, pz), 0.22, 0.16, segs=10)
            add_cyl(bm_wood, (px, 0.42, pz), (px, 2.66, pz), 0.115, 0.105, segs=10)
            # Decorative carved corbel brackets (雀替) near top
            for dx, dz in ((-sx * 0.44, 0.0), (0.0, -sz * 0.44)):
                add_box(bm_beam, (px + dx * 0.55, 2.38, pz + dz * 0.55), (0.48 if dx else 0.12, 0.20, 0.48 if dz else 0.12))

    # Perimeter lintel beams (额枋) + upper white-lime fascia band
    for side_z in (-col_off, col_off):
        add_box(bm_beam, (0.0, 2.52, side_z), (3.44, 0.20, 0.15))
        add_box(bm_plaster, (0.0, 2.66, side_z), (3.32, 0.11, 0.12))
    for side_x in (-col_off, col_off):
        add_box(bm_beam, (side_x, 2.52, 0.0), (0.15, 0.20, 3.44))
        add_box(bm_plaster, (side_x, 2.66, 0.0), (0.12, 0.11, 3.32))

    # Traditional 美人靠 bench & waist-high overlook balustrade:
    # North (-Z): full timber bench & slatted backrest
    add_box(bm_wood, (0.0, 0.64, -1.56), (2.96, 0.09, 0.42))
    add_box(bm_wood, (0.0, 1.06, -1.72), (2.96, 0.07, 0.09))
    for bx in (-1.2, -0.8, -0.4, 0.0, 0.4, 0.8, 1.2):
        add_box(bm_beam, (bx, 0.84, -1.71), (0.06, 0.36, 0.05))
    # East (+X): waist-high overlook balustrade (y=0.86m) looking directly over rice paddies
    add_box(bm_wood, (1.58, 0.86, 0.0), (0.11, 0.08, 2.98))
    add_box(bm_wood, (1.58, 0.38, 0.0), (0.10, 0.12, 2.98))
    for bz in (-1.2, -0.8, -0.4, 0.0, 0.4, 0.8, 1.2):
        add_box(bm_beam, (1.58, 0.62, bz), (0.06, 0.44, 0.06))
    # Short corner rail wings on West (-X) and South (+Z) framing wide 1.8m walk-in doorways
    for sz in (-1.0, 1.0):
        add_box(bm_wood, (-1.60, 0.82, sz * 1.24), (0.10, 0.07, 0.64))
        add_box(bm_beam, (-1.60, 0.56, sz * 1.22), (0.06, 0.48, 0.06))
    for sx in (-1.0, 1.0):
        add_box(bm_wood, (sx * 1.24, 0.82, 1.60), (0.64, 0.07, 0.10))
        add_box(bm_beam, (sx * 1.22, 0.56, 1.60), (0.06, 0.48, 0.06))

    # Sweeping dark-tile upturned Jiangnan pyramidal roof (double eave silhouette)
    _build_jiangnan_roof_into_bms(bm_tile, bm_plaster, bm_tile, 2.58, 2.66, 3.68, 0.24, grid_n=8, thickness=0.075)
    _build_jiangnan_roof_into_bms(bm_tile, bm_plaster, bm_tile, 1.48, 3.36, 4.24, 0.16, grid_n=6, thickness=0.070)
    # Central bronze/gilt gourd roof finial (宝顶)
    add_cyl(bm_gold, (0.0, 4.18, 0.0), (0.0, 4.34, 0.0), 0.18, 0.10, segs=10)
    add_ellipsoid(bm_gold, (0.0, 4.44, 0.0), (0.11, 0.15, 0.11), subdiv=1)
    add_cyl(bm_gold, (0.0, 4.55, 0.0), (0.0, 4.72, 0.0), 0.045, 0.012, segs=8)

    # Center carved granite round table, 2 stone stools, and celadon teapot + cups
    add_cyl(bm_stone, (0.0, 0.28, 0.0), (0.0, 0.84, 0.0), 0.22, 0.18, segs=10)
    add_cyl(bm_granite, (0.0, 0.84, 0.0), (0.0, 0.92, 0.0), 0.52, 0.50, segs=14)
    for sx in (-0.78, 0.72):
        add_cyl(bm_granite, (sx, 0.28, -0.32), (sx, 0.58, -0.32), 0.18, 0.19, segs=10)
    add_ellipsoid(bm_tea, (-0.06, 0.99, 0.02), (0.095, 0.075, 0.095), subdiv=1)
    add_cyl(bm_tea, (-0.06, 1.05, 0.02), (-0.06, 1.09, 0.02), 0.045, 0.02, segs=8)
    for cx, cz in ((0.16, 0.08), (0.14, -0.14)):
        add_cyl(bm_tea, (cx, 0.92, cz), (cx, 0.98, cz), 0.032, 0.040, segs=8)

    # Gilded engraved plaques "望稻亭" hung over West entrance (-X face) & South entrance (+Z face)
    add_box(bm_wood, (-1.70, 2.38, 0.0), (0.08, 0.52, 1.08))
    add_uv_quad_gd(bm_plaque, (-1.745, 2.38, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 0.98, 0.46)
    add_box(bm_wood, (0.0, 2.38, 1.70), (1.08, 0.52, 0.08))
    add_uv_quad_gd(bm_plaque, (0.0, 2.38, 1.745), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.98, 0.46)

    parts.append(create_part("WangdaoStone", bm_stone, m_stone))
    parts.append(create_part("WangdaoGranite", bm_granite, m_stone_light))
    parts.append(create_part("WangdaoWood", bm_wood, m_wood))
    parts.append(create_part("WangdaoBeam", bm_beam, m_beam))
    parts.append(create_part("WangdaoTile", bm_tile, m_tile))
    parts.append(create_part("WangdaoPlaster", bm_plaster, m_plaster))
    parts.append(create_part("WangdaoGold", bm_gold, m_gold, smooth=True))
    parts.append(create_part("WangdaoTea", bm_tea, m_porcelain, smooth=True))
    parts.append(create_part("WangdaoPlaque", bm_plaque, m_plaque, recalc_normals=False, uv_scale=None))
    return join_parts("wangdao_pavilion", parts)


def _arch_deck_y(x: float) -> float:
    ax = abs(x)
    if ax <= 5.0:
        return 0.24 * (1.0 + math.cos(math.pi * ax / 5.0))
    return -0.22 * min(1.0, (ax - 5.0) / 0.35)


def _arch_intrados_y(x: float) -> float:
    # Single semicircular-parabolic arch opening centered on |x| < 2.25
    ax = abs(x)
    if ax >= 2.25:
        return -1.85
    u = ax / 2.25
    return -1.85 + 2.12 * math.sqrt(max(0.0, 1.0 - u * u))


def build_stone_arch_bridge() -> bpy.types.Object:
    m_deck = make_mat("Mat_BridgeBluestone", (0.38, 0.40, 0.38), roughness=0.86)
    m_rail = make_mat("Mat_BridgeGranite", (0.50, 0.52, 0.48), roughness=0.80)
    m_moss = make_mat("Mat_BridgeMossStone", (0.28, 0.34, 0.26), roughness=0.90)

    parts = []
    bm_deck = bmesh.new()
    bm_rail = bmesh.new()
    bm_moss = bmesh.new()

    half_w = 1.20
    # Sculpted arched stone bridge body & deck across 20 longitudinal stations (-5.3 .. +5.3)
    xs = [-5.30] + [-5.0 + i * 0.555556 for i in range(19)] + [5.30]
    for i in range(len(xs) - 1):
        x0, x1 = xs[i], xs[i + 1]
        y0_top, y1_top = _arch_deck_y(x0), _arch_deck_y(x1)
        y0_bot = max(-1.85, _arch_intrados_y(x0))
        y1_bot = max(-1.85, _arch_intrados_y(x1))
        # Clamp floor beneath abutments at least 0.28m thick below deck
        y0_bot = min(y0_bot, y0_top - 0.28)
        y1_bot = min(y1_bot, y1_top - 0.28)
        q0 = [
            Vector((x0, y0_bot, -half_w)),
            Vector((x0, y0_bot, half_w)),
            Vector((x0, y0_top, half_w)),
            Vector((x0, y0_top, -half_w)),
        ]
        q1 = [
            Vector((x1, y1_bot, -half_w)),
            Vector((x1, y1_bot, half_w)),
            Vector((x1, y1_top, half_w)),
            Vector((x1, y1_top, -half_w)),
        ]
        add_prism(bm_moss if (abs(x0) > 2.3 and abs(x1) > 2.3) else bm_deck, q0, q1)

    # Carved arch voussoir keystone blocks lining North (-Z) and South (+Z) elevation faces
    n_vous = 11
    for k in range(n_vous):
        ang = math.radians(-78.0 + k * (156.0 / (n_vous - 1)))
        cx = 2.28 * math.sin(ang)
        cy = -1.85 + 2.16 * math.cos(ang)
        deg = -math.degrees(ang)
        for sz in (-1.21, 1.21):
            add_box(bm_rail, (cx, cy, sz), (0.34, 0.26, 0.14), (0.0, 0.0, deg))

    # Stepped anti-slip bridge deck stone strips along the 10m walk surface
    for x in [(-4.5 + i * 0.60) for i in range(16)]:
        yt = _arch_deck_y(x)
        slope_deg = -math.degrees(math.atan2(_arch_deck_y(x + 0.2) - _arch_deck_y(x - 0.2), 0.4))
        add_box(bm_deck, (x, yt + 0.015, 0.0), (0.48, 0.04, 2.12), (0.0, 0.0, slope_deg))

    # Wing-wall abutment shoulders anchoring both bridge ends deep into creek banks (-2.2m)
    for sx in (-1.0, 1.0):
        add_box(bm_moss, (sx * 4.55, -1.05, 0.0), (1.70, 2.02, 2.52))
        add_box(bm_deck, (sx * 5.25, -0.58, 0.0), (0.65, 1.12, 2.42))

    # Left & Right stone curb coping + low stone balustrade rails & carved octagonal lotus posts
    post_xs = [-4.65, -2.35, 0.0, 2.35, 4.65]
    for sz in (-1.18, 1.18):
        for i in range(len(post_xs) - 1):
            x0, x1 = post_xs[i], post_xs[i + 1]
            xm = 0.5 * (x0 + x1)
            ym = _arch_deck_y(xm)
            seg_len = abs(x1 - x0)
            tilt = math.degrees(math.atan2(_arch_deck_y(x1) - _arch_deck_y(x0), seg_len))
            add_box(bm_rail, (xm, ym + 0.11, sz), (seg_len + 0.12, 0.22, 0.18), (0.0, 0.0, tilt))
            add_box(bm_rail, (xm, ym + 0.56, sz), (seg_len + 0.06, 0.11, 0.15), (0.0, 0.0, tilt))
            # Carved stone balusters between posts
            for sub in (-0.75, 0.0, 0.75):
                bx = xm + sub
                add_box(bm_deck, (bx, _arch_deck_y(bx) + 0.34, sz), (0.14, 0.36, 0.12))
        for px in post_xs:
            py = _arch_deck_y(px)
            add_box(bm_rail, (px, py + 0.38, sz), (0.24, 0.76, 0.24))
            add_ellipsoid(bm_rail, (px, py + 0.81, sz), (0.11, 0.10, 0.11), subdiv=1)

    parts.append(create_part("BridgeDeck", bm_deck, m_deck))
    parts.append(create_part("BridgeRail", bm_rail, m_rail))
    parts.append(create_part("BridgeMoss", bm_moss, m_moss))
    return join_parts("stone_arch_bridge", parts)


def build_boundary_stele() -> bpy.types.Object:
    m_base = make_mat("Mat_BoundaryPlinth", (0.36, 0.39, 0.35), roughness=0.88)
    m_face = make_tex_mat("Mat_BoundaryFace", TEX_DIR / "stele_boundary.png", roughness=0.82)

    bm_base = bmesh.new()
    # Deeply grounded pedestal base extending -0.52m into slope
    add_box(bm_base, (0.0, -0.18, 0.0), (0.98, 0.68, 0.58))
    add_box(bm_base, (0.0, 0.20, 0.0), (0.82, 0.12, 0.40))
    # Upright tapered tablet body
    add_box(bm_base, (0.0, 0.96, 0.0), (0.68, 1.42, 0.22))
    add_cyl(bm_base, (0.0, 1.66, -0.11), (0.0, 1.66, 0.11), 0.34, 0.34, segs=12)

    bm_face = bmesh.new()
    add_uv_quad_gd(bm_face, (0.0, 0.98, 0.116), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.60, 1.24)
    # Also map reverse face so walking up from behind looks detailed too
    add_uv_quad_gd(bm_face, (0.0, 0.98, -0.116), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.60, 1.24)

    return join_parts(
        "boundary_stele",
        [
            create_part("BoundarySteleBody", bm_base, m_base),
            create_part("BoundarySteleFace", bm_face, m_face, recalc_normals=False, uv_scale=None),
        ],
    )


def build_poem_stele_pavilion() -> bpy.types.Object:
    m_stone = make_mat("Mat_PoemPlinth", (0.36, 0.39, 0.37), roughness=0.86)
    m_granite = make_mat("Mat_PoemCarvedStone", (0.48, 0.50, 0.47), roughness=0.82)
    m_wood = make_mat("Mat_PoemCedar", (0.28, 0.14, 0.09), roughness=0.68)
    m_tile = make_mat("Mat_PoemTile", (0.15, 0.17, 0.19), roughness=0.72)
    m_plaster = make_mat("Mat_PoemPlaster", (0.85, 0.84, 0.78), roughness=0.88)
    m_face = make_tex_mat("Mat_PoemSteleFace", TEX_DIR / "stele_poem.png", roughness=0.80)

    bm_s = bmesh.new()
    bm_g = bmesh.new()
    bm_w = bmesh.new()
    bm_t = bmesh.new()
    bm_p = bmesh.new()
    bm_f = bmesh.new()

    # Grounded platform extending -0.40m downward
    add_box(bm_s, (0.0, -0.12, 0.0), (3.00, 0.64, 2.70))
    add_box(bm_g, (0.0, 0.24, 0.0), (2.60, 0.10, 2.30))

    # 4 corner shelter columns (clear of z=+2.0 entrance!)
    for sx in (-1.08, 1.08):
        for sz in (-0.96, 0.96):
            add_cyl(bm_g, (sx, 0.29, sz), (sx, 0.42, sz), 0.14, 0.11, segs=8)
            add_cyl(bm_w, (sx, 0.40, sz), (sx, 2.38, sz), 0.08, 0.075, segs=8)

    for sz in (-0.96, 0.96):
        add_box(bm_w, (0.0, 2.30, sz), (2.30, 0.14, 0.12))
    for sx in (-1.08, 1.08):
        add_box(bm_w, (sx, 2.30, 0.0), (0.12, 0.14, 2.06))

    # Upturned Jiangnan tile roof canopy
    _build_jiangnan_roof_into_bms(bm_t, bm_p, bm_t, 1.72, 2.38, 3.22, 0.18, grid_n=6, thickness=0.068)
    add_ellipsoid(bm_g, (0.0, 3.30, 0.0), (0.12, 0.14, 0.12), subdiv=1)

    # Molded stele pedestal (须弥座) + upright carved granite stele
    add_box(bm_g, (0.0, 0.36, 0.0), (1.18, 0.24, 0.72))
    add_box(bm_s, (0.0, 0.54, 0.0), (0.98, 0.16, 0.52))
    add_box(bm_g, (0.0, 1.38, 0.0), (0.90, 1.56, 0.22))
    # Rounded stele crown (螭首/碑额)
    add_cyl(bm_g, (0.0, 2.15, -0.11), (0.0, 2.15, 0.11), 0.45, 0.45, segs=12)

    # Front engraved verse face (+Z) & small altar incense bowl
    add_uv_quad_gd(bm_f, (0.0, 1.38, 0.116), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.80, 1.40)
    add_uv_quad_gd(bm_f, (0.0, 1.38, -0.116), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.80, 1.40)
    add_cyl(bm_s, (0.0, 0.29, 0.52), (0.0, 0.48, 0.52), 0.16, 0.19, segs=10)

    return join_parts(
        "poem_stele_pavilion",
        [
            create_part("PoemStone", bm_s, m_stone),
            create_part("PoemGranite", bm_g, m_granite),
            create_part("PoemWood", bm_w, m_wood),
            create_part("PoemTile", bm_t, m_tile),
            create_part("PoemPlaster", bm_p, m_plaster),
            create_part("PoemFace", bm_f, m_face, recalc_normals=False, uv_scale=None),
        ],
    )


def build_ancient_camphor() -> bpy.types.Object:
    gen61 = ROOT / "tools" / "generated_v061"
    bark_diff = gen61 / "japanese_camphor_bark_diff_512.jpg"
    bark_norm = gen61 / "japanese_camphor_bark_norm_512.jpg"
    dab_rgba = gen61 / "camphor_ink_dab.png"

    if bark_diff.exists():
        m_bark = make_tex_mat("Mat_CamphorBark", bark_diff, roughness=0.92)
        if bark_norm.exists():
            nt = m_bark.node_tree
            bsdf = nt.nodes.get("Principled BSDF")
            tn = nt.nodes.new("ShaderNodeTexImage")
            tn.image = bpy.data.images.load(str(bark_norm))
            tn.image.colorspace_settings.name = "Non-Color"
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = 0.85
            nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    else:
        m_bark = make_mat("Mat_CamphorBark", (0.18, 0.18, 0.17), roughness=0.92)

    m_leaf = bpy.data.materials.new(name="Mat_SumiDabLeaf")
    m_leaf.use_nodes = True
    m_leaf.use_backface_culling = False
    nt_l = m_leaf.node_tree
    bsdf_l = nt_l.nodes.get("Principled BSDF")
    bsdf_l.inputs["Roughness"].default_value = 0.92
    if dab_rgba.exists():
        tl = nt_l.nodes.new("ShaderNodeTexImage")
        tl.image = bpy.data.images.load(str(dab_rgba))
        nt_l.links.new(tl.outputs["Color"], bsdf_l.inputs["Base Color"])
        gt = nt_l.nodes.new("ShaderNodeMath")
        gt.operation = "GREATER_THAN"
        gt.inputs[1].default_value = 0.40
        nt_l.links.new(tl.outputs["Alpha"], gt.inputs[0])
        nt_l.links.new(gt.outputs["Value"], bsdf_l.inputs["Alpha"])

    m_silk = make_mat("Mat_BlessingRibbon", (0.62, 0.20, 0.18), roughness=0.72)

    bm_bark = bmesh.new()
    bm_leaf = bmesh.new()
    bm_silk = bmesh.new()
    uv_bark = bm_bark.loops.layers.uv.verify()
    uv_leaf = bm_leaf.loops.layers.uv.verify()

    def _tube_uv(pts_gd, radii, segs=8):
        pts_bl = [gd_to_bl(Vector(p)) for p in pts_gd]
        rings, vcs = [], [0.0]
        for i in range(1, len(pts_bl)):
            vcs.append(vcs[-1] + (pts_bl[i] - pts_bl[i - 1]).length * 0.55)
        pref = Vector((1.0, 0.0, 0.0))
        for idx, p in enumerate(pts_bl):
            tang = (pts_bl[min(len(pts_bl) - 1, idx + 1)] - pts_bl[max(0, idx - 1)]).normalized()
            if abs(tang.dot(pref)) > 0.95:
                pref = Vector((0.0, 1.0, 0.0))
            n1 = (pref - tang * pref.dot(tang)).normalized()
            n2 = tang.cross(n1).normalized()
            pref = n1
            r = radii[idx]
            rings.append([bm_bark.verts.new(p + n1 * (math.cos(s * math.tau / segs) * r) + n2 * (math.sin(s * math.tau / segs) * r)) for s in range(segs)])
        for i in range(len(rings) - 1):
            for s in range(segs):
                ns = (s + 1) % segs
                f = bm_bark.faces.new([rings[i][s], rings[i][ns], rings[i + 1][ns], rings[i + 1][s]])
                for lp, uv in zip(f.loops, [(s / segs, vcs[i]), ((s + 1) / segs, vcs[i]), ((s + 1) / segs, vcs[i + 1]), (s / segs, vcs[i + 1])]):
                    lp[uv_bark].uv = uv

    dab_meta: list[tuple[float, float]] = []

    def _add_camera_dab(center_gd: tuple[float, float, float], size_m: float, rot_rad: float):
        """Non-degenerate 2mm seed quad expanded in vertex shader parallel to camera plane!"""
        c = Vector(center_gd)
        eps = 0.002
        corners = [
            c + Vector((-eps, -eps, 0.0)),
            c + Vector((eps, -eps, 0.0)),
            c + Vector((eps, eps, 0.0)),
            c + Vector((-eps, eps, 0.0)),
        ]
        # Note: Blender image UV (0,0) = bottom-left -> glTF UV (0,1); (1,1) = top-right -> glTF UV (1,0)
        uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        vs = [bm_leaf.verts.new(gd_to_bl(p)) for p in corners]
        f = bm_leaf.faces.new(vs)
        for lp, uv in zip(f.loops, uvs):
            lp[uv_leaf].uv = uv
        dab_meta.append((size_m, rot_rad))

    # Gnarled multi-buttress root base + thick sumi-ink century camphor trunk
    for i in range(6):
        ang = i * math.tau / 6.0 + 0.18
        ca, sa = math.cos(ang), math.sin(ang)
        _tube_uv([(ca * 1.38, -0.52, sa * 1.38), (ca * 0.72, -0.02, sa * 0.72), (ca * 0.34, 0.75, sa * 0.34)], [0.15, 0.24, 0.19], segs=6)
    _tube_uv([(0.0, -0.52, 0.0), (0.12, 1.30, -0.08), (-0.10, 2.85, 0.09)], [0.60, 0.47, 0.38], segs=10)

    # Expressive calligraphy-like crooked dark limbs visibly exposed beneath & between airy leaf dabs ('疏可走马')
    boughs = [
        [(-0.08, 2.50, 0.08), (1.05, 3.25, 0.62), (2.25, 3.95, 1.35), (3.15, 4.55, 1.85)],
        [(-0.08, 2.60, 0.08), (-1.12, 3.35, 0.50), (-2.38, 4.10, 1.12), (-3.22, 4.68, 1.52)],
        [(-0.08, 2.55, 0.08), (0.86, 3.40, -0.92), (1.92, 4.22, -1.92), (2.68, 4.78, -2.62)],
        [(-0.08, 2.52, 0.08), (-0.95, 3.30, -0.88), (-2.02, 4.08, -1.82), (-2.75, 4.62, -2.48)],
        [(-0.04, 2.72, 0.05), (0.42, 4.05, 0.28), (0.88, 5.35, 0.58), (1.22, 6.28, 0.78)],
        [(-0.04, 2.72, 0.05), (-0.44, 4.10, -0.32), (-0.92, 5.42, -0.65), (-1.25, 6.35, -0.86)],
    ]
    rng_c = random.Random(6510)
    for idx, pts in enumerate(boughs):
        _tube_uv(pts, [0.27, 0.20, 0.13, 0.058], segs=7)
        pm = Vector(pts[2])
        pt = Vector(pts[3])
        bd = (pt - Vector(pts[1])).normalized()
        _add_camera_dab(tuple(pm + Vector((0, 0.42, 0))), rng_c.uniform(2.15, 2.45), rng_c.uniform(-0.35, 0.35))
        _add_camera_dab(tuple(pt + Vector((0, 0.22, 0))), rng_c.uniform(2.25, 2.60), rng_c.uniform(-0.35, 0.35))
        for sgn in (-1.0, 1.0):
            lat = Vector((-bd.z * sgn, 0.26, bd.x * sgn)).normalized()
            sd = (bd * 0.70 + lat * 0.70).normalized()
            stip = pm + sd * 1.65
            _tube_uv([tuple(pm), tuple((pm + stip) * 0.5 + Vector((0, 0.12, 0))), tuple(stip)], [0.11, 0.072, 0.036], segs=5)
            _add_camera_dab(tuple(stip + Vector((0, 0.18, 0))), rng_c.uniform(2.05, 2.38), rng_c.uniform(-0.40, 0.40))

    # Airy tiered upper dome brushstroke clouds (leaving visible gaps for gnarled dark branches!)
    upper_dabs = [
        ((0.0, 4.65, 0.0), 2.55),
        ((1.15, 5.25, 0.85), 2.40),
        ((-1.20, 5.30, 0.78), 2.40),
        ((1.05, 5.35, -0.95), 2.35),
        ((-1.10, 5.28, -0.92), 2.35),
        ((0.48, 6.18, 0.35), 2.45),
        ((-0.52, 6.24, -0.38), 2.45),
        ((0.0, 6.62, 0.0), 2.50),
    ]
    for pos_d, sz_d in upper_dabs:
        _add_camera_dab(pos_d, sz_d, rng_c.uniform(-0.32, 0.32))

    # Restrained antique cinnabar prayer silk ribbon ('1% 朱砂点睛')
    add_cyl(bm_silk, (0.0, 2.12, 0.0), (0.02, 2.24, 0.02), 0.43, 0.43, segs=12)
    add_box(bm_silk, (0.39, 1.88, 0.20), (0.05, 0.54, 0.12), (-8.0, 18.0, 12.0))
    add_box(bm_silk, (1.45, 3.30, 0.90), (0.035, 0.64, 0.09), (4.0, 15.0, -6.0))

    p_bark = create_part("CamphorBark", bm_bark, m_bark, smooth=True, uv_scale=None)
    p_leaf = create_part("CamphorLeaves", bm_leaf, m_leaf, smooth=True, recalc_normals=False, uv_scale=None)
    p_silk = create_part("CamphorSilk", bm_silk, m_silk)

    # Pure 100% outward spherical canopy normal transfer + dab size/rotation packed into COLOR_0!
    c_bl = gd_to_bl(Vector((0.0, 4.95, 0.0)))
    l_zs = [v.co.z for v in p_leaf.data.vertices]
    lz_min, lz_max = min(l_zs), max(l_zs)
    lz_span = max(0.3, lz_max - lz_min)
    l_rads = [(v.co - c_bl).length for v in p_leaf.data.vertices]
    l_max_r = max(0.4, max(l_rads))
    ca_leaf = p_leaf.data.color_attributes.get("Color") or p_leaf.data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
    vnorms = []
    for vi, v in enumerate(p_leaf.data.vertices):
        dab_idx = vi // 4
        sz_m, rot_r = dab_meta[min(dab_idx, len(dab_meta) - 1)]
        ov = v.co - c_bl + Vector((0.0, 0.0, 0.55))
        ov = ov.normalized() if ov.length > 1e-4 else Vector((0.0, 0.0, 1.0))
        vnorms.append(ov)  # 100% pure smooth spherical canopy normal!
        rad_t = min(1.0, l_rads[vi] / l_max_r)
        h_t = max(0.0, min(1.0, (v.co.z - lz_min) / lz_span))
        ao = max(0.18, min(1.0, 0.18 + 0.54 * (rad_t ** 0.85) + 0.28 * h_t))
        sz_enc = max(0.0, min(1.0, (sz_m - 1.2) / 2.2))  # decoded as 1.2 + COLOR.b * 2.2
        rot_enc = max(0.0, min(1.0, 0.5 + rot_r / 1.6))
        ca_leaf.data[vi].color = (ao, h_t, sz_enc, rot_enc)
    p_leaf.data.normals_split_custom_set_from_vertices(vnorms)

    ca_bark = p_bark.data.color_attributes.get("Color") or p_bark.data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="POINT")
    for vi, v in enumerate(p_bark.data.vertices):
        ao_b = 0.58 + 0.42 * min(1.0, max(0.0, (v.co.z + 0.20) / 1.1))
        ca_bark.data[vi].color = (ao_b, ao_b, ao_b, 1.0)

    return join_parts("ancient_camphor", [p_bark, p_leaf, p_silk])


def build_wayside_shrine() -> bpy.types.Object:
    """Authentic Hui/Jiangnan '粉墙黛瓦 · 马头墙压顶' Wayside Earth Shrine (土地石龛)."""
    m_stone = make_mat("Mat_ShrineBluestone", (0.34, 0.36, 0.35), roughness=0.78)
    m_plaster = make_mat("Mat_HuiPlasterWall", (0.85, 0.83, 0.78), roughness=0.90)
    m_tile = make_mat("Mat_JiangnanTile", (0.14, 0.16, 0.17), roughness=0.68)
    m_wood = make_mat("Mat_ShrineDarkTimber", (0.19, 0.15, 0.12), roughness=0.76)
    m_dark = make_mat("Mat_ShrineNiche", (0.09, 0.09, 0.09), roughness=0.94)
    m_figure = make_mat("Mat_ShrineIdol", (0.50, 0.48, 0.44), roughness=0.84)
    m_candle = make_mat("Mat_ShrineCandle", (0.72, 0.22, 0.18), roughness=0.58)
    m_flame = make_mat("Mat_ShrineFlame", (1.0, 0.76, 0.34), roughness=0.25, emission_srgb=(1.0, 0.64, 0.22), emission_strength=2.0)

    bm_s = bmesh.new()
    bm_p = bmesh.new()
    bm_t = bmesh.new()
    bm_w = bmesh.new()
    bm_d = bmesh.new()
    bm_fig = bmesh.new()
    bm_c = bmesh.new()
    bm_fl = bmesh.new()

    # Wet carved bluestone Sumidero plinth (-0.28m skirt)
    add_box(bm_s, (0.0, -0.06, 0.0), (1.62, 0.44, 1.38))
    add_box(bm_s, (0.0, 0.24, 0.12), (1.44, 0.14, 1.24))

    # Whitewashed Hui-style plaster walls ('粉墙') with stepped side wing-walls ('马头墙阶梯山墙')!
    add_box(bm_p, (0.0, 0.84, -0.30), (1.24, 1.08, 0.22))  # Back whitewashed wall
    # Stepped side horse-head walls (3 tiers rising toward the ridge + dark-tile copings!)
    for sx in (-0.54, 0.54):
        # Tier 1 (front lower step)
        add_box(bm_p, (sx, 0.76, 0.24), (0.16, 0.92, 0.34))
        add_box(bm_t, (sx, 1.25, 0.25), (0.21, 0.065, 0.40))  # Dark tile马头墙 coping + upturned tip
        add_box(bm_t, (sx, 1.29, 0.44), (0.19, 0.055, 0.07), (-18.0, 0.0, 0.0))
        # Tier 2 (mid step)
        add_box(bm_p, (sx, 0.92, -0.04), (0.16, 1.24, 0.32))
        add_box(bm_t, (sx, 1.57, -0.03), (0.21, 0.065, 0.38))
        # Tier 3 (rear high gable step)
        add_box(bm_p, (sx, 1.04, -0.28), (0.16, 1.48, 0.24))
        add_box(bm_t, (sx, 1.81, -0.28), (0.21, 0.065, 0.30))

    # Dark timber lintel frame around niche opening & recessed shadowy inner chamber
    add_box(bm_w, (-0.38, 0.78, 0.16), (0.08, 0.88, 0.08))
    add_box(bm_w, (0.38, 0.78, 0.16), (0.08, 0.88, 0.08))
    add_box(bm_w, (0.0, 1.24, 0.16), (0.92, 0.10, 0.10))
    add_box(bm_d, (0.0, 0.76, -0.02), (0.76, 0.84, 0.34))

    # Sweeping dark-tile Jiangnan flying-eave roof ('黛瓦飞檐')
    _build_jiangnan_roof_into_bms(bm_t, bm_p, bm_t, 0.92, 1.36, 1.94, 0.15, grid_n=6, thickness=0.058)
    add_box(bm_t, (0.0, 1.96, 0.0), (0.42, 0.08, 0.12))  # Central main ridge spine (正脊)

    # Weathered stone Earth-God & Goddess statues + carved bluestone tripod incense burner (NO neon purple!)
    for sx in (-0.16, 0.16):
        add_cyl(bm_fig, (sx, 0.34, 0.02), (sx, 0.74, 0.02), 0.105, 0.085, segs=8)
        add_ellipsoid(bm_fig, (sx, 0.82, 0.02), (0.072, 0.082, 0.072), subdiv=1)
        add_box(bm_fig, (sx, 0.90, 0.02), (0.13, 0.048, 0.11))
    add_cyl(bm_s, (0.0, 0.31, 0.44), (0.0, 0.46, 0.44), 0.11, 0.13, segs=10)
    for cx in (-0.30, 0.30):
        add_cyl(bm_c, (cx, 0.31, 0.44), (cx, 0.45, 0.44), 0.024, 0.022, segs=6)
        add_ellipsoid(bm_fl, (cx, 0.475, 0.44), (0.016, 0.030, 0.016), subdiv=1)

    return join_parts(
        "wayside_shrine",
        [
            create_part("ShrineStone", bm_s, m_stone),
            create_part("ShrinePlaster", bm_p, m_plaster),
            create_part("ShrineTile", bm_t, m_tile),
            create_part("ShrineWood", bm_w, m_wood),
            create_part("ShrineNiche", bm_d, m_dark),
            create_part("ShrineIdol", bm_fig, m_figure),
            create_part("ShrineCandle", bm_c, m_candle),
            create_part("ShrineFlame", bm_fl, m_flame, smooth=True),
        ],
    )


def build_bluestone_flagstone() -> bpy.types.Object:
    m_flag = make_mat("Mat_FlagstoneSlate", (0.37, 0.40, 0.38), roughness=0.86)
    bm = bmesh.new()
    # Irregular beveled chamfered bluestone slab extending down to y=-0.10m so edges sink into soil cleanly
    add_box(bm, (0.0, -0.01, 0.0), (1.04, 0.16, 0.70))
    add_box(bm, (0.0, 0.055, 0.0), (0.94, 0.05, 0.62))
    obj = create_part("bluestone_flagstone", bm, m_flag)
    return obj


def export_all():
    clear_scene()
    builders = [
        build_wangdao_pavilion,
        build_stone_arch_bridge,
        build_boundary_stele,
        build_poem_stele_pavilion,
        build_ancient_camphor,
        build_wayside_shrine,
        build_bluestone_flagstone,
    ]
    objs = [fn() for fn in builders]
    bpy.context.view_layer.update()

    meta = {}
    total_tris = 0
    for obj in objs:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        tris = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
        total_tris += tris
        bb = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        xs = [p.x for p in bb]
        ys = [p.z for p in bb]  # height before GLTF Yup conversion
        zs = [p.y for p in bb]
        meta[obj.name] = {
            "triangles": tris,
            "godot_bounds_m": {
                "x": [round(min(xs), 3), round(max(xs), 3)],
                "y": [round(min(ys), 3), round(max(ys), 3)],
                "z": [round(-max(zs), 3), round(-min(zs), 3)],
            },
        }
        obj.location = (0.0, 0.0, 0.0)

    bpy.ops.object.select_all(action="SELECT")
    out_path = DEST / "v060_jiangnan_assets.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_materials="EXPORT",
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=True,
        export_attributes=True,
    )
    record = {
        "output": "game/assets/slice/v060_jiangnan_assets.glb",
        "total_triangles": total_tris,
        "assets": meta,
    }
    (DOCS / "slice-v060-assets-build.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(f"Exported {out_path} ({total_tris} tris total)")
    for k, v in meta.items():
        print(" ", k, v["triangles"], "tris", v["godot_bounds_m"])


if __name__ == "__main__":
    export_all()
