"""v0.9.9.6 PCK & Asset Texture Deduplication Tool.

Deduplicates byte-identical embedded textures across all .glb files in game/assets/
using standard glTF 2.0 relative external image URIs:
  - Any embedded texture matching an existing file in game/assets/pbr_v097/ points
    directly to ../pbr_v097/<file> (zero extra copies).
  - Any embedded texture shared by 2+ GLB image slots (across GLBs or within the
    same GLB) is extracted ONCE to game/assets/shared_pbr/<canonical_name>.<ext>
    and every referencing GLB image slot is rewritten to its relative URI while
    compacting unreferenced image bufferViews out of the GLB BIN chunk.
  - Also removes superseded/orphaned Godot-extracted <glb_stem>_*.{png,jpg} files
    in game/assets/ that are neither referenced by any .gd/.tscn/.godot script nor
    matched by any remaining embedded image in <glb_stem>.glb.
"""
from __future__ import annotations

import collections
import hashlib
import json
import os
import pathlib
import re
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
ASSETS = GAME / "assets"
PBR_DIR = ASSETS / "pbr_v097"
SHARED_DIR = ASSETS / "shared_pbr"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for ch in iter(lambda: f.read(1048576), b""):
            h.update(ch)
    return h.hexdigest()


def parse_glb(path: pathlib.Path) -> tuple[dict, bytes] | None:
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != b"glTF":
        return None
    jlen, jtype = struct.unpack("<II", raw[12:20])
    if jtype != 0x4E4F534A:
        return None
    g = json.loads(raw[20 : 20 + jlen].decode("utf-8"))
    bin_off = 20 + jlen
    bin_data = b""
    if bin_off + 8 <= len(raw):
        blen, btype = struct.unpack("<II", raw[bin_off : bin_off + 8])
        if btype == 0x004E4942:
            bin_data = raw[bin_off + 8 : bin_off + 8 + blen]
    return g, bin_data


def write_glb(path: pathlib.Path, g: dict, bin_data: bytes):
    jb = json.dumps(g, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    while len(jb) % 4 != 0:
        jb += b" "
    if bin_data:
        pad = (4 - (len(bin_data) % 4)) % 4
        bin_padded = bin_data + (b"\x00" * pad)
        total = 12 + 8 + len(jb) + 8 + len(bin_padded)
        out = (
            struct.pack("<III", 0x46546C67, 2, total)
            + struct.pack("<II", len(jb), 0x4E4F534A)
            + jb
            + struct.pack("<II", len(bin_padded), 0x004E4942)
            + bin_padded
        )
    else:
        total = 12 + 8 + len(jb)
        out = struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(jb), 0x4E4F534A) + jb
    path.write_bytes(out)


def collect_referenced_buffer_views(obj, out: set[int]):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == "bufferView" and isinstance(v, int):
                out.add(v)
            else:
                collect_referenced_buffer_views(v, out)
    elif isinstance(obj, list):
        for item in obj:
            collect_referenced_buffer_views(item, out)


def remap_buffer_views(obj, mapping: dict[int, int]):
    if isinstance(obj, dict):
        for k, v in list(obj.items()):
            if k == "bufferView" and isinstance(v, int):
                obj[k] = mapping[v]
            else:
                remap_buffer_views(v, mapping)
    elif isinstance(obj, list):
        for item in obj:
            remap_buffer_views(item, mapping)


def sanitize_stem(name: str) -> str:
    clean = re.sub(r"\.(png|jpe?g|webp)$", "", name, flags=re.IGNORECASE)
    clean = re.sub(r"\.\d{3}$", "", clean)
    clean = re.sub(r"[^A-Za-z0-9_\-]+", "_", clean).strip("_")
    return clean or "shared_tex"


def ext_for_image(im: dict, blob: bytes) -> str:
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return ".png"
    if blob[:3] == b"\xff\xd8\xff":
        return ".jpg"
    mt = str(im.get("mimeType", "")).lower()
    if "png" in mt:
        return ".png"
    return ".jpg"


