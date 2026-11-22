#!/usr/bin/env python3
"""Build high-craftsmanship sunlit 3D stylized PBR architecture, landmarks & tactical desert props
for Yanshan Force v0.9.0 "Ahsarah Fortress" (Brakkesh sandstone kasbah x Zero Dam concrete bastion)
in Blender 4.5 LTS.

Run with Blender 4.5:
  blender --background --python tools/build_v090_ahsarah_architecture.py

Outputs:
  game/assets/slice/v090_ahsarah_architecture.glb
    - zero_dam_wall_monolith     : Colossal 110m x 42m Zero Dam concrete wall with buttresses, spillways & catwalk
    - babel_radar_tower          : 26m octagonal concrete & steel communications watchtower with radar dish
    - ahsarah_fortress_gatehouse : 20m Brakkesh x Zero Dam hybrid sandstone/concrete administrative fortress gatehouse
    - brakkesh_sandstone_pavilion: Detailed arched sandstone bazaar pavilion with dome, steps, awning & amphorae
    - cement_silo_complex        : Zero Dam twin industrial concrete cement silos with steel bridge & hoppers
    - substation_transformer_bay : Haavk electrical substation transformer with cooling fins, insulators & cyan console
    - tactical_desert_jeep       : Detailed 4x4 open-top military desert recon jeep with roll cage & tires
    - oasis_palm_cluster         : 3-trunk gracefully curved desert oasis date palm cluster with arched pinnate fronds
    - desert_acacia_tree         : North African flat-topped umbrella acacia tree
    - sandbag_bunker_wall        : Staggered 4-row pillowed sandbag firing emplacement with timber posts & crate
    - military_ammo_stack        : Palletized olive military supply crates, fuel cans & tarp
    - dimensional_rift_wall      : Yanxia Ancient Cave carved "次元石壁" monolith behind the skylight
    - desert_mesa_ring           : True 3D sculpted distant desert sandstone mesa & canyon ring (r=238m)
"""
from __future__ import annotations

