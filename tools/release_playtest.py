"""Build standalone Windows releases, sync root launchers, and keep playtest/ tidy.

Git holds full source history and tags, so this script no longer duplicates
source checkpoints or hoards historical playtest ZIPs by default.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def _handle_ro(func, path, _exc_info):
    os.chmod(path, stat.S_IWRITE)
    func(path)


def write_launchers(folder: Path, relative_exe: str = "YanshanBase.exe", root_entry: bool = False):
    exe = f'"%~dp0{relative_exe}"'
    diagnostics = Path(relative_exe).parent / "diagnostics"
    standard_name = "开始烟山试玩.cmd" if root_entry else "开始试玩.cmd"
    scripts = {
        standard_name: f'@echo off\nstart "" {exe}\n',
        "低负载启动.cmd": f'@echo off\nstart "" {exe} --rendering-method gl_compatibility -- --low-quality\n',
        "性能巡检.cmd": (
            '@echo off\n'
            'setlocal\n'
            f'set "DRZ_DIAGNOSTICS_DIR=%~dp0{diagnostics}"\n'
            'if /I "%~1"=="standard" goto standard\n'
            'if /I "%~1"=="balanced" goto balanced\n'
            f'start "" {exe} --rendering-method gl_compatibility -- --qa --hardware-check --low-quality\n'
            'exit /b\n'
            ':standard\n'
            f'start "" {exe} -- --qa --hardware-check\n'
            'exit /b\n'
            ':balanced\n'
            f'start "" {exe} -- --qa --hardware-check --low-quality\n'
        ),
    }
    for name, contents in scripts.items():
        (folder / name).write_bytes(contents.replace("\n", "\r\n").encode("ascii"))


def prune_old_playtests(keep_folder: Path, keep_archive: Path) -> list[str]:
    pt_dir = ROOT / "playtest"
    removed: list[str] = []
    if not pt_dir.exists():
        return removed
    for entry in sorted(pt_dir.iterdir()):
        if entry.resolve() in {keep_folder.resolve(), keep_archive.resolve()}:
            continue
        if entry.is_dir() and entry.name.startswith("windows-v"):
            shutil.rmtree(entry, onexc=_handle_ro)
            removed.append(entry.name)
        elif entry.is_file() and entry.name.startswith("烟山基地试玩_v") and entry.name.endswith("_Windows.zip"):
            os.chmod(entry, stat.S_IWRITE)
            entry.unlink()
            removed.append(entry.name)
    return removed


def git_head_short() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, text=True).strip()
    except Exception:
        return "working-tree"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--notes", default="")
    parser.add_argument("--prepared-build", type=Path, help="Use an already exported and verified Windows EXE/PCK pair")
    parser.add_argument("--root-launchers", action="store_true", help="Kept for CLI compatibility (root launchers sync by default)")
    parser.add_argument("--no-root-launchers", action="store_true", help="Skip updating project root .cmd launchers")
    parser.add_argument("--keep-old", action="store_true", help="Preserve previous playtest/windows-v* builds and ZIPs")
    args = parser.parse_args()

    folder = ROOT / "playtest" / ("windows-v" + args.version)
    archive_path = ROOT / "playtest" / f"烟山基地试玩_v{args.version}_Windows.zip"
    manifest_path = ROOT / "docs" / f"release-{args.version}.json"
    if not args.overwrite and any(p.exists() for p in [folder, archive_path, manifest_path]):
        raise RuntimeError(f"Release files already exist for {args.version}; pass --overwrite to replace")

    if args.prepared_build is not None:
        for name in ["YanshanBase.exe", "YanshanBase.pck"]:
            if not (args.prepared_build / name).is_file():
                raise FileNotFoundError(args.prepared_build / name)

    result: dict = {"version": args.version, "git_base": git_head_short()}
    if args.prepared_build is None:
        cfg = ROOT / "docs/runtime-local.json"
        if cfg.exists():
            runtime = json.loads(cfg.read_text(encoding="utf-8"))
        else:
            import sys
            rt = Path(os.environ.get("DRZ_RUNTIME") or (Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData/Local")) / "Temp/drz-english-shooter-20261103"))
            runtime = {
                "runtime_root": str(rt),
                "console_executable": str(rt / "godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"),
                "python_used": sys.executable,
                "game_working_copy": str(rt / "yanshan-v01"),
            }
        engine_dir = Path(runtime["console_executable"]).parent
        sc_marker = engine_dir / "_sc_"
        if not sc_marker.exists():
            sc_marker.write_bytes(b"")

        qa_appdata = Path(runtime["runtime_root"]) / "qa-appdata"
        (qa_appdata / "Godot").mkdir(parents=True, exist_ok=True)
        qa_logs = Path(runtime["runtime_root"]) / "qa-logs"
        qa_logs.mkdir(parents=True, exist_ok=True)

        src_tpl = engine_dir / "editor_data/export_templates/4.7.2.stable"
        dst_tpl = qa_appdata / "Godot/export_templates/4.7.2.stable"
        if src_tpl.exists() and not (dst_tpl / "windows_release_x86_64.exe").exists():
            dst_tpl.mkdir(parents=True, exist_ok=True)
            for item in src_tpl.iterdir():
                if item.is_file():
                    shutil.copy2(item, dst_tpl / item.name)

        env = os.environ.copy()
        env["APPDATA"] = str(qa_appdata)
        env["LOCALAPPDATA"] = str(qa_appdata)

        subprocess.run([runtime["python_used"], str(ROOT / "tools/build_playtest.py")], check=True, env=env)
        folder.mkdir(parents=True, exist_ok=True)
        command = [runtime["console_executable"], "--headless", "--path", runtime["game_working_copy"], "--editor", "--import", "--quit"]
        with (qa_logs / f"v{args.version}-import.log").open("w", encoding="utf-8") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, env=env)
        with (qa_logs / f"v{args.version}-export.log").open("w", encoding="utf-8") as log:
            subprocess.run(
                [runtime["console_executable"], "--headless", "--path", runtime["game_working_copy"], "--export-release", "Windows Desktop", str(folder / "YanshanBase.exe")],
                stdout=log,
                stderr=subprocess.STDOUT,
                check=True,
                env=env,
            )
    else:
        folder.mkdir(parents=True, exist_ok=True)
        for name in ["YanshanBase.exe", "YanshanBase.pck"]:
            shutil.copy2(args.prepared_build / name, folder / name)

    write_launchers(folder)
    (folder / "试玩说明.txt").write_text(
        f"烟山基地 {args.version}\n{args.notes}\n\n双击开始试玩.cmd即可启动游戏。\n",
        encoding="utf-8-sig",
    )
    override = ROOT / "docs" / f"v{args.version}-试玩说明.txt"
    if override.exists():
        shutil.copy2(override, folder / "试玩说明.txt")
    shutil.copy2(ROOT / "game/THIRD_PARTY.txt", folder)
    shutil.copytree(ROOT / "game/licenses", folder / "licenses", dirs_exist_ok=True)
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for source in sorted(folder.rglob("*")):
            if source.is_file():
                archive.write(source, source.relative_to(folder))

    result["files"] = [
        {"path": str(p.relative_to(ROOT)), "bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
        for p in [folder / "YanshanBase.exe", folder / "YanshanBase.pck", archive_path]
    ]
    manifest_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")

    if not args.no_root_launchers:
        write_launchers(ROOT, str((folder / "YanshanBase.exe").relative_to(ROOT)), root_entry=True)
    if not args.keep_old:
        pruned = prune_old_playtests(folder, archive_path)
        if pruned:
            result["pruned_old_playtests"] = pruned

    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
