#!/usr/bin/env python3
"""Build dedicated 3-frame WALK rows for the mob sprite sheets.

Owner (2026-09-03): the mob walk animations were bad. Each ground mob
gets its own 1x3 strip of three FRONT-facing stride frames (Doom-style,
advancing toward camera), rendered realistic without neon on a black
grid + white twin, then triangulated + neonized exactly like
matte_sheet.py. The three cells become rows 3-5 of the existing 9-row
sheet (idle/attack/death rows are untouched).

Usage:
  python3 walk_sheet.py BLACK_STRIP WHITE_STRIP WALK3_OUT MOB
      -> WALK3_OUT: 256x768 (3 rows of 256x256)
  python3 walk_sheet.py --splice SHEET9 WALK3 SHEET9_OUT
      -> replaces rows 3-5 of SHEET9 (256x2304) with WALK3
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matte_sheet as M  # noqa: E402
from transpose_sprite_strip import read_png, write_png  # noqa: E402


def _black_prof(rows, w, h, axis, step=2, black_max=25):
    prof = []
    if axis == "x":
        for x in range(w):
            hit = n = 0
            for y in range(0, h, step):
                q = rows[y][x * 4:x * 4 + 3]
                n += 1
                if max(q) < black_max:
                    hit += 1
            prof.append(hit / n)
    else:
        for y in range(h):
            hit = n = 0
            for x in range(0, w, step):
                q = rows[y][x * 4:x * 4 + 3]
                n += 1
                if max(q) < black_max:
                    hit += 1
            prof.append(hit / n)
    return prof


def _runs(prof, thr=0.98, minrun=3):
    out = []
    i = 0
    n = len(prof)
    while i < n:
        if prof[i] >= thr:
            j = i
            while j < n and prof[j] >= thr:
                j += 1
            if j - i >= minrun:
                out.append((i, j))
            i = j
        else:
            i += 1
    return out


def bounds_1x3(rows, w, h):
    """Detect [L, g0, g1, R] x-boundaries and [T, B] y-boundaries of a
    1-row x 3-column grid on the WHITE twin (only full-length black lines
    are the border + the two vertical gutters)."""
    xp = _black_prof(rows, w, h, "x")
    yp = _black_prof(rows, w, h, "y")
    # Full-length black lines: border + gutter lines. Their profile value
    # is high over the WHOLE opposite axis, so any run length >= 3 counts.
    xr = [r for r in _runs(xp, minrun=3)]
    yr = [r for r in _runs(yp, minrun=3)]
    # Vertical full lines: outer border runs + gutter runs. Expect 4 runs:
    # left border, g0, g1, right border. Use midpoints, take outer two as
    # borders, the inner two as gutters.
    if len(xr) < 3:
        return None
    # choose runs closest to quarters/their natural extremes
    xr.sort(key=lambda r: (r[0] + r[1]) // 2)
    # If the AI gave a border only on some sides, the outer-most black
    # still delimit content where present; fall back to image edges.
    L = xr[0][1] if xr[0][0] < w * 0.06 else 0
    R = xr[-1][0] if xr[-1][1] > w * 0.94 else w
    inner = xr[1:-1]
    if len(inner) >= 2:
        # nearest to the thirds
        def score(r):
            m = (r[0] + r[1]) / 2
            return min(abs(m - w / 3), abs(m - 2 * w / 3))
        inner.sort(key=score)
        g0 = (inner[0][0] + inner[0][1]) // 2
        g1 = (inner[1][0] + inner[1][1]) // 2
        if g0 > g1:
            g0, g1 = g1, g0
    elif len(inner) == 1:
        m = (inner[0][0] + inner[0][1]) // 2
        if m < w / 2:
            g0, g1 = m, 2 * w // 3
        else:
            g0, g1 = w // 3, m
    else:
        g0, g1 = w // 3, 2 * w // 3
    # Horizontal: expect top + bottom border runs (2). Content between.
    T = yr[0][1] if yr and yr[0][0] < h * 0.08 else 0
    B = yr[-1][0] if yr and yr[-1][1] > h * 0.92 else h
    if B - T < h // 2:
        return None
    return [L, g0, g1, R], [T, B]


def process_walk(black, white, mob, out_walk):
    style = M.MOB_STYLE.get(mob, M.MOB_STYLE["dredger"])
    bw, bh, brows = M.read_rgba(black)
    ww, wh, wrows = M.read_rgba(white)
    xb, yb = bounds_1x3(wrows, ww, wh)
    if xb is None:
        print("ERROR: could not detect 1x3 walk strip layout on the white twin")
        sys.exit(2)
    print("bounds white: x =", xb, " y =", yb)
    xs = sorted(set(xb))
    cells = [(xs[i], yb[0], xs[i + 1], yb[1]) for i in range(3)]
    rows_out = []
    for i, box in enumerate(cells):
        pb = M.cell_to_file(brows, bw, bh, box, "WALK_B%d" % i)
        pw = M.cell_to_file(wrows, ww, wh, box, "WALK_W%d" % i)
        bK = M.border_bg(brows, box)
        bW = M.border_bg(wrows, box)
        _, _, br2 = M.read_rgba(pb)
        _, _, wr2 = M.read_rgba(pw)
        aB = M.alpha_single(br2, bK)
        aW = M.alpha_single(wr2, bW)
        cB = M.centroid(aB)
        cW = M.centroid(aW)
        dx, dy = M.refine_shift(aB, aW, round(cB[0] - cW[0]), round(cB[1] - cW[1]))
        cell_rows = [None] * 256
        M.compose_cell(br2, wr2, bK, bW, dx, dy, style, cell_rows)
        cell_rows = M.normalize_row(cell_rows)
        if cell_rows is None:
            print("cell", i, "EMPTY")
            cell_rows = [bytes(256 * 4)] * 256
        else:
            cell_rows = M.neon_rim(cell_rows, style)
        rows_out.extend(cell_rows)
        cov = sum(1 for r in cell_rows for x in range(0, 256, 2)
                  if r[x * 4 + 3] > 120)
        print("cell", i, "coverage", cov)
    write_png(out_walk, 256, 768, 6, b"", b"", rows_out)
    print("wrote", out_walk, os.path.getsize(out_walk), "bytes")


def splice_rows(sheet9, walk3, out):
    """Replace rows 3-5 of a 256x2304 sheet with the 3 walk rows."""
    w, h, srows = M.read_rgba(sheet9)
    w2, h2, wrows = M.read_rgba(walk3)
    assert h == 2304 and h2 == 768 and w == 256 and w2 == 256, "unexpected dims"
    new = srows[:768] + wrows + srows[1536:]
    write_png(out, 256, 2304, 6, b"", b"", new)
    print("wrote", out, os.path.getsize(out), "bytes")


def main():
    if sys.argv[1] == "--splice":
        splice_rows(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        black, white, out_walk, mob = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
        process_walk(black, white, mob, out_walk)


if __name__ == "__main__":
    main()
