"""v0.9.9.6_dev1 High-Fidelity Ahsarah Human & Boss Characters Pipeline (Blender 5.3).

Builds 3 realistic PBR skeletal characters with real Adobe Mixamo animations (sampled directly
from our game's v097_mistbound_assault.glb Mixamo 65-bone rig) combining:
  - Insignia-scrubbed cloth tactical uniform & pouches (WW2 Panzergrenadier.blend)
  - Unmodified AAA sculpted male head, eyes, brows & hair (Project Resident Evil.blend)
  - Real AAA Blizzard aviator sunglasses (pharah-bodyhack.blend -> ARMR--aviator__head-sunglasses)
  - Detailed CC0 rifle.glb upgraded per-boss (M4 / M249 box-mag LMG / S12K heavy shotgun)
  - Bespoke UV-mapped desert faction gear (checkered keffiyeh scarf, crimson hood + articulated
    saeed_cloak_pivot + bronze owl crest + back compound crossbow, gilded officer pauldrons +
    articulated rotating antique brass horn reis_gramophone!)

Outputs:
  1. game/assets/slice/v0996_ahsarah_guard.glb  (1.80m Ahsarah Desert Guerrilla)
  2. game/assets/slice/v0996_boss_saeed.glb     (2.12m Captain Saeed · Fiery Owl)
  3. game/assets/slice/v0996_boss_reis.glb      (2.56m Warlord Reis w/ Shoulder Gramophone)
  + Optional preview stills & 1024x1280 RGBA studio bust foregrounds for 1:1 Lore Codex portraits!

Usage:
  blender --background --factory-startup --python tools/build_v0996_dev1_ahsarah_humans.py -- \
    --panzer <WW2 Panzergrenadier.blend> --re-blend <Project Resident Evil.blend> \
    --pharah-blend <pharah-bodyhack.blend> [--preview <dir>] [--portraits <dir>]
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

REPO_ROOT = Path(__file__).resolve().parents[1]
SLICE_DIR = REPO_ROOT / "game" / "assets" / "slice"
RIFLE_GLB = SLICE_DIR / "rifle.glb"
MISTBOUND_REF_GLB = SLICE_DIR / "v097_mistbound_assault.glb"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--panzer", type=str, required=True)
    ap.add_argument("--re-blend", type=str, required=True)
    ap.add_argument("--pharah-blend", type=str, required=True)
    ap.add_argument("--preview", type=str, default="")
    ap.add_argument("--portraits", type=str, default="")
    ap.add_argument("--only", type=str, default="")
    return ap.parse_args(argv)


def save_np_image(arr_topdown: np.ndarray, out_name: str, colorspace: str, tmp_dir: Path, keep_alpha: bool = False, fmt: str = "PNG") -> bpy.types.Image:
    """Save top-down float32 [H,W,3|4] array into clean packed 8-bit PNG Blender image (100% Godot 4.7.2 compatible!)."""
    h, w = arr_topdown.shape[:2]
    arr_bu = np.clip(arr_topdown[::-1, :, :], 0.0, 1.0).astype(np.float32)
    if arr_bu.shape[2] == 3:
        rgba = np.concatenate([arr_bu, np.ones((h, w, 1), dtype=np.float32)], axis=2)
    else:
        rgba = arr_bu
    tmp = bpy.data.images.new(out_name + "_tmp", width=w, height=h, alpha=keep_alpha)
    tmp.pixels.foreach_set(rgba.ravel())
    out_p = tmp_dir / f"{out_name}.png"
    tmp.filepath_raw = str(out_p)
    tmp.file_format = "PNG"
    sc = bpy.context.scene
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA" if keep_alpha else "RGB"
    sc.render.image_settings.color_depth = "8"
    tmp.save()
    bpy.data.images.remove(tmp, do_unlink=True)
    im = bpy.data.images.load(str(out_p), check_existing=False)
    im.name = out_name
    im.colorspace_settings.name = colorspace
    im.pack()
    return im


def load_image_topdown(img: bpy.types.Image, max_dim: int) -> np.ndarray:
    cp = img.copy()
    w, h = int(cp.size[0]), int(cp.size[1])
    if max(w, h) > max_dim:
        sc = max_dim / float(max(w, h))
        nw, nh = max(64, int(round(w * sc))), max(64, int(round(h * sc)))
        cp.scale(nw, nh)
        w, h = nw, nh
    px = np.array(cp.pixels[:], dtype=np.float32).reshape(h, w, cp.channels)
    bpy.data.images.remove(cp, do_unlink=True)
    return px[::-1, :, :].copy()


def make_pbr_mat(
    name: str,
    albedo_img: bpy.types.Image | None = None,
    normal_img: bpy.types.Image | None = None,
    rough_img: bpy.types.Image | None = None,
    base_color: tuple[float, float, float, float] = (0.75, 0.75, 0.75, 1.0),
    roughness: float = 0.72,
    metallic: float = 0.0,
    normal_scale: float = 0.70,
    alpha_clip: float | None = None,
    double_sided: bool = False,
    emission_rgba: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = not double_sided
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission_rgba is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = emission_rgba
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tc = nt.nodes.new("ShaderNodeTexCoord")

    if albedo_img is not None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = albedo_img
        nt.links.new(tc.outputs["UV"], t.inputs["Vector"])
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_clip is not None:
            nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
            if hasattr(mat, "surface_render_method"):
                mat.surface_render_method = "DITHERED"
            if hasattr(mat, "blend_method"):
                mat.blend_method = "CLIP"
            if hasattr(mat, "alpha_threshold"):
                mat.alpha_threshold = alpha_clip

    if rough_img is not None:
        tr = nt.nodes.new("ShaderNodeTexImage")
        tr.image = rough_img
        nt.links.new(tc.outputs["UV"], tr.inputs["Vector"])
        nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])

    if normal_img is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = normal_img
        nt.links.new(tc.outputs["UV"], tn.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_scale
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def grade_desert_uniform_maps(img_diff, img_norm, img_ruff, variant: str, tmp_dir: Path):
    """100% scrub all 4 WW2 insignia patches and recolor uniform PBR maps for Ahsarah / Saeed / Reis!"""
    top = load_image_topdown(img_diff, 1024)
    h, w = top.shape[:2]

    def clean_patch(x0_f, y0_f, x1_f, y1_f, sx_f, sy_f):
        px0, px1 = int(x0_f * w), int(x1_f * w)
        py0, py1 = int(y0_f * h), int(y1_f * h)
        sx0, sy0 = int(sx_f * w), int(sy_f * h)
        ph, pw = py1 - py0, px1 - px0
        src = top[sy0 : sy0 + ph, sx0 : sx0 + pw, :3]
        if src.shape[0] == ph and src.shape[1] == pw:
            top[py0:py1, px0:px1, :3] = src

    # Scrub all 4 historical markings cleanly with adjacent cloth samples
    clean_patch(0.215, 0.595, 0.258, 0.638, 0.050, 0.600)
    clean_patch(0.205, 0.540, 0.250, 0.585, 0.050, 0.540)
    clean_patch(0.770, 0.562, 0.818, 0.610, 0.720, 0.300)
    clean_patch(0.915, 0.672, 0.965, 0.748, 0.855, 0.680)

    r, g, b = top[:, :, 0], top[:, :, 1], top[:, :, 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    is_skin = (r > g * 1.12) & (g > b * 1.06) & (r > 0.25) & (lum > 0.18)
    is_cloth = (~is_skin) & (lum > 0.16) & (np.abs(r - b) < 0.14) & (g >= b * 0.94)
    is_dark = (~is_skin) & (~is_cloth) & (lum > 0.02)

    if variant == "ahsarah_guard":
        # Sun-baked desert khaki/sand tactical combat uniform + olive-brown leather straps + tanned hands
        top[is_cloth, 0] = np.clip(lum[is_cloth] * 1.18 + 0.10, 0.0, 0.86)
        top[is_cloth, 1] = np.clip(lum[is_cloth] * 1.04 + 0.08, 0.0, 0.76)
        top[is_cloth, 2] = np.clip(lum[is_cloth] * 0.76 + 0.04, 0.0, 0.56)
        top[is_dark, 0] = np.clip(top[is_dark, 0] * 1.12 + 0.04, 0.0, 0.45)
        top[is_dark, 1] = np.clip(top[is_dark, 1] * 1.02 + 0.03, 0.0, 0.40)
        top[is_dark, 2] = np.clip(top[is_dark, 2] * 0.78 + 0.01, 0.0, 0.30)
        # Warm sun-tanned desert hands
        top[is_skin, 0] = np.clip(top[is_skin, 0] * 0.88, 0.0, 0.80)
        top[is_skin, 1] = np.clip(top[is_skin, 1] * 0.74, 0.0, 0.66)
        top[is_skin, 2] = np.clip(top[is_skin, 2] * 0.60, 0.0, 0.52)
    elif variant == "boss_saeed":
        # Fiery Owl Captain Saeed: rich weathered dark desert-crimson tunic (NOT pastel pink!) + rugged dark brown boots
        top[is_cloth, 0] = np.clip(lum[is_cloth] * 0.82 + 0.04, 0.0, 0.44)
        top[is_cloth, 1] = np.clip(lum[is_cloth] * 0.15 + 0.01, 0.0, 0.11)
        top[is_cloth, 2] = np.clip(lum[is_cloth] * 0.15 + 0.01, 0.0, 0.11)
        top[is_dark, 0] = np.clip(top[is_dark, 0] * 0.92 + 0.03, 0.0, 0.34)
        top[is_dark, 1] = np.clip(top[is_dark, 1] * 0.78 + 0.02, 0.0, 0.28)
        top[is_dark, 2] = np.clip(top[is_dark, 2] * 0.58 + 0.01, 0.0, 0.20)
        top[is_skin, 0] = np.clip(top[is_skin, 0] * 0.84, 0.0, 0.76)
        top[is_skin, 1] = np.clip(top[is_skin, 1] * 0.70, 0.0, 0.62)
        top[is_skin, 2] = np.clip(top[is_skin, 2] * 0.56, 0.0, 0.48)
    else:  # boss_reis
        # Aristocratic Warlord Reis: deep midnight-navy embroidered officer trench + warm bronze/black leather
        top[is_cloth, 0] = np.clip(lum[is_cloth] * 0.24 + 0.02, 0.0, 0.22)
        top[is_cloth, 1] = np.clip(lum[is_cloth] * 0.32 + 0.03, 0.0, 0.28)
        top[is_cloth, 2] = np.clip(lum[is_cloth] * 0.50 + 0.05, 0.0, 0.42)
        top[is_dark, 0] = np.clip(top[is_dark, 0] * 1.10 + 0.04, 0.0, 0.40)
        top[is_dark, 1] = np.clip(top[is_dark, 1] * 0.88 + 0.02, 0.0, 0.32)
        top[is_dark, 2] = np.clip(top[is_dark, 2] * 0.60, 0.0, 0.22)
        # Black tactical fingerless gloves / tanned skin
        top[is_skin, 0] = np.clip(top[is_skin, 0] * 0.82, 0.0, 0.74)
        top[is_skin, 1] = np.clip(top[is_skin, 1] * 0.68, 0.0, 0.60)
        top[is_skin, 2] = np.clip(top[is_skin, 2] * 0.54, 0.0, 0.46)

    new_d = save_np_image(top[:, :, :3], f"Tex_UniDiff_{variant}", "sRGB", tmp_dir, keep_alpha=False, fmt="JPEG")
    new_n = save_np_image(load_image_topdown(img_norm, 512)[:, :, :3], f"Tex_UniNorm_{variant}", "Non-Color", tmp_dir, fmt="JPEG") if img_norm else None
    new_r = save_np_image(load_image_topdown(img_ruff, 512)[:, :, :3], f"Tex_UniRuff_{variant}", "Non-Color", tmp_dir, fmt="JPEG") if img_ruff else None
    return new_d, new_n, new_r


def make_shemagh_texture(tmp_dir: Path) -> bpy.types.Image:
    """Generate crisp 512x512 red-and-white checkered Arab desert keffiyeh (shemagh) woven cloth texture!"""
    sz = 512
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32)
    # Warm sun-bleached cream linen base
    r = np.full((sz, sz), 0.90, dtype=np.float32)
    g = np.full((sz, sz), 0.85, dtype=np.float32)
    b = np.full((sz, sz), 0.78, dtype=np.float32)

    # Classic diagonal houndstooth / checkered crimson keffiyeh weave pattern
    cell = 18.0
    cx = (xx % cell) / cell
    cy = (yy % cell) / cell
    chk = ((np.floor(xx / cell) + np.floor(yy / cell)) % 2) == 0
    fine_h = (np.sin(yy * 0.95) > 0.15)
    fine_v = (np.sin(xx * 0.95) > 0.15)
    red_pat = (chk & (fine_h | fine_v)) | ((~chk) & fine_h & fine_v)
    # Bold crimson border stripes
    border_band = ((yy % 128) < 16) | (((yy % 128) > 22) & ((yy % 128) < 28))
    mask = red_pat | border_band
    weave = 0.025 * np.sin(xx * 1.8) * np.sin(yy * 1.8)
    r = np.where(mask, 0.66 + weave, r + weave)
    g = np.where(mask, 0.17 + weave, g + weave)
    b = np.where(mask, 0.18 + weave, b + weave)
    arr = np.clip(np.stack([r, g, b], axis=2), 0.0, 1.0)
    return save_np_image(arr, "Tex_Ahsarah_Shemagh", "sRGB", tmp_dir, fmt="JPEG")


def grade_aaa_desert_face(src_face_img: bpy.types.Image, variant: str, tmp_dir: Path) -> bpy.types.Image:
    """Warm sun-tanned desert skin + realistic full beard/mustache (Ahsarah/Reis) or charcoal balaclava mask (Saeed) on Leon_Face_D UV!"""
    top = load_image_topdown(src_face_img, 1024)
    h, w = top.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xx / float(w)
    v = yy / float(h)  # top-down: 0=top forehead/hair, ~0.25=eyes, ~0.36=nose, ~0.46=mouth, ~0.55=chin, ~0.65=neck, ~0.85=eyeballs

    # Warm Middle-Eastern / North-African sun-kissed olive-tan skin grade (excluding bottom eyeball islands v > 0.74)
    skin_zone = (v < 0.74)
    top[skin_zone, 0] = np.clip(top[skin_zone, 0] * 0.84, 0.0, 0.84)
    top[skin_zone, 1] = np.clip(top[skin_zone, 1] * 0.72, 0.0, 0.72)
    top[skin_zone, 2] = np.clip(top[skin_zone, 2] * 0.59, 0.0, 0.60)

    # Darken scalp hair at top (v < 0.20) to deep black/espresso
    scalp = (v < 0.18) & ((u < 0.30) | (u > 0.70) | (v < 0.10))
    top[scalp, :3] *= 0.42

    if variant in ("ahsarah_guard", "boss_reis"):
        # Clean, natural rugged desert 5-o'clock jaw stubble (strictly keeping lips & mouth clean warm skin tone!)
        du = (u - 0.50) / 0.18
        dv = (v - 0.545) / 0.105
        jaw_dist = np.sqrt(du * du + dv * dv)
        # Wide mouth exclusion so lips stay 100% natural warm tone (zero dark lip smudge!)
        m_du = (u - 0.50) / 0.095
        m_dv = (v - 0.468) / 0.058
        mouth_mask = np.clip((np.sqrt(m_du * m_du + m_dv * m_dv) - 0.85) * 3.0, 0.0, 1.0)
        jaw_soft = np.clip((1.05 - jaw_dist) * 2.2, 0.0, 1.0)
        v_top_fade = np.clip((v - 0.42) / 0.065, 0.0, 1.0)
        v_bot_fade = np.clip((0.64 - v) / 0.045, 0.0, 1.0)
        beard_field = jaw_soft * v_top_fade * v_bot_fade * mouth_mask
        grain = 0.82 + 0.18 * np.sin(xx * 2.4 + np.sin(yy * 0.9) * 1.6) * np.cos(yy * 1.9)
        strength = np.clip(beard_field * (0.34 if variant == "boss_reis" else 0.28), 0.0, 0.36)
        b_col = np.array([0.11, 0.085, 0.07], dtype=np.float32)
        for c in range(3):
            top[:, :, c] = top[:, :, c] * (1.0 - strength) + (b_col[c] * grain) * strength
    elif variant == "boss_saeed":
        # Paint snug dark charcoal tactical lower-face mask across bridge of nose, cheeks, mouth & chin (eyes fully exposed!)
        mask_edge = 0.335 + 0.035 * np.cos((u - 0.50) * 14.0)
        in_mask = (v > mask_edge) & (v < 0.68) & (u > 0.22) & (u < 0.78)
        weave = 0.014 * np.sin(xx * 1.4) * np.sin(yy * 1.4)
        top[in_mask, 0] = 0.10 + weave[in_mask]
        top[in_mask, 1] = 0.10 + weave[in_mask]
        top[in_mask, 2] = 0.11 + weave[in_mask]

    return save_np_image(top[:, :, :3], f"Tex_Face_{variant}", "sRGB", tmp_dir, fmt="JPEG")


def apply_box_uv_bm(bm: bmesh.types.BMesh, scale: float = 2.0):
    uv_lay = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for l in f.loops:
            co = l.vert.co
            if az >= ax and az >= ay:
                l[uv_lay].uv = (co.x * scale, co.y * scale)
            elif ax >= ay:
                l[uv_lay].uv = (co.y * scale, co.z * scale)
            else:
                l[uv_lay].uv = (co.x * scale, co.z * scale)


def create_rigged_bm_mesh(arm: bpy.types.Object, name: str, bm: bmesh.types.BMesh, mats: list[bpy.types.Material], bone_name: str, uv_scale: float = 2.2) -> bpy.types.Object:
    bm.normal_update()
    apply_box_uv_bm(bm, scale=uv_scale)
    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = arm
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    amod = obj.modifiers.new(name="Armature", type="ARMATURE")
    amod.object = arm
    return obj


def build_keffiyeh_scarf(arm: bpy.types.Object, neck_pos: Vector, sc: float, mat_shemagh: bpy.types.Material) -> bpy.types.Object:
    """Sculpted thick layered desert keffiyeh scarf wrapped cleanly around collar & upper chest."""
    bm = bmesh.new()
    # Multi-ring sculpted draped collar torus + front triangular V-fold!
    n_u, n_v = 28, 12
    R = 0.118 * sc
    r_tube = 0.044 * sc
    verts_grid = []
    for iu in range(n_u):
        ang = (iu / float(n_u)) * math.tau
        ca, sa = math.cos(ang), math.sin(ang)
        # Dip forward & wider over chest (-Y = front where sa < 0)
        front_factor = max(0.0, -sa)
        rad_u = R * (1.0 + 0.14 * front_factor)
        z_drop = -0.042 * sc * (front_factor ** 1.4)
        tube_r = r_tube * (1.0 + 0.35 * front_factor)
        ring = []
        for iv in range(n_v):
            phi = (iv / float(n_v)) * math.tau
            cp, sp = math.cos(phi), math.sin(phi)
            local_r = rad_u + cp * tube_r
            x = ca * local_r
            y = sa * local_r - 0.015 * sc * front_factor
            z = neck_pos.z + 0.025 * sc + z_drop + sp * tube_r * 0.92
            ring.append(bm.verts.new((x, y, z)))
        verts_grid.append(ring)
    for iu in range(n_u):
        iu2 = (iu + 1) % n_u
        for iv in range(n_v):
            iv2 = (iv + 1) % n_v
            bm.faces.new((verts_grid[iu][iv], verts_grid[iu2][iv], verts_grid[iu2][iv2], verts_grid[iu][iv2]))

    # Front draped triangular V-bib hanging down chest
    bib_pts = [
        (-0.140 * sc, -0.118 * sc, neck_pos.z - 0.005 * sc),
        (0.140 * sc, -0.118 * sc, neck_pos.z - 0.005 * sc),
        (0.088 * sc, -0.145 * sc, neck_pos.z - 0.115 * sc),
        (0.0, -0.148 * sc, neck_pos.z - 0.195 * sc),
        (-0.088 * sc, -0.145 * sc, neck_pos.z - 0.115 * sc),
    ]
    bf = [bm.verts.new(p) for p in bib_pts]
    bb = [bm.verts.new((p[0], p[1] + 0.024 * sc, p[2])) for p in bib_pts]
    bm.faces.new(bf)
    bm.faces.new(list(reversed(bb)))
    for i in range(len(bf)):
        j = (i + 1) % len(bf)
        bm.faces.new((bf[i], bb[i], bb[j], bf[j]))

    return create_rigged_bm_mesh(arm, "Ahsarah_Shemagh", bm, [mat_shemagh], "mixamorig:Spine2", uv_scale=3.2)


def make_woven_cloth_texture(tmp_dir: Path, name: str, base_rgb: tuple[float, float, float]) -> bpy.types.Image:
    """Heavy matte woven desert wool/canvas cloth texture with subtle folds & twill grain (ZERO plastic sheen!)."""
    sz = 512
    yy, xx = np.mgrid[0:sz, 0:sz].astype(np.float32)
    twill = 0.035 * np.sin((xx + yy) * 1.35) + 0.022 * np.sin((xx - yy) * 1.85)
    folds = 0.065 * np.sin(xx * 0.055 + np.sin(yy * 0.02) * 1.4) + 0.03 * np.cos(yy * 0.04)
    dust = np.clip((yy / float(sz) - 0.65) * 0.30, 0.0, 0.14)
    r = np.clip(base_rgb[0] * (1.0 + folds + twill) + dust * 0.38, 0.0, 1.0)
    g = np.clip(base_rgb[1] * (1.0 + folds + twill) + dust * 0.28, 0.0, 1.0)
    b = np.clip(base_rgb[2] * (1.0 + folds + twill) + dust * 0.18, 0.0, 1.0)
    arr = np.stack([r, g, b], axis=2)
    return save_np_image(arr, name, "sRGB", tmp_dir, fmt="JPEG")


def build_saeed_hood_and_gear(arm: bpy.types.Object, head_pos: Vector, chest_pos: Vector, sc: float, mat_crimson, mat_bronze, mat_dark, mat_wood):
    """Build Captain Saeed's rich woven crimson desert hood, low-profile antique-bronze Fiery Owl sternum medallion (over AAA Leon.BodyArmour!), back crossbow, and flowing crimson cloak ('saeed_cloak_pivot')!"""
    created = []
    # 1) Snug Heavy-Woven Deep Crimson Desert Hood draping forward over crown & brow (fully enclosing scalp!)
    bm = bmesh.new()
    n_u, n_v = 28, 16
    grid = []
    for iv in range(n_v):
        t = iv / float(n_v - 1)  # 0 = draped collar over shoulders, 1 = forward-overhanging hood peak
        z = head_pos.z - 0.055 * sc + t * 0.300 * sc
        r_lat = (0.136 * sc) * math.sin(min(math.pi * 0.90, 0.46 + t * 2.38)) + 0.026 * sc
        if t < 0.22:
            r_lat += (0.22 - t) * 0.24 * sc
        y_back = -0.010 * sc + (0.018 * sc if t > 0.65 else 0.0)
        ring = []
        for iu in range(n_u):
            ang = math.radians(-124.0 + (iu / float(n_u - 1)) * 248.0)
            x = math.sin(ang) * r_lat
            y = math.cos(ang) * r_lat + y_back
            if t > 0.60:
                # Sweep upper hood arch cleanly forward over forehead/scalp so ZERO bald crown peeks out!
                y -= (t - 0.60) * 0.24 * sc
            ring.append(bm.verts.new((x, y, z)))
        grid.append(ring)
    for iv in range(n_v - 1):
        for iu in range(n_u - 1):
            bm.faces.new((grid[iv][iu], grid[iv][iu + 1], grid[iv + 1][iu + 1], grid[iv + 1][iu]))
    # Cap top hood ridge cleanly so overhead view is completely sealed
    top_row = grid[-1]
    apex = bm.verts.new((0.0, -0.105 * sc, head_pos.z + 0.252 * sc))
    for iu in range(n_u - 1):
        bm.faces.new((top_row[iu], top_row[iu + 1], apex))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.012 * sc)
    created.append(create_rigged_bm_mesh(arm, "Saeed_Hood", bm, [mat_crimson], "mixamorig:Head", uv_scale=2.4))

    # 2) Sleek Low-Profile Sculpted Antique-Bronze Fiery Owl Chest Medallion mounted flush over AAA Leon.BodyArmour!
    bm2 = bmesh.new()
    badge = bmesh.ops.create_cone(bm2, cap_ends=True, segments=6, radius1=0.044 * sc, radius2=0.038 * sc, depth=0.014 * sc)["verts"]
    bmesh.ops.rotate(bm2, matrix=Matrix.Rotation(math.radians(90.0), 3, "X"), verts=badge)
    bmesh.ops.translate(bm2, vec=(0.0, -0.168 * sc, chest_pos.z + 0.045 * sc), verts=badge)
    for sx in (-1.0, 1.0):
        wv = bmesh.ops.create_cube(bm2, size=1.0)["verts"]
        bmesh.ops.scale(bm2, vec=(0.072 * sc, 0.010 * sc, 0.028 * sc), verts=wv)
        bmesh.ops.rotate(bm2, matrix=Matrix.Rotation(math.radians(sx * 20.0), 3, "Y"), verts=wv)
        bmesh.ops.translate(bm2, vec=(sx * 0.056 * sc, -0.162 * sc, chest_pos.z + 0.056 * sc), verts=wv)
    created.append(create_rigged_bm_mesh(arm, "Saeed_OwlCrest", bm2, [mat_bronze], "mixamorig:Spine2", uv_scale=3.0))

    # 3) Back-mounted Dark-Steel Compound Tactical Crossbow
    bm3 = bmesh.new()
    rail = bmesh.ops.create_cube(bm3, size=1.0)["verts"]
    bmesh.ops.scale(bm3, vec=(0.038 * sc, 0.038 * sc, 0.56 * sc), verts=rail)
    for sx in (-1.0, 1.0):
        limb = bmesh.ops.create_cube(bm3, size=1.0)["verts"]
        bmesh.ops.scale(bm3, vec=(0.26 * sc, 0.026 * sc, 0.036 * sc), verts=limb)
        bmesh.ops.rotate(bm3, matrix=Matrix.Rotation(math.radians(sx * 22.0), 3, "Y"), verts=limb)
        bmesh.ops.translate(bm3, vec=(sx * 0.125 * sc, 0.01 * sc, 0.21 * sc), verts=limb)
    st = bmesh.ops.create_cone(bm3, cap_ends=True, segments=6, radius1=0.005 * sc, radius2=0.005 * sc, depth=0.46 * sc)["verts"]
    bmesh.ops.rotate(bm3, matrix=Matrix.Rotation(math.radians(90.0), 3, "Y"), verts=st)
    bmesh.ops.translate(bm3, vec=(0.0, 0.01 * sc, 0.14 * sc), verts=st)
    bmesh.ops.rotate(bm3, matrix=Matrix.Rotation(math.radians(-30.0), 3, "Y"), verts=bm3.verts[:])
    bmesh.ops.translate(bm3, vec=(0.05 * sc, 0.185 * sc, chest_pos.z + 0.05 * sc), verts=bm3.verts[:])
    created.append(create_rigged_bm_mesh(arm, "Saeed_Crossbow", bm3, [mat_dark], "mixamorig:Spine2", uv_scale=2.5))

    # 4) Articulated Flowing Woven Deep-Crimson Desert Cloak ('saeed_cloak_pivot' child node)
    bm4 = bmesh.new()
    rows, cols = 10, 9
    cgrid = []
    for ir in range(rows):
        t = ir / float(rows - 1)
        z = -t * 1.12 * sc
        half_w = (0.19 + t * 0.20) * sc
        y_off = 0.05 * sc + t * 0.15 * sc
        row = []
        for ic in range(cols):
            u = (ic / float(cols - 1)) * 2.0 - 1.0
            x = u * half_w
            y = y_off - (1.0 - u * u) * 0.035 * sc + math.sin(u * 5.2) * 0.022 * sc * t
            row.append(bm4.verts.new((x, y, z)))
        cgrid.append(row)
    for ir in range(rows - 1):
        for ic in range(cols - 1):
            bm4.faces.new((cgrid[ir][ic], cgrid[ir][ic + 1], cgrid[ir + 1][ic + 1], cgrid[ir + 1][ic]))
    bmesh.ops.solidify(bm4, geom=bm4.faces[:], thickness=0.010 * sc)
    bm4.normal_update()
    apply_box_uv_bm(bm4, scale=2.0)
    me4 = bpy.data.meshes.new("saeed_cloak_pivot_Mesh")
    bm4.to_mesh(me4)
    bm4.free()
    me4.materials.append(mat_crimson)
    for p in me4.polygons:
        p.use_smooth = True
    cloak_obj = bpy.data.objects.new("saeed_cloak_pivot", me4)
    bpy.context.scene.collection.objects.link(cloak_obj)
    cloak_obj.location = Vector((0.0, 0.155 * sc, chest_pos.z + 0.135 * sc))
    return created, cloak_obj


