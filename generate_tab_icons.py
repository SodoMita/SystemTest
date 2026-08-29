#!/usr/bin/env python3
"""Generate the inventory tab icons as flat one-colour vector art.

Pipeline, as requested: the shape is described as vector geometry, written out
as an SVG, and then that same geometry is rendered to a 32x32 PNG. The SVG and
the PNG cannot drift apart because both come from one polygon list.

Deliberately dependency-free (stdlib only) -- `create_ui_assets.py` needs PIL,
which is not installed on every machine that has to rebuild these assets.

Every icon is one flat colour on a fully transparent background: no gradient,
no glow, no blur pass. Edge softness comes only from supersampling the exact
vector outline, which is what "render at 32x32" means.

Usage:  python3 generate_tab_icons.py
"""

import math
import os
import struct
import zlib

SIZE = 32          # output PNG edge, in pixels
SUPERSAMPLE = 8    # samples per pixel edge; 8x8 = 64 coverage samples
ACCENT = (0xEA, 0x86, 0x38)   # #ea8638, the accent the other tab icons use
TEXTURES = os.path.join("mods", "apis", "sl_gui", "textures")
SVG_OUT = os.path.join("tools", "tab_icons")


# --------------------------------------------------------------------------
# vector geometry
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
    p = force_ccw(poly)
    return list(reversed(p))


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
    base_half = step * 0.30   # tooth half-width where it meets the body
    tip_half = step * 0.19    # tooth half-width at the tip
    arc_steps = 3             # subdivisions of the body arc between two teeth

    outline = []
    for t in range(teeth):
        a = t * step
        # rise from the body radius out to the tooth tip
        outline.append((cx + r_body * math.cos(a - base_half),
                        cy + r_body * math.sin(a - base_half)))
        outline.append((cx + r_outer * math.cos(a - tip_half),
                        cy + r_outer * math.sin(a - tip_half)))
        outline.append((cx + r_outer * math.cos(a + tip_half),
                        cy + r_outer * math.sin(a + tip_half)))
        outline.append((cx + r_body * math.cos(a + base_half),
                        cy + r_body * math.sin(a + base_half)))
        # body arc across to the next tooth
        for i in range(1, arc_steps + 1):
            aa = a + base_half + (step - 2 * base_half) * i / arc_steps
            outline.append((cx + r_body * math.cos(aa),
                            cy + r_body * math.sin(aa)))
    return [force_ccw(outline), force_cw(circle(cx, cy, r_hole, 48))]


def chat_bubble():
    """Speech bubble: rounded body plus a tail pointing down-left."""
    body = rounded_rect(3.0, 5.5, 29.0, 21.5, 4.0)
    # The tail shares its top edge with the body's bottom edge, so the union
    # stays a simple outline even under nonzero winding.
    tail = [(10.0, 21.5), (17.0, 21.5), (10.5, 28.0)]
    return [force_ccw(body), force_ccw(tail)]


ICONS = {
    "gui_tab_system": gear(16.0, 16.0, teeth=8, r_hole=5.0, r_body=10.0, r_outer=14.5),
    "gui_tab_comms": chat_bubble(),
}


# --------------------------------------------------------------------------
# rasteriser: nonzero winding, supersampled
# --------------------------------------------------------------------------

def winding_number(x, y, poly):
    """How many times poly winds around (x, y); nonzero means inside."""
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
    """Fraction of the pixel (x, y) covered by the union minus the holes."""
    hits = 0
    total = SUPERSAMPLE * SUPERSAMPLE
    sub = 1.0 / SUPERSAMPLE
    for sy in range(SUPERSAMPLE):
        py = y + (sy + 0.5) * sub
        for sx in range(SUPERSAMPLE):
            px = x + (sx + 0.5) * sub
            if any(winding_number(px, py, p) != 0 for p in polys):
                hits += 1
    return hits / total


def render(polys):
    """Return SIZE*SIZE RGBA bytes: one flat colour, alpha = coverage."""
    r, g, b = ACCENT
    out = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            a = int(round(coverage(x, y, polys) * 255))
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
# SVG output (same geometry, so the .svg and the .png always agree)
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
            '</svg>\n' % (SIZE, SIZE, SIZE, SIZE, name, d, hexcol))


# --------------------------------------------------------------------------
# 2x nearest-neighbour upscale for the pre-existing 16x16 pixel-art tabs, so
# the whole strip renders at one resolution. Nearest-neighbour doubles each
# pixel exactly: no resampling, no blur, no change to the artwork.
# --------------------------------------------------------------------------

def read_png_rgba(path):
    with open(path, "rb") as f:
        d = f.read()
    w, h, depth, ctype = struct.unpack(">IIBB", d[16:26])
    if depth != 8:
        raise SystemExit("%s: bit depth %d not supported" % (path, depth))
    pos, idat, plte = 8, b"", None
    while pos < len(d):
        ln = struct.unpack(">I", d[pos:pos + 4])[0]
        tag, data = d[pos + 4:pos + 8], d[pos + 8:pos + 8 + ln]
        if tag == b"IDAT":
            idat += data
        elif tag == b"PLTE":
            plte = data
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    rows, prev, i = [], bytearray(w * ch), 0
    for _ in range(h):
        ft = raw[i]
        i += 1
        line = bytearray(raw[i:i + w * ch])
        i += w * ch
        if ft == 1:
            for x in range(ch, len(line)):
                line[x] = (line[x] + line[x - ch]) & 255
        elif ft == 2:
            for x in range(len(line)):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(len(line)):
                a = line[x - ch] if x >= ch else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif ft == 4:
            for x in range(len(line)):
                a = line[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(bytes(line))
        prev = line
    px = b"".join(rows)
    out = bytearray()
    for i in range(0, len(px), ch):
        if ch == 4:
            out += px[i:i + 4]
        elif ch == 3:
            out += px[i:i + 3] + b"\xff"
        elif ch == 2:
            out += bytes((px[i], px[i], px[i], px[i + 1]))
        elif ctype == 3:
            o = px[i] * 3
            out += plte[o:o + 3] + b"\xff"
        else:
            v = px[i]
            out += bytes((v, v, v, 255))
    return w, h, bytes(out)


def upscale2x(path):
    w, h, px = read_png_rgba(path)
    out = bytearray()
    for y in range(h * 2):
        src_row = (y // 2) * w
        for x in range(w * 2):
            o = (src_row + x // 2) * 4
            out += px[o:o + 4]
    return w * 2, h * 2, bytes(out)


def main():
    os.makedirs(SVG_OUT, exist_ok=True)
    for name, polys in ICONS.items():
        write_svg(os.path.join(SVG_OUT, name + ".svg"), polys, name)
        write_png(os.path.join(TEXTURES, name + ".png"), render(polys), SIZE, SIZE)
        print("wrote %s.png + %s.svg" % (name, name))

    for name in ("gui_tab_crafting", "gui_tab_abilities", "gui_tab_achievements"):
        src = os.path.join(TEXTURES, name + ".png")
        w, h, px = read_png_rgba(src)
        if (w, h) == (SIZE, SIZE):
            print("%s already %dx%d, left alone" % (name, w, h))
            continue
        if (w, h) != (SIZE // 2, SIZE // 2):
            raise SystemExit("%s: expected %dx%d, got %dx%d"
                             % (name, SIZE // 2, SIZE // 2, w, h))
        nw, nh, npx = upscale2x(src)
        write_png(src, npx, nw, nh)
        print("upscaled %s %dx%d -> %dx%d (nearest neighbour)" % (name, w, h, nw, nh))


if __name__ == "__main__":
    main()
