"""Build v0.6.2 3D «迷踪竹石阵» (Lost Bamboo-Stone Labyrinth) & «烟霞古洞» (Yanxia Ancient Cavern) assets in Blender 4.5.

Generated assets (exported into game/assets/slice/v062_bamboo_cave.glb):
- bamboo_maze_gate       (Mossy Jiangnan bluestone & Taihu-karst portal archway reading "迷踪竹石阵")
- karst_monolith_a       (Perforated weathered Jiangnan Taihu/karst strange rock monolith A for maze walls)
- karst_monolith_b       (Craggy layered karst monolith B with overhanging stone brow & through-aperture)
- karst_crouch_arch      (Natural eroded karst rock arch with 1.56m × 1.28m [C]-crouch tunnel shortcut)
- stone_maze_lantern     (Hexagonal mossy Jiangnan stone wayfinder lantern with warm amber firebox)
- stone_sundial_pedestal (Ancient mossy carved bluestone sundial & compass altar for West maze alcove)
- cliff_moya_stele       (Sheer mossy karst cliff face with recessed "竹石清音" Moya carving)
- yanxia_cave_complex    (Walk-in 13m 2-chamber limestone cavern: "烟霞古洞" portal, stalactites, mineral mural,
                          East chronicle carving, overhead skylight shaft & sunken Jade Spring Pool)
- ancestral_hearth_relics(Mossy stone tea hearth with glowing embers & kettle, stone table/stools,
                          bound bamboo slips, Yue-kiln celadon tea set & flickering stone oil lamp)

Run headless:
  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --factory-startup --python tools/build_v062_assets.py
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
TEX_DIR = ROOT / "tools" / "generated_v062"
DEST = ROOT / "game" / "assets" / "slice"
DOCS = ROOT / "docs"
DEST.mkdir(parents=True, exist_ok=True)
DOCS.mkdir(parents=True, exist_ok=True)


def gd_to_bl(v: Vector) -> Vector:
    """Map Godot local coords (x_right, y_up, z_back) to Blender Z-up before export_yup=True."""
    return Vector((v.x, -v.z, v.y))


def bl_to_gd(v: Vector) -> Vector:
    """Inverse of gd_to_bl: Blender (x, y, z) -> Godot (x, z, -y)."""
    return Vector((v.x, v.z, -v.y))


def _srgb_to_lin(c: tuple[float, float, float], alpha: float = 1.0) -> tuple[float, float, float, float]:
    return (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, alpha)


def make_mat(
    name: str,
    srgb: tuple[float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.78,
    emission_srgb: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
    alpha: float = 1.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = _srgb_to_lin(srgb, alpha)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if alpha < 0.999:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND"
    if emission_srgb is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = _srgb_to_lin(emission_srgb)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def make_tex_mat(
    name: str,
    image_path: Path,
    roughness: float = 0.84,
    tint_srgb: tuple[float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    tex_node = nt.nodes.new("ShaderNodeTexImage")
    tex_node.image = bpy.data.images.load(str(image_path))
    color_out = tex_node.outputs["Color"]
    if tint_srgb is not None:
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["B"].default_value = _srgb_to_lin(tint_srgb)
        nt.links.new(color_out, mix.inputs["A"])
        color_out = mix.outputs["Result"]
    nt.links.new(color_out, bsdf.inputs["Base Color"])
    if emission_strength > 0.0:
        nt.links.new(color_out, bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
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
    cap_ends: bool = True,
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
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segs,
        radius1=r0,
        radius2=r1,
        depth=length,
        matrix=mat,
    )


def add_karst_lobe(
    bm: bmesh.types.BMesh,
    center_gd: tuple[float, float, float],
    radii_gd: tuple[float, float, float],
    rot_deg_gd: tuple[float, float, float] = (0.0, 0.0, 0.0),
    subdiv: int = 2,
    seed: int = 1,
    amp: float = 0.20,
) -> None:
    """Create a craggy, stratified Jiangnan karst rock lobe."""
    c = gd_to_bl(Vector(center_gd))
    rx, ry, rz = (math.radians(rot_deg_gd[0]), math.radians(rot_deg_gd[1]), math.radians(rot_deg_gd[2]))
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    verts = ret["verts"]
    rng = random.Random(seed)
    scale = Matrix.Diagonal((radii_gd[0], radii_gd[2], radii_gd[1], 1.0))
    xf = Matrix.Translation(c) @ rot @ scale
    ph1 = rng.uniform(0.0, 6.28)
    ph2 = rng.uniform(0.0, 6.28)
    for v in verts:
        p = v.co.copy()
        # Stratified flutes & craggy Taihu facets
        flute = 0.55 * math.sin(p.z * 5.2 + ph1) + 0.45 * math.cos(p.x * 4.4 - p.y * 3.8 + ph2)
        jag = rng.uniform(-0.55, 0.55)
        p *= 1.0 + amp * (0.62 * flute + 0.38 * jag)
        v.co = xf @ p


def add_uv_quad_gd(
    bm: bmesh.types.BMesh,
    center_gd: tuple[float, float, float],
    right_gd: tuple[float, float, float],
    up_gd: tuple[float, float, float],
    width: float,
    height: float,
) -> None:
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


def apply_box_uv_gd(bm: bmesh.types.BMesh, uv_scale: float = 0.42) -> None:
    """Assign clean box-projected UVs in Godot space so rock textures never stretch."""
    uv_layer = bm.loops.layers.uv.verify()
    bm.normal_update()
    for face in bm.faces:
        n = face.normal
        # Blender (x, y, z) corresponds to Godot (x, -z, y)
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            g = bl_to_gd(loop.vert.co)
            if az >= ax and az >= ay:
                uv = (g.x * uv_scale, g.z * uv_scale)
            elif ax >= ay:
                uv = (g.z * uv_scale, g.y * uv_scale)
            else:
                uv = (g.x * uv_scale, g.y * uv_scale)
            loop[uv_layer].uv = uv


def create_part(
    name: str,
    bm: bmesh.types.BMesh,
    mat: bpy.types.Material,
    smooth: bool = False,
    recalc_normals: bool = True,
    box_uv_scale: float | None = None,
) -> bpy.types.Object:
    if recalc_normals and len(bm.faces) > 0:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if box_uv_scale is not None and len(bm.faces) > 0:
        apply_box_uv_gd(bm, box_uv_scale)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = smooth
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


def _shared_karst_materials() -> dict[str, bpy.types.Material]:
    karst_tex = TEX_DIR / "limestone_karst.png"
    return {
        "karst_light": make_tex_mat("Mat_KarstLimestone", karst_tex, roughness=0.86, tint_srgb=(0.94, 0.96, 0.92)),
        "karst_dark": make_tex_mat("Mat_KarstCaveInterior", karst_tex, roughness=0.82, tint_srgb=(0.74, 0.78, 0.73), emission_strength=0.05),
        "karst_moss": make_tex_mat("Mat_KarstMoss", karst_tex, roughness=0.90, tint_srgb=(0.56, 0.74, 0.50)),
        "bluestone": make_mat("Mat_CarvedBluestone", (0.34, 0.38, 0.36), roughness=0.82),
        "slate_eave": make_mat("Mat_SlateTile", (0.18, 0.21, 0.22), roughness=0.72),
    }


def build_bamboo_maze_gate(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Mossy Jiangnan bluestone & Taihu-karst South archway ('迷踪竹石阵'). Clear opening: 2.44m × 2.88m."""
    m_plaque = make_tex_mat("Mat_MazeGatePlaque", TEX_DIR / "plaque_bamboo_maze.png", roughness=0.78)
    bm_stone = bmesh.new()
    bm_karst = bmesh.new()
    bm_moss = bmesh.new()
    bm_eave = bmesh.new()
    bm_face = bmesh.new()

    # Grounded stone pier plinths & square carved pillars at x = ±1.42 (clear width = 2.44m)
    for sx in (-1.0, 1.0):
        px = sx * 1.42
        add_box(bm_stone, (px, -0.18, 0.0), (0.64, 0.68, 0.78))
        add_box(bm_stone, (px, 0.24, 0.0), (0.50, 0.14, 0.60))
        add_box(bm_stone, (px, 1.62, 0.0), (0.36, 2.66, 0.38))
        # Flanking eroded Taihu strange rocks hugging outer sides of the gate
        add_karst_lobe(bm_karst, (sx * 1.98, 0.78, 0.12), (0.52, 1.28, 0.56), (6.0, sx * 18.0, -sx * 8.0), subdiv=2, seed=101 + int(sx + 2))
        add_karst_lobe(bm_karst, (sx * 1.84, 1.92, -0.08), (0.38, 0.94, 0.44), (-5.0, sx * 24.0, sx * 10.0), subdiv=1, seed=111 + int(sx + 2))
        add_karst_lobe(bm_moss, (sx * 1.92, 0.16, 0.28), (0.46, 0.34, 0.48), subdiv=1, seed=121 + int(sx + 2), amp=0.14)

    # Carved crossbeam lintel (y = 2.88..3.58) & upturned Jiangnan slate roof cap
    add_box(bm_stone, (0.0, 2.98, 0.0), (3.42, 0.20, 0.48))
    add_box(bm_stone, (0.0, 3.34, 0.0), (2.78, 0.62, 0.38))
    # Upturned eave roof over crossbeam
    add_box(bm_eave, (0.0, 3.72, 0.0), (3.86, 0.14, 0.96))
    add_box(bm_eave, (0.0, 3.84, 0.0), (2.96, 0.14, 0.68))
    for sx in (-1.0, 1.0):
        add_box(bm_eave, (sx * 2.02, 3.81, 0.0), (0.42, 0.11, 1.02), (0.0, 0.0, sx * 18.0))
    add_cyl(bm_eave, (-1.65, 3.94, 0.0), (1.65, 3.94, 0.0), 0.06, 0.06, segs=8)

    # Engraved bluestone plaque on South (+Z) and North (-Z) faces
    add_uv_quad_gd(bm_face, (0.0, 3.34, 0.198), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 2.16, 0.72)
    add_uv_quad_gd(bm_face, (0.0, 3.34, -0.198), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 2.16, 0.72)

    return join_parts(
        "bamboo_maze_gate",
        [
            create_part("MazeGateStone", bm_stone, mats["bluestone"], box_uv_scale=0.5),
            create_part("MazeGateKarst", bm_karst, mats["karst_light"], smooth=True, box_uv_scale=0.45),
            create_part("MazeGateMoss", bm_moss, mats["karst_moss"], smooth=True, box_uv_scale=0.5),
            create_part("MazeGateEave", bm_eave, mats["slate_eave"]),
            create_part("MazeGatePlaque", bm_face, m_plaque, recalc_normals=False),
        ],
    )


