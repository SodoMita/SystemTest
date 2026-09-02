# System Looting — Finalization Roadmap

> **Design revision — August 2026:** the immediate milestone is now a reliable match loop, **not crafting**. Ghosts are isolated in a cloud cage; ghost chat is locked; ghosts cannot directly affect teams. Revival creates an evil ghost with a point-loss penalty and limited sabotage powers. All players remain visually identical by design. See [`MATCH_LOOP_SPEC.md`](MATCH_LOOP_SPEC.md).

**Goal of "finalize":** reach something **playable with testers** — a multiplayer match
where two beacon teams compete through movement, looting, combat, death transitions,
and clean match reset. Crafting is a later system layered onto this stable loop.

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
- `sl_modebase` — beacon teams (`beacon_a`/`beacon_b`), single-life death transitions, elimination,
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

## Revised implementation order

### Phase A — Match-loop vertical slice

1. Build and commit one small hand-made arena with two beacons, a lobby, a Monster Master area, a cloud cage, routes, cover, and hand-placed pickups.
2. Add ready check, minimum player/team validation, countdown, insertion, match timer, results, and clean reset.
3. Add a persistent HUD for match phase, own phase state, beacon health, role-local information, and objective status without leaking hidden team identity.
4. Validate identical-player social play: no nametags, no team chat, direct messages, and no accidental team/role indicators.
5. Implement the cloud-cage ghost state: high-altitude containment, no team interaction, no ghost chat, no direct map influence.
6. Add deliberate living-player summoning as the only ghost-to-living information channel.
7. Add voluntary evil-ghost revival with end-of-match point loss, flight, controlled possession, and bounded sabotage.
8. Add scripted AI players and deterministic scenarios for every state transition, disconnect, match end, and reset.

**Exit check:** 2–4 human or scripted AI players can complete repeated matches without administrator intervention after setup.

### Phase B — Crafting foundation, later

1. Remove or disable direct inventory crafting of placeable/world-affecting items.
2. Keep personal crafting limited to information, consumables, charges, repair kits, keys, and tokens.
3. Introduce machines for structures, traps, barriers, objective machinery, and other placeable outputs.
4. Start with partial information items and summoned-ghost information exchange.
5. Add the Objective Core only after the elimination/death/match-reset loop is stable.

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

1. ~~**Define the "final goal" item.**~~ **Done:** `sl_modebase:objective_core`
   exists (`sl_modebase/nodes.lua`), is `stack_max = 1`, `groups.objective = 1`
   per `MASTER_DESIGN_FULL` §6.10 A, and delivering it within 8 blocks of your
   own beacon ends the match.
2. ~~**Author a real recipe tree**~~ **Done + rebalanced:** raw neon → components
   → the Core. The refine branch is *batched* (4 neon → 8 components) so a full
   Core is five machine runs and twenty dug nodes instead of thirty.
3. ~~**Make crafting accessible in-match**~~ **Done:** `sl_machine_crafting`
   ships the **Objective Forge** — one per map, placed at the neutral `forge`
   anchor, with input slots, a run clock (`sl_machine.forge_time`), and a
   broadcast so both teams know when it is hot. `content/workshops` stays
   shelved; `sl_machine_crafting` is the machine home.
4. ~~**Add a new win condition**~~ **Done:** `state.win_conditions.objective`
   (set from the lobby terminal) + `game_mode.deliver_objective()`. Covered
   end-to-end by `tests/objective_loop_test.lua` (99 assertions).
5. ~~**Make loot exist to craft from**~~ **Done:** the procedural and test
   arenas seed mirrored **salvage veins** of all four raw neon types. Before
   this the three exotic types existed on no map, so the chain was
   unwinnable.

**Exit check:** 2 players, 2 teams; a team can gather → craft the goal item → win, and the
match ends correctly and announces the winner. — **MET** headlessly
(`tests/objective_loop_test.lua`, `luajit tests/objective_loop_test.lua`);
still to be confirmed with two human clients in a playtest.

---

## Phase 2 — Make it testable multiplayer (stability pass)
1. **Build a small hand-made test map** (singlenode arena with two bases + loot points).
   Ship it as a saved map or a one-command builder, since there's no mapgen.
   *Done: the match map system ships three types — procedural (seeded), test
   (deterministic builder) and handmade `.mts` schematics — with committed
   example maps (`mods/game/sl_modebase/maps/`) and full initial-state reset
   between matches (see `MATCH_LOOP_SPEC.md`).*
2. **Match lifecycle UX:** clear "how to start" (commands exist: `/sl_be_monster_master`,
   match start). Add an on-screen HUD for phase state, objective progress.
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

## Phase 4 — Lobby & Matchmaking
- [ ] Implement Lobby Room mechanics:
    - [ ] Add `sl_modebase:lobby_terminal` node for match settings and voting.
    - [ ] Create Matchmaking UI (Formspec) for starting matches, choosing modes, and roles.
    - [ ] Add "Waiting for Players" HUD when match is not active.
- [ ] Enhance Monster Master Role:
    - [ ] Add RTS-style unit deployment UI.
    - [x] Monster Spawner Unit: placeable node, MM-only GUI creature list
        (Stalker/Scout/Brute + sl_scary Dredger/Wraith/Containment),
        burns one Monster Essence per spawn.
    - [ ] Implement income system based on damage dealt by monsters.
- [ ] Lore Integration:
    - [ ] Add readable data pads/terminals with AI-generated horror logs.
