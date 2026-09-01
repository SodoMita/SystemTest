#!/usr/bin/env python3
"""
tools/gen_example_map_mts.py — generate the example handmade map .mts.

The match map system (mods/game/sl_modebase/map.lua) accepts handmade
arenas saved as .mts schematics — exactly what WorldEdit's //schem save
(or minetest.create_schematic, or /sl_map save) produces. This tool
writes the "neon_crossfire" example map directly in that binary format
so the repo ships one real .mts without needing an engine to export it.

Format (doc'd in engine src/mapgen/mg_schematic.h — all big-endian):
    u32  signature 'MTSM'
    u16  version (4)
    u16  size X, Y, Z
    Y*u8 slice probabilities        (0x7F = always place)
    u16  node-name count
      .. u16 name length + bytes
    zlib {
      nodes*u16 content id          (index into the name table)
      nodes*u8  param1              (placement probability, 0x7F = always)
      nodes*u8  param2
    }
  node iteration order: z, then y, then x (x varies fastest).

The generator round-trip parses its own output before writing.

Usage: python3 tools/gen_example_map_mts.py [--check-only]
"""

import argparse
import io
import struct
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUT_DIR = REPO / "mods/game/sl_modebase/maps/neon_crossfire"

SIZE_X, SIZE_Y, SIZE_Z = 49, 7, 49

AIR = "air"
FLOOR = "ground:square_neon"
WALL = "ground:square_neon_opaque"

PROB_ALWAYS = 0x7F


def build_layout():
    """Return nodes[x][y][z] = name (gameplay anchors come from map.conf)."""
    n = lambda: AIR
    g = [[[n() for _ in range(SIZE_Z)] for _ in range(SIZE_Y)] for _ in range(SIZE_X)]

    def fill(x0, x1, y0, y1, z0, z1, what):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    g[x][y][z] = what

    # Floor slab.
    fill(0, SIZE_X - 1, 0, 0, 0, SIZE_Z - 1, FLOOR)
    # Perimeter walls.
    for x in range(SIZE_X):
        for y in range(1, 5):
            g[x][y][0] = WALL
            g[x][y][SIZE_Z - 1] = WALL
    for z in range(SIZE_Z):
        for y in range(1, 5):
            g[0][y][z] = WALL
            g[SIZE_X - 1][y][z] = WALL

    # Beacon bastions (5x5 raised pads at the midfield line); the beacon
    # nodes themselves are placed by the game from map.conf anchors.
    for cx in (6, 42):
        fill(cx - 2, cx + 2, 1, 1, 22, 26, WALL)
        for c in ((cx - 2, 22), (cx - 2, 26), (cx + 2, 22), (cx + 2, 26)):
            for y in (2, 3):
                g[c[0]][y][c[1]] = WALL

    # Midfield altar dais.
    fill(22, 26, 1, 1, 22, 26, WALL)

    # Monster Master redoubt (raised 7x7 with a doorway toward midfield).
    fill(21, 27, 1, 1, 38, 44, WALL)
    for x in range(21, 28):
        for z in range(38, 45):
            if x in (21, 27) or z in (38, 44):
                for y in (2, 3, 4):
                    g[x][y][z] = WALL
    for y in (2, 3):  # doorway
        g[24][y][38] = AIR

    # Symmetric cover clusters.
    for cx, cz in ((14, 12), (34, 12), (10, 24), (38, 24), (14, 33), (34, 33)):
        for mx, mz in ((1, 1), (-1, -1)):
            fill(24 + mx * (cx - 24), 24 + mx * (cx - 24) + 1, 1, 2,
                 24 + mz * (cz - 24), 24 + mz * (cz - 24) + 1, WALL)

    return g


