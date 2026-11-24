#!/usr/bin/env python3
"""Fetch verified Poly Haven CC0 1K PBR textures and 3D photogrammetry nature models
for Yanshan Force v0.9.7 (Desert Sand/Cliffs/Buildings + Yanshan Mossy Boulders/Shrubs).

All assets fetched from https://polyhaven.com/ are licensed under CC0 1.0 Public Domain.
"""
from __future__ import annotations

import json
import pathlib
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
PBR_OUT = ROOT / "game" / "assets" / "pbr_v097"
CACHE = pathlib.Path(tempfile.gettempdir()) / "yanshan_v097_cc0_cache"
PBR_OUT.mkdir(parents=True, exist_ok=True)
CACHE.mkdir(parents=True, exist_ok=True)

HEADERS = {"User-Agent": "YanshanForceCC0Fetcher/0.9.7"}

TEXTURES = [
    "coast_sand_01",
    "gravelly_sand",
    "cliff_side",
    "gravel_road",
    "clay_plaster",
    "old_sandstone_02",
    "plaster_grey_04",
    "aerial_grass_rock",
    "mossy_rock",
]

MODELS = [
    "namaqualand_boulder_02",
    "namaqualand_boulder_03",
    "namaqualand_cliff_01",
    "wild_rooibos_bush",
    "rock_moss_set_02",
    "rock_07",
    "shrub_01",
    "shrub_02",
]


def fetch_json(url: str) -> dict:
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8"))


def download_file(url: str, dst: pathlib.Path):
    if dst.exists() and dst.stat().st_size > 1024:
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=60) as r:
        dst.write_bytes(r.read())


def main():
    # 1. Fetch 1K JPG/PNG PBR Texture maps (Diffuse, nor_gl, Rough) straight into game/assets/pbr_v097/
    for slug in TEXTURES:
        meta = fetch_json(f"https://api.polyhaven.com/files/{slug}")
        for chan, suffix in [("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("Rough", "rough")]:
            block = meta.get(chan, {}).get("1k", {})
            ext = "jpg" if "jpg" in block else ("png" if "png" in block else None)
            if not ext:
                print(f"WARN missing {slug}/{chan}")
                continue
            url = block[ext]["url"]
            dst = PBR_OUT / f"{slug}_{suffix}.{ext}"
            download_file(url, dst)
        print(f"[TEX OK] {slug}", flush=True)

    # 2. Fetch 1K GLTF + included bin/textures for 3D photogrammetry rocks, cliffs & shrubs into local cache
    for slug in MODELS:
        meta = fetch_json(f"https://api.polyhaven.com/files/{slug}")
        gltf_blk = meta.get("gltf", {}).get("1k", {}).get("gltf", {})
        if not gltf_blk:
            print(f"WARN missing gltf for {slug}")
            continue
        mdir = CACHE / slug
        mdir.mkdir(parents=True, exist_ok=True)
        main_url = gltf_blk["url"]
        main_name = main_url.rsplit("/", 1)[-1]
        download_file(main_url, mdir / main_name)
        for rel_path, inc_info in gltf_blk.get("include", {}).items():
            download_file(inc_info["url"], mdir / rel_path)
        print(f"[MOD OK] {slug} (gltf + {len(gltf_blk.get('include', {}))} files)", flush=True)

    print("ALL_CC0_FETCH_COMPLETE", flush=True)


if __name__ == "__main__":
    main()
