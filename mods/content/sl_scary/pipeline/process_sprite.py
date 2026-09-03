#!/usr/bin/env python3
"""Post-process AI sticker-style art (near-white background) into game sprites.

Per source frame:
  1. PNG32 normalize
  2. key near-white background -> alpha (two passes: #F0F0F0 family, pure white)
  3. clean mask: 1px erosion (halo) + close (speckle), despill white fringe
  4. trim to content, scale figure height to fill 86% of the cell,
     centre horizontally, feet baseline at 92% cell height
  5. output the frame; stack frames vertically into the final sheet

Usage:
  python3 process_sprite.py CELL SHEET FRAME_REF [FRAME_0 FRAME_1 ...]
  e.g. python3 process_sprite.py 256 out/sl_scary_x_strip.png genwork/ref.png a.png b.png c.png
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from transpose_sprite_strip import read_png  # noqa: E402

WORK = os.environ.get("SPRITE_WORK", "/tmp/sl_sprite_work")
os.makedirs(WORK, exist_ok=True)


def im(args):
    subprocess.run(["convert"] + args, check=True)


def content_bbox(png):
    w, h, ct, _, _, rows = read_png(png)
    xs, ys = [], []
    for yy, r in enumerate(rows):
        for xx in range(0, w, 2):
            if r[xx * 4 + 3] > 40:
                xs.append(xx)
                ys.append(yy)
    return min(xs), min(ys), max(xs), max(ys)


def place(cell, src, out):
    w, h, ct, _, _, rows = read_png(src)
    th = int(cell * 0.86)
    scale = th / h
    nw = max(1, int(w * scale))
    nh = th
    im([src, "-filter", "Lanczos", "-resize", "%dx%d!" % (nw, nh),
        "+repage", "PNG32:" + src])
    x0 = (cell - nw) // 2
    y0 = int(cell * 0.92) - nh
    im(["-size", "%dx%d" % (cell, cell), "xc:none", src,
        "-geometry", "+%d+%d" % (x0, y0), "-composite", "PNG32:" + out])


def key_and_clean(src, dst):
    cur = os.path.join(WORK, "cur.png")
    im([src, "-depth", "8", "PNG32:" + cur])
    im([cur, "-fuzz", "10%", "-transparent", "#F0F0F0", "PNG32:" + cur])
    im([cur, "-fuzz", "5%", "-transparent", "white", "PNG32:" + cur])
    # clean mask: erode 1px (AA halo), close (speckle), re-copy as alpha
    im([cur, "(", "+clone", "-alpha", "extract",
        "-morphology", "Erode", "Disk:1",
        "-morphology", "Close", "Disk:1",
        ")", "-alpha", "off", "-compose", "CopyOpacity", "-composite",
        "PNG32:" + cur])
    # trim to content bbox
    im([cur, "-trim", "+repage", "PNG32:" + cur])
    # remove any white fringe pixels still semi-opaque on the rim
    im([cur, "-fuzz", "12%", "-transparent", "#F8F8F8", "PNG32:" + cur])
    x0, y0, x1, y1 = content_bbox(cur)
    w = x1 - x0 + 1
    h = y1 - y0 + 1
    if w < 4 or h < 4:
        print("WARN: tiny/empty content in", src, (w, h))
    im([cur, "-filter", "Lanczos", "-resize", "%dx%d!" % (w, h),
        "+repage", "PNG32:" + cur])
    im([cur, "PNG32:" + dst])


def main():
    cell = int(sys.argv[1])
    sheet = sys.argv[2]
    ref = sys.argv[3]
    srcs = sys.argv[4:]
    frames = []
    for i, s in enumerate(srcs):
        f = os.path.join(WORK, "f%d.png" % i)
        key_and_clean(s, f)
        tmp = os.path.join(WORK, "placed%d.png" % i)
        place(cell, f, tmp)
        frames.append(tmp)
    im(frames + ["-background", "none", "-append", "+repage", "PNG32:" + sheet])
    if ref and os.path.exists(frames[-1]):
        im([frames[-1], "PNG32:" + ref])
    print("wrote", sheet, "from", len(srcs), "frames; ref->", ref)


if __name__ == "__main__":
    main()
