# Integration — combining the parallel work (agent-01a05980)

**Date:** 2026-09-03 (rev 10)
**Rev 10 adds (owner direction 2026-09-03):** mobs regenerated at
**256px frames — 3 frames of animation per sheet** (was 64×64 × 9),
in the **boxman neon wire-glow style**. The style reference render
(`docs/art_baseline/boxman_style_render.png`) is produced from the
actual `SimpleOutlinedBoxman.glb` + its 2×2 material by the committed
`pipeline/render_boxman_ref.py` (software render — no engine in this
sandbox). New sheets are 256×768 (3×256 cells), ~150-250 KB each;
`pipeline/process_sprite.py` (new) keys/grooms AI sticker frames and
stacks them vertically; all alive states replay the one 3-frame loop at
different speeds, death freezes; loot icons now `^[verticalframe:3:0`.
Weapons hi-res textures (owner): **queued** — the AI-image budget is 10
images/turn and the mob set used it; `docs/art_baseline/weapons_hires_plan.md`
categories the 37 files (16 item icons + 7 node faces + 2 pad rings +
3 decals via AI; 9 effects procedural).
**Rev 9 (correction of rev 8):** the owner art-gate rulings, re-read
correctly on 2026-09-02: "no blur/AA" is a **UI-only** rule; other
surfaces (nodes, mobs, craftitems, world) keep normal rendering and may
use hi-res textures; **3D-model textures must not be swapped for
AI-drawn flat art** — attempts ignore how the texture maps onto the
model (catastrophic on the clothing b3d props and the `SimpleOutlinedBoxman`
GLB). Rev-8's interim ports of `01a04bfa`'s clothing and
`01a049ee`'s boxman texture are therefore **reverted** (byte-identical
to master). The `sl_scary` strips keep the animation fix (rev 7) and
the 64×64 re-ink — sprites are flat billboards, so hi-res art is safe.
No wholesale pass port; per-file triage + port list:
`docs/art_baseline_survey.md` §10.
**Rev 7 adds:** the **art-baseline survey** (Turn 6 step 1, owner-gated):
contact sheets + per-branch diff stats vs master + a pick recommendation
for the four competing art passes — see `docs/art_baseline_survey.md`.
Nothing is ported until the owner picks a pass. Also ships the **sl_scary
sprite-mob animation fix** (master bug: sprite visuals showed their whole
144×16 strip instead of animating): sheets transposed to the engine's
vertical layout (16×144) via the new
`mods/content/sl_scary/pipeline/transpose_sprite_strip.py`, entities use
`spritediv {x=1,y=9}` + `object:set_sprite(...)`, and loot icons crop one
frame with `^[verticalframe:9:0` (rev-D sheets later made it `^[verticalframe:3:0`, rev 10).
**Rev 4 adds:** the map system and the MM-essence ruling (see §0.4).
**Rev 5 adds:** the MM essence engine (the §13.3 ruling, shipped): node
provenance, `groups.sl_essence_value` pricing on the craftable output defs, the
per-match pool with spawner pool-first spend, the named objective-core +3 craft,
the no-MM ambient-hazard security units at thresholds, and the `/sl_state` +
spawner-GUI readouts. Covered by the stub-only `tests/essence_test.lua`, wired
into the `soak` CI gate.
**Rev 6 adds:** the **crafting-to-objective loop** (§5.4, the long-standing
"wedged" item). `sl_machine_crafting` is now a real mod — the **Objective
Forge**, one per map at the new `forge` anchor, running exactly the recipes the
inventory UI refuses (same predicate, one recipe registry, no duplication).
The temporary `sl_craft_in_inventory` opt-in on the Objective Core is **gone**:
placeables come only from the machine, as §6.5 requires. Salvage veins are
seeded on the procedural and test arenas — before this, the three exotic neon
types existed on no map at all, so the chain was literally unwinnable — and the
refine branch is rebalanced so a full run is five forge runs / twenty dug nodes.
`game_mode.run_headless_objective_test()` (`/sl_test_objective`) no longer
*narrates* the steps, it performs them. Covered by the new stub-only
`tests/objective_loop_test.lua` (128 assertions), wired into the `soak` CI
gate. A self-audit pass after the first push found and fixed three real bugs
(§3.1) and corrected a wrong justification in §4.7.
**Branch:** `arena/01a05980-systemtest`
**Base:** `master` @ `457ccb9`
**Purpose:** read every remote branch, the docs, and the full agent mailbox, then
combine **the good things that genuinely belong on main** into one branch and open a PR.

