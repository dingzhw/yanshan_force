"""Build lightweight multi-material PBR Jiangnan & Cloud-Top Arena landmarks for Yanshan Force v0.8.5.

Run with Blender 4.5:
  blender --background --python tools/build_v085_landmarks.py

Outputs:
  game/assets/slice/v085_landmarks.glb
    - bridge_multi_arch   : 14m triple-arch carved Jiangnan bluestone bridge
    - tea_hill_pavilion   : 6-column hexagonal Jiangnan tea-hill rest pavilion with stone tea table
    - cliff_stele         : Monumental weathered bluestone mountain stele with tiled roof cap
    - arena_dragon_pillar : 5.8m carved octagonal Cloud-Top Arena pillar with gilded dragon bands & brazier
    - arena_altar_rim     : Stepped carved bluestone perimeter curb for the 38m Cloud-Top Martial Arena
"""

import math
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUT_GLB = ROOT / "game" / "assets" / "slice" / "v085_landmarks.glb"


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_mat(name, color, rough=0.82, metal=0.04, emit=None, emit_strength=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None and emit_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    return mat


def add_box(bm, center, size, mat_idx=0, rot_euler=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    mat_rot = Matrix.Identity(4)
    if rot_euler != (0.0, 0.0, 0.0):
        mat_rot = (
            Matrix.Rotation(rot_euler[2], 4, "Z")
            @ Matrix.Rotation(rot_euler[1], 4, "Y")
            @ Matrix.Rotation(rot_euler[0], 4, "X")
        )
    scale_m = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    trans_m = Matrix.Translation(center)
    xf = trans_m @ mat_rot @ scale_m
    bmesh.ops.transform(bm, matrix=xf, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl(bm, center, r_bot, r_top, height, segs=12, mat_idx=0, rot_euler=(0.0, 0.0, 0.0)):
    ret = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=r_bot,
        radius2=r_top,
        depth=height,
    )
    verts = ret["verts"]
    mat_rot = Matrix.Identity(4)
    if rot_euler != (0.0, 0.0, 0.0):
        mat_rot = (
            Matrix.Rotation(rot_euler[2], 4, "Z")
            @ Matrix.Rotation(rot_euler[1], 4, "Y")
            @ Matrix.Rotation(rot_euler[0], 4, "X")
        )
    xf = Matrix.Translation(center) @ mat_rot
    bmesh.ops.transform(bm, matrix=xf, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def finalize_obj(name, bm, mats):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    for m in mats:
        mesh.materials.append(m)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_bridge_multi_arch(mats):
    """Triple-arch Jiangnan bluestone bridge spanning X in [-7.0, +7.0], deck width Y=2.8m (Blender Z=up!)."""
    bm = bmesh.new()
    # Blender coords: X = span (-7..7), Y = width (-1.45..1.45), Z = height (up)
    # Gentle arch profile along X: crown +0.44m at X=0, tapers to 0.0 at |X|=7.0
    def deck_z(x):
        ax = min(abs(x), 7.0)
        return 0.22 * (1.0 + math.cos(math.pi * ax / 7.0))

    # 1) Deck slabs (14 contiguous segments)
    segs = 14
    dx = 14.0 / segs
    for i in range(segs):
        x0 = -7.0 + i * dx
        x1 = x0 + dx
        xm = 0.5 * (x0 + x1)
        z0 = deck_z(x0)
        z1 = deck_z(x1)
        zm = 0.5 * (z0 + z1)
        tilt = math.atan2(z1 - z0, dx)
        seg_l = math.hypot(dx, z1 - z0) + 0.06
        add_box(bm, (xm, 0.0, zm - 0.14), (seg_l, 2.72, 0.28), mat_idx=0, rot_euler=(0.0, -tilt, 0.0))
        # Carved bluestone curb trim on both sides
        for sy in (-1.34, 1.34):
            add_box(bm, (xm, sy, zm + 0.05), (seg_l, 0.22, 0.16), mat_idx=1, rot_euler=(0.0, -tilt, 0.0))

    # 2) Four heavy stone piers forming 3 arches (center span -2.4..+2.4, side arches +-2.4..+-6.2)
    pier_xs = [-6.25, -2.55, 2.55, 6.25]
    for px in pier_xs:
        pz_top = deck_z(px) - 0.18
        ph = 2.90
        add_box(bm, (px, 0.0, pz_top - ph * 0.5), (0.86, 3.06, ph), mat_idx=2)
        # Cutwater prow facing upstream (-Y) and downstream (+Y)
        for sy in (-1.56, 1.56):
            add_cyl(bm, (px, sy, pz_top - ph * 0.55), 0.36, 0.30, ph * 0.92, segs=6, mat_idx=2)

    # 3) Three arched masonry rings under the deck
    arches = [(-4.40, 1.58, 0.58), (0.0, 2.25, 0.92), (4.40, 1.58, 0.58)]
    for ax_c, a_rad, a_rise in arches:
        arch_steps = 8
        for k in range(arch_steps):
            t0 = -1.0 + 2.0 * (k / arch_steps)
            t1 = -1.0 + 2.0 * ((k + 1) / arch_steps)
            x0 = ax_c + t0 * a_rad
            x1 = ax_c + t1 * a_rad
            z0 = deck_z(x0) - 0.30 - (1.0 - math.sqrt(max(0.0, 1.0 - t0 * t0))) * a_rise
            z1 = deck_z(x1) - 0.30 - (1.0 - math.sqrt(max(0.0, 1.0 - t1 * t1))) * a_rise
            xm = 0.5 * (x0 + x1)
            zm = 0.5 * (z0 + z1)
            ang = math.atan2(z1 - z0, x1 - x0)
            sl = math.hypot(x1 - x0, z1 - z0) + 0.08
            add_box(bm, (xm, 0.0, zm), (sl, 2.86, 0.24), mat_idx=1, rot_euler=(0.0, -ang, 0.0))

    # 4) Carved Balustrade posts, lotus finials & top rails on both sides
    post_xs = [-6.6, -4.6, -2.55, -0.85, 0.85, 2.55, 4.6, 6.6]
    for sy in (-1.34, 1.34):
        for i, px in enumerate(post_xs):
            pz = deck_z(px)
            add_box(bm, (px, sy, pz + 0.48), (0.20, 0.20, 0.88), mat_idx=1)
            # Lotus-bud cap finial
            add_cyl(bm, (px, sy, pz + 0.99), 0.13, 0.06, 0.16, segs=8, mat_idx=4)
            if i < len(post_xs) - 1:
                nx = post_xs[i + 1]
                nz = deck_z(nx)
                mx = 0.5 * (px + nx)
                mz = 0.5 * (pz + nz)
                ang = math.atan2(nz - pz, nx - px)
                sl = math.hypot(nx - px, nz - pz)
                # Top handrail & carved parapet panel
                add_box(bm, (mx, sy, mz + 0.78), (sl, 0.16, 0.11), mat_idx=1, rot_euler=(0.0, -ang, 0.0))
                add_box(bm, (mx, sy, mz + 0.42), (sl - 0.14, 0.10, 0.46), mat_idx=0, rot_euler=(0.0, -ang, 0.0))

    return finalize_obj("bridge_multi_arch", bm, mats)


def build_tea_hill_pavilion(mats):
    """Hexagonal Jiangnan Tea-Hill Rest Pavilion (茶岭凉亭) with flying slate eaves & stone tea table."""
    bm = bmesh.new()
    # 1) Hexagonal 2-tier bluestone plinth (outer r=3.15, top at z=0.38m)
    add_cyl(bm, (0.0, 0.0, 0.10), 3.30, 3.22, 0.24, segs=6, mat_idx=2)
    add_cyl(bm, (0.0, 0.0, 0.28), 2.95, 2.90, 0.20, segs=6, mat_idx=0)
    # 2) Six vermilion-brown lacquered timber columns around r=2.35m (z=0.38..3.18)
    for k in range(6):
        ang = k * (math.pi / 3.0) + math.pi / 6.0
        cx = math.cos(ang) * 2.35
        cy = math.sin(ang) * 2.35
        add_cyl(bm, (cx, cy, 0.48), 0.20, 0.16, 0.22, segs=8, mat_idx=1)  # stone column drum base
        add_cyl(bm, (cx, cy, 1.88), 0.125, 0.115, 2.66, segs=10, mat_idx=3)
        # Perimeter ring beam + wooden bench on 4 of 6 bays (leave South & West bays wide open for entry!)
        ang_next = (k + 1) * (math.pi / 3.0) + math.pi / 6.0
        nx = math.cos(ang_next) * 2.35
        ny = math.sin(ang_next) * 2.35
        mx, my = 0.5 * (cx + nx), 0.5 * (cy + ny)
        yaw = math.atan2(ny - cy, nx - cx)
        span = math.hypot(nx - cx, ny - cy)
        add_box(bm, (mx, my, 3.08), (span, 0.16, 0.22), mat_idx=3, rot_euler=(0.0, 0.0, yaw))
        if k in (0, 1, 2, 5):
            # Curved timber railing & rest bench ("美人靠")
            add_box(bm, (mx, my, 0.78), (span - 0.16, 0.34, 0.08), mat_idx=3, rot_euler=(0.0, 0.0, yaw))
            add_box(bm, (mx, my, 1.12), (span - 0.12, 0.10, 0.08), mat_idx=3, rot_euler=(0.0, 0.0, yaw))
            add_box(bm, (mx, my, 0.56), (0.14, 0.28, 0.40), mat_idx=1, rot_euler=(0.0, 0.0, yaw))

    # 3) Sweeping Jiangnan hexagonal dark-slate roof with upturned eaves & gourd finial
    add_cyl(bm, (0.0, 0.0, 3.55), 3.62, 2.18, 0.72, segs=6, mat_idx=5)
    add_cyl(bm, (0.0, 0.0, 4.22), 2.26, 0.92, 0.72, segs=6, mat_idx=5)
    add_cyl(bm, (0.0, 0.0, 4.76), 0.98, 0.16, 0.44, segs=6, mat_idx=5)
    # Six hip-ridge beams projecting outward into upturned flying eaves
    for k in range(6):
        ang = k * (math.pi / 3.0) + math.pi / 6.0
        rx = math.cos(ang) * 2.45
        ry = math.sin(ang) * 2.45
        add_box(bm, (rx, ry, 3.72), (2.40, 0.12, 0.14), mat_idx=1, rot_euler=(0.0, 0.36, ang))
        # Upturned corner tip
        tx = math.cos(ang) * 3.58
        ty = math.sin(ang) * 3.58
        add_box(bm, (tx, ty, 3.35), (0.48, 0.16, 0.12), mat_idx=4, rot_euler=(0.0, -0.35, ang))
    # Bronze gourd roof finial ("宝葫芦顶")
    add_cyl(bm, (0.0, 0.0, 5.10), 0.18, 0.14, 0.28, segs=10, mat_idx=4)
    add_cyl(bm, (0.0, 0.0, 5.36), 0.14, 0.04, 0.26, segs=10, mat_idx=4)

    # 4) Center carved stone tea table & 3 stone drum stools
    add_cyl(bm, (0.0, 0.0, 0.64), 0.26, 0.20, 0.56, segs=10, mat_idx=1)
    add_cyl(bm, (0.0, 0.0, 0.96), 0.66, 0.64, 0.10, segs=12, mat_idx=0)
    for s_i in range(3):
        sa = s_i * (2.0 * math.pi / 3.0) + 0.4
        add_cyl(bm, (math.cos(sa) * 1.15, math.sin(sa) * 1.15, 0.58), 0.22, 0.20, 0.44, segs=10, mat_idx=1)

    return finalize_obj("tea_hill_pavilion", bm, mats)


def build_cliff_stele(mats):
    """Monumental Yanshan Inscribed Stele (烟山摩崖石碑) on carved stone pedestal with slate cap."""
    bm = bmesh.new()
    # Stepped carved stone base
    add_box(bm, (0.0, 0.0, 0.16), (2.55, 1.35, 0.36), mat_idx=2)
    add_box(bm, (0.0, 0.0, 0.48), (2.08, 1.02, 0.30), mat_idx=1)
    # Main vertical weathered bluestone tablet
    add_box(bm, (0.0, 0.0, 1.98), (1.58, 0.44, 2.75), mat_idx=0)
    # Recessed bronze-gilded inscription border frame on front (+Y) & back (-Y)
    for sy in (-0.23, 0.23):
        add_box(bm, (0.0, sy, 2.02), (1.30, 0.04, 2.28), mat_idx=2)
        for sx in (-0.64, 0.64):
            add_box(bm, (sx, sy * 1.05, 2.02), (0.07, 0.05, 2.34), mat_idx=4)
        for sz in (0.88, 3.16):
            add_box(bm, (0.0, sy * 1.05, sz), (1.36, 0.05, 0.07), mat_idx=4)
    # Carved cloud-dragon stele crown & pitched slate protective rooflet
    add_box(bm, (0.0, 0.0, 3.46), (1.92, 0.68, 0.26), mat_idx=1)
    add_box(bm, (0.0, -0.34, 3.74), (2.36, 0.88, 0.14), mat_idx=5, rot_euler=(0.34, 0.0, 0.0))
    add_box(bm, (0.0, 0.34, 3.74), (2.36, 0.88, 0.14), mat_idx=5, rot_euler=(-0.34, 0.0, 0.0))
    add_box(bm, (0.0, 0.0, 3.92), (2.42, 0.18, 0.14), mat_idx=4)
    return finalize_obj("cliff_stele", bm, mats)


def build_arena_dragon_pillar(mats):
    """Cloud-Top Martial Arena 5.8m carved octagonal bluestone dragon pillar (云顶盘龙青石柱)."""
    bm = bmesh.new()
    # Heavy 2-step octagonal lotus pedestal (grounded below z=0 to prevent slope floating)
    add_cyl(bm, (0.0, 0.0, 0.14), 1.08, 1.00, 0.56, segs=8, mat_idx=2)
    add_cyl(bm, (0.0, 0.0, 0.56), 0.84, 0.72, 0.34, segs=8, mat_idx=1)
    # Tall octagonal bluestone shaft (z=0.73..5.05)
    add_cyl(bm, (0.0, 0.0, 2.88), 0.50, 0.44, 4.32, segs=8, mat_idx=0)
    # Three gilded bronze cloud-dragon relief collar rings coiled around the shaft
    for rz, tilt in [(1.45, 0.10), (2.75, -0.10), (4.05, 0.10)]:
        add_cyl(bm, (0.0, 0.0, rz), 0.55, 0.54, 0.24, segs=8, mat_idx=4, rot_euler=(tilt, 0.0, 0.0))
    # Stepped capital crown & bronze fire brazier bowl with warm amber-gold flame crystal
    add_cyl(bm, (0.0, 0.0, 5.18), 0.54, 0.76, 0.28, segs=8, mat_idx=1)
    add_cyl(bm, (0.0, 0.0, 5.44), 0.62, 0.74, 0.26, segs=8, mat_idx=4)
    add_cyl(bm, (0.0, 0.0, 5.72), 0.34, 0.10, 0.38, segs=8, mat_idx=6)
    return finalize_obj("arena_dragon_pillar", bm, mats)


def build_arena_altar_rim(mats):
    """Low stepped bluestone perimeter curb block (4.8m long) framing the 38m Cloud-Top Martial Arena."""
    bm = bmesh.new()
    add_box(bm, (0.0, 0.0, 0.18), (4.80, 0.76, 0.56), mat_idx=2)
    add_box(bm, (0.0, 0.0, 0.56), (4.68, 0.58, 0.24), mat_idx=1)
    # Decorative bronze-gold motif strip along inner arena face
    add_box(bm, (0.0, 0.29, 0.46), (4.20, 0.05, 0.09), mat_idx=4)
    for sx in (-2.15, 0.0, 2.15):
        add_box(bm, (sx, 0.0, 0.74), (0.34, 0.62, 0.14), mat_idx=0)
    return finalize_obj("arena_altar_rim", bm, mats)


def main():
    clear_scene()
    mats = [
        make_mat("Mat_BluestoneLight", (0.36, 0.41, 0.40), rough=0.84, metal=0.04),       # 0
        make_mat("Mat_BluestoneTrim", (0.28, 0.33, 0.33), rough=0.78, metal=0.06),        # 1
        make_mat("Mat_WeatheredStoneDark", (0.21, 0.25, 0.24), rough=0.90, metal=0.04),   # 2
        make_mat("Mat_JiangnanLacquerWood", (0.36, 0.16, 0.11), rough=0.62, metal=0.05),  # 3
        make_mat("Mat_GildedBronze", (0.76, 0.58, 0.26), rough=0.34, metal=0.82),         # 4
        make_mat("Mat_DarkSlateTile", (0.14, 0.18, 0.20), rough=0.68, metal=0.12),        # 5
        make_mat("Mat_BrazierEmber", (1.00, 0.72, 0.28), rough=0.25, metal=0.0, emit=(1.0, 0.62, 0.18), emit_strength=2.6),  # 6
    ]

    objs = [
        build_bridge_multi_arch(mats),
        build_tea_hill_pavilion(mats),
        build_cliff_stele(mats),
        build_arena_dragon_pillar(mats),
        build_arena_altar_rim(mats),
    ]

    total_polys = 0
    for o in objs:
        polys = len(o.data.polygons)
        total_polys += polys
        print(f"BUILT {o.name:22s}: {polys:4d} polys")
    print(f"TOTAL_POLYS={total_polys}")

    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print(f"EXPORTED -> {OUT_GLB} ({OUT_GLB.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