def collect_code_referenced_paths() -> set[str]:
    refs: set[str] = set()
    pat = re.compile(r"res://[^\s\"'\)\]\},;]+")
    files = (
        list((GAME / "scripts").rglob("*.gd"))
        + list((GAME / "tests").rglob("*.gd"))
        + list((GAME / "scenes").rglob("*.tscn"))
        + [GAME / "main.tscn", GAME / "project.godot", ROOT / "tools" / "verify_packaged.gd"]
    )
    for p in files:
        if p.is_file():
            txt = p.read_text(encoding="utf-8", errors="ignore")
            for m in pat.findall(txt):
                refs.add(m)
    return refs


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    SHARED_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Index existing canonical textures in pbr_v097/ and shared_pbr/
    canonical_by_hash: dict[str, pathlib.Path] = {}
    for folder in (PBR_DIR, SHARED_DIR):
        if folder.exists():
            for p in sorted(folder.iterdir()):
                if p.is_file() and p.suffix.lower() in (".png", ".jpg", ".jpeg"):
                    canonical_by_hash.setdefault(sha256_file(p), p)

    # 2. Scan all GLBs under game/assets/slice/ (skipping third-party Kenney nature/survival/fps)
    glb_paths = sorted((ASSETS / "slice").rglob("*.glb"))
    occurrences: dict[str, list[tuple[pathlib.Path, int, str, bytes]]] = collections.defaultdict(list)
    parsed_cache: dict[pathlib.Path, tuple[dict, bytes]] = {}

    for gp in glb_paths:
        parsed = parse_glb(gp)
        if parsed is None:
            continue
        parsed_cache[gp] = parsed
        g, bin_data = parsed
        bvs = g.get("bufferViews", [])
        for idx, im in enumerate(g.get("images", [])):
            if "bufferView" not in im:
                continue
            bv = bvs[im["bufferView"]]
            off = int(bv.get("byteOffset", 0))
            blen = int(bv.get("byteLength", 0))
            blob = bin_data[off : off + blen]
            h = sha256_bytes(blob)
            occurrences[h].append((gp, idx, str(im.get("name", f"tex_{idx}")), blob))

    # 3. Decide canonical external path for every shared / pbr_v097-matching hash
    used_shared_names = {p.name.lower() for p in SHARED_DIR.iterdir() if p.is_file()}
    target_by_hash: dict[str, pathlib.Path] = {}
    new_shared_written = 0
    for h, items in sorted(occurrences.items(), key=lambda kv: -len(kv[1][0][3]) * len(kv[1])):
        if h in canonical_by_hash:
            target_by_hash[h] = canonical_by_hash[h]
            continue
        if len(items) < 2:
            continue
        # Extract ONE canonical copy into game/assets/shared_pbr/
        sample_gp, sample_idx, sample_name, sample_blob = items[0]
        im_meta = parsed_cache[sample_gp][0]["images"][sample_idx]
        ext = ext_for_image(im_meta, sample_blob)
        stem = sanitize_stem(sample_name)
        # Strip model-specific suffixes like _ahsarah_guard / _boss_reis / _assault when shared
        stem = re.sub(r"_(ahsarah_guard|boss_reis|boss_saeed|assault|sniper|chen|haavk_trooper|vanguard_boss|skyfall_overlord)$", "", stem)
        cand_name = f"{stem}{ext}"
        if cand_name.lower() in used_shared_names:
            cand_name = f"{stem}_{h[:6]}{ext}"
        used_shared_names.add(cand_name.lower())
        dst = SHARED_DIR / cand_name
        dst.write_bytes(sample_blob)
        canonical_by_hash[h] = dst
        target_by_hash[h] = dst
        new_shared_written += 1

    # 4. Rewrite GLBs referencing target_by_hash & compact unused image bufferViews
    rewritten_glbs = 0
    total_glb_saved = 0
    for gp, (g, bin_data) in parsed_cache.items():
        bvs = g.get("bufferViews", [])
        changed = False
        for idx, im in enumerate(g.get("images", [])):
            if "bufferView" not in im:
                continue
            bv = bvs[im["bufferView"]]
            off = int(bv.get("byteOffset", 0))
            blen = int(bv.get("byteLength", 0))
            blob = bin_data[off : off + blen]
            h = sha256_bytes(blob)
            if h not in target_by_hash:
                continue
            target_path = target_by_hash[h]
            rel_uri = os.path.relpath(target_path, gp.parent).replace("\\", "/")
            im.pop("bufferView", None)
            im.pop("mimeType", None)
            im["uri"] = rel_uri
            changed = True

        if not changed:
            continue

        before_sz = gp.stat().st_size
        # Compact BIN chunk to keep ONLY bufferViews still referenced anywhere in JSON
        keep_bvs: set[int] = set()
        collect_referenced_buffer_views(g, keep_bvs)
        new_bvs: list[dict] = []
        bv_map: dict[int, int] = {}
        new_bin_parts: list[bytes] = []
        cursor = 0
        for old_idx in sorted(keep_bvs):
            bv = dict(bvs[old_idx])
            off = int(bv.get("byteOffset", 0))
            blen = int(bv.get("byteLength", 0))
            chunk = bin_data[off : off + blen]
            pad = (4 - (cursor % 4)) % 4
            if pad:
                new_bin_parts.append(b"\x00" * pad)
                cursor += pad
            bv["byteOffset"] = cursor
            bv["byteLength"] = blen
            new_bin_parts.append(chunk)
            cursor += blen
            bv_map[old_idx] = len(new_bvs)
            new_bvs.append(bv)

        remap_buffer_views(g, bv_map)
        g["bufferViews"] = new_bvs
        new_bin = b"".join(new_bin_parts)
        if g.get("buffers"):
            g["buffers"][0]["byteLength"] = len(new_bin)
        write_glb(gp, g, new_bin)
        after_sz = gp.stat().st_size
        total_glb_saved += max(0, before_sz - after_sz)
        rewritten_glbs += 1
        print(f"DEDUP_GLB {gp.relative_to(GAME).as_posix():48s} {(before_sz/1048576):5.2f} -> {(after_sz/1048576):5.2f} MiB")

    # 5. Purge superseded/duplicate Godot-extracted <glb_stem>_*.{png,jpg} files in game/assets/slice/
    #    Godot will cleanly re-extract ONLY the remaining non-shared embedded images on next --import!
    code_refs = collect_code_referenced_paths()
    glb_stems_by_dir: dict[pathlib.Path, list[str]] = collections.defaultdict(list)
    for gp in glb_paths:
        glb_stems_by_dir[gp.parent].append(gp.stem)

    purged_extracted = 0
    purged_bytes = 0
    for folder, stems in glb_stems_by_dir.items():
        # Sort longest stems first so prefixes match unambiguously
        stems_sorted = sorted(stems, key=len, reverse=True)
        for p in sorted(folder.iterdir()):
            if not p.is_file() or p.suffix.lower() not in (".png", ".jpg", ".jpeg"):
                continue
            rel_res = "res://" + p.relative_to(GAME).as_posix()
            if rel_res in code_refs:
                continue
            matched_stem = next((st for st in stems_sorted if p.name.startswith(st + "_")), None)
            if matched_stem is None:
                continue
            purged_bytes += p.stat().st_size
            p.unlink()
            imp_sidecar = p.with_name(p.name + ".import")
            if imp_sidecar.exists():
                imp_sidecar.unlink()
            purged_extracted += 1

    # 6. Prune any dangling *.import sidecars whose source asset no longer exists
    pruned_dangling = 0
    for imp in sorted(ASSETS.rglob("*.import")):
        src = imp.with_name(imp.name[:-7])
        if not src.exists():
            imp.unlink()
            pruned_dangling += 1

    print(
        f"\nSUMMARY: new_shared_pbr={new_shared_written} rewritten_glbs={rewritten_glbs} "
        f"glb_saved={total_glb_saved/1048576:.2f} MiB purged_old_extracted={purged_extracted} "
        f"({purged_bytes/1048576:.2f} MiB) pruned_dangling_imports={pruned_dangling} "
        f"(Godot --editor --import --quit will regenerate only active unique maps)"
    )


if __name__ == "__main__":
    main()
