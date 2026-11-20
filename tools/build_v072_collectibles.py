#!/usr/bin/env python3
"""Build all 32 sculpted PBR collectibles for v0.7.2 in Blender 4.5.3 LTS.

Outputs:
1. game/assets/slice/v072_collectibles.glb — 32 named multi-material meshes (`loot_<art_id>`),
   grounded at z=0, centered on x=y=0, normalized for tabletop & 3D turntable inspection.
2. game/assets/icons/loot/<art_id>.png — 32 crisp 256x256 transparent-background studio-lit
   Cycles renders from hero 3/4 camera angles matching each 3D model 1:1.
3. docs/v072-review/contact_sheet_32_icons.png — 4x8 labeled visual audit contact sheet.
4. docs/slice-v072-collectibles.json — per-item geometry & icon metrics.

Run with:
  blender --background --python tools/build_v072_collectibles.py
"""

from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
TEX_DIR = ROOT / "tools" / "generated_v072"
GLB_OUT = ROOT / "game" / "assets" / "slice" / "v072_collectibles.glb"
ICON_DIR = ROOT / "game" / "assets" / "icons" / "loot"
REVIEW_DIR = ROOT / "docs" / "v080-review"
REPORT_OUT = ROOT / "docs" / "slice-v080-collectibles.json"

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
    tex_name: str | None = None,
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
        mat.blend_method = "BLEND" if hasattr(mat, "blend_method") else "HASHED"
    if tex_name:
        tp = TEX_DIR / tex_name
        if tp.exists():
            tnode = nt.nodes.new("ShaderNodeTexImage")
            tnode.image = bpy.data.images.load(str(tp), check_existing=True)
            tnode.image.pack()
            nt.links.new(tnode.outputs["Color"], bsdf.inputs["Base Color"])
            if emission_strength > 0.0 and emission is None and "Emission Color" in bsdf.inputs:
                nt.links.new(tnode.outputs["Color"], bsdf.inputs["Emission Color"])
                bsdf.inputs["Emission Strength"].default_value = emission_strength
    if emission is not None and emission_strength > 0.0 and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = hex_lin(emission)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    MAT_CACHE[name] = mat
    return mat


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MAT_CACHE.clear()


class PartBuilder:
    """Accumulates sculpted parts with per-part materials into one clean named mesh."""

    def __init__(self, name: str):
        self.name = name
        self.objs: list[bpy.types.Object] = []

    def _finish_bm(
        self,
        bm: bmesh.types.BMesh,
        mat: bpy.types.Material,
        smooth: bool = True,
        uv_mode: str = "box",
        xform: Matrix | None = None,
    ) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if xform is not None:
            bmesh.ops.transform(bm, matrix=xform, verts=bm.verts)
        uv_layer = bm.loops.layers.uv.verify()
        if uv_mode == "box":
            _uv_box(bm, uv_layer)
        elif uv_mode == "planar_z":
            _uv_planar(bm, uv_layer, axis="z")
        elif uv_mode == "planar_y":
            _uv_planar(bm, uv_layer, axis="y")
        elif uv_mode == "cyl":
            _uv_cyl(bm, uv_layer)
        # else: caller already assigned UVs

        mesh = bpy.data.meshes.new(self.name + "_part")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(mat)
        for poly in mesh.polygons:
            poly.use_smooth = smooth
        obj = bpy.data.objects.new(self.name + "_part", mesh)
        bpy.context.scene.collection.objects.link(obj)
        self.objs.append(obj)
        return obj

    def box(
        self,
        size: tuple[float, float, float],
        pos: tuple[float, float, float] = (0, 0, 0),
        rot: tuple[float, float, float] = (0, 0, 0),
        mat: bpy.types.Material | None = None,
        bevel: float = 0.0,
        bevel_segs: int = 2,
        smooth: bool = False,
        uv_mode: str = "box",
    ):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        if bevel > 0.0:
            bmesh.ops.bevel(
                bm,
                geom=list(bm.edges),
                offset=bevel,
                segments=bevel_segs,
                affect="EDGES",
                clamp_overlap=True,
            )
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth or bevel > 0.0, uv_mode=uv_mode, xform=xf)

    def cyl(
        self,
        r_bot: float,
        r_top: float,
        height: float,
        segs: int = 24,
        pos: tuple[float, float, float] = (0, 0, 0),
        rot: tuple[float, float, float] = (0, 0, 0),
        mat: bpy.types.Material | None = None,
        cap: bool = True,
        smooth: bool = True,
        uv_mode: str = "cyl",
    ):
        bm = bmesh.new()
        bmesh.ops.create_cone(
            bm,
            cap_ends=cap,
            cap_tris=False,
            segments=segs,
            radius1=r_bot,
            radius2=r_top,
            depth=height,
        )
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode=uv_mode, xform=xf)

    def sphere(
        self,
        radius: float | tuple[float, float, float],
        pos: tuple[float, float, float] = (0, 0, 0),
        rot: tuple[float, float, float] = (0, 0, 0),
        mat: bpy.types.Material | None = None,
        segs: int = 20,
        rings: int = 12,
        smooth: bool = True,
        uv_mode: str = "box",
    ):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
        sc = Vector(radius) if isinstance(radius, tuple) else Vector((radius, radius, radius))
        bmesh.ops.scale(bm, vec=sc, verts=bm.verts)
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode=uv_mode, xform=xf)

    def ico(
        self,
        radius: float | tuple[float, float, float],
        subdiv: int = 1,
        pos: tuple[float, float, float] = (0, 0, 0),
        rot: tuple[float, float, float] = (0, 0, 0),
        mat: bpy.types.Material | None = None,
        smooth: bool = False,
    ):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
        sc = Vector(radius) if isinstance(radius, tuple) else Vector((radius, radius, radius))
        bmesh.ops.scale(bm, vec=sc, verts=bm.verts)
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode="box", xform=xf)

    def torus(
        self,
        major_r: float,
        minor_r: float,
        major_segs: int = 28,
        minor_segs: int = 12,
        pos: tuple[float, float, float] = (0, 0, 0),
        rot: tuple[float, float, float] = (0, 0, 0),
        mat: bpy.types.Material | None = None,
        arc_deg: float = 360.0,
        scale_vec: tuple[float, float, float] = (1.0, 1.0, 1.0),
        smooth: bool = True,
        uv_mode: str = "box",
    ):
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
                v = bm.verts.new((rr * ct * scale_vec[0], rr * st * scale_vec[1], minor_r * sp * scale_vec[2]))
                ring.append(v)
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
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode=uv_mode, xform=xf)

    def lathe(
        self,
        profile: list[tuple[float, float]],
        segs: int = 32,
        flute_lobes: int = 0,
        flute_amp: float = 0.0,
        pos: tuple[float, float, float] = (0, 0, 0),
        rot: tuple[float, float, float] = (0, 0, 0),
        mat: bpy.types.Material | None = None,
        smooth: bool = True,
        uv_mode: str = "cyl",
    ):
        """Revolve (radius, z) profile around Z axis with optional lotus-petal fluting."""
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
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode=uv_mode, xform=xf)

    def tube_path(
        self,
        pts: list[tuple[float, float, float]],
        radii: list[float] | float,
        segs: int = 10,
        mat: bpy.types.Material | None = None,
        cap: bool = True,
        smooth: bool = True,
    ):
        """Sweep circular cross-section along 3D polyline points (handles, spouts, dragons, stems)."""
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
                v = bm.verts.new(p + (n * math.cos(a) + b * math.sin(a)) * rad)
                ring.append(v)
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

    def flat_disc_ring(
        self,
        r_in: float,
        r_out: float,
        thickness: float,
        segs: int = 40,
        arc_deg: float = 360.0,
        pos: tuple[float, float, float] = (0, 0, 0),
        rot: tuple[float, float, float] = (0, 0, 0),
        mat: bpy.types.Material | None = None,
        bevel: float = 0.004,
        smooth: bool = True,
        uv_mode: str = "planar_z",
    ):
        """Crisp flattened ceremonial disc / jade huang arc (ZERO donut roundness!)."""
        bm = bmesh.new()
        closed = arc_deg >= 359.5
        steps = segs if closed else segs + 1
        hz = thickness * 0.5
        top_in, top_out, bot_in, bot_out = [], [], [], []
        for i in range(steps):
            a = math.radians(arc_deg) * (i / float(segs))
            ca, sa = math.cos(a), math.sin(a)
            top_in.append(bm.verts.new((r_in * ca, r_in * sa, hz)))
            top_out.append(bm.verts.new((r_out * ca, r_out * sa, hz)))
            bot_in.append(bm.verts.new((r_in * ca, r_in * sa, -hz)))
            bot_out.append(bm.verts.new((r_out * ca, r_out * sa, -hz)))
        n = len(top_in)
        for i in range(n - (0 if closed else 1)):
            inext = (i + 1) % n
            bm.faces.new((top_in[i], top_out[i], top_out[inext], top_in[inext]))
            bm.faces.new((bot_out[i], bot_in[i], bot_in[inext], bot_out[inext]))
            bm.faces.new((bot_out[i], bot_out[inext], top_out[inext], top_out[i]))
            bm.faces.new((top_in[i], top_in[inext], bot_in[inext], bot_in[i]))
        if not closed:
            bm.faces.new((bot_in[0], bot_out[0], top_out[0], top_in[0]))
            bm.faces.new((bot_out[-1], bot_in[-1], top_in[-1], top_out[-1]))
        if bevel > 0.0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES", clamp_overlap=True)
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=smooth, uv_mode=uv_mode, xform=xf)

    def quad_card(
        self,
        width: float,
        height: float,
        pos: tuple[float, float, float],
        rot: tuple[float, float, float],
        mat: bpy.types.Material,
        thickness: float = 0.004,
    ):
        """Thin UV-exact rectangular plaque (full 0..1 UV on front face facing -Y)."""
        bm = bmesh.new()
        hw, hh, ht = width * 0.5, height * 0.5, thickness * 0.5
        v0 = bm.verts.new((-hw, -ht, -hh))
        v1 = bm.verts.new((hw, -ht, -hh))
        v2 = bm.verts.new((hw, -ht, hh))
        v3 = bm.verts.new((-hw, -ht, hh))
        v4 = bm.verts.new((-hw, ht, -hh))
        v5 = bm.verts.new((hw, ht, -hh))
        v6 = bm.verts.new((hw, ht, hh))
        v7 = bm.verts.new((-hw, ht, hh))
        f_front = bm.faces.new((v0, v1, v2, v3))
        f_back = bm.faces.new((v5, v4, v7, v6))
        bm.faces.new((v4, v0, v3, v7))
        bm.faces.new((v1, v5, v6, v2))
        bm.faces.new((v3, v2, v6, v7))
        bm.faces.new((v4, v5, v1, v0))
        uv_layer = bm.loops.layers.uv.verify()
        _uv_box(bm, uv_layer)
        uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for loop, uv in zip(f_front.loops, uvs):
            loop[uv_layer].uv = uv
        for loop, uv in zip(f_back.loops, uvs):
            loop[uv_layer].uv = uv
        xf = Matrix.Translation(pos) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
        return self._finish_bm(bm, mat, smooth=False, uv_mode="custom", xform=xf)

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

        # Normalize scale so max dimension matches target_size, centered in XY, grounded at Z=0
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


def _uv_planar(bm: bmesh.types.BMesh, uv_layer, axis: str = "z"):
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
        for loop in f.loops:
            co = loop.vert.co
            if axis == "z":
                loop[uv_layer].uv = ((co.x - minx) / dx, (co.y - miny) / dy)
            else:
                loop[uv_layer].uv = ((co.x - minx) / dx, (co.z - minz) / dz)


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


