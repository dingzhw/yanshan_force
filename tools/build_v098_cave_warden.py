"""Build v0.9.8 Portrait-Faithful Heroic Ancient Cave Acoustic Warden ('古洞循音石卫') in Blender 5.3.

Faithfully matches game/assets/portraits/cave_warden.png:
  - ~2.58m monumental heroic carved-sandstone humanoid golem sculpted directly from CC0 Blender Studio
    GEO-body_male_stylized FULL anatomy (stoic stone face, muscular trapezius/chest/abs, sculpted limbs —
    NO boxy LEGO limbs & NO giraffe neck!)
  - Chiseled faceted sandstone sculpture with Poly Haven CC0 old_sandstone_02 & cliff_side 512px PBR maps
  - Recessed glowing electric-cyan eyes, twin vertical forehead rune channels & brow glyph
  - Embedded radiant faceted diamond cyan crystal core at gd(0, 1.56, 0.34) + carved chest/ab energy veins
  - Twin massive faceted kite-tapered carved-stone forearm tower shields inlaid with glowing cyan veins
  - Articulated pivots matching cave_warden.gd:
      cave_warden (root Empty)
        ├── warden_body     (sculpted heroic stone torso, chest rune veins, diamond crystal core, belt tassets)
        ├── head_crest      (pivoted at neck gd(0, 2.02, 0.02): stoic sculpted stone face + cyan eyes & brow runes)
        ├── arm_left_pivot  (pivoted at shoulder gd(-0.62, 1.86, 0.00): sculpted arm + pauldron + faceted kite tower shield)
        ├── arm_right_pivot (pivoted at shoulder gd(+0.62, 1.86, 0.00): sculpted arm + pauldron + faceted kite tower shield)
        ├── leg_left_pivot  (pivoted at hip gd(-0.24, 1.06, 0.00): sculpted stone thigh/knee/greave/foot)
        └── leg_right_pivot (pivoted at hip gd(+0.24, 1.06, 0.00): sculpted stone thigh/knee/greave/foot)

Exports: game/assets/slice/v098_cave_warden.glb
"""
from __future__ import annotations

import math
import shutil
import subprocess
import tempfile
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
PBR_DIR = ROOT / "game" / "assets" / "pbr_v097"
BLENDER_STUDIO_BLEND = ROOT / "third_party" / "slice-v052" / "human_base_meshes_bundle.blend"
OUT_GLB = ROOT / "game" / "assets" / "slice" / "v098_cave_warden.glb"
_TMP_TEX_DIR = Path(tempfile.mkdtemp(prefix="v098_warden_tex_"))


def gd_to_bl(v: Vector) -> Vector:
    """Convert Godot (+X right, +Y up, +Z forward) -> Blender (+X right, -Y forward, +Z up)."""
    return Vector((v.x, -v.z, v.y))


def _srgb_to_lin(c: tuple[float, float, float], alpha: float = 1.0):
    return (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, alpha)


def load_pbr_image_512(filename: str, colorspace: str = "sRGB"):
    """Downscale PBR JPG to 512x512 on disk with ffmpeg BEFORE loading into Blender so pack() keeps 100% pixels!"""
    path = PBR_DIR / filename
    if not path.exists():
        return None
    load_p = path
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        out_p = _TMP_TEX_DIR / filename
        if not out_p.exists():
            res = subprocess.run(
                [ffmpeg, "-y", "-v", "error", "-i", str(path), "-vf", "scale=512:512", "-q:v", "4", str(out_p)],
                check=False,
            )
            if res.returncode == 0 and out_p.exists() and out_p.stat().st_size > 1024:
                load_p = out_p
        elif out_p.stat().st_size > 1024:
            load_p = out_p
    img = bpy.data.images.load(str(load_p), check_existing=True)
    img.colorspace_settings.name = colorspace
    try:
        img.pack()
    except Exception:
        pass
    return img


