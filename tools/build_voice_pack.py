#!/usr/bin/env python3
"""Generate offline US natural female English (.ogg) voice pack for Yanshan Force.

Collects all spoken English strings from wordpacks, textbook sentences,
exploration prompts, loot collectibles, and wildlife definitions, synthesizes
each unique normalized phrase using edge-tts (en-US-JennyNeural), converts to
24kHz mono OGG Vorbis via ffmpeg, and writes game/data/learning/voice_manifest.json.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

import edge_tts

ROOT = pathlib.Path(__file__).resolve().parents[1]
GAME_DIR = ROOT / "game"
VOICE_DIR = GAME_DIR / "assets" / "voice"
MANIFEST_PATH = GAME_DIR / "data" / "learning" / "voice_manifest.json"

VOICE_NAME = "en-US-JennyNeural"
VOICE_RATE = "-5%"
CONCURRENCY = 6


def normalize_key(text: str) -> str:
    s = (
        text.replace("...", " ")
        .replace("…", " ")
        .replace("’", "'")
        .replace("‘", "'")
    )
    s = re.sub(r"\s+", " ", s).strip()
    return s.lower()


def clean_spoken_text(text: str) -> str:
    s = (
        text.replace("...", " ")
        .replace("…", " ")
        .replace("’", "'")
        .replace("‘", "'")
    )
    return re.sub(r"\s+", " ", s).strip()


def collect_spoken_entries() -> dict[str, dict]:
    entries: dict[str, dict] = {}

    def register(raw_text: str, tag: str) -> None:
        key = normalize_key(raw_text)
        if not key:
            return
        spoken = clean_spoken_text(raw_text)
        if key not in entries:
            entries[key] = {"text": spoken, "sources": [tag]}
        elif tag not in entries[key]["sources"]:
            entries[key]["sources"].append(tag)

    for path in sorted((GAME_DIR / "data" / "wordpacks").glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for item in data.get("entries", []):
            if item.get("english"):
                register(str(item["english"]), "wordpack")

    for path in sorted((GAME_DIR / "data" / "learning").glob("*.json")):
        if path.name == "voice_manifest.json":
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        for item in data.get("entries", []):
            if item.get("english"):
                register(str(item["english"]), "sentence")

    for path in sorted((GAME_DIR / "data" / "exploration").glob("*.json")):
        txt = path.read_text(encoding="utf-8")
        for m in re.findall(r'"tts"\s*:\s*"([^"]+)"', txt):
            register(m, "exploration")

    rules_txt = (GAME_DIR / "scripts" / "rules.gd").read_text(encoding="utf-8")
    for m in re.findall(r'"en"\s*:\s*"([^"]+)"', rules_txt):
        register(m, "loot")

    wild_txt = (GAME_DIR / "scripts" / "wildlife.gd").read_text(encoding="utf-8")
    for m in re.findall(r'"tts"\s*:\s*"([^"]+)"', wild_txt):
        register(m, "wildlife")

    for gd_path in sorted((GAME_DIR / "scripts").glob("*.gd")):
        txt = gd_path.read_text(encoding="utf-8")
        for m in re.findall(r'speak_english\("([^"]+)"\)', txt):
            register(m, "script")

    return dict(sorted(entries.items()))


def file_for_key(key: str) -> str:
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]
    return f"v_{digest}.ogg"


async def synth_one(
    sem: asyncio.Semaphore,
    ffmpeg: str,
    key: str,
    spoken: str,
    out_path: pathlib.Path,
    tmp_dir: pathlib.Path,
    overwrite: bool,
) -> tuple[str, bool]:
    if out_path.exists() and out_path.stat().st_size > 800 and not overwrite:
        return key, False

    async with sem:
        mp3_path = tmp_dir / (out_path.stem + ".mp3")
        last_err: Exception | None = None
        for attempt in range(4):
            try:
                comm = edge_tts.Communicate(spoken, VOICE_NAME, rate=VOICE_RATE)
                await comm.save(str(mp3_path))
                if not mp3_path.exists() or mp3_path.stat().st_size < 400:
                    raise RuntimeError(f"Empty mp3 output for {spoken!r}")
                subprocess.run(
                    [
                        ffmpeg,
                        "-y",
                        "-v",
                        "error",
                        "-i",
                        str(mp3_path),
                        "-ac",
                        "1",
                        "-ar",
                        "24000",
                        "-c:a",
                        "libvorbis",
                        "-q:a",
                        "4",
                        str(out_path),
                    ],
                    check=True,
                )
                if mp3_path.exists():
                    mp3_path.unlink()
                if out_path.stat().st_size < 800:
                    raise RuntimeError(f"Suspiciously small ogg for {spoken!r}")
                return key, True
            except Exception as exc:
                last_err = exc
                await asyncio.sleep(0.8 * (attempt + 1))
        raise RuntimeError(f"Failed synthesizing {spoken!r}: {last_err}")


async def run_build(overwrite: bool) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg not found in PATH")

    VOICE_DIR.mkdir(parents=True, exist_ok=True)
    collected = collect_spoken_entries()
    print(f"Collected {len(collected)} unique English phrases for {VOICE_NAME} ({VOICE_RATE})")

    sem = asyncio.Semaphore(CONCURRENCY)
    generated = 0
    reused = 0

    with tempfile.TemporaryDirectory(prefix="yanshan_voice_") as td:
        tmp_dir = pathlib.Path(td)
        tasks = [
            synth_one(sem, ffmpeg, k, meta["text"], VOICE_DIR / file_for_key(k), tmp_dir, overwrite)
            for k, meta in collected.items()
        ]
        done = 0
        total = len(tasks)
        for coro in asyncio.as_completed(tasks):
            _key, was_new = await coro
            done += 1
            if was_new:
                generated += 1
            else:
                reused += 1
            if done % 40 == 0 or done == total:
                print(f"  Progress: {done}/{total} (new={generated}, reused={reused})", flush=True)

    # Remove stale orphan .ogg files no longer in manifest
    expected_files = {file_for_key(k) for k in collected}
    for existing in VOICE_DIR.glob("v_*.ogg"):
        if existing.name not in expected_files:
            existing.unlink()

    manifest_entries: dict[str, dict] = {}
    total_bytes = 0
    for key, meta in collected.items():
        fname = file_for_key(key)
        fpath = VOICE_DIR / fname
        raw = fpath.read_bytes()
        total_bytes += len(raw)
        manifest_entries[key] = {
            "file": fname,
            "text": meta["text"],
            "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
        }

    manifest = {
        "schema_version": 1,
        "voice_name": VOICE_NAME,
        "accent": "en-US",
        "rate": VOICE_RATE,
        "audio_format": "ogg_vorbis_mono_24khz",
        "usage_notice": "仅供个人与家庭离线英语学习使用；若对外公开分发，请通过 tools/build_voice_pack.py 替换为已获公开分发许可的开源离线语音或自录音频。",
        "count": len(manifest_entries),
        "total_bytes": total_bytes,
        "entries": manifest_entries,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {MANIFEST_PATH.relative_to(ROOT)}: {len(manifest_entries)} clips, {total_bytes / (1024 * 1024):.2f} MB")


if __name__ == "__main__":
    overwrite_flag = "--overwrite" in sys.argv
    asyncio.run(run_build(overwrite_flag))