# ---------------------------------------------------------------------------
# SHARED MUSEUM MATERIALS
# ---------------------------------------------------------------------------
def mats():
    return {
        "gold": make_mat("m_gold", "e8bd4c", metallic=0.92, roughness=0.20, coat=0.25),
        "gold_deep": make_mat("m_gold_deep", "b88628", metallic=0.88, roughness=0.28),
        "silver": make_mat("m_silver", "d6dde5", metallic=0.92, roughness=0.18),
        "silver_lock": make_mat("m_silver_lock", "bcc8d4", metallic=0.72, roughness=0.32, tex_name="tex_silver_lock.png"),
        "brass": make_mat("m_brass", "c99b42", metallic=0.86, roughness=0.28),
        "copper": make_mat("m_copper", "c96e3b", metallic=0.92, roughness=0.24),
        "bronze_patina": make_mat("m_bronze_patina", "466e5c", metallic=0.66, roughness=0.40),
        "bronze_dark": make_mat("m_bronze_dark", "4d3e28", metallic=0.76, roughness=0.34),
        "gunmetal": make_mat("m_gunmetal", "2c353d", metallic=0.78, roughness=0.32),
        "matte_black": make_mat("m_matte_black", "1c2228", metallic=0.22, roughness=0.56),
        "rubber": make_mat("m_rubber", "202428", metallic=0.0, roughness=0.82),
        "rosewood": make_mat("m_rosewood", "3d1e14", metallic=0.05, roughness=0.32, coat=0.35),
        "wood_warm": make_mat("m_wood_warm", "8a5a32", metallic=0.0, roughness=0.55),
        "bamboo_green": make_mat("m_bamboo_green", "68944a", metallic=0.0, roughness=0.38, coat=0.18),
        "bamboo_aged": make_mat("m_bamboo_aged", "c89c52", metallic=0.0, roughness=0.46),
        "hemp": make_mat("m_hemp", "a8875a", metallic=0.0, roughness=0.85),
        "silk_red": make_mat("m_silk_red", "b5262e", metallic=0.05, roughness=0.42),
        "crimson_gem": make_mat("m_crimson_gem", "e01e34", metallic=0.15, roughness=0.08, emission="ff2b44", emission_strength=0.65, coat=0.8),
        "gold_plasma": make_mat("m_gold_plasma", "ffd15c", metallic=0.25, roughness=0.10, emission="ffbe3b", emission_strength=1.4),
        "cyan_glow": make_mat("m_cyan_glow", "5ef2ff", metallic=0.1, roughness=0.12, emission="4ce8ff", emission_strength=1.6),
        "emerald_lens": make_mat("m_emerald_lens", "1d9e70", metallic=0.45, roughness=0.06, emission="28d99a", emission_strength=0.35, coat=0.9),
        "sapphire_lens": make_mat("m_sapphire_lens", "2b6ad6", metallic=0.50, roughness=0.06, emission="408cff", emission_strength=0.25, coat=0.9),
        "fluorite": make_mat("m_fluorite", "6ae8cf", metallic=0.08, roughness=0.08, emission="56e5c8", emission_strength=0.32, coat=0.85),
        "amber": make_mat("m_amber", "b8540c", metallic=0.06, roughness=0.06, emission="b84c0a", emission_strength=0.06, coat=1.0),
        "slate": make_mat("m_slate", "465056", metallic=0.05, roughness=0.82),
        "taihu": make_mat("m_taihu", "5e6b6e", metallic=0.04, roughness=0.76),
        "jade_dragon": make_mat("m_jade_dragon", "72b092", metallic=0.18, roughness=0.22, coat=0.65),
        "enamel_green": make_mat("m_enamel_green", "1d6e52", metallic=0.15, roughness=0.20, coat=0.6),
        "white_cream": make_mat("m_white_cream", "ece6d6", metallic=0.0, roughness=0.45),
        "cinnabar": make_mat("m_cinnabar", "b5362c", metallic=0.0, roughness=0.62),
        "orange_box": make_mat("m_orange_box", "de4a1a", metallic=0.28, roughness=0.38),
        # Textured materials
        "tex_battery": make_mat("m_tex_battery", "ffffff", metallic=0.25, roughness=0.32, tex_name="tex_battery_wrap.png"),
        "tex_ration": make_mat("m_tex_ration", "ffffff", metallic=0.22, roughness=0.42, tex_name="tex_ration_label.png"),
        "tex_tea": make_mat("m_tex_tea", "ffffff", metallic=0.0, roughness=0.72, tex_name="tex_tea_wrapper.png"),
        "tex_compass": make_mat("m_tex_compass", "ffffff", metallic=0.05, roughness=0.25, tex_name="tex_compass_dial.png", emission_strength=0.22),
        "tex_fan": make_mat("m_tex_fan", "ffffff", metallic=0.0, roughness=0.64, tex_name="tex_fan_painting.png"),
        "tex_radio_lcd": make_mat("m_tex_radio_lcd", "ffffff", metallic=0.05, roughness=0.15, tex_name="tex_radio_screen.png", emission_strength=0.65),
        "tex_chip": make_mat("m_tex_chip", "ffffff", metallic=0.35, roughness=0.28, tex_name="tex_chip_pcb.png"),
        "tex_blackbox": make_mat("m_tex_blackbox", "ffffff", metallic=0.28, roughness=0.34, tex_name="tex_blackbox_label.png"),
        "tex_rubbing": make_mat("m_tex_rubbing", "ffffff", metallic=0.0, roughness=0.76, tex_name="tex_rubbing_scroll.png"),
        "tex_quantum_lcd": make_mat("m_tex_quantum_lcd", "ffffff", metallic=0.05, roughness=0.14, tex_name="tex_quantum_screen.png", emission_strength=0.85),
        "tex_slips": make_mat("m_tex_slips", "ffffff", metallic=0.0, roughness=0.52, tex_name="tex_slips_calligraphy.png"),
        "tex_celadon": make_mat("m_tex_celadon", "ffffff", metallic=0.05, roughness=0.10, tex_name="tex_celadon_glaze.png", coat=0.92),
        "tex_jade": make_mat("m_tex_jade", "ffffff", metallic=0.04, roughness=0.16, tex_name="tex_jade_cloud.png", coat=0.72),
        "tex_ganoderma": make_mat("m_tex_ganoderma", "ffffff", metallic=0.08, roughness=0.16, tex_name="tex_ganoderma_cap.png", coat=0.85),
        "ganoderma_stem": make_mat("m_ganoderma_stem", "541824", metallic=0.08, roughness=0.22, coat=0.75),
        "ganoderma_gill": make_mat("m_ganoderma_gill", "e2be76", metallic=0.0, roughness=0.65),
        "moss": make_mat("m_moss", "4a7840", metallic=0.0, roughness=0.88),
        "led_warm": make_mat("m_led_warm", "fff3c4", metallic=0.1, roughness=0.1, emission="ffe8a0", emission_strength=2.2),
        "red_led": make_mat("m_red_led", "ff3838", metallic=0.1, roughness=0.1, emission="ff3030", emission_strength=1.8),
        # v0.8.0 additional materials for 32 new collectibles (total 64!)
        "clay_stone": make_mat("m_clay_stone", "a69884", metallic=0.0, roughness=0.72),
        "cobalt_blue": make_mat("m_cobalt_blue", "22469c", metallic=0.1, roughness=0.16, coat=0.75),
        "walnut_shell": make_mat("m_walnut_shell", "7a5230", metallic=0.0, roughness=0.68),
        "osmanthus_gold": make_mat("m_osmanthus_gold", "d8a836", metallic=0.05, roughness=0.58),
        "olive_metal": make_mat("m_olive_metal", "4b5c42", metallic=0.45, roughness=0.42),
        "lacquer_red": make_mat("m_lacquer_red", "9e1b1e", metallic=0.08, roughness=0.12, coat=0.92),
        "zisha_clay": make_mat("m_zisha_clay", "8c422c", metallic=0.04, roughness=0.52, coat=0.22),
        "imperial_jade": make_mat("m_imperial_jade", "249e68", metallic=0.06, roughness=0.10, emission="1a8a56", emission_strength=0.18, coat=0.88),
        "kingfisher": make_mat("m_kingfisher", "1ba4c4", metallic=0.25, roughness=0.14, emission="1cc4e8", emission_strength=0.24, coat=0.82),
        "purple_slate": make_mat("m_purple_slate", "443a4c", metallic=0.06, roughness=0.48),
        "yellow_rugged": make_mat("m_yellow_rugged", "dba624", metallic=0.08, roughness=0.44),
        "rope_orange": make_mat("m_rope_orange", "cf5f26", metallic=0.0, roughness=0.78),
        "leather_dark": make_mat("m_leather_dark", "2a221c", metallic=0.04, roughness=0.62),
        "germanium": make_mat("m_germanium", "d87a24", metallic=0.65, roughness=0.08, emission="ff9230", emission_strength=0.42, coat=0.9),
        "tex_ruler": make_mat("m_tex_ruler", "ffffff", metallic=0.0, roughness=0.48, tex_name="tex_bamboo_ruler.png"),
        "tex_blue_cup": make_mat("m_tex_blue_cup", "ffffff", metallic=0.04, roughness=0.10, tex_name="tex_blue_porcelain.png", coat=0.88),
        "tex_herb": make_mat("m_tex_herb", "ffffff", metallic=0.0, roughness=0.35, tex_name="tex_herb_specimen.png", coat=0.45),
        "tex_watch": make_mat("m_tex_watch", "ffffff", metallic=0.05, roughness=0.22, tex_name="tex_pocket_watch.png"),
        "tex_mirror": make_mat("m_tex_mirror", "ffffff", metallic=0.72, roughness=0.24, tex_name="tex_bronze_mirror.png"),
        "tex_pencil_tin": make_mat("m_tex_pencil_tin", "ffffff", metallic=0.32, roughness=0.32, tex_name="tex_pencil_tin.png"),
        "tex_silk": make_mat("m_tex_silk", "ffffff", metallic=0.08, roughness=0.44, tex_name="tex_suzhou_silk.png"),
        "tex_crypto": make_mat("m_tex_crypto", "ffffff", metallic=0.45, roughness=0.26, tex_name="tex_crypto_drive.png", emission_strength=0.20),
        "tex_imperial_bowl": make_mat("m_tex_imperial_bowl", "ffffff", metallic=0.05, roughness=0.08, tex_name="tex_imperial_bowl.png", coat=0.95),
        "tex_inkstone": make_mat("m_tex_inkstone", "ffffff", metallic=0.08, roughness=0.36, tex_name="tex_inkstone_carving.png", coat=0.25),
    }


# ---------------------------------------------------------------------------
# ALL 32 SCULPTED COLLECTIBLE BUILDERS
# ---------------------------------------------------------------------------
def build_battery(M):
    b = PartBuilder("loot_battery")
    b.cyl(0.052, 0.052, 0.24, 28, (0, 0, 0.13), (0, 0, 0), M["tex_battery"])
    b.cyl(0.054, 0.054, 0.016, 28, (0, 0, 0.014), (0, 0, 0), M["gunmetal"])
    b.cyl(0.053, 0.050, 0.018, 28, (0, 0, 0.252), (0, 0, 0), M["rubber"])
    b.cyl(0.022, 0.020, 0.018, 20, (0, 0, 0.268), (0, 0, 0), M["brass"])
    b.torus(0.053, 0.005, 28, 10, (0, 0, 0.22), (0, 0, 0), M["gold"])
    # Secondary leaning spare cell for richer silhouette
    b.cyl(0.044, 0.044, 0.19, 24, (0.095, 0.02, 0.050), (0, 82, -18), M["tex_battery"])
    b.cyl(0.018, 0.016, 0.015, 16, (0.194, -0.012, 0.064), (0, 82, -18), M["brass"])
    return b.finalize(0.32)


def build_ration(M):
    b = PartBuilder("loot_ration")
    # Vacuum-sealed military olive-foil ration pouch with flush crimped top/bottom seals
    b.box((0.195, 0.048, 0.225), (0, 0, 0.135), (-8, 0, 0), M["wood_warm"], bevel=0.016, bevel_segs=3, smooth=True)
    b.box((0.198, 0.010, 0.018), (0, -0.015, 0.254), (-8, 0, 0), M["brass"], bevel=0.002)
    b.box((0.198, 0.010, 0.018), (0, 0.016, 0.018), (-8, 0, 0), M["brass"], bevel=0.002)
    b.quad_card(0.172, 0.190, (0, -0.026, 0.138), (-8, 0, 0), M["tex_ration"], thickness=0.004)
    return b.finalize(0.32)


def build_wire(M):
    b = PartBuilder("loot_wire")
    # Wooden/bakelite spool flanges & hub
    b.cyl(0.135, 0.135, 0.020, 32, (0, 0, 0.012), (0, 0, 0), M["wood_warm"])
    b.cyl(0.135, 0.135, 0.020, 32, (0, 0, 0.168), (0, 0, 0), M["wood_warm"])
    b.cyl(0.052, 0.052, 0.176, 24, (0, 0, 0.090), (0, 0, 0), M["matte_black"])
    b.cyl(0.036, 0.036, 0.184, 20, (0, 0, 0.090), (0, 0, 0), M["brass"])
    # 10 layered metallic copper wire coils
    for row in range(7):
        z = 0.034 + row * 0.0185
        r_maj = 0.098 if row % 2 == 0 else 0.104
        b.torus(r_maj, 0.0105, 30, 10, (0, 0, z), (0, 0, 0), M["copper"])
    # Loose trailing copper lead
    b.tube_path(
        [(0.102, 0.0, 0.11), (0.155, -0.04, 0.09), (0.185, -0.09, 0.045), (0.155, -0.14, 0.018)],
        0.0085, 10, M["copper"]
    )
    return b.finalize(0.32)


def build_tea(M):
    b = PartBuilder("loot_tea")
    # Classic compressed Jiangnan spring tea cake resting tilted slightly on bamboo stand
    b.lathe(
        [(0.015, 0.0), (0.125, 0.0), (0.152, 0.016), (0.155, 0.036), (0.142, 0.052), (0.045, 0.056), (0.018, 0.046)],
        segs=36, pos=(0, 0, 0.155), rot=(74, 0, 0), mat=M["tex_tea"], uv_mode="planar_z"
    )
    # Minimal bamboo easel rest behind it so it faces camera handsomely
    b.box((0.12, 0.016, 0.14), (0, 0.048, 0.072), (-18, 0, 0), M["bamboo_aged"], bevel=0.003)
    b.box((0.14, 0.085, 0.016), (0, 0.020, 0.008), (0, 0, 0), M["bamboo_aged"], bevel=0.003)
    # Red wax seal medallion on front face
    b.cyl(0.026, 0.026, 0.008, 20, (0, -0.025, 0.115), (74, 0, 0), M["cinnabar"])
    return b.finalize(0.32)


def build_bamboo(M):
    b = PartBuilder("loot_bamboo")
    # Angled carved green bamboo whistle tube
    ang = (0, 68, -16)
    b.cyl(0.032, 0.030, 0.28, 24, (0, 0, 0.085), ang, M["bamboo_green"])
    # Bamboo nodal rings
    for off in (-0.06, 0.06):
        vx = off * math.sin(math.radians(68))
        vz = 0.085 + off * math.cos(math.radians(68))
        b.torus(0.033, 0.006, 24, 10, (vx, 0, vz), ang, M["bamboo_aged"])
    # Carved dark mouthpiece slot & tone hole
    b.box((0.022, 0.022, 0.024), (-0.075, -0.012, 0.125), ang, M["rosewood"], bevel=0.002)
    b.cyl(0.009, 0.009, 0.032, 14, (0.015, -0.012, 0.095), (90, 0, 0), M["matte_black"])
    # Woven hemp lanyard loop + wooden bead
    b.tube_path(
        [(0.125, -0.02, 0.036), (0.165, -0.04, 0.055), (0.18, 0.03, 0.065), (0.14, 0.05, 0.038), (0.122, 0.01, 0.036)],
        0.0055, 8, M["hemp"]
    )
    b.sphere(0.016, (0.174, -0.01, 0.062), (0, 0, 0), M["wood_warm"])
    return b.finalize(0.33)


def build_compass(M):
    b = PartBuilder("loot_compass")
    # Lower antique brass compass case + knurled bezel
    b.cyl(0.118, 0.122, 0.036, 36, (0, 0, 0.022), (0, 0, 0), M["brass"])
    b.torus(0.118, 0.012, 36, 12, (0, 0, 0.042), (0, 0, 0), M["gold"])
    # Dial face with compass rose texture
    b.cyl(0.105, 0.105, 0.006, 32, (0, 0, 0.043), (0, 0, 0), M["tex_compass"], uv_mode="planar_z")
    # Raised 3D magnetic needle (red north / cream south)
    b.box((0.014, 0.078, 0.007), (0, 0.036, 0.050), (0, 0, -24), M["crimson_gem"], bevel=0.001)
    b.box((0.014, 0.078, 0.007), (0, -0.036, 0.050), (0, 0, -24), M["white_cream"], bevel=0.001)
    b.cyl(0.012, 0.010, 0.016, 16, (0, 0, 0.050), (0, 0, 0), M["gold"])
    # Open hinged brass lid (tilted back 108 deg) with sighting window & brass wire
    b.cyl(0.014, 0.014, 0.054, 16, (0, 0.122, 0.042), (0, 90, 0), M["brass"])
    b.flat_disc_ring(0.068, 0.116, 0.014, 32, 360.0, (0, 0.145, 0.148), (105, 0, 0), M["brass"], bevel=0.003)
    b.cyl(0.003, 0.003, 0.15, 8, (0, 0.145, 0.148), (15, 0, 0), M["gold"])
    # Thumb loop at front
    b.torus(0.038, 0.007, 20, 10, (0, -0.145, 0.024), (12, 0, 0), M["brass"])
    return b.finalize(0.34)


def build_torch(M):
    b = PartBuilder("loot_torch")
    # Angled tactical flashlight body resting cleanly
    ang = (18, 76, -24)
    # Main barrel + flared reflector head
    b.lathe(
        [(0.036, -0.16), (0.038, -0.13), (0.034, -0.03), (0.036, 0.04), (0.052, 0.075), (0.058, 0.145), (0.050, 0.148), (0.044, 0.105)],
        segs=28, pos=(0, 0, 0.085), rot=ang, mat=M["gunmetal"]
    )
    # Grip knurl rings + tactical red power switch
    for z_off in (-0.08, -0.04, 0.0, 0.048):
        p = Euler(tuple(math.radians(a) for a in ang), "XYZ").to_matrix() @ Vector((0, 0, z_off)) + Vector((0, 0, 0.085))
        b.torus(0.039 if z_off < 0.03 else 0.049, 0.0045, 24, 8, tuple(p), ang, M["matte_black"])
    # Glowing LED lens emitter in front
    p_led = Euler(tuple(math.radians(a) for a in ang), "XYZ").to_matrix() @ Vector((0, 0, 0.125)) + Vector((0, 0, 0.085))
    b.sphere(0.034, tuple(p_led), ang, M["led_warm"])
    # Brass strike bezel ring + red side switch + pocket clip
    p_bez = Euler(tuple(math.radians(a) for a in ang), "XYZ").to_matrix() @ Vector((0, 0, 0.146)) + Vector((0, 0, 0.085))
    b.torus(0.055, 0.006, 24, 10, tuple(p_bez), ang, M["brass"])
    p_sw = Euler(tuple(math.radians(a) for a in ang), "XYZ").to_matrix() @ Vector((0, -0.042, 0.042)) + Vector((0, 0, 0.085))
    b.sphere(0.011, tuple(p_sw), (0, 0, 0), M["red_led"])
    return b.finalize(0.34)


def build_badge(M):
    b = PartBuilder("loot_badge")
    # Heraldic forest-ranger shield crest standing slightly tilted on clasp foot
    bm = bmesh.new()
    pts = [(-0.11, 0.13), (0.0, 0.155), (0.11, 0.13), (0.115, 0.01), (0.078, -0.095), (0.0, -0.155), (-0.078, -0.095), (-0.115, 0.01)]
    front_v = [bm.verts.new((x, -0.016, z + 0.16)) for x, z in pts]
    back_v = [bm.verts.new((x, 0.016, z + 0.16)) for x, z in pts]
    bm.faces.new(front_v)
    bm.faces.new(list(reversed(back_v)))
    n = len(pts)
    for i in range(n):
        inext = (i + 1) % n
        bm.faces.new((back_v[i], back_v[inext], front_v[inext], front_v[i]))
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.006, segments=2, affect="EDGES", clamp_overlap=True)
    b._finish_bm(bm, M["gold"], smooth=True, xform=Matrix.Rotation(math.radians(-10), 4, "X"))

    # Recessed forest-emerald enamel shield face
    bm2 = bmesh.new()
    f2 = [bm2.verts.new((x * 0.80, -0.020, z * 0.80 + 0.16)) for x, z in pts]
    b2 = [bm2.verts.new((x * 0.80, -0.010, z * 0.80 + 0.16)) for x, z in pts]
    bm2.faces.new(f2)
    bm2.faces.new(list(reversed(b2)))
    for i in range(n):
        inext = (i + 1) % n
        bm2.faces.new((b2[i], b2[inext], f2[inext], f2[i]))
    b._finish_bm(bm2, M["enamel_green"], smooth=False, xform=Matrix.Rotation(math.radians(-10), 4, "X"))

    # Raised golden camphor leaf & mountain emblem on shield front
    b.sphere((0.036, 0.010, 0.068), (0, -0.025, 0.175), (-10, 0, 14), M["gold"])
    b.sphere((0.032, 0.010, 0.056), (-0.025, -0.024, 0.155), (-10, 0, -28), M["gold"])
    b.cyl(0.006, 0.004, 0.11, 10, (0, -0.027, 0.165), (-10, 0, 0), M["gold_deep"])
    # Top star crown
    b.ico(0.022, 1, (0, -0.022, 0.278), (0, 0, 0), M["gold"])
    return b.finalize(0.32)


