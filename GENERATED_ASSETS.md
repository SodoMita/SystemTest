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

# Neon Texture Pass (default mod)

Every texture in `mods/default/textures/` (241 files) was replaced with
neon-grid style artwork matching the game's visual direction (neon outlines on
deep black, cf. `mods/sl_blocks/ground/textures/*_neon.png`).

- Run `python3 tools/neon_texture_pass.py` — steps: `prompts` (AI sheet
  prompts) -> generate 1024x1024 sheets into `neon_sheets/` (19 sheets, 4x4 or
  3x3 grids of textures upscaled on a strict 16x16 pixel-art lattice) ->
  `process` (split sheets, BOX-downscale each cell by the same power back to
  16x16, key pure black to alpha for transparent sprites) -> `polish`
  (brightness lift for too-dark tiles, hue tint for a few white sprites) ->
  `assemble` (animated strips: water/lava/torch/furnace vertical frames,
  crack_anylength stage stack).
- The `neon_sheets/` working directory is gitignored; the prompts to regenerate
  it are printed by `tools/neon_texture_pass.py prompts`.
- Animated texture dimensions/animation settings in `mods/default/*.lua` are
  unchanged (16 frames water, 8 lava, 16 torch, 8 furnace fire).

## Neon pass v2 (2026-08-28)

- Strict two-tone rule: near-black field + exactly ONE saturated neon hue per
  texture (hue named per prompt), thin 1px neon wireframes, Tron style.
- Semi-transparent textures (`default_water`, `default_river_water`, `glass`,
  `obsidian_glass`) are now generated as a black-plate/white-plate PAIR on one
  sheet (`P01_semis`) and their alpha is TRIANGULATED from the pair:
  `A = 1-(W-B)/255`, `RGB = B/A` — the Seirin final-matting method
  (cf. `SodoMita/Seirin ai_agent_docs/ART_PIPELINE_NEXT.md`).
- Grass/snow/moss/litter side strips are hue-unified to their top textures
  (`unify` step, circular-mean hue).
- Chests regenerated from a dedicated 2x2 sheet (amber neon + cyan latch).
- `crack_anylength.png` is drawn procedurally: bright neon cracks with real
  alpha, visible over translucent glass.
- Torch animation uses ONE sprite with flame-only flicker (same torch, same
  color every frame); water animation is a roll of the single triangulated
  texture.
- Glass panes: thin 1px neon frame + diagonal streak redrawn procedurally,
  color from the triangulated plates.

## Ground-family coherence pass (2026-08-28, v2.1)

- `default_permafrost.png` + `default_moss_side.png` restored to the v1 look
  (the `permafrost^moss_side` composite node).
- `default_dirt.png` rebuilt: single-hue warm near-black soil, dim amber specks.
- `default_grass` / `default_dry_grass` tops rebuilt: full-coverage neon blade
  grids (no bare margins, no frames), hue-identical to their side strips.
- `default_grass_side` / `default_dry_grass_side` / `default_snow_side` are now
  TRANSPARENT strip overlays (top 2 rows + hanging blades). The engine already
  composites them over `default_dirt.png` (`dirt.png^side.png`), so the soil
  part of every grass/dry/snow node now matches `default:dirt` exactly by
  construction.
- Reproduce with `python3 tools/neon_texture_pass.py cohere`.

## Special-dirt coherence (2026-08-28, v2.2)

All remaining `dirt ^ overlay` ground nodes rebuilt procedurally
(`tools/neon_texture_pass.py cohere`):
- `default:dry_dirt` (savanna): warm near-black base + orange neon crack walks.
- `dirt_with_rainforest_litter` / `dirt_with_coniferous_litter`: litter tops on
  the shared soil base; sides are transparent neon fringes so the engine
  composite (`dirt.png^..._side.png`) shows the real dirt.
- `permafrost_with_stones`: `default_stones.png` / `default_stones_side.png`
  are transparent pale-blue pebble outlines composited over permafrost.

## Tool icons v3 — fully procedural (2026-08-28)

All 24 `default_tool_*.png` are now drawn by `tools/neon_tools.py` (no AI
generation): one pixel-map per archetype (sword / pickaxe / axe / shovel),
one palette per material (wood / stone / steel / bronze / mese / diamond).
Strict 4-color palette per icon: material bright line + dim halo (~40%) +
near-black handle + amber pommel/grip accent. Preview maps with
`python3 tools/neon_tools.py --preview`.
