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


def gen_knife_slash() -> None:
    dur = 0.16
    n = int(SAMPLE_RATE * dur)
    out = []
    state = 1337
    for i in range(n):
        t = i / SAMPLE_RATE
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        noise = ((state / 0x3FFFFFFF) - 1.0)
        freq = 540.0 - 320.0 * (t / dur)
        env = _envelope(t, 0.012, dur, 2.1)
        s = 0.65 * noise * (0.4 + 0.6 * math.sin(math.pi * t / dur)) + 0.45 * math.sin(2 * math.pi * freq * t)
        out.append(s * env)
    _write_wav("knife_slash.wav", out, 0.46)


def gen_knife_hit() -> None:
    dur = 0.20
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.002, dur, 2.4)
        s = math.sin(2 * math.pi * 165.0 * math.exp(-t * 10.0) * t) + 0.55 * math.sin(2 * math.pi * 1950.0 * t) * math.exp(-t * 28.0)
        out.append(s * env)
    _write_wav("knife_hit.wav", out, 0.56)


def gen_dry_fire() -> None:
    dur = 0.075
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.001, dur, 3.8)
        s = math.sin(2 * math.pi * 2400.0 * t) * math.exp(-t * 45.0) + 0.5 * math.sin(2 * math.pi * 620.0 * t)
        out.append(s * env)
    _write_wav("dry_fire.wav", out, 0.36)


def gen_ammo_pickup() -> None:
    dur = 0.22
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        pulse = 1.0 if t < 0.09 else 0.85
        f = 720.0 if t < 0.09 else 1180.0
        env = _envelope(t % 0.095, 0.002, 0.09, 2.6) * pulse
        s = math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * f * 2.0 * t)
        out.append(s * env)
    _write_wav("ammo_pickup.wav", out, 0.44)


def gen_smoke_emp() -> None:
    dur = 0.52
    n = int(SAMPLE_RATE * dur)
    out = []
    state = 4242
    for i in range(n):
        t = i / SAMPLE_RATE
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        noise = ((state / 0x3FFFFFFF) - 1.0)
        env = _envelope(t, 0.008, dur, 1.45)
        zap = math.sin(2 * math.pi * (1400.0 * math.exp(-t * 4.5) + 180.0) * t)
        out.append((0.60 * noise + 0.45 * zap) * env)
    _write_wav("smoke_emp.wav", out, 0.50)


def gen_boss_phase() -> None:
    dur = 0.58
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.015, dur, 1.35)
        f = 130.0 - 45.0 * (t / dur)
        s = math.tanh((math.sin(2 * math.pi * f * t) + 0.65 * math.sin(2 * math.pi * f * 1.49 * t) + 0.35 * math.sin(2 * math.pi * 620.0 * t * math.exp(-t * 4.0))) * 1.5)
        out.append(s * env)
    _write_wav("boss_phase.wav", out, 0.54)


def gen_shot_suppressed() -> None:
    dur = 0.14
    n = int(SAMPLE_RATE * dur)
    out = []
    state = 777
    for i in range(n):
        t = i / SAMPLE_RATE
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        noise = ((state / 0x3FFFFFFF) - 1.0)
        env = _envelope(t, 0.002, dur, 2.8)
        thump = math.sin(2 * math.pi * (320.0 * math.exp(-t * 28.0) + 110.0) * t)
        out.append((0.55 * thump + 0.45 * noise) * env)
    _write_wav("shot_suppressed.wav", out, 0.48)


def gen_radio_scan() -> None:
    notes = [698.46, 880.0, 1174.66, 1396.91]
    dur = 0.52
    n = int(SAMPLE_RATE * dur)
    out = [0.0] * n
    for idx, freq in enumerate(notes):
        start = int(idx * 0.09 * SAMPLE_RATE)
        note_dur = 0.16
        for j in range(int(note_dur * SAMPLE_RATE)):
            if start + j >= n:
                break
            t = j / SAMPLE_RATE
            env = _envelope(t, 0.004, note_dur, 2.0)
            out[start + j] += (math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(4 * math.pi * freq * t)) * env
    _write_wav("radio_scan.wav", out, 0.50)


def gen_airdrop_call() -> None:
    dur = 0.65
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.008, dur, 1.5)
        f = 440.0 + 360.0 * min(1.0, t / 0.35)
        ping = math.sin(2 * math.pi * f * t) + 0.4 * math.sin(2 * math.pi * f * 1.5 * t)
        beeps = 1.0 if (t < 0.14 or t > 0.22) else 0.25
        out.append(ping * env * beeps)
    _write_wav("airdrop_call.wav", out, 0.52)


