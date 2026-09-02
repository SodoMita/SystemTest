#!/usr/bin/env python3
"""Re-ink the sl_scary mob strips at higher resolution + wire-glow palette.

Owner direction (2026-09-02, art baseline gate):
  * strict colour palette (a few colours, binary alpha, no anti-aliasing)
  * the game's content surfaces are 32px+; mobs may be higher resolution
  * mobs must match the game's neon "wire glow" theme

The shipped strips are 16x16 frames from the Seirin toolchain.  Rather
than stretching those soft frames, each frame is re-inked onto a strict
palette (pure-black silhouette + the mob's two accent colours; every
pixel opaque or transparent, no anti-aliased alpha) and scaled 4x
(nearest-neighbour) to 64x64 frames -> 64x576 vertical strips (9 frames,
same order: idle rows 0-2, walk 3-5, attack 6-7, death row 8).
Deterministic, pixel-exact, stdlib only.

Palettes (kept from each mob's spec in GENERATED_ASSETS.md):
  dredger     black + rust-orange #CC6622 + neon-green #00FF41
  wraith      black + deep-void-purple #1A0033 + neon-cyan #00FFFF
  containment black + deep-crimson #8B0000 + neon-amber #FFBF00

    python3 reink_mobs.py            # rewrites the three *_strip.png
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from transpose_sprite_strip import read_png, write_png  # noqa: E402

TEX = os.path.normpath(os.path.join(HERE, "..", "textures"))
SCALE = 4  # 16px frames -> 64px frames

MOBS = {
    "dredger":     [(0xCC, 0x66, 0x22), (0x00, 0xFF, 0x41)],
    "wraith":      [(0x1A, 0x00, 0x33), (0x00, 0xFF, 0xFF)],
    "containment": [(0x8B, 0x00, 0x00), (0xFF, 0xBF, 0x00)],
}
BLACK = (0, 0, 0)


def nearest(palette, r, g, b):
    best, bd = None, None
    for p in palette:
        dr, dg, db = p[0] - r, p[1] - g, p[2] - b
        d = dr * dr * 3 + dg * dg * 6 + db * db  # green-weighted, human-ish
        if bd is None or d < bd:
            bd, best = d, p
    return best


def reink(src, dst, accents):
    w, h, ctype, plte, trns, rows = read_png(src)
    if ctype != 6:
        raise ValueError("expected RGBA input: %s" % src)
    if w != 16 or h % 16 != 0:
        raise ValueError("expected 16-wide vertical strip: %s" % src)
    frames = h // 16
    palette = [BLACK] + list(accents)
    ch = 4
    rows_out = []
    for y in range(h):
        row = rows[y]
        newrow = bytearray(w * ch)
        for x in range(w):
            q = row[x * ch:(x + 1) * ch]
            if q[3] < 64:
                continue  # transparent, binary alpha
            p = nearest(palette, q[0], q[1], q[2])
            newrow[x * ch:x * ch + 3] = bytes(p)
            newrow[x * ch + 3] = 255
        for _ in range(SCALE):
            rows_out.append(bytes(newrow))
    # nearest-neighbour scale in x
    big = []
    for row in rows_out:
        expanded = bytearray()
        for x in range(w):
            px = row[x * ch:(x + 1) * ch]
            for _ in range(SCALE):
                expanded += px
        big.append(bytes(expanded))
    write_png(dst, w * SCALE, h * SCALE, 6, b"", b"", big)
    print("%s -> %s (%dx%d, %d frames @ %dx%d)"
          % (src, dst, w * SCALE, h * SCALE, frames, w * SCALE, 16 * SCALE))


def main():
    for name, accents in MOBS.items():
        src = os.path.join(TEX, "sl_scary_%s_strip.png" % name)
        if not os.path.exists(src):
            print("skip (missing):", src)
            continue
        reink(src, src, accents)


if __name__ == "__main__":
    main()
