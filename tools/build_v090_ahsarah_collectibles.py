#!/usr/bin/env python3
"""Build 6 museum-grade sculpted PBR collectibles for v0.9.0 "Ahsarah Fortress" in Blender 4.5 LTS
(expanding the game's total collectibles from 108 -> 114) AND render matching 256x256 RGBA Cycles studio icons:
  1. heart_of_africa       ("非洲之心", T7 旷世·大红)       — Multi-faceted crimson diamond in gold-velvet presentation cradle
  2. mandel_brick          ("曼德尔加密砖", T7 旷世·大红)   — Haavk chamfered obsidian-gold data monolith with glowing cyan matrices
  3. ahsarah_royal_chalice ("阿萨拉王室金杯", T6 传说·大金) — Chased 24K gold North African goblet with turquoise & ruby inlays
  4. reis_gramophone       ("军阀古董留声机", T6 传说·大金) — Walnut octagonal cabinet + vinyl platter + fluted antique brass horn
  5. fiery_owl_crest       ("赤枭青铜猎徽", T5 珍品·小金)   — Patinated bronze & crimson enamel spread-wing owl medallion
  6. brakkesh_brass_lamp   ("巴克什鎏金油灯", T5 珍品·小金) — Moroccan curved-spout palace brass oil lamp with crescent finial

Outputs:
  game/assets/slice/v090_ahsarah_collectibles.glb
  game/assets/icons/loot/<art_id>.png (6 transparent 256x256 studio renders)
"""
from __future__ import annotations

