"""Build v0.9.9.5 Sculpted PBR Characters with 100% Complete UVs & Real Mixamo Mocap in Blender 5.3.

Produces 3 self-contained rigged + skeletally animated GLBs:
  1. game/assets/slice/npc_chen_guide.glb         — Weathered middle-aged Chen Guide (aged sculpted head + painted
     wrinkle/stubble UV skin + full layered salt-and-pepper Chen_VeteranHair + realistic cloth outdoor parka/boots +
     golden scarf + binoculars + radio + whistle + real Mixamo Breathing_Idle -> Idle_Camp)
  2. game/assets/slice/v097_mistbound_assault.glb — Heavy tactical infantry uniform + dark balaclava/visor + refined
     woven Jiangnan green bamboo hat ('斗笠') + UV-complete lamellar chest/pauldron armor + carbine + real Mixamo
     Idle_Aim / Walk_Patrol / Run_Advance
  3. game/assets/slice/v097_mistbound_sniper.glb  — Heavy obsidian-bronze marksman armor + crimson optic visor +
     wide bamboo hat + sniper half-cape & suppressed long rifle + real Mixamo Idle_Aim / Walk_Patrol / Run_Advance

All generated procedural armor/gear/hair/hat meshes receive explicit UV maps and Principled BSDF UV Texture
Coordinate links (ZERO normal_texcoord == -1 defects!).

Usage (Blender CLI):
  blender --background --factory-startup --python tools/build_v0995_characters.py -- \\
    --panzer-blend path/to/infantry.blend --mocap-dir path/to/mixamo_mocap [--preview path/to/preview_dir]
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
SLICE_DIR = ROOT / "game" / "assets" / "slice"
RIFLE_GLB = SLICE_DIR / "rifle.glb"
BLENDER_STUDIO_BLEND = ROOT / "third_party" / "slice-v052" / "human_base_meshes_bundle.blend"

TOOLS_DIR = str(Path(__file__).resolve().parent)
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

import build_v095_shaoyu_refined as s95  # noqa: E402
import build_v0993_shaoyu_mocap as m93  # noqa: E402

TMP_DIR = Path(tempfile.mkdtemp(prefix="v0995_chars_"))


def srgb(r: int, g: int, b: int) -> tuple[float, float, float]:
    return ((r / 255.0) ** 2.2, (g / 255.0) ** 2.2, (b / 255.0) ** 2.2)


def apply_box_uv_bm(bm: bmesh.types.BMesh, scale: float = 2.4):
    uv_layer = bm.loops.layers.uv.verify()
    bm.normal_update()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for lp in f.loops:
            p = lp.vert.co
            if az >= ax and az >= ay:
                u, v = p.x * scale, p.y * scale
            elif ax >= ay and ax >= az:
                u, v = p.y * scale, p.z * scale
            else:
                u, v = p.x * scale, p.z * scale
            lp[uv_layer].uv = (u, v)


def apply_conical_uv_bm(bm: bmesh.types.BMesh, center: Vector, scale_r: float = 4.5):
    uv_layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        for lp in f.loops:
            d = lp.vert.co - center
            ang = math.atan2(d.y, d.x) / (2.0 * math.pi) + 0.5
            rad = math.hypot(d.x, d.y) * scale_r
            lp[uv_layer].uv = (ang * 6.0, rad)


def make_uv_pbr_mat(
    name: str,
    color: tuple[float, float, float],
    roughness: float = 0.65,
    metallic: float = 0.0,
    normal_img=None,
    normal_scale: float = 0.35,
    tex_scale: float = 1.0,
    albedo_img=None,
    rough_img=None,
    emission=None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    """Strictly UV-mapped Principled BSDF material (NEVER uses Object coords -> ZERO normal_texcoord=-1!)."""
    if name in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials[name], do_unlink=True)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (tex_scale, tex_scale, tex_scale)
    nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])

    if albedo_img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = albedo_img
        nt.links.new(mp.outputs["Vector"], tex.inputs["Vector"])
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    if rough_img is not None:
        tr = nt.nodes.new("ShaderNodeTexImage")
        tr.image = rough_img
        nt.links.new(mp.outputs["Vector"], tr.inputs["Vector"])
        nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])

    if normal_img is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = normal_img
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_scale
        nt.links.new(mp.outputs["Vector"], tn.inputs["Vector"])
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def make_woven_bamboo_images(tag: str, base_rgb: tuple[float, float, float], size: int = 512):
    """Generate crisp procedural woven Jiangnan bamboo-hat albedo + normal maps."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / float(size)
    # Concentric radial strips + fine cross-woven splints
    ring_f = np.sin(yy * 2.0 * math.pi * 26.0)
    spoke_f = np.sin(xx * 2.0 * math.pi * 36.0 + (np.floor(yy * 26.0) % 2) * math.pi)
    weave = 0.55 * ring_f + 0.45 * spoke_f
    grain = 0.08 * np.sin(xx * 2.0 * math.pi * 120.0 + yy * 18.0)

    # Albedo (sRGB): natural lacquered Jiangnan mountain-green bamboo with warm woven highlights
    col = np.zeros((size, size, 4), dtype=np.float32)
    shade = np.clip(0.84 + 0.16 * weave + grain, 0.58, 1.12)
    col[:, :, 0] = np.clip(base_rgb[0] * shade, 0.0, 1.0)
    col[:, :, 1] = np.clip(base_rgb[1] * shade, 0.0, 1.0)
    col[:, :, 2] = np.clip(base_rgb[2] * shade, 0.0, 1.0)
    col[:, :, 3] = 1.0
    img_c = bpy.data.images.new(f"Tex_BambooDiff_{tag}", width=size, height=size, alpha=False)
    img_c.colorspace_settings.name = "sRGB"
    img_c.pixels.foreach_set(col.ravel())
    img_c.pack()

    # Normal map (Non-Color)
    h = 0.5 + 0.28 * weave + 0.08 * grain
    dx = np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)
    dy = np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)
    nx = -dx * 2.6
    ny = -dy * 2.6
    nz = np.ones_like(nx)
    inv_l = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.zeros((size, size, 4), dtype=np.float32)
    nrm[:, :, 0] = (nx * inv_l) * 0.5 + 0.5
    nrm[:, :, 1] = (ny * inv_l) * 0.5 + 0.5
    nrm[:, :, 2] = (nz * inv_l) * 0.5 + 0.5
    nrm[:, :, 3] = 1.0
    img_n = bpy.data.images.new(f"Tex_BambooNorm_{tag}", width=size, height=size, alpha=False)
    img_n.colorspace_settings.name = "Non-Color"
    img_n.pixels.foreach_set(nrm.ravel())
    img_n.pack()
    return img_c, img_n


