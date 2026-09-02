#!/usr/bin/env python3
"""
tools/texgen_make_bases.py — write the shared base textures used by the
sl_texgen runtime [combine programs.

sl_texgen compiles every generated texture to a pure texture-modifier
program ("[combine:...") that the *client* renders.  The modifier
language has no rect/gradient/noise primitives, so a handful of tiny
grayscale bases ship as real media files (texture-packable, cached,
sent once) and everything else — color, layout, animation, labels —
happens in the client-side program:

  stx_px.png      1x1 white (solid fills via ^[resize; engine blank.png
                  is used when available, this is the fallback/pack one)
  stx_glow.png    128x128 white radial gradient (glows, puffs, embers)
  stx_ring.png    128x128 white soft ring (plasma rings, bubbles, portals)
  stx_noise.png   64x64 grayscale TV static (facade speckle, sus_nodes)
  stx_noise_rgb.png 64x64 rainbow static (sus_nodes rainbow variant)
  stx_x.png       64x64 soft diagonal cross (x_neon / x2_neon)
  stx_rhombus.png 64x64 soft rhombus outline (rhombus_neon)
  stx_font.png    64x64 font atlas, 3x5 glyphs at scale 2 (6x10 cells,
                  8 columns, 1px padding; white glyphs on transparent)

Deterministic: run twice, byte-identical.  tools/texgen_check.py
--verify regenerates and compares.
"""
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "mods/apis/sl_texgen/textures"

# same 3x5 glyph set as the old canvas.lua micro font
GLYPHS = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111",
    "3": "111001111001111", "4": "101101111001001", "5": "111100111001111",
    "6": "111100111101111", "7": "111001010010010", "8": "111101111101111",
    "9": "111101111001111",
    "a": "010101111101101", "b": "110101110101110", "c": "011100100100011",
    "d": "110101101101110", "e": "111100110100111", "f": "011100110100100",
    "g": "011100101101011", "h": "100100111101101", "i": "010000010010010",
    "j": "001001001101010", "k": "101110100110101", "l": "100100100100011",
    "m": "101111111101101", "n": "110101101101101", "o": "010101101101010",
    "p": "110101110100100", "q": "010101101110011", "r": "110101100100100",
    "s": "011100010001110", "t": "111010010010010", "u": "101101101101011",
    "v": "101101101010010", "w": "101101111111101", "x": "101101010101101",
    "y": "101101011001110", "z": "111001010100111",
    " ": "000000000000000", "_": "000000000000111", "-": "000000111000000",
    ".": "000000000000010", ",": "000000000101000", "/": "001001010100100",
    "(": "001010010010010", ")": "100010010100100", ":": "000010000010000",
    "=": "000111000111000", "+": "000010111010000", "!": "010010010000010",
    "'": "010010000000000", "%": "101001010100101", "?": "111001011000010",
}


def write_png(path: Path, w: int, h: int, px: bytes) -> None:
    raw = b"".join(b"\x00" + px[y * w * 4:(y + 1) * w * 4] for y in range(h))

    def chunk(t: bytes, d: bytes) -> bytes:
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def canvas(w: int, h: int, rgba=(0, 0, 0, 0)) -> bytearray:
    buf = bytearray(w * h * 4)
    for i in range(w * h):
        buf[i * 4:i * 4 + 4] = bytes(rgba)
    return buf


def put(buf, w, x, y, r, g, b, a):
    if 0 <= x < w and 0 <= y < len(buf) // (w * 4):
        o = (int(y) * w + int(x)) * 4
        sa = a / 255.0
        da = buf[o + 3] / 255.0
        oa = sa + da * (1 - sa)
        if oa <= 0:
            return
        k0, k1 = sa / oa, (da * (1 - sa)) / oa
        for i, v in enumerate((r, g, b)):
            buf[o + i] = int(v * k0 + buf[o + i] * k1)
        buf[o + 3] = int(oa * 255)


def make_px():
    return canvas(1, 1, (255, 255, 255, 255)), 1, 1


