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


def _make_noise(n: int, seed: int = 12345) -> list[float]:
    state = seed & 0x7FFFFFFF
    out = [0.0] * n
    for i in range(n):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        out[i] = (state / 0x3FFFFFFF) - 1.0
    return out


def _one_pole_lp(samples: list[float], cutoff_hz: float) -> list[float]:
    rc = 1.0 / (2.0 * math.pi * max(cutoff_hz, 20.0))
    dt = 1.0 / SAMPLE_RATE
    alpha = dt / (rc + dt)
    out = [0.0] * len(samples)
    y = 0.0
    for i, x in enumerate(samples):
        y += alpha * (x - y)
        out[i] = y
    return out


def _one_pole_hp(samples: list[float], cutoff_hz: float) -> list[float]:
    rc = 1.0 / (2.0 * math.pi * max(cutoff_hz, 20.0))
    dt = 1.0 / SAMPLE_RATE
    alpha = rc / (rc + dt)
    out = [0.0] * len(samples)
    y = 0.0
    prev_x = 0.0
    for i, x in enumerate(samples):
        y = alpha * (y + x - prev_x)
        prev_x = x
        out[i] = y
    return out


def gen_shot_rifle() -> None:
    """Realistic 5.56mm tactical carbine gunshot: supersonic crack + chamber punch + bolt clack + mountain valley slapback."""
    dur = 0.44
    n = int(SAMPLE_RATE * dur)
    raw_a = _make_noise(n, 55601)
    raw_b = _make_noise(n, 55609)
    crack_hi = _one_pole_hp(_one_pole_lp(raw_a, 5400.0), 820.0)
    body_mid = _one_pole_lp(raw_b, 920.0)
    tail_lp = _one_pole_lp(raw_a, 620.0)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        # 1) Sharp supersonic ballistic muzzle blast (0..28ms)
        env_crack = math.exp(-t * 108.0) * (min(1.0, t / 0.0006))
        crack = crack_hi[i] * env_crack * 2.35
        # 2) Resonant 5.56mm chamber low-mid punch (195Hz -> 48Hz)
        env_punch = math.exp(-t * 36.0) * min(1.0, t / 0.0012)
        f_punch = 48.0 + 155.0 * math.exp(-t * 42.0)
        punch = (math.sin(2.0 * math.pi * f_punch * t) + 0.65 * body_mid[i]) * env_punch * 1.45
        # 3) Crisp mechanical steel bolt-carrier clack at t = 14ms..42ms
        bolt = 0.0
        if 0.012 <= t <= 0.065:
            tb = t - 0.012
            eb = math.exp(-tb * 95.0)
            bolt = (math.sin(2.0 * math.pi * 2380.0 * tb) + 0.55 * math.sin(2.0 * math.pi * 4120.0 * tb)) * eb * 0.32
        # 4) Mountain-valley slapback reverb reflections (60ms, 128ms, 215ms)
        echo = 0.0
        for dly, amp in ((0.055, 0.34), (0.125, 0.22), (0.210, 0.12)):
            if t >= dly:
                te = t - dly
                echo += tail_lp[i] * math.exp(-te * 11.5) * amp
        out[i] = math.tanh((crack + punch + bolt + echo) * 1.45)
    _write_wav("shot_rifle.wav", out, 0.72)