def build_fan(M):
    b = PartBuilder("loot_fan")
    # Open 130-degree arched Jiangnan folding fan with 13 carved bamboo ribs & pleated Xuan paper leaf!
    n_ribs = 13
    arc_span = math.radians(128.0)
    r_inner = 0.115
    r_outer = 0.265
    pivot = Vector((0.0, 0.0, 0.055))
    tilt = Matrix.Rotation(math.radians(-12), 4, "X")

    # 13 bamboo ribs + thicker guard sticks
    for i in range(n_ribs):
        t = i / float(n_ribs - 1)
        a = -0.5 * arc_span + t * arc_span
        is_guard = (i == 0 or i == n_ribs - 1)
        rib_w = 0.012 if is_guard else 0.0055
        rib_d = 0.009 if is_guard else 0.0045
        mid_r = r_outer * 0.50
        pos = Vector((mid_r * math.sin(a), 0.002 * (1 if i % 2 == 0 else -1), pivot.z + mid_r * math.cos(a)))
        b.box((rib_w, rib_d, r_outer * 0.96), tuple(pos), (-12, math.degrees(a), 0), M["rosewood" if is_guard else "bamboo_aged"], bevel=0.001)

    # Pleated painted paper fan leaf (exact UV mapping to tex_fan_painting.png!)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()
    n_segs = 24
    inner_v, outer_v = [], []
    for i in range(n_segs + 1):
        t = i / float(n_segs)
        a = -0.5 * arc_span + t * arc_span
        pleat_y = 0.009 if (i % 2 == 0) else -0.009
        inner_v.append(bm.verts.new((r_inner * math.sin(a), pleat_y, pivot.z + r_inner * math.cos(a))))
        outer_v.append(bm.verts.new((r_outer * math.sin(a), pleat_y, pivot.z + r_outer * math.cos(a))))
    for i in range(n_segs):
        u0 = i / float(n_segs)
        u1 = (i + 1) / float(n_segs)
        f = bm.faces.new((inner_v[i], inner_v[i + 1], outer_v[i + 1], outer_v[i]))
        for loop, uv in zip(f.loops, [(u0, 0.0), (u1, 0.0), (u1, 1.0), (u0, 1.0)]):
            loop[uv_layer].uv = uv
    b._finish_bm(bm, M["tex_fan"], smooth=False, uv_mode="custom", xform=tilt)

    # Brass pivot rivet + crimson silk tassel
    b.cyl(0.012, 0.012, 0.022, 16, (0, 0, 0.055), (78, 0, 0), M["brass"])
    b.sphere(0.013, (0.02, -0.015, 0.032), (0, 0, 0), M["silk_red"])
    b.cyl(0.014, 0.005, 0.052, 12, (0.032, -0.020, 0.006), (0, -20, 0), M["silk_red"])
    return b.finalize(0.36)


def build_gem(M):
    b = PartBuilder("loot_gem")
    # Rough dark river-slate rock matrix base
    b.ico((0.14, 0.11, 0.055), 2, (0, 0, 0.042), (6, -4, 15), M["slate"], smooth=False)
    # 7 intersecting hexagonal prismatic translucent aqua-mint fluorite crystal spires!
    crystals = [
        ((0.0, 0.0, 0.14), (0, 6, 12), 0.036, 0.20),
        ((-0.055, -0.025, 0.12), (-14, -22, 24), 0.028, 0.16),
        ((0.058, -0.018, 0.11), (-10, 26, -15), 0.026, 0.15),
        ((-0.022, 0.048, 0.115), (20, -10, 40), 0.024, 0.145),
        ((0.042, 0.042, 0.095), (18, 22, 8), 0.020, 0.115),
        ((-0.075, 0.028, 0.080), (8, -36, 5), 0.018, 0.095),
        ((0.012, -0.056, 0.088), (-28, 8, 30), 0.020, 0.10),
    ]
    for pos, rot, rad, h in crystals:
        # Hexagonal prism shaft + faceted pyramidal apex
        b.lathe(
            [(rad, -h * 0.45), (rad * 0.94, h * 0.30), (0.002, h * 0.55)],
            segs=6, pos=pos, rot=rot, mat=M["fluorite"], smooth=False
        )
    return b.finalize(0.34)


def build_radio(M):
    b = PartBuilder("loot_radio")
    # Rugged tactical transceiver chassis
    b.box((0.115, 0.058, 0.205), (0, 0, 0.105), (0, 0, 0), M["gunmetal"], bevel=0.010, bevel_segs=2)
    # Corner rubber side bumpers
    for sx in (-0.058, 0.058):
        b.box((0.014, 0.062, 0.185), (sx, 0, 0.105), (0, 0, 0), M["rubber"], bevel=0.004)
    # Illuminated green LCD frequency screen
    b.quad_card(0.088, 0.048, (0, -0.031, 0.156), (0, 0, 0), M["tex_radio_lcd"], thickness=0.003)
    # Speaker grille slots
    for row in range(3):
        b.box((0.078, 0.006, 0.008), (0, -0.030, 0.108 - row * 0.014), (0, 0, 0), M["matte_black"])
    # 9 tactile keypad buttons
    for r in range(3):
        for c in range(3):
            b.box((0.018, 0.008, 0.014), (-0.026 + c * 0.026, -0.031, 0.064 - r * 0.020), (0, 0, 0), M["rubber"], bevel=0.002)
    # Rotary knobs + stubby GPS + tall whip antenna
    b.cyl(0.014, 0.012, 0.026, 16, (0.030, 0.0, 0.218), (0, 0, 0), M["brass"])
    b.cyl(0.012, 0.010, 0.022, 16, (-0.002, 0.0, 0.216), (0, 0, 0), M["matte_black"])
    b.cyl(0.011, 0.004, 0.175, 14, (-0.036, 0.0, 0.295), (0, 0, 0), M["rubber"])
    b.sphere(0.007, (-0.036, 0.0, 0.382), (0, 0, 0), M["brass"])
    return b.finalize(0.36)


def build_rangefinder(M):
    b = PartBuilder("loot_rangefinder")
    # Stepped dark-titanium dual-barrel laser rangefinder housing
    b.box((0.155, 0.195, 0.095), (0, 0, 0.068), (0, 0, 0), M["gunmetal"], bevel=0.012, bevel_segs=2)
    b.box((0.120, 0.130, 0.032), (0, 0.01, 0.125), (0, 0, 0), M["matte_black"], bevel=0.006)
    # Picatinny bottom rail mount
    b.box((0.072, 0.140, 0.022), (0, 0, 0.014), (0, 0, 0), M["matte_black"], bevel=0.003)
    # Primary sapphire-coated receiver lens + recessed sunshade hood
    b.cyl(0.044, 0.040, 0.048, 28, (-0.036, -0.105, 0.070), (90, 0, 0), M["matte_black"])
    b.cyl(0.034, 0.034, 0.010, 28, (-0.036, -0.118, 0.070), (90, 0, 0), M["sapphire_lens"])
    b.torus(0.042, 0.005, 28, 10, (-0.036, -0.128, 0.070), (90, 0, 0), M["brass"])
    # Secondary crimson laser emitter lens
    b.cyl(0.026, 0.024, 0.040, 22, (0.044, -0.102, 0.072), (90, 0, 0), M["gunmetal"])
    b.cyl(0.018, 0.018, 0.010, 20, (0.044, -0.115, 0.072), (90, 0, 0), M["crimson_gem"])
    # Top elevation knob & status LED
    b.cyl(0.018, 0.016, 0.022, 18, (-0.030, 0.02, 0.148), (0, 0, 0), M["brass"])
    b.sphere(0.009, (0.036, -0.035, 0.142), (0, 0, 0), M["red_led"])
    return b.finalize(0.34)


def build_amber(M):
    b = PartBuilder("loot_amber")
    # Ornate carved rosewood specimen plinth with brass bezel collar
    b.cyl(0.095, 0.084, 0.032, 24, (0, 0, 0.016), (0, 0, 0), M["rosewood"])
    b.torus(0.088, 0.007, 24, 10, (0, 0, 0.032), (0, 0, 0), M["brass"])
    # Sculpted faceted-organic honey-cognac amber crystal nugget (distinct from egg!)
    b.ico((0.105, 0.068, 0.132), 2, (0, 0, 0.148), (6, -12, 14), M["amber"], smooth=False)
    b.ico((0.068, 0.052, 0.088), 2, (0.048, -0.012, 0.118), (-8, 18, -12), M["amber"], smooth=True)
    # Recessed fossil pine-fern relief silhouette inside polished front facet
    b.box((0.010, 0.008, 0.085), (0.0, -0.066, 0.155), (4, 18, 0), M["rosewood"], bevel=0.002)
    for k in range(3):
        dz = 0.132 + k * 0.022
        b.box((0.046 - k * 0.008, 0.006, 0.007), (0.004, -0.068, dz), (4, 24, 0), M["rosewood"])
    return b.finalize(0.34)


def build_nvg_lens(M):
    b = PartBuilder("loot_nvg_lens")
    # Stepped military night-vision optical assembly barrel tilted towards viewer
    ang = (66, 0, -14)
    b.lathe(
        [
            (0.078, -0.11), (0.082, -0.09), (0.082, -0.04), (0.092, -0.035),
            (0.092, 0.015), (0.085, 0.02), (0.088, 0.075), (0.096, 0.082),
            (0.096, 0.125), (0.080, 0.125), (0.072, 0.095)
        ],
        segs=32, pos=(0, 0, 0.125), rot=ang, mat=M["matte_black"]
    )
    # Knurled brass calibration collar ring
    p_ring = Euler(tuple(math.radians(a) for a in ang), "XYZ").to_matrix() @ Vector((0, 0, -0.008)) + Vector((0, 0, 0.125))
    b.torus(0.094, 0.008, 32, 10, tuple(p_ring), ang, M["brass"])
    # Deep emerald-iridescent coated objective glass dome
    p_lens = Euler(tuple(math.radians(a) for a in ang), "XYZ").to_matrix() @ Vector((0, 0, 0.098)) + Vector((0, 0, 0.125))
    b.sphere((0.076, 0.076, 0.026), tuple(p_lens), ang, M["emerald_lens"])
    # Hinged open rubber flip cap on top
    b.cyl(0.076, 0.076, 0.014, 24, (0.01, -0.01, 0.252), (-22, 0, -14), M["rubber"])
    return b.finalize(0.34)


def build_rock(M):
    b = PartBuilder("loot_rock")
    # Ornate carved rosewood 4-leg scholar stand
    b.box((0.20, 0.13, 0.024), (0, 0, 0.042), (0, 0, 0), M["rosewood"], bevel=0.005)
    for sx in (-0.082, 0.082):
        for sy in (-0.048, 0.048):
            b.box((0.024, 0.024, 0.044), (sx, sy, 0.022), (0, 0, 0), M["rosewood"], bevel=0.003)
    # Sculpted Taihu Scholar Rock with genuine arched loops forming 3 eroded holes!
    b.tube_path(
        [(-0.07, 0.0, 0.052), (-0.095, -0.015, 0.135), (-0.045, 0.01, 0.225), (0.045, -0.01, 0.268), (0.090, 0.015, 0.185), (0.068, 0.0, 0.052)],
        [0.036, 0.032, 0.038, 0.042, 0.032, 0.038], 10, M["taihu"], smooth=False
    )
    # Secondary inner karst bridge dividing the central cavity into multiple eroded holes
    b.tube_path(
        [(-0.068, 0.0, 0.125), (-0.005, -0.018, 0.155), (0.072, 0.012, 0.138)],
        [0.026, 0.024, 0.025], 9, M["taihu"], smooth=False
    )
    b.tube_path(
        [(-0.015, 0.005, 0.155), (0.012, -0.012, 0.245), (0.042, 0.0, 0.305)],
        [0.024, 0.030, 0.022], 9, M["taihu"], smooth=False
    )
    # Subtle moss tufts nestled in crevices
    b.ico((0.032, 0.022, 0.014), 1, (-0.03, -0.025, 0.165), (0, 0, 0), M["moss"])
    return b.finalize(0.36)


def build_chip(M):
    b = PartBuilder("loot_chip")
    # Angled dark-emerald PCB board with golden traces texture
    ang = (-56, 0, 0)
    b.box((0.22, 0.22, 0.018), (0, 0, 0.115), ang, M["tex_chip"], bevel=0.004, uv_mode="planar_z")
    # Raised chamfered obsidian silicon heat-spreader die + golden frame
    b.box((0.118, 0.118, 0.026), (0, -0.014, 0.124), ang, M["gunmetal"], bevel=0.005)
    b.box((0.088, 0.088, 0.032), (0, -0.018, 0.126), ang, M["matte_black"], bevel=0.004)
    # 24 gleaming gold perimeter contact pins along all 4 sides
    rot_m = Euler(tuple(math.radians(a) for a in ang), "XYZ").to_matrix()
    center = Vector((0, 0, 0.115))
    for i in range(6):
        off = -0.075 + i * 0.030
        for local_p, sz in [
            (Vector((off, 0.118, 0.0)), (0.010, 0.024, 0.006)),
            (Vector((off, -0.118, 0.0)), (0.010, 0.024, 0.006)),
            (Vector((0.118, off, 0.0)), (0.024, 0.010, 0.006)),
            (Vector((-0.118, off, 0.0)), (0.024, 0.010, 0.006)),
        ]:
            wp = center + rot_m @ local_p
            b.box(sz, tuple(wp), ang, M["gold"])
    # 4 glowing cyan corner micro-LEDs
    for sx in (-0.052, 0.052):
        for sy in (-0.052, 0.052):
            wp = center + rot_m @ Vector((sx, sy, 0.018))
            b.sphere(0.009, tuple(wp), (0, 0, 0), M["cyan_glow"])
    return b.finalize(0.34)


def build_jade_piece(M):
    b = PartBuilder("loot_jade_piece")
    # Graceful arched C-shaped antique Jade Huang (玉璜) crescent fragment (145 deg flat arc!)
    b.flat_disc_ring(
        r_in=0.095, r_out=0.168, thickness=0.024, segs=32, arc_deg=142.0,
        pos=(0, 0, 0.062), rot=(78, 0, 19), mat=M["tex_jade"], bevel=0.005, uv_mode="planar_z"
    )
    # Aged reddish-cinnabar mineral patina band along one broken tip
    b.box((0.072, 0.028, 0.026), (-0.115, -0.008, 0.142), (78, 0, 22), M["cinnabar"], bevel=0.004)
    # Dark rosewood miniature curved cradle base
    b.box((0.16, 0.056, 0.024), (0, 0.008, 0.014), (0, 0, 0), M["rosewood"], bevel=0.004)
    b.box((0.022, 0.048, 0.062), (-0.062, 0.008, 0.042), (0, 12, 0), M["rosewood"], bevel=0.003)
    b.box((0.022, 0.048, 0.062), (0.062, 0.008, 0.042), (0, -12, 0), M["rosewood"], bevel=0.003)
    # Braided crimson silk suspension cord & bead at upper pinhole
    b.tube_path(
        [(0.095, -0.014, 0.175), (0.132, -0.022, 0.145), (0.140, -0.010, 0.095)],
        0.005, 8, M["silk_red"]
    )
    b.sphere(0.012, (0.138, -0.012, 0.092), (0, 0, 0), M["gold"])
    return b.finalize(0.34)