def build_reis_armor_and_gramophone(arm: bpy.types.Object, chest_pos: Vector, sc: float, mat_bronze, mat_gold, mat_wood, mat_dark):
    """Build Warlord Reis's aristocratic gilded high collar & refined compact antique mahogany/brass Gramophone ('reis_gramophone') — paired with AAA Leon.BodyArmour + sculpted Blizzard shoulder pauldrons!"""
    created = []
    # Sleek upturned aristocratic gold-edged officer collar behind neck (ZERO blocky chestplates or sphere pauldrons!)
    bm = bmesh.new()
    n_u = 18
    c_bot, c_top = [], []
    for iu in range(n_u):
        ang = math.radians(-105.0 + (iu / float(n_u - 1)) * 210.0)
        ca, sa = math.cos(ang), math.sin(ang)
        c_bot.append(bm.verts.new((sa * 0.105 * sc, ca * 0.105 * sc + 0.008 * sc, chest_pos.z + 0.165 * sc)))
        c_top.append(bm.verts.new((sa * 0.128 * sc, ca * 0.128 * sc + 0.022 * sc, chest_pos.z + 0.245 * sc)))
    collar_faces = []
    for iu in range(n_u - 1):
        f = bm.faces.new((c_bot[iu], c_bot[iu + 1], c_top[iu + 1], c_top[iu]))
        f.material_index = 1
        collar_faces.append(f)
    bmesh.ops.solidify(bm, geom=collar_faces, thickness=0.011 * sc)
    created.append(create_rigged_bm_mesh(arm, "Reis_OfficerCollar", bm, [mat_bronze, mat_gold], "mixamorig:Spine2", uv_scale=2.8))

    # Signature Compact Articulated Antique Walnut & Fluted Burnished-Brass Gramophone ('reis_gramophone')!
    # Sized tastefully so the ENTIRE flared horn stays richly visible INSIDE both preview & 512x640 portrait!
    bm2 = bmesh.new()
    gsc = sc * 0.72
    box = bmesh.ops.create_cube(bm2, size=1.0)["verts"]
    bmesh.ops.scale(bm2, vec=(0.20 * gsc, 0.20 * gsc, 0.115 * gsc), verts=box)
    bmesh.ops.bevel(bm2, geom=bm2.edges[:], offset=0.012 * gsc, segments=2, affect="EDGES")
    for f in bm2.faces:
        f.material_index = 0  # dark walnut wood
    # Subtle brass corner trim lip around cabinet top
    lip = bmesh.ops.create_cube(bm2, size=1.0)["verts"]
    bmesh.ops.scale(bm2, vec=(0.214 * gsc, 0.214 * gsc, 0.018 * gsc), verts=lip)
    bmesh.ops.translate(bm2, vec=(0.0, 0.0, 0.056 * gsc), verts=lip)
    for f in bm2.faces:
        if any(v in lip for v in f.verts):
            f.material_index = 1
    # Black vinyl turntable platter
    disc = bmesh.ops.create_cone(bm2, cap_ends=True, segments=20, radius1=0.078 * gsc, radius2=0.078 * gsc, depth=0.012 * gsc)["verts"]
    bmesh.ops.translate(bm2, vec=(0.0, 0.0, 0.070 * gsc), verts=disc)
    for f in bm2.faces:
        if any(v in disc for v in f.verts):
            f.material_index = 2
    # Curved Brass Swan-Neck & Fluted Vintage Bell Horn
    horn_rings = []
    segs = 20
    profile = [
        (0.0, 0.065 * gsc, 0.070 * gsc, 0.013 * gsc),
        (0.0, 0.088 * gsc, 0.135 * gsc, 0.020 * gsc),
        (0.0, 0.048 * gsc, 0.195 * gsc, 0.036 * gsc),
        (0.0, -0.018 * gsc, 0.245 * gsc, 0.068 * gsc),
        (0.0, -0.085 * gsc, 0.292 * gsc, 0.118 * gsc),
        (0.0, -0.125 * gsc, 0.322 * gsc, 0.152 * gsc),
    ]
    for ir_p, (cx, cy, cz, rad) in enumerate(profile):
        ring = []
        for i in range(segs):
            a = (i / float(segs)) * math.tau
            flute = 1.0 + (0.045 * math.sin(a * 10.0) if ir_p >= 3 else 0.0)
            rx = math.cos(a) * rad * flute
            ry = math.sin(a) * rad * flute * 0.55
            rz = math.sin(a) * rad * flute * 0.84
            ring.append(bm2.verts.new((cx + rx, cy + ry, cz + rz)))
        horn_rings.append(ring)
    horn_faces = []
    for ir in range(len(horn_rings) - 1):
        for i in range(segs):
            j = (i + 1) % segs
            f = bm2.faces.new((horn_rings[ir][i], horn_rings[ir][j], horn_rings[ir + 1][j], horn_rings[ir + 1][i]))
            f.material_index = 1
            horn_faces.append(f)
    bmesh.ops.solidify(bm2, geom=horn_faces, thickness=0.006 * gsc)
    bm2.normal_update()
    apply_box_uv_bm(bm2, scale=2.6)
    me2 = bpy.data.meshes.new("reis_gramophone_Mesh")
    bm2.to_mesh(me2)
    bm2.free()
    me2.materials.append(mat_wood)
    me2.materials.append(mat_gold)
    me2.materials.append(mat_dark)
    for p in me2.polygons:
        p.use_smooth = True
    gramo = bpy.data.objects.new("reis_gramophone", me2)
    bpy.context.scene.collection.objects.link(gramo)
    # Mounted cleanly on Reis's left shoulder-pack (+X, slightly back +Y so it frames his face heroically!)
    gramo.location = Vector((0.235 * sc, 0.065 * sc, chest_pos.z + 0.195 * sc))
    return created, gramo


