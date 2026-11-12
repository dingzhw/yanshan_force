"""Create immutable local source checkpoints and standalone Windows releases."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def checkpoint(version):
    dest = ROOT / "docs/checkpoints" / f"source-{version}.zip"
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        raise RuntimeError(f"Preserving existing checkpoint: {dest}")
    with zipfile.ZipFile(dest, "x", zipfile.ZIP_DEFLATED) as archive:
        for source in sorted((ROOT / "game").rglob("*")):
            if source.is_file() and source.suffix in {".gd", ".godot", ".cfg", ".tscn", ".json", ".txt"}:
                archive.write(source, source.relative_to(ROOT))
    return str(dest.relative_to(ROOT))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--checkpoint-only", action="store_true")
    parser.add_argument("--notes", default="")
    args = parser.parse_args()
    result = {"version": args.version, "source_checkpoint": checkpoint(args.version)}
    if not args.checkpoint_only:
        runtime = json.loads((ROOT / "docs/runtime-local.json").read_text(encoding="utf-8"))
        subprocess.run([runtime["python_used"], str(ROOT / "tools/build_playtest.py")], check=True)
        folder = ROOT / "playtest" / ("windows-v" + args.version)
        if folder.exists():
            raise RuntimeError(f"Preserving existing release: {folder}")
        folder.mkdir()
        command = [runtime["console_executable"], "--headless", "--path", runtime["game_working_copy"], "--editor", "--import", "--quit"]
        with (ROOT / "docs" / f"v{args.version}-import.log").open("w", encoding="utf-8") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
        with (ROOT / "docs" / f"v{args.version}-export.log").open("w", encoding="utf-8") as log:
            subprocess.run([runtime["console_executable"], "--headless", "--path", runtime["game_working_copy"], "--export-release", "Windows Desktop", str(folder / "YanshanBase.exe")], stdout=log, stderr=subprocess.STDOUT, check=True)
        (folder / "开始试玩.cmd").write_bytes(b'@echo off\r\nstart "" "%~dp0YanshanBase.exe"\r\n')
        (folder / "性能巡检.cmd").write_bytes(b'@echo off\r\nsetlocal\r\nset "DRZ_DIAGNOSTICS_DIR=%~dp0diagnostics"\r\nstart "" "%~dp0YanshanBase.exe" -- --qa --hardware-check\r\n')
        (folder / "试玩说明.txt").write_text(f"烟山基地 {args.version}\n{args.notes}\n\n双击开始试玩.cmd。请先退出旧游戏。\nWASD/方向键移动，Shift奔跑，空格跳跃，左键射击，右键瞄准，R换弹，E交互，Esc暂停，F12截图。\n存档沿用原路径。现实奖励积分由家长线下兑现。\n\n玩法：绿色终端旁按E激活挑战；沿山路探索营地、林间、怪石区，再到小地图绿色圆圈撤离。普通箱需答5题且正确率70%；高级箱需答10题且正确率85%；100分即可撤离，圈内按E并停留3秒。\n\n目标电脑验收：关闭其他游戏，双击性能巡检.cmd，等待自动走完山路。巡检不保存游戏进度，结果在旁边diagnostics文件夹。请保留JSON报告，用于确认Vega 8实际帧率。\n", encoding="utf-8-sig")
        override = ROOT / "docs" / f"v{args.version}-试玩说明.txt"
        if override.exists():
            shutil.copy2(override, folder / "试玩说明.txt")
        if args.version == "0.4.0":
            (folder / "低负载启动.cmd").write_bytes(b'@echo off\r\nstart "" "%~dp0YanshanBase.exe" -- --low-quality\r\n')
            (folder / "性能巡检.cmd").write_bytes(b'@echo off\r\nsetlocal\r\nset "DRZ_DIAGNOSTICS_DIR=%~dp0diagnostics"\r\nstart "" "%~dp0YanshanBase.exe" -- --qa --hardware-check --low-quality\r\n')
        shutil.copy2(ROOT / "game/THIRD_PARTY.txt", folder)
        shutil.copytree(ROOT / "game/licenses", folder / "licenses")
        archive_path = ROOT / "playtest" / f"烟山基地试玩_v{args.version}_Windows.zip"
        with zipfile.ZipFile(archive_path, "x", zipfile.ZIP_DEFLATED) as archive:
            for source in sorted(folder.rglob("*")):
                if source.is_file():
                    archive.write(source, source.relative_to(folder))
        result["files"] = [{"path": str(p.relative_to(ROOT)), "bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in [folder / "YanshanBase.exe", folder / "YanshanBase.pck", archive_path]]
    (ROOT / "docs" / f"release-{args.version}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
