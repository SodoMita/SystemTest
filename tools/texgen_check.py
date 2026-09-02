#!/usr/bin/env python3
"""
tools/texgen_check.py — CI/dev companion for sl_texgen.

The runtime texture generators (mods/apis/sl_texgen/gen/*.lua) replace
retired stock PNG files.  This tool executes the *same Lua code* under
an embedded Lua 5.1 runtime (lupa, mirroring tests/run_lua51.py) and:

  --verify    consistency between the generator registry and the repo:
                * every registered texture must NOT exist as a file
                  (they are deleted from the game; runtime supplies them)
                * every PNG inside the governed texture directories must
                  be registered (no orphans, nothing forgotten)
                * every generated PNG is structurally valid
  --export D  write all generated textures as real PNGs into D (and a
                contact sheet D/_contact.png) for visual comparison
  --report    print per-family byte counts of what no longer ships

Usage:
  python3 tools/texgen_check.py --verify
  python3 tools/texgen_check.py --export /tmp/texgen_out
"""
from __future__ import annotations

import argparse
import base64
import collections
import struct
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TEXGEN = REPO / "mods/apis/sl_texgen"

# Texture directories governed by the runtime pipeline.  The value is
# either "*" (whole directory), a filename prefix ("sl_"), or — for a
# partial claim — a list of exact filenames.
GOVERNED = {
    "mods/sl_blocks/construction/textures": "*",
    "mods/sl_blocks/ground/textures": "*",
    "mods/content/sl_scary/textures": "*",
    "mods/content/workshops/textures": "*",
    "mods/game/sl_weapons/textures": "*",
    "mods/content/sl_mvp_assets/textures": "*",
    "mods/content/sl_clothing/textures": "*",
    "mods/apis/sl_formspec/textures": "*",
    "mods/apis/dignodes/textures": "*",
    # sl_modebase: only the generated sl_* placeholder icons; the
    # AI-drawn sl_warning_sign.png / sl_objective_core_icon.png stay.
    "mods/game/sl_modebase/textures": "sl_",
    # sl_gui: the generated gui_category_* labelled icons; the 16x16
    # pixel-art tabs/slots/buttons are hand art and stay as files.
    "mods/apis/sl_gui/textures": "gui_category_",
}

# Files inside a claimed prefix that are intentionally NOT generated.
GOVERNED_EXEMPT = {
    "mods/game/sl_modebase/textures": {
        "sl_warning_sign.png",
        "sl_objective_core_icon.png",
    },
}


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
# engine stub + registry dump, executed in embedded Lua 5.1
# ----------------------------------------------------------------------

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
stub.encode_png = nil      -- exercise the pure-Lua fallback here
stub.encode_base64 = nil
stub.register_chatcommand = function() end
stub.get_dir_list = function() return {} end
core = stub
minetest = stub
dofile(ROOT .. "/mods/apis/sl_texgen/init.lua")
T = sl_texgen
textures = T.textures
sheets = {}
for _, d in ipairs(T.defs) do
  local c = T.build_canvas(d)
  sheets[d.name] = { w = c.w, h = c.h, px = c.px }
