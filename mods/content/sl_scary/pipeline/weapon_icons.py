#!/usr/bin/env python3
"""Extract hi-res weapon/item icons from realistic 3x3 grid renders.

Owner workflow (2026-09-03): "generate realistic pics without neon,
then turn into neon flatcolored." Like matte_sheet.py for the mobs, but
each cell is a DIFFERENT item with its own neon palette, and the result
is one transparent 256x256 icon per item (not a 9-row strip).

Generation:
  1. black grid  (square 3x3, cell bg flat near-black #0D0D0F, pure
     black grid lines + outer border; each cell one realistic weapon,
     roughly 45-degree view, no floor/shadow/text)
  2. white twin  (same grid, only cell interiors -> pure white; lines
     and border stay pure black)

Usage:
  python3 weapon_icons.py BLACK_GRID WHITE_GRID OUTDIR \
      itemA,itemB,itemC,...      (9 comma-separated names, row-major;
                                  empty string = empty cell -> skipped)

Writes OUTDIR/sl_weapons_<item>.png (256x256 RGBA, < 1 MB each).
Item palettes live in ICON_STYLES below; tweak + re-run to re-roll a
palette without regenerating art.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matte_sheet as M  # noqa: E402
from transpose_sprite_strip import read_png, write_png  # noqa: E402

# ---------------------------------------------------------------------------
# Per-item neon styles (fill = single flat body colour; rim = neon edge +
# glow; accents = recolour targets for bright saturated features).
# Provisional assignments: ammo crates follow pool colours (bullets cyan,
# shells amber, cells magenta, rockets green); guns get signature hues.
# ---------------------------------------------------------------------------
WHITE = (248, 248, 248)
CYAN = (0, 232, 255)
GREEN = (0, 255, 65)
AMBER = (255, 191, 0)
MAGENTA = (232, 0, 168)

ICON_STYLES = {
    "pistol":         {"fill": (9, 11, 14),  "rim": CYAN,    "accents": [CYAN, WHITE]},
    "chatter":        {"fill": (9, 13, 10),  "rim": GREEN,   "accents": [GREEN, WHITE]},
    "scatter":        {"fill": (13, 11, 8),  "rim": AMBER,   "accents": [AMBER, WHITE]},
    "lance":          {"fill": (13, 8, 13),  "rim": MAGENTA, "accents": [MAGENTA, WHITE]},
    "mortar":         {"fill": (12, 12, 12), "rim": WHITE,   "accents": [(255, 150, 60), WHITE]},
    "driver":         {"fill": (8, 11, 14),  "rim": CYAN,    "accents": [CYAN, WHITE]},
    "neon_six":       {"fill": (13, 10, 8),  "rim": AMBER,   "accents": [AMBER, WHITE]},
    "repeater":       {"fill": (13, 8, 12),  "rim": MAGENTA, "accents": [MAGENTA, WHITE]},
    "severance":      {"fill": (10, 10, 12), "rim": WHITE,   "accents": [WHITE, CYAN]},
    "ammo_bullets":   {"fill": (8, 11, 13),  "rim": CYAN,    "accents": [CYAN, WHITE]},
    "ammo_shells":    {"fill": (13, 11, 8),  "rim": AMBER,   "accents": [AMBER, WHITE]},
    "ammo_cells":     {"fill": (13, 8, 13),  "rim": MAGENTA, "accents": [MAGENTA, WHITE]},
    "ammo_rockets":   {"fill": (9, 13, 10),  "rim": GREEN,   "accents": [GREEN, WHITE]},
    "grapple":        {"fill": (8, 11, 14),  "rim": CYAN,    "accents": [CYAN, WHITE]},
    "sentry_kit":     {"fill": (13, 11, 8),  "rim": AMBER,   "accents": [AMBER, WHITE]},
    "targeting_log":  {"fill": (9, 13, 11),  "rim": GREEN,   "accents": [GREEN, WHITE]},
}
FALLBACK_STYLE = {"fill": (10, 11, 13), "rim": CYAN, "accents": [CYAN, WHITE]}


def normalize_icon(cell_rows, pad=26):
    """Centre the sprite in a 256x256 icon: fit into (256-2*pad) square,
    keep aspect, no floor baseline. Returns 256 rows (or None if empty)."""
    p = os.path.join(M.WORK, "icon_norm.png")
    raw = bytearray()
    for r in cell_rows:
        raw += r
    open(p + ".rgba", "wb").write(bytes(raw))
    M.im(["-size", "256x256", "-depth", "8", "rgba:" + p + ".rgba", "PNG32:" + p])
    w, h, rows = M.read_rgba(p)
    xs, ys = [], []
    for y in range(h):
        for x in range(0, w, 2):
            if rows[y][x * 4 + 3] > 40:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    cw = max(xs) - min(xs) + 1
    ch = max(ys) - min(ys) + 1
    box = 256 - 2 * pad
    scale = min(box / cw, box / ch)
    nw = max(1, min(256, int(cw * scale)))
    nh = max(1, min(256, int(ch * scale)))
    x0 = (256 - nw) // 2
    y0 = (256 - nh) // 2
    M.im([p, "-trim", "+repage", "-filter", "Lanczos", "-resize", "%dx%d!" % (nw, nh),
          "+repage", "PNG32:" + p])
    M.im(["-size", "256x256", "xc:none", p, "-geometry", "+%d+%d" % (x0, y0),
          "-composite", "PNG32:" + p])
    _, _, rows = M.read_rgba(p)
    return rows


def process_pair(black, white, items, outdir):
    """black/white: paths to the two grid renders. items: 9 row-major names."""
    bw, bh, brows = M.read_rgba(black)
    ww, wh, wrows = M.read_rgba(white)
    xb = M.gutters(ww, wh, wrows, (0, 0, 0))
    if xb is None:
        xb = M.gutters(bw, bh, brows, (0, 0, 0))
    xw, yw = xb
    print("bounds white: x =", xw, " y =", yw)
    if None in xw or None in yw:
        print("ERROR: could not detect 3x3 grid")
        sys.exit(2)
    cells = M.slice_cells(xw, yw)
    made = []
    for i in range(9):
        name = items[i].strip() if i < len(items) else ""
        if not name:
            continue
        style = ICON_STYLES.get(name, FALLBACK_STYLE)
        pb = M.cell_to_file(brows, bw, bh, cells[i], "I_B%d" % i)
        pw = M.cell_to_file(wrows, ww, wh, cells[i], "I_W%d" % i)
        bK = M.border_bg(brows, cells[i])
        bW = M.border_bg(wrows, cells[i])
        _, _, br2 = M.read_rgba(pb)
        _, _, wr2 = M.read_rgba(pw)
        aB = M.alpha_single(br2, bK)
        aW = M.alpha_single(wr2, bW)
        cB = M.centroid(aB)
        cW = M.centroid(aW)
        dx, dy = M.refine_shift(aB, aW,
                                round(cB[0] - cW[0]), round(cB[1] - cW[1]))
        cell_rows = [None] * 256
        M.compose_cell(br2, wr2, bK, bW, dx, dy, style, cell_rows)
        cell_rows = normalize_icon(cell_rows)
        if cell_rows is None:
            print("  cell", i, name, "EMPTY - skipped")
            continue
        cell_rows = M.neon_rim(cell_rows, style)
        outp = os.path.join(outdir, "sl_weapons_%s.png" % name)
        write_png(outp, 256, 256, 6, b"", b"", cell_rows)
        cov = sum(1 for r in cell_rows for x in range(0, 256, 2)
                  if r[x * 4 + 3] > 120)
        print("  cell", i, name, "coverage", cov, os.path.getsize(outp), "bytes")
        made.append(outp)
    return made


def main():
    black, white, outdir, manifest = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    items = manifest.split(",")
    if len(items) < 9:
        items += [""] * (9 - len(items))
    os.makedirs(outdir, exist_ok=True)
    process_pair(black, white, items[:9], outdir)


if __name__ == "__main__":
    main()
