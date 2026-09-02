#!/usr/bin/env python3
"""Generate the System / Comms inventory tab icons.

The request was to match the game's existing 16x16 one-bit pixel-art tab icons:
low resolution, hard edges, a single flat colour on a transparent background,
no blur and no antialiasing. So this renders each icon as a 16x16 PNG whose
alpha channel is strictly 0 or 255 (area thresholding of the exact vector
outline; nothing is blended).

The shape is still described as vector geometry and is also written out as an
SVG master (32-unit design space), but the PNG that ships is deliberately a
crisp 16x16 raster so it sits next to gui_tab_crafting/abilities/achievements
(which are the original 16x16 pixel art).

Deliberately dependency-free (stdlib only) -- create_ui_assets.py needs PIL,
which is not installed on every machine that has to rebuild these assets.

Usage:  python3 generate_tab_icons.py
"""

import math
import os
import struct
import zlib

SIZE = 16          # output PNG edge, in pixels (matches the other tab icons)
DESIGN = 32.0      # the vector master's coordinate space
SCALE = DESIGN / SIZE
SUPERSAMPLE = 8    # coverage samples per pixel edge; output is still 1-bit
ACCENT = (0xEA, 0x86, 0x38)   # #ea8638, the accent the other tab icons use
TEXTURES = os.path.join("mods", "apis", "sl_gui", "textures")
SVG_OUT = os.path.join("tools", "tab_icons")


# --------------------------------------------------------------------------
# vector geometry (in the 32-unit design space)
# --------------------------------------------------------------------------

def circle(cx, cy, r, steps=64):
    return [(cx + r * math.cos(2 * math.pi * i / steps),
             cy + r * math.sin(2 * math.pi * i / steps)) for i in range(steps)]


def force_ccw(poly):
    """Return the polygon wound counter-clockwise (positive signed area)."""
    area2 = sum(poly[i][0] * poly[(i + 1) % len(poly)][1]
                - poly[(i + 1) % len(poly)][0] * poly[i][1]
                for i in range(len(poly)))
    return poly if area2 > 0 else list(reversed(poly))


def force_cw(poly):
    return list(reversed(force_ccw(poly)))


def rounded_rect(x0, y0, x1, y1, r, steps=8):
    """Rounded rectangle as one closed polygon."""
    pts = []
    corners = [(x1 - r, y0 + r, -math.pi / 2, 0),
               (x1 - r, y1 - r, 0, math.pi / 2),
               (x0 + r, y1 - r, math.pi / 2, math.pi),
               (x0 + r, y0 + r, math.pi, 3 * math.pi / 2)]
    for cx, cy, a0, a1 in corners:
        for i in range(steps + 1):
            a = a0 + (a1 - a0) * i / steps
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def gear(cx, cy, teeth, r_hole, r_body, r_outer):
    """Gear silhouette (outer contour) plus its centre hole."""
    step = 2 * math.pi / teeth
    base_half = step * 0.34
    tip_half = step * 0.22
    arc_steps = 2

    outline = []
    for t in range(teeth):
        a = t * step
        outline.append((cx + r_body * math.cos(a - base_half),
                        cy + r_body * math.sin(a - base_half)))
        outline.append((cx + r_outer * math.cos(a - tip_half),
                        cy + r_outer * math.sin(a - tip_half)))
        outline.append((cx + r_outer * math.cos(a + tip_half),
                        cy + r_outer * math.sin(a + tip_half)))
        outline.append((cx + r_body * math.cos(a + base_half),
                        cy + r_body * math.sin(a + base_half)))
        for i in range(1, arc_steps + 1):
            aa = a + base_half + (step - 2 * base_half) * i / arc_steps
            outline.append((cx + r_body * math.cos(aa),
                            cy + r_body * math.sin(aa)))
    return [force_ccw(outline), force_cw(circle(cx, cy, r_hole, 32))]


def chat_bubble():
    """Speech bubble: rounded body plus a tail pointing down-left."""
    body = rounded_rect(2.0, 4.0, 30.0, 22.0, 5.0)
    tail = [(9.0, 22.0), (18.0, 22.0), (10.0, 30.0)]
    return [force_ccw(body), force_ccw(tail)]


