# The Salvage Plan — bringing `sl_weapons` across the family split

**Author:** jax (`arena/01a05890-systemtest`) · **Date:** 2026-08-31
**Status:** **plan only.** This branch is an ideas branch: nothing below has been
executed here, and I am not proposing to execute it here. This is the document
whoever owns the trunk hands to whoever does the port.
**Companions:** `docs/jax_branch_survey.md` (the territory),
`docs/jax_weapon_audit.md` (the numbers).

---

## 0. The one-paragraph version

A complete ranged arsenal (`mods/game/sl_weapons/`, ~3,300 lines, eight weapons,
sentries, corpses, pads, 1,756 lines of tests, a 982-line spec) sits on
`arena/01a04d5b-systemtest`, in a branch family that shares **no common ancestor**
with the family every agent is working in today. It therefore cannot be merged
by `git merge`. It does not need to be: the mod is self-contained, its host-side
hooks are all written as `if sl_weapons and sl_weapons.X then`, and the API it
calls already exists on our side. **The port is a directory copy plus five small
guarded hooks — not a history merge.** Roughly a day of careful work, most of it
verification.

---

## 1. The constraint, stated once

```
merge-base origin/master origin/arena/01a04d5b-systemtest      -> (empty)
merge-base origin/agent-comms origin/arena/01a04d5b-systemtest -> (empty)
```

**Correction to my own survey, owed to carmack (`20260831T170141Z-91b42f`):** I
reported *three* roots; my clone is shallow (`.git/shallow` contains `0446adc`
and `457ccb9`), so `master` and `agent-comms` looked unrelated to me and are not.
Two families, not three. The split that matters is unchanged in every clone:
**`fd4e879` family (16 branches, the engineering history) vs the snapshot family
(where we all live).**

### Bridge sizing (the artifact carmack asked for)

| Comparison, `mods/` only | Files | +/− |
|---|---|---|
| `457ccb9` (master snapshot) → weapons tip | 68 | +3,862 / −231 |
| `agent-comms` → weapons tip | 79 | +3,862 / −1,400 |
| Files that exist **only** on the weapons tip | **50** | 12 Lua + 38 textures — i.e. `sl_weapons` and nothing else |

The −1,400 on the second row is almost entirely `mods/game/sl_strand/`, which
*we* have and *they* do not. **Nothing on our side is deleted by this port.**

---

## 2. Three ways across, and why I pick the middle one

| | Method | Cost | Verdict |
|---|---|---|---|
| **A** | `git merge --allow-unrelated-histories` | Conflicts in every one of the ~18 host files that diverged for unrelated reasons (tournament mode, UI rework, sl_scary changes). Drags two days of unrelated divergence into the trunk. | **No.** |
| **B** | **Path copy: `git checkout <ref> -- mods/game/sl_weapons`, then hand-apply five hooks** | Loses the weapons branch's commit history (the port is one commit that names the source SHA). Surgical; nothing unrelated crosses. | **Recommended.** |
| **C** | `git format-patch` the ~40 `feat(weapons)`/`fix(weapons)` commits and replay | Best history fidelity; every patch that touches a diverged host file needs manual fixing. Days, not hours. | Only if the owner wants the archaeology. |

Option B is not a compromise here. The mod was *written* to be droppable: its
match plumbing wraps `game_mode.start_new_match` / `end_match` at runtime
(`sl_weapons/init.lua`) rather than editing them, and every host callsite is
guarded. That is a deliberate design choice by whoever wrote it, and it is what
makes this cheap.

---

## 3. The manifest

```bash
# Source of record — pin the SHA in the commit message.
SRC=origin/arena/01a04d5b-systemtest   # 9a251fe, "v1.3.9"

# 1. the mod (12 lua + mod.conf + 38 textures)
git checkout $SRC -- mods/game/sl_weapons

# 2. the specs (they are the review gate; port them or the port is folklore)
git checkout $SRC -- WEAPONS_SPEC.md WEAPONS_COUNCIL.md

# 3. the tests + the stub extensions they need (+503 lines, additive)
git checkout $SRC -- tests/weapons_test.lua tests/soak_stub_turbo.lua
#    tests/minetest_stub.lua: DO NOT take wholesale — ours has diverged.
#    Port the block headed "sl_weapons extensions (additive …)" only.

# 4. the incident log — read before touching the mortar
git checkout $SRC -- docs/agent_logs/2026-08-29-mortar-segfault.md
```

`mod.conf` declares `depends = sl_modebase, default`, `optional_depends = sl_gui`,
`min_minetest_version = 5.6`. All satisfied on our side.

### API check — done, and it passes

`sl_weapons` calls 14 `game_mode.*` entry points. **Thirteen exist on
`agent-comms` today** (`get_player_state`, `is_possessed`, `refuse_if_possessed`,
`is_sabotaged`, `refuse_if_sabotaged`, `damage_beacon`, `set_monster_master`,
`start_new_match`, `end_match`, `release_possession`, `broadcast`, `pos_hash`,
`state`). **One does not: `register_pickup_roll`** — see hook 1.

---

## 4. The five host hooks (~35 lines total, all guarded)

1. **`sl_modebase/content.lua` — the weighted pickup table.** Replace the flat
   four-item `pickup_loot` list with the weighted `{item, count, weight}` form and
   add `game_mode.register_pickup_roll(item, count, weight)` /
   `game_mode.get_pickup_rolls()`. ~25 lines. This is the only *new* API, and
   it is how ammo enters the loot economy. Without it, guns spawn with no
   ammunition supply.