def make_weathered_chen_face_textures(head_obj: bpy.types.Object, hinfo: dict, size: int = 512):
    """Bake a crisp 512x512 weathered middle-aged mountain-guide skin albedo + normal map onto Chen_Head's UV!

    Draws directly via UV->3D correspondence on Chen_Head's actual geometry so forehead wrinkles, crow's-feet,
    warm sun-weathered skin shading, thicker dark eyebrows, and salt-and-pepper chin/jaw stubble align 100%!
    """
    mesh = head_obj.data
    uv_layer = mesh.uv_layers.active
    if uv_layer is None:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        apply_box_uv_bm(bm, scale=3.0)
        bm.to_mesh(mesh)
        bm.free()
        uv_layer = mesh.uv_layers.active

    # Map every UV pixel center to approximate 3D head-local position by rasterizing triangles in UV space
    eye_z = float(hinfo["eye_z"])
    eye_y = float(hinfo["eye_y"])
    head_top = float(hinfo["z_max"])
    z_min = float(hinfo["z_min"])

    # Compute per-vertex weathered skin color & subtle bump height in 3D anatomical coordinates!
    # Then bake onto a clean 512x512 image via barycentric triangle rasterization!
    albedo = np.zeros((size, size, 3), dtype=np.float32)
    albedo[:, :, 0] = 0.72
    albedo[:, :, 1] = 0.53
    albedo[:, :, 2] = 0.40
    bump = np.full((size, size), 0.5, dtype=np.float32)
    covered = np.zeros((size, size), dtype=bool)

    def eval_face_point(p: Vector):
        x, y, z = p.x, p.y, p.z
        ax = abs(x)
        # Base warm sun-weathered outdoor mountain uncle skin (sRGB)
        r, g, b = 0.75, 0.55, 0.41
        h_val = 0.50

        # Front face mask (facing -Y)
        front = max(0.0, min(1.0, (eye_y + 0.055 - y) / 0.075))

        # Slight warm sun-tan gradient on nose bridge, cheeks & forehead
        cheek_sun = front * math.exp(-((ax - 0.036) / 0.032) ** 2 - ((z - (eye_z - 0.022)) / 0.026) ** 2)
        r += 0.03 * cheek_sun
        g -= 0.015 * cheek_sun
        b -= 0.025 * cheek_sun

        # Subtle hollow shadow beneath cheekbones & under-eye maturity lines
        under_eye = front * math.exp(-((ax - 0.032) / 0.020) ** 2 - ((z - (eye_z - 0.016)) / 0.007) ** 2)
        r -= 0.07 * under_eye
        g -= 0.06 * under_eye
        b -= 0.05 * under_eye
        h_val -= 0.07 * under_eye

        # 3 gentle horizontal weathered forehead creases matching chen_guide.png!
        if front > 0.3 and ax < 0.052:
            fw_fade = front * max(0.0, 1.0 - (ax / 0.052) ** 2)
            for fz_off in (0.032, 0.044, 0.056):
                d_w = abs(z - (eye_z + fz_off))
                if d_w < 0.0045:
                    t = (1.0 - d_w / 0.0045) * fw_fade
                    r -= 0.09 * t
                    g -= 0.08 * t
                    b -= 0.07 * t
                    h_val -= 0.14 * t

        # Crow's-feet creases beside outer eye corners
        if front > 0.25 and 0.044 < ax < 0.068 and abs(z - eye_z) < 0.016:
            cf = front * math.exp(-((ax - 0.055) / 0.011) ** 2) * (0.5 + 0.5 * math.cos((z - eye_z) * 520.0))
            r -= 0.055 * cf
            g -= 0.050 * cf
            b -= 0.045 * cf
            h_val -= 0.10 * cf

        # Subtle nasolabial smile folds framing nose-to-mouth
        if front > 0.35 and 0.016 < ax < 0.044 and (eye_z - 0.068) < z < (eye_z - 0.022):
            expected_x = 0.018 + (eye_z - 0.022 - z) * 0.42
            dn = abs(ax - expected_x)
            if dn < 0.0065:
                tn = (1.0 - dn / 0.0065) * front
                r -= 0.085 * tn
                g -= 0.075 * tn
                b -= 0.065 * tn
                h_val -= 0.12 * tn

        # Thick dark arched veteran eyebrows right above eye sockets
        if front > 0.35 and 0.012 < ax < 0.052:
            eb_z = eye_z + 0.019 + 0.004 * math.sin((ax - 0.012) / 0.040 * math.pi)
            de = abs(z - eb_z)
            if de < 0.0065:
                te = (1.0 - (de / 0.0065) ** 2) * front
                r = r * (1.0 - 0.78 * te) + 0.14 * 0.78 * te
                g = g * (1.0 - 0.78 * te) + 0.14 * 0.78 * te
                b = b * (1.0 - 0.78 * te) + 0.16 * 0.78 * te
                h_val += 0.10 * te

        # Mature weathered lip tone (calm muted brick-tan, NOT bright pink!)
        if front > 0.5 and ax < 0.028 and abs(z - (eye_z - 0.058)) < 0.009:
            tl = (1.0 - (ax / 0.028) ** 2) * (1.0 - abs(z - (eye_z - 0.058)) / 0.009) * front
            r = r * (1.0 - 0.45 * tl) + 0.54 * 0.45 * tl
            g = g * (1.0 - 0.45 * tl) + 0.34 * 0.45 * tl
            b = b * (1.0 - 0.45 * tl) + 0.28 * 0.45 * tl

        # Signature salt-and-pepper weathered beard stubble with smooth organic falloff (ZERO sharp box edges!)
        chin_w = math.exp(-((ax / 0.044) ** 2)) * max(0.0, 1.0 - max(0.0, (z - (eye_z - 0.068)) / 0.016)) * max(0.0, min(1.0, (z - (z_min + 0.012)) / 0.018)) * max(0.0, min(1.0, (eye_y + 0.065 - y) / 0.035))
        must_w = math.exp(-((ax / 0.022) ** 2)) * math.exp(-(((z - (eye_z - 0.047)) / 0.0065) ** 2)) * max(0.0, front)
        jaw_w = math.exp(-(((ax - 0.046) / 0.018) ** 2)) * math.exp(-(((z - (eye_z - 0.064)) / 0.024) ** 2)) * max(0.0, min(1.0, (eye_y + 0.062 - y) / 0.032))
        stubble_mask = min(1.0, max(chin_w * 0.85, must_w * 0.72, jaw_w * 0.45))
        if stubble_mask > 0.03:
            grain = math.sin(x * 1850.0 + z * 2300.0) * math.cos(y * 1950.0 - z * 2100.0)
            sw = stubble_mask * 0.32
            if grain > 0.30:
                r = r * (1.0 - sw * 0.55) + 0.60 * sw * 0.55
                g = g * (1.0 - sw * 0.55) + 0.60 * sw * 0.55
                b = b * (1.0 - sw * 0.55) + 0.62 * sw * 0.55
            else:
                r = r * (1.0 - sw) + 0.28 * sw
                g = g * (1.0 - sw) + 0.24 * sw
                b = b * (1.0 - sw) + 0.21 * sw
            h_val += 0.035 * grain * stubble_mask

        # Neck slightly warmer-shaded under jaw
        if z < eye_z - 0.085:
            nt_s = min(1.0, (eye_z - 0.085 - z) / 0.05)
            r *= (1.0 - 0.14 * nt_s)
            g *= (1.0 - 0.14 * nt_s)
            b *= (1.0 - 0.12 * nt_s)

        return (max(0.0, min(1.0, r)), max(0.0, min(1.0, g)), max(0.0, min(1.0, b))), max(0.0, min(1.0, h_val))

    # Rasterize every mesh triangle into UV space
    uv_data = uv_layer.data
    verts = mesh.vertices
    mesh.calc_loop_triangles()
    for tri in mesh.loop_triangles:
        u0, v0 = uv_data[tri.loops[0]].uv
        u1, v1 = uv_data[tri.loops[1]].uv
        u2, v2 = uv_data[tri.loops[2]].uv
        p0 = verts[tri.vertices[0]].co
        p1 = verts[tri.vertices[1]].co
        p2 = verts[tri.vertices[2]].co

        x0, y0 = u0 * (size - 1), v0 * (size - 1)
        x1, y1 = u1 * (size - 1), v1 * (size - 1)
        x2, y2 = u2 * (size - 1), v2 * (size - 1)
        min_x = max(0, int(math.floor(min(x0, x1, x2))) - 1)
        max_x = min(size - 1, int(math.ceil(max(x0, x1, x2))) + 1)
        min_y = max(0, int(math.floor(min(y0, y1, y2))) - 1)
        max_y = min(size - 1, int(math.ceil(max(y0, y1, y2))) + 1)
        denom = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(denom) < 1e-6:
            continue
        inv_d = 1.0 / denom
        for py in range(min_y, max_y + 1):
            for px in range(min_x, max_x + 1):
                w0 = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) * inv_d
                w1 = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) * inv_d
                w2 = 1.0 - w0 - w1
                if w0 >= -0.02 and w1 >= -0.02 and w2 >= -0.02:
                    pt = p0 * w0 + p1 * w1 + p2 * w2
                    rgb, hv = eval_face_point(pt)
                    albedo[py, px, 0] = rgb[0]
                    albedo[py, px, 1] = rgb[1]
                    albedo[py, px, 2] = rgb[2]
                    bump[py, px] = hv
                    covered[py, px] = True

    # Dilate 3px into uncovered UV gutters to eliminate mip seam bleeding
    for _ in range(3):
        for dy_s, dx_s in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            sh_cov = np.roll(np.roll(covered, dy_s, axis=0), dx_s, axis=1)
            fill = (~covered) & sh_cov
            if np.any(fill):
                albedo[fill] = np.roll(np.roll(albedo, dy_s, axis=0), dx_s, axis=1)[fill]
                bump[fill] = np.roll(np.roll(bump, dy_s, axis=0), dx_s, axis=1)[fill]
                covered[fill] = True

    rgba = np.ones((size, size, 4), dtype=np.float32)
    rgba[:, :, :3] = albedo
    img_c = bpy.data.images.new("Tex_ChenFaceDiff", width=size, height=size, alpha=False)
    img_c.colorspace_settings.name = "sRGB"
    img_c.pixels.foreach_set(rgba.ravel())
    img_c.pack()

    dx = np.roll(bump, -1, axis=1) - np.roll(bump, 1, axis=1)
    dy = np.roll(bump, -1, axis=0) - np.roll(bump, 1, axis=0)
    nx = -dx * 2.2
    ny = -dy * 2.2
    nz = np.ones_like(nx)
    inv_l = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.ones((size, size, 4), dtype=np.float32)
    nrm[:, :, 0] = (nx * inv_l) * 0.5 + 0.5
    nrm[:, :, 1] = (ny * inv_l) * 0.5 + 0.5
    nrm[:, :, 2] = (nz * inv_l) * 0.5 + 0.5
    img_n = bpy.data.images.new("Tex_ChenFaceNorm", width=size, height=size, alpha=False)
    img_n.colorspace_settings.name = "Non-Color"
    img_n.pixels.foreach_set(nrm.ravel())
    img_n.pack()
    return img_c, img_n


