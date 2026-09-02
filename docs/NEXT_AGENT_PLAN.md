# Multi-turn plan — finish System Looting (handover to the next agent)

**Date:** 2026-09-02 · **Base:** `master` @ `8b2c6e7` (PR #6 merged) + **PR #7**
(`feat/match-map-system`, open, CI-green, `mergeable_state: clean` — merge it
FIRST; it carries the map system, the procedural layout overrides, the
essence ruling commit and this plan).

Each turn = one agent session that lands **one scoped PR** (branch off
`origin/master`, suites green, verification table in the PR body, CI green,
merged). Update `docs/INTEGRATION.md` rev number and its verification table
every turn. Never push to `master` directly.

---

## 0. Turn 0 — Warm-up (every session, 15 min)

```
cd repo && git fetch origin
git checkout -B work origin/master          # NEVER trust a stale local master
git config user.name  "arena-ai-coding-agent[bot]"   # .git/config is NOT
git config user.email "arena-ai-coding-agent[bot]@users.noreply.github.com"  # persisted!
git remote add origin https://x-access-token:<PAT>@github.com/SodoMita/SystemTest.git
```

Toolchain (fresh sandbox has no LuaJIT; apt needs root you don't have):

```
cd /tmp && git clone -q --depth 1 --branch v2.1 https://github.com/LuaJIT/LuaJIT.git
cd LuaJIT && make -j4 && make install PREFIX=$HOME/.local
export PATH=$HOME/.local/bin:$PATH
export LUA_PATH="$HOME/.local/share/luajit-2.1/?.lua;$HOME/.local/share/luajit-2.1/?/init.lua;;"
```

The `;;` in `LUA_PATH` matters — without it `luajit -bl` reports
"jit.* modules not installed" on every file. (Fallback for suites without
`io.popen`: `pip install --user lupa; python3 tests/run_lua51.py <suite>`.)

Golden ladder (must be green before any work):

```
luajit tests/smoke_test.lua        # 193/193 after PR #7
luajit tests/strand_test.lua       # 84/84
luajit tests/weapons_test.lua      # 288/288
luajit tests/soak_stub_turbo.lua   # PASS
for f in $(find mods -name '*.lua'); do luajit -bl "$f" >/dev/null || echo "SYNTAX FAIL: $f"; done
python3 tests/run_lua51.py tests/smoke_test.lua   # PUC 5.1 parity
```

Read first: `docs/INTEGRATION.md` (rev 4), `docs/MASTER_DESIGN_FULL.md`
§6.10 (crafting), §13.1–13.3 (essence, now RULED), §15.3 (one-shot pillar),
§17–18; `docs/jax_merge_plan.md` §9 (second wave), §10 (owner gates);
`ROADMAP.md` (note: its "procedural mapgen is abandoned" line is stale —
the owner ruled the procedural map system default + overrides stands;
reconcile in Turn 6).

## House rules / don't-retry list (hard-won this session)

- **Never run the full `python3 generate_sounds.py` CLI.** It dies with
  `KeyError: 'no recipe for achievement_unlock.1.ogg'` and rewrites
  `menu/*.ogg`. Generate only via the module-import snippet into
  `mods/game/sl_weapons/sounds/`. (`WEAPONS_FAMILY` is the corrected
  39-entry dict; helpers `_w_*` + `SPECIAL`/`RECIPES` updates live in
  `generate_sounds.py`.)
- Never revert: `show_rank_formspec`'s `;`-joined table rows (live-server
  "Invalid table element" crash — comma-join, never `;`); the stub's
  single rich entity factory (`make_entity_object`, items included);
  `M.item_drops`; the soak's RNG pin (`sl_map.seed`/`sl_map.mobs=0` with
  its comment); `vector.safe_dir`/`vector.finite` in both
  `sl_modebase/init.lua` and the stub.
- `fd4e879`-lineage branches have no common ancestor with master → path-copy
  (per `docs/jax_merge_plan.md`). Branches on the master lineage → cherry-pick.
- PR #6's deferred items in INTEGRATION §4 now shipped: weapons host hooks,
  tournament mode, map system. Do **not** re-port them.
- Suite invariants: weapons 288 and soak gates must stay green; if a map
  change perturbs the soak, pin the map RNG again, never loosen the gates.

---

## Turn 1 — MM essence engine (the unshipped ruling; top priority)