def build_blackbox(M):
    b = PartBuilder("loot_blackbox")
    # Heavy-duty crash-survivable safety-orange flight recorder
    b.box((0.23, 0.155, 0.155), (0, 0, 0.092), (0, 0, 0), M["orange_box"], bevel=0.010, bevel_segs=2)
    b.quad_card(0.205, 0.130, (0, -0.079, 0.092), (0, 0, 0), M["tex_blackbox"], thickness=0.003)
    b.quad_card(0.205, 0.130, (0, 0.079, 0.092), (0, 0, 180), M["tex_blackbox"], thickness=0.003)
    # 8 heavy armored black corner bumpers
    for sx in (-0.112, 0.112):
        for sy in (-0.074, 0.074):
            for sz in (0.018, 0.166):
                b.box((0.032, 0.032, 0.032), (sx, sy, sz), (0, 0, 0), M["rubber"], bevel=0.005)
    # Brushed stainless steel top carry handle
    b.tube_path(
        [(-0.075, 0.0, 0.170), (-0.075, 0.0, 0.222), (0.075, 0.0, 0.222), (0.075, 0.0, 0.170)],
        0.011, 12, M["silver"]
    )
    # Front cylindrical silver underwater acoustic beacon (ULB)
    b.cyl(0.022, 0.022, 0.115, 20, (0, -0.096, 0.042), (0, 90, 0), M["silver"])
    b.box((0.014, 0.044, 0.044), (-0.034, -0.088, 0.042), (0, 0, 0), M["matte_black"], bevel=0.002)
    b.box((0.014, 0.044, 0.044), (0.034, -0.088, 0.042), (0, 0, 0), M["matte_black"], bevel=0.002)
    return b.finalize(0.35)


def build_rubbing(M):
    b = PartBuilder("loot_rubbing")
    # Partially unrolled antique Xuan-paper stone-rubbing scroll standing slightly tilted
    tilt = (-16, 0, 0)
    b.quad_card(0.20, 0.26, (0, 0, 0.155), tilt, M["tex_rubbing"], thickness=0.006)
    # Turned dark sandalwood top & bottom scroll rollers + pale jade endcaps
    for z_pos, y_pos, r_rol in ((0.285, 0.036, 0.016), (0.028, -0.036, 0.022)):
        b.cyl(r_rol, r_rol, 0.255, 20, (0, y_pos, z_pos), (0, 90, 0), M["rosewood"])
        for sx in (-0.135, 0.135):
            b.cyl(r_rol * 0.92, r_rol * 0.85, 0.022, 16, (sx, y_pos, z_pos), (0, 90, 0), M["tex_jade"])
    # Hanging silk cord triangle at top
    b.tube_path(
        [(-0.085, 0.036, 0.292), (0.0, 0.044, 0.342), (0.085, 0.036, 0.292)],
        0.0045, 8, M["silk_red"]
    )
    return b.finalize(0.36)


def build_silver_lock(M):
    b = PartBuilder("loot_silver_lock")
    # Sculpted traditional Jiangnan Ruyi-cloud Longevity Silver Lock (长命锁)!
    b.box((0.20, 0.032, 0.135), (0, 0, 0.125), (-8, 0, 0), M["silver_lock"], bevel=0.014, bevel_segs=3, smooth=True, uv_mode="planar_y")
    b.quad_card(0.175, 0.112, (0, -0.018, 0.125), (-8, 0, 0), M["silver_lock"], thickness=0.004)
    # Ruyi cloud corner lobes
    for sx in (-0.095, 0.095):
        b.sphere((0.038, 0.020, 0.046), (sx, 0, 0.145), (-8, 0, 0), M["silver"])
    # Graceful curved silver padlock shackle bail on top
    b.torus(0.082, 0.010, 28, 12, (0, 0.006, 0.178), (82, 0, 0), M["silver"], arc_deg=185.0)
    # Crimson braided silk neck cord + knots
    b.torus(0.098, 0.007, 28, 10, (0, 0.012, 0.215), (82, 0, 0), M["silk_red"], arc_deg=180.0)
    # 3 charming miniature dangling silver bells along the bottom edge!
    for sx, dz in ((-0.068, 0.032), (0.0, 0.022), (0.068, 0.032)):
        b.cyl(0.004, 0.004, 0.024, 8, (sx, -0.005, dz + 0.018), (0, 0, 0), M["silver"])
        b.sphere(0.017, (sx, -0.005, dz), (0, 0, 0), M["silver"])
        b.torus(0.017, 0.003, 14, 8, (sx, -0.005, dz), (0, 0, 0), M["gold"])
    return b.finalize(0.35)


def build_kettle(M):
    b = PartBuilder("loot_kettle")
    # Archaic verdigris bronze tea kettle (先民青铜茶铫)
    b.lathe(
        [(0.045, 0.028), (0.095, 0.045), (0.126, 0.095), (0.118, 0.155), (0.082, 0.195), (0.068, 0.212), (0.078, 0.220), (0.058, 0.214)],
        segs=32, mat=M["bronze_patina"]
    )
    # Decorative raised bronze belly band
    b.torus(0.124, 0.008, 32, 10, (0, 0, 0.115), (0, 0, 0), M["bronze_dark"])
    # Domed lid + lotus-bud finial knob
    b.lathe(
        [(0.066, 0.212), (0.056, 0.236), (0.018, 0.246), (0.008, 0.256), (0.020, 0.272), (0.002, 0.292)],
        segs=24, mat=M["bronze_dark"]
    )
    # Graceful S-curved pouring spout
    b.tube_path(
        [(0.098, 0.0, 0.105), (0.152, 0.0, 0.128), (0.172, 0.0, 0.188), (0.196, 0.0, 0.224)],
        [0.024, 0.019, 0.015, 0.013], 14, M["bronze_patina"]
    )
    # Tall arched forged bronze overhead bail handle
    b.tube_path(
        [(-0.088, 0.0, 0.185), (-0.112, 0.0, 0.285), (0.0, 0.0, 0.345), (0.112, 0.0, 0.285), (0.088, 0.0, 0.185)],
        0.011, 12, M["bronze_dark"]
    )
    # 3 sturdy tripod bronze legs
    for i in range(3):
        a = math.radians(i * 120 + 30)
        b.cyl(0.012, 0.018, 0.044, 12, (0.072 * math.cos(a), 0.072 * math.sin(a), 0.022), (0, 0, 0), M["bronze_dark"])
    return b.finalize(0.36)


def build_tally(M):
    b = PartBuilder("loot_tally")
    # Regal Qin/Warring-States Bronze Tiger Tally (烟山古铜虎符) with angular feline anatomy & inlaid gold!
    b.box((0.26, 0.098, 0.030), (0, 0, 0.015), (0, 0, 0), M["bronze_dark"], bevel=0.005)
    b.box((0.23, 0.100, 0.008), (0, 0, 0.016), (0, 0, 0), M["gold"])
    # Muscular faceted tiger chest, waist & crouched haunches
    b.box((0.082, 0.068, 0.076), (0.056, 0, 0.092), (0, -8, 0), M["bronze_dark"], bevel=0.016, bevel_segs=2)
    b.box((0.092, 0.056, 0.060), (-0.012, 0, 0.096), (0, 6, 0), M["bronze_patina"], bevel=0.014, bevel_segs=2)
    b.box((0.076, 0.068, 0.068), (-0.078, 0, 0.082), (0, 14, 0), M["bronze_dark"], bevel=0.016, bevel_segs=2)
    # Fierce chiseled tiger head, square jaw, ears & golden eyes
    b.box((0.056, 0.058, 0.052), (0.114, 0, 0.128), (0, 8, 0), M["bronze_dark"], bevel=0.012, bevel_segs=2)
    b.box((0.036, 0.040, 0.030), (0.148, 0, 0.116), (0, 10, 0), M["bronze_patina"], bevel=0.006)
    for sy in (-0.022, 0.022):
        b.lathe([(0.012, 0.0), (0.002, 0.024)], segs=4, pos=(0.100, sy, 0.152), mat=M["bronze_dark"], smooth=False)
        b.sphere(0.007, (0.132, sy * 1.15, 0.134), (0, 0, 0), M["gold_plasma"])
        b.box((0.062, 0.024, 0.028), (0.095, sy * 1.25, 0.044), (0, 0, 0), M["bronze_dark"], bevel=0.006)
        b.box((0.062, 0.026, 0.032), (-0.086, sy * 1.25, 0.046), (0, 0, 0), M["bronze_dark"], bevel=0.007)
    # Sweeping archaic curling bronze tail
    b.tube_path(
        [(-0.110, 0, 0.078), (-0.146, 0, 0.128), (-0.122, 0, 0.175), (-0.074, 0, 0.168)],
        [0.013, 0.011, 0.010, 0.008], 10, M["bronze_dark"]
    )
    # Bold inlaid gleaming gold-wire calligraphic stripes & dorsal spine crest!
    for sx in (-0.052, -0.022, 0.008, 0.038, 0.066):
        b.box((0.008, 0.072, 0.056), (sx, 0, 0.098), (0, 0, 0), M["gold"], bevel=0.002)
    b.box((0.155, 0.012, 0.010), (0.0, 0, 0.132), (0, 0, 0), M["gold"])
    return b.finalize(0.36)


def build_medal(M):
    b = PartBuilder("loot_medal")
    tilt = (-12, 0, 0)
    # Crimson & gold silk suspension ribbon with top horizontal gold bar clasp
    b.box((0.105, 0.016, 0.130), (0, 0.012, 0.255), tilt, M["silk_red"], bevel=0.003)
    for sx in (-0.034, 0.034):
        b.box((0.012, 0.018, 0.130), (sx, 0.012, 0.255), tilt, M["gold"])
    b.box((0.124, 0.024, 0.022), (0, 0.022, 0.320), tilt, M["gold"], bevel=0.004)
    # Suspension ring
    b.torus(0.020, 0.005, 16, 8, (0, 0.0, 0.188), (78, 0, 0), M["gold"])
    # 8-pointed sculpted golden starburst medallion!
    for i in range(8):
        ang_y = i * 45.0
        b.lathe(
            [(0.032, 0.0), (0.018, 0.055), (0.002, 0.102)],
            segs=4, pos=(0, -0.010, 0.102), rot=(-12, ang_y, 0), mat=M["gold"], smooth=False
        )
    # Recessed crimson enamel centerpiece + laurel ring + raised central gold star
    b.cyl(0.062, 0.062, 0.022, 28, (0, -0.012, 0.102), (78, 0, 0), M["crimson_gem"])
    b.torus(0.058, 0.009, 28, 10, (0, -0.020, 0.102), (78, 0, 0), M["gold"])
    b.ico(0.028, 1, (0, -0.026, 0.102), (0, 0, 0), M["gold"])
    return b.finalize(0.36)


def build_quantum(M):
    b = PartBuilder("loot_quantum")
    # Sleek folding futuristic bilingual lexicon terminal (brushed gunmetal + gold trim)
    b.box((0.23, 0.165, 0.024), (0, 0, 0.014), (0, 0, 0), M["gunmetal"], bevel=0.006)
    b.box((0.236, 0.170, 0.008), (0, 0, 0.024), (0, 0, 0), M["gold"], bevel=0.002)
    # Illuminated tactile keys on deck base
    for r in range(3):
        for c in range(6):
            b.box((0.026, 0.018, 0.008), (-0.075 + c * 0.030, -0.048 + r * 0.026, 0.028), (0, 0, 0), M["matte_black"], bevel=0.002)
    # Hinged angled holographic display lid
    b.box((0.228, 0.018, 0.152), (0, 0.095, 0.095), (-18, 0, 0), M["gunmetal"], bevel=0.005)
    b.quad_card(0.205, 0.128, (0, 0.084, 0.095), (-18, 0, 0), M["tex_quantum_lcd"], thickness=0.003)
    # Floating faceted cyan-gold holographic acoustic prism hovering above emitter dish!
    b.cyl(0.032, 0.024, 0.012, 20, (0, 0.035, 0.030), (0, 0, 0), M["gold"])
    b.ico((0.032, 0.032, 0.048), 1, (0, 0.032, 0.092), (18, 24, 15), M["cyan_glow"], smooth=False)
    b.torus(0.044, 0.004, 24, 8, (0, 0.032, 0.092), (24, -18, 0), M["gold_plasma"])
    return b.finalize(0.36)


def build_slips(M):
    b = PartBuilder("loot_slips")
    # 11 individual beveled aged bamboo slips fanning in an authentic S-scroll!
    n_slips = 11
    cord_top, cord_bot = [], []
    for i in range(n_slips):
        t = i / float(n_slips - 1)
        if i < 4:
            # Rolled left coil
            a = math.radians(150 - i * 42)
            x = -0.115 + 0.034 * math.cos(a)
            y = 0.034 * math.sin(a)
            yaw = math.degrees(a) - 90
        else:
            # Unfurled gently curved right fan
            u = (i - 3) / float(n_slips - 4)
            x = -0.088 + u * 0.225
            y = 0.022 * math.sin(u * math.pi)
            yaw = -12.0 * math.cos(u * math.pi)
        b.box((0.024, 0.009, 0.255), (x, y, 0.130), (-10, 0, yaw), M["tex_slips"], bevel=0.002, uv_mode="planar_y")
        cord_top.append((x, y - 0.008, 0.205))
        cord_bot.append((x, y - 0.008, 0.062))
    # Twin 3D braided hemp binding cords
    b.tube_path(cord_top, 0.005, 8, M["hemp"])
    b.tube_path(cord_bot, 0.005, 8, M["hemp"])
    return b.finalize(0.36)


def build_core(M):
    b = PartBuilder("loot_core")
    # Multi-layered Warden Golden Fusion Core!
    # Radiant faceted golden plasma heart
    b.ico(0.072, 2, (0, 0, 0.175), (15, 22, 0), M["gold_plasma"], smooth=False)
    # 3 interlocking tilted chamfered titanium-gold gimbal containment rings
    b.torus(0.112, 0.014, 32, 12, (0, 0, 0.175), (28, 18, 0), M["gold"])
    b.torus(0.134, 0.012, 32, 12, (0, 0, 0.175), (-52, 34, 15), M["gunmetal"])
    b.torus(0.148, 0.010, 32, 10, (0, 0, 0.175), (78, -22, 40), M["gold_deep"])
    # 4 radial armored cooling fins + bolted top/bottom magnetic containment caps
    for i in range(4):
        a = math.radians(i * 90 + 45)
        b.box((0.028, 0.065, 0.24), (0.112 * math.cos(a), 0.112 * math.sin(a), 0.175), (0, 0, math.degrees(a) + 90), M["gunmetal"], bevel=0.005)
    b.cyl(0.095, 0.082, 0.036, 8, (0, 0, 0.020), (0, 0, 22.5), M["gunmetal"], smooth=False)
    b.cyl(0.082, 0.095, 0.036, 8, (0, 0, 0.330), (0, 0, 22.5), M["gunmetal"], smooth=False)
    b.torus(0.088, 0.009, 24, 10, (0, 0, 0.038), (0, 0, 0), M["gold"])
    b.torus(0.088, 0.009, 24, 10, (0, 0, 0.312), (0, 0, 0), M["gold"])
    return b.finalize(0.36)


def build_censer(M):
    b = PartBuilder("loot_censer")
    # Imperial Gilded Boshan Mountain Incense Burner (望稻亭鎏金香炉)!
    # Scalloped lotus-rimmed tripod dish
    b.lathe(
        [(0.02, 0.022), (0.115, 0.022), (0.142, 0.052), (0.132, 0.056), (0.095, 0.034), (0.038, 0.036)],
        segs=32, flute_lobes=8, flute_amp=0.05, mat=M["gold_deep"]
    )
    for i in range(3):
        a = math.radians(i * 120 + 30)
        b.cyl(0.012, 0.018, 0.028, 12, (0.092 * math.cos(a), 0.092 * math.sin(a), 0.014), (0, 0, 0), M["gold"])
    # Slender collared stem + lotus bowl body
    b.lathe(
        [(0.042, 0.034), (0.022, 0.075), (0.032, 0.095), (0.022, 0.115), (0.072, 0.145), (0.106, 0.185), (0.096, 0.212)],
        segs=32, flute_lobes=10, flute_amp=0.04, mat=M["gold"]
    )
    # Iconic conical multi-peaked Boshan mountain openwork lid!
    b.lathe(
        [(0.096, 0.210), (0.084, 0.245), (0.064, 0.285), (0.036, 0.325), (0.010, 0.352)],
        segs=24, flute_lobes=7, flute_amp=0.14, mat=M["gold_deep"]
    )
    # Sculpted jagged mountain peaks around the lid + warm glowing incense vents
    for i in range(6):
        a = math.radians(i * 60)
        r = 0.068
        b.lathe([(0.022, 0.0), (0.014, 0.038), (0.002, 0.062)], segs=5, pos=(r * math.cos(a), r * math.sin(a), 0.215), mat=M["gold"], smooth=False)
        b.sphere(0.009, (0.056 * math.cos(a + 0.5), 0.056 * math.sin(a + 0.5), 0.258), (0, 0, 0), M["gold_plasma"])
    # Perched golden phoenix finial on summit
    b.sphere((0.016, 0.024, 0.016), (0, 0, 0.366), (12, 0, 0), M["gold"])
    b.box((0.058, 0.014, 0.008), (0, 0.006, 0.372), (18, 0, 0), M["gold"], bevel=0.002)
    b.tube_path([(0, -0.012, 0.372), (0, -0.024, 0.396), (0, -0.034, 0.392)], 0.006, 8, M["gold"])
    return b.finalize(0.38)


