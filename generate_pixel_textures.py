#!/usr/bin/env python3
"""System Looting — canonical pixel-texture generator.

Art direction (owner directive 2026-08):
  * Colours are only white with glow; other colours appear very rarely and
    only where essential (caution yellow, medkit red, status LEDs).
  * Symbols must resemble real-world symbols (first-aid cross, radiation
    trefoil, biohazard, warning triangle, padlock, chevrons, ...).
  * Clouds are real clouds: `sky:cloud` is an opaque walkable node,
    `sky:cloud_puff` is a leaves-style puffy variant.

Every sprite is drawn on a tiny deterministic pixel canvas (Bresenham lines,
discs, rings, polygons) so shapes stay crisp, reviewable and reproducible.

Run:  python3 generate_pixel_textures.py
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent

# ---------------------------------------------------------------------------
# Palette — white-with-glow plus the rare essential accents.
# ---------------------------------------------------------------------------
PALETTE = {
    "W": (255, 255, 255, 255),   # white core (the "glow" centre)
    "w": (228, 233, 242, 255),   # bright grey
    "+": (188, 195, 208, 255),   # mid grey
    "-": (134, 141, 156, 255),   # dim grey
    "=": (84, 90, 104, 255),     # deep grey detail
    "#": (46, 50, 60, 255),      # plate fill
    "~": (20, 22, 28, 255),      # outline / shadow
    "%": (12, 13, 17, 255),      # near-black
    ".": (30, 33, 41, 255),      # recessed detail
    " ": (0, 0, 0, 0),           # transparent
    # --- essential colours, used only where the real-world symbol needs them
    "Y": (255, 208, 56, 255),    # caution yellow
    "y": (158, 120, 20, 255),    # caution yellow shade
    "R": (232, 54, 46, 255),     # signal red (medkit, danger)
    "r": (134, 26, 22, 255),     # signal red shade
    "G": (110, 230, 150, 255),   # status LED green (tiny accents only)
    "C": (150, 228, 255, 255),   # energy cyan (tiny accents only)
}


class C:
    """16-ish pixel canvas with plotting primitives."""

    def __init__(self, w: int, h: int | None = None, bg: str = " "):
        self.w = w
        self.h = h if h is not None else w
        self.grid = [[bg for _ in range(w)] for _ in range(self.h)]

    def px(self, x: int, y: int, ch: str) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.grid[y][x] = ch

    def get(self, x: int, y: int) -> str:
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.grid[y][x]
        return " "

    def hline(self, x0: int, x1: int, y: int, ch: str) -> None:
        for x in range(min(x0, x1), max(x0, x1) + 1):
            self.px(x, y, ch)

    def vline(self, x: int, y0: int, y1: int, ch: str) -> None:
        for y in range(min(y0, y1), max(y0, y1) + 1):
            self.px(x, y, ch)

    def line(self, x0, y0, x1, y1, ch: str) -> None:
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.px(x0, y0, ch)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def rect(self, x0, y0, x1, y1, ch: str) -> None:
        self.hline(x0, x1, y0, ch)
        self.hline(x0, x1, y1, ch)
        self.vline(x0, y0, y1, ch)
        self.vline(x1, y0, y1, ch)

    def fill(self, x0, y0, x1, y1, ch: str) -> None:
        for y in range(min(y0, y1), max(y0, y1) + 1):
            self.hline(x0, x1, y, ch)

    def disc(self, cx, cy, r, ch: str) -> None:
        for y in range(self.h):
            for x in range(self.w):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + r * 0.6:
                    self.px(x, y, ch)

    def ring(self, cx, cy, r, ch: str) -> None:
        for y in range(self.h):
            for x in range(self.w):
                d = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
                if r - 0.6 <= d <= r + 0.4:
                    self.px(x, y, ch)

    def poly(self, pts, ch: str, close: bool = True) -> None:
        for i in range(len(pts) - 1):
            self.line(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], ch)
        if close and len(pts) > 2:
            self.line(pts[-1][0], pts[-1][1], pts[0][0], pts[0][1], ch)

    def to_image(self, glow: bool = True) -> Image.Image:
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        p = img.load()
        for y in range(self.h):
            for x in range(self.w):
                p[x, y] = PALETTE[self.grid[y][x]]
        return add_glow(img) if glow else img


def add_glow(img: Image.Image, alpha: int = 70) -> Image.Image:
    """One-pixel white halo around near-white cores — 'white with glow'."""
    w, h = img.size
    src = img.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            if a > 0:
                dst[x, y] = (r, g, b, a)
                continue
            near = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and 0 <= yy < h:
                    rr, gg, bb, aa = src[xx, yy]
                    if aa > 200 and rr > 200 and gg > 200 and bb > 200:
                        near = True
                        break
            if near:
                dst[x, y] = (255, 255, 255, alpha)
    return out


def upscale(img: Image.Image, factor: int) -> Image.Image:
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def save(img: Image.Image, rel: str, scale: int = 1) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    if scale > 1:
        img = upscale(img, scale)
    img.save(path)
    print(f"  {rel}  {img.size[0]}x{img.size[1]}")


# ---------------------------------------------------------------------------
# sl_modebase — items, tools, materials (real-world symbols)
# ---------------------------------------------------------------------------
def gen_modebase() -> None:
    d = "mods/game/sl_modebase/textures"

    def plate_icon(c: C, rel: str, scale: int = 1) -> None:
        """Composite a 16x16 symbol on the rounded dark plate."""
        plate = C(16)
        plate.fill(2, 2, 13, 13, "#")
        plate.px(1, 1, "~")
        plate.px(14, 1, "~")
        plate.px(1, 14, "~")
        plate.px(14, 14, "~")
        plate.rect(1, 2, 14, 13, "~")
        plate.rect(2, 1, 13, 14, "~")
        base = plate.to_image(glow=False)
        base.alpha_composite(c.to_image(glow=True))
        save(base, rel, scale)

    # -- Barricade: crowd barrier — two legs, horizontal beam, X brace.
    c = C(16)
    c.line(2, 13, 5, 7, "w"); c.line(2, 12, 5, 6, "+")   # left leg
    c.line(13, 13, 10, 7, "w"); c.line(13, 12, 10, 6, "+")  # right leg
    c.fill(1, 4, 14, 6, "=")
    c.hline(1, 14, 4, "+"); c.hline(1, 14, 6, "-")
    c.line(3, 6, 12, 4, "w"); c.line(12, 6, 3, 4, "w")   # X brace
    plate_icon(c, f"{d}/sl_barricade.png")

    # -- Blast shield: ballistic shield with vision slit.
    c = C(16)
    c.rect(2, 2, 13, 13, "w")                            # rim
    c.px(3, 1, "w"); c.px(4, 1, "w"); c.px(11, 1, "w"); c.px(12, 1, "w")
    c.px(3, 14, "w"); c.px(4, 14, "w"); c.px(11, 14, "w"); c.px(12, 14, "w")
    c.fill(4, 3, 11, 12, "=")
    c.vline(3, 3, 12, "+")
    c.fill(7, 4, 8, 6, "~")                              # vision slit
    c.hline(7, 8, 7, ".")
    c.px(5, 8, "-"); c.px(10, 8, "-")                    # bolts
    c.px(5, 11, "."); c.px(10, 11, ".")
    c.hline(4, 11, 12, ".")
    plate_icon(c, f"{d}/sl_blast_shield.png")

    # -- Breaching pick: pick head + shaft, 45 degrees.
    c = C(16)
    c.line(9, 2, 12, 5, "W"); c.line(10, 2, 12, 4, "w")  # pick head
    c.line(9, 2, 8, 3, "w")
    c.line(9, 4, 3, 10, "="); c.line(10, 5, 4, 11, "-")  # shaft
    c.fill(2, 10, 4, 12, "#"); c.rect(2, 10, 4, 12, "-")  # grip
    plate_icon(c, f"{d}/sl_breaching_pick.png")

    # -- Circuit board: PCB with traces and a central chip.
    c = C(16)
    c.rect(2, 2, 13, 13, "w"); c.rect(3, 3, 12, 12, "-")
    c.fill(6, 6, 9, 9, "="); c.rect(6, 6, 9, 9, "w")     # chip
    c.px(7, 7, "w")
    for i, x in enumerate((4, 11)):                       # traces to edge
        c.vline(x, 4, 6, "w" if i == 0 else "-")
        c.px(x, 4, "w")
        c.hline(x, 7 if i == 0 else 8, 4, "w" if i == 0 else "-")
        c.vline(x, 9, 11, "w" if i == 0 else "-")
        c.hline(7 if i == 0 else 8, x, 11, "w" if i == 0 else "-")
    c.px(4, 4, "W"); c.px(11, 11, "W")
    plate_icon(c, f"{d}/sl_circuit_board.png")

    # -- Combat blade: machete — diagonal blade, guard, grip.
    c = C(16)
    c.line(13, 2, 5, 10, "W"); c.line(13, 3, 6, 10, "w")  # edge + spine
    c.line(12, 2, 5, 9, "+")
    c.line(3, 9, 6, 12, "w"); c.line(6, 9, 3, 12, "w")    # guard
    c.line(3, 11, 2, 13, "="); c.line(2, 11, 1, 12, "=")  # grip
    c.px(2, 12, "~"); c.px(1, 13, "~")
    plate_icon(c, f"{d}/sl_combat_blade.png")

    # -- Electronic waste: circuit board snapped in two.
    c = C(16)
    c.rect(2, 3, 9, 9, "w")                              # upper half
    c.line(2, 9, 9, 3, "~")                              # torn diagonal
    c.fill(5, 5, 7, 7, "="); c.rect(5, 5, 7, 7, "w")     # chip
    c.px(3, 4, "W"); c.px(8, 8, "-")
    c.rect(6, 9, 13, 13, "w")                            # lower half, offset
    c.line(6, 9, 13, 12, "~")
    c.fill(9, 10, 11, 11, "=")
    c.px(9, 10, "W")
    c.px(10, 8, "w"); c.px(12, 8, "w")                   # dangling traces
    c.vline(12, 8, 9, "w")
    plate_icon(c, f"{d}/sl_electronic_waste.png")

    # -- Energy blade: contained energy edge (bright double line).
    c = C(16)
    c.line(13, 2, 5, 10, "W"); c.line(13, 4, 6, 11, "W")  # energy edges
    c.line(12, 3, 6, 9, "w")
    c.line(3, 9, 6, 12, "w"); c.line(6, 9, 3, 12, "w")    # emitter guard
    c.px(4, 10, "W")
    c.line(3, 11, 2, 13, "="); c.line(2, 11, 1, 12, "=")
    c.px(2, 12, "~"); c.px(1, 13, "~")
    plate_icon(c, f"{d}/sl_energy_blade.png")

    # -- Energy crystal: brilliant-cut gem.
    c = C(16)
    c.px(8, 2, "W")
    c.poly([(8, 3), (12, 6), (8, 13), (4, 6)], "w")
    c.line(4, 6, 12, 6, "+")                              # girdle
    c.line(8, 3, 6, 6, "-"); c.line(8, 3, 10, 6, "-")     # crown facets
    c.line(6, 6, 8, 13, "="); c.line(10, 6, 8, 13, "=")
    c.px(8, 5, "W"); c.px(8, 7, "w")
    plate_icon(c, f"{d}/sl_energy_crystal.png")

    # -- Flare: burning emergency flare.
    c = C(16)
    c.px(8, 2, "W")
    c.line(8, 3, 4, 4, "w"); c.line(8, 3, 12, 4, "w")
    c.line(5, 5, 3, 6, "w"); c.line(11, 5, 13, 6, "w")
    c.fill(6, 4, 10, 6, "w"); c.fill(7, 3, 9, 7, "W")     # burst
    c.fill(7, 8, 9, 12, "=")                              # stick
    c.vline(7, 8, 12, "+"); c.vline(9, 8, 12, "-")
    c.fill(7, 13, 9, 13, "~")
    plate_icon(c, f"{d}/sl_flare.png")

    # -- Hardened plate: riveted armour plate.
    c = C(16)
    c.rect(2, 2, 13, 13, "w")
    c.rect(3, 3, 12, 12, "=")
    c.hline(3, 12, 3, "+"); c.vline(3, 3, 12, "+")        # bevel light
    c.hline(3, 12, 12, "-"); c.vline(12, 3, 12, "-")      # bevel shade
    for bx, by in ((5, 5), (10, 5), (5, 10), (10, 10)):   # rivets
        c.px(bx, by, "W")
    c.fill(7, 7, 8, 8, "=")
    plate_icon(c, f"{d}/sl_hardened_plate.png")

    # -- Loot crate: military supply crate with lid + latch.
    c = C(16)
    c.rect(2, 5, 13, 13, "w")
    c.hline(2, 13, 7, "-")
    c.fill(3, 6, 12, 6, "=")
    c.fill(2, 3, 13, 4, "+")                              # lid
    c.hline(2, 13, 4, "-")
    c.fill(7, 3, 8, 6, "w")                               # latch
    c.px(7, 5, "~"); c.px(8, 5, "~")
    c.vline(4, 8, 12, "."); c.vline(11, 8, 12, ".")       # panel seams
    plate_icon(c, f"{d}/sl_loot_crate.png")

    # -- Medkit: first-aid kit with the red cross of life.
    c = C(16)
    c.fill(6, 2, 9, 3, "=")                               # handle
    c.rect(2, 3, 13, 13, "w")
    c.rect(3, 4, 12, 12, "-")
    c.hline(3, 12, 11, "=")
    for x in range(7, 9):
        c.vline(x, 6, 10, "R")
    for y in range(7, 9):
        c.hline(5, 10, y, "R")
    plate_icon(c, f"{d}/sl_medkit.png")

    # -- Metal ingot: poured bar, 3/4 view.
    c = C(16)
    c.poly([(4, 5), (12, 5), (14, 8), (2, 8)], "w", close=False)  # top face
    c.line(4, 5, 12, 5, "W")
    c.line(2, 8, 2, 11, "w"); c.line(14, 8, 14, 11, "w")
    c.hline(2, 14, 11, "w")
    c.line(4, 5, 2, 8, "+"); c.line(12, 5, 14, 8, "-")
    c.hline(3, 13, 9, "="); c.px(4, 9, "+")               # front face
    plate_icon(c, f"{d}/sl_metal_ingot.png")

    # -- Monster essence: specimen vial with trapped wisp.
    c = C(16)
    c.fill(6, 2, 9, 3, "y"); c.hline(6, 9, 2, "w")        # cork
    c.fill(7, 4, 8, 5, "+")                               # neck
    c.rect(5, 6, 10, 13, "w")
    c.rect(6, 7, 9, 12, "-")
    c.px(7, 9, "W"); c.px(8, 10, "W"); c.px(7, 11, "w")   # wisp
    c.px(8, 8, "w")
    plate_icon(c, f"{d}/sl_monster_essence.png")

    # -- Monster spawner: summoning slab (also the node tile).
    c = C(16)
    c.rect(1, 1, 14, 14, "=")
    c.hline(1, 14, 1, "+"); c.vline(1, 1, 14, "+")
    c.hline(1, 14, 14, "~"); c.vline(14, 1, 14, "~")
    c.ring(7.5, 7.5, 4.2, "w")
    c.px(7, 3, "W"); c.px(11, 6, "W"); c.px(10, 11, "W")
    c.px(5, 11, "W"); c.px(4, 6, "W")                     # rune points
    c.poly([(7, 5), (9, 10), (5, 8)], "w")
    for bx, by in ((2, 2), (13, 2), (2, 13), (13, 13)):   # corner studs
        c.px(bx, by, "+")
    save(c.to_image(), f"{d}/sl_monster_spawner.png")

    # -- Objective core: glowing orb in a focusing ring.
    c = C(16)
    c.ring(7.5, 7.5, 5.4, "+")
    c.px(2, 4, "w"); c.px(2, 11, "w"); c.px(13, 4, "w"); c.px(13, 11, "w")
    c.disc(7.5, 7.5, 2.4, "w")
    c.px(7, 7, "W"); c.px(8, 7, "W"); c.px(7, 8, "W"); c.px(8, 8, "W")
    c.px(6, 6, "+"); c.px(9, 6, "+"); c.px(6, 9, "+"); c.px(9, 9, "+")
    plate_icon(c, f"{d}/sl_objective_core.png")
    plate_icon(c, f"{d}/sl_objective_core_icon.png")

    # -- Plastic scrap: curled machining ribbon (spiral).
    c = C(16)
    for t in [i * 0.18 for i in range(38)]:              # spiral band
        r = 1.4 + 0.42 * t
        x = 7.0 + r * math.cos(t + 1.2)
        y = 8.0 + r * math.sin(t + 1.2)
        c.px(int(x), int(y), "w")
        c.px(int(x) + 1, int(y), "+")
    c.line(12, 8, 14, 11, "-")                           # tail
    plate_icon(c, f"{d}/sl_plastic_scrap.png")

    # -- Power cell: battery with charge window (rare cyan LED).
    c = C(16)
    c.fill(6, 2, 9, 3, "w")                               # terminal
    c.rect(4, 4, 11, 13, "w")
    c.rect(5, 5, 10, 12, "=")
    c.fill(7, 5, 8, 12, "-")                              # window
    c.hline(7, 8, 6, "G"); c.hline(7, 8, 7, "G")          # charge bars
    c.hline(7, 8, 9, "=")
    c.hline(4, 11, 4, "+")
    plate_icon(c, f"{d}/sl_power_cell.png")

    # -- Power drill: pistol-grip drill with bit.
    c = C(16)
    c.fill(2, 4, 8, 8, "+"); c.rect(2, 4, 8, 8, "w")      # body
    c.vline(2, 4, 8, "W")
    c.fill(8, 5, 10, 7, "-")                              # chuck
    c.line(10, 6, 13, 6, "W"); c.line(11, 5, 13, 5, "w")  # bit
    c.fill(4, 9, 6, 13, "="); c.rect(4, 9, 6, 13, "-")    # grip
    c.hline(4, 6, 10, "~"); c.hline(4, 6, 12, "~")
    c.px(7, 9, "w")                                       # trigger
    plate_icon(c, f"{d}/sl_power_drill.png")

    # -- Raw crystal: uncut shard cluster.
    c = C(16)
    c.poly([(8, 2), (10, 6), (8, 11), (6, 6)], "w")       # main shard
    c.line(8, 2, 8, 11, "+")
    c.poly([(4, 6), (6, 8), (5, 12), (3, 9)], "-")        # left shard
    c.poly([(12, 5), (13, 8), (11, 11), (10, 8)], "-")    # right shard
    c.px(8, 4, "W"); c.px(5, 9, "+"); c.px(12, 7, "+")
    c.hline(4, 12, 13, ".")                               # ground shadow
    plate_icon(c, f"{d}/sl_raw_crystal.png")

    # -- Reinforced glass (also node tile): bolted security pane.
    c = C(16)
    c.rect(1, 1, 14, 14, "w")
    c.rect(2, 2, 13, 13, "=")
    c.line(5, 11, 10, 4, "+"); c.line(6, 11, 11, 4, "-")  # glints
    for bx, by in ((3, 3), (12, 3), (3, 12), (12, 12)):   # bolts
        c.px(bx, by, "w"); c.px(bx, by, "W")
    save(c.to_image(), f"{d}/sl_reinforced_glass.png")

    # -- Scrap metal: torn jagged plate with rivets.
    c = C(16)
    c.poly([(2, 4), (12, 3), (13, 6), (11, 7), (12, 10), (8, 9),
            (7, 12), (4, 10), (2, 11)], "w")
    c.line(3, 5, 11, 4, "+")
    c.px(5, 6, "W"); c.px(9, 6, "W")                      # rivets
    c.line(4, 8, 10, 7, "-")                              # bend
    plate_icon(c, f"{d}/sl_scrap_metal.png")

    # -- Sensor array: radar dish on a tripod.
    c = C(16)
    c.ring(6, 6, 4.4, "w")
    c.line(6, 6, 10, 2, "W"); c.px(10, 2, "W")            # feed rod
    c.line(9, 3, 7, 5, "+")
    c.line(6, 10, 4, 13, "="); c.line(6, 10, 8, 13, "=")  # tripod
    c.vline(6, 9, 10, "-")
    plate_icon(c, f"{d}/sl_sensor_array.png")

    # -- Signal relay: mast with emitting waves.
    c = C(16)
    c.fill(7, 6, 8, 13, "-")                              # mast
    c.vline(7, 6, 13, "+")
    c.hline(5, 10, 6, "w")                                # head
    c.px(7, 4, "W"); c.px(8, 4, "W")
    c.px(4, 2, "w"); c.px(3, 3, "w"); c.px(3, 5, "w"); c.px(4, 6, "w")
    c.px(11, 2, "w"); c.px(12, 3, "w"); c.px(12, 5, "w"); c.px(11, 6, "w")
    c.px(2, 1, "+"); c.px(13, 1, "+"); c.px(2, 7, "+"); c.px(13, 7, "+")
    c.fill(5, 13, 10, 13, "=")                            # base
    plate_icon(c, f"{d}/sl_signal_relay.png")

    # -- Tactical axe: fire axe — blade + spike + diagonal haft.
    c = C(16)
    c.line(3, 13, 10, 6, "y"); c.line(4, 13, 11, 6, "=")  # haft
    c.line(8, 8, 12, 4, "w"); c.line(9, 9, 13, 5, "+")    # blade edge
    c.line(12, 4, 13, 5, "w")
    c.fill(10, 6, 11, 7, "w")                             # eye
    c.line(8, 5, 9, 6, "w"); c.px(7, 4, "W")              # spike
    plate_icon(c, f"{d}/sl_tactical_axe.png")

    # -- Trench shovel: entrenching tool, blade up-right.
    c = C(16)
    c.line(3, 13, 9, 7, "y"); c.line(4, 13, 10, 7, "=")   # haft
    c.fill(9, 3, 13, 7, "+")                              # blade
    c.line(9, 3, 13, 3, "w"); c.line(13, 3, 13, 7, "w")
    c.line(9, 3, 9, 5, "-"); c.line(9, 5, 11, 7, "-")     # collar
    c.px(11, 5, "=")
    plate_icon(c, f"{d}/sl_trench_shovel.png")


# ---------------------------------------------------------------------------
# Sky — real volumetric-look clouds.
#   sky:cloud        opaque, walkable cumulus slab (classic cloud block)
#   sky:cloud_puff   leaves-style puffy variant you can walk through
# ---------------------------------------------------------------------------
# 4x4 ordered-dither matrix for crisp two-tone shading at 16px scale.
_BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def _cloud_field(sz: int, seed: int, puffs: int, rmin: float, rmax: float):
    """Supersampled metaball field for a cumulus puff (0..255 coverage)."""
    rnd = random.Random(seed)
    ss = 4
    big = Image.new("L", (sz * ss, sz * ss), 0)
    dr = ImageDraw.Draw(big)
    for i in range(puffs):
        t = i / max(1, puffs - 1)
        # alternating high/low lobes give the classic bumpy cumulus top
        cx = sz * (0.20 + 0.60 * t) + rnd.uniform(-0.8, 0.8)
        lift = rmax * (0.30 if i % 2 == 0 else 0.05)
        cy = sz * 0.58 - lift + rnd.uniform(-0.06, 0.06) * sz
        r = rnd.uniform(rmin, rmax)
        dr.ellipse(((cx - r) * ss, (cy - r) * ss, (cx + r) * ss, (cy + r) * ss), fill=255)
    big = big.filter(ImageFilter.GaussianBlur(sz * ss * 0.04))
    return big.resize((sz, sz), Image.BILINEAR)


def _cloud_canvas(sz: int, seed: int, puffs: int, rmin: float, rmax: float,
                  base_alpha: int) -> Image.Image:
    """A dense, puffy cumulus sprite: bright white mass, clean soft shade."""
    field = _cloud_field(sz, seed, puffs, rmin, rmax)
    fpx = field.load()
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    px = img.load()
    rnd = random.Random(seed * 31 + 7)
    for y in range(sz):
        for x in range(sz):
            v = fpx[x, y]
            if v < 96:
                continue
            a = 255 if v >= 150 else int((v - 96) * 255 / 54)
            a = min(255, a * base_alpha // 255)
            if a <= 0:
                continue
            # illumination: snow-white top third, gentle falloff below
            depth = max(0.0, (y / sz - 0.42))          # 0 at top .. ~0.6 bottom
            shade = depth * depth * 46 + (8 if v < 190 else 0)
            tone = 252 - int(shade)
            if rnd.random() < 0.05 and depth < 0.2:
                tone = 255                              # sun glints
            tone = max(206, min(255, tone))
            px[x, y] = (tone, tone, min(255, tone + 6), a)
    return img


def gen_clouds() -> None:
    d = "mods/sl_blocks/sky/textures"

    # Opaque walkable cloud block: full-bleed cumulus surface.
    c = C(16)
    rnd = random.Random(7)
    for y in range(16):
        lit = 1.0 - max(0.0, (y / 16 - 0.40)) * 1.1
        for x in range(16):
            billow = (math.sin(x * 0.9 + 1.3) + math.sin(x * 0.45 + y * 0.6)) * 0.5
            tone = 242 + int(13 * lit) + int(billow * 4)
            if _BAYER[y % 4][x % 4] / 16 > lit + 0.34:
                tone -= 20
            if rnd.random() < 0.04:
                tone = 255
            c.px(x, y, None)
    img = Image.new("RGBA", (16, 16))
    px = img.load()
    rnd2 = random.Random(11)
    for y in range(16):
        lit = 1.0 - max(0.0, (y / 16 - 0.40)) * 1.1
        for x in range(16):
            billow = (math.sin(x * 0.9 + 1.3) + math.sin(x * 0.45 + y * 0.6)) * 0.5
            tone = 242 + int(13 * lit) + int(billow * 4)
            if _BAYER[y % 4][x % 4] / 16 > lit + 0.34:
                tone -= 20
            if rnd2.random() < 0.04:
                tone = 255
            tone = max(210, min(255, tone))
            px[x, y] = (tone, tone, min(255, tone + 6), 255)
    save(img, f"{d}/sky_cloud.png")

    # Puffy variant: soft dense vapor (clip alpha), allfaces drawtype.
    for name, seed in (("sky_cloud_puff", 23), ("sky_cloud_puff_hi", 41)):
        puff = _cloud_canvas(32, seed=seed, puffs=7, rmin=6.0, rmax=10.0,
                             base_alpha=255)
        save(puff, f"{d}/{name}.png")

    # Pure-white glow accent for particles/HUD use.
    glow = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    gp = glow.load()
    for y in range(16):
        for x in range(16):
            dd = math.hypot(x - 7.5, y - 7.5)
            if dd < 7:
                v = max(0.0, 1.0 - dd / 7)
                gp[x, y] = (255, 255, 255, int(210 * v))
    save(glow, f"{d}/sky_glow.png")


# ---------------------------------------------------------------------------
# Workshops — furniture/lab node textures (dark industrial, white glow).
# ---------------------------------------------------------------------------
def _panel(c: C, x0, y0, x1, y1, face: str = "=") -> None:
    """A bevelled metal panel."""
    c.fill(x0, y0, x1, y1, face)
    c.hline(x0, x1, y0, "+"); c.vline(x0, y0, y1, "+")
    c.hline(x0, x1, y1, "~"); c.vline(x1, y0, y1, "~")


def gen_workshops() -> None:
    d = "mods/content/workshops/textures"

    def steel(seed: int) -> C:
        """Mottled steel base plate."""
        rnd = random.Random(seed)
        c = C(16)
        for y in range(16):
            for x in range(16):
                v = rnd.random()
                c.px(x, y, "+" if v < 0.06 else ("-" if v < 0.12 else "="))
        return c

    # wood-ish (dark) planks for benches
    wood = C(16)
    for y in range(16):
        wood.hline(0, 15, y, "=" if y % 4 else "-")
    for y in (3, 7, 11, 15):
        wood.hline(0, 15, y, "~")
    for x in (5, 12):
        wood.vline(x, 0, 2, "~"); wood.vline(x, 4, 6, "~")
        wood.vline(x, 8, 10, "~"); wood.vline(x, 12, 14, "~")
    tile_wood = wood.to_image(glow=False)

    # industrial panel side
    side = C(16)
    _panel(side, 1, 1, 14, 14, "=")
    side.hline(1, 14, 5, "-"); side.hline(1, 14, 10, "-")
    side.px(3, 3, "+"); side.px(12, 12, "+")
    tile_side = side.to_image(glow=False)

    # dark underside
    bottom = C(16)
    _panel(bottom, 1, 1, 14, 14, "-")
    bottom.fill(3, 3, 12, 12, "=")
    bottom.hline(1, 14, 8, "~")
    tile_bottom = bottom.to_image(glow=False)

    def save_variants(base: str, top_img, side_img, bottom_img=None,
                      front_img=None, back_img=None):
        save(top_img, f"{d}/{base}_top.png")
        save(side_img, f"{d}/{base}_side.png")
        save(bottom_img or tile_bottom, f"{d}/{base}_bottom.png")
        if front_img is not None:
            save(front_img, f"{d}/{base}_front.png")
        if back_img is not None:
            save(back_img, f"{d}/{base}_back.png")

    # ---- Advanced workbench ----------------------------------------------
    top = C(16)
    for y in range(16):                                   # wooden top
        top.hline(0, 15, y, "=" if y % 4 else "-")
    for y in (3, 7, 11, 15):
        top.hline(0, 15, y, "~")
    top.fill(2, 2, 6, 5, "-"); top.rect(2, 2, 6, 5, "w")  # blueprint
    top.line(3, 3, 5, 5, "w"); top.line(5, 3, 3, 5, "w")
    top.fill(10, 3, 12, 6, "+"); top.rect(10, 3, 12, 6, "~")  # toolbox
    top.px(11, 2, "w")
    top.line(8, 9, 13, 13, "w"); top.line(9, 9, 13, 12, "+")  # wrench
    top.disc(8, 13, 1.2, "w")
    save(top.to_image(glow=False), f"{d}/advanced_workbench_top.png")

    front = C(16)
    for y in range(16):
        front.hline(0, 15, y, "=" if y % 4 else "-")
    for y in (3, 7, 11, 15):
        front.hline(0, 15, y, "~")
    for dx in (1, 8):                                     # two drawers
        front.rect(dx + 1, 4, dx + 6, 9, "+")
        front.hline(dx + 3, dx + 4, 6, "W")               # handles
        front.rect(dx + 1, 10, dx + 6, 14, "+")
        front.hline(dx + 3, dx + 4, 12, "W")
    save(front.to_image(glow=False), f"{d}/advanced_workbench_front.png")
    save_variants("advanced_workbench", top.to_image(glow=False),
                  tile_side, tile_bottom, front.to_image(glow=False))

    # ---- Precision anvil ---------------------------------------------------
    top = steel(5)
    top.ring(7.5, 7.5, 4.5, "-")
    top.disc(7.5, 7.5, 1.6, "+"); top.px(7, 7, "W")
    for bx, by in ((3, 3), (12, 3), (3, 12), (12, 12)):
        top.px(bx, by, "+")
    save(top.to_image(glow=False), f"{d}/precision_anvil_top.png")

    side = C(16)
    _panel(side, 1, 1, 14, 14, "=")
    side.fill(4, 6, 11, 12, "-"); side.rect(4, 6, 11, 12, "+")
    side.hline(4, 11, 9, "=")
    save(side.to_image(glow=False), f"{d}/precision_anvil_side.png")
    save_variants("precision_anvil", top.to_image(glow=False),
                  side.to_image(glow=False))

    # ---- Assembly table ----------------------------------------------------
    top = steel(9)
    for i in range(4):                                    # hole grid
        for j in range(4):
            top.px(4 + i * 3, 4 + j * 3, "%")
            top.px(5 + i * 3, 4 + j * 3, "-")
    top.rect(2, 2, 13, 13, "-")
    save(top.to_image(glow=False), f"{d}/assembly_table_top.png")
    save_variants("assembly_table", top.to_image(glow=False), tile_side)

    # ---- Tool rack ----------------------------------------------------------
    top = C(16)
    for y in range(16):                                   # plank top
        top.hline(0, 15, y, "=" if y % 4 else "-")
    for y in (5, 10, 15):
        top.hline(0, 15, y, "~")
    save(top.to_image(glow=False), f"{d}/tool_rack_top.png")

    side = C(16)
    for y in range(16):
        side.hline(0, 15, y, "=" if y % 4 else "-")
    for y in (5, 10, 15):
        side.hline(0, 15, y, "~")
    side.vline(3, 1, 14, "w"); side.vline(12, 1, 14, "w")  # rail
    side.line(5, 3, 5, 8, "+"); side.disc(5, 3, 0.9, "w")  # hanging hammer
    side.line(6, 3, 6, 7, "+"); side.fill(4, 8, 7, 9, "-")
    side.line(10, 3, 10, 9, "+"); side.disc(10, 3, 0.9, "w")  # wrench
    side.line(9, 3, 9, 9, "+"); side.disc(9, 10, 1.3, "+")
    save(side.to_image(glow=False), f"{d}/tool_rack_side.png")
    save_variants("tool_rack", top.to_image(glow=False), side.to_image(glow=False))

    # ---- Chemical station ---------------------------------------------------
    top = steel(13)
    top.disc(5, 5, 2.2, "w"); top.disc(5, 5, 1.2, "+")    # beaker mouth
    top.disc(10, 9, 1.8, "w"); top.disc(10, 9, 0.9, "+")
    top.line(5, 7, 5, 10, "-"); top.line(10, 11, 10, 13, "-")  # tubes
    top.line(7, 12, 9, 10, "-")
    save(top.to_image(glow=False), f"{d}/chemical_station_top.png")

    side = C(16)
    _panel(side, 1, 1, 14, 14, "=")
    side.fill(2, 4, 5, 12, "+"); side.rect(2, 4, 5, 12, "w")  # cabinet
    side.hline(3, 4, 8, "W")
    side.rect(8, 3, 13, 8, "w")                           # fume hood
    side.fill(9, 4, 12, 7, "%")
    side.line(9, 11, 12, 11, "-")                         # pipes
    side.px(9, 10, "+"); side.px(12, 10, "+")
    save(side.to_image(glow=False), f"{d}/chemical_station_side.png")
    save_variants("chemical_station", top.to_image(glow=False),
                  side.to_image(glow=False))

    # ---- Blueprint drawer ----------------------------------------------------
    top = C(16)
    for y in range(16):
        top.hline(0, 15, y, "=" if y % 4 else "-")
    for y in (3, 7, 11, 15):
        top.hline(0, 15, y, "~")
    save(top.to_image(glow=False), f"{d}/blueprint_drawer_top.png")

    front = C(16)
    for y in range(16):
        front.hline(0, 15, y, "=" if y % 4 else "-")
    for y in (3, 7, 11, 15):
        front.hline(0, 15, y, "~")
    front.rect(2, 3, 13, 9, "+"); front.hline(4, 11, 6, "W")   # drawer
    front.fill(3, 11, 12, 14, "-")                              # rolled plans
    front.disc(3, 12, 1.4, "w"); front.disc(3, 12, 0.6, "=")
    save(front.to_image(glow=False), f"{d}/blueprint_drawer_front.png")
    save_variants("blueprint_drawer", top.to_image(glow=False), tile_side,
                  front_img=front.to_image(glow=False))

    # ---- Metal locker ----------------------------------------------------------
    top = steel(17)
    save(top.to_image(glow=False), f"{d}/metal_locker_top.png")

    front = C(16)
    _panel(front, 1, 0, 14, 15, "=")
    front.rect(3, 2, 12, 13, "+")
    for x in range(4, 12, 2):                             # vents
        for y in range(4, 8):
            front.px(x, y, "-")
    front.vline(11, 4, 11, "W")                           # handle
    front.hline(7, 8, 13, "w")                            # lock
    save(front.to_image(glow=False), f"{d}/metal_locker_front.png")
    save_variants("metal_locker", top.to_image(glow=False), tile_side,
                  front_img=front.to_image(glow=False))

    # ---- Filing cabinet ----------------------------------------------------------
    top = steel(21)
    save(top.to_image(glow=False), f"{d}/filing_cabinet_top.png")

    front = C(16)
    _panel(front, 1, 0, 14, 15, "=")
    for y0 in (1, 6, 11):                                 # three drawers
        front.rect(3, y0, 12, y0 + 4, "+")
        front.hline(6, 9, y0 + 2, "W")
        front.px(4, y0 + 2, "-")                          # card holder
    save(front.to_image(glow=False), f"{d}/filing_cabinet_front.png")
    save_variants("filing_cabinet", top.to_image(glow=False), tile_side,
                  front_img=front.to_image(glow=False))

    # ---- Metal desk ----------------------------------------------------------
    top = steel(25)
    top.rect(2, 2, 13, 13, "-")                           # desk pad
    top.fill(3, 3, 12, 12, "=")
    top.rect(9, 3, 12, 6, "+")                            # terminal block
    top.px(10, 4, "W"); top.px(11, 4, "W")
    save(top.to_image(glow=False), f"{d}/metal_desk_top.png")

    front = C(16)
    _panel(front, 1, 1, 14, 14, "=")
    front.rect(2, 4, 13, 8, "+"); front.hline(5, 10, 6, "W")   # drawer
    front.fill(2, 10, 13, 13, "-")                              # knee space
    save(front.to_image(glow=False), f"{d}/metal_desk_front.png")
    save_variants("metal_desk", top.to_image(glow=False), tile_side,
                  front_img=front.to_image(glow=False))

    # ---- Lab shelf ----------------------------------------------------------
    top = steel(29)
    save(top.to_image(glow=False), f"{d}/lab_shelf_top.png")

    side = C(16)
    side.rect(1, 0, 14, 15, "+")
    side.hline(1, 14, 4, "="); side.hline(1, 14, 9, "=")
    side.hline(1, 14, 14, "=")
    side.vline(2, 0, 15, "w"); side.vline(13, 0, 15, "w")
    side.disc(5, 2, 1.0, "w"); side.fill(8, 1, 10, 3, "w")     # jars
    side.disc(6, 7, 1.0, "w"); side.fill(9, 6, 11, 8, "w")
    side.fill(4, 11, 6, 13, "w"); side.disc(9, 12, 1.0, "w")
    save(side.to_image(glow=False), f"{d}/lab_shelf_side.png")
    save_variants("lab_shelf", top.to_image(glow=False), side.to_image(glow=False))

    # ---- Server rack ----------------------------------------------------------
    top = steel(33)
    for i in range(4):
        top.disc(4 + i * 3, 8, 0.9, "%")
    save(top.to_image(glow=False), f"{d}/server_rack_top.png")

    front = C(16)
    _panel(front, 1, 0, 14, 15, "=")
    for y in range(1, 15, 3):                             # 1U units
        front.rect(2, y, 13, y + 2, "+")
        front.px(3, y + 1, "G")                           # status LED
        front.hline(5, 12, y + 1, "-")
    save(front.to_image(glow=False), f"{d}/server_rack_front.png")

    back = C(16)
    _panel(back, 1, 0, 14, 15, "=")
    for x, y in ((3, 3), (7, 3), (11, 3), (3, 8), (7, 8), (11, 8),
                 (5, 12), (10, 12)):
        back.px(x, y, "w")                                # ports
        back.px(x + 1, y, "-")
    save(back.to_image(glow=False), f"{d}/server_rack_back.png")
    save_variants("server_rack", top.to_image(glow=False), tile_side,
                  front_img=front.to_image(glow=False),
                  back_img=back.to_image(glow=False))

    # ---- Control panel ----------------------------------------------------------
    front = C(16)
    _panel(front, 1, 0, 14, 15, "=")
    front.rect(2, 1, 13, 6, "%")                          # screen
    front.fill(3, 2, 8, 5, "-")
    front.line(4, 5, 6, 3, "W"); front.line(6, 3, 8, 4, "W")   # waveform
    front.px(11, 2, "G"); front.px(12, 2, "-")
    for x in (3, 6, 9, 12):                               # button row
        front.px(x, 9, "+"); front.px(x, 10, "-")
    front.rect(2, 12, 13, 14, "-")                        # label strip
    front.hline(4, 7, 13, "w"); front.hline(9, 11, 13, "-")
    save(front.to_image(glow=False), f"{d}/control_panel_front.png")
    save(front.to_image(glow=False), f"{d}/control_panel_back.png")
    save_variants("control_panel", front.to_image(glow=False),
                  tile_side, front_img=front.to_image(glow=False))

    # ---- Vent grate ----------------------------------------------------------
    vent = C(16)
    _panel(vent, 0, 0, 15, 15, "=")
    for y in range(2, 14, 3):                             # louvers
        vent.hline(2, 13, y, "+")
        vent.hline(2, 13, y + 1, "~")
    for bx in (1, 14):
        for by in (1, 7, 14):
            vent.px(bx, by, "w")
    save(vent.to_image(glow=False), f"{d}/vent_grate.png")

    # ---- Pipes ----------------------------------------------------------
    pipe_side = C(16)
    pipe_side.fill(3, 0, 12, 15, "=")
    pipe_side.vline(3, 0, 15, "+"); pipe_side.vline(12, 0, 15, "~")
    pipe_side.vline(5, 0, 15, "-"); pipe_side.vline(10, 0, 15, "-")
    for y in range(2, 16, 5):                             # joints
        pipe_side.hline(3, 12, y, "+")
        pipe_side.hline(3, 12, y + 1, "w")
    save(pipe_side.to_image(glow=False), f"{d}/pipe_side.png")

    pipe_end = C(16)
    pipe_end.fill(2, 0, 13, 15, "=")
    pipe_end.disc(7.5, 7.5, 5.2, "+")
    pipe_end.disc(7.5, 7.5, 3.4, "%")                     # bore
    pipe_end.ring(7.5, 7.5, 4.6, "w")
    for ang in range(0, 360, 90):                         # flange bolts
        bx = 7 + int(5.6 * math.cos(math.radians(ang)))
        by = 7 + int(5.6 * math.sin(math.radians(ang)))
        pipe_end.px(bx, by, "w")
    save(pipe_end.to_image(glow=False), f"{d}/pipe_end.png")

    # ---- Caution tape ----------------------------------------------------------
    tape = C(16)
    tape.fill(0, 5, 15, 10, "Y")                          # yellow band
    tape.hline(0, 15, 5, "y"); tape.hline(0, 15, 10, "y")
    for x in range(-16, 17, 8):                           # black stripes
        for y in range(5, 11):
            xx = x + (y - 5)
            if 0 <= xx < 16:
                tape.px(xx, y, "%")
    save(tape.to_image(glow=False), f"{d}/caution_tape.png")

    # ---- Window set ----------------------------------------------------------
    frame = C(16)
    _panel(frame, 0, 0, 15, 15, "=")
    frame.rect(1, 1, 14, 14, "+")
    frame.fill(3, 3, 12, 12, "%")
    frame.vline(7, 1, 14, "+"); frame.hline(1, 14, 7, "+")
    for bx, by in ((2, 2), (13, 2), (2, 13), (13, 13)):
        frame.px(bx, by, "W")
    save(frame.to_image(glow=False), f"{d}/window_frame.png")

    glass = C(16)
    glass.fill(1, 1, 14, 14, "=")
    glass.line(4, 10, 9, 4, "+"); glass.line(8, 11, 12, 7, "-")
    glass.rect(1, 1, 14, 14, "w")
    save(glass.to_image(glow=False), f"{d}/window_glass.png")

    broken = C(16)
    broken.fill(1, 1, 14, 14, "=")
    broken.poly([(3, 2), (7, 7), (5, 12), (9, 9), (12, 13), (12, 6), (8, 3),
                 (10, 8)], "%")                          # impact cracks
    broken.px(8, 7, "w")
    broken.rect(1, 1, 14, 14, "w")
    save(broken.to_image(glow=False), f"{d}/window_broken.png")

    # ---- Warning signs (16x16 node faces) --------------------------------------
    def sign_back() -> C:
        b = C(16)
        b.fill(0, 0, 15, 15, "-")
        b.rect(0, 0, 15, 15, "+")
        for bx, by in ((1, 1), (14, 1), (1, 14), (14, 14)):
            b.px(bx, by, "=")
        return b

    back = sign_back()
    save(back.to_image(glow=False), f"{d}/warning_sign_back.png")

    # general hazard: yellow triangle with exclamation
    hazard = sign_back()
    hazard.poly([(8, 2), (14, 12), (2, 12)], "Y")
    hazard.poly([(8, 4), (12, 11), (4, 11)], "%")
    hazard.fill(7, 6, 8, 9, "Y")
    hazard.fill(7, 10, 8, 10, "Y")
    save(hazard.to_image(glow=False), f"{d}/warning_sign_hazard.png")

    # radiation trefoil
    rad = sign_back()
    rad.disc(8, 8, 6.5, "Y")
    rad.disc(8, 8, 1.4, "%")
    for ang0 in (90, 210, 330):                           # three blades
        for rr in range(30, 62):
            for tt in range(-28, 29):
                x = 8 + int(rr / 10 * math.cos(math.radians(ang0 + tt / 2.2)))
                y = 8 + int(rr / 10 * math.sin(math.radians(ang0 + tt / 2.2)))
                if math.hypot(x - 8, y - 8) >= 2.2:
                    rad.px(x, y, "%")
    save(rad.to_image(glow=False), f"{d}/warning_sign_radiation.png")

    # biohazard (three interlocking arcs + ring)
    bio = sign_back()
    bio.disc(8, 8, 6.5, "Y")
    for cx, cy in ((8, 5), (5.5, 10), (10.5, 10)):
        bio.ring(cx, cy, 2.6, "%")
    bio.ring(8, 8.5, 1.2, "%")
    save(bio.to_image(glow=False), f"{d}/warning_sign_biohazard.png")


# ---------------------------------------------------------------------------
# sl_scary — hide spot (locker you hide inside) + mob texture
# ---------------------------------------------------------------------------
def gen_scary() -> None:
    d = "mods/content/sl_scary/textures"

    top = C(16)
    top.fill(1, 1, 14, 14, "=")
    top.rect(1, 1, 14, 14, "+")
    top.fill(3, 3, 12, 12, "-")
    save(top.to_image(glow=False), f"{d}/hide_spot_top.png")

    bottom = C(16)
    bottom.fill(1, 1, 14, 14, "-")
    bottom.rect(1, 1, 14, 14, "=")
    save(bottom.to_image(glow=False), f"{d}/hide_spot_bottom.png")

    side = C(16)
    _panel(side, 1, 0, 14, 15, "=")
    side.rect(3, 1, 12, 14, "+")
    for y in range(3, 7):                                 # vents
        side.px(4, y, "-"); side.px(6, y, "-"); side.px(8, y, "-")
    side.px(11, 8, "W"); side.px(11, 9, "w")              # handle
    save(side.to_image(glow=False), f"{d}/hide_spot_side.png")

    # scary_mob_texture: pitch-black silhouette with two white eyes
    mob = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    mp = mob.load()
    body = [
        "                ",
        "      ####      ",
        "     ######     ",
        "    ########    ",
        "    ########    ",
        "   ##########   ",
        "   ##W####W##   ",
        "   ##########   ",
        "   ##########   ",
        "    ########    ",
        "    ########    ",
        "   ##########   ",
        "  ###########   ",
        "  ###:::::###   ",
        "  ###########   ",
        "                ",
    ]
    pal = {"#": (10, 10, 12, 255), "W": (255, 255, 255, 255),
           ":": (30, 30, 34, 255), " ": (0, 0, 0, 0)}
    for y, row in enumerate(body):
        for x, ch in enumerate(row):
            mp[x, y] = pal[ch]
    save(mob, f"{d}/scary_mob_texture.png")


# ---------------------------------------------------------------------------
# sl_mvp_assets — platform / terminal / door / item node textures
# ---------------------------------------------------------------------------
def gen_mvp() -> None:
    d = "mods/content/sl_mvp_assets/textures"

    # Platform: dark tread plate with grip dots and edge stripe.
    plat = C(16)
    plat.fill(0, 0, 15, 15, "=")
    plat.hline(0, 15, 0, "+"); plat.hline(0, 15, 15, "~")
    for y in range(3, 14, 3):
        for x in range(2, 15, 3):
            plat.px(x, y, "+")
    plat.hline(0, 15, 1, "w")
    save(plat.to_image(glow=False), f"{d}/platform_texture.png")

    # Terminal: screen with prompt glyph.
    term = C(16)
    _panel(term, 1, 1, 14, 14, "=")
    term.fill(3, 3, 12, 10, "%")
    term.hline(4, 7, 5, "w"); term.vline(8, 5, 6, "w")
    term.hline(4, 8, 8, "+")
    term.hline(3, 12, 12, "-"); term.px(6, 12, "G")
    save(term.to_image(glow=False), f"{d}/terminal_texture.png")

    # Door: secure bulkhead door with porthole + wheel.
    door = C(16)
    _panel(door, 1, 0, 14, 15, "=")
    door.rect(2, 1, 13, 14, "+")
    door.ring(7.5, 6.5, 2.6, "-")                         # porthole
    door.disc(7.5, 6.5, 1.8, "%")
    door.ring(7.5, 11.5, 2.2, "w")                        # wheel
    door.line(6, 11, 9, 11, "w"); door.line(6, 10, 9, 13, "w")
    door.px(7, 5, "w"); door.px(8, 6, "w")
    save(door.to_image(glow=False), f"{d}/door_texture.png")

    # Item: wrapped supply parcel with strap.
    item = C(16)
    item.rect(2, 3, 13, 13, "+")
    item.fill(3, 4, 12, 12, "=")
    item.vline(7, 3, 13, "w"); item.vline(8, 3, 13, "-")  # strap
    item.hline(2, 13, 3, "W")
    item.px(4, 6, "+"); item.px(11, 10, "-")
    save(item.to_image(glow=False), f"{d}/item_texture.png")


# ---------------------------------------------------------------------------
# construction — animated particle strips (32x32 frames) + static decor tiles
# ---------------------------------------------------------------------------
FRAME = 32


def _strip(name: str, frames: int, painter) -> None:
    """Lay out frames horizontally into an animation sheet."""
    sheet = Image.new("RGBA", (FRAME * frames, FRAME), (0, 0, 0, 0))
    for i in range(frames):
        img = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        painter(ImageDraw.Draw(img), i, frames)
        sheet.paste(img, (i * FRAME, 0))
    save(sheet, f"mods/sl_blocks/construction/textures/{name}")


def gen_construction() -> None:
    d = "mods/sl_blocks/construction/textures"

    # ---- fire: white-hot core, warm tips (essential colour) ----------------
    def fire(d2, i, n):
        t = i / n
        rnd = random.Random(100 + i)
        h = 20 + int(6 * math.sin(i / n * 2 * math.pi))
        for yy in range(31, 31 - h, -1):
            p = (31 - yy) / h
            w = max(1, int((1 - p) * 9 + math.sin(yy * 0.8 + i) * 2))
            cx = 16 + int(math.sin(yy * 0.5 + i * 0.9) * (2 + p * 3))
            tone = (255, 255, 255) if p < 0.45 else (
                (255, 208 + rnd.randrange(0, 30), 90) if p < 0.75 else (255, 150, 40))
            for xx in range(cx - w // 2, cx - w // 2 + w + 1):
                a = 255 if p < 0.7 else 230 - int(p * 90)
                if rnd.random() > 0.12:
                    d2.point((xx, yy), fill=(*tone, a))
        for _ in range(3):  # embers
            ex, ey = rnd.randrange(8, 24), rnd.randrange(4, 14)
            d2.point((ex, ey), fill=(255, 190, 80, 200))

    _strip("tech_fire_30frames.png", 30, fire)
    _strip("forest_fire_30f.png", 30, fire)
    _strip("cave_fire_30f.png", 30, fire)

    # ---- smoke: soft white puffs rising and dissolving ----------------------
    def smoke(d2, i, n):
        t = i / n
        rnd = random.Random(200 + i)
        for k in range(3):
            ph = (t + k / 3) % 1.0
            cy = 28 - int(ph * 24)
            r = 3 + int(ph * 6)
            a = int(150 * (1 - ph) + 30)
            cx = 16 + int(math.sin(ph * 5 + k * 2.1) * 4)
            for yy in range(cy - r, cy + r + 1):
                for xx in range(cx - r, cx + r + 1):
                    dd = math.hypot(xx - cx, yy - cy)
                    if dd <= r and rnd.random() < 0.65:
                        shade = 210 + int(40 * (1 - dd / max(1, r)))
                        d2.point((xx, yy), fill=(shade, shade, shade + 6, a))

    _strip("tech_smoke_30frames.png", 30, smoke)
    _strip("forest_smoke_30f.png", 30, smoke)

    # ---- bubbles: rising white rings ----------------------------------------
    def bubbles(d2, i, n):
        rnd = random.Random(300 + i)
        for k in range(4):
            ph = (i / n + k / 4) % 1.0
            cy = 30 - int(ph * 28)
            r = 2 + (k % 3)
            cx = 6 + k * 6 + int(math.sin(ph * 7 + k) * 2)
            for ang in range(0, 360, 30):
                xx = cx + int(r * math.cos(math.radians(ang)))
                yy = cy + int(r * math.sin(math.radians(ang)))
                d2.point((xx, yy), fill=(235, 240, 250, 220))
            d2.point((cx - 1, cy - r + 1), fill=(255, 255, 255, 255))

    _strip("tech_bubbles_30frames.png", 30, bubbles)
    _strip("cave_bubbles_30f.png", 30, bubbles)

    # ---- sparks: white streak bursts -----------------------------------------
    def sparks(d2, i, n):
        rnd = random.Random(400 + i)
        for k in range(4):
            ang = rnd.uniform(0, 2 * math.pi)
            r0 = rnd.uniform(2, 6) + (i % 5)
            ln = rnd.uniform(3, 7)
            x0, y0 = 16 + r0 * math.cos(ang), 16 + r0 * math.sin(ang)
            x1, y1 = 16 + (r0 + ln) * math.cos(ang), 16 + (r0 + ln) * math.sin(ang)
            steps = max(2, int(ln))
            for s in range(steps + 1):
                xx = x0 + (x1 - x0) * s / steps
                yy = y0 + (y1 - y0) * s / steps
                d2.point((int(xx), int(yy)), fill=(255, 255, 255, 240))
            d2.point((int(x1), int(y1)), fill=(255, 240, 200, 180))

    _strip("tech_sparks_30frames.png", 30, sparks)
    _strip("tech_sparks_15frames_loop.png", 15, sparks)
    _strip("tech_sparks_50frames_loop.png", 50, sparks)

    # ---- water: rippling foam (essential pale blue) ---------------------------
    def water(d2, i, n):
        for yy in range(6, 28):
            for xx in range(2, 30):
                wave = math.sin(xx * 0.5 + i * 0.5 + yy * 0.9)
                if wave > 0.55:
                    d2.point((xx, yy), fill=(200, 228, 252, 210))
                elif wave > 0.2 and (xx + yy + i) % 3 == 0:
                    d2.point((xx, yy), fill=(160, 200, 245, 160))

    _strip("forest_water_30f.png", 30, water)
    _strip("cave_water_30f.png", 30, water)
    _strip("tech_water_30frames.png", 30, water)

    # ---- ice: white crystal frost ---------------------------------------------
    def ice(d2, i, n):
        rnd = random.Random(600 + i)
        pulse = 1 + int(math.sin(i / n * 2 * math.pi) * 1)
        for arm in range(6):
            ang = math.radians(arm * 60 + i * 3)
            for r in range(3, 12 + pulse):
                xx = int(16 + r * math.cos(ang))
                yy = int(16 + r * math.sin(ang))
                d2.point((xx, yy), fill=(224, 240, 255, 235))
                if r % 3 == 0:
                    for b in (-1, 1):
                        ba = ang + b * 0.6
                        bx = int(16 + (r - 2) * math.cos(ba) * 0.5 + (r - 2) * math.cos(ang))
                        by = int(16 + (r - 2) * math.sin(ba) * 0.5 + (r - 2) * math.sin(ang))
                        d2.point((bx, by), fill=(200, 224, 248, 200))
        d2.point((16, 16), fill=(255, 255, 255, 255))
        for _ in range(4):
            d2.point((rnd.randrange(4, 28), rnd.randrange(4, 28)),
                     fill=(255, 255, 255, 160))

    _strip("tech_ice_30frames.png", 30, ice)
    _strip("spinning_snowflake_30f.png", 30,
           lambda d2, i, n: ice(d2, i, n))

    # ---- plasma: vertical energy arcs ------------------------------------------
    def plasma(d2, i, n):
        rnd = random.Random(700 + i)
        x = 16
        for yy in range(3, 30):
            x = max(4, min(28, x + rnd.choice((-1, 0, 0, 1))))
            w = 1 if yy % 3 else 2
            for xx in range(x - w, x + w + 1):
                d2.point((xx, yy), fill=(255, 255, 255, 245))
            if rnd.random() < 0.3:
                d2.point((x + rnd.choice((-2, 2)), yy), fill=(170, 226, 255, 180))
        d2.ellipse((13, 0, 19, 5), fill=(255, 255, 255, 220))

    _strip("tech_plasma_30frames.png", 30, plasma)
    _strip("cave_plasma_30f.png", 30, plasma)
    _strip("forest_plasma_8f.png", 8, plasma)

    # ---- static decor tiles ------------------------------------------------------
    def static32(name, painter):
        img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        painter(ImageDraw.Draw(img))
        save(img, f"{d}/{name}")

    # decoration: glowing white shrub
    def decoration(d2):
        rnd = random.Random(9)
        for _ in range(26):
            x, y = 16 + rnd.randrange(-8, 9), 26 - rnd.randrange(0, 14)
            d2.line((x, y, x, y + rnd.randrange(2, 5)),
                    fill=(220 + rnd.randrange(0, 35), 226, 235, 235))
        d2.ellipse((12, 8, 20, 16), outline=(255, 255, 255, 200))

    # platform: hovering tech platform tile
    def platform(d2):
        d2.rectangle((2, 12, 29, 19), fill=(52, 56, 66, 255))
        d2.rectangle((2, 12, 29, 19), outline=(210, 216, 228, 255))
        d2.line((4, 14, 27, 14), fill=(255, 255, 255, 255))
        for x in range(6, 27, 5):
            d2.point((x, 17), fill=(150, 156, 170, 255))
        d2.polygon([(8, 20), (24, 20), (20, 25), (12, 25)], fill=(34, 37, 45, 255))

    # wall: segmented panel wall with glow seams
    def wall(d2):
        d2.rectangle((0, 0, 31, 31), fill=(48, 52, 62, 255))
        d2.rectangle((0, 0, 31, 31), outline=(28, 30, 38, 255))
        for yy in (10, 21):
            d2.line((2, yy, 29, yy), fill=(160, 166, 180, 255))
        d2.line((16, 2, 16, 10), fill=(255, 255, 255, 180))
        d2.rectangle((5, 4, 9, 8), outline=(120, 126, 140, 255))
        d2.rectangle((22, 23, 27, 28), outline=(120, 126, 140, 255))

    # special: crystal cluster
    def special(d2):
        for pts in (((16, 4), (21, 16), (16, 27), (11, 16)),
                    ((7, 10), (11, 18), (8, 26), (4, 18)),
                    ((25, 9), (28, 17), (24, 25), (21, 17))):
            d2.polygon(pts, fill=(206, 214, 228, 255))
            d2.line((pts[0][0], pts[0][1], pts[2][0], pts[2][1]),
                    fill=(255, 255, 255, 255))
        d2.point((16, 8), fill=(255, 255, 255, 255))

    static32("forest_decoration_1.png", decoration)
    static32("forest_platform_0.png", platform)
    static32("forest_wall_0.png", wall)
    static32("forest_special_0.png", special)


# ---------------------------------------------------------------------------
# sl_mvp_assets — mob / player model textures + particle glows + HUD
# ---------------------------------------------------------------------------
def gen_mvp_models() -> None:
    d = "mods/content/sl_mvp_assets/textures"

    # monster: grey beast — tinted via ^[colorize overlays in entities.lua
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(img)
    rnd = random.Random(5)
    # hunched body
    d2.ellipse((8, 18, 56, 58), fill=(96, 100, 112, 255))
    d2.ellipse((14, 24, 50, 52), fill=(120, 124, 136, 255))
    # head
    d2.ellipse((22, 6, 46, 28), fill=(104, 108, 120, 255))
    # eyes (white, glow)
    d2.rectangle((27, 14, 30, 18), fill=(255, 255, 255, 255))
    d2.rectangle((37, 14, 40, 18), fill=(255, 255, 255, 255))
    # claws
    for cx in (14, 26, 38, 50):
        d2.polygon([(cx, 44), (cx + 4, 58), (cx - 3, 56)], fill=(140, 144, 156, 255))
    # fur ticks
    for _ in range(90):
        x, y = rnd.randrange(10, 54), rnd.randrange(20, 56)
        if d2._image.getpixel((x, y))[3]:
            v = rnd.randrange(70, 150)
            d2.point((x, y), fill=(v, v, v + 8, 255))
    save(img, f"{d}/monster_texture.png")

    # player: identity-neutral pale figure
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(img)
    d2.ellipse((24, 4, 40, 20), fill=(210, 214, 224, 255))          # head
    d2.rectangle((22, 20, 42, 44), fill=(190, 194, 206, 255))       # torso
    d2.rectangle((14, 20, 21, 42), fill=(180, 184, 196, 255))       # arms
    d2.rectangle((43, 20, 50, 42), fill=(180, 184, 196, 255))
    d2.rectangle((24, 44, 32, 62), fill=(170, 174, 186, 255))       # legs
    d2.rectangle((32, 44, 40, 62), fill=(170, 174, 186, 255))
    d2.rectangle((26, 10, 30, 13), fill=(40, 42, 50, 255))          # visor band
    d2.rectangle((34, 10, 38, 13), fill=(40, 42, 50, 255))
    save(img, f"{d}/player_texture.png")

    # radial white glows
    def radial(name, inner=255, mid=140):
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        px = img.load()
        for y in range(64):
            for x in range(64):
                dd = math.hypot(x - 31.5, y - 31.5) / 31
                if dd < 1:
                    a = int((1 - dd) ** 1.8 * inner)
                    px[x, y] = (255, 255, 255, min(255, a + (mid if dd < 0.3 else 0)))
        save(img, f"{d}/{name}")

    radial("flare_light_texture.png")
    radial("particle_texture.png", inner=220)
    radial("pulse_texture.png")

    # pulse ring variant overlay: crisp ring on the glow
    img = Image.open(f"{d}/pulse_texture.png")
    d2 = ImageDraw.Draw(img)
    d2.ellipse((14, 14, 50, 50), outline=(255, 255, 255, 255), width=3)
    d2.ellipse((20, 20, 44, 44), outline=(255, 255, 255, 120), width=1)
    save(img, f"{d}/pulse_texture.png")

    # neon cube: white wireframe cube
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(img)
    f = [(8, 24), (40, 24), (40, 56), (8, 56)]
    b = [(22, 8), (54, 8), (54, 40), (22, 40)]
    d2.polygon(f, outline=(255, 255, 255, 255), width=2)
    d2.polygon(b, outline=(210, 216, 228, 255), width=2)
    for i in range(4):
        d2.line((f[i], b[i]), fill=(170, 176, 190, 255), width=2)
    save(img, f"{d}/neon_cube.png")

    # cursor: precise white crosshair
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(img)
    d2.line((16, 2, 16, 29), fill=(255, 255, 255, 255), width=1)
    d2.line((2, 16, 29, 16), fill=(255, 255, 255, 255), width=1)
    d2.line((16, 2, 16, 6), fill=(20, 20, 24, 255), width=3)
    d2.line((16, 26, 16, 29), fill=(20, 20, 24, 255), width=3)
    d2.line((2, 16, 6, 16), fill=(20, 20, 24, 255), width=3)
    d2.line((26, 16, 29, 16), fill=(20, 20, 24, 255), width=3)
    save(img, f"{d}/cursor.png")

    # HUD: monochrome status bars + frame
    hud = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(hud)
    for k, y in enumerate((6, 20, 34, 48)):
        d2.rounded_rectangle((2, y, 253, y + 11), radius=4,
                             fill=(18, 20, 26, 200), outline=(200, 205, 216, 255))
        wfill = (250 - int(30 * k)) if k < 3 else 120
        d2.rounded_rectangle((5, y + 3, 5 + wfill, y + 8), radius=2,
                             fill=(235, 238, 246, 255))
    save(hud, f"{d}/hud.png")

    fr = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(fr)
    d2.rounded_rectangle((1, 1, 254, 62), radius=6,
                         outline=(220, 224, 234, 255), width=2)
    for x in range(12, 250, 24):
        d2.line((x, 4, x, 9), fill=(150, 156, 170, 255), width=1)
    save(fr, f"{d}/hud_frame.png")


# ---------------------------------------------------------------------------
# sl_clothing — garment icons on the standard plate (64x64)
# ---------------------------------------------------------------------------
def gen_clothing() -> None:
    d = "mods/content/sl_clothing/textures"

    S = 4  # 16x16 -> 64x64

    def clothing_icon(rel, painter):
        c = C(16)
        painter(c)
        img = c.to_image(glow=True)
        big = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        plate = C(16)
        plate.fill(2, 2, 13, 13, "#")
        plate.rect(1, 2, 14, 13, "~")
        plate.rect(2, 1, 13, 14, "~")
        big.alpha_composite(plate.to_image(glow=False).resize((64, 64), Image.NEAREST))
        big.alpha_composite(img.resize((64, 64), Image.NEAREST))
        save(big, f"{d}/{rel}.png")

    def hood(c):
        c.poly([(3, 8), (5, 4), (11, 4), (13, 8), (12, 12), (4, 12)], "w")
        c.poly([(6, 7), (8, 5), (10, 7), (10, 12), (6, 12)], "%")

    def cap(c):
        c.fill(4, 6, 11, 10, "+")
        c.hline(5, 10, 5, "w")
        c.fill(2, 9, 7, 10, "w")            # brim
        c.px(8, 3, "W")

    def jacket(c):
        c.poly([(3, 4), (6, 3), (8, 5), (10, 3), (13, 4), (13, 12), (3, 12)], "w")
        c.vline(8, 5, 12, "-")
        c.line(3, 4, 5, 12, "+"); c.line(13, 4, 11, 12, "+")

    def coat(c):
        c.poly([(2, 4), (6, 3), (8, 5), (10, 3), (14, 4), (13, 13), (3, 13)], "w")
        c.vline(8, 5, 13, "-")
        c.px(5, 7, "W"); c.px(11, 7, "W")   # buttons

    def backpack(c):
        c.rect(4, 3, 12, 13, "+")
        c.rect(5, 4, 11, 12, "=")
        c.rect(6, 1, 10, 3, "-")            # straps
        c.px(8, 8, "W"); c.px(9, 8, "W")

    def glove(c):
        c.fill(4, 4, 11, 11, "+")
        c.px(5, 3, "+"); c.px(8, 3, "+"); c.px(10, 3, "+")
        c.fill(4, 12, 9, 13, "w")           # cuff
        c.hline(4, 11, 7, "-")

    def trousers(c):
        c.rect(5, 2, 11, 5, "w")
        c.fill(5, 6, 7, 13, "+"); c.fill(9, 6, 11, 13, "+")
        c.vline(8, 2, 5, "-")

    def boots(c):
        c.fill(5, 3, 8, 9, "+")
        c.fill(5, 10, 12, 12, "w")          # sole
        c.hline(5, 12, 13, "-")
        c.px(6, 4, "W")

    clothing_icon("character_tool_head_01", hood)
    clothing_icon("character_tool_head_02", cap)
    clothing_icon("character_tool_body_01", jacket)
    clothing_icon("character_tool_body_02", coat)
    clothing_icon("character_tool_back_01", backpack)
    clothing_icon("character_tool_hand_01", glove)
    clothing_icon("character_tool_hand_02", glove)
    clothing_icon("character_tool_legs_01", trousers)
    clothing_icon("character_tool_legs_02", trousers)
    clothing_icon("character_tool_feet_01", boots)
    clothing_icon("character_tool_feet_02", boots)


# ---------------------------------------------------------------------------
# sl_characters — identity-neutral boxman (colorizable base)
# ---------------------------------------------------------------------------
def gen_boxman() -> None:
    c = C(16)
    c.rect(5, 1, 10, 5, "w")            # head
    c.rect(6, 2, 9, 4, "=")
    c.px(7, 3, "W"); c.px(9, 3, "W")    # eyes
    c.vline(8, 6, 11, "+")              # torso
    c.fill(6, 6, 7, 11, "w"); c.fill(9, 6, 10, 11, "w")
    c.hline(4, 6, 6, "w"); c.hline(10, 12, 6, "w")     # arms
    c.fill(4, 6, 4, 10, "+"); c.fill(12, 6, 12, 10, "+")
    c.fill(6, 12, 7, 15, "-"); c.fill(9, 12, 10, 15, "-")  # legs
    save(c.to_image(glow=True), "mods/content/sl_characters/textures/sl_boxman_neon.png")


# ---------------------------------------------------------------------------
# dark_skybox — crisp pixel sun
# ---------------------------------------------------------------------------
def gen_sun() -> None:
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    px = img.load()
    cx = cy = 63.5
    for y in range(128):
        for x in range(128):
            dd = math.hypot(x - cx, y - cy)
            if dd < 34:
                px[x, y] = (255, 255, 255, 255)
            elif dd < 40:
                px[x, y] = (255, 255, 255, int(160 * (1 - (dd - 34) / 6)))
            elif dd < 52:
                px[x, y] = (255, 255, 255, int(70 * (1 - (dd - 40) / 12)))
    d2 = ImageDraw.Draw(img)
    for arm in range(8):  # short rays
        ang = math.radians(arm * 45)
        d2.line((cx + 44 * math.cos(ang), cy + 44 * math.sin(ang),
                 cx + 54 * math.cos(ang), cy + 54 * math.sin(ang)),
                fill=(255, 255, 255, 120), width=3)
    save(img, "mods/content/dark_skybox/textures/round_sun.png")


# ---------------------------------------------------------------------------
# sl_formspec — crisp dark panel + buttons (24x24)
# ---------------------------------------------------------------------------
def gen_formspec() -> None:
    d = "mods/apis/sl_formspec/textures"

    def panel(alpha_fill=235):
        img = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
        d2 = ImageDraw.Draw(img)
        d2.rectangle((0, 0, 23, 23), fill=(16, 18, 23, alpha_fill))
        d2.rectangle((0, 0, 23, 23), outline=(210, 214, 224, 255))
        d2.rectangle((1, 1, 22, 22), outline=(70, 75, 88, 255))
        d2.line((2, 2, 21, 2), fill=(120, 126, 140, 255))
        return img

    save(panel(), f"{d}/tz_formspec_bg.png")
    save(panel(), f"{d}/tz_formspec_button.png")
    img = panel()
    dd = ImageDraw.Draw(img)
    dd.rectangle((1, 1, 22, 22), outline=(255, 255, 255, 255))
    save(img, f"{d}/tz_formspec_button_hovered.png")
    img = panel()
    dd = ImageDraw.Draw(img)
    dd.rectangle((1, 1, 22, 22), outline=(150, 156, 170, 255))
    dd.rectangle((2, 2, 21, 21), fill=(10, 11, 15, 255))
    save(img, f"{d}/tz_formspec_button_pressed.png")


# ---------------------------------------------------------------------------
# dignodes — tool durability overlays
# ---------------------------------------------------------------------------
def gen_dignodes() -> None:
    d = "mods/apis/dignodes/textures"

    hammer = [
        "                ",
        "   WWWWWWWW     ",
        "   WWWWWWWW     ",
        "   WW====WW     ",
        "      ==        ",
        "      ==        ",
        "      ==        ",
        "      ==        ",
        "      ==        ",
        "      ==        ",
        "      ==        ",
        "      ==        ",
        "     ====       ",
        "                ",
        "                ",
        "                ",
    ]
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    pal = {"W": (255, 255, 255, 255), "=": (140, 146, 160, 255),
           " ": (0, 0, 0, 0)}
    for y, row in enumerate(hammer):
        for x, ch in enumerate(row):
            px[x, y] = pal[ch]
    save(img, f"{d}/dignodes_choppy.png")

    crack = [
        "                ",
        "                ",
        "        W       ",
        "        W       ",
        "       W        ",
        "       W        ",
        "      W         ",
        "      W         ",
        "       W        ",
        "       W        ",
        "        W       ",
        "        W       ",
        "                ",
        "                ",
        "                ",
        "                ",
    ]
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(crack):
        for x, ch in enumerate(row):
            if ch == "W":
                px[x, y] = (20, 20, 20, 255)
    save(img, f"{d}/dignodes_cracky.png")

    # crumbly: scattered dark dots
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    rnd = random.Random(3)
    for _ in range(26):
        x, y = rnd.randrange(16), rnd.randrange(16)
        px[x, y] = (20, 20, 20, 255)
    save(img, f"{d}/dignodes_crumbly.png")

    save(Image.new("RGBA", (16, 16), (20, 20, 20, 255)),
         f"{d}/dignodes_dig_immediate.png")
    save(Image.new("RGBA", (16, 16), (0, 0, 0, 0)), f"{d}/dignodes_none.png")

    for rating in (1, 2, 3):
        r = C(16)
        for i in range(rating):
            r.px(5 + i * 3, 12, "W")
            r.px(5 + i * 3, 11, "W")
            r.px(6 + i * 3, 12, "-")
        save(r.to_image(glow=False), f"{d}/dignodes_rating{rating}.png")


# ---------------------------------------------------------------------------
# sl_hand — first-person hand (identity-neutral light silhouette)
# ---------------------------------------------------------------------------
def gen_hand() -> None:
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    px = img.load()
    rnd = random.Random(77)
    for y in range(128):                                   # forearm
        for x in range(128):
            if x > 60 + (127 - y) * 0.35 - 18 and y > 40:
                t = (x + y) / 256
                v = 96 + int(70 * rnd.random() * (1 - t / 1.6))
                px[x, y] = (v, v, v + 6, 255)
    for y in range(40, 86):                                # fist
        for x in range(56, 112):
            dx, dy = (x - 84) / 28, (y - 63) / 23
            if dx * dx + dy * dy < 1:
                v = 128 + int(80 * rnd.random() * (1 - (dx + dy + 2) / 4))
                px[x, y] = (v, v, v + 6, 255)
    for y in range(70, 100):                               # thumb
        for x in range(48, 78):
            dx, dy = (x - 63) / 15, (y - 85) / 15
            if dx * dx + dy * dy < 1:
                v = 110 + int(60 * rnd.random())
                px[x, y] = (v, v, v + 6, 255)
    for kx in range(64, 110, 10):                          # knuckle hints
        for y in range(46, 54):
            if px[kx, y][3]:
                px[kx, y] = (70, 70, 78, 255)
    save(img, "mods/apis/sl_hand/textures/sl_hand_neon.png")


# ---------------------------------------------------------------------------
# sl_gui — HUD/inventory symbols 16x16 (white glyphs with glow)
# ---------------------------------------------------------------------------
def gen_gui() -> None:
    d = "mods/apis/sl_gui/textures"

    def glyph(rel: str, draw) -> None:
        c = C(16)
        draw(c)
        save(c.to_image(), f"{d}/{rel}.png")

    # --- ability icons ------------------------------------------------------
    glyph("ability_attack", lambda c: (
        c.ring(7.5, 7.5, 6.0, "w"),
        c.poly([(8, 3), (6, 8), (9, 8), (7, 13)], "W", close=False),
    ))
    glyph("ability_armor_efficiency", lambda c: (
        c.poly([(8, 2), (13, 4), (13, 9), (8, 14), (3, 9), (3, 4)], "w"),
        c.poly([(8, 4), (11, 5), (11, 8), (8, 11), (5, 8), (5, 5)], "-"),
        c.px(8, 6, "W"), c.px(8, 8, "W"),
    ))
    glyph("ability_auto_repair", lambda c: (
        c.ring(7.5, 8.5, 4.0, "w"), c.px(7, 4, "="), c.px(8, 4, "="),
        c.line(11, 2, 13, 4, "W"), c.line(12, 2, 13, 3, "W"),
        c.px(10, 3, "W"),
    ))
    glyph("ability_breath", lambda c: (
        c.line(3, 5, 10, 5, "w"), c.line(10, 5, 12, 6, "w"),
        c.line(3, 8, 11, 8, "w"), c.line(11, 8, 13, 9, "w"),
        c.line(3, 11, 9, 11, "w"), c.line(9, 11, 11, 12, "w"),
    ))
    glyph("ability_build", lambda c: (
        c.rect(3, 3, 8, 8, "w"), c.rect(7, 7, 12, 12, "w"),
        c.px(4, 4, "W"), c.px(9, 9, "W"),
    ))
    glyph("ability_bulk_craft", lambda c: (
        c.rect(2, 5, 7, 10, "w"), c.rect(6, 4, 11, 9, "+"),
        c.rect(9, 6, 14, 11, "-"),
    ))
    glyph("ability_craft_speed", lambda c: (
        c.ring(7.5, 8.5, 4.4, "w"),
        c.line(7, 8, 10, 5, "W"), c.px(7, 8, "W"),
        c.line(12, 2, 14, 4, "w"), c.line(13, 1, 14, 2, "w"),
    ))
    glyph("ability_critical", lambda c: (
        c.line(8, 2, 8, 13, "W"), c.line(3, 7, 13, 7, "W"),
        c.line(5, 4, 11, 10, "w"), c.line(11, 4, 5, 10, "w"),
    ))
    glyph("ability_defense", lambda c: (
        c.poly([(8, 2), (13, 4), (13, 9), (8, 14), (3, 9), (3, 4)], "w"),
        c.line(8, 4, 8, 11, "W"), c.line(5, 7, 11, 7, "W"),
    ))
    glyph("ability_durability", lambda c: (
        c.rect(2, 6, 13, 10, "w"),
        c.vline(3, 7, 9, "W"), c.vline(5, 7, 9, "W"), c.vline(7, 7, 9, "W"),
        c.vline(9, 7, 9, "W"), c.vline(12, 7, 9, "-"),
        c.fill(6, 4, 9, 5, "+"),
    ))
    glyph("ability_efficiency", lambda c: (
        c.line(8, 2, 8, 8, "w"), c.line(8, 8, 12, 11, "W"),
        c.ring(7.5, 7.5, 5.5, "-"),
    ))
    glyph("ability_fast_dig", lambda c: (
        c.line(4, 12, 10, 6, "w"), c.line(5, 13, 11, 7, "+"),
        c.line(9, 4, 12, 7, "W"), c.px(10, 3, "W"), c.px(13, 6, "W"),
        c.px(3, 10, "-"),
    ))
    glyph("ability_fly", lambda c: (
        c.line(8, 3, 8, 12, "w"),
        c.poly([(8, 5), (3, 3), (4, 7)], "w"),
        c.poly([(8, 5), (13, 3), (12, 7)], "w"),
        c.line(6, 13, 10, 13, "W"),
    ))
    glyph("ability_gravity", lambda c: (
        c.disc(8, 4, 1.6, "W"),
        c.disc(8, 12, 2.6, "w"),
        c.line(8, 6, 8, 8, "+"),
    ))
    glyph("ability_health", lambda c: (
        c.px(4, 3, "w"), c.px(3, 4, "w"), c.px(2, 5, "w"),
        c.px(12, 3, "w"), c.px(13, 4, "w"), c.px(14, 5, "w"),
        c.line(8, 13, 3, 6, "w"), c.line(8, 13, 13, 6, "w"),
        c.line(4, 4, 8, 9, "W"), c.line(12, 4, 8, 9, "W"),
    ))
    glyph("ability_inventory", lambda c: (
        c.rect(3, 3, 12, 13, "w"), c.hline(3, 12, 6, "w"),
        c.vline(8, 3, 6, "w"),
        c.px(5, 9, "W"), c.px(8, 9, "W"), c.px(11, 9, "W"),
    ))
    glyph("ability_invisibility", lambda c: (
        c.line(3, 3, 13, 13, "w"),
        c.line(13, 3, 3, 13, "w"),
        c.px(8, 8, "W"),
    ))
    glyph("ability_jump", lambda c: (
        c.line(8, 12, 8, 3, "W"),
        c.line(5, 6, 8, 3, "w"), c.line(11, 6, 8, 3, "w"),
        c.hline(5, 11, 13, "w"),
    ))
    glyph("ability_light", lambda c: (
        c.disc(8, 7, 2.6, "W"),
        c.line(8, 2, 8, 3, "w"), c.line(8, 11, 8, 12, "w"),
        c.line(3, 7, 4, 7, "w"), c.line(12, 7, 13, 7, "w"),
        c.line(4, 3, 5, 4, "w"), c.line(11, 3, 12, 4, "w"),
        c.line(4, 11, 5, 10, "w"), c.line(11, 11, 12, 10, "w"),
        c.hline(6, 10, 14, "+"),
    ))
    glyph("ability_master_craft", lambda c: (
        c.line(4, 13, 4, 4, "w"), c.hline(3, 6, 3, "W"),
        c.line(6, 4, 6, 8, "w"),
        c.line(10, 13, 10, 4, "w"), c.hline(9, 12, 3, "W"),
        c.line(12, 4, 12, 8, "w"),
        c.hline(3, 13, 13, "w"),
    ))
    glyph("ability_noclip", lambda c: (
        c.rect(3, 3, 12, 12, "w"),
        c.line(2, 2, 6, 6, "W"), c.line(13, 13, 9, 9, "W"),
        c.line(13, 2, 9, 6, "W"), c.line(2, 13, 6, 9, "W"),
    ))
    glyph("ability_reach", lambda c: (
        c.line(3, 12, 9, 6, "w"), c.disc(10, 5, 1.8, "W"),
        c.line(12, 3, 14, 1, "+"), c.px(13, 3, "+"),
    ))
    glyph("ability_recipes", lambda c: (
        c.rect(4, 2, 12, 13, "w"), c.vline(4, 2, 13, "+"),
        c.hline(6, 10, 5, "-"), c.hline(6, 10, 7, "-"),
        c.hline(6, 10, 9, "-"), c.hline(6, 8, 10, "-"),
    ))
    glyph("ability_resist_fire", lambda c: (
        c.poly([(8, 2), (11, 6), (12, 9), (10, 13), (6, 13), (4, 9),
                (5, 6)], "w"),
        c.line(8, 5, 8, 10, "W"), c.line(6, 13, 10, 13, "+"),
    ))
    glyph("ability_resist_hunger", lambda c: (
        c.disc(8, 6, 3.2, "w"), c.line(5, 9, 5, 13, "w"),
        c.line(11, 9, 11, 13, "w"), c.px(6, 5, "W"),
        c.px(10, 7, "+"),
    ))
    glyph("ability_resist_poison", lambda c: (
        c.poly([(8, 2), (12, 9), (8, 13), (4, 9)], "w"),
        c.line(8, 5, 8, 10, "W"), c.px(7, 11, "W"), c.px(9, 11, "W"),
    ))
    glyph("ability_shadow_step", lambda c: (
        c.disc(6, 8, 3.4, "="),
        c.line(10, 4, 13, 4, "w"), c.line(10, 8, 14, 8, "w"),
        c.line(10, 12, 13, 12, "w"),
    ))
    glyph("ability_speed", lambda c: (
        c.line(3, 5, 10, 5, "w"), c.line(5, 8, 12, 8, "W"),
        c.line(3, 11, 10, 11, "w"),
        c.line(11, 5, 14, 5, "+"), c.line(13, 8, 14, 8, "+"),
        c.line(11, 11, 14, 11, "+"),
    ))
    glyph("ability_sprint_efficiency", lambda c: (
        c.disc(5, 4, 1.4, "W"),
        c.line(4, 7, 9, 7, "w"), c.line(9, 7, 12, 9, "w"),
        c.line(5, 11, 10, 11, "w"), c.line(3, 13, 7, 13, "+"),
        c.line(12, 12, 14, 13, "+"),
    ))
    glyph("ability_sprint_hud", lambda c: (
        c.line(2, 8, 13, 8, "-"),
        c.line(2, 8, 5, 8, "W"), c.line(4, 7, 5, 8, "W"),
        c.line(6, 6, 8, 8, "+"), c.line(9, 9, 11, 8, "+"),
        c.line(13, 6, 13, 10, "w"),
    ))
    glyph("ability_stealth", lambda c: (
        c.disc(8, 7, 3.0, "="),
        c.line(2, 13, 5, 13, "w"), c.line(7, 13, 10, 13, "w"),
        c.line(12, 13, 14, 13, "w"),
        c.px(7, 6, "W"),
    ))
    glyph("ability_swim", lambda c: (
        c.line(2, 5, 5, 4, "w"), c.line(5, 4, 8, 5, "w"),
        c.line(8, 5, 11, 4, "w"), c.line(11, 4, 14, 5, "w"),
        c.line(2, 9, 5, 8, "W"), c.line(5, 8, 8, 9, "W"),
        c.line(8, 9, 11, 8, "W"), c.line(11, 8, 14, 9, "W"),
        c.line(2, 13, 5, 12, "+"), c.line(5, 12, 8, 13, "+"),
        c.line(8, 13, 11, 12, "+"), c.line(11, 12, 14, 13, "+"),
    ))
    glyph("ability_teleport", lambda c: (
        c.ring(7.5, 7.5, 5.5, "w"),
        c.px(7, 2, "W"), c.px(8, 2, "W"),
        c.px(2, 7, "W"), c.px(2, 8, "W"),
        c.px(13, 7, "W"), c.px(13, 8, "W"),
        c.px(7, 13, "W"), c.px(8, 13, "W"),
    ))

    # --- GUI buttons / slots / tabs ------------------------------------------
    def btn_frame(c, ch: str = "w"):
        c.rect(1, 1, 14, 14, ch)
        c.rect(2, 2, 13, 13, "=")
        c.hline(2, 13, 2, "+")
        c.hline(2, 13, 13, "~")

    glyph("gui_button_clear", lambda c: (
        btn_frame(c), c.line(4, 4, 11, 11, "W"), c.line(11, 4, 4, 11, "W"),
    ))
    glyph("gui_button_craft", lambda c: (
        btn_frame(c),
        c.rect(4, 4, 7, 7, "w"), c.rect(8, 8, 11, 11, "w"),
        c.px(5, 5, "W"), c.px(9, 9, "W"),
    ))
    glyph("gui_button_done", lambda c: (
        btn_frame(c),
        c.line(4, 8, 7, 11, "W"), c.line(7, 11, 12, 4, "W"),
    ))
    glyph("gui_button_nav_down", lambda c: (
        btn_frame(c),
        c.line(4, 6, 8, 11, "W"), c.line(8, 11, 12, 6, "W"),
    ))
    glyph("gui_button_nav_left", lambda c: (
        btn_frame(c),
        c.line(11, 4, 5, 8, "W"), c.line(5, 8, 11, 12, "W"),
    ))
    glyph("gui_button_nav_reset", lambda c: (
        btn_frame(c), c.ring(7.5, 7.5, 3.6, "W"), c.px(7, 7, "W"),
    ))
    glyph("gui_button_nav_right", lambda c: (
        btn_frame(c),
        c.line(4, 4, 10, 8, "W"), c.line(10, 8, 4, 12, "W"),
    ))
    glyph("gui_button_nav_up", lambda c: (
        btn_frame(c),
        c.line(4, 11, 8, 6, "W"), c.line(8, 6, 12, 11, "W"),
    ))
    glyph("gui_button_next", lambda c: (
        btn_frame(c),
        c.line(3, 4, 8, 8, "W"), c.line(8, 8, 3, 12, "W"),
        c.line(8, 4, 13, 8, "W"), c.line(13, 8, 8, 12, "W"),
    ))
    glyph("gui_button_search", lambda c: (
        btn_frame(c), c.ring(7, 7, 3.2, "W"), c.line(9, 10, 12, 13, "W"),
    ))
    glyph("gui_button_skip", lambda c: (
        btn_frame(c),
        c.line(4, 4, 9, 8, "W"), c.line(9, 8, 4, 12, "W"),
        c.line(9, 4, 13, 8, "-"), c.line(13, 8, 9, 12, "-"),
    ))
    glyph("gui_category_basic", lambda c: (
        c.rect(2, 2, 13, 13, "w"), c.rect(3, 3, 12, 12, "="),
        c.px(4, 4, "W"),
    ))
    glyph("gui_category_advanced", lambda c: (
        c.ring(7.5, 7.5, 5.0, "w"), c.ring(7.5, 7.5, 2.4, "W"),
    ))
    glyph("gui_category_glass", lambda c: (
        c.rect(2, 2, 13, 13, "w"), c.rect(3, 3, 12, 12, "="),
        c.line(5, 10, 9, 5, "+"), c.line(8, 11, 11, 8, "-"),
    ))
    glyph("gui_category_objective", lambda c: (
        c.ring(7.5, 7.5, 5.2, "w"),
        c.px(7, 2, "W"), c.px(8, 2, "W"),
        c.px(7, 13, "W"), c.px(8, 13, "W"),
        c.px(2, 7, "W"), c.px(2, 8, "W"),
        c.px(13, 7, "W"), c.px(13, 8, "W"),
        c.px(7, 7, "W"), c.px(8, 8, "W"),
    ))
    glyph("gui_category_urban", lambda c: (
        c.fill(2, 8, 13, 13, "="),
        c.rect(2, 8, 13, 13, "w"),
        c.fill(3, 3, 6, 8, "+"), c.fill(9, 2, 12, 8, "+"),
        c.px(4, 4, "W"), c.px(10, 4, "W"), c.px(4, 10, "+"), c.px(11, 10, "+"),
    ))

    def slot(rel: str, kind: str) -> None:
        c = C(16)
        c.rect(1, 1, 14, 14, "-")
        c.rect(2, 2, 13, 13, "=")
        c.px(2, 2, "~")
        if kind == "head":
            c.disc(8, 7, 2.8, "w"); c.fill(6, 9, 10, 12, "w")
        elif kind == "torso":
            c.line(5, 4, 4, 12, "w"); c.line(11, 4, 12, 12, "w")
            c.line(5, 4, 11, 4, "w"); c.line(4, 12, 12, 12, "w")
            c.line(6, 5, 10, 5, "W")
        elif kind == "leg":
            c.rect(5, 3, 10, 6, "w"); c.vline(6, 7, 12, "w")
            c.vline(9, 7, 12, "w")
        elif kind == "foot":
            c.line(4, 5, 4, 10, "w"); c.line(4, 10, 11, 10, "w")
            c.line(11, 10, 11, 12, "w"); c.hline(4, 11, 12, "w")
        elif kind == "hand":
            c.disc(8, 8, 2.6, "w"); c.line(8, 5, 8, 11, "+")
            c.line(5, 8, 11, 8, "+")
        save(c.to_image(glow=False), f"{d}/{rel}.png")

    slot("gui_slot_back", "torso")
    slot("gui_slot_foot", "foot")
    slot("gui_slot_hand", "hand")
    slot("gui_slot_head", "head")
    slot("gui_slot_leg", "leg")
    slot("gui_slot_torso", "torso")

    def tab(rel: str, kind: str) -> None:
        c = C(16)
        c.rect(1, 1, 14, 14, "w"); c.rect(2, 2, 13, 13, "=")
        if kind == "crafting":
            c.rect(4, 4, 7, 7, "w"); c.rect(8, 8, 11, 11, "w")
            c.px(5, 5, "W"); c.px(9, 9, "W")
        elif kind == "abilities":
            c.line(8, 3, 8, 12, "W"); c.line(3, 7, 13, 7, "W")
        elif kind == "achievements":
            c.poly([(8, 3), (9, 6), (12, 6), (10, 8), (11, 11), (8, 9),
                    (5, 11), (6, 8), (4, 6), (7, 6)], "W")
        else:  # player info
            c.disc(8, 6, 2.0, "w"); c.fill(5, 9, 11, 12, "w")
        save(c.to_image(glow=False), f"{d}/{rel}.png")

    tab("gui_tab_abilities", "abilities")
    tab("gui_tab_achievements", "achievements")
    tab("gui_tab_crafting", "crafting")
    tab("gui_tab_player_info", "player")

    # small star used by achievement HUD
    star = C(16)
    star.poly([(8, 2), (9, 6), (13, 6), (10, 9), (11, 13), (8, 10),
               (5, 13), (6, 9), (3, 6), (7, 6)], "W")
    save(star.to_image(), f"{d}/gui_achievement_star.png")

    save(Image.new("RGBA", (1, 1), (0, 0, 0, 0)), f"{d}/gui_blank.png")

    # wide category banners (256x64): white pictogram + dark translucent band
    from PIL import ImageDraw as _ID

    def banner(rel: str, kind: str) -> None:
        img = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
        px = img.load()
        rnd = random.Random(hash(rel) & 0xFF)
        for y in range(8, 56):
            edge = 14 if 16 < y < 48 else 0
            for x in range(edge, 256 - edge):
                px[x, y] = (14, 16, 20, 200)
        d2 = _ID.Draw(img)
        if kind == "equipment":
            d2.polygon([(30, 20), (46, 26), (46, 40), (30, 46)],
                       outline=(255, 255, 255, 255))
            d2.line((33, 33, 43, 33), fill=(255, 255, 255, 255), width=3)
        elif kind == "salvage":
            d2.polygon([(26, 44), (34, 22), (42, 44)],
                       outline=(255, 255, 255, 255))
            d2.line((30, 38, 38, 38), fill=(255, 255, 255, 255), width=3)
        elif kind == "tactical":
            d2.ellipse((26, 22, 46, 42), outline=(255, 255, 255, 255), width=3)
            d2.line((36, 22, 36, 42), fill=(255, 255, 255, 255), width=2)
        else:  # information
            d2.ellipse((28, 20, 44, 36), outline=(255, 255, 255, 255), width=3)
            d2.line((36, 26, 36, 32), fill=(255, 255, 255, 255), width=3)
            d2.rectangle((34, 38, 38, 42), fill=(255, 255, 255, 255))
        for _ in range(30):   # sparkle dust
            x, y = rnd.randrange(60, 250), rnd.randrange(12, 52)
            px[x, y] = (255, 255, 255, rnd.randrange(30, 90))
        save(img, f"{d}/{rel}.png")

    banner("gui_category_equipment", "equipment")
    banner("gui_category_salvage", "salvage")
    banner("gui_category_tactical", "tactical")
    banner("gui_category_information", "information")


# ---------------------------------------------------------------------------
# Warning sign — big 384x64-style board (keeps sl_warning_sign.png name/size)
# ---------------------------------------------------------------------------
def gen_signs() -> None:
    def board() -> tuple[Image.Image, ImageDraw.ImageDraw]:
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        d2 = ImageDraw.Draw(img)
        d2.rounded_rectangle((2, 2, 61, 61), radius=6,
                             fill=(24, 26, 32, 255),
                             outline=(210, 214, 224, 255), width=2)
        for bx, by in ((8, 8), (55, 8), (8, 55), (55, 55)):
            d2.ellipse((bx - 2, by - 2, bx + 2, by + 2),
                       fill=(140, 146, 160, 255))
        return img, d2

    # hazard triangle with exclamation
    img, d2 = board()
    d2.polygon([(32, 10), (56, 50), (8, 50)], outline=(255, 208, 56, 255), width=3)
    d2.polygon([(32, 18), (49, 46), (15, 46)], outline=(255, 208, 56, 160), width=1)
    d2.rectangle((30, 26, 34, 40), fill=(255, 208, 56, 255))
    d2.rectangle((30, 43, 34, 46), fill=(255, 208, 56, 255))
    save(img, "mods/game/sl_modebase/textures/sl_warning_sign.png", scale=6)


# ---------------------------------------------------------------------------
# Big art — achievement badges (256) + ladder rungs (96)
# ---------------------------------------------------------------------------
def _badge_font(size: int):
    from PIL import ImageFont
    try:
        return ImageFont.truetype("DejaVuSans-Bold.ttf", size)
    except Exception:
        return ImageFont.load_default()


def _badge_base(sz: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(img)
    d2.regular_polygon((sz * 0.5, sz * 0.5, sz * 0.47), n_sides=8, rotation=22.5,
                       fill=(16, 18, 24, 235),
                       outline=(235, 238, 246, 255), width=max(2, sz // 96))
    d2.regular_polygon((sz * 0.5, sz * 0.5, sz * 0.40), n_sides=8, rotation=22.5,
                       outline=(120, 126, 140, 255), width=1)
    return img, d2


def gen_badges() -> None:
    d = "mods/apis/sl_gui/textures"

    def badge(rel, draw_fn, sz=256):
        img, d2 = _badge_base(sz)
        draw_fn(d2, sz)
        # outer glow dust
        rnd = random.Random(hash(rel) & 0xFFFF)
        px = img.load()
        for _ in range(sz // 3):
            ang = rnd.uniform(0, 2 * math.pi)
            r = sz * 0.36 + rnd.uniform(0, sz * 0.06)
            x = int(sz / 2 + r * math.cos(ang))
            y = int(sz / 2 + r * math.sin(ang))
            if 0 <= x < sz and 0 <= y < sz and px[x, y][3] == 0:
                px[x, y] = (255, 255, 255, rnd.randrange(40, 120))
        save(img, f"{d}/{rel}.png")

    def rung(rel, label, ring_count, sz=96):
        img, d2 = _badge_base(sz)
        cx, cy = sz * 0.28, sz * 0.52
        for i in range(ring_count):
            r = sz * (0.20 - i * 0.055)
            d2.regular_polygon((cx, cy, r), 6, rotation=0,
                               outline=(255, 255, 255, 255), width=2)
        f = _badge_font(int(sz * 0.22))
        bb = d2.textbbox((0, 0), label, font=f)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        d2.text((sz * 0.60 - tw / 2, sz * 0.50 - th / 2 - bb[1]), label,
                fill=(255, 255, 255, 255), font=f)
        save(img, f"{d}/{rel}.png")

    def ghost(d2, sz):
        d2.regular_polygon((sz * .5, sz * .42, sz * .16), 8, rotation=0,
                           fill=(255, 255, 255, 255))
        d2.polygon([(sz * .38, sz * .48), (sz * .62, sz * .48),
                    (sz * .62, sz * .66), (sz * .56, sz * .61),
                    (sz * .5, sz * .68), (sz * .44, sz * .61),
                    (sz * .38, sz * .66)], fill=(255, 255, 255, 255))

    badge("achievement_first_ghost", ghost)
    badge("achievement_ghost_hunter", lambda d2, sz: (
        ghost(d2, sz),
        d2.line((sz * .62, sz * .36, sz * .74, sz * .24),
                fill=(255, 255, 255, 255), width=5),
        d2.line((sz * .74, sz * .24, sz * .78, sz * .30),
                fill=(255, 255, 255, 255), width=5),
    ))
    badge("achievement_ghost_veteran", lambda d2, sz: (
        ghost(d2, sz),
        d2.line((sz * .60, sz * .30, sz * .76, sz * .18),
                fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .76, sz * .30, sz * .60, sz * .18),
                fill=(255, 255, 255, 255), width=4),
    ))
    badge("achievement_first_craft", lambda d2, sz: (
        d2.regular_polygon((sz * .5, sz * .52, sz * .20), 4, rotation=45,
                           outline=(255, 255, 255, 255), width=5),
        d2.line((sz * .5, sz * .38, sz * .5, sz * .66),
                fill=(255, 255, 255, 255), width=3),
        d2.line((sz * .36, sz * .52, sz * .64, sz * .52),
                fill=(255, 255, 255, 255), width=3),
    ))
    badge("achievement_first_dig", lambda d2, sz: (
        d2.line((sz * .34, sz * .66, sz * .58, sz * .40),
                fill=(255, 255, 255, 255), width=5),
        d2.polygon([(sz * .56, sz * .26), (sz * .72, sz * .40),
                    (sz * .60, sz * .46), (sz * .52, sz * .36)],
                   fill=(255, 255, 255, 255)),
    ))
    badge("achievement_craft_10_items", lambda d2, sz: (
        d2.regular_polygon((sz * .5, sz * .56, sz * .18), 4, rotation=45,
                           outline=(255, 255, 255, 255), width=4),
        d2.text((sz * .30, sz * .16), "x10", font=_badge_font(int(sz * .2)),
                fill=(255, 255, 255, 255)),
    ))
    badge("achievement_craft_100_items", lambda d2, sz: (
        d2.regular_polygon((sz * .5, sz * .56, sz * .18), 4, rotation=45,
                           outline=(255, 255, 255, 255), width=4),
        d2.text((sz * .22, sz * .16), "x100", font=_badge_font(int(sz * .2)),
                fill=(255, 255, 255, 255)),
    ))
    badge("achievement_craft_glass", lambda d2, sz: (
        d2.rectangle((sz * .34, sz * .32, sz * .66, sz * .72),
                     outline=(255, 255, 255, 255), width=4),
        d2.line((sz * .40, sz * .64, sz * .56, sz * .42),
                fill=(255, 255, 255, 160), width=2),
    ))
    badge("achievement_craft_urban_item", lambda d2, sz: (
        d2.rectangle((sz * .28, sz * .44, sz * .48, sz * .70),
                     outline=(255, 255, 255, 255), width=4),
        d2.rectangle((sz * .50, sz * .34, sz * .72, sz * .70),
                     outline=(255, 255, 255, 255), width=4),
        d2.rectangle((sz * .55, sz * .40, sz * .67, sz * .50),
                     fill=(255, 255, 255, 200)),
    ))
    badge("achievement_dig_100_blocks", lambda d2, sz: (
        d2.rectangle((sz * .30, sz * .44, sz * .48, sz * .66),
                     outline=(255, 255, 255, 255), width=4),
        d2.rectangle((sz * .52, sz * .44, sz * .70, sz * .66),
                     outline=(255, 255, 255, 255), width=4),
        d2.line((sz * .34, sz * .36, sz * .66, sz * .36),
                fill=(255, 255, 255, 255), width=4),
    ))
    badge("achievement_dig_1000_blocks", lambda d2, sz: (
        d2.rectangle((sz * .30, sz * .48, sz * .48, sz * .70),
                     outline=(255, 255, 255, 255), width=4),
        d2.rectangle((sz * .52, sz * .48, sz * .70, sz * .70),
                     outline=(255, 255, 255, 255), width=4),
        d2.text((sz * .24, sz * .14), "1000",
                font=_badge_font(int(sz * .18)), fill=(255, 255, 255, 255)),
    ))
    badge("achievement_place_10_blocks", lambda d2, sz: (
        d2.rectangle((sz * .38, sz * .42, sz * .62, sz * .66),
                     outline=(255, 255, 255, 255), width=4),
        d2.line((sz * .50, sz * .18, sz * .50, sz * .36),
                fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .44, sz * .24, sz * .50, sz * .18),
                fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .56, sz * .24, sz * .50, sz * .18),
                fill=(255, 255, 255, 255), width=4),
    ))
    badge("achievement_place_1000_blocks", lambda d2, sz: (
        d2.rectangle((sz * .38, sz * .46, sz * .62, sz * .70),
                     outline=(255, 255, 255, 255), width=4),
        d2.text((sz * .24, sz * .14), "1000",
                font=_badge_font(int(sz * .18)), fill=(255, 255, 255, 255)),
    ))
    badge("achievement_travel_1000_blocks", lambda d2, sz: (
        d2.arc((sz * .24, sz * .30, sz * .76, sz * .74), 200, 340,
               fill=(255, 255, 255, 255), width=4),
        d2.polygon([(sz * .74, sz * .40), (sz * .62, sz * .44),
                    (sz * .72, sz * .52)], fill=(255, 255, 255, 255)),
        d2.ellipse((sz * .18, sz * .52, sz * .30, sz * .64),
                   outline=(255, 255, 255, 255), width=3),
    ))
    badge("achievement_visit_10_islands", lambda d2, sz: (
        d2.arc((sz * .22, sz * .56, sz * .78, sz * .90), 180, 360,
               fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .30, sz * .60, sz * .30, sz * .44),
                fill=(255, 255, 255, 255), width=3),
        d2.line((sz * .70, sz * .60, sz * .70, sz * .44),
                fill=(255, 255, 255, 255), width=3),
        d2.text((sz * .40, sz * .14), "10",
                font=_badge_font(int(sz * .24)), fill=(255, 255, 255, 255)),
    ))
    badge("achievement_visit_floating_island", lambda d2, sz: (
        d2.ellipse((sz * .30, sz * .40, sz * .70, sz * .58),
                   outline=(255, 255, 255, 255), width=4),
        d2.polygon([(sz * .38, sz * .56), (sz * .62, sz * .56),
                    (sz * .52, sz * .68), (sz * .46, sz * .66)],
                   fill=(255, 255, 255, 255)),
        d2.polygon([(sz * .46, sz * .34), (sz * .50, sz * .26),
                    (sz * .54, sz * .34)], fill=(255, 255, 255, 255)),
    ))
    badge("achievement_find_city", lambda d2, sz: (
        d2.rectangle((sz * .26, sz * .42, sz * .44, sz * .70),
                     outline=(255, 255, 255, 255), width=3),
        d2.rectangle((sz * .48, sz * .30, sz * .68, sz * .70),
                     outline=(255, 255, 255, 255), width=3),
        d2.rectangle((sz * .52, sz * .38, sz * .64, sz * .48),
                     fill=(255, 255, 255, 220)),
    ))
    badge("achievement_max_ability", lambda d2, sz: (
        d2.line((sz * .5, sz * .26, sz * .5, sz * .70),
                fill=(255, 255, 255, 255), width=5),
        d2.line((sz * .28, sz * .48, sz * .72, sz * .48),
                fill=(255, 255, 255, 255), width=5),
        d2.line((sz * .32, sz * .30, sz * .68, sz * .66),
                fill=(255, 255, 255, 150), width=2),
        d2.line((sz * .68, sz * .30, sz * .32, sz * .66),
                fill=(255, 255, 255, 150), width=2),
    ))
    badge("achievement_unlock_first_ability", lambda d2, sz: (
        d2.ellipse((sz * .28, sz * .28, sz * .72, sz * .72),
                   outline=(255, 255, 255, 255), width=3),
        d2.line((sz * .5, sz * .38, sz * .5, sz * .62),
                fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .38, sz * .5, sz * .62, sz * .5),
                fill=(255, 255, 255, 255), width=4),
    ))
    badge("achievement_unlock_5_abilities", lambda d2, sz: (
        d2.ellipse((sz * .28, sz * .28, sz * .72, sz * .72),
                   outline=(255, 255, 255, 255), width=3),
        d2.text((sz * .40, sz * .34), "5", font=_badge_font(int(sz * .34)),
                fill=(255, 255, 255, 255)),
    ))
    badge("achievement_unlock_all_movement", lambda d2, sz: (
        d2.ellipse((sz * .28, sz * .28, sz * .72, sz * .72),
                   outline=(255, 255, 255, 255), width=3),
        d2.line((sz * .50, sz * .36, sz * .50, sz * .64),
                fill=(255, 255, 255, 255), width=3),
        d2.polygon([(sz * .42, sz * .42), (sz * .50, sz * .34),
                    (sz * .58, sz * .42)], fill=(255, 255, 255, 255)),
        d2.polygon([(sz * .42, sz * .58), (sz * .50, sz * .66),
                    (sz * .58, sz * .58)], fill=(255, 255, 255, 255)),
    ))
    badge("achievement_secret_easter_egg", lambda d2, sz: (
        d2.ellipse((sz * .38, sz * .34, sz * .62, sz * .66),
                   outline=(255, 255, 255, 255), width=4),
        d2.arc((sz * .44, sz * .44, sz * .56, sz * .56), 30, 150,
               fill=(255, 255, 255, 255), width=2),
    ))
    badge("achievement_up_is_down", lambda d2, sz: (
        d2.line((sz * .50, sz * .68, sz * .50, sz * .34),
                fill=(255, 255, 255, 255), width=4),
        d2.polygon([(sz * .42, sz * .42), (sz * .50, sz * .32),
                    (sz * .58, sz * .42)], fill=(255, 255, 255, 255)),
        d2.line((sz * .30, sz * .74, sz * .70, sz * .74),
                fill=(255, 255, 255, 255), width=3),
    ))
    badge("achievement_easter_egg", lambda d2, sz: (
        d2.ellipse((sz * .36, sz * .30, sz * .64, sz * .70),
                   outline=(255, 255, 255, 255), width=4),
        d2.arc((sz * .44, sz * .42, sz * .56, sz * .56), 40, 140,
               fill=(255, 255, 255, 255), width=2),
    ))
    badge("achievement_loop_land", lambda d2, sz: (
        d2.arc((sz * .30, sz * .30, sz * .70, sz * .70), 300, 240,
               fill=(255, 255, 255, 255), width=4),
        d2.polygon([(sz * .66, sz * .36), (sz * .56, sz * .40),
                    (sz * .66, sz * .46)], fill=(255, 255, 255, 255)),
    ))
    badge("achievement_puppeteer", lambda d2, sz: (
        d2.line((sz * .36, sz * .28, sz * .64, sz * .28),
                fill=(255, 255, 255, 255), width=2),
        d2.line((sz * .36, sz * .28, sz * .36, sz * .40),
                fill=(255, 255, 255, 255), width=2),
        d2.line((sz * .64, sz * .28, sz * .64, sz * .40),
                fill=(255, 255, 255, 255), width=2),
        d2.line((sz * .50, sz * .28, sz * .50, sz * .38),
                fill=(255, 255, 255, 255), width=2),
        d2.ellipse((sz * .44, sz * .40, sz * .56, sz * .50),
                   fill=(255, 255, 255, 255)),
        d2.rectangle((sz * .42, sz * .52, sz * .58, sz * .68),
                     fill=(255, 255, 255, 255)),
    ))

    # secret depths: downward arrow sinking past depth lines
    badge("achievement_secret_find_depths", lambda d2, sz: (
        d2.line((sz * .50, sz * .26, sz * .50, sz * .56),
                fill=(255, 255, 255, 255), width=5),
        d2.polygon([(sz * .40, sz * .48), (sz * .50, sz * .60), (sz * .60, sz * .48)],
                   fill=(255, 255, 255, 255)),
        d2.line((sz * .30, sz * .68, sz * .70, sz * .68),
                fill=(255, 255, 255, 150), width=3),
        d2.line((sz * .36, sz * .75, sz * .64, sz * .75),
                fill=(255, 255, 255, 100), width=2),
    ))

    # --- ladder rungs -----------------------------------------------------
    rung("achievement_reach_level_5", "5", 1)
    rung("achievement_reach_level_10", "10", 2)
    rung("achievement_reach_level_25", "25", 2)
    rung("achievement_reach_level_50", "50", 3)
    rung("achievement_depth_1k", "1k", 1)
    rung("achievement_depth_5k", "5k", 2)
    rung("achievement_depth_10k", "10k", 2)
    rung("achievement_depth_20k", "20k", 3)
    rung("achievement_fall_100", "100", 1)
    rung("achievement_fall_1k", "1k", 2)
    rung("achievement_fall_10k", "10k", 3)


def gen_badge_legacy() -> None:
    """White-glow redraws of the large story badges (256) + combat/board art."""
    d = "mods/apis/sl_gui/textures"

    def badge(rel, draw_fn, sz=256):
        img, d2 = _badge_base(sz)
        draw_fn(d2, sz)
        rnd = random.Random(hash(rel) & 0xFFFF)
        px = img.load()
        for _ in range(sz // 3):
            ang = rnd.uniform(0, 2 * math.pi)
            r = sz * 0.36 + rnd.uniform(0, sz * 0.06)
            x = int(sz / 2 + r * math.cos(ang))
            y = int(sz / 2 + r * math.sin(ang))
            if 0 <= x < sz and 0 <= y < sz and px[x, y][3] == 0:
                px[x, y] = (255, 255, 255, rnd.randrange(40, 120))
        save(img, f"{d}/{rel}.png")

    # champion: trophy cup with "1"
    def trophy(d2, sz, label=None):
        d2.rectangle((sz * .40, sz * .26, sz * .60, sz * .30), fill=(255, 255, 255, 255))
        d2.polygon([(sz * .40, sz * .28), (sz * .60, sz * .28), (sz * .55, sz * .52),
                    (sz * .45, sz * .52)], outline=(255, 255, 255, 255), width=4)
        d2.arc((sz * .28, sz * .26, sz * .44, sz * .42), 90, 270,
               fill=(255, 255, 255, 255), width=4)
        d2.arc((sz * .56, sz * .26, sz * .72, sz * .42), 270, 90,
               fill=(255, 255, 255, 255), width=4)
        d2.line((sz * .50, sz * .52, sz * .50, sz * .62), fill=(255, 255, 255, 255), width=5)
        d2.rectangle((sz * .38, sz * .62, sz * .62, sz * .68), fill=(255, 255, 255, 255))
        if label:
            d2.text((sz * .43, sz * .32), label, font=_badge_font(int(sz * .16)),
                    fill=(255, 255, 255, 255))

    badge("achievement_champion", lambda d2, sz: trophy(d2, sz, "1"))
    badge("achievement_victory", lambda d2, sz: trophy(d2, sz, "1ST"))

    def survivor(d2, sz):
        d2.polygon([(sz * .5, sz * .22), (sz * .72, sz * .30), (sz * .72, sz * .52),
                    (sz * .5, sz * .76), (sz * .28, sz * .52), (sz * .28, sz * .30)],
                   outline=(255, 255, 255, 255), width=4)
        d2.ellipse((sz * .44, sz * .34, sz * .56, sz * .46), fill=(255, 255, 255, 255))
        d2.polygon([(sz * .42, sz * .48), (sz * .58, sz * .48), (sz * .55, sz * .62),
                    (sz * .45, sz * .62)], fill=(255, 255, 255, 255))

    badge("achievement_survivor", survivor)

    # abyss: diver silhouette under a grate
    badge("achievement_abyss", lambda d2, sz: (
        d2.line((sz * .28, sz * .26, sz * .72, sz * .26), fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .36, sz * .26, sz * .36, sz * .34), fill=(255, 255, 255, 200), width=3),
        d2.line((sz * .50, sz * .26, sz * .50, sz * .34), fill=(255, 255, 255, 200), width=3),
        d2.line((sz * .64, sz * .26, sz * .64, sz * .34), fill=(255, 255, 255, 200), width=3),
        d2.ellipse((sz * .44, sz * .42, sz * .56, sz * .54), fill=(255, 255, 255, 255)),
        d2.polygon([(sz * .40, sz * .54), (sz * .60, sz * .54), (sz * .54, sz * .68),
                    (sz * .46, sz * .68)], fill=(255, 255, 255, 255)),
        d2.arc((sz * .34, sz * .56, sz * .66, sz * .78), 20, 160,
               fill=(255, 255, 255, 160), width=2),
    ))
    badge("achievement_abyss_base", lambda d2, sz: (
        d2.arc((sz * .30, sz * .30, sz * .70, sz * .70), 200, 340,
               fill=(255, 255, 255, 255), width=4),
        d2.ellipse((sz * .46, sz * .58, sz * .54, sz * .66), fill=(255, 255, 255, 255)),
    ))
    badge("achievement_abyss_base2", lambda d2, sz: (
        d2.arc((sz * .30, sz * .30, sz * .70, sz * .70), 20, 160,
               fill=(255, 255, 255, 255), width=4),
        d2.ellipse((sz * .46, sz * .34, sz * .54, sz * .42), fill=(255, 255, 255, 255)),
    ))

    # combat: crossed blades + skull
    def crossed(d2, sz):
        d2.line((sz * .32, sz * .28, sz * .66, sz * .64), fill=(255, 255, 255, 255), width=6)
        d2.line((sz * .68, sz * .28, sz * .34, sz * .64), fill=(255, 255, 255, 255), width=6)
        d2.line((sz * .30, sz * .64, sz * .40, sz * .70), fill=(255, 255, 255, 255), width=5)
        d2.line((sz * .70, sz * .64, sz * .60, sz * .70), fill=(255, 255, 255, 255), width=5)
        d2.ellipse((sz * .44, sz * .34, sz * .58, sz * .46), fill=(20, 22, 28, 255),
                   outline=(255, 255, 255, 255), width=3)

    badge("achievement_combat", crossed)
    badge("achievement_combat2", crossed)

    # crafting: gear with core
    badge("achievement_crafting", lambda d2, sz: (
        [d2.arc((sz * .30, sz * .30, sz * .70, sz * .70),
                a, a + 40, fill=(255, 255, 255, 255), width=6)
         for a in range(0, 360, 60)],
        d2.ellipse((sz * .43, sz * .43, sz * .57, sz * .57),
                   outline=(255, 255, 255, 255), width=4),
    ))

    # exploration: compass needle in a ring
    badge("achievement_exploration", lambda d2, sz: (
        d2.ellipse((sz * .26, sz * .26, sz * .74, sz * .74),
                   outline=(255, 255, 255, 255), width=4),
        d2.polygon([(sz * .5, sz * .30), (sz * .56, sz * .5), (sz * .5, sz * .70),
                    (sz * .44, sz * .5)], fill=(255, 255, 255, 255)),
    ))
    badge("achievement_exploration_2", lambda d2, sz: (
        d2.ellipse((sz * .30, sz * .34, sz * .70, sz * .68),
                   outline=(255, 255, 255, 255), width=4),
        d2.line((sz * .34, sz * .40, sz * .66, sz * .62), fill=(255, 255, 255, 200), width=2),
    ))

    # leveling: star ascending
    badge("achievement_leveling", lambda d2, sz: (
        d2.polygon([(sz * .5, sz * .24), (sz * .56, sz * .44), (sz * .74, sz * .44),
                    (sz * .60, sz * .56), (sz * .66, sz * .76), (sz * .5, sz * .63),
                    (sz * .34, sz * .76), (sz * .40, sz * .56), (sz * .26, sz * .44),
                    (sz * .44, sz * .44)], outline=(255, 255, 255, 255), width=4),
    ))
    badge("achievement_leveling_2", lambda d2, sz: (
        d2.polygon([(sz * .5, sz * .22), (sz * .58, sz * .44), (sz * .78, sz * .44),
                    (sz * .62, sz * .58), (sz * .70, sz * .78), (sz * .5, sz * .64),
                    (sz * .30, sz * .78), (sz * .38, sz * .58), (sz * .22, sz * .44),
                    (sz * .42, sz * .44)], fill=(255, 255, 255, 255)),
    ))

    # fall base: falling stick figure
    badge("achievement_fall_base", lambda d2, sz: (
        d2.ellipse((sz * .46, sz * .30, sz * .56, sz * .40), fill=(255, 255, 255, 255)),
        d2.line((sz * .51, sz * .40, sz * .47, sz * .54), fill=(255, 255, 255, 255), width=5),
        d2.line((sz * .50, sz * .44, sz * .62, sz * .50), fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .50, sz * .44, sz * .39, sz * .49), fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .47, sz * .54, sz * .56, sz * .66), fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .47, sz * .54, sz * .38, sz * .64), fill=(255, 255, 255, 255), width=4),
        d2.line((sz * .30, sz * .26, sz * .36, sz * .32), fill=(255, 255, 255, 150), width=2),
        d2.line((sz * .64, sz * .30, sz * .69, sz * .36), fill=(255, 255, 255, 150), width=2),
    ))


# ---------------------------------------------------------------------------
# Menu icon — white "SL" monogram on dark rounded shield
# ---------------------------------------------------------------------------
def gen_menu() -> None:
    img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(img)
    d2.rounded_rectangle((6, 6, 121, 121), radius=22, fill=(12, 13, 18, 255))
    d2.rounded_rectangle((6, 6, 121, 121), radius=22,
                         outline=(235, 238, 246, 255), width=3)
    # S built from bars
    d2.rounded_rectangle((28, 30, 84, 42), radius=6, fill=(255, 255, 255, 255))
    d2.rounded_rectangle((28, 58, 72, 70), radius=6, fill=(255, 255, 255, 255))
    d2.rounded_rectangle((28, 86, 84, 98), radius=6, fill=(255, 255, 255, 255))
    d2.rectangle((28, 30, 40, 70), fill=(255, 255, 255, 255))
    d2.rectangle((72, 58, 84, 98), fill=(255, 255, 255, 255))
    # L
    d2.rectangle((96, 30, 106, 98), fill=(200, 205, 216, 255))
    d2.rectangle((96, 88, 114, 98), fill=(200, 205, 216, 255))
    save(img, "menu/icon.png")


# ---------------------------------------------------------------------------
def main() -> None:
    print("Generating white-with-glow pixel textures...")
    gen_modebase()
    gen_clouds()
    gen_workshops()
    gen_scary()
    gen_mvp()
    gen_dignodes()
    gen_hand()
    gen_gui()
    gen_signs()
    gen_badges()
    gen_badge_legacy()
    gen_menu()
    gen_construction()
    gen_mvp_models()
    gen_clothing()
    gen_boxman()
    gen_sun()
    gen_formspec()
    print("done.")


if __name__ == "__main__":
    main()
