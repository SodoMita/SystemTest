# Generated Missing Assets

This asset pass was generated procedurally for prototype use.  It fills missing media references found in the repository and the MVP list in `NEEDED ASSETS.md`.

## Added

- `mods/content/sl_mvp_assets/` — MVP placeholder models (`player.obj`, `monster.obj`, `platform.obj`, `terminal.obj`, `door.obj`, `hatch.obj`, `item.obj`, `item_pickup.obj`, `pulse.obj`, `scanner_pulse.obj`, `flare_light.obj`, `particle.obj`, `death_particle.obj`), textures/UI (`neon_cube.png`, `cursor.png`, `hud.png`, `hud_frame.png`, `font.png`, model textures), and OGG sounds (`ambience`, `music`, footsteps, alerts, monster cues, radio static, etc.).
- `mods/content/sl_clothing/textures/` — inventory icons for all clothing items.
- `mods/content/sl_clothing/models/` — valid B3D stand-ins for clothing/accessory model names.
- `mods/content/workshops/textures/` — workshop/furniture/lab/sign/window node textures listed in the workshop prototype.
- `mods/content/sl_scary/textures/` and `mods/content/sl_scary/sounds/` — hide spot textures plus `scary_attack.ogg`, `mob_idle.ogg`, and `mob_death.ogg`.
- `mods/apis/sl_gui/sounds/` — `achievement_unlock.ogg` and `level_up.ogg`.
- `mods/content/dark_skybox/sounds/` — `creepy_ambient.ogg` for the optional dark-skybox ambience hook.
- `mods/sl_blocks/ground/textures/` — white/rainbow noise animated and still textures.
- `menu/` — `header.png`, `background.png`, and `menu_music.ogg` for Luanti-compatible menu branding/audio.

## Notes

These are intentionally lightweight placeholders: suitable for loading the game and testing gameplay loops, not final production art. Replace files in place as final assets become available.

## Sound pass (2026-08-27)

All 106 `.ogg` files in the game are now generated procedurally by
`generate_sound_assets.py` — no third-party default audio remains. The set covers
`mods/default/sounds` (footsteps, digs, dug/place, glass, tools, chests, lava,
furnace, smoke, player damage), `mods/content/sl_mvp_assets/sounds`,
`mods/content/sl_scary/sounds`, `mods/content/dark_skybox/sounds`,
`mods/apis/sl_gui/sounds`, and `menu/`.

Encoding targets small download size: mono, 22.05 kHz for one-shots and 16 kHz for
long beds, Vorbis at a low quality target, peak-normalised with anti-click fades and
seamless cross-faded loops for ambience/music. Whole set is ~800 KiB (~7.6 KiB avg,
down from ~3.4 MB). Regenerate deterministically with:

    python3 generate_sound_assets.py
