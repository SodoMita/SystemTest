# Mobs: 9-frame hi-res sprite sheets (current pipeline)

The `sl_scary` mobs (`sl_scary:dredger`, `sl_scary:signal_wraith`,
`sl_scary:containment`) are **flat sprite billboards**, so hi-res art is
safe (no UV mapping; owner art gate 2026-09-02: the no-blur/no-AA rule
is UI-only and 3D-model textures are not AI-swappable — sprites are
neither).

## Layout: 9-frame sheets, VERTICAL

Owner layout (2026-09-03): each sheet carries **FRONT, BACK, SIDE,
WALK×3, ATTACK×2, DEATH** = 9 frames of 256×256, stacked vertically to
256×2304:

- row 0 FRONT (idle pose 1)
- row 1 BACK (idle pose 2)
- row 2 SIDE (idle pose 3)
- rows 3-5 WALK cycle
- rows 6-7 ATTACK pair
- row 8 DEATH

Luanti plays `sprite` visuals with `object:set_sprite(...)`, iterating
frames along the frame **y** position (`lua_api.md` -> `set_sprite`;
engine `content_cao.cpp`: "Animation goes downwards"). The strip is
therefore **vertical** with `spritediv = {x=1, y=9}`. A horizontal
strip would render as one undivided sheet — never ship one.

State mapping in `sl_scary/init.lua` (`sprite_animations`): idle slowly
cycles FRONT→BACK→SIDE (a scanning turn), chase plays the walk cycle,
close combat the 2-frame attack, death freezes on the last frame. Loot
icons crop the front frame with `^[verticalframe:9:0`.

## Regenerating the art

1. Generate the poses as AI sticker art (plain near-white background,
   style = `docs/art_baseline/boxman_style_render.png`: dark tinted
   boxy panels + neon rim; per-mob palettes in `GENERATED_ASSETS.md`).
   Frame 0 can be reused from an earlier sheet; generate BACK+SIDE as a
   2-panel image and WALK×3 / ATTACK×2 as multi-panel images (the
   builder slices panels on the white gaps).
2. `python3 pipeline/build_mob_sheet.py OUT_SHEET PREVIEW SRC[:PANELS]x9`
   — e.g.
   `python3 pipeline/build_mob_sheet.py \
       ../textures/sl_scary_X_strip.png /tmp/row0.png \
       front.png:1 back_side.png:2 walk3.png:3 atk2.png:2 death.png:1`
   Each source's panels are white-keyed, halo-cleaned, trimmed and
   normalised into 256px cells, then stacked vertically in row order.
3. Keep the row order — `sprite_animations` and the `^[verticalframe:9:0`
   loot icons assume it. Verify file size < 1 MB/asset.

## Scripts

- `build_mob_sheet.py` — panel slicing + keying + 9-row vertical sheet.
- `process_sprite.py` — white-key + halo cleanup + 256px cell
  normalisation (used per frame; kept for the single-frame case).
- `transpose_sprite_strip.py` — stdlib PNG read/write; shared reader.
- `render_boxman_ref.py` — software render of `SimpleOutlinedBoxman.glb`
  (geometry + animation pose + material texture sampling + neon rim)
  that produced the style reference `docs/art_baseline/boxman_style_render.png`.
- `reink_mobs.py` — **removed.** It belonged to the superseded 16px
  re-ink stage (rev C). History: commit `c819070`.
