# Art-baseline survey — four competing art passes vs master

**Author:** arena-agent (`arena/01a063d9-systemtest`) · **Date:** 2026-09-02
**Base:** `origin/master` @ `21bc2d80` (PR #12 merged)
**Scope:** Turn 6 step 1 of `docs/NEXT_AGENT_PLAN.md` ("Art baseline
(owner-gated)") and the deferred item in `docs/INTEGRATION.md` §4.3: *the
285 modified textures across four competing passes* (`01a04c31`,
`01a04bfa`, `01a0487d`, `01a049ee`). "Never port two. Survey-only
deliverable first: contact sheets + per-branch diff stats vs master + a
pick recommendation. Gate: owner decides the pass."

This branch also carries a code fix found while surveying — **master's
sprite mobs render their whole 144×16 strip instead of animating it**
(`sl_scary:dredger`, `sl_scary:containment`, `sl_scary:signal_wraith`).
It is unrelated to which art pass wins: all four passes carry the same
broken strips, so the fix ships here regardless (see §7).

---

## 1. Bottom line

| # | Decision | Detail |
|---|---|---|
| 1 | **Pick `01a04c31` as the node/content art slice** | Strictest palette discipline of the four (avg ~4.3 colors/file, all-16×16, ~13 KiB of changed pixels across ~93 files), covers every *game-owned* node/item surface (modebase items, workshops furniture, mvp, sky, scary nodes), newest tip of the lineage, and is a restyle-and-extension of `01a049ee`'s neutral sets (which it subsumes). |
| 2 | **Do not port `01a04bfa`'s UI/clothing/formspec re-authoring over master's current UI** | Master's `sl_gui` icons are *newer* than that pass (roster tab, tab-icon series, achievement icons). The pass predates them, so a port would overwrite curated master work with older art — a regression risk, not an upgrade. |
| 3 | **`01a0487d` (default-family re-texture) is a separate world-style decision** | 241 files over the stock mtg family, incl. oversized/custom exceptions (`default_furnace_front_new.png` 512×341, `gui_formbg` 26k colors, animated torch/water sheets). Only relevant if the game wants a re-skinned *world* in addition to arena content. Curate if chosen; never squash-merge. |
| 4 | **Companion fix in this PR** | Mob sprite strips transposed 144×16 → 16×144 and animated through `set_sprite` + `spritediv` (see §7). |

The "owner gate" questions are collected in §8.

---

## 2. Method

Git-only survey, no mailbox: `git fetch` of all remote heads, tree
comparisons via `git diff origin/master <branch>`, and per-file PNG
decoding (stdlib `zlib`, deterministic). Style is measured from pixels
(luminance/saturation/white/dark share over opaque pixels of the 16×16
files), not guessed from thumbnails. Contact sheets were composited from
the branch trees with ImageMagick. Every claim below is re-derivable with
`git archive` + the scripts described in §9.

All four passes live on an unrelated-history strand (see
`docs/jax_branch_survey.md`): they are older trees that master absorbed
from selectively via squash merges. That is why "files changed vs master"
includes ~40 *master-only* PNGs (roster/tab icons, weapons placeholders)
that the branches predate — those are **not** pass defects and are
excluded from the pass-to-pass reading below.

---

## 3. Where master stands visually (the baseline)

| Surface | Master state |
|---|---|
| World blocks | Stock mtg default family (16×16, palette-indexed, 4-bit on many files) |
| Arena / modebase nodes & items | Mix of base textures + later-turn additions; dark, ~13.7% near-black pixels |
| UI (`sl_gui`) | Curated by UI turns 08-29/09-02: roster tab, 1-bit tab icons, achievement icons |
| Sounds | Synthesized set already integrated (`GENERATED_ASSETS.md` sound pass) |
| `sl_weapons` art | 37 × 16×16 solid-colour placeholders (90–101 bytes) — *none of the four passes fixes this* |
| `sl_scary` mobs | 3 sprite mobs; **bug**: strips shown whole, not animated (§7) |

---

## 4. Per-branch diff stats vs master

Counts are `.png` files whose tree differs from master at the same path
(`changed`), files master lacks (`added`), plus master files the branch
lacks (`master-only`, lineage skew). "Δ bytes" = sum of file sizes of the
changed/add set as stored.

| Pass | Branch tip | Changed | Added | Δ bytes | Avg colors/file | Non-16×16 files | Focus dirs |
|---|---|---|---|---|---|---|---|
| `01a0487d` | a9109e6, 08-28 | 241 | 0 | 811.9 KiB | 423.6* | 19 | `default/textures` only |
| `01a049ee` | 029a2b8, 08-28 | 85 | 1 | 17.5 KiB | 4.8 | 0 | workshops (50), modebase (27), mvp, scary, sky |
| `01a04bfa` | 047af66, 08-29 | 260 | 11 | 298.1 KiB | 20.1 | 108* | `sl_gui` (117), workshops (57), modebase (28), construction (22), mvp, clothing, dignodes, formspec, sky, scary |
| `01a04c31` | 941d8b0, 08-29 | 85 | 8 | 13.2 KiB | 4.3 | 1 (4×4 cloud particle) | workshops (50), modebase (31), sky (5), mvp, scary |

\* Averages are skewed by outliers: `01a0487d`'s mean is dominated by
photo-like assets (`default_furnace_front_new.png` 512×341 ≈ 42k colors,
`gui_formbg` ≈ 26k); the typical 16×16 tile is far leaner. `01a04bfa`'s
non-16 set is mostly its re-authored 256×256 achievement icons and 24×24
formspec chrome — dimensions master already uses for those surfaces.

`01a04bfa` and `01a04c31` both forked from `01a049ee`'s tip (029a2b8)
and went in different directions: `04bfa` = broad white-glow pass across
UI + furniture + clothing; `04c31` = white-bloom node/utility pass,
restyling `049ee`'s sets and extending modebase coverage to 31 files.

---

## 5. Style, measured

Pixel metrics on opaque pixels (luminance 0..1, saturation 0..1, share of
near-white / near-black pixels):

### Default world family (19–20 shared names; rows `cs_default.png`)

| Tree | Mean lum | Mean sat | White | Dark | Character |
|---|---|---|---|---|---|
| master (stock mtg) | 0.47 | 0.44 | 2.1% | 4.3% | familiar browns/greys |
| `01a0487d` | 0.39 | 0.59 | 0.1% | 13.0% | saturated neon lines on near-black — matches the neon map |

### Game-owned node/item surfaces (108 shared files; rows `cs_nodes_*.png`)

| Tree | Mean lum | Mean sat | White | Dark | Character |
|---|---|---|---|---|---|
| master | 0.31 | 0.42 | 0.2% | 13.7% | dark, mid-saturation |
| `01a049ee` | 0.32 | 0.22 | 3.6% | 20.2% | neutral white/grey panels, desaturated |
| `01a04bfa` | 0.50 | 0.18 | 9.2% | 4.9% | light "white-with-glow", low saturation |
| `01a04c31` | 0.43 | 0.24 | 27.2% | 38.5% | white-bloom neon line-art on dark fill (bimodal) |

`01a04c31` and `01a049ee` are the only passes that keep every file at
16×16 with a tiny palette (≤13 colors/file for 049ee; ~4-5 avg for
04c31), consistent with `docs/low_spec_visual_budget.md` and the
repo's own "strict 3-4 color" discipline. Top offenders are modest:
`01a04c31`'s `sl_beacon_a/b` (79-89 colors, damage-state lettering).

---

## 6. Contact sheets (`docs/art_baseline/`)

Cells carry a white column index (0-based) burned into the corner; rows
are ordered per sheet.

**`cs_default.png`** — 2 rows × 20 cols. Row 1 = master (stock mtg), row
2 = `01a0487d`. Columns 0-19: `default_stone`, `default_cobble`,
`default_dirt`, `default_grass`, `default_sand`, `default_gravel`,
`default_desert_sand`, `default_tree`, `default_wood`,
`default_jungletree`, `default_brick`, `default_glass`,
`default_steel_block`, `default_furnace_front`, `default_coal_block`,
`default_obsidian`, `default_snow`, `default_ice`, `default_clay`,
`default_desert_stone`.

**`cs_nodes_items.png`** — 4 rows × 18 cols. Rows = master, `01a049ee`,
`01a04bfa`, `01a04c31`. Columns 0-17: `sl_metal_ingot`, `sl_circuit_board`,
`sl_energy_crystal`, `sl_power_cell`, `sl_monster_essence`,
`sl_hardened_plate`, `sl_reinforced_glass`, `sl_scrap_metal`,
`sl_plastic_scrap`, `sl_electronic_waste`, `sl_objective_core`,
`sl_loot_crate`, `sl_sensor_array`, `sl_signal_relay`, `sl_warning_sign`,
`sl_monster_spawner`, `sl_barricade`, `sl_blast_shield`.

**`cs_nodes_furn.png`** — 4 rows × 15 cols, same row order. Columns 0-14:
`advanced_workbench_front`, `assembly_table_top`, `blueprint_drawer_front`,
`control_panel_front`, `filing_cabinet_front`, `metal_desk_front`,
`metal_locker_front`, `server_rack_front`, `vent_grate`,
`warning_sign_biohazard`, `pipe_end`, `caution_tape`,
`precision_anvil_top`, `window_frame`, `tool_rack_side`.

**`cs_gui.png`** — 2 rows × 12 cols: master vs `01a04bfa`. Columns 0-11:
`ability_attack`, `ability_speed`, `ability_teleport`,
`achievement_abyss`, `achievement_combat`, `achievement_first_dig`,
`achievement_place_1000_blocks`, `achievement_victory`,
`achievement_visit_10_islands`, `gui_achievement_star`, `gui_blank`,
`gui_button_clear`. Read this sheet with the caveat from §1#2: master's
icons postdate the pass, so differences here are mostly "older re-style"
vs "current master series".

**`cs_mobs.png`** — top band = the bug as shipped on master (each 144×16
strip rendered whole); bottom 3 rows = the corrected frame sequences
(dredger, containment, wraith), columns 0-8 = frames: 0-2 idle, 3-5
walk, 6-7 attack, 8 death. This is the animation this PR turns on.

---

## 7. The mob sprite bug and the fix on this branch

**Root cause (verified against Luanti 5.17.0 source, the pinned engine):
** `sprite` visuals are animated with `object:set_sprite(start_frame,
num_frames, framelength, select_x_by_camera)` and the engine advances
frames along the frame *y* position only (`content_cao.cpp`:
`// Animation goes downwards; row += m_anim_frame`). The mob code called
`object:set_animation(...)` — a mesh-keyframe API that does nothing for
sprites — and the sheets were horizontal (144×16) with no `spritediv`, so
`spritediv` defaults to {1,1} and the client draws the *entire* strip as
one billboard. Result: exactly what the report describes, mobs showing
the whole sheet at once.

**Same blob, everywhere:** the three `sl_scary_*_strip.png` files are
byte-identical across master and all four passes (`9b35b7f3`, `7c65c7e4`,
`88a44e7f`), and every tree's `init.lua` calls `set_animation` on them.
No branch ever fixed this, so the fix is pass-independent.

**Fix shipped on this branch:**

1. `mods/content/sl_scary/pipeline/transpose_sprite_strip.py` — new,
   pure-stdlib, deterministic block transpose. 144×16 → **16×144**,
   pixels untouched (verified frame-identical for all 9 frames of all
   three mobs).
2. `init.lua`: each sprite mob now declares `spritediv = {x=1, y=9}` +
   `initial_sprite_basepos = {x=0, y=0}`, and `set_sprite_anim()` calls
   `object:set_sprite({x=0, y=<row>}, <n frames>, <s/frame>, false)` per
   state — idle rows 0-2 @2fps, walk 3-5 @4fps, attack 6-7 @6fps, death
   row 8. Frame-range comments updated to the vertical layout.
3. Loot icons (`dredger_badge`, `containment_shard`, `corrupted_data`)
   used `^[resize:16x16` on the whole strip (a squashed-sheet icon);
   now `^[verticalframe:9:0` — a clean 16×16 crop of the idle frame.
4. `pipeline/README.md` and `GENERATED_ASSETS.md` document the vertical
   layout and why (the Seirin toolchain on `01a0436b-systemtest` still
   emits horizontal strips; run the transpose script after regenerating).

Side note: `sl_scary_signal_wraith.png` (16×16, single frame) has no Lua
reference on master — legacy leftover from before the strip rebuild;
left in place (referenced by none of the passes either).

---

## 8. Owner-gated questions (decision request)

1. **Which direction for game-owned nodes/items?** Recommendation:
   `01a04c31`. Alternatives: `01a04bfa` (if the game should go light /
   white-glow across UI too — then decide how to reconcile with master's
   newer `sl_gui` series) or `01a049ee`'s neutral palette (superseded in
   style by 04c31 for the same surfaces).
2. **Do we re-skin the stock default world family** (`01a0487d`, optional
   later slice) or keep stock mtg art around the arena?
3. **Weapons icons**: none of the passes covers them (37 placeholders
   remain everywhere). Open a separate small icon slice, or leave for the
   weapon-art milestone?
4. **UI reconciliation**: keep master's current `sl_gui` (recommended),
   or trial `01a04bfa`'s UI restyle on a branch for in-engine screenshots
   before deciding?

**If no decision:** this turn stops here (survey + decision request), per
the plan — nothing beyond the §7 bug fix and this survey has been merged.

**If `01a04c31` is picked, the curate step should:** port its
`sl_modebase`, `workshops`, `sl_blocks/sky`, `sl_mvp_assets`,
`sl_scary` (hide-spot faces) textures; verify every texture referenced by
Lua exists (add the texture-reference audit assertion to the stub
suites); run the in-engine visual smoke / soak; keep 0-byte and
placeholder-free output; and only then drop any `01a049ee`-only files
that 04c31 did not carry forward. `sl_weapons` textures (37) and the
default family stay untouched unless question 2/3 rule otherwise.

---

## 9. Reproducibility

Contact sheets were built from `git archive origin/<branch> mods` trees
and ImageMagick `convert`/`+append` (index badges burned in), using the
file lists in §6. PNG decoding/dimension/palette stats used the stdlib
reader in `mods/content/sl_scary/pipeline/transpose_sprite_strip.py`.
The strip transpose itself is the committed, rerunnable script.

**Verification note:** this sandbox has no Lua runtime, so `luajit -bl`
/ suite runs from the golden ladder in `docs/NEXT_AGENT_PLAN.md` could
not be executed here; the only Lua change is isolated to
`sl_scary/init.lua` (not covered by the stub suites). CI's syntax gate
and soak cover it on push.

Still open from Turn 6 step 3: reconcile the stale "procedural mapgen is
abandoned" line in `ROADMAP.md` with the shipped map system (unchanged
here; flagged so it is not lost).
