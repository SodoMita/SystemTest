#!/usr/bin/env python3
"""
tools/texgen_check.py — CI/dev companion for sl_texgen.

The runtime texture pipeline compiles every generated texture to a
pure "[combine:..." program that the CLIENT renders (see
mods/apis/sl_texgen/stx.lua).  This tool executes the *same Lua
generator code* under an embedded Lua 5.1 runtime (lupa, mirroring
tests/run_lua51.py) and:

  --verify    full consistency gate:
                * shared base textures (textures/stx_*.png) match a
                  fresh deterministic regeneration
                * every compiled program is executed by a reference
                  interpreter (resize/multiply/opacity/sheet/combine)
                  and produces an in-bounds image
                * registered textures must NOT exist as repo files
                * every PNG inside the governed texture directories
                  must be registered
                * game code must reference runtime textures through
                  sl_texgen.texture()/icon() and declare the dep
  --export D  execute all programs and write the resulting PNGs into
              D (+ _contact.png) for visual comparison
  --report    print program-string accounting

Usage:
  python3 tools/texgen_check.py --verify
  python3 tools/texgen_check.py --export /tmp/texgen_out
"""
from __future__ import annotations

import argparse
import base64  # noqa: F401  (kept for parity with older exports)
import collections
import re
import struct
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TEXGEN = REPO / "mods/apis/sl_texgen"

LUA_PRELUDE = r"""
ROOT = %r
textures = {}
defs = {}
stub = {}
stub.get_current_modname = function() return "sl_texgen" end
stub.get_modpath = function(name)
  if name == "sl_texgen" then return ROOT .. "/mods/apis/sl_texgen" end
  return nil
end
stub.settings = { get = function() return nil end }
stub.log = function() end
stub.register_chatcommand = function() end
stub.get_dir_list = function() return {} end
core = stub
minetest = stub
dofile(ROOT .. "/mods/apis/sl_texgen/init.lua")
T = sl_texgen
"""

# Texture directories governed by the runtime pipeline.  The value is
# either "*" (whole directory), a filename prefix ("sl_"), or — for a
# partial claim — a list of exact filenames.
GOVERNED = {
    "mods/sl_blocks/construction/textures": "*",
    "mods/sl_blocks/ground/textures": "*",
    "mods/content/sl_scary/textures": "*",
    "mods/content/workshops/textures": "*",
    "mods/game/sl_weapons/textures": "*",
    "mods/game/sl_modebase/textures": "sl_",
    "mods/apis/sl_formspec/textures": "*",
    "mods/apis/dignodes/textures": "*",
    "mods/apis/sl_gui/textures": "gui_category_",
    # sl_mvp_assets/sl_clothing textures moved fully under the program
    # pipeline too:
    "mods/content/sl_mvp_assets/textures": "*",
    "mods/content/sl_clothing/textures": "*",
}

# Files inside a claimed prefix that are intentionally NOT generated.
GOVERNED_EXEMPT = {
    "mods/game/sl_modebase/textures": {
        "sl_warning_sign.png",
        "sl_objective_core_icon.png",
    },
}

BASES = [
    "stx_px.png", "stx_glow.png", "stx_ring.png", "stx_noise.png",
    "stx_noise_rgb.png", "stx_x.png", "stx_rhombus.png", "stx_font.png",
]


def claimed(dir_rel: str, fname: str) -> bool:
    claim = GOVERNED.get(dir_rel)
    if claim is None:
        return False
    if fname in GOVERNED_EXEMPT.get(dir_rel, set()):
        return False
    if claim == "*":
        return True
    if isinstance(claim, str):
        return fname.startswith(claim)
    return fname in claim


# ----------------------------------------------------------------------
# registry dump (embedded Lua)
# ----------------------------------------------------------------------

def build_registry() -> dict[str, dict]:
    import lupa.lua51

    lua = lupa.lua51.LuaRuntime(unpack_returned_tuples=True, encoding=None)
    lua.execute(LUA_PRELUDE % str(REPO))
    T = lua.globals().T
    registry = {}
    for i in range(1, len(T.defs) + 1):
        d = T.defs[i]
        bname = d[b"name"]
        name = bname.decode()
        frames = int(d[b"frames"] or 1)
        vertical = bool(d[b"vertical"])
        program = T.textures[bname]
        registry[name] = {
            "w": int(d[b"w"]), "h": int(d[b"h"]),
            "frames": frames, "vertical": vertical,
            "program": program.decode("ascii"),
        }
    return registry