def build_faction_weapon(arm: bpy.types.Object, variant: str, sc: float, mat_gun, mat_accent, mat_olive) -> bpy.types.Object:
    """Import detailed CC0 rifle.glb aligned to Weapon_R (+Y barrel), upgrading silhouette for M249 (Saeed) & S12K (Reis)!"""
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
            rot_m = Matrix.Rotation(math.pi * 0.5, 4, "Z") if (dims.x > dims.y and dims.x > dims.z) else Matrix.Identity(4)
            rpts = [rot_m @ p for p in pts]
            rmin = Vector((min(p.x for p in rpts), min(p.y for p in rpts), min(p.z for p in rpts)))
            rmax = Vector((max(p.x for p in rpts), max(p.y for p in rpts), max(p.z for p in rpts)))
            rlen = max(0.1, rmax.y - rmin.y)
            low_z = [p.z for p in rpts if p.y < rmin.y + rlen * 0.16]
            hi_z = [p.z for p in rpts if p.y > rmax.y - rlen * 0.16]
            if (max(low_z) - min(low_z)) < (max(hi_z) - min(hi_z)):
                rot_m = Matrix.Rotation(math.pi, 4, "Z") @ rot_m
                rpts = [rot_m @ p for p in pts]
                rmin = Vector((min(p.x for p in rpts), min(p.y for p in rpts), min(p.z for p in rpts)))
                rmax = Vector((max(p.x for p in rpts), max(p.y for p in rpts), max(p.z for p in rpts)))
                rlen = max(0.1, rmax.y - rmin.y)
            tlen = (0.98 if variant == "boss_saeed" else (0.92 if variant == "boss_reis" else 0.80)) * sc
            wsc = tlen / rlen
            rcen = Vector((0.5 * (rmin.x + rmax.x), rmin.y + rlen * 0.38, rmin.z + (rmax.z - rmin.z) * 0.44))
            for o in imp_meshes:
                tbm = bmesh.new()
                tbm.from_mesh(o.data)
                for v in tbm.verts:
                    wp = rot_m @ (o.matrix_world @ v.co)
                    v.co = origin + (wp - rcen) * wsc
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

    # Boss-specific sleek tactical weapon upgrades (matte finish, zero blocky glossy rectangles!)
    if variant == "boss_saeed":
        # M249 compact dark-olive tactical drum pouch (beveled matte!)
        bx = bmesh.ops.create_cube(bm, size=1.0)["verts"]
        bmesh.ops.scale(bm, vec=(0.068 * sc, 0.105 * sc, 0.092 * sc), verts=bx)
        bmesh.ops.translate(bm, vec=origin + Vector((0.0, 0.075 * sc, -0.072 * sc)), verts=bx)
        for f in bm.faces:
            if any(v in bx for v in f.verts):
                f.material_index = 2
    elif variant == "boss_reis":
        # S12K sleek tactical extended box magazine
        mag = bmesh.ops.create_cube(bm, size=1.0)["verts"]
        bmesh.ops.scale(bm, vec=(0.036 * sc, 0.078 * sc, 0.145 * sc), verts=mag)
        bmesh.ops.translate(bm, vec=origin + Vector((0.0, 0.105 * sc, -0.078 * sc)), verts=mag)
        for f in bm.faces:
            if any(v in mag for v in f.verts):
                f.material_index = 0

    return create_rigged_bm_mesh(arm, f"{variant}_Weapon", bm, [mat_gun, mat_accent, mat_olive], "Weapon_R", uv_scale=3.0)


