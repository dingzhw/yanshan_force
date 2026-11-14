"""Fetch open-community CC0 (Poly Haven) and CC BY 4.0 (Polyfork) 3D wildlife & botanical assets for v0.6.1.

Downloads raw source files into gitignored `downloads/slice-v061/` along with
SHA-256 verification and author/license metadata in `downloads/slice-v061/download-record.json`.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "downloads" / "slice-v061"
POLYFORK_DIR = OUT_DIR / "polyfork"
POLYHAVEN_DIR = OUT_DIR / "polyhaven"

UA = {"User-Agent": "YanshanAssetPrep/0.6.1"}
PROXY_URL = "http://127.0.0.1:7913"
PROXY_OPENER = urllib.request.build_opener(
    urllib.request.ProxyHandler({"http": PROXY_URL, "https": PROXY_URL})
)

POLYFORK_MODELS = [
    # Wildlife creatures (CC BY 4.0, Lucas Martinic / Polyfork)
    "forest-rabbit-ea2da0",
    "red-fox-5c3bc0",
    "pig-base",
    "thorn-boar-base",
    "pigeon-base",
    "herring-gull-base",
    "koi-base",
    "shore-crab-base",
    "cleaner-shrimp-base",
    # Woodland undergrowth & waterside props
    "azalea-bush-7bb14d",
    "cattail-reed-6abbb3",
    "moat-reed-clump-dd6b60",
    "fern-plant-1559b8",
    "grass-tuft-a40a08",
    "fallen-log-1685fb",
]

POLYHAVEN_TEXTURES = [
    "japanese_camphor_bark",
    "bark_willow",
    "trident_maple_bark",
    "river_small_rocks",
]


def fetch_bytes(url: str, timeout: int = 25) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    try:
        return PROXY_OPENER.open(req, timeout=timeout).read()
    except Exception:
        return urllib.request.urlopen(req, timeout=timeout).read()


def save_verified(dest: Path, url: str) -> dict:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 256:
        data = dest.read_bytes()
    else:
        print(f"Downloading {url} -> {dest.relative_to(ROOT)} ...")
        data = fetch_bytes(url)
        dest.write_bytes(data)
    sha256 = hashlib.sha256(data).hexdigest()
    return {
        "file": str(dest.relative_to(ROOT)).replace("\\", "/"),
        "url": url,
        "bytes": len(data),
        "sha256": sha256,
    }


def main() -> None:
    POLYFORK_DIR.mkdir(parents=True, exist_ok=True)
    POLYHAVEN_DIR.mkdir(parents=True, exist_ok=True)

    record: dict = {
        "version": "0.6.1",
        "polyfork_license": "CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) - Credit: Lucas Martinic / Polyfork (https://polyfork.dev)",
        "polyhaven_license": "CC0 1.0 Universal (https://polyhaven.com/license)",
        "polyfork": {},
        "polyhaven": {},
    }

    for mid in POLYFORK_MODELS:
        url = f"https://polyfork.dev/cdn/{mid}.glb"
        dest = POLYFORK_DIR / f"{mid}.glb"
        record["polyfork"][mid] = save_verified(dest, url)

    for tid in POLYHAVEN_TEXTURES:
        info = json.loads(fetch_bytes(f"https://api.polyhaven.com/info/{tid}").decode("utf-8"))
        files = json.loads(fetch_bytes(f"https://api.polyhaven.com/files/{tid}").decode("utf-8"))
        t_rec = {
            "authors": info.get("authors", {}),
            "page": f"https://polyhaven.com/a/{tid}",
            "channels": {},
        }
        for ch in ("Diffuse", "nor_gl", "Rough"):
            fmt_map = files.get(ch, {}).get("1k", {})
            chosen = fmt_map.get("jpg") or fmt_map.get("png")
            if not chosen or not chosen.get("url"):
                continue
            ext = Path(chosen["url"]).suffix or ".jpg"
            dest = POLYHAVEN_DIR / f"{tid}_{ch.lower()}{ext}"
            t_rec["channels"][ch] = save_verified(dest, chosen["url"])
        record["polyhaven"][tid] = t_rec

    rec_path = OUT_DIR / "download-record.json"
    rec_path.write_text(json.dumps(record, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"Saved download record to {rec_path} ({len(record['polyfork'])} Polyfork GLBs, {len(record['polyhaven'])} Poly Haven PBR sets).")


if __name__ == "__main__":
    main()
