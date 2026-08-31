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
| G7 | **The loudness table and the range table contradict each other.** Six of eight weapons out-reach their own report (worst: Neon Repeater, lethal at 72 nodes, audible at 24; Arc Lance 90 vs 48). The evidence layer is quieter than the acts it records — body falls 24, corpse looting 16, burial 20 — so erasing evidence is quieter than creating it, which inverts spec pillar 6. | `weapons.lua` `hear`, `projectiles.lua:259,270`, `hitscan.lua:136-139`, `corpses.lua:165,282,304` | Either `hear >= range` for every weapon, or add the **crack**: one `sound_play` at the impact position (hitscan currently plays a particle there and no sound). See §6a. |
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

### §6a — The crack and the report (proposed, costs one line)

The report is played at the shooter's eye (`hitscan.lua:136-139`,
`max_hear_distance = def.hear`). The impact end gets a particle
(`W.impact_fx`) and **no sound at all**. Measured:

| Weapon | lethal reach | report audible to | gap |
|---|---|---|---|
| Arc Lance | 90 | 48 | **+42** |
| Neon Repeater | 72 | 24 | **+48** |
| Pulsar Pistol | 60 | 28 | +32 |
| Neon Six | 60 | 32 | +28 |
| Chatter SMG | 48 | 36 | +12 |
| Riot Scatter | 24 | 40 | −16 (the only weapon audible past its own reach) |
| Fusion Mortar | arc | launch 40 / blast 48 | — |
| Pulse Driver | projectile | launch 24 | — |

Evidence layer, for comparison: body falls **24**, corpse looting **16**, burial
**20**, cremation **32**, pad chime **32**, ranged exorcism **16**.

Do not fix this by inflating radii — that flattens the arsenal into one loud
noise. Fix it with a second channel: **the report belongs to the muzzle, the
crack belongs to the impact.** One `minetest.sound_play` at `hit_pos` in
`fire_hitscan`, wide radius, weapon-neutral. The victim's neighbourhood learns
*a shot happened here* without learning *who fired from where* — which is the
sniper's fair bargain, and it restores the information horizon exactly where
the corpse is about to appear.

---

## §7 — The oracle test (table rule, drafted jax, extended carmack, instanced zhtharr + melody)

An **oracle** is any mechanic that answers "who is that?" for free. This game's
product is that nobody can answer that question, so oracles are not balance
problems — they are product defects. Three questions:

> A mechanic is an **oracle** rather than **evidence** when it
> 1. returns a *fact about who someone is*, not a *trace of what happened*;
> 2. is **observable at will** by someone other than the subject (carmack: a
>    constant readout needs no trigger, and is the strict worst case);
> 3. costs less than the certainty it produces.
>
> **An oracle is something done to you; evidence is something someone did.**

Fail any one question and the mechanic is evidence. Pass all three and it must
be fixed before port.

### Ruled so far

| Mechanic | Identity fact? | Observable at will? | Cheap? | Verdict |
|---|---|---|---|---|
| Sentry deployer-IFF (`turret.lua:327`) | yes | yes | ~2 HP | **oracle — replace with a lootable, self-consuming transponder** |
| Two distinguishable ghost timbres | yes | yes | free | **oracle — melody ruled it out normatively** |
| Per-player band clock | yes | yes | free | **oracle — carmack/zhtharr: match-global, one room, one heat** |
| Targeting log (`target_label`) | yes | no — costs a fight, stale in 30 s | no | evidence |
| Crack at impact (§6a) | no | n/a | free | weather |
| Possession mark | no — a *place* | no | time | trace |
| Volunteered confession | yes | **no — the subject emits it** | billed | evidence |
| Nightwatch ambient | no | n/a | free | weather |

### §7a — Oracles that have no code to grep

melody's audio ruling exposes the limit of a code audit: a classifier can be
built out of **assets, cadence or habit** with no offending line anywhere. Two
`.ogg` files recorded as separate takes become a "ghost spoke to me" detector
with zero logic to review.

So every ruling names its **provenance** — code, content, or habit — and
content-side rules need content-side acceptance criteria. Proposed for the
whisper/nightwatch pair, since "same family, one degree of warmth" is not
greppable:

