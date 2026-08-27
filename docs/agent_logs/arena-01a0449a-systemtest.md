# Agent log — arena-01a0449a-systemtest

**Date:** 2026-08-27
**Task:** Rebuild the default tiny generated map without anything from the
default Minetest Game: neon grid ground, opaque neon grid walls forming
configurable hollow cubes with a monster in each, plus a Monster Master base.
**Follow-up (same day):** the neon grid ground is now an infinite flat plane,
so players can never walk off the map and fall into the void.

## Follow-up: infinite flat neon floor (worldgen.lua)

Owner direction after the first pass: the grid is supposed to be infinite —
a flat surface, not a finite platform floating over the void.

- New `mods/game/sl_modebase/worldgen.lua`, included from `init.lua` before
  `test_harness.lua`. Every generated chunk that crosses ground level
  (y = 0) gets a one-node-thick layer of `ground:square_neon` across its
  whole footprint. The floor extends infinitely in every direction; the
  cube-grid arena is now an island on that endless plane (same node, same
  level, no seam).
- Fast path uses the mapgen VoxelManip (`get_mapgen_object("voxelmanip")` +
  `set_data`/`write_to_map`, per the documented on_generated contract) for
  a single bulk write per chunk; falls back to plain `set_node` when the
  mapgen object is unavailable (headless stub) or refuses. The callback is
  `pcall`-guarded so a VoxelManip failure degrades instead of erroring.
- Chunks entirely above or below ground level are left untouched, and the
  write is idempotent (`data[vi] ~= id` check) so re-generation re-floors
  nothing.
- Setting: `sl_arena.infinite_floor` (bool, default true) disables the
  floor. Gated with a string compare (`~= "false"`) like `sl_test.auto_arena`
  so unset settings behave like the engine's nil.
- `test_harness.lua` now takes its floor node constant from
  `game_mode.FLOOR_NODE` (owned by worldgen.lua) and documents that the
  arena sits on the plane.
- Stub: `register_on_generated` now records handlers and
  `M.fire_on_generated(minp, maxp)` replays them like the engine would.
- Smoke test PHASE 16: far chunks (positive and negative coordinates) get
  floored, chunks above/below ground level are untouched, nothing is added
  above the surface, the arena is on the same plane, and `generate_floor`
  reports its column count. Suite: 122/122.

## What changed (first pass)


### 1. Opaque neon grid node (new)
- `mods/sl_blocks/ground/init.lua`: `ground:square_neon_opaque` — a copy of
  `ground:square_neon` with `drawtype = "normal"` and no `use_texture_alpha`
  (fully opaque). Same glow (`light_source = 14`), same dig groups.
- `mods/sl_blocks/ground/textures/square_neon_opaque.png`: `square_neon.png`
  alpha-composited onto a solid dark plate (near-black `#06080e`). The neon
  grid lines sit on the texture edges, so tiled nodes read as one continuous
  glowing grid.
- `mods/sl_blocks/ground/mod.conf`: explicit `depends = default` (the mod
  already called `default.node_sound_glass_defaults()` at load time).

### 2. The default tiny map (rewrite of `build_test_arena`)
`mods/game/sl_modebase/test_harness.lua` no longer builds the 41x21
`default:stone` / `default:obsidian` box. The generated map is now a neon
grid arena made only of System Looting nodes:

- **Floor** — `ground:square_neon` (the transparent neon grid) across the
  whole footprint.
- **Cube grid** — `ground:square_neon_opaque` walls on every cell boundary:
  one node thick, as tall as the cubes are wide, so the playfield is a grid
  of sealed hollow cubes.
- **Monsters** — one `sl_modebase:monster` penned at the center of every
  ordinary cube (11 at default settings). Rebuilds de-duplicate (tracked
  ObjRefs + an `get_objects_inside_radius` sweep for static-saved
  survivors), and an `end_match` wrapper re-populates the pens after a
  match because `end_match` wipes every monster entity.
- **Special cubes** — beacon A / beacon B pads on the west/east edge
  (opaque neon pad + beacon + team spawn), the ghost altar at the center
  cube with an open lobby deck floating above it (lobby players cannot dig,
  so they need open ground), and the Monster Master base citadel on the
  north edge (solid neon plinth + `spawn_mm` marker; the master's floaty
  jump clears the walls trivially).
- **Robustness** — the builder refuses to fall back to `default:*` nodes if
  the ground nodes are missing; node placement runs after
  `minetest.emerge_area` (set_node no-ops on never-generated blocks — same
  lesson `aaa_botmatch` learned); `arena_built` is set before building to
  block on_generated re-entry; the volume is cleared to air before placing
  so rebuilds after settings changes leave no orphans.

### 3. Configurable geometry (settingtypes.txt)
- `sl_arena.cube_size` (int, default 4, 2–16): interior side length of each
  hollow cube; wall height matches it so cells are literal hollow cubes.
- `sl_arena.grid_width` / `sl_arena.grid_depth` (int, default 5 / 3, 2–32):
  number of cubes along X / Z. Default footprint: 26 x 16 nodes.

### 4. Cloud cage de-defaulted
`nodes.lua` `build_cloud_cage` used `default:glass` and
`default:obsidianbrick`. It now uses `ground:square_neon` (floor slab) and
`ground:square_neon_opaque` (pylons), so no generated structure places
default-mod nodes anymore.

### 5. Dependencies
`sl_modebase/mod.conf` now depends on `ground` (hard dep, guarantees the
neon nodes exist before the arena builder runs).

## Test changes
- `tests/minetest_stub.lua`: `add_entity` now returns tracked fake
  ObjectRefs (position, `get_pos`, valid `remove`, `get_luaentity`) and
  `get_objects_inside_radius` is implemented. The fakes deliberately have
  no `.name` field so `end_match`'s `minetest.luaentities` iteration keeps
  skipping them.
- `tests/smoke_test.lua`:
  - PHASE 1 loads the real `ground` mod (with `core`/`default` shims) and
    asserts the opaque node is registered and truly opaque.
  - PHASE 2 cloud-cage expectations updated to the neon nodes.
  - New PHASE 15 builds the arena and asserts floor/wall materials, hollow
    cube geometry, altar/beacons/Monster Master base/deck placement, state
    spawns, monster count + placement, rebuild de-duplication,
    settings-driven re-configuration (cube size 2), and — the point of the
    task — zero `default:*` nodes anywhere in the generated map.
- `tests/bin/run_lua.py`: tiny dev runner used in this sandbox (no luajit
  available here); CI keeps using `luajit tests/smoke_test.lua`.

## Verification
- Stub suite: 122/122 (was 85; +28 arena pass, +9 infinite floor pass).
- LuaJIT-equivalent syntax sweep: 74 files clean.
- ASCII top-down/cross-section render of the generated voxels verified the
  grid layout, special cubes, deck, and monster pens by eye.

## Out of scope (left alone)
- `aaa_botmatch` builds and owns its own soak arena (`default:stone`
  floor); it disables the auto-arena and is CI-only harness scenery, not
  the game's default map.
- Beacon mesh textures (`default_mese_block.png` etc.) — item visuals, not
  map content.