def build_celadon(M):
    b = PartBuilder("loot_celadon")
    # Mythic T6: Tang/Song 10-lobed Lotus-Petal Yue-Ware Secret Celadon Bowl (越窑秘色青瓷盏)
    # Stepped carved dark zitan wood saucer pedestal
    b.lathe(
        [(0.065, 0.0), (0.118, 0.0), (0.128, 0.018), (0.112, 0.030), (0.072, 0.022)],
        segs=36, mat=M["rosewood"]
    )
    # Genuine 10-lobed fluted lotus-petal thin-walled celadon bowl (outer + inner wall!)
    b.lathe(
        [
            (0.056, 0.022), (0.058, 0.044), (0.088, 0.068), (0.132, 0.118),
            (0.158, 0.172), (0.165, 0.206), (0.156, 0.208),
            (0.146, 0.170), (0.118, 0.118), (0.072, 0.072), (0.004, 0.056)
        ],
        segs=60, flute_lobes=10, flute_amp=0.068, mat=M["tex_celadon"], smooth=True, uv_mode="cyl"
    )
    # Subtle golden hairline rim kintsugi gleam
    b.torus(0.161, 0.0032, 48, 8, (0, 0, 0.206), (0, 0, 0), M["gold"])
    return b.finalize(0.36)


def build_ganoderma(M):
    b = PartBuilder("loot_ganoderma")
    # Mythic T6: Millennium Purple-Crimson Royal Ganoderma (烟山千年紫芝王)!
    # Mossy cliff-rock base
    b.ico((0.125, 0.105, 0.048), 2, (0, 0, 0.034), (5, -8, 12), M["slate"], smooth=False)
    b.ico((0.095, 0.075, 0.028), 1, (-0.02, -0.02, 0.066), (0, 0, 0), M["moss"], smooth=False)

    # Gnarled glossy lacquered stems branching into 3 overlapping kidney-shaped caps
    stems = [
        ([(0.0, 0.0, 0.055), (-0.015, -0.01, 0.125), (-0.028, 0.01, 0.195), (-0.015, 0.0, 0.255)], [0.024, 0.019, 0.017, 0.020]),
        ((0.01, 0.0, 0.062), (0.048, -0.02, 0.125), (0.082, -0.015, 0.175)),
        ((-0.01, 0.01, 0.065), (-0.062, -0.018, 0.112), (-0.098, -0.012, 0.145)),
    ]
    b.tube_path(stems[0][0], stems[0][1], 12, M["ganoderma_stem"])
    b.tube_path(list(stems[1]), [0.018, 0.015, 0.016], 10, M["ganoderma_stem"])
    b.tube_path(list(stems[2]), [0.016, 0.013, 0.014], 10, M["ganoderma_stem"])

    # 3 ruffled kidney-shaped concentric-ring lacquered caps with golden margins!
    caps = [
        ((-0.005, 0.0, 0.262), (8, -6, 10), 0.135, 0.105, 0.034),
        ((0.088, -0.018, 0.178), (12, 14, -22), 0.096, 0.078, 0.026),
        ((-0.102, -0.014, 0.148), (10, -16, 25), 0.084, 0.068, 0.024),
    ]
    for pos, rot, rx, ry, h in caps:
        # Upper ruffled glossy crimson-purple cap (fluted wavy cloud rim!)
        b.lathe(
            [(0.01, h * 0.5), (rx * 0.45, h * 0.95), (rx * 0.85, h * 0.65), (rx, 0.0), (rx * 0.92, -h * 0.30)],
            segs=36, flute_lobes=9, flute_amp=0.075, pos=pos, rot=rot, mat=M["tex_ganoderma"], uv_mode="planar_z"
        )
        # Golden-cream velvety pore underside
        b.lathe(
            [(0.01, -h * 0.35), (rx * 0.88, -h * 0.25), (rx * 0.94, -h * 0.08)],
            segs=30, pos=pos, rot=rot, mat=M["ganoderma_gill"]
        )
    return b.finalize(0.38)


def build_jade_bi(M):
    b = PartBuilder("loot_jade_bi")
    # Mythic T6: Twin-Dragon Ceremonial White-Jade Bi-Disc (诚庄先民双龙玉璧 — ZERO DONUT!)
    # 1) Ornate carved rosewood museum saddle stand (紫檀插屏座)
    b.box((0.22, 0.082, 0.026), (0, 0, 0.014), (0, 0, 0), M["rosewood"], bevel=0.006)
    b.box((0.18, 0.062, 0.018), (0, 0, 0.034), (0, 0, 0), M["rosewood"], bevel=0.004)
    for sx in (-0.078, 0.078):
        b.box((0.026, 0.056, 0.072), (sx, 0, 0.068), (0, 18 if sx < 0 else -18, 0), M["rosewood"], bevel=0.005)
    b.box((0.15, 0.066, 0.008), (0, 0, 0.025), (0, 0, 0), M["gold"])

    # 2) Crisp FLATTENED mutton-fat white-jade ceremonial Bi-disc standing upright!
    disc_z = 0.205
    b.flat_disc_ring(
        r_in=0.048, r_out=0.148, thickness=0.024, segs=48, arc_deg=360.0,
        pos=(0, 0, disc_z), rot=(90, 0, 0), mat=M["tex_jade"], bevel=0.004, uv_mode="planar_z"
    )
    # Raised double-beveled inner and outer ceremonial borders (classic Han/Tang Bi-disc!)
    b.flat_disc_ring(
        r_in=0.134, r_out=0.152, thickness=0.030, segs=48, arc_deg=360.0,
        pos=(0, 0, disc_z), rot=(90, 0, 0), mat=M["tex_jade"], bevel=0.003, uv_mode="planar_z"
    )
    b.flat_disc_ring(
        r_in=0.044, r_out=0.058, thickness=0.030, segs=36, arc_deg=360.0,
        pos=(0, 0, disc_z), rot=(90, 0, 0), mat=M["tex_jade"], bevel=0.003, uv_mode="planar_z"
    )

    # 3) TWO sculpted sinuous guardian dragons perched along the upper crest facing a golden pearl!
    for sgn in (-1.0, 1.0):
        # Coiled dragon body clinging to upper rim in deeper celadon-jade contrast!
        pts = [
            (sgn * 0.150, 0.0, disc_z + 0.020),
            (sgn * 0.146, -0.012, disc_z + 0.082),
            (sgn * 0.108, 0.008, disc_z + 0.134),
            (sgn * 0.066, -0.010, disc_z + 0.166),
            (sgn * 0.036, 0.0, disc_z + 0.160),
        ]
        b.tube_path(pts, [0.010, 0.015, 0.018, 0.017, 0.014], 10, M["jade_dragon"])
        # Dragon head + golden horns facing center pearl
        b.sphere((0.020, 0.016, 0.015), (sgn * 0.032, -0.004, disc_z + 0.164), (0, sgn * 18, 0), M["jade_dragon"])
        b.cyl(0.0045, 0.001, 0.026, 8, (sgn * 0.046, 0.0, disc_z + 0.182), (0, sgn * -28, 0), M["gold"])
        # Golden cloud-scroll mane accent
        b.torus(0.018, 0.0045, 14, 8, (sgn * 0.098, -0.014, disc_z + 0.138), (90, 0, 0), M["gold"])

    # Central flaming golden pearl at crown apex + subtle gold inlay borders on disc
    b.torus(0.143, 0.0032, 48, 8, (0, -0.015, disc_z), (90, 0, 0), M["gold"])
    b.torus(0.051, 0.0030, 36, 8, (0, -0.015, disc_z), (90, 0, 0), M["gold"])
    b.sphere(0.019, (0, 0, disc_z + 0.174), (0, 0, 0), M["gold_plasma"])
    b.torus(0.026, 0.0042, 20, 8, (0, 0, disc_z + 0.174), (90, 0, 0), M["gold"])
    return b.finalize(0.38)


def build_radar_heart(M):
    b = PartBuilder("loot_radar_heart")
    # Mythic T6: Phased-Array Supercomputer Radar Core (相控阵超算雷达心)!
    # Stepped octagonal dark-obsidian & gold armored chassis tilted 18 deg upward
    ang = (-20, 0, 0)
    b.cyl(0.155, 0.145, 0.088, 8, (0, 0, 0.155), (70, 0, 22.5), M["gunmetal"], smooth=False)
    b.cyl(0.164, 0.164, 0.018, 8, (0, -0.028, 0.165), (70, 0, 22.5), M["gold"], smooth=False)
    # 16 gleaming faceted crimson phased-array emitter cells arranged in 4x4 grid!
    rot_m = Euler(tuple(math.radians(a) for a in ang), "XYZ").to_matrix()
    center = Vector((0, -0.044, 0.170))
    for r in range(4):
        for c in range(4):
            lx = -0.066 + c * 0.044
            lz = -0.066 + r * 0.044
            if abs(lx) > 0.06 and abs(lz) > 0.06:
                continue  # Octagonal trim
            wp = center + rot_m @ Vector((lx, 0.0, lz))
            b.box((0.032, 0.018, 0.032), tuple(wp), ang, M["crimson_gem"], bevel=0.005)
    # Central glowing ruby quantum lens core
    b.ico(0.038, 2, tuple(center + rot_m @ Vector((0, -0.014, 0))), ang, M["crimson_gem"], smooth=False)
    b.torus(0.048, 0.006, 24, 10, tuple(center + rot_m @ Vector((0, -0.008, 0))), (70, 0, 0), M["gold"])
    # Twin swept gold heat-sink wings & heavy armored stand base
    for sgn in (-1.0, 1.0):
        b.box((0.052, 0.082, 0.175), (sgn * 0.168, 0.01, 0.152), (-14, sgn * 18, 0), M["gold_deep"], bevel=0.006)
        b.box((0.016, 0.095, 0.155), (sgn * 0.194, 0.01, 0.152), (-14, sgn * 18, 0), M["gold"], bevel=0.003)
    b.box((0.20, 0.135, 0.034), (0, 0.018, 0.018), (0, 0, 0), M["matte_black"], bevel=0.006)
    return b.finalize(0.38)


def build_seal(M):
    b = PartBuilder("loot_seal")
    # Mythic T6: Heart of Yanshan · Imperial Crimson-Gold Dragon Seal (烟山之心·赤金龙印)!
    # Vermilion cinnabar-inked bottom seal plate
    b.box((0.184, 0.184, 0.016), (0, 0, 0.008), (0, 0, 0), M["cinnabar"], bevel=0.002)
    # Tier 1 & Tier 2 stepped solid-gold imperial seal plinth
    b.box((0.192, 0.192, 0.082), (0, 0, 0.056), (0, 0, 0), M["gold"], bevel=0.008, bevel_segs=2)
    b.box((0.152, 0.152, 0.028), (0, 0, 0.108), (0, 0, 0), M["gold_deep"], bevel=0.005)
    # Recessed crimson-gold side fretwork panels on all 4 sides
    for rot_z, off in ((0, (0, -0.096, 0.056)), (180, (0, 0.096, 0.056)), (90, (0.096, 0, 0.056)), (-90, (-0.096, 0, 0.056))):
        b.box((0.132, 0.008, 0.044), off, (0, 0, rot_z), M["cinnabar"], bevel=0.002)
        b.box((0.102, 0.010, 0.018), off, (0, 0, rot_z), M["gold"])

    # Sculpted Coiled Imperial Golden Dragon Finial!
    # Powerful arched S-curve dragon body rising from plinth and coiling around the Heart Ruby
    dragon_pts = [
        (-0.058, 0.048, 0.125),
        (-0.068, 0.0, 0.168),
        (-0.048, -0.046, 0.218),
        (0.0, -0.036, 0.256),
        (0.050, 0.0, 0.236),
        (0.056, 0.046, 0.188),
        (0.024, 0.054, 0.145),
    ]
    b.tube_path(dragon_pts, [0.015, 0.022, 0.026, 0.028, 0.024, 0.019, 0.013], 14, M["gold"])
    # Dorsal ridge spikes along arched dragon spine
    for p in dragon_pts[1:5]:
        b.lathe([(0.012, 0.0), (0.002, 0.024)], segs=4, pos=(p[0], p[1], p[2] + 0.020), mat=M["gold_deep"], smooth=False)
    # Sculpted imperial dragon head + golden horns + whiskers facing forward-left
    b.sphere((0.028, 0.034, 0.024), (-0.042, -0.058, 0.228), (10, -12, -24), M["gold"])
    b.box((0.024, 0.028, 0.016), (-0.052, -0.082, 0.224), (8, 0, -24), M["gold"], bevel=0.004)
    for sx in (-0.012, 0.012):
        b.cyl(0.005, 0.001, 0.032, 8, (-0.035 + sx, -0.044, 0.256), (-28, sx * 600, 0), M["gold_deep"])
    # 4 golden dragon claws gripping the corners of the seal plinth
    for sx in (-0.056, 0.056):
        for sy in (-0.052, 0.052):
            b.cyl(0.013, 0.010, 0.038, 10, (sx, sy, 0.132), (0, 0, 0), M["gold_deep"])

    # Glowing faceted Blood-Ruby "Heart of Yanshan" suspended in the dragon's coil!
    b.ico((0.042, 0.042, 0.052), 1, (0.004, -0.008, 0.194), (18, 28, 12), M["crimson_gem"], smooth=False)
    b.torus(0.058, 0.005, 28, 10, (0.004, -0.008, 0.194), (24, -18, 0), M["gold_plasma"])
    return b.finalize(0.38)


# ---------------------------------------------------------------------------
# v0.8.0: 32 BRAND-NEW SCULPTED PBR COLLECTIBLES (TOTAL = 64!)
# ---------------------------------------------------------------------------
def build_rice_bowl(M):
    b = PartBuilder("loot_rice_bowl")
    b.lathe(
        [(0.058, 0.0), (0.062, 0.024), (0.105, 0.062), (0.142, 0.118), (0.150, 0.156), (0.136, 0.158), (0.125, 0.115), (0.088, 0.060), (0.004, 0.040)],
        segs=36, mat=M["clay_stone"]
    )
    b.torus(0.146, 0.006, 36, 10, (0, 0, 0.152), (0, 0, 0), M["cobalt_blue"])
    b.torus(0.126, 0.005, 36, 8, (0, 0, 0.095), (0, 0, 0), M["cobalt_blue"])
    # Pair of bamboo chopsticks resting across the bowl rim
    for dy in (-0.014, 0.014):
        b.cyl(0.005, 0.003, 0.30, 10, (0.0, dy, 0.162), (0, 90, 12), M["bamboo_aged"])
    return b.finalize(0.33)


def build_walnut(M):
    b = PartBuilder("loot_walnut")
    # Pair of grooved Jiangnan wild mountain walnuts on a tiny leaf tray
    b.lathe([(0.02, 0.0), (0.135, 0.008), (0.148, 0.024), (0.125, 0.026)], segs=24, mat=M["wood_warm"])
    for pos, rot in (((-0.052, -0.01, 0.072), (14, 18, 20)), ((0.054, 0.015, 0.068), (-18, -14, -28))):
        b.lathe(
            [(0.004, -0.058), (0.044, -0.036), (0.056, 0.0), (0.042, 0.038), (0.004, 0.060)],
            segs=24, flute_lobes=8, flute_amp=0.09, pos=pos, rot=rot, mat=M["walnut_shell"]
        )
        b.torus(0.054, 0.006, 20, 8, pos, (rot[0], rot[1] + 90, rot[2]), M["wood_warm"])
    return b.finalize(0.32)


