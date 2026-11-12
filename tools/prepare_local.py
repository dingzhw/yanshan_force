"""Restore the portable editor and a disposable sample from verified archives.

Uses Python's standard library; performs no downloads, installs, or deletion.
Source packages remain in the project; Godot and generated caches stay in a
task-specific directory beneath the user's local temporary directory.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import shutil
import stat
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2"


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def reject_links(path):
    for current in (path, *path.parents):
        if current.exists() and (current.is_symlink() or current.is_junction()):
            raise RuntimeError(f"Linked path requires separate review: {current}")


def extract_new(archive_path, destination, strip_root=False):
    reject_links(destination)
    if destination.exists():
        print(f"Preserving existing directory: {destination}")
        return
    with zipfile.ZipFile(archive_path) as archive:
        selected = []
        for item in archive.infolist():
            posix = PurePosixPath(item.filename)
            windows = PureWindowsPath(item.filename)
            if (posix.is_absolute() or windows.drive or windows.root
                    or ".." in posix.parts or "\\" in item.filename
                    or stat.S_ISLNK(item.external_attr >> 16)):
                raise RuntimeError(f"Unsafe ZIP entry: {item.filename}")
            parts = posix.parts[1:] if strip_root else posix.parts
            if parts:
                selected.append((item, destination.joinpath(*parts)))
        destination.mkdir(parents=True)
        for item, target in selected:
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)


def write_new_or_same(path, content):
    if path.exists():
        if path.read_text(encoding="utf-8") != content:
            raise RuntimeError(f"Existing file differs; preserving it: {path}")
    else:
        path.write_text(content, encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-root", type=Path, required=True)
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    runtime = args.runtime_root.absolute()
    reject_links(runtime)
    user_temp = Path(os.environ["USERPROFILE"]) / "AppData" / "Local" / "Temp"
    if not runtime.is_relative_to(user_temp) or runtime == user_temp:
        raise RuntimeError("Runtime must be a task-specific directory under Local/Temp.")
    if runtime.name != "drz-english-shooter-20261103":
        raise RuntimeError("Unexpected runtime directory name.")
    if runtime.is_relative_to(ROOT):
        raise RuntimeError("Keep runtime and caches outside the source project.")

    manifest = json.loads((ROOT / "docs/resources.json").read_text(encoding="utf-8"))
    packages = {item["id"]: item for item in manifest["packages"]}
    for package in packages.values():
        path = ROOT / package["archive"]
        if path.stat().st_size != package["bytes"] or sha256(path) != package["sha256"]:
            raise RuntimeError(f"Archive integrity mismatch: {path}")
        print(f"Verified: {path.name}")

    for item in manifest.get("extra_files", []):
        path = ROOT / item["file"]
        if path.stat().st_size != item["bytes"] or sha256(path) != item["sha256"]:
            raise RuntimeError(f"Extra resource integrity mismatch: {path}")

    for package_id in ("fps", "nature", "survival"):
        package = packages[package_id]
        extract_new(ROOT / package["archive"], ROOT / package["destination"],
                    strip_root=package_id == "fps")

    engine = runtime / f"godot-{VERSION}"
    extract_new(ROOT / packages["godot"]["archive"], engine)
    write_new_or_same(engine / "_sc_", "")
    sample = runtime / "fps-template"
    reject_links(sample)
    if not sample.exists():
        shutil.copytree(ROOT / packages["fps"]["destination"], sample,
                        ignore=shutil.ignore_patterns(".godot", ".git"))
        config_path = sample / "project.godot"
        original = config_path.read_bytes()
        (sample / "project.godot.upstream").write_bytes(original)
        config = original.decode("utf-8")
        if config.count('"Forward Plus"') != 1 or config.count("[rendering]") != 1:
            raise RuntimeError("Unexpected upstream configuration; inspect before adapting.")
        config = config.replace('"Forward Plus"', '"GL Compatibility"')
        config = config.replace("anti_aliasing/quality/screen_space_aa=1",
                                "anti_aliasing/quality/screen_space_aa=0")
        config = config.replace("[rendering]", '[rendering]\n\n'
                                'renderer/rendering_method="gl_compatibility"\n'
                                'renderer/rendering_method.mobile="gl_compatibility"')
        config_path.write_text(config, encoding="utf-8", newline="\n")

    paths = {
        "godot_version": VERSION,
        "runtime_root": str(runtime),
        "executable": str(engine / f"Godot_v{VERSION}-stable_win64.exe"),
        "console_executable": str(engine / f"Godot_v{VERSION}-stable_win64_console.exe"),
        "sample_project": str(sample),
        "renderer": "gl_compatibility",
        "source_template": str(ROOT / packages["fps"]["destination"]),
        "python_used": sys.executable,
        "self_contained_mode": True,
        "export_templates_installed": False
    }
    write_new_or_same(ROOT / "docs/runtime-local.json",
                      json.dumps(paths, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(paths, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