def downscale_and_retexture_panzer_uniform(
    img_diff: bpy.types.Image,
    img_norm: bpy.types.Image,
    img_ruff: bpy.types.Image,
    variant: str,
    target_size: int = 1024,
):
    """Sanitize & recolor the infantry uniform PBR maps cleanly in numpy:
    1. 100% paints over all 4 tiny historical WW2 patches (chest eagle, 2 collar tabs, sleeve chevron)
       using clean neighboring cloth pixels so ZERO WW2 insignia remain anywhere!
    2. Recolors uniform fabric into Jiangnan Mistbound pine-teal / obsidian-slate / Chen olive parka,
       and masks face/skin UV islands into dark tactical balaclava for Mistbound variants.
    3. Downscales 2048 -> 1024 JPG/PNG cleanly for lean game-ready GLBs!
    """
    w0, h0 = img_diff.size[0], img_diff.size[1]
    pix = np.empty(w0 * h0 * 4, dtype=np.float32)
    img_diff.pixels.foreach_get(pix)
    arr = pix.reshape((h0, w0, 4)).copy()  # Blender bottom-to-top (row 0 = bottom v=0, row h0-1 = top v=1)

    # Convert from bottom-to-top to top-to-bottom coordinates for intuitive patch removal matching panzer_diff_raw.png
    top_arr = arr[::-1, :, :].copy()

    def clean_patch(x0_f, y0_f, x1_f, y1_f, sx_f, sy_f):
        px0, px1 = int(x0_f * w0), int(x1_f * w0)
        py0, py1 = int(y0_f * h0), int(y1_f * h0)
        sx0 = int(sx_f * w0)
        sy0 = int(sy_f * h0)
        ph, pw = py1 - py0, px1 - px0
        # Sample clean cloth patch of identical size & blend smoothly
        src = top_arr[sy0:sy0 + ph, sx0:sx0 + pw, :3]
        if src.shape[0] == ph and src.shape[1] == pw:
            top_arr[py0:py1, px0:px1, :3] = src

    # 1) Remove ALL 4 historical WW2 markings with adjacent clean wool cloth samples:
    clean_patch(0.215, 0.595, 0.258, 0.638, 0.050, 0.600)  # Chest eagle -> clean jacket fabric
    clean_patch(0.205, 0.540, 0.250, 0.585, 0.050, 0.540)  # Left collar tab -> clean jacket fabric
    clean_patch(0.770, 0.562, 0.818, 0.610, 0.720, 0.300)  # Right collar tab -> clean jacket fabric
    clean_patch(0.915, 0.672, 0.965, 0.748, 0.855, 0.680)  # Right sleeve chevron -> clean sleeve fabric

    # 2) Separate cloth vs leather/dark straps vs skin pixels by HSV/RGB heuristics
    r = top_arr[:, :, 0]
    g = top_arr[:, :, 1]
    b = top_arr[:, :, 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    is_skin = (r > g * 1.12) & (g > b * 1.06) & (r > 0.25) & (lum > 0.18)
    is_cloth = (~is_skin) & (lum > 0.16) & (np.abs(r - b) < 0.14) & (g >= b * 0.94)
    is_dark_leather = (~is_skin) & (~is_cloth) & (lum > 0.02)

    if variant == "assault":
        # Rich Jiangnan Mistbound pine-teal uniform + dark charcoal tactical balaclava mask/gloves!
        top_arr[is_cloth, 0] = np.clip(lum[is_cloth] * 0.40, 0.0, 1.0)
        top_arr[is_cloth, 1] = np.clip(lum[is_cloth] * 0.72, 0.0, 1.0)
        top_arr[is_cloth, 2] = np.clip(lum[is_cloth] * 0.64, 0.0, 1.0)
        # Mask face & bare hands into matte dark tactical balaclava & gloves
        top_arr[is_skin, 0] = np.clip(lum[is_skin] * 0.16, 0.0, 1.0)
        top_arr[is_skin, 1] = np.clip(lum[is_skin] * 0.22, 0.0, 1.0)
        top_arr[is_skin, 2] = np.clip(lum[is_skin] * 0.23, 0.0, 1.0)
    elif variant == "sniper":
        # Heavy obsidian-slate marksman uniform + matte charcoal balaclava & gloves!
        top_arr[is_cloth, 0] = np.clip(lum[is_cloth] * 0.36, 0.0, 1.0)
        top_arr[is_cloth, 1] = np.clip(lum[is_cloth] * 0.38, 0.0, 1.0)
        top_arr[is_cloth, 2] = np.clip(lum[is_cloth] * 0.42, 0.0, 1.0)
        top_arr[is_skin, 0] = np.clip(lum[is_skin] * 0.14, 0.0, 1.0)
        top_arr[is_skin, 1] = np.clip(lum[is_skin] * 0.16, 0.0, 1.0)
        top_arr[is_skin, 2] = np.clip(lum[is_skin] * 0.18, 0.0, 1.0)
    elif variant == "chen":
        # Deep forest-olive mountain ranger parka + warm weathered hands + warm saddle-brown harness/boots!
        top_arr[is_cloth, 0] = np.clip(lum[is_cloth] * 0.42, 0.0, 1.0)
        top_arr[is_cloth, 1] = np.clip(lum[is_cloth] * 0.64, 0.0, 1.0)
        top_arr[is_cloth, 2] = np.clip(lum[is_cloth] * 0.44, 0.0, 1.0)
        top_arr[is_dark_leather, 0] = np.clip(top_arr[is_dark_leather, 0] * 1.15 + 0.03, 0.0, 1.0)
        top_arr[is_dark_leather, 1] = np.clip(top_arr[is_dark_leather, 1] * 0.92 + 0.015, 0.0, 1.0)
        top_arr[is_dark_leather, 2] = np.clip(top_arr[is_dark_leather, 2] * 0.72, 0.0, 1.0)
        # Warm tanned mountain ranger hands
        top_arr[is_skin, 0] = np.clip(top_arr[is_skin, 0] * 0.96, 0.0, 1.0)
        top_arr[is_skin, 1] = np.clip(top_arr[is_skin, 1] * 0.86, 0.0, 1.0)
        top_arr[is_skin, 2] = np.clip(top_arr[is_skin, 2] * 0.76, 0.0, 1.0)

    # Flip back to Blender bottom-to-top and save + downscale to 1024px JPEG cleanly
    out_arr = top_arr[::-1, :, :]
    tmp_raw = bpy.data.images.new(f"_tmp_diff_{variant}", width=w0, height=h0, alpha=False)
    tmp_raw.pixels.foreach_set(out_arr.ravel())
    raw_png = TMP_DIR / f"uni_diff_{variant}_raw.png"
    tmp_raw.filepath_raw = str(raw_png)
    tmp_raw.file_format = "PNG"
    tmp_raw.save()
    bpy.data.images.remove(tmp_raw)

    def _shrink_to_jpg(src_img_or_path, out_name: str, colorspace: str, sz: int = target_size):
        if isinstance(src_img_or_path, bpy.types.Image):
            src_p = TMP_DIR / f"{out_name}_src.png"
            src_img_or_path.filepath_raw = str(src_p)
            src_img_or_path.file_format = "PNG"
            src_img_or_path.save()
        else:
            src_p = Path(src_img_or_path)
        dst_p = TMP_DIR / f"{out_name}.jpg"
        ffmpeg = shutil.which("ffmpeg")
        if ffmpeg:
            subprocess.run(
                [ffmpeg, "-y", "-v", "error", "-i", str(src_p), "-vf", f"scale={sz}:{sz}", "-q:v", "4", str(dst_p)],
                check=True,
            )
            load_p = dst_p
        else:
            load_p = src_p
        im = bpy.data.images.load(str(load_p), check_existing=False)
        im.name = out_name
        im.colorspace_settings.name = colorspace
        im.pack()
        return im

    new_diff = _shrink_to_jpg(raw_png, f"Tex_UniDiff_{variant}", "sRGB", target_size)
    new_norm = _shrink_to_jpg(img_norm, f"Tex_UniNorm_{variant}", "Non-Color", 512) if img_norm else None
    new_ruff = _shrink_to_jpg(img_ruff, f"Tex_UniRuff_{variant}", "Non-Color", 512) if img_ruff else None
    return new_diff, new_norm, new_ruff


def load_normalized_infantry_base(panzer_blend: Path, target_height: float, keep_pouches: bool):
    """Open WW2 Panzergrenadier.blend, normalize scale to exact target_height (m), feet at Z=0, facing -Y,
    delete WW2 helmet, add Weapon_R bone, and return (arm, main_obj, pouches_obj_or_None).
    """
    bpy.ops.wm.open_mainfile(filepath=str(panzer_blend))

    # Delete helmet and any stray cameras/lights
    for obj in list(bpy.data.objects):
        if obj.name == "helmet" or obj.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(obj, do_unlink=True)
    if not keep_pouches:
        pouch = bpy.data.objects.get("ammopouches")
        if pouch is not None:
            bpy.data.objects.remove(pouch, do_unlink=True)

    arm = bpy.data.objects["Armature"]
    main_obj = bpy.data.objects["main"]
    pouches_obj = bpy.data.objects.get("ammopouches") if keep_pouches else None

    # Clear any pre-existing animation on Armature so we inspect true rest pose
    if arm.animation_data:
        arm.animation_data_clear()
    for pb in arm.pose.bones:
        pb.location = Vector((0, 0, 0))
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.rotation_euler = Euler((0, 0, 0))
        pb.scale = Vector((1, 1, 1))
    bpy.context.view_layer.update()

    # Apply transforms cleanly on mesh objects while keeping Armature at origin -> measure true bounds
    mesh_objs = [o for o in (main_obj, pouches_obj) if o is not None]
    pts = []
    for o in mesh_objs:
        mw = o.matrix_world
        pts.extend([mw @ v.co for v in o.data.vertices])
    min_z = min(p.z for p in pts)
    max_z = max(p.z for p in pts)
    raw_h = max(0.01, max_z - min_z)
    sc = target_height / raw_h

    # Scale Armature + meshes uniformly & ground feet at Z = 0.000m, centered at X=0, Y=0!
    cx = 0.5 * (min(p.x for p in pts) + max(p.x for p in pts))
    cy = 0.5 * (min(p.y for p in pts) + max(p.y for p in pts))
    arm.location = Vector((-cx * sc, -cy * sc, -min_z * sc))
    arm.scale = Vector((sc, sc, sc))
    bpy.context.view_layer.update()

    # Bake scale & translation into Armature & Meshes cleanly so Armature scale == (1, 1, 1)!
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for o in mesh_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.update()

    # Add Weapon_R bone as child of mixamorig:RightHand!
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    hr = eb["mixamorig:RightHand"]
    wr = eb.new("Weapon_R")
    wr.parent = hr
    wr.head = hr.head + (hr.tail - hr.head) * 0.55
    # Point strictly along +Y with roll=0 -> matrix_local.to_3x3() == Identity(3) matching m93 Weapon_R space 1:1!
    wr.tail = wr.head + Vector((0.0, 0.22, 0.0))
    wr.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()

    return arm, main_obj, pouches_obj


def attach_uv_mesh_to_bone(
    arm: bpy.types.Object,
    name: str,
    bm: bmesh.types.BMesh,
    mats: list[bpy.types.Material],
    bone_name: str,
    uv_scale: float = 2.4,
    conical_center: Vector | None = None,
    smooth: bool = True,
) -> bpy.types.Object:
    bm.normal_update()
    if conical_center is not None:
        apply_conical_uv_bm(bm, conical_center, scale_r=uv_scale)
    else:
        apply_box_uv_bm(bm, scale=uv_scale)
    for f in bm.faces:
        f.smooth = smooth
    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add([v.index for v in me.vertices], 1.0, "REPLACE")
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    return obj


def preload_mocap_cache(mocap_dir: Path, files_and_max: list[tuple[str, int]]) -> dict[str, dict]:
    """Sample all unique Mixamo FBX clips BEFORE loading target scenes (sample_mixamo_fbx resets Blender scene!)."""
    cache: dict[str, dict] = {}
    for fbx_file, max_f in files_and_max:
        if fbx_file in cache:
            continue
        p = mocap_dir / fbx_file
        raw = m93.sample_mixamo_fbx(p, max_frames=max_f)
        conv_frames = []
        for fd in raw["frames"]:
            nd = {}
            for sk, mat in fd["deltas"].items():
                mk = m93.SHAOYU_TO_MIXAMO.get(sk)
                if mk:
                    nd[mk] = mat
            conv_frames.append({
                "src_fr": fd["src_fr"],
                "hips_pos": fd["hips_pos"],
                "hips_disp": fd["hips_disp"],
                "deltas": nd,
            })
        conv_dirs = {}
        for sk, dv in raw["rest_dir"].items():
            mk = m93.SHAOYU_TO_MIXAMO.get(sk)
            if mk:
                conv_dirs[mk] = dv
        cache[fbx_file] = {
            "src_hip_h": raw["src_hip_h"],
            "src_dirs": conv_dirs,
            "frames": conv_frames,
        }
    return cache


def retarget_mixamo_clips(
    arm: bpy.types.Object,
    body_meshes: list[bpy.types.Object],
    mocap_cache: dict[str, dict],
    clip_specs: list[tuple[str, str, str, bool, int]],
):
    """Retarget real studio Mixamo FBX mocap clips directly onto a 64-bone mixamorig:* skeleton!
    clip_specs: [(anim_name, fbx_filename, mode, inplace_detrend, max_frames)]
      mode: "unarmed" | "rifle_2h"
    """
    align_set = {
        "mixamorig:LeftArm", "mixamorig:LeftForeArm", "mixamorig:LeftHand",
        "mixamorig:RightArm", "mixamorig:RightForeArm", "mixamorig:RightHand",
        "mixamorig:LeftUpLeg", "mixamorig:LeftLeg", "mixamorig:LeftFoot", "mixamorig:LeftToeBase",
        "mixamorig:RightUpLeg", "mixamorig:RightLeg", "mixamorig:RightFoot", "mixamorig:RightToeBase",
    }

    mw = arm.matrix_world.copy()
    mw_rot = mw.to_3x3().normalized()
    tgt_rest_rot: dict[str, Matrix] = {}
    tgt_rest_dir: dict[str, Vector] = {}
    for b in arm.data.bones:
        tgt_rest_rot[b.name] = mw_rot @ b.matrix_local.to_3x3().normalized()
        d = (mw @ b.tail_local) - (mw @ b.head_local)
        tgt_rest_dir[b.name] = d.normalized() if d.length > 1e-6 else Vector((0, 0, 1))

    ref_dirs = next(iter(mocap_cache.values()))["src_dirs"]
    bind_corr: dict[str, Matrix] = {}
    for bn in arm.data.bones.keys():
        if bn in align_set and bn in ref_dirs:
            q_al = tgt_rest_dir[bn].rotation_difference(ref_dirs[bn])
            bind_corr[bn] = q_al.to_matrix()
        else:
            bind_corr[bn] = Matrix.Identity(3)
    for side in ("Left", "Right"):
        hc = bind_corr.get(f"mixamorig:{side}Hand", Matrix.Identity(3))
        for fg in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
            for i in (1, 2, 3, 4):
                fn = f"mixamorig:{side}Hand{fg}{i}"
                if fn in bind_corr:
                    bind_corr[fn] = hc

    topo: list[str] = []
    vis: set[str] = set()
    def visit(bn: str):
        if bn in vis:
            return
        b = arm.data.bones[bn]
        if b.parent:
            visit(b.parent.name)
        vis.add(bn)
        topo.append(bn)
    for b in arm.data.bones:
        visit(b.name)

    tgt_hip_h = float((mw @ arm.data.bones["mixamorig:Hips"].head_local).z)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.use_nla = False

    actions: list[bpy.types.Action] = []
    for anim_name, fbx_file, mode, inplace_detrend, _ in clip_specs:
        mc = mocap_cache[fbx_file]
        frames = mc["frames"]
        n_fr = len(frames)
        hip_scale = tgt_hip_h / max(0.25, float(mc["src_hip_h"]))

        h0_xy = Vector((frames[0]["hips_pos"].x, frames[0]["hips_pos"].y, 0.0))
        h1_xy = Vector((frames[-1]["hips_pos"].x, frames[-1]["hips_pos"].y, 0.0))
        xy_list = []
        for idx, fd in enumerate(frames):
            u = idx / float(max(1, n_fr - 1))
            cxy = Vector((fd["hips_pos"].x, fd["hips_pos"].y, 0.0))
            if inplace_detrend:
                xy_list.append((cxy - h0_xy.lerp(h1_xy, u)) * hip_scale)
            else:
                xy_list.append((cxy - h0_xy) * hip_scale)
        if inplace_detrend and n_fr > 1:
            mean_xy = sum(xy_list, Vector((0, 0, 0))) / float(n_fr)
            xy_list = [v - mean_xy for v in xy_list]

        act = bpy.data.actions.new(name=anim_name)
        arm.animation_data.action = act
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.location = Vector((0, 0, 0))
            pb.rotation_quaternion = Quaternion((1, 0, 0, 0))

        def pose_at(idx: int, z_lift: float, keyframe: bool, out_fr: int):
            fd = frames[idx]
            deltas = fd["deltas"]
            hips_w = Vector((xy_list[idx].x, xy_list[idx].y, fd["hips_disp"].z * hip_scale + z_lift))
            cur_w: dict[str, Matrix] = {}
            for bn in topo:
                b = arm.data.bones[bn]
                pb = arm.pose.bones[bn]
                pn = b.parent.name if b.parent else None
                if bn == "Weapon_R":
                    q_loc = Quaternion((1, 0, 0, 0))
                    cur_w[bn] = cur_w[pn] @ (tgt_rest_rot[pn].inverted() @ tgt_rest_rot[bn])
                elif bn in deltas:
                    m_tw = deltas[bn] @ bind_corr[bn] @ tgt_rest_rot[bn]
                    if pn:
                        m_exp = cur_w[pn] @ (tgt_rest_rot[pn].inverted() @ tgt_rest_rot[bn])
                        q_loc = (m_exp.inverted() @ m_tw).to_quaternion()
                    else:
                        q_loc = (tgt_rest_rot[bn].inverted() @ m_tw).to_quaternion()
                    cur_w[bn] = m_tw
                else:
                    q_loc = Quaternion((1, 0, 0, 0))
                    cur_w[bn] = (cur_w[pn] @ (tgt_rest_rot[pn].inverted() @ tgt_rest_rot[bn])) if pn else tgt_rest_rot[bn]
                pb.rotation_quaternion = q_loc
                if bn == "mixamorig:Hips":
                    pb.location = tgt_rest_rot["mixamorig:Hips"].inverted() @ hips_w
                if keyframe:
                    pb.keyframe_insert(data_path="rotation_quaternion", frame=out_fr)
                    if bn == "mixamorig:Hips":
                        pb.keyframe_insert(data_path="location", frame=out_fr)

            bpy.context.view_layer.update()

            if mode == "rifle_2h" and "Weapon_R" in arm.pose.bones:
                pb_hr = arm.pose.bones["mixamorig:RightHand"]
                pb_hl = arm.pose.bones["mixamorig:LeftHand"]
                pb_wr = arm.pose.bones["Weapon_R"]
                m1r = arm.pose.bones.get("mixamorig:RightHandMiddle1")
                m1l = arm.pose.bones.get("mixamorig:LeftHandMiddle1")
                pr = (mw @ pb_hr.head).lerp(mw @ m1r.head, 0.55) if m1r else (mw @ pb_hr.tail)
                pl = (mw @ pb_hl.head).lerp(mw @ m1l.head, 0.55) if m1l else (mw @ pb_hl.tail)
                hv = pl - pr
                if hv.length > 0.14:
                    m_hl = m93.build_bone_basis(hv.normalized(), Vector((0, 0, 1)))
                    m_wr = m_hl @ Matrix.Rotation(-m93.RIFLE_HANDLINE_PITCH_RAD, 3, "X")
                    p_wr = pr - (m_wr @ m93.RIFLE_GRIP_IN_WEAP)
                else:
                    m_wr = m93.build_bone_basis(Vector((0, -1, 0)), Vector((0, 0, 1)))
                    p_wr = pr - (m_wr @ m93.RIFLE_GRIP_IN_WEAP)
                # Solve Weapon_R local pose relative to RightHand parent
                hr_m = mw @ pb_hr.matrix
                hr_rot = hr_m.to_3x3().normalized()
                wr_rest_in_hr = arm.data.bones["mixamorig:RightHand"].matrix_local.inverted() @ arm.data.bones["Weapon_R"].matrix_local
                exp_wr_m = hr_m @ wr_rest_in_hr
                exp_wr_rot = exp_wr_m.to_3x3().normalized()
                pb_wr.rotation_quaternion = (exp_wr_rot.inverted() @ m_wr).to_quaternion()
                pb_wr.location = exp_wr_rot.inverted() @ (p_wr - exp_wr_m.translation)
                if keyframe:
                    pb_wr.keyframe_insert(data_path="rotation_quaternion", frame=out_fr)
                    pb_wr.keyframe_insert(data_path="location", frame=out_fr)

        # Measure ground contact on frame 0 and mid-frame so feet plant cleanly on Z = 0.000m!
        sample_min_zs = []
        for s_idx in sorted({0, n_fr // 2}):
            pose_at(s_idx, 0.0, False, 1)
            deps = bpy.context.evaluated_depsgraph_get()
            mz = 1e9
            for bo in body_meshes:
                eo = bo.evaluated_get(deps)
                me = eo.to_mesh()
                bmw = eo.matrix_world
                for v in me.vertices:
                    z = (bmw @ v.co).z
                    if z < mz:
                        mz = z
                eo.to_mesh_clear()
            sample_min_zs.append(mz)
        z_lift = -min(sample_min_zs) if sample_min_zs else 0.0

        for idx in range(n_fr):
            pose_at(idx, z_lift, True, idx + 1)

        act.use_fake_user = True
        actions.append(act)

    # Push all actions onto NLA tracks for clean glTF export
    arm.animation_data.action = None
    for tr in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(tr)
    for act in actions:
        tr = arm.animation_data.nla_tracks.new()
        tr.name = act.name
        st = tr.strips.new(act.name, int(round(act.frame_range[0])), act)
        st.name = act.name
        tr.mute = True
    for pb in arm.pose.bones:
        pb.location = Vector((0, 0, 0))
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
    bpy.context.view_layer.update()


def build_mistbound_rifle_from_glb(arm: bpy.types.Object, is_sniper: bool, mat_gun, mat_bronze, mat_optic) -> bpy.types.Object:
    """Import real detailed rifle.glb carbine, align barrel along +Y (matching m93 Weapon_R space 1:1!), lock to Weapon_R!"""
    wb = arm.data.bones["Weapon_R"]
    origin = wb.head_local
    bm = bmesh.new()

    if RIFLE_GLB.exists():
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(RIFLE_GLB))
        imported = [o for o in bpy.data.objects if o not in before]
        bpy.context.view_layer.update()
        imp_meshes = [o for o in imported if o.type == "MESH"]
        if imp_meshes:
            pts = [o.matrix_world @ v.co for o in imp_meshes for v in o.data.vertices]
            min_v = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
            max_v = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
            dims = max_v - min_v
            # Align longest horizontal axis onto Y
            rot_m = Matrix.Identity(4)
            if dims.x > dims.y and dims.x > dims.z:
                rot_m = Matrix.Rotation(math.pi * 0.5, 4, "Z")
            rpts = [rot_m @ p for p in pts]
            rmin = Vector((min(p.x for p in rpts), min(p.y for p in rpts), min(p.z for p in rpts)))
            rmax = Vector((max(p.x for p in rpts), max(p.y for p in rpts), max(p.z for p in rpts)))
            rlen = max(0.1, rmax.y - rmin.y)
            # Determine which end is thin barrel vs taller stock so barrel ALWAYS points toward +Y!
            low_z = [p.z for p in rpts if p.y < rmin.y + rlen * 0.16]
            hi_z = [p.z for p in rpts if p.y > rmax.y - rlen * 0.16]
            low_span = (max(low_z) - min(low_z)) if low_z else 1.0
            hi_span = (max(hi_z) - min(hi_z)) if hi_z else 1.0
            if low_span < hi_span:
                # Thin muzzle is currently at -Y -> flip 180 deg around Z so muzzle points +Y!
                rot_m = Matrix.Rotation(math.pi, 4, "Z") @ rot_m
                rpts = [rot_m @ p for p in pts]
                rmin = Vector((min(p.x for p in rpts), min(p.y for p in rpts), min(p.z for p in rpts)))
                rmax = Vector((max(p.x for p in rpts), max(p.y for p in rpts), max(p.z for p in rpts)))
                rlen = max(0.1, rmax.y - rmin.y)
            target_len = 0.98 if is_sniper else 0.82
            sc = target_len / rlen
            # Place pistol grip near (0, -0.095, -0.052) and barrel extending cleanly along +Y!
            rcen = Vector((0.5 * (rmin.x + rmax.x), rmin.y + rlen * 0.38, rmin.z + (rmax.z - rmin.z) * 0.44))
            for o in imp_meshes:
                tbm = bmesh.new()
                tbm.from_mesh(o.data)
                for v in tbm.verts:
                    wp = rot_m @ (o.matrix_world @ v.co)
                    v.co = origin + (wp - rcen) * sc
                # Unify all imported rifle faces onto mat_idx=0 (dark matte tactical gunmetal!)
                for f in tbm.faces:
                    f.material_index = 0
                tme = bpy.data.meshes.new("_tmp_rif")
                tbm.to_mesh(tme)
                tbm.free()
                bm.from_mesh(tme)
                bpy.data.meshes.remove(tme)
        for o in imported:
            if o.name in bpy.data.objects:
                bpy.data.objects.remove(o, do_unlink=True)

    # Sniper suppressor & high-zoom optic / Assault reflex sight along +Y barrel!
    def p(dx, dy, dz):
        return origin + Vector((dx, dy, dz))

    if len(bm.verts) < 20:
        s95.add_box_mesh(bm, p(0.0, 0.05, 0.045), (0.052, 0.42, 0.086), mat_idx=0, bevel=0.006)
        s95.add_cyl_mesh(bm, p(0.0, 0.42, 0.052), 0.015, 0.014, 0.38, segs=12, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=0)
        s95.add_box_mesh(bm, p(0.0, -0.22, 0.036), (0.042, 0.25, 0.070), mat_idx=0, bevel=0.005)
        s95.add_box_mesh(bm, p(0.0, -0.095, -0.045), (0.034, 0.052, 0.112), rot_euler=(0.22, 0, 0), mat_idx=0, bevel=0.004)
    if is_sniper:
        # Matte gunmetal sniper suppressor + dark scope tube with subtle crimson objective lens
        s95.add_cyl_mesh(bm, p(0.0, 0.58, 0.036), 0.018, 0.018, 0.22, segs=12, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=0)
        s95.add_cyl_mesh(bm, p(0.0, 0.48, 0.036), 0.020, 0.020, 0.022, segs=12, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=1)
        s95.add_cyl_mesh(bm, p(0.0, 0.06, 0.110), 0.020, 0.016, 0.24, segs=12, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=0)
        s95.add_cyl_mesh(bm, p(0.0, 0.184, 0.110), 0.016, 0.016, 0.008, segs=12, rot_euler=(math.pi * 0.5, 0, 0), mat_idx=2)
    else:
        # Compact low-profile dark optic housing + subtle cyan lens dot
        s95.add_box_mesh(bm, p(0.0, 0.04, 0.096), (0.030, 0.078, 0.032), mat_idx=0, bevel=0.004)
        s95.add_box_mesh(bm, p(0.0, 0.080, 0.096), (0.018, 0.006, 0.016), mat_idx=2, bevel=0.002)

    return attach_uv_mesh_to_bone(arm, "Mistbound_Rifle", bm, [mat_gun, mat_bronze, mat_optic], "Weapon_R", uv_scale=3.0)


def export_char_glb(arm: bpy.types.Object, meshes: list[bpy.types.Object], out_path: Path):
    # Guarantee EVERY single exported mesh is topologically valid AND has at least 1 UV map!
    for o in meshes:
        if o and o.type == "MESH":
            o.data.validate(verbose=False)
            if not o.data.uv_layers:
                bm = bmesh.new()
                bm.from_mesh(o.data)
                apply_box_uv_bm(bm, scale=2.4)
                bm.to_mesh(o.data)
                bm.free()

    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for o in meshes:
        if o and o.name in bpy.data.objects:
            o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_nla_strips_merged_animation_name="",
        export_optimize_animation_size=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    kb = out_path.stat().st_size / 1024.0
    tris = sum(len(o.data.polygons) for o in meshes if o and o.name in bpy.data.objects)
    n_anims = len(arm.animation_data.nla_tracks) if arm.animation_data else 0
    print(f"EXPORTED_V0995 {out_path.name} ({kb:.0f} KB | {tris} polys | {n_anims} anims)")


# ===========================================================================
# 1. Weathered Middle-Aged Camp Liaison: 陈向导 (npc_chen_guide.glb)
# ===========================================================================
def build_chen_guide(panzer_blend: Path, mocap_cache: dict[str, dict], preview_dir: Path | None = None):
    arm, main_obj, _ = load_normalized_infantry_base(panzer_blend, target_height=1.74, keep_pouches=False)
    arm.name = "ChenGuideArmature"

    # Retexture infantry uniform into deep forest-olive Jiangnan ranger parka + warm brown straps/boots (ZERO WW2 badges!)
    img_diff = bpy.data.images.get("panzergren_low2k_diff.png")
    img_norm = bpy.data.images.get("panzergren_low2k_norm.png")
    img_ruff = bpy.data.images.get("panzergren_low2k_ruff.png")
    c_diff, c_norm, c_ruff = downscale_and_retexture_panzer_uniform(img_diff, img_norm, img_ruff, "chen", target_size=1024)
    m_parka = make_uv_pbr_mat("Chen_ParkaBody", srgb(56, 82, 62), roughness=0.78, normal_img=c_norm, normal_scale=0.60, albedo_img=c_diff, rough_img=c_ruff)
    main_obj.data.materials.clear()
    main_obj.data.materials.append(m_parka)

    # Cleanly remove European bald head polygons above neck base (keep realistic folded collar & parka body!)
    neck_b = arm.data.bones["mixamorig:Neck"]
    head_b = arm.data.bones["mixamorig:Head"]
    cut_z = float(neck_b.head_local.z + (head_b.head_local.z - neck_b.head_local.z) * 0.55)
    vg_names = {vg.index: vg.name for vg in main_obj.vertex_groups}
    bm_cut = bmesh.new()
    bm_cut.from_mesh(main_obj.data)
    bm_cut.faces.ensure_lookup_table()
    deform = bm_cut.verts.layers.deform.active
    del_faces = []
    for f in bm_cut.faces:
        cz = f.calc_center_median().z
        head_w = 0.0
        for v in f.verts:
            if deform is not None:
                for gi, w in v[deform].items():
                    if "Head" in vg_names.get(gi, ""):
                        head_w += w
        head_w /= max(1, len(f.verts))
        if cz > cut_z or head_w > 0.35:
            del_faces.append(f)
    bmesh.ops.delete(bm_cut, geom=del_faces, context="FACES")
    loose = [v for v in bm_cut.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm_cut, geom=loose, context="VERTS")
    bm_cut.to_mesh(main_obj.data)
    bm_cut.free()
    main_obj.data.update()
    main_obj.name = "Chen_ParkaMesh"

    # Load Blender Studio CC0 stylized male head & anatomically AGE it into a weathered middle-aged mountain guide!
    with bpy.data.libraries.load(str(BLENDER_STUDIO_BLEND), link=False) as (data_from, data_to):
        data_to.objects = [n for n in ("GEO-body_male_stylized", "GEO-body_male_stylized.eye.L", "GEO-body_male_stylized.eye.R") if n in data_from.objects]
    loaded = {}
    for o in data_to.objects:
        if o is not None:
            bpy.context.scene.collection.objects.link(o)
            loaded[o.name] = o

    src_body = loaded["GEO-body_male_stylized"]
    src_el = loaded["GEO-body_male_stylized.eye.L"]
    src_er = loaded["GEO-body_male_stylized.eye.R"]
    bpy.context.view_layer.update()

    # Slice head + upper neck from GEO-body_male_stylized
    mw_b = src_body.matrix_world.copy()
    el_pts = [src_el.matrix_world @ v.co for v in src_el.data.vertices]
    er_pts = [src_er.matrix_world @ v.co for v in src_er.data.vertices]
    el_c0 = sum(el_pts, Vector((0, 0, 0))) / len(el_pts)
    er_c0 = sum(er_pts, Vector((0, 0, 0))) / len(er_pts)
    eye_mid0 = 0.5 * (el_c0 + er_c0)
    src_all_z = [(mw_b @ v.co).z for v in src_body.data.vertices]
    src_top_z = max(src_all_z)
    src_head_h = max(0.08, src_top_z - (eye_mid0.z - 0.145))

    # Target head dimensions seated cleanly on Chen's mixamorig:Head bone
    head_base = head_b.head_local
    target_head_h = 0.245
    h_sc = target_head_h / src_head_h
    target_eye_z = float(head_base.z) + 0.088
    target_eye_y = float(head_base.y) - 0.068

    def xform_aged_head(wp: Vector) -> Vector:
        # Center on eye midpoint, scale, then apply middle-aged anatomical sculpting!
        lx = (wp.x - eye_mid0.x) * h_sc
        ly = (wp.y - eye_mid0.y) * h_sc
        lz = (wp.z - eye_mid0.z) * h_sc

        # 1) Broaden & square the lower jaw / mandible (+16% width, firmer chin) -> instant middle-aged gravitas!
        if lz < -0.025 and lz > -0.105:
            jt = math.sin(min(1.0, max(0.0, (-0.025 - lz) / 0.080)) * math.pi)
            lx *= (1.0 + 0.17 * jt)
            if ly < 0.03:
                ly -= 0.008 * jt  # firmer forward square chin & jaw angle!
        # 2) Stronger cheekbones & brow ridge
        if -0.032 < lz < -0.005 and abs(lx) > 0.030 and ly < 0.02:
            lx *= 1.07
        if 0.012 < lz < 0.030 and ly < 0.01:
            ly -= 0.006 * max(0.0, 1.0 - abs(lx) / 0.065)
        # 3) Slightly broader solid neck column seating seamlessly into olive parka collar
        if lz < -0.085:
            lx *= 1.18
            ly *= 1.15
        # 4) Slightly relax/narrow vertical eye opening (removes teenage big-anime-eye look!)
        if abs(lz) < 0.018 and abs(lx) > 0.012 and abs(lx) < 0.052 and ly < 0.01:
            lz *= 0.86

        return Vector((lx + float(head_base.x), ly + target_eye_y, lz + target_eye_z))

    bm_head = bmesh.new()
    bm_head.from_mesh(src_body.data)
    bm_head.verts.ensure_lookup_table()
    # Keep head + neck down into collar (z >= eye_mid0.z - 0.175 in source space)
    z_keep_min = eye_mid0.z - 0.178
    for v in bm_head.verts:
        v.co = mw_b @ v.co
    del_h = [f for f in bm_head.faces if f.calc_center_median().z < z_keep_min]
    bmesh.ops.delete(bm_head, geom=del_h, context="FACES")
    loose_h = [v for v in bm_head.verts if not v.link_faces]
    if loose_h:
        bmesh.ops.delete(bm_head, geom=loose_h, context="VERTS")
    for v in bm_head.verts:
        v.co = xform_aged_head(v.co)
    bm_head.normal_update()
    for f in bm_head.faces:
        f.smooth = True

    head_me = bpy.data.meshes.new("Chen_Head_Mesh")
    bm_head.to_mesh(head_me)
    bm_head.free()
    head_obj = bpy.data.objects.new("Chen_Head", head_me)
    bpy.context.scene.collection.objects.link(head_obj)
    vg_h = head_obj.vertex_groups.new(name="mixamorig:Head")
    vg_n = head_obj.vertex_groups.new(name="mixamorig:Neck")
    for v in head_me.vertices:
        if v.co.z < float(head_base.z) - 0.012:
            vg_n.add([v.index], 1.0, "REPLACE")
        else:
            vg_h.add([v.index], 1.0, "REPLACE")
    head_obj.parent = arm
    head_obj.modifiers.new("Armature", "ARMATURE").object = arm

    h_pts = [v.co for v in head_me.vertices]
    hinfo = {
        "z_min": min(p.z for p in h_pts),
        "z_max": max(p.z for p in h_pts),
        "y_min": min(p.y for p in h_pts),
        "y_max": max(p.y for p in h_pts),
        "eye_z": target_eye_z,
        "eye_y": target_eye_y,
    }

    # Paint custom 512x512 weathered middle-aged skin albedo + normal directly onto Chen_Head's UV!
    face_diff, face_norm = make_weathered_chen_face_textures(head_obj, hinfo, size=512)
    m_face = make_uv_pbr_mat("Chen_WeatheredFace", srgb(188, 138, 102), roughness=0.64, normal_img=face_norm, normal_scale=0.55, albedo_img=face_diff)
    head_obj.data.materials.clear()
    head_obj.data.materials.append(m_face)

    # Mature calm dark-brown East Asian eyes (deep espresso iris + warm relaxed upper eyelids!)
    m_sclera = make_uv_pbr_mat("Chen_EyeSclera", srgb(220, 212, 202), roughness=0.28)
    m_iris = make_uv_pbr_mat("Chen_EyeIris", srgb(34, 20, 12), roughness=0.14)
    m_pupil = make_uv_pbr_mat("Chen_EyePupil", srgb(10, 10, 12), roughness=0.08)
    m_lid = make_uv_pbr_mat("Chen_EyeLid", srgb(156, 112, 82), roughness=0.68)
    bm_eyes = bmesh.new()
    for eye_src in (src_el, src_er):
        ec_s = sum((eye_src.matrix_world @ v.co for v in eye_src.data.vertices), Vector((0, 0, 0))) / len(eye_src.data.vertices)
        ec = xform_aged_head(ec_s)
        ec.y -= 0.001
        s95.add_sphere_mesh(bm_eyes, ec, (0.0122, 0.0120, 0.0106), segs=14, rings=10, mat_idx=0)
        s95.add_sphere_mesh(bm_eyes, ec + Vector((0, -0.0098, -0.0005)), (0.0066, 0.0042, 0.0060), segs=12, rings=8, mat_idx=1)
        s95.add_sphere_mesh(bm_eyes, ec + Vector((0, -0.0124, -0.0005)), (0.0032, 0.0024, 0.0030), segs=10, rings=6, mat_idx=2)
        # Subtle relaxed upper eyelid hood removing wide-eyed stare!
        s95.add_box_mesh(bm_eyes, ec + Vector((0, -0.0092, 0.0068)), (0.025, 0.009, 0.0062), rot_euler=(0.18, 0.0, 0.0), mat_idx=3, bevel=0.002)
    eyes_obj = attach_uv_mesh_to_bone(arm, "Chen_Eyes", bm_eyes, [m_sclera, m_iris, m_pupil, m_lid], "mixamorig:Head", uv_scale=4.0)

    # Clean up temporary Blender Studio source objects
    for o in loaded.values():
        bpy.data.objects.remove(o, do_unlink=True)

    # Full layered brushed salt-and-pepper veteran hair ('Chen_VeteranHair' — exact name checked by slice.gd & verify_packaged.gd!)
    fab_n = s95.make_fabric_normal_image("Tex_ChenFabNrm", 256, 14, 0.36)
    m_hair_dark = make_uv_pbr_mat("Chen_HairDark", srgb(42, 46, 52), roughness=0.64, normal_img=fab_n, normal_scale=0.22, tex_scale=4.0)
    m_hair_silver = make_uv_pbr_mat("Chen_HairSilver", srgb(96, 102, 110), roughness=0.62, normal_img=fab_n, normal_scale=0.22, tex_scale=4.0)

    head_top = hinfo["z_max"]
    head_y_max = hinfo["y_max"]
    eye_z = hinfo["eye_z"]
    eye_y = hinfo["eye_y"]
    head_cy = 0.5 * (eye_y + head_y_max)

    bm_hair = bmesh.new()
    # Thick form-fitting brushed-back scalp volume covering crown, nape & neat silvered temples
    bm_scalp = bmesh.new()
    bm_scalp.from_mesh(head_obj.data)
    bm_scalp.verts.ensure_lookup_table()
    bm_scalp.faces.ensure_lookup_table()
    keep_f = set()
    for f in bm_scalp.faces:
        c = f.calc_center_median()
        is_ear = (abs(c.x) > 0.064 and (eye_z - 0.042) < c.z < (eye_z + 0.022) and abs(c.y - head_cy) < 0.048)
        if is_ear:
            continue
        in_crown = (c.z > eye_z + 0.026) and (c.y > eye_y - 0.014)
        in_back = (c.y > head_cy - 0.002) and (c.z > eye_z - 0.070)
        in_temple = (abs(c.x) > 0.052) and (c.y > eye_y + 0.010) and (c.y < head_cy - 0.008) and (c.z > eye_z - 0.004)
        if in_crown or in_back or in_temple:
            keep_f.add(f)
    bmesh.ops.delete(bm_scalp, geom=[f for f in bm_scalp.faces if f not in keep_f], context="FACES")
    bm_scalp.normal_update()
    for _ in range(5):
        bmesh.ops.smooth_vert(bm_scalp, verts=list(bm_scalp.verts), factor=0.48, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm_scalp.normal_update()
    for v in bm_scalp.verts:
        thk = 0.022 if v.co.z > eye_z + 0.046 else (0.015 if v.co.y > head_cy else 0.011)
        v.co += v.normal * thk
    res_ext = bmesh.ops.extrude_face_region(bm_scalp, geom=list(bm_scalp.faces))
    for g in res_ext["geom"]:
        if isinstance(g, bmesh.types.BMVert):
            g.co -= g.normal * 0.011
    for f in bm_scalp.faces:
        c = f.calc_center_median()
        is_silver = (abs(c.x) > 0.058 and c.z < eye_z + 0.042 and c.y < head_cy + 0.016)
        f.material_index = 1 if is_silver else 0
        f.smooth = True
    tmp_sc = bpy.data.meshes.new("_chen_sc")
    bm_scalp.to_mesh(tmp_sc)
    bm_scalp.free()
    bm_hair.from_mesh(tmp_sc)
    bpy.data.meshes.remove(tmp_sc)

    # Subtle low-profile crown volume layered flush into scalp (ZERO boxy protruding blocks!)
    chen_locks = [
        ([(0.000, eye_y + 0.008, head_top - 0.014), (0.000, head_cy - 0.002, head_top + 0.012), (0.000, head_cy + 0.044, head_top + 0.002)], [0.068, 0.072, 0.048], [0.012, 0.014, 0.010], 0),
        ([(-0.032, eye_y + 0.010, head_top - 0.020), (-0.036, head_cy - 0.002, head_top + 0.008), (-0.034, head_cy + 0.040, head_top - 0.004)], [0.044, 0.046, 0.032], [0.010, 0.012, 0.009], 0),
        ([(0.032, eye_y + 0.010, head_top - 0.020), (0.036, head_cy - 0.002, head_top + 0.008), (0.034, head_cy + 0.040, head_top - 0.004)], [0.044, 0.046, 0.032], [0.010, 0.012, 0.009], 0),
    ]
    for pts, ws, ts, midx in chen_locks:
        s95.add_ribbon_strip(bm_hair, pts, ws, ts, mat_idx=midx)
    hair_obj = attach_uv_mesh_to_bone(arm, "Chen_VeteranHair", bm_hair, [m_hair_dark, m_hair_silver], "mixamorig:Head", uv_scale=4.0)

    # Portrait-faithful ranger field gear (compact hooded collar, warm golden scarf tucked snugly,
    # chest binoculars with dark tinted lenses, snug left-lapel olive radio & right-chest brass whistle) — ZERO floating straps!
    m_scarf = make_uv_pbr_mat("Chen_GoldScarf", srgb(184, 134, 48), roughness=0.80, normal_img=fab_n, normal_scale=0.40, tex_scale=6.0)
    m_collar = make_uv_pbr_mat("Chen_ParkaCollar", srgb(44, 68, 50), roughness=0.76, normal_img=fab_n, normal_scale=0.35, tex_scale=5.0)
    m_strap = make_uv_pbr_mat("Chen_BrownStrap", srgb(68, 48, 32), roughness=0.66, normal_img=fab_n, normal_scale=0.28, tex_scale=5.0)
    m_radio = make_uv_pbr_mat("Chen_RadioOlive", srgb(50, 62, 46), roughness=0.52, metallic=0.22)
    m_brass = make_uv_pbr_mat("Chen_Brass", srgb(198, 156, 68), roughness=0.30, metallic=0.82)
    m_glass = make_uv_pbr_mat("Chen_OpticLens", srgb(24, 58, 72), roughness=0.14, metallic=0.32)
    m_bino = make_uv_pbr_mat("Chen_BinoBody", srgb(34, 40, 36), roughness=0.52, metallic=0.18)

    sp2 = arm.data.bones["mixamorig:Spine2"]
    cz = float(sp2.head_local.z)
    nz = float(neck_b.head_local.z)
    bm_gear = bmesh.new()
    # Sleek wide rear hooded parka collar seated cleanly behind the golden scarf (ZERO cylinder intersection!)
    s95.add_cyl_mesh(bm_gear, (0.0, 0.048, nz - 0.016), 0.148, 0.140, 0.056, segs=22, rot_euler=(0.24, 0.0, 0.0), mat_idx=1)
    # Warm tucked ribbed golden-ochre scarf nested neatly around neck (matching chen_guide.png!)
    s95.add_cyl_mesh(bm_gear, (0.0, -0.008, nz + 0.014), 0.104, 0.098, 0.044, segs=22, mat_idx=0)
    s95.add_cyl_mesh(bm_gear, (0.0, -0.016, nz - 0.022), 0.112, 0.104, 0.036, segs=22, rot_euler=(0.12, 0.0, 0.0), mat_idx=0)
    s95.add_box_mesh(bm_gear, (0.008, -0.118, nz - 0.062), (0.066, 0.020, 0.088), rot_euler=(0.10, 0.0, -0.08), mat_idx=0, bevel=0.010)
    # Dual-barrel matte dark olive field binoculars resting flush on chest
    for bx in (-0.036, 0.036):
        s95.add_cyl_mesh(bm_gear, (bx, -0.152, cz + 0.016), 0.025, 0.020, 0.108, segs=16, rot_euler=(math.radians(78), 0, 0), mat_idx=6)
        s95.add_cyl_mesh(bm_gear, (bx, -0.205, cz + 0.004), 0.018, 0.018, 0.008, segs=14, rot_euler=(math.radians(78), 0, 0), mat_idx=5)
    s95.add_box_mesh(bm_gear, (0.0, -0.150, cz + 0.018), (0.058, 0.042, 0.022), mat_idx=6, bevel=0.004)
    s95.add_cyl_mesh(bm_gear, (0.0, -0.132, cz + 0.026), 0.011, 0.011, 0.026, segs=12, rot_euler=(math.radians(78), 0, 0), mat_idx=4)
    # Snug olive tactical radio clipped flush to LEFT chest strap
    s95.add_box_mesh(bm_gear, (0.122, -0.136, cz + 0.056), (0.050, 0.034, 0.096), mat_idx=3, bevel=0.007)
    s95.add_box_mesh(bm_gear, (0.122, -0.156, cz + 0.068), (0.032, 0.007, 0.038), mat_idx=6, bevel=0.002)
    s95.add_cyl_mesh(bm_gear, (0.138, -0.134, cz + 0.160), 0.004, 0.0025, 0.125, segs=8, mat_idx=6)
    # Brass scout whistle clipped flush to RIGHT chest strap
    s95.add_cyl_mesh(bm_gear, (-0.118, -0.136, cz + 0.042), 0.010, 0.008, 0.044, segs=12, rot_euler=(0.12, 0.0, 0.08), mat_idx=4)
    gear_obj = attach_uv_mesh_to_bone(
        arm, "Chen_RangerGear", bm_gear,
        [m_scarf, m_collar, m_strap, m_radio, m_brass, m_glass, m_bino],
        "mixamorig:Spine2", uv_scale=3.2,
    )

    body_meshes = [main_obj, head_obj, eyes_obj, hair_obj, gear_obj]
    retarget_mixamo_clips(
        arm, [main_obj], mocap_cache,
        [("Idle_Camp", "Breathing_Idle.fbx", "unarmed", False, 64)],
    )
    export_char_glb(arm, body_meshes, SLICE_DIR / "npc_chen_guide.glb")

    if preview_dir is not None:
        act_camp = bpy.data.actions.get("Idle_Camp")
        if act_camp:
            arm.animation_data.use_nla = False
            arm.animation_data.action = act_camp
            bpy.context.scene.frame_set(1)
            bpy.context.view_layer.update()
        render_quick_preview(arm, body_meshes, preview_dir / "v0995_preview_chen.png", focus_z=1.32, dist=1.45)


# ===========================================================================
# 2 & 3. Mistbound Assault & Sniper — Heavy Tactical Body + Woven Green Bamboo Hat ('斗笠')
# ===========================================================================
def build_mistbound_trooper(variant: str, panzer_blend: Path, mocap_cache: dict[str, dict], preview_dir: Path | None = None):
    is_sniper = (variant == "sniper")
    target_h = 1.84 if is_sniper else 1.76
    arm, main_obj, pouches_obj = load_normalized_infantry_base(panzer_blend, target_height=target_h, keep_pouches=True)
    arm.name = f"Mistbound_{variant.title()}_Armature"

    # Retexture uniform cleanly (100% WW2 insignia stripped, face/hands masked dark tactical balaclava & gloves!)
    img_diff = bpy.data.images.get("panzergren_low2k_diff.png")
    img_norm = bpy.data.images.get("panzergren_low2k_norm.png")
    img_ruff = bpy.data.images.get("panzergren_low2k_ruff.png")
    u_diff, u_norm, u_ruff = downscale_and_retexture_panzer_uniform(img_diff, img_norm, img_ruff, variant, target_size=1024)
    m_uni = make_uv_pbr_mat(
        f"Mist_{variant}_Uniform",
        srgb(42, 46, 52) if is_sniper else srgb(44, 78, 70),
        roughness=0.72,
        normal_img=u_norm,
        normal_scale=0.60,
        albedo_img=u_diff,
        rough_img=u_ruff,
    )
    main_obj.data.materials.clear()
    main_obj.data.materials.append(m_uni)
    main_obj.name = f"Mistbound_{variant.title()}_Body"

    if pouches_obj is not None:
        # Downscale pouch textures to 512px JPG/PNG to keep GLB lean (~1.9MB instead of 5.8MB!)
        p_diff_raw = bpy.data.images.get("ammopouchesgerman_diff")
        p_norm_raw = bpy.data.images.get("ammopouchesgerman_norm")
        p_diff = p_diff_raw
        p_norm = p_norm_raw
        ffmpeg = shutil.which("ffmpeg")
        if ffmpeg and p_diff_raw is not None:
            for tag_p, src_i, is_c in (("pdiff", p_diff_raw, True), ("pnorm", p_norm_raw, False)):
                if src_i is None:
                    continue
                raw_p = TMP_DIR / f"{variant}_{tag_p}_raw.png"
                out_p = TMP_DIR / f"{variant}_{tag_p}_512.{'jpg' if is_c else 'png'}"
                src_i.filepath_raw = str(raw_p)
                src_i.file_format = "PNG"
                src_i.save()
                cmd = [ffmpeg, "-y", "-loglevel", "error", "-i", str(raw_p), "-vf", "scale=512:512"]
                if is_c:
                    cmd += ["-q:v", "3"]
                cmd.append(str(out_p))
                subprocess.run(cmd, check=False)
                if out_p.exists() and out_p.stat().st_size > 100:
                    ni = bpy.data.images.load(str(out_p), check_existing=False)
                    ni.name = f"Mist_{variant}_{tag_p}"
                    ni.colorspace_settings.name = "sRGB" if is_c else "Non-Color"
                    ni.pack()
                    if is_c:
                        p_diff = ni
                    else:
                        p_norm = ni
        m_pouch = make_uv_pbr_mat(f"Mist_{variant}_Pouches", srgb(34, 38, 42), roughness=0.64, normal_img=p_norm, normal_scale=0.50, albedo_img=p_diff)
        pouches_obj.data.materials.clear()
        pouches_obj.data.materials.append(m_pouch)
        pouches_obj.name = f"Mistbound_{variant.title()}_Pouches"

    fab_n = s95.make_fabric_normal_image(f"Tex_MistArmNrm_{variant}", 256, 16, 0.38)
    if is_sniper:
        m_armor = make_uv_pbr_mat("MistSniper_Armor", srgb(40, 44, 48), roughness=0.56, metallic=0.22, normal_img=fab_n, normal_scale=0.32, tex_scale=4.0)
        m_plate = make_uv_pbr_mat("MistSniper_Plate", srgb(26, 30, 34), roughness=0.46, metallic=0.34, normal_img=fab_n, normal_scale=0.25, tex_scale=4.0)
        m_bronze = make_uv_pbr_mat("MistSniper_Bronze", srgb(164, 124, 62), roughness=0.36, metallic=0.78)
        m_visor = make_uv_pbr_mat("MistSniper_Visor", srgb(245, 68, 86), roughness=0.14, emission=srgb(245, 56, 76), emission_strength=1.55)
        b_diff, b_norm = make_woven_bamboo_images("sniper", (0.20, 0.32, 0.26), size=512)
    else:
        m_armor = make_uv_pbr_mat("MistAssault_Armor", srgb(44, 78, 68), roughness=0.56, metallic=0.18, normal_img=fab_n, normal_scale=0.34, tex_scale=4.0)
        m_plate = make_uv_pbr_mat("MistAssault_Plate", srgb(24, 40, 40), roughness=0.46, metallic=0.30, normal_img=fab_n, normal_scale=0.25, tex_scale=4.0)
        m_bronze = make_uv_pbr_mat("MistAssault_Bronze", srgb(172, 134, 68), roughness=0.36, metallic=0.76)
        m_visor = make_uv_pbr_mat("MistAssault_Visor", srgb(82, 232, 198), roughness=0.14, emission=srgb(68, 224, 188), emission_strength=1.45)
        b_diff, b_norm = make_woven_bamboo_images("assault", (0.24, 0.44, 0.32), size=512)

    m_bamboo = make_uv_pbr_mat(f"Mist_{variant}_BambooHat", srgb(62, 112, 82), roughness=0.72, normal_img=b_norm, normal_scale=0.72, albedo_img=b_diff)
    m_gun = make_uv_pbr_mat(f"Mist_{variant}_Gun", srgb(32, 36, 42), roughness=0.38, metallic=0.62)

    # 1) Tactical Masked Helmet + Sleek Curved Recessed Visor Strip + Seated Woven Bamboo Hat ('斗笠')!
    hb = arm.data.bones["mixamorig:Head"]
    hc = hb.head_local + Vector((0.0, -0.008, 0.104))
    bm_helm = bmesh.new()
    # Sleek armored helmet dome + contoured respirator jaw mask
    s95.add_sphere_mesh(bm_helm, hc + Vector((0.0, 0.008, 0.006)), (0.110, 0.120, 0.116), segs=22, rings=14, mat_idx=1)
    s95.add_box_mesh(bm_helm, hc + Vector((0.0, -0.082, -0.044)), (0.118, 0.082, 0.086), rot_euler=(0.14, 0.0, 0.0), mat_idx=1, bevel=0.016)
    # Recessed curved wraparound visor lens + matte brow bezel hugging helmet face cleanly (ZERO jutting neon box!)
    for si in range(7):
        ang = math.radians(-48.0 + si * 16.0)
        vx = math.sin(ang) * 0.109
        vy = -math.cos(ang) * 0.115
        s95.add_box_mesh(bm_helm, hc + Vector((vx, vy, 0.008)), (0.032, 0.016, 0.024), rot_euler=(0.0, 0.0, ang), mat_idx=3, bevel=0.003)
        s95.add_box_mesh(bm_helm, hc + Vector((vx * 1.03, vy * 1.03, 0.025)), (0.036, 0.022, 0.012), rot_euler=(0.0, 0.0, ang), mat_idx=1, bevel=0.003)
    helm_base_obj = attach_uv_mesh_to_bone(
        arm, "Mistbound_Helmet", bm_helm,
        [m_armor, m_plate, m_bronze, m_visor],
        "mixamorig:Head", uv_scale=3.0,
    )

    # Dedicated woven conical Jiangnan bamboo hat ('斗笠') seated SNUGLY onto the helmet crown (ZERO floating gap!)
    bm_hat = bmesh.new()
    brim_r = 0.305 if is_sniper else 0.278
    hat_c = hc + Vector((0.0, 0.006, 0.056))
    hat_rings = [
        (0.000, brim_r),
        (0.034, brim_r * 0.78),
        (0.072, brim_r * 0.52),
        (0.110, brim_r * 0.26),
        (0.138, 0.020),
    ]
    segs = 32
    top_rings = []
    bot_rings = []
    for dz, rad in hat_rings:
        tr = []
        br = []
        for si in range(segs):
            ang = 2.0 * math.pi * si / segs
            ca, sa = math.cos(ang), math.sin(ang)
            # Slight mysterious forward dip (-Y slightly lower than +Y!)
            pitch_z = sa * 0.018
            tr.append(bm_hat.verts.new(hat_c + Vector((ca * rad, sa * rad, dz + pitch_z))))
            br.append(bm_hat.verts.new(hat_c + Vector((ca * rad * 0.96, sa * rad * 0.96, dz - 0.012 + pitch_z))))
        top_rings.append(tr)
        bot_rings.append(br)
    for ri in range(len(hat_rings) - 1):
        for si in range(segs):
            nsi = (si + 1) % segs
            f1 = bm_hat.faces.new((top_rings[ri][si], top_rings[ri][nsi], top_rings[ri + 1][nsi], top_rings[ri + 1][si]))
            f1.material_index = 0
            f2 = bm_hat.faces.new((bot_rings[ri][nsi], bot_rings[ri][si], bot_rings[ri + 1][si], bot_rings[ri + 1][nsi]))
            f2.material_index = 0
    for si in range(segs):
        nsi = (si + 1) % segs
        fr = bm_hat.faces.new((bot_rings[0][si], bot_rings[0][nsi], top_rings[0][nsi], top_rings[0][si]))
        fr.material_index = 1
    # Inner woven headband socket hugging helmet dome seamlessly + bronze crown finial
    s95.add_cyl_mesh(bm_hat, hat_c + Vector((0.0, 0.0, 0.030)), 0.118, 0.112, 0.044, segs=22, mat_idx=0)
    s95.add_cyl_mesh(bm_hat, hat_c + Vector((0.0, 0.0, 0.146)), 0.032, 0.010, 0.028, segs=16, mat_idx=1)
    hat_obj = attach_uv_mesh_to_bone(
        arm, "Mistbound_BambooHat", bm_hat,
        [m_bamboo, m_bronze],
        "mixamorig:Head", uv_scale=4.2, conical_center=hat_c,
    )

    # 2) Contoured Tactical Chest Plate Rig + Compact Back Comms Pack (hugging the folded uniform naturally!)
    sp2 = arm.data.bones["mixamorig:Spine2"]
    cz = float(sp2.head_local.z)
    bm_chest = bmesh.new()
    s95.add_box_mesh(bm_chest, (0.0, -0.128, cz + 0.082), (0.26, 0.056, 0.25), mat_idx=1, bevel=0.018)
    s95.add_box_mesh(bm_chest, (0.0, -0.158, cz + 0.118), (0.19, 0.024, 0.12), mat_idx=0, bevel=0.010)
    s95.add_box_mesh(bm_chest, (0.0, -0.172, cz + 0.128), (0.054, 0.014, 0.054), rot_euler=(0.0, math.radians(45), 0.0), mat_idx=2, bevel=0.004)
    # Sleek armored neck gorget
    s95.add_cyl_mesh(bm_chest, (0.0, 0.012, cz + 0.215), 0.132, 0.118, 0.052, segs=20, rot_euler=(0.14, 0.0, 0.0), mat_idx=1)
    # Compact rear tactical comms pack + slim antenna
    s95.add_box_mesh(bm_chest, (0.0, 0.150, cz + 0.068), (0.22, 0.088, 0.26), mat_idx=1, bevel=0.018)
    s95.add_cyl_mesh(bm_chest, (-0.088, 0.158, cz + 0.295), 0.005, 0.003, 0.24, segs=8, mat_idx=2)
    if is_sniper:
        # Compact shoulder laser rangefinder + twin telemetry antennas (clean silhouette, zero stiff flat cape!)
        s95.add_box_mesh(bm_chest, (-0.172, -0.01, cz + 0.215), (0.052, 0.17, 0.050), mat_idx=1, bevel=0.008)
        s95.add_cyl_mesh(bm_chest, (0.088, 0.158, cz + 0.275), 0.0045, 0.003, 0.20, segs=8, mat_idx=2)
    chest_obj = attach_uv_mesh_to_bone(arm, "Mistbound_ChestArmor", bm_chest, [m_armor, m_plate, m_bronze], "mixamorig:Spine2", uv_scale=3.0)

    # 3) Sleek Curved Tactical Pauldrons hugging shoulder silhouette cleanly (ZERO oversized boxes!)
    p_objs = []
    for side_m, sgn in (("Left", 1.0), ("Right", -1.0)):
        ub = arm.data.bones[f"mixamorig:{side_m}Arm"]
        pc = ub.head_local + Vector((sgn * 0.024, 0.004, 0.012))
        bm_p = bmesh.new()
        s95.add_box_mesh(bm_p, pc, (0.116, 0.152, 0.132), rot_euler=(0.0, sgn * 0.34, 0.0), mat_idx=0, bevel=0.024)
        s95.add_box_mesh(bm_p, pc + Vector((sgn * 0.018, 0.0, -0.050)), (0.122, 0.158, 0.016), rot_euler=(0.0, sgn * 0.34, 0.0), mat_idx=1, bevel=0.004)
        p_objs.append(attach_uv_mesh_to_bone(arm, f"Mistbound_Pauldron_{side_m[0]}", bm_p, [m_armor, m_bronze], f"mixamorig:{side_m}Arm", uv_scale=3.2))

    # 4) Detailed Tactical Carbine / Suppressed Sniper Rifle locked to Weapon_R!
    rifle_obj = build_mistbound_rifle_from_glb(arm, is_sniper, m_gun, m_bronze, m_visor)

    # 5) Real Mixamo studio mocap animations: Idle_Aim, Walk_Patrol, Run_Advance!
    retarget_mixamo_clips(
        arm, [main_obj], mocap_cache,
        [
            ("Idle_Aim",    "Rifle_Aiming_Idle.fbx",  "rifle_2h", False, 52),
            ("Walk_Patrol", "Walk_With_Rifle_3.fbx",  "rifle_2h", True,  34),
            ("Run_Advance", "Rifle_Run.fbx",          "rifle_2h", True,  24),
        ],
    )

    meshes = [main_obj] + ([pouches_obj] if pouches_obj else []) + [helm_base_obj, hat_obj, chest_obj, rifle_obj] + p_objs
    out_name = "v097_mistbound_sniper.glb" if is_sniper else "v097_mistbound_assault.glb"
    export_char_glb(arm, meshes, SLICE_DIR / out_name)

    if preview_dir is not None:
        # Pose at Idle_Aim frame 1 for realistic combat preview!
        act_idle = bpy.data.actions.get("Idle_Aim")
        if act_idle:
            arm.animation_data.use_nla = False
            arm.animation_data.action = act_idle
            bpy.context.scene.frame_set(1)
            bpy.context.view_layer.update()
        render_quick_preview(arm, meshes, preview_dir / f"v0995_preview_{variant}.png", focus_z=1.18, dist=2.15)


def render_quick_preview(arm, meshes, out_png: Path, focus_z: float = 1.15, dist: float = 1.95):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    cam_d = bpy.data.cameras.new("_PrevCam")
    cam = bpy.data.objects.new("_PrevCam", cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = Vector((dist * 0.24, -dist, focus_z + 0.08))
    cam.rotation_euler = (Vector((0.0, 0.0, focus_z)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    l_d = bpy.data.lights.new("_PrevSun", "SUN")
    l_d.energy = 3.2
    sun = bpy.data.objects.new("_PrevSun", l_d)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (0.65, 0.25, -0.45)
    if not scene.world:
        scene.world = bpy.data.worlds.new("_PrevWorld")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.18, 0.24, 0.28, 1.0)
    out_png.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(out_png)
    bpy.ops.render.render(write_still=True)


def audit_glb_uvs(glb_path: Path) -> tuple[int, int]:
    """Verify ZERO missing normal/baseColor UV texcoords (-1) in exported GLB!"""
    with glb_path.open("rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        j = json.loads(f.read(clen).decode("utf-8"))
    mats = j.get("materials", [])
    total_prims = 0
    missing_uv = 0
    for mesh in j.get("meshes", []):
        for prim in mesh.get("primitives", []):
            total_prims += 1
            attrs = prim.get("attributes", {})
            mi = prim.get("material")
            if mi is not None and mi < len(mats):
                m = mats[mi]
                needs_uv = ("normalTexture" in m) or ("baseColorTexture" in m.get("pbrMetallicRoughness", {}))
                if needs_uv and "TEXCOORD_0" not in attrs:
                    missing_uv += 1
    print(f"UV_AUDIT {glb_path.name}: prims={total_prims}, missing_uv={missing_uv}")
    return total_prims, missing_uv


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--panzer-blend", required=True)
    ap.add_argument("--mocap-dir", required=True)
    ap.add_argument("--preview-dir", default="")
    args = ap.parse_args(argv)

    panzer = Path(args.panzer_blend)
    mocap = Path(args.mocap_dir)
    prev = Path(args.preview_dir) if args.preview_dir else None

    mocap_cache = preload_mocap_cache(mocap, [
        ("Breathing_Idle.fbx", 64),
        ("Rifle_Aiming_Idle.fbx", 52),
        ("Walk_With_Rifle_3.fbx", 34),
        ("Rifle_Run.fbx", 24),
    ])

    build_chen_guide(panzer, mocap_cache, prev)
    build_mistbound_trooper("assault", panzer, mocap_cache, prev)
    build_mistbound_trooper("sniper", panzer, mocap_cache, prev)

    # Audit ALL 4 v0.9.9.5 character GLBs for 100% UV completeness!
    total_missing = 0
    for fn in ("npc_chen_guide.glb", "v097_mistbound_assault.glb", "v097_mistbound_sniper.glb", "v098_cave_warden.glb"):
        p = SLICE_DIR / fn
        if p.exists():
            _, miss = audit_glb_uvs(p)
            total_missing += miss
    print(f"V0995_ALL_CHARS_COMPLETE total_missing_uv={total_missing}")
    if total_missing > 0:
        raise RuntimeError(f"UV audit failed: {total_missing} primitives missing TEXCOORD_0!")


if __name__ == "__main__":
    main()