> **DONE — PR #9 merged (`43998d6`), 2026-09-02.** Node provenance,
> `groups.sl_essence_value` pricing, the per-match pool with spawner
> pool-first spend, the ambient-hazard security units, the `/sl_state` +
> spawner-GUI readouts, `tests/essence_test.lua`, and the `soak.yml` step.
> **Note for whoever runs the essence suite next:** the named +3 craft is
> no longer reachable through the inventory UI — Turn 2 removed the
> `sl_craft_in_inventory` opt-in and the +3 now fires from the Objective
> Forge. The assertion is unchanged; only the route moved.
> **Known remaining gap:** Turn 1's `sl_essence_value` pricing pass covers
> the outputs that existed then. Machine-crafting outputs added since
> (and the forge itself) have values; `construction:*` components do not.

**Ruling (recorded, `MASTER_DESIGN_FULL.md` §13.3):** the MM's essence is
earned by **destruction of crew-placed nodes, scaled by node price**
(`essence = price(node)`); some crafts pay directly (**objective core +3**);
**essence is fuel, not score** — points come primarily from killing crew;
no-MM matches accrue the pool into **ambient hazard** (automated security
unit at thresholds, spawned from the Node). Implementation is explicitly
queued behind the map system — the map system is SHIPPED, so turn 1 is it.

**Deliverable:** PR `feat(mm): essence engine — node provenance, pricing, pool`.

