"""Build realistic CC0 first-person tactical arms & gloved hands (fp_arms.glb) in Blender 4.5.

Source assets (all CC0 1.0 Public Domain):
- third_party/slice-v052/human_base_meshes_bundle.blend (Blender Studio 'GEO-body_male_realistic')
- third_party/slice-v052/Fabric030_1K-JPG_*.jpg (ambientCG woven cloth PBR)
- third_party/slice-v052/Leather026_1K-JPG_*.jpg (ambientCG fine leather PBR)
- game/assets/slice/rifle.glb (reference mannequin only; NOT exported inside fp_arms.glb)

Run headless:
  blender.exe --background --factory-startup --python tools/build_fp_arms.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "third_party" / "slice-v052"
DEST = ROOT / "game" / "assets" / "slice"
DEST.mkdir(parents=True, exist_ok=True)

ARM_SCALE = 0.94

# FaceSet IDs authored in Blender Studio's GEO-body_male_realistic
FS_LEFT = {
    "upper": {21},
    "forearm": {12},
    "hand": {9},
    "thumb_01": {80}, "thumb_02": {81}, "thumb_03": {82}, "thumb_nail": {83},
    "index_01": {76}, "index_02": {77}, "index_03": {78}, "index_nail": {79},
    "middle_01": {72}, "middle_02": {73}, "middle_03": {74}, "middle_nail": {75},
    "ring_01": {68}, "ring_02": {69}, "ring_03": {70}, "ring_nail": {71},
    "little_01": {64}, "little_02": {65}, "little_03": {66}, "little_nail": {67},
}
FS_RIGHT = {
    "upper": {20},
    "forearm": {11},
    "hand": {10},
    "thumb_01": {84}, "thumb_02": {85}, "thumb_03": {86}, "thumb_nail": {87},
    "index_01": {88}, "index_02": {89}, "index_03": {90}, "index_nail": {91},
    "middle_01": {92}, "middle_02": {93}, "middle_03": {94}, "middle_nail": {95},
    "ring_01": {96}, "ring_02": {97}, "ring_03": {98}, "ring_nail": {99},
    "little_01": {100}, "little_02": {101}, "little_03": {102}, "little_nail": {103},
}


def gd(x: float, y: float, z: float) -> Vector:
    """Convert Godot WeaponView Y-up (-Z forward) coordinates to Blender Z-up (+Y forward)."""
    return Vector((x, -z, y))


def bl_to_gd(v: Vector) -> list[float]:
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


# ---------------------------------------------------------------------------
# 1. PBR Texture Generation (512x512 JPGs into game/assets/slice/)
# ---------------------------------------------------------------------------

def _load_resized_pixels(path: Path, size: int = 512, non_color: bool = False) -> np.ndarray:
    img = bpy.data.images.load(str(path), check_existing=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    img.scale(size, size)
    arr = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    bpy.data.images.remove(img)
    return arr.reshape((size, size, 4))


def _srgb_to_lin(rgb: np.ndarray | tuple[float, ...]) -> np.ndarray:
    arr = np.asarray(rgb, dtype=np.float32)
    return np.power(np.clip(arr, 0.0, 1.0), 2.2)


def _save_jpg(arr_srgb_rgba: np.ndarray, out_path: Path, non_color: bool = False) -> Path:
    h, w, _ = arr_srgb_rgba.shape
    img = bpy.data.images.new("tmp_out", width=w, height=h, alpha=False)
    out = np.clip(arr_srgb_rgba, 0.0, 1.0).copy()
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    else:
        # Blender stores float image buffers in scene-linear space and applies sRGB transfer on JPEG save
        out[..., :3] = _srgb_to_lin(out[..., :3])
    img.pixels.foreach_set(out.ravel())
    img.filepath_raw = str(out_path)
    img.file_format = "JPEG"
    img.save()
    bpy.data.images.remove(img)
    return out_path


def prepare_pbr_textures() -> dict[str, Path]:
    size = 512
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)

    fab_col = _load_resized_pixels(SRC / "Fabric030_1K-JPG_Color.jpg", size, non_color=False)
    fab_ao = _load_resized_pixels(SRC / "Fabric030_1K-JPG_AmbientOcclusion.jpg", size, non_color=True)
    fab_nrm = _load_resized_pixels(SRC / "Fabric030_1K-JPG_NormalGL.jpg", size, non_color=True)
    fab_rgh = _load_resized_pixels(SRC / "Fabric030_1K-JPG_Roughness.jpg", size, non_color=True)

    lum = (0.299 * fab_col[..., 0] + 0.587 * fab_col[..., 1] + 0.114 * fab_col[..., 2])
    lum_norm = np.clip((lum - lum.mean()) * 2.1 + 1.0, 0.76, 1.24) * np.clip(fab_ao[..., 0], 0.72, 1.0)

    # Subtle ripstop grid reinforcement threads every 16 px
    rip_x = np.where((xx.astype(int) % 16) < 2, 0.91, 1.0)
    rip_y = np.where((yy.astype(int) % 16) < 2, 0.91, 1.0)
    rip = (rip_x * rip_y).astype(np.float32)

    # Standard Military Ranger Olive-Drab sleeve albedo (sRGB target)
    olive = np.ones((size, size, 4), dtype=np.float32)
    base_olive = np.array([0.335, 0.385, 0.285], dtype=np.float32)
    olive[..., :3] = base_olive[None, None, :] * (lum_norm * rip)[..., None]

    # Woodland Camo ("forest_skin") sleeve albedo (sRGB target)
    camo = np.ones((size, size, 4), dtype=np.float32)
    n1 = (
        np.sin(xx * 2 * math.pi / 256.0 + 0.7) * np.cos(yy * 2 * math.pi / 256.0 - 0.4)
        + 0.55 * np.sin((xx + yy) * 2 * math.pi / 128.0)
        + 0.30 * np.cos((xx * 2.0 - yy) * 2 * math.pi / 64.0)
    )
    n2 = (
        np.cos(xx * 2 * math.pi / 256.0 - 1.1) * np.sin(yy * 2 * math.pi / 128.0 + 0.8)
        + 0.45 * np.sin((xx - 2.0 * yy) * 2 * math.pi / 128.0)
    )
    c_base = np.array([0.275, 0.395, 0.285], dtype=np.float32)
    c_pine = np.array([0.165, 0.265, 0.205], dtype=np.float32)
    c_bark = np.array([0.345, 0.295, 0.215], dtype=np.float32)
    c_moss = np.array([0.385, 0.465, 0.305], dtype=np.float32)
    rgb_camo = np.tile(c_base, (size, size, 1))
    rgb_camo = np.where((n1 > 0.32)[..., None], c_pine, rgb_camo)
    rgb_camo = np.where((n2 > 0.42)[..., None], c_bark, rgb_camo)
    rgb_camo = np.where(((n1 < -0.45) & (n2 < 0.1))[..., None], c_moss, rgb_camo)
    camo[..., :3] = rgb_camo * (lum_norm * rip)[..., None]

    # Leather / Microfiber glove maps (matte charcoal tactical suede sRGB target)
    lea_col = _load_resized_pixels(SRC / "Leather026_1K-JPG_Color.jpg", size, non_color=False)
    lea_nrm = _load_resized_pixels(SRC / "Leather026_1K-JPG_NormalGL.jpg", size, non_color=True)
    lea_rgh = _load_resized_pixels(SRC / "Leather026_1K-JPG_Roughness.jpg", size, non_color=True)
    lea_lum = (0.3 * lea_col[..., 0] + 0.59 * lea_col[..., 1] + 0.11 * lea_col[..., 2])
    lea_mod = np.clip((lea_lum - lea_lum.mean()) * 1.8 + 1.0, 0.80, 1.20)

    glove_alb = np.ones((size, size, 4), dtype=np.float32)
    glove_alb[..., :3] = np.array([0.195, 0.208, 0.220], dtype=np.float32)[None, None, :] * lea_mod[..., None]
    glove_rgh = np.clip(0.72 + (lea_rgh - lea_rgh.mean()) * 0.45, 0.62, 0.90)

    # Natural warm human hand skin albedo (sRGB target) + fine skin pore normal
    skin_alb = np.ones((size, size, 4), dtype=np.float32)
    pore = (
        0.015 * np.sin(xx * 2 * math.pi / 32.0) * np.cos(yy * 2 * math.pi / 32.0)
        + 0.010 * (lea_mod - 1.0)
    )
    warmth = 0.018 * np.sin(yy * 2 * math.pi / 256.0)
    skin_alb[..., 0] = np.clip(0.815 + pore + warmth, 0.0, 1.0)
    skin_alb[..., 1] = np.clip(0.642 + pore * 0.8 - warmth * 0.22, 0.0, 1.0)
    skin_alb[..., 2] = np.clip(0.525 + pore * 0.7 - warmth * 0.35, 0.0, 1.0)

    skin_nrm = np.ones((size, size, 4), dtype=np.float32)
    skin_nrm[..., 0] = np.clip(0.5 + (lea_nrm[..., 0] - 0.5) * 0.28, 0.0, 1.0)
    skin_nrm[..., 1] = np.clip(0.5 + (lea_nrm[..., 1] - 0.5) * 0.28, 0.0, 1.0)
    skin_nrm[..., 2] = 1.0

    paths = {
        "sleeve_olive": _save_jpg(olive, DEST / "arm_sleeve_olive.jpg"),
        "sleeve_forest": _save_jpg(camo, DEST / "arm_sleeve_forest.jpg"),
        "sleeve_normal": _save_jpg(fab_nrm, DEST / "arm_sleeve_normal.jpg", non_color=True),
        "sleeve_rough": _save_jpg(np.clip(fab_rgh * 1.05, 0.55, 0.96), DEST / "arm_sleeve_rough.jpg", non_color=True),
        "glove_albedo": _save_jpg(glove_alb, DEST / "arm_glove_albedo.jpg"),
        "glove_normal": _save_jpg(lea_nrm, DEST / "arm_glove_normal.jpg", non_color=True),
        "glove_rough": _save_jpg(glove_rgh, DEST / "arm_glove_rough.jpg", non_color=True),
        "skin_albedo": _save_jpg(skin_alb, DEST / "arm_skin_albedo.jpg"),
        "skin_normal": _save_jpg(skin_nrm, DEST / "arm_skin_normal.jpg", non_color=True),
    }
    return paths


def _lin_rgba(r: float, g: float, b: float, a: float = 1.0) -> tuple[float, float, float, float]:
    return (r ** 2.2, g ** 2.2, b ** 2.2, a)


def make_pbr_mat(
    name: str,
    base_color: tuple[float, float, float, float],
    roughness: float,
    metallic: float = 0.0,
    albedo_path: Path | None = None,
    normal_path: Path | None = None,
    normal_strength: float = 0.8,
    rough_path: Path | None = None,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic

    if albedo_path and albedo_path.exists():
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(albedo_path), check_existing=True)
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    if rough_path and rough_path.exists():
        rtex = nodes.new("ShaderNodeTexImage")
        rtex.image = bpy.data.images.load(str(rough_path), check_existing=True)
        rtex.image.colorspace_settings.name = "Non-Color"
        links.new(rtex.outputs["Color"], bsdf.inputs["Roughness"])

    if normal_path and normal_path.exists():
        ntex = nodes.new("ShaderNodeTexImage")
        ntex.image = bpy.data.images.load(str(normal_path), check_existing=True)
        ntex.image.colorspace_settings.name = "Non-Color"
        nmap = nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = normal_strength
        links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    if emission is not None and emission_strength > 0.0:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = emission
            bsdf.inputs["Emission Strength"].default_value = emission_strength

    return mat


# ---------------------------------------------------------------------------
# 2. Extract Sculpted Human Arms & Build Layered Tactical Gear
# ---------------------------------------------------------------------------

def extract_sculpted_arms() -> tuple[bpy.types.Object, list[int]]:
    """Open Blender Studio bundle, evaluate GEO-body_male_realistic at Multires Level 1, and isolate both arms."""
    src_blend = SRC / "human_base_meshes_bundle.blend"
    bpy.ops.wm.open_mainfile(filepath=str(src_blend), load_ui=False, use_scripts=False)

    src_obj = bpy.data.objects["GEO-body_male_realistic"]
    for mod in list(src_obj.modifiers):
        if mod.type == "MULTIRES":
            mod.levels = 1
            mod.sculpt_levels = 1
            mod.render_levels = 1
        else:
            src_obj.modifiers.remove(mod)

    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = src_obj.evaluated_get(depsgraph)
    raw_mesh = bpy.data.meshes.new_from_object(eval_obj)

    keep_fs = set()
    for d in (FS_LEFT, FS_RIGHT):
        for s in d.values():
            keep_fs |= s

    fs_data = raw_mesh.attributes[".sculpt_face_set"].data
    poly_fs = [fs_data[p.index].value for p in raw_mesh.polygons]

    # Build clean mesh containing only the left & right arms (trimmed cleanly outside shoulder armpit |x| >= 0.165)
    bm = bmesh.new()
    bm.from_mesh(raw_mesh)
    bm.faces.ensure_lookup_table()

    face_fs_layer = bm.faces.layers.int.get(".sculpt_face_set") or bm.faces.layers.int.new(".sculpt_face_set")
    for f, fval in zip(bm.faces, poly_fs):
        f[face_fs_layer] = fval

    to_delete = []
    for f in bm.faces:
        fval = f[face_fs_layer]
        cx = sum(v.co.x for v in f.verts) / len(f.verts)
        if fval not in keep_fs or abs(cx) < 0.168:
            to_delete.append(f)
    bmesh.ops.delete(bm, geom=to_delete, context="FACES")

    # Scale uniformly by ARM_SCALE around origin (0, 0, 0)
    for v in bm.verts:
        v.co *= ARM_SCALE

    bm.normal_update()
    kept_fs = [f[face_fs_layer] for f in bm.faces]
    bpy.data.meshes.remove(raw_mesh)

    # Start a clean empty scene BEFORE creating bpy.data.meshes (since read_factory_settings clears bpy.data!)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    clean_mesh = bpy.data.meshes.new("TacticalArmsMesh")
    bm.to_mesh(clean_mesh)
    bm.free()
    arm_obj = bpy.data.objects.new("TacticalArms", clean_mesh)
    bpy.context.collection.objects.link(arm_obj)
    return arm_obj, kept_fs


def compute_joints_and_normals(mesh: bpy.types.Mesh, poly_fs: list[int]) -> dict:
    """Compute exact joint centroids and dorsal normals directly from sculpted FaceSet boundaries."""
    vert_fs: list[set[int]] = [set() for _ in range(len(mesh.vertices))]
    fs_normals: dict[int, Vector] = {}
    fs_verts: dict[int, list[int]] = {}

    for pi, p in enumerate(mesh.polygons):
        fval = poly_fs[pi]
        fs_normals[fval] = fs_normals.get(fval, Vector((0.0, 0.0, 0.0))) + p.normal.copy()
        vlist = fs_verts.setdefault(fval, [])
        for vi in p.vertices:
            vert_fs[vi].add(fval)
            vlist.append(vi)

    for k in fs_normals:
        if fs_normals[k].length > 1e-6:
            fs_normals[k].normalize()

    def boundary(fs_a: set[int], fs_b: set[int]) -> Vector:
        pts = [mesh.vertices[i].co for i, s in enumerate(vert_fs) if (s & fs_a) and (s & fs_b)]
        if not pts:
            raise RuntimeError(f"Missing FaceSet boundary between {fs_a} and {fs_b}")
        return sum(pts, Vector((0.0, 0.0, 0.0))) / len(pts)

    def region_center(fs_set: set[int]) -> Vector:
        pts = [mesh.vertices[i].co for i, s in enumerate(vert_fs) if s & fs_set]
        return sum(pts, Vector((0.0, 0.0, 0.0))) / len(pts)

    def side_joints(fs_map: dict[str, set[int]], sign_x: float) -> dict:
        # Shoulder head is upper-medial rim of upper arm
        upper_pts = [mesh.vertices[i].co for i, s in enumerate(vert_fs) if s & fs_map["upper"]]
        rim_pts = sorted(upper_pts, key=lambda p: sign_x * p.x)[:24]
        shoulder = sum(rim_pts, Vector((0.0, 0.0, 0.0))) / len(rim_pts)
        elbow = boundary(fs_map["upper"], fs_map["forearm"])
        wrist = boundary(fs_map["forearm"], fs_map["hand"])
        forearm_mid = elbow.lerp(wrist, 0.54)

        j = {
            "shoulder": shoulder,
            "elbow": elbow,
            "forearm_mid": forearm_mid,
            "wrist": wrist,
            "hand_dorsal": fs_normals[next(iter(fs_map["index_nail"]))].copy(),
        }
        # Hand dorsal normal from dorsal side of palm (+X on L, -X on R)
        palm_dorsal = Vector((0.0, 0.0, 0.0))
        for pi, p in enumerate(mesh.polygons):
            if poly_fs[pi] in fs_map["hand"] and p.normal.x * sign_x > 0.35:
                palm_dorsal += p.normal
        j["palm_dorsal"] = palm_dorsal.normalized()

        for fname in ("thumb", "index", "middle", "ring", "little"):
            b1 = boundary(fs_map["hand"], fs_map[f"{fname}_01"])
            b2 = boundary(fs_map[f"{fname}_01"], fs_map[f"{fname}_02"])
            b3 = boundary(fs_map[f"{fname}_02"], fs_map[f"{fname}_03"])
            tip_dir = (b3 - b2).normalized()
            distal_pts = [mesh.vertices[i].co for i, s in enumerate(vert_fs) if s & (fs_map[f"{fname}_03"] | fs_map[f"{fname}_nail"])]
            tip = max(distal_pts, key=lambda p: (p - b3).dot(tip_dir))
            nail_id = next(iter(fs_map[f"{fname}_nail"]))
            dorsal = fs_normals[nail_id].copy()
            j[f"{fname}_01"] = b1
            j[f"{fname}_02"] = b2
            j[f"{fname}_03"] = b3
            j[f"{fname}_tip"] = tip
            j[f"{fname}_dorsal"] = dorsal
        return j

    return {
        "L": side_joints(FS_LEFT, +1.0),
        "R": side_joints(FS_RIGHT, -1.0),
        "vert_fs": vert_fs,
    }


def sculpt_tactical_garments_and_materials(
    arm_obj: bpy.types.Object,
    poly_fs: list[int],
    joints: dict,
    tex_paths: dict[str, Path],
) -> None:
    """Displace sleeve folds, wrist cuffs, half-finger tactical gloves & carbon knuckle armor over the sculpted anatomy."""
    mesh = arm_obj.data
    vert_fs: list[set[int]] = joints["vert_fs"]

    # Create material slots:
    # 0: Mat_Sleeve, 1: Mat_Cuff, 2: Mat_Glove, 3: Mat_LeatherPalm, 4: Mat_KnuckleArmor,
    # 5: Mat_Skin, 6: Mat_Nail, 7: Mat_WatchCase, 8: Mat_WatchScreen
    mats = [
        make_pbr_mat(
            "Mat_Sleeve",
            _lin_rgba(0.26, 0.30, 0.23),
            roughness=0.86,
            metallic=0.02,
            albedo_path=tex_paths["sleeve_olive"],
            normal_path=tex_paths["sleeve_normal"],
            normal_strength=0.95,
            rough_path=tex_paths["sleeve_rough"],
        ),
        make_pbr_mat(
            "Mat_Cuff",
            _lin_rgba(0.13, 0.145, 0.155),
            roughness=0.76,
            metallic=0.06,
            normal_path=tex_paths["sleeve_normal"],
            normal_strength=0.55,
        ),
        make_pbr_mat(
            "Mat_Glove",
            _lin_rgba(0.175, 0.188, 0.198),
            roughness=0.68,
            metallic=0.05,
            albedo_path=tex_paths["glove_albedo"],
            normal_path=tex_paths["glove_normal"],
            normal_strength=0.85,
            rough_path=tex_paths["glove_rough"],
        ),
        make_pbr_mat(
            "Mat_LeatherPalm",
            _lin_rgba(0.145, 0.155, 0.165),
            roughness=0.76,
            metallic=0.04,
            albedo_path=tex_paths["glove_albedo"],
            normal_path=tex_paths["glove_normal"],
            normal_strength=0.95,
            rough_path=tex_paths["glove_rough"],
        ),
        make_pbr_mat(
            "Mat_KnuckleArmor",
            _lin_rgba(0.22, 0.245, 0.265),
            roughness=0.36,
            metallic=0.48,
        ),
        make_pbr_mat(
            "Mat_Skin",
            _lin_rgba(0.815, 0.642, 0.525),
            roughness=0.72,
            metallic=0.0,
            albedo_path=tex_paths["skin_albedo"],
            normal_path=tex_paths["skin_normal"],
            normal_strength=0.35,
        ),
        make_pbr_mat(
            "Mat_Nail",
            _lin_rgba(0.845, 0.695, 0.610),
            roughness=0.42,
            metallic=0.01,
        ),
        make_pbr_mat(
            "Mat_WatchCase",
            _lin_rgba(0.19, 0.215, 0.235),
            roughness=0.32,
            metallic=0.75,
        ),
        make_pbr_mat(
            "Mat_WatchScreen",
            _lin_rgba(0.14, 0.68, 0.56),
            roughness=0.22,
            metallic=0.05,
            emission=_lin_rgba(0.22, 0.85, 0.70),
            emission_strength=0.35,
        ),
    ]
    mesh.materials.clear()
    for m in mats:
        mesh.materials.append(m)

    sleeve_fs = FS_LEFT["upper"] | FS_LEFT["forearm"] | FS_RIGHT["upper"] | FS_RIGHT["forearm"]
    glove_palm_fs = FS_LEFT["hand"] | FS_RIGHT["hand"]
    glove_prox_fs = (
        FS_LEFT["thumb_01"] | FS_LEFT["index_01"] | FS_LEFT["middle_01"] | FS_LEFT["ring_01"] | FS_LEFT["little_01"]
        | FS_RIGHT["thumb_01"] | FS_RIGHT["index_01"] | FS_RIGHT["middle_01"] | FS_RIGHT["ring_01"] | FS_RIGHT["little_01"]
    )
    bare_skin_fs = (
        FS_LEFT["thumb_02"] | FS_LEFT["thumb_03"]
        | FS_LEFT["index_02"] | FS_LEFT["index_03"]
        | FS_LEFT["middle_02"] | FS_LEFT["middle_03"]
        | FS_LEFT["ring_02"] | FS_LEFT["ring_03"]
        | FS_LEFT["little_02"] | FS_LEFT["little_03"]
        | FS_RIGHT["thumb_02"] | FS_RIGHT["thumb_03"]
        | FS_RIGHT["index_02"] | FS_RIGHT["index_03"]
        | FS_RIGHT["middle_02"] | FS_RIGHT["middle_03"]
        | FS_RIGHT["ring_02"] | FS_RIGHT["ring_03"]
        | FS_RIGHT["little_02"] | FS_RIGHT["little_03"]
    )
    nail_fs = (
        FS_LEFT["thumb_nail"] | FS_LEFT["index_nail"] | FS_LEFT["middle_nail"] | FS_LEFT["ring_nail"] | FS_LEFT["little_nail"]
        | FS_RIGHT["thumb_nail"] | FS_RIGHT["index_nail"] | FS_RIGHT["middle_nail"] | FS_RIGHT["ring_nail"] | FS_RIGHT["little_nail"]
    )

    # Precompute smoothed vertex normals so garment inflation never splits edges
    v_normals = [v.normal.copy() for v in mesh.vertices]
    adj: list[set[int]] = [set() for _ in range(len(mesh.vertices))]
    for e in mesh.edges:
        a, b = e.vertices[0], e.vertices[1]
        adj[a].add(b)
        adj[b].add(a)
    for _ in range(2):
        next_n = []
        for i, nb in enumerate(adj):
            acc = v_normals[i] * 2.0
            for j in nb:
                acc += v_normals[j]
            next_n.append(acc.normalized() if acc.length > 1e-6 else v_normals[i])
        v_normals = next_n

    # Compute axial arm parameter t_arm in [0..1] (0=shoulder, 0.5=elbow, 1.0=wrist) for every vertex
    v_t_arm = [0.0] * len(mesh.vertices)
    v_knuckle_armor = [0.0] * len(mesh.vertices)

    for vi, v in enumerate(mesh.vertices):
        side = "L" if v.co.x >= 0.0 else "R"
        sign_x = 1.0 if side == "L" else -1.0
        j = joints[side]
        s_pt, e_pt, w_pt = j["shoulder"], j["elbow"], j["wrist"]

        # Piecewise projection onto shoulder->elbow and elbow->wrist segments
        se = e_pt - s_pt
        ew = w_pt - e_pt
        t_se = max(0.0, min(1.0, (v.co - s_pt).dot(se) / max(se.length_squared, 1e-6)))
        t_ew = max(0.0, min(1.0, (v.co - e_pt).dot(ew) / max(ew.length_squared, 1e-6)))
        d_se = (v.co - (s_pt + se * t_se)).length
        d_ew = (v.co - (e_pt + ew * t_ew)).length
        t_arm = (0.5 * t_se) if (d_se < d_ew and t_ew < 0.08) else (0.5 + 0.5 * t_ew)
        v_t_arm[vi] = t_arm

        vfs = vert_fs[vi]
        nrm = v_normals[vi]

        # Check if vertex sits on the dorsal MCP knuckle band for carbon knuckle guard
        mcp_centers = [j["index_01"], j["middle_01"], j["ring_01"], j["little_01"]]
        min_mcp_dist = min((v.co - mc).length for mc in mcp_centers)
        dorsal_dot = nrm.dot(j["palm_dorsal"])
        if (vfs & glove_palm_fs) and not (vfs & bare_skin_fs) and min_mcp_dist < 0.021 and dorsal_dot > 0.42:
            falloff = max(0.0, 1.0 - (min_mcp_dist / 0.021) ** 2)
            v_knuckle_armor[vi] = falloff

        # Displace vertices by layer
        if vfs & sleeve_fs:
            # Loose BDU ripstop sleeve with natural cloth folds at elbow & wrist blousing
            radial_vec = v.co - (s_pt.lerp(e_pt, t_se) if t_arm < 0.5 else e_pt.lerp(w_pt, t_ew))
            ang = math.atan2(radial_vec.y, radial_vec.x * sign_x)

            # Base BDU cloth clearance (tapers snugly into wrist cuff)
            cuff_taper = 1.0 - 0.52 * max(0.0, (t_arm - 0.85) / 0.15)
            base_lift = 0.0078 * cuff_taper

            # Gravity drape on lower/posterior forearm
            drape = 0.0022 * max(0.0, math.sin(ang + 0.6)) * math.sin(min(1.0, t_arm) * math.pi)

            # Elbow compression folds (stronger on anterior/flexor side y < 0)
            elbow_env = math.exp(-((t_arm - 0.50) / 0.11) ** 2)
            flexor_bias = 0.55 + 0.45 * max(0.0, -math.sin(ang))
            elbow_folds = 0.0028 * elbow_env * flexor_bias * (
                0.65 * math.sin(t_arm * 92.0 + 1.4 * math.sin(ang * 2.0))
                + 0.35 * math.cos(t_arm * 145.0 - ang)
            )

            # Wrist blousing gathers right above cuff (t_arm in [0.74, 0.91])
            wrist_env = math.exp(-((t_arm - 0.84) / 0.065) ** 2)
            wrist_folds = 0.0024 * wrist_env * (
                0.7 * math.sin(t_arm * 125.0 + 1.2 * math.cos(ang))
                + 0.3 * math.sin(ang * 3.0 + t_arm * 60.0)
            )

            # Raised tailored cuff hem band (t_arm in [0.91, 0.99])
            cuff_band = 0.0018 if (0.905 <= t_arm <= 0.992) else 0.0
            # Boundary seam step between sleeve cuff and hand glove
            if vfs & glove_palm_fs:
                total = 0.0032
            else:
                total = base_lift + drape + elbow_folds + wrist_folds + cuff_band
            v.co += nrm * total

        elif (vfs & (glove_palm_fs | glove_prox_fs)) and not (vfs & bare_skin_fs):
            # Tactical half-finger glove + carbon knuckle armor
            lift = 0.0016 + 0.0026 * v_knuckle_armor[vi]
            v.co += nrm * lift

        elif (vfs & glove_prox_fs) and (vfs & bare_skin_fs):
            # Crisp half-finger glove hem lip stepping down onto bare intermediate phalanx skin
            v.co += nrm * 0.0012

    # Topological quad-ring cuff selection: exact 3 edge-loop rings on forearm adjacent to hand FaceSet -> zero sawtooth!
    wrist_ring_verts = {vi for vi, s in enumerate(vert_fs) if (s & sleeve_fs) and (s & glove_palm_fs)}
    cuff_ring_verts = set(wrist_ring_verts)
    frontier = set(wrist_ring_verts)
    for _ in range(3):
        nxt = set()
        for vi in frontier:
            for nb in adj[vi]:
                if (vert_fs[nb] & sleeve_fs) and nb not in cuff_ring_verts:
                    nxt.add(nb)
        cuff_ring_verts |= nxt
        frontier = nxt

    # Assign per-polygon materials and clean tiled UVs so cloth & leather weaves render crisply
    uv_layer = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    uv_data = uv_layer.data

    for pi, p in enumerate(mesh.polygons):
        fval = poly_fs[pi]
        side = "L" if mesh.vertices[p.vertices[0]].co.x >= 0.0 else "R"
        j = joints[side]
        avg_ka = sum(v_knuckle_armor[vi] for vi in p.vertices) / len(p.vertices)
        is_cuff_poly = all(vi in cuff_ring_verts for vi in p.vertices)

        if fval in nail_fs:
            p.material_index = 6  # Mat_Nail
            uv_scale = 2.0
        elif fval in bare_skin_fs:
            p.material_index = 5  # Mat_Skin
            uv_scale = 3.0
        elif fval in sleeve_fs:
            p.material_index = 1 if is_cuff_poly else 0  # Mat_Cuff or Mat_Sleeve
            uv_scale = 7.5
        elif fval in (glove_palm_fs | glove_prox_fs):
            if avg_ka > 0.36:
                p.material_index = 4  # Mat_KnuckleArmor
                uv_scale = 4.0
            else:
                p.material_index = 2  # Mat_Glove (seamless microfiber/leather without side stair-steps)
                uv_scale = 5.5
        else:
            p.material_index = 5
            uv_scale = 3.0

        for li in p.loop_indices:
            uv = uv_data[li].uv
            uv_data[li].uv = (uv.x * uv_scale, uv.y * uv_scale)

    for p in mesh.polygons:
        p.use_smooth = True
    mesh.update()


def add_left_wrist_tactical_watch(arm_obj: bpy.types.Object, joints: dict) -> list[int]:
    """Append a 3D tactical telemetry watch + nylon strap onto the left wrist in rest pose; return added vertex indices."""
    jL = joints["L"]
    w_pt = jL["wrist"]
    e_pt = jL["elbow"]
    # Place watch ~2.4 cm proximal to wrist crease along forearm
    axis_y = (w_pt - e_pt).normalized()  # distal along forearm
    # Watch dial faces radial-dorsal (between thumb -Y and dorsal +X on Left arm) so player sees it clearly in 1P
    dial_up = (jL["palm_dorsal"] * 0.58 + Vector((0.0, -1.0, 0.0)) * 0.82).normalized()
    axis_x = axis_y.cross(dial_up).normalized()
    dial_up = axis_x.cross(axis_y).normalized()
    center = w_pt - axis_y * 0.024
    watch_xf = Matrix((
        (axis_x.x, axis_y.x, dial_up.x, center.x),
        (axis_x.y, axis_y.y, dial_up.y, center.y),
        (axis_x.z, axis_y.z, dial_up.z, center.z),
        (0.0, 0.0, 0.0, 1.0),
    ))

    bm = bmesh.new()
    bm.from_mesh(arm_obj.data)
    start_vert_count = len(bm.verts)

    # 1) Nylon NATO wrist strap ring around wrist oval (rx = 0.033, rz = 0.029, width = 0.018)
    segs = 20
    ring_a, ring_b = [], []
    for k in range(segs):
        th = 2.0 * math.pi * k / segs
        px = math.cos(th) * 0.031
        pz = math.sin(th) * 0.034
        va = bm.verts.new(watch_xf @ Vector((px, -0.009, pz)))
        vb = bm.verts.new(watch_xf @ Vector((px, +0.009, pz)))
        ring_a.append(va)
        ring_b.append(vb)
    for k in range(segs):
        kn = (k + 1) % segs
        f = bm.faces.new((ring_a[k], ring_a[kn], ring_b[kn], ring_b[k]))
        f.material_index = 1  # Mat_Cuff
        f.smooth = True

    def add_box(local_center: Vector, half_ext: Vector, mat_idx: int):
        res = bmesh.ops.create_cube(bm, size=2.0)
        for v in res["verts"]:
            p = Vector((
                v.co.x * half_ext.x + local_center.x,
                v.co.y * half_ext.y + local_center.y,
                v.co.z * half_ext.z + local_center.z,
            ))
            v.co = watch_xf @ p
        for f in {f for v in res["verts"] for f in v.link_faces}:
            f.material_index = mat_idx
            f.smooth = False

    # 2) Beveled titanium watch case + top bezel + side pushers + glowing telemetry screen
    add_box(Vector((0.0, 0.0, 0.0345)), Vector((0.0145, 0.0165, 0.0045)), 7)  # Mat_WatchCase
    add_box(Vector((0.0, 0.0, 0.0385)), Vector((0.0125, 0.0140, 0.0018)), 7)  # Bezel
    add_box(Vector((0.0155, 0.005, 0.035)), Vector((0.0018, 0.0025, 0.0022)), 7)  # Pusher 1
    add_box(Vector((0.0155, -0.005, 0.035)), Vector((0.0018, 0.0025, 0.0022)), 7)  # Pusher 2
    add_box(Vector((0.0, 0.0, 0.0402)), Vector((0.0098, 0.0112, 0.0006)), 8)  # Mat_WatchScreen

    bm.verts.ensure_lookup_table()
    added_indices = list(range(start_vert_count, len(bm.verts)))
    bm.normal_update()
    bm.to_mesh(arm_obj.data)
    bm.free()
    arm_obj.data.update()
    return added_indices


# ---------------------------------------------------------------------------
# 3. Build Anatomical Armature & Zero-Bleed Parent-Child Skinning
# ---------------------------------------------------------------------------

def create_armature_and_weights(
    arm_obj: bpy.types.Object,
    joints: dict,
    watch_verts: list[int],
) -> bpy.types.Object:
    arm_data = bpy.data.armatures.new("FPArmsRig")
    rig_obj = bpy.data.objects.new("FPArmsRig", arm_data)
    bpy.context.collection.objects.link(rig_obj)
    bpy.context.view_layer.objects.active = rig_obj
    bpy.ops.object.mode_set(mode="EDIT")

    eb = arm_data.edit_bones
    root = eb.new("root")
    root.head = Vector((0.0, 0.0, 0.0))
    root.tail = Vector((0.0, 0.08, 0.0))

    for side in ("L", "R"):
        j = joints[side]
        suf = f".{side}"

        b_up = eb.new("upperarm" + suf)
        b_up.head = j["shoulder"]
        b_up.tail = j["elbow"]
        b_up.parent = root
        b_up.use_connect = False
        b_up.align_roll(j["palm_dorsal"])

        b_fa = eb.new("forearm" + suf)
        b_fa.head = j["elbow"]
        b_fa.tail = j["forearm_mid"]
        b_fa.parent = b_up
        b_fa.use_connect = True
        b_fa.align_roll(j["palm_dorsal"])

        b_ft = eb.new("forearm_twist" + suf)
        b_ft.head = j["forearm_mid"]
        b_ft.tail = j["wrist"]
        b_ft.parent = b_fa
        b_ft.use_connect = True
        b_ft.align_roll(j["palm_dorsal"])

        b_hd = eb.new("hand" + suf)
        b_hd.head = j["wrist"]
        b_hd.tail = j["middle_01"]
        b_hd.parent = b_ft
        b_hd.use_connect = True
        b_hd.align_roll(j["palm_dorsal"])

        for fname in ("thumb", "index", "middle", "ring", "little"):
            dorsal = j[f"{fname}_dorsal"]
            b1 = eb.new(f"{fname}_01{suf}")
            b1.head = j[f"{fname}_01"]
            b1.tail = j[f"{fname}_02"]
            b1.parent = b_hd
            b1.use_connect = False
            b1.align_roll(dorsal)

            b2 = eb.new(f"{fname}_02{suf}")
            b2.head = j[f"{fname}_02"]
            b2.tail = j[f"{fname}_03"]
            b2.parent = b1
            b2.use_connect = True
            b2.align_roll(dorsal)

            b3 = eb.new(f"{fname}_03{suf}")
            b3.head = j[f"{fname}_03"]
            b3.tail = j[f"{fname}_tip"]
            b3.parent = b2
            b3.use_connect = True
            b3.align_roll(dorsal)

    bpy.ops.object.mode_set(mode="OBJECT")

    # Build parent-child bone adjacency so weight smoothing NEVER bleeds across neighbor fingers
    bone_names = [b.name for b in arm_data.bones if b.name != "root"]
    bone_idx = {name: idx for idx, name in enumerate(bone_names)}
    allowed_pair: set[tuple[int, int]] = set()
    for b in arm_data.bones:
        if b.name not in bone_idx:
            continue
        bi = bone_idx[b.name]
        allowed_pair.add((bi, bi))
        if b.parent and b.parent.name in bone_idx:
            pi = bone_idx[b.parent.name]
            allowed_pair.add((bi, pi))
            allowed_pair.add((pi, bi))

    mesh = arm_obj.data
    n_verts = len(mesh.vertices)
    n_bones = len(bone_names)
    weights = np.zeros((n_verts, n_bones), dtype=np.float32)

    vert_fs: list[set[int]] = joints["vert_fs"]
    watch_set = set(watch_verts)

    for vi in range(n_verts):
        if vi in watch_set:
            weights[vi, bone_idx["forearm_twist.L"]] = 1.0
            continue
        v = mesh.vertices[vi]
        side = "L" if v.co.x >= 0.0 else "R"
        suf = f".{side}"
        fs_map = FS_LEFT if side == "L" else FS_RIGHT
        j = joints[side]
        vfs = vert_fs[vi]

        # Accumulate initial weights from incident FaceSets
        assigned = False
        if vfs & fs_map["upper"]:
            weights[vi, bone_idx["upperarm" + suf]] += 1.0
            assigned = True
        if vfs & fs_map["forearm"]:
            ew = j["wrist"] - j["elbow"]
            t_fa = max(0.0, min(1.0, (v.co - j["elbow"]).dot(ew) / max(ew.length_squared, 1e-6)))
            w_twist = max(0.0, min(1.0, (t_fa - 0.35) / 0.38))
            weights[vi, bone_idx["forearm" + suf]] += (1.0 - w_twist)
            weights[vi, bone_idx["forearm_twist" + suf]] += w_twist
            assigned = True
        if vfs & fs_map["hand"]:
            # Blend thenar eminence slightly with thumb_01 for realistic palm-thumb muscle deformation
            d_thumb = (v.co - j["thumb_01"]).length
            th_blend = 0.28 * max(0.0, 1.0 - d_thumb / 0.032)
            weights[vi, bone_idx["hand" + suf]] += (1.0 - th_blend)
            weights[vi, bone_idx["thumb_01" + suf]] += th_blend
            assigned = True
        for fname in ("thumb", "index", "middle", "ring", "little"):
            if vfs & fs_map[f"{fname}_01"]:
                weights[vi, bone_idx[f"{fname}_01{suf}"]] += 1.0
                assigned = True
            if vfs & fs_map[f"{fname}_02"]:
                weights[vi, bone_idx[f"{fname}_02{suf}"]] += 1.0
                assigned = True
            if vfs & (fs_map[f"{fname}_03"] | fs_map[f"{fname}_nail"]):
                weights[vi, bone_idx[f"{fname}_03{suf}"]] += 1.0
                assigned = True
        if not assigned:
            weights[vi, bone_idx["hand" + suf]] = 1.0

    # Normalize initial weights
    row_sums = weights.sum(axis=1, keepdims=True)
    weights /= np.maximum(row_sums, 1e-6)

    # 3 iterations of parent-child-restricted Laplacian weight smoothing
    adj: list[list[int]] = [[] for _ in range(n_verts)]
    for e in mesh.edges:
        a, b = e.vertices[0], e.vertices[1]
        if a not in watch_set and b not in watch_set:
            adj[a].append(b)
            adj[b].append(a)

    for _ in range(3):
        smoothed = weights.copy()
        for vi in range(n_verts):
            if vi in watch_set or not adj[vi]:
                continue
            dom_bone = int(np.argmax(weights[vi]))
            acc = weights[vi] * 2.0
            for nb in adj[vi]:
                for bi in np.flatnonzero(weights[nb] > 1e-4):
                    if (dom_bone, int(bi)) in allowed_pair:
                        acc[bi] += weights[nb, bi] * 0.55
            s = acc.sum()
            if s > 1e-6:
                smoothed[vi] = acc / s
        weights = smoothed

    # Keep top 4 influences per vertex (glTF standard skinning limit) and renormalize
    for name in bone_names:
        arm_obj.vertex_groups.new(name=name)

    for vi in range(n_verts):
        row = weights[vi]
        top4 = np.argsort(row)[-4:]
        vals = row[top4]
        vals = vals[vals > 1e-3]
        top_ids = top4[-len(vals):]
        vals /= vals.sum()
        for bi, w in zip(top_ids, vals):
            arm_obj.vertex_groups[bone_names[int(bi)]].add([vi], float(w), "REPLACE")

    arm_obj.parent = rig_obj
    mod = arm_obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = rig_obj
    mod.use_bone_envelopes = False
    mod.use_vertex_groups = True
    return rig_obj


# ---------------------------------------------------------------------------
# 4. Exact Analytical Chain Posing & NLA Action Authoring
# ---------------------------------------------------------------------------

def _basis_from_yz(y_dir: Vector, z_hint: Vector) -> Matrix:
    y = y_dir.normalized()
    x = y.cross(z_hint)
    if x.length < 1e-5:
        x = y.cross(Vector((0.0, 0.0, 1.0)))
    x.normalize()
    z = x.cross(y).normalized()
    return Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z)))


def pose_arm_chain(
    rig_obj: bpy.types.Object,
    side: str,
    wrist_bl: Vector,
    mcp_target_bl: Vector,
    hand_dorsal_bl: Vector,
    elbow_dir_bl: Vector,
    shoulder_dir_bl: Vector,
    finger_curls_deg: dict[str, tuple[float, float, float]],
    thumb_abduct_deg: tuple[float, float] = (0.0, 0.0),
    index_abduct_deg: tuple[float, float] = (0.0, 0.0),
) -> dict[str, list[float]]:
    """Analytically pose upperarm -> forearm -> forearm_twist -> hand + 5 fingers without stretching any bone."""
    suf = f".{side}"
    pb = rig_obj.pose.bones
    bones = rig_obj.data.bones

    L_up = bones["upperarm" + suf].length
    L_fa = bones["forearm" + suf].length
    L_ft = bones["forearm_twist" + suf].length
    L_fore_total = L_fa + L_ft

    # Exact unstretched elbow & shoulder positions in Armature object space
    fore_back_dir = (elbow_dir_bl - wrist_bl).normalized()
    elbow_pos = wrist_bl + fore_back_dir * L_fore_total
    fore_mid_pos = elbow_pos.lerp(wrist_bl, L_fa / L_fore_total)
    up_back_dir = (shoulder_dir_bl - elbow_pos).normalized()
    shoulder_pos = elbow_pos + up_back_dir * L_up

    hand_y = (mcp_target_bl - wrist_bl).normalized()
    hand_rot = _basis_from_yz(hand_y, hand_dorsal_bl)
    hand_z = Vector((hand_rot[0][2], hand_rot[1][2], hand_rot[2][2]))

    # Natural radius/ulna twist distribution: forearm carries 40% of hand dorsal roll, forearm_twist carries 75%
    elbow_bend_normal = up_back_dir.cross(-fore_back_dir)
    if elbow_bend_normal.length < 1e-4:
        elbow_bend_normal = hand_z
    elbow_bend_normal.normalize()
    if elbow_bend_normal.dot(hand_z) < 0.0:
        elbow_bend_normal = -elbow_bend_normal

    up_y = (elbow_pos - shoulder_pos).normalized()
    fa_y = (fore_mid_pos - elbow_pos).normalized()
    ft_y = (wrist_bl - fore_mid_pos).normalized()

    up_rot = _basis_from_yz(up_y, elbow_bend_normal)
    fa_rot = _basis_from_yz(fa_y, elbow_bend_normal.lerp(hand_z, 0.35).normalized())
    ft_rot = _basis_from_yz(ft_y, elbow_bend_normal.lerp(hand_z, 0.78).normalized())

    def set_world_mat(bname: str, head_pos: Vector, rot3: Matrix):
        pbone = pb[bname]
        mat4 = rot3.to_4x4()
        mat4.translation = head_pos
        pbone.matrix = mat4
        bpy.context.view_layer.update()

    set_world_mat("upperarm" + suf, shoulder_pos, up_rot)
    set_world_mat("forearm" + suf, elbow_pos, fa_rot)
    set_world_mat("forearm_twist" + suf, fore_mid_pos, ft_rot)
    set_world_mat("hand" + suf, wrist_bl, hand_rot)

    # Finger curls in local anatomical hinge coordinates (negative X = palmar flexion on both L and R!)
    for fname in ("thumb", "index", "middle", "ring", "little"):
        c1, c2, c3 = finger_curls_deg[fname]
        for idx, ang_deg in ((1, c1), (2, c2), (3, c3)):
            fbone = pb[f"{fname}_0{idx}{suf}"]
            fbone.rotation_mode = "QUATERNION"
            rx = -math.radians(ang_deg)
            ry = 0.0
            rz = 0.0
            if fname == "thumb" and idx == 1:
                rz = math.radians(thumb_abduct_deg[0])
                ry = math.radians(thumb_abduct_deg[1])
            elif fname == "index" and idx == 1:
                rz = math.radians(index_abduct_deg[0])
                ry = math.radians(index_abduct_deg[1])
            fbone.rotation_quaternion = Euler((rx, ry, rz), "XYZ").to_quaternion()

    bpy.context.view_layer.update()
    return {
        f"shoulder_{side}_gd": bl_to_gd(shoulder_pos),
        f"elbow_{side}_gd": bl_to_gd(elbow_pos),
        f"wrist_{side}_gd": bl_to_gd(wrist_bl),
        f"mcp_{side}_gd": bl_to_gd(pb["hand" + suf].tail),
        f"index_tip_{side}_gd": bl_to_gd(pb["index_03" + suf].tail),
        f"middle_tip_{side}_gd": bl_to_gd(pb["middle_03" + suf].tail),
        f"thumb_tip_{side}_gd": bl_to_gd(pb["thumb_03" + suf].tail),
    }


def apply_pose_preset(rig_obj: bpy.types.Object, preset: str) -> dict:
    # Reset all bones first
    for pbone in rig_obj.pose.bones:
        pbone.location = (0.0, 0.0, 0.0)
        pbone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pbone.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()

    if preset == "pose_knife_idle":
        # Natural human sabre grip: knuckles rake forward-down (-Y,-Z) so top of fist & blade aim forward-up-left (-X,+Y,-Z)
        r_info = pose_arm_chain(
            rig_obj,
            "R",
            wrist_bl=gd(+0.025, +0.005, +0.165),
            mcp_target_bl=gd(-0.008, -0.035, +0.082),
            hand_dorsal_bl=gd(+0.76, +0.42, +0.32),
            elbow_dir_bl=gd(+0.195, -0.155, +0.325),
            shoulder_dir_bl=gd(+0.285, -0.075, +0.545),
            finger_curls_deg={
                "thumb": (28.0, 38.0, 26.0),
                "index": (68.0, 86.0, 62.0),
                "middle": (72.0, 90.0, 66.0),
                "ring": (74.0, 92.0, 68.0),
                "little": (76.0, 94.0, 68.0),
            },
            thumb_abduct_deg=(-12.0, +14.0),
            index_abduct_deg=(+4.0, 0.0),
        )
        # Left hand kept low in natural non-obstructing tactical balance position
        l_info = pose_arm_chain(
            rig_obj,
            "L",
            wrist_bl=gd(-0.365, -0.135, +0.185),
            mcp_target_bl=gd(-0.315, -0.105, +0.105),
            hand_dorsal_bl=gd(-0.72, +0.48, +0.30),
            elbow_dir_bl=gd(-0.465, -0.265, +0.345),
            shoulder_dir_bl=gd(-0.545, -0.205, +0.535),
            finger_curls_deg={
                "thumb": (16.0, 22.0, 14.0),
                "index": (34.0, 44.0, 30.0),
                "middle": (38.0, 48.0, 32.0),
                "ring": (42.0, 52.0, 36.0),
                "little": (46.0, 56.0, 38.0),
            },
            thumb_abduct_deg=(+14.0, -10.0),
        )
        return {**r_info, **l_info}
    elif preset == "pose_knife_slash_a":
        # Fast forehand diagonal cleave from upper-right to lower-left across screen center
        r_info = pose_arm_chain(
            rig_obj,
            "R",
            wrist_bl=gd(-0.185, +0.095, +0.055),
            mcp_target_bl=gd(-0.260, +0.055, -0.015),
            hand_dorsal_bl=gd(+0.22, +0.90, -0.32),
            elbow_dir_bl=gd(+0.035, -0.075, +0.235),
            shoulder_dir_bl=gd(+0.205, -0.055, +0.465),
            finger_curls_deg={
                "thumb": (30.0, 40.0, 28.0),
                "index": (70.0, 88.0, 64.0),
                "middle": (74.0, 92.0, 68.0),
                "ring": (76.0, 94.0, 70.0),
                "little": (78.0, 96.0, 70.0),
            },
            thumb_abduct_deg=(-12.0, +14.0),
            index_abduct_deg=(+4.0, 0.0),
        )
        l_info = pose_arm_chain(
            rig_obj,
            "L",
            wrist_bl=gd(-0.415, -0.175, +0.205),
            mcp_target_bl=gd(-0.365, -0.145, +0.125),
            hand_dorsal_bl=gd(-0.72, +0.48, +0.30),
            elbow_dir_bl=gd(-0.505, -0.295, +0.365),
            shoulder_dir_bl=gd(-0.565, -0.215, +0.545),
            finger_curls_deg={
                "thumb": (16.0, 22.0, 14.0),
                "index": (38.0, 48.0, 32.0),
                "middle": (42.0, 52.0, 36.0),
                "ring": (46.0, 56.0, 38.0),
                "little": (50.0, 60.0, 42.0),
            },
            thumb_abduct_deg=(+14.0, -10.0),
        )
        return {**r_info, **l_info}
    elif preset == "pose_knife_slash_b":
        # Reverse diagonal cross-slash sweeping back lower-left to upper-right
        r_info = pose_arm_chain(
            rig_obj,
            "R",
            wrist_bl=gd(-0.075, +0.120, +0.035),
            mcp_target_bl=gd(+0.015, +0.155, -0.035),
            hand_dorsal_bl=gd(+0.55, -0.62, +0.55),
            elbow_dir_bl=gd(+0.115, -0.085, +0.225),
            shoulder_dir_bl=gd(+0.235, -0.055, +0.465),
            finger_curls_deg={
                "thumb": (28.0, 38.0, 26.0),
                "index": (68.0, 86.0, 62.0),
                "middle": (72.0, 90.0, 66.0),
                "ring": (74.0, 92.0, 68.0),
                "little": (76.0, 94.0, 68.0),
            },
            thumb_abduct_deg=(-12.0, +14.0),
            index_abduct_deg=(+4.0, 0.0),
        )
        l_info = pose_arm_chain(
            rig_obj,
            "L",
            wrist_bl=gd(-0.385, -0.155, +0.195),
            mcp_target_bl=gd(-0.335, -0.125, +0.115),
            hand_dorsal_bl=gd(-0.72, +0.48, +0.30),
            elbow_dir_bl=gd(-0.485, -0.275, +0.355),
            shoulder_dir_bl=gd(-0.555, -0.205, +0.535),
            finger_curls_deg={
                "thumb": (16.0, 22.0, 14.0),
                "index": (34.0, 44.0, 30.0),
                "middle": (38.0, 48.0, 32.0),
                "ring": (42.0, 52.0, 36.0),
                "little": (46.0, 56.0, 38.0),
            },
            thumb_abduct_deg=(+14.0, -10.0),
        )
        return {**r_info, **l_info}

    # Right Hand seated cleanly outside YS-04 Pistol Grip (+0.013 right wall) + Index Finger hooked onto Trigger Blade
    trig_curl = (24.0, 52.0, 36.0) if preset == "pose_fire" else (8.0, 34.0, 26.0)
    r_info = pose_arm_chain(
        rig_obj,
        "R",
        wrist_bl=gd(+0.036, +0.068, +0.184),
        mcp_target_bl=gd(+0.027, +0.092, +0.096),
        hand_dorsal_bl=gd(+0.94, +0.14, +0.31),
        elbow_dir_bl=gd(+0.155, -0.125, +0.355),
        shoulder_dir_bl=gd(+0.245, -0.065, +0.560),
        finger_curls_deg={
            "thumb": (24.0, 34.0, 26.0),
            "index": trig_curl,
            "middle": (62.0, 78.0, 52.0),
            "ring": (66.0, 80.0, 54.0),
            "little": (70.0, 82.0, 56.0),
        },
        thumb_abduct_deg=(-14.0, +12.0),
        index_abduct_deg=(+14.0, 0.0),
    )

    if preset in ("pose_hip", "pose_fire"):
        l_info = pose_arm_chain(
            rig_obj,
            "L",
            wrist_bl=gd(-0.036, +0.114, -0.064),
            mcp_target_bl=gd(-0.006, +0.135, -0.156),
            hand_dorsal_bl=gd(-0.56, -0.81, +0.15),
            elbow_dir_bl=gd(-0.182, -0.158, +0.052),
            shoulder_dir_bl=gd(-0.355, -0.185, +0.255),
            finger_curls_deg={
                "thumb": (16.0, 22.0, 16.0),
                "index": (62.0, 76.0, 52.0),
                "middle": (66.0, 78.0, 54.0),
                "ring": (68.0, 80.0, 56.0),
                "little": (70.0, 82.0, 56.0),
            },
            thumb_abduct_deg=(+16.0, -12.0),
        )
    elif preset == "pose_ads":
        l_info = pose_arm_chain(
            rig_obj,
            "L",
            wrist_bl=gd(-0.036, +0.114, -0.064),
            mcp_target_bl=gd(-0.006, +0.135, -0.156),
            hand_dorsal_bl=gd(-0.58, -0.80, +0.15),
            elbow_dir_bl=gd(-0.195, -0.172, +0.065),
            shoulder_dir_bl=gd(-0.365, -0.195, +0.265),
            finger_curls_deg={
                "thumb": (18.0, 24.0, 16.0),
                "index": (62.0, 76.0, 52.0),
                "middle": (66.0, 78.0, 54.0),
                "ring": (68.0, 80.0, 56.0),
                "little": (70.0, 82.0, 56.0),
            },
            thumb_abduct_deg=(+14.0, -10.0),
        )
    elif preset == "pose_reload_reach":
        # Left hand swings down-back to wrap snugly around YS04_magazine near magwell
        l_info = pose_arm_chain(
            rig_obj,
            "L",
            wrist_bl=gd(-0.042, +0.032, +0.068),
            mcp_target_bl=gd(-0.014, +0.056, -0.026),
            hand_dorsal_bl=gd(-0.92, -0.34, +0.18),
            elbow_dir_bl=gd(-0.175, -0.185, +0.185),
            shoulder_dir_bl=gd(-0.355, -0.205, +0.345),
            finger_curls_deg={
                "thumb": (24.0, 34.0, 26.0),
                "index": (56.0, 72.0, 48.0),
                "middle": (60.0, 74.0, 50.0),
                "ring": (62.0, 76.0, 52.0),
                "little": (64.0, 76.0, 52.0),
            },
            thumb_abduct_deg=(+22.0, -16.0),
        )
    elif preset == "pose_reload_pull":
        # Left hand pulls YS04_magazine downward & slightly rearward (matching magazine.position = (0, -0.16, +0.07))
        l_info = pose_arm_chain(
            rig_obj,
            "L",
            wrist_bl=gd(-0.040, -0.095, +0.128),
            mcp_target_bl=gd(-0.014, -0.068, +0.034),
            hand_dorsal_bl=gd(-0.92, -0.36, +0.16),
            elbow_dir_bl=gd(-0.175, -0.265, +0.235),
            shoulder_dir_bl=gd(-0.355, -0.245, +0.375),
            finger_curls_deg={
                "thumb": (26.0, 36.0, 28.0),
                "index": (58.0, 74.0, 50.0),
                "middle": (62.0, 76.0, 52.0),
                "ring": (64.0, 78.0, 54.0),
                "little": (66.0, 78.0, 54.0),
            },
            thumb_abduct_deg=(+22.0, -16.0),
        )
    else:
        l_info = apply_pose_preset(rig_obj, "pose_hip")
        return l_info

    return {**r_info, **l_info}


def bake_actions_to_nla(rig_obj: bpy.types.Object) -> dict:
    """Create distinct 2-frame pose Actions FIRST (without NLA interference), then push to NLA tracks."""
    rig_obj.animation_data_create()
    pose_names = [
        "pose_hip",
        "pose_ads",
        "pose_reload_reach",
        "pose_reload_pull",
        "pose_fire",
        "pose_knife_idle",
        "pose_knife_slash_a",
        "pose_knife_slash_b",
    ]
    diagnostics = {}
    baked_actions = []

    bpy.context.scene.frame_set(1)
    for pname in pose_names:
        rig_obj.animation_data.action = None
        info = apply_pose_preset(rig_obj, pname)
        diagnostics[pname] = info

        act = bpy.data.actions.new(name=pname)
        act.use_fake_user = True
        rig_obj.animation_data.action = act

        # Insert keyframes directly without calling scene.frame_set() so NLA/action eval never resets pose bones
        for pbone in rig_obj.pose.bones:
            pbone.rotation_mode = "QUATERNION"
            pbone.keyframe_insert(data_path="location", frame=1)
            pbone.keyframe_insert(data_path="rotation_quaternion", frame=1)
            pbone.keyframe_insert(data_path="location", frame=2)
            pbone.keyframe_insert(data_path="rotation_quaternion", frame=2)

        baked_actions.append((pname, act))

    rig_obj.animation_data.action = None
    for pname, act in baked_actions:
        track = rig_obj.animation_data.nla_tracks.new()
        track.name = pname
        strip = track.strips.new(pname, 1, act)
        strip.name = pname
        track.mute = False

    # Verify baked action fcurves actually differ between pose_hip and pose_reload_pull
    hip_fc = {fc.data_path + ":" + str(fc.array_index): fc.keyframe_points[0].co[1] for fc in bpy.data.actions["pose_hip"].fcurves}
    pull_fc = {fc.data_path + ":" + str(fc.array_index): fc.keyframe_points[0].co[1] for fc in bpy.data.actions["pose_reload_pull"].fcurves}
    max_diff = max(abs(hip_fc[k] - pull_fc.get(k, hip_fc[k])) for k in hip_fc)
    if max_diff < 0.05:
        raise RuntimeError(f"Baked NLA actions did not diverge (max_diff={max_diff})!")

    apply_pose_preset(rig_obj, "pose_hip")
    return diagnostics


def measure_posed_bounds_godot(arm_obj: bpy.types.Object, rig_obj: bpy.types.Object, preset: str) -> dict:
    was_nla = rig_obj.animation_data.use_nla if rig_obj.animation_data else False
    if rig_obj.animation_data:
        rig_obj.animation_data.use_nla = False
    apply_pose_preset(rig_obj, preset)
    deps = bpy.context.evaluated_depsgraph_get()
    ev = arm_obj.evaluated_get(deps)
    m = ev.to_mesh()
    pts_gd = [Vector((v.co.x, v.co.z, -v.co.y)) for v in m.vertices]
    l_pts = [p for v, p in zip(arm_obj.data.vertices, pts_gd) if v.co.x >= 0.0]
    r_pts = [p for v, p in zip(arm_obj.data.vertices, pts_gd) if v.co.x < 0.0]
    # Specifically check max Y near top of handguard (z in [-0.20, -0.05], |x| < 0.020) for ADS sightline clearance
    rail_band = [p for p in l_pts if -0.20 <= p.z <= -0.02 and abs(p.x) < 0.018]
    max_rail_y = round(max((p.y for p in rail_band), default=0.0), 4)
    ev.to_mesh_clear()
    if rig_obj.animation_data:
        rig_obj.animation_data.use_nla = was_nla
    return {
        "left_bounds_gd": [
            [round(min(p[i] for p in l_pts), 4) for i in range(3)],
            [round(max(p[i] for p in l_pts), 4) for i in range(3)],
        ],
        "right_bounds_gd": [
            [round(min(p[i] for p in r_pts), 4) for i in range(3)],
            [round(max(p[i] for p in r_pts), 4) for i in range(3)],
        ],
        "max_center_rail_y_gd": max_rail_y,
        "optic_reticle_y_gd": 0.234,
        "sightline_clear": max_rail_y < 0.195,
    }


def measure_knife_hand_frame(rig_obj: bpy.types.Object) -> dict:
    was_nla = rig_obj.animation_data.use_nla if rig_obj.animation_data else False
    if rig_obj.animation_data:
        rig_obj.animation_data.use_nla = False
    apply_pose_preset(rig_obj, "pose_knife_idle")
    pb = rig_obj.pose.bones
    inv_hand = pb["hand.R"].matrix.inverted()
    samples = {}
    for bname in [
        "hand.R",
        "thumb_01.R", "thumb_02.R", "thumb_03.R",
        "index_01.R", "index_02.R", "index_03.R",
        "middle_01.R", "middle_02.R", "middle_03.R",
        "ring_01.R", "ring_02.R", "ring_03.R",
        "little_01.R", "little_02.R", "little_03.R",
    ]:
        h_loc = inv_hand @ pb[bname].head
        t_loc = inv_hand @ pb[bname].tail
        samples[bname] = {
            "head": [round(float(x), 4) for x in h_loc],
            "tail": [round(float(x), 4) for x in t_loc],
        }
    idx_tail = Vector(samples["index_01.R"]["tail"])
    lit_tail = Vector(samples["little_01.R"]["tail"])
    grip_axis = (idx_tail - lit_tail).normalized()
    grip_center = (idx_tail.lerp(lit_tail, 0.52) + Vector((0.0, 0.0, -0.015)))
    if rig_obj.animation_data:
        rig_obj.animation_data.use_nla = was_nla
    return {
        "grip_center_bone_local": [round(float(x), 4) for x in grip_center],
        "grip_axis_to_index_bone_local": [round(float(x), 4) for x in grip_axis],
        "finger_samples_bone_local": samples,
    }


def main():
    tex_paths = prepare_pbr_textures()
    arm_obj, poly_fs = extract_sculpted_arms()
    joints = compute_joints_and_normals(arm_obj.data, poly_fs)
    sculpt_tactical_garments_and_materials(arm_obj, poly_fs, joints, tex_paths)
    watch_verts = add_left_wrist_tactical_watch(arm_obj, joints)
    rig_obj = create_armature_and_weights(arm_obj, joints, watch_verts)
    pose_diag = bake_actions_to_nla(rig_obj)

    bounds_hip = measure_posed_bounds_godot(arm_obj, rig_obj, "pose_hip")
    bounds_ads = measure_posed_bounds_godot(arm_obj, rig_obj, "pose_ads")
    bounds_pull = measure_posed_bounds_godot(arm_obj, rig_obj, "pose_reload_pull")
    knife_frame = measure_knife_hand_frame(rig_obj)
    apply_pose_preset(rig_obj, "pose_hip")

    # Export fp_arms.glb
    bpy.ops.object.select_all(action="DESELECT")
    rig_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = rig_obj

    out_glb = DEST / "fp_arms.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_all_influences=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_image_format="JPEG",
        export_jpeg_quality=88,
    )

    summary = {
        "output_glb": str(out_glb.relative_to(ROOT)),
        "glb_bytes": out_glb.stat().st_size,
        "vertices": len(arm_obj.data.vertices),
        "polygons": len(arm_obj.data.polygons),
        "bones": len(rig_obj.data.bones),
        "materials": [m.name for m in arm_obj.data.materials],
        "bounds_hip": bounds_hip,
        "bounds_ads": bounds_ads,
        "bounds_pull": bounds_pull,
        "knife_hand_local": knife_frame,
        "poses": pose_diag,
    }
    report_path = ROOT / "docs" / "slice-v052-arms-build.json"
    report_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print("FP_ARMS_BUILT", json.dumps({k: v for k, v in summary.items() if k != "poses"}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