def make_rock_pbr_mat(name: str, diff_file: str, nor_file: str, rough_file: str, fallback_srgb, rough_val=0.84, metal_val=0.05, uv_scale=1.6):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = _srgb_to_lin(fallback_srgb)
    bsdf.inputs["Metallic"].default_value = metal_val
    bsdf.inputs["Roughness"].default_value = rough_val
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (uv_scale, uv_scale, uv_scale)
    nt.links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])

    diff_img = load_pbr_image_512(diff_file, "sRGB")
    if diff_img is not None:
        td = nt.nodes.new("ShaderNodeTexImage")
        td.image = diff_img
        nt.links.new(mapping.outputs["Vector"], td.inputs["Vector"])
        nt.links.new(td.outputs["Color"], bsdf.inputs["Base Color"])

    nor_img = load_pbr_image_512(nor_file, "Non-Color")
    if nor_img is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = nor_img
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 0.90
        nt.links.new(mapping.outputs["Vector"], tn.inputs["Vector"])
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])

    rough_img = load_pbr_image_512(rough_file, "Non-Color")
    if rough_img is not None:
        tr = nt.nodes.new("ShaderNodeTexImage")
        tr.image = rough_img
        nt.links.new(mapping.outputs["Vector"], tr.inputs["Vector"])
        nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])

    return mat


def make_emissive_mat(name: str, srgb, em_srgb, em_str=2.8, rough=0.14, metal=0.12):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = _srgb_to_lin(srgb)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Emission Color"].default_value = _srgb_to_lin(em_srgb)
    bsdf.inputs["Emission Strength"].default_value = em_str
    return mat


def apply_box_uv(bm: bmesh.types.BMesh, scale: float = 0.72):
    uv_layer = bm.loops.layers.uv.verify()
    bm.faces.ensure_lookup_table()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            p = loop.vert.co
            if az >= ax and az >= ay:
                u, v = p.x * scale, p.y * scale
            elif ax >= ay and ax >= az:
                u, v = p.y * scale, p.z * scale
            else:
                u, v = p.x * scale, p.z * scale
            loop[uv_layer].uv = (u, v)


