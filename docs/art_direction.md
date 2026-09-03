# sl_scary mob art — rev F+ direction & generation spec (owner 2026-09-03)

Live working spec for the `sl_scary` mob sprite sheets. Supersedes the
boxman wire-glow style (`docs/art_baseline/boxman_style_render.png`) for
mob art. Owner decisions below are verbatim-captured.

## Owner rulings (verbatim quotes, 2026-09-03)

- "Still cartoons instead of realism." (target: previous grids)
- "my answers vanished due arena.ai bug. Sighouette realistic. Fill is
  singlecolor. Very scary with effects."
- "keep neon. but ask to negate everything 2d stylized cartoon related"
- "Say that is to be used like doom, not sidescroller, so walk is
  exactly front side." (mobs are camera-facing billboards → WALK and
  ATTACK rows are drawn FRONT-facing, like a Doom monster advancing)
- Earlier: "They dont fit neon style, not scary, didnt use triangulation
  for alpha, like doc say."
- Earlier: "Wraith all broken because you didn't ask white grid borders
  with pitch black bg."
- "you can ask text annotation on the side of image saying if animation
  frames appeared good or not usable ... or ask on next image gen call
  to selfcriticise"

## Locked rules

1. **Realism, not cartoon.** Every prompt must explicitly negate
   2D-stylized/cartoon: "NOT cartoon, no cel shading, no black outlines,
   no sticker look, no exaggerated cartoon proportions, no comic
   silhouette, no anime." Ask for "realistic dark horror graphic".
2. **Single flat body colour.** Interior fill is one colour per mob
   (see `matte_sheet.py` `FILL`). Effects (rim light, glows, shards,
   spatter, fog) may be added — they are part of "very scary with
   effects".
3. **Keep neon.** Bright neon rim/eyes/effects stay — the owner said
   "keep neon" — but the figure itself must read as a realistic
   creature, not a wire-glow box.
4. **Two-background alpha triangulation** (docs workflow, not white-key):
   - black 3×3 grid: cell bg flat **near-black #0D0D0F** (NOT pure
     #000000 — the model lightens pure-black canvases for very dark
     subjects), grid lines + outer border **pure black #000000**;
   - white twin: generate from the black grid as reference, "only the
     cell interiors flip to white; grid lines and outer border REMAIN
     pure black". Verify per-cell bg-fraction before matting.
5. **Doom-style facing.** Row 0 FRONT, row 1 BACK, row 2 SIDE are the
   idle "scanning turn" trio. Rows 3-5 WALK×3 and rows 6-7 ATTACK×2 are
   **FRONT-facing** (advancing/lunging toward camera). Never draw
   sidescroller side-profile locomotion. Wraith's WALK is a simple glide
   (owner: "hopefully not complex"); the other two mobs may have a more
   specified front-facing lurch/stride.
6. **One figure per cell.** No duplicates/mirrors/echoes — wraith came
   back doubled previously.
7. **Annotation strip.** Optional bottom margin text line, outside the
   grid's black border: `WALKOK` / `WALKRETRY`, or a short realism /
   readability self-critique. The matte pipeline detects the outer
   border and crops the strip out; it never enters a cell.
8. **No black text/borders inside the art cells; no watermark.**
9. Layout stays **9-frame vertical 256×2304**, `spritediv {x=1,y=9}`,
   row order FRONT/BACK/SIDE/WALK×3/ATTACK×2/DEATH (unchanged from
   rev E; `init.lua` mapping untouched).

## Per-mob specifics

| mob | figure | body fill (flat) | rim/eyes (neon, kept) |
|---|---|---|---|
| dredger | corrupted ex-maintenance worker, hunched, metal-plated corpse, worn visor | near-black charcoal `#0B0C0E`-ish | rust-amber `#CC6622` rim + neon-green `#00FF41` visor crack/chest LEDs |
| wraith | tall thin signal ghost, tattered wisps, two eye slashes | very dark violet `#07040E` | neon-cyan `#00FFFF` rim + eyes + data shards |
| containment | colossal hunched bio-mechanical horror, maw, many sensor eyes | near-black `#080604` | neon-amber `#FFBF00` rim + maw + sensor eyes |

## Next execution (rev F re-render batch)

Per mob, in order:
1. Black grid (3×3, near-black #0D0D0F cells, pure-black gutters/border,
   exact FRONT/BACK/SIDE + FRONT-facing WALK×3/ATTACK×2 + DEATH poses,
   bottom margin verdict strip). Wraith first — regenerated from scratch
   to kill the doubled-figure bug; dredger/containment reuse the current
   v2/v3 framing.
2. White twin (from black ref; gutters stay pure black).
3. Run `.art` per-cell diagnostics (bgFrac, cluster count) before matting.
4. `matte_sheet.py` → textures; verify coverage + <1 MB; commit.
5. Owner eyeball gate on the real preview (not ASCII).