Design skeleton (agent refines, but must keep the ruling's four rules):

1. **Provenance.** New `mods/game/sl_modebase/essence.lua`, included from
   `init.lua`. Own `on_placenode` handler (the stub has `placenode`/
   `dignode` handlers; the map journal already registers its own — compose,
   don't clobber): record `pos -> price` only when (a) match active,
   (b) `not map.building` (map-placed nodes never pay — beacons, altar, MM
   pad, spawner unit are all placed under `map.building`), (c) the placer is
   a beacon-team player (`game_mode.is_beacon_team`). Sl_weapons residue/
   scorch (no player) never pays.
2. **Pricing.** Introduce `groups.sl_essence_value = N` on node defs (or a
   def field; pick one, document it). Default: 0 (rubble/scaffolding pays
   nothing — the ruling's "cheap scaffolding" line). Wire the crafting
   output defs in `sl_gui/crafting_system.lua` (machine outputs, fortify
   blocks) with real values; **objective core = the named +3 craft**. No
   price table exists today anywhere — this is the greenfield piece.
3. **Credit.** On `on_dignode` of a tracked pos: `pool = pool + price` (any
   digger — MM destroying a bastion pays the MM; that's the intended
   tension), drop the provenance entry. `game_mode.damage_beacon`-style
   API: `game_mode.add_mm_essence(n, source)`.
4. **Pool & spend.** `state.monster_master.essence_pool` (int), reset at
   match start (per-match, like every other match state — document it).
   The spawner unit (`content.lua`, burns 1 essence per spawn from its feed)
   draws pool-first. MM UI/formspec readout in the spawner GUI + `sl_state`
   line.
5. **Ambient hazard.** Match with no MM: pool accrues; at thresholds (e.g.
   10/25/50, make them `settingtypes.txt` knobs) one automated security
   unit spawns from the Node (a minimal custodian: simplest honest route is
   a `MONSTER_TYPES` variant or a tiny entity in `sl_modebase`; `sl_security`
   stays a stub — do not build the anti-cheat shell in this turn).
6. **Not score.** Touch NOTHING in the kill/points path. Add a test that the
   scoreboard values are unchanged by essence activity.

**Tests:** new `tests/essence_test.lua` (stub-only; wire into `soak.yml`
between the weapons step and the live soak):
placement → provenance recorded; dig → credited at price; un-priced node →
0; map-placed node ignored; MM-placed/monster-placed ignored; before-match
placement ignored; objective-core craft → +3 (via the crafting handler);
pool reset at match start; no-MM threshold spawn; points unchanged;
`sl_state`/spawner GUI shows the pool. Then the full ladder + soak.

**Docs:** INTEGRATION → rev 5 (deferred list opens: essence done);
MASTER_DESIGN_FULL §13.3 status line → "implemented"; add the pool reset
semantics to the ruling text.

---

## Turn 2 — Crafting-to-objective loop, end-to-end acceptance

> **DONE — PR #10 merged (`aca248e`), 2026-09-02.** `sl_machine_crafting`
> is a real mod (the Objective Forge, one per map at the `forge` anchor);
> salvage veins seeded on the procedural + test arenas; the Core is
> machine-only again; `/sl_test_objective` performs the chain instead of
> narrating it; `tests/objective_loop_test.lua` (128 assertions).
>
> **What it changed that this plan does not yet reflect:**
> * the whole salvage branch was dead — every salvage recipe outputs a
>   registered node, which the inventory gate refuses. It runs at the
>   Forge now, and the refine yields are batched (4 neon -> 8 components)
>   so a full Core is 5 runs / 20 dug nodes;
> * **the item set this turn's text calls "missing" is not missing** —
>   `metal_ingot` / `circuit_board` / `energy_crystal` / `hardened_plate`
>   / `reinforced_glass` all exist as craftitems. What's missing is
>   *supply*: nothing produces them except `MONSTER_LOOT`, and two have
>   no source at all. Re-read `INTEGRATION` §4.7 before acting on it;
> * `sl_weapons/fabricator.lua` is a **second** machine implementation
>   with its own job engine (`INTEGRATION` §4.8) — read it before adding
>   a third one;
> * `sl_weapons:fabricator` and `sl_modebase:ghost_altar` had dead
>   inventory recipes (registered nodes, gate-refused). They are Forge
>   outputs now, i.e. **the Forge is how crew build stations**;
> * the house-rule list above needs one more line: **never trust
>   `add_item`'s return value in the stub** (it always succeeds) and
>   **never assume `can_dig` gated your `on_dig`** — both cost real bugs.
>
> **Still open from this turn:** the `soak.yml` step for
> `tests/objective_loop_test.lua` is **not committed** (the agent token
> cannot write `.github/workflows/**`). It is written out in
> `INTEGRATION.md` and in the PR #10 body — apply it first chance.

**Gap (INTEGRATION §5.4, "Wedged on this":** `objective_core` node +
`deliver_objective` work (nodes.lua:255–310), the recipe exists
(crafting_system.lua:441), but the chain salvage → machine → core →
delivery → match end has never run, and `sl_machine_crafting` is a stub.

**Deliverable:** PR `feat(objective): salvage-to-delivery loop + acceptance test`.

1. ~~Write `tests/objective_loop_test.lua` FIRST (stub)~~ **— shipped.**
   (The item below is kept for the reasoning, not as a to-do.)
   build map →
   `sl_map.type = test`, objective win condition on → salvage grant →
   craft via `crafting_system` handler → core in inventory → place within 8
   of own beacon → `end_match(team, "delivered the Objective Core")`.
   Negatives: objective mode off (refused); non-beacon team (refused);
   >8 blocks (refused); no active match (refused); MM/ghost can't deliver.
   Assert Turn 1's +3 essence credits on the craft.
2. Then fix what the test proves broken. Expect: the machine chain is the
   real work — decide (and document) the minimal honest form: either
   implement one real station in `sl_machine_crafting` (energy + time per
   its header comment: "advanced crafting stations that require energy and
   time") or fold the forge step into the existing button-based
   `crafting_system` UI and mark `sl_machine_crafting` as deliberately
   shelved in its README. Owner-shaped decision — if genuinely ambiguous,
   ask; the ruling order was "crafts like objective core would also give MM
   essence", i.e. the chain must be real enough to run a match.
3. Wire a match-win smoke assertion (win by objective, not elimination).
4. Full ladder + soak; PR with verification table; CI green.

**Docs:** INTEGRATION rev 6; MASTER_DESIGN_FULL §6.10 status.

---

## Turn 3 — Full-game procedural sound sets (G1 fix)

> **Not started.** One note from Turn 2: the Objective Forge plays
> `minetest.sound_play("alert", ...)`, a name `sl_modebase` already
> uses, so it adds no new entries to the missing-sound inventory.

**Gap:** weapons audio is done (39 `.ogg` via `generate_sounds.py`); the rest
of the game still calls `sound_play("hit")`, `"menu"` etc. from MTG/legacy
assets. Branches `arena/01a044a3-systemtest` + `arena/01a044a2-systemtest`
hold the full-game sets. Lowest-risk of the remaining art tasks (procedural,
no licensing, deterministic).

**Deliverable:** PR `feat(sounds): full-game procedural sound sets`.
- Extract every `sound_play("...")` string literal (grep `mods/`), diff
  against `mods/**/sounds/` inventories; extend `generate_sounds.py` with a
  non-weapons family section (module-import generation only — NEVER the
  full CLI; see house rules) or backport the branch families if they port
  cleanly (they're `fd4e879`-lineage → path-copy per the plan).
- Tests: add a sound-inventory audit to the stub suites
  (`minetest.sound_play` captures names; assert every played name exists in
  the generated set — same idea as W0b's texture/props audit).

---

## Turn 4 — Live-engine combined soak (the "feature complete" claim)

**Gap (INTEGRATION §4.6):"** everything so far is stub-validated; the real
engine has never run map+arsenal+tournament+objective together.

**Deliverable:** PR `test(live): combined live-engine soak`.

`soak.yml` already installs `minetest`/`luanti` and runs a live-engine soak
step (it exists below the stub steps — extend it, don't replace):
- scripted headless server (`minetest --server --config tests/live/*.conf`,
  `singlenode` + `sl_map.type = test`), drive N matches with `aaa_botmatch`
  arena adoption + map reset between matches + weapons spawns + tournament
  start/end; assert: journal restores out-of-volume edits, corpses
  buried/cremated, beacons full-HP after reset, mob purge, objective
  delivery ends the match, `/sl_tournament` season rows persist, zero Lua
  errors in the server log.
- Keep it a required check only after it's green twice in a row locally +
  on CI; until then mark `continue-on-error` with an open issue note —
  never block the suite ladder on a flaky live job.

---

## Turn 5 — Deployment tooling hardening

**Gap (INTEGRATION §4.5):** `websocket_proxy.js` accepts arbitrary
client-supplied destination IP:port (incl. loopback), no allowlist/auth/
timeouts; unsafe to expose. Runbooks (DEPLOY_SERVER/PUBLIC_DEPLOY/FREE_
HOSTING) shipped already.

**Deliverable:** PR `feat(deploy): harden websocket proxy + docker all-in-one`.
- Allowlist via env (`SL_PROXY_ALLOW=<host:port,...>`; default: deny all
  and refuse loopback/private ranges unless explicitly listed), per-route
  auth token, connect+idle timeouts, per-IP rate limit, redacted logs.
- `tests/proxy_test.mjs` with `node:test` (no deps): rule table, denied
  destination refused, token required, timeout closes.
- Real external-join test (two processes, per the runbook) and the docker
  all-in-one given the same defaults + secrets via env.
- Re-run the PR #6 review's exact complaint list as acceptance.

---

## Turn 6 — Art baseline (owner-gated) + doc reconciliation

**Gap:** 285 textures across FOUR competing passes (`01a04c31`,
`01a04bfa`, `01a0487d`, `01a049ee`). Never port two. Current weapon art is
37 16×16 solid-colour placeholders (90–101 bytes).

1. Survey-only deliverable first: contact sheets + per-branch diff stats
   vs master + a pick recommendation. **Gate: owner decides the pass.** If
   no decision, this turn stops at the survey + decision request (posted
   on the PR, like PR #6's review).
2. Once picked: curate (16×16 RGBA; every referenced texture exists — add a
   texture-reference audit assertion to the stub suites), in-engine visual
   smoke (headless render/screenshot if the harness allows), drop the
   winners, keep 0-byte/placeholder-free.
3. Same turn: reconcile `ROADMAP.md`'s stale "procedural mapgen is
   abandoned" line with the shipped map system + owner's map-policy ruling
   (procedural default stands, now position-configurable).

---

## Turn 7 — Green web release + design-decision requests

**Gap (INTEGRATION §5.5):** WASM build fails (exit 77); `gh-pages` frozen.
1. Reproduce `release.yml`'s web job locally, capture the real error into a
   diagnosable artifact (workflow logs + upload), fix the documented
   blocker (historically: emsdk/libarchive pin — see the `pin luanti-wasm`
   commit lineage), then advance `gh-pages` with the standard release
   verification (project-server join runbook).
2. Owner decision request doc (one per question, options + recommendation):
   §17.1 underground layer (a full content slice — its own multi-feature
   arc if ruled yes), §17.3 season trade, §17.4 one-shot weapons vs the 1 s
   pillar (exempt mortar/lance or retune — small if ruled), §17.5
   tournament ballot (confirm absent). Implement only what gets ruled;
   leave every unruled question in INTEGRATION §5 with a date.

---

## Backlog (low urgency, do NOT start before Turns 1–2)

- `01a04377` Monster Spawner Unit + horror mobs — overlaps `sl_scary`;
  produce a real diff first (never blind-port).
- `feat/wp5-system-inventory-gui` — highest risk (diverged `sl_gui`),
  lowest urgency; only after an `sl_gui` divergence audit.
- Arena economy detail from the ruling's spirit: machine/fortify pricing
  pass once essence pricing lands (Turn 1) so every craft output has a
  defensible `sl_essence_value`.

## Arc-exit criteria

`docs/INTEGRATION.md` has an empty deferred list except explicitly
owner-gated items; all suites + the live soak green; every §17 question
either ruled-and-implemented or dated-deferred; the six-item "feel
checklist" (§18) is re-run against the build and documented turn by turn.