# ----------------------------------------------------------------------
# PNG I/O (stdlib only)
# ----------------------------------------------------------------------

def write_png(path: Path, w: int, h: int, px: bytes) -> None:
    raw = b"".join(b"\x00" + px[y * w * 4:(y + 1) * w * 4] for y in range(h))

    def chunk(t: bytes, d: bytes) -> bytes:
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )


def read_png(path: Path):
    """Decode an 8-bit RGBA/palette PNG (stdlib only). Returns (w,h,rgba)."""
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos, idat, trns, plte = 8, b"", None, None
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        c = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, bitd, ct = struct.unpack(">IIBB", c[:10])
        elif typ == b"IDAT":
            idat += c
        elif typ == b"PLTE":
            plte = c
        elif typ == b"tRNS":
            trns = c
        pos += 12 + ln
    raw = zlib.decompress(idat)
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    stride = (w * nch * bitd + 7) // 8
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    ptr = 0

    def rd(buf, idx):
        if bitd == 8:
            return buf[idx]
        per = 8 // bitd
        v = (buf[idx // per] >> (8 - bitd * (idx % per + 1))) & ((1 << bitd) - 1)
        return v * 255 // ((1 << bitd) - 1)

    for y in range(h):
        ft = raw[ptr]
        ptr += 1
        line = bytearray(raw[ptr:ptr + stride])
        ptr += stride
        for i in range(stride):
            a = line[i - nch] if i >= nch else 0
            b = prev[i]
            c0 = prev[i - nch] if i >= nch else 0
            if ft == 1:
                line[i] = (line[i] + a) & 255
            elif ft == 2:
                line[i] = (line[i] + b) & 255
            elif ft == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif ft == 4:
                p = a + b - c0
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c0)
                line[i] = (line[i] + (a if (pa <= pb and pa <= pc) else (b if pb <= pc else c0))) & 255
        prev = line
        for x in range(w):
            o = (y * w + x) * 4
            if ct == 6:
                out[o:o + 4] = line[x * 4:x * 4 + 4]
            elif ct == 2:
                out[o:o + 3] = line[x * 3:x * 3 + 3]
                out[o + 3] = 255
            elif ct == 0:
                v = rd(line, x)
                out[o] = out[o + 1] = out[o + 2] = v
                out[o + 3] = 255
            elif ct == 3:
                v = rd(line, x)
                if v * 3 + 3 <= len(plte or b""):
                    out[o:o + 3] = plte[v * 3:v * 3 + 3]
                out[o + 3] = trns[v] if trns and v < len(trns) else 255
    return w, h, bytes(out)


# ----------------------------------------------------------------------
# reference [combine interpreter
# ----------------------------------------------------------------------

def split_unescaped(s: str, sep: str) -> list[str]:
    parts, cur, i = [], [], 0
    while i < len(s):
        c = s[i]
        if c == "\\":
            cur.append(c)
            cur.append(s[i + 1] if i + 1 < len(s) else "")
            i += 2
        elif c == sep:
            parts.append("".join(cur))
            cur = []
            i += 1
        else:
            cur.append(c)
            i += 1
    parts.append("".join(cur))
    return parts


unescape = lambda s: re.sub(r"\\(.)", r"\1", s)


def resize_img(img, tw, th):
    """Box-average resample (w,h,rgba) -> (tw,th,rgba)."""
    w, h, px = img
    out = bytearray(tw * th * 4)
    for y in range(th):
        sy0, sy1 = y * h // th, max(y * h // th + 1, (y + 1) * h // th)
        for x in range(tw):
            sx0, sx1 = x * w // tw, max(x * w // tw + 1, (x + 1) * w // tw)
            r = g = b = a = n = 0
            for yy in range(sy0, min(sy1, h)):
                for xx in range(sx0, min(sx1, w)):
                    o = (yy * w + xx) * 4
                    r += px[o]
                    g += px[o + 1]
                    b += px[o + 2]
                    a += px[o + 3]
                    n += 1
            o = (y * tw + x) * 4
            out[o], out[o + 1], out[o + 2], out[o + 3] = (
                r // n, g // n, b // n, a // n)
    return tw, th, bytes(out)


def apply_term(img, op):
    """Apply one '^[kind:args' op (unescaped) to an image."""
    m = re.match(r"^\[([a-z]+):?(.*)$", op)
    assert m, f"bad op {op!r}"
    kind, args = m.group(1), m.group(2)
    w, h, px = img
    if kind == "resize":
        tw, th = (int(v) for v in re.match(r"^(\d+)x(\d+)$", args).groups())
        return resize_img(img, tw, th)
    if kind == "multiply":
        r0, g0, b0 = (int(args[i:i + 2], 16) for i in (1, 3, 5))
        out = bytearray(px)
        for i in range(w * h):
            o = i * 4
            out[o] = px[o] * r0 // 255
            out[o + 1] = px[o + 1] * g0 // 255
            out[o + 2] = px[o + 2] * b0 // 255
        return w, h, bytes(out)
    if kind == "opacity":
        n = int(args)
        out = bytearray(px)
        for i in range(w * h):
            out[i * 4 + 3] = px[i * 4 + 3] * n // 255
        return w, h, bytes(out)
    if kind == "sheet":
        m2 = re.match(r"^(\d+)x(\d+):(\d+),(\d+)$", args)
        tw, th, tx, ty = (int(v) for v in m2.groups())
        cw, chh = w // tw, h // th
        out = bytearray(cw * chh * 4)
        for y in range(chh):
            so = ((ty * chh + y) * w + tx * cw) * 4
            o = (y * cw) * 4
            out[o:o + cw * 4] = px[so:so + cw * 4]
        return cw, chh, bytes(out)
    raise AssertionError(f"interpreter: unsupported modifier [{kind}")


def over(canvas, img, x, y):
    cw, ch, cpx = canvas
    w, h, px = img
    out = bytearray(cpx)
    for yy in range(max(0, y), min(ch, y + h)):
        for xx in range(max(0, x), min(cw, x + w)):
            so = ((yy - y) * w + (xx - x)) * 4
            sa = px[so + 3] / 255.0
            t = (yy * cw + xx) * 4
            da = out[t + 3] / 255.0
            oa = sa + da * (1 - sa)
            if oa <= 0:
                continue
            k0, k1 = sa / oa, (da * (1 - sa)) / oa
            for k in range(3):
                out[t + k] = int(px[so + k] * k0 + out[t + k] * k1)
            out[t + 3] = int(oa * 255)
    return cw, ch, bytes(out)


def execute_program(program: str, bases: dict) -> tuple[int, int, bytes]:
    """Run a compiled sl_texgen program; returns (w,h,rgba)."""
    finishing = []
    core = program
    if core.startswith("("):
        close = core.index(")")
        finishing = [unescape(p) for p in re.split(r"(?<!\\)\^", core[close + 1:]) if p]
        core = core[1:close]
    m = re.match(r"^\[combine:(\d+)x(\d+):?(.*)$", core, re.S)
    assert m, f"not a combine program: {program[:80]!r}"
    w, h = int(m.group(1)), int(m.group(2))
    canvas = (w, h, bytes(w * h * 4))
    body = m.group(3)
    if body:
        for blit in split_unescaped(body, ":"):
            mm = re.match(r"^(-?\d+),(-?\d+)=(.+)$", unescape(blit), re.S)
            assert mm, f"malformed blit {blit[:60]!r}"
            x, y, term = int(mm.group(1)), int(mm.group(2)), mm.group(3)
            ops = term.split("^")
            img = bases[ops[0]]
            for op in ops[1:]:
                img = apply_term(img, op)
            canvas = over(canvas, img, x, y)
    for f in finishing:
        canvas = apply_term(canvas, f)
    return canvas


def load_bases() -> dict:
    return {name: read_png(TEXGEN / "textures" / name) for name in BASES}


# ----------------------------------------------------------------------
# base-texture regeneration check (determinism of the shared bases)
# ----------------------------------------------------------------------

def check_bases() -> list[str]:
    problems = []
    sys.path.insert(0, str(REPO / "tools"))
    import texgen_make_bases as maker

    expected = {
        "stx_px.png": maker.make_px(),
        "stx_glow.png": maker.make_glow(),
        "stx_ring.png": maker.make_ring(),
        "stx_noise.png": maker.make_noise(rgb=False),
        "stx_noise_rgb.png": maker.make_noise(rgb=True),
        "stx_x.png": maker.make_x(),
        "stx_rhombus.png": maker.make_rhombus(),
        "stx_font.png": maker.make_font(),
    }
    import tempfile
    for name, (buf, w, h) in expected.items():
        want_path = TEXGEN / "textures" / name
        if not want_path.exists():
            problems.append(f"missing base texture {name}")
            continue
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
            maker.write_png(Path(tf.name), w, h, bytes(buf))
            want = Path(tf.name).read_bytes()
        if want_path.read_bytes() != want:
            problems.append(f"{name} does not match deterministic regeneration "
                            "(run tools/texgen_make_bases.py)")
    return problems


# ----------------------------------------------------------------------
# repo consistency + hygiene
# ----------------------------------------------------------------------

def governed_pngs():
    out = {}
    for d in GOVERNED:
        p = REPO / d
        if not p.is_dir():
            continue
        for f in sorted(p.glob("*.png")):
            if claimed(d, f.name):
                out[str(f.relative_to(REPO))] = f
    return out


def cmd_verify() -> int:
    fail = 0

    # 0. shared bases are byte-stable
    problems = check_bases()
    if problems:
        fail += 1
        for p in problems:
            print(f"FAIL {p}")
    else:
        print(f"OK  {len(BASES)} shared base textures match deterministic regeneration")

    registry = build_registry()
    bases = load_bases()

    # 1. execute every program with the reference interpreter
    exec_bad = []
    total = 0
    for name, info in sorted(registry.items()):
        total += len(info["program"])
        try:
            w, h, px = execute_program(info["program"], bases)
            iw = info["w"] * (1 if info["vertical"] else info["frames"])
            ih = info["h"] * (info["frames"] if info["vertical"] else 1)
            if (w, h) != (iw, ih):
                exec_bad.append(f"{name}: executed {w}x{h} != sheet {iw}x{ih}")
        except Exception as e:  # noqa: BLE001
            exec_bad.append(f"{name}: {e}")
    if exec_bad:
        fail += 1
        for b in exec_bad[:15]:
            print(f"FAIL {b}")
    else:
        print(f"OK  {len(registry)} programs executed by the reference interpreter "
              f"({total / 1024:.1f} KiB of program strings)")

    # 2. registered textures must not exist as files
    files = governed_pngs()
    still_there = [n for n in registry if any(f.name == n for f in files.values())]
    if still_there:
        fail += 1
        print(f"FAIL {len(still_there)} registered textures still exist as files:")
        for n in sorted(still_there)[:15]:
            print(f"     {n}")

    # 3. every governed PNG must be registered
    orphans = sorted(f for f in files.values() if f.name not in registry)
    if orphans:
        fail += 1
        print(f"FAIL {len(orphans)} unregistered PNGs inside governed directories:")
        for f in orphans[:15]:
            print(f"     {f.relative_to(REPO)}")

    # 4. hygiene: no bare references, deps declared
    lit = re.compile(r'"([A-Za-z0-9_]+\.png)((?:\^[^"]*)?)"')
    resize_re = re.compile(r"\^\[resize:(\d+)x(\d+)$")
    bare = []
    for path in sorted(REPO.glob("mods/**/*.lua"), key=str):
        if "sl_texgen" in path.parts:
            continue
        src = path.read_text()
        for m in lit.finditer(src):
            base, suf = m.group(1), m.group(2)
            if base not in registry:
                continue
            ok_ctx = "sl_texgen.texture(\"" in src[max(0, m.start() - 20):m.start() + 1] or \
                "sl_texgen.icon(\"" in src[max(0, m.start() - 20):m.start() + 1]
            if not ok_ctx and ".." in src[max(0, m.start() - 3):m.start()]:
                ok_ctx = True
            if not ok_ctx and suf and not resize_re.match(suf):
                ok_ctx = True
            if not ok_ctx:
                bare.append((str(path.relative_to(REPO)), base))
        if "sl_texgen." in src:
            conf = path.parent / "mod.conf"
            if not conf.exists() or "sl_texgen" not in conf.read_text():
                bare.append((str(path.relative_to(REPO)), "(missing mod.conf dep)"))
    if bare:
        fail += 1
        print(f"FAIL {len(bare)} hygiene problems:")
        for p, n in bare[:15]:
            print(f"     {p}: {n}")

    if fail == 0:
        print(f"OK  registry and repo consistent; runtime texture pipeline verified.")
    return 1 if fail else 0


def cmd_export(outdir: Path) -> int:
    registry = build_registry()
    bases = load_bases()
    outdir.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, info in sorted(registry.items()):
        w, h, px = execute_program(info["program"], bases)
        write_png(outdir / name, w, h, px)
        total += len(info["program"])
    print(f"executed+exported {len(registry)} textures "
          f"({total / 1024:.1f} KiB of programs) to {outdir}")
    return 0


def cmd_contact(out: Path) -> int:
    """Execute all programs and render a labelled review sheet (needs Pillow)."""
    from PIL import Image, ImageDraw

    registry = build_registry()
    bases = load_bases()
    cols, cell, scale = 8, 72, 3
    names = sorted(registry)
    rows = (len(names) + cols - 1) // cols
    out_im = Image.new("RGBA", (cols * cell, rows * (cell + 11)), (24, 24, 30, 255))
    d = ImageDraw.Draw(out_im)
    for i, name in enumerate(names):
        info = registry[name]
        w, h, px = execute_program(info["program"], bases)
        im = Image.frombytes("RGBA", (w, h), px)
        frames = []
        for f in range(min(info["frames"], 3)):
            frames.append(im.crop((0, f * info["h"], info["w"], (f + 1) * info["h"]))
                          if info["vertical"] else
                          im.crop((f * info["w"], 0, (f + 1) * info["w"], info["h"])))
        per = min(3, len(frames))
        grid = Image.new("RGBA", (per * info["w"], info["h"] * ((len(frames) + per - 1) // per)),
                         (28, 28, 34, 255))
        for j, fr in enumerate(frames):
            grid.alpha_composite(fr, ((j % per) * info["w"], (j // per) * info["h"]))
        grid = grid.resize((grid.width * scale, grid.height * scale), Image.NEAREST)
        grid.thumbnail((cell, cell))
        x, y = (i % cols) * cell, (i // cols) * (cell + 11)
        out_im.alpha_composite(grid, (x + (cell - grid.width) // 2, y + (cell - grid.height) // 2))
        d.text((x + 2, y + cell - 1), name.replace(".png", "")[:17], fill=(170, 170, 180, 255))
    out.parent.mkdir(parents=True, exist_ok=True)
    out_im.save(out)
    print(f"contact sheet with {len(names)} textures -> {out}")
    return 0


def cmd_report() -> int:
    registry = build_registry()
    total = sum(len(i["program"]) for i in registry.values())
    biggest = max(registry.items(), key=lambda kv: len(kv[1]["program"]))
    by_family = collections.Counter()
    for name, info in registry.items():
        by_family[info["frames"] > 1 and "animated sheets" or "single textures"] += len(info["program"])
    print(f"registered: {len(registry)} textures -> {total / 1024:.1f} KiB of [combine programs")
    for k, v in by_family.most_common():
        print(f"  {k}: {v / 1024:.1f} KiB")
    print(f"  largest: {biggest[0]} ({len(biggest[1]['program']) / 1024:.1f} KiB)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true", help="full consistency gate")
    ap.add_argument("--export", metavar="DIR", help="execute programs and export PNGs")
    ap.add_argument("--contact", metavar="PNG",
                    help="execute programs and render a labelled review sheet")
    ap.add_argument("--report", action="store_true", help="print program accounting")
    args = ap.parse_args()
    if args.contact:
        return cmd_contact(Path(args.contact))
    if args.export:
        return cmd_export(Path(args.export))
    if args.report:
        return cmd_report()
    return cmd_verify()


if __name__ == "__main__":
    sys.exit(main())
