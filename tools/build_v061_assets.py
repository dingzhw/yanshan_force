"""Build v0.6.1 Jiangnan botanical trees, Moso bamboo, undergrowth & open-community wildlife in Blender 4.5.

Combines:
- Poly Haven CC0 1K scanned bark & river pebble textures (japanese_camphor_bark, bark_willow,
  trident_maple_bark, river_small_rocks)
- Locally generated 1024x1024 RGBA alpha-cutout botanical boughs & seamless bamboo culm textures
  (camphor_bough.png, willow_curtain.png, maple_tallow_bough.png, bamboo_spray.png, bamboo_culm.png)
- Polyfork CC BY 4.0 3D wildlife & undergrowth meshes refined, grounded, oriented (-Z forward in Godot),
  and wired with vertex-color PBR materials, plus an organic sculpted woodland squirrel.

Outputs:
- game/assets/slice/v061_nature_wildlife.glb
- game/assets/slice/river_pebbles_color.jpg, river_pebbles_normal.jpg, river_pebbles_rough.jpg
- docs/slice-v061-assets.json
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
DL_PF = ROOT / "downloads" / "slice-v061" / "polyfork"
GEN_DIR = ROOT / "tools" / "generated_v061"
SLICE_DIR = ROOT / "game" / "assets" / "slice"
DOCS_DIR = ROOT / "docs"

GEN_DIR.mkdir(parents=True, exist_ok=True)
SLICE_DIR.mkdir(parents=True, exist_ok=True)
DOCS_DIR.mkdir(parents=True, exist_ok=True)


def gd_to_bl(v: Vector) -> Vector:
    """Map Godot local coords (x_right, y_up, z_back; -Z forward) to Blender Z-up (+Y forward)."""
    return Vector((v.x, -v.z, v.y))


def staged_pbr_paths() -> dict[str, Path]:
    staged: dict[str, Path] = {}
    for bark in ("japanese_camphor_bark", "bark_willow", "trident_maple_bark"):
        for out_suf in ("diff", "norm"):
            staged[f"{bark}_{out_suf}"] = GEN_DIR / f"{bark}_{out_suf}_512.jpg"
    return staged


def make_bark_mat(name: str, diff_path: Path, norm_path: Path | None = None, roughness: float = 0.88) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness

    tex_c = nt.nodes.new("ShaderNodeTexImage")
    tex_c.image = bpy.data.images.load(str(diff_path))
    nt.links.new(tex_c.outputs["Color"], bsdf.inputs["Base Color"])

    if norm_path is not None and norm_path.exists():
        tex_n = nt.nodes.new("ShaderNodeTexImage")
        tex_n.image = bpy.data.images.load(str(norm_path))
        tex_n.image.colorspace_settings.name = "Non-Color"
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = 0.85
        nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_cutout_foliage_mat(
    name: str,
    rgba_path: Path,
    roughness: float = 0.66,
    alpha_cutoff: float = 0.40,
) -> bpy.types.Material:
    """Create a glTF MASK (ALPHA_SCISSOR) double-sided botanical leaf material."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0

    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(rgba_path))
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    gt = nt.nodes.new("ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    gt.inputs[1].default_value = alpha_cutoff
    nt.links.new(tex.outputs["Alpha"], gt.inputs[0])
    nt.links.new(gt.outputs["Value"], bsdf.inputs["Alpha"])
    return mat


def make_vcol_mat(name: str, roughness: float = 0.72, metallic: float = 0.0) -> bpy.types.Material:
    """Material driven by mesh Color Attribute 'Color' (exported as glTF COLOR_0)."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic

    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def add_tapered_tube_uv(
    bm: bmesh.types.BMesh,
    pts_gd: list[tuple[float, float, float]],
    radii: list[float],
    segs: int = 8,
    u_scale: float = 1.0,
    v_per_m: float = 0.65,
    cap_tip: bool = True,
) -> None:
    """Sweep a smooth UV-mapped tube along 3D Godot points."""
    uv_layer = bm.loops.layers.uv.verify()
    pts_bl = [gd_to_bl(Vector(p)) for p in pts_gd]
    rings: list[list[bmesh.types.BMVert]] = []
    v_coords: list[float] = [0.0]

    for i in range(1, len(pts_bl)):
        v_coords.append(v_coords[-1] + (pts_bl[i] - pts_bl[i - 1]).length * v_per_m)

    prev_ref = Vector((1.0, 0.0, 0.0))
    for idx, p in enumerate(pts_bl):
        if idx == 0:
            tang = (pts_bl[1] - pts_bl[0]).normalized()
        elif idx == len(pts_bl) - 1:
            tang = (pts_bl[-1] - pts_bl[-2]).normalized()
        else:
            tang = (pts_bl[idx + 1] - pts_bl[idx - 1]).normalized()
        if abs(tang.dot(prev_ref)) > 0.96:
            prev_ref = Vector((0.0, 1.0, 0.0))
        n1 = (prev_ref - tang * prev_ref.dot(tang)).normalized()
        n2 = tang.cross(n1).normalized()
        prev_ref = n1

        r = radii[idx]
        ring = []
        for s in range(segs):
            ang = s * math.tau / segs
            off = n1 * (math.cos(ang) * r) + n2 * (math.sin(ang) * r)
            ring.append(bm.verts.new(p + off))
        rings.append(ring)

    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        v0, v1 = v_coords[i], v_coords[i + 1]
        for s in range(segs):
            ns = (s + 1) % segs
            u0 = (s / segs) * u_scale
            u1 = ((s + 1) / segs) * u_scale
            face = bm.faces.new([r0[s], r0[ns], r1[ns], r1[s]])
            for loop, uv in zip(face.loops, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]):
                loop[uv_layer].uv = uv

    if cap_tip and radii[-1] > 0.005:
        tip_v = bm.verts.new(pts_bl[-1])
        r_last = rings[-1]
        v_top = v_coords[-1]
        for s in range(segs):
            ns = (s + 1) % segs
            f = bm.faces.new([r_last[s], r_last[ns], tip_v])
            for loop in f.loops:
                loop[uv_layer].uv = (0.5, v_top)


def add_domed_bough_cluster(
    bm: bmesh.types.BMesh,
    anchor_gd: tuple[float, float, float],
    dir_gd: tuple[float, float, float],
    width: float,
    length: float,
    droop: float = 0.22,
    cup: float = 0.18,
    roll_deg: float = 0.0,
) -> None:
    """Create a 3D crossed-arch foliage bough cluster (never flat edge-on from any angle)."""
    uv_layer = bm.loops.layers.uv.verify()
    a = Vector(anchor_gd)
    fwd = Vector(dir_gd)
    if fwd.length < 1e-4:
        fwd = Vector((0.0, 1.0, 0.0))
    fwd.normalize()
    up_ref = Vector((0.0, 1.0, 0.0)) if abs(fwd.y) < 0.92 else Vector((1.0, 0.0, 0.0))
    right0 = fwd.cross(up_ref).normalized()
    up0 = right0.cross(fwd).normalized()

    # Crossed pair of cupped 2x2 arched leaf shells rotated 58 degrees apart around fwd
    for sheet_ang_deg in (roll_deg, roll_deg + 62.0):
        ang = math.radians(sheet_ang_deg)
        ca, sa = math.cos(ang), math.sin(ang)
        r_vec = right0 * ca + up0 * sa
        u_vec = -right0 * sa + up0 * ca

        # 3x3 grid in UV (u in 0..1 across width, v in 0..1 along length from anchor to tip)
        # Note: Blender image UV (0,0) is bottom-left (anchor base of bough PNG!) and (1,1) is top-right (leaf tips!)
        grid_v: list[list[bmesh.types.BMVert]] = []
        for iv in range(3):
            vt = iv / 2.0
            row = []
            for iu in range(3):
                ut = iu / 2.0
                lat = (ut - 0.5) * width
                # Cupped arch across width + natural gravity droop along length
                arch_lift = cup * width * (1.0 - (2.0 * ut - 1.0) ** 2) * math.sin(math.pi * min(1.0, vt * 0.85 + 0.15))
                grav_drop = droop * length * (vt ** 1.7)
                p_gd = a + fwd * (vt * length) + r_vec * lat + u_vec * arch_lift - Vector((0.0, grav_drop, 0.0))
                row.append(bm.verts.new(gd_to_bl(p_gd)))
            grid_v.append(row)

        for iv in range(2):
            for iu in range(2):
                v00, v10 = grid_v[iv][iu], grid_v[iv][iu + 1]
                v11, v01 = grid_v[iv + 1][iu + 1], grid_v[iv + 1][iu]
                face = bm.faces.new([v00, v10, v11, v01])
                uvs = [
                    (iu / 2.0, iv / 2.0),
                    ((iu + 1) / 2.0, iv / 2.0),
                    ((iu + 1) / 2.0, (iv + 1) / 2.0),
                    (iu / 2.0, (iv + 1) / 2.0),
                ]
                for loop, uv in zip(face.loops, uvs):
                    loop[uv_layer].uv = uv


def add_willow_curtain_drape(
    bm: bmesh.types.BMesh,
    top_center_gd: tuple[float, float, float],
    radial_dir_gd: tuple[float, float, float],
    width: float,
    drop_height: float,
    curve_out: float = 0.35,
) -> None:
    """Create a gently curved vertical weeping-willow frond curtain (top UV v=1 -> bottom UV v=0)."""
    uv_layer = bm.loops.layers.uv.verify()
    tc = Vector(top_center_gd)
    rad = Vector((radial_dir_gd[0], 0.0, radial_dir_gd[2]))
    if rad.length < 1e-4:
        rad = Vector((1.0, 0.0, 0.0))
    rad.normalize()
    tang = Vector((-rad.z, 0.0, rad.x))

    # Build two gently curved intersecting drapes (tangential curtain + radial cross-curtain) so never edge-on!
    for mode in (0, 1):
        span_dir = tang if mode == 0 else (tang * 0.38 + rad * 0.92).normalized()
        out_dir = rad if mode == 0 else (-tang * 0.92 + rad * 0.38).normalized()
        w_use = width if mode == 0 else width * 0.78

        grid_v: list[list[bmesh.types.BMVert]] = []
        for iy in range(4):
            t_down = iy / 3.0  # 0 at top arch, 1 at bottom tips
            row = []
            for ix in range(3):
                ux = ix / 2.0
                lat = (ux - 0.5) * w_use
                # Gentle outward cascade + slight cylindrical wrap
                bulge = curve_out * math.sin(math.pi * 0.65 * t_down) + 0.14 * w_use * (1.0 - (2.0 * ux - 1.0) ** 2)
                p_gd = tc + span_dir * lat + out_dir * bulge - Vector((0.0, t_down * drop_height, 0.0))
                row.append(bm.verts.new(gd_to_bl(p_gd)))
            grid_v.append(row)

        for iy in range(3):
            v_top = 1.0 - (iy / 3.0)
            v_bot = 1.0 - ((iy + 1) / 3.0)
            for ix in range(2):
                u0, u1 = ix / 2.0, (ix + 1) / 2.0
                f = bm.faces.new([grid_v[iy][ix], grid_v[iy][ix + 1], grid_v[iy + 1][ix + 1], grid_v[iy + 1][ix]])
                for loop, uv in zip(f.loops, [(u0, v_top), (u1, v_top), (u1, v_bot), (u0, v_bot)]):
                    loop[uv_layer].uv = uv


def finalize_part(
    name: str,
    bm: bmesh.types.BMesh,
    mat: bpy.types.Material,
    smooth: bool = True,
    canopy_center_gd: tuple[float, float, float] | None = None,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = smooth

    if canopy_center_gd is not None and len(mesh.vertices) > 0:
        center_bl = gd_to_bl(Vector(canopy_center_gd))
        vert_normals = []
        for v in mesh.vertices:
            out_v = v.co - center_bl + Vector((0.0, 0.0, 0.55))
            if out_v.length < 1e-4:
                out_v = Vector((0.0, 0.0, 1.0))
            else:
                out_v.normalize()
            blended = (Vector(v.normal) * 0.22 + out_v * 0.78).normalized()
            vert_normals.append(blended)
        mesh.normals_split_custom_set_from_vertices(vert_normals)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def join_objects(target_name: str, parts: list[bpy.types.Object]) -> bpy.types.Object:
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


def build_tree_camphor(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Authentic Jiangnan Camphor Tree (香樟): gnarled forked trunk + domed glossy leaf crown."""
    bm_bark = bmesh.new()
    bm_leaf = bmesh.new()
    rng = random.Random(6110)

    # Flared buttress roots down to y=-0.50m + slightly sinuous camphor trunk
    for i in range(5):
        ang = i * math.tau / 5.0 + 0.25
        ca, sa = math.cos(ang), math.sin(ang)
        add_tapered_tube_uv(
            bm_bark,
            [(ca * 0.88, -0.48, sa * 0.88), (ca * 0.45, -0.02, sa * 0.45), (ca * 0.20, 0.55, sa * 0.20)],
            [0.10, 0.15, 0.12],
            segs=6,
            cap_tip=False,
        )
    add_tapered_tube_uv(
        bm_bark,
        [(0.0, -0.50, 0.0), (0.05, 0.85, -0.03), (-0.04, 1.95, 0.04), (0.02, 2.75, 0.0)],
        [0.42, 0.33, 0.28, 0.23],
        segs=9,
        cap_tip=False,
    )

    # 6 wide-spreading curved primary boughs + 12 secondary forked limbs
    bough_specs = [
        [(0.02, 2.45, 0.0), (0.72, 3.25, 0.42), (1.68, 3.98, 1.05), (2.42, 4.48, 1.48)],
        [(0.02, 2.50, 0.0), (-0.78, 3.32, 0.36), (-1.78, 4.08, 0.96), (-2.48, 4.58, 1.28)],
        [(0.02, 2.48, 0.0), (0.58, 3.30, -0.68), (1.46, 4.05, -1.52), (2.10, 4.58, -2.12)],
        [(0.02, 2.42, 0.0), (-0.64, 3.22, -0.62), (-1.52, 3.96, -1.42), (-2.16, 4.48, -1.98)],
        [(0.02, 2.58, 0.0), (0.28, 3.85, 0.22), (0.62, 5.05, 0.48), (0.86, 5.88, 0.62)],
        [(0.02, 2.58, 0.0), (-0.26, 3.90, -0.24), (-0.58, 5.12, -0.52), (-0.76, 5.95, -0.68)],
    ]

    foliage_anchors: list[tuple[Vector, Vector, float, float]] = []
    for idx, pts in enumerate(bough_specs):
        add_tapered_tube_uv(bm_bark, pts, [0.18, 0.135, 0.092, 0.046], segs=7)
        p_low = Vector(pts[1])
        p_mid = Vector(pts[2])
        p_tip = Vector(pts[3])
        b_dir = (p_tip - p_low).normalized()
        foliage_anchors.append((p_low * 0.96 + Vector((0.0, 0.15, 0.0)), (b_dir + Vector((0.0, 0.55, 0.0))).normalized(), 2.30, 2.20))
        foliage_anchors.append((p_mid, (b_dir + Vector((0.0, 0.42, 0.0))).normalized(), 2.50, 2.38))
        foliage_anchors.append((p_tip * 0.90, (b_dir + Vector((0.0, 0.18, 0.0))).normalized(), 2.60, 2.48))

        # Two secondary forks per primary bough
        for sgn in (-1.0, 1.0):
            lat = Vector((-b_dir.z * sgn, 0.24, b_dir.x * sgn)).normalized()
            sub_dir = (b_dir * 0.72 + lat * 0.68).normalized()
            sub_tip = p_mid + sub_dir * 1.32
            add_tapered_tube_uv(
                bm_bark,
                [tuple(p_mid), tuple((p_mid + sub_tip) * 0.5 + Vector((0, 0.08, 0))), tuple(sub_tip)],
                [0.085, 0.056, 0.030],
                segs=5,
            )
            foliage_anchors.append((sub_tip * 0.88, (sub_dir + Vector((0.0, 0.16, 0.0))).normalized(), 2.35, 2.22))

    # Central mid & upper crown dome clusters so silhouette is a full Jiangnan camphor umbrella ("香樟如盖")
    crown_tops = [
        (Vector((0.0, 3.65, 0.0)), Vector((0.18, 0.96, 0.12)), 2.85, 2.65),
        (Vector((0.0, 4.55, 0.0)), Vector((-0.14, 0.98, 0.10)), 2.90, 2.65),
        (Vector((0.55, 5.25, 0.35)), Vector((0.38, 0.88, 0.25)), 2.55, 2.35),
        (Vector((-0.55, 5.30, -0.35)), Vector((-0.38, 0.88, -0.25)), 2.55, 2.35),
        (Vector((0.35, 5.15, -0.55)), Vector((0.25, 0.88, -0.38)), 2.45, 2.25),
        (Vector((-0.35, 5.15, 0.55)), Vector((-0.25, 0.88, 0.38)), 2.45, 2.25),
        (Vector((0.0, 5.75, 0.0)), Vector((0.0, 1.0, 0.08)), 2.50, 2.20),
    ]
    foliage_anchors.extend(crown_tops)

    for k, (anc, dvec, w, L) in enumerate(foliage_anchors):
        add_domed_bough_cluster(
            bm_leaf,
            tuple(anc),
            tuple(dvec),
            width=w * rng.uniform(0.94, 1.08),
            length=L * rng.uniform(0.94, 1.06),
            droop=0.20,
            cup=0.19,
            roll_deg=(k * 37.0) % 180.0,
        )

    p_bark = finalize_part("CamphorTreeBark", bm_bark, mats["camphor_bark"], smooth=True)
    p_leaf = finalize_part("CamphorTreeLeaves", bm_leaf, mats["camphor_leaf"], smooth=True, canopy_center_gd=(0.0, 4.8, 0.0))
    return join_objects("tree_camphor", [p_bark, p_leaf])


def build_tree_willow(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Authentic Jiangnan Weeping Willow (垂柳): leaning willow trunk + cascading frond curtains."""
    bm_bark = bmesh.new()
    bm_crown = bmesh.new()
    bm_drape = bmesh.new()
    rng = random.Random(6111)

    # Slightly leaning waterside willow trunk with flared roots
    for i in range(5):
        ang = i * math.tau / 5.0 + 0.4
        ca, sa = math.cos(ang), math.sin(ang)
        add_tapered_tube_uv(
            bm_bark,
            [(ca * 0.78, -0.48, sa * 0.78), (ca * 0.36, 0.02, sa * 0.36), (ca * 0.16, 0.52, sa * 0.16)],
            [0.09, 0.14, 0.10],
            segs=6,
            cap_tip=False,
        )
    add_tapered_tube_uv(
        bm_bark,
        [(0.0, -0.50, 0.0), (0.14, 0.95, 0.06), (0.26, 2.05, 0.10), (0.22, 2.85, 0.08)],
        [0.38, 0.30, 0.25, 0.21],
        segs=9,
        cap_tip=False,
    )

    # 7 arching umbrella willow boughs rising to y=5.7m then gracefully drooping at outer rim
    n_boughs = 7
    for i in range(n_boughs):
        ang = i * math.tau / n_boughs + 0.18
        ca, sa = math.cos(ang), math.sin(ang)
        pts = [
            (0.22, 2.70, 0.08),
            (0.22 + ca * 0.95, 4.15, 0.08 + sa * 0.95),
            (0.22 + ca * 1.95, 5.45, 0.08 + sa * 1.95),
            (0.22 + ca * 2.65, 5.05, 0.08 + sa * 2.65),
        ]
        add_tapered_tube_uv(bm_bark, pts, [0.15, 0.11, 0.072, 0.036], segs=6)
        # Upper leafy cap along the arch so looking up from under the willow feels full
        add_domed_bough_cluster(
            bm_crown,
            (0.22 + ca * 0.85, 4.35, 0.08 + sa * 0.85),
            (ca * 0.68, 0.65, sa * 0.68),
            width=2.15,
            length=2.05,
            droop=0.32,
            cup=0.18,
            roll_deg=i * 29.0,
        )

        # Outer weeping curtain + mid-ring weeping curtain per bough
        add_willow_curtain_drape(
            bm_drape,
            (0.22 + ca * 2.38, 5.42 + rng.uniform(-0.18, 0.18), 0.08 + sa * 2.38),
            (ca, 0.0, sa),
            width=2.25,
            drop_height=rng.uniform(3.45, 3.85),
            curve_out=0.34,
        )
        mid_ang = ang + (math.pi / n_boughs)
        mca, msa = math.cos(mid_ang), math.sin(mid_ang)
        add_willow_curtain_drape(
            bm_drape,
            (0.22 + mca * 1.48, 5.75 + rng.uniform(-0.15, 0.15), 0.08 + msa * 1.48),
            (mca, 0.0, msa),
            width=2.05,
            drop_height=rng.uniform(3.15, 3.55),
            curve_out=0.26,
        )

    # Top central willow crown dome + 4 high inner drapes
    add_domed_bough_cluster(bm_crown, (0.22, 5.15, 0.08), (0.0, 1.0, 0.0), width=2.45, length=2.10, droop=0.28, roll_deg=15.0)
    for k in range(4):
        ang = k * math.pi * 0.5 + 0.45
        ca, sa = math.cos(ang), math.sin(ang)
        add_willow_curtain_drape(
            bm_drape,
            (0.22 + ca * 0.82, 6.05, 0.08 + sa * 0.82),
            (ca, 0.0, sa),
            width=1.85,
            drop_height=2.95,
            curve_out=0.20,
        )

    p_bark = finalize_part("WillowBark", bm_bark, mats["willow_bark"], smooth=True)
    p_crown = finalize_part("WillowCrown", bm_crown, mats["camphor_leaf"], smooth=True, canopy_center_gd=(0.2, 4.9, 0.1))
    p_drape = finalize_part("WillowDrapes", bm_drape, mats["willow_curtain"], smooth=True, canopy_center_gd=(0.2, 4.2, 0.1))
    return join_objects("tree_willow", [p_bark, p_crown, p_drape])


def build_tree_maple_tallow(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Southern Chinese Trident Maple / Chinese Tallow (三角枫/乌桕) with tiered airy boughs."""
    bm_bark = bmesh.new()
    bm_leaf = bmesh.new()
    rng = random.Random(6112)

    add_tapered_tube_uv(
        bm_bark,
        [(0.0, -0.50, 0.0), (-0.06, 1.05, 0.04), (0.04, 2.35, -0.05), (-0.02, 3.45, 0.02)],
        [0.34, 0.25, 0.20, 0.15],
        segs=8,
        cap_tip=False,
    )
    for i in range(4):
        ang = i * math.pi * 0.5 + 0.35
        ca, sa = math.cos(ang), math.sin(ang)
        add_tapered_tube_uv(
            bm_bark,
            [(ca * 0.65, -0.45, sa * 0.65), (ca * 0.28, 0.05, sa * 0.28), (ca * 0.14, 0.45, sa * 0.14)],
            [0.08, 0.11, 0.08],
            segs=5,
            cap_tip=False,
        )

    limbs = [
        [(0.02, 2.25, -0.04), (0.95, 3.15, 0.62), (2.05, 3.95, 1.25)],
        [(0.02, 2.40, -0.04), (-1.05, 3.30, 0.55), (-2.12, 4.05, 1.12)],
        [(0.02, 2.55, -0.04), (0.78, 3.55, -0.88), (1.72, 4.35, -1.82)],
        [(0.02, 2.65, -0.04), (-0.82, 3.65, -0.78), (-1.75, 4.45, -1.65)],
        [(-0.02, 3.30, 0.02), (0.68, 4.65, 0.42), (1.35, 5.65, 0.85)],
        [(-0.02, 3.35, 0.02), (-0.65, 4.75, -0.48), (-1.28, 5.75, -0.92)],
        [(-0.02, 3.42, 0.02), (0.12, 5.10, -0.18), (0.22, 6.45, -0.28)],
    ]
    for idx, pts in enumerate(limbs):
        add_tapered_tube_uv(bm_bark, pts, [0.14, 0.095, 0.042], segs=6)
        p1 = Vector(pts[1])
        p2 = Vector(pts[2])
        d = (p2 - Vector(pts[0])).normalized()
        add_domed_bough_cluster(bm_leaf, tuple(p1), tuple((d + Vector((0, 0.35, 0))).normalized()), 2.20, 2.10, droop=0.18, roll_deg=idx * 41.0)
        add_domed_bough_cluster(bm_leaf, tuple(p2 * 0.90), tuple((d + Vector((0, 0.15, 0))).normalized()), 2.35, 2.25, droop=0.22, roll_deg=idx * 41.0 + 30.0)
        for sgn in (-1.0, 1.0):
            lat = Vector((-d.z * sgn, 0.22, d.x * sgn)).normalized()
            sd = (d * 0.7 + lat * 0.65).normalized()
            stip = p1 + sd * 1.22
            add_tapered_tube_uv(bm_bark, [tuple(p1), tuple(stip)], [0.068, 0.030], segs=5)
            add_domed_bough_cluster(bm_leaf, tuple(stip * 0.92), tuple(sd), 2.05, 1.95, droop=0.18, roll_deg=idx * 23.0 + sgn * 40.0)

    add_domed_bough_cluster(bm_leaf, (0.0, 5.85, 0.0), (0.0, 1.0, 0.0), 2.35, 2.15, droop=0.16, roll_deg=12.0)
    p_bark = finalize_part("MapleTallowBark", bm_bark, mats["maple_bark"], smooth=True)
    p_leaf = finalize_part("MapleTallowLeaves", bm_leaf, mats["maple_leaf"], smooth=True, canopy_center_gd=(0.0, 4.7, 0.0))
    return join_objects("tree_maple_tallow", [p_bark, p_leaf])


def _add_moso_bamboo_culm(
    bm_culm: bmesh.types.BMesh,
    bm_leaf: bmesh.types.BMesh,
    base_xz: tuple[float, float],
    lean_dir_xz: tuple[float, float],
    height: float,
    base_r: float,
    arch_dist: float,
    seed: int,
    spray_density: int = 2,
) -> None:
    """Build one segmented Moso bamboo culm with 3D nodal rings, twigs & feathery leaf sprays."""
    rng = random.Random(seed)
    bx, bz = base_xz
    lx, lz = lean_dir_xz
    lmag = math.hypot(lx, lz)
    if lmag < 1e-4:
        lx, lz = 1.0, 0.0
    else:
        lx, lz = lx / lmag, lz / lmag

    n_nodes = 13
    pts: list[tuple[float, float, float]] = []
    radii: list[float] = []
    for i in range(n_nodes + 1):
        # Start underground at y=-0.45m so culm bases never float on mountain slopes!
        if i == 0:
            y = -0.45
            t = 0.0
        else:
            t = (i - 0.5) / n_nodes
            y = t * height
        bend = arch_dist * (t ** 2.15)
        px = bx + lx * bend
        pz = bz + lz * bend
        r = base_r * (1.0 - 0.68 * (t ** 1.15))
        pts.append((px, y, pz))
        radii.append(max(0.016, r))

    add_tapered_tube_uv(bm_culm, pts, radii, segs=7, u_scale=1.0, v_per_m=0.45, cap_tip=True)

    # Real 3D raised bamboo nodal rings (竹节环) + alternating nodal twigs & bamboo leaf sprays in upper half
    for i in range(2, n_nodes):
        px, py, pz = pts[i]
        r_here = radii[i]
        px_prev, py_prev, pz_prev = pts[i - 1]
        px_next, py_next, pz_next = pts[i + 1]
        tang = Vector((px_next - px_prev, py_next - py_prev, pz_next - pz_prev)).normalized()
        p_vec = Vector((px, py, pz))
        # Subtle 3D swollen node collar
        add_tapered_tube_uv(
            bm_culm,
            [tuple(p_vec - tang * 0.026), tuple(p_vec), tuple(p_vec + tang * 0.026)],
            [r_here * 1.02, r_here * 1.16, r_here * 1.02],
            segs=7,
            v_per_m=0.45,
            cap_tip=False,
        )

        # Side branches & feathery leaf sprays from 44% height up to crown tip
        if i >= 6:
            n_twigs = spray_density if i >= 8 else 1
            for tw in range(n_twigs):
                az = (i * 2.35 + tw * 2.6 + seed * 0.7) % math.tau
                tdir = Vector((math.cos(az) * 0.84 + lx * 0.25, 0.42 - 0.03 * (i - 6), math.sin(az) * 0.84 + lz * 0.25)).normalized()
                twig_len = rng.uniform(0.55, 0.85) * (1.0 - 0.25 * (i / n_nodes))
                tip_p = p_vec + tdir * twig_len
                add_tapered_tube_uv(
                    bm_culm,
                    [tuple(p_vec), tuple(tip_p)],
                    [max(0.010, r_here * 0.34), 0.005],
                    segs=4,
                    v_per_m=0.5,
                )
                add_domed_bough_cluster(
                    bm_leaf,
                    tuple(p_vec + tdir * (twig_len * 0.35)),
                    tuple(tdir),
                    width=rng.uniform(1.35, 1.75),
                    length=rng.uniform(1.45, 1.85),
                    droop=0.34,
                    cup=0.15,
                    roll_deg=(i * 47.0 + tw * 73.0) % 180.0,
                )

    # Plume spray right at the arched bamboo tip
    top_p = Vector(pts[-1])
    top_dir = (top_p - Vector(pts[-2])).normalized()
    add_domed_bough_cluster(bm_leaf, tuple(top_p * 0.96), tuple(top_dir), width=1.55, length=1.75, droop=0.42, cup=0.14, roll_deg=seed * 19.0)


def build_bamboo_culm_single(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Single arched Moso bamboo stalk with 3D nodes & feathery leaf sprays for dense MultiMesh groves."""
    bm_culm = bmesh.new()
    bm_leaf = bmesh.new()
    _add_moso_bamboo_culm(bm_culm, bm_leaf, (0.0, 0.0), (0.85, 0.52), height=7.8, base_r=0.074, arch_dist=1.05, seed=6120, spray_density=1)
    p_c = finalize_part("BambooSingleCulm", bm_culm, mats["bamboo_culm"], smooth=True)
    p_l = finalize_part("BambooSingleLeaves", bm_leaf, mats["bamboo_leaf"], smooth=True, canopy_center_gd=(0.4, 5.8, 0.25))
    return join_objects("bamboo_culm_single", [p_c, p_l])


def build_bamboo_clump(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Natural 6-culm Jiangnan Moso bamboo clump + basal spring bamboo shoots (春笋) for village & trails."""
    bm_culm = bmesh.new()
    bm_leaf = bmesh.new()
    specs = [
        ((0.00, 0.00), (0.65, 0.75), 8.5, 0.078, 1.15, 6121),
        ((0.36, 0.14), (0.92, 0.28), 7.9, 0.072, 1.25, 6122),
        ((-0.34, 0.22), (-0.84, 0.54), 8.2, 0.075, 1.18, 6123),
        ((0.18, -0.35), (0.42, -0.90), 7.4, 0.068, 1.10, 6124),
        ((-0.28, -0.26), (-0.72, -0.68), 6.9, 0.064, 0.98, 6125),
        ((0.46, -0.18), (0.88, -0.45), 6.4, 0.058, 0.92, 6126),
    ]
    for bxz, ldir, h, br, ad, sd in specs:
        _add_moso_bamboo_culm(bm_culm, bm_leaf, bxz, ldir, h, br, ad, sd, spray_density=1)

    # 3 plump young spring bamboo shoots (春笋) emerging beside the culms
    for sx, sz, sh in ((0.54, 0.28, 0.58), (-0.48, 0.05, 0.46), (0.08, 0.48, 0.40)):
        add_tapered_tube_uv(
            bm_culm,
            [(sx, -0.22, sz), (sx, sh * 0.45, sz), (sx + 0.02, sh, sz)],
            [0.085, 0.068, 0.012],
            segs=7,
        )

    p_c = finalize_part("BambooClumpCulms", bm_culm, mats["bamboo_culm"], smooth=True)
    p_l = finalize_part("BambooClumpLeaves", bm_leaf, mats["bamboo_leaf"], smooth=True, canopy_center_gd=(0.0, 5.8, 0.0))
    return join_objects("bamboo_clump", [p_c, p_l])


def _import_polyfork_mesh(
    stem: str,
    target_name: str,
    mat: bpy.types.Material,
    rotate_180_z: bool,
    target_length_m: float | None = None,
    ground_offset_z: float = 0.0,
    center_vertically: bool = False,
    decimate_max_tris: int = 1650,
    color_transform=None,
) -> bpy.types.Object:
    """Import a Polyfork GLB into a temp collection, strip dummy Icosphere, orient, scale, decimate & recolor."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(DL_PF / f"{stem}.glb"))
    imported = [o for o in bpy.data.objects if o not in before]

    keep_meshes: list[bpy.types.Object] = []
    trash: list[bpy.types.Object] = []
    for o in imported:
        if o.type == "MESH" and "icosphere" not in o.name.lower():
            keep_meshes.append(o)
        else:
            trash.append(o)

    # Unparent kept meshes preserving world matrix, then delete dummy Icosphere / empties
    for o in keep_meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in trash:
        bpy.data.objects.remove(o, do_unlink=True)

    obj = join_objects(target_name, keep_meshes)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Rotate 180 deg around Blender Z so head at -Y rotates to +Y (which exports to Godot -Z Forward!)
    if rotate_180_z:
        rot_m = Matrix.Rotation(math.pi, 4, "Z")
        obj.data.transform(rot_m)

    # Compute current bounds in Blender Z-up
    vs = [v.co for v in obj.data.vertices]
    xmin, xmax = min(v.x for v in vs), max(v.x for v in vs)
    ymin, ymax = min(v.y for v in vs), max(v.y for v in vs)
    zmin, zmax = min(v.z for v in vs), max(v.z for v in vs)
    cx = 0.5 * (xmin + xmax)
    cy = 0.5 * (ymin + ymax)
    cz = 0.5 * (zmin + zmax) if center_vertically else zmin

    # Recenter X/Y and ground Z
    obj.data.transform(Matrix.Translation(Vector((-cx, -cy, -cz))))
    if target_length_m is not None:
        span = max(xmax - xmin, ymax - ymin, 1e-4)
        s = target_length_m / span
        obj.data.transform(Matrix.Scale(s, 4))
    if abs(ground_offset_z) > 1e-5:
        obj.data.transform(Matrix.Translation(Vector((0.0, 0.0, ground_offset_z))))

    # Optional vertex-color customization BEFORE decimation
    if color_transform is not None and obj.data.color_attributes:
        ca = obj.data.color_attributes[0]
        if ca.domain == "CORNER":
            for poly in obj.data.polygons:
                for li in poly.loop_indices:
                    vi = obj.data.loops[li].vertex_index
                    vco = obj.data.vertices[vi].co
                    c = ca.data[li].color
                    nr, ng, nb = color_transform(vco, (c[0], c[1], c[2]))
                    ca.data[li].color = (nr, ng, nb, 1.0)
        elif ca.domain == "POINT":
            for vi, v in enumerate(obj.data.vertices):
                c = ca.data[vi].color
                nr, ng, nb = color_transform(v.co, (c[0], c[1], c[2]))
                ca.data[vi].color = (nr, ng, nb, 1.0)

    # Clear any leftover skeleton/armature modifiers from imported GLBs before decimation
    obj.modifiers.clear()
    obj.vertex_groups.clear()

    # Clean decimation if high-poly while preserving 'Color' attribute
    cur_tris = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    if cur_tris > decimate_max_tris:
        mod = obj.modifiers.new(name="DecimateV061", type="DECIMATE")
        mod.ratio = max(0.25, decimate_max_tris / float(cur_tris))
        bpy.ops.object.modifier_apply(modifier=mod.name)

    # Ensure active color attribute is named 'Color' and bind shared vcol PBR material
    if obj.data.color_attributes:
        obj.data.color_attributes[0].name = "Color"
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def build_wild_boar(mat_vcol: bpy.types.Material) -> bpy.types.Object:
    """Adapt Polyfork pig-base into a bristled dark-brown Jiangnan wild boarlet (小野猪) with ivory tusks."""
    def _boar_pelage(vco: Vector, rgb: tuple[float, float, float]) -> tuple[float, float, float]:
        # Slim dark umber-charcoal coat with dark dorsal ridge & subtle tawny juvenile stripes
        r, g, b = rgb
        if r < 0.06 and g < 0.06 and b < 0.06:
            return (r, g, b)  # preserve dark eyes/nostrils/hooves
        stripe = 0.5 + 0.5 * math.sin(abs(vco.x) * 34.0 + vco.z * 12.0)
        dorsal = max(0.0, min(1.0, (vco.z - 0.28) / 0.32))
        base_r = 0.11 + 0.08 * stripe * (1.0 - 0.55 * dorsal)
        base_g = 0.075 + 0.055 * stripe * (1.0 - 0.60 * dorsal)
        base_b = 0.045 + 0.025 * stripe * (1.0 - 0.65 * dorsal)
        return (base_r, base_g, base_b)

    obj = _import_polyfork_mesh(
        "pig-base",
        "animal_boar",
        mat_vcol,
        rotate_180_z=True,
        target_length_m=0.92,
        decimate_max_tris=1450,
        color_transform=_boar_pelage,
    )
    # Slim flank width slightly & taper snout forward (+Y in Blender = -Z in Godot) for wild boar silhouette
    for v in obj.data.vertices:
        v.co.x *= 0.82
        if v.co.y > 0.22:
            t = (v.co.y - 0.22) / 0.26
            v.co.y += 0.06 * min(1.5, t)
            v.co.x *= max(0.70, 1.0 - 0.18 * t)

    # Add two curved pale-ivory wild boar tusks painted into the same 'Color' attribute!
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    clayer = bm.loops.layers.color.get("Color") or bm.loops.layers.color.new("Color")
    for sgn in (-1.0, 1.0):
        tusk_pts = [
            (sgn * 0.068, 0.28, -0.44),
            (sgn * 0.095, 0.32, -0.47),
            (sgn * 0.105, 0.38, -0.46),
        ]
        before_f = set(bm.faces)
        add_tapered_tube_uv(bm, tusk_pts, [0.018, 0.013, 0.003], segs=6)
        for f in set(bm.faces) - before_f:
            for loop in f.loops:
                loop[clayer] = (0.86, 0.82, 0.68, 1.0)
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def build_river_shrimp(mat_vcol: bpy.types.Material) -> bpy.types.Object:
    """Adapt Polyfork cleaner-shrimp-base into a jade-olive Jiangnan freshwater river shrimp (清溪河虾)."""
    def _jade_shrimp(vco: Vector, rgb: tuple[float, float, float]) -> tuple[float, float, float]:
        r, g, b = rgb
        if r < 0.08 and g < 0.08 and b < 0.08:
            return (0.02, 0.02, 0.02)  # glossy black eyes
        lum = 0.35 * r + 0.45 * g + 0.20 * b
        return (0.18 + 0.24 * lum, 0.34 + 0.32 * lum, 0.22 + 0.22 * lum)

    return _import_polyfork_mesh(
        "cleaner-shrimp-base",
        "animal_shrimp",
        mat_vcol,
        rotate_180_z=True,
        target_length_m=0.36,
        center_vertically=True,
        decimate_max_tris=1200,
        color_transform=_jade_shrimp,
    )


def build_woodland_squirrel(mat_vcol: bpy.types.Material) -> bpy.types.Object:
    """Sculpt a high-detail organic woodland squirrel (小松鼠) with S-curved plumed tail & vertex colors."""
    bm = bmesh.new()

    def _part_sphere(center_gd, radii_gd, rot_deg=(0.0, 0.0, 0.0), sub=2):
        ret = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        eu = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix()
        cx, cy, cz = center_gd
        rx, ry, rz = radii_gd
        for v in ret["verts"]:
            p = eu @ Vector((v.co.x * rx, v.co.y * ry, v.co.z * rz))
            v.co = gd_to_bl(Vector((cx + p.x, cy + p.y, cz + p.z)))
        return ret["verts"]

    # Arched agile torso, haunches, shoulders, sculpted head, snout, ear tufts, paws, eyes & lush S-plume tail
    _part_sphere((0.0, 0.115, 0.01), (0.068, 0.066, 0.115), (-14.0, 0.0, 0.0), sub=2)
    _part_sphere((0.0, 0.105, 0.085), (0.072, 0.074, 0.078), (8.0, 0.0, 0.0), sub=2)
    _part_sphere((0.0, 0.168, -0.108), (0.056, 0.054, 0.066), (8.0, 0.0, 0.0), sub=2)
    _part_sphere((0.0, 0.155, -0.168), (0.032, 0.028, 0.038), (12.0, 0.0, 0.0), sub=1)
    nose_vs = _part_sphere((0.0, 0.158, -0.202), (0.011, 0.010, 0.012), sub=1)
    eye_vs = []
    for sx in (-1.0, 1.0):
        # Pointed squirrel ears + ear tufts
        _part_sphere((sx * 0.036, 0.228, -0.092), (0.014, 0.034, 0.018), (-10.0, 0.0, -sx * 14.0), sub=1)
        _part_sphere((sx * 0.040, 0.258, -0.090), (0.006, 0.018, 0.007), sub=1)
        eye_vs.extend(_part_sphere((sx * 0.044, 0.180, -0.140), (0.010, 0.011, 0.011), sub=1))
        # Hind haunches & feet grounded at y=0
        _part_sphere((sx * 0.058, 0.068, 0.072), (0.032, 0.052, 0.048), (18.0, 0.0, 0.0), sub=1)
        _part_sphere((sx * 0.056, 0.016, 0.042), (0.020, 0.016, 0.046), sub=1)
        # Forelimbs & paws grounded/ready
        _part_sphere((sx * 0.044, 0.068, -0.068), (0.020, 0.046, 0.022), (-16.0, 0.0, 0.0), sub=1)
        _part_sphere((sx * 0.044, 0.015, -0.088), (0.016, 0.015, 0.030), sub=1)

    # Signature fluffy S-curved squirrel tail rising behind haunches and curling gracefully at tip
    tail_segs = [
        ((0.0, 0.115, 0.145), (0.046, 0.048, 0.062), (38.0, 0.0, 0.0)),
        ((0.0, 0.185, 0.195), (0.058, 0.072, 0.064), (16.0, 0.0, 0.0)),
        ((0.0, 0.268, 0.205), (0.064, 0.078, 0.068), (-8.0, 0.0, 0.0)),
        ((0.0, 0.335, 0.172), (0.056, 0.062, 0.065), (-36.0, 0.0, 0.0)),
        ((0.0, 0.358, 0.118), (0.042, 0.040, 0.052), (-62.0, 0.0, 0.0)),
    ]
    tail_vs = set()
    for tc, tr, trot in tail_segs:
        tail_vs.update(_part_sphere(tc, tr, trot, sub=2))

    dark_vs = set(nose_vs) | set(eye_vs)
    clayer = bm.loops.layers.color.new("Color")
    for f in bm.faces:
        for loop in f.loops:
            v = loop.vert
            if v in dark_vs:
                loop[clayer] = (0.025, 0.022, 0.022, 1.0)
                continue
            # Convert Blender Z-up back to Godot Y-up for natural pelage shading
            gx, gy, gz = v.co.x, v.co.z, -v.co.y
            if v in tail_vs:
                # Rich cinnamon-russet tail with warm Frosted golden-cream tip highlights
                tip_t = max(0.0, min(1.0, (gy - 0.14) / 0.23))
                r = 0.28 + 0.18 * tip_t
                g = 0.11 + 0.10 * tip_t
                b = 0.04 + 0.05 * tip_t
                loop[clayer] = (r, g, b, 1.0)
            else:
                # Warm creamy-buff chest/belly vs rich chestnut-rufous back
                belly = max(0.0, min(1.0, (0.105 - gy) * 9.0 + (0.042 - abs(gx)) * 8.0))
                if gz > 0.10:
                    belly *= 0.25
                r = 0.30 * (1.0 - belly) + 0.72 * belly
                g = 0.13 * (1.0 - belly) + 0.62 * belly
                b = 0.05 * (1.0 - belly) + 0.46 * belly
                loop[clayer] = (r, g, b, 1.0)

    obj = finalize_part("animal_squirrel", bm, mat_vcol, smooth=True)
    return obj


def build_woodland_bird(mat_vcol: bpy.types.Material) -> bpy.types.Object:
    """Jiangnan spotted dove / songbird (山斑鸠/山林飞鸟) from Polyfork pigeon-base with warm russet breast."""
    def _dove_plumage(vco: Vector, rgb: tuple[float, float, float]) -> tuple[float, float, float]:
        r, g, b = rgb
        if r < 0.06 and g < 0.06 and b < 0.06:
            return (r, g, b)
        # Warm rosy-buff breast (+Y front, lower Z) & slate-olive wings/back
        breast = max(0.0, min(1.0, (vco.y + 0.02) * 5.0)) * max(0.0, min(1.0, (0.20 - vco.z) * 6.0))
        nr = (r * 0.95 + 0.06) * (1.0 - breast) + 0.46 * breast
        ng = (g * 1.05 + 0.06) * (1.0 - breast) + 0.31 * breast
        nb = (b * 1.15 + 0.08) * (1.0 - breast) + 0.24 * breast
        return (min(1.0, nr), min(1.0, ng), min(1.0, nb))

    return _import_polyfork_mesh(
        "pigeon-base",
        "animal_bird",
        mat_vcol,
        rotate_180_z=True,
        target_length_m=0.38,
        decimate_max_tris=1250,
        color_transform=_dove_plumage,
    )


def build_azalea_bush(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Botanical Jiangnan Mountain Azalea shrub (映山红灌木丛): multi-stem woody base + leafy crimson-flowering boughs."""
    bm_bark = bmesh.new()
    bm_leaf = bmesh.new()
    rng = random.Random(6128)

    # 6 multi-stemmed woody azalea branches radiating from -0.18m underground so steep slopes never show gaps
    for i in range(6):
        ang = i * (math.tau / 6.0) + rng.uniform(-0.18, 0.18)
        ca, sa = math.cos(ang), math.sin(ang)
        r_mid = rng.uniform(0.24, 0.36)
        r_tip = rng.uniform(0.52, 0.72)
        h_tip = rng.uniform(0.52, 0.76)
        pts = [
            (ca * 0.06, -0.18, sa * 0.06),
            (ca * r_mid, 0.24, sa * r_mid),
            (ca * r_tip, h_tip, sa * r_tip),
        ]
        add_tapered_tube_uv(bm_bark, pts, [0.036, 0.024, 0.012], segs=5)
        b_dir = Vector((ca * 0.76, 0.65, sa * 0.76)).normalized()
        add_domed_bough_cluster(
            bm_leaf,
            (ca * 0.14, 0.12, sa * 0.14),
            tuple(b_dir),
            width=rng.uniform(0.95, 1.15),
            length=rng.uniform(0.92, 1.12),
            droop=0.22,
            cup=0.18,
            roll_deg=(i * 43.0) % 180.0,
        )

    # Lush domed central flowering crown cluster
    for k, dv in enumerate([(0.12, 0.98, 0.08), (-0.15, 0.96, -0.12)]):
        add_domed_bough_cluster(bm_leaf, (0.0, 0.18, 0.0), dv, width=1.12, length=0.98, droop=0.16, cup=0.20, roll_deg=25.0 + k * 68.0)

    p_b = finalize_part("AzaleaStems", bm_bark, mats["maple_bark"], smooth=True)
    p_l = finalize_part("AzaleaFoliage", bm_leaf, mats["azalea_leaf"], smooth=True, canopy_center_gd=(0.0, 0.55, 0.0))
    return join_objects("prop_azalea_bush", [p_b, p_l])


def build_all() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    staged = staged_pbr_paths()

    mats = {
        "camphor_bark": make_bark_mat("Mat_V061_CamphorBark", staged["japanese_camphor_bark_diff"], staged["japanese_camphor_bark_norm"], roughness=0.90),
        "willow_bark": make_bark_mat("Mat_V061_WillowBark", staged["bark_willow_diff"], staged["bark_willow_norm"], roughness=0.88),
        "maple_bark": make_bark_mat("Mat_V061_MapleBark", staged["trident_maple_bark_diff"], staged["trident_maple_bark_norm"], roughness=0.88),
        "camphor_leaf": make_cutout_foliage_mat("Mat_V061_CamphorLeaf", GEN_DIR / "camphor_bough.png", roughness=0.58, alpha_cutoff=0.40),
        "willow_curtain": make_cutout_foliage_mat("Mat_V061_WillowCurtain", GEN_DIR / "willow_curtain.png", roughness=0.64, alpha_cutoff=0.38),
        "maple_leaf": make_cutout_foliage_mat("Mat_V061_MapleLeaf", GEN_DIR / "maple_tallow_bough.png", roughness=0.64, alpha_cutoff=0.40),
        "azalea_leaf": make_cutout_foliage_mat("Mat_V061_AzaleaLeaf", GEN_DIR / "azalea_bough.png", roughness=0.62, alpha_cutoff=0.40),
        "bamboo_culm": make_bark_mat("Mat_V061_BambooCulm", GEN_DIR / "bamboo_culm.png", None, roughness=0.52),
        "bamboo_leaf": make_cutout_foliage_mat("Mat_V061_BambooLeaf", GEN_DIR / "bamboo_spray.png", roughness=0.62, alpha_cutoff=0.38),
        "vcol_fauna": make_vcol_mat("Mat_V061_WildlifeVCol", roughness=0.68),
        "vcol_aquatic": make_vcol_mat("Mat_V061_AquaticVCol", roughness=0.30),
        "vcol_flora": make_vcol_mat("Mat_V061_UndergrowthVCol", roughness=0.78),
    }

    objs: list[bpy.types.Object] = [
        # 5 Jiangnan Trees & Moso Bamboo assets
        build_tree_camphor(mats),
        build_tree_willow(mats),
        build_tree_maple_tallow(mats),
        build_bamboo_culm_single(mats),
        build_bamboo_clump(mats),
        # 6 Botanical & Open-Community Undergrowth & Slope Props (sunk at base so slopes never leave air gaps)
        build_azalea_bush(mats),
        _import_polyfork_mesh("moat-reed-clump-dd6b60", "prop_reed_clump", mats["vcol_flora"], rotate_180_z=False, target_length_m=1.30, ground_offset_z=-0.12, decimate_max_tris=650),
        _import_polyfork_mesh("cattail-reed-6abbb3", "prop_cattail_clump", mats["vcol_flora"], rotate_180_z=False, target_length_m=0.48, ground_offset_z=-0.10, decimate_max_tris=420),
        _import_polyfork_mesh("fern-plant-1559b8", "prop_fern_clump", mats["vcol_flora"], rotate_180_z=False, target_length_m=1.05, ground_offset_z=-0.08, decimate_max_tris=720),
        _import_polyfork_mesh("grass-tuft-a40a08", "prop_grass_tuft", mats["vcol_flora"], rotate_180_z=False, target_length_m=0.62, ground_offset_z=-0.06, decimate_max_tris=380),
        _import_polyfork_mesh("fallen-log-1685fb", "prop_fallen_log", mats["vcol_flora"], rotate_180_z=False, target_length_m=2.85, ground_offset_z=-0.14, decimate_max_tris=520),
        # 9 Wildlife Meshes (8 species + white creek egret variant!)
        _import_polyfork_mesh("forest-rabbit-ea2da0", "animal_rabbit", mats["vcol_fauna"], rotate_180_z=True, target_length_m=0.46, decimate_max_tris=1350),
        build_woodland_squirrel(mats["vcol_fauna"]),
        build_wild_boar(mats["vcol_fauna"]),
        _import_polyfork_mesh("red-fox-5c3bc0", "animal_fox", mats["vcol_fauna"], rotate_180_z=True, target_length_m=0.86, decimate_max_tris=1450),
        build_woodland_bird(mats["vcol_fauna"]),
        _import_polyfork_mesh("herring-gull-base", "animal_egret", mats["vcol_fauna"], rotate_180_z=True, target_length_m=0.56, decimate_max_tris=1350),
        _import_polyfork_mesh("koi-base", "animal_fish", mats["vcol_aquatic"], rotate_180_z=True, target_length_m=0.44, center_vertically=True, decimate_max_tris=1350),
        _import_polyfork_mesh("shore-crab-base", "animal_crab", mats["vcol_aquatic"], rotate_180_z=True, target_length_m=0.38, decimate_max_tris=1350),
        build_river_shrimp(mats["vcol_aquatic"]),
    ]

    bpy.context.view_layer.update()
    meta: dict = {}
    total_tris = 0
    for obj in objs:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        tris = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
        total_tris += tris
        bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        xs = [p.x for p in bb]
        ys = [p.z for p in bb]  # Godot Y height
        zs = [p.y for p in bb]  # Blender Y -> Godot -Z
        meta[obj.name] = {
            "triangles": tris,
            "has_vertex_colors": bool(obj.data.color_attributes),
            "godot_bounds_m": {
                "x": [round(min(xs), 3), round(max(xs), 3)],
                "y": [round(min(ys), 3), round(max(ys), 3)],
                "z": [round(-max(zs), 3), round(-min(zs), 3)],
            },
        }
        obj.location = (0.0, 0.0, 0.0)

    bpy.ops.object.select_all(action="SELECT")
    out_glb = SLICE_DIR / "v061_nature_wildlife.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_materials="EXPORT",
        export_normals=True,
        export_attributes=True,
    )

    manifest = {
        "bundle": "game/assets/slice/v061_nature_wildlife.glb",
        "total_triangles": total_tris,
        "file_size_bytes": out_glb.stat().st_size,
        "assets": meta,
    }
    (DOCS_DIR / "slice-v061-assets.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Exported {out_glb.name} ({out_glb.stat().st_size / 1024:.1f} KB, {len(objs)} assets, {total_tris} tris).")


if __name__ == "__main__":
    build_all()
