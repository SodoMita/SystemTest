# Generated Missing Assets

This asset pass was generated procedurally for prototype use.  It fills missing media references found in the repository and the MVP list in `NEEDED ASSETS.md`.

## Added

- `mods/content/sl_mvp_assets/` — MVP placeholder models (`player.obj`, `monster.obj`, `platform.obj`, `terminal.obj`, `door.obj`, `hatch.obj`, `item.obj`, `item_pickup.obj`, `pulse.obj`, `scanner_pulse.obj`, `flare_light.obj`, `particle.obj`, `death_particle.obj`), textures/UI (`neon_cube.png`, `cursor.png`, `hud.png`, `hud_frame.png`, `font.png`, model textures), and OGG sounds (`ambience`, `music`, footsteps, alerts, monster cues, radio static, etc.).
- `mods/content/sl_clothing/textures/` — inventory icons for all clothing items.
- `mods/content/sl_clothing/models/` — valid B3D stand-ins for clothing/accessory model names.
- `mods/content/workshops/textures/` — workshop/furniture/lab/sign/window node textures listed in the workshop prototype.
- `mods/content/sl_scary/textures/` and `mods/content/sl_scary/sounds/` — hide spot textures plus `scary_attack.ogg`, `mob_idle.ogg`, and `mob_death.ogg`.
- **New high-tech horror mobs** (see `mods/content/sl_scary/init.lua` for full registration). All mobs follow a strict **3-color palette** rule: pure black silhouette + 1-2 accent colors (neon when multiple):
  - **`sl_scary:dredger`** — Corrupted maintenance worker (Kowalski). Patrols routes, stops to "fix" nearby interactable nodes, attacks when interrupted. Drops `sl_scary:dredger_badge` (lore item). **Animated sprite strip** (`sl_scary_dredger_strip.png`, 144×16, 9 frames): 3 idle, 3 walk, 2 attack, 1 death. Palette: black body, rust-orange (#CC6622) armor outlines (shoulders/knees), neon-green (#00FF41) visor crack + chest LEDs.
  - **`sl_scary:signal_wraith`** — Ghost data trapped in the signal layer. Non-physical (phases through walls), drifts between glitch-teleports, corrupts players with screen-shake on hit. Drops `sl_scary:corrupted_data` (information item, unreliable). **Animated sprite strip** (`sl_scary_wraith_strip.png`, 144×16, 9 frames): 3 idle, 3 walk, 2 attack, 1 death. Palette: black silhouette, deep-void-purple (#1A0033) body fill, neon-cyan (#00FFFF) eyes + data fragments.
  - **`sl_scary:containment`** — Bio-mechanical horror sealed in Section 12. Dormant until a player enters its 5-node wake range. Slow, devastating (10 dmg), stunned after each attack. Drops `sl_scary:containment_shard` (lore + proof). **Animated sprite strip** (`sl_scary_containment_strip.png`, 144×16, 9 frames): 3 idle, 3 walk, 2 attack, 1 death. Palette: black body, deep-crimson (#8B0000) flesh patches, neon-amber (#FFBF00) maw + sensor-eyes.
  - **Sprite pipeline** (`mods/content/sl_scary/pipeline/`): adapted from `SodoMita/Seirin/tools/img_pipeline`.
    - `downscale_filter.c` — Mitchell/Hermite kernel downscale (pure C, no deps). Runs on opaque source first.
    - `matte_floodfill.c` — border-seeded flood-fill alpha extraction from solid-white background. Run on downscaled output.
    - Workflow: generate 3D front-facing portrait sprite sheet (3×3 grid, 9 frames) on black bg + white bg → extract frames → downscale each to 16×16 with Mitchell kernel → matte white version → composite RGB from black with alpha from white → arrange into 144×16 horizontal sprite strip.
  - Creative-only dev commands: `/sl_spawn_dredger`, `/sl_spawn_wraith`, `/sl_spawn_containment`.
- `mods/apis/sl_gui/sounds/` — `achievement_unlock.ogg` and `level_up.ogg`.
- `mods/content/dark_skybox/sounds/` — `creepy_ambient.ogg` for the optional dark-skybox ambience hook.
- `mods/sl_blocks/ground/textures/` — white/rainbow noise animated and still textures.
- `menu/` — `header.png`, `background.png`, and `menu_music.ogg` for Luanti-compatible menu branding/audio.

## Notes

These are intentionally lightweight placeholders: suitable for loading the game and testing gameplay loops, not final production art. Replace files in place as final assets become available.

---

# 16x16 Node Texture Pass

A follow-up asset pass replaced the 64×64 (and larger) placeholder node/item textures
with crisp **16×16 hard-edge pixel** versions so block sides, items, and cloud/cage
nodes render at the canonical Minetest/Luanti texture scale without blur or
anti-aliasing.

## What changed

- **`mods/sl_blocks/sky/`** — new `sky` mod in the `sl_blocks` modpack holds the
  sky/cloud nodes (the cloud node no longer lives in `mods/default`). It registers
  `sky:cloud` with a 16×16 transparent cloud silhouette
  (`mods/sl_blocks/sky/textures/cloud.png`, `use_texture_alpha = "clip"`), plus
  aliases `cloud` and `default:cloud` so old worlds keep loading.
- **`mods/content/sl_characters/textures/sl_boxman_neon.png`** — 2×2 placeholder
  upgraded to the intended neon-outlined 16×16 identity-neutral boxman used by the
  player model, spawn markers, and ghost/evil-ghost colorize overlays.
- **`mods/content/sl_mvp_assets/textures/`** — `terminal_texture.png`,
  `door_texture.png`, `platform_texture.png`, and `item_texture.png` now 16×16.
- **`mods/game/sl_modebase/textures/`** — loot crate, monster spawner, objective
  core, and all crafting/salvage/tactical item icons replaced with 16×16 pixel art
  (the previous `sl_objective_core_icon.png` was a 512×512 AI-style image).
- **`mods/content/sl_scary/textures/`** — `hide_spot_top/side/bottom.png` now 16×16.
- **`mods/content/workshops/textures/`** — all 50 workshop node textures regenerated
  as 16×16 tiles (workbench, anvil, assembly table, drawers, lockers, desks, racks,
  server/control panels, vents, pipes, caution tape, warning signs, windows).
- **`mods/sl_blocks/ground/textures/`** — intentionally **not touched**: the neon
  grid/rhombus/x/x2 tiles and opaque plate are existing good art (`square_neon`,
  `rhombus_neon`, `x_neon`, `x2_neon`, `square_neon_opaque`). They are left at
  their original 32×32 size and original saturated palette (neon accents are a
  deliberate special case; the code multiplies/colorizes their near-white base).

## Notes

- **Node textures are mostly white/grey.** Regenerated node faces use a
  black/dark-grey/white-grey palette so per-node `color = ...` and `^[colorize`
  works cleanly; saturated colour is reserved for special surfaces only (the
  existing ground neon tiles and non-node tool/item icons).
- All regenerated images are **16×16 RGBA PNGs** with no gradient smoothing;
  the 16×16 sprite sheets/door/window textures are intentionally left larger where
  the code animates or otherwise expects a multi-frame sheet.
- The generation scripts were run from a **temporary outside-the-repo directory**
  and were **not added** to the repository.

---

# Bloom Bake Pass

A follow-up pass baked a small additive halo into the **bright node-light
textures** that are used with alpha-blend or opaque node faces. The bloom is
distance-limited (about 1–2 px at 16×16) so the hard pixel edges remain crisp
but the light sources pick up a short neon glow.

## Applied to (node lights only)

- `mods/content/sl_mvp_assets/textures/terminal_texture.png`
  (terminal mesh face, `light_source = 8`).
- `mods/game/sl_modebase/textures/` — `sl_monster_spawner.png`,
  `sl_objective_core.png`, `sl_objective_core_icon.png`, `sl_power_cell.png`,
  `sl_blast_shield.png`, `sl_signal_relay.png`, `sl_sensor_array.png`
  (placeable tactical/objective node lights, `light_source` 8–14).

## Not applied

- Tool and item icon textures (`sl_combat_blade.png`, `sl_scrap_metal.png`,
  `sl_circuit_board.png`, flare, medkit, ritual/data-pad icons, etc.) — no
  additional bloom needed on inventory icons.
- Non-light world textures (clouds, hide spots, doors, platforms, etc.).
- Existing `mods/sl_blocks/ground` neon tiles — untouched good art, no bloom bake.
- Stock `mods/default` textures, which stay untouched to avoid changing MTG
  scaffolding wholesale.

---

# Sound Replacement Pass

A follow-up pass replaced **every** `.ogg` in the game with a freshly synthesised,
highly packed set. Run `python3 generate_sounds.py` to reproduce it byte-for-byte.

## What changed

- **108 files** (106 replaced in place + 2 new sounds that code references but were missing):
  `mods/default/sounds/default_tool_break.ogg` (referenced by `sl_modebase`) and
  `mods/apis/sl_gui/sounds/level_up_sound.ogg` (referenced by `sl_gui/player_gui.lua`).
- **Size: 4.27 MB → 0.88 MB total (~4.9× smaller).** One-shots are mono 22050 Hz,
  loops/music mono 16000 Hz (drone loops at ~11 kbps), all Vorbis-encoded at the
  smallest usable quality — most SFX sit within ~1 KB of the ~3.7 KB Ogg header floor.
  Only `alert.ogg` is marginally larger (+102 B) than the previous placeholder; every
  other file shrank.
- **Procedurally synthesised** — filtered noise, resonant metal/wood bodies, FM growls,
  pitch glides, and Schroeder reverb. No external samples, so no licensing concerns.
- All looping sounds (furnace, ambience, music, monster cues, radio static, menu tracks)
  are crossfade-loopable with zero seam click.
- Deterministic: running the script twice produces byte-identical files (seeded per
  file/variant, fixed Ogg serial numbers and CRCs).

---

# Neon Node Texture Pass (2026-08-29)

The previous 16×16 pass flattened nearly every surface to white/grey noise with
glow blobs. This pass replaces the **node** textures with bold, saturated pixel
art (deep charcoal base + one vivid accent per object) and reverts the **entity**
textures to their previous versions. Ground neon tiles and `mods/default` stock
textures remain untouched.

## Clouds — three types (`mods/sl_blocks/sky/`)

- **`sky:cloud`** — *foliage cloud*: plant-like green leaf-clump texture
  (`cloud.png`, clip alpha, breakable `choppy=3`, leaf sounds). Aliases
  `cloud` / `default:cloud` preserved.
- **`sky:cloud_solid`** — *solid cloud*: opaque, **seamless** (tileable) cloud
  texture, **walkable**, **unbreakable** arena structure.
- **`sky:cloud_water`** — *cloud water*: transparent white liquid
  (`liquidtype = "source"`, blend alpha). **Swimmable** (liquid physics +
  `liquid_damping`) but **static** — no `liquid_alternative_flowing`, so it
  never flows or spreads. White-tinted haze, obviously not water.
- **Ambient particles**: a nearby-player-gated ABM emits drifting leaf specks
  (`cloud_leaf_particle.png`) around foliage clouds and slow-rising dust motes
  (`cloud_particle.png`) around solid clouds.

## Node textures (all 16×16 RGBA, hard-edge pixel art)

Design language: deep black/charcoal surfaces, one bold saturated accent per
object, real-world functional colors for symbols — "neon against deep black".

- **`mods/content/workshops/textures/`** (50 files, regenerated):
  wood-top workbench, cyan-grid assembly table, blue blueprint drawer,
  yellow/black **caution tape**, green flask chemical station, cyan-screen
  control panel, blue-steel cabinets/lockers/desks, galvanized pipes with cyan
  flanges, steel anvil, LED-lit server rack, orange/cyan tool rack, vent grate,
  windows (cyan glass, cracked variant).
- **Warning signs now show real-world symbols** (yellow field, black symbol):
  - `warning_sign_hazard.png` — warning triangle with exclamation mark
  - `warning_sign_radiation.png` — radiation trefoil + outer ring
  - `warning_sign_biohazard.png` — interlocking biohazard circles + center ring
  - `warning_sign_back.png` — charcoal plate, steel frame, corner bolts
- **`mods/game/sl_modebase/textures/`** (regenerated where they are node faces):
  orange loot crate, red-eye monster spawner, cyan objective core (+icon),
  yellow power cell with white **lightning bolt**, blue-band blast shield,
  orange-striped barricade, green-antenna signal relay, magenta-lens sensor
  array, `sl_warning_sign.png` (the 384×512 AI image replaced by a 16×16
  hazard triangle), and **new beacon textures** `sl_beacon_a.png` (team-red
  core), `sl_beacon_b.png` (team-blue core), `sl_beacon_destroyed.png` (charred
  with dim embers) — now referenced by `beacon_a` / `beacon_b` /
  `destroyed_beacon` in `nodes.lua` (previously upstream mese/steel/obsidian).
- **`mods/content/sl_mvp_assets/textures/`** node faces: green-screen
  terminal, red-striped door, yellow-safety-edge platform, amber pickup cube.
- **`mods/content/sl_scary/textures/`** `hide_spot_*`: dark panels with a
  faint red glow slit.

## Entity textures — reverted

Per owner decision, entity textures were **restored to their previous
(pre-neon-pass) versions** rather than regenerated:

- `sl_boxman_neon.png` restored to the 2×2 placeholder that all branches
  before the 16×16 pass used (the 16×16 replacement sampled a 3-pixel UV
  strip on the boxman GLB and stretched it over every body part).
- `monster_texture.png`, `player_texture.png`, the scary mob sprite strips,
  `sl_scary_signal_wraith.png`, `scary_mob_texture.png` — verified
  byte-identical to the previous state (they were never changed by the neon
  pass).

## White-bloom neon line-art pass (2026-08-29) — node textures redone

Per owner correction, the bold multi-color fill textures were **replaced** with
the established visual direction: **sharp monochrome vector line art on deep
black** ("neon outlines against deep black", `BRIEF GDD.md`). The glow is not
baked in — lines are snapped to full brightness and the engine's bloom does the
glowing from line brightness.

**Line color policy (owner-confirmed):**
- Lines are **white** by default (white-bloom).
- **Beacons keep their team hue**: `sl_beacon_a` = red, `sl_beacon_b` = blue,
  `sl_beacon_destroyed` = grey.
- **Warning/hazard symbols stay yellow**: hazard triangle, radiation trefoil,
  biohazard, caution tape, and `sl_warning_sign`.

**How they were made:** 10 `generate_image` sprite sheets (3×3 grids of
flat-vector tiles) rendered as monochrome neon line art on black, then each
16×16 texture is cut from its cell and post-processed: downscale → threshold →
snap surviving strokes to full-brightness line color, background crushed to
black (or made transparent for the alpha cloud tiles). Sheets are kept at
`~/.texgen/sheets2/` (outside the repo).

**Alpha cloud tiles** (foliage + cloud water) are line art on **transparent**
background: the near-white cell background is flood-filled out to alpha 0 and
the dark strokes inverted to white, so the cloud reads as white neon leaf/
haze outlines. `cloud.png` = foliage clump (clip alpha), `cloud_water.png` =
white haze (blend, ~140 alpha), `cloud_solid.png` = opaque white puff outline.

Reinstalled on top of the earlier fill textures (same filenames, same 16×16
sizes): all 50 workshop faces, all sl_modebase node faces, the 3 beacon faces,
the sl_mvp_assets faces (terminal, door, platform, pickup), the 3 sl_scary
hide-spot faces, and the 3 sky cloud faces.

### Crash fix + ABM removal (same pass)
- **Sky particle crash fixed.** `mods/sl_blocks/sky/init.lua` called
  `minetest.particles:spawn`, which does not exist in this Luanti build
  (`minetest.particles` is nil → `AsyncErr: attempt to index field 'particles'`).
  Particles are now spawned with `core.add_particlespawner({...})` (the
  documented Luanti API), with a `type(core.add_particlespawner)=="function"`
  guard so the mod degrades to no particles instead of crashing on any build.
- **No ABMs.** The ambient-particle ABM and the `sl_modebase` "Restore Beacons
  in Lobby" ABM were both removed (owner: ABMs are too slow).
  - Cloud particles now come from a low-frequency (2 s) `register_globalstep`
    that samples a small fixed set of cached voxels around each player and
    emits at most one short-lived (2 s) particlespawner per player per tick.
  - Beacon lobby-restore now uses the classic per-node timer API:
    `minetest.get_node_timer(pos):start(5)` in `handle_beacon_destruction`
    plus an `on_timer` callback on the `destroyed_beacon` node definition.
    Node timers are persistent (stored in the mapblock) and only tick while
    the block is loaded; at most 2 destroyed beacons exist at a time, and
    `on_timer` returns false once the node is restored or removed, so the
    timer stops itself. A one-time check of the two known spawn positions
    shortly after load covers pre-existing destroyed beacons without a timer.
