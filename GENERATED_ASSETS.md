# Generated Missing Assets

This asset pass was generated procedurally for prototype use.  It fills missing media references found in the repository and the MVP list in `NEEDED ASSETS.md`.

## Added

- `mods/content/sl_mvp_assets/` — MVP placeholder models (`player.obj`, `monster.obj`, `platform.obj`, `terminal.obj`, `door.obj`, `hatch.obj`, `item.obj`, `item_pickup.obj`, `pulse.obj`, `scanner_pulse.obj`, `flare_light.obj`, `particle.obj`, `death_particle.obj`), textures/UI (`neon_cube.png`, `cursor.png`, `hud.png`, `hud_frame.png`, `font.png`, model textures), and OGG sounds (`ambience`, `music`, footsteps, alerts, monster cues, radio static, etc.).
- `mods/content/sl_clothing/textures/` — inventory icons for all clothing items.
- `mods/content/sl_clothing/models/` — valid B3D stand-ins for clothing/accessory model names.
- `mods/content/workshops/textures/` — workshop/furniture/lab/sign/window node textures listed in the workshop prototype.
- `mods/content/sl_scary/textures/` and `mods/content/sl_scary/sounds/` — hide spot textures plus `scary_attack.ogg`, `mob_idle.ogg`, and `mob_death.ogg`.
- **New high-tech horror mobs** (see `mods/content/sl_scary/init.lua` for full registration). Art direction (owner 2026-09-03): **realistic dark-horror silhouettes — NOT cartoon** (no cel shading, no outlines, no sticker look); body interior is **one single flat colour**; **bright neon rim + scary effects kept** so the silhouette reads in-game. The mobs are camera-facing billboards — **used like Doom monsters, not sidescrollers**, so walk/attack rows are FRONT-facing:
  - **`sl_scary:dredger`** — Corrupted maintenance worker (Kowalski). Patrols routes, stops to "fix" nearby interactable nodes, attacks when interrupted. Drops `sl_scary:dredger_badge` (lore item). **Animated sprite strip** (`sl_scary_dredger_strip.png`, 256×2304 vertical, 9 frames of 256×256): FRONT / BACK / SIDE idle-turn poses, WALK×3 cycle, ATTACK×2 wrench lunge, DEATH collapse. Palette: near-black body fill with a rust-amber (#CC6622) neon rim + neon-green (#00FF41) visor crack & chest LEDs. The WALK×3 rows are a **dedicated front-facing stride strip** (owner rev I: walk frames were bad) — see `pipeline/walk_sheet.py`; watch `docs/art_baseline/walk_dredger.gif`.
  - **`sl_scary:signal_wraith`** — Ghost data trapped in the signal layer. Non-physical (phases through walls), drifts between glitch-teleports, corrupts players with screen-shake on hit. Drops `sl_scary:corrupted_data` (information item, unreliable). **Animated sprite strip** (`sl_scary_wraith_strip.png`, 256×2304 vertical, 9 frames of 256×256): FRONT / BACK / SIDE hovering poses, static glide frame, ATTACK×2 data-corruption burst, DEATH dissolve. Palette: near-black violet body fill with neon-cyan (#00FFFF) rim, eyes and data shards. The wraith has **no walk frames** (owner rev I: "use static image, but use effect to wobble that image"): chase uses the static FRONT frame (`glide` state) and `init.lua`'s `apply_wobble` adds a sinusoidal vertical float.
  - **`sl_scary:containment`** — Bio-mechanical horror sealed in Section 12. Dormant until a player enters its 5-node wake range. Slow, devastating (10 dmg), stunned after each attack. Drops `sl_scary:containment_shard` (lore + proof). **Animated sprite strip** (`sl_scary_containment_strip.png`, 256×2304 vertical, 9 frames of 256×256): FRONT / BACK / SIDE looming poses, WALK×3 heavy lurch, ATTACK×2 claw slam, DEATH collapse. Palette: near-black body fill with neon-amber (#FFBF00) rim, maw and sensor eyes. The WALK×3 rows are a **dedicated front-facing lurch strip** (owner rev I); watch `docs/art_baseline/walk_containment.gif`.
  - **Sprite pipeline** (`mods/content/sl_scary/pipeline/`): the old Seirin C toolchain (from `SodoMita/Seirin/tools/img_pipeline`, kept on branch `arena/01a0436b-systemtest`) is superseded.
    - `transpose_sprite_strip.py` — stdlib PNG reader/transposer; still used as the shared PNG reader by the pipeline scripts.
    - `process_sprite.py` — white-key + halo cleanup + 256px cell normalisation for individual frames (legacy single-frame helper).
    - `matte_sheet.py` — **current builder**: 3×3 grid slicing (border-aware on the white twin), per-cell two-background alpha triangulation, single-colour flatten, 9-row vertical stack.
    - `build_mob_sheet.py` — superseded white-key panel builder; kept only for reference/history.
    - Workflow (owner 2026-09-03, rev G, then rev I): **generate realistic pictures WITHOUT neon** — each mob is generated as a **black 3×3 grid** (square image; cell background flat near-black #0D0D0F, grid lines + outer border pure black; photorealistic creature, no floor/shadow; FRONT/BACK/SIDE idle row, FRONT-facing WALK×3, ATTACK×2, DEATH), then its **white twin** (only cell interiors flip to white; grid lines/border stay pure black) → `matte_sheet.py` slices the cells inside the outer border (an optional bottom text-verdict strip such as WALKOK/WALKRETRY is cropped out), alpha-solves each cell from the **two backgrounds** (triangulation, not white-key), then **neonizes**: flattens the interior to one single flat colour, recolours bright features to the mob's neon accents, strokes a neon rim + glow around the silhouette (palette in `MOB_STYLE`) → 256px cells stacked vertically to 256×2304. Luanti's sprite animation (`object:set_sprite`) iterates frames along the *y* axis only, so the strip is **vertical** with `spritediv = {x=1, y=9}`; a horizontal strip renders as one undivided sheet. **Rev I (owner: "Walk animations are bad"):** the WALK×3 rows are generated separately as dedicated **1×3 front-facing walk strips** (`pipeline/walk_sheet.py`, spliced into rows 3–5), and the wraith uses a **static FRONT frame + code float** instead of walk frames.
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