2. **`sl_modebase/match.lua`, in `register_on_dieplayer`** — corpse capture:
   ```lua
   if sl_weapons and sl_weapons.capture_death_items then
       sl_weapons.capture_death_items(player, pos, inv)
   else
       <existing drop loop>
   end
   ```
3. **`sl_modebase/entities.lua`, monster `on_punch`** — 4 lines:
   `if sl_weapons and sl_weapons.melee_entity_hit then sl_weapons.melee_entity_hit(hitter) end`
4. **`sl_scary/init.lua`** — the same 4 lines at four monster `on_punch` sites.
5. **`sl_gui/achievement_system.lua`** — optional; the match-end reset hook the
   mod calls. Skip on the first pass; achievements are not load-bearing.

Hooks 2-5 are no-ops when the mod is absent, so they can land **before** the mod
in a separate commit and break nothing. That is the safe ordering.

---

## 5. What deliberately does NOT come across

The weapons branch also carries tournament seasons, a workshops-from-spoils
economy, an inventory/UI rework, and sl_scary changes. **None of it is required
by `sl_weapons`** and all of it collides with our side. Leave it. If the table
wants tournament mode, that is a second, separately argued port.

---

## 6. Known gaps the port inherits (do not discover these later)

| # | Gap | Where | Fix |
|---|---|---|---|
| G1 | **No audio ships.** 30+ `sl_weapons_*` sound names are referenced; the mod contains **zero `.ogg` files**, and neither `generate_sound_assets.py` nor `generate_sounds.py` knows the name `sl_weapons`. Every gun is currently silent. | `weapons.lua`, `pads.lua`, `corpses.lua` | Generate the set. **This is not cosmetic:** the spec's whole answer to "guns break deduction" is *sound is information*. A silent arsenal is a broken design, not a rough one. |
| G2 | **The bare hand still out-damages five of six melee tools** (1 dmg / 0.1 s = 10 DPS) — unchanged on the weapons branch too. | `sl_hand/init.lua` | Raise the interval or drop the hand to a non-combat tool. One line. |
| G3 | **The live-engine soak still never fires a weapon**: `run_soak.py:92` sets `enable_damage = false`; `aaa_botmatch/behavior.lua:544` applies a flat synthetic `combat_damage = 5`. | soak harness | Bots read the wielded `tool_capabilities` and pull triggers. |
| G4 | Five melee tools (pick, axe, shovel, drill, energy blade) still have **no recipe, no loot, no kit** on any branch. Only the Combat Blade gained one (2 ingots, `sl_weapons/init.lua:127`). | `crafting_system.lua` | Six recipes in the `equipment` category. |
| G5 | `CRAFTING_GUIDE.md` still sends the player to an **Objective** tab that exists on no branch. | `CRAFTING_GUIDE.md` | Reconcile or relabel. |
| G6 | The mod header claims **WP9**, which is not in `AGENT_PARALLEL_PLAN.md`, so `--to wp9` routes nowhere and `lint` warns. | plan doc | Add WP9, or the port has no addressable owner. |

---

## 7. Verification ladder — in this order, no skipping

1. `lua51 tests/weapons_test.lua` — 288 assertions. Must be green before anything
   else is believed.
2. `lua51 tests/soak_stub_turbo.lua 40 <seed>` × 3 seeds — the Phase W exit gate
   the branch already defines: **no weapon > 30 % of kills**, Grapple-Lash holders
   die at ≥ the rate of non-holders, zero Lua errors, clean inter-match sweep.
   *(Correction to my own earlier claim: this harness exists and does exercise
   real weapon logic. What has never happened is a **live-engine** measured
   match — the branch's own README calls the engine soak "the CI authority" and
   the stub soak "the fast local verdict".)*
3. `python3 tests/soak/run_soak.py` after G3 is fixed — the first time these guns
   are measured by the authority.
4. Owner playtest, one match, guns audible (G1 fixed first).

---

## 8. Rollback

`rm -rf mods/game/sl_weapons` and the game runs exactly as it does today: the five
hooks are guarded and become no-ops. That property is worth protecting — **do not
"simplify" the guards away** after the port.

---

## 9. Second wave, ranked by value over risk

Everything below is also stranded on the `fd4e879` family. Same method, harder
each step down:

1. **Match map system** (`01a0487f`) — procedural / test / handmade `.mts` with
   initial-state reset. The arena is currently hand-placed nodes; this is the
   biggest single unlock and it is mostly additive.
2. **Procedural sound sets** (`01a044a3`, `01a044a2`) — solves G1 for the whole
   game, not just weapons.
3. **Art passes** (`01a04c31`, `01a04bfa`, `01a0487d`, `01a049ee`) — four
   *competing* passes. Someone has to pick one; do not port two.
4. **Monster Spawner Unit + horror mobs** (`01a04377`) — overlaps our `sl_scary`;
   needs a real diff first.
5. **WP5 inventory GUI** (`feat/wp5-system-inventory-gui`) — collides with our
   `sl_gui` divergence. Highest risk, lowest urgency.

---

## 10. What the owner has to decide (nobody else can)

1. **Which family is the trunk.** Every ruling this week landed on the family
   with less game in it. Until this is answered, "add six recipes" is not even
   the right fix.
2. **Who owns the port** — and whether WP9 exists.
3. **Whether the arsenal is canon.** Eight guns change the identity game the
   council has spent a day designing. The spec argues they *are* the deduction
   loop (sound, pads, chimes, corpses). I now agree — but it is a design ruling,
   not a merge decision, and it should be made out loud before 3,300 lines land.

I don't move the herd without being told which valley we're heading for. This is
the map of both valleys and the cost of the crossing.

-- Jax // Sky-Metal strip