def gen_shot_suppressed() -> None:
    """Realistic suppressed 5.56mm carbine: muted subsonic baffle puff + crisp steel bolt cycle + tight mechanical thump."""
    dur = 0.22
    n = int(SAMPLE_RATE * dur)
    raw = _make_noise(n, 7771)
    gas_puff = _one_pole_hp(_one_pole_lp(raw, 2900.0), 420.0)
    low_baffle = _one_pole_lp(raw, 480.0)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        # Tight baffled gas vent
        e_gas = math.exp(-t * 46.0) * min(1.0, t / 0.0014)
        gas = gas_puff[i] * e_gas * 1.25
        # Muted chamber thump
        e_thump = math.exp(-t * 58.0) * min(1.0, t / 0.001)
        f_sub = 74.0 + 130.0 * math.exp(-t * 65.0)
        thump = (math.sin(2.0 * math.pi * f_sub * t) * 0.78 + low_baffle[i] * 0.6) * e_thump
        # Audible metallic bolt-carrier snap (distinctive signature of a suppressed rifle!)
        bolt = 0.0
        if 0.009 <= t <= 0.075:
            tb = t - 0.009
            eb = math.exp(-tb * 82.0)
            bolt = (math.sin(2.0 * math.pi * 2650.0 * tb) + 0.65 * math.sin(2.0 * math.pi * 4350.0 * tb)) * eb * 0.52
        out[i] = math.tanh((gas + thump + bolt) * 1.35)
    _write_wav("shot_suppressed.wav", out, 0.60)


def gen_reload_mag_out() -> None:
    """Metallic magazine catch release + polymer mag sliding clear."""
    dur = 0.24
    n = int(SAMPLE_RATE * dur)
    raw = _one_pole_hp(_one_pole_lp(_make_noise(n, 8101), 3200.0), 650.0)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        click = (math.sin(2.0 * math.pi * 1850.0 * t) + 0.6 * math.sin(2.0 * math.pi * 3400.0 * t)) * math.exp(-t * 140.0) * 0.85
        slide = raw[i] * _envelope(t - 0.035, 0.02, 0.17, 1.8) * 0.55 if t >= 0.035 else 0.0
        out[i] = math.tanh((click + slide) * 1.3)
    _write_wav("reload_mag_out.wav", out, 0.52)


def gen_reload_mag_in() -> None:
    """Firm magazine seating thud + steel locking latch snap."""
    dur = 0.22
    n = int(SAMPLE_RATE * dur)
    raw = _one_pole_lp(_make_noise(n, 8102), 1600.0)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        thud = (math.sin(2.0 * math.pi * 165.0 * t) + 0.5 * raw[i]) * math.exp(-t * 52.0) * 0.9
        latch = 0.0
        if t >= 0.068:
            tl = t - 0.068
            latch = (math.sin(2.0 * math.pi * 2420.0 * tl) + 0.7 * math.sin(2.0 * math.pi * 4180.0 * tl)) * math.exp(-tl * 130.0) * 1.0
        out[i] = math.tanh((thud + latch) * 1.35)
    _write_wav("reload_mag_in.wav", out, 0.56)


def gen_reload_bolt() -> None:
    """Crisp two-stage steel bolt release slap / charging handle rack."""
    dur = 0.28
    n = int(SAMPLE_RATE * dur)
    raw = _one_pole_hp(_one_pole_lp(_make_noise(n, 8103), 4800.0), 1100.0)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        pull = (raw[i] * 0.65 + math.sin(2.0 * math.pi * 1950.0 * t) * 0.5) * math.exp(-t * 48.0) * 0.85
        slam = 0.0
        if t >= 0.095:
            ts = t - 0.095
            slam = (
                math.sin(2.0 * math.pi * 2850.0 * ts)
                + 0.75 * math.sin(2.0 * math.pi * 4680.0 * ts)
                + 0.55 * math.sin(2.0 * math.pi * 240.0 * ts)
                + 0.5 * raw[i]
            ) * math.exp(-ts * 75.0) * 1.1
        out[i] = math.tanh((pull + slam) * 1.35)
    _write_wav("reload_bolt.wav", out, 0.58)


def gen_shell_clink() -> None:
    """High-pitched spinning 5.56mm brass casing double bounce on bluestone."""
    dur = 0.26
    n = int(SAMPLE_RATE * dur)
    out = [0.0] * n
    for hit_t, amp in ((0.0, 0.9), (0.095, 0.45), (0.165, 0.22)):
        start = int(hit_t * SAMPLE_RATE)
        for j in range(int(0.08 * SAMPLE_RATE)):
            if start + j >= n:
                break
            t = j / SAMPLE_RATE
            env = math.exp(-t * 68.0)
            s = math.sin(2.0 * math.pi * 5120.0 * t) + 0.65 * math.sin(2.0 * math.pi * 7680.0 * t) + 0.35 * math.sin(2.0 * math.pi * 9840.0 * t)
            out[start + j] += s * env * amp
    _write_wav("shell_clink.wav", out, 0.34)


