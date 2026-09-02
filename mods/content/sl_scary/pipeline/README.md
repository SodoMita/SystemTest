# Mobs: 3-frame hi-res sprite strips (current pipeline)

The `sl_scary` mobs (`sl_scary:dredger`, `sl_scary:signal_wraith`,
`sl_scary:containment`) are **flat sprite billboards**, so hi-res art is
safe (no UV mapping; owner art gate 2026-09-02: the no-blur/no-AA rule
is UI-only and 3D-model textures are not AI-swappable — sprites are
neither).

## Layout: one 3-frame loop per sheet, VERTICAL

Luanti plays `sprite` visuals with `object:set_sprite(...)`, iterating
frames along the frame **y** position (`lua_api.md` -> `set_sprite`;
engine `content_cao.cpp`: "Animation goes downwards"). The strips are
therefore **vertical** with `spritediv = {x=1, y=3}` (256×768, three
256×256 frames):

- row 0 = idle / neutral pose
- row 1 = mid-stride / sway / lurch
- row 2 = return pose (opposite stride / sway back)

All alive states (idle/walk/attack) replay the same loop at different
speeds (`sl_scary/init.lua` -> `sprite_animations`); death freezes the
last frame. A horizontal strip would render as one undivided sheet —
never ship one.

## Regenerating the art

1. Generate three sticker-style frames per mob (AI, ~1024px, plain
   near-white background, frame 0 in the style of
   `docs/art_baseline/boxman_style_render.png` — dark tinted boxy panels
   + neon rim; frames 1-2 with the previous frame as the character
   reference, posing the walk/sway cycle). Keep colors/species per mob
   (palettes are in `GENERATED_ASSETS.md`).
2. `python3 pipeline/process_sprite.py 256 ../textures/sl_scary_X_strip.png genwork/ref.png f0.png f1.png f2.png`
   — keys the white background, cleans the AA halo, normalizes every
   frame to 256px cells (same centre, same height) and stacks them into
   the final vertical strip.
3. Keep the frame order (idle, mid, return). The Lua table and the
   `^[verticalframe:3:0` loot icons assume it.

## Scripts

- `process_sprite.py` — white-key + normalize + vertical strip builder.
- `transpose_sprite_strip.py` — stdlib PNG read/write + the old 16px
  horizontal→vertical transposer. The PNG reader is shared by the
  pipeline (and by the docs' palette scripts).
- `reink_mobs.py` — **removed.** It belonged to the superseded 16px
  re-ink stage (rev C, 64×576 9-frame sheets) that the owner's
  3-frame hi-res request replaced. History: commit `c819070`.
