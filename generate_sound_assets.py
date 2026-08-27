#!/usr/bin/env python3
"""Procedurally generate the full SystemTest sound set as highly packed OGG/Vorbis.

Every .ogg shipped with the game (default node/tool/footstep sounds, MVP assets,
scary mod cues, GUI stingers, ambience and menu music) is synthesised here so the
game carries no third-party default audio.  Output is deterministic:

  * mono, 22050 Hz (16 kHz for long ambience/music beds)
  * Vorbis with a low quality target -> small files, fast to stream
  * peak-normalised with short fades so nothing clicks

Run:  python3 generate_sound_assets.py
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parent
SR = 22050          # sample rate for one-shot SFX
SR_LONG = 16000     # sample rate for long loops (music / ambience)
Q_SFX = 0.05        # vorbis quality for short SFX (very small)
Q_LONG = 0.15       # slightly better for long beds

rng = np.random.default_rng(20260827)


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def t(dur: float, sr: int = SR) -> np.ndarray:
    return np.linspace(0.0, dur, max(1, int(sr * dur)), endpoint=False)


def noise(dur: float, sr: int = SR) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, max(1, int(sr * dur)))


def env(x: np.ndarray, attack: float = 0.005, decay: float = 0.0,
        power: float = 2.0, sr: int = SR) -> np.ndarray:
    n = len(x)
    e = np.ones(n)
    a = max(1, int(attack * sr))
    e[:a] = np.linspace(0.0, 1.0, a)
    d = n - a
    if d > 0:
        tail = np.linspace(0.0, 1.0, d)
        if decay <= 0:
            e[a:] = (1.0 - tail) ** power
        else:
            e[a:] = np.exp(-tail * (n / sr) / max(1e-4, decay))
    return x * e


def lowpass(x: np.ndarray, cutoff: float, sr: int = SR) -> np.ndarray:
    """One-pole low pass."""
    a = math.exp(-2.0 * math.pi * cutoff / sr)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x: np.ndarray, cutoff: float, sr: int = SR) -> np.ndarray:
    return x - lowpass(x, cutoff, sr)


def bandpass(x: np.ndarray, low: float, high: float, sr: int = SR) -> np.ndarray:
    return highpass(lowpass(x, high, sr), low, sr)


def resonator(x: np.ndarray, freq: float, q: float = 40.0, sr: int = SR) -> np.ndarray:
    """Simple two-pole resonant filter, used for metallic / glassy rings."""
    w = 2.0 * math.pi * freq / sr
    r = math.exp(-w / (2.0 * q))
    a1 = 2.0 * r * math.cos(w)
    a2 = -r * r
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    for i, v in enumerate(x):
        cur = v + a1 * y1 + a2 * y2
        y[i] = cur
        y2, y1 = y1, cur
    return y * (1.0 - r)


def sine(freq, dur: float, sr: int = SR, phase: float = 0.0) -> np.ndarray:
    tt = t(dur, sr)
    f = np.full_like(tt, freq, dtype=float) if np.isscalar(freq) else np.asarray(freq)[:len(tt)]
    return np.sin(2 * np.pi * np.cumsum(f) / sr + phase)


def saw(freq, dur: float, sr: int = SR) -> np.ndarray:
    tt = t(dur, sr)
    f = np.full_like(tt, freq, dtype=float) if np.isscalar(freq) else np.asarray(freq)[:len(tt)]
    ph = np.cumsum(f) / sr
    return 2.0 * (ph % 1.0) - 1.0


def fit(x: np.ndarray, dur: float, sr: int = SR) -> np.ndarray:
    n = int(dur * sr)
    if len(x) < n:
        return np.pad(x, (0, n - len(x)))
    return x[:n]


def mix(*parts: np.ndarray) -> np.ndarray:
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def norm(x: np.ndarray, peak: float = 0.9) -> np.ndarray:
    m = float(np.max(np.abs(x))) or 1.0
    return x / m * peak


def edges(x: np.ndarray, sr: int = SR, ms: float = 6.0) -> np.ndarray:
    n = min(len(x) // 2, max(1, int(sr * ms / 1000.0)))
    if n > 1:
        x[:n] *= np.linspace(0, 1, n)
        x[-n:] *= np.linspace(1, 0, n)
    return x


def loopable(x: np.ndarray, sr: int, xfade: float = 0.35) -> np.ndarray:
    """Cross-fade the tail into the head so the bed loops seamlessly."""
    n = int(xfade * sr)
    if n * 2 >= len(x):
        return x
    head, tail = x[:n].copy(), x[-n:].copy()
    ramp = np.linspace(0, 1, n)
    x = x[:-n]
    x[:n] = head * ramp + tail * (1 - ramp)
    return x


WRITTEN: list[tuple[str, int]] = []


def save(rel: str, x: np.ndarray, sr: int = SR, quality: float = Q_SFX,
         peak: float = 0.9) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    data = edges(norm(np.nan_to_num(x), peak), sr).astype(np.float32)
    sf.write(path, data, sr, format="OGG", subtype="VORBIS",
             compression_level=1.0 - quality)
    WRITTEN.append((rel, path.stat().st_size))


# --------------------------------------------------------------------------- #
# sound designers
# --------------------------------------------------------------------------- #
def footstep(kind: str, seed_shift: float = 0.0) -> np.ndarray:
    """Soft granular impact tuned per surface material."""
    presets = {
        "dirt":   (0.11, 120, 1400, 0.0, 0.0),
        "grass":  (0.13, 300, 5200, 0.0, 0.0),
        "sand":   (0.14, 400, 6500, 0.0, 0.0),
        "gravel": (0.13, 250, 4800, 0.35, 0.0),
        "snow":   (0.16, 500, 8000, 0.15, 0.0),
        "wood":   (0.10, 90, 2200, 0.0, 220.0),
        "hard":   (0.09, 150, 3000, 0.0, 380.0),
        "glass":  (0.09, 800, 8000, 0.0, 2400.0),
        "metal":  (0.12, 200, 6000, 0.0, 1150.0),
        "ice":    (0.10, 600, 7500, 0.0, 1900.0),
        "water":  (0.22, 200, 3800, 0.0, 0.0),
    }
    dur, lo, hi, crunch, ring = presets[kind]
    body = bandpass(noise(dur), lo, hi)
    body = env(body, 0.002, power=3.0 + seed_shift)
    parts = [body]
    if crunch:
        # a few discrete grains for loose materials
        g = np.zeros(int(dur * SR))
        for _ in range(6):
            i = rng.integers(0, max(1, len(g) - 400))
            grain = env(bandpass(noise(0.018), 800, 7000), 0.001, power=4.0)
            g[i:i + len(grain)] += grain * rng.uniform(0.3, 1.0)
        parts.append(g * crunch * 1.5)
    if ring:
        r = resonator(env(noise(dur), 0.001, power=6.0), ring, q=25)
        parts.append(fit(r, dur) * 0.5)
    if kind == "water":
        # splash: rising filtered noise plus a couple of bubbles
        sw = env(bandpass(noise(dur), 300, 2500), 0.03, power=2.0)
        bub = np.zeros(int(dur * SR))
        for _ in range(3):
            i = rng.integers(0, max(1, len(bub) - 900))
            f = np.linspace(rng.uniform(400, 700), rng.uniform(900, 1600), 800)
            b = env(np.sin(2 * np.pi * np.cumsum(f) / SR), 0.001, power=3.0)
            bub[i:i + len(b)] += b * 0.35
        parts += [sw * 0.8, bub]
    out = mix(*[fit(p, dur) for p in parts])
    return out * 0.8


def dig(kind: str) -> np.ndarray:
    presets = {
        "choppy":   (0.16, 150, 2600, 300.0),
        "cracky":   (0.18, 200, 5000, 0.0),
        "crumbly":  (0.16, 120, 3000, 0.0),
        "snappy":   (0.12, 900, 8000, 0.0),
        "metal":    (0.20, 300, 7000, 1400.0),
        "immediate": (0.09, 400, 6000, 0.0),
        "hand":     (0.14, 150, 2400, 0.0),
        "gravel":   (0.17, 250, 5500, 0.0),
        "ice":      (0.20, 700, 9000, 2200.0),
    }
    dur, lo, hi, ring = presets[kind]
    scrape = bandpass(noise(dur), lo, hi)
    amp = np.linspace(1.0, 0.0, len(scrape)) ** 1.6
    amp *= 0.6 + 0.4 * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t(dur)))
    body = scrape * amp
    thump = env(sine(np.linspace(160, 60, int(dur * SR)), dur), 0.001, power=3.0) * 0.35
    parts = [body, thump]
    if ring:
        parts.append(fit(resonator(env(noise(dur), 0.001, power=8.0), ring, q=30), dur) * 0.45)
    return mix(*[fit(p, dur) for p in parts])


def dug(kind: str) -> np.ndarray:
    dur = 0.22
    if kind == "metal":
        base = resonator(env(noise(dur), 0.001, power=9.0), 780, q=45)
        base += 0.5 * resonator(env(noise(dur), 0.001, power=9.0), 1630, q=40)
        base += 0.3 * resonator(env(noise(dur), 0.001, power=9.0), 2410, q=35)
    elif kind == "ice":
        base = resonator(env(noise(dur), 0.001, power=7.0), 2100, q=55)
        base += 0.6 * resonator(env(noise(dur), 0.001, power=7.0), 3300, q=50)
    elif kind == "gravel":
        base = np.zeros(int(dur * SR))
        for _ in range(9):
            i = rng.integers(0, len(base) - 500)
            g = env(bandpass(noise(0.02), 700, 8000), 0.001, power=5.0)
            base[i:i + len(g)] += g * rng.uniform(0.3, 1.0)
    else:
        base = env(bandpass(noise(dur), 120, 2600), 0.003, power=2.4)
        base += env(sine(np.linspace(180, 70, int(dur * SR)), dur), 0.002, power=3.0) * 0.4
    return fit(base, dur)


def place(kind: str) -> np.ndarray:
    dur = 0.16
    if kind == "metal":
        x = resonator(env(noise(dur), 0.001, power=10.0), 950, q=40) * 0.9
        x += resonator(env(noise(dur), 0.001, power=10.0), 1870, q=35) * 0.4
    elif kind == "hard":
        x = env(bandpass(noise(dur), 200, 4000), 0.001, power=6.0)
        x += fit(resonator(env(noise(dur), 0.001, power=9.0), 520, q=20), dur) * 0.6
    else:
        x = env(bandpass(noise(dur), 120, 2600), 0.002, power=5.0)
        x += env(sine(np.linspace(220, 90, int(dur * SR)), dur), 0.001, power=4.0) * 0.5
    return fit(x, dur)


def break_glass() -> np.ndarray:
    dur = 0.55
    out = np.zeros(int(dur * SR))
    crack = env(bandpass(noise(0.05), 1500, 9500), 0.001, power=4.0)
    out[:len(crack)] += crack
    for _ in range(14):
        i = rng.integers(0, len(out) - 3000)
        f = rng.uniform(1800, 6500)
        sh = fit(resonator(env(noise(0.12), 0.001, power=8.0), f, q=60), 0.12)
        out[i:i + len(sh)] += sh * rng.uniform(0.15, 0.6) * (1 - i / len(out))
    return out


def tool_breaks() -> np.ndarray:
    dur = 0.30
    snap = env(bandpass(noise(0.04), 800, 7000), 0.0005, power=3.0)
    ring = fit(resonator(env(noise(dur), 0.001, power=6.0), 1250, q=45), dur) * 0.5
    fall = env(bandpass(noise(dur), 300, 4000), 0.05, power=2.5) * 0.35
    return mix(fit(snap, dur), ring, fall)


def chest(open_: bool) -> np.ndarray:
    dur = 0.45
    creak_f = np.linspace(420, 700, int(dur * SR)) if open_ else np.linspace(700, 380, int(dur * SR))
    creak = saw(creak_f, dur) * (0.12 + 0.10 * np.sin(2 * np.pi * 17 * t(dur)))
    creak = bandpass(creak, 300, 2600)
    creak = env(creak, 0.04, power=1.4)
    knock = env(bandpass(noise(0.09), 100, 1800), 0.001, power=5.0) * 0.9
    out = np.zeros(int(dur * SR))
    out += fit(creak, dur)
    pos = 0 if open_ else int(0.28 * SR)
    out[pos:pos + len(knock)] += knock[:len(out) - pos]
    return out


def cool_lava() -> np.ndarray:
    dur = 0.9
    hiss = bandpass(noise(dur), 1200, 8000)
    a = np.linspace(1.0, 0.0, len(hiss)) ** 1.3
    a *= 0.7 + 0.3 * rng.uniform(0, 1, len(hiss))
    hiss *= a
    pop = np.zeros(len(hiss))
    for _ in range(5):
        i = rng.integers(0, len(pop) - 1500)
        p = env(bandpass(noise(0.05), 200, 2200), 0.001, power=4.0)
        pop[i:i + len(p)] += p * rng.uniform(0.2, 0.6)
    rumble = lowpass(noise(dur), 120) * 0.5
    return mix(hiss, pop, rumble)


def furnace_active() -> np.ndarray:
    dur = 4.0
    sr = SR_LONG
    n = int(dur * sr)
    roar = lowpass(noise(dur, sr), 320, sr)
    roar *= 0.8 + 0.2 * np.sin(2 * np.pi * 3.1 * t(dur, sr))
    air = bandpass(noise(dur, sr), 900, 4200, sr) * 0.22
    crackle = np.zeros(n)
    for _ in range(28):
        i = rng.integers(0, n - 800)
        c = env(bandpass(noise(0.02, sr), 1500, 6000, sr), 0.0005, power=5.0, sr=sr)
        crackle[i:i + len(c)] += c * rng.uniform(0.1, 0.45)
    return loopable(mix(roar, air, crackle), sr, 0.3)


def item_smoke() -> np.ndarray:
    dur = 0.5
    x = bandpass(noise(dur), 600, 5000)
    x *= np.linspace(0.2, 1.0, len(x)) * np.linspace(1.0, 0.0, len(x)) ** 0.6
    x += env(sine(np.linspace(900, 220, int(dur * SR)), dur), 0.02, power=2.0) * 0.2
    return x


def player_damage() -> np.ndarray:
    dur = 0.35
    thud = env(sine(np.linspace(200, 55, int(dur * SR)), dur), 0.002, power=2.2)
    grunt_f = np.linspace(230, 150, int(dur * SR))
    grunt = (saw(grunt_f, dur) * 0.5 + sine(grunt_f * 2, dur) * 0.3)
    grunt = bandpass(grunt, 180, 1800)
    grunt = env(grunt, 0.01, power=2.5) * 0.8
    slap = env(bandpass(noise(0.08), 400, 4500), 0.001, power=4.0) * 0.5
    return mix(fit(thud, dur), fit(grunt, dur), fit(slap, dur))


# ---- mvp / gui / horror ---------------------------------------------------- #
def ui_click() -> np.ndarray:
    dur = 0.06
    x = env(sine(1650, dur), 0.001, power=6.0) * 0.7
    x += env(bandpass(noise(dur), 2000, 8000), 0.0005, power=8.0) * 0.4
    return x


def alert() -> np.ndarray:
    dur = 0.75
    out = np.zeros(int(dur * SR))
    for k, f in enumerate((880, 1174)):
        beep = env(sine(f, 0.16), 0.006, power=2.0) * 0.9
        beep += env(sine(f * 2, 0.16), 0.006, power=3.0) * 0.25
        i = int((0.02 + k * 0.24) * SR)
        out[i:i + len(beep)] += beep
    out += fit(lowpass(noise(dur), 200), dur) * 0.12
    return out


def hit() -> np.ndarray:
    dur = 0.18
    x = env(bandpass(noise(dur), 300, 5000), 0.0008, power=5.0)
    x += env(sine(np.linspace(320, 90, int(dur * SR)), dur), 0.001, power=3.0) * 0.7
    return x


def swim() -> np.ndarray:
    dur = 0.6
    x = bandpass(noise(dur), 200, 2200)
    x *= 0.5 + 0.5 * np.sin(2 * np.pi * 1.6 * t(dur) - 1.2)
    x = env(x, 0.06, power=1.2)
    for _ in range(4):
        i = rng.integers(0, len(x) - 900)
        f = np.linspace(rng.uniform(300, 600), rng.uniform(800, 1500), 800)
        x[i:i + 800] += env(np.sin(2 * np.pi * np.cumsum(f) / SR), 0.001, power=3.0) * 0.25
    return x


def radio_static() -> np.ndarray:
    dur = 2.5
    sr = SR_LONG
    x = bandpass(noise(dur, sr), 500, 5500, sr)
    x *= 0.6 + 0.4 * rng.uniform(0, 1, len(x))
    # intermittent carrier squelch
    for _ in range(6):
        i = rng.integers(0, len(x) - int(0.25 * sr))
        seg = int(rng.uniform(0.05, 0.2) * sr)
        car = np.sin(2 * np.pi * rng.uniform(700, 2400) * t(seg / sr, sr))
        x[i:i + seg] += car * 0.25 * np.hanning(seg)
    return loopable(x, sr, 0.2)


def monster_idle() -> np.ndarray:
    dur = 1.6
    f = 78 + 8 * np.sin(2 * np.pi * 1.3 * t(dur))
    growl = saw(f, dur) * 0.6 + saw(f * 1.5, dur) * 0.2
    growl = lowpass(growl, 900)
    growl *= 0.5 + 0.5 * np.sin(2 * np.pi * 6.5 * t(dur)) ** 2
    breath = bandpass(noise(dur), 300, 2000) * 0.18
    breath *= 0.4 + 0.6 * np.sin(2 * np.pi * 0.6 * t(dur)) ** 2
    return env(mix(growl, breath), 0.08, power=1.1)


def monster_chase() -> np.ndarray:
    dur = 1.8
    f = np.linspace(120, 210, int(dur * SR)) * (1 + 0.06 * np.sin(2 * np.pi * 9 * t(dur)))
    roar = saw(f, dur) * 0.7 + saw(f * 0.5, dur) * 0.4
    roar = bandpass(roar, 90, 3000)
    roar *= np.linspace(0.5, 1.0, len(roar))
    stomp = np.zeros(int(dur * SR))
    for k in range(5):
        i = int((0.15 + k * 0.34) * SR)
        s = env(sine(np.linspace(120, 40, int(0.16 * SR)), 0.16), 0.001, power=3.0)
        stomp[i:i + len(s)] += s * 0.8
    return env(mix(roar, stomp), 0.05, power=1.0)


def scary_attack() -> np.ndarray:
    dur = 1.1
    shriek_f = np.concatenate([
        np.linspace(600, 2200, int(0.3 * SR)),
        np.linspace(2200, 900, int(0.5 * SR)),
        np.linspace(900, 400, int(0.3 * SR)),
    ])
    shriek = saw(shriek_f, dur)[:len(shriek_f)]
    shriek = bandpass(shriek, 400, 6000)
    shriek *= 0.6 + 0.4 * rng.uniform(0, 1, len(shriek))
    sub = env(sine(np.linspace(90, 35, int(dur * SR)), dur), 0.01, power=1.5) * 0.8
    hitn = env(bandpass(noise(0.2), 500, 7000), 0.001, power=4.0) * 0.6
    return mix(fit(shriek, dur), fit(sub, dur), fit(hitn, dur))


def mob_idle() -> np.ndarray:
    dur = 1.0
    f = 150 + 20 * np.sin(2 * np.pi * 2.2 * t(dur))
    x = saw(f, dur) * 0.4
    x = bandpass(x, 120, 1600)
    x *= np.hanning(len(x)) ** 0.7
    x += bandpass(noise(dur), 400, 2500) * 0.12 * np.hanning(len(x))
    return x


def mob_death() -> np.ndarray:
    dur = 1.0
    f = np.linspace(320, 70, int(dur * SR))
    x = saw(f, dur) * 0.6 + sine(f * 2, dur) * 0.2
    x = bandpass(x, 90, 2500)
    x = env(x, 0.01, power=1.8)
    x += env(bandpass(noise(dur), 200, 3000), 0.02, power=2.5) * 0.25
    return x


def dizzy() -> np.ndarray:
    dur = 3.0
    sr = SR_LONG
    wob = 220 * (1 + 0.35 * np.sin(2 * np.pi * 0.9 * t(dur, sr)))
    x = np.sin(2 * np.pi * np.cumsum(wob) / sr) * 0.5
    x += np.sin(2 * np.pi * np.cumsum(wob * 1.005) / sr) * 0.4
    x *= 0.5 + 0.5 * np.sin(2 * np.pi * 3.3 * t(dur, sr))
    x += lowpass(noise(dur, sr), 400, sr) * 0.25
    return env(x, 0.3, power=1.0, sr=sr)


def whisper(seed_pitch: float) -> np.ndarray:
    dur = 2.0
    sr = SR_LONG
    x = bandpass(noise(dur, sr), 700 * seed_pitch, 3400 * seed_pitch, sr)
    syll = 0.5 + 0.5 * np.sin(2 * np.pi * 3.7 * t(dur, sr) * seed_pitch)
    x *= syll ** 3
    x *= np.hanning(len(x)) ** 0.5
    x += np.sin(2 * np.pi * 55 * seed_pitch * t(dur, sr)) * 0.08
    return x


def achievement() -> np.ndarray:
    dur = 1.4
    sr = SR_LONG
    out = np.zeros(int(dur * sr))
    for k, semi in enumerate((0, 4, 7, 12)):
        f = 523.25 * (2 ** (semi / 12))
        note = env(np.sin(2 * np.pi * f * t(0.9, sr)), 0.005, power=2.2, sr=sr) * 0.6
        note += env(np.sin(2 * np.pi * f * 2 * t(0.9, sr)), 0.005, power=4.0, sr=sr) * 0.18
        i = int(k * 0.09 * sr)
        out[i:i + len(note)] += note[:len(out) - i]
    shimmer = bandpass(noise(dur, sr), 4000, 7000, sr) * 0.12
    return mix(out, env(shimmer, 0.2, power=1.5, sr=sr))


def level_up() -> np.ndarray:
    dur = 1.2
    sr = SR_LONG
    out = np.zeros(int(dur * sr))
    for k, semi in enumerate((0, 5, 9, 12, 16)):
        f = 440 * (2 ** (semi / 12))
        note = env(np.sin(2 * np.pi * f * t(0.5, sr)), 0.004, power=3.0, sr=sr)
        note += env(saw(f * 2, 0.5, sr), 0.004, power=5.0, sr=sr) * 0.12
        i = int(k * 0.075 * sr)
        out[i:i + len(note)] += note[:len(out) - i] * 0.55
    return out


def ambience() -> np.ndarray:
    dur = 12.0
    sr = SR_LONG
    n = int(dur * sr)
    drone = np.zeros(n)
    for f, amp in ((55, 0.5), (82.5, 0.28), (110, 0.2), (164.8, 0.1)):
        det = f * (1 + 0.0015 * np.sin(2 * np.pi * 0.07 * t(dur, sr)))
        drone += np.sin(2 * np.pi * np.cumsum(det) / sr) * amp
    air = lowpass(noise(dur, sr), 700, sr) * 0.25
    air *= 0.7 + 0.3 * np.sin(2 * np.pi * 0.05 * t(dur, sr))
    clicks = np.zeros(n)
    for _ in range(10):
        i = rng.integers(0, n - 4000)
        c = env(bandpass(noise(0.08, sr), 1200, 5000, sr), 0.01, power=3.0, sr=sr)
        clicks[i:i + len(c)] += c * rng.uniform(0.05, 0.18)
    return loopable(mix(drone, air, clicks), sr, 0.8)


def creepy_ambient() -> np.ndarray:
    dur = 14.0
    sr = SR_LONG
    n = int(dur * sr)
    bed = np.zeros(n)
    for f, amp in ((41.2, 0.55), (61.7, 0.3), (98, 0.16), (146.8, 0.09)):
        bed += np.sin(2 * np.pi * f * (1 + 0.004 * np.sin(2 * np.pi * 0.033 * t(dur, sr)))
                      * t(dur, sr)) * amp
    wind = lowpass(noise(dur, sr), 420, sr) * 0.3
    wind *= 0.55 + 0.45 * np.sin(2 * np.pi * 0.06 * t(dur, sr) + 1.0)
    metal = np.zeros(n)
    for _ in range(5):
        i = rng.integers(0, n - int(1.5 * sr))
        r = resonator(env(noise(1.2, sr), 0.002, power=4.0, sr=sr),
                      rng.uniform(300, 1400), q=60, sr=sr)
        metal[i:i + len(r)] += r * rng.uniform(0.1, 0.3)
    return loopable(mix(bed, wind, metal), sr, 1.0)


def music_bed() -> np.ndarray:
    """Slow minor arpeggio pad — the in-game music loop."""
    dur = 24.0
    sr = SR_LONG
    n = int(dur * sr)
    out = np.zeros(n)
    chords = [(220.0, 261.63, 329.63), (196.0, 246.94, 293.66),
              (174.61, 220.0, 261.63), (196.0, 233.08, 293.66)]
    bar = dur / len(chords)
    for bi, chord in enumerate(chords):
        start = int(bi * bar * sr)
        for f in chord:
            pad = np.sin(2 * np.pi * f * t(bar, sr)) * 0.28
            pad += np.sin(2 * np.pi * f * 2.002 * t(bar, sr)) * 0.08
            pad *= np.hanning(len(pad)) ** 0.4
            out[start:start + len(pad)] += pad[:n - start]
        # arpeggio plucks
        for k in range(6):
            f = chord[k % 3] * (2 if k >= 3 else 1)
            i = start + int(k * bar / 6 * sr)
            pl = env(np.sin(2 * np.pi * f * t(0.6, sr)), 0.004, power=4.0, sr=sr) * 0.22
            out[i:i + len(pl)] += pl[:n - i]
        # sub pulse
        sub = env(np.sin(2 * np.pi * chord[0] / 2 * t(0.8, sr)), 0.02, power=2.0, sr=sr) * 0.3
        out[start:start + len(sub)] += sub[:n - start]
    out += lowpass(noise(dur, sr), 300, sr) * 0.05
    return loopable(out, sr, 1.2)


def menu_music() -> np.ndarray:
    dur = 28.0
    sr = SR_LONG
    n = int(dur * sr)
    out = np.zeros(n)
    prog = [(146.83, 174.61, 220.0), (164.81, 196.0, 246.94),
            (130.81, 164.81, 196.0), (174.61, 220.0, 261.63)]
    bar = dur / len(prog)
    for bi, chord in enumerate(prog):
        s = int(bi * bar * sr)
        for f in chord:
            pad = (np.sin(2 * np.pi * f * t(bar, sr)) * 0.3 +
                   np.sin(2 * np.pi * f * 1.5 * t(bar, sr)) * 0.1)
            pad *= np.hanning(len(pad)) ** 0.35
            out[s:s + len(pad)] += pad[:n - s]
        for k in range(8):
            f = chord[k % 3] * (2 ** ((k // 3) % 2))
            i = s + int(k * bar / 8 * sr)
            bell = env(np.sin(2 * np.pi * f * 2 * t(0.9, sr)), 0.003, power=5.0, sr=sr) * 0.16
            out[i:i + len(bell)] += bell[:n - i]
    out += lowpass(noise(dur, sr), 250, sr) * 0.04
    return loopable(out, sr, 1.5)


def menu_sfx(kind: str) -> tuple[np.ndarray, int]:
    sr = SR_LONG
    if kind == "beep":
        dur = 1.2
        out = np.zeros(int(dur * sr))
        for k, f in enumerate((660, 990, 1320)):
            b = env(np.sin(2 * np.pi * f * t(0.18, sr)), 0.004, power=3.0, sr=sr) * 0.7
            i = int(k * 0.2 * sr)
            out[i:i + len(b)] += b
        return out, sr
    if kind == "lava":
        dur = 6.0
        rumble = lowpass(noise(dur, sr), 150, sr)
        rumble *= 0.7 + 0.3 * np.sin(2 * np.pi * 0.4 * t(dur, sr))
        bub = np.zeros(len(rumble))
        for _ in range(24):
            i = rng.integers(0, len(bub) - 3000)
            f = np.linspace(rng.uniform(90, 200), rng.uniform(220, 420), int(0.14 * sr))
            b = env(np.sin(2 * np.pi * np.cumsum(f) / sr), 0.005, power=3.0, sr=sr)
            bub[i:i + len(b)] += b * rng.uniform(0.15, 0.5)
        return loopable(mix(rumble, bub), sr, 0.4), sr
    if kind == "old":
        dur = 4.0
        x = bandpass(noise(dur, sr), 300, 3000, sr) * 0.4
        x *= 0.5 + 0.5 * np.sin(2 * np.pi * 0.8 * t(dur, sr))
        x += np.sin(2 * np.pi * 120 * t(dur, sr)) * 0.15
        crackle = np.zeros(len(x))
        for _ in range(60):
            i = rng.integers(0, len(crackle) - 200)
            crackle[i:i + 60] += rng.uniform(-1, 1, 60) * rng.uniform(0.05, 0.3)
        return loopable(mix(x, crackle), sr, 0.3), sr
    if kind == "piano":
        dur = 3.0
        out = np.zeros(int(dur * sr))
        for k, f in enumerate((261.63, 329.63, 392.0, 523.25)):
            note = np.zeros(int(0.9 * sr))
            for h, amp in ((1, 1.0), (2, 0.4), (3, 0.18), (4, 0.08)):
                note += np.sin(2 * np.pi * f * h * t(0.9, sr)) * amp
            note = env(note, 0.004, power=3.2, sr=sr) * 0.45
            i = int(k * 0.35 * sr)
            out[i:i + len(note)] += note[:len(out) - i]
        return out, sr
    if kind == "leaves":
        dur = 6.0
        x = bandpass(noise(dur, sr), 1500, 7000, sr)
        x *= 0.35 + 0.65 * np.abs(np.sin(2 * np.pi * 0.35 * t(dur, sr)))
        rust = np.zeros(len(x))
        for _ in range(120):
            i = rng.integers(0, len(rust) - 400)
            g = env(bandpass(noise(0.02, sr), 2000, 8000, sr), 0.001, power=4.0, sr=sr)
            rust[i:i + len(g)] += g * rng.uniform(0.05, 0.3)
        return loopable(mix(x * 0.6, rust), sr, 0.4), sr
    raise ValueError(kind)


# --------------------------------------------------------------------------- #
# build
# --------------------------------------------------------------------------- #
def build() -> None:
    d = "mods/default/sounds"

    # footsteps
    fs = {
        "dirt": 2, "grass": 3, "sand": 3, "gravel": 4, "snow": 5, "wood": 2,
        "hard": 3, "metal": 3, "ice": 3, "water": 3,
    }
    for kind, count in fs.items():
        for i in range(1, count + 1):
            save(f"{d}/default_{kind}_footstep.{i}.ogg", footstep(kind, i * 0.15))
    save(f"{d}/default_glass_footstep.ogg", footstep("glass"))

    # digs
    for i in (1, 2, 3):
        save(f"{d}/default_dig_choppy.{i}.ogg", dig("choppy"))
        save(f"{d}/default_dig_cracky.{i}.ogg", dig("cracky"))
        save(f"{d}/default_ice_dig.{i}.ogg", dig("ice"))
    for i in (1, 2):
        save(f"{d}/default_gravel_dig.{i}.ogg", dig("gravel"))
    save(f"{d}/default_dig_crumbly.ogg", dig("crumbly"))
    save(f"{d}/default_dig_snappy.ogg", dig("snappy"))
    save(f"{d}/default_dig_metal.ogg", dig("metal"))
    save(f"{d}/default_dig_dig_immediate.ogg", dig("immediate"))
    save(f"{d}/default_dig_oddly_breakable_by_hand.ogg", dig("hand"))

    # dug
    for i in (1, 2):
        save(f"{d}/default_dug_node.{i}.ogg", dug("node"))
        save(f"{d}/default_dug_metal.{i}.ogg", dug("metal"))
    for i in (1, 2, 3):
        save(f"{d}/default_gravel_dug.{i}.ogg", dug("gravel"))
    save(f"{d}/default_ice_dug.ogg", dug("ice"))

    # place
    for i in (1, 2, 3):
        save(f"{d}/default_place_node.{i}.ogg", place("soft"))
    for i in (1, 2):
        save(f"{d}/default_place_node_hard.{i}.ogg", place("hard"))
        save(f"{d}/default_place_node_metal.{i}.ogg", place("metal"))

    # misc default
    for i in (1, 2, 3):
        save(f"{d}/default_break_glass.{i}.ogg", break_glass())
        save(f"{d}/default_tool_breaks.{i}.ogg", tool_breaks())
        save(f"{d}/default_cool_lava.{i}.ogg", cool_lava())
    save(f"{d}/default_chest_open.ogg", chest(True))
    save(f"{d}/default_chest_close.ogg", chest(False))
    save(f"{d}/default_item_smoke.ogg", item_smoke())
    save(f"{d}/default_furnace_active.ogg", furnace_active(), SR_LONG, Q_LONG)
    save(f"{d}/player_damage.ogg", player_damage())

    # mvp assets
    m = "mods/content/sl_mvp_assets/sounds"
    save(f"{m}/click.ogg", ui_click())
    save(f"{m}/alert.ogg", alert())
    save(f"{m}/hit.ogg", hit())
    save(f"{m}/damage.ogg", player_damage())
    save(f"{m}/place.ogg", place("soft"))
    save(f"{m}/footstep_metal.ogg", footstep("metal"))
    save(f"{m}/footstep_water.ogg", footstep("water"))
    save(f"{m}/swim.ogg", swim())
    save(f"{m}/monster_idle.ogg", monster_idle())
    save(f"{m}/monster_chase.ogg", monster_chase())
    save(f"{m}/radio_static.ogg", radio_static(), SR_LONG, Q_LONG)
    save(f"{m}/ambience.ogg", ambience(), SR_LONG, Q_LONG)
    save(f"{m}/music.ogg", music_bed(), SR_LONG, Q_LONG)

    # scary mod
    s = "mods/content/sl_scary/sounds"
    save(f"{s}/scary_attack.ogg", scary_attack())
    save(f"{s}/mob_idle.ogg", mob_idle())
    save(f"{s}/mob_death.ogg", mob_death())
    save(f"{s}/random_dizz.ogg", dizzy(), SR_LONG, Q_LONG)
    save(f"{s}/A_A.ogg", whisper(1.0), SR_LONG, Q_LONG)
    save(f"{s}/A_A1.ogg", whisper(0.82), SR_LONG, Q_LONG)
    save(f"{s}/A_A2.ogg", whisper(1.24), SR_LONG, Q_LONG)

    # gui stingers
    save("mods/apis/sl_gui/sounds/achievement_unlock.ogg", achievement(), SR_LONG, Q_LONG)
    save("mods/apis/sl_gui/sounds/level_up.ogg", level_up(), SR_LONG, Q_LONG)

    # skybox ambience
    save("mods/content/dark_skybox/sounds/creepy_ambient.ogg", creepy_ambient(), SR_LONG, Q_LONG)

    # menu
    save("menu/menu_music.ogg", menu_music(), SR_LONG, Q_LONG)
    for name, kind in (("beep-boop", "beep"), ("lava-sfx_121823", "lava"),
                       ("old-sound", "old"), ("piano_short", "piano"),
                       ("scratchy_pine_leaves", "leaves")):
        data, sr = menu_sfx(kind)
        save(f"menu/{name}.ogg", data, sr, Q_LONG)


if __name__ == "__main__":
    build()
    total = sum(s for _, s in WRITTEN)
    for rel, size in sorted(WRITTEN):
        print(f"{size:8d}  {rel}")
    print(f"\n{len(WRITTEN)} files, {total / 1024:.1f} KiB total "
          f"({total / len(WRITTEN) / 1024:.1f} KiB avg)")