def gen_achievement_unlock() -> None:
    """Heroic Jiangnan gilded medal chime + crisp ascending triad shimmer."""
    dur = 0.88
    n = int(SAMPLE_RATE * dur)
    out = [0.0] * n
    notes = [(0.0, 523.25, 0.42), (0.09, 659.25, 0.46), (0.18, 783.99, 0.52), (0.28, 1046.50, 0.60), (0.28, 1567.98, 0.55)]
    for st, freq, ndur in notes:
        si = int(st * SAMPLE_RATE)
        for j in range(int(ndur * SAMPLE_RATE)):
            if si + j >= n:
                break
            t = j / SAMPLE_RATE
            env = _envelope(t, 0.006, ndur, 1.65)
            tone = math.sin(2.0 * math.pi * freq * t) + 0.38 * math.sin(4.0 * math.pi * freq * t) + 0.16 * math.sin(6.0 * math.pi * freq * t)
            out[si + j] += tone * env * 0.55
    _write_wav("achievement_unlock.wav", out, 0.60)


def gen_warden_sonar() -> None:
    """Haunting deep karst cavern acoustic pulse for Yanxia Cave Acoustic Warden."""
    dur = 0.78
    n = int(SAMPLE_RATE * dur)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.018, dur, 1.45)
        f1 = 115.0 + 265.0 * math.exp(-t * 5.2)
        f2 = 540.0 + 420.0 * math.exp(-t * 7.5)
        pulse = math.sin(2.0 * math.pi * f1 * t) * 0.8 + math.sin(2.0 * math.pi * f2 * t) * 0.36 * math.exp(-t * 3.8)
        wobble = 0.82 + 0.18 * math.sin(2.0 * math.pi * 16.0 * t)
        out[i] = math.tanh(pulse * wobble * 1.4) * env
    _write_wav("warden_sonar.wav", out, 0.62)


def gen_boss_skyfall() -> None:
    """Descending turbine shriek (0..0.42s) into seismic earth-shattering iron landing slam (0.42..1.35s)."""
    dur = 1.35
    n = int(SAMPLE_RATE * dur)
    raw = _make_noise(n, 9988)
    rumble_lp = _one_pole_lp(raw, 280.0)
    shriek_bp = _one_pole_hp(_one_pole_lp(raw, 2600.0), 600.0)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        if t < 0.42:
            u = t / 0.42
            f_wh = 980.0 - 640.0 * u
            wh = (math.sin(2.0 * math.pi * f_wh * t) * 0.42 + shriek_bp[i] * 0.55) * (u ** 1.4)
            out[i] = wh * 0.72
        else:
            ti = t - 0.42
            env_sub = math.exp(-ti * 3.2) * min(1.0, ti / 0.004)
            f_sub = 38.0 + 125.0 * math.exp(-ti * 14.0)
            impact = (math.sin(2.0 * math.pi * f_sub * ti) * 1.35 + rumble_lp[i] * 1.65) * env_sub
            clang = (math.sin(2.0 * math.pi * 620.0 * ti) + 0.6 * math.sin(2.0 * math.pi * 945.0 * ti)) * math.exp(-ti * 11.0) * 0.45
            out[i] = math.tanh((impact + clang) * 1.5)
    _write_wav("boss_skyfall.wav", out, 0.74)


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


def gen_loot_scan_tick() -> None:
    """Crisp tactical magnifying-glass sonar tick during container slot inspection."""
    dur = 0.065
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.002, dur, 3.0)
        freq = 1280.0 + 360.0 * (t / dur)
        s = math.sin(2 * math.pi * freq * t) + 0.30 * math.sin(2 * math.pi * freq * 2.0 * t)
        out.append(s * env)
    _write_wav("loot_scan_tick.wav", out, 0.34)


