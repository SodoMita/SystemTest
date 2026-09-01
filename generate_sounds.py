#!/usr/bin/env python3
"""
generate_sounds.py — replace every sound in System Looting with a fresh,
procedurally synthesised, highly packed (tiny) Ogg Vorbis set.

Why / how
---------
* One-shot SFX are mono 22050 Hz; loops, ambience and music are mono
  16000 Hz.  Vorbis is encoded at the smallest usable quality
  (libsndfile compression_level ~1.0), so every file sits close to the
  ~3.7 KB Ogg header floor — typically 4-6 KB per sound, vs. 6-670 KB
  for the originals.
* Everything is deterministic: running this script reproduces the exact
  same bytes.
* Sound design is built entirely from DSP primitives (filtered noise,
  resonant bodies, FM growls, glides, Schroeder reverb).  No external
  samples are used, so there are no licensing issues.

Usage
-----
    python3 generate_sounds.py

The script regenerates every .ogg in place (git tracks the diff).
"""

from __future__ import annotations

import hashlib
import io
import os
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, iirpeak, lfilter, sosfilt

ROOT = Path(__file__).resolve().parent

SR = 22050       # one-shot SFX sample rate
SR_LOOP = 16000  # loops / ambience / music sample rate
PEAK = 0.72      # normalisation headroom (leaves room for Vorbis overshoot)


# --------------------------------------------------------------------------
# small DSP toolkit
# --------------------------------------------------------------------------

def rng(name: str, variant: int = 0) -> np.random.Generator:
    seed = int(hashlib.md5(f"{name}::{variant}".encode()).hexdigest(), 16) % (2 ** 32)
    return np.random.default_rng(seed)


def t_axis(dur: float, sr: int = SR) -> np.ndarray:
    return np.arange(int(dur * sr)) / sr


def white(n: int, g: np.random.Generator) -> np.ndarray:
    return g.normal(0.0, 1.0, n)


def pink(n: int, g: np.random.Generator) -> np.ndarray:
    """Paul Kellet-style pink noise (approximation)."""
    b = [0.0] * 7
    x = np.empty(n)
    for i in range(n):
        w = g.normal(0.0, 1.0)
        b[0] = 0.99886 * b[0] + w * 0.0555179
        b[1] = 0.99332 * b[1] + w * 0.0750759
        b[2] = 0.96900 * b[2] + w * 0.1538520
        b[3] = 0.86650 * b[3] + w * 0.3104856
        b[4] = 0.55000 * b[4] + w * 0.5329522
        b[5] = -0.7616 * b[5] - w * 0.0168980
        x[i] = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + w * 0.5362
        b[6] = w * 0.115926
    s = np.std(x)
    return x / s if s > 1e-9 else x


def brown(n: int, g: np.random.Generator) -> np.ndarray:
    x = np.cumsum(g.normal(0.0, 1.0, n))
    s = np.std(x)
    return x / s if s > 1e-9 else x


def lp(x: np.ndarray, sr: int, fc: float, order: int = 2) -> np.ndarray:
    sos = butter(order, min(max(fc, 1e-3), sr / 2 - 10), "lowpass", output="sos", fs=sr)
    return sosfilt(sos, x)


def hp(x: np.ndarray, sr: int, fc: float, order: int = 2) -> np.ndarray:
    sos = butter(order, min(max(fc, 1e-3), sr / 2 - 10), "highpass", output="sos", fs=sr)
    return sosfilt(sos, x)


def bnd(x: np.ndarray, sr: int, f1: float, f2: float, order: int = 2) -> np.ndarray:
    sos = butter(order, [max(f1, 1e-3), min(f2, sr / 2 - 10)], "bandpass", output="sos", fs=sr)
    return sosfilt(sos, x)


def reso(x: np.ndarray, sr: int, fc: float, q: float = 12.0) -> np.ndarray:
    """Narrow resonant bandpass (formant / 'voice' feel)."""
    b, a = iirpeak(max(fc, 1.0), q, fs=sr)
    return lfilter(b, a, x)


def svf_bp(x: np.ndarray, sr: int, fc: np.ndarray, q: float = 0.8) -> np.ndarray:
    """State-variable bandpass with a per-sample centre frequency."""
    out = np.empty_like(x)
    low = 0.0
    band = 0.0
    for i in range(len(x)):
        f = 2.0 * np.sin(np.pi * max(min(fc[i], sr / 2 - 10), 20.0) / sr)
        high = x[i] - low - q * band
        band = f * high + band
        low = f * band + low
        out[i] = band
    return out


def env_exp(n: int, k: float = 6.0) -> np.ndarray:
    return np.exp(-np.linspace(0.0, k, n))


def env_ad(n: int, a: float, k: float = 6.0) -> np.ndarray:
    """Attack-decay envelope.  a in [0,1] = attack fraction."""
    e = np.empty(n)
    na = max(int(n * a), 1)
    e[:na] = np.linspace(0.0, 1.0, na)
    e[na:] = np.exp(-np.linspace(0.0, k, n - na))
    return e


def fade(x: np.ndarray, fin: float = 0.008, fout: float = 0.008, sr: int = SR) -> np.ndarray:
    ni, no = int(fin * sr), int(fout * sr)
    if 0 < ni < len(x):
        x[:ni] *= np.linspace(0.0, 1.0, ni)
    if 0 < no < len(x):
        x[-no:] *= np.linspace(1.0, 0.0, no)
    return x


def norm(x: np.ndarray, peak: float = PEAK) -> np.ndarray:
    m = np.max(np.abs(x))
    if m < 1e-9:
        return x
    return x / m * peak


def soft(x: np.ndarray, k: float = 3.0) -> np.ndarray:
    return np.tanh(k * x) / np.tanh(k)


def resample(x: np.ndarray, factor: float) -> np.ndarray:
    """Linear resample.  factor > 1 -> longer/slower, < 1 -> shorter/faster."""
    n = int(len(x) / factor)
    idx = np.minimum(np.arange(n) * factor, len(x) - 1)
    return np.interp(idx, np.arange(len(x)), x)


def glide(f0: float, f1: float, dur: float, sr: int = SR,
          kind: str = "sine", vib: float = 0.0, vib_rate: float = 6.0) -> np.ndarray:
    t = t_axis(dur, sr)
    f = np.linspace(f0, f1, len(t))
    if vib:
        f *= 1.0 + vib * np.sin(2 * np.pi * vib_rate * t)
    ph = 2 * np.pi * np.cumsum(f) / sr
    if kind == "sine":
        return np.sin(ph)
    if kind == "saw":
        return 2.0 * (ph / (2 * np.pi) % 1.0) - 1.0
    if kind == "square":
        return np.sign(np.sin(ph))
    if kind == "tri":
        return 2.0 * np.abs(2.0 * (ph / (2 * np.pi) % 1.0) - 1.0) - 1.0
    raise ValueError(kind)


def tone(f: float, dur: float, sr: int = SR, decay: float = 5.0,
         partials: tuple = ((1.0, 1.0),)) -> np.ndarray:
    t = t_axis(dur, sr)
    x = np.zeros_like(t)
    for m, a in partials:
        x += a * np.sin(2 * np.pi * f * m * t)
    return x * env_exp(len(t), decay)


def metal_ring(f: float, dur: float = 0.5, sr: int = SR, decay: float = 9.0,
               bright: float = 1.0) -> np.ndarray:
    """Inharmonic damped-sine body of a struck piece of metal."""
    t = t_axis(dur, sr)
    x = np.zeros_like(t)
    for m, a in ((1.0, 1.0), (2.00, 0.55), (2.93, 0.42), (3.87, 0.26), (5.13, 0.14)):
        x += a * np.sin(2 * np.pi * f * m * t)
    x *= np.exp(-np.linspace(0.0, decay * (2.0 - bright), len(t)))
    return x


def knock(f: float = 210.0, dur: float = 0.3, sr: int = SR, decay: float = 7.0) -> np.ndarray:
    """Wooden / hollow knock."""
    t = t_axis(dur, sr)
    x = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.7 * t))
    return x * np.exp(-np.linspace(0.0, decay, len(t)))


def thump(f: float = 90.0, dur: float = 0.25, sr: int = SR, decay: float = 10.0) -> np.ndarray:
    t = t_axis(dur, sr)
    return np.sin(2 * np.pi * f * t) * np.exp(-np.linspace(0.0, decay, len(t)))


def nburst(n: int, g: np.random.Generator, sr: int = SR, f1: float = 0.0,
           f2: float = 0.0, peak: float = 1.0, order: int = 2) -> np.ndarray:
    x = g.normal(0.0, 1.0, n)
    if f2:
        x = lp(x, sr, f2, order)
    if f1:
        x = hp(x, sr, f1, order)
    if peak:
        x = norm(x, peak)
    return x


def comb(x: np.ndarray, sr: int, d_s: float, fb: float) -> np.ndarray:
    d = max(int(d_s * sr), 1)
    buf = np.zeros(d)
    y = np.empty_like(x)
    for i in range(len(x)):
        out = x[i] + buf[i % d] * fb
        buf[i % d] = out
        y[i] = out
    return y


def allpass(x: np.ndarray, sr: int, d_s: float, fb: float) -> np.ndarray:
    d = max(int(d_s * sr), 1)
    buf = np.zeros(d)
    y = np.empty_like(x)
    for i in range(len(x)):
        bv = buf[i % d]
        out = bv + x[i] * fb
        buf[i % d] = x[i] - bv * fb
        y[i] = out
    return y


def reverb(x: np.ndarray, sr: int, mix: float = 0.35, decay: float = 0.5,
           size: float = 1.0) -> np.ndarray:
    """Cheap Schroeder reverb — good enough for dark game SFX."""
    y = np.zeros_like(x)
    for d in (0.0297, 0.0371, 0.0411, 0.0437):
        y += comb(x, sr, d * size, decay)
    y /= 4.0
    y = allpass(y, sr, 0.0051 * size, 0.7)
    y = allpass(y, sr, 0.0077 * size, 0.7)
    return y * mix + x * (1.0 - mix)


