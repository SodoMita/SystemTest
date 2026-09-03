#!/usr/bin/env python3
"""Procedural batch E — weapon FX sprites (deterministic, stdlib only).

Replaces the 16x16 placeholders for: blast, grit, hit, spark, tracer,
lash_hook, lash_line, mortar_shell, pulse_bolt. Radial/burst glows at
256x256 RGBA, additive-look (bright core -> transparent rim). Palette
follows the system rule: tracers/beams cyan/white; fire amber/white.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mods",
                                "content", "sl_scary", "pipeline"))
from transpose_sprite_strip import write_png  # noqa: E402

S = 256
CX = CY = 128


def new():
    return [[(0, 0, 0, 0)] * S for _ in range(S)]


def add_radial(img, cx, cy, r_in, r_out, col, amax=255, falloff=2.0):
    """Add a radial glow: full `col` inside r_in, fading to 0 at r_out.
    Alpha is premultiplied-look (col scaled by intensity)."""
    for dy in range(-int(r_out) - 1, int(r_out) + 2):
        for dx in range(-int(r_out) - 1, int(r_out) + 2):
            x, y = cx + dx, cy + dy
            if not (0 <= x < S and 0 <= y < S):
                continue
            d = math.hypot(dx, dy)
            if d > r_out:
                continue
            if d <= r_in:
                t = 1.0
            else:
                t = max(0.0, 1.0 - (d - r_in) / (r_out - r_in)) ** falloff
            a = int(amax * t)
            if a <= 0:
                continue
            px = img[y][x]
            na = px[3] + a * (255 - px[3]) / 255
            if na <= 0:
                continue
            f = a / na
            r = int(px[0] * (1 - f) + col[0] * f)
            g = int(px[1] * (1 - f) + col[1] * f)
            b = int(px[2] * (1 - f) + col[2] * f)
            img[y][x] = (r, g, b, int(na))


def line(img, x0, y0, x1, y1, col, width=1.0, a=255):
    n = max(int(math.hypot(x1 - x0, y1 - y0)) * 2, 1)
    for i in range(n + 1):
        t = i / n
        x = int(round(x0 + (x1 - x0) * t))
        y = int(round(y0 + (y1 - y0) * t))
        r = max(1, int(width))
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r and 0 <= x + dx < S and 0 <= y + dy < S:
                    img[y + dy][x + dx] = (col[0], col[1], col[2], a)


def blob(img, x, y, r, col, a=200):
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r and 0 <= x + dx < S and 0 <= y + dy < S:
                img[y + dy][x + dx] = (col[0], col[1], col[2], a)


def clamp_col(c):
    return tuple(max(0, min(255, int(v))) for v in c)


def write(img, path):
    rows = []
    for y in range(S):
        rows.append(bytes(v for px in img[y] for v in px))
    write_png(path, S, S, 6, b"", b"", rows)
    print(path, os.path.getsize(path), "bytes")


def make_blast():
    img = new()
    add_radial(img, CX, CY, 0, 46, (255, 250, 235), 255, 1.6)
    add_radial(img, CX, CY, 30, 118, (255, 160, 60), 235, 2.2)
    add_radial(img, CX, CY, 70, 124, (255, 110, 30), 110, 3.0)
    rng = random.Random(7)
    for _ in range(26):  # irregular tongues
        ang = rng.uniform(0, math.tau)
        d0 = rng.uniform(70, 112)
        d1 = d0 + rng.uniform(10, 30)
        lx0 = CX + math.cos(ang) * d0
        ly0 = CY + math.sin(ang) * d0
        lx1 = CX + math.cos(ang + rng.uniform(-0.25, 0.25)) * d1
        ly1 = CY + math.sin(ang + rng.uniform(-0.25, 0.25)) * d1
        line(img, lx0, ly0, lx1, ly1, (255, 170, 70), rng.uniform(2, 5),
             int(rng.uniform(90, 170)))
    write(img, "sl_weapons_blast.png")


def make_grit():
    img = new()
    rng = random.Random(11)
    for _ in range(90):
        x = CX + rng.gauss(0, 60)
        y = CY + rng.gauss(0, 60)
        r = rng.uniform(0.8, 3.2)
        g = int(rng.uniform(90, 175))
        blob(img, int(x), int(y), max(1, int(r)), (g, g, g - 8), int(rng.uniform(120, 210)))
    write(img, "sl_weapons_grit.png")


def make_hit():
    img = new()
    add_radial(img, CX, CY, 0, 22, (235, 252, 255), 255, 1.4)
    for ang in (0, math.pi / 2, math.pi, 3 * math.pi / 2, math.pi / 4, 3 * math.pi / 4,
                5 * math.pi / 4, 7 * math.pi / 4):
        x1 = CX + math.cos(ang) * 112
        y1 = CY + math.sin(ang) * 112
        line(img, CX, CY, x1, y1, (170, 240, 255), 3, 235)
        line(img, CX, CY, x1 * 0.6 + CX * 0.4, y1 * 0.6 + CY * 0.4, (255, 255, 255), 1.5, 255)
    write(img, "sl_weapons_hit.png")


def make_spark():
    img = new()
    add_radial(img, CX, CY, 0, 12, (235, 252, 255), 255, 1.3)
    rng = random.Random(23)
    for _ in range(16):
        ang = rng.uniform(0, math.tau)
        d = rng.uniform(40, 118)
        w = rng.uniform(1, 2.4)
        line(img, CX + math.cos(ang) * 8, CY + math.sin(ang) * 8,
             CX + math.cos(ang) * d, CY + math.sin(ang) * d,
             (0, 232, 255) if rng.random() < 0.6 else (255, 255, 255), w, 220)
    write(img, "sl_weapons_spark.png")


def make_beam(name, color=(0, 232, 255), core=(255, 255, 255), half=16, core_h=3, L=S):
    img = new()
    x0 = (S - L) // 2
    for y in range(S):
        for x in range(S):
            dy = y - CY
            if abs(dy) > half:
                continue
            t = 1.0 - abs(dy) / half
            # end fade along length
            if x < x0 or x >= x0 + L:
                continue
            ed = min(x - x0, x0 + L - 1 - x) / 60.0
            ed = max(0.0, min(1.0, ed))
            t *= ed
            if abs(dy) <= core_h:
                c = core
            else:
                c = color
            a = int(255 * t)
            if a > 0:
                img[y][x] = (c[0], c[1], c[2], a)
    write(img, name)


def make_lash_hook():
    img = new()
    add_radial(img, CX, CY - 4, 0, 26, (180, 244, 255), 220, 1.6)
    add_radial(img, CX, CY - 4, 0, 9, (255, 255, 255), 255, 1.2)
    # hook arc: bright ring open at the bottom
    for a in range(0, 330, 2):
        ang = math.radians(a)
        x = CX + math.cos(ang) * 30
        y = CY - 4 + math.sin(ang) * 30
        blob(img, int(x), int(y), 2, (230, 250, 255), 240)
    for a in range(300, 361, 3):
        ang = math.radians(a)
        x = CX + math.cos(ang) * 30
        y = CY - 4 + math.sin(ang) * 30
        blob(img, int(x), int(y), 1, (230, 250, 255), 160)
    # tine hint inside the arc
    line(img, CX - 10, CY - 4, CX - 10, CY + 10, (200, 245, 255), 2, 200)
    write(img, "sl_weapons_lash_hook.png")


def make_lash_line():
    make_beam("sl_weapons_lash_line.png", color=(0, 232, 255), core=(255, 255, 255),
              half=7, core_h=2, L=150)


def make_tracer():
    make_beam("sl_weapons_tracer.png", color=(0, 232, 255), core=(255, 255, 255),
              half=18, core_h=2, L=S)


def make_mortar_shell():
    img = new()
    add_radial(img, CX, CY, 0, 16, (255, 240, 210), 255, 1.3)
    add_radial(img, CX, CY, 10, 40, (255, 170, 60), 230, 1.8)
    add_radial(img, CX, CY, 30, 62, (255, 110, 30), 120, 2.6)
    write(img, "sl_weapons_mortar_shell.png")


def make_pulse_bolt():
    img = new()
    add_radial(img, CX, CY, 0, 12, (255, 255, 255), 255, 1.2)
    add_radial(img, CX, CY, 8, 34, (0, 232, 255), 235, 1.7)
    add_radial(img, CX, CY, 26, 60, (0, 160, 255), 110, 2.4)
    write(img, "sl_weapons_pulse_bolt.png")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "mods/game/sl_weapons/textures"
    os.chdir(out)
    make_blast()
    make_grit()
    make_hit()
    make_spark()
    make_tracer()
    make_lash_hook()
    make_lash_line()
    make_mortar_shell()
    make_pulse_bolt()


if __name__ == "__main__":
    main()