---

## 0. What this revision corrects (from review feedback)

1. **Agent messages are NOT on main.** The prior draft (rev 1) carried the entire
   mailbox conversation corpus (`agent_mail/messages/*`, `agent_mail/agents/*`).
   That is ephemeral cross-agent chatter, not product content. Rev 2 commits only
   the **mail tooling + protocol docs** (`tools/agentmail.py`, `tests/agentmail_test.py`,
   the `.github/workflows/agent-mail.yml` CI gate, and `agent_mail/PROTOCOL.md` /
   `README.md` / `AMENDMENTS.md`). The message corpus and agent cards stay on the
   agent branches.

2. **The real gameplay work was not merely documented — it was ported.** Rev 1 only
   combined shared-root agent work (mail, strand, whisper, docs) and *deferred* the
   `fd4e879` lineage. That lineage holds the single most valuable missing gameplay
   feature, the ranged arsenal. Because it shares **no common ancestor** with this
   root, `git merge` refuses it; per `docs/jax_merge_plan.md` the correct technique is
   a **path-copy port**. Rev 2 performs the port for the self-contained pieces.

3. **Rev 3 — the port is now complete, not just self-contained.** Rev 2 shipped the
   weapons mod and its 288-assertion suite, BUT the suite could not run: the tests
   were written against the weapons branch's extended `tests/minetest_stub.lua`
   (modpath routing, sound/particle/drop capture, real luaentity instances,
   `minetest.raycast`, `get_objects_inside_radius`), and the path-copy port dropped
   the stub changes. It also shipped tests that exercised **host hooks that were
   never ported**, so the branch was internally inconsistent:
   * the **vector armor** (`vector.safe_dir` / `vector.finite` — the live-server
     NaN → client-segfault fix) lives in `sl_modebase/init.lua` on the source
     lineage; `sl_weapons` fires `vector.safe_dir` unguarded;
   * the **corpse capture** hook in `match.lua` (the death fountain is supposed to
     land in the corpse; without the hook it lands on the floor and no corpse is
     ever spawned);
   * **salvage rolls** (`game_mode.register_pickup_roll` / `get_pickup_rolls` +
     weighted `item_pickup` rolling) — `sl_weapons/init.lua` registers two entries
     on a function that did not exist;
   * **monster spoils** (`MONSTER_LOOT` / `drop_monster_loot`) + the melee hook on
     `entities.lua` — the fabricator recipe's ingredients must all be
     monster-obtainable;
   * the **ghost altar recipe** (`nodes.lua`, spoils economy);
   * **tournament mode** (`/sl_tournament`, season bookkeeping, roster/spectator
     rule, `reset_player_progression` / `reset_match_achievements` lifecycle) —
     PHASE W3e of the shipped suite covers it;
   * **match-start inventory clearing** (unconditional — the old creative-mode
     skip leaked arsenals between matches) + MM kit re-grant.
   Rev 3 ports all of it from the `fd4e879` lineage (path-copy, same reviewer
   discipline as rev 2), adds the **39 missing `sl_weapons` sounds** through the
   existing `generate_sounds.py` pipeline (SPEC §13 — the mod calls
   `sound_play("sl_weapons_*")` 30+ times and shipped zero audio files), and wires
   the three new Lua suites into the `soak` CI gate. All suites now run on master's
   stub: smoke 126/126, strand 84/84, weapons 288/288, turbo soak PASS.

