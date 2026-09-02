# Generated Missing Assets

This asset pass was generated procedurally for prototype use.  It fills missing media references found in the repository and the MVP list in `NEEDED ASSETS.md`.

## Added

- `mods/content/sl_mvp_assets/` — MVP placeholder models (`player.obj`, `monster.obj`, `platform.obj`, `terminal.obj`, `door.obj`, `hatch.obj`, `item.obj`, `item_pickup.obj`, `pulse.obj`, `scanner_pulse.obj`, `flare_light.obj`, `particle.obj`, `death_particle.obj`), textures/UI (`neon_cube.png`, `cursor.png`, `hud.png`, `hud_frame.png`, `font.png`, model textures), and OGG sounds (`ambience`, `music`, footsteps, alerts, monster cues, radio static, etc.).
- `mods/content/sl_clothing/textures/` — inventory icons for all clothing items.
- `mods/content/sl_clothing/models/` — valid B3D stand-ins for clothing/accessory model names.
- `mods/content/workshops/textures/` — workshop/furniture/lab/sign/window node textures listed in the workshop prototype.
- `mods/content/sl_scary/textures/` and `mods/content/sl_scary/sounds/` — hide spot textures plus `scary_attack.ogg`, `mob_idle.ogg`, and `mob_death.ogg`.
- **New high-tech horror mobs** (see `mods/content/sl_scary/init.lua` for full registration). All mobs follow a strict **3-color palette** rule: pure black silhouette + 1-2 accent colors (neon when multiple):
  - **`sl_scary:dredger`** — Corrupted maintenance worker (Kowalski). Patrols routes, stops to "fix" nearby interactable nodes, attacks when interrupted. Drops `sl_scary:dredger_badge` (lore item). **Animated sprite strip** (`sl_scary_dredger_strip.png`, 256×768 vertical, 3 frames of 256×256): one 3-frame alive loop (idle/stride/sway — all states replay it at different speeds; death freezes). Palette: dark rust-grey panels with rust-orange (#CC6622) plating + neon-green (#00FF41) visor crack & chest LEDs, in the boxman neon wire-glow style.
  - **`sl_scary:signal_wraith`** — Ghost data trapped in the signal layer. Non-physical (phases through walls), drifts between glitch-teleports, corrupts players with screen-shake on hit. Drops `sl_scary:corrupted_data` (information item, unreliable). **Animated sprite strip** (`sl_scary_wraith_strip.png`, 256×768 vertical, 3 frames of 256×256): one 3-frame alive loop (idle/stride/sway — all states replay it at different speeds; death freezes). Palette: dark void-purple (#1A0033) panels with neon-cyan (#00FFFF) wire-glow outline, eyes and data shards, in the boxman neon wire-glow style.
  - **`sl_scary:containment`** — Bio-mechanical horror sealed in Section 12. Dormant until a player enters its 5-node wake range. Slow, devastating (10 dmg), stunned after each attack. Drops `sl_scary:containment_shard` (lore + proof). **Animated sprite strip** (`sl_scary_containment_strip.png`, 256×768 vertical, 3 frames of 256×256): one 3-frame alive loop (idle/stride/sway — all states replay it at different speeds; death freezes). Palette: near-black armour slabs with deep-crimson (#8B0000) flesh patches + neon-amber (#FFBF00) maw and sensor eyes, in the boxman neon wire-glow style.
  - **Sprite pipeline** (`mods/content/sl_scary/pipeline/`): the old Seirin C toolchain (from `SodoMita/Seirin/tools/img_pipeline`, kept on branch `arena/01a0436b-systemtest`) is superseded.
    - `transpose_sprite_strip.py` — stdlib PNG reader/transposer; still used as the shared PNG reader by the pipeline scripts.
    - `process_sprite.py` — post-processes AI sticker frames (white-key → halo cleanup → 256px cell normalisation) and stacks them into the vertical strip.
    - Workflow (owner 2026-09-03): generate 3 sticker-style frames per mob (256px+ AI art; white-key background) in the visual style of the boxman neon render (`docs/art_baseline/boxman_style_render.png` — dark tinted panels + bright neon rim) → post-process and stack vertically with `mods/content/sl_scary/pipeline/process_sprite.py` (white key, halo cleanup, 256px-cell normalisation). Luanti's sprite animation (`object:set_sprite`) iterates frames along the *y* axis only, so the strip is **vertical** with `spritediv = {x=1, y=3}` (3 frames/sheet, per the owner; a horizontal strip renders as one undivided sheet).
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