def loopify(x: np.ndarray, sr: int, win: float = 0.4) -> np.ndarray:
    """Crossfade the tail into the head so the file loops seamlessly."""
    n = int(win * sr)
    if len(x) < 2 * n:
        return x
    f = np.linspace(0.0, 1.0, n)
    blend = x[:n] * (1.0 - f) + x[-n:] * f
    x[:n] = blend
    x[-n:] = blend
    return x


def mix_at(buf: np.ndarray, src: np.ndarray, at_s: float, gain: float = 1.0) -> None:
    i = int(at_s * SR)
    if i >= len(buf):
        return
    j = min(i + len(src), len(buf))
    buf[i:j] += src[: j - i] * gain


# --------------------------------------------------------------------------
# recipes — each returns (samples float32 mono, sample_rate)
# --------------------------------------------------------------------------

PV = [1.0, 1.09, 0.92, 1.17, 0.86, 1.24, 1.05, 0.95]  # variant pitch factors


def _pitch(variant: int, g: np.random.Generator) -> float:
    return PV[variant % len(PV)] * g.uniform(0.98, 1.02)


# ---- UI / feedback --------------------------------------------------------

def r_click(g, v):
    sr = SR
    p = _pitch(v, g)
    t = t_axis(0.09, sr)
    blip = np.sin(2 * np.pi * 1250 * p * t) * env_ad(len(t), 0.15, 9.0)
    blip += 0.15 * nburst(len(t), g, sr, f1=3000, peak=0.5)
    return norm(blip, 0.7), sr


