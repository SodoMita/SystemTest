# sl_machine_crafting — the Objective Forge

Machine crafting for **System Looting**. One station today; the full
five-station plan is deferred (see below).

## The rule it exists to enforce

> Placeable, structural, deployable or world-affecting outputs are never
> produced by personal inventory crafting. They come from a machine: the
> machine owns the recipe, the input slots, the processing time and the
> risk.
> — `MATCH_LOOP_SPEC.md` (Crafting model), `MASTER_DESIGN_FULL.md` §6.5 / §6.10

`sl_gui/crafting_system.lua` enforces its half of the rule by refusing
any recipe whose output is a **registered node**. This mod is the other
half: the Forge runs exactly those recipes. Both sides call the same
predicate (`minetest.registered_nodes[output] ~= nil`), and the Forge
resolves its list from `get_crafting_recipes()` — the one registry — so
the two sides cannot drift and no recipe is ever declared twice.

## The Objective Forge — `sl_machine_crafting:objective_forge`

| Property | Value |
|---|---|
| Placement | **1 per map**, placed by the map system at the `forge` anchor |
| Position | neutral midfield; overridable with `sl_map.forge_pos` (`x,z`) or `forge.pos` in a handmade map's `map.conf` |
| Operation | beacon-team crew only, during an active match |
| Run time | `sl_machine.forge_time` seconds (default 20) |
| Concurrency | **one job at a time** — the queue is the contention |
| Inputs | 8 `src` slots, locked while a job runs |
| Output | 4 `dst` slots; a full output spills the item on the floor |
| Loudness | starting and finishing a run is broadcast to **every player** with the forge's coordinates |
| Risk | the charge is consumed **up front**; a job abandoned by the match end (or by the forge being destroyed) pays out nothing |
| Mining | `can_dig` is false while a match is live — griefing the economy is not a mechanic |
| Possession | `groups.possessable = 1`, so an evil ghost can seize it (bounded sabotage, `sl_modebase`) |

### Why one station and not five

`MASTER_DESIGN_FULL.md` §6.10 B plans five stations and a two-step Core
(Assembly Station → `core_frame` → Objective Forge → `objective_core`).
Until that lands, **every** machine-gated recipe runs here.

The blocker is **supply, not content** — the first draft of this section
got that wrong. `metal_ingot`, `circuit_board`, `energy_crystal`,
`hardened_plate` and `reinforced_glass` are all registered craftitems
(`sl_modebase/content.lua`). But **nothing makes them**: they come only
from `MONSTER_LOOT`, and `hardened_plate` / `reinforced_glass` have no
source at all. Re-authoring the Core over that chain would move the win
condition from *scavenging* to *hunting* — a balance call, not a
plumbing one. Tracked in `docs/INTEGRATION.md` §4.7.

### Known debt: two machine implementations

`sl_weapons/fabricator.lua` (the **Precision Fabricator**) already
existed when this mod landed, and it duplicates the job plumbing: its
own `W.FAB_RECIPES` table, a globalstep job queue, its own formspec.

They do not conflict — the recipe sets are disjoint, and the
Fabricator's outputs (weapons, Grapple Lash, Sentry Kit) are not in the
shared crafting registry at all. But the job engine should be one
engine, not two. Unification is deliberately deferred: the Fabricator
carries the 288-assertion weapons suite, and re-pinning that suite is a
job of its own. When it happens, unify **onto** the Forge's node-timer
engine (`docs/INTEGRATION.md` §4.8).

One useful side effect: the Fabricator and the Ghost Altar are
registered *nodes*, so their `register_craft_recipe` entries were
already refused by the inventory gate — dead recipes with no machine to
run them. They are Forge outputs now, which means **the Forge is how
crew build stations**, exactly as the design intends.

## The loop this unlocks

```text
scavenge the salvage veins  ->  8 square / 4 rhombus / 4 x / 4 x2 neon
        |
        v   (5 forge runs, 20 s each, each announced to the arena)
Objective Forge:  neon -> plasma / thermal / sparks / loot crates
        |
        v
Objective Forge:  2 crates + 5 plasma + 5 thermal + 5 sparks
                  -> SYSTEM OBJECTIVE CORE   (+3 MM essence, §13.3 r2)
        |
        v
carry it to your beacon, place it within 8 blocks
        |
        v
game_mode.deliver_objective(team, name)  ->  end_match(team, ...)
```

Salvage veins are seeded by the procedural generator (mirrored, like the
cover blocks) and fixed on the deterministic test arena. They sit **on**
the floor plane, never in it, so scavenging cannot punch a hole through
the arena.

**A handmade (schematic) map seeds no veins** — the schematic is the
author's content. It still gets a forge (`forge.pos` in `map.conf`), so
a handmade map that does not place all four raw neon types has a forge
it cannot feed. See `mods/game/sl_modebase/maps/README.md`.

## API

```lua
sl_machine.FORGE_NAME                    -- "sl_machine_crafting:objective_forge"
sl_machine.forge_time()                  -- run time in seconds
sl_machine.get_recipes()                 -- {{ id = <index>, recipe = <def> }, ...}
sl_machine.start_job(pos, entry, name)   -- -> ok, err
sl_machine.abandon_job(pos, meta, reason)
sl_machine.status()                      -- nil | { present, running, output, left, ... }
sl_machine.forge_formspec(pos, meta)
```

## Test

`tests/objective_loop_test.lua` (128 assertions) runs the whole chain
headlessly: veins (test **and** procedural arenas) → refuse-in-inventory
→ refine → core → +3 essence → delivery refusals → winning delivery →
reset → forfeit → access control → `/sl_test_objective` → hardening (refused digs, both-direction
slot locks, match-end sweep) → the Core survives death and is
consumed by no recipe → output spill → stations as forge outputs.
