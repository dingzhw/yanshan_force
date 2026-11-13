"""Create immutable local source checkpoints and standalone Windows releases."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def checkpoint(version):
    dest = ROOT / "docs/checkpoints" / f"source-{version}.zip"
    dest.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as archive:
        for source in sorted((ROOT / "game").rglob("*")):
            if source.is_file() and source.suffix in {".gd", ".godot", ".cfg", ".tscn", ".json", ".txt"}:
                archive.write(source, source.relative_to(ROOT))
    return str(dest.relative_to(ROOT))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--checkpoint-only", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--notes", default="")
    args = parser.parse_args()
    if args.version in {"0.3.1", "0.4.0", "0.5.0", "0.5.1", "0.5.2", "0.5.3", "0.5.4", "0.5.5"}:
        raise RuntimeError(f"Protected historical release: {args.version}")
    result = {"version": args.version, "source_checkpoint": checkpoint(args.version)}
    if not args.checkpoint_only:
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
        folder = ROOT / "playtest" / ("windows-v" + args.version)
        if folder.exists() and (folder / "YanshanBase.exe").exists() and not args.overwrite:
            raise RuntimeError(f"Preserving existing completed release: {folder}")
        folder.mkdir(parents=True, exist_ok=True)
        command = [runtime["console_executable"], "--headless", "--path", runtime["game_working_copy"], "--editor", "--import", "--quit"]
        with (ROOT / "docs" / f"v{args.version}-import.log").open("w", encoding="utf-8") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, env=env)
        with (ROOT / "docs" / f"v{args.version}-export.log").open("w", encoding="utf-8") as log:
            subprocess.run(
                [runtime["console_executable"], "--headless", "--path", runtime["game_working_copy"], "--export-release", "Windows Desktop", str(folder / "YanshanBase.exe")],
                stdout=log,
                stderr=subprocess.STDOUT,
                check=True,
                env=env,
            )
        (folder / "开始试玩.cmd").write_bytes(b'@echo off\r\nstart "" "%~dp0YanshanBase.exe"\r\n')
        (folder / "低负载启动.cmd").write_bytes(b'@echo off\r\nstart "" "%~dp0YanshanBase.exe" -- --low-quality\r\n')
        (folder / "性能巡检.cmd").write_bytes(b'@echo off\r\nsetlocal\r\nset "DRZ_DIAGNOSTICS_DIR=%~dp0diagnostics"\r\nstart "" "%~dp0YanshanBase.exe" -- --qa --hardware-check --low-quality\r\n')
        (folder / "试玩说明.txt").write_text(
            f"烟山基地 {args.version}\n{args.notes}\n\n双击开始试玩.cmd即可启动游戏。\n",
            encoding="utf-8-sig",
        )
        override = ROOT / "docs" / f"v{args.version}-试玩说明.txt"
        if override.exists():
            shutil.copy2(override, folder / "试玩说明.txt")
        shutil.copy2(ROOT / "game/THIRD_PARTY.txt", folder)
        shutil.copytree(ROOT / "game/licenses", folder / "licenses", dirs_exist_ok=True)
        archive_path = ROOT / "playtest" / f"烟山基地试玩_v{args.version}_Windows.zip"
        with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for source in sorted(folder.rglob("*")):
                if source.is_file():
                    archive.write(source, source.relative_to(folder))
        result["files"] = [
            {"path": str(p.relative_to(ROOT)), "bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
            for p in [folder / "YanshanBase.exe", folder / "YanshanBase.pck", archive_path]
        ]
    (ROOT / "docs" / f"release-{args.version}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