def r_hit(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.32
    x = thump(95 * p, dur, sr, 12.0) * 0.9
    x += knock(240 * p, dur, sr, 8.0) * 0.5
    x += nburst(len(x), g, sr, f1=400, f2=6000, peak=0.8) * env_ad(len(x), 0.1, 5.0) * 0.6
    x = reverb(x, sr, 0.18, 0.35, 0.7)
    return norm(fade(x, 0.001, 0.02, sr)), sr


def r_place(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.4
    x = thump(110 * p, dur, sr, 9.0) * 0.8
    for _ in range(4):
        i = g.integers(int(0.03 * sr), int(0.22 * sr))
        L = int(0.02 * sr)
        if i + L < len(x):
            x[i:i + L] += nburst(L, g, sr, f1=1500, f2=7000, peak=0.35)
    return norm(fade(x, 0.002, 0.04, sr)), sr


def r_alert(g, v):
    sr = SR
    dur = 0.42
    x = np.zeros(int(dur * sr))
    for k in range(3):
        at = 0.03 + k * 0.125
        b = glide(640 * (1.0 if k % 2 else 1.25), 640 * (1.0 if k % 2 else 1.25),
                  0.055, sr, "tri") * env_ad(int(0.055 * sr), 0.1, 5.0)
        mix_at(x, b, at, 0.5)
    x += nburst(len(x), g, sr, f1=2000, f2=9000, peak=0.03)
    return norm(fade(x, 0.002, 0.02, sr)), sr


def r_damage(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.55
    x = np.zeros(int(dur * sr))
    # pain groan: saw that drops fast
    gr = glide(360 * p, 130 * p, 0.34, sr, "saw", vib=0.12, vib_rate=9.0)
    gr *= env_exp(len(gr), 5.0)
    mix_at(x, gr, 0.02, 0.45)
    # impact
    mix_at(x, thump(85, dur, sr, 14.0), 0.0, 0.9)
    mix_at(x, nburst(int(0.07 * sr), g, sr, f1=300, f2=5000, peak=0.7), 0.0, 0.55)
    x = reverb(x, sr, 0.2, 0.4, 0.8)
    return norm(fade(x, 0.002, 0.05, sr)), sr


def r_achievement(g, v):
    sr = SR
    dur = 0.58
    x = np.zeros(int(dur * sr))
    notes = [1046.5, 1318.5, 1568.0, 2093.0]  # C6 E6 G6 C7
    for i, f in enumerate(notes):
        mix_at(x, tone(f, 0.45, sr, 6.0), 0.02 + i * 0.06, 0.5)
    x = reverb(x, sr, 0.35, 0.4, 1.0)
    return norm(fade(x, 0.002, 0.06, sr)), sr


def r_level_up(g, v):
    sr = SR
    dur = 0.6
    sw = glide(420, 1280, 0.42, sr, "sine") * env_exp(int(0.42 * sr), 4.0)
    x = sw * 0.8
    b = tone(1568, 0.42, sr, 5.0) * env_ad(int(0.42 * sr), 0.5, 4.0) * 0.4
    x[:len(b)] += b
    x = reverb(x, sr, 0.4, 0.55, 0.9)
    return norm(fade(x, 0.002, 0.1, sr)), sr


def r_level_up_sound(g, v):
    return r_level_up(g, v)


# ---- MVP assets -----------------------------------------------------------

def r_footstep_metal(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.3
    x = metal_ring(880 * p, dur, sr, 11.0, 1.1) * 0.7
    b = nburst(int(0.03 * sr), g, sr, f1=2500, f2=9000, peak=0.8)
    x[:len(b)] += b
    return norm(fade(x, 0.001, 0.05, sr)), sr


def r_footstep_water(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.65
    t = t_axis(dur, sr)
    body = nburst(len(t), g, sr, f1=250, f2=2500, order=2) * env_ad(len(t), 0.08, 4.0)
    wob = 1 + 0.5 * np.sin(2 * np.pi * 22 * t)  # resonant wobble
    body *= wob
    # droplets
    for _ in range(5):
        at = g.uniform(0.05, 0.5)
        f = g.uniform(700, 1400) * p
        d = tone(f, 0.1, sr, 8.0) * 0.3
        mix_at(body, d, at, 0.5)
    return norm(fade(body, 0.002, 0.06, sr)), sr


def r_swim(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.85
    t = t_axis(dur, sr)
    x = nburst(len(t), g, sr, f1=200, f2=3000) * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * t)) ** 2
    x += nburst(len(t), g, sr, f1=3000, f2=8000, peak=0.3) * 0.4
    for _ in range(3):
        f = g.uniform(600, 1600) * p
        mix_at(x, tone(f, 0.08, sr, 9.0), g.uniform(0.1, 0.6), 0.35)
    return norm(fade(x, 0.01, 0.1, sr)), sr


def r_ambience(g, v):
    sr = SR_LOOP
    dur = 8.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = np.zeros(n)
    # deep ventilation hum
    for f, a in ((50.0, 0.5), (100.0, 0.35), (150.0, 0.2)):
        det = 1 + g.uniform(-0.003, 0.003)
        x += a * np.sin(2 * np.pi * f * det * t)
    # slow airy swell
    air = hp(white(n, g), sr, 900, 2)
    air = lp(air, sr, 5000, 1)
    swell = (0.35 + 0.65 * np.sin(2 * np.pi * 0.11 * t + g.uniform(0, 6))) ** 2
    x += air * swell * 0.10
    # faint metallic clank drift, once per loop
    for at in (2.1, 5.3):
        s = int(at * sr)
        L = int(0.8 * sr)
        if s + L < n:
            x[s:s + L] += metal_ring(g.uniform(500, 900), 0.8, sr, 7.0) * 0.05
    x = norm(x, 0.75)
    x = loopify(x, sr, 0.8)
    return fade(x, 0.005, 0.005, sr), sr


def r_music(g, v):
    sr = SR_LOOP
    dur = 10.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = np.zeros(n)
    # Dark A-minor-ish drone built from pure detuned sines with slow tremolo:
    # sines encode to almost nothing in Vorbis, so this loop stays tiny.
    for f, a, lt in ((55.0, 0.5, 0.07), (110.0, 0.4, 0.11), (130.81, 0.28, 0.05),
                     (164.81, 0.22, 0.09), (98.0, 0.2, 0.13)):
        det = 1 + g.uniform(-0.003, 0.003)
        trem = 1.0 + 0.25 * np.sin(2 * np.pi * lt * t + g.uniform(0, 6))
        x += a * np.sin(2 * np.pi * f * det * t) * trem
    # deep heartbeat pulse every ~3.3 s
    for i in range(3):
        at = 0.4 + i * 3.3
        s, L = int(at * sr), int(0.8 * sr)
        if s + L < n:
            x[s:s + L] += np.sin(2 * np.pi * 41 * t[:L]) * np.exp(-np.linspace(0, 6, L)) * 0.10
    x = norm(x, 0.8)
    x = loopify(x, sr, 0.8)
    return fade(x, 0.005, 0.005, sr), sr


def r_monster_idle(g, v):
    sr = SR_LOOP
    dur = 2.5
    n = int(dur * sr)
    t = t_axis(dur, sr)
    # low FM growl
    base = 52.0 * (1 + g.uniform(-0.02, 0.02))
    fm = base + 14 * np.sin(2 * np.pi * 3.1 * t)
    ph = 2 * np.pi * np.cumsum(fm) / sr
    x = 2.0 * (ph / (2 * np.pi) % 1.0) - 1.0
    x = lp(x, sr, 220, 2)
    x *= 0.5 + 0.5 * np.sin(2 * np.pi * 1.7 * t + g.uniform(0, 6))
    # breath bursts
    breath = bnd(white(n, g), sr, 350, 1200)
    for at in (0.35, 1.35):
        s, L = int(at * sr), int(0.5 * sr)
        if s + L < n:
            e = env_ad(L, 0.4, 4.0)
            x[s:s + L] += breath[s:s + L] * e * 0.22
    x = norm(x, 0.8)
    x = loopify(x, sr, 0.5)
    return fade(x, 0.004, 0.004, sr), sr


def r_monster_chase(g, v):
    sr = SR_LOOP
    dur = 1.6
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = np.zeros(n)
    base = 66.0
    ph = 2 * np.pi * np.cumsum(base + 9 * np.sin(2 * np.pi * 5.5 * t)) / sr
    growl = 2.0 * (ph / (2 * np.pi) % 1.0) - 1.0
    growl = lp(growl, sr, 300, 2)
    x += growl * 0.5
    # fast loping hits
    for i in range(4):
        at = i * 0.4
        s = int(at * sr)
        L = int(0.14 * sr)
        if s + L < n:
            x[s:s + L] += thump(72, 0.14, sr, 12.0) * 0.8
            x[s:s + int(0.03 * sr)] += nburst(int(0.03 * sr), g, sr, f1=1500, f2=8000, peak=0.5)
    x = norm(x, 0.85)
    x = loopify(x, sr, 0.3)
    return fade(x, 0.004, 0.004, sr), sr


def r_radio_static(g, v):
    sr = SR_LOOP
    dur = 3.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = white(n, g) * 0.5
    # burst pattern
    gate = np.zeros(n)
    i = 0
    while i < n:
        L = int(g.integers(1500, 9000))
        gate[i:i + L] = 1.0
        i += L + int(g.integers(2000, 12000))
    x *= gate
    # formant "garbled voice" bursts
    for at in (0.5, 1.3, 2.1):
        s, L = int(at * sr), int(0.4 * sr)
        if s + L < n:
            vx = bnd(white(L, g), sr, 400, 2600)
            vx = svf_bp(vx, sr, 700 + 900 * np.sin(2 * np.pi * 6 * t[:L]), 0.6)
            x[s:s + L] += vx * 0.6
    # crackle pops
    for _ in range(30):
        i = g.integers(0, n)
        L = int(g.integers(30, 200))
        if i + L < n:
            x[i:i + L] += nburst(L, g, sr, f1=2000, peak=0.5) * g.uniform(0.3, 1.0)
    x = norm(x, 0.7)
    return fade(x, 0.01, 0.08, sr), sr


# ---- sl_scary -------------------------------------------------------------

def r_scary_attack(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 1.3
    n = int(dur * sr)
    x = np.zeros(n)
    # screech sweep up + distort
    sc = glide(620 * p, 1650 * p, 0.55, sr, "saw", vib=0.15, vib_rate=11)
    sc = soft(sc, 2.2)
    sc *= env_ad(len(sc), 0.08, 4.0)
    mix_at(x, sc, 0.0, 0.6)
    # slam at the end
    at = 0.72
    mix_at(x, thump(70, 0.5, sr, 12.0), at, 1.0)
    mix_at(x, nburst(int(0.09 * sr), g, sr, f1=250, f2=4000, peak=0.8), at, 0.7)
    x = reverb(x, sr, 0.3, 0.5, 1.0)
    return norm(fade(x, 0.002, 0.1, sr)), sr


def r_A_A(g, v):
    """Monster locomotion: walk (v0) / run (v1) / call variant (v2)."""
    sr = SR_LOOP
    if v == 2:
        dur = 2.0
        n = int(dur * sr)
        t = t_axis(dur, sr)
        f = 220 * (1 + 0.35 * np.sin(2 * np.pi * 1.3 * t))
        ph = 2 * np.pi * np.cumsum(f * (1 + 0.08 * np.sin(2 * np.pi * 0.4 * t))) / sr
        x = np.sin(ph) + 0.4 * np.sin(2 * ph)
        x = soft(x, 1.8)
        x = reverb(x, sr, 0.5, 0.6, 1.2)
        return norm(fade(x, 0.02, 0.15, sr)), sr
    speed = 1.0 if v == 0 else 1.6
    dur = 2.5 if v == 0 else 2.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = np.zeros(n)
    # heavy dragging scrape
    drag = bnd(white(n, g), sr, 180, 900)
    env = (0.4 + 0.6 * np.sin(2 * np.pi * (0.55 * speed) * t)) ** 2
    x += drag * env * 0.4
    # deep growl
    ph = 2 * np.pi * np.cumsum(48 + 10 * np.sin(2 * np.pi * 2.2 * t)) / sr
    growl = lp(2.0 * (ph / (2 * np.pi) % 1.0) - 1.0, sr, 200, 2)
    x += growl * (0.35 + 0.25 * np.sin(2 * np.pi * 1.3 * t))
    # loping thuds
    for i in range(3 if v == 0 else 4):
        at = i * (0.62 if v == 0 else 0.42)
        s = int(at * sr)
        L = int(0.12 * sr)
        if s + L < n:
            x[s:s + L] += thump(58, 0.12, sr, 10.0) * 0.9
    x = norm(x, 0.85)
    x = loopify(x, sr, 0.4)
    return fade(x, 0.004, 0.004, sr), sr


def r_mob_idle(g, v):
    return r_monster_idle(g, v + 1)


def r_mob_death(g, v):
    sr = SR
    dur = 1.9
    n = int(dur * sr)
    x = np.zeros(n)
    gr = glide(210, 48, 1.1, sr, "saw", vib=0.1, vib_rate=7)
    gr *= env_exp(len(gr), 2.2)
    mix_at(x, gr, 0.0, 0.55)
    # airy exhale
    L = int(0.9 * sr)
    exh = bnd(white(L, g), sr, 250, 1400) * env_ad(L, 0.3, 2.5)
    mix_at(x, exh, 0.25, 0.3)
    # final body thud
    mix_at(x, thump(60, 0.6, sr, 8.0), 1.05, 1.0)
    mix_at(x, nburst(int(0.08 * sr), g, sr, f1=200, f2=2500, peak=0.7), 1.05, 0.6)
    x = reverb(x, sr, 0.25, 0.5, 1.0)
    return norm(fade(x, 0.003, 0.15, sr)), sr


def r_random_dizz(g, v):
    sr = SR_LOOP
    dur = 4.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = np.zeros(n)
    # machine malfunction: stuttering static
    i = 0
    while i < n:
        L = int(g.integers(500, 7000))
        seg = white(min(L, n - i), g)
        r = g.uniform(0, 1)
        if r < 0.4:
            seg = bnd(seg, sr, 300, 2500)
        elif r < 0.7:
            seg = reso(seg, sr, g.uniform(400, 2000), 6.0)
        seg = soft(seg, 2.2)
        x[i:i + len(seg)] += seg * 0.42
        i += L + int(g.integers(800, 8000))
    # failing power blips
    for _ in range(6):
        at = g.uniform(0.2, 3.6)
        mix_at(x, glide(g.uniform(300, 900), g.uniform(100, 400), 0.12, sr, "square") * 0.5, at, 0.5)
    x = norm(x, 0.7)
    return fade(x, 0.02, 0.15, sr), sr


# ---- dark skybox ----------------------------------------------------------

def r_creepy_ambient(g, v):
    sr = SR_LOOP
    dur = 10.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = np.zeros(n)
    # dissonant minor-second pad
    for f, a in ((110.0, 0.4), (116.54, 0.38), (220.0, 0.25), (233.08, 0.22)):
        x += a * np.sin(2 * np.pi * f * (1 + g.uniform(-0.002, 0.002)) * t)
    saw = 0.0
    for f, a in ((110.0, 0.5), (116.54, 0.45)):
        saw += a * (2.0 * ((f * t) % 1.0) - 1.0)
    x += lp(saw, sr, 180, 2) * (0.35 + 0.65 * np.sin(2 * np.pi * 0.06 * t)) * 0.2
    # high shimmer
    sh = hp(white(n, g), sr, 3000, 2)
    sh *= (0.4 + 0.6 * np.sin(2 * np.pi * 0.043 * t + 1.0)) ** 2
    x += sh * 0.05
    # distant moan sweep
    for at in (2.3, 6.1):
        s, L = int(at * sr), int(1.6 * sr)
        if s + L < n:
            f = 240 + 120 * np.sin(2 * np.pi * 0.6 * t[:L])
            ph = 2 * np.pi * np.cumsum(f) / sr
            x[s:s + L] += np.sin(ph) * env_ad(L, 0.4, 3.0) * 0.12
    x = norm(x, 0.8)
    x = loopify(x, sr, 0.9)
    return fade(x, 0.005, 0.005, sr), sr


# ---- default mod: materials ----------------------------------------------

def _material_hit(mat: str, g, v):
    """Shared dig/step body for the default node-sound materials."""
    sr = SR
    p = _pitch(v, g)
    dur = 0.34
    if mat == "wood":
        x = knock(230 * p, 0.16, sr, 8.0) * 0.9
        b = nburst(int(0.03 * sr), g, sr, f1=900, f2=5000, peak=0.5)
        x[:len(b)] += b
    elif mat == "stone":
        x = knock(320 * p, 0.14, sr, 9.0) * 0.8
        b = nburst(int(0.04 * sr), g, sr, f1=1800, f2=9000, peak=0.7)
        x[:len(b)] += b
        x += metal_ring(1500 * p, 0.18, sr, 12.0, 0.8) * 0.25
    elif mat == "dirt":
        x = thump(95 * p, 0.2, sr, 8.0) * 0.9
        b = nburst(int(0.05 * sr), g, sr, f1=200, f2=2800, peak=0.8)
        x[:len(b)] += b
    elif mat == "gravel":
        x = thump(110 * p, 0.16, sr, 9.0) * 0.8
        for _ in range(8):
            i = g.integers(0, int(0.18 * sr))
            L = int(0.012 * sr)
            if i + L < len(x):
                x[i:i + L] += nburst(L, g, sr, f1=1600, f2=8000, peak=0.6)
    elif mat == "sand":
        x = nburst(int(0.22 * sr), g, sr, f1=500, f2=4200, order=3) * env_ad(int(0.22 * sr), 0.25, 3.5)
    elif mat == "snow":
        x = nburst(int(0.2 * sr), g, sr, f1=700, f2=5200, order=3) * env_ad(int(0.2 * sr), 0.2, 3.0)
        b = glide(500 * p, 700 * p, 0.09, sr, "sine") * 0.25  # squeak
        x[:len(b)] += b
    elif mat == "ice":
        x = nburst(int(0.2 * sr), g, sr, f1=2500, f2=9000) * env_ad(int(0.2 * sr), 0.05, 4.5)
        b = metal_ring(1800 * p, 0.16, sr, 10.0, 1.2) * 0.5
        x[:len(b)] += b
    elif mat == "glass":
        x = nburst(int(0.24 * sr), g, sr, f1=3000, f2=12000, order=3) * env_ad(int(0.24 * sr), 0.04, 5.0)
        for f in (2400, 3200, 4100):
            b = tone(f * p, 0.14, sr, 9.0) * 0.35
            x[:len(b)] += b
    elif mat == "metal":
        x = metal_ring(1050 * p, 0.24, sr, 11.0, 1.1) * 0.8
        b = nburst(int(0.02 * sr), g, sr, f1=3000, f2=10000, peak=0.6)
        x[:len(b)] += b
    elif mat == "hard":
        x = knock(480 * p, 0.12, sr, 9.0) * 0.7
        b = nburst(int(0.03 * sr), g, sr, f1=1500, f2=8000, peak=0.8)
        x[:len(b)] += b
    elif mat == "grass":
        x = nburst(int(0.2 * sr), g, sr, f1=400, f2=3800, order=3) * env_ad(int(0.2 * sr), 0.15, 3.0)
        b = thump(90 * p, 0.12, sr, 7.0) * 0.4
        x[:len(b)] += b
    elif mat == "water":
        return r_footstep_water(g, v)
    else:
        x = nburst(int(0.15 * sr), g, sr, f1=300, f2=3000)
    return norm(fade(x, 0.001, 0.06, sr)), sr


def r_dig_choppy(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.34
    x = np.zeros(int(dur * sr))
    for at in (0.0, 0.1):
        mix_at(x, knock(240 * p, 0.12, sr, 8.0), at, 0.9)
        mix_at(x, nburst(int(0.025 * sr), g, sr, f1=900, f2=5000, peak=0.5), at, 0.5)
    return norm(fade(x, 0.001, 0.05, sr)), sr


def r_dig_cracky(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.3
    x = np.zeros(int(dur * sr))
    for at in (0.0, 0.07, 0.15):
        mix_at(x, knock(330 * p, 0.1, sr, 10.0), at, 0.8)
        mix_at(x, nburst(int(0.03 * sr), g, sr, f1=1800, f2=9000, peak=0.6), at, 0.5)
    return norm(fade(x, 0.001, 0.05, sr)), sr


def r_dig_crumbly(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.34
    x = nburst(int(dur * sr), g, sr, f1=200, f2=2600) * env_ad(int(dur * sr), 0.1, 3.0)
    b = thump(95 * p, 0.16, sr, 8.0) * 0.7
    x[:len(b)] += b
    for _ in range(5):
        i = g.integers(0, int(0.2 * sr))
        x[i:i + int(0.01 * sr)] += nburst(int(0.01 * sr), g, sr, f1=1000, f2=5000, peak=0.4)
    return norm(fade(x, 0.002, 0.06, sr)), sr


def r_dig_immediate(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.24
    x = nburst(int(dur * sr), g, sr, f1=300, f2=4000) * env_ad(int(dur * sr), 0.06, 4.5)
    b = thump(100 * p, 0.12, sr, 9.0) * 0.6
    x[:len(b)] += b
    return norm(fade(x, 0.001, 0.04, sr)), sr


def r_dig_metal(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.26
    x = metal_ring(1200 * p, dur, sr, 12.0, 1.2) * 0.9
    b = nburst(int(0.02 * sr), g, sr, f1=2500, f2=10000, peak=0.7)
    x[:len(b)] += b
    return norm(fade(x, 0.001, 0.05, sr)), sr


def r_dig_oddly(g, v):
    sr = SR
    dur = 0.3
    x = nburst(int(dur * sr), g, sr, f1=250, f2=3000) * env_ad(int(dur * sr), 0.15, 3.5)
    return norm(fade(x, 0.002, 0.06, sr)), sr


def r_dig_snappy(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.3
    x = np.zeros(int(dur * sr))
    b = nburst(int(0.05 * sr), g, sr, f1=800, f2=7000, peak=0.8)
    x[:len(b)] += b
    b = knock(380 * p, 0.12, sr, 9.0) * 0.7
    x[:len(b)] += b
    return norm(fade(x, 0.001, 0.05, sr)), sr


def r_dug_node(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.3
    x = thump(110 * p, 0.2, sr, 8.0)
    b = nburst(int(0.18 * sr), g, sr, f1=250, f2=3200) * env_ad(int(0.18 * sr), 0.05, 4.0) * 0.7
    x[:len(b)] += b
    for _ in range(4):
        i = g.integers(int(0.04 * sr), int(0.2 * sr))
        L = int(0.012 * sr)
        x[i:i + L] += nburst(L, g, sr, f1=1200, f2=6000, peak=0.5)
    return norm(fade(x, 0.001, 0.07, sr)), sr


def r_dug_metal(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.5
    x = metal_ring(950 * p, dur, sr, 8.0, 1.0) * 0.8
    b = nburst(int(0.3 * sr), g, sr, f1=400, f2=6000) * env_ad(int(0.3 * sr), 0.04, 5.0) * 0.5
    x[:len(b)] += b
    for _ in range(6):
        i = g.integers(int(0.05 * sr), int(0.3 * sr))
        L = int(0.02 * sr)
        x[i:i + L] += nburst(L, g, sr, f1=2000, f2=9000, peak=0.5)
    x = reverb(x, sr, 0.25, 0.45, 0.8)
    return norm(fade(x, 0.001, 0.08, sr)), sr


def r_place_node(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.45
    x = thump(105 * p, 0.25, sr, 7.0) * 0.9
    b = nburst(int(0.25 * sr), g, sr, f1=200, f2=2200) * env_ad(int(0.25 * sr), 0.08, 3.5) * 0.6
    x[:len(b)] += b
    for _ in range(3):
        i = g.integers(int(0.05 * sr), int(0.2 * sr))
        x[i:i + int(0.015 * sr)] += nburst(int(0.015 * sr), g, sr, f1=900, f2=4500, peak=0.4)
    return norm(fade(x, 0.002, 0.08, sr)), sr


def r_place_node_hard(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.3
    x = knock(430 * p, 0.14, sr, 9.0) * 0.8
    b = nburst(int(0.04 * sr), g, sr, f1=1500, f2=8000, peak=0.7)
    x[:len(b)] += b
    return norm(fade(x, 0.001, 0.06, sr)), sr


def r_place_node_metal(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.5
    x = metal_ring(820 * p, dur, sr, 9.0, 1.0) * 0.8
    b = nburst(int(0.03 * sr), g, sr, f1=2500, f2=9500, peak=0.6)
    x[:len(b)] += b
    return norm(fade(x, 0.001, 0.09, sr)), sr


def r_break_glass(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.6
    n = int(dur * sr)
    x = np.zeros(n)
    # initial crack
    b = nburst(int(0.05 * sr), g, sr, f1=2000, f2=14000, peak=0.9)
    x[:len(b)] += b
    # shard cascade
    for _ in range(26):
        at = g.uniform(0.0, 0.4)
        L = int(0.03 * sr)
        s = int(at * sr)
        if s + L < n:
            sh = nburst(L, g, sr, f1=3500, f2=14000, peak=0.5)
            x[s:s + L] += sh * env_ad(L, 0.2, 5.0)
    # ringing shards
    for f in (2600, 3400, 4300, 5100):
        mix_at(x, tone(f * p, 0.3, sr, 7.0), g.uniform(0.02, 0.15), 0.3)
    x = reverb(x, sr, 0.3, 0.5, 0.9)
    return norm(fade(x, 0.001, 0.1, sr)), sr


def r_chest_open(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.62
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = np.zeros(n)
    # hinge squeak
    f = 620 + 320 * np.sin(2 * np.pi * 1.1 * t)
    ph = 2 * np.pi * np.cumsum(f * p) / sr
    squeak = np.sin(ph) * env_ad(n, 0.12, 2.6) * 0.35
    x += squeak
    # wooden creak
    creak = (np.sin(2 * np.pi * 92 * p * t) + 0.4 * np.sin(2 * np.pi * 137 * p * t))
    creak *= env_ad(n, 0.2, 1.8) * (0.6 + 0.4 * np.sin(2 * np.pi * 2.3 * t))
    x += creak * 0.4
    # lid thud at end
    mix_at(x, knock(180 * p, 0.16, sr, 8.0), 0.42, 0.7)
    return norm(fade(x, 0.004, 0.05, sr)), sr


def r_chest_close(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.7
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = np.zeros(n)
    f = 480 + 260 * np.sin(2 * np.pi * 0.9 * t)
    ph = 2 * np.pi * np.cumsum(f * p) / sr
    x += np.sin(ph) * env_ad(n, 0.15, 2.2) * 0.3
    x += (np.sin(2 * np.pi * 105 * p * t)) * env_ad(n, 0.1, 2.0) * 0.4
    mix_at(x, thump(120 * p, 0.18, sr, 9.0), 0.34, 0.9)
    mix_at(x, nburst(int(0.03 * sr), g, sr, f1=1200, f2=6000, peak=0.5), 0.34, 0.5)
    return norm(fade(x, 0.004, 0.05, sr)), sr


def r_cool_lava(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.7
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = nburst(n, g, sr, f1=2500, f2=14000, order=3) * env_ad(n, 0.1, 3.0)
    # bubbles
    for _ in range(5):
        at = g.uniform(0.02, 0.55)
        f = g.uniform(250, 700) * p
        mix_at(x, glide(f, f * 0.4, 0.12, sr, "sine"), at, 0.4)
    b = thump(55, 0.25, sr, 6.0) * 0.3
    x[:len(b)] += b
    return norm(fade(x, 0.005, 0.09, sr)), sr


def r_furnace(g, v):
    sr = SR_LOOP
    dur = 10.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    rumble = lp(brown(n, g), sr, 90, 1)
    rumble *= 0.65 + 0.35 * np.sin(2 * np.pi * 0.09 * t + g.uniform(0, 6))
    crack = hp(white(n, g), sr, 1500, 1)
    cenv = np.zeros(n)
    for _ in range(240):
        i = g.integers(0, n - 400)
        L = int(g.integers(60, 480))
        cenv[i:i + L] += np.exp(-np.arange(L) / 40.0) * g.uniform(0.1, 0.9)
    x = rumble * 0.75 + crack * cenv * 0.45
    # occasional pop
    for _ in range(14):
        i = g.integers(0, n - 300)
        L = int(g.integers(40, 120))
        x[i:i + L] += nburst(L, g, sr, f1=800, f2=3000, peak=0.4)
    x = norm(x, 0.8)
    x = loopify(x, sr, 0.8)
    return fade(x, 0.004, 0.004, sr), sr


def r_item_smoke(g, v):
    sr = SR
    dur = 0.6
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = nburst(n, g, sr, f1=2000, f2=9000) * env_ad(n, 0.1, 3.0) * 0.5
    x += nburst(n, g, sr, f1=400, f2=2500) * env_ad(n, 0.3, 2.0) * 0.3
    mix_at(x, tone(g.uniform(900, 1500), 0.09, sr, 8.0), g.uniform(0.2, 0.45), 0.35)
    return norm(fade(x, 0.01, 0.1, sr)), sr


def r_tool_breaks(g, v):
    sr = SR
    p = _pitch(v, g)
    dur = 0.3
    x = np.zeros(int(dur * sr))
    b = nburst(int(0.04 * sr), g, sr, f1=700, f2=9000, peak=0.9)
    x[:len(b)] += b
    mix_at(x, knock(260 * p, 0.14, sr, 8.0), 0.015, 0.8)
    mix_at(x, knock(190 * p, 0.16, sr, 7.0), 0.07, 0.6)
    return norm(fade(x, 0.001, 0.06, sr)), sr


def r_tool_break(g, v):
    return r_tool_breaks(g, v + 1)


def r_player_damage(g, v):
    return r_damage(g, v + 1)


# ---- default footsteps ----------------------------------------------------

def _mk_footstep(mat: str):
    def fn(g, v):
        return _material_hit(mat, g, v)
    return fn


# ---- menu music -----------------------------------------------------------

def r_menu_music(g, v):
    return r_music(g, v + 1)


def r_beep_boop(g, v):
    sr = SR_LOOP
    bpm = 124.0
    beat = 60.0 / bpm
    dur = 4 * beat * 9  # 9 bars of 4/4, 8th-note arp -> ~17.4 s
    n = int(dur * sr)
    x = np.zeros(n)
    notes = [220.0, 261.63, 329.63, 440.0, 329.63, 261.63, 220.0, 196.0,
             220.0, 261.63, 329.63, 493.88, 440.0, 329.63, 261.63, 246.94]
    for i in range(int(dur / (beat * 0.5))):
        f = notes[i % len(notes)]
        at = i * beat * 0.5
        s = int(at * sr)
        L = int(beat * 0.5 * 0.9 * sr)
        if s + L < n:
            blip = np.sign(np.sin(2 * np.pi * f * t_axis(L / sr, sr))) * env_ad(L, 0.05, 3.0)
            x[s:s + L] += blip * 0.4
    # bass pulse on beats
    for i in range(int(dur / beat)):
        at = i * beat
        s = int(at * sr)
        L = int(beat * 0.4 * sr)
        if s + L < n:
            b = np.sign(np.sin(2 * np.pi * 55.0 * t_axis(L / sr, sr))) * env_exp(L, 4.0)
            x[s:s + L] += b * 0.3
    # hat ticks on 8ths
    for i in range(int(dur / (beat * 0.5))):
        at = i * beat * 0.5
        s = int(at * sr)
        L = int(0.02 * sr)
        if s + L < n:
            x[s:s + L] += nburst(L, g, sr, f1=5000, f2=12000, peak=0.5) * 0.18
    x = norm(x, 0.8)
    return fade(x, 0.01, 0.3, sr), sr


def r_lava_sfx(g, v):
    sr = SR_LOOP
    dur = 20.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    rumble = lp(brown(n, g), sr, 70, 1)
    rumble *= 0.7 + 0.3 * np.sin(2 * np.pi * 0.045 * t)
    x = rumble * 0.7
    # bubbles
    for _ in range(110):
        at = g.uniform(0.1, dur - 1.0)
        f = g.uniform(220, 620)
        s = int(at * sr)
        L = int(0.16 * sr)
        if s + L < n:
            x[s:s + L] += glide(f, f * 0.35, 0.16, sr, "sine") * g.uniform(0.15, 0.5)
    # hisses
    for _ in range(7):
        at = g.uniform(0.5, dur - 3.0)
        s, L = int(at * sr), int(g.uniform(0.6, 1.6) * sr)
        if s + L < n:
            x[s:s + L] += nburst(L, g, sr, f1=2500, f2=12000, peak=0.5) * env_ad(L, 0.3, 1.5)
    x = norm(x, 0.8)
    return fade(x, 0.3, 0.8, sr), sr


def r_old_sound(g, v):
    sr = SR_LOOP
    dur = 16.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    x = np.zeros(n)
    # lo-fi detuned pad
    for f, a in ((110.0, 0.4), (116.54, 0.35), (164.81, 0.25), (220.0, 0.18)):
        x += a * np.sin(2 * np.pi * f * (1 + g.uniform(-0.006, 0.006)) * t)
    saw = 0.0
    for f, a in ((110.0, 0.5), (164.81, 0.35)):
        saw += a * (2.0 * ((f * (1 + g.uniform(-0.005, 0.005)) * t) % 1.0) - 1.0)
    flfo = 0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t)
    x += lp(saw, sr, 500, 2) * flfo * 0.14
    # vinyl crackle
    crack = hp(white(n, g), sr, 3500, 1) * 0.12
    for _ in range(300):
        i = g.integers(0, n)
        L = int(g.integers(20, 90))
        if i + L < n:
            crack[i:i + L] *= 1.0
    x += crack
    # distant bell
    for at in (2.5, 7.5, 12.5):
        s, L = int(at * sr), int(3.0 * sr)
        if s + L < n:
            x[s:s + L] += tone(g.uniform(330, 420), 3.0, sr, 1.6,
                                ((1, 1.0), (2.0, 0.4), (2.9, 0.25))) * 0.12
    x = norm(x, 0.8)
    return fade(x, 0.3, 0.9, sr), sr


def r_piano_short(g, v):
    sr = SR_LOOP
    motif = [220.0, 261.63, 329.63, 220.0, 196.0, 174.61]
    step = 1.6
    dur = step * len(motif) + 1.5
    n = int(dur * sr)
    x = np.zeros(n)
    for i, f in enumerate(motif):
        at = 0.4 + i * step
        s = int(at * sr)
        L = int(2.4 * sr)
        if s + L >= n:
            L = n - s
        # inharmonic hammer partials
        key = np.zeros(L)
        for m, a in ((1.0, 1.0), (2.0, 0.5), (3.01, 0.3), (4.03, 0.16), (5.07, 0.09)):
            key += a * np.sin(2 * np.pi * f * m * t_axis(L / sr, sr))
        key *= np.exp(-np.linspace(0, 2.4, L))
        x[s:s + L] += key * 0.3
        # hammer knock
        x[s:s + int(0.02 * sr)] += nburst(int(0.02 * sr), g, sr, f1=800, f2=5000, peak=0.4)
    x = reverb(x, sr, 0.35, 0.5, 1.2)
    x = norm(x, 0.8)
    return fade(x, 0.3, 0.8, sr), sr


def r_scratchy_pine(g, v):
    sr = SR_LOOP
    dur = 16.0
    n = int(dur * sr)
    t = t_axis(dur, sr)
    # wind swells through needles
    wind = bnd(white(n, g), sr, 300, 1600)
    sw = (0.4 + 0.6 * np.sin(2 * np.pi * 0.05 * t + 0.7) ** 2) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.013 * t))
    x = wind * sw * 0.5
    # rustle grains
    rust = hp(white(n, g), sr, 2500, 2)
    renv = np.zeros(n)
    for _ in range(550):
        i = g.integers(0, n)
        L = int(g.integers(40, 300))
        if i + L < n:
            renv[i:i + L] += np.exp(-np.arange(L) / 60.0) * g.uniform(0.1, 1.0)
    x += rust * renv * 0.2
    # low drone underneath
    x += np.sin(2 * np.pi * 50 * t) * 0.12
    x += np.sin(2 * np.pi * 74 * t) * 0.08
    # occasional branch creak
    for _ in range(3):
        at = g.uniform(2.0, 13.5)
        s, L = int(at * sr), int(1.2 * sr)
        if s + L < n:
            f = 130 + 40 * np.sin(2 * np.pi * 0.4 * t[:L])
            ph = 2 * np.pi * np.cumsum(f) / sr
            x[s:s + L] += np.sin(ph) * env_ad(L, 0.3, 2.5) * 0.12
    x = norm(x, 0.8)
    return fade(x, 0.4, 1.0, sr), sr


# --------------------------------------------------------------------------
# sl_weapons — the ranged arsenal (WEAPONS_SPEC §13: "Assets (generated,
# zero external files)"). Every name below is a literal the mod passes to
# minetest.sound_play. The arsenal's audio identity is its warning
# language: pads identify the weapon by pitch (council resolution #1 —
# handled at runtime by the Lua `pitch` param, so pad_chime stays one
# clean bell here), the dry click is intentionally loud and room-audible,
# and blades/severance break loudly when they die.
# --------------------------------------------------------------------------


def _w_env(n, k=12.0):
    return np.exp(-np.linspace(0.0, k, n))


def _w_noiser(g, v, f2, f1=180.0, dur=0.40, k=22.0, gain=0.85, at=0.0):
    sr = SR
    n = int(dur * sr)
    x = nburst(n, g, sr, f1=f1, f2=f2, peak=1.0) * _w_env(n, k) * gain
    if at > 0:  # slow attack (booms, roars)
        a = np.linspace(0.0, 1.0, int(at * sr))
        x[:len(a)] *= a
    x *= _pitch(v, g)  # slight per-variant character
    return x, sr


def _w_body(g, v, f, dur=0.40, k=26.0, gain=0.7):
    sr = SR
    n = int(dur * sr)
    t = t_axis(dur, sr)
    return np.sin(2 * np.pi * f * t) * _w_env(n, k) * gain, sr


def _w_ring(g, v, f, dur=0.5, decay=11.0, bright=0.7, gain=0.3):
    sr = SR
    p = _pitch(v, g)
    return metal_ring(f * p, dur, sr, decay, bright=bright) * gain, sr


def _w_shoot(g, v, f2=4800.0, body_f=330.0, body_g=0.75, ring_f=1600.0,
             ring_g=0.22, dur=0.42, rev=0.14):
    """One gunshot: muzzle noise + body knock + optional ringing tail."""
    sr = SR
    n = int(dur * sr)
    x = np.zeros(n)
    ng, _ = _w_noiser(g, v, f2, f1=200.0, dur=dur, k=22.0, gain=0.9)
    x += ng
    bg, _ = _w_body(g, v, body_f, dur=dur, k=26.0, gain=body_g)
    x += bg
    if ring_g > 0:
        rg, _ = _w_ring(g, v, ring_f, dur=dur, decay=12.0, bright=0.7, gain=ring_g)
        x += rg
    x = reverb(x, sr, rev, 0.32, 0.7)
    return norm(fade(x, 0.001, 0.03, sr)), sr


def _w_burst(g, v, shots=5, spacing=0.078):
    """Machine-gun burst: n cracks at fixed spacing (chatter)."""
    sr = SR
    dur = spacing * (shots - 1) + 0.35
    n = int(dur * sr)
    x = np.zeros(n)
    for i in range(shots):
        ng, _ = _w_noiser(g, v, 4200, f1=220, dur=0.24, k=30.0, gain=0.85)
        bg, _ = _w_body(g, v, 360, dur=0.24, k=34.0, gain=0.6)
        mix_at(x, norm(ng + bg, 0.9), i * spacing, 1.0)
    return norm(fade(x, 0.001, 0.03, sr)), sr


def _w_two_note(g, v, gap=0.14):
    """Two-note clack (lever action / reload slide): loud, then softer."""
    sr = SR
    n = int(0.55 * sr)
    x = np.zeros(n)
    for i, (g1, f2, k) in enumerate(((0.95, 5200, 24.0), (0.7, 3800, 26.0))):
        ng, _ = _w_noiser(g, v, f2, f1=240, dur=0.28, k=k, gain=g1)
        bg, _ = _w_body(g, v, 300, dur=0.28, k=30.0, gain=0.6)
        mix_at(x, ng + bg, i * gap, 1.0)
    return norm(fade(x, 0.001, 0.03, sr)), sr


def _w_zap(g, v, f0=1900.0, f1=260.0, dur=0.22, vib=0.12):
    sr = SR
    x = glide(f0, f1, dur, sr, kind="sine", vib=vib, vib_rate=18.0)
    x = reso(x, sr, 900.0, q=4.0) * 0.6
    noise = nburst(len(x), g, sr, f1=800, f2=6000, peak=0.7) * env_ad(len(x), 0.05, 8.0)
    return norm(fade(x * env_ad(len(x), 0.05, 7.0) + noise * 0.5, 0.001, 0.02, sr)), sr


def _w_boom(g, v, dur=1.7, f2=650.0, k=7.0, sub=46.0):
    sr = SR
    n = int(dur * sr)
    x, _ = _w_noiser(g, v, f2, f1=40.0, dur=dur, k=k, gain=1.0, at=0.02)
    x += np.sin(2 * np.pi * sub * t_axis(dur, sr)) * _w_env(n, 9.0) * 0.9
    x = reverb(x, sr, 0.45, 0.5, 1.0)
    return norm(fade(x, 0.002, 0.12, sr)), sr


def _w_chime(g, v, f=760.0, dur=0.9, decay=5.5, bright=1.0, rev=0.45):
    sr = SR
    p = _pitch(v, g)
    x = metal_ring(f * p, dur, sr, decay, bright=bright) * 0.8
    x += tone(f * 2.0 * p, dur, sr, decay=8.0, partials=((1.0, 0.3),)) * 0.25
    x = reverb(x, sr, rev, 0.55, 0.8)
    return norm(fade(x, 0.002, 0.10, sr)), sr


def _w_hum(g, v, f=118.0, dur=1.5, loop=False, vib=0.004):
    sr = SR_LOOP if loop else SR
    t = t_axis(dur, sr)
    fmod = np.sin(2 * np.pi * 1.9 * t) * f * vib * 8.0
    x = np.sin(2 * np.pi * (f + fmod) * t) * 0.7
    x += np.sin(2 * np.pi * 2 * (f + fmod) * t) * 0.25
    x += np.sin(2 * np.pi * 3 * (f + fmod) * t) * 0.08
    x = reso(x, sr, f * 4.0, q=2.0) * 0.25 + x
    if loop:
        x = loopify(x, sr, 0.5)
    return norm(fade(x, 0.01, 0.01, sr)), sr


def _w_glitch(g, v, up=True, dur=1.1):
    """Glitch static: rising (deadwalk) or falling (dissolve) bursts."""
    sr = SR
    n = int(dur * sr)
    x = np.zeros(n)
    bursts = 14
    for i in range(bursts):
        t0 = (i / bursts) * (dur - 0.05)
        L = int((0.02 + 0.045 * (i / bursts)) * sr)
        filter_args = dict(f1=600, f2=9000) if up else dict(f1=200, f2=5000)
        mix_at(x, nburst(L, g, sr, peak=0.8, **filter_args), t0, 0.6)
    f0, f1 = (120.0, 850.0) if up else (900.0, 60.0)
    x += glide(f0, f1, dur, sr, kind="saw", vib=0.5, vib_rate=11.0) * _w_env(n, 3.0) * 0.18
    return norm(fade(reverb(x, sr, 0.25, 0.4, 0.8), 0.002, 0.05, sr)), sr


def _w_dig(g, v, scoops=3, dur=1.25):
    """Shovel burial: 2-3 scoops of filtered dirt, then a settle thump."""
    sr = SR
    n = int(dur * sr)
    x = np.zeros(n)
    step = 0.30
    for i in range(scoops):
        L = int(0.16 * sr)
        d = nburst(L, g, sr, f1=120, f2=2600, peak=0.9) * env_ad(L, 0.18, 5.0)
        t = thump(85, 0.16, sr, 9.0) * 0.8
        mix_at(x, d + t, i * step, 1.0)
    mix_at(x, thump(70, 0.25, sr, 8.0), scoops * step - 0.05, 0.9)
    return norm(fade(x, 0.002, 0.04, sr)), sr


def _w_whoosh(g, v, f0=300.0, f1=1300.0, dur=0.45, noise_f2=1800.0):
    sr = SR
    n = int(dur * sr)
    x = glide(f0, f1, dur, sr, kind="sine", vib=0.3, vib_rate=8.0) * _w_env(n, 4.0) * 0.5
    x += nburst(n, g, sr, f1=f0 * 0.7, f2=noise_f2) * _w_env(n, 4.5) * 0.8
    return norm(fade(x, 0.002, 0.03, sr)), sr


def _w_servo(g, v):
    """Turret deploy: three metal clicks then a short servo whine."""
    sr = SR
    n = int(0.7 * sr)
    x = np.zeros(n)
    for i, f in enumerate((520.0, 430.0, 360.0)):
        mix_at(x, knock(f, 0.16, sr, 9.0) * 0.8, i * 0.09, 1.0)
    whine = glide(280, 520, 0.32, sr) * env_ad(int(0.32 * sr), 0.2, 4.0) * 0.35
    mix_at(x, whine, 0.28, 1.0)
    return norm(fade(x, 0.001, 0.03, sr)), sr


def _w_chirp(g, v, f0=640.0, f1=1500.0, dur=0.22):
    sr = SR
    n = int(dur * sr)
    x = np.zeros(n)
    half = int(0.09 * sr)
    mix_at(x, glide(f0, f1, 0.09, sr) * env_ad(half, 0.1, 6.0), 0.0, 0.8)
    mix_at(x, glide(f0 * 1.2, f1 * 1.3, 0.09, sr) * env_ad(half, 0.1, 8.0), 0.11, 0.7)
    mix_at(x, metal_ring(2200, 0.12, sr, 14.0, bright=1.2) * 0.4, 0.20, 1.0)
    return norm(fade(x, 0.001, 0.02, sr)), sr


def _w_powerdown(g, v, dur=0.62):
    sr = SR
    n = int(dur * sr)
    x = glide(820, 110, dur, sr, kind="saw", vib=0.25, vib_rate=13.0) * _w_env(n, 3.4) * 0.55
    x += nburst(n, g, sr, f1=300, f2=4000, peak=0.5) * _w_env(n, 5.0) * 0.5
    return norm(fade(reverb(x, sr, 0.2, 0.4, 0.8), 0.002, 0.04, sr)), sr


def _w_sweep(g, v, up=True):
    sr = SR
    dur = 0.24
    n = int(dur * sr)
    if up:
        x = glide(420, 1500, dur, sr, kind="sine", vib=0.15, vib_rate=10.0)
    else:
        x = glide(1500, 420, dur, sr, kind="sine", vib=0.15, vib_rate=10.0)
    x += nburst(n, g, sr, f1=900, f2=5200, peak=0.5) * env_ad(n, 0.1, 7.0)
    return norm(fade(x, 0.002, 0.02, sr)), sr


def _w_break(g, v):
    """Blade / severance break: snap, ping, then shard rain."""
    sr = SR
    n = int(0.6 * sr)
    x = np.zeros(n)
    mix_at(x, nburst(int(0.05 * sr), g, sr, f1=1400, f2=9500, peak=0.95), 0.0, 1.0)
    mix_at(x, metal_ring(2900, 0.4, sr, 10.0, bright=1.3) * 0.7, 0.01, 1.0)
    for i in range(6):
        mix_at(x, nburst(int(0.03 * sr), g, sr, f1=2200, f2=8000, peak=0.5),
               0.08 + 0.05 * i + g.random() * 0.03, 1.0)
    return norm(fade(reverb(x, sr, 0.22, 0.4, 0.8), 0.001, 0.05, sr)), sr


def _w_mm_strike(g, v):
    sr = SR
    dur = 0.4
    n = int(dur * sr)
    x = thump(92, dur, sr, 11.0) * 0.95
    x += knock(250, dur, sr, 8.0) * 0.5
    x += nburst(n, g, sr, f1=350, f2=5500, peak=0.7) * env_ad(n, 0.08, 6.0) * 0.6
    return norm(fade(reverb(x, sr, 0.2, 0.35, 0.7), 0.001, 0.03, sr)), sr



def _w_fab_done(g, v):
    """Fabricator completion: the two-note chime over a relay click."""
    sr = SR
    x = tone(880, 0.6, sr, decay=6.0) * 0.7
    x += tone(1320, 0.6, sr, decay=6.0, partials=((1.0, 0.5),)) * 0.4
    click = nburst(int(0.05 * sr), g, sr, f1=2500, f2=9000, peak=0.5) * 0.6
    x[:len(click)] += click
    return norm(fade(reverb(x, sr, 0.3, 0.45, 0.7), 0.002, 0.06, sr)), sr

def _w_fab_start(g, v):
    """Fabricator spin-up: click then the working hum swells in."""
    sr = SR
    n = int(1.6 * sr)
    x = np.zeros(n)
    hum, _ = _w_hum(g, v, f=96, dur=1.6, loop=False, vib=0.005)
    at = np.linspace(0.0, 1.0, int(0.25 * sr))
    hum[:len(at)] *= at
    x += hum
    mix_at(x, knock(600, 0.1, sr, 12.0) * 0.5, 0.0, 1.0)
    return norm(fade(x, 0.002, 0.05, sr)), sr


# --------------------------------------------------------------------------
# sl_weapons family table: name -> builder(g, v) -> (samples, sr)
# --------------------------------------------------------------------------

WEAPONS_FAMILY = {
    "sl_weapons_pistol_fire": lambda g, v: _w_shoot(g, v, f2=4800, body_f=330, body_g=0.7, ring_f=1700, ring_g=0.20, rev=0.12),
    "sl_weapons_pistol": lambda g, v: _w_shoot(g, v, f2=4800, body_f=330, body_g=0.7, ring_f=1700, ring_g=0.20, rev=0.12),
    "sl_weapons_chatter_fire": lambda g, v: _w_burst(g, v, shots=5, spacing=0.078),
    "sl_weapons_scatter_fire": lambda g, v: _w_shoot(g, v, f2=3600, body_f=140, body_g=1.0, ring_f=700, ring_g=0.5, dur=0.6, rev=0.28),
    "sl_weapons_lance_fire": lambda g, v: _w_shoot(g, v, f2=5200, body_f=260, body_g=0.75, ring_f=2600, ring_g=0.85, dur=0.8, rev=0.32),
    "sl_weapons_six_fire": lambda g, v: _w_shoot(g, v, f2=4000, body_f=200, body_g=0.95, ring_f=1150, ring_g=0.45, dur=0.55, rev=0.2),
    "sl_weapons_repeater_fire": lambda g, v: _w_two_note(g, v, gap=0.14),
    "sl_weapons_pulse_fire": lambda g, v: _w_zap(g, v),
    "sl_weapons_mortar_launch": lambda g, v: _w_whoosh(g, v, f0=250, f1=900, dur=0.5),
    "sl_weapons_explosion": lambda g, v: _w_boom(g, v),
    "sl_weapons_spark_hit": lambda g, v: (norm(fade(metal_ring(3400, 0.14, SR, 13.0, bright=1.4) * 0.8 + nburst(int(0.14 * SR), g, SR, f1=1800, f2=9000, peak=0.5) * env_exp(int(0.14 * SR), 16.0), 0.001, 0.02, SR)), SR),
    "sl_weapons_dry_click": lambda g, v: (norm(fade(nburst(int(0.055 * SR), g, SR, f1=2600, f2=9000, peak=1.0) + knock(900, 0.055, SR, 12.0) * 0.35, 0.0005, 0.03, SR)), SR),
    "sl_weapons_ammo_load": lambda g, v: _w_two_note(g, v, gap=0.07),
    "sl_weapons_body_falls": lambda g, v: (norm(fade(reverb(thump(105, 0.4, SR, 9.0) * 0.9 + knock(190, 0.4, SR, 9.0) * 0.5 + nburst(int(0.4 * SR), g, SR, f1=120, f2=1200, peak=0.5) * env_exp(int(0.4 * SR), 9.0) * 0.5, SR, 0.25, 0.4, 0.7), 0.001, 0.05, SR)), SR),
    "sl_weapons_exorcise": lambda g, v: (norm(fade(reverb(glide(1500, 240, 0.75, SR, kind="sine", vib=0.4, vib_rate=9.0) * _w_env(int(0.75 * SR), 3.0) * 0.7 + nburst(int(0.75 * SR), g, SR, f1=500, f2=6000, peak=0.4) * _w_env(int(0.75 * SR), 4.5), SR, 0.5, 0.55, 1.0), 0.002, 0.08, SR)), SR),
    "sl_weapons_dissolve": lambda g, v: _w_glitch(g, v, up=False, dur=0.9),
    "sl_weapons_deadwalk_rise": lambda g, v: _w_glitch(g, v, up=True, dur=1.2),
    "sl_weapons_puppet_collapse": lambda g, v: (norm(fade(nburst(int(0.5 * SR), g, SR, f1=80, f2=1800, peak=0.85) * _w_env(int(0.5 * SR), 8.0) + thump(78, 0.5, SR, 9.0) * 0.9, 0.001, 0.06, SR)), SR),
    "sl_weapons_cremation": lambda g, v: (norm(fade(reverb(_w_noiser(g, v, 520, f1=30, dur=2.2, k=4.0, gain=1.0, at=0.25)[0] + np.sin(2 * np.pi * 38 * t_axis(2.2, SR)) * _w_env(int(2.2 * SR), 5.0) * 0.8, SR, 0.55, 0.5, 1.0), 0.01, 0.25, SR)), SR),
    "sl_weapons_shovel_bury": lambda g, v: _w_dig(g, v),
    "sl_weapons_loot_hum": lambda g, v: _w_hum(g, v, f=170, dur=1.6, loop=True, vib=0.01),
    "sl_weapons_fab_start": lambda g, v: _w_fab_start(g, v),
    "sl_weapons_fab_hum": lambda g, v: _w_hum(g, v, f=96, dur=10.0, loop=True, vib=0.006),
    "sl_weapons_fab_done": lambda g, v: _w_fab_done(g, v),
    "sl_weapons_pad_chime": lambda g, v: _w_chime(g, v),
    "sl_weapons_lash_launch": lambda g, v: (norm(fade(_w_shoot(g, v, f2=5400, body_f=400, body_g=0.5, ring_f=3200, ring_g=0.4, dur=0.3, rev=0.15)[0] + _w_whoosh(g, v, f0=400, f1=1500, dur=0.3)[0] * 0.6, 0.001, 0.03, SR)), SR),
    "sl_weapons_lash_bite": lambda g, v: (norm(fade(metal_ring(2400, 0.16, SR, 12.0, bright=1.3) * 0.8 + nburst(int(0.16 * SR), g, SR, f1=1200, f2=8500, peak=0.9) * env_exp(int(0.16 * SR), 14.0), 0.001, 0.02, SR)), SR),
    "sl_weapons_lash_snap": lambda g, v: (norm(fade(nburst(int(0.25 * SR), g, SR, f1=1500, f2=9000, peak=1.0) * env_exp(int(0.25 * SR), 22.0) + metal_ring(3200, 0.25, SR, 12.0, bright=1.2) * 0.6, 0.001, 0.05, SR)), SR),
    "sl_weapons_mm_strike": lambda g, v: _w_mm_strike(g, v),
    "sl_weapons_turret_acquire": lambda g, v: _w_chirp(g, v),
    "sl_weapons_turret_deploy": lambda g, v: _w_servo(g, v),
    "sl_weapons_turret_fire": lambda g, v: (norm(fade(_w_zap(g, v, f0=1400, f1=500, dur=0.14)[0] + tone(880, 0.14, SR, decay=9.0) * 0.4, 0.001, 0.02, SR)), SR),
    "sl_weapons_turret_hit": lambda g, v: (norm(fade(metal_ring(2600, 0.2, SR, 12.0, bright=1.2) * 0.8, 0.001, 0.03, SR)), SR),
    "sl_weapons_turret_death": lambda g, v: _w_powerdown(g, v, dur=0.7),
    "sl_weapons_turret_powerdown": lambda g, v: _w_powerdown(g, v, dur=0.4),
    "sl_weapons_zoom_in": lambda g, v: _w_sweep(g, v, up=True),
    "sl_weapons_zoom_out": lambda g, v: _w_sweep(g, v, up=False),
    "sl_weapons_blade_break": lambda g, v: _w_break(g, v),
    "sl_weapons_severance_break": lambda g, v: _w_break(g, v),
}


# file -> recipe resolution
# --------------------------------------------------------------------------

SPECIAL = {
    "beep-boop.ogg": ("beep_boop", 0),
    "lava-sfx_121823.ogg": ("lava_sfx", 0),
    "menu_music.ogg": ("menu_music", 0),
    "old-sound.ogg": ("old_sound", 0),
    "piano_short.ogg": ("piano_short", 0),
    "scratchy_pine_leaves.ogg": ("scratchy_pine", 0),
    "achievement_unlock.ogg": ("achievement", 0),
    "level_up.ogg": ("level_up", 0),
    "level_up_sound.ogg": ("level_up_sound", 0),
    "creepy_ambient.ogg": ("creepy_ambient", 0),
    "alert.ogg": ("alert", 0),
    "ambience.ogg": ("ambience", 0),
    "click.ogg": ("click", 0),
    "damage.ogg": ("damage", 0),
    "footstep_metal.ogg": ("footstep_metal", 0),
    "footstep_water.ogg": ("footstep_water", 0),
    "hit.ogg": ("hit", 0),
    "monster_chase.ogg": ("monster_chase", 0),
    "monster_idle.ogg": ("monster_idle", 0),
    "music.ogg": ("music", 0),
    "place.ogg": ("place", 0),
    "radio_static.ogg": ("radio_static", 0),
    "swim.ogg": ("swim", 0),
    "A_A.ogg": ("A_A", 0),
    "A_A1.ogg": ("A_A", 1),
    "A_A2.ogg": ("A_A", 2),
    "mob_death.ogg": ("mob_death", 0),
    "mob_idle.ogg": ("mob_idle", 0),
    "random_dizz.ogg": ("random_dizz", 0),
    "scary_attack.ogg": ("scary_attack", 0),
    "default_tool_break.ogg": ("tool_break", 0),
    "player_damage.ogg": ("player_damage", 0),
}

SPECIAL.update({
    f"{n}.ogg": (n, 0) for n in WEAPONS_FAMILY
})

DEFAULT_FAMILY = {
    "default_break_glass": "break_glass",
    "default_chest_close": "chest_close",
    "default_chest_open": "chest_open",
    "default_cool_lava": "cool_lava",
    "default_dig_choppy": "dig_choppy",
    "default_dig_cracky": "dig_cracky",
    "default_dig_crumbly": "dig_crumbly",
    "default_dig_dig_immediate": "dig_immediate",
    "default_dig_metal": "dig_metal",
    "default_dig_oddly_breakable_by_hand": "dig_oddly",
    "default_dig_snappy": "dig_snappy",
    "default_dirt_footstep": "footstep_dirt",
    "default_dug_metal": "dug_metal",
    "default_dug_node": "dug_node",
    "default_furnace_active": "furnace",
    "default_glass_footstep": "footstep_glass",
    "default_grass_footstep": "footstep_grass",
    "default_gravel_dig": "dig_gravel",
    "default_gravel_dug": "dug_gravel",
    "default_gravel_footstep": "footstep_gravel",
    "default_hard_footstep": "footstep_hard",
    "default_ice_dig": "dig_ice",
    "default_ice_dug": "dug_ice",
    "default_ice_footstep": "footstep_ice",
    "default_item_smoke": "item_smoke",
    "default_metal_footstep": "footstep_metal",
    "default_place_node": "place_node",
    "default_place_node_hard": "place_node_hard",
    "default_place_node_metal": "place_node_metal",
    "default_sand_footstep": "footstep_sand",
    "default_snow_footstep": "footstep_snow",
    "default_tool_breaks": "tool_breaks",
    "default_water_footstep": "footstep_water",
    "default_wood_footstep": "footstep_wood",
}

RECIPES = {
    "click": r_click,
    "hit": r_hit,
    "place": r_place,
    "alert": r_alert,
    "damage": r_damage,
    "achievement": r_achievement,
    "level_up": r_level_up,
    "level_up_sound": r_level_up_sound,
    "footstep_metal": _mk_footstep("metal"),
    "footstep_water": _mk_footstep("water"),
    "swim": r_swim,
    "ambience": r_ambience,
    "music": r_music,
    "monster_idle": r_monster_idle,
    "monster_chase": r_monster_chase,
    "radio_static": r_radio_static,
    "scary_attack": r_scary_attack,
    "A_A": r_A_A,
    "mob_idle": r_mob_idle,
    "mob_death": r_mob_death,
    "random_dizz": r_random_dizz,
    "creepy_ambient": r_creepy_ambient,
    "dig_choppy": r_dig_choppy,
    "dig_cracky": r_dig_cracky,
    "dig_crumbly": r_dig_crumbly,
    "dig_immediate": r_dig_immediate,
    "dig_metal": r_dig_metal,
    "dig_oddly": r_dig_oddly,
    "dig_snappy": r_dig_snappy,
    "dug_node": r_dug_node,
    "dug_metal": r_dug_metal,
    "place_node": r_place_node,
    "place_node_hard": r_place_node_hard,
    "place_node_metal": r_place_node_metal,
    "break_glass": r_break_glass,
    "chest_open": r_chest_open,
    "chest_close": r_chest_close,
    "cool_lava": r_cool_lava,
    "furnace": r_furnace,
    "item_smoke": r_item_smoke,
    "tool_breaks": r_tool_breaks,
    "tool_break": r_tool_break,
    "player_damage": r_player_damage,
    "footstep_dirt": _mk_footstep("dirt"),
    "footstep_grass": _mk_footstep("grass"),
    "footstep_gravel": _mk_footstep("gravel"),
    "footstep_sand": _mk_footstep("sand"),
    "footstep_snow": _mk_footstep("snow"),
    "footstep_hard": _mk_footstep("hard"),
    "footstep_wood": _mk_footstep("wood"),
    "footstep_ice": _mk_footstep("ice"),
    "footstep_glass": _mk_footstep("glass"),
    "dig_gravel": _mk_footstep("gravel"),
    "dug_gravel": _mk_footstep("gravel"),
    "dig_ice": _mk_footstep("ice"),
    "dug_ice": _mk_footstep("ice"),
    "beep_boop": r_beep_boop,
    "lava_sfx": r_lava_sfx,
    "menu_music": r_menu_music,
    "old_sound": r_old_sound,
    "piano_short": r_piano_short,
    "scratchy_pine": r_scratchy_pine,
}

RECIPES.update(WEAPONS_FAMILY)


def resolve(filename: str):
    if filename in SPECIAL:
        return SPECIAL[filename]
    base = filename.split(".")[0]
    variant = 0
    parts = filename.split(".")
    if len(parts) >= 3 and parts[1].isdigit():
        variant = int(parts[1])
    if base in DEFAULT_FAMILY:
        return DEFAULT_FAMILY[base], variant
    raise KeyError(f"no recipe for {filename}")


# --------------------------------------------------------------------------
# encode + write
# --------------------------------------------------------------------------

def _ogg_crc(page: bytes) -> int:
    """Ogg page CRC-32 (poly 0x04C11DB7, init 0, no final xor, MSB-first)."""
    crc = 0
    for b in page:
        crc ^= b << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if (crc & 0x80000000) else (crc << 1) & 0xFFFFFFFF
    return crc


def _fix_ogg_headers(data: bytes, serial: int) -> bytes:
    """libsndfile randomises the Ogg serial per write; pin it so the bytes are
    reproducible, and recompute the per-page CRCs to stay valid."""
    out = bytearray(data)
    pos = 0
    while pos < len(out):
        assert bytes(out[pos:pos + 4]) == b"OggS"
        segs = out[pos + 26]
        body = sum(out[pos + 27:pos + 27 + segs])
        end = pos + 27 + segs + body
        out[pos + 14:pos + 18] = serial.to_bytes(4, "little")
        out[pos + 22:pos + 26] = b"\x00\x00\x00\x00"
        crc = _ogg_crc(bytes(out[pos:end]))
        out[pos + 22:pos + 26] = crc.to_bytes(4, "little")
        pos = end
    return bytes(out)


def encode(x: np.ndarray, sr: int, quality: float = 1.0, name: str = "") -> bytes:
    # kill DC offset / subsonic drift (brown-noise beds etc.), then re-normalise
    x = hp(x, sr, 28, 1)
    x = x - float(np.mean(x))
    m = float(np.max(np.abs(x)))
    if m > 1e-9:
        x = x / m * PEAK
    buf = io.BytesIO()
    sf.write(buf, x.astype(np.float32), sr, format="OGG", subtype="VORBIS",
             compression_level=quality)
    data = buf.getvalue()
    serial = int(hashlib.md5(name.encode()).hexdigest(), 16) & 0xFFFFFFFF
    return _fix_ogg_headers(data, serial)


def main() -> int:
    targets = []
    for p in sorted(ROOT.rglob("*.ogg")):
        if ".git" in p.parts:
            continue
        targets.append(p)
    # referenced in code but missing — generate them too
    targets += [
        ROOT / "mods/default/sounds/default_tool_break.ogg",
        ROOT / "mods/apis/sl_gui/sounds/level_up_sound.ogg",
    ]
    targets += [
        ROOT / "mods/game/sl_weapons/sounds" / (n + ".ogg")
        for n in WEAPONS_FAMILY
    ]

    total_new = total_old = 0
    rows = []
    for path in sorted(set(targets)):
        name = path.name
        family, variant = resolve(name)
        g = rng(family, variant)
        samples, sr = RECIPES[family](g, variant)
        quality = 1.0
        if family in ("music", "menu_music", "ambience", "creepy_ambient",
                      "old_sound", "piano_short", "lava_sfx", "beep_boop",
                      "scratchy_pine"):
            quality = 0.95
        data = encode(samples, sr, quality, name)
        # round-trip check
        rt, rtsr = sf.read(io.BytesIO(data))
        dur_new = len(rt) / rtsr
        dur_want = len(samples) / sr
        if abs(dur_new - dur_want) > 0.25 * dur_want:
            print(f"!! duration mismatch {name}: want {dur_want:.2f}s got {dur_new:.2f}s")
        rms = float(np.sqrt(np.mean(rt ** 2)))
        if rms < 0.01:
            print(f"!! nearly silent {name}: rms={rms:.4f}")

        old = path.stat().st_size if path.exists() else 0
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        rows.append((str(path.relative_to(ROOT)), old, len(data), round(dur_want, 2)))
        total_new += len(data)
        total_old += old

    print(f"{'file':60s} {'old B':>8s} {'new B':>8s} {'dur s':>7s}")
    for rel, old, new, d in rows:
        mark = " <=" if new > old else ""
        print(f"{rel:60s} {old:8d} {new:8d} {d:7.2f}{mark}")
    print(f"\nold total: {total_old} bytes   new total: {total_new} bytes   "
          f"({100 * total_new / max(total_old, 1):.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