def make_glow(size=128):
    """White radial gradient: opaque center, transparent edge (smooth)."""
    buf = canvas(size, size)
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / (size / 2)
            if d < 1.0:
                # smooth falloff (1-d)^2 keeps a soft, pack-friendly glow
                a = int(round(255 * (1 - d) ** 2))
                o = (y * size + x) * 4
                buf[o:o + 3] = b"\xff\xff\xff"
                buf[o + 3] = a
    return buf, size, size


def make_ring(size=128):
    """White soft ring at radius 0.36*size, thickness ~0.10*size."""
    buf = canvas(size, size)
    c = (size - 1) / 2
    r0, w0 = 0.36 * size, 0.10 * size
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c)
            t = abs(d - r0) / w0
            if t < 1.0:
                a = int(round(255 * (1 - t) ** 1.5))
                o = (y * size + x) * 4
                buf[o:o + 3] = b"\xff\xff\xff"
                buf[o + 3] = a
    return buf, size, size


def lcg(seed):
    s = seed & 0xFFFFFFFF
    while True:
        s = (s * 1103515245 + 12345) & 0xFFFFFFFF
        yield s / 0x100000000


def make_noise(size=64, rgb=False, seed=1234):
    buf = canvas(size, size)
    R = lcg(seed)
    for y in range(size):
        for x in range(size):
            v = next(R)
            if rgb:
                r = int((math.sin((x + v * 255) * 0.12) * 0.5 + 0.5) * 255)
                g = int((math.sin((y + v * 255) * 0.10 + 2) * 0.5 + 0.5) * 255)
                b = int((math.sin((x + y + v * 255) * 0.08 + 4) * 0.5 + 0.5) * 255)
                o = (y * size + x) * 4
                buf[o], buf[o + 1], buf[o + 2], buf[o + 3] = r, g, b, 255
            else:
                g = int(v * 255)
                o = (y * size + x) * 4
                buf[o], buf[o + 1], buf[o + 2], buf[o + 3] = g, g, g, 255
    return buf, size, size


def make_x(size=64):
    """Soft diagonal cross (light glow arms on transparent bg)."""
    buf = canvas(size, size)
    m = size * 0.14
    for i in range(int(size - 2 * m)):
        t = m + i
        for off in range(-2, 3):
            a = 150 - abs(off) * 40
            put(buf, size, t, t + off, 255, 255, 255, a)
            put(buf, size, size - 1 - t, t + off, 255, 255, 255, a)
    return buf, size, size


def make_rhombus(size=64):
    buf = canvas(size, size)
    m = size * 0.14
    c = size / 2
    # outline via distance to the four edges of a rotated square
    for y in range(size):
        for x in range(size):
            d = abs(x - c) + abs(y - c)  # manhattan radius
            if abs(d - (size / 2 - m)) < 1.8:
                put(buf, size, x, y, 255, 255, 255, 170)
    return buf, size, size


def make_font():
    """Atlas: 8 columns of 8x12 cells (glyph 6x10 at +1,+1); rows grow
    with the glyph count so nothing is clipped."""
    CW, CH = 8, 12
    cols = 8
    rows = (len(GLYPHS) + cols - 1) // cols
    W, H = cols * CW, rows * CH
    buf = canvas(W, H)
    for i, ch in enumerate(sorted(GLYPHS)):
        g = GLYPHS[ch]
        cx, cy = (i % cols) * CW + 1, (i // cols) * CH + 1
        for r in range(5):
            for c in range(3):
                if g[r * 3 + c] == "1":
                    for sy in range(2):
                        for sx in range(2):
                            put(buf, W, cx + c * 2 + sx, cy + r * 2 + sy,
                                255, 255, 255, 255)
    return buf, W, H


def main() -> int:
    bases = [
        ("stx_px.png", make_px()),
        ("stx_glow.png", make_glow()),
        ("stx_ring.png", make_ring()),
        ("stx_noise.png", make_noise(rgb=False)),
        ("stx_noise_rgb.png", make_noise(rgb=True)),
        ("stx_x.png", make_x()),
        ("stx_rhombus.png", make_rhombus()),
        ("stx_font.png", make_font()),
    ]
    total = 0
    for name, (buf, w, h) in bases:
        path = OUT / name
        write_png(path, w, h, bytes(buf))
        size = path.stat().st_size
        total += size
        print(f"  {name:22s} {w}x{h}  {size} B")
    print(f"total {total / 1024:.1f} KiB -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
