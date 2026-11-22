#!/usr/bin/env python3
"""Generate offline Chinese faction & boss voice pack (.ogg) for Yanshan Force v0.9.3.

Synthesizes 63 expressive Chinese dialogue lines across all enemy factions & bosses
(Ahsarah Guard, Captain Saeed, Warlord Reis, HAAVK Security, Yanshan Mistbound Clan,
Ironface Vanguard, Skyfall Overlord, and Yanxia Cave Acoustic Warden) using edge-tts
neural Chinese voices + tailored ffmpeg acoustic filters (radio bandpass for HAAVK,
valley majesty echo for Overlord, cavern resonance for Cave Warden).

Outputs:
  game/assets/voice_cn/*.ogg
  game/data/audio/cn_voice_manifest.json
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

import edge_tts

ROOT = pathlib.Path(__file__).resolve().parents[1]
GAME_DIR = ROOT / "game"
OUT_DIR = GAME_DIR / "assets" / "voice_cn"
MANIFEST_PATH = GAME_DIR / "data" / "audio" / "cn_voice_manifest.json"
CONCURRENCY = 5

PROFILES = {
    "ahsarah_guard": {
        "speaker": "阿萨拉卫队",
        "voice": "zh-CN-YunxiNeural",
        "rate": "+5%",
        "pitch": "-6Hz",
        "af": "highpass=f=120,equalizer=f=2400:t=q:w=1.2:g=2.5,loudnorm=I=-15:TP=-1.5:LRA=8",
    },
    "boss_saeed": {
        "speaker": "赤枭·赛伊德",
        "voice": "zh-CN-YunjianNeural",
        "rate": "+2%",
        "pitch": "-4Hz",
        "af": "highpass=f=95,equalizer=f=200:t=q:w=1.1:g=2.0,equalizer=f=2800:t=q:w=1.3:g=2.5,loudnorm=I=-14:TP=-1.2:LRA=9",
    },
    "boss_reis": {
        "speaker": "阿萨拉军阀·雷斯",
        "voice": "zh-CN-YunyangNeural",
        "rate": "-2%",
        "pitch": "-10Hz",
        "af": "highpass=f=85,equalizer=f=160:t=q:w=1.0:g=3.2,equalizer=f=2200:t=q:w=1.2:g=1.8,loudnorm=I=-14:TP=-1.2:LRA=9",
    },
    "haavk_trooper": {
        "speaker": "哈夫克特勤",
        "voice": "zh-CN-XiaoyiNeural",
        "rate": "+4%",
        "pitch": "-3Hz",
        "af": "highpass=f=360,lowpass=f=3200,acompressor=threshold=0.14:ratio=4.5:attack=8:release=80,equalizer=f=1600:t=q:w=1.4:g=3.0,loudnorm=I=-15:TP=-1.5:LRA=7",
    },
    "mistbound_soldier": {
        "speaker": "雾隐词兵",
        "voice": "zh-CN-YunxiNeural",
        "rate": "+3%",
        "pitch": "-2Hz",
        "af": "highpass=f=115,equalizer=f=2500:t=q:w=1.2:g=2.0,loudnorm=I=-15:TP=-1.5:LRA=8",
    },
    "boss_ironface": {
        "speaker": "雾隐先锋·铁面词卫",
        "voice": "zh-CN-YunjianNeural",
        "rate": "+0%",
        "pitch": "-6Hz",
        "af": "highpass=f=90,equalizer=f=180:t=q:w=1.0:g=2.8,loudnorm=I=-14:TP=-1.2:LRA=9",
    },
    "boss_overlord": {
        "speaker": "雾隐机关王·玄铁词尊",
        "voice": "zh-CN-YunyangNeural",
        "rate": "-5%",
        "pitch": "-12Hz",
        "af": "highpass=f=80,equalizer=f=150:t=q:w=1.0:g=3.5,aecho=0.85:0.76:48:0.24,loudnorm=I=-14:TP=-1.2:LRA=9",
    },
    "cave_warden": {
        "speaker": "古洞循音石卫",
        "voice": "zh-CN-YunyangNeural",
        "rate": "-10%",
        "pitch": "-18Hz",
        "af": "highpass=f=70,lowpass=f=2900,equalizer=f=130:t=q:w=1.0:g=4.0,aecho=0.85:0.80:75|145:0.34|0.18,loudnorm=I=-14:TP=-1.2:LRA=9",
    },
}

# (id, group, tag, subtitle_text, spoken_text_override_or_None)
LINES = [
    # 1. Ahsarah Guard Soldiers (8)
    ("ag_01", "ahsarah_guard", "proximity", "来！咱俩练练！", None),
    ("ag_02", "ahsarah_guard", "combat", "别让他们跑了，围上去！", None),
    ("ag_03", "ahsarah_guard", "combat", "守住防线，都给我顶上去！", None),
    ("ag_04", "ahsarah_guard", "proximity", "发现外来者！注意掩体，准备开火！", None),
    ("ag_05", "ahsarah_guard", "proximity", "阿萨拉的地盘，可不是你想来就来的！", None),
    ("ag_06", "ahsarah_guard", "combat", "快掩护我换位，别露破绽！", None),
    ("ag_07", "ahsarah_guard", "combat", "小心侧翼包抄，把词盾撑紧了！", None),
    ("ag_08", "ahsarah_guard", "proximity", "哟，还挺能躲的，咱俩接着练！", None),

    # 2. Captain Saeed — Normal Boss in Ahsarah (10)
    ("saeed_01", "boss_saeed", "intro", "父亲教导我，好的猎人懂得尊重猎物……但你，不配！", "父亲教导我，好的猎人懂得尊重猎物。但你，不配！"),
    ("saeed_02", "boss_saeed", "proximity", "我看到你了，小耗子！", None),
    ("saeed_03", "boss_saeed", "combat", "你掉进陷阱里了！", None),
    ("saeed_04", "boss_saeed", "proximity", "赤枭的领地，轮不到外来者撒野！", None),
    ("saeed_05", "boss_saeed", "skill_lmg", "M249 火力压制！看你往哪儿躲！", "M二四九火力压制！看你往哪儿躲！"),
    ("saeed_06", "boss_saeed", "skill_bolt", "尝尝我的燃烧弩箭，烧断你的退路！", None),
    ("saeed_07", "boss_saeed", "skill_smoke", "烟幕掩护，换位包抄！", None),
    ("saeed_08", "boss_saeed", "phase", "有两下子，居然破了我的词盾！", None),
    ("saeed_09", "boss_saeed", "proximity", "想带走曼德尔砖？先问问我手里的枪！", None),
    ("saeed_10", "boss_saeed", "combat", "还站得起来？那就继续，小耗子！", None),

    # 3. Warlord Reis — Confidential Boss in Ahsarah (10)
    ("reis_01", "boss_reis", "intro", "把留声机开大声点！没有交响乐的战场，简直粗俗不堪！", None),
    ("reis_02", "boss_reis", "proximity", "在阿萨拉，规矩由枪口和黄金说了算！", None),
    ("reis_03", "boss_reis", "skill_sonic", "听听这首交响乐，专为你的撤离倒计时准备的！", None),
    ("reis_04", "boss_reis", "skill_shotgun", "重甲突击！尝尝霰弹枪的滋味！", None),
    ("reis_05", "boss_reis", "skill_grenade", "送你三颗破片手雷，跟着节奏跳支舞吧！", None),
    ("reis_06", "boss_reis", "phase", "近卫们！出来好好招待一下我们的贵客！", None),
    ("reis_07", "boss_reis", "skill_ult", "零号大坝听令！重炮泄洪，全区覆盖！", None),
    ("reis_08", "boss_reis", "combat", "哈哈哈，居然撑过了零号大坝的炮火！", None),
    ("reis_09", "boss_reis", "proximity", "非洲之心，岂是你能轻易带走的？", None),
    ("reis_10", "boss_reis", "combat", "不错！你配听完这最后一曲！", None),

    # 4. HAAVK Security Troopers (8)
    ("haavk_01", "haavk_trooper", "proximity", "警告，未授权目标进入哈夫克管制区。", None),
    ("haavk_02", "haavk_trooper", "combat", "安保协议三级启动，展开全息词盾阵列。", None),
    ("haavk_03", "haavk_trooper", "combat", "监测到曼德尔砖异常信号，立即拦截目标。", None),
    ("haavk_04", "haavk_trooper", "proximity", "保护变电站核心资产，执行精准清除。", None),
    ("haavk_05", "haavk_trooper", "combat", "目标已锁定，请求无人机协同压制。", None),
    ("haavk_06", "haavk_trooper", "proximity", "哈夫克财产不容侵犯，立刻停止行动。", None),
    ("haavk_07", "haavk_trooper", "combat", "敌方具备识词破盾能力，提高警戒等级。", None),
    ("haavk_08", "haavk_trooper", "combat", "封锁撤退通道，严禁数据外泄。", None),

    # 5. Yanshan Mistbound Clan Soldiers (8)
    ("mb_01", "mistbound_soldier", "proximity", "站住！烟山重地，谁敢擅闯！", None),
    ("mb_02", "mistbound_soldier", "combat", "兄弟们，把词盾撑起来，别放他过桥！", None),
    ("mb_03", "mistbound_soldier", "combat", "好小子，有两下子，吃我一记！", None),
    ("mb_04", "mistbound_soldier", "proximity", "休想动诚庄留下的秘藏箱！", None),
    ("mb_05", "mistbound_soldier", "combat", "快掩护，往竹林那边绕后包抄！", None),
    ("mb_06", "mistbound_soldier", "combat", "英文认得挺溜，看你破不破得了这面盾！", None),
    ("mb_07", "mistbound_soldier", "proximity", "盯紧山道，有人摸上来了！", None),
    ("mb_08", "mistbound_soldier", "proximity", "小心点，这家伙枪法不赖！", None),

    # 6. Ironface Vanguard — Yanshan Normal Boss (7)
    ("iron_01", "boss_ironface", "intro", "想过云顶？先过我铁面词卫这一关！", None),
    ("iron_02", "boss_ironface", "phase2", "破一面盾算什么？双盾齐开！", None),
    ("iron_03", "boss_ironface", "phase3", "三盾困阵已成，看你认不认得清！", None),
    ("iron_04", "boss_ironface", "combat", "侦察蜂升空，封死他的走位！", None),
    ("iron_05", "boss_ironface", "proximity", "别光躲在石头后面，出来拼真本事！", None),
    ("iron_06", "boss_ironface", "skill", "重盾冲锋，接招！", None),
    ("iron_07", "boss_ironface", "combat", "好本事，看来今天遇到硬茬了！", None),

    # 7. Skyfall Overlord — Yanshan Confidential Boss (7)
    ("over_01", "boss_overlord", "proximity", "区区凡辈，也敢踏足云顶演武坛！", None),
    ("over_02", "boss_overlord", "intro", "雷云天降，玄铁词尊在此！", None),
    ("over_03", "boss_overlord", "skill", "玄铁法轮起，万词皆为我刃！", None),
    ("over_04", "boss_overlord", "phase2", "十息之内，若破不得三面金盾，便见识天地万象！", None),
    ("over_05", "boss_overlord", "skill_ult", "云海倒悬，镜像烟山——镇！", "云海倒悬，镜像烟山，镇！"),
    ("over_06", "boss_overlord", "combat", "竟能从天地万象下稳住阵脚，有点意思！", None),
    ("over_07", "boss_overlord", "combat", "来吧，看看你的词汇量够不够硬！", None),

    # 8. Yanxia Cave Acoustic Warden (5)
    ("cave_01", "cave_warden", "proximity", "擅入烟霞古洞者……止步！", "擅入烟霞古洞者，止步！"),
    ("cave_02", "cave_warden", "alert", "我听见你的脚步了……", "我听见你的脚步了。"),
    ("cave_03", "cave_warden", "alert", "屏息静气，也藏不住你的动静！", None),
    ("cave_04", "cave_warden", "skill_lance", "藏在暗处放冷枪？穿石声波——锁！", "藏在暗处放冷枪？穿石声波，锁！"),
    ("cave_05", "cave_warden", "proximity", "休想染指一线天后的次元石壁！", None),
]


async def synth_one(
    sem: asyncio.Semaphore,
    ffmpeg: str,
    line_id: str,
    group: str,
    subtitle: str,
    spoken: str,
    out_path: pathlib.Path,
    tmp_dir: pathlib.Path,
    overwrite: bool,
) -> tuple[str, bool]:
    if out_path.exists() and out_path.stat().st_size > 1200 and not overwrite:
        return line_id, False

    prof = PROFILES[group]
    async with sem:
        mp3_path = tmp_dir / f"{line_id}.mp3"
        last_err: Exception | None = None
        for attempt in range(4):
            try:
                comm = edge_tts.Communicate(
                    spoken,
                    prof["voice"],
                    rate=prof["rate"],
                    pitch=prof["pitch"],
                )
                await comm.save(str(mp3_path))
                if not mp3_path.exists() or mp3_path.stat().st_size < 400:
                    raise RuntimeError(f"Empty mp3 for {line_id}")
                cmd = [
                    ffmpeg, "-y", "-v", "error",
                    "-i", str(mp3_path),
                    "-af", prof["af"],
                    "-ac", "1", "-ar", "24000",
                    "-c:a", "libvorbis", "-q:a", "4",
                    str(out_path),
                ]
                subprocess.run(cmd, check=True)
                if mp3_path.exists():
                    mp3_path.unlink()
                if out_path.stat().st_size < 1200:
                    raise RuntimeError(f"Suspiciously small ogg for {line_id}")
                return line_id, True
            except Exception as exc:
                last_err = exc
                await asyncio.sleep(0.8 * (attempt + 1))
        raise RuntimeError(f"Failed synthesizing {line_id} ({subtitle!r}): {last_err}")


async def run_build(overwrite: bool) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg not found in PATH")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)

    sem = asyncio.Semaphore(CONCURRENCY)
    generated = 0
    reused = 0
    print(f"Synthesizing {len(LINES)} Chinese faction/boss offline voice lines...", flush=True)

    with tempfile.TemporaryDirectory(prefix="yanshan_cn_voice_") as td:
        tmp_dir = pathlib.Path(td)
        tasks = [
            synth_one(
                sem, ffmpeg, lid, grp, sub, (spk or sub),
                OUT_DIR / f"{lid}.ogg", tmp_dir, overwrite
            )
            for (lid, grp, _tag, sub, spk) in LINES
        ]
        done = 0
        total = len(tasks)
        for coro in asyncio.as_completed(tasks):
            _lid, was_new = await coro
            done += 1
            if was_new:
                generated += 1
            else:
                reused += 1
            if done % 15 == 0 or done == total:
                print(f"  Progress: {done}/{total} (new={generated}, reused={reused})", flush=True)

    entries: dict[str, dict] = {}
    groups: dict[str, list[str]] = {}
    total_bytes = 0
    for (lid, grp, tag, sub, _spk) in LINES:
        fname = f"{lid}.ogg"
        fpath = OUT_DIR / fname
        raw = fpath.read_bytes()
        total_bytes += len(raw)
        entries[lid] = {
            "id": lid,
            "group": grp,
            "speaker": PROFILES[grp]["speaker"],
            "tag": tag,
            "file": fname,
            "text": sub,
            "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest(),
        }
        groups.setdefault(grp, []).append(lid)

    manifest = {
        "schema_version": 1,
        "language": "zh-CN",
        "audio_format": "ogg_vorbis_mono_24khz",
        "usage_notice": "仅供个人与家庭离线教育试玩使用；对外公开分发前请通过 tools/build_cn_voice_pack.py 替换为开源语音或自录音频。",
        "count": len(entries),
        "total_bytes": total_bytes,
        "groups": groups,
        "entries": entries,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {MANIFEST_PATH.relative_to(ROOT)}: {len(entries)} clips, {total_bytes / (1024 * 1024):.2f} MB", flush=True)


if __name__ == "__main__":
    overwrite_flag = "--overwrite" in sys.argv
    asyncio.run(run_build(overwrite_flag))
