"""Fetch approved public CC0 human base mesh & fabric PBR assets for v0.5.2 first-person arms; never execute downloads."""
from pathlib import Path
from urllib.request import urlopen, Request
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "downloads" / "slice-v052"
OUT.mkdir(parents=True, exist_ok=True)

HEADERS = {"User-Agent": "YanshanAssetPreparation/0.5.2"}


def fetch(url: str, path: Path, limit: int = 120_000_000) -> Path:
    if path.exists() and path.stat().st_size > 0:
        return path
    req = Request(url, headers=HEADERS)
    with urlopen(req, timeout=90) as resp:
        data = resp.read(limit + 1)
    if len(data) > limit:
        raise RuntimeError(f"Size cap exceeded ({limit} bytes): {url}")
    path.write_bytes(data)
    return path


def resolve_blender_human_bundle_url() -> tuple[str, str]:
    index_url = "https://download.blender.org/demo/asset-bundles/human-base-meshes/"
    fallback_name = "human-base-meshes-bundle-v1.4.1.zip"
    try:
        req = Request(index_url, headers=HEADERS)
        with urlopen(req, timeout=30) as resp:
            html = resp.read(500_000).decode("utf-8", errors="replace")
        matches = sorted(set(re.findall(r'href="(human-base-meshes-bundle-v[\d.]+\.zip)"', html)))
        if matches:
            chosen = matches[-1]
            return chosen, index_url + chosen
    except Exception as exc:
        print("INDEX_WARN", str(exc), flush=True)
    return fallback_name, index_url + fallback_name


def main() -> int:
    bundle_name, bundle_url = resolve_blender_human_bundle_url()
    targets = [
        (bundle_name, bundle_url, 120_000_000, True, "Blender Studio Human Base Meshes Bundle (CC0 1.0)"),
        (
            "mpfb2_base.obj",
            "https://raw.githubusercontent.com/makehumancommunity/mpfb2/master/src/mpfb/data/3dobjs/base.obj",
            15_000_000,
            False,
            "MakeHuman / MPFB2 Canonical Human Base Mesh (CC0 1.0)",
        ),
        (
            "Fabric030_1K-JPG.zip",
            "https://ambientcg.com/get?file=Fabric030_1K-JPG.zip",
            25_000_000,
            False,
            "ambientCG Fabric 030 1K PBR Maps (CC0 1.0)",
        ),
        (
            "Leather026_1K-JPG.zip",
            "https://ambientcg.com/get?file=Leather026_1K-JPG.zip",
            25_000_000,
            False,
            "ambientCG Leather 026 1K PBR Maps (CC0 1.0)",
        ),
    ]

    records = []
    primary_ok = False
    for filename, url, limit, required, label in targets:
        try:
            path = fetch(url, OUT / filename, limit)
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            size = path.stat().st_size
            records.append(
                {
                    "file": filename,
                    "label": label,
                    "license": "CC0-1.0",
                    "url": url,
                    "bytes": size,
                    "sha256": digest,
                }
            )
            print("OK", filename, size, digest[:16], flush=True)
            if filename.endswith(".zip") and "human-base-meshes" in filename or filename == "mpfb2_base.obj":
                primary_ok = True
        except Exception as exc:
            records.append({"file": filename, "label": label, "url": url, "error": str(exc)})
            print("ERR", filename, str(exc), flush=True)
            if required and not primary_ok:
                print("WARN primary bundle failed, checking fallback...", flush=True)

    (OUT / "download-record.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    if not primary_ok:
        print("FATAL: No CC0 human base mesh could be downloaded.", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
