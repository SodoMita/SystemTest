#!/usr/bin/env python3
"""Vector-neon stone & ore pass: AI vector-style sheet -> autotrace (SVG) ->
render SVG at exactly 16x16 (flat shapes, no downscale blur).

Steps:
  1. `python3 tools/neon_vector_pass.py prompts` shows the two sheet prompts.
  2. Generate `neon_sheets/S01_stone_vector.png` (4x4 tiles) and
     `neon_sheets/S02_ores_vector.png` (3x3 specks on black).
  3. `python3 tools/neon_vector_pass.py trace` splits each cell, traces it to
     SVG with vtracer (color, stacked splines) and rasterizes the SVG to a
     16x16 PNG with PyMuPDF. Ore cells are alpha-keyed (black -> transparent)
     so they composite over `default_stone.png` at runtime.
"""

import io
import os
import sys

import vtracer
from PIL import ImageFilter
import pymupdf
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEXDIR = os.path.join(ROOT, "mods", "default", "textures")
SHEETS = os.path.join(ROOT, "neon_sheets")

# file -> (sheet, cols, rows, cell-index, opaque?)
TILES = [
    ("default_stone.png",             0), ("default_cobble.png",          1),
    ("default_mossycobble.png",       2), ("default_stone_brick.png",    3),
    ("default_stone_block.png",       4), ("default_gravel.png",         5),
    ("default_desert_stone.png",      6), ("default_desert_cobble.png",  7),
    ("default_desert_stone_block.png", 8), ("default_desert_stone_brick.png", 9),
    ("default_obsidian.png",         10), ("default_obsidian_block.png", 11),
    ("default_obsidian_brick.png",   12), ("default_moss.png",           13),
    ("default_ice.png",              14), ("default_cloud.png",          15),
]
ORES = [
    ("default_mineral_coal.png",    0), ("default_mineral_iron.png",    1),
    ("default_mineral_copper.png",  2), ("default_mineral_tin.png",     3),
    ("default_mineral_gold.png",    4), ("default_mineral_diamond.png", 5),
    ("default_mineral_mese.png",    6),
]


def load(sheet):
    im = Image.open(os.path.join(SHEETS, sheet)).convert("RGB")
    if im.size != (1024, 1024):
        print("note: stretching %s %s -> 1024x1024" % (sheet, im.size))
        im = im.resize((1024, 1024), Image.LANCZOS)
    return im