def person(cx, cy_head, r_head, y_body, w_body, body_bottom):
    """One blocky roster figure: a round head over a shoulder/body bar."""
    # Head disc; the body bar overlaps it by a couple of units so the two
    # shapes read as one silhouette.
    head = circle(cx, cy_head, r_head, 48)
    # Rounded body bar, centered on cx, from y_body down to body_bottom.
    half = w_body / 2.0
    body = rounded_rect(cx - half, y_body, cx + half, body_bottom,
                        min(3.0, w_body * 0.18))
    return [force_ccw(head), force_ccw(body)]


def people():
    """Player roster: a larger operator in front and a smaller one behind."""
    polys = []
    # Rear (smaller, up-right) figure first; the front figure paints over it.
    polys += person(22.0, 8.5, 4.2, 11.0, 11.0, 28.0)
    # Front (larger, down-left) figure.
    polys += person(12.0, 12.5, 5.5, 16.0, 14.0, 29.5)
    return polys


ICONS = {
    "gui_tab_system": gear(16.0, 16.0, teeth=8, r_hole=4.5, r_body=10.0, r_outer=15.0),
    "gui_tab_comms": chat_bubble(),
    "gui_tab_players": people(),
}


# --------------------------------------------------------------------------
# rasteriser: nonzero winding, 1-bit output (no antialiasing)
# --------------------------------------------------------------------------

def winding_number(x, y, poly):
    w = 0
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        if y0 <= y:
            if y1 > y and (x1 - x0) * (y - y0) - (x - x0) * (y1 - y0) > 0:
                w += 1
        else:
            if y1 <= y and (x1 - x0) * (y - y0) - (x - x0) * (y1 - y0) < 0:
                w -= 1
    return w


def coverage(x, y, polys):
    """Fraction of the output pixel covered, in design coordinates."""
    hits = 0
    total = SUPERSAMPLE * SUPERSAMPLE
    sub = SCALE / SUPERSAMPLE
    for sy in range(SUPERSAMPLE):
        py = y * SCALE + (sy + 0.5) * sub
        for sx in range(SUPERSAMPLE):
            px = x * SCALE + (sx + 0.5) * sub
            # Nonzero winding over ALL subpaths: the body adds +1 and the
            # centre hole (wound the other way) subtracts it back to 0.
            if sum(winding_number(px, py, p) for p in polys) != 0:
                hits += 1
    return hits / total


def render(polys):
    """SIZE*SIZE RGBA bytes: flat colour, alpha strictly 0 or 255 (no AA)."""
    r, g, b = ACCENT
    out = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            a = 255 if coverage(x, y, polys) >= 0.5 else 0
            out += bytes((r, g, b, a))
    return bytes(out)


def write_png(path, rgba, w, h):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


# --------------------------------------------------------------------------
# SVG master (same geometry; the 32-unit vector the 16x16 raster is cut from)
# --------------------------------------------------------------------------

def write_svg(path, polys, name):
    def subpath(poly):
        d = "M %.3f %.3f " % poly[0]
        d += " ".join("L %.3f %.3f" % p for p in poly[1:])
        return d + " Z"

    d = " ".join(subpath(p) for p in polys)
    hexcol = "#%02x%02x%02x" % ACCENT
    with open(path, "w") as f:
        f.write(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
            'viewBox="0 0 %d %d">\n'
            '  <title>%s</title>\n'
            '  <path d="%s" fill="%s" fill-rule="nonzero"/>\n'
            '</svg>\n' % (int(DESIGN), int(DESIGN), int(DESIGN), int(DESIGN),
                          name, d, hexcol))


def main():
    os.makedirs(SVG_OUT, exist_ok=True)
    for name, polys in ICONS.items():
        write_svg(os.path.join(SVG_OUT, name + ".svg"), polys, name)
        write_png(os.path.join(TEXTURES, name + ".png"), render(polys), SIZE, SIZE)
        print("wrote %s.png (%dx%d, 1-bit) + %s.svg" % (name, SIZE, SIZE, name))


if __name__ == "__main__":
    main()
