#!/usr/bin/env python3
"""Transpose a horizontal sprite strip into a vertical sprite strip.

Luanti plays `sprite` visuals with `object:set_sprite(...)`; the engine
advances animation frames along the frame **y** position (one row per
frame, rows stacked top-to-bottom, see `lua_api.md` -> set_sprite).  A
horizontal strip (9 frames of 16x16 laid left-to-right, 144x16) can never
animate in-engine: the whole texture is drawn because spritediv defaults
to {x=1, y=1}.

This script re-arranges an existing horizontal strip into the vertical
layout the engine expects, **without touching a single pixel**: each
16x16 frame is copied unchanged into its own row band.  Frame order is
preserved (frame 0 ends up at the top).  The inverse layout is the one
the `sl_scary` mob art used at authoring time and it is what the
spritesheet comment in `sl_scary/init.lua` describes.

    python3 transpose_sprite_strip.py IN.png OUT.png [--frames 9]

Pure stdlib (zlib) so it runs anywhere the repo's other generator
scripts run.  Deterministic: same input -> byte-identical output.
Supports 8-bit RGBA/RGB/grayscale/palette PNGs with any scanline filter.

Usage for the shipped sheets:

    python3 transpose_sprite_strip.py \
        textures/sl_scary_dredger_strip.png \
        textures/sl_scary_dredger_strip.png --frames 9
"""

import argparse
import struct
import sys
import zlib


def read_png(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG: %s" % path)
    pos = 8
    width = height = depth = ctype = None
    palette = b""
    trns = b""
    idat = b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, _ = struct.unpack(
                ">IIBBBBB", chunk)
        elif kind == b"PLTE":
            palette = chunk
        elif kind == b"tRNS":
            trns = chunk
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
        pos += 12 + length
    if depth != 8:
        raise ValueError("only 8-bit PNGs are supported: %s" % path)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = width * channels
    rows = []
    off = 0
    for y in range(height):
        filt = raw[off]
        off += 1
        line = bytearray(raw[off:off + stride])
        off += stride
        prev = rows[-1] if rows else None
        if filt == 1:      # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filt == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif filt == 3:    # Average
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i] if prev else 0
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
        elif filt == 4:    # Paeth
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i] if prev else 0
                c = prev[i - channels] if prev and i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif filt != 0:
            raise ValueError("bad scanline filter %d" % filt)
        rows.append(bytes(line))
    return width, height, ctype, palette, trns, rows


def write_png(path, width, height, ctype, palette, trns, rows):
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    stride = width * channels
    out = b"\x89PNG\r\n\x1a\n"
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload +
                struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, ctype,
                                      0, 0, 0))
    if ctype == 3:
        out += chunk(b"PLTE", palette)
        if trns:
            out += chunk(b"tRNS", trns)
    raw = b"".join(b"\x00" + r for r in rows)
    out += chunk(b"IDAT", zlib.compress(raw, 9))
    out += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(out)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--frames", type=int, default=9,
                    help="number of frames in the strip (default 9)")
    args = ap.parse_args(argv)

    w, h, ctype, palette, trns, rows = read_png(args.src)
    if w % args.frames != 0:
        sys.exit("width %d is not divisible by %d frames" %
                 (w, args.frames))
    cell_w = w // args.frames
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]

    # Horizontal strip: frame k occupies x in [k*cell_w, (k+1)*cell_w),
    # y in [0, h).  Vertical strip: frame k occupies x in [0, cell_w),
    # y in [k*h, (k+1)*h).  Pixels are copied verbatim (no resampling).
    out_rows = []
    for k in range(args.frames):
        for y in range(h):
            row = rows[y]
            out_rows.append(
                row[k * cell_w * channels:(k + 1) * cell_w * channels])

    out_w, out_h = cell_w, args.frames * h
    write_png(args.dst, out_w, out_h, ctype, palette, trns, out_rows)
    print("wrote %s: %dx%d -> %dx%d (%d frames of %dx%d, unchanged pixels)"
          % (args.dst, w, h, out_w, out_h, args.frames, cell_w, h))


if __name__ == "__main__":
    main(sys.argv[1:])