def build_abacus(M):
    b = PartBuilder("loot_abacus")
    tilt = (-26, 0, 0)
    rot_m = Euler(tuple(math.radians(a) for a in tilt), "XYZ").to_matrix()
    ctr = Vector((0, 0, 0.125))
    # Rosewood rectangular frame + horizontal divider beam
    b.box((0.26, 0.026, 0.020), tuple(ctr + rot_m @ Vector((0, 0, 0.088))), tilt, M["rosewood"], bevel=0.003)
    b.box((0.26, 0.026, 0.020), tuple(ctr + rot_m @ Vector((0, 0, -0.088))), tilt, M["rosewood"], bevel=0.003)
    b.box((0.24, 0.022, 0.014), tuple(ctr + rot_m @ Vector((0, 0, 0.024))), tilt, M["rosewood"], bevel=0.002)
    for sx in (-0.122, 0.122):
        b.box((0.020, 0.026, 0.190), tuple(ctr + rot_m @ Vector((sx, 0, 0))), tilt, M["rosewood"], bevel=0.003)
    # 7 vertical brass rods with bi-conical abacus beads!
    for ci in range(7):
        lx = -0.090 + ci * 0.030
        b.cyl(0.0035, 0.0035, 0.165, 8, tuple(ctr + rot_m @ Vector((lx, 0, 0))), tilt, M["brass"])
        # Upper bead (heaven deck) + 3 lower beads (earth deck)
        z_hi = 0.056 if ci % 2 == 0 else 0.044
        b.sphere((0.013, 0.013, 0.008), tuple(ctr + rot_m @ Vector((lx, 0, z_hi))), tilt, M["bamboo_aged"])
        for bi in range(3):
            z_lo = -0.066 + bi * 0.018 + (0.014 if (ci + bi) % 3 == 0 else 0.0)
            b.sphere((0.013, 0.013, 0.008), tuple(ctr + rot_m @ Vector((lx, 0, z_lo))), tilt, M["wood_warm"])
    return b.finalize(0.34)


def build_pencil_tin(M):
    b = PartBuilder("loot_pencil_tin")
    b.box((0.26, 0.115, 0.042), (0, 0, 0.022), (0, 0, 0), M["olive_metal"], bevel=0.006, bevel_segs=2)
    b.quad_card(0.245, 0.100, (0, 0, 0.044), (90, 0, 0), M["tex_pencil_tin"], thickness=0.004)
    b.box((0.036, 0.012, 0.014), (0, -0.060, 0.028), (0, 0, 0), M["brass"], bevel=0.002)
    # Yellow hexagonal pencil + eraser resting diagonally on top!
    b.cyl(0.008, 0.008, 0.21, 6, (0.01, -0.01, 0.056), (0, 90, 14), M["yellow_rugged"], smooth=False)
    b.cyl(0.008, 0.001, 0.026, 6, (0.125, 0.018, 0.056), (0, 90, 14), M["bamboo_aged"], smooth=False)
    b.cyl(0.0085, 0.0085, 0.020, 12, (-0.102, -0.038, 0.056), (0, 90, 14), M["silk_red"])
    return b.finalize(0.34)


def build_bamboo_ruler(M):
    b = PartBuilder("loot_bamboo_ruler")
    tilt = (-24, 0, 12)
    b.box((0.30, 0.068, 0.012), (0, 0, 0.055), tilt, M["bamboo_aged"], bevel=0.002)
    b.quad_card(0.292, 0.062, (0, -0.003, 0.062), (66, 0, 12), M["tex_ruler"], thickness=0.003)
    # Brass hanging eyelet + red tassel at end
    b.torus(0.012, 0.0035, 16, 8, (0.128, 0.025, 0.058), (66, 0, 12), M["brass"])
    b.tube_path([(0.138, 0.028, 0.058), (0.168, 0.012, 0.032), (0.174, -0.015, 0.014)], 0.0045, 8, M["silk_red"])
    return b.finalize(0.34)


def build_osmanthus_pack(M):
    b = PartBuilder("loot_osmanthus_pack")
    # Plump golden embroidered osmanthus fragrance sachet tied at neck
    b.lathe(
        [(0.01, 0.0), (0.072, 0.016), (0.105, 0.068), (0.095, 0.135), (0.036, 0.182), (0.064, 0.228), (0.048, 0.232), (0.026, 0.185)],
        segs=28, flute_lobes=8, flute_amp=0.055, mat=M["osmanthus_gold"]
    )
    b.torus(0.040, 0.009, 24, 10, (0, 0, 0.180), (0, 0, 0), M["silk_red"])
    # Hanging red cord & tiny brass bell
    b.tube_path([(0.038, -0.01, 0.180), (0.088, -0.04, 0.125), (0.098, -0.04, 0.065)], 0.005, 8, M["silk_red"])
    b.sphere(0.016, (0.098, -0.04, 0.054), (0, 0, 0), M["brass"])
    b.sphere(0.018, (0, -0.098, 0.095), (0, 0, 0), M["silk_red"])
    return b.finalize(0.32)


def build_key_ring(M):
    b = PartBuilder("loot_key_ring")
    # Antique brass split ring with 3 distinct notched vintage keys fanned out
    b.torus(0.052, 0.008, 28, 10, (0, 0, 0.185), (78, 0, 0), M["brass"])
    key_specs = [(-38, M["brass"], 0.155), (0, M["gold"], 0.175), (36, M["bronze_dark"], 0.145)]
    for ang_y, mat_k, length in key_specs:
        rad = math.radians(ang_y)
        dx, dz = math.sin(rad), -math.cos(rad)
        mid = (dx * (length * 0.5 + 0.045), 0.008 * (1 if ang_y == 0 else -1), 0.178 + dz * (length * 0.5 + 0.045))
        b.cyl(0.007, 0.006, length, 12, mid, (0, -ang_y, 0), mat_k)
        # Key bow ring at top + bit teeth at bottom
        top_p = (dx * 0.042, mid[1], 0.178 + dz * 0.042)
        b.torus(0.022, 0.006, 18, 8, top_p, (78, -ang_y, 0), mat_k)
        tip_p = (dx * (length + 0.025), mid[1], 0.178 + dz * (length + 0.025))
        b.box((0.032, 0.007, 0.028), (tip_p[0] + 0.014 * math.cos(rad), tip_p[1], tip_p[2] + 0.014 * math.sin(rad)), (0, -ang_y, 0), mat_k, bevel=0.001)
    return b.finalize(0.34)


def build_canteen(M):
    b = PartBuilder("loot_canteen")
    # Classic flattened oval olive military canteen with canvas strap & chained cap
    b.sphere((0.118, 0.056, 0.128), (0, 0, 0.132), (0, 0, 0), M["olive_metal"])
    b.cyl(0.028, 0.026, 0.050, 20, (0, 0, 0.268), (0, 0, 0), M["gunmetal"])
    b.cyl(0.032, 0.032, 0.024, 20, (0, 0, 0.296), (0, 0, 0), M["matte_black"])
    # Canvas harness wrap band + chained cap tether
    b.torus(0.118, 0.010, 28, 10, (0, 0, 0.132), (0, 90, 0), M["hemp"], scale_vec=(1.05, 0.55, 1.0))
    b.box((0.244, 0.022, 0.034), (0, 0, 0.132), (0, 0, 0), M["hemp"], bevel=0.004)
    b.tube_path([(0.032, 0, 0.295), (0.068, -0.01, 0.270), (0.055, 0, 0.235)], 0.0045, 8, M["silver"])
    return b.finalize(0.35)


def build_rope_coil(M):
    b = PartBuilder("loot_rope_coil")
    # Neatly bundled alpine climbing rope coils + brushed steel D-carabiner
    for i in range(6):
        off_y = -0.036 + i * 0.0145
        b.torus(0.105, 0.0125, 28, 10, (0, off_y, 0.125), (90, 0, 0), M["rope_orange"], scale_vec=(0.78, 1.12, 1.0))
    # Central lashing strap + silver/black carabiner clipped to top
    b.box((0.19, 0.115, 0.042), (0, 0, 0.125), (0, 0, 0), M["matte_black"], bevel=0.006)
    b.torus(0.044, 0.009, 24, 10, (0.055, -0.015, 0.245), (84, 18, 0), M["silver"], scale_vec=(0.72, 1.15, 1.0))
    b.cyl(0.011, 0.011, 0.042, 12, (0.084, -0.015, 0.242), (0, 18, 0), M["brass"])
    return b.finalize(0.34)


def build_lacquer_box(M):
    b = PartBuilder("loot_lacquer_box")
    # Glossy cinnabar-red Jiangnan lacquer trinket chest with brass corners & lock hasp
    b.box((0.24, 0.165, 0.118), (0, 0, 0.068), (0, 0, 0), M["lacquer_red"], bevel=0.008, bevel_segs=2)
    b.box((0.252, 0.175, 0.036), (0, 0, 0.132), (0, 0, 0), M["lacquer_red"], bevel=0.008, bevel_segs=2)
    # Brass corner brackets & front cloud lock plate
    for sx in (-0.118, 0.118):
        for sy in (-0.080, 0.080):
            b.box((0.026, 0.026, 0.026), (sx, sy, 0.020), (0, 0, 0), M["gold"], bevel=0.003)
            b.box((0.026, 0.026, 0.026), (sx, sy, 0.142), (0, 0, 0), M["gold"], bevel=0.003)
    b.cyl(0.032, 0.032, 0.010, 24, (0, -0.088, 0.110), (90, 0, 0), M["gold"])
    b.box((0.016, 0.014, 0.042), (0, -0.092, 0.102), (0, 0, 0), M["gold_deep"], bevel=0.002)
    # 4 short carved feet
    for sx in (-0.095, 0.095):
        for sy in (-0.058, 0.058):
            b.box((0.024, 0.024, 0.018), (sx, sy, 0.009), (0, 0, 0), M["rosewood"])
    return b.finalize(0.34)


def build_blue_teacup(M):
    b = PartBuilder("loot_blue_teacup")
    b.lathe(
        [(0.048, 0.0), (0.052, 0.022), (0.088, 0.052), (0.118, 0.115), (0.128, 0.168), (0.118, 0.170), (0.108, 0.115), (0.075, 0.052), (0.004, 0.034)],
        segs=40, mat=M["tex_blue_cup"], uv_mode="cyl"
    )
    b.lathe([(0.055, 0.0), (0.135, 0.0), (0.142, 0.014), (0.095, 0.018)], segs=32, pos=(0, 0, -0.014), mat=M["rosewood"])
    return b.finalize(0.32)


def build_folding_shovel(M):
    b = PartBuilder("loot_folding_shovel")
    tilt = (0, 52, -14)
    # Pointed matte-olive steel tactical spade blade
    bm = bmesh.new()
    pts = [(-0.078, 0.095), (0.078, 0.095), (0.082, -0.025), (0.0, -0.135), (-0.082, -0.025)]
    fv = [bm.verts.new((x, -0.008, z)) for x, z in pts]
    bv = [bm.verts.new((x, 0.008, z)) for x, z in pts]
    bm.faces.new(fv)
    bm.faces.new(list(reversed(bv)))
    for i in range(len(pts)):
        inext = (i + 1) % len(pts)
        bm.faces.new((bv[i], bv[inext], fv[inext], fv[i]))
    xf_blade = Matrix.Translation((-0.075, 0, 0.095)) @ Euler((math.radians(12), math.radians(52), math.radians(-14)), "XYZ").to_matrix().to_4x4()
    b._finish_bm(bm, M["olive_metal"], smooth=False, xform=xf_blade)
    # Locking collar + shaft + triangular D-handle grip
    b.cyl(0.018, 0.018, 0.038, 16, (0.01, 0, 0.145), tilt, M["brass"])
    b.cyl(0.012, 0.012, 0.195, 14, (0.085, 0, 0.195), tilt, M["gunmetal"])
    b.torus(0.044, 0.010, 20, 10, (0.175, 0, 0.252), (90, 52, -14), M["rubber"])
    return b.finalize(0.36)


def build_smoke_can(M):
    b = PartBuilder("loot_smoke_can")
    b.cyl(0.056, 0.056, 0.225, 28, (0, 0, 0.115), (0, 0, 0), M["olive_metal"])
    b.cyl(0.058, 0.058, 0.038, 28, (0, 0, 0.165), (0, 0, 0), M["yellow_rugged"])
    b.cyl(0.058, 0.058, 0.022, 28, (0, 0, 0.015), (0, 0, 0), M["matte_black"])
    b.cyl(0.028, 0.024, 0.048, 20, (0, 0, 0.246), (0, 0, 0), M["gunmetal"])
    # Safety spoon lever + silver pull-pin ring!
    b.tube_path([(0.022, 0, 0.264), (0.068, 0, 0.245), (0.072, 0, 0.120)], 0.008, 8, M["olive_metal"])
    b.torus(0.028, 0.0055, 20, 8, (-0.042, -0.01, 0.252), (90, 18, 0), M["silver"])
    return b.finalize(0.34)


def build_brush_set(M):
    b = PartBuilder("loot_brush_set")
    # Sculpted 5-peak celadon mountain brush rest
    b.box((0.185, 0.032, 0.028), (0, 0, 0.014), (0, 0, 0), M["tex_celadon"], bevel=0.006)
    for sx, h in ((-0.068, 0.052), (-0.032, 0.072), (0.0, 0.095), (0.034, 0.068), (0.068, 0.048)):
        b.lathe([(0.022, 0.0), (0.014, h * 0.6), (0.003, h)], segs=12, pos=(sx, 0, 0.018), mat=M["tex_celadon"])
    # Traditional Huzhou bamboo calligraphy brush resting diagonally across the peaks
    b.cyl(0.008, 0.009, 0.26, 16, (-0.01, -0.026, 0.088), (0, 82, -10), M["bamboo_aged"])
    b.cyl(0.011, 0.010, 0.028, 16, (0.125, -0.046, 0.070), (0, 82, -10), M["rosewood"])
    b.lathe([(0.011, 0.0), (0.013, 0.024), (0.002, 0.066)], segs=16, pos=(0.138, -0.048, 0.068), rot=(0, 82, -10), mat=M["white_cream"])
    return b.finalize(0.36)


def build_morse_key(M):
    b = PartBuilder("loot_morse_key")
    # Dark bakelite wooden base + vintage brass straight telegraph lever & black knob
    b.box((0.135, 0.225, 0.034), (0, 0, 0.017), (0, 0, 0), M["rosewood"], bevel=0.006)
    b.box((0.026, 0.168, 0.018), (0, -0.008, 0.078), (6, 0, 0), M["brass"], bevel=0.003)
    b.box((0.058, 0.042, 0.054), (0, 0.020, 0.056), (0, 0, 0), M["brass"], bevel=0.004)
    # Tapping disc knob at front + twin copper binding posts at rear
    b.cyl(0.036, 0.038, 0.016, 24, (0, -0.082, 0.098), (6, 0, 0), M["matte_black"])
    b.cyl(0.012, 0.012, 0.028, 14, (0, -0.082, 0.082), (6, 0, 0), M["brass"])
    for sx in (-0.038, 0.038):
        b.cyl(0.013, 0.011, 0.034, 16, (sx, 0.082, 0.048), (0, 0, 0), M["copper"])
    return b.finalize(0.34)


def build_herb_case(M):
    b = PartBuilder("loot_herb_case")
    # Cedar botanical specimen display frame standing tilted on easel foot
    tilt = (-20, 0, 0)
    b.box((0.23, 0.034, 0.23), (0, 0, 0.132), tilt, M["wood_warm"], bevel=0.006)
    b.quad_card(0.196, 0.196, (0, -0.018, 0.132), tilt, M["tex_herb"], thickness=0.004)
    # Brass corner clasps & stand prop
    for sx in (-0.110, 0.110):
        for sz in (0.024, 0.240):
            b.box((0.024, 0.038, 0.024), (sx, -0.002, sz), tilt, M["brass"], bevel=0.002)
    b.box((0.06, 0.016, 0.14), (0, 0.058, 0.072), (18, 0, 0), M["wood_warm"], bevel=0.002)
    return b.finalize(0.35)


def build_binoculars(M):
    b = PartBuilder("loot_binoculars")
    # Twin rubber-armored military binoculars with emerald coated objective lenses & center focus wheel
    for sx in (-0.066, 0.066):
        b.lathe(
            [(0.030, -0.105), (0.036, -0.065), (0.046, 0.025), (0.052, 0.105), (0.044, 0.105)],
            segs=24, pos=(sx, 0, 0.062), rot=(90, 0, 0), mat=M["gunmetal"]
        )
        b.torus(0.049, 0.006, 24, 8, (sx, -0.102, 0.062), (90, 0, 0), M["rubber"])
        b.sphere((0.042, 0.042, 0.014), (sx, -0.098, 0.062), (90, 0, 0), M["emerald_lens"])
        b.cyl(0.022, 0.020, 0.022, 18, (sx, 0.112, 0.062), (90, 0, 0), M["rubber"])
    # Central articulated hinge bridge & knurled focus wheel
    b.box((0.125, 0.046, 0.032), (0, -0.01, 0.068), (0, 0, 0), M["matte_black"], bevel=0.005)
    b.cyl(0.022, 0.022, 0.058, 18, (0, 0.015, 0.088), (90, 0, 0), M["brass"])
    return b.finalize(0.34)


