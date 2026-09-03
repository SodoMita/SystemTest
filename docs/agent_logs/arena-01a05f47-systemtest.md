# Session log — arena/01a05f47-systemtest (Turn 1: MM essence engine)

**Date:** 2026-09-02 · **Agent:** agent-01a05f47 (WP2) · **Branch:** `arena/01a05f47-systemtest`
**Base:** `a5ae568` (handover plan commit) on top of `master` @ `8b2c6e7` (PR #6)
**Plan ref:** `docs/NEXT_AGENT_PLAN.md` Turn 1

## What shipped (commit `54a0f57`)

The MM essence engine per the owner's ruling (`MASTER_DESIGN_FULL.md` §13.3):

1. **Provenance** — `mods/game/sl_modebase/essence.lua` (new, included from
   `init.lua` after `content.lua`). Own `on_placenode` handler composes with the
   map journal (both run): records `pos -> price` only when a match is active,
   `not map.building`, and the placer is a beacon-team player. Sl_weapons
   residue/scorch (no player) never pays; MM-placed and monster-placed never pay.
2. **Pricing** — `groups.sl_essence_value = N` on node defs (documented choice;
   default 0 = cheap scaffolding). Values wired on the craftable output defs:
   fortify blocks firenode/water/snowflake2 = 1, plasma2 = 2, loot crate = 1,
   hide_spot = 2, monster spawner unit = 4, objective core = 5.
3. **Credit** — `on_dignode` of a tracked pos credits the pool at price (any
   digger — MM destroying a bastion pays the MM) and drops the provenance entry.
   Public API: `game_mode.add_mm_essence(n, source)` (refuses outside a match).
4. **Pool & spend** — `state.monster_master.essence_pool` (int), reset at match
   start AND match end (`game_mode.essence_reset` called from `start_new_match`
   and `end_match`); the spawner unit draws the pool first, its feed covers the
   rest; fuel check now counts pool + feed. Spawner GUI + `/sl_state` read out
   the pool.
5. **Ambient hazard** — no-MM matches accrue the pool; at thresholds (knob
   `sl_essence.thresholds`, default 10,25,50) one automated security unit
   (new `custodian` MONSTER_TYPES variant) spawns from the Node (mm_pad anchor).
6. **Not score** — zero touches to the kill/points path; regression test asserts
   scoreboard values are unchanged by essence activity.
7. **Objective core craft** — the named +3 craft. The core's def opts into
   inventory crafting via `sl_craft_in_inventory = 1` (the only node that does;
   everything else stays machine-gated); the crafting handler fires
   `game_mode.on_craft_essence` on completion, crediting +3 from
   `ESSENCE_CRAFT_CREDITS` (scales to the Objective Forge).

## Tests

`tests/essence_test.lua` — 61 assertions, stub-only, mirroring the smoke
pattern (players, test map, `start_new_match`):
placement -> provenance; dig -> price; un-priced -> 0; map.building ignored;
MM/placerless ignored; pre-match ignored; machine gate regression; core craft
+3; non-named craft 0; points unchanged; `/sl_state` line; spawner GUI pool
label; pool-first spend with empty feed; pool reset at match start/end;
hazard at 10/25 (not at 30), none while an MM is live; custom thresholds
20,40 honored; `essence_price` reads def groups.

Golden ladder (all green after the change):
- smoke 193/193 · strand 84/84 · weapons 288/288 · soak PASS · essence 61/61
- syntax gate clean across `mods/**/*.lua` (LuaJIT -bl)
- PUC 5.1 parity: NOT run — this sandbox has no lua5.1 binary, no root for
  apt, and no network to lua.org; the soak CI runs the suites under `luajit`.

## CI wiring — NOT committed (needs owner)

The one soak.yml step (between the weapons turbo soak and the live soak):

```yaml
      - name: MM essence engine stub suite (provenance, pricing, pool, hazard)
        run: luajit tests/essence_test.lua
```

This session's GitHub App token lacks the `workflows` permission — pushes
containing any `.github/workflows/**` change are rejected by GitHub
("refusing to allow a GitHub App to create or update workflow …"). The step is
prepared and verified locally; apply it with a token that has `workflows: write`
(or the owner merges a one-line PR).

## House-rule compliance

- No `generate_sounds.py` CLI run; nothing reverted from the do-not-retry list.
- Stub change is additive only: `PlayerMeta:set_inventory_formspec` /
  `get_inventory_formspec` (engine parity; crafting_system routes through it).
- Soak RNG pin untouched (`sl_map.seed=424242`, `sl_map.mobs=0`,
  `mm_auto_assign=false`); custodian appended last in `MONSTER_TYPE_ORDER` so
  deterministic arenas (budget 6) are unchanged.

## Open items handed on

- **Turn 1 leftover:** soak.yml wiring (above) — blocked by token permission.
- **Turn 2 (next):** crafting-to-objective loop — the objective-core inventory
  craft now works (+3), but the machine chain (`sl_machine_crafting`,
  `content/workshops`) is still a stub; decide the minimal honest form there.
  The essence hook (`ESSENCE_CRAFT_CREDITS`) is ready for the forge step.
- The rest of the multi-turn plan (Turns 3–7) is unchanged.