def add_beveled_box_gd(bm: bmesh.types.BMesh, center_gd, size_gd, rot_deg=(0.0, 0.0, 0.0), bevel_w: float = 0.025):
    sx, sy, sz = size_gd
    rx, ry, rz = (math.radians(a) for a in rot_deg)
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sz, v.co.z * sy))
    if bevel_w > 0.002:
        bmesh.ops.bevel(
            tmp,
            geom=list(tmp.edges),
            offset=min(bevel_w, min(sx, sy, sz) * 0.28),
            segments=2,
            affect="EDGES",
            clamp_overlap=True,
        )
    m_rot = Matrix.Rotation(ry, 4, "Z") @ Matrix.Rotation(-rz, 4, "Y") @ Matrix.Rotation(rx, 4, "X")
    m_loc = Matrix.Translation(gd_to_bl(Vector(center_gd)))
    m_all = m_loc @ m_rot
    for v in tmp.verts:
        v.co = m_all @ v.co
    tmp.normal_update()
    me = bpy.data.meshes.new("_tmp_box")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def add_diamond_crystal_gd(bm: bmesh.types.BMesh, center_gd, rx: float, ry: float, rz: float):
    c = gd_to_bl(Vector(center_gd))
    tmp = bmesh.new()
    ring_n = 6
    top_v = tmp.verts.new(Vector((0.0, 0.0, ry)))
    bot_v = tmp.verts.new(Vector((0.0, 0.0, -ry)))
    mid_ring, upper_ring, lower_ring = [], [], []
    for i in range(ring_n):
        ang = (2.0 * math.pi * i) / ring_n + math.pi / 6.0
        ca, sa = math.cos(ang), math.sin(ang)
        mid_ring.append(tmp.verts.new(Vector((ca * rx, sa * rz, 0.0))))
        upper_ring.append(tmp.verts.new(Vector((ca * rx * 0.62, sa * rz * 0.68, ry * 0.52))))
        lower_ring.append(tmp.verts.new(Vector((ca * rx * 0.62, sa * rz * 0.68, -ry * 0.52))))
    for i in range(ring_n):
        ni = (i + 1) % ring_n
        tmp.faces.new((top_v, upper_ring[i], upper_ring[ni]))
        tmp.faces.new((upper_ring[i], mid_ring[i], mid_ring[ni], upper_ring[ni]))
        tmp.faces.new((mid_ring[i], lower_ring[i], lower_ring[ni], mid_ring[ni]))
        tmp.faces.new((bot_v, lower_ring[ni], lower_ring[i]))
    for v in tmp.verts:
        v.co += c
    tmp.normal_update()
    me = bpy.data.meshes.new("_tmp_diam")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def add_sculpted_kite_shield_gd(bm_stone: bmesh.types.BMesh, bm_dark: bmesh.types.BMesh, bm_cyan: bmesh.types.BMesh, sx: float):
    """Build a monumental faceted kite-diamond carved sandstone forearm tower shield matching cave_warden.png!
    Uses true tapered multi-ring hexagonal monolith geometry (NOT a flat cube!), inlaid with dark carved
    stone crevices and radiant electric-cyan geometric energy veins!
    """
    sh_c = Vector((sx * 0.80, 1.08, 0.22))
    rot_s = (6.0, sx * 18.0, sx * 4.0)
    rx_r, ry_r, rz_r = (math.radians(a) for a in rot_s)
    m_rot = Matrix.Rotation(ry_r, 4, "Z") @ Matrix.Rotation(-rz_r, 4, "Y") @ Matrix.Rotation(rx_r, 4, "X")
    m_all = Matrix.Translation(gd_to_bl(sh_c)) @ m_rot

    # 1) Sculpted 5-tier faceted sandstone kite-tower monolith!
    #    Profile rings in local (x=width, y=thickness along -Y front/+Y back, z=height)
    rings_spec = [
        (0.58, 0.14, 0.055),   # sharp upper crest point
        (0.36, 0.26, 0.115),   # upper flared shoulder
        (0.02, 0.28, 0.130),   # broadest muscular center shield face
        (-0.34, 0.23, 0.105),  # tapered lower flanks
        (-0.62, 0.11, 0.055),  # heavy chisel lower tip
    ]
    tmp = bmesh.new()
    rings_v = []
    for rz_h, rw, rd in rings_spec:
        # 6-point hexagonal beveled shield cross-section (flat back, faceted forward ridge!)
        pts_2d = [
            (-rw * 0.72, rd * 0.62),   # back-left
            (rw * 0.72, rd * 0.62),    # back-right
            (rw, 0.0),                 # right beveled edge
            (rw * 0.60, -rd * 1.05),   # front-right facet
            (-rw * 0.60, -rd * 1.05),  # front-left facet
            (-rw, 0.0),                # left beveled edge
        ]
        rings_v.append([tmp.verts.new(Vector((px, py, rz_h))) for px, py in pts_2d])
    for ri in range(len(rings_v) - 1):
        r0, r1 = rings_v[ri], rings_v[ri + 1]
        for k in range(6):
            nk = (k + 1) % 6
            tmp.faces.new((r0[k], r0[nk], r1[nk], r1[k]))
    tmp.faces.new(rings_v[0][::-1])
    tmp.faces.new(rings_v[-1])
    for v in tmp.verts:
        v.co = m_all @ v.co
    tmp.normal_update()
    me = bpy.data.meshes.new("_tmp_kite")
    tmp.to_mesh(me)
    tmp.free()
    bm_stone.from_mesh(me)
    bpy.data.meshes.remove(me)

    # 2) Dark carved basalt inner rune recessed plate & forearm lock straps
    add_beveled_box_gd(bm_dark, (sh_c.x, sh_c.y + 0.02, sh_c.z + 0.105), (0.24, 0.86, 0.055), rot_s, bevel_w=0.018)
    for by_off in (0.24, -0.04, -0.28):
        add_beveled_box_gd(bm_dark, (sh_c.x - sx * 0.06, sh_c.y + by_off, sh_c.z - 0.07), (0.30, 0.09, 0.16), rot_s, bevel_w=0.014)

    # 3) Sleek recessed electric-cyan rune circuit etched down the shield face (slim crisp glowing veins!)
    add_beveled_box_gd(bm_cyan, (sh_c.x, sh_c.y + 0.02, sh_c.z + 0.132), (0.028, 0.82, 0.024), rot_s, bevel_w=0.005)
    for cy_off, ang_z in ((0.26, 36.0), (0.26, -36.0), (-0.02, 28.0), (-0.02, -28.0), (-0.28, -36.0), (-0.28, 36.0)):
        bx_d = 1.0 if ang_z > 0 else -1.0
        add_beveled_box_gd(
            bm_cyan,
            (sh_c.x + bx_d * 0.09, sh_c.y + cy_off, sh_c.z + 0.128),
            (0.16, 0.024, 0.022),
            (rot_s[0], rot_s[1], rot_s[2] + ang_z),
            bevel_w=0.004,
        )
    add_diamond_crystal_gd(bm_cyan, (sh_c.x, sh_c.y + 0.04, sh_c.z + 0.145), 0.064, 0.105, 0.036)