def gen_loot_reveal_common() -> None:
    """Clean mechanical card-flip & latch snap for Common/Uncommon loot reveal."""
    dur = 0.14
    n = int(SAMPLE_RATE * dur)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.003, dur, 2.5)
        f = 740.0 if t < 0.045 else 987.77
        s = math.sin(2 * math.pi * f * t) + 0.25 * math.sin(2 * math.pi * f * 1.5 * t)
        out.append(s * env)
    _write_wav("loot_reveal_common.wav", out, 0.40)


def gen_loot_reveal_rare() -> None:
    """Shimmering crystalline triad chime for Blue Rare / Purple Epic loot reveal."""
    notes = [659.25, 830.61, 987.77, 1318.51]
    dur = 0.46
    n = int(SAMPLE_RATE * dur)
    out = [0.0] * n
    for idx, freq in enumerate(notes):
        start = int(idx * 0.052 * SAMPLE_RATE)
        ndur = dur - idx * 0.052
        for j in range(int(ndur * SAMPLE_RATE)):
            if start + j >= n:
                break
            t = j / SAMPLE_RATE
            env = _envelope(t, 0.004, ndur, 1.8)
            out[start + j] += (math.sin(2 * math.pi * freq * t) + 0.32 * math.sin(4 * math.pi * freq * t)) * env
    _write_wav("loot_reveal_rare.wav", out, 0.48)


def gen_loot_mythic_red() -> None:
    """Exhilarating Delta-Force-style '出大红！' sub-bass impact + triumphant radiant brass/bell chord fanfare."""
    dur = 1.08
    n = int(SAMPLE_RATE * dur)
    out = [0.0] * n
    # 1) Heartbeat sub-bass drop (0.0 .. 0.32s)
    for i in range(int(0.35 * SAMPLE_RATE)):
        t = i / SAMPLE_RATE
        env = _envelope(t, 0.006, 0.35, 1.7)
        f_sub = 138.0 - 68.0 * (t / 0.35)
        out[i] += 0.85 * math.tanh(math.sin(2 * math.pi * f_sub * t) * 1.8) * env
    # 2) Ascending crimson-gold fanfare arpeggio + shimmering sustain chord
    fanfare = [
        (0.05, 587.33, 0.42),
        (0.12, 739.99, 0.45),
        (0.19, 880.00, 0.50),
        (0.27, 1174.66, 0.78),
        (0.35, 1479.98, 0.72),
        (0.35, 1760.00, 0.72),
        (0.35, 587.33, 0.70),
    ]
    for start_s, freq, ndur in fanfare:
        start = int(start_s * SAMPLE_RATE)
        for j in range(int(ndur * SAMPLE_RATE)):
            if start + j >= n:
                break
            t = j / SAMPLE_RATE
            env = _envelope(t, 0.008, ndur, 1.35)
            tone = (
                math.sin(2 * math.pi * freq * t)
                + 0.42 * math.sin(4 * math.pi * freq * t)
                + 0.18 * math.sin(6 * math.pi * freq * t)
            )
            out[start + j] += 0.55 * tone * env
    _write_wav("loot_mythic_red.wav", out, 0.62)


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
    gen_shot_rifle()
    gen_shot_suppressed()
    gen_reload_mag_out()
    gen_reload_mag_in()
    gen_reload_bolt()
    gen_shell_clink()
    gen_achievement_unlock()
    gen_warden_sonar()
    gen_boss_skyfall()
    gen_radio_scan()
    gen_airdrop_call()
    gen_animal_flee()
    gen_animal_hit()
    gen_flora_collect()
    gen_boar_charge()
    gen_bird_flap()
    gen_loot_scan_tick()
    gen_loot_reveal_common()
    gen_loot_reveal_rare()
    gen_loot_mythic_red()
    print("Generated 34 procedural SFX files in", OUT_DIR)


if __name__ == "__main__":
    main()