import math
import random
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "v090_ahsarah_architecture.glb"
OUT_GLB.parent.mkdir(parents=True, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def srgb_lin(rgb: tuple[float, float, float]) -> tuple[float, float, float, float]:
    return (rgb[0] ** 2.2, rgb[1] ** 2.2, rgb[2] ** 2.2, 1.0)


def hex_lin(h: str) -> tuple[float, float, float, float]:
    h = h.lstrip("#")
    return srgb_lin((int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0))


def make_mat(name: str, hex_col: str, rough=0.78, metal=0.05, emit_hex: str | None = None, emit_str: float = 0.0, coat: float = 0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = hex_lin(hex_col)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.14
    if emit_hex is not None and emit_str > 0.0:
        bsdf.inputs["Emission Color"].default_value = hex_lin(emit_hex)
        bsdf.inputs["Emission Strength"].default_value = emit_str
    return mat


def make_vcol_mat(name: str, rough=0.88):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.0
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def gd_to_bl(v: tuple[float, float, float]) -> Vector:
    return Vector((v[0], -v[2], v[1]))


def add_box(bm: bmesh.types.BMesh, center_gd, size_gd, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    scale = Matrix.Diagonal((size_gd[0], size_gd[2], size_gd[1], 1.0))
    xf = Matrix.Translation(gd_to_bl(center_gd)) @ rot @ scale
    bmesh.ops.transform(bm, matrix=xf, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl(bm: bmesh.types.BMesh, center_gd, r_bot, r_top, height, segs=12, mat_idx=0, rot_deg_gd=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_bot, radius2=r_top, depth=height)
    verts = ret["verts"]
    rx, ry, rz = (math.radians(a) for a in rot_deg_gd)
    rot = Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
    xf = Matrix.Translation(gd_to_bl(center_gd)) @ rot
    bmesh.ops.transform(bm, matrix=xf, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl_pts(bm: bmesh.types.BMesh, p0_gd, p1_gd, r0, r1, segs=10, mat_idx=0):
    a = gd_to_bl(p0_gd)
    b = gd_to_bl(p1_gd)
    delta = b - a
    length = delta.length
    if length < 1e-4:
        return
    rot = Vector((0, 0, 1)).rotation_difference(delta.normalized()).to_matrix().to_4x4()
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=length)
    verts = ret["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) * 0.5) @ rot, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_sphere(bm: bmesh.types.BMesh, center_gd, radii_gd, segs=14, rings=9, mat_idx=0):
    ret = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    verts = ret["verts"]
    scale = Matrix.Diagonal((radii_gd[0], radii_gd[2], radii_gd[1], 1.0))
    bmesh.ops.transform(bm, matrix=Matrix.Translation(gd_to_bl(center_gd)) @ scale, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_dome(bm: bmesh.types.BMesh, center_gd, rx, ry, rz, segs=16, rings=7, mat_idx=0):
    """Upper hemisphere dome sitting cleanly at center_gd.y."""
    ring_verts = []
    cx, cy, cz = center_gd
    for ri in range(rings):
        phi = (float(ri) / float(rings)) * (math.pi * 0.5)
        r_ring = math.cos(phi)
        y_ring = cy + math.sin(phi) * ry
        row = []
        for si in range(segs):
            ang = (float(si) / float(segs)) * math.tau
            vx = cx + math.cos(ang) * rx * r_ring
            vz = cz + math.sin(ang) * rz * r_ring
            row.append(bm.verts.new(gd_to_bl((vx, y_ring, vz))))
        ring_verts.append(row)
    top_v = bm.verts.new(gd_to_bl((cx, cy + ry, cz)))
    for ri in range(rings - 1):
        for si in range(segs):
            s2 = (si + 1) % segs
            f = bm.faces.new((ring_verts[ri][si], ring_verts[ri][s2], ring_verts[ri + 1][s2], ring_verts[ri + 1][si]))
            f.material_index = mat_idx
    for si in range(segs):
        s2 = (si + 1) % segs
        f = bm.faces.new((ring_verts[-1][si], ring_verts[-1][s2], top_v))
        f.material_index = mat_idx


def add_arch_opening_wall(bm: bmesh.types.BMesh, cx, y0, cz, width, height, depth, arch_w, arch_h, mat_idx, along_z=False):
    """Build a crisp real architectural arch opening (left pier + right pier + arched voussoir spandrel header)."""
    pillar_w = max(0.22, (width - arch_w) * 0.5)
    spring_y = y0 + arch_h * 0.58
    arch_r = arch_w * 0.5
    top_y = y0 + height

    def _box(lx, ly, lz, sx, sy, sz, rot=(0.0, 0.0, 0.0)):
        if not along_z:
            add_box(bm, (cx + lx, ly, cz + lz), (sx, sy, sz), mat_idx, rot)
        else:
            add_box(bm, (cx + lz, ly, cz + lx), (sz, sy, sx), mat_idx, (rot[0], rot[1] + 90.0, rot[2]))

    # Left and right solid piers up to full height
    for sgn in (-1.0, 1.0):
        px = sgn * (arch_w * 0.5 + pillar_w * 0.5)
        _box(px, y0 + height * 0.5, 0.0, pillar_w, height, depth)

    # Spandrel blocks arching cleanly from spring_y to top_y
    n_seg = 10
    for i in range(n_seg):
        t0 = float(i) / float(n_seg)
        t1 = float(i + 1) / float(n_seg)
        tm = 0.5 * (t0 + t1)
        a0 = math.pi * (1.0 - t0)
        a1 = math.pi * (1.0 - t1)
        x0 = math.cos(a0) * arch_r
        x1 = math.cos(a1) * arch_r
        xm = 0.5 * (x0 + x1)
        seg_w = abs(x1 - x0) + 0.06
        arch_y = spring_y + math.sin(math.pi * tm) * (arch_h - (spring_y - y0))
        sp_h = max(0.18, top_y - arch_y)
        _box(xm, arch_y + sp_h * 0.5, 0.0, seg_w, sp_h, depth)


def finalize_obj(name: str, bm: bmesh.types.BMesh, mat_list: list, smooth: bool = False) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    for m in mat_list:
        mesh.materials.append(m)
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_materials() -> tuple[list, dict[str, int]]:
    specs = [
        ("Mat_SandstoneMain", "d8a768", 0.86, 0.02, None, 0.0, 0.0),         # 0
        ("Mat_SandstoneDark", "b27c44", 0.90, 0.02, None, 0.0, 0.0),         # 1
        ("Mat_SandstoneLight", "e8c58c", 0.82, 0.02, None, 0.0, 0.0),        # 2
        ("Mat_Terracotta", "b8643e", 0.84, 0.03, None, 0.0, 0.0),            # 3
        ("Mat_ConcreteMain", "a6a9ab", 0.86, 0.05, None, 0.0, 0.0),          # 4
        ("Mat_ConcreteDark", "767c80", 0.90, 0.08, None, 0.0, 0.0),          # 5
        ("Mat_SteelDark", "394048", 0.48, 0.72, None, 0.0, 0.0),             # 6
        ("Mat_SteelLight", "8d969e", 0.42, 0.65, None, 0.0, 0.0),            # 7
        ("Mat_CedarWood", "68472b", 0.82, 0.02, None, 0.0, 0.0),             # 8
        ("Mat_CanvasTan", "d8c59e", 0.92, 0.0, None, 0.0, 0.0),              # 9
        ("Mat_AhsarahRed", "b5362e", 0.82, 0.04, None, 0.0, 0.0),            # 10
        ("Mat_OliveMil", "525d3a", 0.78, 0.12, None, 0.0, 0.0),              # 11
        ("Mat_HaavkWhite", "e6ebf0", 0.34, 0.14, None, 0.0, 0.25),           # 12
        ("Mat_HaavkCyan", "3ae8ff", 0.20, 0.15, "2ad8ff", 2.8, 0.3),         # 13
        ("Mat_AmberGlow", "ffb84d", 0.22, 0.10, "ffaa33", 2.4, 0.2),         # 14
        ("Mat_Brass", "c89c46", 0.32, 0.82, None, 0.0, 0.2),                 # 15
        ("Mat_PalmTrunk", "7b593c", 0.92, 0.0, None, 0.0, 0.0),              # 16
        ("Mat_PalmFrond", "4c7d3c", 0.76, 0.0, None, 0.0, 0.0),              # 17
        ("Mat_PalmFrondSun", "6ca048", 0.74, 0.0, None, 0.0, 0.0),           # 18
        ("Mat_Rubber", "242628", 0.84, 0.05, None, 0.0, 0.0),                # 19
        ("Mat_GlassTint", "2d4958", 0.14, 0.18, None, 0.0, 0.75),            # 20
        ("Mat_WarningYellow", "e5b32e", 0.62, 0.10, None, 0.0, 0.0),         # 21
        ("Mat_Sandbag", "c7b085", 0.94, 0.0, None, 0.0, 0.0),                # 22
        ("Mat_KarstDark", "414b4e", 0.88, 0.08, None, 0.0, 0.0),             # 23
        ("Mat_RiftGlow", "48e5d8", 0.16, 0.10, "3cd8d0", 2.6, 0.3),          # 24
        ("Mat_Copper", "b86f42", 0.34, 0.80, None, 0.0, 0.15),               # 25
        ("Mat_DesertRock", "b97946", 0.94, 0.0, None, 0.0, 0.0),             # 26
        ("Mat_DesertRockDark", "8e5630", 0.96, 0.0, None, 0.0, 0.0),         # 27
        ("Mat_DesertRockLight", "d49c64", 0.92, 0.0, None, 0.0, 0.0),        # 28
        ("Mat_OasisReed", "5c8a3e", 0.80, 0.0, None, 0.0, 0.0),              # 29
    ]
    mat_list = [make_mat(*s) for s in specs]
    idx = {s[0]: i for i, s in enumerate(specs)}
    return mat_list, idx


def add_sculpted_rock(bm: bmesh.types.BMesh, center_gd, radii_gd, seed: int, mat_idx=26, strata_strength=0.22):
    """Create a crisp faceted, wind-eroded stratified desert sandstone boulder (NO smooth eggs/bricks!)."""
    rng = random.Random(seed)
    ret = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)
    verts = ret["verts"]
    cx, cy, cz = center_gd
    rx, ry, rz = radii_gd
    # Random angular plane directions for geological cleavage facets
    p1 = Vector((rng.uniform(-1, 1), rng.uniform(0.1, 0.9), rng.uniform(-1, 1))).normalized()
    p2 = Vector((rng.uniform(-1, 1), rng.uniform(-0.2, 0.8), rng.uniform(-1, 1))).normalized()
    p3 = Vector((rng.uniform(-1, 1), rng.uniform(0.3, 1.0), rng.uniform(-1, 1))).normalized()
    phase_a = rng.uniform(0.0, math.tau)
    phase_b = rng.uniform(0.0, math.tau)
    for v in verts:
        p = v.co.copy()
        # Horizontal sedimentary strata ledges + angular wind erosion
        strata = math.sin(p.z * 7.5 + phase_a) * strata_strength + math.cos(p.x * 3.1 + p.y * 2.7 + phase_b) * 0.14
        r_mult = 1.0 + strata
        # Flatten bottom slightly & add geological cleavage bevels
        if p.dot(p1) > 0.55:
            r_mult *= 0.82
        if p.dot(p2) > 0.60:
            r_mult *= 0.84
        if p.dot(p3) > 0.65:
            r_mult *= 0.78
        # Godot coordinates: p.x -> x, p.z -> y (up), -p.y -> z
        gx = cx + p.x * rx * r_mult
        gy = cy + p.z * ry * r_mult
        gz = cz - p.y * rz * r_mult
        # Wide stable base tucked below center
        if p.z < -0.25:
            gx = cx + (gx - cx) * 1.14
            gz = cz + (gz - cz) * 1.14
        v.co = gd_to_bl((gx, gy, gz))
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def build_zero_dam_wall(mats, M):
    """Monumental Zero Dam concrete canyon wall (~114m wide x 40m tall x 14m deep)."""
    bm = bmesh.new()
    C_MAIN = M["Mat_ConcreteMain"]
    C_DARK = M["Mat_ConcreteDark"]
    STEEL = M["Mat_SteelDark"]
    WARN = M["Mat_WarningYellow"]
    CYAN = M["Mat_HaavkCyan"]
    AMBER = M["Mat_AmberGlow"]

    # Main stepped battered dam core (deeply rooted down to y=-14m so never exposed on canyon slopes!)
    add_box(bm, (0.0, -1.0, 0.0), (118.0, 26.0, 15.6), C_DARK)
    add_box(bm, (0.0, 19.0, -0.8), (114.0, 14.0, 12.0), C_MAIN)
    add_box(bm, (0.0, 32.0, -1.6), (112.0, 12.0, 9.6), C_MAIN)
    # Massive sculpted sandstone canyon cliff abutment wings locking BOTH sides of the dam into canyon mountains!
    ROCK_M = M["Mat_DesertRock"]
    ROCK_D = M["Mat_DesertRockDark"]
    ROCK_L = M["Mat_DesertRockLight"]
    for sgn_idx, sgn in enumerate((-1.0, 1.0)):
        # Sweeping stepped red-ochre canyon rock shoulders anchoring dam flanks (|x|>=68m, strictly behind z=-150m so Helipad & Radar stay 100% clear!)
        add_sculpted_rock(bm, (sgn * 70.0, 14.0, -2.0), (18.0, 26.0, 12.0), 101 + sgn_idx * 17, ROCK_D, 0.18)
        add_sculpted_rock(bm, (sgn * 86.0, 18.0, 1.0), (20.0, 29.0, 14.0), 137 + sgn_idx * 19, ROCK_M, 0.18)
        add_sculpted_rock(bm, (sgn * 76.0, 5.0, 6.0), (12.0, 13.0, 9.0), 173 + sgn_idx * 23, ROCK_L, 0.16)
        add_sculpted_rock(bm, (sgn * 94.0, 11.0, 8.0), (16.0, 20.0, 13.0), 251 + sgn_idx * 31, ROCK_D, 0.18)
    # Horizontal concrete architectural lift bands
    for ly in (11.8, 19.2, 26.2, 33.4, 37.8):
        add_box(bm, (0.0, ly, 4.35 - (ly * 0.06)), (113.0, 0.65, 1.4), C_DARK)

    # 8 massive sloped vertical structural buttresses across face
    for bx in (-46.0, -32.0, -18.0, -6.5, 6.5, 18.0, 32.0, 46.0):
        add_box(bm, (bx, 18.5, 4.8), (3.4, 37.0, 4.6), C_MAIN, (-5.5, 0.0, 0.0))
        add_box(bm, (bx, 3.5, 7.0), (4.0, 7.0, 3.2), C_DARK)
        # Top parapet turret block above each buttress
        add_box(bm, (bx, 39.2, 2.2), (3.8, 2.8, 4.4), C_DARK)

    # 3 central recessed hydro spillway chutes with dark sluice gates & side guide walls
    for sx in (-12.2, 0.0, 12.2):
        # Recessed dark intake bay
        add_box(bm, (sx, 29.0, 3.4), (7.6, 8.2, 1.4), STEEL)
        # 4 sluice louver ribs
        for ry in (26.2, 28.0, 29.8, 31.6):
            add_box(bm, (sx, ry, 4.25), (7.4, 0.42, 0.55), C_DARK)
        # Sloped concrete spillway chute plunging down
        add_box(bm, (sx, 14.0, 6.8), (7.2, 25.0, 2.4), C_DARK, (-14.5, 0.0, 0.0))
        # Chute guide cheek walls
        for sgn in (-1.0, 1.0):
            add_box(bm, (sx + sgn * 3.8, 13.5, 7.6), (0.85, 24.5, 2.6), C_MAIN, (-14.5, 0.0, 0.0))
        # Bottom stilling apron lip
        add_box(bm, (sx, 1.8, 11.4), (8.2, 3.6, 3.2), C_MAIN)

    # Top cantilevered crest highway deck + guardrails + industrial lamp posts
    add_box(bm, (0.0, 38.4, 0.5), (116.0, 1.8, 11.8), C_DARK)
    add_box(bm, (0.0, 39.8, 5.9), (115.0, 1.2, 0.55), C_MAIN)
    add_box(bm, (0.0, 40.55, 5.95), (115.0, 0.22, 0.22), STEEL)
    # Warning stripes on central control parapet
    add_box(bm, (0.0, 36.8, 3.6), (26.0, 1.2, 0.8), WARN)
    add_box(bm, (0.0, 36.8, 4.05), (22.0, 0.55, 0.25), STEEL)
    # Haavk hydro telemetry beacons on crest
    for lx in (-38.0, -24.0, 0.0, 24.0, 38.0):
        add_cyl(bm, (lx, 42.4, 5.5), 0.16, 0.12, 4.8, 8, STEEL)
        add_box(bm, (lx, 44.6, 6.2), (1.4, 0.32, 0.9), STEEL)
        add_box(bm, (lx, 44.38, 6.35), (1.1, 0.18, 0.45), CYAN if lx == 0.0 else AMBER)

    return finalize_obj("zero_dam_wall_monolith", bm, mats, smooth=False)


def build_babel_radar_tower(mats, M):
    """26m Zero Dam / Babel Tower inspired concrete-and-steel radar & command tower."""
    bm = bmesh.new()
    C_MAIN = M["Mat_ConcreteMain"]
    C_DARK = M["Mat_ConcreteDark"]
    STEEL = M["Mat_SteelDark"]
    ST_LT = M["Mat_SteelLight"]
    GLASS = M["Mat_GlassTint"]
    WHITE = M["Mat_HaavkWhite"]
    CYAN = M["Mat_HaavkCyan"]
    RED = M["Mat_AhsarahRed"]

    # Heavy octagonal concrete plinth deeply grounded down to y=-3.0m
    add_cyl(bm, (0.0, 0.1, 0.0), 4.9, 4.1, 6.2, 8, C_DARK)
    add_cyl(bm, (0.0, 3.4, 0.0), 4.2, 3.8, 0.6, 8, C_MAIN)
    # Tapered octagonal reinforced concrete shaft
    add_cyl(bm, (0.0, 9.8, 0.0), 3.1, 2.55, 12.6, 8, C_MAIN)
    # 4 vertical concrete structural fins + slit windows
    for ang_deg in (0, 90, 180, 270):
        rad = math.radians(ang_deg)
        fx, fz = math.cos(rad) * 2.75, math.sin(rad) * 2.75
        add_box(bm, (fx, 9.8, fz), (0.65, 12.0, 1.15), C_DARK, (0.0, ang_deg, 0.0))
        add_box(bm, (fx * 0.92, 10.2, fz * 0.92), (0.28, 7.6, 0.35), GLASS, (0.0, ang_deg, 0.0))

    # Cantilevered command cabin deck (y = 16..20m)
    add_cyl(bm, (0.0, 16.5, 0.0), 2.8, 4.7, 1.4, 8, C_DARK)
    add_cyl(bm, (0.0, 17.5, 0.0), 4.85, 4.85, 0.65, 8, WHITE)
    # 360-degree panoramic tinted observation cabin
    add_cyl(bm, (0.0, 18.85, 0.0), 4.2, 4.4, 2.2, 8, GLASS)
    for si in range(8):
        ang = si * (math.tau / 8.0)
        mx, mz = math.cos(ang) * 4.35, math.sin(ang) * 4.35
        add_cyl(bm, (mx, 18.85, mz), 0.14, 0.14, 2.35, 6, STEEL)
        # Exterior perimeter catwalk stanchion
        px, pz = math.cos(ang) * 5.05, math.sin(ang) * 5.05
        add_cyl(bm, (px, 18.2, pz), 0.06, 0.06, 1.15, 6, ST_LT)
    # Roof cap & Haavk cyan glow collar
    add_cyl(bm, (0.0, 20.2, 0.0), 4.8, 3.8, 0.85, 8, WHITE)
    add_cyl(bm, (0.0, 19.85, 0.0), 4.65, 4.65, 0.18, 8, CYAN)

    # Upper steel radar mast + parabolic dish + whip antennas
    add_cyl(bm, (0.0, 23.0, 0.0), 0.72, 0.36, 5.0, 6, STEEL)
    for ay in (21.5, 23.2, 24.8):
        add_cyl(bm, (0.0, ay, 0.0), 1.05 - (ay - 21.5) * 0.14, 1.05 - (ay - 21.5) * 0.14, 0.16, 6, ST_LT)
    # Parabolic satellite dish facing south-west
    add_cyl(bm, (1.4, 22.8, 1.4), 1.65, 0.35, 0.62, 14, WHITE, (56.0, 35.0, 0.0))
    add_cyl_pts(bm, (1.4, 22.8, 1.4), (2.4, 23.5, 2.4), 0.08, 0.05, 6, STEEL)
    add_sphere(bm, (2.45, 23.55, 2.45), (0.18, 0.18, 0.18), 8, 6, CYAN)
    # Top spire & red aviation warning beacon
    add_cyl(bm, (0.0, 26.8, 0.0), 0.12, 0.04, 3.2, 6, ST_LT)
    add_sphere(bm, (0.0, 28.5, 0.0), (0.26, 0.26, 0.26), 10, 6, RED)

    return finalize_obj("babel_radar_tower", bm, mats, smooth=False)


def build_ahsarah_fortress_gatehouse(mats, M):
    """Hero Administrative Fortress Gatehouse (20m wide x 10.6m tall x 13.5m deep):
    Warm Moroccan sandstone kasbah twin towers + central arched gateway + concrete bastion collars."""
    bm = bmesh.new()
    SAND = M["Mat_SandstoneMain"]
    S_DK = M["Mat_SandstoneDark"]
    S_LT = M["Mat_SandstoneLight"]
    TERRA = M["Mat_Terracotta"]
    CONC = M["Mat_ConcreteMain"]
    C_DK = M["Mat_ConcreteDark"]
    WOOD = M["Mat_CedarWood"]
    CANVAS = M["Mat_CanvasTan"]
    RED = M["Mat_AhsarahRed"]
    STEEL = M["Mat_SteelDark"]
    AMBER = M["Mat_AmberGlow"]
    SANDBAG = M["Mat_Sandbag"]

    # Stepped fortress stone base plinth deeply grounded to y=-1.60m + solid grand south entry stairs
    add_box(bm, (0.0, -0.45, 0.0), (21.2, 2.30, 14.6), S_DK)
    # Extended front porch foundation pad under left shade awning & entry stairs (y=-1.4..+0.04)
    add_box(bm, (-7.0, -0.68, 7.6), (6.0, 1.44, 2.6), S_DK)
    for st in range(4):
        top_y = 0.18 + st * 0.165
        h_solid = top_y + 1.20
        add_box(bm, (0.0, top_y - h_solid * 0.5, 7.3 + (3 - st) * 0.45), (6.5, h_solid, 0.54), S_LT)

    # Twin flanking battered kasbah towers (left x=-7.0, right x=+7.0)
    for sgn in (-1.0, 1.0):
        tx = sgn * 7.0
        # Lower battered sandstone base + concrete armored military corner collar
        add_box(bm, (tx, 2.2, 0.0), (6.2, 4.4, 11.4), SAND)
        add_box(bm, (tx + sgn * 2.55, 2.0, 5.25), (1.35, 4.0, 1.4), CONC)
        add_box(bm, (tx + sgn * 2.55, 2.0, -5.25), (1.35, 4.0, 1.4), CONC)
        # Upper sandstone turret story
        add_box(bm, (tx, 6.2, 0.0), (5.5, 4.0, 10.4), S_LT)
        # Cornice band & recessed decorative blind arches on front/side faces
        add_box(bm, (tx, 4.35, 0.0), (6.45, 0.32, 11.7), S_DK)
        add_box(bm, (tx, 8.25, 0.0), (5.85, 0.34, 10.8), S_DK)
        # Recessed dark arched windows on upper story
        for wx in (-1.2, 1.2):
            add_box(bm, (tx + wx, 6.2, 5.22), (0.85, 1.65, 0.18), STEEL)
            add_box(bm, (tx + wx, 7.12, 5.26), (0.98, 0.26, 0.24), S_DK)
            add_box(bm, (tx + wx, 6.2, -5.22), (0.85, 1.65, 0.18), STEEL)
        # Projecting cedar timber tie-beam ends (signature North African kasbah detail!)
        for by in (3.6, 7.6):
            for bx in (-2.0, -0.7, 0.7, 2.0):
                add_cyl(bm, (tx + bx, by, 5.55), 0.10, 0.10, 0.85, 6, WOOD, (90.0, 0.0, 0.0))
        # Sawtooth crenellated battlements around tower roof
        for mi in range(-2, 3):
            add_box(bm, (tx + mi * 1.15, 8.85, 5.05), (0.62, 0.92, 0.42), SAND)
            add_box(bm, (tx + mi * 1.15, 8.85, -5.05), (0.62, 0.92, 0.42), SAND)
        for mz in (-3.6, -1.8, 0.0, 1.8, 3.6):
            add_box(bm, (tx + sgn * 2.55, 8.85, mz), (0.42, 0.92, 0.62), SAND)
        # Roof sandbag firing lip & timber shade canopy on left tower, sandstone dome on right tower!
        if sgn < 0:
            for sb in range(-2, 3):
                add_sphere(bm, (tx + sb * 0.95, 8.55, 4.25), (0.55, 0.24, 0.30), 8, 6, SANDBAG)
            for cx in (-1.8, 1.8):
                for cz in (-2.4, 2.4):
                    add_cyl(bm, (tx + cx, 9.65, cz), 0.08, 0.08, 2.6, 6, WOOD)
            add_box(bm, (tx, 10.95, 0.0), (4.4, 0.12, 5.6), CANVAS, (4.0, 0.0, 0.0))
        else:
            add_cyl(bm, (tx, 8.65, 0.0), 2.35, 2.25, 0.75, 12, S_DK)
            add_dome(bm, (tx, 9.0, 0.0), 2.15, 2.05, 2.15, 14, 7, TERRA)
            add_cyl(bm, (tx, 11.35, 0.0), 0.08, 0.03, 0.72, 8, M["Mat_Brass"])

    # Central connecting fortress bridge & wide monumental arched gatehouse portal (x=-4..+4)
    # Front arched gateway wall (z=+4.4) and rear arched wall (z=-4.4) leaving a clear walkable vaulted tunnel!
    add_arch_opening_wall(bm, 0.0, 0.7, 4.4, 8.2, 6.2, 1.6, 4.8, 4.4, SAND, along_z=False)
    add_arch_opening_wall(bm, 0.0, 0.7, -4.4, 8.2, 6.2, 1.6, 4.8, 4.4, SAND, along_z=False)
    # Concrete reinforced command bridge spanning above the tunnel (y=5.4..7.2)
    add_box(bm, (0.0, 6.3, 0.0), (8.4, 1.6, 10.4), CONC)
    add_box(bm, (0.0, 7.35, 4.95), (8.4, 0.95, 0.45), C_DK)
    add_box(bm, (0.0, 7.35, -4.95), (8.4, 0.95, 0.45), C_DK)
    # Crimson Ahsarah Guard heraldic war banners flanking the main arch!
    for sgn in (-1.0, 1.0):
        add_cyl(bm, (sgn * 3.15, 5.4, 5.4), 0.06, 0.06, 0.9, 6, WOOD, (0.0, 0.0, 90.0))
        add_box(bm, (sgn * 3.15, 3.85, 5.45), (0.95, 2.85, 0.06), RED)
        add_box(bm, (sgn * 3.15, 4.35, 5.50), (0.42, 0.42, 0.04), M["Mat_Brass"], (0.0, 0.0, 45.0))
        # Warm glowing fortress wall lanterns flanking archway
        add_box(bm, (sgn * 2.85, 3.15, 5.38), (0.28, 0.44, 0.28), STEEL)
        add_box(bm, (sgn * 2.85, 3.15, 5.42), (0.18, 0.28, 0.18), AMBER)

    # Front slanted canvas shade awning on left wing (posts deeply grounded down to y=-1.2m + stone plinth collars!)
    add_box(bm, (-7.0, 3.7, 6.65), (5.4, 0.10, 2.4), CANVAS, (16.0, 0.0, 0.0))
    for px in (-9.3, -4.7):
        add_cyl(bm, (px, 1.15, 7.7), 0.08, 0.07, 4.7, 6, WOOD)
        add_box(bm, (px, 0.16, 7.7), (0.34, 0.36, 0.34), S_DK)

    return finalize_obj("ahsarah_fortress_gatehouse", bm, mats, smooth=False)


def build_brakkesh_sandstone_pavilion(mats, M):
    """Detailed Brakkesh sandstone arched bazaar pavilion (~8.6m x 9.6m x 7.6m) with deep foundations,
    solid front stone apron terrace, grounded awning posts & seated terracotta amphorae."""
    bm = bmesh.new()
    SAND = M["Mat_SandstoneMain"]
    S_DK = M["Mat_SandstoneDark"]
    S_LT = M["Mat_SandstoneLight"]
    TERRA = M["Mat_Terracotta"]
    WOOD = M["Mat_CedarWood"]
    CANVAS = M["Mat_CanvasTan"]
    RED = M["Mat_AhsarahRed"]
    BRASS = M["Mat_Brass"]

    # Raised sandstone terrace floor deeply grounded down to y=-1.50m so zero gaps ever appear on slopes!
    add_box(bm, (0.0, -0.45, 0.0), (8.8, 2.10, 7.2), S_DK)
    # Continuous solid front stone apron terrace extending under stairs, awning posts & amphorae (z=3.4..5.75, y=-1.4..+0.04)
    add_box(bm, (0.0, -0.68, 4.62), (8.4, 1.44, 2.35), S_DK)
    # 3 solid stone entry steps rising cleanly from apron (y=0.04) to pavilion floor (y=0.60), extending deep into apron
    for st in range(3):
        top_y = 0.22 + st * 0.18
        h_solid = top_y + 1.10
        add_box(bm, (0.0, top_y - h_solid * 0.5, 3.74 + (2 - st) * 0.38), (4.0, h_solid, 0.44), S_LT)

    # Four arched perimeter walls (walkable open bazaar gallery!)
    add_arch_opening_wall(bm, 0.0, 0.6, 3.05, 8.0, 3.8, 0.68, 4.4, 3.1, SAND, along_z=False)
    add_arch_opening_wall(bm, 0.0, 0.6, -3.05, 8.0, 3.8, 0.68, 4.4, 3.1, SAND, along_z=False)
    add_arch_opening_wall(bm, -3.66, 0.6, 0.0, 5.6, 3.8, 0.68, 3.2, 3.0, SAND, along_z=True)
    add_arch_opening_wall(bm, 3.66, 0.6, 0.0, 5.6, 3.8, 0.68, 3.2, 3.0, SAND, along_z=True)

    # Roof slab, stepped parapet merlons & central Moroccan dome
    add_box(bm, (0.0, 4.55, 0.0), (8.4, 0.38, 6.8), S_LT)
    for mx in (-3.6, -2.4, -1.2, 0.0, 1.2, 2.4, 3.6):
        add_box(bm, (mx, 5.05, 3.25), (0.55, 0.65, 0.32), SAND)
        add_box(bm, (mx, 5.05, -3.25), (0.55, 0.65, 0.32), SAND)
    add_cyl(bm, (0.0, 4.95, 0.0), 2.35, 2.25, 0.55, 14, S_DK)
    add_dome(bm, (0.0, 5.20, 0.0), 2.15, 1.85, 2.15, 16, 7, S_LT)
    add_cyl(bm, (0.0, 7.25, 0.0), 0.07, 0.02, 0.65, 8, BRASS)

    # Front market fabric awning + deeply grounded wooden posts with stone plinth bases + seated terracotta amphorae!
    add_box(bm, (0.0, 3.55, 4.45), (5.4, 0.09, 2.2), CANVAS, (15.0, 0.0, 0.0))
    for px in (-2.4, 2.4):
        add_cyl(bm, (px, 1.05, 5.42), 0.075, 0.065, 4.5, 6, WOOD)
        add_box(bm, (px, 0.16, 5.42), (0.32, 0.36, 0.32), S_LT)
    # Terracotta amphorae jars resting firmly ON the solid stone apron terrace (bottom embedded cleanly at y=-0.02!)
    for jx, jz, sc in ((-3.0, 3.95, 1.0), (-2.35, 4.25, 0.78), (3.0, 4.0, 0.92)):
        # Flat stoneware foot seated directly into apron y=0.04
        add_cyl(bm, (jx, 0.04 * sc, jz), 0.22 * sc, 0.20 * sc, 0.12 * sc, 10, S_DK)
        add_cyl(bm, (jx, 0.28 * sc, jz), 0.18 * sc, 0.31 * sc, 0.46 * sc, 10, TERRA)
        add_cyl(bm, (jx, 0.64 * sc, jz), 0.31 * sc, 0.14 * sc, 0.32 * sc, 10, TERRA)
        add_cyl(bm, (jx, 0.84 * sc, jz), 0.14 * sc, 0.18 * sc, 0.14 * sc, 10, S_DK)
    # Woven crimson desert rug draped over upper parapet
    add_box(bm, (-2.0, 4.15, 3.46), (1.35, 1.55, 0.06), RED)
    add_box(bm, (-2.0, 4.15, 3.49), (1.05, 1.10, 0.03), M["Mat_WarningYellow"])

    return finalize_obj("brakkesh_sandstone_pavilion", bm, mats, smooth=False)


def build_cement_silo_complex(mats, M):
    """Zero Dam West Cement Plant hero structure: twin 15m concrete silos + steel bridge + hoppers."""
    bm = bmesh.new()
    C_MAIN = M["Mat_ConcreteMain"]
    C_DARK = M["Mat_ConcreteDark"]
    STEEL = M["Mat_SteelDark"]
    ST_LT = M["Mat_SteelLight"]
    WARN = M["Mat_WarningYellow"]
    TERRA = M["Mat_Terracotta"]

    # Raised concrete industrial loading apron deeply grounded to y=-1.80m
    add_box(bm, (0.0, -0.60, 0.0), (14.0, 2.40, 8.6), C_DARK)
    # Twin tall cylindrical concrete silos (x = -3.4 and x = +3.4)
    for sx in (-3.4, 3.4):
        # 4 heavy steel support legs under discharge hopper
        for lx in (-1.8, 1.8):
            for lz in (-1.8, 1.8):
                add_box(bm, (sx + lx, 1.85, lz), (0.42, 3.1, 0.42), STEEL)
        # Conical steel hopper
        add_cyl(bm, (sx, 2.75, 0.0), 0.55, 2.72, 2.2, 16, STEEL)
        # Main tall reinforced concrete cylinder
        add_cyl(bm, (sx, 8.9, 0.0), 2.75, 2.75, 10.4, 18, C_MAIN)
        # Exterior steel reinforcement bands
        for hy in (4.8, 7.6, 10.4, 13.2):
            add_cyl(bm, (sx, hy, 0.0), 2.86, 2.86, 0.24, 18, C_DARK)
        # Top conical roof cap + vent stack
        add_cyl(bm, (sx, 14.55, 0.0), 2.88, 1.15, 1.0, 16, ST_LT)
        add_cyl(bm, (sx, 15.45, 0.0), 0.42, 0.42, 1.1, 10, STEEL)
        # Industrial hazard stripe band near lower rim
        add_cyl(bm, (sx, 4.15, 0.0), 2.82, 2.82, 0.36, 18, WARN)

    # Overhead steel gantry catwalk connecting both silos at y=14.3
    add_box(bm, (0.0, 14.35, 0.0), (7.6, 0.24, 1.55), STEEL)
    for rz in (-0.72, 0.72):
        add_box(bm, (0.0, 15.25, rz), (7.6, 0.08, 0.08), ST_LT)
        for rx in (-2.4, -0.8, 0.8, 2.4):
            add_box(bm, (rx, 14.82, rz), (0.08, 0.92, 0.08), ST_LT)

    # Diagonal industrial conveyor pipe descending to ground shed
    add_cyl_pts(bm, (-3.4, 13.6, 2.4), (5.8, 3.6, 2.8), 0.32, 0.32, 10, ST_LT)
    # Corrugated rusty-terracotta control booth on east edge
    add_box(bm, (5.5, 1.9, 1.8), (2.4, 2.6, 3.2), TERRA)
    add_box(bm, (5.5, 3.3, 1.8), (2.7, 0.22, 3.5), STEEL)
    # Vertical steel caged ladder on front of left silo
    for lx in (-3.65, -3.15):
        add_cyl(bm, (lx, 7.6, 2.95), 0.04, 0.04, 13.4, 6, STEEL)
    for ry in range(2, 15):
        add_cyl(bm, (-3.4, float(ry) * 0.96, 2.95), 0.03, 0.03, 0.52, 6, ST_LT, (0.0, 0.0, 90.0))

    return finalize_obj("cement_silo_complex", bm, mats, smooth=False)


def build_substation_transformer_bay(mats, M):
    """East Haavk Electrical Substation transformer bay (~7.6m x 5.6m x 4.8m)."""
    bm = bmesh.new()
    C_DARK = M["Mat_ConcreteDark"]
    STEEL = M["Mat_SteelDark"]
    ST_LT = M["Mat_SteelLight"]
    WHITE = M["Mat_HaavkWhite"]
    CYAN = M["Mat_HaavkCyan"]
    WARN = M["Mat_WarningYellow"]
    COPPER = M["Mat_Copper"]
    TERRA = M["Mat_Terracotta"]

    # Concrete equipment pad deeply grounded down to y=-1.40m with yellow hazard border
    add_box(bm, (0.0, -0.48, 0.0), (7.8, 1.84, 5.6), C_DARK)
    add_box(bm, (0.0, 0.46, 2.62), (7.6, 0.08, 0.18), WARN)
    add_box(bm, (0.0, 0.46, -2.62), (7.6, 0.08, 0.18), WARN)

    # Main heavy transformer body + vertical cooling radiator fin arrays
    add_box(bm, (-1.0, 1.65, 0.0), (3.4, 2.4, 2.2), STEEL)
    for fx in (-2.3, -1.8, -1.3, -0.8, -0.3, 0.2):
        add_box(bm, (fx, 1.65, 1.32), (0.12, 1.95, 0.48), ST_LT)
        add_box(bm, (fx, 1.65, -1.32), (0.12, 1.95, 0.48), ST_LT)
    # Cylindrical oil conservator drum on top
    add_cyl(bm, (-1.0, 3.25, -0.55), 0.44, 0.44, 2.8, 12, ST_LT, (0.0, 0.0, 90.0))
    # 3 ceramic high-voltage insulator stacks + copper busbar
    for ix in (-2.0, -1.0, 0.0):
        add_cyl(bm, (ix, 3.35, 0.55), 0.16, 0.11, 1.15, 10, TERRA)
        for dy in (3.0, 3.25, 3.50, 3.72):
            add_cyl(bm, (ix, dy, 0.55), 0.24, 0.24, 0.07, 10, TERRA)
        add_cyl_pts(bm, (ix, 3.92, 0.55), (ix, 4.45, 0.55), 0.04, 0.04, 6, COPPER)
    add_cyl(bm, (-1.0, 4.45, 0.55), 0.05, 0.05, 2.8, 8, COPPER, (0.0, 0.0, 90.0))

    # Overhead steel gantry frame
    for gx in (-3.3, 1.3):
        add_box(bm, (gx, 2.45, 0.55), (0.24, 4.1, 0.24), STEEL)
    add_box(bm, (-1.0, 4.58, 0.55), (4.9, 0.24, 0.24), STEEL)

    # Haavk white & glowing cyan telemetry relay console on east side
    add_box(bm, (2.45, 1.45, 0.0), (1.35, 2.1, 1.45), WHITE)
    add_box(bm, (2.45, 1.72, 0.74), (0.95, 0.65, 0.08), CYAN)
    add_box(bm, (2.45, 2.58, 0.0), (1.45, 0.18, 1.55), STEEL)

    return finalize_obj("substation_transformer_bay", bm, mats, smooth=False)


def build_tactical_desert_jeep(mats, M):
    """Detailed open-top 4x4 military desert recon jeep (~4.2m long x 2.0m wide x 1.95m tall)."""
    bm = bmesh.new()
    OLIVE = M["Mat_OliveMil"]
    TAN = M["Mat_SandstoneMain"]
    STEEL = M["Mat_SteelDark"]
    RUBBER = M["Mat_Rubber"]
    ST_LT = M["Mat_SteelLight"]
    GLASS = M["Mat_GlassTint"]
    AMBER = M["Mat_AmberGlow"]
    RED = M["Mat_AhsarahRed"]

    # Chassis frame & armored lower tub
    add_box(bm, (0.0, 0.62, 0.0), (1.76, 0.32, 3.95), STEEL)
    add_box(bm, (0.0, 0.96, 1.15), (1.74, 0.56, 1.55), OLIVE)     # Engine hood (front +Z)
    add_box(bm, (0.0, 0.92, -0.95), (1.82, 0.54, 1.95), OLIVE)    # Rear cargo tub
    # Side sills & flared fenders
    for sgn in (-1.0, 1.0):
        add_box(bm, (sgn * 0.88, 0.92, 0.05), (0.14, 0.42, 3.85), TAN)
        add_box(bm, (sgn * 0.92, 1.10, 1.32), (0.34, 0.10, 0.92), STEEL)
        add_box(bm, (sgn * 0.92, 1.10, -1.25), (0.34, 0.10, 0.92), STEEL)
    # Front bumper + slotted radiator grille + glowing twin headlamps
    add_box(bm, (0.0, 0.68, 2.08), (1.92, 0.24, 0.24), STEEL)
    for gx in (-0.42, -0.21, 0.0, 0.21, 0.42):
        add_box(bm, (gx, 0.98, 1.94), (0.09, 0.38, 0.08), STEEL)
    for hx in (-0.64, 0.64):
        add_cyl(bm, (hx, 1.02, 1.95), 0.12, 0.12, 0.10, 10, AMBER, (90.0, 0.0, 0.0))
        add_box(bm, (hx, 0.94, -1.96), (0.18, 0.12, 0.08), RED)

    # Windshield frame & tilted tinted glass
    add_box(bm, (0.0, 1.48, 0.44), (1.68, 0.64, 0.08), OLIVE, (-14.0, 0.0, 0.0))
    add_box(bm, (0.0, 1.48, 0.46), (1.46, 0.48, 0.04), GLASS, (-14.0, 0.0, 0.0))
    # Interior twin bucket seats, dashboard & steering wheel
    add_box(bm, (0.0, 1.12, 0.36), (1.56, 0.28, 0.24), STEEL)
    for sx in (-0.44, 0.44):
        add_box(bm, (sx, 0.96, -0.28), (0.48, 0.16, 0.48), RUBBER)
        add_box(bm, (sx, 1.30, -0.50), (0.48, 0.62, 0.14), RUBBER, (-10.0, 0.0, 0.0))
    add_cyl(bm, (-0.44, 1.24, 0.12), 0.18, 0.18, 0.04, 12, RUBBER, (60.0, 0.0, 0.0))

    # Full tubular steel roll cage
    for sgn in (-1.0, 1.0):
        add_cyl_pts(bm, (sgn * 0.80, 1.18, -0.55), (sgn * 0.78, 1.92, -0.55), 0.045, 0.045, 8, STEEL)
        add_cyl_pts(bm, (sgn * 0.80, 1.18, -1.78), (sgn * 0.78, 1.92, -1.78), 0.045, 0.045, 8, STEEL)
        add_cyl_pts(bm, (sgn * 0.78, 1.92, 0.34), (sgn * 0.78, 1.92, -1.78), 0.045, 0.045, 8, STEEL)
    add_cyl_pts(bm, (-0.78, 1.92, -0.55), (0.78, 1.92, -0.55), 0.045, 0.045, 8, STEEL)
    add_cyl_pts(bm, (-0.78, 1.92, -1.78), (0.78, 1.92, -1.78), 0.045, 0.045, 8, STEEL)

    # 4 chunky off-road wheels with rims + rear spare tire + whip antenna + fuel jerrycan
    for wx in (-0.96, 0.96):
        for wz in (1.32, -1.25):
            add_cyl(bm, (wx, 0.46, wz), 0.46, 0.46, 0.34, 14, RUBBER, (0.0, 0.0, 90.0))
            add_cyl(bm, (wx, 0.46, wz), 0.24, 0.24, 0.36, 10, ST_LT, (0.0, 0.0, 90.0))
    add_cyl(bm, (0.0, 1.08, -2.08), 0.42, 0.42, 0.28, 14, RUBBER, (90.0, 0.0, 0.0))
    add_cyl(bm, (0.0, 1.08, -2.08), 0.22, 0.22, 0.30, 10, ST_LT, (90.0, 0.0, 0.0))
    add_box(bm, (0.64, 1.08, -2.02), (0.28, 0.46, 0.16), RED)
    add_cyl(bm, (-0.82, 2.25, -1.85), 0.018, 0.008, 2.1, 6, STEEL)

    return finalize_obj("tactical_desert_jeep", bm, mats, smooth=False)


def build_oasis_palm_cluster(mats, M):
    """Graceful 3-trunk North African oasis date-palm cluster with ringed trunks & arched pinnate fronds."""
    bm = bmesh.new()
    TRUNK = M["Mat_PalmTrunk"]
    FROND = M["Mat_PalmFrond"]
    FROND_S = M["Mat_PalmFrondSun"]
    DATE = M["Mat_AmberGlow"]

    trunks = [
        (0.0, 0.0, 9.2, 1.35, 0.35, 0.38, 13),
        (-1.45, 0.85, 7.2, -1.10, 0.80, 0.32, 11),
        (1.30, -0.75, 5.8, 0.95, -0.95, 0.28, 10),
    ]
    for bx, bz, height, lean_x, lean_z, r_base, n_fronds in trunks:
        # Deep flared root flare extending down to y=-1.15m so trunks NEVER float even on steep oasis banks!
        add_cyl_pts(bm, (bx, -1.15, bz), (bx, 0.08, bz), r_base * 1.48, r_base * 1.04, 8, TRUNK)
        segs = 11
        prev = (bx, 0.0, bz)
        for i in range(1, segs + 1):
            t = float(i) / float(segs)
            curve = t * t
            nx = bx + lean_x * curve
            nz = bz + lean_z * curve
            ny = height * t
            r0 = r_base * (1.0 - 0.54 * ((i - 1) / float(segs)))
            r1 = r_base * (1.0 - 0.54 * t) * 1.12  # Ringed palm trunk ridge step!
            add_cyl_pts(bm, prev, (nx, ny, nz), r0, r1, 8, TRUNK)
            prev = (nx, ny, nz)

        cx, cy, cz = prev
        # Date cluster bunches tucked beneath crown
        for di in range(3):
            da = di * (math.tau / 3.0)
            add_sphere(bm, (cx + math.cos(da) * 0.42, cy - 0.42, cz + math.sin(da) * 0.42), (0.24, 0.34, 0.24), 7, 5, DATE)

        # Radiating arched pinnate fronds (multi-segment arched stem + angled leaflet fans!)
        for fi in range(n_fronds):
            yaw = (float(fi) / float(n_fronds)) * math.tau + (0.25 if fi % 2 else 0.0)
            tier_lift = 0.52 if fi % 2 == 0 else 0.14
            flen = 3.15 if fi % 2 == 0 else 2.75
            mat_f = FROND_S if fi % 2 == 0 else FROND
            fprev = (cx, cy + 0.08, cz)
            dx, dz = math.cos(yaw), math.sin(yaw)
            px, pz = -dz, dx
            for s in range(1, 6):
                ft = float(s) / 5.0
                dist = flen * ft
                arc_y = cy + 0.12 + math.sin(ft * math.pi * 0.72) * (1.05 + tier_lift) - (ft * ft) * 1.35
                fnext = (cx + dx * dist, arc_y, cz + dz * dist)
                # Central rachis rib
                add_cyl_pts(bm, fprev, fnext, 0.055 * (1.0 - ft * 0.6), 0.03 * (1.0 - ft * 0.5), 5, mat_f)
                # Angled pinnate leaflet blades left & right
                leaf_w = math.sin(ft * math.pi * 0.92) * 0.62
                if leaf_w > 0.12:
                    mid = ((fprev[0] + fnext[0]) * 0.5, (fprev[1] + fnext[1]) * 0.5, (fprev[2] + fnext[2]) * 0.5)
                    for side in (-1.0, 1.0):
                        v0 = bm.verts.new(gd_to_bl(fprev))
                        v1 = bm.verts.new(gd_to_bl(fnext))
                        v2 = bm.verts.new(gd_to_bl((mid[0] + px * side * leaf_w + dx * 0.18, mid[1] - 0.18, mid[2] + pz * side * leaf_w + dz * 0.18)))
                        f = bm.faces.new((v0, v1, v2) if side > 0 else (v1, v0, v2))
                        f.material_index = mat_f
                fprev = fnext

    return finalize_obj("oasis_palm_cluster", bm, mats, smooth=False)


def build_desert_acacia_tree(mats, M):
    """Stylized North African flat-topped umbrella desert acacia (~6.2m tall)."""
    bm = bmesh.new()
    TRUNK = M["Mat_CedarWood"]
    LEAF_A = M["Mat_PalmFrond"]
    LEAF_B = M["Mat_PalmFrondSun"]

    # Deeply grounded root flare down to y=-1.15m so acacia trunks never hover on slopes
    add_cyl_pts(bm, (0.0, -1.15, 0.0), (0.0, 0.05, 0.0), 0.50, 0.35, 8, TRUNK)
    add_cyl_pts(bm, (0.0, 0.0, 0.0), (0.18, 2.3, 0.08), 0.34, 0.24, 8, TRUNK)
    branches = [
        ((0.18, 2.2, 0.08), (-2.1, 4.6, 0.8), 2.3, 0.68),
        ((0.18, 2.2, 0.08), (2.2, 4.8, -0.6), 2.4, 0.72),
        ((0.18, 2.2, 0.08), (0.2, 5.2, 1.7), 2.1, 0.65),
        ((0.18, 2.2, 0.08), (-0.6, 4.9, -1.9), 2.2, 0.68),
    ]
    for i, (p0, p1, rad, thick) in enumerate(branches):
        add_cyl_pts(bm, p0, p1, 0.18, 0.09, 7, TRUNK)
        add_sphere(bm, p1, (rad, thick, rad * 0.92), 11, 6, LEAF_B if i % 2 == 0 else LEAF_A)
    add_sphere(bm, (0.1, 5.45, 0.0), (2.6, 0.72, 2.4), 12, 6, LEAF_B)

    return finalize_obj("desert_acacia_tree", bm, mats, smooth=True)


def build_sandbag_bunker_wall(mats, M):
    """Curved 4-row staggered pillowed sandbag firing wall (~4.4m wide x 1.25m tall)."""
    bm = bmesh.new()
    BAG = M["Mat_Sandbag"]
    WOOD = M["Mat_CedarWood"]
    OLIVE = M["Mat_OliveMil"]

    # Compacted earthen/sandbag footing berm extending down to y=-0.75m so bunkers sit flush on slopes
    add_box(bm, (0.0, -0.34, -0.18), (4.45, 0.84, 1.05), BAG)
    for row in range(4):
        n_bags = 7 - (row % 2)
        y = 0.15 + row * 0.27
        for i in range(n_bags):
            t = (float(i) + 0.5) / float(n_bags) - 0.5
            x = t * 4.1
            z = (x * x) * 0.085 - 0.25
            add_sphere(bm, (x, y, z), (0.34, 0.16, 0.22), 9, 6, BAG)
    for px in (-2.05, 0.0, 2.05):
        pz = (px * px) * 0.085 - 0.52
        add_cyl(bm, (px, 0.28, pz), 0.06, 0.06, 1.95, 6, WOOD)
    add_box(bm, (-1.1, 0.10, -0.82), (0.94, 0.88, 0.56), OLIVE)
    add_box(bm, (-1.1, 0.55, -0.82), (0.96, 0.08, 0.58), M["Mat_SteelDark"])

    return finalize_obj("sandbag_bunker_wall", bm, mats, smooth=True)


def build_military_ammo_stack(mats, M):
    """Palletized military ammo cases, fuel cans & folded tarp (~2.4m x 1.6m x 1.3m)."""
    bm = bmesh.new()
    WOOD = M["Mat_CedarWood"]
    OLIVE = M["Mat_OliveMil"]
    STEEL = M["Mat_SteelDark"]
    BRASS = M["Mat_Brass"]
    RED = M["Mat_AhsarahRed"]
    TAN = M["Mat_CanvasTan"]

    # Deeply grounded wooden slatted pallet footing (y=-0.50..+0.16)
    add_box(bm, (0.0, -0.17, 0.0), (2.25, 0.66, 1.50), WOOD)
    # Stacked stamped military ammo crates with brass corner latches
    crates = [
        (-0.52, 0.44, 0.12, 1.02, 0.54, 0.62, 4.0),
        (0.55, 0.44, 0.05, 0.96, 0.54, 0.58, -6.0),
        (-0.42, 0.92, 0.08, 0.88, 0.42, 0.52, 12.0),
        (0.45, 0.86, -0.25, 0.72, 0.34, 0.44, -14.0),
    ]
    for cx, cy, cz, sx, sy, sz, ry in crates:
        add_box(bm, (cx, cy, cz), (sx, sy, sz), OLIVE, (0.0, ry, 0.0))
        add_box(bm, (cx, cy + sy * 0.48, cz), (sx + 0.04, 0.06, sz + 0.04), STEEL, (0.0, ry, 0.0))
        add_box(bm, (cx, cy + sy * 0.2, cz + sz * 0.51), (0.14, 0.10, 0.04), BRASS, (0.0, ry, 0.0))
    # Two red tactical fuel jerrycans beside stack
    for jx, jz in ((0.68, 0.46), (0.98, 0.36)):
        add_box(bm, (jx, 0.42, jz), (0.24, 0.52, 0.36), RED, (0.0, 18.0, 0.0))
        add_cyl(bm, (jx, 0.72, jz + 0.06), 0.04, 0.04, 0.10, 6, STEEL)
    # Rolled canvas tarp
    add_cyl(bm, (-0.1, 0.30, -0.50), 0.16, 0.16, 1.35, 10, TAN, (0.0, 8.0, 90.0))

    return finalize_obj("military_ammo_stack", bm, mats, smooth=False)


def build_dimensional_rift_wall(mats, M):
    """Yanxia Ancient Cave '次元石壁' monolith behind skylight (~2.9m wide x 3.2m tall x 0.7m deep)."""
    bm = bmesh.new()
    KARST = M["Mat_KarstDark"]
    SAND = M["Mat_SandstoneMain"]
    BRASS = M["Mat_Brass"]
    RIFT = M["Mat_RiftGlow"]
    AMBER = M["Mat_AmberGlow"]

    # Massive stepped ancient karst stone stele frame
    add_box(bm, (0.0, 1.58, -0.16), (2.95, 3.16, 0.52), KARST)
    add_box(bm, (0.0, 0.22, 0.06), (3.18, 0.44, 0.78), KARST)
    # Flanking carved stone pilasters with ancient desert-sandstone inlay reliefs
    for sgn in (-1.0, 1.0):
        add_box(bm, (sgn * 1.18, 1.62, 0.10), (0.54, 2.75, 0.38), KARST)
        add_box(bm, (sgn * 1.18, 1.62, 0.28), (0.22, 2.15, 0.08), BRASS)
    add_box(bm, (0.0, 2.98, 0.12), (3.12, 0.38, 0.56), KARST)

    # Recessed dimensional stone slab etched with concentric glowing bronze/turquoise rift rings
    add_box(bm, (0.0, 1.60, 0.08), (1.84, 2.42, 0.14), SAND)
    # Concentric bronze astrolabe / rift ring carved into center
    segs = 20
    for r_ring, mat_r, thick, zoff in ((0.78, BRASS, 0.075, 0.19), (0.58, RIFT, 0.055, 0.21), (0.34, AMBER, 0.045, 0.22)):
        for i in range(segs):
            a0 = (float(i) / float(segs)) * math.tau
            a1 = (float(i + 1) / float(segs)) * math.tau
            p0 = (math.cos(a0) * r_ring, 1.62 + math.sin(a0) * r_ring, zoff)
            p1 = (math.cos(a1) * r_ring, 1.62 + math.sin(a1) * r_ring, zoff)
            add_cyl_pts(bm, p0, p1, thick, thick, 6, mat_r)

    # Glowing central dimensional crystal fissure core
    add_box(bm, (0.0, 1.62, 0.20), (0.44, 1.42, 0.08), RIFT, (0.0, 0.0, 12.0))
    add_box(bm, (0.0, 1.62, 0.23), (0.18, 1.05, 0.06), AMBER, (0.0, 0.0, -8.0))
    # 4 radiating compass runes
    for ang in (0, 90, 180, 270):
        rad = math.radians(ang)
        add_box(bm, (math.cos(rad) * 0.78, 1.62 + math.sin(rad) * 0.78, 0.23), (0.16, 0.16, 0.08), BRASS, (0.0, 0.0, 45.0))

    return finalize_obj("dimensional_rift_wall", bm, mats, smooth=False)


def build_desert_mesa_ring():
    """3D sculpted sunlit sandstone mesa & canyon ridge ring at r=238m (vertex-colored ochre/terracotta)."""
    bm = bmesh.new()
    vcol_layer = bm.loops.layers.color.new("Color")
    segs = 112
    radius = 238.0
    base_y = -24.0

    # Layered canyon mesa silhouettes (flat-topped mesas + rugged desert crags)
    bot_ring = []
    mid_ring = []
    top_ring = []
    for i in range(segs):
        ang = (float(i) / float(segs)) * math.tau
        # Flat-topped stepped mesa height profile
        raw = 28.0 + 18.0 * math.sin(ang * 3.0 + 0.4) + 12.0 * math.cos(ang * 7.0 - 0.8) + 7.0 * math.sin(ang * 13.0)
        mesa_h = min(56.0, max(16.0, raw))
        # Plateau quantization for authentic North African flat-top mesa look
        if mesa_h > 36.0:
            mesa_h = 36.0 + (mesa_h - 36.0) * 0.45
        cx = math.cos(ang) * radius
        cz = math.sin(ang) * radius
        bot_ring.append(bm.verts.new(gd_to_bl((cx * 1.04, base_y, cz * 1.04))))
        mid_ring.append(bm.verts.new(gd_to_bl((cx * 1.00, mesa_h * 0.42, cz * 1.00))))
        top_ring.append(bm.verts.new(gd_to_bl((cx * 1.03, mesa_h, cz * 1.03))))

    c_bot = (0.78, 0.62, 0.44, 1.0)
    c_mid = (0.82, 0.56, 0.36, 1.0)
    c_top = (0.89, 0.68, 0.46, 1.0)

    for i in range(segs):
        j = (i + 1) % segs
        f1 = bm.faces.new((bot_ring[i], bot_ring[j], mid_ring[j], mid_ring[i]))
        f2 = bm.faces.new((mid_ring[i], mid_ring[j], top_ring[j], top_ring[i]))
        for lp, col in zip(f1.loops, (c_bot, c_bot, c_mid, c_mid)):
            lp[vcol_layer] = col
        for lp, col in zip(f2.loops, (c_mid, c_mid, c_top, c_top)):
            lp[vcol_layer] = col

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("desert_mesa_ring_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    mat = make_vcol_mat("Mat_DesertMesaVCol", rough=0.90)
    mesh.materials.append(mat)
    for p in mesh.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new("desert_mesa_ring", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_desert_boulder_a(mats, M):
    """Sculpted layered wind-eroded Saharan sandstone boulder cluster (~4.4m x 2.5m x 3.5m, rooted to y=-1.1m)."""
    bm = bmesh.new()
    add_sculpted_rock(bm, (0.0, 0.62, 0.0), (2.05, 1.48, 1.65), 901, M["Mat_DesertRock"], 0.20)
    add_sculpted_rock(bm, (1.45, 0.28, 0.65), (1.15, 0.92, 0.98), 902, M["Mat_DesertRockDark"], 0.18)
    add_sculpted_rock(bm, (-1.35, 0.22, -0.55), (1.10, 0.85, 1.05), 903, M["Mat_DesertRockLight"], 0.18)
    return finalize_obj("desert_boulder_a", bm, mats, smooth=False)


def build_desert_boulder_b(mats, M):
    """Sculpted tall stratified desert crag formation (~3.6m x 3.8m x 3.0m, rooted to y=-1.2m)."""
    bm = bmesh.new()
    add_sculpted_rock(bm, (0.0, 1.15, 0.0), (1.55, 2.25, 1.38), 911, M["Mat_DesertRockDark"], 0.22)
    add_sculpted_rock(bm, (-1.15, 0.45, 0.48), (1.05, 1.25, 1.05), 912, M["Mat_DesertRock"], 0.19)
    add_sculpted_rock(bm, (1.18, 0.35, -0.40), (0.98, 1.05, 0.95), 913, M["Mat_DesertRockLight"], 0.18)
    return finalize_obj("desert_boulder_b", bm, mats, smooth=False)


def build_desert_perimeter_rockwall(mats, M):
    """10m-wide stacked weathered desert sandstone boulder half-wall & canyon barrier (2.3m-3.4m tall, rooted to y=-1.9m).
    Visually and physically encloses the playable canyon perimeter in place of bare invisible air walls!"""
    bm = bmesh.new()
    RM = M["Mat_DesertRock"]
    RD = M["Mat_DesertRockDark"]
    RL = M["Mat_DesertRockLight"]
    S_DK = M["Mat_SandstoneDark"]
    # Lower dry-stone retaining rock berm spanning full 10.6m width down to y=-1.9m (zero gaps underneath!)
    add_box(bm, (0.0, -0.45, 0.0), (10.6, 2.9, 2.55), RD)
    # Interlocking stacked natural desert boulders forming an organic, un-climbable 2.4m-3.5m rocky canyon half-wall!
    boulder_specs = [
        (-4.1, 0.85, 0.10, (1.85, 1.45, 1.55), 301, RM),
        (-1.8, 1.15, -0.18, (2.05, 1.78, 1.68), 302, RD),
        (0.65, 0.95, 0.15, (1.92, 1.52, 1.60), 303, RL),
        (2.95, 1.28, -0.12, (2.15, 1.92, 1.72), 304, RM),
        (4.65, 0.82, 0.14, (1.65, 1.38, 1.45), 305, RD),
        # Upper stacked rock capstones & weathered dry-stone ledge slabs
        (-3.0, 2.05, -0.05, (1.35, 0.85, 1.15), 306, RL),
        (-0.5, 2.15, 0.08, (1.42, 0.95, 1.22), 307, RM),
        (1.85, 2.22, -0.08, (1.48, 1.02, 1.18), 308, S_DK),
        # Ground-hugging rubble rocks along front toe so it blends naturally into the desert sand
        (-3.6, 0.15, 1.22, (0.95, 0.55, 0.78), 309, RL),
        (0.1, 0.12, 1.35, (1.10, 0.52, 0.82), 310, RM),
        (3.4, 0.16, 1.18, (0.92, 0.58, 0.75), 311, RD),
    ]
    for cx, cy, cz, rad, sd, m_idx in boulder_specs:
        add_sculpted_rock(bm, (cx, cy, cz), rad, sd, m_idx, 0.20)
    return finalize_obj("desert_perimeter_rockwall", bm, mats, smooth=False)


def build_oasis_spring_head(mats, M):
    """Natural rocky oasis spring outlet & desert reed cluster sitting along the recessed oasis bank."""
    bm = bmesh.new()
    RM = M["Mat_DesertRock"]
    RD = M["Mat_DesertRockDark"]
    RL = M["Mat_DesertRockLight"]
    REED = M["Mat_OasisReed"]
    WATER = M["Mat_RiftGlow"]
    # Layered rocky spring mound dipping cleanly down to y=-1.2m into the pool bank
    add_sculpted_rock(bm, (0.0, 0.35, -0.45), (1.85, 1.15, 1.35), 401, RD, 0.18)
    add_sculpted_rock(bm, (-1.25, 0.10, 0.15), (1.15, 0.78, 1.05), 402, RM, 0.16)
    add_sculpted_rock(bm, (1.28, 0.14, 0.10), (1.22, 0.82, 0.98), 403, RL, 0.16)
    # Carved stone trickle spout & shimmering water cascade into the sunken basin
    add_box(bm, (0.0, 0.32, 0.45), (0.62, 0.18, 0.95), M["Mat_SandstoneDark"], (14.0, 0.0, 0.0))
    add_box(bm, (0.0, 0.39, 0.48), (0.34, 0.06, 0.92), WATER, (14.0, 0.0, 0.0))
    # Oasis reed & desert sedge blade clusters along wet rocks
    rng = random.Random(409)
    for rx, rz in ((-1.75, 0.55), (-1.45, 0.92), (1.65, 0.65), (1.95, 0.35), (-0.75, 0.85), (0.85, 0.82)):
        for _ in range(5):
            lean_x = rng.uniform(-0.28, 0.28)
            lean_z = rng.uniform(-0.28, 0.28)
            h = rng.uniform(0.75, 1.45)
            add_cyl_pts(bm, (rx, -0.45, rz), (rx + lean_x, h, rz + lean_z), 0.045, 0.008, 5, REED)
    return finalize_obj("oasis_spring_head", bm, mats, smooth=False)


def main():
    clear_scene()
    mats, M = build_materials()
    built = [
        build_zero_dam_wall(mats, M),
        build_babel_radar_tower(mats, M),
        build_ahsarah_fortress_gatehouse(mats, M),
        build_brakkesh_sandstone_pavilion(mats, M),
        build_cement_silo_complex(mats, M),
        build_substation_transformer_bay(mats, M),
        build_tactical_desert_jeep(mats, M),
        build_oasis_palm_cluster(mats, M),
        build_desert_acacia_tree(mats, M),
        build_sandbag_bunker_wall(mats, M),
        build_military_ammo_stack(mats, M),
        build_dimensional_rift_wall(mats, M),
        build_desert_mesa_ring(),
        build_desert_boulder_a(mats, M),
        build_desert_boulder_b(mats, M),
        build_desert_perimeter_rockwall(mats, M),
        build_oasis_spring_head(mats, M),
    ]
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        export_yup=True,
        export_materials="EXPORT",
        export_apply=True,
    )
    print(f"Exported {len(built)} Ahsarah architecture assets -> {OUT_GLB} ({OUT_GLB.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
