# Integration — combining the parallel work (agent-01a05980)

**Date:** 2026-09-02 (rev 5)
**Rev 4 adds:** the map system and the MM-essence ruling (see §0.4).
**Rev 5 adds:** the MM essence engine (the §13.3 ruling, shipped): node
provenance, `groups.sl_essence_value` pricing on the craftable output defs, the
per-match pool with spawner pool-first spend, the named objective-core +3 craft
through the button crafting UI, the no-MM ambient-hazard security units at
thresholds, and the `/sl_state` + spawner-GUI readouts. Covered by the new
stub-only `tests/essence_test.lua` (61 assertions), wired into the `soak` CI gate
between the weapons turbo soak and the live-engine soak.
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
| `luajit tests/essence_test.lua` | 61/61 (rev 5: provenance, pricing, pool reset, +3 core craft, ambient hazard thresholds, scoreboard untouched, readouts) |
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

---

## 5. Product/owner decisions still required

Drawn from `MASTER_DESIGN_FULL.md` §17 and the assessment snapshot:

1. **Decide where the game lives** (pick a trunk; the `fd4e879` lineage can only be
   path-copied, never history-merged).
2. **Map policy** — production default `schematic` (hand-built, committed) and CI
   deterministic `test`; keep `procedural` only if the design docs are revised.
3. **Weapons integration order** — map lifecycle first, then weapons core, then
   corpse/sentry/grapple/fabricator/tournament in slices, then art.
4. **Real crafting-to-objective loop** — `objective_core`/machine-gate is still a
   placeholder; the acceptance test must exercise actual salvage → machine → core →
   delivery → match end.
5. **Green web release** — the WASM build fails (exit 77); `gh-pages` is not being
   advanced until it is fixed/made diagnosable.

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