def cell(im, cols, rows, idx, inset=0):
    cw, ch = im.width / cols, im.height / rows
    x0, y0 = int(idx % cols * cw), int(idx // cols * ch)
    return im.crop((x0 + inset, y0 + inset, x0 + cw - inset, y0 + ch - inset))


def auto_contrast(pil):
    """Stretch so faint neon lines survive: p1 -> 0, p99 -> 255 (per luminance)."""
    g = pil.convert("L")
    h = g.histogram()
    total = sum(h)
    lo = hi = 0
    acc = 0
    for i, c in enumerate(h):
        acc += c
        if acc >= total * 0.01:
            lo = i
            break
    acc = 0
    for i in range(255, -1, -1):
        acc += h[i]
        if acc >= total * 0.01:
            hi = i
            break
    if hi - lo < 24:
        return pil
    k = 255.0 / (hi - lo)
    return pil.point(lambda v: max(0, min(255, int((v - lo) * k))))


def neon_flatten_source(pil):
    """Make thin neon lines survive the 16x16 render:
    - bright-line cells: dilate the neon mask to ~1.2 output px and paint it in
      the cell's dominant neon hue;
    - bright-dense cells (gravel-like): dilate the DARK seam mask instead.
    Background is a flat 6-color quantization. Feeds a clean SVG."""
    stretched = auto_contrast(pil)
    lum = stretched.convert("L")
    px = stretched.load()
    lp = lum.load()
    W, H = pil.size
    vals = sorted(lum.getdata())
    frac_bright = sum(1 for v in vals if v > 150) / float(len(vals))
    oval = sorted(pil.convert("L").getdata())
    p5, p50 = oval[int(len(oval) * 0.05)], oval[int(len(oval) * 0.5)]
    if p5 > 90 and not frac_bright > 0.40:              # low-contrast bright cell
        olum = pil.convert("L")                         # (pale pebbles, faint seams)
        mask = olum.point(lambda v: 255 if v < max(60, p50) else 0)
        mask = mask.filter(ImageFilter.MaxFilter(9))
        line_color = (12, 10, 9)
    elif frac_bright > 0.40:                            # busy bright cell
        olum = pil.convert("L")
        oval = sorted(olum.getdata())
        t = oval[int(len(oval) * 0.35)]                 # darker third = seams
        mask = olum.point(lambda v: 255 if v < max(40, t) else 0)
        mask = mask.filter(ImageFilter.MaxFilter(11))
        line_color = (12, 10, 9)
    else:
        mask = lum.point(lambda v: 255 if v > 150 else 0)
        t = int(vals[int(len(vals) * 0.995)])
        th = min(170, max(140, t - 20))                 # keep faint lines in
        mask = mask.point(lambda v: 255 if v > th else 0)
        mask = mask.filter(ImageFilter.MaxFilter(19))
        # dominant neon hue of the bright pixels, saturated
        rs = gs = bs = n = 0.0
        for y in range(H):
            for x in range(W):
                if lp[x, y] > 150:
                    r, g, b = px[x, y]
                    m = float(max(r, g, b))
                    rs += r / m; gs += g / m; bs += b / m; n += 1
        cm = max(rs, gs, bs) or 1.0
        line_color = (min(255, int(255 * rs / cm)), min(255, int(255 * gs / cm)),
                      min(255, int(255 * bs / cm)))
    mp = mask.load()
    if p5 > 90 and line_color == (12, 10, 9) and not frac_bright > 0.40:
        k = 100                                         # pebble fills stay visible
    else:
        k = 45                                          # near-black flat fills
    base = pil.quantize(6, method=Image.MEDIANCUT).convert("RGB").point(
        lambda v: v * k // 100)
    bp = base.load()
    for y in range(H):
        for x in range(W):
            if mp[x, y]:
                bp[x, y] = line_color
    return base, line_color


def trace_to_svg(pil, path_precision=1):
    tmp = path_of(".tmp_cell.png")
    out = path_of(".tmp_cell.svg")
    pil, _line = neon_flatten_source(pil)
    pil.save(tmp)
    vtracer.convert_image_to_svg_py(
        tmp, out, colormode="color", hierarchical="stacked", mode="spline",
        corner_threshold=60, length_threshold=4.0, max_iterations=10,
        splice_threshold=45, filter_speckle=10, color_precision=5,
        layer_difference=24, path_precision=path_precision)
    svg = open(out).read()
    os.remove(tmp)
    os.remove(out)
    return svg


def path_of(name):
    return os.path.join(SHEETS, name)


def render_svg(svg, size=16):
    doc = pymupdf.open(stream=svg.encode(), filetype="svg")
    pix = doc[0].get_pixmap(matrix=pymupdf.Matrix(size / 1024, size / 1024),
                            alpha=False)
    return Image.frombytes("RGB", (pix.width, pix.height), pix.samples)


def key_alpha(im, lo=14, hi=90):
    px = im.load()
    out = Image.new("RGBA", im.size)
    op = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = px[x, y]
            k = (max(r, g, b) - lo) / float(hi - lo)
            k = 0.0 if k < 0 else 1.0 if k > 1 else k
            op[x, y] = (r, g, b, int(round(255 * k)))
    return out


def flatten(im, n):
    """Snap every pixel to the n most frequent colors -> hard flat edges."""
    counts = {}
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            counts[c] = counts.get(c, 0) + 1
    pal = sorted(counts, key=counts.get, reverse=True)[:n]
    out = im.copy()
    op = out.load()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            op[x, y] = min(pal, key=lambda p: (p[0]-c[0])**2 + (p[1]-c[1])**2 + (p[2]-c[2])**2)
    return out


def flatten_hybrid(im, n=5):
    """Palette = top-3 by frequency (the dark fills) + top-2 brightness-weighted
    (the neon lines), then nearest-color mapping -> flat regions, hard edges."""
    counts = {}
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            counts[c] = counts.get(c, 0) + 1
    by_freq = sorted(counts, key=counts.get, reverse=True)
    pal = by_freq[:3]
    rest = [c for c in by_freq[3:] if c not in pal]
    pal += sorted(rest, key=lambda c: counts[c] * (max(c) / 255.0), reverse=True)[:n - len(pal)]
    out = im.copy()
    op = out.load()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            op[x, y] = min(pal, key=lambda p: (p[0]-c[0])**2 + (p[1]-c[1])**2 + (p[2]-c[2])**2)
    return out


def flatten_bright(im, n):
    """Like flatten but palette candidates are weighted by brightness so small
    bright specks survive next to a large black background."""
    counts = {}
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            counts[c] = counts.get(c, 0) + 1
    pal = sorted(counts, key=lambda c: counts[c] * (0.2 + max(c) / 255.0), reverse=True)[:n]
    out = im.copy()
    op = out.load()
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            op[x, y] = min(pal, key=lambda p: (p[0]-c[0])**2 + (p[1]-c[1])**2 + (p[2]-c[2])**2)
    return out


def fallback_gravel():
    """Pebble tile drawn directly (source cell was too low-contrast to trace)."""
    import random
    rng = random.Random(0x6A)
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    op = im.load()
    base = [(11, 13, 18), (15, 18, 24)]
    for y in range(16):
        for x in range(16):
            op[x, y] = base[(x // 2 + y // 2) % 2] + (255,)
    B, D = (159, 216, 255), (62, 88, 112)
    spots = [(1, 1), (6, 0), (11, 2), (3, 5), (8, 6), (13, 6), (0, 10), (5, 11), (10, 10), (13, 13)]
    for i, (x0, y0) in enumerate(spots):
        w, h = (3, 2) if i % 3 else (4, 3)
        for dx in range(w):
            op[min(15, x0 + dx), y0] = B + (255,)
            op[min(15, x0 + dx), min(15, y0 + h - 1)] = B + (255,)
        for dy in range(h):
            op[x0, min(15, y0 + dy)] = B + (255,)
            op[min(15, x0 + w - 1), min(15, y0 + dy)] = B + (255,)
        if w > 3 and h > 2:
            op[x0 + 1, y0 + 1] = D + (255,)
    return im


def neon_recolor(rendered, line_color):
    """Deterministic 3-level recolor by brightness: full-bright neon line /
    dim halo (line hue at ~37%) / near-black fill. No palette guessing."""
    dim = tuple(v * 95 // 255 for v in line_color)
    lum = rendered.convert("L")
    px, lp = rendered.load(), lum.load()
    for y in range(rendered.height):
        for x in range(rendered.width):
            v = lp[x, y]
            if v > 100:
                px[x, y] = line_color
            elif v > 50:
                px[x, y] = dim
            else:
                px[x, y] = (12, 10, 9)
    return rendered


def trace():
    s01 = load("S01_stone_vector.png")
    s02 = load("S02_ores_vector.png")
    for name, idx in TILES:
        if name == "default_gravel.png":
            fallback_gravel().save(os.path.join(TEXDIR, name), optimize=True)
            print("traced %-38s (procedural fallback)" % name)
            continue
        pil = cell(s01, 4, 4, idx)
        pil = pil.resize((1024, 1024), Image.LANCZOS)   # normalize viewBox
        flat, line = neon_flatten_source(pil)
        svg = trace_to_svg(pil)
        out = neon_recolor(render_svg(svg, 16), line)
        out.save(os.path.join(TEXDIR, name), optimize=True)
        print("traced %-38s line=%s" % (name, line))
    for name, idx in ORES:
        pil = cell(s02, 3, 3, idx, inset=24)
        pil = pil.resize((1024, 1024), Image.LANCZOS)
        svg = trace_to_svg(pil)
        out = flatten_bright(render_svg(svg, 16), 3)
        key_alpha(out).save(os.path.join(TEXDIR, name), optimize=True)
        a = key_alpha(out).getchannel("A").tobytes()
        print("traced %-38s colors=%d coverage=%d%%" %
              (name, len(set(out.getdata())), 100 * sum(1 for v in a if v > 8) // 256))


if __name__ == "__main__":
    trace()