def build_ink_box(M):
    b = PartBuilder("loot_ink_box")
    # Circular antique engraved brass scholar's ink box (lid slightly ajar revealing black ink pad!)
    b.cyl(0.118, 0.122, 0.054, 36, (0, 0, 0.028), (0, 0, 0), M["brass"])
    b.cyl(0.102, 0.102, 0.012, 32, (0, 0, 0.056), (0, 0, 0), M["matte_black"])
    # Tilted resting carved brass lid leaning behind box
    b.cyl(0.122, 0.118, 0.026, 36, (0, 0.062, 0.145), (72, 0, 0), M["brass"])
    b.torus(0.112, 0.008, 36, 10, (0, 0.052, 0.142), (72, 0, 0), M["gold"])
    b.sphere((0.036, 0.036, 0.016), (0, 0.044, 0.142), (72, 0, 0), M["gold"])
    return b.finalize(0.34)


def build_inkstick(M):
    b = PartBuilder("loot_inkstick")
    # Glossy jet-black octagonal Chinese Pine-Soot Inkstick with embossed gold pine relief
    tilt = (-16, 0, 10)
    b.box((0.072, 0.024, 0.255), (0, 0, 0.132), tilt, M["matte_black"], bevel=0.006)
    b.box((0.056, 0.027, 0.232), (0, -0.002, 0.132), tilt, M["gold"], bevel=0.002)
    b.box((0.046, 0.029, 0.220), (0, -0.003, 0.132), tilt, M["matte_black"], bevel=0.002)
    # Embossed golden pine & mountain motif down the center
    for dz, w in ((0.185, 0.030), (0.145, 0.034), (0.105, 0.026), (0.068, 0.020)):
        b.box((w, 0.006, 0.016), (0, -0.019 + (dz - 0.132) * 0.28, dz), tilt, M["gold"], bevel=0.001)
    # Tiny rosewood presentation stand
    b.box((0.11, 0.068, 0.018), (0, 0.006, 0.009), (0, 0, 0), M["rosewood"], bevel=0.003)
    return b.finalize(0.35)


def build_silk_pouch(M):
    b = PartBuilder("loot_silk_pouch")
    # Emerald-gold Suzhou brocade drawstring pouch with jade bead & golden tassel!
    b.lathe(
        [(0.015, 0.020), (0.088, 0.042), (0.116, 0.105), (0.098, 0.172), (0.042, 0.212), (0.074, 0.258), (0.058, 0.262), (0.034, 0.215)],
        segs=32, flute_lobes=10, flute_amp=0.045, mat=M["tex_silk"], uv_mode="cyl"
    )
    b.torus(0.046, 0.008, 24, 10, (0, 0, 0.212), (0, 0, 0), M["gold"])
    b.sphere(0.018, (0, -0.052, 0.205), (0, 0, 0), M["imperial_jade"])
    b.cyl(0.018, 0.006, 0.068, 12, (0, -0.055, 0.152), (0, 0, 0), M["gold"])
    return b.finalize(0.35)


def build_anemometer(M):
    b = PartBuilder("loot_anemometer")
    # Rugged yellow-black handheld field wind meter with 3-cup spinning rotor & LCD
    b.box((0.105, 0.046, 0.185), (0, 0, 0.095), (0, 0, 0), M["yellow_rugged"], bevel=0.010, bevel_segs=2)
    b.box((0.084, 0.050, 0.155), (0, 0, 0.095), (0, 0, 0), M["rubber"], bevel=0.006)
    b.quad_card(0.072, 0.054, (0, -0.027, 0.128), (0, 0, 0), M["tex_radio_lcd"], thickness=0.003)
    # Top stem + 3-arm wind-cup rotor assembly!
    b.cyl(0.012, 0.010, 0.075, 16, (0, 0, 0.222), (0, 0, 0), M["silver"])
    b.sphere(0.016, (0, 0, 0.262), (0, 0, 0), M["matte_black"])
    for i in range(3):
        a = math.radians(i * 120 + 20)
        b.cyl(0.005, 0.005, 0.082, 10, (0.040 * math.cos(a), 0.040 * math.sin(a), 0.262), (0, 90, math.degrees(a)), M["silver"])
        b.sphere((0.022, 0.022, 0.022), (0.086 * math.cos(a), 0.086 * math.sin(a), 0.262), (0, 0, math.degrees(a)), M["yellow_rugged"])
    return b.finalize(0.36)


def build_pocket_watch(M):
    b = PartBuilder("loot_pocket_watch")
    # Classic open brass pocket watch with Roman numeral dial & looped chain
    b.cyl(0.108, 0.108, 0.032, 36, (0, 0, 0.118), (78, 0, 0), M["gold"])
    b.torus(0.108, 0.010, 36, 10, (0, -0.015, 0.116), (78, 0, 0), M["gold_deep"])
    b.cyl(0.096, 0.096, 0.006, 32, (0, -0.017, 0.116), (78, 0, 0), M["tex_watch"], uv_mode="planar_z")
    # Top winding crown & bow ring
    b.cyl(0.016, 0.016, 0.028, 16, (0, 0.008, 0.238), (-12, 0, 0), M["gold"])
    b.torus(0.028, 0.006, 20, 8, (0, 0.012, 0.270), (78, 0, 0), M["gold"])
    # Open hinged protective cover swung out to the left
    b.cyl(0.104, 0.104, 0.014, 32, (-0.155, -0.036, 0.118), (78, 0, 52), M["brass"])
    # Draped brass watch chain arc on bottom
    b.tube_path([(0.022, 0.012, 0.262), (0.118, -0.012, 0.185), (0.132, -0.024, 0.075), (0.068, -0.022, 0.016)], 0.006, 8, M["gold"])
    return b.finalize(0.36)


def build_hairpin(M):
    b = PartBuilder("loot_hairpin")
    # Slender gilded silver hairpin topped with kingfisher-blue cloud-phoenix ornament
    ang = (0, 62, -16)
    b.cyl(0.006, 0.002, 0.30, 12, (-0.01, 0, 0.095), ang, M["silver"])
    # Ornate gilded cloud-phoenix headpiece at upper-right end
    head_p = (0.105, -0.015, 0.165)
    b.sphere((0.044, 0.016, 0.034), head_p, (0, 22, -16), M["kingfisher"])
    b.torus(0.046, 0.007, 24, 10, head_p, (75, 22, -16), M["gold"])
    for dx, dz in ((-0.024, 0.028), (0.022, 0.024), (0.036, -0.012)):
        b.sphere(0.015, (head_p[0] + dx, head_p[1] - 0.008, head_p[2] + dz), (0, 0, 0), M["kingfisher"])
    b.sphere(0.014, (head_p[0], head_p[1] - 0.014, head_p[2]), (0, 0, 0), M["crimson_gem"])
    # Delicate hanging pearl drop tassel
    b.cyl(0.003, 0.003, 0.056, 8, (0.120, -0.018, 0.118), (0, 0, 0), M["gold"])
    b.sphere(0.013, (0.120, -0.018, 0.088), (0, 0, 0), M["white_cream"])
    return b.finalize(0.36)


def build_water_dropper(M):
    b = PartBuilder("loot_water_dropper")
    # Sculpted Yue-ware celadon desk water dropper (青瓷蟾蜍水注)
    b.sphere((0.118, 0.098, 0.074), (0, 0, 0.076), (0, 0, 0), M["tex_celadon"])
    b.lathe([(0.036, 0.140), (0.032, 0.162), (0.042, 0.172), (0.028, 0.174)], segs=24, mat=M["tex_celadon"])
    b.sphere(0.020, (0, 0, 0.184), (0, 0, 0), M["gold"])
    # Sculpted spout & curved handle + 4 short curled feet
    b.tube_path([(0.095, 0, 0.088), (0.145, 0, 0.115), (0.168, 0, 0.138)], [0.020, 0.014, 0.010], 12, M["tex_celadon"])
    b.tube_path([(-0.085, 0, 0.112), (-0.142, 0, 0.126), (-0.136, 0, 0.068), (-0.095, 0, 0.056)], 0.011, 10, M["tex_celadon"])
    for sx in (-0.064, 0.064):
        for sy in (-0.054, 0.054):
            b.sphere((0.024, 0.024, 0.018), (sx, sy, 0.018), (0, 0, 0), M["tex_celadon"])
    return b.finalize(0.34)


def build_optic_core(M):
    b = PartBuilder("loot_optic_core")
    # Precision titanium thermal/low-light prism housing with glowing amber germanium lens!
    b.cyl(0.088, 0.094, 0.145, 8, (0, 0, 0.105), (90, 0, 22.5), M["gunmetal"], smooth=False)
    b.torus(0.095, 0.010, 28, 10, (0, -0.072, 0.105), (90, 0, 0), M["gold"])
    b.sphere((0.076, 0.076, 0.028), (0, -0.068, 0.105), (90, 0, 0), M["germanium"])
    b.box((0.128, 0.110, 0.036), (0, 0.008, 0.022), (0, 0, 0), M["matte_black"], bevel=0.005)
    b.cyl(0.022, 0.020, 0.032, 16, (0, 0.01, 0.205), (0, 0, 0), M["brass"])
    b.cyl(0.020, 0.018, 0.032, 16, (0.102, 0.01, 0.105), (0, 90, 0), M["brass"])
    return b.finalize(0.34)


def build_inkstone(M):
    b = PartBuilder("loot_inkstone")
    # Carved purplish-slate Duanxi Scholar's Inkstone displayed upright on rosewood museum easel
    tilt = (-26, 0, 0)
    # Rosewood backing cradle + easel prop
    b.box((0.214, 0.030, 0.262), (0, 0.012, 0.132), tilt, M["rosewood"], bevel=0.006)
    b.box((0.068, 0.018, 0.145), (0, 0.068, 0.074), (20, 0, 0), M["rosewood"], bevel=0.003)
    # Purplish-slate Duanxi inkstone slab nestled in cradle
    b.box((0.188, 0.030, 0.236), (0, -0.003, 0.136), tilt, M["purple_slate"], bevel=0.010, bevel_segs=2)
    # Carved ink-well & cloud relief faceplate flush on front surface (-Y normal)
    b.quad_card(0.168, 0.216, (0, -0.018, 0.143), tilt, M["tex_inkstone"], thickness=0.004)
    return b.finalize(0.35)


def build_bronze_mirror(M):
    b = PartBuilder("loot_bronze_mirror")
    # Tier 5 Small Gold: Tang Silver-Inlaid Bronze Mirror standing in carved rosewood cradle!
    b.box((0.18, 0.072, 0.024), (0, 0, 0.012), (0, 0, 0), M["rosewood"], bevel=0.005)
    for sx in (-0.068, 0.068):
        b.box((0.024, 0.052, 0.068), (sx, 0, 0.048), (0, 16 if sx < 0 else -16, 0), M["rosewood"], bevel=0.004)
    # Circular beveled antique bronze mirror disc with silver-inlaid texture & central boss knob
    b.cyl(0.142, 0.142, 0.022, 48, (0, 0, 0.182), (90, 0, 0), M["bronze_dark"])
    b.torus(0.140, 0.010, 48, 12, (0, -0.008, 0.182), (90, 0, 0), M["silver"])
    b.cyl(0.130, 0.130, 0.006, 44, (0, -0.011, 0.182), (90, 0, 0), M["tex_mirror"], uv_mode="planar_z")
    b.sphere((0.028, 0.022, 0.028), (0, -0.018, 0.182), (0, 0, 0), M["gold"])
    return b.finalize(0.36)


def build_crypto_drive(M):
    b = PartBuilder("loot_crypto_drive")
    # Tier 5 Small Gold: Rugged titanium & gold encrypted tactical SSD vault standing tilted!
    tilt = (-22, 0, 0)
    # Main gunmetal titanium armored chassis (standing tall along Z, facing -Y)
    b.box((0.172, 0.044, 0.242), (0, 0, 0.128), tilt, M["gunmetal"], bevel=0.010, bevel_segs=2)
    # Crisp encrypted tactical faceplate flush on front surface (-Y normal)
    b.quad_card(0.140, 0.204, (0, -0.022, 0.137), tilt, M["tex_crypto"], thickness=0.004)
    # Solid gold shock-bumper side rails gripping both flanks
    for sx in (-0.088, 0.088):
        b.box((0.020, 0.052, 0.222), (sx, 0, 0.128), tilt, M["gold"], bevel=0.004)
    # Embedded glowing cyan status LED strip flush on lower front bezel (same tilt!)
    b.box((0.092, 0.008, 0.014), (0, -0.001, 0.052), tilt, M["cyan_glow"], bevel=0.002)
    # Top armored connector collar + gold carabiner loop
    b.box((0.072, 0.036, 0.024), (0, 0.046, 0.248), tilt, M["matte_black"], bevel=0.004)
    b.torus(0.026, 0.006, 20, 8, (0, 0.054, 0.272), (68, 0, 0), M["gold"])
    return b.finalize(0.36)


def build_zisha_teapot(M):
    b = PartBuilder("loot_zisha_teapot")
    # Tier 5 Small Gold: Classic Yixing Zisha terracotta teapot (宜兴朱泥水平壶)!
    b.lathe(
        [(0.056, 0.0), (0.095, 0.022), (0.126, 0.078), (0.118, 0.132), (0.078, 0.165), (0.068, 0.176), (0.058, 0.172)],
        segs=36, mat=M["zisha_clay"]
    )
    # Flush domed lid + classic pearl finial knob + subtle gold rim inlay
    b.lathe([(0.066, 0.174), (0.054, 0.194), (0.016, 0.200), (0.024, 0.216), (0.004, 0.232)], segs=28, mat=M["zisha_clay"])
    b.torus(0.069, 0.004, 32, 8, (0, 0, 0.174), (0, 0, 0), M["gold"])
    # Elegant curved spout & balanced ear handle
    b.tube_path([(0.102, 0, 0.078), (0.156, 0, 0.105), (0.182, 0, 0.156), (0.198, 0, 0.172)], [0.022, 0.017, 0.013, 0.011], 14, M["zisha_clay"])
    b.tube_path([(-0.088, 0, 0.148), (-0.158, 0, 0.145), (-0.165, 0, 0.088), (-0.112, 0, 0.052)], 0.013, 12, M["zisha_clay"])
    return b.finalize(0.35)


def build_jade_pendant(M):
    b = PartBuilder("loot_jade_pendant")
    # Tier 5 Small Gold: Translucent imperial emerald carved bamboo-node jade pendant!
    tilt = (-10, 0, 0)
    b.cyl(0.042, 0.038, 0.076, 24, (0, 0, 0.105), tilt, M["imperial_jade"])
    b.torus(0.044, 0.009, 24, 10, (0, -0.006, 0.142), tilt, M["imperial_jade"])
    b.cyl(0.038, 0.034, 0.072, 24, (0, 0.012, 0.180), tilt, M["imperial_jade"])
    b.torus(0.040, 0.009, 24, 10, (0, 0.018, 0.216), tilt, M["imperial_jade"])
    # Carved jade bamboo leaf hugging side + gold bail + crimson Chinese knot & tassel
    b.sphere((0.024, 0.010, 0.056), (0.042, -0.016, 0.152), (-10, 0, -28), M["imperial_jade"])
    b.torus(0.024, 0.0055, 20, 8, (0, 0.022, 0.242), (80, 0, 0), M["gold"])
    b.torus(0.052, 0.007, 24, 10, (0, 0.028, 0.282), (80, 0, 0), M["silk_red"], arc_deg=190.0)
    b.sphere(0.016, (0, -0.012, 0.056), (0, 0, 0), M["gold"])
    b.cyl(0.018, 0.006, 0.052, 12, (0, -0.014, 0.026), (0, 0, 0), M["silk_red"])
    return b.finalize(0.36)


