# System Looting — Finalization Roadmap

**Goal of "finalize":** reach something **playable with testers** — a multiplayer match
where two beacon teams compete, with a working **crafting → final-goal** loop layered
on top of the existing last-team-standing MVP.

**Locked design decisions (from discussion):**
- MTG `default` and other `external/` mods are **temporary scaffolding**, swapped out
  piece-by-piece as bespoke content is made. Do **not** spend effort stripping MTG now.
- The **MVP exists**: `sl_modebase` has teams + win-by-elimination + a monster master.
- **Procedural mapgen is abandoned.** `singlenode` + **hand-built maps** is the plan.
  `game.conf`'s `allowed_mapgens = singlenode` is correct on purpose.
- **Next milestone = a crafting gameplay loop that leads to a final goal / win.**
- The **"AI council" horror brainstorming** stays as an ongoing idea source.
- "Done" = stable enough to put in front of testers (multiplayer).

---

## Current state (verified from the code)

### Works / present
- `sl_modebase` — beacon teams (`beacon_a`/`beacon_b`), per-player lives, elimination,
  monster master role, `/sl_*` chat commands, beacon nodes that set team spawns.
- `sl_gui/crafting_system.lua` — a **complete button-based crafting UI** (categories,
  search, ingredient check/consume). This is the crafting engine to build on.
- `sl_gui` also has ability, achievement, experience, running/sprint, outfit systems.
- `dialogue` — YAML-driven dialogue engine with triggers.
- `sl_scary` — monster entity + AI.
- Forked MTG `default`, `player_api`, `flowers`, `food`, `give_initial_stuff`, etc.

### Broken / incomplete (verified)
| Item | Status | Impact |
|---|---|---|
| `content/sl_characters` | has `mod.conf` but **no `init.lua`** (only `.blend` files) | **Mod load error** — fix or delete |
| `game/sl_machine_crafting/init.lua` | **empty (0 bytes)** | dead mod |
| `game/sl_energy/init.lua` | **empty (0 bytes)** | dead mod |
| `game/sl_security/init.lua` | **empty (0 bytes)** | dead mod |
| `content/workshops/init.lua` | **entirely commented out** | no crafting stations |
| `game/sl_platforming`, `game/sl_spawn` | **no `mod.conf`** (only model files) | not loaded; just asset dumps |
| Crafting recipes | placeholder demo items, **not tied to any goal** | no real loop |
| Win conditions | only elimination + MM-slain | **no crafting/objective win** |
| `menu/` "music" | `.mp4` / `.aac` / `.mp3` / `.wav` | Luanti only plays **.ogg**; menu music silent |
| `menu/` branding | only `icon.png` | missing `header.png` + background |
| Repo hygiene | **22 junk files** (`*~`, `*.bak`, `*.blend1`, `*.kra`), no `.gitignore`, no README, `author = [Your Name]`, joke license | not presentable |
| Duplicate code | `ability_system.lua` (410) **and** `ability_system_new.lua` (1480) + `.bak` | confusing/dead code |
| `.git` size | 66 MB (tree only ~19 MB) | heavy history from committed binaries |

> Note: `goto continue` in 4 files is **valid** in Luanti's LuaJIT runtime — not a bug.

---

## Phase 0 — Repo hygiene & "loads clean" (½ day, do first)
Cheap, unblocks everything, makes the project shareable.

1. **Fix the load error:** delete `content/sl_characters` (it's only `.blend` source),
   or add a stub `init.lua` + an exported model. It's referenced nowhere, so deletion is safe.
2. **Add `.gitignore`:** `*~`, `*.bak`, `*.blend1`, `*.kra`, `*.kra~`, `*.glb` (if source-only),
   editor/OS cruft. Then `git rm` the 22 tracked junk files.
3. **Resolve the ability-system duplication:** pick `ability_system.lua` **or**
   `ability_system_new.lua`, delete the other + the `.bak`. (Check which `init.lua` loads.)
4. **Delete or `.conf`-ify dead mods:** either remove the three empty `game/sl_*` stubs and
   the two `mod.conf`-less asset dirs, or give them real `mod.conf` + content. Don't leave half-mods.
5. **Add `README.md`** (what the game is, how to run it, current status, controls/commands).
6. **Fix `game.conf`:** real `author`, real `description`, confirm `release` bump policy.
7. **Decide the license** (left as-is per your call — revisit before any public release).

**Exit check:** game loads in Luanti 5.x with **zero red errors** in the log; `git status` clean.

---

## Phase 1 — The crafting → final-goal loop (the headline milestone)
Connect existing pieces; little needs to be built from scratch.

1. **Define the "final goal" item.** e.g. `sl_modebase:objective_core` — the thing a team
   crafts (and optionally delivers to their beacon) to win.
2. **Author a real recipe tree** in `sl_gui/crafting_system.lua` (replace demo recipes):
   - raw loot → intermediate components → the goal item.
   - Use items that already exist (MTG ores/ingots) as placeholders for now.
3. **Make crafting accessible in-match:** either via the existing button UI bound to a
   key/command, or revive ONE station from `workshops` (uncomment + give it textures).
4. **Add a new win condition** in `sl_modebase/match.lua`:
   - new `state.win_mode = "objective"` alongside the existing elimination check;
   - fire `game_mode.end_match(team, "crafted/delivered the objective")` when a team
     crafts (or places at beacon) the goal item.
   - This is the GDD's planned **"Item Delivery Objective"** mode — start here.
5. **Make loot exist to craft from:** simplest version = `give_initial_stuff` + a few
   loot nodes/chests hand-placed on the test map. (Procedural loot can come later.)

**Exit check:** 2 players, 2 teams; a team can gather → craft the goal item → win, and the
match ends correctly and announces the winner.

---

## Phase 2 — Make it testable multiplayer (stability pass)
1. **Build a small hand-made test map** (singlenode arena with two bases + loot points).
   Ship it as a saved map or a one-command builder, since there's no mapgen.
2. **Match lifecycle UX:** clear "how to start" (commands exist: `/sl_be_monster_master`,
   match start). Add an on-screen HUD for team, lives, objective progress.
3. **Convert menu audio to `.ogg`**, name it `menu_music.ogg`; add `menu/header.png` +
   background so the game looks intentional in the menu.
4. **Playtest checklist:** join → assigned team → spawn at beacon → craft loop → win/lose →
   restart. Fix the crashes/edge cases that surface (empty teams, MM disconnect, etc.).

**Exit check:** an outsider can join your server and complete a full match unaided.

---

## Phase 3 — Iterate on content & horror (ongoing, post-tester)
1. Feed the best **AI-council horror ideas** in as concrete, implementable units
   ("lore = text files, logs = simple tables" per `EVENT IDEAS.md`).
2. Replace MTG scaffolding with bespoke neon-on-black content **one node/tool at a time**
   (keeps the game playable throughout).
3. Flesh out the death → ghost → monster → monster-master cascade from the GDD.
4. Add the other win modes (point-based, defense) once the objective mode proves fun.

---

## Suggested immediate next actions (this week)
- [ ] Phase 0, items 1–5 (clean repo, kills the load error, README).
- [ ] Phase 1, items 1–2 (define goal item + draft the recipe tree).
- [ ] Phase 1, item 4 (objective win condition) — smallest change that creates a *new loop*.

> Biggest leverage: **Phase 1 item 4** (objective win condition). It turns the existing
> crafting UI from a sandbox feature into an actual *way to win*, which is the whole point
> of "a crafting loop toward the final goal."