import math
import sys
from pathlib import Path
import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
GLB_OUT = ROOT / "game" / "assets" / "slice" / "v090_ahsarah_collectibles.glb"
ICON_DIR = ROOT / "game" / "assets" / "icons" / "loot"
ICON_DIR.mkdir(parents=True, exist_ok=True)
GLB_OUT.parent.mkdir(parents=True, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def hex_lin(h: str) -> tuple[float, float, float, float]:
    h = h.lstrip("#")
    return ((int(h[0:2], 16) / 255.0) ** 2.2, (int(h[2:4], 16) / 255.0) ** 2.2, (int(h[4:6], 16) / 255.0) ** 2.2, 1.0)


def make_mat(name: str, col: str, metallic=0.0, roughness=0.40, emission=None, emission_strength=0.0, coat=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    bsdf.inputs["Base Color"].default_value = hex_lin(col)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.06
    if emission and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = hex_lin(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def mats():
    return {
        "gold": make_mat("v90_gold", "f2c24e", 0.94, 0.20, coat=0.30),
        "gold_deep": make_mat("v90_gold_deep", "c9932e", 0.92, 0.28, coat=0.20),
        "bronze": make_mat("v90_bronze", "8e6032", 0.86, 0.36),
        "titanium": make_mat("v90_titanium", "262c34", 0.78, 0.30, coat=0.25),
        "velvet": make_mat("v90_velvet", "20141a", 0.02, 0.86),
        "walnut": make_mat("v90_walnut", "4e2816", 0.04, 0.30, coat=0.55),
        "vinyl": make_mat("v90_vinyl", "141618", 0.12, 0.22, coat=0.60),
        "chrome": make_mat("v90_chrome", "dde4ec", 0.96, 0.14),
        "diamond_red": make_mat("v90_diamond_red", "ff2442", 0.18, 0.05, emission="ff1e3c", emission_strength=1.55, coat=1.0),
        "diamond_core": make_mat("v90_diamond_core", "ffdbe4", 0.12, 0.04, emission="ff6880", emission_strength=2.2, coat=1.0),
        "cyan_holo": make_mat("v90_cyan_holo", "38f0ff", 0.15, 0.10, emission="26e6ff", emission_strength=3.4, coat=0.6),
        "turquoise": make_mat("v90_turquoise", "2ec8ba", 0.08, 0.18, coat=0.80),
        "crimson_enamel": make_mat("v90_crimson_enamel", "b82422", 0.12, 0.20, coat=0.85),
        "cord_red": make_mat("v90_cord_red", "8c2220", 0.0, 0.84),
    }


def add_box(bm, loc, size, mat_idx=0, rot_deg=(0, 0, 0)):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    xf = Matrix.Translation(Vector(loc)) @ rot @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    bmesh.ops.transform(bm, matrix=xf, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_cyl(bm, loc, r1, r2, h, segs=18, mat_idx=0, rot_deg=(0, 0, 0)):
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=h)
    verts = ret["verts"]
    rot = Euler(tuple(math.radians(a) for a in rot_deg), "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(loc)) @ rot, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_sphere(bm, loc, radii, segs=16, rings=10, mat_idx=0):
    ret = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    verts = ret["verts"]
    xf = Matrix.Translation(Vector(loc)) @ Matrix.Diagonal((radii[0], radii[1], radii[2], 1.0))
    bmesh.ops.transform(bm, matrix=xf, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def add_tube(bm, p0, p1, r0, r1, segs=10, mat_idx=0):
    a, b = Vector(p0), Vector(p1)
    d = b - a
    if d.length < 1e-4:
        return
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    ret = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=d.length)
    verts = ret["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) * 0.5) @ rot, verts=verts)
    for f in bm.faces:
        if all(v in verts for v in f.verts):
            f.material_index = mat_idx


def finish_item(art_id: str, bm: bmesh.types.BMesh, mat_list: list, smooth: bool = True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Ground mesh cleanly at z = 0 in Blender space (maps to y = 0 in Godot!)
    min_z = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= min_z
    mesh = bpy.data.meshes.new(f"loot_{art_id}_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    for m in mat_list:
        mesh.materials.append(m)
    for p in mesh.polygons:
        p.use_smooth = smooth
    obj = bpy.data.objects.new(f"loot_{art_id}", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_heart_of_africa(M):
    """T7 旷世·大红: 非洲之心 — Multi-faceted legendary crimson-diamond jewel in royal gold & velvet cradle."""
    bm = bmesh.new()
    ml = [M["velvet"], M["gold"], M["diamond_red"], M["diamond_core"], M["gold_deep"]]
    # Stepped octagonal royal obsidian-velvet & gold museum display base
    add_cyl(bm, (0, 0, 0.020), 0.145, 0.135, 0.040, 8, 0)
    add_cyl(bm, (0, 0, 0.046), 0.132, 0.118, 0.014, 8, 1)
    add_cyl(bm, (0, 0, 0.068), 0.112, 0.100, 0.032, 8, 0)
    # 6 sculpted curved gold prong claws cradling the giant Heart of Africa diamond
    for i in range(6):
        ang = i * (math.tau / 6.0)
        p0 = (math.cos(ang) * 0.068, math.sin(ang) * 0.068, 0.080)
        p1 = (math.cos(ang) * 0.102, math.sin(ang) * 0.102, 0.155)
        p2 = (math.cos(ang) * 0.088, math.sin(ang) * 0.088, 0.215)
        add_tube(bm, p0, p1, 0.010, 0.008, 8, 1)
        add_tube(bm, p1, p2, 0.008, 0.005, 8, 1)
        add_sphere(bm, p2, (0.008, 0.008, 0.008), 8, 6, 4)

    # Brilliant multi-faceted cushion-cut diamond gem (sharp flat facets for specular sparkle!)
    # Lower pavilion (culet -> girdle) + crown bevel + flat table!
    segs = 12
    culet = bm.verts.new(Vector((0.0, 0.0, 0.095)))
    table_c = bm.verts.new(Vector((0.0, 0.0, 0.285)))
    pav_ring = []
    girdle_ring = []
    crown_ring = []
    for i in range(segs):
        ang = (float(i) / float(segs)) * math.tau
        # Slight heart/cushion lobe modulation
        rad_mod = 1.0 + 0.08 * math.cos(2.0 * ang)
        pav_ring.append(bm.verts.new(Vector((math.cos(ang) * 0.068 * rad_mod, math.sin(ang) * 0.056 * rad_mod, 0.145))))
        girdle_ring.append(bm.verts.new(Vector((math.cos(ang) * 0.115 * rad_mod, math.sin(ang) * 0.092 * rad_mod, 0.205))))
        crown_ring.append(bm.verts.new(Vector((math.cos(ang) * 0.072 * rad_mod, math.sin(ang) * 0.058 * rad_mod, 0.268))))
    for i in range(segs):
        j = (i + 1) % segs
        f1 = bm.faces.new((culet, pav_ring[j], pav_ring[i]))
        f2 = bm.faces.new((pav_ring[i], pav_ring[j], girdle_ring[j], girdle_ring[i]))
        f3 = bm.faces.new((girdle_ring[i], girdle_ring[j], crown_ring[j], crown_ring[i]))
        f4 = bm.faces.new((crown_ring[i], crown_ring[j], table_c))
        for f in (f1, f2, f3):
            f.material_index = 2
        f4.material_index = 3  # Brilliant inner core flash on table facet!

    return finish_item("heart_of_africa", bm, ml, smooth=False)


def build_mandel_brick(M):
    """T7 旷世·大红: 曼德尔加密砖 — Haavk chamfered obsidian-gold data cube with glowing cyan matrices."""
    bm = bmesh.new()
    ml = [M["titanium"], M["gold"], M["cyan_holo"], M["chrome"]]
    # Chamfered main heavy data brick chassis
    add_box(bm, (0, 0, 0.13), (0.24, 0.18, 0.20), 0)
    # Recessed luminous electric-cyan holographic circuit matrices on all 4 vertical sides + top!
    add_box(bm, (0, 0, 0.13), (0.248, 0.11, 0.11), 2)
    add_box(bm, (0, 0, 0.13), (0.14, 0.188, 0.11), 2)
    add_box(bm, (0, 0, 0.232), (0.13, 0.09, 0.012), 2)
    # Armored brushed-gold corner clamp cages & precision locking rails
    for sx in (-0.112, 0.112):
        for sy in (-0.082, 0.082):
            add_box(bm, (sx, sy, 0.13), (0.036, 0.036, 0.224), 1)
            for sz in (0.03, 0.23):
                add_box(bm, (sx, sy, sz), (0.048, 0.048, 0.028), 1)
    # Precision titanium rib lattice crossing the glowing cyan panels
    for oz in (0.095, 0.165):
        add_box(bm, (0, 0, oz), (0.254, 0.194, 0.014), 0)
    # Top armored carry handle & chrome telemetry pins
    add_box(bm, (-0.065, 0, 0.252), (0.022, 0.026, 0.044), 3)
    add_box(bm, (0.065, 0, 0.252), (0.022, 0.026, 0.044), 3)
    add_box(bm, (0, 0, 0.270), (0.155, 0.024, 0.020), 1)
    # Base shock-absorber rubber/titanium feet
    for sx in (-0.09, 0.09):
        for sy in (-0.065, 0.065):
            add_cyl(bm, (sx, sy, 0.014), 0.022, 0.022, 0.028, 10, 3)

    return finish_item("mandel_brick", bm, ml, smooth=False)


def build_ahsarah_royal_chalice(M):
    """T6 传说·大金: 阿萨拉王室金杯 — Chased 24K gold North African goblet with turquoise & ruby cabochons."""
    bm = bmesh.new()
    ml = [M["gold"], M["gold_deep"], M["turquoise"], M["diamond_red"]]
    # Stepped circular chased gold pedestal base
    add_cyl(bm, (0, 0, 0.014), 0.095, 0.082, 0.028, 20, 1)
    add_cyl(bm, (0, 0, 0.036), 0.072, 0.044, 0.024, 20, 0)
    # Fluted stem with ornate central jewel knop
    add_cyl(bm, (0, 0, 0.088), 0.024, 0.020, 0.086, 16, 1)
    add_sphere(bm, (0, 0, 0.095), (0.040, 0.040, 0.030), 14, 8, 0)
    # Scalloped chalice cup bowl
    add_cyl(bm, (0, 0, 0.155), 0.028, 0.086, 0.058, 20, 1)
    add_cyl(bm, (0, 0, 0.228), 0.086, 0.104, 0.092, 20, 0)
    add_cyl(bm, (0, 0, 0.276), 0.108, 0.102, 0.016, 20, 1)  # Flared gold lip rim
    # Belt of inlaid turquoise & ruby cabochons around chalice waist!
    for i in range(8):
        ang = i * (math.tau / 8.0)
        gx, gy = math.cos(ang) * 0.094, math.sin(ang) * 0.094
        add_sphere(bm, (gx, gy, 0.215), (0.015, 0.015, 0.018), 10, 6, 2 if i % 2 == 0 else 3)
        add_cyl(bm, (math.cos(ang) * 0.088, math.sin(ang) * 0.088, 0.215), 0.018, 0.018, 0.008, 8, 1, (0, 90, math.degrees(ang)))

    return finish_item("ahsarah_royal_chalice", bm, ml, smooth=True)


def build_reis_gramophone(M):
    """T6 传说·大金: 军阀古董留声机 — Walnut octagonal base, vinyl record, chrome arm & flared brass horn."""
    bm = bmesh.new()
    ml = [M["walnut"], M["gold"], M["gold_deep"], M["vinyl"], M["chrome"]]
    # Stepped octagonal walnut cabinet with gold corner trims
    add_cyl(bm, (0, 0, 0.016), 0.125, 0.118, 0.032, 8, 0)
    add_cyl(bm, (0, 0, 0.068), 0.108, 0.108, 0.076, 8, 0)
    add_cyl(bm, (0, 0, 0.110), 0.116, 0.112, 0.014, 8, 1)
    # Hand-crank handle on right side
    add_tube(bm, (0.105, 0.0, 0.065), (0.148, 0.0, 0.065), 0.006, 0.006, 8, 1)
    add_tube(bm, (0.148, 0.0, 0.065), (0.148, 0.032, 0.088), 0.005, 0.005, 8, 1)
    # Black vinyl platter + gold center label + chrome tonearm
    add_cyl(bm, (0, 0, 0.124), 0.088, 0.088, 0.014, 24, 3)
    add_cyl(bm, (0, 0, 0.132), 0.028, 0.028, 0.004, 16, 1)
    add_tube(bm, (-0.078, 0.055, 0.126), (-0.015, 0.010, 0.140), 0.006, 0.005, 8, 4)
    # Ornate curved brass support bracket & seamless flared morning-glory brass horn!
    add_tube(bm, (-0.078, 0.060, 0.115), (-0.065, 0.050, 0.215), 0.012, 0.016, 12, 2)
    add_tube(bm, (-0.065, 0.050, 0.215), (-0.025, 0.018, 0.252), 0.016, 0.028, 14, 1)
    # Continuous coaxially aligned flared horn bell (3 segments along exact same unit direction!)
    h_dir = Vector((0.68, -0.48, 0.55)).normalized()
    h_p0 = Vector((-0.025, 0.018, 0.252))
    h_p1 = h_p0 + h_dir * 0.065
    h_p2 = h_p1 + h_dir * 0.072
    h_p3 = h_p2 + h_dir * 0.024
    add_tube(bm, h_p0, h_p1, 0.026, 0.056, 20, 1)
    add_tube(bm, h_p1, h_p2, 0.056, 0.116, 20, 1)
    add_tube(bm, h_p2, h_p3, 0.116, 0.128, 20, 2)
    # Recessed dark inner acoustic throat at mouth of brass horn
    add_tube(bm, h_p2 + h_dir * 0.004, h_p3 + h_dir * 0.002, 0.058, 0.096, 20, 3)

    return finish_item("reis_gramophone", bm, ml, smooth=True)


def build_fiery_owl_crest(M):
    """T5 珍品·小金: 赤枭青铜猎徽 — Sculpted spread-wing owl bronze & crimson enamel medallion."""
    bm = bmesh.new()
    ml = [M["bronze"], M["gold"], M["crimson_enamel"], M["diamond_red"], M["cord_red"]]
    # Sculpted circular patinated bronze medallion + beaded gold rim
    add_cyl(bm, (0, 0, 0.135), 0.128, 0.128, 0.026, 24, 0, (90, 0, 0))
    add_cyl(bm, (0, 0, 0.135), 0.114, 0.114, 0.030, 24, 2, (90, 0, 0))  # Crimson enamel inlay disc
    # Spread feathered owl wings sculpted in relief!
    for sgn in (-1.0, 1.0):
        for fi, (dx, dz, ang, w) in enumerate([(0.068, 0.028, 24, 0.095), (0.076, 0.002, 8, 0.088), (0.064, -0.024, -12, 0.072)]):
            add_box(bm, (sgn * dx, -0.018, 0.135 + dz), (w, 0.016, 0.022), 1, (0, -sgn * ang, 0))
            add_box(bm, (sgn * dx, 0.018, 0.135 + dz), (w, 0.016, 0.022), 1, (0, -sgn * ang, 0))
    # Central owl torso, fierce brow tuft & glowing crimson ruby eyes!
    add_sphere(bm, (0, 0, 0.126), (0.042, 0.028, 0.058), 12, 8, 1)
    add_sphere(bm, (0, 0, 0.172), (0.034, 0.026, 0.030), 12, 8, 1)
    for sgn in (-1.0, 1.0):
        add_box(bm, (sgn * 0.022, -0.018, 0.194), (0.018, 0.012, 0.022), 0, (0, sgn * 28, 0))
        add_sphere(bm, (sgn * 0.014, -0.024, 0.174), (0.009, 0.007, 0.009), 8, 6, 3)
    # Top suspension ring & braided desert-red tactical lanyard base
    add_cyl(bm, (0, 0, 0.272), 0.024, 0.024, 0.012, 14, 1, (90, 0, 0))
    add_box(bm, (0, 0, 0.012), (0.16, 0.06, 0.024), 4)  # Folded red tactical cord base stand

    return finish_item("fiery_owl_crest", bm, ml, smooth=True)


def build_brakkesh_brass_lamp(M):
    """T5 珍品·小金: 巴克什鎏金油灯 — Moroccan curved-spout palace oil lamp with crescent finial."""
    bm = bmesh.new()
    ml = [M["gold"], M["gold_deep"], M["turquoise"], M["bronze"]]
    # Footed hammered brass pedestal base
    add_cyl(bm, (0, 0, 0.012), 0.072, 0.056, 0.024, 18, 1)
    add_cyl(bm, (0, 0, 0.034), 0.028, 0.036, 0.026, 16, 0)
    # Elongated bulbous Moroccan lamp reservoir body
    add_sphere(bm, (0, 0, 0.088), (0.105, 0.072, 0.054), 18, 10, 0)
    # Turquoise filigree decorative collar ring
    add_cyl(bm, (0, 0, 0.136), 0.046, 0.036, 0.022, 16, 2)
    # Hinged domed palace lid with spire & crescent finial!
    add_sphere(bm, (0, 0, 0.156), (0.038, 0.038, 0.028), 14, 8, 1)
    add_cyl(bm, (0, 0, 0.194), 0.008, 0.004, 0.048, 8, 0)
    add_sphere(bm, (0, 0, 0.222), (0.014, 0.014, 0.014), 10, 6, 0)
    # Gracefully sweeping upward spout (+X)
    add_tube(bm, (0.072, 0, 0.092), (0.145, 0, 0.118), 0.036, 0.022, 12, 0)
    add_tube(bm, (0.145, 0, 0.118), (0.202, 0, 0.156), 0.022, 0.012, 12, 1)
    # Ornate scrolled loop handle (-X)
    add_tube(bm, (-0.084, 0, 0.106), (-0.142, 0, 0.148), 0.012, 0.010, 10, 1)
    add_tube(bm, (-0.142, 0, 0.148), (-0.156, 0, 0.102), 0.010, 0.009, 10, 0)
    add_tube(bm, (-0.156, 0, 0.102), (-0.102, 0, 0.068), 0.009, 0.011, 10, 1)

    return finish_item("brakkesh_brass_lamp", bm, ml, smooth=True)


COLLECTIBLES = [
    ("heart_of_africa", 7, "非洲之心", build_heart_of_africa, (0, 0, 18)),
    ("mandel_brick", 7, "曼德尔加密砖", build_mandel_brick, (0, 0, 26)),
    ("ahsarah_royal_chalice", 6, "阿萨拉王室金杯", build_ahsarah_royal_chalice, (0, 0, 16)),
    ("reis_gramophone", 6, "军阀古董留声机", build_reis_gramophone, (0, 0, -24)),
    ("fiery_owl_crest", 5, "赤枭青铜猎徽", build_fiery_owl_crest, (0, 0, 14)),
    ("brakkesh_brass_lamp", 5, "巴克什鎏金油灯", build_brakkesh_brass_lamp, (0, 0, -16)),
]

RARITY_RIM_COLORS = {
    5: (0.96, 0.82, 0.50),
    6: (1.00, 0.80, 0.24),
    7: (1.00, 0.34, 0.40),
}


def setup_studio_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 2
    scene.cycles.glossy_bounces = 2
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "AgX" if "AgX" in [e.identifier for e in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = -0.10

    world = bpy.data.worlds.new("MuseumStudioWorld90")
    scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs["Color"].default_value = (0.32, 0.34, 0.36, 1.0)
        bg.inputs["Strength"].default_value = 0.78

    cam_data = bpy.data.cameras.new("StudioCam")
    cam_data.lens = 58.0
    cam_obj = bpy.data.objects.new("StudioCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    def add_area(name, pos, look_at, energy, size, col):
        ld = bpy.data.lights.new(name, type="AREA")
        ld.energy = energy
        ld.size = size
        ld.color = col
        lo = bpy.data.objects.new(name, ld)
        lo.location = Vector(pos)
        lo.rotation_euler = (Vector(look_at) - lo.location).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(lo)
        return lo, ld

    add_area("KeyLight", (-0.65, -0.95, 0.85), (0, 0, 0.14), 36.0, 1.05, (1.0, 0.96, 0.90))
    add_area("FillLight", (0.85, -0.65, 0.45), (0, 0, 0.14), 18.0, 1.15, (0.82, 0.94, 1.0))
    _, rim_data = add_area("RimLight", (0.35, 0.95, 0.65), (0, 0, 0.14), 40.0, 0.80, (1.0, 0.86, 0.56))
    return cam_obj, rim_data


def frame_camera_for_object(cam_obj, obj):
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    min_v = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    max_v = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center = (min_v + max_v) * 0.5
    radius = max((max_v - min_v).length * 0.5, 0.08)
    dist = radius * 3.05
    elev = math.radians(22.0)
    azim = math.radians(-16.0)
    cam_pos = center + Vector((
        dist * math.cos(elev) * math.sin(azim),
        -dist * math.cos(elev) * math.cos(azim),
        dist * math.sin(elev),
    ))
    cam_obj.location = cam_pos
    cam_obj.rotation_euler = (center - cam_pos).to_track_quat("-Z", "Y").to_euler()


def main():
    clear_scene()
    M = mats()
    built = []
    for art_id, rarity, zh, fn, hero_rot in COLLECTIBLES:
        obj = fn(M)
        built.append((art_id, rarity, zh, obj, hero_rot))
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        print(f"  Built {obj.name:28s}: {tris:4d} tris, {len(obj.data.materials)} mats", flush=True)

    bpy.ops.object.select_all(action="DESELECT")
    for _aid, _r, _zh, obj, _rot in built:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    print(f"Exported {GLB_OUT} ({GLB_OUT.stat().st_size // 1024} KB)", flush=True)

    if "--skip-icons" not in sys.argv:
        cam_obj, rim_data = setup_studio_render()
        for _aid, _r, _zh, obj, _rot in built:
            obj.hide_render = True
        scene = bpy.context.scene
        for art_id, rarity, zh, obj, hero_rot in built:
            out_icon = ICON_DIR / f"{art_id}.png"
            obj.hide_render = False
            obj.rotation_euler = Euler(tuple(math.radians(a) for a in hero_rot), "XYZ")
            rim_data.color = RARITY_RIM_COLORS[rarity]
            frame_camera_for_object(cam_obj, obj)
            scene.render.filepath = str(out_icon)
            bpy.ops.render.render(write_still=True)
            obj.rotation_euler = Euler((0, 0, 0), "XYZ")
            obj.hide_render = True
            print(f"  Rendered studio icon -> {out_icon.name} ({out_icon.stat().st_size // 1024} KB)", flush=True)


if __name__ == "__main__":
    main()
