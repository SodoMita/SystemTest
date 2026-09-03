# Mobs: 9-frame hi-res sprite sheets (current pipeline)

The `sl_scary` mobs (`sl_scary:dredger`, `sl_scary:signal_wraith`,
`sl_scary:containment`) are **flat sprite billboards**, so hi-res art is
safe (no UV mapping; owner art gate 2026-09-02: the no-blur/no-AA rule
is UI-only and 3D-model textures are not AI-swappable — sprites are
neither).

## Layout: 9-frame sheets, VERTICAL, Doom-style FRONT-facing

Owner layout (2026-09-03): each sheet carries **FRONT, BACK, SIDE,
WALK×3, ATTACK×2, DEATH** = 9 frames of 256×256, stacked vertically to
256×2304:

- row 0 FRONT (idle pose 1)
- row 1 BACK (idle pose 2)
- row 2 SIDE (idle pose 3)
- rows 3-5 WALK cycle
- rows 6-7 ATTACK pair
- row 8 DEATH

The mob is a camera-facing billboard (**used like a Doom monster, NOT a
sidescroller**): even the WALK rows and ATTACK rows are drawn
**FRONT-facing** — the creature advances/lunges toward the camera.
Do not generate sidescroller side-profile locomotion frames.

Luanti plays `sprite` visuals with `object:set_sprite(...)`, iterating
frames along the frame **y** position (`lua_api.md` -> `set_sprite`;
engine `content_cao.cpp`: "Animation goes downwards"). The strip is
therefore **vertical** with `spritediv = {x=1, y=9}`. A horizontal
strip would render as one undivided sheet — never ship one.

State mapping in `sl_scary/init.lua` (`sprite_animations`): idle slowly
cycles FRONT→BACK→SIDE (a scanning turn), chase plays the walk cycle,
close combat the 2-frame attack, death freezes on the last frame. Loot
icons crop the front frame with `^[verticalframe:9:0`.

## Art direction (owner 2026-09-03, supersedes the boxman style)

- **Realistic, dark-horror, NOT cartoon.** Ask explicitly to negate
  everything 2D-stylized/cartoon related (no cel shading, no outlines,
  no exaggerated proportions, no clean comic silhouettes, no sticker
  look).
- **Body interior = one single flat colour** per mob (near-black fills,
  listed in `matte_sheet.py` `FILL`). Effects (rim light, glows, data
  shards, fog/blood spatter) are kept.
- **Bright neon rim + scary effects are KEPT** (owner: "keep neon") so
  the dark silhouette reads in-game. Per-mob rim/eye colours in
  `GENERATED_ASSETS.md`.
- Never put black text or borders inside the art; no watermark.
- Per-mob generation prompts must describe an **actual creature**, not a
  wireframe/box figure.

## Regenerating the art (realistic render → two-bg alpha → neonize)

Owner workflow (2026-09-03 rev G): **generate realistic pictures WITHOUT
neon, then turn them into neon flatcolored.** The AI is only asked for
photorealistic creatures on plain backgrounds (no neon/flat/outline
constraints — those were what made earlier attempts look cartoonish);
`matte_sheet.py` applies the neon-flat look deterministically.

1. Generate a **3×3 black grid** per mob — ask for a SQUARE image (the
   generator otherwise sometimes drops to 2 rows). Cell backgrounds: one
   flat very dark near-black (#0D0D0F) — pure #000000 makes the model
   lighten the canvas. Grid lines + outer border: pure black. Strict
   framing, exact poses per row (FRONT/BACK/SIDE / WALK×3 / ATTACK×2 /
   DEATH — all FRONT-facing except the labelled BACK/SIDE idle poses).
   No floor/shadow/pedestal; exactly one figure per cell.
2. Generate the **white twin** from the black grid as reference:
   "only the cell interiors flip to white; grid lines and border stay
   pure black". 
3. Optionally ask for a bottom margin **text verdict** strip
   (WALKOK/WALKRETRY or a short realism self-critique). It sits below
   the outer border; `matte_sheet.py` detects the border and never
   crops that strip into a cell.
4. `python3 matte_sheet.py BLACK_GRID WHITE_GRID OUT_SHEET MOB`
   — the white twin is the layout authority (its cell interiors are near
   white so only the grid lines are black); cells are sliced inside the
   outer border; per cell the alpha is solved by triangulation from the
   two backgrounds, then the cell is **neonized**: interior flattened to
   the single fill colour, bright saturated features recoloured to the
   mob's neon accents, a crisp neon rim + soft glow stroked around the
   silhouette, and low-alpha wisp/glow pixels tinted with the rim colour
   (palette in `MOB_STYLE`, no regeneration needed to tweak it).
5. Keep the row order — `sprite_animations` and the `^[verticalframe:9:0`
   loot icons assume it. Verify file size < 1 MB/asset.

## Walk strips (owner rev I, 2026-09-03)

The ground mobs' walk rows are produced as **dedicated 1×3 strips** so
the stride can be directed precisely (the 3×3 grids read as "bad walk"
poses). `python3 walk_sheet.py BLACK_STRIP WHITE_STRIP WALK3_OUT MOB`
slices a one-row/three-cell strip (border + two gutters detected on the
white twin), triangulates + neonizes each cell, and writes 3 rows
(256×768); `walk_sheet.py --splice SHEET9 WALK3 OUT` replaces rows 3-5
of the 9-row sheet. The wraith has **no walk frames**: it chases on one
static FRONT frame (`glide` state) and floats via a code wobble
(`apply_wobble` in `init.lua`).

## Scripts

- `matte_sheet.py` — the current builder: 3×3 grid slicing (border-aware
  on the white twin), per-cell two-background alpha triangulation,
  single-colour flatten, normalisation, 9-row vertical stack.
- `walk_sheet.py` — dedicated 1×3 walk-strip matting + splice helper.
- `build_mob_sheet.py` — **superseded** white-key panel builder; kept
  only for reference/history. Do not use for new art.
- `process_sprite.py` — white-key + halo cleanup + 256px cell
  normalisation (kept for the single-frame case).
- `transpose_sprite_strip.py` — stdlib PNG read/write; shared reader.
- `render_boxman_ref.py` — historical software render of the old
  `SimpleOutlinedBoxman.glb` boxman style reference. **Not used** for
  the current rev F art (boxman style is superseded).
- `reink_mobs.py` — **removed.** It belonged to the superseded 16px
  re-ink stage (rev C). History: commit `c819070`.
