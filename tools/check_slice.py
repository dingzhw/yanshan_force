"""Run Godot integration checks with QA profiles; retain explicit failures/logs."""
from pathlib import Path
import subprocess
import json
import argparse
import re
import sys
import os

ROOT = Path(__file__).resolve().parents[1]


def _load_runtime() -> dict:
    cfg = ROOT / "docs/runtime-local.json"
    if cfg.exists():
        return json.loads(cfg.read_text(encoding="utf-8"))
    rt = Path(os.environ.get("DRZ_RUNTIME") or (Path(os.environ.get("LOCALAPPDATA") or (Path.home() / "AppData/Local")) / "Temp/drz-english-shooter-20261103"))
    engine = rt / "godot-4.7.2"
    return {
        "runtime_root": str(rt),
        "console_executable": str(engine / "Godot_v4.7.2-stable_win64_console.exe"),
        "python_used": sys.executable,
        "game_working_copy": str(rt / "yanshan-v01"),
    }


runtime = _load_runtime()

p = argparse.ArgumentParser()
p.add_argument("tests", nargs="+")
p.add_argument("--stage", action="store_true")
p.add_argument("--ver", default="0.5.2")
args = p.parse_args()

ver_tag = "v" + args.ver.replace(".", "")
qa_appdata = Path(runtime["runtime_root"]) / "qa-appdata"
(qa_appdata / "Godot").mkdir(parents=True, exist_ok=True)

base_env = os.environ.copy()
base_env["APPDATA"] = str(qa_appdata)
base_env["LOCALAPPDATA"] = str(qa_appdata)

if args.stage:
    subprocess.run([runtime["python_used"], str(ROOT / "tools/build_playtest.py")], check=True, env=base_env)
    imported = subprocess.run(
        [runtime["console_executable"], "--headless", "--path", runtime["game_working_copy"], "--editor", "--import", "--quit"],
        capture_output=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
        env=base_env,
    )
    (ROOT / f"docs/{ver_tag}-import.log").write_text(imported.stdout + "\n" + imported.stderr, encoding="utf-8")
    print("IMPORT_EXIT", imported.returncode, flush=True)
    if imported.returncode or "SCRIPT ERROR:" in imported.stderr:
        raise RuntimeError(f"Godot import failed; inspect {ver_tag}-import.log")

out = ROOT / "docs" / f"{ver_tag}-checks"
out.mkdir(parents=True, exist_ok=True)
results = []

for name in args.tests:
    command = (
        [runtime["console_executable"]]
        + ([] if (name.startswith("capture_") or name in ["slice_visual", "terrain_render"]) else ["--headless"])
        + ["--path", runtime["game_working_copy"], "--script", f"res://tests/{name}.gd", "--", "--qa"]
    )
    if name == "hardware-tour":
        command = [runtime["console_executable"], "--path", runtime["game_working_copy"], "--", "--qa", "--hardware-check", "--auto-quit", "--low-quality"]
    if name == "packaged-tour":
        command = [str(ROOT / f"playtest/windows-v{args.ver}/YanshanBase.exe"), "--log-file", str(out / "packaged-engine.log"), "--", "--qa", "--hardware-check", "--auto-quit", "--low-quality"]

    env = base_env.copy()
    screenshots = ROOT / "docs" / "screenshots" / ver_tag
    screenshots.mkdir(parents=True, exist_ok=True)
    env["DRZ_SCREENSHOT_DIR"] = str(screenshots)
    diagnostics = ROOT / "docs" / "diagnostics" / ver_tag
    diagnostics.mkdir(parents=True, exist_ok=True)
    env["DRZ_DIAGNOSTICS_DIR"] = str(diagnostics)

    try:
        r = subprocess.run(
            command,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=180,
            env=env,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        text = r.stdout + "\n" + r.stderr
        if name == "packaged-tour" and "PERFORMANCE_REPORT " not in text and (out / "packaged-engine.log").exists():
            text += "\n" + (out / "packaged-engine.log").read_text(encoding="utf-8", errors="replace")
        (out / (name + ".log")).write_text(text, encoding="utf-8")
        failures = [line for line in text.splitlines() if re.search(r"^FAIL |SCRIPT ERROR:|Parse Error:|Assertion failed", line)]
        entry = {
            "test": name,
            "exit_code": r.returncode,
            "passes": len(re.findall(r"^PASS ", text, re.M)),
            "failures": failures,
            "summary": [line for line in text.splitlines() if "CHECKS" in line or "LIVE_ROUND" in line],
        }
        if name in ["hardware-tour", "packaged-tour"]:
            report = re.search(r"^PERFORMANCE_REPORT (\{.*\})$", text, re.M)
            entry["report"] = json.loads(report.group(1)) if report else None
            if not entry["report"] or not entry["report"].get("route_and_extraction_passed"):
                entry["failures"].append("Complete performance-tour result missing or not passed")
    except subprocess.TimeoutExpired as e:
        text = (e.stdout or b"").decode("utf-8", errors="replace") if isinstance(e.stdout, bytes) else str(e.stdout)
        (out / (name + ".log")).write_text(text, encoding="utf-8")
        entry = {"test": name, "error": "timeout", "tail": text[-2400:]}

    print(json.dumps(entry, ensure_ascii=False), flush=True)
    results.append(entry)
    if entry.get("exit_code", 1) != 0 or entry.get("failures"):
        break

(out / ("run-" + args.tests[0] + ".json")).write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
sys.exit(0 if all(r.get("exit_code", 1) == 0 and not r.get("failures") for r in results) else 1)
