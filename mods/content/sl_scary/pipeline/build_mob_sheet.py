#!/usr/bin/env python3
"""Build the 9-frame vertical mob sheets from AI panel art.

Each mob sheet is 9 rows of 256x256 cells (256x2304 total):
  row 0 FRONT, 1 BACK, 2 SIDE, 3-5 WALK x3, 6-7 ATTACK x2, 8 DEATH.

Sources are the AI sticker renders (plain near-white background), some
containing N poses in one image ("panels" argument per frame, separated
by near-white columns).  Each panel is white-keyed, halo-cleaned,
trimmed, normalised into a 256px cell (same height/centre) and the cells
are stacked vertically in row order.

Usage:
  build_mob_sheet.py OUT_SHEET [preview_cell.png]
      --frame FRONT.png:1 BACK.png:1 SIDE.png:1 W1.png:3 W2.png:1 ...
  The ":N" suffix says how many equal panels to slice from that source
  (1 = whole image).  Panel count per mob row group must total:
  front 1, back 1, side 1, walk 3, attack 2, death 1.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from transpose_sprite_strip import read_png, write_png  # noqa: E402

CELL = 256
WORK = os.environ.get("SPRITE_WORK", "/tmp/sl_sprite_work")
os.makedirs(WORK, exist_ok=True)


def im(args):
    subprocess.run(["convert"] + args, check=True)


def key_white(src, dst):
    im([src, "-depth", "8", "PNG32:" + dst])
    im([dst, "-fuzz", "10%", "-transparent", "#F0F0F0", "PNG32:" + dst])
    im([dst, "-fuzz", "5%", "-transparent", "white", "PNG32:" + dst])
    im([dst, "(", "+clone", "-alpha", "extract",
        "-morphology", "Erode", "Disk:1",
        "-morphology", "Close", "Disk:1",
        ")", "-alpha", "off", "-compose", "CopyOpacity", "-composite",
        "PNG32:" + dst])
    im([dst, "-fuzz", "12%", "-transparent", "#F8F8F8", "PNG32:" + dst])


def nearwhite(r, g, b):
    return r > 232 and g > 232 and b > 232


def split_panels(src, n):
    """Slice src into n panels along near-white vertical separators."""
    p = os.path.join(WORK, "pan.png")
    im([src, "-depth", "8", "PNG32:" + p])
    w, h, ct, _, _, rows = read_png(p)
    # column purity: fraction of near-white pixels (ignore transparent)
    col = []
    for x in range(w):
        hit = tot = 0
        for y in range(0, h, 2):
            q = rows[y][x * 4:x * 4 + 4]
            if q[3] > 200:
                tot += 1
                if nearwhite(q[0], q[1], q[2]):
                    hit += 1
        col.append(hit / max(1, tot))
    # candidate separators: runs of width>=6 where purity>0.97
    seps = []
    i = 0
    while i < w:
        if col[i] > 0.97:
            j = i
            while j < w and col[j] > 0.97:
                j += 1
            if j - i >= 6:
                seps.append((i + j) // 2)
            i = j
        else:
            i += 1
    if len(seps) >= n - 1:
        # cluster separators that belong to the same gap (within ~w/6n of
        # the nearest cluster centre), then choose the n-1 gap centres
        # closest to the expected equal-width boundaries
        seps = sorted(seps)
        clusters = []
        for s in seps:
            if clusters and s - clusters[-1][-1] < max(6, w // (6 * n)):
                clusters[-1].append(s)
            else:
                clusters.append([s])
        gaps = [sum(c) / len(c) for c in clusters]
        chosen = []
        for k in range(1, n):
            target = w * k // n
            chosen.append(min(gaps, key=lambda s: abs(s - target)))
        bounds = [0] + sorted(chosen) + [w]
    else:  # fallback: equal thirds
        bounds = [w * k // n for k in range(n + 1)]
    outs = []
    for k in range(n):
        x0 = bounds[k]
        x1 = bounds[k + 1]
        o = os.path.join(WORK, "panel%d.png" % k)
        im([p, "-crop", "%dx%d+%d+0" % (x1 - x0, h, x0), "+repage", "PNG32:" + o])
        outs.append(o)
    return outs


def place_cell(panel, dst):
    cur = os.path.join(WORK, "cell.png")
    key_white(panel, cur)
    im([cur, "-trim", "+repage", "PNG32:" + cur])
    w, h, ct, _, _, rows = read_png(cur)
    xs, ys = [], []
    for yy, r in enumerate(rows):
        for xx in range(0, w, 2):
            if r[xx * 4 + 3] > 40:
                xs.append(xx)
                ys.append(yy)
    if not xs or not ys:
        print("WARN empty panel", panel)
        im(["-size", "%dx%d" % (CELL, CELL), "xc:none", "PNG32:" + dst])
        return
    cw = max(xs) - min(xs) + 1
    ch = max(ys) - min(ys) + 1
    th = int(CELL * 0.86)
    scale = th / ch
    nw = max(1, int(cw * scale))
    nh = th
    im([cur, "-filter", "Lanczos", "-resize", "%dx%d!" % (nw, nh),
        "+repage", "PNG32:" + cur])
    x0 = (CELL - nw) // 2
    y0 = int(CELL * 0.92) - nh
    im(["-size", "%dx%d" % (CELL, CELL), "xc:none", cur,
        "-geometry", "+%d+%d" % (x0, y0), "-composite", "PNG32:" + dst])


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    sheet = args[0]
    preview = args[1] if args[1].endswith(".png") else None
    frames = []
    # positional frame specs in row order 0..8
    specs = []
    for a in args[2:]:
        m = re.match(r"^(.*):(\d+)$", a)
        specs.append((m.group(1), int(m.group(2))) if m else (a, 1))
    if sum(n for _, n in specs) != 9:
        print("need 9 total frames (front1, back+side2, walk3, attack2, death1); got", sum(n for _, n in specs))
        sys.exit(1)
    cell_paths = []
    for si, (src, n) in enumerate(specs):
        panels = split_panels(src, n) if n > 1 else [src]
        if len(panels) != n:
            print("WARN: %s sliced into %d panels, expected %d" % (src, len(panels), n))
        for pi, panel in enumerate(panels):
            cell = os.path.join(WORK, "cell%d_%d.png" % (si, pi))
            place_cell(panel, cell)
            cell_paths.append(cell)
    # stack
    im(cell_paths + ["-background", "none", "-append", "+repage", "PNG32:" + sheet])
    if preview:
        im([cell_paths[0], "PNG32:" + preview])
    # size guard (1MB/asset)
    sz = os.path.getsize(sheet)
    print("wrote", sheet, "(%dx%d, %d bytes)" % (CELL, CELL * 9, sz))
    if sz > 1_000_000:
        print("WARN: over 1MB")


if __name__ == "__main__":
    main()
