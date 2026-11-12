"""Inspect downloaded CC0 human base meshes and exact YS-04 rifle grip geometry in headless Blender 4.5."""
import json
import zipfile
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
DL = ROOT / "downloads" / "slice-v052"
SRC = ROOT / "third_party" / "slice-v052"
SRC.mkdir(parents=True, exist_ok=True)


def extract_sources() -> list[Path]:
    blends = []
    for zpath in sorted(DL.glob("*.zip")):
        with zipfile.ZipFile(zpath) as zf:
            for member in zf.namelist():
                lower = member.lower()
                if lower.endswith((".blend", ".obj", ".jpg", ".png", ".txt", ".md")):
                    target = SRC / Path(member).name
                    if not target.exists():
                        target.write_bytes(zf.read(member))
                    if lower.endswith(".blend"):
                        blends.append(target)
    return blends


def inspect_blend(path: Path) -> list[dict]:
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False, use_scripts=False)
    items = []
    for obj in sorted(bpy.data.objects, key=lambda o: o.name):
        if obj.type not in {"MESH", "ARMATURE"}:
            continue
        info = {
            "name": obj.name,
            "type": obj.type,
            "dimensions": [round(x, 4) for x in obj.dimensions],
            "location": [round(x, 4) for x in obj.location],
        }
        if obj.type == "MESH":
            mesh = obj.data
            coords = [obj.matrix_world @ v.co for v in mesh.vertices]
            if coords:
                lo = [round(min(v[i] for v in coords), 4) for i in range(3)]
                hi = [round(max(v[i] for v in coords), 4) for i in range(3)]
                info["world_bounds"] = [lo, hi]
            info["verts"] = len(mesh.vertices)
            info["polys"] = len(mesh.polygons)
            info["uvs"] = [uv.name for uv in mesh.uv_layers]
            info["vgroups"] = [vg.name for vg in obj.vertex_groups[:15]]
        elif obj.type == "ARMATURE":
            info["bones"] = [b.name for b in obj.data.bones[:30]]
        items.append(info)
    return items


def inspect_rifle_in_godot_space() -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rifle_glb = ROOT / "game" / "assets" / "slice" / "rifle.glb"
    bpy.ops.import_scene.gltf(filepath=str(rifle_glb))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # Note: Blender uses Z-up, whereas Godot uses Y-up (-Z forward, +X right, +Y up).
    # In Blender: X_bl = X_gd, Y_bl = -Z_gd, Z_bl = Y_gd (since glTF +Y up -> Blender +Z up, glTF +Z -> Blender -Y).
    all_pts_gd = []
    part_bounds = {}
    for o in meshes:
        pts_bl = [o.matrix_world @ v.co for v in o.data.vertices]
        # Convert Blender (x, y, z) back to Godot glTF space: x_gd = x_bl, y_gd = z_bl, z_gd = -y_bl
        pts_gd = [Vector((p.x, p.z, -p.y)) for p in pts_bl]
        all_pts_gd.extend(pts_gd)
        part_bounds[o.name] = pts_gd

    lo = Vector((min(p.x for p in all_pts_gd), min(p.y for p in all_pts_gd), min(p.z for p in all_pts_gd)))
    hi = Vector((max(p.x for p in all_pts_gd), max(p.y for p in all_pts_gd), max(p.z for p in all_pts_gd)))
    size = hi - lo
    center = (lo + hi) * 0.5
    scale_factor = 0.22 / max(size.y, 0.01)
    offset = Vector((-center.x, -lo.y, -center.z)) * scale_factor

    def to_weapon_view(pts: list[Vector]) -> list[Vector]:
        return [p * scale_factor + offset for p in pts]

    wv_all = to_weapon_view(all_pts_gd)
    wv_parts = {}
    for name, pts in part_bounds.items():
        wpts = to_weapon_view(pts)
        wlo = [round(min(p[i] for p in wpts), 4) for i in range(3)]
        whi = [round(max(p[i] for p in wpts), 4) for i in range(3)]
        wv_parts[name] = {"lo": wlo, "hi": whi, "verts": len(wpts)}

    # Slice receiver along Z_gd to locate exact pistol grip, trigger guard, and handguard cross-sections
    rec_pts = []
    for name, pts in part_bounds.items():
        if "magazine" not in name.lower():
            rec_pts.extend(to_weapon_view(pts))

    slices = []
    for z_idx in range(-26, 26, 2):
        z0 = z_idx * 0.01
        z1 = z0 + 0.02
        band = [p for p in rec_pts if z0 <= p.z <= z1]
        if band:
            slices.append(
                {
                    "z": [round(z0, 3), round(z1, 3)],
                    "x": [round(min(p.x for p in band), 4), round(max(p.x for p in band), 4)],
                    "y": [round(min(p.y for p in band), 4), round(max(p.y for p in band), 4)],
                }
            )
    # Specifically inspect pistol grip band (y < 0.125 and z > 0.06)
    grip_band = [p for p in rec_pts if p.y < 0.128 and p.z > 0.065]
    grip_slices = []
    for y_idx in range(2, 13):
        y0 = y_idx * 0.01
        y1 = y0 + 0.01
        sub = [p for p in grip_band if y0 <= p.y <= y1]
        if sub:
            grip_slices.append(
                {
                    "y": [round(y0, 3), round(y1, 3)],
                    "x": [round(min(p.x for p in sub), 4), round(max(p.x for p in sub), 4)],
                    "z": [round(min(p.z for p in sub), 4), round(max(p.z for p in sub), 4)],
                }
            )

    return {
        "scale_factor": round(scale_factor, 5),
        "offset_godot": [round(offset.x, 5), round(offset.y, 5), round(offset.z, 5)],
        "parts_godot": wv_parts,
        "receiver_z_slices_godot": slices,
        "pistol_grip_y_slices_godot": grip_slices,
    }


def main():
    blends = extract_sources()
    report = {
        "extracted_files": sorted(p.name for p in SRC.iterdir()),
        "blends": {b.name: inspect_blend(b) for b in blends},
        "mpfb2_obj_exists": (DL / "mpfb2_base.obj").exists(),
        "rifle_godot_space": inspect_rifle_in_godot_space(),
    }
    out_path = ROOT / "docs" / "slice-v052-arm-inspection.json"
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("INSPECT_OK", out_path, "BLENDS", [b.name for b in blends], flush=True)


if __name__ == "__main__":
    main()