def append_aaa_head_from_re(
    re_blend: Path,
    pharah_blend: Path,
    arm: bpy.types.Object,
    variant: str,
    target_height: float,
    tmp_dir: Path,
) -> list[bpy.types.Object]:
    """Append unmodified AAA sculpted male head (eyes, brows, hair) + AAA Leon.BodyArmour ballistic tactical vest (Saeed/Reis)
    strictly rotated +90 deg X into upright Z-up space facing -Y, plus Blizzard aviator sunglasses & armored shoulder pauldrons for Reis!"""
    need_objs = ["Leon.Head", "Leon.Cornea", "Leon.Brows/Lashes", "Leon.Teeth"]
    if variant != "boss_saeed":
        need_objs += ["Leon.Hair", "Leon.Hair_xtra"]
    if variant in ("boss_saeed", "boss_reis"):
        need_objs += ["Leon.BodyArmour"]

    with bpy.data.libraries.load(str(re_blend), link=False) as (data_from, data_to):
        data_to.objects = [n for n in need_objs if n in data_from.objects]
        data_to.images = [
            n for n in ["Leon_Face_D.tga", "Leon_Face_N.tga", "Leon_Hair_D.tga", "Leon_Hair_N.tga", "Leon_Eyebrows_D.tga", "Leon_Eyebrows_N.tga"]
            if n in data_from.images
        ]

    appended = [o for o in data_to.objects if o is not None]
    sc_col = bpy.context.scene.collection
    rot_yup_to_zup = Matrix.Rotation(math.radians(90.0), 4, "X")
    for o in appended:
        if o.name not in sc_col.objects:
            sc_col.objects.link(o)
        o.hide_viewport = False
        o.hide_render = False
        o.hide_select = False
        o.parent = None
        for mod in list(o.modifiers):
            o.modifiers.remove(mod)
        if o.data.shape_keys is not None:
            o.shape_key_clear()
        # CRITICAL FIX: Leon meshes are authored Y-up (Y=1.0..1.83, Z=-0.15..+0.15) with rot_x=+90 deg on the object!
        # Explicitly rotate raw Y-up vertex coordinates by +90 deg X so EVERY head & vest stands DEAD-UPRIGHT facing -Y!
        raw_ys = [v.co.y for v in o.data.vertices]
        raw_zs = [v.co.z for v in o.data.vertices]
        if raw_ys and (max(raw_ys) > 0.70 and max(raw_zs) < 0.50):
            o.data.transform(rot_yup_to_zup)
        else:
            bpy.context.view_layer.update()
            o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)

    # Separate head meshes from AAA BodyArmour vest
    vest_obj = next((o for o in appended if "bodyarmour" in o.name.lower()), None)
    head_pieces = [o for o in appended if o is not vest_obj]

    # Measure Leon's exact upright head center in Z-up space (~z in [1.46..1.81], facing -Y!)
    h_obj = next(o for o in head_pieces if o.name.startswith("Leon.Head"))
    pts = [v.co for v in h_obj.data.vertices]
    l_min_z, l_max_z = min(p.z for p in pts), max(p.z for p in pts)
    l_cx = 0.5 * (min(p.x for p in pts) + max(p.x for p in pts))
    l_cy = 0.5 * (min(p.y for p in pts) + max(p.y for p in pts))
    print(f"  [{variant}] Upright Leon.Head z=[{l_min_z:.3f},{l_max_z:.3f}] y=[{min(p.y for p in pts):.3f},{max(p.y for p in pts):.3f}]")
    hb = arm.data.bones["mixamorig:Head"]
    head_sc = (target_height / 1.84) * 1.03
    src_anchor = Vector((l_cx, l_cy, l_min_z + (l_max_z - l_min_z) * 0.34))
    tgt_anchor = hb.head_local + Vector((0.0, -0.008 * head_sc, -0.015 * head_sc))

    img_face_src = bpy.data.images.get("Leon_Face_D.tga")
    img_face_n_src = bpy.data.images.get("Leon_Face_N.tga")
    img_brow_src = bpy.data.images.get("Leon_Eyebrows_D.tga")
    img_hair_src = bpy.data.images.get("Leon_Hair_D.tga")

    face_d = grade_aaa_desert_face(img_face_src, variant, tmp_dir)
    face_n = save_np_image(load_image_topdown(img_face_n_src, 512)[:, :, :3], f"Tex_FaceN_{variant}", "Non-Color", tmp_dir, fmt="JPEG")
    brow_rgba = load_image_topdown(img_brow_src, 512)
    brow_rgba[:, :, :3] *= 0.35
    brow_d = save_np_image(brow_rgba, f"Tex_Brow_{variant}", "sRGB", tmp_dir, keep_alpha=True, fmt="PNG")

    mat_head = make_pbr_mat(f"Mat_{variant}_Head", face_d, face_n, roughness=0.68, normal_scale=0.52)
    mat_eyes = make_pbr_mat(f"Mat_{variant}_Eyes", face_d, None, roughness=0.18, metallic=0.0)
    mat_brows = make_pbr_mat(f"Mat_{variant}_Brows", brow_d, None, roughness=0.72, alpha_clip=0.18, double_sided=True)
    mat_lashes = make_pbr_mat(f"Mat_{variant}_Lashes", brow_d, None, roughness=0.70, alpha_clip=0.22, double_sided=True)

    mat_hair = None
    if variant != "boss_saeed" and img_hair_src is not None:
        hair_rgba = load_image_topdown(img_hair_src, 512)
        hair_rgba[:, :, :3] = np.clip(hair_rgba[:, :, :3] * 0.24, 0.0, 1.0)
        hair_d = save_np_image(hair_rgba, f"Tex_Hair_{variant}", "sRGB", tmp_dir, keep_alpha=True, fmt="PNG")
        mat_hair = make_pbr_mat(f"Mat_{variant}_Hair", hair_d, None, roughness=0.60, alpha_clip=0.30, double_sided=True)

    out_objs: list[bpy.types.Object] = []
    for o in head_pieces:
        xform = Matrix.Translation(tgt_anchor) @ Matrix.Diagonal((head_sc, head_sc, head_sc, 1.0)) @ Matrix.Translation(-src_anchor)
        o.data.transform(xform)
        uvs = o.data.uv_layers
        if len(uvs) == 0:
            uvs.new(name="UVMap")
        else:
            uvs.active_index = 0
            uvs[0].name = "UVMap"
            while len(uvs) > 1:
                uvs.remove(uvs[-1])
        on = o.name.lower()
        if "cornea" in on:
            o.data.materials.clear(); o.data.materials.append(mat_eyes)
        elif "brow" in on:
            for i in range(len(o.data.materials)):
                o.data.materials[i] = mat_brows if i == 0 else mat_lashes
        elif "hair" in on and mat_hair is not None:
            o.data.materials.clear(); o.data.materials.append(mat_hair)
            if len(o.data.polygons) > 4500:
                bpy.context.view_layer.objects.active = o
                dec = o.modifiers.new("Dec", "DECIMATE")
                dec.ratio = 0.55
                bpy.ops.object.modifier_apply(modifier=dec.name)
        else:
            o.data.materials.clear(); o.data.materials.append(mat_head)
            if "head" in on and len(o.data.polygons) > 3600:
                bpy.context.view_layer.objects.active = o
                dec = o.modifiers.new("Dec", "DECIMATE")
                dec.ratio = 0.72
                bpy.ops.object.modifier_apply(modifier=dec.name)

        o.vertex_groups.clear()
        vg = o.vertex_groups.new(name="mixamorig:Head")
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        o.parent = arm
        amod = o.modifiers.new(name="Armature", type="ARMATURE")
        amod.object = arm
        for p in o.data.polygons:
            p.use_smooth = True
        out_objs.append(o)

    # Fit REAL AAA Capcom Leon.BodyArmour tactical armored vest onto Saeed & Reis (replacing boxy bmesh armor!)
    if vest_obj is not None:
        v_diff_src, v_norm_src = None, None
        for m in vest_obj.data.materials:
            if m and m.use_nodes and m.node_tree:
                for n in m.node_tree.nodes:
                    if n.type == "TEX_IMAGE" and n.image is not None:
                        inm = n.image.name.lower()
                        if "_d" in inm or "albedo" in inm or "diff" in inm:
                            v_diff_src = n.image
                        elif "_n" in inm or "norm" in inm:
                            v_norm_src = n.image
        if v_diff_src is not None:
            varr = load_image_topdown(v_diff_src, 512)[:, :, :3]
            vlum = 0.299 * varr[:, :, 0] + 0.587 * varr[:, :, 1] + 0.114 * varr[:, :, 2]
            # COMPLETELY scrub bright white 'R.P.D.' chest lettering by clamping all bright text pixels into smooth dark weave!
            flat_lum = np.where(vlum > 0.28, 0.18 + (vlum - 0.28) * 0.12, vlum)
            if variant == "boss_saeed":
                # Matte charcoal-obsidian tactical Kevlar vest (ZERO R.P.D. text!)
                varr[:, :, 0] = np.clip(flat_lum * 0.52 + 0.04, 0.0, 0.24)
                varr[:, :, 1] = np.clip(flat_lum * 0.48 + 0.035, 0.0, 0.22)
                varr[:, :, 2] = np.clip(flat_lum * 0.46 + 0.035, 0.0, 0.22)
            else:
                # Warlord Reis: royal dark midnight-navy ballistic vest (ZERO R.P.D. text!)
                varr[:, :, 0] = np.clip(flat_lum * 0.32 + 0.025, 0.0, 0.18)
                varr[:, :, 1] = np.clip(flat_lum * 0.42 + 0.035, 0.0, 0.24)
                varr[:, :, 2] = np.clip(flat_lum * 0.72 + 0.055, 0.0, 0.38)
            vd_img = save_np_image(varr, f"Tex_VestD_{variant}", "sRGB", tmp_dir, fmt="JPEG")
            vn_img = save_np_image(load_image_topdown(v_norm_src, 512)[:, :, :3], f"Tex_VestN_{variant}", "Non-Color", tmp_dir, fmt="JPEG") if v_norm_src else None
            mat_vest = make_pbr_mat(f"Mat_{variant}_TacticalVest", vd_img, vn_img, roughness=0.66, metallic=0.18 if variant == "boss_reis" else 0.10, normal_scale=0.68)
        else:
            mat_vest = make_pbr_mat(f"Mat_{variant}_TacticalVest", base_color=(0.14, 0.14, 0.16, 1.0), roughness=0.66, metallic=0.14)

        vpts = [v.co for v in vest_obj.data.vertices]
        vcen = Vector((
            0.5 * (min(p.x for p in vpts) + max(p.x for p in vpts)),
            0.5 * (min(p.y for p in vpts) + max(p.y for p in vpts)),
            0.5 * (min(p.z for p in vpts) + max(p.z for p in vpts)),
        ))
        sp2 = arm.data.bones["mixamorig:Spine2"]
        vest_sc = (target_height / 1.84) * 1.04
        # Lower vest cleanly onto shoulders/chest so straps sit flush below jawline (never crowding chin!)
        vest_tgt = Vector((0.0, sp2.head_local.y - 0.010 * vest_sc, sp2.head_local.z - 0.055 * vest_sc))
        vest_obj.data.transform(Matrix.Translation(vest_tgt) @ Matrix.Diagonal((vest_sc * 1.02, vest_sc * 1.12, vest_sc * 0.96, 1.0)) @ Matrix.Translation(-vcen))
        # Prune any stray detached forearm/elbow straps far outside the torso (|x| > 0.22 * vest_sc) so ZERO floating clips appear on Saeed's sleeves!
        bm_v = bmesh.new()
        bm_v.from_mesh(vest_obj.data)
        stray_v = [v for v in bm_v.verts if abs(v.co.x) > 0.215 * vest_sc]
        if stray_v:
            bmesh.ops.delete(bm_v, geom=stray_v, context="VERTS")
        bm_v.to_mesh(vest_obj.data)
        bm_v.free()
        vest_obj.data.validate(verbose=False)
        uvs = vest_obj.data.uv_layers
        if len(uvs) == 0:
            uvs.new(name="UVMap")
        else:
            uvs.active_index = 0; uvs[0].name = "UVMap"
            while len(uvs) > 1:
                uvs.remove(uvs[-1])
        vest_obj.data.materials.clear()
        vest_obj.data.materials.append(mat_vest)
        if len(vest_obj.data.polygons) > 3200:
            bpy.context.view_layer.objects.active = vest_obj
            dec = vest_obj.modifiers.new("Dec", "DECIMATE")
            dec.ratio = 0.45
            bpy.ops.object.modifier_apply(modifier=dec.name)
        vest_obj.vertex_groups.clear()
        vg = vest_obj.vertex_groups.new(name="mixamorig:Spine2")
        vg.add(list(range(len(vest_obj.data.vertices))), 1.0, "REPLACE")
        vest_obj.parent = arm
        amod = vest_obj.modifiers.new(name="Armature", type="ARMATURE")
        amod.object = arm
        for p in vest_obj.data.polygons:
            p.use_smooth = True
        vest_obj.name = f"{variant}_TacticalVest"
        out_objs.append(vest_obj)

    # For Warlord Reis: append REAL AAA Blizzard Aviator Sunglasses AND sculpted metallic armored shoulder pauldrons!
    if variant == "boss_reis":
        with bpy.data.libraries.load(str(pharah_blend), link=False) as (df, dt):
            dt.objects = [n for n in ["ARMR--aviator__head-sunglasses", "ARMR--default__arms-pauldrons"] if n in df.objects]
            dt.images = [n for n in ["ARMR__anubis-D.jpg", "ARMR__anubis-N.jpg"] if n in df.images]
        app_ph = [o for o in dt.objects if o is not None]
        sg = next((o for o in app_ph if "sunglasses" in o.name.lower()), None)
        pauld = next((o for o in app_ph if "pauldrons" in o.name.lower()), None)

        if sg is not None:
            sc_col.objects.link(sg)
            sg.hide_viewport = False; sg.hide_render = False; sg.hide_select = False
            sg.parent = None
            for mod in list(sg.modifiers):
                sg.modifiers.remove(mod)
            bpy.context.view_layer.update()
            sg.data.transform(sg.matrix_world)
            sg.matrix_world = Matrix.Identity(4)
            eye_o = next(o for o in out_objs if "cornea" in o.name.lower())
            e_pts = [v.co for v in eye_o.data.vertices]
            eye_cen = Vector((
                0.5 * (min(p.x for p in e_pts) + max(p.x for p in e_pts)),
                min(p.y for p in e_pts) - 0.014 * head_sc,
                0.5 * (min(p.z for p in e_pts) + max(p.z for p in e_pts)),
            ))
            s_pts = [v.co for v in sg.data.vertices]
            s_cen = Vector((
                0.5 * (min(p.x for p in s_pts) + max(p.x for p in s_pts)),
                0.5 * (min(p.y for p in s_pts) + max(p.y for p in s_pts)),
                0.5 * (min(p.z for p in s_pts) + max(p.z for p in s_pts)),
            ))
            s_w = max(0.05, max(p.x for p in s_pts) - min(p.x for p in s_pts))
            ssc = (0.146 * head_sc) / s_w
            sg.data.transform(Matrix.Translation(eye_cen) @ Matrix.Diagonal((ssc, ssc, ssc, 1.0)) @ Matrix.Translation(-s_cen))
            uvs = sg.data.uv_layers
            if len(uvs) == 0:
                uvs.new(name="UVMap")
            else:
                uvs.active_index = 0; uvs[0].name = "UVMap"
                while len(uvs) > 1:
                    uvs.remove(uvs[-1])
            mat_lens = make_pbr_mat("Mat_Reis_ShadesLens", base_color=(0.05, 0.05, 0.06, 1.0), roughness=0.08, metallic=0.65)
            mat_frame = make_pbr_mat("Mat_Reis_ShadesFrame", base_color=(0.86, 0.66, 0.22, 1.0), roughness=0.22, metallic=0.92)
            for i in range(len(sg.data.materials)):
                sg.data.materials[i] = mat_lens if i == 0 else mat_frame
            sg.vertex_groups.clear()
            vg = sg.vertex_groups.new(name="mixamorig:Head")
            vg.add(list(range(len(sg.data.vertices))), 1.0, "REPLACE")
            sg.parent = arm
            amod = sg.modifiers.new(name="Armature", type="ARMATURE")
            amod.object = arm
            sg.name = "Reis_AviatorSunglasses"
            out_objs.append(sg)

        if pauld is not None:
            sc_col.objects.link(pauld)
            pauld.hide_viewport = False; pauld.hide_render = False; pauld.hide_select = False
            pauld.parent = None
            bpy.context.view_layer.objects.active = pauld
            for mod in list(pauld.modifiers):
                if mod.type == "MIRROR":
                    try:
                        bpy.ops.object.modifier_apply(modifier=mod.name)
                    except Exception:
                        pauld.modifiers.remove(mod)
                else:
                    pauld.modifiers.remove(mod)
            bpy.context.view_layer.update()
            pauld.data.transform(pauld.matrix_world)
            pauld.matrix_world = Matrix.Identity(4)
            p_pts = [v.co for v in pauld.data.vertices]
            pcen = Vector((
                0.5 * (min(p.x for p in p_pts) + max(p.x for p in p_pts)),
                0.5 * (min(p.y for p in p_pts) + max(p.y for p in p_pts)),
                0.5 * (min(p.z for p in p_pts) + max(p.z for p in p_pts)),
            ))
            p_w = max(0.2, max(p.x for p in p_pts) - min(p.x for p in p_pts))
            l_sh = arm.data.bones["mixamorig:LeftArm"].head_local
            r_sh = arm.data.bones["mixamorig:RightArm"].head_local
            sh_span = abs(l_sh.x - r_sh.x) * 2.15
            psc = sh_span / p_w
            sh_mid = Vector((0.0, 0.5 * (l_sh.y + r_sh.y) - 0.01 * psc, 0.5 * (l_sh.z + r_sh.z) + 0.045 * (target_height / 1.80)))
            pauld.data.transform(Matrix.Translation(sh_mid) @ Matrix.Diagonal((psc, psc, psc * 0.88, 1.0)) @ Matrix.Translation(-pcen))
            uvs = pauld.data.uv_layers
            if len(uvs) == 0:
                uvs.new(name="UVMap")
            else:
                uvs.active_index = 0; uvs[0].name = "UVMap"
                while len(uvs) > 1:
                    uvs.remove(uvs[-1])
            an_d = bpy.data.images.get("ARMR__anubis-D.jpg")
            an_n = bpy.data.images.get("ARMR__anubis-N.jpg")
            if an_d is not None:
                aarr = load_image_topdown(an_d, 512)[:, :, :3]
                alum = 0.299 * aarr[:, :, 0] + 0.587 * aarr[:, :, 1] + 0.114 * aarr[:, :, 2]
                is_gold = (aarr[:, :, 0] > aarr[:, :, 2] * 1.25) & (alum > 0.24)
                aarr[:, :, 0] = np.where(is_gold, np.clip(aarr[:, :, 0] * 1.15, 0.0, 0.92), np.clip(alum * 0.22 + 0.02, 0.0, 0.20))
                aarr[:, :, 1] = np.where(is_gold, np.clip(aarr[:, :, 1] * 0.95, 0.0, 0.72), np.clip(alum * 0.28 + 0.03, 0.0, 0.26))
                aarr[:, :, 2] = np.where(is_gold, np.clip(aarr[:, :, 2] * 0.42, 0.0, 0.26), np.clip(alum * 0.46 + 0.05, 0.0, 0.42))
                pd_img = save_np_image(aarr, "Tex_Reis_PauldronsD", "sRGB", tmp_dir, fmt="JPEG")
                pn_img = save_np_image(load_image_topdown(an_n, 512)[:, :, :3], "Tex_Reis_PauldronsN", "Non-Color", tmp_dir, fmt="JPEG") if an_n else None
                mat_pauld = make_pbr_mat("Mat_Reis_GildedPauldrons", pd_img, pn_img, roughness=0.34, metallic=0.78, normal_scale=0.80)
            else:
                mat_pauld = make_pbr_mat("Mat_Reis_GildedPauldrons", base_color=(0.76, 0.58, 0.20, 1.0), roughness=0.32, metallic=0.82)
            for i in range(len(pauld.material_slots)):
                pauld.material_slots[i].link = "DATA"
                pauld.data.materials[i] = mat_pauld
            if len(pauld.data.polygons) > 2200:
                bpy.context.view_layer.objects.active = pauld
                dec = pauld.modifiers.new("Dec", "DECIMATE")
                dec.ratio = 0.45
                bpy.ops.object.modifier_apply(modifier=dec.name)
            pauld.vertex_groups.clear()
            vg = pauld.vertex_groups.new(name="mixamorig:Spine2")
            vg.add(list(range(len(pauld.data.vertices))), 1.0, "REPLACE")
            pauld.parent = arm
            amod = pauld.modifiers.new(name="Armature", type="ARMATURE")
            amod.object = arm
            for p in pauld.data.polygons:
                p.use_smooth = True
            pauld.name = "Reis_ArmoredPauldrons"
            out_objs.append(pauld)

    return out_objs