def serialize_mts(grid):
    names = []
    name_ids = {}

    def nid(name):
        if name not in name_ids:
            name_ids[name] = len(names)
            names.append(name)
        return name_ids[name]

    ids = bytearray()
    p1 = bytearray()
    p2 = bytearray()
    for z in range(SIZE_Z):          # z outer, x fastest — engine order
        for y in range(SIZE_Y):
            for x in range(SIZE_X):
                ids += struct.pack(">H", nid(grid[x][y][z]))
                p1.append(PROB_ALWAYS)
                p2.append(0)

    out = io.BytesIO()
    out.write(b"MTSM")
    out.write(struct.pack(">H", 4))                       # version
    out.write(struct.pack(">HHH", SIZE_X, SIZE_Y, SIZE_Z))
    for _ in range(SIZE_Y):                               # slice probs
        out.write(bytes([PROB_ALWAYS]))
    out.write(struct.pack(">H", len(names)))
    for name in names:
        raw = name.encode("ascii")
        out.write(struct.pack(">H", len(raw)))
        out.write(raw)
    out.write(zlib.compress(bytes(ids) + bytes(p1) + bytes(p2)))
    return out.getvalue()


def parse_mts(blob):
    """Round-trip verification against the documented format."""
    assert blob[:4] == b"MTSM", "bad signature"
    off = 4
    (version,) = struct.unpack_from(">H", blob, off)
    off += 2
    assert version == 4, f"unexpected version {version}"
    sx, sy, sz = struct.unpack_from(">HHH", blob, off)
    off += 6
    assert (sx, sy, sz) == (SIZE_X, SIZE_Y, SIZE_Z), "bad size"
    off += sy  # slice probabilities
    (count,) = struct.unpack_from(">H", blob, off)
    off += 2
    names = []
    for _ in range(count):
        (ln,) = struct.unpack_from(">H", blob, off)
        off += 2
        names.append(blob[off : off + ln].decode("ascii"))
        off += ln
    data = zlib.decompress(blob[off:])
    total = sx * sy * sz
    assert len(data) == total * 4, "node data size mismatch"
    ids = struct.unpack_from(f">{total}H", data, 0)
    p1 = data[total * 2 : total * 3]
    p2 = data[total * 3 :]
    assert all(v == PROB_ALWAYS for v in p1), "bad probability"
    assert all(v == 0 for v in p2), "unexpected param2"

    def node_at(x, y, z):
        idx = z * (sy * sx) + y * sx + x
        return names[ids[idx]]

    return node_at


MAP_CONF = """\
# Handmade map: Neon Crossfire
# Saved as a WorldEdit-compatible .mts schematic (rotation 0).
# Coordinates below are schematic-relative (min corner = 0,0,0);
# the game places beacons / altar / MM pad / spawns at these anchors.
name = Neon Crossfire
author = SodoMita
rotation = 0
size = {sx},{sy},{sz}

beacon_a.pos = 6,2,24
beacon_b.pos = 42,2,24
altar.pos = 24,2,24
mm.pos = 24,2,41
lobby.pos = 24,1,4
ghost.pos = 24,12,24

# Initial mob population, respawned at every match start.
mobs.1 = 12,2,12,stalker
mobs.2 = 36,2,12,scout
mobs.3 = 24,2,30,brute
mobs.4 = 12,2,36,dredger
mobs.5 = 36,2,36,wraith
""".format(sx=SIZE_X, sy=SIZE_Y, sz=SIZE_Z)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-only", action="store_true",
                    help="verify the committed .mts instead of rewriting it")
    args = ap.parse_args()

    grid = build_layout()
    blob = serialize_mts(grid)

    # Round-trip: reparse and spot-check structure.
    node_at = parse_mts(blob)
    assert node_at(24, 0, 24) == FLOOR
    assert node_at(0, 3, 0) == WALL
    assert node_at(24, 2, 24) == AIR      # altar anchor is placed by the game
    assert node_at(6, 1, 24) == WALL      # beacon A bastion pad
    assert node_at(24, 2, 38) == AIR      # MM doorway
    assert node_at(3, 1, 24) == AIR       # inside the arena

    mts = OUT_DIR / "map.mts"
    if args.check_only:
        have = mts.read_bytes()
        if have != blob:
            print("FAIL: committed map.mts differs from generator output")
            return 1
        print(f"OK: {mts} ({len(blob)} bytes) round-trips")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    mts.write_bytes(blob)
    (OUT_DIR / "map.conf").write_text(MAP_CONF)
    print(f"wrote {mts} ({len(blob)} bytes) + map.conf")
    return 0


if __name__ == "__main__":
    sys.exit(main())