def gen_animal_flee() -> None:
    """Quick gentle rustle + nimble hop pitch rise when startling forest critters."""
    dur = 0.24
    n = int(SAMPLE_RATE * dur)
    out = []
    state = 9182
    for i in range(n):
        t = i / SAMPLE_RATE
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        noise = ((state / 0x3FFFFFFF) - 1.0)
        env = _envelope(t, 0.005, dur, 2.2)
        chirp = math.sin(2 * math.pi * (480.0 + 520.0 * (t / dur)) * t)
        out.append((0.48 * noise * (1.0 - 0.5 * (t / dur)) + 0.38 * chirp) * env)
    _write_wav("animal_flee.wav", out, 0.34)


def gen_animal_hit() -> None:
    """Soft puff + shimmer disappear chime when an animal is hit and vanishes."""
    dur = 0.32
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.004, dur, 2.0)
        f = 620.0 * math.exp(-t * 3.8) + 210.0
        tone = math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * f * 1.5 * t)
        out.append(tone * env)
    _write_wav("animal_hit.wav", out, 0.42)


def gen_flora_collect() -> None:
    """Bright herbal chime (E5-G#5-B5-E6) when studying/gathering wild flora."""
    notes = [659.25, 830.61, 987.77, 1318.51]
    dur = 0.42
    n = int(SAMPLE_RATE * dur)
    out = [0.0] * n
    for idx, freq in enumerate(notes):
        start = int(idx * 0.055 * SAMPLE_RATE)
        ndur = 0.19
        for j in range(int(ndur * SAMPLE_RATE)):
            if start + j >= n:
                break
            t = j / SAMPLE_RATE
            env = _envelope(t, 0.004, ndur, 2.2)
            out[start + j] += (math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(4 * math.pi * freq * t)) * env
    _write_wav("flora_collect.wav", out, 0.46)


def gen_boar_charge() -> None:
    """Brush rustle + double low guttural boar snort when a wild boar darts from bushes."""
    dur = 0.42
    n = int(SAMPLE_RATE * dur)
    out = []
    state = 5150
    for i in range(n):
        t = i / SAMPLE_RATE
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        noise = ((state / 0x3FFFFFFF) - 1.0)
        rustle = 0.35 * noise * _envelope(t, 0.008, 0.24, 1.6)
        # Two short low-frequency nasal grunts (0.02..0.17s and 0.19..0.38s)
        g1 = _envelope(t - 0.01, 0.015, 0.16, 1.8) if t >= 0.01 else 0.0
        g2 = _envelope(t - 0.18, 0.018, 0.21, 1.7) if t >= 0.18 else 0.0
        f = 112.0 - 24.0 * (t / dur) + 14.0 * math.sin(2 * math.pi * 26.0 * t)
        grunt = math.tanh((math.sin(2 * math.pi * f * t) + 0.65 * math.sin(2 * math.pi * f * 2.02 * t) + 0.35 * noise) * 1.9)
        out.append(rustle + 0.72 * grunt * (g1 + 0.9 * g2))
    _write_wav("boar_charge.wav", out, 0.50)


def gen_bird_flap() -> None:
    """Crisp woodland songbird two-note chirp + rapid feather wingbeat burst."""
    dur = 0.40
    n = int(SAMPLE_RATE * dur)
    out = []
    state = 7331
    for i in range(n):
        t = i / SAMPLE_RATE
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        noise = ((state / 0x3FFFFFFF) - 1.0)
        # Melodic high chirp (0..0.13s)
        c1 = _envelope(t, 0.004, 0.065, 2.0) * math.sin(2 * math.pi * (2150.0 + 650.0 * (t / 0.07)) * t)
        c2 = (_envelope(t - 0.065, 0.004, 0.075, 2.1) if t > 0.065 else 0.0) * math.sin(2 * math.pi * (2680.0 - 420.0 * ((t - 0.065) / 0.08)) * t)
        # 4 rapid wingbeats (14 Hz)
        beat = max(0.0, math.sin(2 * math.pi * 14.5 * t)) ** 2.2
        flap = 0.52 * noise * beat * _envelope(t - 0.03, 0.01, 0.35, 1.4) if t > 0.03 else 0.0
        out.append(0.46 * (c1 + c2) + flap)
    _write_wav("bird_flap.wav", out, 0.42)


def main() -> None:
    gen_hit_correct()
    gen_hit_wrong()
    gen_cipher_key()
    gen_cipher_unlock()
    gen_loot_epic()
    gen_warning_lock()
    gen_extract_pulse()
    gen_heal_shield()
    gen_knife_slash()
    gen_knife_hit()
    gen_dry_fire()
    gen_ammo_pickup()
    gen_smoke_emp()
    gen_boss_phase()
    gen_shot_suppressed()
    gen_radio_scan()
    gen_airdrop_call()
    gen_animal_flee()
    gen_animal_hit()
    gen_flora_collect()
    gen_boar_charge()
    gen_bird_flap()
    print("Generated 22 procedural SFX files in", OUT_DIR)


if __name__ == "__main__":
    main()
