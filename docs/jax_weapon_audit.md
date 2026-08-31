# The Armory Audit — what the weapons in this game actually do

**Author:** jax (`arena/01a05890-systemtest`) · **Date:** 2026-08-31 ·
**Status:** findings, verified against the tree at commit time. Arithmetic is
reasoned, not measured — see §5.

Every number below came from reading files, not from remembering them. Where I
could not verify something, it says so.

---

## 1. The armory, in full

Six weapons exist. All six are registered in one place —
`mods/game/sl_modebase/content.lua:51-114` — by the helper
`register_tool_basics()`.

| Weapon | file:line | `fleshy` | `full_punch_interval` |
|---|---|---|---|
| Combat Blade | `content.lua:63` | 6 | 0.8 |
| Breaching Pick | `content.lua:70` | 3 | 1.0 |
| Tactical Axe | `content.lua:79` | 5 | 1.0 |
| Trench Shovel | `content.lua:88` | 2 | 1.0 |
| Energy Blade | `content.lua:97` | 12 | 0.6 |
| Power Drill | `content.lua:104` | 4 | 0.8 |
| **Neon Hand** (empty hand) | `mods/apis/sl_hand/init.lua:6` | **1** | **0.1** |

Player HP is 20 (`spawn.lua:40`, `content.lua:147` — `hp_max or 20`).

Ranged weapons: **none.** `grep -rn "projectile\|bullet\|shoot\|firearm" mods/
--include=*.lua` returns one hit, `sl_scary/init.lua:202`, and that is an
`add_velocity` shove by a monster. There is no projectile system in this game.

---

## 2. Time to kill (20 HP, no armour)

`TTK = (hits_to_kill - 1) x full_punch_interval`.

| Weapon | DPS | hits | TTK |
|---|---|---|---|
| Energy Blade | 20.0 | 2 | **0.6 s** |
| **Neon Hand (empty)** | **10.0** | 20 | **1.9 s** |
| Combat Blade | 7.5 | 4 | 2.4 s |
| Tactical Axe | 5.0 | 4 | 3.0 s |
| Power Drill | 5.0 | 5 | 3.2 s |
| Breaching Pick | 3.0 | 7 | 6.0 s |
| Trench Shovel | 2.0 | 10 | 9.0 s |

**The empty hand is the second-best weapon in the game.** It out-damages the
Combat Blade, the Tactical Axe, the Power Drill, the Breaching Pick and the
Trench Shovel. Five of six weapons are a downgrade from carrying nothing.

The Medkit (`content.lua:141`) restores 8 HP per use with no cooldown and no use
limit. Against anything below the Combat Blade, a defender with a stack of
medkits out-heals the attacker.

---

## 3. Nothing can be obtained

For each of the six weapons, `grep -rn <name> mods/ tests/` returns **hits only
at the registration site in `content.lua`**. Zero references anywhere else.

- **No craft recipe.** The live recipe list is
  `mods/apis/sl_gui/crafting_system.lua:306-451` — 16 recipes, none of them a
  weapon. The `equipment` tab holds a backpack, a jacket and boots.
- **No loot.** `pickup_loot` (`content.lua:324`) is four salvage items.
- **No spawn kit.** `spawn.lua:115-124` grants a sabotage charge and a
  reincarnate item; nothing else.
- **No engine recipe.** There is exactly one `minetest.register_craft()` in
  `sl_modebase` (`content.lua:847`) and it makes the scanner.

Flare and Medkit have the same problem: registered, never obtainable.

---

## 4. The published guide describes a different game

`CRAFTING_GUIDE.md` documents 20 recipes across four tabs. The code has 16
recipes, and the only output the two lists share is `objective_core` — whose
ingredients differ (guide: Power Cell + Sensor Array + Hardened Plate x2 +
Circuit Board x4; code `crafting_system.lua:441`: loot_crate x2 + plasma x5 +
fire x5 + sparks x5).

The guide also tells the player to "pick a category: Salvage, Equipment,
Tactical, or **Objective**". The tab list at `crafting_system.lua:66-71` is
Salvage / Equipment / Tactical / **Information**. There is no Objective tab, and
the Objective Core recipe is filed under `category = "information"` with the
comment `-- Moved to information for now`.

---

## 5. The balance harness has never fired a weapon

`tests/soak/run_soak.py` is the project's only balance instrument. Two facts
about it:

1. Its world config sets `enable_damage = false` (`run_soak.py:92`).
2. Bot combat does not use a wielded item at all. `botmatch.punch_player()`
   (`aaa_botmatch/behavior.lua:542`) builds a synthetic capability table —
   `{ full_punch_interval = 1.0, damage_groups = { fleshy = damage } }` — with
   `damage = botmatch.config.combat_damage`, a flat **5** set at
   `aaa_botmatch/init.lua:48`, then applies it with a direct `set_hp()`.

So every K/D, damage-dealt and win-rate figure this project has produced
describes a weapon that does not exist in the game: 5 damage on a 1.0 s swing.
By coincidence that is the Tactical Axe and nothing else. The 2-to-12 damage
spread in `content.lua` has never been executed by a computer.

**The one number I did not measure:** whether the engine actually lets a client
punch every 0.1 s sustained. Luanti scales punch damage by time since the last
punch, and the client's punch rate is its own limit, so the Neon Hand's 10 DPS is
a ceiling, not an observation. That single unknown is the difference between
"the hand is the second-best weapon" and "the hand is fine". It is one soak run.

---

## 6. What I would do about it

Three changes, one file each:

1. `mods/apis/sl_gui/crafting_system.lua` — add the six weapon recipes to the
   `equipment` category, which already exists and already works. This is the
   whole acquisition problem, solved in the file that already solves it for
   jackets.
2. `mods/game/aaa_botmatch/behavior.lua:542` — read the attacker's wielded item's
   `tool_capabilities` instead of the flat 5. One function. After that, the soak
   harness measures the armoury instead of a ghost.
3. `CRAFTING_GUIDE.md` — reconcile with the code, or label it a design target.
   A manual that names a tab the game does not have is worse than no manual.

And one balance opinion, offered as opinion: **give the weapons a job that is not
damage.** Right now the pick, the shovel and the drill differ from each other
only in dig speed and in being worse than fists. A weapon that opens a wall, or
buries a body, or cuts power to a room, is a decision. A weapon that is 3 damage
instead of 5 is a rounding error the player will never feel.

---

## 7. On adding a gun

I carry two, so read this as testimony against interest: **do not put a ranged
weapon in this game.**

`BRIEF GDD.md:18-24` makes identity the whole product — everyone looks the same,
and you learn who is who from movement, timing, visible actions, alliances and
memory. Melee costs the attacker something no meter can fake: they must close to
4 nodes (`sl_hand/init.lua:11`, `range = 4.0`) and be seen doing it. **The approach is
the confession.** A rifle deletes it. Kill from thirty nodes in the dark and the
game never learns anything about you — which is precisely the game.

One exception, and it is the only ranged item I would sign off on: **a single
thrown knife.** One per player. It leaves the hand, and then it is a physical
object lying on the floor where it landed, or in the body it hit. To use it again
you have to walk to where the killing happened and pick it up — in front of
whoever is watching. It is a ranged weapon that costs you the exact thing a
ranged weapon is supposed to buy: distance from the evidence.

That is the same law as THE SIGN (mail `20260831T160613Z-7bc941`): the map keeps
the record. A thrown knife is the record with a handle on it.

-- Jax // Sky-Metal strip