4. **Rev 4 — the map system and the MM-essence ruling.** The single biggest
   deferred unlock (`arena/01a0487f`) is now integrated: the match loop runs
   on a real map system — seeded **procedural** arenas, the deterministic
   **test** arena, and handler-built **schematic** maps with a full
   initial-state reset contract (volume re-materialization, node-journal for
   out-of-volume edits, mob purge + initial population respawn, beacon/ghost
   restoration). Procedural maps gained **layout overrides**:
   `sl_map.cage_pos` / `sl_map.beacon_a_pos` / `sl_map.beacon_b_pos` /
   `sl_map.mm_base_pos` place the cloud cage, the two beacon bastions and the
   Monster Master redoubt anywhere on the arena floor; the resolved layout is
   carried by the descriptor so match-end rebuilds are drift-free and
   `/sl_map save` exports it like any other arena. The owner's ruling on MM
   essence (§13.3/§17.2 of MASTER_DESIGN_FULL) is recorded in the design
   canon. Verification: smoke 193/193 (phases 17–21 cover map prepare/journal/
   reset/mobs/schematics//sl_map/layout overrides), strand 84/84, weapons
   288/288, turbo soak PASS (map RNG pinned so the weapons-balance stream
   stays deterministic).

---

## 1. Repository reality (verified from git, not mail)

Three unrelated histories share this remote (`git rev-list --max-parents=0` /
`git merge-base` return empty across roots):

| Root | What it is |
|------|------------|
| `457ccb9` | `master` / `build` — the snapshot every "current" agent branched from |
| `fd4e879` | the real engineering history (96–152 commits, Aug 27–29); **cannot `git merge` into the snapshot family** |
| `6ea1f16` | `gh-pages` |

Everything in this PR is on the `457ccb9` root (fetchable, path-copyable). Nothing
here is a history merge across roots.

---

## 2. What is in this branch, and from where

### Cross-agent mail **tooling** (not the conversation corpus)
- `tools/agentmail.py` — cross-agent mailbox CLI (newest, incl. the D10 union fix).
- `tests/agentmail_test.py` — 53 checks.
- `.github/workflows/agent-mail.yml` — lint + unit-test CI gate.
- `agent_mail/PROTOCOL.md`, `README.md`, `AMENDMENTS.md` — the protocol and how-to docs.
- *Explicitly excluded:* `agent_mail/messages/*`, `agent_mail/agents/*`.

### THE WHISPER — evil-ghost body possession / secure DM channel
- `mods/game/sl_modebase/whisper.lua` (from `arena/01a05892-systemtest`), one
  `include_files` line in `init.lua`, `optional_depends = sl_scary` in `mod.conf`.

### Simulacrum Strand — singleplayer roguelike deduction mode (`feat/strand-chain-ledger`)
- `mods/game/sl_strand/**` with the **Chain Ledger** (`strand_ledger.lua`): score
  earn rule, debt burn/paydown, seven named endings, `HOLLOW CROWN` corruption win.
- `xor32` rewritten in plain arithmetic (Lua 5.1 / LuaJIT-safe).
- `tests/strand_test.lua`, `docs/STRAND.md`.

### `sl_weapons` — the ranged arsenal (the headline port, `arena/01a04a09-systemtest`)
- `mods/game/sl_weapons/**` (12 Lua files, `mod.conf`, 38 textures) — eight weapons,
  hitscan + projectile, weapon/ammo pads with pitched chimes, deployable Sentry Kit,
  corpse incident + burial/cremation, Precision Fabricator, Grapple Lash, MM
  bare-hand doctrine.
- `WEAPONS_SPEC.md` (v1.2, 982 lines), `WEAPONS_COUNCIL.md`.
- `tests/weapons_test.lua` (288 assertions), `tests/soak_stub_turbo.lua`.
- **Drop-in and non-invasive by construction:** every `game_mode.*` call is guarded
  (`if game_mode and game_mode.X`), and the mod wraps `game_mode.start_new_match` /
  `end_match` at runtime rather than editing `sl_modebase`.

### Consolidated design / content docs (shared-root + salvage plan)
- `docs/MASTER_DESIGN_FULL.md` (authoritative, 857 lines) + `MASTER_DESIGN.md`
  + `MASTER_DESIGN_FILL.md`.
- `docs/zhtharr_lore_002..007`, `docs/zhtharr_match_specimen_001.md`.
- `docs/jax_merge_plan.md`, `docs/jax_weapon_audit.md`, `docs/jax_branch_survey.md`.
- `docs/low_spec_visual_budget.md`, `docs/match_example_v2/v3_melody.md`,
  `docs/melody_design_thoughts.md`, `docs/melody_whisper_spec.md`.

### Deployment runbooks (docs only)
- `docs/DEPLOY_SERVER.md`, `docs/PUBLIC_DEPLOY.md`, `docs/FREE_HOSTING.md`.

---

## 3. Verification

| Check | Result |
|-------|--------|
| `python3 tools/agentmail.py lint` | 0 errors (no message corpus to report on) |
| `python3 tests/agentmail_test.py` | 53/53 |
| LuaJIT syntax gate, all `mods/**/*.lua` | clean (incl. the modebase hook edits) |
| `luajit tests/smoke_test.lua` | 193/193 (phases 17–21: map prepare/journal/reset, mob lifecycle, handmade maps, `/sl_map`, layout overrides) |
| `luajit tests/strand_test.lua` | 84/84 |
| `luajit tests/weapons_test.lua` | 288/288 (was: crash on missing stub `modpaths`, then 6+ real failures) |
| `luajit tests/soak_stub_turbo.lua` | PASS (40 matches × 3 seeds: no weapon > 30 % kill share; Lash ≥ non-holder death rate; zero Lua errors; map RNG pinned for a deterministic bot stream) |
| `luajit tests/essence_test.lua` | 69/69 (rev 5: provenance, pricing, pool reset, +3 core craft — now routed through the Forge, ambient hazard thresholds, scoreboard untouched, readouts) |
| `luajit tests/objective_loop_test.lua` | 128/128 (rev 6: forge anchor + materialization, salvage veins on **both** the test and procedural arenas, inventory refuses every placeable, single-job/time-gated/loud forge runs, refine + core assembly, +3 essence on the core, delivery refusals, winning delivery, reset, forfeit, access control, `/sl_test_objective` performs the chain, hardening regressions, the Core survives death, output spill, stations as forge outputs) |
| sl_weapons assets | 39/39 sounds generated through `generate_sounds.py` (SPEC §13); 37 textures are 16×16 solid-colour placeholders (art baseline still deferred) |

CI runs the new suites: `agent-mail` workflow (lint + unit tests) and the `soak`
workflow now gates smoke, strand, weapons, the stub turbo soak and the live-engine
soak.

---

## 4. What is deliberately deferred (and why) — the honest boundaries

This branch is a **curated port**, not a "merge every tip." The following are the
genuinely-needed items that could not be shipped *safely* in a single PR and are
therefore teed up as the next scoped steps (see §5, the owner decisions).

1. ~~**Map system (`arena/01a0487f`)**~~ **— shipped in rev 4.** Procedural /
   test / schematic map types, initial-state reset (volume re-materialization,
   node journal, mob purge + respawn, beacon + ghost restoration),
   `/sl_map` command set, two shipped handmade maps, and — added here —
   procedural layout overrides for the cloud cage, the beacon bastions and the
   MM redoubt. Map policy resolved: procedural stays the default and is now
   position-configurable; schematic exists for hand-built arenas; the test
   arena keeps CI deterministic.
2. ~~**`sl_weapons` host hooks**~~ **— shipped in rev 3.** `register_pickup_roll` /
   `get_pickup_rolls` + weighted loot rolling (`content.lua`), corpse capture
   (`match.lua` dieplayer), monster spoils + melee wear hook (`entities.lua`),
   vector armor (`init.lua`), ghost-altar recipe (`nodes.lua`).
3. **Art baseline (`01a04bfa`) + selected refinement (`01a04c31`)** — a large
   binary-review load (285 modified textures) that the assessment says must be curated,
   not merged as a unit, and which needs in-engine visual smoke tests. Deferred.
4. ~~**Tournament mode**~~ **— shipped in rev 3** (`/sl_tournament`, season
   bookkeeping, roster/spectator rule, progression loan; wedded to its W3e tests:
   scoring, persistence, late-joiner, auto-close).
5. **Deployment tooling** (`websocket_proxy.js`, docker all-in-one) — **not** included:
   the proxy accepts arbitrary client-supplied destination IP/ports (incl. loopback),
   has no allowlist/auth/timeouts, and is unsafe to expose as written. The runbooks are
   shipped; hardening + a real external join test are required before the tooling can
   land.
6. **Live-engine combined validation** — the map+weapons lifecycle, magazine/reserve
   wear, every death route, corpse burial/cremation, and tournament scoring all need a
   live soak the way `WEAPONS_SPEC` and `docs/jax_weapon_audit.md` describe. The stub
   suites validate the branch; the live soak is still an open step.
7. **Two-station Core (rev 6, deferred).** §6.10 B's Assembly Station →
   `core_frame` → Objective Forge split, plus the remaining four stations
   (Salvage Bench, Signal Terminal). Every machine-gated recipe runs at the
   single Forge today.

   *Correction to the first draft of this entry:* it claimed the split is
   blocked on an intermediate item set "that does not exist as content yet".
   That is wrong — `metal_ingot`, `circuit_board`, `energy_crystal`,
   `hardened_plate` and `reinforced_glass` are all registered craftitems
   (`sl_modebase/content.lua`). The real blocker is **supply**: those items
   are produced by *nothing* except `MONSTER_LOOT` (and `hardened_plate` /
   `reinforced_glass` have no source at all). Re-authoring the Core over
   them would move the win condition from scavenging to hunting — a
   balance decision, not a plumbing one. See §4.8.

8. **Two machine implementations (rev 6, known debt).** `sl_machine_crafting`
   (the Forge — generic, drives its list from the shared recipe registry,
   node-timer jobs) and `sl_weapons/fabricator.lua` (the Precision
   Fabricator — specialist, its own `W.FAB_RECIPES` table and a globalstep
   job queue) now coexist with duplicated job plumbing. They do not
   conflict (disjoint recipe sets), and unifying them is deliberately
   deferred: the Fabricator carries the 288-assertion weapons suite.
   Unify on the Forge's node-timer engine when that suite can be re-pinned.

9. **Handmade maps must author their own salvage (rev 6).** A schematic map
   gets a forge anchor (`forge.pos`) but no salvage veins — the procedural
   and test arenas seed theirs, a schematic is the author's content. A
   handmade map without all four raw neon types cannot run the objective
   loop. Documented in `mods/game/sl_modebase/maps/README.md`.

---

## 5. Product/owner decisions still required

Drawn from `MASTER_DESIGN_FULL.md` §17 and the assessment snapshot:

1. **Decide where the game lives** (pick a trunk; the `fd4e879` lineage can only be
   path-copied, never history-merged).
2. **Map policy** — production default `schematic` (hand-built, committed) and CI
   deterministic `test`; keep `procedural` only if the design docs are revised.
3. **Weapons integration order** — map lifecycle first, then weapons core, then
   corpse/sentry/grapple/fabricator/tournament in slices, then art.
4. ~~**Real crafting-to-objective loop**~~ **— shipped in rev 6.** The Objective
   Forge is the machine step; salvage veins make the raw material obtainable;
   `tests/objective_loop_test.lua` exercises the real chain end to end. Still
   open (smaller): the §6.10 B plan wants **two** stations and a `core_frame`
   intermediate — see §4.7 for what actually blocks it (supply, not
   plumbing).
5. **Green web release** — the WASM build fails (exit 77); `gh-pages` is not being
   advanced until it is fixed/made diagnosable.

**Ruled since rev 5 (owner, 2026-09-02):**

8. **The machine chain lands in the objective-loop turn.** Recorded in the
   code at the point it mattered: `sl_modebase:objective_core` carried
   `sl_craft_in_inventory = 1` explicitly "until the machine chain lands
   (objective-loop turn)". Rev 6 built the machine and removed the opt-in,
   restoring the §6.5 rule that placeables come only from machines. The +3
   craft credit (ruling 7) is unchanged — it now fires from the Forge.

**Ruled since rev 3 (owner, 2026-09-02):**

6. **Map policy** — procedural default stands, now with position overrides for
   the cloud cage, beacons and MM base (`sl_map.cage_pos` /
   `sl_map.beacon_a_pos` / `sl_map.beacon_b_pos` / `sl_map.mm_base_pos`);
   schematic remains the handmade-map path, test the CI-deterministic one.
7. **Essence from crew activity (§13.3)** — accepted with its mechanism ruled:
   destruction of crew-placed nodes pays `price(node)` to the MM pool, select
   crafts (the objective core, +3) pay directly, essence is **fuel, not score**,
   and points come primarily from killing crew (no farming economy).
   **Implemented in rev 5** (the essence engine + `tests/essence_test.lua`);
   the ruling text now carries the pool-reset semantics and the pricing source.

---

### 3.1 Self-audit: three real bugs found after the first push

Found by re-reading the new code against engine semantics rather than
against the stub, and each one pinned by a test that fails when the
fix is reverted:

1. **`on_dig` emptied the charge even when `can_dig` refused.** `can_dig`
   is a Lua-level convention — the engine calls `on_dig` regardless. A
   player punching the forge mid-match (dig refused) would still have had
   the input slots spilled: the crew loses the charge to a punch that did
   nothing. `on_dig` now checks `can_dig` first.
2. **The mid-run slot lock only blocked one direction.** Moving items
   *into* `src` during a run was still allowed, so an announced job could
   be topped up. Both directions are blocked now.
3. **The payout could silently delete a win-condition item.** It trusted
   `add_item`'s return value, which the headless stub does not model. The
   output capacity is now computed explicitly (`put_or_spill`), so an
   over-full output slot spills at the foot of the machine in both the
   stub and the engine.

Also swept: the forge's `src`/`dst` are now emptied and its timer stopped
at match end, so last match's charge cannot survive into the next one on
arenas that are journal-restored instead of rebuilt (external/adopted
maps).

## 6. Commit list (from `master`)

```
ed4a665 chore(mail): add cross-agent mailbox tooling + CI gate (no message corpus)
b6c6dfa feat(whisper): add THE WHISPER evil-ghost body-possession secure DM channel
6e6fa14 feat(strand): add Simulacrum Strand singleplayer mode + Chain Ledger
e08f833 docs: add consolidated design set (MASTER_DESIGN*, zhtharr lore 002-007, jax salvage plan)
f7c603b feat(weapons): add sl_weapons ranged arsenal (WP9) + spec + tests
3211b4b docs(deploy): add public server hosting runbooks
3fe1216 docs: rewrite INTEGRATION summary (rev 2)
069f5f2 chore: ignore Python bytecode (__pycache__)
+ rev 3 (see git log): host hooks, test stub, tournament, weapon audio, CI wiring
```
