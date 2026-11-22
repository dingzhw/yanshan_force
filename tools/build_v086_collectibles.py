#!/usr/bin/env python3
"""Build 62 sculpted PBR collectibles for v0.8.6 in Blender 4.5 LTS:
  - 44 brand-new Jiangnan / scholar / museum / tactical collectibles (expanding 64 -> 108 total)
  - 18 re-sculpted & refined legacy collectibles (overriding rougher v0.7.2 models & refreshing icons)

Outputs:
  1. game/assets/slice/v086_collectibles.glb  -- 62 named meshes (`loot_<art_id>`), grounded Z=0.
  2. game/assets/icons/loot/<art_id>.png      -- 62 studio-lit 256x256 transparent Cycles icons.
  3. docs/slice-v086-collectibles.json        -- geometry & icon metrics.

Run with:
  blender --background --python tools/build_v086_collectibles.py
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
GLB_OUT = ROOT / "game" / "assets" / "slice" / "v086_collectibles.glb"
ICON_DIR = ROOT / "game" / "assets" / "icons" / "loot"
REVIEW_DIR = ROOT / "docs" / "v086-review"
REPORT_OUT = ROOT / "docs" / "slice-v086-collectibles.json"

ICON_DIR.mkdir(parents=True, exist_ok=True)
REVIEW_DIR.mkdir(parents=True, exist_ok=True)
GLB_OUT.parent.mkdir(parents=True, exist_ok=True)


def srgb(r: float, g: float, b: float) -> tuple[float, float, float, float]:
    return (r ** 2.2, g ** 2.2, b ** 2.2, 1.0)


def hex_lin(h: str) -> tuple[float, float, float, float]:
    h = h.lstrip("#")
    return srgb(int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0)


MAT_CACHE: dict[str, bpy.types.Material] = {}


def make_mat(
    name: str,
    col: str = "cccccc",
    metallic: float = 0.0,
    roughness: float = 0.45,
    emission: str | None = None,
    emission_strength: float = 0.0,
    coat: float = 0.0,
    alpha: float = 1.0,
) -> bpy.types.Material:
    if name in MAT_CACHE:
        return MAT_CACHE[name]
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out_n = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs["BSDF"], out_n.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = hex_lin(col)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.08
    if "Alpha" in bsdf.inputs and alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    if emission is not None and emission_strength > 0.0 and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = hex_lin(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    MAT_CACHE[name] = mat
    return mat


def mats() -> dict[str, bpy.types.Material]:
    return {
        # Woods & Bamboo
        "bamboo": make_mat("v86_bamboo", "a99558", 0.0, 0.46, coat=0.12),
        "bamboo_dark": make_mat("v86_bamboo_dark", "6c562c", 0.0, 0.50, coat=0.14),
        "purple_bamboo": make_mat("v86_purple_bamboo", "4b2938", 0.0, 0.28, coat=0.45),
        "boxwood": make_mat("v86_boxwood", "d5a764", 0.0, 0.36, coat=0.25),
        "rosewood": make_mat("v86_rosewood", "3d1915", 0.0, 0.28, coat=0.42),
        "walnut": make_mat("v86_walnut", "5c3c24", 0.0, 0.48),
        "ebony": make_mat("v86_ebony", "1d1715", 0.0, 0.30, coat=0.32),
        "bark": make_mat("v86_bark", "4d3626", 0.0, 0.84),
        "straw": make_mat("v86_straw", "cfb06c", 0.0, 0.72),
        # Ceramics & Lacquer
        "clay": make_mat("v86_clay", "9a6c4e", 0.0, 0.76),
        "clay_dark": make_mat("v86_clay_dark", "694430", 0.0, 0.72),
        "porcelain": make_mat("v86_porcelain", "f2f3ee", 0.0, 0.14, coat=0.85),
        "cobalt": make_mat("v86_cobalt", "214a96", 0.0, 0.16, coat=0.85),
        "celadon": make_mat("v86_celadon", "78b59f", 0.0, 0.14, coat=0.92),
        "celadon_deep": make_mat("v86_celadon_deep", "50917e", 0.0, 0.16, coat=0.90),
        "cinnabar": make_mat("v86_cinnabar", "a6221c", 0.0, 0.24, coat=0.68),
        "lacquer_black": make_mat("v86_lacquer_black", "1a1414", 0.0, 0.14, coat=0.88),
        "cloisonne_blue": make_mat("v86_cloisonne_blue", "18469e", 0.08, 0.18, coat=0.82),
        "turquoise": make_mat("v86_turquoise", "2ab5b2", 0.05, 0.22, coat=0.72),
        # Metals
        "gold": make_mat("v86_gold", "f2c249", 0.94, 0.18, coat=0.22),
        "gold_deep": make_mat("v86_gold_deep", "c79128", 0.90, 0.24),
        "brass": make_mat("v86_brass", "cfa248", 0.88, 0.26),
        "copper": make_mat("v86_copper", "c96c3e", 0.90, 0.24),
        "bronze": make_mat("v86_bronze", "6e5b3c", 0.80, 0.38),
        "bronze_patina": make_mat("v86_bronze_patina", "467564", 0.42, 0.56),
        "pewter": make_mat("v86_pewter", "9ea4a8", 0.84, 0.34),
        "silver": make_mat("v86_silver", "dde4ea", 0.94, 0.18),
        "steel": make_mat("v86_steel", "626b73", 0.84, 0.32),
        "titanium": make_mat("v86_titanium", "333c46", 0.82, 0.34),
        "carbon": make_mat("v86_carbon", "23282e", 0.22, 0.42),
        "foil": make_mat("v86_foil", "bfc7cb", 0.78, 0.28),
        # Stones & Gems & Jade
        "granite": make_mat("v86_granite", "7f8687", 0.0, 0.82),
        "taihu_stone": make_mat("v86_taihu_stone", "a4a9a2", 0.0, 0.68),
        "moss": make_mat("v86_moss", "486e39", 0.0, 0.86),
        "white_jade": make_mat("v86_white_jade", "eef2e6", 0.0, 0.14, coat=0.90),
        "jade_green": make_mat("v86_jade_green", "329e68", 0.0, 0.16, coat=0.90),
        "jade_emerald": make_mat("v86_jade_emerald", "1f8c52", 0.0, 0.14, coat=0.94),
        "jade_yellow": make_mat("v86_jade_yellow", "c7b878", 0.0, 0.22, coat=0.72),
        "ruby": make_mat("v86_ruby", "d91c38", 0.05, 0.10, emission="ff2a48", emission_strength=0.45, coat=0.95),
        "fluorite": make_mat("v86_fluorite", "4be0be", 0.04, 0.12, emission="38d4b2", emission_strength=0.35, coat=0.95),
        "ivory": make_mat("v86_ivory", "f2ead8", 0.0, 0.28, coat=0.40),
        "pearl": make_mat("v86_pearl", "faf6ee", 0.12, 0.12, coat=0.95),
        "lingzhi": make_mat("v86_lingzhi", "5a1d48", 0.0, 0.18, coat=0.90),
        "lingzhi_rim": make_mat("v86_lingzhi_rim", "d6a147", 0.10, 0.34, coat=0.45),
        # Textiles, Paper, Tactical
        "silk_red": make_mat("v86_silk_red", "c82428", 0.0, 0.42),
        "silk_cream": make_mat("v86_silk_cream", "eee4cb", 0.0, 0.56),
        "silk_jade": make_mat("v86_silk_jade", "2f8a74", 0.0, 0.44),
        "silk_gold": make_mat("v86_silk_gold", "d9a944", 0.18, 0.38),
        "paper": make_mat("v86_paper", "e6dbc2", 0.0, 0.72),
        "paper_ink": make_mat("v86_paper_ink", "25282c", 0.0, 0.76),
        "olive": make_mat("v86_olive", "495b3b", 0.0, 0.62),
        "orange": make_mat("v86_orange", "e85b1c", 0.05, 0.32, coat=0.30),
        "rubber": make_mat("v86_rubber", "1e2226", 0.0, 0.74),
        "solar_blue": make_mat("v86_solar_blue", "133368", 0.45, 0.16, coat=0.80),
        "pcb": make_mat("v86_pcb", "145a3c", 0.12, 0.34, coat=0.45),
        # Emissives
        "glow_cyan": make_mat("v86_glow_cyan", "22d8ff", 0.0, 0.15, emission="22d8ff", emission_strength=2.2),
        "glow_amber": make_mat("v86_glow_amber", "ffaa22", 0.0, 0.18, emission="ffaa22", emission_strength=2.0),
        "glow_green": make_mat("v86_glow_green", "3cff88", 0.0, 0.18, emission="3cff88", emission_strength=1.8),
        "glow_red": make_mat("v86_glow_red", "ff3044", 0.0, 0.16, emission="ff3044", emission_strength=2.2),
        "kingfisher": make_mat("v86_kingfisher", "1387b8", 0.30, 0.18, coat=0.85),
    }


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MAT_CACHE.clear()


def _uv_box(bm: bmesh.types.BMesh, uv_layer):
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    if not xs:
        return
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    minz, maxz = min(zs), max(zs)
    dx = max(maxx - minx, 1e-4)
    dy = max(maxy - miny, 1e-4)
    dz = max(maxz - minz, 1e-4)
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                loop[uv_layer].uv = ((co.x - minx) / dx, (co.y - miny) / dy)
            elif ay >= ax:
                loop[uv_layer].uv = ((co.x - minx) / dx, (co.z - minz) / dz)
            else:
                loop[uv_layer].uv = ((co.y - miny) / dy, (co.z - minz) / dz)


def _uv_cyl(bm: bmesh.types.BMesh, uv_layer):
    zs = [v.co.z for v in bm.verts]
    if not zs:
        return
    minz, maxz = min(zs), max(zs)
    dz = max(maxz - minz, 1e-4)
    for f in bm.faces:
        for loop in f.loops:
            co = loop.vert.co
            u = (math.atan2(co.y, co.x) + math.pi) / (2.0 * math.pi)
            v = (co.z - minz) / dz
            loop[uv_layer].uv = (u, v)


class PartBuilder:
    def __init__(self, name: str):
        self.name = name
        self.objs: list[bpy.types.Object] = []

    def _finish_bm(self, bm, mat, smooth=True, uv_mode="box", xform=None):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if xform is not None:
            bmesh.ops.transform(bm, matrix=xform, verts=bm.verts)
        uv_layer = bm.loops.layers.uv.verify()
        if uv_mode == "cyl":
            _uv_cyl(bm, uv_layer)
        else:
            _uv_box(bm, uv_layer)
        mesh = bpy.data.meshes.new(self.name + "_p")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(mat)
        for poly in mesh.polygons:
            poly.use_smooth = smooth
        obj = bpy.data.objects.new(self.name + "_p", mesh)
        bpy.context.scene.collection.objects.link(obj)
        self.objs.append(obj)
        return obj

    def box(self, size, pos=(0, 0, 0), rot=(0, 0, 0), mat=None, bevel=0.0, bevel_segs=2, smooth=False):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if bevel > 0.0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=bevel_segs, affect="EDGES", clamp_overlap=True)
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth or bevel > 0.0, uv_mode="box", xform=xf)

    def cyl(self, r_bot, r_top, height, segs=22, pos=(0, 0, 0), rot=(0, 0, 0), mat=None, cap=True, smooth=True):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segs, radius1=r_bot, radius2=r_top, depth=height)
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode="cyl", xform=xf)

    def sphere(self, radius, pos=(0, 0, 0), rot=(0, 0, 0), mat=None, segs=18, rings=10, smooth=True):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
        sc = Vector(radius) if isinstance(radius, tuple) else Vector((radius, radius, radius))
        bmesh.ops.scale(bm, vec=sc, verts=bm.verts)
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode="box", xform=xf)

    def torus(self, major_r, minor_r, major_segs=26, minor_segs=10, pos=(0, 0, 0), rot=(0, 0, 0), mat=None, arc_deg=360.0, scale_vec=(1.0, 1.0, 1.0), smooth=True):
        bm = bmesh.new()
        closed = arc_deg >= 359.5
        steps = major_segs if closed else major_segs + 1
        rings_v = []
        for i in range(steps):
            theta = math.radians(arc_deg) * (i / float(major_segs))
            ct, st = math.cos(theta), math.sin(theta)
            ring = []
            for j in range(minor_segs):
                phi = 2.0 * math.pi * j / minor_segs
                cp, sp = math.cos(phi), math.sin(phi)
                rr = major_r + minor_r * cp
                ring.append(bm.verts.new((rr * ct * scale_vec[0], rr * st * scale_vec[1], minor_r * sp * scale_vec[2])))
            rings_v.append(ring)
        n_rings = len(rings_v)
        for i in range(n_rings - (0 if closed else 1)):
            r1 = rings_v[i]
            r2 = rings_v[(i + 1) % n_rings]
            for j in range(minor_segs):
                jn = (j + 1) % minor_segs
                bm.faces.new((r1[j], r2[j], r2[jn], r1[jn]))
        if not closed:
            bm.faces.new(list(reversed(rings_v[0])))
            bm.faces.new(rings_v[-1])
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode="box", xform=xf)

    def lathe(self, profile, segs=28, flute_lobes=0, flute_amp=0.0, pos=(0, 0, 0), rot=(0, 0, 0), mat=None, smooth=True):
        bm = bmesh.new()
        rings_v = []
        z_min = min(p[1] for p in profile)
        z_max = max(p[1] for p in profile)
        z_span = max(1e-5, z_max - z_min)
        for r, z in profile:
            ring = []
            h_frac = (z - z_min) / z_span
            for i in range(segs):
                a = 2.0 * math.pi * i / segs
                rr = r
                if flute_lobes > 0 and r > 0.01:
                    rr *= 1.0 + flute_amp * h_frac * abs(math.cos(0.5 * flute_lobes * a))
                ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), z)))
            rings_v.append(ring)
        for k in range(len(rings_v) - 1):
            r1, r2 = rings_v[k], rings_v[k + 1]
            for i in range(segs):
                inext = (i + 1) % segs
                bm.faces.new((r1[i], r1[inext], r2[inext], r2[i]))
        if profile[0][0] > 1e-4:
            bm.faces.new(list(reversed(rings_v[0])))
        if profile[-1][0] > 1e-4:
            bm.faces.new(rings_v[-1])
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode="cyl", xform=xf)

    def tube_path(self, pts, radii, segs=10, mat=None, cap=True, smooth=True):
        bm = bmesh.new()
        vecs = [Vector(p) for p in pts]
        rlist = [radii] * len(vecs) if isinstance(radii, (int, float)) else list(radii)
        rings_v = []
        prev_n = Vector((0, 0, 1))
        for idx, p in enumerate(vecs):
            if idx == 0:
                t = (vecs[1] - vecs[0]).normalized()
            elif idx == len(vecs) - 1:
                t = (vecs[-1] - vecs[-2]).normalized()
            else:
                t = (vecs[idx + 1] - vecs[idx - 1]).normalized()
            if abs(t.dot(prev_n)) > 0.92:
                prev_n = Vector((1, 0, 0)) if abs(t.x) < 0.8 else Vector((0, 1, 0))
            b = t.cross(prev_n).normalized()
            n = b.cross(t).normalized()
            prev_n = n
            rad = rlist[idx]
            ring = []
            for j in range(segs):
                a = 2.0 * math.pi * j / segs
                ring.append(bm.verts.new(p + (n * math.cos(a) + b * math.sin(a)) * rad))
            rings_v.append(ring)
        for k in range(len(rings_v) - 1):
            r1, r2 = rings_v[k], rings_v[k + 1]
            for j in range(segs):
                jn = (j + 1) % segs
                bm.faces.new((r1[j], r2[j], r2[jn], r1[jn]))
        if cap:
            bm.faces.new(list(reversed(rings_v[0])))
            bm.faces.new(rings_v[-1])
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode="box")

    def finalize(self, target_size: float = 0.34) -> bpy.types.Object:
        bpy.ops.object.select_all(action="DESELECT")
        for o in self.objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = self.objs[0]
        if len(self.objs) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.name = self.name
        obj.data.name = self.name + "_mesh"
        bpy.context.view_layer.update()
        corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        min_v = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
        max_v = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
        ext = max_v - min_v
        max_dim = max(ext.x, ext.y, ext.z, 1e-4)
        sc = target_size / max_dim
        cx = (min_v.x + max_v.x) * 0.5
        cy = (min_v.y + max_v.y) * 0.5
        cz = min_v.z
        mat_norm = Matrix.Scale(sc, 4) @ Matrix.Translation((-cx, -cy, -cz))
        obj.data.transform(mat_norm)
        obj.matrix_world = Matrix.Identity(4)
        return obj


# =============================================================================
# 44 BRAND-NEW COLLECTIBLES (T1..T7)
# =============================================================================

# --- TIER 1 (+8) ---
def build_bamboo_basket(M):
    b = PartBuilder("loot_bamboo_basket")
    prof = [(0.08, 0.0), (0.095, 0.06), (0.125, 0.16), (0.145, 0.26), (0.135, 0.27), (0.115, 0.16), (0.082, 0.03), (0.002, 0.025)]
    b.lathe(prof, segs=20, mat=M["bamboo"])
    for z in (0.05, 0.12, 0.19, 0.255):
        r = 0.092 + (z / 0.26) * 0.054
        b.torus(r, 0.009, major_segs=24, minor_segs=8, pos=(0, 0, z), mat=M["bamboo_dark"])
    for i in range(8):
        a = 2 * math.pi * i / 8
        b.tube_path([(0.082 * math.cos(a), 0.082 * math.sin(a), 0.01), (0.146 * math.cos(a), 0.146 * math.sin(a), 0.26)], 0.006, 6, mat=M["bamboo_dark"])
    # Tea leaves mound inside
    b.sphere((0.105, 0.105, 0.045), pos=(0, 0, 0.235), mat=M["moss"])
    # Twin shoulder straps
    b.torus(0.085, 0.008, major_segs=18, minor_segs=6, pos=(0, 0.135, 0.14), rot=(90, 0, 0), mat=M["straw"], arc_deg=200)
    return b.finalize(0.34)


def build_oil_paper_umbrella(M):
    b = PartBuilder("loot_oil_paper_umbrella")
    # Slanted half-open Jiangnan oil-paper umbrella
    tilt = (22, 0, 0)
    b.cyl(0.012, 0.011, 0.42, 12, pos=(0, 0, 0.16), rot=tilt, mat=M["bamboo_dark"])
    b.cyl(0.020, 0.016, 0.055, 12, pos=(0, -0.075, -0.02), rot=tilt, mat=M["rosewood"])
    # Canopy dome
    b.lathe([(0.002, 0.115), (0.045, 0.108), (0.14, 0.072), (0.21, 0.015), (0.22, 0.0), (0.205, 0.005), (0.13, 0.062), (0.02, 0.095)], segs=24, flute_lobes=12, flute_amp=0.03, pos=(0, 0.07, 0.25), rot=tilt, mat=M["silk_cream"])
    # Red decorative painted band on canopy
    b.lathe([(0.16, 0.058), (0.212, 0.014), (0.214, 0.008), (0.158, 0.052)], segs=24, pos=(0, 0.07, 0.252), rot=tilt, mat=M["cinnabar"])
    b.cyl(0.022, 0.012, 0.024, 14, pos=(0, 0.115, 0.365), rot=tilt, mat=M["cinnabar"])
    # Crimson tassel at handle end
    b.cyl(0.009, 0.016, 0.055, 10, pos=(0, -0.09, -0.065), mat=M["silk_red"])
    return b.finalize(0.36)


def build_straw_hat(M):
    b = PartBuilder("loot_straw_hat")
    prof = [(0.004, 0.145), (0.045, 0.125), (0.135, 0.068), (0.22, 0.008), (0.225, 0.0), (0.21, 0.002), (0.12, 0.055), (0.03, 0.105)]
    b.lathe(prof, segs=30, mat=M["straw"])
    b.torus(0.222, 0.009, 30, 8, pos=(0, 0, 0.005), mat=M["bamboo_dark"])
    b.lathe([(0.002, 0.156), (0.038, 0.142), (0.052, 0.122)], segs=18, mat=M["bamboo_dark"])
    for r, z in [(0.09, 0.094), (0.155, 0.050)]:
        b.torus(r, 0.005, 24, 6, pos=(0, 0, z), mat=M["bamboo"])
    b.tube_path([(-0.08, 0.0, 0.045), (-0.06, -0.06, -0.015), (0.0, -0.09, -0.035), (0.06, -0.06, -0.015), (0.08, 0.0, 0.045)], 0.005, 6, mat=M["silk_red"])
    return b.finalize(0.36)


def build_wooden_comb(M):
    b = PartBuilder("loot_wooden_comb")
    # Crescent spine
    pts = [(math.cos(a) * 0.15, 0.0, 0.08 + math.sin(a) * 0.062) for a in [math.radians(t) for t in range(15, 166, 15)]]
    b.tube_path(pts, [0.015 + 0.006 * math.sin(i / 10.0 * math.pi) for i in range(len(pts))], 10, mat=M["boxwood"])
    b.box((0.28, 0.022, 0.036), pos=(0, 0, 0.082), bevel=0.006, mat=M["boxwood"])
    # Fine teeth
    for i in range(15):
        x = -0.126 + i * 0.018
        h = 0.068 + 0.012 * math.cos(x * 8.0)
        b.box((0.007, 0.012, h), pos=(x, 0, 0.036), bevel=0.002, mat=M["boxwood"])
    # Carved gold floral medallion + red tassel
    b.cyl(0.018, 0.018, 0.026, 14, pos=(0, 0, 0.108), rot=(90, 0, 0), mat=M["gold_deep"])
    b.cyl(0.007, 0.014, 0.055, 10, pos=(0.155, 0, 0.055), rot=(0, -18, 0), mat=M["silk_red"])
    return b.finalize(0.32)


def build_clay_teapot(M):
    b = PartBuilder("loot_clay_teapot")
    prof = [(0.065, 0.0), (0.085, 0.02), (0.118, 0.095), (0.110, 0.165), (0.072, 0.215), (0.078, 0.232), (0.064, 0.232), (0.060, 0.205)]
    b.lathe(prof, segs=26, mat=M["clay"])
    # Cork lid & rustic dark neck band
    b.torus(0.074, 0.008, 22, 8, pos=(0, 0, 0.205), mat=M["clay_dark"])
    b.cyl(0.056, 0.060, 0.028, 18, pos=(0, 0, 0.242), mat=M["walnut"])
    b.sphere(0.016, pos=(0, 0, 0.262), mat=M["bamboo_dark"])
    # Spout
    b.tube_path([(0.098, 0, 0.11), (0.148, 0, 0.155), (0.175, 0, 0.215)], [0.024, 0.017, 0.012], 12, mat=M["clay"])
    # Arched bamboo overhead bail handle
    hpts = [(0.0, 0.088 * math.cos(a), 0.215 + 0.095 * math.sin(a)) for a in [math.radians(t) for t in range(0, 181, 18)]]
    b.tube_path(hpts, 0.009, 8, mat=M["bamboo"])
    return b.finalize(0.34)


def build_pine_cone(M):
    b = PartBuilder("loot_pine_cone")
    # Cedar base twig + needles
    b.tube_path([(-0.14, 0.03, 0.02), (0.0, 0.0, 0.028), (0.14, -0.03, 0.038)], 0.011, 8, mat=M["bark"])
    for i in range(10):
        a = -0.8 + i * 0.18
        b.cyl(0.004, 0.001, 0.095, 6, pos=(-0.10 + i * 0.022, 0.04 * (1 if i % 2 == 0 else -1), 0.032), rot=(68, 0, math.degrees(a) * 2.0), mat=M["moss"])
    # Spiral pinecone scales
    b.sphere((0.052, 0.052, 0.095), pos=(0, 0, 0.115), mat=M["clay_dark"])
    for layer in range(6):
        z = 0.045 + layer * 0.028
        r = 0.068 * math.sin((layer + 0.8) / 6.8 * math.pi) + 0.018
        n = 8 if layer < 4 else 6
        for k in range(n):
            ang = 2 * math.pi * (k + layer * 0.5) / n
            b.box((0.030, 0.024, 0.016), pos=(r * math.cos(ang), r * math.sin(ang), z), rot=(28, 0, math.degrees(ang) + 90), bevel=0.004, mat=M["walnut"] if layer % 2 == 0 else M["bark"])
    return b.finalize(0.30)


def build_matchbox(M):
    b = PartBuilder("loot_matchbox")
    # Outer sleeve
    b.box((0.20, 0.13, 0.056), pos=(-0.02, 0, 0.032), bevel=0.004, mat=M["olive"])
    b.box((0.175, 0.108, 0.004), pos=(-0.02, 0, 0.061), mat=M["silk_cream"])
    b.box((0.065, 0.052, 0.005), pos=(-0.02, 0, 0.063), mat=M["cinnabar"])
    # Striker strip on side
    b.box((0.192, 0.005, 0.044), pos=(-0.02, -0.066, 0.032), mat=M["clay_dark"])
    # Half-open inner tray + wooden matches with crimson tips
    b.box((0.18, 0.115, 0.044), pos=(0.065, 0, 0.028), bevel=0.003, mat=M["boxwood"])
    for i in range(6):
        y = -0.042 + i * 0.017
        b.cyl(0.005, 0.005, 0.11, 8, pos=(0.085, y, 0.042), rot=(0, 90, 0), mat=M["straw"])
        b.sphere((0.011, 0.008, 0.008), pos=(0.140, y, 0.042), mat=M["silk_red"])
    return b.finalize(0.30)


def build_bamboo_steamer(M):
    b = PartBuilder("loot_bamboo_steamer")
    # Two stacked woven tiers
    for z0 in (0.0, 0.095):
        b.cyl(0.135, 0.138, 0.092, 26, pos=(0, 0, z0 + 0.046), mat=M["bamboo"])
        b.torus(0.139, 0.009, 26, 8, pos=(0, 0, z0 + 0.012), mat=M["bamboo_dark"])
        b.torus(0.141, 0.009, 26, 8, pos=(0, 0, z0 + 0.084), mat=M["bamboo_dark"])
    # Domed lid slightly tilted to reveal warm steam buns inside
    b.sphere((0.042, 0.042, 0.032), pos=(-0.045, -0.03, 0.195), mat=M["ivory"])
    b.sphere((0.042, 0.042, 0.032), pos=(0.045, -0.025, 0.195), mat=M["ivory"])
    b.sphere((0.042, 0.042, 0.032), pos=(0.0, 0.045, 0.195), mat=M["ivory"])
    b.lathe([(0.142, 0.0), (0.142, 0.022), (0.125, 0.048), (0.06, 0.066), (0.003, 0.070)], 26, pos=(0.02, 0.03, 0.21), rot=(-14, 10, 0), mat=M["bamboo"])
    b.torus(0.032, 0.007, 16, 6, pos=(0.02, 0.045, 0.278), rot=(76, 10, 0), mat=M["bamboo_dark"], arc_deg=180)
    return b.finalize(0.34)


# --- TIER 2 (+8) ---
def build_stone_mill(M):
    b = PartBuilder("loot_stone_mill")
    # Catch tray with pouring lip
    b.cyl(0.165, 0.175, 0.038, 28, pos=(0, 0, 0.019), mat=M["granite"])
    b.box((0.075, 0.055, 0.032), pos=(0, -0.175, 0.022), bevel=0.006, mat=M["granite"])
    # Lower and upper millstones
    b.cyl(0.132, 0.132, 0.072, 26, pos=(0, 0, 0.072), mat=M["taihu_stone"])
    b.cyl(0.130, 0.124, 0.082, 26, pos=(0, 0, 0.152), mat=M["granite"])
    # Grinding feed hopper hole & radial carved grooves
    b.cyl(0.026, 0.032, 0.016, 16, pos=(0.042, 0.01, 0.194), mat=M["ebony"])
    b.cyl(0.018, 0.018, 0.022, 14, pos=(0, 0, 0.198), mat=M["walnut"])
    # Wooden turning handle mounted on side peg
    b.box((0.055, 0.028, 0.026), pos=(-0.135, 0, 0.155), bevel=0.004, mat=M["granite"])
    b.cyl(0.014, 0.016, 0.145, 14, pos=(-0.155, 0, 0.215), mat=M["boxwood"])
    return b.finalize(0.34)


def build_paper_lantern(M):
    b = PartBuilder("loot_paper_lantern")
    # Hexagonal glowing palace lantern
    b.lathe([(0.058, 0.0), (0.095, 0.035), (0.118, 0.125), (0.098, 0.215), (0.060, 0.25)], segs=6, mat=M["silk_red"], smooth=False)
    # Glowing inner lantern ribs
    for i in range(6):
        a = 2 * math.pi * i / 6
        b.tube_path([(0.062 * math.cos(a), 0.062 * math.sin(a), 0.0), (0.122 * math.cos(a), 0.122 * math.sin(a), 0.125), (0.064 * math.cos(a), 0.064 * math.sin(a), 0.25)], 0.008, 6, mat=M["rosewood"])
    # Top & bottom ornate gilt hexagonal crowns
    b.cyl(0.072, 0.088, 0.032, 6, pos=(0, 0, 0.262), mat=M["gold"], smooth=False)
    b.cyl(0.084, 0.068, 0.028, 6, pos=(0, 0, -0.012), mat=M["gold"], smooth=False)
    b.torus(0.026, 0.006, 16, 6, pos=(0, 0, 0.295), rot=(90, 0, 0), mat=M["gold"])
    # Warm golden inner bead & hanging silk tassel
    b.sphere(0.018, pos=(0, 0, -0.042), mat=M["gold"])
    b.cyl(0.010, 0.022, 0.085, 12, pos=(0, 0, -0.095), mat=M["silk_red"])
    return b.finalize(0.36)


def build_wooden_flute(M):
    b = PartBuilder("loot_wooden_flute")
    # Diagonal presentation on mini carved wooden rest
    b.box((0.032, 0.065, 0.058), pos=(-0.10, 0, 0.029), bevel=0.004, mat=M["rosewood"])
    b.box((0.032, 0.065, 0.058), pos=(0.10, 0, 0.029), bevel=0.004, mat=M["rosewood"])
    b.box((0.24, 0.032, 0.016), pos=(0, 0, 0.008), bevel=0.003, mat=M["rosewood"])
    # Purple bamboo dizi body
    b.cyl(0.017, 0.017, 0.44, 18, pos=(0, 0, 0.072), rot=(0, 90, 0), mat=M["purple_bamboo"])
    # Ivory end caps & silk wrapping bands
    b.cyl(0.019, 0.019, 0.026, 18, pos=(-0.215, 0, 0.072), rot=(0, 90, 0), mat=M["ivory"])
    b.cyl(0.019, 0.019, 0.026, 18, pos=(0.215, 0, 0.072), rot=(0, 90, 0), mat=M["ivory"])
    for x in (-0.14, -0.04, 0.06, 0.15):
        b.torus(0.018, 0.0035, 16, 6, pos=(x, 0, 0.072), rot=(0, 90, 0), mat=M["gold"])
    # Tone holes
    for x in (-0.11, -0.01, 0.025, 0.055, 0.085, 0.115, 0.145):
        b.cyl(0.0055, 0.0055, 0.008, 10, pos=(x, 0, 0.088), mat=M["ebony"])
    # Jade bead & crimson silk tassel hanging from tail
    b.sphere(0.012, pos=(0.20, -0.01, 0.042), mat=M["jade_green"])
    b.cyl(0.008, 0.014, 0.055, 10, pos=(0.20, -0.015, 0.008), mat=M["silk_red"])
    return b.finalize(0.36)


def build_brass_bell(M):
    b = PartBuilder("loot_brass_bell")
    prof = [(0.095, 0.0), (0.082, 0.025), (0.068, 0.085), (0.056, 0.15), (0.036, 0.185), (0.004, 0.195)]
    b.lathe(prof, segs=28, mat=M["brass"])
    for z, r in [(0.022, 0.084), (0.095, 0.067), (0.148, 0.057)]:
        b.torus(r, 0.006, 26, 8, pos=(0, 0, z), mat=M["bronze_patina"])
    # Suspension loop & dragon crown
    b.torus(0.024, 0.007, 18, 8, pos=(0, 0, 0.215), rot=(90, 0, 0), mat=M["gold"])
    # Hanging clapper & wind catcher plaque
    b.cyl(0.004, 0.004, 0.12, 8, pos=(0, 0, -0.035), mat=M["silk_red"])
    b.sphere(0.016, pos=(0, 0, -0.015), mat=M["brass"])
    b.box((0.052, 0.006, 0.095), pos=(0, 0, -0.115), bevel=0.002, mat=M["cinnabar"])
    b.box((0.036, 0.008, 0.072), pos=(0, 0, -0.115), mat=M["gold"])
    return b.finalize(0.35)


def build_tea_caddy(M):
    b = PartBuilder("loot_tea_caddy")
    # Octagonal hammered pewter tea caddy
    prof = [(0.072, 0.0), (0.086, 0.015), (0.094, 0.14), (0.086, 0.185), (0.062, 0.202)]
    b.lathe(prof, segs=8, mat=M["pewter"], smooth=False)
    # Tight-fitting double cap & brass blossom finial
    b.cyl(0.070, 0.064, 0.042, 8, pos=(0, 0, 0.218), mat=M["pewter"], smooth=False)
    b.cyl(0.074, 0.074, 0.010, 8, pos=(0, 0, 0.198), mat=M["brass"], smooth=False)
    b.sphere(0.018, pos=(0, 0, 0.252), mat=M["brass"])
    # Front embossed golden plum medallion
    b.cyl(0.034, 0.034, 0.008, 18, pos=(0, -0.088, 0.105), rot=(90, 0, 0), mat=M["gold_deep"])
    b.cyl(0.024, 0.024, 0.010, 18, pos=(0, -0.089, 0.105), rot=(90, 0, 0), mat=M["cinnabar"])
    return b.finalize(0.32)


def build_tactical_watch(M):
    b = PartBuilder("loot_tactical_watch")
    # Angled display stand presentation
    tilt = (58, 0, 0)
    # Rugged case + notched bezel
    b.cyl(0.078, 0.078, 0.030, 28, pos=(0, 0, 0.12), rot=tilt, mat=M["steel"])
    b.torus(0.070, 0.010, 28, 8, pos=(0, -0.014, 0.128), rot=tilt, mat=M["titanium"])
    b.cyl(0.062, 0.062, 0.006, 24, pos=(0, -0.013, 0.128), rot=tilt, mat=M["ebony"])
    # Glowing lume markers & hands
    for i in range(12):
        a = 2 * math.pi * i / 12
        r = 0.048
        local = Euler((math.radians(58), 0, 0), "XYZ").to_matrix() @ Vector((r * math.cos(a), r * math.sin(a), 0.017))
        b.sphere(0.0045 if i % 3 == 0 else 0.0028, pos=(local.x, local.y, 0.12 + local.z), mat=M["glow_green"])
    b.box((0.006, 0.036, 0.004), pos=(0.008, -0.019, 0.135), rot=(58, 0, -30), mat=M["glow_green"])
    b.box((0.005, 0.026, 0.004), pos=(-0.012, -0.018, 0.130), rot=(58, 0, 65), mat=M["orange"])
    # Crown & olive nylon strap loop
    b.cyl(0.012, 0.012, 0.018, 12, pos=(0.082, 0, 0.12), rot=(0, 90, 0), mat=M["steel"])
    b.torus(0.088, 0.016, 26, 8, pos=(0, 0.055, 0.082), rot=(0, 90, 0), scale_vec=(0.82, 1.0, 1.0), mat=M["olive"])
    return b.finalize(0.32)


def build_silk_fan(M):
    b = PartBuilder("loot_silk_fan")
    # Round silk palace fan with handle & jade tassel
    b.cyl(0.135, 0.135, 0.007, 32, pos=(0, 0, 0.22), rot=(90, 0, 0), mat=M["silk_cream"])
    b.torus(0.136, 0.008, 32, 8, pos=(0, 0, 0.22), rot=(90, 0, 0), mat=M["rosewood"])
    # Painted misty mountain relief bands on silk face
    b.sphere((0.075, 0.005, 0.038), pos=(-0.03, -0.004, 0.195), mat=M["celadon_deep"])
    b.sphere((0.068, 0.005, 0.052), pos=(0.032, -0.004, 0.215), mat=M["celadon"])
    b.cyl(0.020, 0.020, 0.006, 16, pos=(-0.045, -0.005, 0.275), rot=(90, 0, 0), mat=M["cinnabar"])
    # Bamboo handle & pearl drop
    b.cyl(0.009, 0.008, 0.16, 12, pos=(0, 0, 0.045), mat=M["bamboo_dark"])
    b.sphere(0.013, pos=(0, 0, -0.042), mat=M["pearl"])
    b.cyl(0.007, 0.013, 0.048, 10, pos=(0, 0, -0.078), mat=M["silk_jade"])
    return b.finalize(0.36)


def build_brass_scale(M):
    b = PartBuilder("loot_brass_scale")
    # Ebony beam steelyard scale resting on display cradle
    b.cyl(0.009, 0.006, 0.42, 14, pos=(0.02, 0, 0.18), rot=(0, 86, 0), mat=M["ebony"])
    for i in range(9):
        b.sphere(0.0035, pos=(-0.08 + i * 0.032, -0.007, 0.184 - i * 0.002), mat=M["gold"])
    # Brass weighing pan hanging on left via 3 cords
    b.lathe([(0.002, 0.0), (0.055, 0.006), (0.078, 0.022), (0.074, 0.025), (0.048, 0.010), (0.002, 0.006)], 22, pos=(-0.15, 0, 0.025), mat=M["brass"])
    for a_deg in (0, 120, 240):
        a = math.radians(a_deg)
        b.tube_path([(-0.15, 0, 0.165), (-0.15 + 0.072 * math.cos(a), 0.072 * math.sin(a), 0.046)], 0.003, 6, mat=M["gold_deep"])
    # Hanging brass counterweight on right
    b.tube_path([(0.12, 0, 0.174), (0.12, 0, 0.068)], 0.0035, 6, mat=M["silk_red"])
    b.lathe([(0.016, 0.0), (0.028, 0.018), (0.026, 0.042), (0.012, 0.056), (0.002, 0.060)], 16, pos=(0.12, 0, 0.012), mat=M["brass"])
    # Central fulcrum hook
    b.torus(0.020, 0.005, 16, 6, pos=(-0.075, 0, 0.212), rot=(90, 0, 0), mat=M["brass"])
    return b.finalize(0.36)


# --- TIER 3 (+7) ---
def build_longquan_vase(M):
    b = PartBuilder("loot_longquan_vase")
    # Rosewood stand
    b.cyl(0.068, 0.062, 0.026, 24, pos=(0, 0, 0.013), mat=M["rosewood"])
    # Classic Song Dynasty Longquan celadon Meiping plum vase profile
    prof = [
        (0.050, 0.026), (0.056, 0.045), (0.068, 0.105), (0.098, 0.185),
        (0.112, 0.245), (0.092, 0.292), (0.036, 0.315), (0.034, 0.340),
        (0.042, 0.352), (0.032, 0.352), (0.028, 0.335)
    ]
    b.lathe(prof, segs=32, mat=M["celadon"])
    b.torus(0.037, 0.004, 24, 6, pos=(0, 0, 0.318), mat=M["celadon_deep"])
    return b.finalize(0.35)


def build_suzhou_embroidery(M):
    b = PartBuilder("loot_suzhou_embroidery")
    # Carved rosewood table-screen stand
    b.box((0.26, 0.075, 0.024), pos=(0, 0, 0.012), bevel=0.005, mat=M["rosewood"])
    b.box((0.024, 0.058, 0.14), pos=(-0.105, 0, 0.082), bevel=0.004, mat=M["rosewood"])
    b.box((0.024, 0.058, 0.14), pos=(0.105, 0, 0.082), bevel=0.004, mat=M["rosewood"])
    # Circular embroidered silk frame
    b.torus(0.118, 0.013, 32, 10, pos=(0, 0, 0.185), rot=(90, 0, 0), mat=M["rosewood"])
    b.cyl(0.110, 0.110, 0.006, 32, pos=(0, 0, 0.185), rot=(90, 0, 0), mat=M["silk_jade"])
    # Embossed white crane + golden sun & pine branch motif
    b.sphere((0.024, 0.006, 0.018), pos=(-0.015, -0.004, 0.175), mat=M["ivory"])
    b.sphere((0.045, 0.005, 0.016), pos=(0.022, -0.004, 0.195), rot=(0, -24, 0), mat=M["pearl"])
    b.cyl(0.018, 0.018, 0.005, 16, pos=(0.045, -0.004, 0.242), rot=(90, 0, 0), mat=M["gold"])
    b.tube_path([(-0.085, -0.004, 0.135), (-0.02, -0.004, 0.145), (0.045, -0.004, 0.128)], 0.006, 6, mat=M["gold_deep"])
    return b.finalize(0.35)


def build_copper_kettle(M):
    b = PartBuilder("loot_copper_kettle")
    prof = [(0.078, 0.0), (0.112, 0.032), (0.122, 0.095), (0.102, 0.155), (0.064, 0.178), (0.068, 0.192), (0.058, 0.192)]
    b.lathe(prof, segs=28, mat=M["copper"])
    # Domed lid + brass lotus finial
    b.lathe([(0.064, 0.190), (0.054, 0.208), (0.022, 0.220), (0.002, 0.222)], 24, mat=M["copper"])
    b.sphere(0.016, pos=(0, 0, 0.236), mat=M["brass"])
    # Graceful gooseneck pouring spout
    b.tube_path([(0.105, 0, 0.075), (0.155, 0, 0.105), (0.175, 0, 0.185), (0.195, 0, 0.205)], [0.020, 0.015, 0.011, 0.009], 12, mat=M["copper"])
    # Coiled brass overhead bail handle
    hpts = [(0.0, 0.095 * math.cos(a), 0.175 + 0.105 * math.sin(a)) for a in [math.radians(t) for t in range(0, 181, 15)]]
    b.tube_path(hpts, 0.009, 8, mat=M["brass"])
    return b.finalize(0.34)


def build_bamboo_carving(M):
    b = PartBuilder("loot_bamboo_carving")
    # Jiading carved bamboo brush pot
    b.cyl(0.088, 0.086, 0.022, 24, pos=(0, 0, 0.011), mat=M["rosewood"])
    prof = [(0.080, 0.022), (0.084, 0.12), (0.082, 0.235), (0.086, 0.245), (0.072, 0.245), (0.070, 0.045), (0.002, 0.040)]
    b.lathe(prof, segs=28, mat=M["boxwood"])
    # High-relief carved scholar pine & scholar rock on front surface
    b.tube_path([(-0.042, -0.075, 0.055), (-0.018, -0.082, 0.135), (0.028, -0.078, 0.195)], [0.012, 0.009, 0.007], 8, mat=M["bamboo_dark"])
    for p in [(-0.032, -0.084, 0.175), (0.018, -0.084, 0.205), (0.048, -0.074, 0.185)]:
        b.sphere((0.026, 0.012, 0.016), pos=p, mat=M["walnut"])
    b.sphere((0.028, 0.014, 0.038), pos=(0.036, -0.076, 0.078), mat=M["bamboo_dark"])
    # Top rosewood rim ring
    b.torus(0.080, 0.007, 26, 8, pos=(0, 0, 0.244), mat=M["rosewood"])
    return b.finalize(0.34)


def build_jade_hairpin(M):
    b = PartBuilder("loot_jade_hairpin")
    # Slanted velvet stand
    b.box((0.26, 0.09, 0.024), pos=(0, 0, 0.012), bevel=0.005, mat=M["rosewood"])
    # Mutton-fat white jade pin shaft
    b.cyl(0.006, 0.012, 0.34, 16, pos=(0.01, 0, 0.075), rot=(0, 82, 0), mat=M["white_jade"])
    # Sculpted magnolia flower head in jade + silver filigree collar
    b.torus(0.015, 0.004, 16, 6, pos=(-0.115, 0, 0.092), rot=(0, 82, 0), mat=M["silver"])
    for i in range(5):
        a = 2 * math.pi * i / 5
        b.sphere((0.032, 0.016, 0.014), pos=(-0.148, 0.016 * math.cos(a), 0.098 + 0.016 * math.sin(a)), rot=(math.degrees(a), 25, 0), mat=M["white_jade"])
    b.sphere(0.011, pos=(-0.158, 0, 0.100), mat=M["gold"])
    # Hanging pearl & emerald drop
    b.sphere(0.010, pos=(-0.132, -0.015, 0.062), mat=M["jade_emerald"])
    b.sphere(0.009, pos=(-0.132, -0.018, 0.042), mat=M["pearl"])
    return b.finalize(0.35)


def build_solar_beacon(M):
    b = PartBuilder("loot_solar_beacon")
    # Central ruggedized orange-titanium rescue unit
    b.box((0.11, 0.085, 0.145), pos=(0, 0, 0.075), bevel=0.010, mat=M["orange"])
    b.box((0.095, 0.090, 0.075), pos=(0, 0, 0.068), bevel=0.006, mat=M["titanium"])
    # Amber strobe dome & folding antenna
    b.cyl(0.030, 0.024, 0.048, 18, pos=(0, 0, 0.168), mat=M["glow_amber"])
    b.cyl(0.005, 0.003, 0.125, 10, pos=(0.038, 0.025, 0.205), mat=M["carbon"])
    # Fold-out twin photovoltaic solar wings
    for sgn in (-1, 1):
        b.box((0.125, 0.014, 0.105), pos=(sgn * 0.125, -0.01, 0.082), rot=(0, 0, -sgn * 14), bevel=0.003, mat=M["titanium"])
        b.box((0.112, 0.016, 0.090), pos=(sgn * 0.125, -0.011, 0.082), rot=(0, 0, -sgn * 14), mat=M["solar_blue"])
    return b.finalize(0.36)


def build_compass_sundial(M):
    b = PartBuilder("loot_compass_sundial")
    # Open hinged brass pocket sundial compass
    b.cyl(0.112, 0.118, 0.024, 30, pos=(0, 0, 0.012), mat=M["brass"])
    b.cyl(0.094, 0.094, 0.006, 28, pos=(0, 0, 0.025), mat=M["silk_cream"])
    # Compass rose needle
    b.box((0.014, 0.072, 0.005), pos=(0, 0.020, 0.032), mat=M["cinnabar"])
    b.box((0.014, 0.072, 0.005), pos=(0, -0.020, 0.032), mat=M["titanium"])
    # Tilted equatorial latitude arc & brass gnomon
    b.torus(0.086, 0.007, 28, 8, pos=(0, 0, 0.095), rot=(54, 0, 0), mat=M["gold"])
    b.cyl(0.004, 0.003, 0.145, 10, pos=(0, 0, 0.102), rot=(-36, 0, 0), mat=M["brass"])
    # Hinged open brass cover tilted behind
    b.cyl(0.108, 0.108, 0.012, 28, pos=(0, 0.132, 0.112), rot=(105, 0, 0), mat=M["brass"])
    return b.finalize(0.34)


# --- TIER 4 (+6) ---
def build_cloisonne_vase(M):
    b = PartBuilder("loot_cloisonne_vase")
    b.cyl(0.070, 0.062, 0.022, 24, pos=(0, 0, 0.011), mat=M["ebony"])
    prof = [
        (0.052, 0.022), (0.064, 0.048), (0.056, 0.082), (0.102, 0.165),
        (0.104, 0.215), (0.052, 0.265), (0.046, 0.305), (0.068, 0.338), (0.058, 0.338)
    ]
    b.lathe(prof, segs=30, mat=M["cloisonne_blue"])
    # Turquoise shoulder/belly bands & gilt bronze wire collars
    b.lathe([(0.104, 0.172), (0.106, 0.205), (0.096, 0.225)], 30, mat=M["turquoise"])
    for z, r in [(0.026, 0.055), (0.165, 0.104), (0.228, 0.095), (0.275, 0.052), (0.338, 0.065)]:
        b.torus(r, 0.006, 28, 8, pos=(0, 0, z), mat=M["gold"])
    # Twin gilt-bronze dragon ear handles
    for sgn in (-1, 1):
        b.tube_path([(sgn * 0.052, 0, 0.295), (sgn * 0.092, 0, 0.272), (sgn * 0.092, 0, 0.225)], 0.008, 8, mat=M["gold"])
    return b.finalize(0.35)


def build_guqin_mini(M):
    b = PartBuilder("loot_guqin_mini")
    # Classic banana-leaf silhouette 7-string guqin on low display risers
    b.box((0.032, 0.072, 0.032), pos=(-0.14, 0, 0.016), bevel=0.004, mat=M["rosewood"])
    b.box((0.032, 0.056, 0.032), pos=(0.14, 0, 0.016), bevel=0.004, mat=M["rosewood"])
    # Main curved lacquered soundbox
    b.box((0.46, 0.088, 0.026), pos=(0, 0, 0.046), bevel=0.010, mat=M["rosewood"])
    b.box((0.20, 0.106, 0.026), pos=(-0.12, 0, 0.046), bevel=0.010, mat=M["rosewood"])
    b.box((0.14, 0.072, 0.022), pos=(0.17, 0, 0.045), bevel=0.008, mat=M["rosewood"])
    # Bridge (Yueshan) & 7 silk-gold strings + 13 pearl hui studs
    b.box((0.016, 0.094, 0.014), pos=(-0.205, 0, 0.062), bevel=0.003, mat=M["ebony"])
    for i in range(7):
        y = -0.030 + i * 0.010
        b.cyl(0.0018, 0.0018, 0.42, 6, pos=(0.0, y, 0.065), rot=(0, 90, 0), mat=M["silk_gold"])
    for i in range(13):
        x = -0.18 + i * 0.030
        b.sphere(0.0032, pos=(x, -0.040, 0.060), mat=M["pearl"])
    # Jade tuning pegs underneath head
    for i in range(4):
        b.cyl(0.005, 0.004, 0.024, 8, pos=(-0.165, -0.024 + i * 0.016, 0.024), mat=M["white_jade"])
    return b.finalize(0.38)


def build_bronze_ding(M):
    b = PartBuilder("loot_bronze_ding")
    # Antique ritual tripod bronze ding cauldron
    prof = [(0.002, 0.092), (0.068, 0.098), (0.112, 0.135), (0.116, 0.195), (0.104, 0.222), (0.120, 0.232), (0.102, 0.234), (0.096, 0.195)]
    b.lathe(prof, segs=30, mat=M["bronze"])
    # Patina taotie relief band
    b.lathe([(0.117, 0.155), (0.119, 0.198), (0.114, 0.206)], 30, mat=M["bronze_patina"])
    for i in range(6):
        a = 2 * math.pi * i / 6
        b.box((0.012, 0.016, 0.056), pos=(0.118 * math.cos(a), 0.118 * math.sin(a), 0.178), rot=(0, 0, math.degrees(a)), mat=M["gold_deep"])
    # Three tall cabriole tripod legs
    for i in range(3):
        a = math.radians(30 + i * 120)
        b.tube_path([
            (0.074 * math.cos(a), 0.074 * math.sin(a), 0.115),
            (0.092 * math.cos(a), 0.092 * math.sin(a), 0.055),
            (0.082 * math.cos(a), 0.082 * math.sin(a), 0.008),
        ], [0.022, 0.017, 0.015], 10, mat=M["bronze"])
    # Twin upright rectangular loop handles on rim
    for sgn in (-1, 1):
        b.torus(0.032, 0.009, 18, 8, pos=(sgn * 0.108, 0, 0.258), rot=(90, 0, 0), mat=M["bronze"], arc_deg=200)
    return b.finalize(0.35)


def build_cinnabar_box(M):
    b = PartBuilder("loot_cinnabar_box")
    # Carved cinnabar lacquer round treasure box (Ti-Hong)
    prof = [(0.088, 0.0), (0.118, 0.022), (0.134, 0.060), (0.132, 0.098), (0.116, 0.128), (0.068, 0.136), (0.004, 0.138)]
    b.lathe(prof, segs=32, mat=M["cinnabar"])
    # Gold mid-seam ring
    b.torus(0.134, 0.0045, 32, 8, pos=(0, 0, 0.064), mat=M["gold"])
    # Layered carved peony petal relief on lid top
    for i in range(8):
        a = 2 * math.pi * i / 8
        b.sphere((0.036, 0.022, 0.012), pos=(0.056 * math.cos(a), 0.056 * math.sin(a), 0.134), rot=(0, 0, math.degrees(a)), mat=M["cinnabar"])
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.3
        b.sphere((0.024, 0.016, 0.012), pos=(0.028 * math.cos(a), 0.028 * math.sin(a), 0.142), rot=(0, 0, math.degrees(a)), mat=M["silk_red"])
    b.sphere(0.016, pos=(0, 0, 0.148), mat=M["gold"])
    return b.finalize(0.34)


def build_blue_white_jar(M):
    b = PartBuilder("loot_blue_white_jar")
    # Classic Ming/Qing Blue-and-White General's Jar (Jiangjun Guan)
    prof = [
        (0.068, 0.0), (0.078, 0.032), (0.095, 0.105), (0.128, 0.195),
        (0.118, 0.242), (0.076, 0.265), (0.072, 0.285)
    ]
    b.lathe(prof, segs=32, mat=M["porcelain"])
    # Rich cobalt bands & lotus panels
    for z0, z1, r0, r1 in [(0.022, 0.055, 0.077, 0.086), (0.125, 0.212, 0.105, 0.130), (0.242, 0.262, 0.116, 0.082)]:
        b.lathe([(r0, z0), (r1, z1)], 32, mat=M["cobalt"])
    for i in range(6):
        a = 2 * math.pi * i / 6
        b.sphere((0.026, 0.012, 0.030), pos=(0.122 * math.cos(a), 0.122 * math.sin(a), 0.172), rot=(0, 0, math.degrees(a) + 90), mat=M["porcelain"])
    # Domed lid + lotus bud finial
    b.lathe([(0.086, 0.278), (0.092, 0.292), (0.068, 0.322), (0.022, 0.342), (0.026, 0.362), (0.003, 0.382)], 28, mat=M["porcelain"])
    b.torus(0.088, 0.006, 28, 8, pos=(0, 0, 0.286), mat=M["cobalt"])
    b.sphere(0.016, pos=(0, 0, 0.366), mat=M["cobalt"])
    return b.finalize(0.36)


def build_tactical_drone(M):
    b = PartBuilder("loot_tactical_drone")
    # Compact carbon-fiber recon quadcopter
    b.box((0.105, 0.145, 0.044), pos=(0, 0, 0.055), bevel=0.010, mat=M["carbon"])
    b.box((0.080, 0.110, 0.014), pos=(0, 0, 0.080), bevel=0.005, mat=M["titanium"])
    # Front gimbal camera + glowing cyan lens
    b.sphere(0.022, pos=(0, -0.076, 0.046), mat=M["titanium"])
    b.cyl(0.012, 0.012, 0.012, 16, pos=(0, -0.094, 0.046), rot=(90, 0, 0), mat=M["glow_cyan"])
    # 4 arms + shrouded rotor ducts + blades
    for sx in (-1, 1):
        for sy in (-1, 1):
            ax, ay = sx * 0.118, sy * 0.108
            b.tube_path([(sx * 0.04, sy * 0.05, 0.055), (ax, ay, 0.068)], 0.009, 8, mat=M["carbon"])
            b.torus(0.048, 0.006, 22, 6, pos=(ax, ay, 0.074), mat=M["titanium"])
            b.cyl(0.010, 0.010, 0.022, 12, pos=(ax, ay, 0.072), mat=M["orange"])
            b.box((0.082, 0.012, 0.003), pos=(ax, ay, 0.082), rot=(0, 0, 28 * sx * sy), mat=M["steel"])
            b.sphere(0.006, pos=(ax, ay, 0.058), mat=M["glow_green"] if sy < 0 else M["glow_red"])
    return b.finalize(0.36)


# --- TIER 5 · 小金 (+6) ---
def build_jade_ruyi(M):
    b = PartBuilder("loot_jade_ruyi")
    # Carved rosewood cradle
    b.box((0.26, 0.08, 0.022), pos=(0, 0, 0.011), bevel=0.005, mat=M["rosewood"])
    b.box((0.024, 0.055, 0.062), pos=(-0.09, 0, 0.042), bevel=0.004, mat=M["rosewood"])
    b.box((0.024, 0.055, 0.085), pos=(0.085, 0, 0.052), bevel=0.004, mat=M["rosewood"])
    # Graceful S-curved imperial emerald jade ruyi body
    pts = [(-0.155, 0, 0.062), (-0.095, 0, 0.076), (0.0, 0, 0.068), (0.085, 0, 0.096), (0.140, 0, 0.132)]
    b.tube_path(pts, [0.014, 0.018, 0.020, 0.022, 0.018], 12, mat=M["jade_emerald"])
    # Lingzhi cloud-head ruyi crown
    b.sphere((0.054, 0.068, 0.022), pos=(0.165, 0, 0.145), rot=(0, -28, 0), mat=M["jade_emerald"])
    b.sphere((0.032, 0.042, 0.018), pos=(0.168, 0, 0.154), rot=(0, -28, 0), mat=M["jade_green"])
    b.torus(0.024, 0.004, 18, 6, pos=(0.168, 0, 0.160), rot=(0, -28, 0), mat=M["gold"])
    # Imperial bullion gold tassel at tail
    b.sphere(0.014, pos=(-0.172, 0, 0.045), mat=M["gold"])
    b.cyl(0.010, 0.018, 0.052, 12, pos=(-0.178, 0, 0.012), mat=M["silk_gold"])
    return b.finalize(0.36)


def build_gold_filigree_box(M):
    b = PartBuilder("loot_gold_filigree_box")
    # Octagonal imperial gold filigree treasure casket
    b.cyl(0.118, 0.125, 0.088, 8, pos=(0, 0, 0.048), mat=M["gold"], smooth=False)
    b.cyl(0.126, 0.112, 0.044, 8, pos=(0, 0, 0.114), mat=M["gold"], smooth=False)
    b.torus(0.126, 0.007, 24, 8, pos=(0, 0, 0.092), mat=M["gold_deep"])
    # Inset turquoise & ruby cabochons around sides and crown
    for i in range(8):
        a = 2 * math.pi * i / 8
        b.sphere((0.014, 0.014, 0.018), pos=(0.118 * math.cos(a), 0.118 * math.sin(a), 0.052), mat=M["turquoise"] if i % 2 == 0 else M["ruby"])
    b.cyl(0.056, 0.044, 0.018, 8, pos=(0, 0, 0.144), mat=M["gold_deep"], smooth=False)
    b.sphere((0.026, 0.026, 0.022), pos=(0, 0, 0.162), mat=M["ruby"])
    return b.finalize(0.34)


def build_bronze_sword(M):
    b = PartBuilder("loot_bronze_sword")
    # Carved wooden sword rack
    b.box((0.28, 0.075, 0.020), pos=(0, 0, 0.010), bevel=0.004, mat=M["rosewood"])
    b.box((0.022, 0.045, 0.082), pos=(-0.105, 0, 0.052), bevel=0.003, mat=M["rosewood"])
    b.box((0.022, 0.045, 0.082), pos=(0.105, 0, 0.052), bevel=0.003, mat=M["rosewood"])
    # Goujian-style faceted diamond-ridge bronze blade
    bm = bmesh.new()
    v_tip = bm.verts.new((0.235, 0.0, 0.098))
    v_top = bm.verts.new((-0.075, 0.0, 0.122))
    v_bot = bm.verts.new((-0.075, 0.0, 0.074))
    v_f = bm.verts.new((-0.075, -0.012, 0.098))
    v_b = bm.verts.new((-0.075, 0.012, 0.098))
    for tri in [(v_tip, v_top, v_f), (v_tip, v_f, v_bot), (v_tip, v_bot, v_b), (v_tip, v_b, v_top), (v_top, v_b, v_bot, v_f)]:
        bm.faces.new(tri)
    b._finish_bm(bm, M["gold_deep"], smooth=False)
    # Turquoise-inlaid bronze guard, ringed grip & flared pommel
    b.box((0.028, 0.028, 0.068), pos=(-0.088, 0, 0.098), bevel=0.005, mat=M["bronze"])
    b.sphere((0.009, 0.016, 0.018), pos=(-0.088, 0, 0.098), mat=M["turquoise"])
    b.cyl(0.012, 0.012, 0.095, 14, pos=(-0.145, 0, 0.098), rot=(0, 90, 0), mat=M["bronze_patina"])
    for x in (-0.125, -0.150):
        b.torus(0.015, 0.004, 14, 6, pos=(x, 0, 0.098), rot=(0, 90, 0), mat=M["gold"])
    b.cyl(0.024, 0.014, 0.016, 18, pos=(-0.198, 0, 0.098), rot=(0, 90, 0), mat=M["gold"])
    return b.finalize(0.38)


def build_celadon_ewer(M):
    b = PartBuilder("loot_celadon_ewer")
    # Song-style melon-lobed Yue celadon wine ewer
    prof = [
        (0.056, 0.0), (0.068, 0.022), (0.104, 0.095), (0.102, 0.162),
        (0.054, 0.212), (0.044, 0.268), (0.056, 0.292), (0.048, 0.292)
    ]
    b.lathe(prof, segs=32, flute_lobes=8, flute_amp=0.055, mat=M["celadon"])
    # Domed lid + tiny lion/bud finial
    b.lathe([(0.046, 0.288), (0.042, 0.308), (0.016, 0.326), (0.002, 0.330)], 22, mat=M["celadon_deep"])
    b.sphere(0.014, pos=(0, 0, 0.340), mat=M["celadon"])
    # Curved spout & ribbon loop handle
    b.tube_path([(0.088, 0, 0.145), (0.135, 0, 0.195), (0.158, 0, 0.275)], [0.018, 0.013, 0.009], 12, mat=M["celadon"])
    b.tube_path([(-0.046, 0, 0.262), (-0.125, 0, 0.252), (-0.135, 0, 0.175), (-0.094, 0, 0.132)], 0.011, 10, mat=M["celadon"])
    return b.finalize(0.36)


def build_ivory_chess(M):
    b = PartBuilder("loot_ivory_chess")
    # Open carved rosewood Xiangqi chessboard box
    b.box((0.28, 0.24, 0.028), pos=(0, 0, 0.014), bevel=0.005, mat=M["rosewood"])
    b.box((0.25, 0.21, 0.006), pos=(0, 0, 0.029), mat=M["boxwood"])
    # Grid lines
    for i in range(5):
        b.box((0.23, 0.004, 0.002), pos=(0, -0.08 + i * 0.04, 0.033), mat=M["rosewood"])
    for j in range(5):
        b.box((0.004, 0.19, 0.002), pos=(-0.09 + j * 0.045, 0, 0.033), mat=M["rosewood"])
    # Turned ivory-cream & jade-green Xiangqi pieces
    pieces = [
        (-0.08, -0.055, "ivory", "cinnabar"), (0.0, -0.065, "ivory", "cinnabar"), (0.085, -0.045, "ivory", "cinnabar"),
        (-0.04, -0.01, "ivory", "cinnabar"), (-0.075, 0.055, "jade_green", "gold"),
        (0.01, 0.062, "jade_green", "gold"), (0.075, 0.045, "jade_green", "gold"), (0.045, 0.01, "jade_green", "gold"),
    ]
    for px, py, pm, tm in pieces:
        b.cyl(0.022, 0.020, 0.016, 16, pos=(px, py, 0.041), mat=M[pm])
        b.cyl(0.014, 0.014, 0.004, 14, pos=(px, py, 0.050), mat=M[tm])
    return b.finalize(0.35)


def build_encrypted_tablet(M):
    b = PartBuilder("loot_encrypted_tablet")
    # Armored tactical field tablet tilted on folding kickstand
    tilt = (62, 0, 0)
    b.box((0.26, 0.18, 0.022), pos=(0, 0, 0.115), rot=tilt, bevel=0.008, mat=M["titanium"])
    # Corner shock bumpers
    for sx in (-1, 1):
        for sy in (-1, 1):
            local = Euler((math.radians(62), 0, 0), "XYZ").to_matrix() @ Vector((sx * 0.125, sy * 0.086, 0))
            b.box((0.032, 0.032, 0.028), pos=(local.x, local.y, 0.115 + local.z), rot=tilt, bevel=0.005, mat=M["rubber"])
    # Illuminated cyan topo radar screen + golden target blip
    local_scr = Euler((math.radians(62), 0, 0), "XYZ").to_matrix() @ Vector((0, 0, 0.011))
    b.box((0.215, 0.138, 0.004), pos=(local_scr.x, local_scr.y, 0.115 + local_scr.z), rot=tilt, mat=M["solar_blue"])
    b.torus(0.045, 0.003, 24, 6, pos=(local_scr.x, local_scr.y - 0.003, 0.117 + local_scr.z), rot=tilt, mat=M["glow_cyan"])
    b.torus(0.024, 0.003, 20, 6, pos=(local_scr.x, local_scr.y - 0.003, 0.117 + local_scr.z), rot=tilt, mat=M["glow_cyan"])
    b.sphere(0.008, pos=(local_scr.x + 0.022, local_scr.y - 0.004, 0.124 + local_scr.z), mat=M["glow_amber"])
    # Rear kickstand
    b.box((0.12, 0.012, 0.11), pos=(0, 0.075, 0.056), rot=(-28, 0, 0), mat=M["steel"])
    return b.finalize(0.35)


# --- TIER 6 · 传说大金 (+5) ---
def build_gold_phoenix_crown(M):
    b = PartBuilder("loot_gold_phoenix_crown")
    # Display stand & imperial golden filigree crown body
    b.cyl(0.078, 0.068, 0.026, 24, pos=(0, 0, 0.013), mat=M["rosewood"])
    prof = [(0.088, 0.042), (0.096, 0.082), (0.088, 0.155), (0.068, 0.205), (0.032, 0.228), (0.002, 0.232)]
    b.lathe(prof, segs=28, mat=M["gold"])
    # Kingfisher-blue enamel (Dian-Cui) cloud bands & soaring phoenix wings
    b.torus(0.095, 0.011, 28, 8, pos=(0, 0, 0.085), mat=M["kingfisher"])
    b.torus(0.086, 0.009, 28, 8, pos=(0, 0, 0.145), mat=M["kingfisher"])
    for sgn in (-1, 1):
        b.box((0.068, 0.014, 0.052), pos=(sgn * 0.105, -0.01, 0.155), rot=(10, -sgn * 28, sgn * 16), bevel=0.005, mat=M["kingfisher"])
        b.box((0.054, 0.012, 0.040), pos=(sgn * 0.088, -0.02, 0.195), rot=(12, -sgn * 38, sgn * 12), bevel=0.004, mat=M["gold"])
    # Central golden phoenix crest + ruby & pearl halo
    b.sphere((0.024, 0.028, 0.036), pos=(0, -0.078, 0.192), mat=M["gold"])
    b.sphere(0.016, pos=(0, -0.098, 0.198), mat=M["ruby"])
    for i in range(9):
        a = math.radians(-120 + i * 30)
        b.sphere(0.010, pos=(0.102 * math.sin(a), -0.102 * math.cos(a), 0.115 + 0.016 * math.cos(a)), mat=M["pearl"])
    return b.finalize(0.35)


def build_jade_cong(M):
    b = PartBuilder("loot_jade_cong")
    # Authentic Liangzhu Jade Cong (square outer prism, cylindrical inner bore, stepped corner registers)
    b.box((0.18, 0.18, 0.022), pos=(0, 0, 0.011), bevel=0.004, mat=M["ebony"])
    # Inner cylindrical tube protruding slightly top & bottom
    b.cyl(0.068, 0.068, 0.245, 28, pos=(0, 0, 0.145), mat=M["jade_yellow"])
    b.cyl(0.044, 0.044, 0.252, 24, pos=(0, 0, 0.145), mat=M["ebony"])
    # 4 tiered square outer registers with vertical center channel grooves
    for tier in range(4):
        z = 0.060 + tier * 0.054
        w = 0.142 + tier * 0.004
        b.box((w, w, 0.044), pos=(0, 0, z), bevel=0.006, mat=M["jade_yellow"])
        b.box((w + 0.004, 0.026, 0.046), pos=(0, 0, z), mat=M["jade_green"])
        b.box((0.026, w + 0.004, 0.046), pos=(0, 0, z), mat=M["jade_green"])
    return b.finalize(0.35)


def build_bronze_chime(M):
    b = PartBuilder("loot_bronze_chime")
    # Lacquered twin-pillar chime rack suspending 5 graduated almond-section bronze bianzhong bells
    b.box((0.36, 0.095, 0.022), pos=(0, 0, 0.011), bevel=0.004, mat=M["cinnabar"])
    for sgn in (-1, 1):
        b.cyl(0.016, 0.014, 0.22, 14, pos=(sgn * 0.155, 0, 0.125), mat=M["cinnabar"])
        b.sphere(0.022, pos=(sgn * 0.155, 0, 0.242), mat=M["gold"])
    b.box((0.36, 0.022, 0.022), pos=(0, 0, 0.228), bevel=0.004, mat=M["ebony"])
    b.box((0.34, 0.024, 0.008), pos=(0, 0, 0.228), mat=M["gold"])
    # 5 graduated bronze bells
    for i in range(5):
        x = -0.108 + i * 0.054
        sc = 1.0 - abs(i - 2) * 0.14
        h = 0.092 * sc
        r = 0.025 * sc
        b.cyl(0.004, 0.004, 0.045, 8, pos=(x, 0, 0.205), mat=M["gold"])
        b.cyl(r * 1.15, r * 0.78, h, 16, pos=(x, 0, 0.175 - h * 0.5), mat=M["bronze"])
        b.torus(r * 0.98, 0.003, 14, 6, pos=(x, 0, 0.175 - h * 0.72), mat=M["bronze_patina"])
    return b.finalize(0.38)


def build_landscape_scroll(M):
    b = PartBuilder("loot_landscape_scroll")
    # Partially unrolled Qinglü Shan-Shui painting scroll
    # Left & right rolled brocade cylinders with jade end rollers
    for x, r in [(-0.145, 0.032), (0.145, 0.026)]:
        b.cyl(r, r, 0.22, 22, pos=(x, 0, r + 0.005), rot=(90, 0, 0), mat=M["silk_gold"])
        b.cyl(0.011, 0.011, 0.258, 14, pos=(x, 0, r + 0.005), rot=(90, 0, 0), mat=M["white_jade"])
    # Unrolled silk scroll sheet in center
    b.box((0.28, 0.20, 0.007), pos=(0, 0, 0.010), mat=M["silk_cream"])
    # Painted Qinglü mountain peaks & golden cloud mist in sculpted low relief
    b.sphere((0.055, 0.058, 0.016), pos=(-0.055, 0.015, 0.016), mat=M["celadon_deep"])
    b.sphere((0.068, 0.062, 0.020), pos=(0.028, 0.025, 0.018), mat=M["jade_green"])
    b.sphere((0.045, 0.042, 0.014), pos=(0.075, -0.025, 0.015), mat=M["cobalt"])
    b.box((0.20, 0.024, 0.008), pos=(0, -0.025, 0.016), bevel=0.003, mat=M["silk_cream"])
    # Collector vermilion seal stamps
    b.box((0.016, 0.016, 0.004), pos=(-0.105, -0.065, 0.015), mat=M["cinnabar"])
    return b.finalize(0.36)


def build_armillary_sphere(M):
    b = PartBuilder("loot_armillary_sphere")
    # Base ring + 4 dragon-pillar legs
    b.torus(0.115, 0.010, 30, 8, pos=(0, 0, 0.012), mat=M["bronze"])
    for i in range(4):
        a = math.radians(45 + i * 90)
        b.tube_path([(0.108 * math.cos(a), 0.108 * math.sin(a), 0.016), (0.095 * math.cos(a), 0.095 * math.sin(a), 0.085), (0.088 * math.cos(a), 0.088 * math.sin(a), 0.145)], 0.009, 8, mat=M["bronze"])
    # Concentric graduated gilt-bronze celestial rings
    c = (0, 0, 0.175)
    b.torus(0.118, 0.008, 32, 8, pos=c, rot=(0, 0, 0), mat=M["gold"])
    b.torus(0.108, 0.007, 32, 8, pos=c, rot=(90, 0, 0), mat=M["gold"])
    b.torus(0.096, 0.006, 30, 8, pos=c, rot=(90, 0, 90), mat=M["brass"])
    b.torus(0.084, 0.006, 28, 8, pos=c, rot=(24, 24, 0), mat=M["gold"])
    # Central celestial axis & polished bronze earth sphere
    b.cyl(0.004, 0.004, 0.26, 10, pos=c, rot=(24, 0, 0), mat=M["gold_deep"])
    b.sphere(0.026, pos=c, mat=M["bronze_patina"])
    return b.finalize(0.36)


# --- TIER 7 · 旷世大红 (+4) ---
def build_gold_dragon_cup(M):
    b = PartBuilder("loot_gold_dragon_cup")
    # Iconic Imperial Gold Chalice ("Jin Ou Yong Gu Bei")
    # Three stylized elephant-trunk gold legs
    for i in range(3):
        a = math.radians(30 + i * 120)
        b.tube_path([
            (0.068 * math.cos(a), 0.068 * math.sin(a), 0.095),
            (0.075 * math.cos(a), 0.075 * math.sin(a), 0.042),
            (0.056 * math.cos(a), 0.056 * math.sin(a), 0.010),
        ], [0.018, 0.015, 0.013], 10, mat=M["gold"])
    # Flared pure gold cup bowl
    prof = [(0.002, 0.080), (0.068, 0.088), (0.095, 0.145), (0.108, 0.215), (0.118, 0.232), (0.104, 0.232), (0.090, 0.148), (0.002, 0.098)]
    b.lathe(prof, segs=32, mat=M["gold"])
    # Jewel-studded rim with rubies, pearls & turquoise
    for i in range(12):
        a = 2 * math.pi * i / 12
        jm = M["ruby"] if i % 3 == 0 else (M["pearl"] if i % 3 == 1 else M["turquoise"])
        b.sphere(0.012, pos=(0.112 * math.cos(a), 0.112 * math.sin(a), 0.222), mat=jm)
    # Twin sculpted dragon ear handles arching above rim
    for sgn in (-1, 1):
        b.tube_path([
            (sgn * 0.096, 0, 0.155),
            (sgn * 0.145, 0, 0.205),
            (sgn * 0.135, 0, 0.262),
            (sgn * 0.105, 0, 0.242),
        ], [0.011, 0.013, 0.015, 0.010], 10, mat=M["gold"])
        b.sphere(0.012, pos=(sgn * 0.132, 0, 0.268), mat=M["ruby"])
    return b.finalize(0.35)


def build_jade_cabbage(M):
    b = PartBuilder("loot_jade_cabbage")
    # Carved rosewood pedestal
    b.cyl(0.075, 0.066, 0.032, 24, pos=(0, 0, 0.016), mat=M["rosewood"])
    # Translucent white jadeite stalk base
    b.sphere((0.066, 0.058, 0.085), pos=(0, 0, 0.095), rot=(14, -8, 0), mat=M["white_jade"])
    # Layered translucent white-to-emerald sculpted bok-choy leaves
    for i in range(7):
        a = math.radians(-100 + i * 33)
        b.sphere((0.032, 0.052, 0.105), pos=(0.042 * math.cos(a), 0.036 * math.sin(a) + 0.01, 0.165), rot=(22 * math.sin(a), -24 * math.cos(a), math.degrees(a)), mat=M["white_jade"])
        b.sphere((0.034, 0.056, 0.082), pos=(0.052 * math.cos(a), 0.048 * math.sin(a) + 0.015, 0.238), rot=(32 * math.sin(a), -30 * math.cos(a), math.degrees(a)), mat=M["jade_emerald"])
    # Inner bright emerald ruffled heart
    b.sphere((0.048, 0.045, 0.062), pos=(0.01, 0.015, 0.248), mat=M["jade_green"])
    # Iconic tiny golden katydid perched on front emerald leaf
    b.sphere((0.012, 0.022, 0.010), pos=(0.025, -0.052, 0.242), rot=(30, 0, 18), mat=M["gold"])
    return b.finalize(0.35)


def build_imperial_jade_seal(M):
    b = PartBuilder("loot_imperial_jade_seal")
    # Imperial white-jade square seal (He Shi Bi)
    b.box((0.185, 0.185, 0.020), pos=(0, 0, 0.010), bevel=0.004, mat=M["cinnabar"])
    b.box((0.168, 0.168, 0.088), pos=(0, 0, 0.066), bevel=0.010, mat=M["white_jade"])
    b.box((0.174, 0.174, 0.014), pos=(0, 0, 0.028), bevel=0.003, mat=M["gold"])
    # Coiled twin imperial dragons carved atop the jade plinth
    for sgn in (-1, 1):
        b.tube_path([
            (sgn * 0.052, -0.045, 0.112),
            (sgn * 0.042, 0.0, 0.178),
            (0.0, sgn * 0.018, 0.205),
            (-sgn * 0.042, 0.032, 0.168),
            (-sgn * 0.052, 0.045, 0.112),
        ], [0.018, 0.022, 0.024, 0.020, 0.016], 12, mat=M["white_jade"])
    b.sphere(0.020, pos=(0, 0, 0.212), mat=M["ruby"])
    # Imperial crimson silk tassel looping through dragon arch
    b.tube_path([(0, -0.025, 0.155), (0.065, -0.075, 0.125), (0.115, -0.088, 0.055)], 0.008, 8, mat=M["silk_red"])
    b.cyl(0.012, 0.020, 0.052, 12, pos=(0.118, -0.090, 0.024), mat=M["silk_gold"])
    return b.finalize(0.35)


def build_quantum_prism(M):
    b = PartBuilder("loot_quantum_prism")
    # Dark titanium hexagonal levitation pedestal
    b.cyl(0.115, 0.098, 0.036, 6, pos=(0, 0, 0.018), mat=M["titanium"], smooth=False)
    b.cyl(0.076, 0.076, 0.008, 6, pos=(0, 0, 0.038), mat=M["glow_red"], smooth=False)
    # Three nested gyroscopic gold orbital rings
    c = (0, 0, 0.185)
    b.torus(0.125, 0.007, 32, 8, pos=c, rot=(28, 14, 0), mat=M["gold"])
    b.torus(0.104, 0.006, 30, 8, pos=c, rot=(-42, 58, 0), mat=M["gold_deep"])
    b.torus(0.084, 0.005, 28, 8, pos=c, rot=(68, -32, 0), mat=M["glow_amber"])
    # Floating ruby-gold geometric octahedron crystal prism
    b.cyl(0.058, 0.001, 0.088, 4, pos=(0, 0, 0.229), mat=M["ruby"], smooth=False)
    b.cyl(0.001, 0.058, 0.088, 4, pos=(0, 0, 0.141), mat=M["ruby"], smooth=False)
    b.torus(0.062, 0.005, 4, 6, pos=c, mat=M["gold"], smooth=False)
    return b.finalize(0.36)


# =============================================================================
# 18 UPGRADED / RE-SCULPTED LEGACY COLLECTIBLES (replacing rougher v0.7.2 models)
# =============================================================================

def build_battery(M):
    b = PartBuilder("loot_battery")
    # Dual-cell rugged ranger Li-ion pack
    b.box((0.18, 0.105, 0.195), pos=(0, 0, 0.098), bevel=0.012, mat=M["titanium"])
    b.box((0.186, 0.110, 0.065), pos=(0, 0, 0.108), bevel=0.004, mat=M["olive"])
    for z in (0.042, 0.162):
        b.box((0.190, 0.114, 0.018), pos=(0, 0, z), bevel=0.004, mat=M["rubber"])
    # Brass terminals + glowing green charge indicator bars
    b.cyl(0.018, 0.016, 0.026, 16, pos=(-0.045, 0, 0.208), mat=M["brass"])
    b.cyl(0.018, 0.016, 0.026, 16, pos=(0.045, 0, 0.208), mat=M["copper"])
    b.torus(0.022, 0.004, 14, 6, pos=(0.045, 0, 0.198), mat=M["silk_red"])
    for i in range(4):
        b.box((0.022, 0.006, 0.010), pos=(-0.045 + i * 0.030, -0.057, 0.125), mat=M["glow_green"] if i < 3 else M["rubber"])
    return b.finalize(0.32)


def build_ration(M):
    b = PartBuilder("loot_ration")
    # Crimped foil vacuum-sealed field ration brick
    b.box((0.19, 0.13, 0.072), pos=(0, 0, 0.040), bevel=0.014, mat=M["olive"])
    b.box((0.22, 0.134, 0.012), pos=(0, 0, 0.040), bevel=0.002, mat=M["foil"])
    b.box((0.135, 0.092, 0.006), pos=(0, 0, 0.076), bevel=0.002, mat=M["silk_cream"])
    b.box((0.095, 0.022, 0.007), pos=(0, 0.016, 0.077), mat=M["orange"])
    b.box((0.080, 0.014, 0.007), pos=(0, -0.015, 0.077), mat=M["titanium"])
    return b.finalize(0.32)


def build_wire(M):
    b = PartBuilder("loot_wire")
    # Wooden flange spool tightly wound with gleaming copper coils
    b.cyl(0.118, 0.118, 0.018, 28, pos=(0, 0, 0.009), mat=M["walnut"])
    b.cyl(0.118, 0.118, 0.018, 28, pos=(0, 0, 0.175), mat=M["walnut"])
    b.cyl(0.042, 0.042, 0.185, 20, pos=(0, 0, 0.092), mat=M["ebony"])
    for k in range(7):
        z = 0.030 + k * 0.020
        b.torus(0.088, 0.011, 28, 10, pos=(0, 0, z), mat=M["copper"])
    # Free unspooled copper lead tail
    b.tube_path([(0.092, 0, 0.125), (0.145, -0.04, 0.095), (0.162, -0.095, 0.022)], 0.007, 8, mat=M["copper"])
    return b.finalize(0.32)


def build_bamboo(M):
    b = PartBuilder("loot_bamboo")
    # Authentic bamboo-node whistle with windway mouthpiece & braided lanyard
    b.cyl(0.028, 0.026, 0.28, 20, pos=(0, 0, 0.042), rot=(0, 80, 0), mat=M["bamboo"])
    for x in (-0.09, 0.02, 0.10):
        b.torus(0.029, 0.005, 20, 6, pos=(x, 0, 0.042 - x * 0.17), rot=(0, 80, 0), mat=M["bamboo_dark"])
    # Bevel fipple mouthpiece notch & finger holes
    b.box((0.032, 0.024, 0.016), pos=(-0.11, 0, 0.082), rot=(0, -10, 0), mat=M["ebony"])
    for x in (-0.03, 0.01, 0.05):
        b.cyl(0.007, 0.007, 0.010, 10, pos=(x, 0, 0.068 - x * 0.17), mat=M["ebony"])
    # Braided jade-gold lanyard loop
    b.torus(0.048, 0.006, 20, 6, pos=(0.175, -0.02, 0.022), rot=(25, 0, 0), mat=M["silk_jade"])
    return b.finalize(0.34)


def build_badge(M):
    b = PartBuilder("loot_badge")
    # Multi-layered ranger shield crest with gold laurel wreath & camphor leaf
    tilt = (72, 0, 0)
    b.cyl(0.115, 0.115, 0.022, 6, pos=(0, 0, 0.125), rot=tilt, mat=M["gold"], smooth=False)
    b.cyl(0.096, 0.096, 0.026, 6, pos=(0, -0.004, 0.125), rot=tilt, mat=M["silk_jade"], smooth=False)
    b.torus(0.098, 0.012, 24, 8, pos=(0, -0.008, 0.125), rot=tilt, mat=M["gold"])
    # Raised camphor leaf emblem + ribbon scroll
    b.sphere((0.028, 0.056, 0.012), pos=(0, -0.018, 0.132), rot=tilt, mat=M["gold"])
    b.box((0.155, 0.034, 0.014), pos=(0, -0.022, 0.068), rot=tilt, bevel=0.004, mat=M["cinnabar"])
    return b.finalize(0.32)


def build_gem(M):
    b = PartBuilder("loot_gem")
    # Mossy river stone matrix + cluster of 9 faceted luminous fluorite crystal prisms
    b.sphere((0.125, 0.105, 0.052), pos=(0, 0, 0.036), mat=M["granite"], segs=12, rings=8, smooth=False)
    b.sphere((0.095, 0.080, 0.028), pos=(0.02, -0.01, 0.062), mat=M["moss"])
    crystals = [
        ((0.0, 0.0, 0.135), (0.034, 0.185), (4, -6, 12)),
        ((-0.055, 0.018, 0.118), (0.026, 0.150), (14, -24, 30)),
        ((0.056, -0.015, 0.112), (0.024, 0.138), (-16, 22, -20)),
        ((-0.022, -0.052, 0.102), (0.022, 0.125), (-26, -10, 45)),
        ((0.032, 0.052, 0.105), (0.022, 0.128), (28, 12, -35)),
        ((-0.075, -0.032, 0.088), (0.018, 0.095), (-22, -34, 15)),
        ((0.078, 0.025, 0.084), (0.016, 0.088), (18, 36, 10)),
    ]
    for pos, (rad, h), rot in crystals:
        b.cyl(rad, rad * 0.85, h, 6, pos=pos, rot=rot, mat=M["fluorite"], smooth=False)
        top_v = Vector(pos) + Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix() @ Vector((0, 0, h * 0.5 + rad * 0.55))
        b.cyl(rad * 0.85, 0.001, rad * 1.15, 6, pos=tuple(top_v), rot=rot, mat=M["fluorite"], smooth=False)
    return b.finalize(0.34)


def build_radio(M):
    b = PartBuilder("loot_radio")
    # Tactical encrypted handheld transceiver
    b.box((0.105, 0.064, 0.215), pos=(0, 0, 0.108), bevel=0.010, mat=M["titanium"])
    b.box((0.112, 0.050, 0.165), pos=(0, 0, 0.105), bevel=0.006, mat=M["olive"])
    # Backlit LCD display + speaker grille + keypad buttons
    b.box((0.074, 0.008, 0.044), pos=(0, -0.032, 0.155), mat=M["glow_green"])
    for i in range(4):
        b.box((0.068, 0.006, 0.006), pos=(0, -0.032, 0.095 + i * 0.011), mat=M["ebony"])
    for r in range(3):
        for c in range(3):
            b.box((0.014, 0.007, 0.010), pos=(-0.022 + c * 0.022, -0.033, 0.036 + r * 0.016), mat=M["rubber"])
    # Rotary channel knobs + whip antenna
    b.cyl(0.014, 0.012, 0.028, 14, pos=(-0.026, 0, 0.228), mat=M["rubber"])
    b.cyl(0.012, 0.010, 0.022, 14, pos=(0.008, 0, 0.225), mat=M["brass"])
    b.cyl(0.008, 0.004, 0.185, 10, pos=(0.036, 0, 0.305), mat=M["carbon"])
    return b.finalize(0.36)


def build_rock(M):
    b = PartBuilder("loot_rock")
    # Carved hongmu display stand
    b.box((0.18, 0.115, 0.026), pos=(0, 0, 0.013), bevel=0.005, mat=M["rosewood"])
    # Sculpted Taihu scholar rock with authentic hollow arches ("Shou Zhou Lou Tou")
    b.tube_path([(-0.055, 0, 0.028), (-0.078, 0.01, 0.125), (-0.025, 0, 0.235), (0.045, -0.01, 0.275)], [0.034, 0.040, 0.036, 0.028], 10, mat=M["taihu_stone"], smooth=False)
    b.tube_path([(0.052, 0.01, 0.028), (0.075, -0.01, 0.105), (0.048, 0, 0.185), (-0.015, 0.01, 0.215)], [0.032, 0.036, 0.028, 0.024], 10, mat=M["taihu_stone"], smooth=False)
    b.tube_path([(-0.055, 0, 0.115), (0.0, -0.018, 0.105), (0.058, 0, 0.122)], [0.024, 0.020, 0.024], 8, mat=M["taihu_stone"], smooth=False)
    b.sphere((0.036, 0.028, 0.046), pos=(0.055, -0.012, 0.268), mat=M["taihu_stone"], segs=10, rings=7, smooth=False)
    b.sphere((0.028, 0.024, 0.018), pos=(-0.058, -0.015, 0.155), mat=M["moss"])
    return b.finalize(0.35)


def build_chip(M):
    b = PartBuilder("loot_chip")
    tilt = (45, 0, 0)
    # Ceramic-gold quantum microprocessor with dense gold edge pins & iridescent core
    b.box((0.20, 0.20, 0.024), pos=(0, 0, 0.11), rot=tilt, bevel=0.005, mat=M["pcb"])
    b.box((0.155, 0.155, 0.030), pos=(0, -0.004, 0.112), rot=tilt, bevel=0.004, mat=M["titanium"])
    b.box((0.088, 0.088, 0.036), pos=(0, -0.007, 0.114), rot=tilt, bevel=0.004, mat=M["glow_cyan"])
    b.torus(0.062, 0.005, 24, 6, pos=(0, -0.014, 0.118), rot=tilt, mat=M["gold"])
    # 28 crisp gold edge pins around all 4 sides
    rot_m = Euler((math.radians(45), 0, 0), "XYZ").to_matrix()
    for i in range(7):
        off = -0.072 + i * 0.024
        for dx, dy in [(off, -0.108), (off, 0.108), (-0.108, off), (0.108, off)]:
            p = rot_m @ Vector((dx, dy, 0))
            b.box((0.008, 0.018, 0.008), pos=(p.x, p.y, 0.11 + p.z), rot=tilt, mat=M["gold"])
    return b.finalize(0.34)


def build_blackbox(M):
    b = PartBuilder("loot_blackbox")
    # Crash-survivable international-orange flight data recorder
    b.box((0.24, 0.155, 0.135), pos=(0, 0, 0.072), bevel=0.010, mat=M["orange"])
    # Protective reinforcing ribs & corner bolts
    for x in (-0.095, 0.0, 0.095):
        b.box((0.022, 0.165, 0.145), pos=(x, 0, 0.072), bevel=0.004, mat=M["orange"])
    # Reflective white/silver stripes
    b.box((0.18, 0.006, 0.020), pos=(0, -0.080, 0.098), mat=M["porcelain"])
    b.box((0.18, 0.006, 0.020), pos=(0, -0.080, 0.048), mat=M["porcelain"])
    # Underwater locator beacon cylinder & top steel carry handle
    b.cyl(0.026, 0.026, 0.135, 18, pos=(0, -0.095, 0.068), rot=(0, 90, 0), mat=M["silver"])
    b.torus(0.056, 0.009, 18, 8, pos=(0, 0, 0.142), rot=(90, 0, 0), mat=M["titanium"], arc_deg=180)
    return b.finalize(0.35)


def build_rubbing(M):
    b = PartBuilder("loot_rubbing")
    # Framed ink-rubbing stone stele scroll on wooden display easel
    tilt = (74, 0, 0)
    b.box((0.22, 0.28, 0.020), pos=(0, 0, 0.142), rot=tilt, bevel=0.005, mat=M["walnut"])
    b.box((0.185, 0.242, 0.024), pos=(0, -0.003, 0.142), rot=tilt, mat=M["paper_ink"])
    # Crisp white carved rubbing calligraphy & mountain lines
    rot_m = Euler((math.radians(74), 0, 0), "XYZ").to_matrix()
    for col_i in range(4):
        for seg_i in range(4):
            p = rot_m @ Vector((-0.058 + col_i * 0.038, -0.072 + seg_i * 0.046, 0.013))
            b.box((0.016, 0.026, 0.004), pos=(p.x, p.y, 0.142 + p.z), rot=tilt, mat=M["silk_cream"])
    # Red seal stamp + easel rear leg
    ps = rot_m @ Vector((-0.062, -0.092, 0.014))
    b.box((0.022, 0.022, 0.005), pos=(ps.x, ps.y, 0.142 + ps.z), rot=tilt, mat=M["cinnabar"])
    b.box((0.032, 0.014, 0.18), pos=(0, 0.088, 0.085), rot=(-28, 0, 0), mat=M["walnut"])
    return b.finalize(0.35)


def build_tally(M):
    b = PartBuilder("loot_tally")
    # Velvet plinth
    b.box((0.26, 0.115, 0.024), pos=(0, 0, 0.012), bevel=0.005, mat=M["rosewood"])
    # Crouching antique bronze Tiger Tally (Hu-Fu) with gold inlaid runes
    b.sphere((0.105, 0.042, 0.048), pos=(-0.01, 0, 0.074), mat=M["bronze"])
    b.sphere((0.048, 0.038, 0.044), pos=(0.088, 0, 0.105), mat=M["bronze"])
    b.sphere((0.026, 0.024, 0.022), pos=(0.122, 0, 0.098), mat=M["bronze"])
    for sy in (-1, 1):
        b.sphere(0.012, pos=(0.082, sy * 0.026, 0.142), mat=M["gold"])
        b.box((0.045, 0.020, 0.026), pos=(0.055, sy * 0.036, 0.038), bevel=0.006, mat=M["bronze"])
        b.box((0.052, 0.022, 0.032), pos=(-0.075, sy * 0.036, 0.040), bevel=0.006, mat=M["bronze"])
    # Curled bronze tail & gold spine seam/inscriptions
    b.tube_path([(-0.098, 0, 0.076), (-0.138, 0, 0.108), (-0.122, 0, 0.138)], 0.011, 8, mat=M["bronze"])
    for x in (-0.055, -0.020, 0.015, 0.048):
        b.box((0.014, 0.088, 0.010), pos=(x, 0, 0.088), mat=M["gold"])
    return b.finalize(0.35)


def build_medal(M):
    b = PartBuilder("loot_medal")
    tilt = (76, 0, 0)
    # Pleated crimson-gold military silk ribbon drape
    b.box((0.125, 0.145, 0.016), pos=(0, 0.025, 0.215), rot=tilt, bevel=0.004, mat=M["cinnabar"])
    b.box((0.038, 0.148, 0.019), pos=(0, 0.024, 0.215), rot=tilt, mat=M["gold"])
    b.box((0.142, 0.022, 0.022), pos=(0, 0.045, 0.285), rot=tilt, bevel=0.004, mat=M["gold"])
    # 8-pointed pure gold sunburst star medallion + ruby heart
    b.cyl(0.092, 0.092, 0.018, 8, pos=(0, -0.008, 0.096), rot=tilt, mat=M["gold"], smooth=False)
    b.cyl(0.092, 0.092, 0.016, 8, pos=(0, -0.008, 0.096), rot=(76, 0, 22.5), mat=M["gold_deep"], smooth=False)
    b.torus(0.058, 0.010, 24, 8, pos=(0, -0.015, 0.096), rot=tilt, mat=M["gold"])
    b.sphere((0.032, 0.032, 0.018), pos=(0, -0.019, 0.096), rot=tilt, mat=M["ruby"])
    return b.finalize(0.35)


def build_quantum(M):
    b = PartBuilder("loot_quantum")
    # Sleek open clamshell Quantum Dictionary prototype
    b.box((0.24, 0.165, 0.028), pos=(0, 0, 0.014), bevel=0.006, mat=M["titanium"])
    b.box((0.195, 0.105, 0.006), pos=(0, -0.012, 0.030), mat=M["gold_deep"])
    # Tilted open holographic sapphire screen lid
    b.box((0.24, 0.165, 0.018), pos=(0, 0.118, 0.105), rot=(66, 0, 0), bevel=0.005, mat=M["titanium"])
    b.box((0.205, 0.132, 0.006), pos=(0, 0.108, 0.108), rot=(66, 0, 0), mat=M["solar_blue"])
    # Floating glowing cyan hologram diamond & orbital gold ring above keyboard
    b.cyl(0.034, 0.001, 0.048, 4, pos=(0, 0.0, 0.138), mat=M["glow_cyan"], smooth=False)
    b.cyl(0.001, 0.034, 0.048, 4, pos=(0, 0.0, 0.090), mat=M["glow_cyan"], smooth=False)
    b.torus(0.054, 0.0045, 24, 6, pos=(0, 0.0, 0.114), rot=(22, -16, 0), mat=M["gold"])
    return b.finalize(0.35)


def build_core(M):
    b = PartBuilder("loot_core")
    # Armored golden fusion containment orb on cradle
    b.cyl(0.095, 0.082, 0.026, 6, pos=(0, 0, 0.013), mat=M["titanium"], smooth=False)
    c = (0, 0, 0.145)
    b.sphere(0.068, pos=c, mat=M["glow_amber"])
    # Armored hex-ribbed gold gimbal rings & containment fins
    b.torus(0.098, 0.012, 24, 8, pos=c, rot=(0, 0, 0), mat=M["gold"])
    b.torus(0.098, 0.012, 24, 8, pos=c, rot=(90, 0, 0), mat=M["gold"])
    b.torus(0.116, 0.010, 28, 8, pos=c, rot=(45, 45, 0), mat=M["titanium"])
    for i in range(6):
        a = 2 * math.pi * i / 6
        b.box((0.022, 0.022, 0.042), pos=(0.106 * math.cos(a), 0.106 * math.sin(a), 0.145), rot=(0, 0, math.degrees(a)), bevel=0.003, mat=M["gold_deep"])
    return b.finalize(0.34)


def build_radar_heart(M):
    b = PartBuilder("loot_radar_heart")
    # Hexagonal phased-array supercomputer red-core heart
    b.cyl(0.125, 0.112, 0.034, 6, pos=(0, 0, 0.017), mat=M["titanium"], smooth=False)
    tilt = (62, 0, 0)
    b.cyl(0.118, 0.118, 0.042, 6, pos=(0, 0, 0.145), rot=tilt, mat=M["titanium"], smooth=False)
    b.torus(0.112, 0.012, 6, 8, pos=(0, -0.012, 0.152), rot=tilt, mat=M["gold"], smooth=False)
    # Crimson emitter grid cells
    rot_m = Euler((math.radians(62), 0, 0), "XYZ").to_matrix()
    for ring_i, (r, n) in enumerate([(0.0, 1), (0.042, 6), (0.080, 12)]):
        for k in range(n):
            a = 2 * math.pi * k / n
            p = rot_m @ Vector((r * math.cos(a), r * math.sin(a), 0.024))
            b.cyl(0.014 if ring_i < 2 else 0.010, 0.012 if ring_i < 2 else 0.008, 0.014, 6, pos=(p.x, p.y, 0.145 + p.z), rot=tilt, mat=M["glow_red"] if ring_i < 2 else M["ruby"], smooth=False)
    return b.finalize(0.35)


def build_ganoderma(M):
    b = PartBuilder("loot_ganoderma")
    # Gnarled mossy cedar rootwood base
    b.tube_path([(-0.12, 0.02, 0.024), (0.0, 0.0, 0.038), (0.11, -0.02, 0.022)], [0.026, 0.038, 0.024], 10, mat=M["bark"])
    b.sphere((0.068, 0.052, 0.024), pos=(0, 0, 0.048), mat=M["moss"])
    # Three lacquered royal-purple & gold-rimmed millennium Lingzhi mushroom caps
    caps = [
        ((0.0, 0.0, 0.215), (0.105, 0.086, 0.028), (-10, 8, 0), [(0, 0, 0.045), (-0.01, 0.01, 0.125), (0, 0, 0.205)]),
        ((-0.075, -0.022, 0.145), (0.074, 0.062, 0.022), (14, -20, 20), [(-0.02, 0, 0.045), (-0.058, -0.015, 0.095), (-0.075, -0.022, 0.140)]),
        ((0.072, 0.024, 0.128), (0.068, 0.056, 0.020), (-16, 18, -24), [(0.02, 0, 0.042), (0.055, 0.015, 0.088), (0.072, 0.024, 0.124)]),
    ]
    for pos, rad, rot, stem in caps:
        b.tube_path(stem, [0.018, 0.015, 0.014], 10, mat=M["lingzhi"])
        b.sphere(rad, pos=pos, rot=rot, mat=M["lingzhi"])
        b.torus(rad[0] * 0.96, 0.008, 24, 8, pos=(pos[0], pos[1], pos[2] - 0.004), rot=rot, scale_vec=(1.0, rad[1] / rad[0], 1.0), mat=M["lingzhi_rim"])
    return b.finalize(0.35)


def build_seal(M):
    b = PartBuilder("loot_seal")
    # Heart of Yanshan: Imperial red-gold dragon seal with inset glowing ruby orb
    b.box((0.185, 0.185, 0.022), pos=(0, 0, 0.011), bevel=0.004, mat=M["ebony"])
    b.box((0.162, 0.162, 0.092), pos=(0, 0, 0.068), bevel=0.009, mat=M["gold"])
    b.box((0.168, 0.168, 0.016), pos=(0, 0, 0.032), bevel=0.003, mat=M["cinnabar"])
    b.box((0.168, 0.168, 0.014), pos=(0, 0, 0.108), bevel=0.003, mat=M["gold_deep"])
    # Sculpted coiled golden dragon finial arching around floating ruby Heart of Yanshan
    b.tube_path([
        (-0.058, -0.048, 0.118), (-0.064, 0.020, 0.175), (0.0, 0.048, 0.215),
        (0.062, 0.015, 0.182), (0.054, -0.045, 0.125), (0.0, -0.056, 0.195),
    ], [0.018, 0.022, 0.025, 0.022, 0.018, 0.024], 12, mat=M["gold"])
    b.sphere(0.032, pos=(0, -0.005, 0.172), mat=M["ruby"])
    b.torus(0.044, 0.005, 22, 6, pos=(0, -0.005, 0.172), rot=(72, 0, 0), mat=M["gold"])
    return b.finalize(0.35)


COLLECTIBLE_REGISTRY = [
    # --- 44 NEW COLLECTIBLES ---
    ("bamboo_basket", 1, "竹编采茶篓", build_bamboo_basket, (0, 0, 14)),
    ("oil_paper_umbrella", 1, "江南油纸伞", build_oil_paper_umbrella, (0, 0, -18)),
    ("straw_hat", 1, "烟山竹笠", build_straw_hat, (0, 0, 10)),
    ("wooden_comb", 1, "黄杨木梳", build_wooden_comb, (0, 0, 14)),
    ("clay_teapot", 1, "粗陶山泉壶", build_clay_teapot, (0, 0, -18)),
    ("pine_cone", 1, "千年红松果", build_pine_cone, (0, 0, 12)),
    ("matchbox", 1, "防潮火柴盒", build_matchbox, (0, 0, 22)),
    ("bamboo_steamer", 1, "小竹蒸笼", build_bamboo_steamer, (0, 0, 16)),

    ("stone_mill", 2, "迷你青石磨", build_stone_mill, (0, 0, 18)),
    ("paper_lantern", 2, "宫廷红灯笼", build_paper_lantern, (0, 0, 12)),
    ("wooden_flute", 2, "紫竹长笛", build_wooden_flute, (0, 0, 12)),
    ("brass_bell", 2, "古寺铜风铃", build_brass_bell, (0, 0, 14)),
    ("tea_caddy", 2, "锡制茶叶罐", build_tea_caddy, (0, 0, 14)),
    ("tactical_watch", 2, "户外机械表", build_tactical_watch, (0, 0, 14)),
    ("silk_fan", 2, "团扇仕女图", build_silk_fan, (0, 0, 10)),
    ("brass_scale", 2, "老式杆秤", build_brass_scale, (0, 0, 10)),

    ("longquan_vase", 3, "龙泉梅瓶", build_longquan_vase, (0, 0, 12)),
    ("suzhou_embroidery", 3, "苏绣双面屏", build_suzhou_embroidery, (0, 0, 12)),
    ("copper_kettle", 3, "紫铜炭炉壶", build_copper_kettle, (0, 0, -18)),
    ("bamboo_carving", 3, "嘉定竹雕笔筒", build_bamboo_carving, (0, 0, 14)),
    ("jade_hairpin", 3, "白玉兰花簪", build_jade_hairpin, (0, 0, 10)),
    ("solar_beacon", 3, "太阳能信标器", build_solar_beacon, (0, 0, 16)),
    ("compass_sundial", 3, "日晷罗盘仪", build_compass_sundial, (0, 0, 14)),

    ("cloisonne_vase", 4, "景泰蓝赏瓶", build_cloisonne_vase, (0, 0, 14)),
    ("guqin_mini", 4, "蕉叶式七弦古琴", build_guqin_mini, (0, 0, 16)),
    ("bronze_ding", 4, "青铜三足小鼎", build_bronze_ding, (0, 0, 14)),
    ("cinnabar_box", 4, "剔红雕漆圆盒", build_cinnabar_box, (0, 0, 14)),
    ("blue_white_jar", 4, "青花将军罐", build_blue_white_jar, (0, 0, 14)),
    ("tactical_drone", 4, "侦察四旋翼机", build_tactical_drone, (0, 0, 22)),

    ("jade_ruyi", 5, "碧玉如意", build_jade_ruyi, (0, 0, 12)),
    ("gold_filigree_box", 5, "花丝镶嵌金盒", build_gold_filigree_box, (0, 0, 14)),
    ("bronze_sword", 5, "越王式青铜短剑", build_bronze_sword, (0, 0, 12)),
    ("celadon_ewer", 5, "越窑青瓷执壶", build_celadon_ewer, (0, 0, -16)),
    ("ivory_chess", 5, "紫檀象棋匣", build_ivory_chess, (0, 0, 20)),
    ("encrypted_tablet", 5, "军用战术平板", build_encrypted_tablet, (0, 0, 16)),

    ("gold_phoenix_crown", 6, "鎏金凤冠", build_gold_phoenix_crown, (0, 0, 12)),
    ("jade_cong", 6, "良渚神徽玉琮", build_jade_cong, (0, 0, 24)),
    ("bronze_chime", 6, "曾侯乙式编钟", build_bronze_chime, (0, 0, 12)),
    ("landscape_scroll", 6, "青绿山水手卷", build_landscape_scroll, (0, 0, 14)),
    ("armillary_sphere", 6, "浑天仪模型", build_armillary_sphere, (0, 0, 16)),

    ("gold_dragon_cup", 7, "金瓯永固杯", build_gold_dragon_cup, (0, 0, 14)),
    ("jade_cabbage", 7, "翠玉白菜", build_jade_cabbage, (0, 0, 14)),
    ("imperial_jade_seal", 7, "传国和氏璧玉玺", build_imperial_jade_seal, (0, 0, 18)),
    ("quantum_prism", 7, "烟山天穹全息棱镜", build_quantum_prism, (0, 0, 18)),

    # --- 18 UPGRADED LEGACY COLLECTIBLES ---
    ("battery", 1, "旧巡护电池", build_battery, (0, 0, 20)),
    ("ration", 1, "压缩干粮", build_ration, (0, 0, 18)),
    ("wire", 1, "信号铜线", build_wire, (0, 0, 16)),
    ("bamboo", 1, "青竹编织哨", build_bamboo, (0, 0, 14)),
    ("badge", 2, "巡护员徽章", build_badge, (0, 0, 12)),
    ("gem", 2, "溪石萤光矿", build_gem, (0, 0, 14)),
    ("radio", 3, "加密无线电台", build_radio, (0, 0, 20)),
    ("rock", 3, "太湖透漏赏石", build_rock, (0, 0, 16)),
    ("chip", 4, "无人机核心芯片", build_chip, (0, 0, 16)),
    ("blackbox", 4, "军用黑匣子", build_blackbox, (0, 0, 20)),
    ("rubbing", 4, "烟霞岩画残拓", build_rubbing, (0, 0, 14)),
    ("tally", 6, "烟山古铜虎符", build_tally, (0, 0, -18)),
    ("medal", 6, "特级金质勋章", build_medal, (0, 0, 12)),
    ("quantum", 6, "量子词典原型机", build_quantum, (0, 0, 18)),
    ("core", 6, "烟山统领黄金核心", build_core, (0, 0, 18)),
    ("radar_heart", 7, "相控阵超算雷达心", build_radar_heart, (0, 0, 16)),
    ("ganoderma", 7, "烟山千年紫芝王", build_ganoderma, (0, 0, 14)),
    ("seal", 7, "烟山之心·赤金龙印", build_seal, (0, 0, 22)),
]

RARITY_RIM_COLORS = {
    1: (0.86, 0.90, 0.94),
    2: (0.48, 0.96, 0.72),
    3: (0.42, 0.76, 1.00),
    4: (0.82, 0.56, 1.00),
    5: (0.96, 0.82, 0.50),
    6: (1.00, 0.80, 0.24),
    7: (1.00, 0.34, 0.40),
}


def setup_studio_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 20
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
    scene.view_settings.exposure = -0.15

    world = bpy.data.worlds.new("MuseumStudioWorld86")
    scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs["Color"].default_value = (0.30, 0.34, 0.38, 1.0)
        bg.inputs["Strength"].default_value = 0.74

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

    add_area("KeyLight", (-0.65, -0.95, 0.85), (0, 0, 0.14), 34.0, 1.05, (1.0, 0.96, 0.90))
    add_area("FillLight", (0.85, -0.65, 0.45), (0, 0, 0.14), 16.0, 1.15, (0.78, 0.94, 1.0))
    _, rim_data = add_area("RimLight", (0.35, 0.95, 0.65), (0, 0, 0.14), 38.0, 0.80, (1.0, 0.86, 0.56))
    return cam_obj, rim_data


def frame_camera_for_object(cam_obj, obj):
    bpy.context.view_layer.update()
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    min_v = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    max_v = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center = (min_v + max_v) * 0.5
    radius = max((max_v - min_v).length * 0.5, 0.08)
    dist = radius * 3.10
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
    built_objs = []
    stats = {}

    for art_id, rarity, zh, fn, hero_rot in COLLECTIBLE_REGISTRY:
        obj = fn(M)
        built_objs.append((art_id, rarity, zh, obj, hero_rot))
        tri_count = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        corners = [Vector(c) for c in obj.bound_box]
        ext = Vector((
            max(c.x for c in corners) - min(c.x for c in corners),
            max(c.y for c in corners) - min(c.y for c in corners),
            max(c.z for c in corners) - min(c.z for c in corners),
        ))
        stats[art_id] = {
            "title": zh,
            "rarity": rarity,
            "mesh_name": obj.name,
            "triangles": tri_count,
            "materials": len(obj.data.materials),
            "size_m": [round(ext.x, 3), round(ext.y, 3), round(ext.z, 3)],
        }
        print(f"  Built {obj.name:24s}: {tri_count:4d} tris, {len(obj.data.materials)} mats", flush=True)

    # Export all 62 clean PBR meshes in ONE unified GLB
    bpy.ops.object.select_all(action="DESELECT")
    for _aid, _r, _zh, obj, _rot in built_objs:
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
        export_image_format="AUTO",
    )
    print(f"Exported {GLB_OUT.relative_to(ROOT)} ({GLB_OUT.stat().st_size / (1024 * 1024):.2f} MB)", flush=True)

    # Render all 62 256x256 transparent studio icons (always refresh these 62 for v0.8.6!)
    skip_icons = "--skip-icons" in sys.argv
    if not skip_icons:
        cam_obj, rim_data = setup_studio_render()
        for _aid, _r, _zh, obj, _rot in built_objs:
            obj.hide_render = True
        scene = bpy.context.scene
        total_icon_bytes = 0
        for idx, (art_id, rarity, zh, obj, hero_rot) in enumerate(built_objs, 1):
            out_icon = ICON_DIR / f"{art_id}.png"
            obj.hide_render = False
            obj.rotation_euler = Euler(tuple(math.radians(a) for a in hero_rot), "XYZ")
            rim_data.color = RARITY_RIM_COLORS[rarity]
            frame_camera_for_object(cam_obj, obj)
            scene.render.filepath = str(out_icon)
            bpy.ops.render.render(write_still=True)
            obj.rotation_euler = Euler((0, 0, 0), "XYZ")
            obj.hide_render = True
            b_sz = out_icon.stat().st_size
            total_icon_bytes += b_sz
            stats[art_id]["icon_bytes"] = b_sz
            if idx % 10 == 0 or idx == len(built_objs):
                print(f"  Icon progress: {idx}/{len(built_objs)}", flush=True)
    else:
        total_icon_bytes = 0

    summary = {
        "version": "0.8.6",
        "glb_path": str(GLB_OUT.relative_to(ROOT)).replace("\\", "/"),
        "glb_bytes": GLB_OUT.stat().st_size,
        "count": len(built_objs),
        "new_count": 44,
        "upgraded_count": 18,
        "total_icon_bytes": total_icon_bytes,
        "total_triangles": sum(v["triangles"] for v in stats.values()),
        "items": stats,
    }
    REPORT_OUT.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"DONE v0.8.6 collectibles: {len(built_objs)} meshes + icons, {summary['total_triangles']} tris, GLB={summary['glb_bytes']/(1024*1024):.2f}MB", flush=True)


if __name__ == "__main__":
    main()
