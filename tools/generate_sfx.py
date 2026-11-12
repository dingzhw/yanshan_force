"""Generate crisp, zero-dependency 16-bit PCM WAV sound effects for v0.5+."""
from pathlib import Path
import math
import struct
import wave

SAMPLE_RATE = 44100
OUT_DIR = Path(__file__).resolve().parents[1] / "game/assets/sfx"


def _envelope(t: float, attack: float, duration: float, decay_power: float = 2.0) -> float:
    if t < 0.0 or t > duration:
        return 0.0
    if t < attack:
        return t / max(attack, 1e-5)
    rem = 1.0 - (t - attack) / max(duration - attack, 1e-5)
    return max(0.0, rem) ** decay_power


def _write_wav(name: str, samples: list[float], gain: float = 0.55) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    peak = max((abs(s) for s in samples), default=1.0)
    scale = (32767.0 * gain) / max(peak, 1e-5)
    path = OUT_DIR / name
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for s in samples:
            val = max(-32767, min(32767, int(s * scale)))
            frames.extend(struct.pack("<h", val))
        wf.writeframes(bytes(frames))


def gen_hit_correct() -> None:
    dur = 0.26
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        f1 = 880.0 if t < 0.075 else 1318.5
        env = _envelope(t, 0.004, dur, 2.2)
        s = math.sin(2 * math.pi * f1 * t) + 0.35 * math.sin(2 * math.pi * f1 * 2.0 * t)
        out.append(s * env)
    _write_wav("hit_correct.wav", out, 0.5)


def gen_hit_wrong() -> None:
    dur = 0.30
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        f = 230.0 - 75.0 * (t / dur)
        env = _envelope(t, 0.005, dur, 1.6)
        raw = math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * (f * 1.48) * t)
        # Soft square-ish buzz
        s = math.tanh(raw * 1.8)
        out.append(s * env)
    _write_wav("hit_wrong.wav", out, 0.48)


def gen_cipher_key() -> None:
    dur = 0.045
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.001, dur, 3.5)
        s = math.sin(2 * math.pi * 1450.0 * t) + 0.4 * math.sin(2 * math.pi * 2900.0 * t)
        out.append(s * env)
    _write_wav("cipher_key.wav", out, 0.32)


def gen_cipher_unlock() -> None:
    notes = [523.25, 659.25, 783.99, 1046.50]
    dur = 0.48
    n = int(SAMPLE_RATE * dur)
    out = [0.0] * n
    for idx, freq in enumerate(notes):
        start = int(idx * 0.075 * SAMPLE_RATE)
        note_dur = dur - idx * 0.075
        for j in range(int(note_dur * SAMPLE_RATE)):
            if start + j >= n:
                break
            t = j / SAMPLE_RATE
            env = _envelope(t, 0.005, note_dur, 1.9)
            out[start + j] += (math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(4 * math.pi * freq * t)) * env
    _write_wav("cipher_unlock.wav", out, 0.52)


def gen_loot_epic() -> None:
    notes = [587.33, 739.99, 880.0, 1174.66, 1479.98]
    dur = 0.68
    n = int(SAMPLE_RATE * dur)
    out = [0.0] * n
    for idx, freq in enumerate(notes):
        start = int(idx * 0.065 * SAMPLE_RATE)
        note_dur = dur - idx * 0.065
        for j in range(int(note_dur * SAMPLE_RATE)):
            if start + j >= n:
                break
            t = j / SAMPLE_RATE
            env = _envelope(t, 0.006, note_dur, 1.5)
            out[start + j] += (math.sin(2 * math.pi * freq * t) + 0.35 * math.sin(4 * math.pi * freq * t)) * env
    _write_wav("loot_epic.wav", out, 0.55)


def gen_warning_lock() -> None:
    dur = 0.24
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        pulse = 1.0 if (t < 0.085 or (0.125 < t < 0.21)) else 0.0
        env = _envelope(t % 0.125, 0.003, 0.09, 1.4) * pulse
        s = math.sin(2 * math.pi * 960.0 * t) + 0.25 * math.sin(2 * math.pi * 1920.0 * t)
        out.append(s * env)
    _write_wav("warning_lock.wav", out, 0.42)


def gen_extract_pulse() -> None:
    dur = 0.35
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.01, dur, 2.4)
        freq = 660.0 + 180.0 * (t / dur)
        s = math.sin(2 * math.pi * freq * t)
        out.append(s * env)
    _write_wav("extract_pulse.wav", out, 0.38)


def gen_heal_shield() -> None:
    dur = 0.36
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.015, dur, 1.7)
        freq = 440.0 + 440.0 * (t / dur)
        s = math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(2 * math.pi * freq * 1.5 * t)
        out.append(s * env)
    _write_wav("heal_shield.wav", out, 0.44)


def main() -> None:
    gen_hit_correct()
    gen_hit_wrong()
    gen_cipher_key()
    gen_cipher_unlock()
    gen_loot_epic()
    gen_warning_lock()
    gen_extract_pulse()
    gen_heal_shield()
    print("Generated 8 procedural SFX files in", OUT_DIR)


if __name__ == "__main__":
    main()