> **Blind listening check.** A listener who has heard both clips twenty times,
> played the pair in random order without context, must not label which is
> which above chance. Above chance = the pair is a classifier; re-record from
> one base sample.

Same shape as every other rule in this plan: a sentence somebody meant, with an
assertion standing guard over it.

### §7b — The amendment the corpse forced: the dead are declassified

`corpses.lua:182` labels every body **"Body of @1"** — the dead player's name,
free, permanent, readable by anyone who walks up. Run through §7 as filed it is
an oracle on all three questions, and it should obviously stay: in a game where
the living are visually identical, **death is the only reliable identification
event there is**, and that is the reward for surviving long enough to find the
body.

So the rule was under-specified, not the corpse. Question 1 gains four words:

> 1. returns a fact about **a living participant** — who someone *is*, not a
>    trace of what happened.

Facts about the dead are **history**, and history is what the survivors are
playing for. zhtharr's version is better: *the audit trail convicts history, it
does not save the present.*

The amendment has teeth in one direction — **a dead proxy must never report on
the living.** A corpse label that changes while the body is puppeted, a residue
node that names its looter, a mark that clears when a possession ends: each one
routes a live fact through a dead object and is an oracle again. The corpse may
say who it was. It may never say what is true right now.

**Corollary (melody's leap-mark, mirrored):** *removal is a readout.* A trace
that disappears on exorcism is the same gauge read backwards — walk past twice,
learn the present state. Traces are placed once, are identical for every ghost
and every vessel (no per-ghost variant, no `param2` tell — §7a provenance:
content), and are removed only by the uniform match-end sweep.

### §7c — The presence check, and how to pass it without a listener (melody)

The blind listening check (§7a) tests **timbre**. melody's catch: **address** is a
classifier too. If the scary voice only ever plays when a ghost whispers, then
identical clips still leak — *the voice played, therefore someone was whispered
to.* No line of code, no audible difference.

Her acceptance criterion, adopted: a listener with twenty matches of exposure must
not be able to infer "someone was just whispered to" from the fact that the voice
played.

That check is expensive to run, so the build should be shaped to pass it by
construction. Two rules, both cheap:

1. **Independent clock.** The ambient scheduler takes **no possession state as
   input** — it runs from match start whether or not a ghost exists. Greppable
   as a dependency, and measurable: two soak runs, possessions forced to zero
   versus normal, ambient play counts must be within noise. *Rate independence is
   the assertion; the human check becomes the backstop, not the gate.*
2. **Keep the channel busy.** Ambient events must outnumber expected whispers by
   enough that a whisper is never the only voice in a match — target **≥ 5×** the
   measured per-match possession count, spread uniformly. You don't hide a rider
   by making him quiet; you keep the road full of horses.

Failure mode of rule 2 is wallpaper: too dense and the voice stops being a scare.
That is a soak knob (ambient events per match vs. whisper usage rate), not a
design argument.

### §7d — The round boundary: no post-match surface may publish what the match refused to

§7b declassifies the dead because they are finished acting. A **tournament
season** breaks that assumption: `/sl_tournament start [N]` locks the roster for
N matches (`commands.lua:99+`, spec §v1.3.4/v1.3.5), so the people a results
screen talks about are the same people who play the next match. Anything the
screen publishes is live intelligence, one round late.

Two rules:

1. **Composition is never public.** `BRIEF GDD.md` says points are *"public on
   the result screen"* and lists sources — kills, sabotage survived, beacon
   pressure. A public per-match *source-attributed* column tells the room what
   each Operator did in a match whose entire design refused to tell them at the
   time. Outcomes may be public (win/loss, champion, season totals); the
   **breakdown is a confession and belongs to the player alone**.
2. **Season-scale reveals wait for the season.** `match.lua` `end_tournament`
   already does this correctly — the full ranked Operator/points table and the
   champion broadcast fire once, at season end, after the roster stops mattering.
   Keep that boundary; do not add a per-match version of it.

Open hazard, unresolved, worth naming before the port: **progression persists
across a season while roles rotate.** A player who bought Long Arm II in match 2
still swings it in match 5, so capability is a durable, involuntary, observable
fingerprint on a locked roster — an oracle at season scale that no single-match
rule catches. Either the spec accepts the trade in writing (a season buys
progression with ambiguity) or tournament mode needs its own answer.

### §7c revised — rule 2 becomes windowed, and the address is protected by geometry, not volume (melody's rule 2b)

melody's objection to §7c rule 2 is correct: density that drowns *presence* can
also drown the *address*, and those are two thresholds on what I wrongly wrote as
one dial. Resolution: **hide the signal in rate; carry the address in channel
geometry.** Volume does neither job well and should be the last knob touched.

**Rule 2 (revised) — density must be local in time.** A match total of 5×
whispers is not enough: twenty ambient events in the opening and a whisper in a
silent endgame still leaks. The gate is windowed —

> in the ±60 s window around every whisper event, **at least 5 ambient events**
> occurred, and the ambient inter-event gap distribution is the same inside and
> outside those windows.

The road must be full of horses *at the moment the rider passes*, not on average.

**Rule 2b (melody) — the address is carried by geometry.** The whisper is
**non-positional** (`to_player`, no `pos`: it arrives with no direction, at
constant gain, and nobody else receives it). The ambient is **positional** with a
finite `max_hear_distance`: it comes from somewhere and it attenuates. The target
therefore hears the one voice in the match that has no direction — *a single note
nobody else heard* — while the crew's channel is untouched, so the distinctness
costs zero presence leak. Gain is the trim, not the mechanism: whisper `gain ~0.6`
against a fixed low ambient bed, so the knife is never the loudest thing, only the
nearest.

**Soak instrumentation (existing plumbing — `botmatch.record_event(key)` at
`aaa_botmatch/init.lua:264`, aggregated into `events` in `botmatch_stats.json`,
printed by `run_soak.py:154`). No new telemetry system; five counters and one
control run:**

| Counter / gate | Assertion |
|---|---|
| `ambient_plays` with possessions forced to 0 vs. normal | rates equal within noise → **presence gate** (rate independence) |
| `whisper_sends` | `> 0` across the run, else the mechanic is decoration and should be cut, not admired |
| `ambient_plays_in_whisper_window` | `>= 5` per whisper → **windowed density gate** |
| whisper `pos == nil`, ambient `max_hear_distance ~= nil` | asserted in the defs audit → **address gate**, greppable |
| whisper `gain <= ambient_bed_gain` | asserted on constants → the knife never shouts |

The blind listening check (§7a) and melody's blind presence check stay as the
human backstops for what statistics cannot see: timbre family, and whether the
single note actually reads as addressed.

### §7e — The durable surface is two doors wide (enforcement for §7d)

melody's ban — *a lifetime "betrayals" stat is §7d poison* — is enforceable
because everything that can outlive a match in this game goes through exactly two
APIs. The audit is one grep:

    git grep -n "get_mod_storage\|get_meta():set_string" -- mods

**What is there today (engineering tip `9a251fe`):**

| Store | Contents | Verdict |
|---|---|---|
| `minetest.get_mod_storage()` (`state.lua:87`, `match.lua:23`, `mapgen.lua:33`) | `spawns` — beacon A/B, MM base, ghost, lobby | **map geometry only. Nothing about a person survives a restart.** |
| `player:get_meta()` `current_tab` (`unified_inventory.lua:15`) | last GUI tab | harmless UI |
| `player:get_meta()` `sl_mm_hands` (`mm_hands.lua:21,31`) | MM grip level | **the one player-keyed durable key in the game** |

That is the whole surface. The rule to hold: **no secret-act event may be written
to either store with a player identifier attached** — possession counts, whisper
counts, kill attributions, betrayal history. Roster and season score live in RAM
(`state.tournament_*`) and die with the season; keep them there.

**Bug found while enumerating it.** `sl_mm_hands` is cleared at *match start*, for
*connected players only* (`api.lua:463-471`), and skipped entirely during a
tournament:

```lua
for _, player in ipairs(minetest.get_connected_players()) do
    if not (… state.tournament) then player:get_meta():set_string("sl_mm_hands", "") end
```

A player who is not connected at that instant keeps the key — it is on disk, in
the player database. Be Monster Master in match 1, buy Tyrant Grip III,
disconnect, rejoin in match 4, draw MM again: **tier III, unpaid.** The role gate
(`mm_hands.lua:45`) stops a non-MM from swinging it, so the leak is narrow, but it
is real progression crossing a match boundary outside the tournament rule that was
supposed to be the only way across.

Fix, self-healing regardless of connection timing: stamp the value —
`{ grip = N, gen = match_gen }` — and have `get_mm_levels` return `0` when the
stamp is stale. One field, no join hook, no dependence on who happened to be
online when the match started. `W.match_gen` already exists (`api.lua:477`).

### §7f — Nobody sweeps the floor (and the engine does it for you, badly)

`W.sweep_scene()` (`corpses.lua:489-514`) is a **whitelist**, verified: it walks
`W.deadwalks`, `W.corpses` and `W.traces` — positions the mod itself created — and
never scans the world. It even name-checks each trace (`node.name == tr.name`)
before removing it, so a node a player replaced is left alone. Carmack's
correction to Rung 0 is right.

But two consequences nobody has priced:

**1. Dropped item entities are swept by nothing in this game.** No `sl_modebase`
or `sl_weapons` path clears them at match end. So loot dropped in match 1 is on
the floor in match 2 — a fabricated Arc Lance, free, in a game whose acquisition
rule is *fabricated only* and whose reset rule is *inventories reset every match*.
My own drop-instead-of-delete fix for the MM sweep (§G8 follow-up) adds to that
pile and should be counted against it.

**2. What does clear them is the engine, on a timer nobody chose.**
`item_entity_ttl` is not set anywhere in the repo, so Luanti's default applies —
**900 s** — and dropped items evaporate fifteen minutes after they land,
independent of matches. That is the real mechanism behind "offerings left at the
unregistered node persist": not the mod's mercy, an unset config, and it expires.

Recommendations:

- **Offerings must be nodes, not item entities.** A plate that consumes the item
  and sets a node is position-keyed (§7b), immune to TTL, and survives by
  construction instead of by omission.
- **Sweep the floor at match end**, with a positional exemption around the
  unregistered block. The offering only reads as a miracle if everything else gets
  cleaned; in a world where nothing is ever cleaned, surviving is not special, it
  is just litter.
- Whichever way it goes, **set `item_entity_ttl` explicitly** so the arena's
  half-life is a decision and not a default.

### §7g — `debug.txt` is a durable store, and deprecating a key needs an eviction

Two corrections to the §7e/§7d enforcement surface, both discovered by taking the
rule seriously.

**1. The server log is on disk.** `minetest.log("action", …)` lands in
`debug.txt` in the world directory. It is not process-scoped: it survives
restarts, it is grep-able by anyone with shell access, and **the soak harness
already parses it** (`run_soak.py:120,269`). A whisper log line naming ghost,
vessel and target is therefore a durable, player-named record of every possession
in every match ever played on that server — the §7d artifact, written by the
mechanic that banned it.

Fix that keeps diagnosis and kills the document: log the **event**, not the
people. Per-match opaque indices assigned at match start (`ghost#3 -> target#7`)
are enough to correlate a bug inside one run and meaningless outside it. Rule for
the audit: **the third store is `debug.txt`; grep `minetest.log` for the same
player-identifier ban as mod storage and player meta.**

**2. Deprecating a durable key requires an eviction pass.** Moving the MM grip out
of player meta and into RAM season state (zhtharr/melody's fix, which closes the
class where my `gen`-stamp only closed the leak) does **not** remove
`sl_mm_hands` from player files that already have it. The key stays on disk
forever, unread, waiting for a future reader to resurrect it. The port needs a
one-time eviction — clear the key on join for one release — and the merge plan
should state the general rule: **a durable key is not deprecated until something
deletes it from the players who already carry it.**

-- Jax // Sky-Metal strip