def build_karst_monolith_a(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Perforated Jiangnan Taihu/karst rock wall segment A (~2.52m wide × 3.45m high × 0.86m thick)."""
    bm_k = bmesh.new()
    bm_m = bmesh.new()

    # Deeply grounded base mass (y = -0.55..1.45) blocking passage cleanly
    add_karst_lobe(bm_k, (-0.56, 0.45, 0.02), (0.78, 1.05, 0.44), (4.0, 8.0, -5.0), subdiv=2, seed=201, amp=0.20)
    add_karst_lobe(bm_k, (0.58, 0.48, -0.03), (0.76, 1.08, 0.43), (-3.0, -10.0, 6.0), subdiv=2, seed=202, amp=0.20)
    # Twin upper pillars + dramatic overhanging stone crown creating a natural Taihu window ("透漏奇石") around y=1.85!
    add_karst_lobe(bm_k, (-0.68, 2.02, 0.04), (0.52, 0.96, 0.38), (5.0, 12.0, -8.0), subdiv=2, seed=203, amp=0.22)
    add_karst_lobe(bm_k, (0.64, 2.08, -0.04), (0.54, 1.02, 0.39), (-6.0, -14.0, 7.0), subdiv=2, seed=204, amp=0.22)
    add_karst_lobe(bm_k, (0.02, 2.98, 0.05), (1.06, 0.56, 0.45), (3.0, 5.0, 4.0), subdiv=2, seed=205, amp=0.21)
    # Mossy root cushions
    add_karst_lobe(bm_m, (-0.42, 0.08, 0.26), (0.54, 0.28, 0.32), subdiv=1, seed=206, amp=0.15)
    add_karst_lobe(bm_m, (0.48, 0.10, -0.24), (0.52, 0.26, 0.32), subdiv=1, seed=207, amp=0.15)
    add_karst_lobe(bm_m, (0.04, 3.34, 0.02), (0.68, 0.22, 0.32), subdiv=1, seed=208, amp=0.16)

    return join_parts(
        "karst_monolith_a",
        [
            create_part("KarstMonoABody", bm_k, mats["karst_light"], smooth=True, box_uv_scale=0.44),
            create_part("KarstMonoAMoss", bm_m, mats["karst_moss"], smooth=True, box_uv_scale=0.50),
        ],
    )


def build_karst_monolith_b(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Craggy layered karst strange rock B (~2.48m wide × 3.70m high × 0.88m thick)."""
    bm_k = bmesh.new()
    bm_m = bmesh.new()

    add_karst_lobe(bm_k, (0.0, 0.42, 0.0), (1.24, 1.02, 0.45), (0.0, 4.0, -3.0), subdiv=2, seed=211, amp=0.20)
    add_karst_lobe(bm_k, (-0.72, 1.78, -0.05), (0.56, 0.98, 0.40), (-4.0, 15.0, 8.0), subdiv=2, seed=212, amp=0.22)
    add_karst_lobe(bm_k, (0.28, 1.92, 0.06), (0.68, 1.12, 0.42), (6.0, -9.0, -6.0), subdiv=2, seed=213, amp=0.22)
    add_karst_lobe(bm_k, (-0.22, 3.06, 0.03), (0.94, 0.68, 0.42), (4.0, -6.0, 7.0), subdiv=2, seed=214, amp=0.22)
    add_karst_lobe(bm_k, (0.76, 2.75, -0.02), (0.48, 0.66, 0.36), (-5.0, 12.0, -9.0), subdiv=1, seed=215, amp=0.20)
    add_karst_lobe(bm_m, (0.0, 0.06, 0.28), (0.86, 0.24, 0.30), subdiv=1, seed=216, amp=0.14)
    add_karst_lobe(bm_m, (-0.25, 3.52, 0.02), (0.58, 0.20, 0.30), subdiv=1, seed=217, amp=0.15)

    return join_parts(
        "karst_monolith_b",
        [
            create_part("KarstMonoBBody", bm_k, mats["karst_light"], smooth=True, box_uv_scale=0.44),
            create_part("KarstMonoBMoss", bm_m, mats["karst_moss"], smooth=True, box_uv_scale=0.50),
        ],
    )


def build_karst_crouch_arch(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Natural eroded karst arch shortcut: clear under-arch opening 1.56m wide (x=-0.78..+0.78) × 1.28m high!"""
    bm_k = bmesh.new()
    bm_m = bmesh.new()

    # Left & Right grounded piers (|x| = 0.78 .. 1.42, leaving x = -0.78..+0.78 completely clear up to y=1.28!)
    for sx in (-1.0, 1.0):
        add_box(bm_k, (sx * 1.08, 0.42, 0.0), (0.58, 1.88, 0.92))
        add_karst_lobe(bm_k, (sx * 1.14, 0.58, 0.02), (0.34, 1.06, 0.56), (4.0, sx * 12.0, 0.0), subdiv=2, seed=231 + int(sx + 2), amp=0.14)
        add_karst_lobe(bm_m, (sx * 1.10, 0.05, 0.38), (0.36, 0.24, 0.34), subdiv=1, seed=241 + int(sx + 2), amp=0.12)

    # Overhead natural karst bridge span (bottom sits strictly >= 1.28m above y=0!)
    add_box(bm_k, (0.0, 1.86, 0.0), (2.72, 1.14, 0.96))
    add_karst_lobe(bm_k, (-0.54, 2.28, 0.04), (0.86, 0.72, 0.58), (3.0, 9.0, 4.0), subdiv=2, seed=251, amp=0.16)
    add_karst_lobe(bm_k, (0.52, 2.34, -0.04), (0.88, 0.76, 0.58), (-4.0, -8.0, -5.0), subdiv=2, seed=252, amp=0.16)
    add_karst_lobe(bm_k, (0.0, 2.94, 0.0), (0.95, 0.52, 0.50), subdiv=2, seed=253, amp=0.18)
    add_karst_lobe(bm_m, (0.0, 3.26, 0.04), (0.76, 0.24, 0.42), subdiv=1, seed=254, amp=0.14)

    return join_parts(
        "karst_crouch_arch",
        [
            create_part("KarstCrouchBody", bm_k, mats["karst_light"], smooth=True, box_uv_scale=0.44),
            create_part("KarstCrouchMoss", bm_m, mats["karst_moss"], smooth=True, box_uv_scale=0.50),
        ],
    )


def build_stone_maze_lantern(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Hexagonal mossy Jiangnan stone lantern ('古石灯笼', 1.78m tall) with warm amber firebox."""
    m_glow = make_mat(
        "Mat_LanternAmber",
        (0.98, 0.78, 0.42),
        roughness=0.35,
        emission_srgb=(1.0, 0.74, 0.34),
        emission_strength=2.4,
    )
    bm_s = bmesh.new()
    bm_m = bmesh.new()
    bm_g = bmesh.new()

    # Grounded hexagonal plinth + lotus seat + shaft + firebox tray + curved hexagonal cap
    add_cyl(bm_s, (0.0, -0.38, 0.0), (0.0, 0.16, 0.0), 0.38, 0.32, segs=6)
    add_cyl(bm_m, (0.0, 0.16, 0.0), (0.0, 0.28, 0.0), 0.33, 0.24, segs=6)
    add_cyl(bm_s, (0.0, 0.28, 0.0), (0.0, 0.98, 0.0), 0.13, 0.11, segs=6)
    add_cyl(bm_s, (0.0, 0.98, 0.0), (0.0, 1.10, 0.0), 0.16, 0.29, segs=6)

    # Glowing amber core + 6 corner lattice stone mullions
    add_cyl(bm_g, (0.0, 1.11, 0.0), (0.0, 1.38, 0.0), 0.16, 0.16, segs=6)
    for i in range(6):
        ang = i * (math.pi / 3.0)
        cx, cz = math.cos(ang) * 0.21, math.sin(ang) * 0.21
        add_cyl(bm_s, (cx, 1.10, cz), (cx, 1.40, cz), 0.028, 0.028, segs=5)

    # Hexagonal stone roof cap & lotus bud finial
    add_cyl(bm_s, (0.0, 1.39, 0.0), (0.0, 1.58, 0.0), 0.40, 0.14, segs=6)
    add_cyl(bm_m, (0.0, 1.58, 0.0), (0.0, 1.68, 0.0), 0.14, 0.05, segs=6)
    add_karst_lobe(bm_s, (0.0, 1.73, 0.0), (0.07, 0.09, 0.07), subdiv=1, seed=301, amp=0.05)

    return join_parts(
        "stone_maze_lantern",
        [
            create_part("LanternStone", bm_s, mats["bluestone"], box_uv_scale=0.6),
            create_part("LanternMoss", bm_m, mats["karst_moss"], box_uv_scale=0.6),
            create_part("LanternGlow", bm_g, m_glow),
        ],
    )


def build_stone_sundial_pedestal(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Ancient mossy carved bluestone sundial & compass altar ('烟山古石日晷') for Maze West Alcove."""
    m_bronze = make_mat("Mat_AncientBronze", (0.28, 0.44, 0.36), metallic=0.65, roughness=0.46)
    bm_s = bmesh.new()
    bm_m = bmesh.new()
    bm_b = bmesh.new()

    add_cyl(bm_s, (0.0, -0.35, 0.0), (0.0, 0.18, 0.0), 0.56, 0.48, segs=8)
    add_cyl(bm_m, (0.0, 0.18, 0.0), (0.0, 0.30, 0.0), 0.48, 0.36, segs=8)
    add_cyl(bm_s, (0.0, 0.30, 0.0), (0.0, 0.88, 0.0), 0.22, 0.19, segs=8)
    # Equatorial tilted stone dial disc (~31 deg Jiangnan latitude!) + bronze gnomon needle
    add_cyl(bm_s, (0.0, 0.94, 0.04), (0.0, 1.05, -0.02), 0.44, 0.44, segs=16)
    add_cyl(bm_b, (0.0, 0.96, 0.06), (0.0, 1.32, -0.15), 0.022, 0.006, segs=8)
    add_cyl(bm_b, (0.0, 0.99, 0.04), (0.0, 1.06, 0.0), 0.16, 0.16, segs=12)

    return join_parts(
        "stone_sundial_pedestal",
        [
            create_part("SundialStone", bm_s, mats["bluestone"], box_uv_scale=0.6),
            create_part("SundialMoss", bm_m, mats["karst_moss"], box_uv_scale=0.6),
            create_part("SundialBronze", bm_b, m_bronze),
        ],
    )


def build_cliff_moya_stele(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Sheer mossy karst cliff face with recessed '竹石清音' Moya carving (faces -X West by default)."""
    m_carving = make_tex_mat("Mat_MoyaCarving", TEX_DIR / "stele_cliff_carving.png", roughness=0.80, emission_strength=0.06)
    bm_k = bmesh.new()
    bm_s = bmesh.new()
    bm_m = bmesh.new()
    bm_f = bmesh.new()

    # Backing karst cliff mass centered around x = +0.42 so front carved face sits cleanly at x = -0.06
    add_box(bm_k, (0.44, 1.52, 0.0), (0.88, 3.90, 2.28))
    add_karst_lobe(bm_k, (0.56, 0.95, -0.78), (0.58, 1.45, 0.66), subdiv=2, seed=401, amp=0.20)
    add_karst_lobe(bm_k, (0.56, 1.05, 0.78), (0.58, 1.52, 0.66), subdiv=2, seed=402, amp=0.20)
    add_karst_lobe(bm_k, (0.48, 3.12, 0.0), (0.64, 0.74, 1.32), subdiv=2, seed=403, amp=0.20)
    add_karst_lobe(bm_m, (0.38, 3.56, 0.0), (0.52, 0.28, 1.08), subdiv=1, seed=404, amp=0.15)
    add_karst_lobe(bm_m, (0.14, 0.08, -0.68), (0.36, 0.26, 0.42), subdiv=1, seed=405, amp=0.14)
    add_karst_lobe(bm_m, (0.14, 0.08, 0.68), (0.36, 0.26, 0.42), subdiv=1, seed=406, amp=0.14)

    # Chiseled stone frame & low stone offering shelf on the -X face
    add_box(bm_s, (0.04, 1.66, 0.0), (0.18, 1.96, 1.36))
    add_box(bm_s, (-0.12, 0.34, 0.0), (0.34, 0.14, 1.18))
    # UV quad facing -X (viewer stands West looking East +X -> right_gd = (0, 0, +1))
    add_uv_quad_gd(bm_f, (-0.062, 1.66, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 1.20, 1.80)

    return join_parts(
        "cliff_moya_stele",
        [
            create_part("MoyaKarst", bm_k, mats["karst_light"], smooth=True, box_uv_scale=0.42),
            create_part("MoyaFrame", bm_s, mats["bluestone"], box_uv_scale=0.55),
            create_part("MoyaMoss", bm_m, mats["karst_moss"], smooth=True, box_uv_scale=0.50),
            create_part("MoyaFace", bm_f, m_carving, recalc_normals=False),
        ],
    )


def _cavern_half_width(z_gd: float) -> float:
    """Half-width of walkable cavern gallery from South mouth (z=+6.1) to North inner sanctum (z=-5.4)."""
    if z_gd > 4.8:
        # Smoothly widen from 1.72m at portal mouth (z=+6.1) to 3.35m in Outer Gallery (z=+4.8)
        t = max(0.0, min(1.0, (6.1 - z_gd) / 1.3))
        return 1.72 + (3.35 - 1.72) * (t * t * (3.0 - 2.0 * t))
    if z_gd > -0.2:
        # Outer Gallery ("前厅"): ~6.7m total width
        return 3.35 + 0.14 * math.sin(z_gd * 0.9)
    if z_gd > -4.5:
        # Inner Sanctum ("内室"): vaulted ~7.1m wide chamber
        return 3.55 + 0.18 * math.cos((z_gd + 2.2) * 0.8)
    # Rounded North back apse closing smoothly toward z = -5.6
    t = max(0.0, min(1.0, (z_gd - (-5.65)) / 1.15))
    return 0.85 + (3.55 - 0.85) * math.sqrt(t)


def _cavern_vault_height(z_gd: float) -> float:
    if z_gd > 4.8:
        t = max(0.0, min(1.0, (6.1 - z_gd) / 1.3))
        return 3.32 + (3.95 - 3.32) * t
    if z_gd > -0.2:
        return 3.95 + 0.12 * math.cos(z_gd * 0.8)
    if z_gd > -4.5:
        return 4.58 + 0.15 * math.sin((z_gd + 2.4) * 0.7)
    t = max(0.0, min(1.0, (z_gd - (-5.65)) / 1.15))
    return 2.65 + (4.55 - 2.65) * math.sqrt(t)


def build_yanxia_cave_complex(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Complete 13m walk-in 2-chamber limestone cavern ('烟霞古洞') with mural, chronicle, jade pool & skylight."""
    m_plaque = make_tex_mat("Mat_YanxiaPlaque", TEX_DIR / "plaque_yanxia_cave.png", roughness=0.78, emission_strength=0.06)
    m_mural = make_tex_mat("Mat_YanxiaMural", TEX_DIR / "mural_yanxia_ancients.png", roughness=0.82, emission_strength=0.14)
    m_chron = make_tex_mat("Mat_YanxiaChronicle", TEX_DIR / "inscription_cave_chronicle.png", roughness=0.80, emission_strength=0.12)
    m_stal = make_tex_mat("Mat_Stalactite", TEX_DIR / "limestone_karst.png", roughness=0.72, tint_srgb=(0.86, 0.84, 0.76), emission_strength=0.06)
    m_pool = make_mat(
        "Mat_JadeSpringWater",
        (0.10, 0.44, 0.42),
        metallic=0.08,
        roughness=0.10,
        emission_srgb=(0.14, 0.52, 0.48),
        emission_strength=0.58,
    )
    m_beam = make_mat(
        "Mat_SkylightMistBeam",
        (0.86, 0.96, 0.90),
        roughness=1.0,
        emission_srgb=(0.76, 0.92, 0.84),
        emission_strength=0.85,
        alpha=0.11,
    )

    bm_in = bmesh.new()      # Interior sculpted limestone vault + wet stone floor
    bm_out = bmesh.new()     # Exterior craggy karst mountain bluff shell
    bm_moss = bmesh.new()    # Exterior mossy cliff ledges & skylight rim
    bm_stone = bmesh.new()   # Carved stone frames, lintel & pool coping
    bm_stal = bmesh.new()    # Stalactites & stalagmites
    bm_pool = bmesh.new()    # Jade spring water surface
    bm_beam = bmesh.new()    # Translucent skylight mist shaft
    bm_pq = bmesh.new()      # Portal plaque
    bm_mq = bmesh.new()      # West Wall Ancient Mineral Mural
    bm_cq = bmesh.new()      # East Wall Historical Chronicle

    # 1) Interior vaulted karst tunnel shell (inward-facing normals!) from z = +6.10 to z = -5.65
    z_rings = [6.10, 5.45, 4.75, 3.70, 2.55, 1.35, 0.20, -0.85, -1.90, -2.85, -3.80, -4.65, -5.25, -5.65]
    arch_n = 14
    rng = random.Random(6288)
    rings_verts: list[list[bmesh.types.BMVert]] = []
    for r_idx, zg in enumerate(z_rings):
        hw = _cavern_half_width(zg)
        vh = _cavern_vault_height(zg)
        row: list[bmesh.types.BMVert] = []
        for a_idx in range(arch_n + 1):
            theta = math.pi * (a_idx / arch_n)  # 0 = East (+X), pi/2 = Crown (+Y), pi = West (-X)
            base_x = math.cos(theta) * hw
            base_y = math.sin(theta) * vh
            # Keep floor rim plunging to y = -0.35 so wall meets floor watertight; keep mural/chronicle bays flatter!
            if a_idx == 0 or a_idx == arch_n:
                base_y = -0.38
                jitter = 0.0
                vx_out = base_x
            else:
                in_art_bay = (1.20 <= zg <= 4.80) and (a_idx in (1, 2, 3, 4, arch_n - 4, arch_n - 3, arch_n - 2, arch_n - 1))
                if in_art_bay:
                    jitter = 0.0
                    sign_x = 1.0 if base_x >= 0.0 else -1.0
                    vx_out = sign_x * max(abs(base_x), 3.44)
                else:
                    amp = 0.04 if r_idx == 0 else 0.19
                    jitter = rng.uniform(-amp, amp)
                    vx_out = base_x + jitter * math.cos(theta)
            # Carve upward skylight dome chimney near (x ≈ -1.25, z ≈ -2.85)
            sky_d = math.hypot(vx_out - (-1.25), zg - (-2.85))
            if base_y > 2.8 and sky_d < 1.35:
                base_y += (1.0 - sky_d / 1.35) * 0.95
            v = bm_in.verts.new(gd_to_bl(Vector((vx_out, base_y + jitter * 0.6, zg))))
            row.append(v)
        rings_verts.append(row)

    # Connect rings with INWARD-facing winding (toward cavern centerline (0, 1.5, zg))
    for r_idx in range(len(z_rings) - 1):
        r0 = rings_verts[r_idx]
        r1 = rings_verts[r_idx + 1]
        for a_idx in range(arch_n):
            f = bm_in.faces.new([r0[a_idx], r1[a_idx], r1[a_idx + 1], r0[a_idx + 1]])
            center_bl = gd_to_bl(Vector((0.0, 1.5, 0.5 * (z_rings[r_idx] + z_rings[r_idx + 1]))))
            face_mid = sum((v.co for v in f.verts), Vector()) * 0.25
            f.normal_update()
            if f.normal.dot(center_bl - face_mid) < 0.0:
                f.normal_flip()

    # Close North back apse wall at z_rings[-1] facing +Z (inward)
    back_row = rings_verts[-1]
    back_bot = bm_in.verts.new(gd_to_bl(Vector((0.0, -0.38, -5.72))))
    for a_idx in range(arch_n):
        f = bm_in.faces.new([back_bot, back_row[a_idx + 1], back_row[a_idx]])
        f.normal_update()
        if f.normal.dot(gd_to_bl(Vector((0.0, 1.2, 0.0))) - gd_to_bl(Vector((0.0, 1.2, -5.7)))) < 0.0:
            f.normal_flip()

    # 2) Wet Chiseled Limestone Floor Slab (y = +0.025m) with sunken Jade Spring Pool basin at x∈[-3.05,-1.05], z∈[-4.35,-1.35]!
    fx_vals = [-3.75, -3.05, -1.05, 1.05, 3.75]
    fz_vals = [-5.80, -4.35, -1.35, 1.50, 6.25]
    f_grid: list[list[bmesh.types.BMVert]] = []
    for fz in fz_vals:
        frow = []
        for fx in fx_vals:
            frow.append(bm_in.verts.new(gd_to_bl(Vector((fx, 0.026, fz)))))
        f_grid.append(frow)
    for iz in range(len(fz_vals) - 1):
        for ix in range(len(fx_vals) - 1):
            # Cell (ix=1, iz=1) is the sunken Jade Spring Pool cutout!
            if ix == 1 and iz == 1:
                continue
            f = bm_in.faces.new([f_grid[iz][ix], f_grid[iz + 1][ix], f_grid[iz + 1][ix + 1], f_grid[iz][ix + 1]])
            f.normal_update()
            if f.normal.z < 0.0:
                f.normal_flip()

    # Sunken Jade Spring Pool walls, dark pebble bottom (y = -0.32m), glowing emerald water (y = +0.07m) & mossy stone rim!
    add_box(bm_in, (-2.05, -0.36, -2.85), (2.30, 0.14, 3.30))
    add_box(bm_pool, (-2.05, 0.04, -2.85), (2.06, 0.08, 3.06))
    # Mossy irregular limestone rim boulders around the Jade Spring Pool (max y ≈ 0.22m)
    pool_rim_pts = [
        (-3.08, -3.85), (-3.08, -2.85), (-3.08, -1.85),
        (-2.55, -1.32), (-1.65, -1.32), (-1.04, -1.85),
        (-1.04, -2.85), (-1.04, -3.85), (-1.65, -4.38), (-2.55, -4.38),
    ]
    for idx, (rx, rz) in enumerate(pool_rim_pts):
        add_karst_lobe(bm_stone, (rx, 0.09, rz), (0.34, 0.14, 0.36), (0.0, idx * 29.0, 0.0), subdiv=1, seed=500 + idx, amp=0.14)
        if idx % 2 == 0:
            add_karst_lobe(bm_moss, (rx, 0.17, rz), (0.24, 0.08, 0.26), subdiv=1, seed=530 + idx, amp=0.12)

    # 3) Exterior Craggy Jiangnan Karst Mountain Bluff Shell (recalc_normals=True on bm_out -> outward normals!)
    # Left & Right Portal Cliff Buttresses (leaving x = -1.66 .. +1.66 completely open up to y = 3.28 at z = +5.3..+6.4!)
    for sx in (-1.0, 1.0):
        add_box(bm_out, (sx * 3.85, 1.75, 5.75), (4.35, 6.20, 1.55))
        add_karst_lobe(bm_out, (sx * 2.55, 1.45, 6.05), (1.02, 2.35, 0.85), (5.0, sx * 16.0, -sx * 6.0), subdiv=2, seed=601 + int(sx + 2), amp=0.18)
        add_karst_lobe(bm_out, (sx * 4.55, 1.85, 5.85), (1.65, 2.85, 1.25), (-4.0, sx * 22.0, sx * 8.0), subdiv=2, seed=611 + int(sx + 2), amp=0.22)
        add_karst_lobe(bm_moss, (sx * 2.65, 0.05, 6.42), (0.85, 0.42, 0.55), subdiv=1, seed=621 + int(sx + 2), amp=0.15)

    # Portal Over-Arch Cliff Brow & Chiseled Lintel ("烟霞古洞") at y = 3.30..5.65, z = +5.25..+6.35
    add_box(bm_out, (0.0, 4.52, 5.68), (4.80, 2.42, 1.48))
    add_karst_lobe(bm_out, (-1.65, 4.85, 5.88), (1.45, 0.95, 0.95), subdiv=2, seed=631, amp=0.18)
    add_karst_lobe(bm_out, (1.65, 4.92, 5.85), (1.48, 0.98, 0.95), subdiv=2, seed=632, amp=0.18)
    add_karst_lobe(bm_moss, (0.0, 5.56, 5.72), (2.25, 0.46, 0.88), subdiv=1, seed=633, amp=0.16)
    # Recessed bluestone plaque frame facing +Z South at (0.0, 3.84, 6.42)
    add_box(bm_stone, (0.0, 3.84, 6.32), (2.88, 1.06, 0.28))
    add_uv_quad_gd(bm_pq, (0.0, 3.84, 6.47), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), 2.64, 0.88)

    # Thick West, East & North Mountain Cliff Walls & Crown Boulders (keeping skylight chimney (-1.25, -2.85) open!)
    for sx, side_x in ((-1.0, -4.95), (1.0, 4.85)):
        add_box(bm_out, (side_x, 1.85, -0.25), (2.65, 6.45, 11.80))
        for k, kz in enumerate([3.8, 1.0, -1.8, -4.4]):
            add_karst_lobe(
                bm_out,
                (side_x + sx * 0.55, 1.95 + (k % 2) * 0.45, kz),
                (1.45, 2.85, 2.05),
                (4.0, sx * 14.0, -sx * 7.0),
                subdiv=2,
                seed=640 + int(sx + 2) * 10 + k,
                amp=0.22,
            )
            add_karst_lobe(bm_moss, (side_x + sx * 0.35, 4.85, kz), (1.15, 0.48, 1.45), subdiv=1, seed=670 + int(sx + 2) * 10 + k, amp=0.16)

    # North Back Cliff Mass (z = -5.45 .. -6.65)
    add_box(bm_out, (0.0, 2.05, -6.05), (9.80, 6.80, 1.65))
    for k, kx in enumerate([-3.2, 0.0, 3.1]):
        add_karst_lobe(bm_out, (kx, 2.25, -6.15), (2.15, 3.10, 1.15), subdiv=2, seed=690 + k, amp=0.22)

    # Roof Cap Mountain Mass with an authentic open Skylight Crevice ("一线天光") around (x=-1.25, z=-2.85)!
    roof_blocks = [
        (0.0, 4.95, 2.65, 8.80, 1.55, 5.20),    # Front roof over Outer Gallery (z = +0.05..+5.25)
        (2.15, 5.25, -2.85, 4.50, 1.45, 5.80),  # East roof over Inner Sanctum (x = -0.10..+4.40)
        (-3.65, 5.20, -2.85, 2.40, 1.45, 5.80), # Far-West roof (x = -4.85..-2.45)
        (-1.25, 5.20, -0.75, 2.50, 1.40, 1.65), # South lip of skylight (z = -1.58..+0.08)
        (-1.25, 5.25, -4.95, 2.50, 1.45, 1.75), # North lip of skylight (z = -5.82..-4.08)
    ]
    for bx, by, bz, sx_s, sy_s, sz_s in roof_blocks:
        add_box(bm_out, (bx, by, bz), (sx_s, sy_s, sz_s))

    # Sculpted karst crags & mossy crown boulders atop the roof around the skylight opening
    crown_lobes = [
        (0.2, 5.55, 3.2, 2.4, 0.85, 2.1),
        (-2.2, 5.45, 1.8, 1.9, 0.80, 1.8),
        (2.2, 5.75, -1.6, 2.1, 0.95, 2.2),
        (1.6, 5.80, -4.2, 2.0, 0.90, 1.8),
        (-3.2, 5.65, -2.8, 1.5, 0.82, 2.2),
    ]
    for idx, (cx, cy, cz, rx, ry, rz) in enumerate(crown_lobes):
        add_karst_lobe(bm_out, (cx, cy, cz), (rx, ry, rz), subdiv=2, seed=710 + idx, amp=0.20)
        add_karst_lobe(bm_moss, (cx, cy + ry * 0.72, cz), (rx * 0.78, 0.34, rz * 0.78), subdiv=1, seed=730 + idx, amp=0.15)

    # Translucent Volumetric-Style Skylight Mist Beam ("一线天光雾柱") slanting from skylight to Jade Spring Pool
    add_cyl(bm_beam, (-1.25, 5.05, -2.85), (-1.95, 0.10, -2.85), 0.56, 1.18, segs=14, cap_ends=False)

    # 4) Outer Gallery Recessed Ancient Mineral Mural (West Wall x=-3.16, z=+2.85, facing +X East!)
    add_box(bm_stone, (-3.26, 1.72, 2.85), (0.24, 1.74, 3.28))
    add_box(bm_stone, (-3.06, 0.78, 2.85), (0.28, 0.14, 3.36))
    add_uv_quad_gd(bm_mq, (-3.12, 1.72, 2.85), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), 3.08, 1.54)

    # 5) Outer Gallery Recessed Historical Chronicle Stele (East Wall x=+3.16, z=+2.85, facing -X West!)
    add_box(bm_stone, (3.26, 1.66, 2.85), (0.24, 2.22, 1.56))
    add_box(bm_stone, (3.08, 0.48, 2.85), (0.26, 0.14, 1.62))
    add_uv_quad_gd(bm_cq, (3.12, 1.66, 2.85), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), 1.38, 2.06)

    # 6) 18 Ceiling Limestone Stalactites + 8 Margin/Pool Stalagmites ("钟乳石与石笋")
    stalactite_specs = [
        # (x, z, len, r_base) — over central walkways tip stays >= 2.65m above floor!
        (-1.25, 4.55, 0.95, 0.18), (1.30, 4.40, 1.05, 0.20), (0.15, 3.95, 0.88, 0.16),
        (-2.15, 3.55, 1.25, 0.24), (2.15, 3.65, 1.22, 0.23), (-0.65, 2.65, 1.02, 0.18),
        (0.85, 2.25, 0.96, 0.17), (-1.95, 1.35, 1.38, 0.26), (1.95, 1.20, 1.34, 0.25),
        (0.05, 0.65, 1.12, 0.20), (-2.55, -0.45, 1.58, 0.28), (2.45, -0.55, 1.52, 0.27),
        (0.65, -1.35, 1.22, 0.22), (2.25, -2.15, 1.62, 0.28), (-2.65, -2.15, 1.65, 0.28),
        (1.45, -3.65, 1.35, 0.24), (-0.35, -4.25, 1.28, 0.22), (-2.25, -4.10, 1.55, 0.27),
    ]
    for sx, sz, slen, sr in stalactite_specs:
        top_y = _cavern_vault_height(sz) + 0.12
        mid_y = top_y - slen * 0.52
        tip_y = top_y - slen
        add_cyl(bm_stal, (sx, top_y, sz), (sx, mid_y, sz), sr, sr * 0.46, segs=7)
        add_cyl(bm_stal, (sx, mid_y, sz), (sx, tip_y, sz), sr * 0.48, 0.022, segs=7)

    stalagmite_specs = [
        # Placed along outer margins / pool edge so central floor & mural corners stay unobstructed
        (-2.95, 4.82, 1.12, 0.22), (2.95, 4.75, 1.12, 0.22),
        (-2.95, 0.72, 1.28, 0.25), (2.95, 0.65, 1.26, 0.25),
        (-3.12, -2.35, 1.55, 0.30), (-2.85, -4.55, 1.48, 0.28),
        (2.95, -4.15, 1.38, 0.26), (1.85, -4.95, 1.25, 0.24),
    ]
    for gx, gz, glen, gr in stalagmite_specs:
        add_cyl(bm_stal, (gx, -0.15, gz), (gx, glen * 0.55, gz), gr, gr * 0.52, segs=7)
        add_cyl(bm_stal, (gx, glen * 0.52, gz), (gx, glen, gz), gr * 0.54, 0.045, segs=7)

    return join_parts(
        "yanxia_cave_complex",
        [
            create_part("CaveInteriorVault", bm_in, mats["karst_dark"], smooth=True, recalc_normals=False, box_uv_scale=0.38),
            create_part("CaveExteriorKarst", bm_out, mats["karst_light"], smooth=True, recalc_normals=True, box_uv_scale=0.32),
            create_part("CaveExteriorMoss", bm_moss, mats["karst_moss"], smooth=True, recalc_normals=True, box_uv_scale=0.45),
            create_part("CaveCarvedFrames", bm_stone, mats["bluestone"], box_uv_scale=0.55),
            create_part("CaveStalactites", bm_stal, m_stal, smooth=True, box_uv_scale=0.65),
            create_part("CaveJadePool", bm_pool, m_pool),
            create_part("CavePortalPlaque", bm_pq, m_plaque, recalc_normals=False),
            create_part("CaveMuralFace", bm_mq, m_mural, recalc_normals=False),
            create_part("CaveChronicleFace", bm_cq, m_chron, recalc_normals=False),
            create_part("CaveSkylightBeam", bm_beam, m_beam, smooth=True, recalc_normals=False),
        ],
    )


def build_ancestral_hearth_relics(mats: dict[str, bpy.types.Material]) -> bpy.types.Object:
    """Ancestral mountain-dwelling traces in Inner Sanctum: stone tea hearth, embers, clay kettle,
    carved stone scholar table & stools, bamboo slips ('古竹简'), Yue-kiln celadon tea set & oil lamp!"""
    m_ember = make_mat(
        "Mat_HearthEmbers",
        (0.95, 0.36, 0.12),
        roughness=0.55,
        emission_srgb=(1.0, 0.38, 0.10),
        emission_strength=2.8,
    )
    m_flame = make_mat(
        "Mat_OilLampFlame",
        (1.0, 0.85, 0.42),
        roughness=0.25,
        emission_srgb=(1.0, 0.80, 0.36),
        emission_strength=3.4,
    )
    m_clay = make_mat("Mat_SeasonedClayKettle", (0.24, 0.18, 0.15), roughness=0.68)
    m_bamboo_slip = make_mat("Mat_AncientBambooSlips", (0.68, 0.54, 0.30), roughness=0.72)
    m_celadon = make_mat("Mat_YueKilnCeladon", (0.50, 0.66, 0.56), metallic=0.05, roughness=0.24)

    bm_stone = bmesh.new()
    bm_moss = bmesh.new()
    bm_ember = bmesh.new()
    bm_flame = bmesh.new()
    bm_clay = bmesh.new()
    bm_slip = bmesh.new()
    bm_cel = bmesh.new()

    # 1) Mossy Bluestone Tea Hearth ("先民石砌茶灶") at (-0.88, 0.0, -0.35)
    hx, hz = -0.88, -0.35
    add_box(bm_stone, (hx, 0.06, hz), (1.06, 0.16, 0.96))
    add_box(bm_stone, (hx - 0.38, 0.34, hz), (0.26, 0.44, 0.84))
    add_box(bm_stone, (hx + 0.38, 0.34, hz), (0.26, 0.44, 0.84))
    add_box(bm_stone, (hx, 0.36, hz - 0.30), (0.56, 0.48, 0.24))
    add_box(bm_moss, (hx - 0.42, 0.14, hz + 0.36), (0.22, 0.12, 0.22))
    # Glowing charcoal bed inside hearth
    add_karst_lobe(bm_ember, (hx, 0.20, hz + 0.04), (0.24, 0.09, 0.24), subdiv=1, seed=801, amp=0.18)
    # Stone crossbar & clay mountain-spring tea kettle ("粗陶煮泉瓦铫")
    add_box(bm_stone, (hx, 0.54, hz + 0.02), (0.78, 0.06, 0.14))
    add_cyl(bm_clay, (hx, 0.56, hz + 0.02), (hx, 0.78, hz + 0.02), 0.16, 0.13, segs=10)
    add_cyl(bm_clay, (hx, 0.78, hz + 0.02), (hx, 0.83, hz + 0.02), 0.11, 0.04, segs=10)
    add_cyl(bm_clay, (hx + 0.13, 0.68, hz + 0.02), (hx + 0.24, 0.77, hz + 0.02), 0.032, 0.018, segs=6)
    add_cyl(bm_clay, (hx - 0.10, 0.80, hz + 0.02), (hx + 0.10, 0.90, hz + 0.02), 0.016, 0.016, segs=6)

    # 2) Carved Round Bluestone Scholar Table & Two Stone Drum Stools at (+0.38, 0.0, +0.10)
    tx, tz = 0.38, 0.10
    add_cyl(bm_stone, (tx, -0.10, tz), (tx, 0.12, tz), 0.38, 0.32, segs=10)
    add_cyl(bm_stone, (tx, 0.12, tz), (tx, 0.68, tz), 0.18, 0.21, segs=10)
    add_cyl(bm_stone, (tx, 0.68, tz), (tx, 0.77, tz), 0.68, 0.68, segs=16)
    # Two carved stone drum stools ("青石鼓墩")
    for sx, sz in [(tx - 0.84, tz + 0.42), (tx + 0.82, tz + 0.38)]:
        add_cyl(bm_stone, (sx, -0.06, sz), (sx, 0.44, sz), 0.21, 0.22, segs=10)
        add_moss_cap = (sx < tx)
        if add_moss_cap:
            add_cyl(bm_moss, (sx, 0.0, sz), (sx, 0.08, sz), 0.23, 0.21, segs=8)

    # 3) Bound Ancient Bamboo Slips ("烟山先民竹简") unrolled on the stone table + rolled scroll bundle
    for i in range(9):
        bx = tx - 0.26 + i * 0.048
        add_box(bm_slip, (bx, 0.785, tz + 0.12), (0.036, 0.016, 0.34), (0.0, 6.0, 0.0))
    # Rolled bamboo slip bundle beside it
    add_cyl(bm_slip, (tx + 0.26, 0.83, tz + 0.22), (tx + 0.44, 0.83, tz + 0.06), 0.055, 0.055, segs=10)

    # 4) Yue-Kiln Celadon Teapot & Two Tea Cups ("越窑青瓷茶盏")
    add_cyl(bm_cel, (tx + 0.22, 0.77, tz - 0.18), (tx + 0.22, 0.93, tz - 0.18), 0.085, 0.065, segs=10)
    add_cyl(bm_cel, (tx + 0.22, 0.93, tz - 0.18), (tx + 0.22, 0.97, tz - 0.18), 0.052, 0.022, segs=8)
    for cx, cz in [(tx + 0.04, tz - 0.22), (tx + 0.34, tz - 0.02)]:
        add_cyl(bm_cel, (cx, 0.77, cz), (cx, 0.835, cz), 0.036, 0.048, segs=10)

    # 5) Carved Stone Pine-Oil Lamp ("青石松油灯") with warm glowing wick flame
    lx, lz = tx - 0.26, tz - 0.22
    add_cyl(bm_stone, (lx, 0.77, lz), (lx, 0.95, lz), 0.065, 0.035, segs=8)
    add_cyl(bm_stone, (lx, 0.95, lz), (lx, 1.00, lz), 0.038, 0.095, segs=10)
    add_karst_lobe(bm_flame, (lx, 1.05, lz), (0.032, 0.065, 0.032), subdiv=1, seed=822, amp=0.05)

    return join_parts(
        "ancestral_hearth_relics",
        [
            create_part("RelicStone", bm_stone, mats["bluestone"], box_uv_scale=0.65),
            create_part("RelicMoss", bm_moss, mats["karst_moss"], box_uv_scale=0.65),
            create_part("RelicEmbers", bm_ember, m_ember),
            create_part("RelicFlame", bm_flame, m_flame),
            create_part("RelicClayKettle", bm_clay, m_clay),
            create_part("RelicBambooSlips", bm_slip, m_bamboo_slip),
            create_part("RelicCeladon", bm_cel, m_celadon, smooth=True),
        ],
    )


def export_all():
    clear_scene()
    mats = _shared_karst_materials()
    builders = [
        lambda: build_bamboo_maze_gate(mats),
        lambda: build_karst_monolith_a(mats),
        lambda: build_karst_monolith_b(mats),
        lambda: build_karst_crouch_arch(mats),
        lambda: build_stone_maze_lantern(mats),
        lambda: build_stone_sundial_pedestal(mats),
        lambda: build_cliff_moya_stele(mats),
        lambda: build_yanxia_cave_complex(mats),
        lambda: build_ancestral_hearth_relics(mats),
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
        ys = [p.z for p in bb]
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
    out_path = DEST / "v062_bamboo_cave.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_materials="EXPORT",
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
    )
    record = {
        "output": "game/assets/slice/v062_bamboo_cave.glb",
        "total_triangles": total_tris,
        "assets": meta,
    }
    (DOCS / "slice-v062-assets-build.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(f"Exported {out_path} ({total_tris} tris total)")
    for k, v in meta.items():
        print(" ", k, v["triangles"], "tris", v["godot_bounds_m"])


if __name__ == "__main__":
    export_all()