end
"""


def build_registry():
    import lupa.lua51

    # encoding=None so Lua strings arrive as raw bytes (PNG data is binary)
    lua = lupa.lua51.LuaRuntime(unpack_returned_tuples=True, encoding=None)
    lua.execute((LUA_PRELUDE % str(REPO)))
    T = lua.globals().T
    sheets = lua.globals().sheets
    textures = lua.globals().textures
    registry = {}
    for i in range(1, len(T.defs) + 1):
        d = T.defs[i]
        # encoding=None runtime: Lua string values/keys arrive as bytes
        name = d[b"name"].decode()
        frames = int(d[b"frames"] or 1)
        vertical = bool(d[b"vertical"])
        sheet = sheets[name.encode()]
        w = int(sheet[b"w"])
        h = int(sheet[b"h"])
        px = bytearray(w * h * 4)
        for i2 in range(w * h * 4):
            px[i2] = int(sheet[b"px"][i2 + 1] or 0)
        tex = textures[name.encode()]
        assert tex.startswith(b"[png:"), name
        registry[name] = {
            "w": w, "h": h, "px": bytes(px),
            "frames": frames, "vertical": vertical,
            "modifier": tex.decode("ascii"),
            "png": base64.b64decode(tex[5:]),
        }
    return registry


# ----------------------------------------------------------------------
# PNG output + structural decode (stdlib only)
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
    """Decode an 8-bit RGBA/palette PNG (stdlib only). Returns (w,h,rgba bytes)."""
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


def validate_png_bytes(png: bytes, name: str) -> str | None:
    """Return None if structurally valid, else a reason."""
    if png[:8] != b"\x89PNG\r\n\x1a\n":
        return "bad signature"
    pos = 8
    seen_ihdr = False
    while pos + 12 <= len(png):
        ln = struct.unpack(">I", png[pos:pos + 4])[0]
        typ = png[pos + 4:pos + 8]
        cdata = png[pos + 8:pos + 8 + ln]
        crc = struct.unpack(">I", png[pos + 8 + ln:pos + 12 + ln])[0]
        if zlib.crc32(typ + cdata) & 0xFFFFFFFF != crc:
            return f"{typ!r} chunk CRC mismatch"
        if typ == b"IHDR":
            seen_ihdr = True
            w, h = struct.unpack(">II", cdata[:8])
            if w == 0 or h == 0 or w > 4096 or h > 4096:
                return f"implausible dims {w}x{h}"
        pos += 12 + ln
        if typ == b"IEND":
            return None
    return "IEND missing" if seen_ihdr else "no IHDR"


# ----------------------------------------------------------------------
# checks
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
    registry = build_registry()
    fail = 0

    files = governed_pngs()
    # 1. registered textures must not exist as files
    still_there = [n for n in registry if any(f.name == n for f in files.values())]
    if still_there:
        fail += 1
        print(f"FAIL {len(still_there)} registered textures still exist as files (delete them):")
        for n in sorted(still_there)[:20]:
            print(f"     {n}")

    # 2. every governed PNG must be registered
    orphans = sorted(f for f in files.values() if f.name not in registry)
    if orphans:
        fail += 1
        print(f"FAIL {len(orphans)} unregistered PNGs inside governed directories:")
        for f in orphans[:20]:
            print(f"     {f.relative_to(REPO)}")

    # 3. no bare string references to registered names outside sl_texgen
    #    (they must go through sl_texgen.texture()/icon() so the [png:
    #    modifier actually reaches clients)
    import re
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
            # composed names (dignodes) are built with .. on both sides
            if not ok_ctx and ".." in src[max(0, m.start() - 3):m.start()]:
                ok_ctx = True
            # icon() handles the pure-resize suffix; other suffixes chain
            # after texture() — both fine
            if not ok_ctx and suf and not resize_re.match(suf):
                ok_ctx = True
            if not ok_ctx:
                bare.append((str(path.relative_to(REPO)), base))
    if bare:
        fail += 1
        print(f"FAIL {len(bare)} bare references to runtime textures (wrap in sl_texgen.texture()):")
        for p, n in bare[:20]:
            print(f"     {p}: {n}")

    # 4. mods referencing sl_texgen must declare the dependency
    for path in sorted(REPO.glob("mods/**/*.lua"), key=str):
        if "sl_texgen" in path.parts:
            continue
        src = path.read_text()
        if "sl_texgen." not in src:
            continue
        conf = path.parent / "mod.conf"
        if not conf.exists() or "sl_texgen" not in conf.read_text():
            bare_dep = str(path.relative_to(REPO))
            if (bare_dep, "") not in [(b, "") for b, _ in bare]:
                fail += 1
                print(f"FAIL {bare_dep}: uses sl_texgen but mod.conf does not depend on it")

    # 3. generated PNGs valid
    bad = []
    for name, info in registry.items():
        reason = validate_png_bytes(info["png"], name)
        if reason:
            bad.append((name, reason))
        w, h = info["w"], info["h"]
        # header dims must match canvas
        ihdr_w, ihdr_h = struct.unpack(">II", info["png"][16:24])
        if (ihdr_w, ihdr_h) != (w, h):
            bad.append((name, f"canvas {w}x{h} != IHDR {ihdr_w}x{ihdr_h}"))
    if bad:
        fail += 1
        print(f"FAIL {len(bad)} generated PNGs invalid:")
        for n, r in bad[:20]:
            print(f"     {n}: {r}")

    if fail == 0:
        total = sum(len(i["png"]) for i in registry.values())
        print(f"OK  {len(registry)} runtime textures, {total / 1024:.1f} KiB generated, "
              f"{len(files)} stock files correctly absent, registry and repo consistent.")
    return 1 if fail else 0


def cmd_export(outdir: Path) -> int:
    registry = build_registry()
    outdir.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, info in sorted(registry.items()):
        write_png(outdir / name, info["w"], info["h"], info["px"])
        write_png(outdir / name, info["w"], info["h"], info["px"]) if False else None
        total += len(info["png"])
    # contact sheet: vertical strip of thumbnails, labeled by order
    names = sorted(registry)
    entries = []
    for n in names:
        info = registry[n]
        # shrink anything wider than 160 px by integer factor
        w, h, px = info["w"], info["h"], info["px"]
        f = max(1, w // 160)
        if f > 1:
            sw, sh = w // f, h // f
            sp = bytearray(sw * sh * 4)
            for y in range(sh):
                for x in range(sw):
                    so = ((y * f) * w + x * f) * 4
                    sp[(y * sw + x) * 4:(y * sw + x) * 4 + 4] = px[so:so + 4]
            w, h, px = sw, sh, bytes(sp)
        entries.append((n, w, h, px))
    pad = 4
    cell_w = max(w for _, w, _, _ in entries) + 8
    cell_h = max(h for _, _, h, _ in entries) + 8
    sheet_h = sum(h + pad for _, _, h, _ in entries) + pad
    sheet = bytearray((cell_w + pad) * sheet_h * 4)
    for i in range((cell_w + pad) * sheet_h):
        sheet[i * 4 + 0] = 26
        sheet[i * 4 + 1] = 28
        sheet[i * 4 + 2] = 36
        sheet[i * 4 + 3] = 255
    y = pad
    for n, w, h, px in entries:
        base = (y * (cell_w + pad) + pad) * 4
        for yy in range(h):
            ro = (base + yy * (cell_w + pad) * 4)
            for xx in range(w):
                so = (yy * w + xx) * 4
                a = px[so + 3] / 255.0
                t = ro + xx * 4
                for k in range(3):
                    sheet[t + k] = int(px[so + k] * a + sheet[t + k] * (1 - a))
                sheet[t + 3] = 255
        y += h + pad
    write_png(outdir / "_contact.png", cell_w + pad, sheet_h, bytes(sheet))
    print(f"exported {len(registry)} PNGs ({total / 1024:.1f} KiB) + _contact.png to {outdir}")
    return 0


def cmd_report() -> int:
    registry = build_registry()
    fams = collections.Counter()
    for name, info in registry.items():
        # family guess from old path
        fams["generated"] += len(info["png"])
    files = governed_pngs()
    on_disk = sum(f.stat().st_size for f in files.values())
    print(f"registered: {len(registry)} textures, {fams['generated'] / 1024:.1f} KiB generated PNG")
    print(f"stock files matching registry still on disk: {sum(1 for f in files.values() if f.name in registry)} "
          f"({on_disk / 1024:.1f} KiB)")
    unreg = [(f, f.stat().st_size) for f in files.values() if f.name not in registry]
    if unreg:
        print(f"unregistered (kept as files): {len(unreg)} ({sum(s for _, s in unreg) / 1024:.1f} KiB)")
        for f, s in unreg:
            print(f"     {f} ({s} B)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true", help="check registry/repo consistency")
    ap.add_argument("--export", metavar="DIR", help="render all generated textures to DIR")
    ap.add_argument("--report", action="store_true", help="print byte accounting")
    args = ap.parse_args()
    if args.export:
        return cmd_export(Path(args.export))
    if args.report:
        return cmd_report()
    return cmd_verify()


if __name__ == "__main__":
    sys.exit(main())