def set_world_rot_delta(pb: bpy.types.PoseBone, arm_obj: bpy.types.Object, world_axis: tuple[float, float, float], angle_deg: float):
    q_world = Quaternion(Vector(world_axis).normalized(), math.radians(angle_deg))
    rest_rot = (arm_obj.matrix_world.to_3x3() @ pb.bone.matrix_local.to_3x3()).to_quaternion()
    q_local = rest_rot.inverted() @ q_world @ rest_rot
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = q_local @ pb.rotation_quaternion


def pose_desert_combat(arm: bpy.types.Object, phase: float, gait_amp: float = 0.0, run_lean: float = 0.0):
    """World-space quaternion combat animation on Panzergrenadier Mixamo rig:
    100% immune to glTF rest-axis drift — level gaze, boots planted on Z=0, crisp 2-handed rifle grip!
    """
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = Vector((0, 0, 0))

    breath = math.sin(phase * 2.0)
    sway = math.sin(phase)
    stride = math.sin(phase) * gait_amp
    opp = -stride

    def rot(bname: str, axis: tuple[float, float, float], deg: float):
        pb = arm.pose.bones.get(bname)
        if pb is not None:
            set_world_rot_delta(pb, arm, axis, deg)

    # Subtle combat posture + dead-level forward gaze!
    rot("mixamorig:Spine", (1, 0, 0), -(2.0 + run_lean * 0.6) + breath * 1.0)
    rot("mixamorig:Spine2", (1, 0, 0), -(1.5 + run_lean * 0.4) + breath * 1.2)
    rot("mixamorig:Spine", (0, 0, 1), sway * (1.8 + gait_amp * 4.0))
    rot("mixamorig:Head", (0, 0, 1), -sway * (1.5 + gait_amp * 2.5))
    rot("mixamorig:Head", (1, 0, 0), 2.5 + run_lean * 0.8)

    # Right & Left arms: Low-ready mid-chest tactical rifle carry (leaves shemagh, owl badge & collar 100% visible!)
    rot("mixamorig:RightShoulder", (0, 1, 0), -5.0)
    rot("mixamorig:RightArm", (0, 1, 0), -22.0 + breath * 1.0)
    rot("mixamorig:RightArm", (1, 0, 0), -20.0 + stride * 5.0)
    rot("mixamorig:RightArm", (0, 0, 1), 16.0)
    rot("mixamorig:RightForeArm", (1, 0, 0), -34.0)
    rot("mixamorig:RightForeArm", (0, 0, 1), 36.0)
    rot("mixamorig:RightHand", (0, 1, 0), 32.0)

    rot("mixamorig:LeftShoulder", (0, 1, 0), 5.0)
    rot("mixamorig:LeftArm", (0, 1, 0), 20.0 - breath * 1.0)
    rot("mixamorig:LeftArm", (1, 0, 0), -28.0 + opp * 5.0)
    rot("mixamorig:LeftArm", (0, 0, 1), -22.0)
    rot("mixamorig:LeftForeArm", (1, 0, 0), -30.0)
    rot("mixamorig:LeftForeArm", (0, 0, 1), -42.0)
    rot("mixamorig:LeftHand", (0, 1, 0), -28.0)

    # Curl ALL fingers tightly into natural closed rifle grip (ZERO flat open "jazz hands"!)
    for side_p in ("LeftHand", "RightHand"):
        for f_nm in ("Index", "Middle", "Ring", "Pinky"):
            for seg, deg in [(1, 58.0), (2, 68.0), (3, 42.0)]:
                fpb = arm.pose.bones.get(f"mixamorig:{side_p}{f_nm}{seg}")
                if fpb is not None:
                    fpb.rotation_mode = "QUATERNION"
                    fpb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0), math.radians(deg))
        for seg, deg in [(1, 24.0), (2, 34.0), (3, 28.0)]:
            tpb = arm.pose.bones.get(f"mixamorig:{side_p}Thumb{seg}")
            if tpb is not None:
                tpb.rotation_mode = "QUATERNION"
                tpb.rotation_quaternion = Quaternion((0.0, 0.0, 1.0), math.radians(deg if "Left" in side_p else -deg))

    # Align Weapon_R barrel straight forward-left (-Y/+X) held naturally across chest in both hands!
    bpy.context.view_layer.update()
    pb_wr = arm.pose.bones.get("Weapon_R")
    pb_hr = arm.pose.bones.get("mixamorig:RightHand")
    pb_hl = arm.pose.bones.get("mixamorig:LeftHand")
    if pb_wr is not None and pb_hr is not None and pb_hl is not None:
        mw = arm.matrix_world
        pr = mw @ pb_hr.head
        pl = mw @ pb_hl.head
        aim_dir = (pl - pr)
        if aim_dir.length > 0.08:
            aim_dir = aim_dir.normalized()
        else:
            aim_dir = Vector((0.35, -0.92, 0.08)).normalized()
        # Weapon_R local +Y points along barrel, +Z points up -> build clean world basis!
        y_ax = aim_dir
        x_ax = y_ax.cross(Vector((0, 0, 1))).normalized()
        z_ax = x_ax.cross(y_ax).normalized()
        m_want = Matrix((x_ax, y_ax, z_ax)).transposed()
        hr_m = mw @ pb_hr.matrix
        wr_rest_in_hr = arm.data.bones["mixamorig:RightHand"].matrix_local.inverted() @ arm.data.bones["Weapon_R"].matrix_local
        exp_m = hr_m @ wr_rest_in_hr
        exp_rot = exp_m.to_3x3().normalized()
        pb_wr.rotation_quaternion = (exp_rot.inverted() @ m_want).to_quaternion()

    # Legs: solidly planted in Idle_Aim, crisp military stride in Walk_Patrol & Run_Advance!
    if gait_amp < 0.01:
        rot("mixamorig:LeftUpLeg", (0, 1, 0), -2.0)
        rot("mixamorig:RightUpLeg", (0, 1, 0), 2.0)
    else:
        l_hip = stride * 26.0
        l_knee = -max(0.0, math.cos(phase)) * gait_amp * 32.0 - 6.0
        r_hip = opp * 26.0
        r_knee = -max(0.0, -math.cos(phase)) * gait_amp * 32.0 - 6.0
        rot("mixamorig:LeftUpLeg", (1, 0, 0), l_hip)
        rot("mixamorig:LeftLeg", (1, 0, 0), l_knee)
        rot("mixamorig:LeftFoot", (1, 0, 0), -l_hip * 0.35 - l_knee * 0.35)
        rot("mixamorig:RightUpLeg", (1, 0, 0), r_hip)
        rot("mixamorig:RightLeg", (1, 0, 0), r_knee)
        rot("mixamorig:RightFoot", (1, 0, 0), -r_hip * 0.35 - r_knee * 0.35)