def build_vintage_camera(M):
    b = PartBuilder("loot_vintage_camera")
    # Tier 5 Small Gold: Classic brushed-brass & dark-leather rangefinder camera!
    b.box((0.235, 0.088, 0.128), (0, 0, 0.068), (0, 0, 0), M["leather_dark"], bevel=0.010, bevel_segs=2)
    b.box((0.238, 0.090, 0.036), (0, 0, 0.132), (0, 0, 0), M["brass"], bevel=0.006)
    b.box((0.238, 0.090, 0.016), (0, 0, 0.008), (0, 0, 0), M["brass"], bevel=0.004)
    # Stepped protruding multi-ring coated optical lens barrel
    b.lathe([(0.056, 0.0), (0.058, 0.025), (0.050, 0.030), (0.052, 0.068), (0.044, 0.072)], segs=32, pos=(0.012, -0.044, 0.068), rot=(90, 0, 0), mat=M["gunmetal"])
    b.torus(0.054, 0.005, 32, 8, (0.012, -0.105, 0.068), (90, 0, 0), M["brass"])
    b.sphere((0.040, 0.040, 0.014), (0.012, -0.104, 0.068), (90, 0, 0), M["sapphire_lens"])
    # Viewfinder window + top shutter speed dials
    b.box((0.042, 0.012, 0.024), (-0.068, -0.046, 0.132), (0, 0, 0), M["sapphire_lens"], bevel=0.002)
    b.cyl(0.020, 0.018, 0.022, 18, (-0.072, 0, 0.160), (0, 0, 0), M["gold"])
    b.cyl(0.016, 0.016, 0.020, 18, (0.074, 0, 0.158), (0, 0, 0), M["silver"])
    return b.finalize(0.35)


def build_imperial_bowl(M):
    b = PartBuilder("loot_imperial_bowl")
    # Tier 5 Small Gold: Imperial Ming/Qing Blue-and-White Lotus-Scroll Footed Cup with Gold Rim!
    b.lathe(
        [(0.054, 0.0), (0.062, 0.045), (0.042, 0.078), (0.095, 0.112), (0.142, 0.168), (0.156, 0.214), (0.146, 0.216), (0.132, 0.168), (0.082, 0.112), (0.004, 0.090)],
        segs=48, mat=M["tex_imperial_bowl"], uv_mode="cyl"
    )
    b.torus(0.152, 0.0045, 48, 8, (0, 0, 0.214), (0, 0, 0), M["gold"])
    b.torus(0.056, 0.0045, 32, 8, (0, 0, 0.004), (0, 0, 0), M["gold"])
    return b.finalize(0.35)


# Master ordered registry matching rules.gd 7-tier LOOT_TABLE (T1 -> T7, 64 unique items!)
COLLECTIBLE_REGISTRY = [
    # Tier 1 · 常规白 (14)
    ("battery", 1, "旧巡护电池", build_battery, (0.0, 0.0, 18.0)),
    ("ration", 1, "压缩干粮", build_ration, (0.0, 0.0, 12.0)),
    ("wire", 1, "信号铜线", build_wire, (0.0, 0.0, -20.0)),
    ("tea", 1, "诚庄春茶饼", build_tea, (0.0, 0.0, 8.0)),
    ("bamboo", 1, "青竹编织哨", build_bamboo, (0.0, 0.0, 15.0)),
    ("rice_bowl", 1, "粗陶米碗", build_rice_bowl, (0.0, 0.0, 16.0)),
    ("walnut", 1, "烟山野生核桃", build_walnut, (0.0, 0.0, 14.0)),
    ("abacus", 1, "老式木算盘", build_abacus, (0.0, 0.0, 10.0)),
    ("pencil_tin", 1, "铁皮铅笔盒", build_pencil_tin, (0.0, 0.0, 18.0)),
    ("bamboo_ruler", 1, "老竹尺", build_bamboo_ruler, (0.0, 0.0, 8.0)),
    ("osmanthus_pack", 1, "干桂花香包", build_osmanthus_pack, (0.0, 0.0, 12.0)),
    ("key_ring", 1, "旧黄铜钥匙串", build_key_ring, (0.0, 0.0, 8.0)),
    ("canteen", 1, "军绿旧水壶", build_canteen, (0.0, 0.0, 16.0)),
    ("rope_coil", 1, "尼龙登山绳", build_rope_coil, (0.0, 0.0, 14.0)),
    # Tier 2 · 精良绿 (12)
    ("compass", 2, "林间指北针", build_compass, (0.0, 0.0, 14.0)),
    ("torch", 2, "防水战术手电", build_torch, (0.0, 0.0, -10.0)),
    ("badge", 2, "巡护员徽章", build_badge, (0.0, 0.0, 10.0)),
    ("fan", 2, "烟山手工折扇", build_fan, (0.0, 0.0, 8.0)),
    ("gem", 2, "溪石萤光矿", build_gem, (0.0, 0.0, 18.0)),
    ("lacquer_box", 2, "朱漆首饰匣", build_lacquer_box, (0.0, 0.0, 20.0)),
    ("blue_teacup", 2, "青花品茗杯", build_blue_teacup, (0.0, 0.0, 14.0)),
    ("folding_shovel", 2, "工兵折叠铲", build_folding_shovel, (0.0, 0.0, 10.0)),
    ("smoke_can", 2, "信号发烟罐", build_smoke_can, (0.0, 0.0, 18.0)),
    ("brush_set", 2, "湖笔书写套组", build_brush_set, (0.0, 0.0, 10.0)),
    ("morse_key", 2, "铜制电报发报键", build_morse_key, (0.0, 0.0, 22.0)),
    ("herb_case", 2, "烟山草药标本匣", build_herb_case, (0.0, 0.0, 10.0)),
    # Tier 3 · 稀有蓝 (11)
    ("radio", 3, "加密无线电台", build_radio, (0.0, 0.0, 16.0)),
    ("rangefinder", 3, "光学测距模块", build_rangefinder, (0.0, 0.0, 22.0)),
    ("amber", 3, "古树琥珀标本", build_amber, (0.0, 0.0, 14.0)),
    ("nvg_lens", 3, "军规夜视镜片", build_nvg_lens, (0.0, 0.0, 18.0)),
    ("rock", 3, "太湖透漏赏石", build_rock, (0.0, 0.0, 14.0)),
    ("binoculars", 3, "军用双筒望远镜", build_binoculars, (0.0, 0.0, 20.0)),
    ("ink_box", 3, "雕花黄铜墨盒", build_ink_box, (0.0, 0.0, 12.0)),
    ("inkstick", 3, "松烟鎏金古墨锭", build_inkstick, (0.0, 0.0, 10.0)),
    ("silk_pouch", 3, "江南苏绣锦囊", build_silk_pouch, (0.0, 0.0, 12.0)),
    ("anemometer", 3, "便携气象测风仪", build_anemometer, (0.0, 0.0, 16.0)),
    ("pocket_watch", 3, "机械铜壳怀表", build_pocket_watch, (0.0, 0.0, 10.0)),
    # Tier 4 · 史诗紫 (10)
    ("chip", 4, "无人机核心芯片", build_chip, (0.0, 0.0, 12.0)),
    ("jade_piece", 4, "竹海古玉残片", build_jade_piece, (0.0, 0.0, 10.0)),
    ("blackbox", 4, "军用黑匣子", build_blackbox, (0.0, 0.0, 22.0)),
    ("rubbing", 4, "烟霞岩画残拓", build_rubbing, (0.0, 0.0, 8.0)),
    ("silver_lock", 4, "古樟祈福银锁", build_silver_lock, (0.0, 0.0, 8.0)),
    ("kettle", 4, "先民青铜茶铫", build_kettle, (0.0, 0.0, -18.0)),
    ("hairpin", 4, "鎏金点翠银簪", build_hairpin, (0.0, 0.0, 8.0)),
    ("water_dropper", 4, "青瓷蟾蜍水注", build_water_dropper, (0.0, 0.0, -16.0)),
    ("optic_core", 4, "微光瞄具光学核", build_optic_core, (0.0, 0.0, 20.0)),
    ("inkstone", 4, "端溪雕云古砚", build_inkstone, (0.0, 0.0, 14.0)),
    # Tier 5 · 珍品小金 (6)
    ("bronze_mirror", 5, "海兽葡萄错银铜镜", build_bronze_mirror, (0.0, 0.0, 12.0)),
    ("crypto_drive", 5, "战备量子加密硬盘", build_crypto_drive, (0.0, 0.0, 16.0)),
    ("zisha_teapot", 5, "宜兴朱泥水平壶", build_zisha_teapot, (0.0, 0.0, -18.0)),
    ("jade_pendant", 5, "翡翠节节高玉佩", build_jade_pendant, (0.0, 0.0, 10.0)),
    ("vintage_camera", 5, "复古黄铜旁轴相机", build_vintage_camera, (0.0, 0.0, 20.0)),
    ("imperial_bowl", 5, "御窑青花缠枝盏", build_imperial_bowl, (0.0, 0.0, 14.0)),
    # Tier 6 · 传说大金 (6)
    ("tally", 6, "烟山古铜虎符", build_tally, (0.0, 0.0, -24.0)),
    ("medal", 6, "特级金质勋章", build_medal, (0.0, 0.0, 10.0)),
    ("quantum", 6, "量子词典原型机", build_quantum, (0.0, 0.0, 18.0)),
    ("slips", 6, "烟山先民竹简", build_slips, (0.0, 0.0, 12.0)),
    ("core", 6, "烟山统领黄金核心", build_core, (0.0, 0.0, 18.0)),
    ("censer", 6, "望稻亭鎏金香炉", build_censer, (0.0, 0.0, 12.0)),
    # Tier 7 · 旷世大红 (5)
    ("celadon", 7, "越窑秘色青瓷盏", build_celadon, (0.0, 0.0, 15.0)),
    ("ganoderma", 7, "烟山千年紫芝王", build_ganoderma, (0.0, 0.0, 12.0)),
    ("jade_bi", 7, "诚庄先民双龙玉璧", build_jade_bi, (0.0, 0.0, 12.0)),
    ("radar_heart", 7, "相控阵超算雷达心", build_radar_heart, (0.0, 0.0, 16.0)),
    ("seal", 7, "烟山之心·赤金龙印", build_seal, (0.0, 0.0, 22.0)),
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
    scene.cycles.samples = 28
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

    # Clean museum studio neutral-warm ambient world
    world = bpy.data.worlds.new("MuseumStudioWorld")
    scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs["Color"].default_value = (0.30, 0.34, 0.38, 1.0)
        bg.inputs["Strength"].default_value = 0.72

    # Camera positioned at front-3/4 museum angle (-Y looking toward +Y)
    cam_data = bpy.data.cameras.new("StudioCam")
    cam_data.lens = 58.0
    cam_obj = bpy.data.objects.new("StudioCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    # 3-Point Studio Lighting (Warm Key, Cool Jade Fill, Rarity-Tinted Rim)
    def add_area(name, pos, look_at, energy, size, col):
        ld = bpy.data.lights.new(name, type="AREA")
        ld.energy = energy
        ld.size = size
        ld.color = col
        lo = bpy.data.objects.new(name, ld)
        lo.location = Vector(pos)
        direction = Vector(look_at) - lo.location
        lo.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
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
    # Distance tuned so hero fills ~78% of 256x256 square frame cleanly
    dist = radius * 3.15
    elev = math.radians(22.0)
    azim = math.radians(-16.0)
    cam_pos = center + Vector((
        dist * math.cos(elev) * math.sin(azim),
        -dist * math.cos(elev) * math.cos(azim),
        dist * math.sin(elev),
    ))
    cam_obj.location = cam_pos
    cam_obj.rotation_euler = (center - cam_pos).to_track_quat("-Z", "Y").to_euler()


def build_contact_sheet():
    from PIL import Image, ImageDraw, ImageFont

    font_path = ROOT / "game" / "assets" / "font" / "NotoSansSC.ttf"
    font = ImageFont.truetype(str(font_path), 15) if font_path.exists() else ImageFont.load_default()
    cols, rows = 8, 4
    cell_w, cell_h = 200, 232
    sheet = Image.new("RGBA", (cols * cell_w + 24, rows * cell_h + 64), (14, 24, 29, 255))
    draw = ImageDraw.Draw(sheet)
    title_font = ImageFont.truetype(str(font_path), 24) if font_path.exists() else font
    draw.text((20, 16), "烟山基地 v0.7.2 · 32 件藏品影棚实拍图标总览（Blender 4.5 PBR 同源渲染）", fill=(244, 206, 114, 255), font=title_font)

    tier_hex = {
        1: (185, 198, 204), 2: (118, 235, 170), 3: (106, 186, 255),
        4: (204, 132, 255), 5: (255, 209, 92), 6: (255, 76, 92),
    }

    for idx, (art_id, rarity, zh, _fn, _rot) in enumerate(COLLECTIBLE_REGISTRY):
        c = idx % cols
        r = idx // cols
        x0 = 12 + c * cell_w
        y0 = 56 + r * cell_h
        tc = tier_hex[rarity]
        draw.rounded_rectangle((x0 + 6, y0 + 6, x0 + cell_w - 6, y0 + cell_h - 6), radius=10, fill=(22, 36, 44, 255), outline=(tc[0], tc[1], tc[2], 210), width=2)
        icon_path = ICON_DIR / f"{art_id}.png"
        if icon_path.exists():
            ic = Image.open(icon_path).convert("RGBA").resize((164, 164), Image.Resampling.LANCZOS)
            sheet.alpha_composite(ic, (x0 + 18, y0 + 14))
        draw.text((x0 + 14, y0 + 182), f"T{rarity} {zh}", fill=(tc[0], tc[1], tc[2], 255), font=font)
        draw.text((x0 + 14, y0 + 203), art_id, fill=(162, 196, 186, 255), font=font)

    out_png = REVIEW_DIR / "contact_sheet_32_icons.png"
    sheet.convert("RGB").save(out_png)
    print(f"Wrote contact sheet: {out_png.relative_to(ROOT)}", flush=True)


def main():
    clear_scene()
    M = mats()

    built_objs: list[tuple[str, int, str, bpy.types.Object, tuple[float, float, float]]] = []
    stats: dict[str, dict] = {}

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
        print(f"  Built {obj.name:18s}: {tri_count:4d} tris, {len(obj.data.materials)} mats, size={stats[art_id]['size_m']}", flush=True)

    # 1) Export all 32 clean PBR meshes in ONE unified GLB (origin-centered, zero render rig clutter!)
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
    print(f"Exported unified GLB: {GLB_OUT.relative_to(ROOT)} ({GLB_OUT.stat().st_size / (1024 * 1024):.2f} MB)", flush=True)

    # 2) Render crisp 256x256 studio transparent icons (reuse existing unless --overwrite-icons)
    overwrite_icons = "--overwrite-icons" in sys.argv
    cam_obj, rim_data = setup_studio_render()
    for _aid, _r, _zh, obj, _rot in built_objs:
        obj.hide_render = True

    scene = bpy.context.scene
    total_icon_bytes = 0
    rendered_now = 0
    for idx, (art_id, rarity, zh, obj, hero_rot) in enumerate(built_objs, 1):
        out_icon = ICON_DIR / f"{art_id}.png"
        if overwrite_icons or not out_icon.exists() or out_icon.stat().st_size < 1024:
            obj.hide_render = False
            obj.rotation_euler = Euler(tuple(math.radians(a) for a in hero_rot), "XYZ")
            rim_data.color = RARITY_RIM_COLORS[rarity]
            frame_camera_for_object(cam_obj, obj)
            scene.render.filepath = str(out_icon)
            bpy.ops.render.render(write_still=True)
            obj.rotation_euler = Euler((0, 0, 0), "XYZ")
            obj.hide_render = True
            rendered_now += 1
        b_sz = out_icon.stat().st_size
        total_icon_bytes += b_sz
        stats[art_id]["icon_bytes"] = b_sz
        if idx % 16 == 0 or idx == len(built_objs):
            print(f"  Icon progress: {idx}/{len(built_objs)} (rendered_now={rendered_now})", flush=True)

    # 3) Remove stale legacy PNGs not in registry
    valid_names = {f"{aid}.png" for aid, *_ in COLLECTIBLE_REGISTRY}
    for f in ICON_DIR.glob("*.png"):
        if f.name not in valid_names:
            f.unlink()

    summary = {
        "version": "0.8.0",
        "glb_path": str(GLB_OUT.relative_to(ROOT)).replace("\\", "/"),
        "glb_bytes": GLB_OUT.stat().st_size,
        "icon_count": len(built_objs),
        "total_icon_bytes": total_icon_bytes,
        "total_triangles": sum(v["triangles"] for v in stats.values()),
        "items": stats,
    }
    REPORT_OUT.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"DONE: {len(built_objs)} meshes + icons (GLB={summary['glb_bytes']/(1024*1024):.2f}MB, PNGs={total_icon_bytes/(1024*1024):.2f}MB)", flush=True)


if __name__ == "__main__":
    main()
    # Contact sheet built via system Python PIL if Pillow not inside Blender Python
    try:
        build_contact_sheet()
    except Exception as exc:
        print(f"NOTE: skipped in-Blender contact sheet ({exc}); run via system Python next.", flush=True)