def slice_body_region(src_obj, mw, xform_fn, keep_fn, dec_ratio: float, mat_stone, name: str) -> bpy.types.Object:
    """Slice an anatomical region from CC0 GEO-body_male_stylized, chisel-decimate to faceted stone sculpture, and box-UV."""
    bm = bmesh.new()
    bm.from_mesh(src_obj.data)
    bm.verts.ensure_lookup_table()
    # Transform all vertices first so region bounds are exact in target 2.58m golem space!
    for v in bm.verts:
        v.co = xform_fn(mw @ v.co)
    bm.faces.ensure_lookup_table()
    del_faces = [f for f in bm.faces if not keep_fn(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    # Remove any loose verts
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.normal_update()
    apply_box_uv(bm, scale=0.80)
    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    if len(obj.data.polygons) > 120:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        dec = obj.modifiers.new("StoneChisel", "DECIMATE")
        dec.ratio = dec_ratio
        bpy.ops.object.modifier_apply(modifier=dec.name)
    # Re-apply box UVs after decimate so rock grain is crisp everywhere
    bm2 = bmesh.new()
    bm2.from_mesh(obj.data)
    bm2.normal_update()
    apply_box_uv(bm2, scale=0.82)
    bm2.to_mesh(obj.data)
    bm2.free()
    for p in obj.data.polygons:
        p.use_smooth = False  # chiseled carved stone sculpture facets!
    obj.data.materials.clear()
    obj.data.materials.append(mat_stone)
    return obj


def part_obj(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, smooth: bool = False) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    apply_box_uv(bm, scale=0.78)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = smooth
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def join_under_pivot(root_empty, part_name: str, pivot_gd: tuple[float, float, float], mesh_parts: list[bpy.types.Object]) -> bpy.types.Object:
    non_empty = [o for o in mesh_parts if o is not None and len(o.data.vertices) > 0]
    for o in mesh_parts:
        if o is not None and o not in non_empty:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in non_empty:
        o.select_set(True)
    bpy.context.view_layer.objects.active = non_empty[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = part_name
    joined.data.name = part_name + "_Mesh"
    piv_bl = gd_to_bl(Vector(pivot_gd))
    for v in joined.data.vertices:
        v.co -= piv_bl
    joined.data.update()
    joined.location = piv_bl
    joined.parent = root_empty
    return joined


def build_v098_cave_warden():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    m_stone = make_rock_pbr_mat(
        "Mat_WardenSandstone",
        "old_sandstone_02_diff.jpg",
        "old_sandstone_02_nor_gl.jpg",
        "old_sandstone_02_rough.jpg",
        fallback_srgb=(0.56, 0.52, 0.46),
        rough_val=0.84,
        metal_val=0.04,
        uv_scale=1.5,
    )
    m_dark = make_rock_pbr_mat(
        "Mat_WardenBasalt",
        "cliff_side_diff.jpg",
        "cliff_side_nor_gl.jpg",
        "cliff_side_rough.jpg",
        fallback_srgb=(0.24, 0.25, 0.27),
        rough_val=0.78,
        metal_val=0.14,
        uv_scale=1.8,
    )
    m_cyan = make_emissive_mat(
        "Mat_WardenCyanRune",
        srgb=(0.12, 0.88, 1.0),
        em_srgb=(0.10, 0.86, 1.0),
        em_str=2.8,
        rough=0.14,
        metal=0.12,
    )
    m_crystal = make_emissive_mat(
        "Mat_WardenDiamondCore",
        srgb=(0.45, 0.96, 1.0),
        em_srgb=(0.22, 0.92, 1.0),
        em_str=4.2,
        rough=0.08,
        metal=0.18,
    )

    # Load FULL heroic sculpted male anatomy from Blender Studio CC0 bundle!
    with bpy.data.libraries.load(str(BLENDER_STUDIO_BLEND), link=False) as (data_from, data_to):
        data_to.objects = [n for n in ("GEO-body_male_stylized", "GEO-body_male_stylized.eye.L", "GEO-body_male_stylized.eye.R") if n in data_from.objects]

    loaded = {}
    for o in data_to.objects:
        if o is not None:
            bpy.context.collection.objects.link(o)
            loaded[o.name] = o

    src_body = loaded["GEO-body_male_stylized"]
    eye_l = loaded["GEO-body_male_stylized.eye.L"]
    eye_r = loaded["GEO-body_male_stylized.eye.R"]
    bpy.context.view_layer.update()

    mw_b = src_body.matrix_world.copy()
    body_pts = [mw_b @ v.co for v in src_body.data.vertices]
    eye_l_pts = [eye_l.matrix_world @ v.co for v in eye_l.data.vertices]
    eye_r_pts = [eye_r.matrix_world @ v.co for v in eye_r.data.vertices]
    mid_x = 0.5 * (sum(p.x for p in eye_l_pts) / len(eye_l_pts) + sum(p.x for p in eye_r_pts) / len(eye_r_pts))
    min_z_src = min(p.z for p in body_pts)
    max_z_src = max(p.z for p in body_pts)
    mid_y_src = 0.5 * (min(p.y for p in body_pts) + max(p.y for p in body_pts))
    src_h = max_z_src - min_z_src
    target_h = 2.58
    s_all = target_h / src_h

    def xform_body(wp: Vector) -> Vector:
        """Transform CC0 male body into 2.58m heroic broad-shouldered carved stone colossus (feet at z=0, facing -Y Blender == +Z Godot!)."""
        lx = (wp.x - mid_x) * s_all
        ly = (wp.y - mid_y_src) * s_all
        lz = (wp.z - min_z_src) * s_all
        # Broaden heroic shoulders, chest & muscular build smoothly while keeping natural waist & seated head!
        if 1.15 < lz < 2.08:
            # Heroic V-taper chest/shoulders expansion (+28% width, +22% depth across upper chest!)
            chest_w = math.sin(max(0.0, min(1.0, (lz - 1.15) / 0.93)) * math.pi)
            lx *= (1.0 + 0.28 * chest_w)
            ly *= (1.0 + 0.22 * chest_w)
        elif lz <= 1.15:
            # Athletic heroic sturdy stone pillar legs (+14% thickness)
            lx *= 1.14
            ly *= 1.16
        else:
            # Head slightly heroic broad & seated cleanly into muscular trapezius neck (NO giraffe neck!)
            lx *= 1.06
            ly *= 1.06
            lz -= 0.035 * min(1.0, (lz - 2.08) / 0.16)
        return Vector((lx, ly, lz))

    # Measure transformed eye centers for exact glowing cyan eye & forehead rune placement
    el_x = [xform_body(p) for p in eye_l_pts]
    er_x = [xform_body(p) for p in eye_r_pts]
    el_c = sum(el_x, Vector((0, 0, 0))) / len(el_x)
    er_c = sum(er_x, Vector((0, 0, 0))) / len(er_x)
    eye_z_gd = 0.5 * (el_c.z + er_c.z)
    eye_front_gd = -min(min(p.y for p in el_x), min(p.y for p in er_x))

    # Find exact anatomical bounds of transformed body (note: Blender T-pose/A-pose arms extend along ±X!)
    root_empty = bpy.data.objects.new("cave_warden", None)
    root_empty.empty_display_type = "PLAIN_AXES"
    bpy.context.collection.objects.link(root_empty)

    # ------------------------------------------------------------------
    # 1) warden_body — Full Sculpted Heroic Stone Torso + Engraved Collar/Belt/Tassets + Cyan Veins + Diamond Core!
    # ------------------------------------------------------------------
    torso_sculpt = slice_body_region(
        src_body, mw_b, xform_body,
        lambda c: (c.z >= 1.02 and c.z <= 2.12 and abs(c.x) <= 0.44),
        dec_ratio=0.18, mat_stone=m_stone, name="WardenTorsoSculpt",
    )
    bm_st, bm_dk, bm_cy, bm_cr = (bmesh.new() for _ in range(4))

    # Sculpted stone collarbone/trapezius armor collar bridging shoulders & neck cleanly (eliminates any neck gap!)
    for sx in (-1.0, 1.0):
        add_beveled_box_gd(bm_st, (sx * 0.30, 1.98, 0.04), (0.40, 0.16, 0.34), (0.0, sx * 12.0, -sx * 16.0), bevel_w=0.036)
        add_beveled_box_gd(bm_cy, (sx * 0.30, 1.95, 0.21), (0.28, 0.026, 0.024), (0.0, sx * 12.0, -sx * 16.0), bevel_w=0.004)
        # Carved sandstone pectoral armor bevel plates hugging the sculpted chest
        add_beveled_box_gd(bm_st, (sx * 0.27, 1.72, 0.15), (0.34, 0.28, 0.22), (-4.0, sx * 16.0, -sx * 6.0), bevel_w=0.042)
        # Sleek contoured stone hip tasset plates hugging the heroic thighs cleanly
        add_beveled_box_gd(bm_st, (sx * 0.25, 0.99, 0.03), (0.14, 0.26, 0.26), (0.0, sx * 10.0, sx * 10.0), bevel_w=0.026)

    # Dark basalt warrior belt + central carved stone loin guard with slim cyan rune line
    add_beveled_box_gd(bm_dk, (0.0, 1.08, 0.03), (0.60, 0.12, 0.42), (0.0, 0.0, 0.0), bevel_w=0.022)
    add_beveled_box_gd(bm_st, (0.0, 0.94, 0.21), (0.22, 0.30, 0.09), (-6.0, 0.0, 0.0), bevel_w=0.022)
    add_beveled_box_gd(bm_cy, (0.0, 0.96, 0.26), (0.026, 0.18, 0.018), (-6.0, 0.0, 0.0), bevel_w=0.004)

    # Sleek recessed dark channels + vibrant cyan energy veins radiating across chest & abs from diamond core!
    add_beveled_box_gd(bm_dk, (0.0, 1.28, 0.22), (0.068, 0.32, 0.036), (0.0, 0.0, 0.0), bevel_w=0.008)
    add_beveled_box_gd(bm_cy, (0.0, 1.28, 0.236), (0.026, 0.30, 0.020), (0.0, 0.0, 0.0), bevel_w=0.004)
    for ay in (1.35, 1.21):
        add_beveled_box_gd(bm_dk, (0.0, ay, 0.21), (0.44, 0.052, 0.034), (0.0, 0.0, 0.0), bevel_w=0.006)
        add_beveled_box_gd(bm_cy, (0.0, ay, 0.228), (0.40, 0.022, 0.018), (0.0, 0.0, 0.0), bevel_w=0.004)
    # Rear spine cyan power conduit
    add_beveled_box_gd(bm_cy, (0.0, 1.62, -0.26), (0.038, 0.56, 0.032), (0.0, 0.0, 0.0), bevel_w=0.006)

    # Recessed dark basalt diamond bezel + radiant faceted diamond cyan crystal right at gd(0, 1.56, 0.33)!
    add_beveled_box_gd(bm_dk, (0.0, 1.56, 0.25), (0.30, 0.38, 0.14), (0.0, 0.0, 45.0), bevel_w=0.028)
    add_diamond_crystal_gd(bm_cr, (0.0, 1.56, 0.33), 0.145, 0.215, 0.115)

    join_under_pivot(root_empty, "warden_body", (0.0, 0.0, 0.0), [
        torso_sculpt,
        part_obj("WardenBodyStoneAdd", bm_st, m_stone, smooth=False),
        part_obj("WardenBodyBasalt", bm_dk, m_dark, smooth=False),
        part_obj("WardenBodyCyan", bm_cy, m_cyan, smooth=False),
        part_obj("WardenBodyCrystal", bm_cr, m_crystal, smooth=False),
    ])

    # ------------------------------------------------------------------
    # 2) head_crest (pivoted at neck gd(0.0, 2.02, 0.02)) — Sculpted stoic stone head + glowing cyan eyes & forehead runes!
    # ------------------------------------------------------------------
    head_sculpt = slice_body_region(
        src_body, mw_b, xform_body,
        lambda c: (c.z >= 2.04 and abs(c.x) <= 0.24),
        dec_ratio=0.22, mat_stone=m_stone, name="WardenHeadSculpt",
    )
    bm_hs, bm_hd, bm_hc = (bmesh.new() for _ in range(3))
    # Subtle sculpted angular brow crown & temple cheek plates (NO boxy helmet!)
    add_beveled_box_gd(bm_hs, (0.0, eye_z_gd + 0.17, eye_front_gd - 0.13), (0.28, 0.09, 0.30), (-8.0, 0.0, 0.0), bevel_w=0.028)
    for sx in (-1.0, 1.0):
        ex_gd = el_c.x if sx > 0 else er_c.x
        # Recessed dark eye sockets + intense sleek glowing cyan eyes!
        add_beveled_box_gd(bm_hd, (ex_gd, eye_z_gd, eye_front_gd + 0.004), (0.064, 0.030, 0.026), (0.0, sx * 12.0, 0.0), bevel_w=0.005)
        add_beveled_box_gd(bm_hc, (ex_gd, eye_z_gd, eye_front_gd + 0.016), (0.048, 0.017, 0.018), (0.0, sx * 12.0, 0.0), bevel_w=0.004)
        # Sleek twin vertical forehead glowing cyan rune channels (portrait signature!)
        add_beveled_box_gd(bm_hc, (sx * 0.048, eye_z_gd + 0.108, eye_front_gd + 0.010), (0.013, 0.115, 0.016), (-12.0, sx * 10.0, 0.0), bevel_w=0.003)
    add_diamond_crystal_gd(bm_hc, (0.0, eye_z_gd + 0.098, eye_front_gd + 0.020), 0.022, 0.040, 0.015)

    join_under_pivot(root_empty, "head_crest", (0.0, 2.02, 0.02), [
        head_sculpt,
        part_obj("HeadCrown", bm_hs, m_stone, smooth=False),
        part_obj("HeadDark", bm_hd, m_dark, smooth=False),
        part_obj("HeadCyan", bm_hc, m_cyan, smooth=False),
    ])

    # ------------------------------------------------------------------
    # 3) arm_left_pivot (-X) & arm_right_pivot (+X) — Sculpted faceted shoulders/arms + Twin Kite Stone Tower Shields!
    # ------------------------------------------------------------------
    for arm_name, sx in (("arm_left_pivot", -1.0), ("arm_right_pivot", 1.0)):
        as_st, as_dk, as_cy = (bmesh.new() for _ in range(3))
        piv = (sx * 0.62, 1.86, 0.00)

        # Layered chamfered hexagonal stone shoulder pauldron (broad heroic deltoid silhouette matching portrait!)
        add_beveled_box_gd(as_st, (sx * 0.66, 1.90, 0.02), (0.38, 0.32, 0.38), (0.0, sx * 12.0, -sx * 20.0), bevel_w=0.058)
        add_beveled_box_gd(as_st, (sx * 0.74, 1.72, 0.04), (0.30, 0.24, 0.32), (0.0, sx * 10.0, -sx * 14.0), bevel_w=0.045)
        add_beveled_box_gd(as_cy, (sx * 0.68, 1.88, 0.21), (0.24, 0.028, 0.024), (0.0, sx * 12.0, -sx * 20.0), bevel_w=0.004)
        # Muscular carved stone bicep & dark basalt elbow/forearm core
        add_beveled_box_gd(as_st, (sx * 0.73, 1.50, 0.05), (0.24, 0.34, 0.26), (0.0, sx * 8.0, -sx * 8.0), bevel_w=0.048)
        add_beveled_box_gd(as_dk, (sx * 0.75, 1.24, 0.09), (0.20, 0.36, 0.22), (8.0, 0.0, 0.0), bevel_w=0.036)
        # Heavy chiseled stone fist + glowing cyan knuckles
        add_beveled_box_gd(as_st, (sx * 0.76, 0.76, 0.16), (0.22, 0.24, 0.24), (8.0, 0.0, 0.0), bevel_w=0.042)
        add_beveled_box_gd(as_cy, (sx * 0.76, 0.70, 0.27), (0.15, 0.040, 0.028), (8.0, 0.0, 0.0), bevel_w=0.006)

        # Monumental sculpted kite-tapered carved sandstone forearm tower shield!
        add_sculpted_kite_shield_gd(as_st, as_dk, as_cy, sx)

        join_under_pivot(root_empty, arm_name, piv, [
            part_obj(arm_name + "_Stone", as_st, m_stone, smooth=False),
            part_obj(arm_name + "_Basalt", as_dk, m_dark, smooth=False),
            part_obj(arm_name + "_Cyan", as_cy, m_cyan, smooth=False),
        ])

    # ------------------------------------------------------------------
    # 4) leg_left_pivot (-X) & leg_right_pivot (+X) — Real Sculpted Athletic Stone Legs from GEO-body_male_stylized!
    # ------------------------------------------------------------------
    for leg_name, sx in (("leg_left_pivot", -1.0), ("leg_right_pivot", 1.0)):
        piv = (sx * 0.24, 1.06, 0.00)
        leg_sculpt = slice_body_region(
            src_body, mw_b, xform_body,
            lambda c, s=sx: (c.z <= 1.06 and (c.x * s >= -0.02)),
            dec_ratio=0.20, mat_stone=m_stone, name=f"Warden_{leg_name}_Sculpt",
        )
        ls_st, ls_dk, ls_cy = (bmesh.new() for _ in range(3))
        # Sculpted angular stone knee plate + sleek glowing cyan knee/shin rune accents!
        add_beveled_box_gd(ls_st, (sx * 0.21, 0.62, 0.15), (0.21, 0.20, 0.14), (0.0, sx * 8.0, 0.0), bevel_w=0.036)
        add_beveled_box_gd(ls_cy, (sx * 0.21, 0.62, 0.22), (0.11, 0.024, 0.018), (0.0, sx * 8.0, 0.0), bevel_w=0.004)
        add_beveled_box_gd(ls_cy, (sx * 0.21, 0.36, 0.15), (0.024, 0.22, 0.018), (-4.0, sx * 8.0, 0.0), bevel_w=0.004)
        # Sturdy dark basalt boot sole grounding feet cleanly at y = 0.0
        add_beveled_box_gd(ls_dk, (sx * 0.22, 0.045, 0.06), (0.26, 0.09, 0.40), (0.0, sx * 6.0, 0.0), bevel_w=0.018)

        join_under_pivot(root_empty, leg_name, piv, [
            leg_sculpt,
            part_obj(leg_name + "_StoneAdd", ls_st, m_stone, smooth=False),
            part_obj(leg_name + "_Basalt", ls_dk, m_dark, smooth=False),
            part_obj(leg_name + "_Cyan", ls_cy, m_cyan, smooth=False),
        ])

    for o in loaded.values():
        bpy.data.objects.remove(o, do_unlink=True)

    bpy.ops.object.select_all(action="SELECT")
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    kb = OUT_GLB.stat().st_size / 1024.0
    polys = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    print(f"EXPORTED_WARDEN {OUT_GLB.name} ({kb:.0f} KB | {polys} polys)")


if __name__ == "__main__":
    build_v098_cave_warden()