def transfer_mixamo_anims_from_mistbound(arm: bpy.types.Object, target_height: float):
    """Purge all stray source actions (Leon Pose, etc.) and bake clean Idle_Aim / Walk_Patrol / Run_Advance loops!"""
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act, do_unlink=True)
    bpy.context.scene.render.fps = 24
    arm.animation_data_create()
    arm.animation_data.use_nla = False
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")

    created_acts = []
    for clip_name, n_frames, gait_amp, run_lean in [
        ("Idle_Aim", 48, 0.0, 0.0),
        ("Walk_Patrol", 24, 0.72, 4.0),
        ("Run_Advance", 16, 1.10, 9.0),
    ]:
        act = bpy.data.actions.new(name=clip_name)
        arm.animation_data.action = act
        step = max(2, n_frames // 8)
        frames = list(range(0, n_frames, step)) + [n_frames]
        for f in frames:
            bpy.context.scene.frame_set(f)
            phase = (f / float(n_frames)) * math.tau
            pose_desert_combat(arm, phase, gait_amp=gait_amp, run_lean=run_lean)
            for pb in arm.pose.bones:
                pb.keyframe_insert(data_path="rotation_quaternion", frame=f)
        act.use_fake_user = True
        created_acts.append((clip_name, act, 0, n_frames))

    bpy.ops.object.mode_set(mode="OBJECT")
    arm.animation_data.action = None
    for tr in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(tr)
    for nm, act, f0, f1 in created_acts:
        tr = arm.animation_data.nla_tracks.new()
        tr.name = nm
        st = tr.strips.new(nm, f0, act)
        st.action_frame_start = f0
        st.action_frame_end = f1
        tr.mute = True


def render_human_preview_and_portrait(arm: bpy.types.Object, height: float, preview_path: Path | None, portrait_path: Path | None):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0

    # Pose at Idle_Aim frame 12 for natural heroic rifle-ready look!
    idle_act = bpy.data.actions.get("Idle_Aim")
    if idle_act:
        arm.animation_data.use_nla = False
        arm.animation_data.action = idle_act
        sc.frame_set(12)
        bpy.context.view_layer.update()

    w = bpy.data.worlds.new("DesertStudioW")
    sc.world = w
    w.use_nodes = True
    wnt = w.node_tree
    wnt.nodes.clear()
    wbg = wnt.nodes.new("ShaderNodeBackground")
    wbg.inputs[0].default_value = (0.34, 0.30, 0.24, 1.0)
    wbg.inputs[1].default_value = 0.95
    wout = wnt.nodes.new("ShaderNodeOutputWorld")
    wnt.links.new(wbg.outputs[0], wout.inputs[0])

    lights = []
    for ln, en, col, rot in [
        ("Key", 2.9, (1.0, 0.94, 0.84), (36, 0, -24)),
        ("Fill", 1.25, (0.80, 0.88, 1.0), (24, 0, 128)),
        ("Rim", 1.9, (1.0, 0.86, 0.62), (30, 0, 162)),
    ]:
        ld = bpy.data.lights.new(ln, "SUN")
        ld.energy = en; ld.color = col
        lo = bpy.data.objects.new(ln, ld)
        sc.collection.objects.link(lo)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        lights.append(lo)

    cd = bpy.data.cameras.new("HCam")
    cam = bpy.data.objects.new("HCam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam

    if preview_path is not None:
        preview_path.parent.mkdir(parents=True, exist_ok=True)
        sc.render.resolution_x = 640
        sc.render.resolution_y = 800
        sc.render.film_transparent = False
        sc.render.image_settings.color_mode = "RGB"
        cd.lens = 58.0
        cam.location = Vector((0.32 * height, -2.12 * height, 0.54 * height))
        cam.rotation_euler = (Vector((0, 0, 0.50 * height)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = str(preview_path)
        bpy.ops.render.render(write_still=True)
        print(f"PREVIEW_SAVED {preview_path}")

    if portrait_path is not None:
        portrait_path.parent.mkdir(parents=True, exist_ok=True)
        sc.render.resolution_x = 1024
        sc.render.resolution_y = 1280
        sc.render.film_transparent = True
        sc.render.image_settings.file_format = "PNG"
        sc.render.image_settings.color_mode = "RGBA"
        cd.lens = 74.0
        cam.location = Vector((0.20 * height, -1.18 * height, 0.85 * height))
        cam.rotation_euler = (Vector((0, 0, 0.81 * height)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = str(portrait_path)
        bpy.ops.render.render(write_still=True)
        print(f"PORTRAIT_FG_SAVED {portrait_path}")

    arm.animation_data.action = None
    arm.animation_data.use_nla = True
    for pb in arm.pose.bones:
        pb.location = Vector((0, 0, 0))
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
    for o in lights + [cam]:
        bpy.data.objects.remove(o, do_unlink=True)


def build_human_unit(panzer_blend: Path, re_blend: Path, pharah_blend: Path, spec: dict, preview_dir: Path | None, portrait_dir: Path | None):
    bpy.ops.wm.open_mainfile(filepath=str(panzer_blend))
    tmp_dir = Path(tempfile.mkdtemp(prefix=f"v0996_{spec['id']}_"))

    # Remove WW2 helmet & stray cameras/lights
    for o in list(bpy.data.objects):
        if o.name == "helmet" or o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o, do_unlink=True)

    arm = bpy.data.objects["Armature"]
    main_obj = bpy.data.objects["main"]
    pouches_obj = bpy.data.objects.get("ammopouches")
    if arm.animation_data:
        arm.animation_data_clear()
    for pb in arm.pose.bones:
        pb.location = Vector((0, 0, 0))
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.rotation_euler = Euler((0, 0, 0))
        pb.scale = Vector((1, 1, 1))
    bpy.context.view_layer.update()

    # Normalize scale to target_height & ground feet strictly at Z=0
    mesh_objs = [o for o in (main_obj, pouches_obj) if o is not None]
    pts = [o.matrix_world @ v.co for o in mesh_objs for v in o.data.vertices]
    min_z, max_z = min(p.z for p in pts), max(p.z for p in pts)
    raw_h = max(0.01, max_z - min_z)
    sc_base = spec["target_height"] / raw_h
    cx = 0.5 * (min(p.x for p in pts) + max(p.x for p in pts))
    cy = 0.5 * (min(p.y for p in pts) + max(p.y for p in pts))
    arm.location = Vector((-cx * sc_base, -cy * sc_base, -min_z * sc_base))
    arm.scale = Vector((sc_base, sc_base, sc_base))
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for o in mesh_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.update()

    # Add Weapon_R bone identically matching v097_mistbound_assault.glb!
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    hr = eb["mixamorig:RightHand"]
    wr = eb.new("Weapon_R")
    wr.parent = hr
    wr.head = hr.head + (hr.tail - hr.head) * 0.55
    wr.tail = wr.head + Vector((0.0, 0.22 * (spec["target_height"] / 1.84), 0.0))
    wr.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()

    # Remove original lower-quality head polygons on 'main' cleanly above upper neck so unmodified AAA Leon head mounts seamlessly!
    head_cut_z = arm.data.bones["mixamorig:Head"].head_local.z - 0.015 * (spec["target_height"] / 1.84)
    bm_m = bmesh.new()
    bm_m.from_mesh(main_obj.data)
    del_faces = [f for f in bm_m.faces if f.calc_center_median().z > head_cut_z]
    bmesh.ops.delete(bm_m, geom=del_faces, context="FACES")
    bm_m.to_mesh(main_obj.data)
    bm_m.free()
    main_obj.data.validate(verbose=False)

    # Scrub WW2 insignia & grade desert PBR uniform
    u_diff, u_norm, u_ruff = grade_desert_uniform_maps(
        bpy.data.images["panzergren_low2k_diff.png"],
        bpy.data.images.get("panzergren_low2k_norm.png"),
        bpy.data.images.get("panzergren_low2k_ruff.png"),
        spec["id"],
        tmp_dir,
    )
    mat_uni = make_pbr_mat(f"Mat_{spec['id']}_Uniform", u_diff, u_norm, u_ruff, roughness=0.78, normal_scale=0.75)
    main_obj.data.materials.clear()
    main_obj.data.materials.append(mat_uni)

    if pouches_obj is not None:
        p_diff_src = bpy.data.images.get("ammopouchesgerman_diff")
        p_norm_src = bpy.data.images.get("ammopouchesgerman_norm")
        if p_diff_src:
            parr = load_image_topdown(p_diff_src, 512)[:, :, :3]
            parr[:, :, 0] = np.clip(parr[:, :, 0] * 1.12 + 0.04, 0.0, 0.55)
            parr[:, :, 1] = np.clip(parr[:, :, 1] * 0.98 + 0.02, 0.0, 0.48)
            parr[:, :, 2] = np.clip(parr[:, :, 2] * 0.72, 0.0, 0.34)
            pd = save_np_image(parr, f"Tex_Pouch_{spec['id']}", "sRGB", tmp_dir, fmt="JPEG")
            pn = save_np_image(load_image_topdown(p_norm_src, 512)[:, :, :3], f"Tex_PouchN_{spec['id']}", "Non-Color", tmp_dir, fmt="JPEG") if p_norm_src else None
            mat_pouch = make_pbr_mat(f"Mat_{spec['id']}_Pouches", pd, pn, roughness=0.68, normal_scale=0.65)
            pouches_obj.data.materials.clear()
            pouches_obj.data.materials.append(mat_pouch)

    # Append unmodified AAA male head (eyes, brows, beard/mask, hair, + aviator sunglasses for Reis!)
    head_objs = append_aaa_head_from_re(re_blend, pharah_blend, arm, spec["id"], spec["target_height"], tmp_dir)

    # Faction-specific signature gear & weapons!
    sc_u = spec["target_height"] / 1.80
    neck_pos = arm.data.bones["mixamorig:Neck"].head_local
    head_pos = arm.data.bones["mixamorig:Head"].head_local
    chest_pos = arm.data.bones["mixamorig:Spine2"].head_local

    mat_gun = make_pbr_mat(f"Mat_{spec['id']}_Gun", base_color=(0.09, 0.10, 0.12, 1.0), roughness=0.52, metallic=0.68)
    mat_gold = make_pbr_mat(f"Mat_{spec['id']}_Gold", base_color=(0.76, 0.56, 0.18, 1.0), roughness=0.30, metallic=0.86)
    mat_olive = make_pbr_mat(f"Mat_{spec['id']}_Olive", base_color=(0.20, 0.24, 0.15, 1.0), roughness=0.68, metallic=0.14)
    mat_bronze = make_pbr_mat(f"Mat_{spec['id']}_Bronze", base_color=(0.52, 0.39, 0.22, 1.0), roughness=0.38, metallic=0.76)
    crimson_tex = make_woven_cloth_texture(tmp_dir, f"Tex_CrimsonCloth_{spec['id']}", (0.28, 0.042, 0.045))
    mat_crimson = make_pbr_mat(f"Mat_{spec['id']}_Crimson", crimson_tex, roughness=0.90, metallic=0.0, double_sided=True)
    mat_wood = make_pbr_mat(f"Mat_{spec['id']}_Wood", base_color=(0.22, 0.10, 0.045, 1.0), roughness=0.44, metallic=0.06)

    extra_rigged: list[bpy.types.Object] = []
    extra_static: list[bpy.types.Object] = []

    weap = build_faction_weapon(arm, spec["id"], sc_u, mat_gun, mat_gold, mat_olive)
    extra_rigged.append(weap)

    if spec["id"] == "ahsarah_guard":
        shem_img = make_shemagh_texture(tmp_dir)
        mat_shem = make_pbr_mat("Mat_Ahsarah_Shemagh", shem_img, roughness=0.86, metallic=0.0)
        extra_rigged.append(build_keffiyeh_scarf(arm, neck_pos, sc_u, mat_shem))
    elif spec["id"] == "boss_saeed":
        gear_objs, cloak_obj = build_saeed_hood_and_gear(arm, head_pos, chest_pos, sc_u, mat_crimson, mat_bronze, mat_gun, mat_wood)
        extra_rigged.extend(gear_objs)
        extra_static.append(cloak_obj)
    elif spec["id"] == "boss_reis":
        gear_objs, gramo_obj = build_reis_armor_and_gramophone(arm, chest_pos, sc_u, mat_bronze, mat_gold, mat_wood, mat_gun)
        extra_rigged.extend(gear_objs)
        extra_static.append(gramo_obj)

    arm.name = spec["arm_name"]

    # Transfer real Adobe Mixamo Idle_Aim / Walk_Patrol / Run_Advance clips directly from v097_mistbound_assault.glb!
    transfer_mixamo_anims_from_mistbound(arm, spec["target_height"])

    # Clean up any leftover objects
    keep = set(mesh_objs) | set(head_objs) | set(extra_rigged) | set(extra_static) | {arm}
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)

    # Guarantee single UVMap on main & pouches
    for o in mesh_objs:
        uvs = o.data.uv_layers
        if len(uvs) == 0:
            uvs.new(name="UVMap")
        else:
            uvs.active_index = 0; uvs[0].name = "UVMap"
            while len(uvs) > 1:
                uvs.remove(uvs[-1])
        for p in o.data.polygons:
            p.use_smooth = True

    if preview_dir or portrait_dir:
        render_human_preview_and_portrait(
            arm,
            spec["target_height"],
            (preview_dir / f"{spec['id']}_preview.png") if preview_dir else None,
            (portrait_dir / f"{spec['portrait_id']}_fg.png") if portrait_dir else None,
        )

    bpy.ops.object.select_all(action="DESELECT")
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm

    out_glb = SLICE_DIR / spec["glb_name"]
    out_glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
        export_format="GLB",
        use_selection=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_skins=True,
        export_animations=True,
        export_nla_strips=True,
        export_bake_animation=True,
        export_def_bones=False,
    )

    # Patch alphaMode='MASK' on hair/brows/lashes cleanly inside GLB JSON (same proven rule as Chen Guide!)
    raw = out_glb.read_bytes()
    jlen = struct.unpack("<I", raw[12:16])[0]
    g = json.loads(raw[20 : 20 + jlen])
    bin_off = 20 + jlen + 8
    bad_imgs = []
    for im_d in g.get("images", []):
        bv = g["bufferViews"][im_d["bufferView"]]
        hdr = raw[bin_off + bv.get("byteOffset", 0) : bin_off + bv.get("byteOffset", 0) + 8]
        if im_d.get("mimeType") != "image/png" or hdr != b"\x89PNG\r\n\x1a\n":
            bad_imgs.append((im_d.get("name"), im_d.get("mimeType"), hdr))
    assert not bad_imgs, f"Invalid embedded PNG images in {out_glb.name}: {bad_imgs}"
    patched = False
    for m in g.get("materials", []):
        mn = m.get("name", "")
        if mn.endswith("_Hair"):
            m["alphaMode"] = "MASK"; m["alphaCutoff"] = 0.30; m["doubleSided"] = True; patched = True
        elif mn.endswith("_Brows"):
            m["alphaMode"] = "MASK"; m["alphaCutoff"] = 0.18; m["doubleSided"] = True; patched = True
        elif mn.endswith("_Lashes"):
            m["alphaMode"] = "MASK"; m["alphaCutoff"] = 0.22; m["doubleSided"] = True; patched = True
    if patched:
        new_j = json.dumps(g, separators=(",", ":")).encode("utf-8")
        new_j += b" " * ((4 - (len(new_j) % 4)) % 4)
        bin_part = raw[20 + jlen :]
        total_len = 12 + 8 + len(new_j) + len(bin_part)
        out_glb.write_bytes(struct.pack("<III", 0x46546C67, 2, total_len) + struct.pack("<II", len(new_j), 0x4E4F534A) + new_j + bin_part)
        raw = out_glb.read_bytes()
        jlen = struct.unpack("<I", raw[12:16])[0]
        g = json.loads(raw[20 : 20 + jlen])

    polys = sum(len(o.data.polygons) for o in keep if o.type == "MESH")
    tcs = sorted({k for m in g.get("meshes", []) for pr in m.get("primitives", []) for k in pr.get("attributes", {}) if k.startswith("TEXCOORD")})
    miss = sum(1 for m in g.get("meshes", []) for pr in m.get("primitives", []) if "TEXCOORD_0" not in pr.get("attributes", {}))
    anims = [a.get("name") for a in g.get("animations", [])]
    print(f"EXPORTED {out_glb.name}: {len(raw)/1048576:.2f} MiB | {polys} polys | meshes={len(g.get('meshes', []))} | bones={len(arm.data.bones)} | anims={anims} | TEXCOORDS={tcs} | missing_uv0={miss}")
    assert miss == 0 and tcs == ["TEXCOORD_0"], f"UV check failed on {out_glb.name}!"


SPECS = [
    {"id": "ahsarah_guard", "portrait_id": "ahsarah_guard", "glb_name": "v0996_ahsarah_guard.glb", "arm_name": "AhsarahGuard_Armature", "target_height": 1.80},
    {"id": "boss_saeed", "portrait_id": "saeed_fiery_owl", "glb_name": "v0996_boss_saeed.glb", "arm_name": "BossSaeed_Armature", "target_height": 2.12},
    {"id": "boss_reis", "portrait_id": "reis_warlord", "glb_name": "v0996_boss_reis.glb", "arm_name": "BossReis_Armature", "target_height": 2.56},
]


def main():
    args = parse_args()
    pdir = Path(args.preview) if args.preview else None
    fgdir = Path(args.portraits) if args.portraits else None
    only = {s.strip() for s in args.only.split(",") if s.strip()}
    for sp in SPECS:
        if only and sp["id"] not in only:
            continue
        build_human_unit(Path(args.panzer), Path(args.re_blend), Path(args.pharah_blend), sp, pdir, fgdir)


if __name__ == "__main__":
    main()
