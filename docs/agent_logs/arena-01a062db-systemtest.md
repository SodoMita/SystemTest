# Turn 2 — crafting-to-objective loop (objective-loop turn)

**Date:** 2026-09-02 · **Branch:** `arena/01a062db-systemtest` · **Base:**
`master` @ `43998d6` (PR #9 merged — Turn 1, the MM essence engine, is in).

Scope was read off `docs/NEXT_AGENT_PLAN.md` **Turn 2** and
`docs/INTEGRATION.md` §5.4 ("Wedged on this"): the `objective_core` node and
`deliver_objective` worked, the recipe existed, but the chain
**salvage → machine → core → delivery → match end** had never run, and
`sl_machine_crafting` was a 6-line stub.

## What was actually broken (found while writing the test)

1. **The whole salvage branch was dead.** The inventory UI refuses any
   recipe whose output is a registered node (§6.5 "placeables come only
   from machines"). Every salvage recipe outputs a node
   (`construction:plasma`, `sl_modebase:loot_crate`, …), so *nothing* in
   the salvage branch could be crafted anywhere. Only the three
   `sl_clothing:*` recipes worked.
2. **The exotic neon types existed on no map.** `ground:rhombus_neon`,
   `ground:x_neon` and `ground:x2_neon` are the ingredients of every
   component, and the generators only ever place `square_neon` (floor) and
   `square_neon_opaque` (walls). The Core was literally uncraftable.
3. **The +3 craft had an escape hatch.** `objective_core` carried
   `sl_craft_in_inventory = 1`, added by Turn 1 with the comment "until
   the machine chain lands (objective-loop turn)". That turn is this one.
4. **`/sl_test_objective` narrated the steps without performing them.**
   `run_headless_objective_test` pushed six strings into a log and called
   `deliver_objective` directly — a green test that tested nothing.

## What shipped

**`sl_machine_crafting` is now a real mod — the Objective Forge**
(`mods/game/sl_machine_crafting/init.lua`, + `mod.conf`, + `README.md`):

- One per map, placed by the map system at the new **`forge` anchor**
  (procedural + test + schematic; `sl_map.forge_pos` / `map.conf`
  `forge.pos` overrides; carried on the descriptor layout so resets are
  drift-free, and serialized in `anchor.forge`).
- Runs **exactly** the recipes the inventory refuses — same predicate
  (`minetest.registered_nodes[output]`), and it resolves its list from
  `get_crafting_recipes()` (new read-only accessor added to
  `crafting_system.lua`), so the two sides cannot drift and no recipe is
  declared twice.
- **Loud:** starting and finishing a run broadcasts the job and the
  forge's coordinates to every player.
- **Time-gated and single-job** (`sl_machine.forge_time`, default 20 s);
  input slots lock while a job runs.
- **Risk:** the charge is consumed up front; a job abandoned by the match
  end (or by destroying the forge) pays out nothing. `can_dig` is false
  while a match is live — griefing the economy is not a mechanic.
- Crew-only (beacon teams, during a match); MM and ghosts refused on both
  `on_rightclick` and the field handler. `groups.possessable = 1` so an
  evil ghost can sabotage it.
- Fires `game_mode.on_craft_essence` on completion, so **the Core still
  pays the named +3** (ruling §13.3 rule 2) — now from the machine.

**Objective Core** lost `sl_craft_in_inventory`, gained
`groups.objective = 1` and `stack_max = 1` (§6.10 A).

**Salvage veins** seeded on the procedural arena (mirrored, seeded like
the cover blocks, RNG drawn *after* the mob scatter so the existing
stream is untouched) and fixed on the test arena. They sit **on** the
floor plane, never in it — scavenging can't punch a hole through the
arena.

**Recipe rebalance:** refine yields batched (4 neon → 8 components,
8 neon → 2 crates). A full Core is now 5 forge runs / 20 dug nodes
instead of ~30 runs.

**`/sl_state`** gained a `Forge: <job> (Ns left)` / `Forge: idle` line.

**`/sl_test_objective`** now *performs* the chain: scavenge the veins →
refine → forge the Core → deliver → match end, failing loudly at the
step that fails.

## Tests

- **New `tests/objective_loop_test.lua` — 99 assertions.** Mod-load
  invariants (gate == machine predicate, `stack_max`, no opt-in), forge
  anchor + materialization, vein seeding + scavenging, inventory refuses
  every placeable, single-job/time-gated/loud runs, input locking, the
  refine chain, the Core run + +3 essence, delivery refusals (>8 blocks,
  MM, objective mode off, no active match), the winning delivery, reset,
  match-end forfeit, access control (both entry points), and
  `/sl_test_objective`.
- **`tests/essence_test.lua` 61 → 69.** Phase E10 was rewritten: it now
  asserts the Core is refused in the inventory and routes the +3 through
  the Forge. The +3 assertion itself is unchanged — only the route
  moved, which is exactly what Turn 1's "until the machine chain lands"
  comment said would happen.
- **Stub (`tests/minetest_stub.lua`): node timers added** — additive
  only, driven from `M.step`, so `H.advance()` runs them like the engine.

Golden ladder after the change:

| Suite | Result |
|---|---|
| `luajit tests/smoke_test.lua` | 193/193 |
| `luajit tests/strand_test.lua` | 84/84 |
| `luajit tests/weapons_test.lua` | 288/288 |
| `luajit tests/essence_test.lua` | 69/69 |
| `luajit tests/objective_loop_test.lua` | 99/99 |
| `luajit tests/soak_stub_turbo.lua` | PASS |
| LuaJIT `-bl` syntax gate over `mods/**/*.lua` | clean |

PUC 5.1 parity: **not run** — no `lua5.1` binary in this sandbox, no root
for apt. CI runs the suites under `luajit`.

## Owner-shaped decision (recorded, not asked)

The plan flagged "implement one real station vs fold the forge into the
button UI" as an owner decision. It was already answered in the code:
Turn 1's `sl_craft_in_inventory` comment and `MASTER_DESIGN_FULL` §6.5 /
§6.10 both say **placeables come only from machines**, and the machine
gate was already live. So the machine chain was built and the opt-in
removed. The remaining §6.10 B ambition — five stations and a two-step
Core via `core_frame` — needs an intermediate item set
(`metal_ingot`, `circuit_board`, `energy_crystal`, `hardened_plate`,
`reinforced_glass`) that is not content yet; it is filed in
`INTEGRATION.md` §4.7 rather than faked.

## CI wiring — NOT committed (needs a token with `workflows: write`)

Same blocker as Turn 1: this session's GitHub App token cannot create or
update `.github/workflows/**`, and the push is rejected wholesale if the
branch touches one. The step is prepared and verified locally; it goes
into `soak.yml` **between the essence suite and the turbo soak**:

```yaml
      - name: Objective loop stub suite (scavenge -> forge -> deliver -> win)
        run: luajit tests/objective_loop_test.lua
```

Apply it with a token that has `workflows: write`, or let the owner merge
a one-line PR.

## Handed on

- **Turn 3** (full-game procedural sound sets): unchanged. Note the Forge
  calls `minetest.sound_play("alert", …)`, a name `sl_modebase` already
  uses — no new sound inventory debt.
- **Turn 4** (live-engine soak): the objective chain is now worth adding
  to the live soak — scavenge → forge → deliver under a real engine.
- `content/workshops` remains entirely commented out and
  `sl_energy` / `sl_security` remain stubs; deliberately untouched.
