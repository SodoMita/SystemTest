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

- **`mods/default/textures/default_cloud.png`** — the previous file was a solid
  16×16 white tile, so `default:cloud` looked like a white cuboid. Replaced with a
  transparent white/pale-blue cloud silhouette and set `use_texture_alpha = "clip"`
  on the node so the cloud reads as fluff, not a solid block.
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
- **`mods/sl_blocks/ground/textures/`** — `square_neon.png`, `rhombus_neon.png`,
  `x_neon.png`, `x2_neon.png`, and `square_neon_opaque.png` now 16×16 hard-edge
  neon tiles (previously 32×32 or larger).

## Notes

- All regenerated images are **16×16 RGBA PNGs** with no gradient smoothing;
  the 16×16 sprite sheets/door/window textures are intentionally left larger where
  the code animates or otherwise expects a multi-frame sheet.
- The generation scripts were run from a **temporary outside-the-repo directory**
  and were **not added** to the repository.

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
