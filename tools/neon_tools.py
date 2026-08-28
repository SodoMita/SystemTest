#!/usr/bin/env python3
"""Procedural 16x16 neon tool icons (no AI generation).

One pixel-map per tool archetype (sword / pickaxe / axe / shovel), one palette
per material. Strict palette per icon:
  # = near-black handle fill     A = amber accent (guard / grip)
  B = material bright line       D = material dim halo (~40%)

Maps are authored on a 16x16 grid, y down. Preview with `python3 tools/neon_tools.py --preview`.
"""

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXDIR = os.path.join(ROOT, "mods", "default", "textures")

MATERIALS = {
    "wood":    (255, 199, 92),
    "stone":   (158, 186, 210),
    "steel":   (172, 220, 255),
    "bronze":  (255, 138, 48),
    "mese":    (202, 255, 60),
    "diamond": (195, 255, 250),
}
DARK = (12, 10, 9)
AMBER = (255, 170, 70)


def W(x0, y0, x1, y1):
    """Cells of a straight walk (4/8-connected) from (x0,y0) to (x1,y1)."""
    cells = []
    dx, dy = x1 - x0, y1 - y0
    sx = (dx > 0) - (dx < 0)
    sy = (dy > 0) - (dy < 0)
    dx, dy = abs(dx), abs(dy)
    x, y = x0, y0
    err = dx - dy
    while True:
        cells.append((x, y))
        if (x, y) == (x1, y1):
            return cells
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy


def uniq(cells):
    seen = set()
    out = []
    for c in cells:
        if c not in seen:
            seen.add(c)
            out.append(c)
    return out


# ------------------------------------------------------------------ shapes --

def sword():
    B, D, K, A = [], [], [], []
    grip = W(1, 14, 3, 12)
    K += grip + [(x, y - 1) for x, y in grip]          # 2-thick handle
    A += [(0, 15), (1, 15), (0, 14)]                   # pommel
    A += [(3, 10), (2, 9), (5, 12), (6, 13)]           # crossguard
    A += [(4, 10), (4, 12)]                            # guard thickening
    blade = W(5, 10, 13, 2)
    B += blade + [(14, 1)]                             # bright core to the tip
    D += [(x + 1, y) for x, y in blade]                # halo above the core
    D += [(4, 11)]
    return dict(B=B, D=D, K=K, A=A)


def pickaxe():
    B, D, K, A = [], [], [], []
    handle = W(2, 13, 9, 6)
    K += handle + [(x, y - 1) for x, y in handle]
    A += [(0, 15), (1, 15), (1, 14)]                   # grip cap
    arc = uniq([(3, 4), (4, 3), (5, 2), (6, 2), (7, 1), (8, 1), (9, 1),
                (10, 2), (11, 2), (12, 3), (13, 4), (14, 5), (14, 6)])
    B += arc
    D += [(3, 5), (4, 4), (5, 3), (6, 3), (7, 2), (8, 2), (9, 2), (10, 3),
          (11, 3), (12, 4), (13, 5), (14, 7)]          # halo under the arc
    D += [(2, 5), (2, 6), (15, 7), (15, 8)]            # drop tips past the ends
    K += [(9, 3), (9, 4), (9, 5)]                      # socket pole into the arc
    return dict(B=B, D=D, K=K, A=A)


def axe():
    B, D, K, A = [], [], [], []
    handle = W(1, 14, 10, 5)
    K += handle + [(x, y - 1) for x, y in handle]
    A += [(0, 15), (1, 15), (1, 14)]
    B += [(12, 2), (13, 2), (14, 3), (15, 4), (15, 5), (15, 6), (15, 7), (14, 8)]
    B += [(11, 3), (11, 4), (11, 5), (12, 6), (13, 7)]  # back of the head
    D += [(12, 3), (12, 4), (13, 4), (14, 4), (12, 5), (13, 5), (14, 5),
          (13, 6), (14, 6), (14, 7), (13, 8), (14, 8)]  # blade fill
    return dict(B=B, D=D, K=K, A=A)


def shovel():
    B, D, K, A = [], [], [], []
    handle = W(1, 14, 9, 6)
    K += handle + [(x, y - 1) for x, y in handle]
    A += [(0, 15), (1, 15), (1, 14)]
    B += [(11, 1), (12, 1), (13, 1), (14, 1)]           # top of the scoop
    B += [(10, 2), (10, 3), (10, 4), (10, 5)]           # left rim
    B += [(15, 2), (15, 3), (15, 4), (15, 5)]           # right rim
    B += [(11, 6), (12, 6), (13, 6), (14, 6)]           # bottom of the scoop
    D += [(x, y) for x in range(11, 15) for y in range(2, 6)]  # scoop fill
    return dict(B=B, D=D, K=K, A=A)


SHAPES = {"sword": sword, "pick": pickaxe, "axe": axe, "shovel": shovel}

# ------------------------------------------------------------------ render --

def render(shape, mat_rgb):
    bright = mat_rgb
    dim = tuple(int(v * 96 // 255) for v in mat_rgb)
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = im.load()
    for sym, color in (("D", dim), ("K", DARK), ("A", AMBER), ("B", bright)):
        for (x, y) in uniq(shape.get(sym, [])):
            if 0 <= x < 16 and 0 <= y < 16:
                px[x, y] = color + (255,)
    return im


def preview(name, shape):
    grid = [["."] * 16 for _ in range(16)]
    for sym in ("K", "A", "D", "B"):
        for (x, y) in uniq(shape.get(sym, [])):
            if 0 <= x < 16 and 0 <= y < 16:
                grid[y][x] = sym
    print(name)
    for row in grid:
        print("   " + "".join(row))


def main():
    if "--preview" in sys.argv:
        for name, fn in SHAPES.items():
            preview(name, fn())
        return
    n = 0
    for mat, rgb in MATERIALS.items():
        for tool, fn in SHAPES.items():
            im = render(fn(), rgb)
            name = "default_tool_%s%s.png" % (mat, tool)
            # file naming: default_tool_<mat><tool> e.g. default_tool_steelpick.png
            im.save(os.path.join(TEXDIR, name), optimize=True)
            n += 1
    print("wrote %d tool icons" % n)


if __name__ == "__main__":
    main()
