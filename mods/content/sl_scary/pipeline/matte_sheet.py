#!/usr/bin/env python3
"""Build the 9-frame mob sheets with two-background alpha triangulation.

Per the asset workflow (GENERATED_ASSETS.md): every pose is rendered
twice — on a pure-black background and on pure white, same 3x3 layout.
The black and white grids are each sliced into nine cells and, per cell,
the alpha channel is solved from the pair of renders:

    B = C*a + bK*(1-a)   (black render, straight colour C, bg bK)
    W = C*a + bW*(1-a)   (white render, bg bW)
  => a = clamp(1 - (W - B)/(bW - bK))          [triangulated alpha]

The white cell is shift-registered onto the black cell (centroid + coarse
correlation) before solving. Then the cell is **neonized** (owner
2026-09-03: "generate realistic pics without neon, then turn into neon
flatcolored"): the AI renders REALISTIC creatures; this script flattens
the body interior to the mob's single flat colour, recolours bright
saturated features (eyes/visor/maw/glints) to the mob's neon accents by
hue, colours soft/AA/glow pixels with the rim colour, and strokes a
crisp neon rim + soft glow around the silhouette.

Output: 256x2304 vertical sheet, 9 rows of 256x256:
  row 0 FRONT, 1 BACK, 2 SIDE, 3-5 WALK x3, 6-7 ATTACK x2, 8 DEATH

Usage: python3 matte_sheet.py BLACK_GRID WHITE_GRID OUT_SHEET MOB
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from transpose_sprite_strip import read_png, write_png  # noqa: E402

WORK = os.environ.get("SPRITE_WORK", "/tmp/sl_sprite_work")
os.makedirs(WORK, exist_ok=True)

# Neon-flat style per mob (owner 2026-09-03 "generate realistic pics
# without neon, then turn into neon flatcolored"): the AI draws a
# REALISTIC creature (no neon/colouring constraints); this script then
# flattens the body to a single colour, recolours the creature's bright
# features to the mob's neon accents, and strokes a neon rim + glow
# around the triangulated silhouette.
#   fill    - single flat body colour
#   rim     - neon colour of the silhouette rim / soft parts (glow)
#   accents - neon palette used to recolour bright saturated features
#             (eyes, visor crack, maw, sparks) - picked per pixel by hue
MOB_STYLE = {
    "dredger":     {"fill": (9, 10, 12), "rim": (230, 120, 40),
                    "accents": [(230, 120, 40), (0, 255, 65)]},   # amber rim, green visor
    "wraith":      {"fill": (8, 5, 16), "rim": (0, 235, 255),
                    "accents": [(0, 235, 255), (150, 235, 255)]},  # cyan rim/eyes, ice
    "containment": {"fill": (10, 7, 5), "rim": (255, 170, 0),
                    "accents": [(255, 170, 0), (255, 70, 40)]},    # amber rim, ember eyes
}

# Feature threshold: pixels at/above this saturation (or very high
# luminance) inside the silhouette become neon accents; everything else
# becomes the flat fill.
SAT_FEATURE = 0.30
LUM_FEATURE = 205


def im(args):
    subprocess.run(["convert"] + args, check=True)


def read_rgba(png):
    w, h, ct, _, _, rows = read_png(png)
    if ct != 6:
        im([png, "-depth", "8", "PNG32:/tmp/norm_%d.png" % abs(hash(png))])
        w, h, ct, _, _, rows = read_png("/tmp/norm_%d.png" % abs(hash(png)))
    return w, h, rows


def gutters(w, h, rows, bg, tol=14):
    """Grid boundaries of the 3x3 layout.

    Searches four positions per axis (outer frame edges at k=0 and k=3,
    the two inner gutter midlines at k=1 and k=2), each inside a window
    around its geometric third. Every boundary is the widest pure-`bg`
    run (fraction > 0.99) in that window:

      k=0  -> outer edge:  end   of the run  (content starts after the
             top/left border; falls back to 0 when the AI omitted that
             border side)
      k=3  -> outer edge:  start of the run  (content ends before the
             bottom/right border; excludes post-generation margin junk
             such as the annotation text strip, which can sit below the
             grid's black border)
      k=1,2 -> inner gutters: midline of the run

    Detected on the white twin (its cell interiors are near white, so the
    only full-width near-black runs are border + gutter lines).
    """
    def energy_prof(axis):
        prof = []
        if axis == "x":
            n = h
            for x in range(w):
                hit = 0
                for y in range(0, h, 3):
                    q = rows[y][x * 4:x * 4 + 4]
                    if abs(q[0] - bg[0]) <= tol and abs(q[1] - bg[1]) <= tol and abs(q[2] - bg[2]) <= tol:
                        hit += 1
                prof.append(hit / ((h + 2) // 3))
        else:
            n = w
            for y in range(h):
                hit = 0
                for x in range(0, w, 3):
                    q = rows[y][x * 4:x * 4 + 4]
                    if abs(q[0] - bg[0]) <= tol and abs(q[1] - bg[1]) <= tol and abs(q[2] - bg[2]) <= tol:
                        hit += 1
                prof.append(hit / ((w + 2) // 3))
        return prof

    def find(prof, size):
        def runs_in(lo, hi):
            runs = []
            i = max(0, lo)
            while i < min(size, hi):
                if prof[i] > 0.98:
                    j = i
                    while j < min(size, hi) and prof[j] > 0.98:
                        j += 1
                    if j - i >= 2:
                        runs.append((i, j))
                    i = j
                else:
                    i += 1
            return runs
        out = []
        for k in range(4):
            if k == 0:
                centre = 0
                win = max(10, size // 8)
                want = "end"      # content starts after the border run
            elif k == 3:
                centre = size
                win = max(10, size // 8)
                want = "start"    # content ends before the border run
            else:
                centre = size * k // 3
                win = max(10, size // 8)
                want = "mid"
            lo = max(0, centre - win)
            hi = min(size, centre + win)
            rs = runs_in(lo, hi)
            if not rs:
                rs = runs_in(max(0, centre - win * 2), min(size, centre + win * 2))
            if rs:
                rs.sort(key=lambda r: r[1] - r[0], reverse=True)
                a, b = rs[0]
                if want == "end":
                    out.append(b)
                elif want == "start":
                    out.append(a)
                else:
                    out.append((a + b) // 2)
            else:
                out.append(0 if k == 0 else (size if k == 3 else centre))
        return out

    px = find(energy_prof("x"), w)
    py = find(energy_prof("y"), h)
    if len(px) < 4 or len(py) < 4:
        return None
    # px/py are [L, gx0, gx1, R] and [T, gy0, gy1, B] on the white twin.
    return px, py


def slice_cells(xb, yb):
    """Nine cell boxes from the four x boundaries and four y boundaries."""
    cells = []
    for r in range(3):
        for c in range(3):
            cells.append((xb[c], yb[r], xb[c + 1], yb[r + 1]))
    return cells


def cell_to_file(rows, w, h, box, tag, pad=4):
    """Crop one cell. `pad` skips the pixels immediately next to the grid
    lines: the AI keeps those ~1-3px gutter strips black in BOTH twins, so
    leaving them in would make the alpha solve paint them as opaque fill
    (the 'double-pixel outline chip' artifact). Cells are ~250-550px wide,
    so dropping pad px on every side costs nothing measurable."""
    x0, y0, x1, y1 = box
    if x1 - x0 > 2 * pad + 4 and y1 - y0 > 2 * pad + 4:
        x0 += pad
        y0 += pad
        x1 -= pad
        y1 -= pad
    p = os.path.join(WORK, "%s.png" % tag)
    raw = bytearray()
    for y in range(y0, y1):
        raw += rows[y][x0 * 4:x1 * 4]
    open(p + ".rgba", "wb").write(bytes(raw))
    im(["-size", "%dx%d" % (x1 - x0, y1 - y0), "-depth", "8", "rgba:" + p + ".rgba",
        "-resize", "256x256!", "PNG32:" + p])
    os.unlink(p + ".rgba")
    return p


def border_bg(rows, box):
    x0, y0, x1, y1 = box
    acc = [0, 0, 0]
    n = 0
    for y in range(y0, y1):
        for x in list(range(x0, min(x0 + 5, x1))) + list(range(max(x0, x1 - 5), x1)):
            q = rows[y][x * 4:x * 4 + 3]
            for k in range(3):
                acc[k] += q[k]
            n += 1
    for x in range(x0, x1):
        for y in (y0, min(y1 - 1, y0 + 4)):
            q = rows[y][x * 4:x * 4 + 3]
            for k in range(3):
                acc[k] += q[k]
            n += 1
    return tuple(acc[k] // max(1, n) for k in range(3))


def alpha_single(rows, bg, thr=60):
    a = [0] * (256 * 256)
    for y in range(256):
        r = rows[y]
        for x in range(256):
            q = r[x * 4:x * 4 + 3]
            if abs(q[0] - bg[0]) + abs(q[1] - bg[1]) + abs(q[2] - bg[2]) > thr:
                a[y * 256 + x] = 1
    return a


def centroid(a):
    sx = sy = m = 0
    for y in range(0, 256, 2):
        for x in range(0, 256, 2):
            if a[y * 256 + x]:
                m += 1
                sx += x
                sy += y
    return (sx / m, sy / m) if m else (128, 128)


def refine_shift(aB, aW, dx0, dy0):
    """coarse best integer shift of aW onto aB in a small window around dx0,dy0"""
    best = None
    best_score = 1e18
    for dy in range(dy0 - 3, dy0 + 4):
        for dx in range(dx0 - 3, dx0 + 4):
            diff = 0
            cnt = 0
            for y in range(0, 256, 4):
                for x in range(0, 256, 4):
                    sx = x - dx
                    sy = y - dy
                    if 0 <= sx < 256 and 0 <= sy < 256:
                        diff += abs(aB[y * 256 + x] - aW[sy * 256 + sx])
                        cnt += 1
            if cnt:
                s = diff / cnt
                if s < best_score:
                    best_score = s
                    best = (dx, dy)
    return best or (dx0, dy0)


def _sat(r, g, b):
    mx = max(r, g, b)
    return 0.0 if mx == 0 else (mx - min(r, g, b)) / mx


def _hue(r, g, b):
    """Standard 0..360 hue; -1 for neutral greys."""
    mx, mn = max(r, g, b), min(r, g, b)
    if mx == mn:
        return -1.0
    d = mx - mn
    if mx == r:
        h = ((g - b) / d) % 6
    elif mx == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    return h * 60.0


def _nearest_accent(r, g, b, accents):
    """Pick the accent whose hue is closest to the pixel's hue (wrap-safe)."""
    h = _hue(r, g, b)
    if h < 0:
        return accents[0]
    best, bestd = accents[0], 999.0
    for a in accents:
        ha = _hue(*a)
        d = abs(h - ha)
        d = min(d, 360.0 - d)
        if d < bestd:
            bestd = d
            best = a
    return best


def compose_cell(brows, wrows, bK, bW, dx, dy, style, out_row):
    """Triangulate alpha, then neonize the pixel (owner workflow).

    Pixel classes (the AI's two renders rarely share the exact same
    straight colour, so plain triangulation would leave the whole body
    semi-transparent):
      * solid core (alpha high) - opaque:
          - dark / low-saturation interior  -> single flat `fill`
          - bright saturated features       -> nearest neon `accent`
      * soft pixels (low alpha: AA edge, wisps, glows, thin effects)
        -> `rim` colour at the triangulated soft alpha (this becomes the
        neon aura on edges; a crisp rim is stroked afterwards).
    """
    bd = tuple(bW[k] - bK[k] for k in range(3))
    den = 0.30 * bd[0] + 0.59 * bd[1] + 0.11 * bd[2]
    fill = style["fill"]
    rim = style["rim"]
    accents = style["accents"]
    for y in range(256):
        br = brows[y]
        out = bytearray(256 * 4)
        for x in range(256):
            sx = x - dx
            sy = y - dy
            if 0 <= sx < 256 and 0 <= sy < 256:
                wr = wrows[sy]
                wq = wr[sx * 4:sx * 4 + 3]
                bq = br[x * 4:x * 4 + 3]
                num = 0.30 * (wq[0] - bq[0]) + 0.59 * (wq[1] - bq[1]) + 0.11 * (wq[2] - bq[2])
                av = 1.0 - num / den if den > 0 else 0.0
                if av > 0.04:
                    if av > 0.55:
                        sat = _sat(*bq)
                        LB = 0.2126 * bq[0] + 0.7152 * bq[1] + 0.0722 * bq[2]
                        # Feature = saturated colour (eyes/visor/maw/neon
                        # bits). Neutral-bright pixels (studio highlights,
                        # light metal, white-hot blades) are NOT features:
                        # recolouring them would break the single-flat-fill
                        # look. Only ~pure-white cores (LB > 250) pass so a
                        # white-hot edge still reads as a glint accent.
                        if sat >= SAT_FEATURE or LB >= 250:
                            c = _nearest_accent(*bq, accents)
                        else:
                            c = fill
                        out[x * 4:x * 4 + 3] = bytes(c)
                        out[x * 4 + 3] = 255
                    else:
                        # soft edge / wisp / glow -> neon rim at soft alpha
                        a255 = int(max(0.0, min(1.0, av * 1.9)) * 255)
                        out[x * 4:x * 4 + 3] = bytes(rim)
                        out[x * 4 + 3] = a255
        out_row[y] = bytes(out)


def neon_rim(cell_rows, style):
    """Stroke a neon rim + soft outer glow around the silhouette.

    Operates on a normalised 256x256 cell (post normalize_row): the rim
    is the 2px dilation ring of the alpha mask coloured with the mob's
    rim colour, plus a blurred 4px halo at low alpha for the glow.
    """
    p = os.path.join(WORK, "rim_in.png")
    raw = bytearray()
    for r in cell_rows:
        raw += r
    open(p + ".rgba", "wb").write(bytes(raw))
    im(["-size", "256x256", "-depth", "8", "rgba:" + p + ".rgba", "PNG32:" + p])
    base = os.path.join(WORK, "rim_base.png")
    mask = os.path.join(WORK, "rim_mask.png")
    dil2 = os.path.join(WORK, "rim_d2.png")
    dil6 = os.path.join(WORK, "rim_d6.png")
    ring = os.path.join(WORK, "rim_ring.png")
    halo = os.path.join(WORK, "rim_halo.png")
    ringc = os.path.join(WORK, "rim_ringc.png")
    haloc = os.path.join(WORK, "rim_haloc.png")
    out = os.path.join(WORK, "rim_out.png")
    im([p, "-alpha", "extract", mask])
    # empty cell guard: mean of mask ~ 0
    probe = subprocess.run(["convert", mask, "-format", "%[fx:mean]", "info:"],
                           capture_output=True, text=True)
    if not probe.stdout or float(probe.stdout) < 0.002:
        return cell_rows
    rim_hex = "#%02X%02X%02X" % style["rim"]
    im([mask, "-morphology", "Dilate", "Disk:2", dil2])
    im([mask, "-morphology", "Dilate", "Disk:6", dil6])
    # ring = dil2 minus mask ; halo = dil6 minus dil2
    im([dil2, mask, "-compose", "MinusSrc", "-composite", ring])
    im([dil6, dil2, "-compose", "MinusSrc", "-composite", halo])
    im(["-size", "256x256", "xc:" + rim_hex, ringc])
    im([ringc, ring, "-alpha", "off", "-compose", "CopyOpacity", "-composite", ringc + "2.png"])
    im(["-size", "256x256", "xc:" + rim_hex, haloc])
    im([haloc, halo, "-alpha", "off", "-compose", "CopyOpacity", "-composite", haloc + "2.png"])
    # halo: soft glow behind the sprite
    im([haloc + "2.png", "-channel", "A", "-evaluate", "Multiply", "0.55", "+channel",
        "-blur", "0x4", haloc])
    # final compose: base (sprite) <- halo behind <- sharp ring on top
    im(["-size", "256x256", "xc:none", base])
    im([base, p, "-composite", haloc, "-composite", ringc + "2.png", "-composite", out])
    _, _, rows = read_rgba(out)
    for f in (ringc + "2.png", haloc + "2.png", ring, halo, ringc, haloc, dil2, dil6, mask, base):
        try:
            os.unlink(f)
        except OSError:
            pass
    return rows


def normalize_row(cell_rows):
    """Trim the alpha bbox, scale height to 220px (Lanczos), centre
    horizontally, feet baseline at row 238. Returns 256 rows."""
    p = os.path.join(WORK, "norm.png")
    raw = bytearray()
    for r in cell_rows:
        raw += r
    open(p + ".rgba", "wb").write(bytes(raw))
    im(["-size", "256x256", "-depth", "8", "rgba:" + p + ".rgba", "PNG32:" + p])
    # bbox
    w, h, rows = read_rgba(p)
    xs, ys = [], []
    for y in range(h):
        for x in range(0, w, 2):
            if rows[y][x * 4 + 3] > 40:
                xs.append(x)
                ys.append(y)
    if not xs:
        # empty cell: transparent (signal None -> main writes blank rows)
        return None
    cw = max(xs) - min(xs) + 1
    ch = max(ys) - min(ys) + 1
    target_h = 220
    scale = target_h / ch
    nw = max(1, min(256, int(cw * scale)))
    x0 = max(0, (256 - nw) // 2)
    y0 = 238 - target_h
    im([p, "-trim", "+repage", "-filter", "Lanczos", "-resize", "%dx%d!" % (nw, target_h),
        "+repage", "PNG32:" + p])
    im(["-size", "256x256", "xc:none", p, "-geometry", "+%d+%d" % (x0, y0),
        "-composite", "PNG32:" + p])
    _, _, rows = read_rgba(p)
    return rows


def main():
    black, white, out, mob = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    style = MOB_STYLE.get(mob, MOB_STYLE["dredger"])
    bw, bh, brows = read_rgba(black)
    ww, wh, wrows = read_rgba(white)
    # The white twin is the layout authority: its cell interiors are near
    # white, so the ONLY full-width near-black lines are the grid border +
    # gutters. (The black twin's cell background is also near black, which
    # would fool a black-background search into reporting wide interior
    # runs instead of the 1-3px lines.) Boundaries = [L,gx0,gx1,R] and
    # [T,gy0,gy1,B] — the outer pair are the frame edges, so post-gen
    # margin junk outside the grid is never cropped into a cell.
    xb = gutters(ww, wh, wrows, (0, 0, 0))
    if xb is None:
        # Degenerate fallback: detect on the black twin.
        xb = gutters(bw, bh, brows, (0, 0, 0))
    xw, yw = xb
    print("bounds white: x =", xw, " y =", yw)
    if None in xw or None in yw:
        print("ERROR: could not detect 3x3 grid")
        sys.exit(2)
    # The black twin was generated anchored on the same layout; any
    # residual 1-4px drift is handled by the per-cell shift registration.
    cb = slice_cells(xw, yw)
    cw = slice_cells(xw, yw)
    sheet_rows = []  # 9*256 rows
    stats = []
    for i in range(9):
        pb = cell_to_file(brows, bw, bh, cb[i], "B%d" % i)
        pw = cell_to_file(wrows, ww, wh, cw[i], "W%d" % i)
        bK = border_bg(brows, cb[i])
        bW = border_bg(wrows, cw[i])
        _, _, br2 = read_rgba(pb)
        _, _, wr2 = read_rgba(pw)
        aB = alpha_single(br2, bK)
        aW = alpha_single(wr2, bW)
        cB = centroid(aB)
        cW = centroid(aW)
        dx0 = round(cB[0] - cW[0])
        dy0 = round(cB[1] - cW[1])
        dx, dy = refine_shift(aB, aW, dx0, dy0)
        cell_rows = [None] * 256
        compose_cell(br2, wr2, bK, bW, dx, dy, style, cell_rows)
        cell_rows = normalize_row(cell_rows)
        if cell_rows is None:
            blank = [bytes(256 * 4)] * 256
            sheet_rows.extend(blank)
            stats.append(0)
            continue
        cell_rows = neon_rim(cell_rows, style)
        sheet_rows.extend(cell_rows)
        cov = sum(1 for r in cell_rows for x in range(0, 256, 2) if r[x * 4 + 3] > 120)
        stats.append(cov)
    write_png(out, 256, 256 * 9, 6, b"", b"", sheet_rows)
    print("wrote", out, "coverage/row:", stats)
    sz = os.path.getsize(out)
    print("size:", sz, "bytes", "WARN>1MB" if sz > 1_000_000 else "")


if __name__ == "__main__":
    main()
