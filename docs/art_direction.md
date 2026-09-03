# sl_scary mob art — rev G direction & generation spec (owner 2026-09-03)

Live working spec for the `sl_scary` mob sprite sheets. Supersedes the
boxman wire-glow style (`docs/art_baseline/boxman_style_render.png`) for
mob art. Owner decisions below are verbatim-captured.

## Owner rulings (verbatim quotes, 2026-09-03)

- "Still cartoons instead of realism." (target: previous grids)
- "my answers vanished due arena.ai bug. Sighouette realistic. Fill is
  singlecolor. Very scary with effects."
- "keep neon. but ask to negate everything 2d stylized cartoon related"
- **"You can generate realistic pics without neon, then turn into neon
  flatcolored."** ← the current workflow (rev G): the AI is asked ONLY
  for photorealistic creatures (no neon/flat constraints, which were
  pulling the output toward "cartoon"); the neon-flat look is applied
  deterministically afterwards by `matte_sheet.py` (single flat fill +
  neon rim/glow + accent recolouring of bright features).
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

1. **Generate realistic, WITHOUT neon** (owner rev G). The AI prompt
   asks only for a photorealistic creature on a plain background; it
   must still negate 2D-stylized/cartoon ("no cartoon, no cel shading,
   no black outlines, no sticker look, no comic silhouette, no anime")
   because those styles are not "realism" either. Interior texture,
   lighting and material detail are WANTED here — the flat/neon stage is
   done in code.
2. **The neon-flat look is applied by `matte_sheet.py`**, never asked of
   the AI:
   - body interior → one single flat colour per mob (`MOB_STYLE.fill`);
   - silhouette rim → crisp 2px neon ring + soft blurred glow in the
     mob's `rim` colour;
   - bright saturated features (eyes/visor/maw/glints) → recoloured to
     the mob's `accents` palette by hue proximity;
   - soft low-alpha pixels (AA, wisps, small glows) → `rim` colour at
     low alpha (keeps "very scary with effects").
3. **Two-background alpha triangulation** (docs workflow, not white-key):
   - black 3×3 grid: cell bg flat **near-black #0D0D0F** (NOT pure
     #000000 — the model lightens pure-black canvases for very dark
     subjects), grid lines + outer border **pure black #000000**;
   - white twin: generate from the black grid as reference, "only the
     cell interiors flip to white; grid lines and outer border REMAIN
     pure black". Verify grid bounds before matting.
   - Ask for a **square image** when generating the black grid — the
     generator otherwise tends to emit a 2-row wide grid (observed on
     the wraith) and drop the 3-row layout.
4. **Doom-style facing.** Row 0 FRONT, row 1 BACK, row 2 SIDE are the
   idle "scanning turn" trio. Rows 3-5 WALK×3 and rows 6-7 ATTACK×2 are
   **FRONT-facing** (advancing/lunging toward camera). Never draw
   sidescroller side-profile locomotion. Wraith's WALK is a simple glide
   (owner: "hopefully not complex"); the other two mobs may have a more
   specified front-facing lurch/stride.
5. **One figure per cell.** No duplicates/mirrors/echoes — wraith came
   back doubled previously.
6. **Annotation strip.** Optional bottom margin text line, outside the
   grid's black border: `WALKOK` / `WALKRETRY`, or a short realism /
   readability self-critique. The matte pipeline detects the outer
   border and crops the strip out; it never enters a cell.
7. **No black text/borders inside the art cells; no watermark.**
8. Layout stays **9-frame vertical 256×2304**, `spritediv {x=1,y=9}`,
   row order FRONT/BACK/SIDE/WALK×3/ATTACK×2/DEATH (unchanged from
   rev E; `init.lua` mapping untouched).

## Per-mob specifics

| mob | figure | body fill (flat) | rim/eyes (neon, kept) |
|---|---|---|---|
| dredger | corrupted ex-maintenance worker, hunched, metal-plated corpse, worn visor | near-black charcoal `#0B0C0E`-ish | rust-amber `#CC6622` rim + neon-green `#00FF41` visor crack/chest LEDs |
| wraith | tall thin signal ghost, tattered wisps, two eye slashes | very dark violet `#07040E` | neon-cyan `#00FFFF` rim + eyes + data shards |
| containment | colossal hunched bio-mechanical horror, maw, many sensor eyes | near-black `#080604` | neon-amber `#FFBF00` rim + maw + sensor eyes |

## Status / next execution

Rev G batch shipped (2026-09-03): realistic no-neon black+white 3×3
grids generated for all three mobs, matted + neonized into the
256×2304 sheets. Preview: `docs/art_baseline/cs_mobs_v5_revF.png`.
Wraith needed one regen after the model collapsed its grid to 2 rows
(ask for a square image).

Rev I (2026-09-03, owner: "Walk animations are bad"): the walk rows
were re-done as **dedicated 1×3 walk strips** for dredger and
containment — three explicit FRONT-facing stride/lurch frames
(generated realistic no-neon + white twin, triangulated + neonized via
`pipeline/walk_sheet.py`, then spliced into rows 3-5 of each 9-row
sheet; idle/attack/death rows untouched). Watch the loops:
`docs/art_baseline/walk_dredger.gif`, `walk_containment.gif`; full
sheet preview `docs/art_baseline/cs_mobs_v7_walkfix.png`.
**Wraith: no walk frames** — owner: "For wraith use static image, but
use effect to wobble that image for floating flying animation." Chase
now uses ONE static FRONT frame (`glide` animation state) and
`init.lua` bobs the entity with a sinusoidal vertical wobble
(`apply_wobble`, ±0.22 nodes at ~3.2 rad/s) so the ghost floats.

**OWNER GATE: PASSED (2026-09-03, "good").** The three mob sheets are
accepted as-is: dredger / wraith / containment 256×2304 9-row strips,
realistic-silhouette neonized look, dedicated walk strips, wraith
static+wobble float. Sheets committed on
`arena/01a063d9-systemtest` (`94940d0`, docs `0775fce`). No further
mob art re-rolls pending.

Rev H (2026-09-03): the same realistic→neonize workflow applied to the
sl_weapons **batch A inventory icons** (16 files) via
`weapon_icons.py` (per-item palettes in `ICON_STYLES`; two 3×3 grids +
white twins = 4 AI calls). Icons are 256×256 transparent RGBA,
18–53 KB each. Preview: `docs/art_baseline/cs_weapons_v1.png`.
Palette tweaks need no regeneration.

Per-mob palette used by the neonize stage (`matte_sheet.py` MOB_STYLE):
dredger amber rim + green feature accents; wraith cyan rim + ice;
containment amber rim + ember. All fills are near-black single colours.
If the owner wants any palette tweak, edit MOB_STYLE and re-run the
matte (no regeneration needed — the neonization is deterministic).
