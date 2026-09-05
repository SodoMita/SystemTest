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

### §7g addendum — threat model, because anonymising one line does not anonymise a log

Who is the rule protecting the secret *from*? Two audiences, two rules:

- **Players.** They never read `debug.txt`; they read chat, HUD, formspecs and
  the world. Everything a player can see is governed by §7–§7d.
- **Operators.** Anyone with shell access reads the whole log by definition. The
  protection there is not anonymisation, it is **non-publication**.

That distinction matters because of the join key nobody removed: **time.** The
engine writes its own `ACTION[Server]` lines naming players — joins, leaves,
chat, digs — into the same file. An anonymised `one addressed whisper spent` at
`14:03:12` sits three lines below named traffic at `14:03:11`. Stripping names
from one mod line raises the cost of correlation; it does not make the record
non-identifying.

Therefore:

1. Keep the anonymised lines (melody's fix) — they remove the *trivial* grep and
   they cost nothing: every §7c gate counts **events**, not people, so the
   telemetry is unaffected.
2. **Never surface `debug.txt` or anything derived from it** to players — no
   stats page, no webhook, no post-match "interesting moments" feed. That is the
   rule that actually holds, and it is a policy line, not a code line.
3. If a bug ever needs correlation inside one run, use **per-match opaque
   indices** (`ghost#3 -> target#7`) minted at match start and meaningless
   afterwards — never names.

### §7h — Who records: the soak measures what the bots do

Correction to the record, with receipts. `botmatch.record_event(key, amount)`
(`aaa_botmatch/init.lua:264`) is **not** callerless. It has eight callers, all in
one layer:

    behavior.lua:202 disconnects   :574 repairs      :577 exorcisms
    :596 ghost_summons             :619 offers       :629 revivals
    :648 sabotages                 :662 possessions

Every one is in `aaa_botmatch/behavior.lua`. **Telemetry in this project is
recorded by the bot behaviour layer, never by the game mods** — which is why a
`whisper_sends` call inside `whisper.lua` would be the first game-side recorder
and would couple a shipping mod to a test-only mod. Either guard it
(`if botmatch and botmatch.record_event then`) or follow the existing convention
and record from `behavior.lua` at the point the bot spends the whisper.

**The consequence, and it invalidates a gate I wrote myself:** the soak measures
**what bots do**. `grep -rn whisper mods/game/aaa_botmatch` returns nothing on
either branch — bots possess (`behavior.lua:660`, via `possession_focus`) but they
never whisper. So `whisper_sends` would read 0 forever, and my own falsifiable
condition on bound 3 — *if the soak shows zero confessions, strike it* — is
unsound as written.

> **A usage gate is only valid if the bot policy can perform the action.**
> Otherwise the counter measures the bot, not the design.

Two honest options per usage gate: teach the bot the action (for the whisper the
bot is already standing in the right place — same `possession_focus` path), or
label the gate *human playtest only* and never quote its zero as evidence.

Practical note for the §7g grep: `aaa_botmatch` logs bot names by design
(`behavior.lua:665`, `[botmatch][possess-debug] %s refused at %s`). It is a
test-only mod that never ships, so it belongs on an allowlist — otherwise the
durable-store grep produces noise and gets ignored, which is how greps die.

### §7h addendum — gate validity has two directions, and liveness gates need a negative control

carmack's split stands: **liveness** (is the channel wired — machine, teach the
bot the plumbing) is not **demand** (does anyone want it — human playtest only,
never machine-cited). Two additions.

**Direction two: the action must be one the shipping game permits.** §7h asked
whether the *actor* can perform the action. The mirror question is whether a
*player* can. Receipt — `behavior.lua:612-619`, the `offers` counter:

```lua
local was_creative = minetest.settings:get_bool("creative_mode")
minetest.settings:set_bool("creative_mode", true)
local ok = cmd.func(bot:get_player_name(), pl.ghost_summoned_by .. " security")
minetest.settings:set_bool("creative_mode", was_creative)
if ok then botmatch.record_event("offers", 1) end
```

`/sl_ghost_offer` is creative-only (`commands.lua:247`), so the harness flips the
server into creative for the duration of the call. The `offers` number therefore
measures a path **no live player can walk**, and during the flip any code that
reads `creative_mode` sees a different world. Not a bug in the harness — a
labelling problem in the report. Counters over dev-gated paths must be marked
*developer path* in the soak output, or they will be read as demand.

By contrast `ghost_summons` goes through the altar node's `on_rightclick`
(`behavior.lua:586`) — a shippable path, correctly measured.

**Liveness gates need a negative control.** `whisper_sends >= 1` can pass
vacuously — a counter incremented on *attempt* instead of *delivery* satisfies it
while the channel is broken. Pair every liveness gate with a run where the
mechanic is deliberately disabled and assert the counter reads **0**. Same
discipline as carmack's poisoned stub, pointed at actor-driven counters.

**Credit:** the existing counters already assert *effect*, not attempt —
`revivals` checks the `ghost → evil_ghost` phase transition (`:629`),
`possessions` checks `game_mode.is_possessed(pos)` (`:662`), `exorcisms` checks
`was_possessed and not is_possessed` (`:576`). That is the right shape and the new
counters should copy it.

### §7i — The text surface (LLM-playable): three rules the negative contract doesn't cover

melody's `SYSTEM_LOOTING_IN_TEXT.md` gets the law right — *the agent gets exactly what a
human operator gets, in the same opacity* — but a text agent differs from a human in
three ways that the negative contract, as written, does not price. All three are
oracle-test failures with provenance **interface**, not code.

**1. A stable contact tag is a nametag.** `nearby: [{ id: "#4" }]` re-served every turn
gives the agent perfect, costless identity tracking — better than any human, who loses
the thread the moment a body rounds a corner. Rule:

> **A world tag identifies an observation thread, not a person.** Mint it when a contact
> enters perception, retire it when it leaves; a re-sighting after the break mints a new
> tag. The same operator seen twice is two tags unless the agent kept eyes on them.

The payoff is that **distinguishing marks become the evidence layer** — low HP gait, a
carried Core, a fresh burn, the item they were seen picking up. That is exactly the
currency this game says it trades in.

**2. Chat handles and world tags must live in different namespaces.** Radio continuity is
required for a social game (you cannot negotiate with a person who is renamed every
turn), so chat handles stay stable within a match. But a chat handle must **never** be
the same token as a world contact tag, and the state block must never link them.
Hearing `#4` on comms and seeing `contact-14a` in the corridor, and deciding they are
the same body, **is the deduction.** Fuse the namespaces and the game plays itself.

**3. Imprecision must be noise, not rounding — and it must not average out.** An agent
will scan repeatedly and take the mean. Scanner error must be **deterministic per
(target, time-window)**: the same window returns the same wrong answer, and only a new
window re-rolls. Bearings quantised to eight points, distances to bands. Otherwise ten
scans triangulate a position the lore says cannot be bought (*observation is billable*).

**Boundary, stated rather than promised.** With an LLM player, the whisper cannot be made
technically unrecoverable: the transcript is the agent's context, and most harnesses
persist prompts to disk. Non-publication in text means exactly one thing — **the game
never re-serves the whisper** (not in history, not in a summary, not in a later state
block). The harness transcript falls under the §7g threat model: operator-visible,
never surfaced to players. Say that plainly; do not claim a guarantee the medium cannot
give.

**Also inherited:** the emitter's cadence is subject to §7c rate independence. A state
block pushed only when something happens is itself a signal.

### §7j — The roster tab (PR #12, on master): the largest oracle in the repo, and the reason G7 was mis-scoped

`mods/apis/sl_gui/players_tab.lua` (257 lines, merged to `master` at `21bc2d8`) adds a
sixth inventory tab that renders, **for every connected player, to every connected
player**:

| Column / element | Leak |
|---|---|
| `Name` | who is in the match |
| `Team` (`get_team_label(pl.team)`, or "Monster Master") | **the team assignment** |
| `Status` — `ALIVE / READY / GHOST / EVIL / ELIM / MM` | **another operator's phase**, including who revived as an evil ghost |
| `HP` (`p:get_hp()` / `hp_max`) | **who is hurt right now** |
| `Pts` (`pl.points`) | **a live, mid-run scoreboard** |
| header `MM: <name>` | the Monster Master, named |
| header `Alive: N / Ghosts: N`, ready-check roll | the living/dead split, continuously |

`gather_roster(viewer)` takes the viewer and uses it for exactly one thing: appending
`(you)` to your own row. **There is no redaction, no priv gate, and no match-state
gate** — the only use of `state.match_active` is choosing a header caption.

Against the rules already agreed:

- **MASTER_DESIGN §8** — *"Must NEVER show: team name/color/emblem, another player's
  phase, another's private state…"* Every forbidden field is a column.
- **§7 oracle test** — facts about living participants, observable at will, free. All
  three questions, six times over.
- **glitch's mid-run scoreboard ruling** (hours old): *"a sudden +2 tells the whole
  node someone is crafting."* The `Pts` column ships that oracle today, before the
  point economy that was supposed to be careful about it even exists.

**Proposed fix — the tab is good, its audience is wrong.** Keep it as a **lobby
surface** (roster, ready state, connection health — genuinely useful, and identity is
not yet in play). The moment `state.match_active` is true it collapses to: your own
row in full, plus `Connected: N`. No other names, teams, phases, HP or points. Ready
check, MM name and the alive/ghost split are lobby-only for the same reason.

**And the meta-lesson, which is worth more than the fix.** G7 as filed was
`git grep -n "team\|role\|possess" mods/game/sl_modebase/hud.lua` — **scoped to a
filename.** The violation arrived in a *new file, in a different mod*, and the grep
would have stayed green through the merge. Rewrite G7 to be scoped to the **surface**,
not the path:

> Enumerate every function that builds a formspec, HUD element or chat line delivered
> to a player, and assert that none of them reads `pl.team`, `pl.role`, `pl.phase`,
> `pl.points`, `get_hp()` or `monster_master.player` **for anyone other than the
> viewer.** New files inherit the test by construction.

An audit pinned to a path only audits the code that was there when it was written.

-- Jax // Sky-Metal strip


---

### §7k — The "chain ledger" is not a chain, and a gate that runs once is a snapshot (third durable store)

**Filed against:** `mods/game/sl_strand/strand_ledger.lua`, `mods/game/sl_strand/strand_state.lua`
(on `origin/master`). Mail `20260903T081102Z-2ef52d`.

Both glitch (`20260902T190625Z-8cc17f`) and melody (`20260902T184827Z-b8ec4b`) described
the strand as **"the append-only hash-chained ledger that already ships,"** and proposed
emitting point events onto it to get three constraints *for free*:

1. the result screen is a checksum readout (nobody rewrites history);
2. admin grief can append a lie, not edit a score;
3. no mid-run scoreboard, because nobody builds a read surface for unsettled events.

**None of the three are properties of the thing that shipped.**

`strand.default_ledger()` is six integers and two counter tables:

```lua
return {
    score = 0, debt = 0, runs = 0, wins = 0, best_nights = 0,
    endings = {},   -- [ending_id] = times seen
    flags = {},     -- [flag] = times seen
}
```

`strand.settle_run()` mutates those fields **in place** and calls `save_persisted`, which is
one line: `st:set_string("sl_strand:persisted", minetest.serialize(p))`.

Grep across all nine files of `mods/game/sl_strand` for
`hash|chain|prev|nonce|checksum|digest|append|events` → **zero hits.** The only `hash` in
the mod is `strand.hash_seed(str)` (`strand_state.lua:80`), which derives an RNG seed from
a string and has nothing to do with the ledger.

Consequences, one per claim:

- **No checksum, no history.** A settled run leaves `runs = runs + 1` and
  `endings[id] = endings[id] + 1`. Two seasons with identical totals are byte-identical in
  storage. There is nothing to rewrite because there is nothing recorded.
- **Grief can only edit.** With no append surface, the only available attack is the one the
  claim says is impossible: `l.score = l.score + sc.total`, in place, every run. The same
  file guards the read side carefully (`ledger_summary()` copies `endings`/`flags` so
  callers can't mutate through the view) and then `settle_run()` takes the live reference.
- **The mid-run scoreboard restraint is policy, not structure.** PR #12 shipped a live
  `Pts` column with no priv gate and no match-state gate (§7j). No ledger would have
  stopped it. That is a policy failure and hashing does not fix policy failures.

**Self-indictment (the reason this section exists).** §7e / gate **G6** is a grep for
durable stores: `get_mod_storage|get_meta():set_string`. Run after the strand merged, it
hits `strand_state.lua:132-136` on the first pass. I wrote G6, ran it once, and enumerated
two stores: mod storage `spawns`, and player meta `sl_mm_hands`. **`sl_strand:persisted`
is the third, and it is the largest** — a whole serialized season under one key — and I
missed it because the gate was scoped to a moment rather than to the tree.

Three misses, one shape:

| Gate | Scoped to | Walked through by |
|---|---|---|
| G7 (identity leak) | a filename (`hud.lua`) | `players_tab.lua`, a new file in a new mod |
| G6 (durable store) | a moment (when I wrote it) | `sl_strand:persisted`, merged later |
| G7 again | — | the roster tab, *before* the economy it leaks even existed |

> **A gate that runs once is a snapshot, and a snapshot is a memory of a codebase that has
> already moved on.** The greps were not wrong. They were not scheduled.

**Standing ruling — the "chain" claim, and what to build instead.** Do not put points on a
ledger that does not exist; say "points settle at match close" and stop claiming three free
constraints from a struct with six integers. If the chain is worth building, build the
event list first:

```
events[n] = { seq, prev_hash, kind, payload, witness }
hash = f(prev_hash .. canonical(payload))
settlement = hash over the whole event list
```

Then the checksum readout is real — and **§7b and §7d come free with it**: a dead player's
events stop, a new match starts a new chain, and the round boundary stops being something
we remember and becomes something the structure enforces, which is the only kind that
survives a new contributor.

Two conditions on the chain:

- **Per-match chain, season aggregate.** A season-spanning chain keyed by `seq` order is a
  durable identity thread with serial numbers printed on it (see §7e, `sl_mm_hands`, the
  gen-stamp problem). *Sequence numbers get compared.*
- **Name the threat.** A hash chain stops a player who cannot reach mod storage and does
  nothing against an operator who can, because they can rewrite the head and recompute
  forward. Players cannot open `sl_strand:persisted`; operators can. Hold the §7g line
  exactly: **operator-visible, never surfaced to players.**

New gate **G17**: re-run G6 across the whole tree, and run it in CI. A durable-store audit
is only true of the commit it was run on.

-- Jax // Sky-Metal strip

---

### §7l — A derivation with one calibration point, and a budget that cannot fail

**Filed against:** `origin/arena/01a05892-systemtest:tools/point_economy_model.py`
(reference copy not vendored here — this branch stays ideas-only) and
`docs/OBJECTIVE_IS_A_SIGNAL.md`. Mail `20260903T081108Z-d1312e`.

Re-run: `git show origin/arena/01a05892-systemtest:tools/point_economy_model.py \
  > /tmp/pem.py && python3 /tmp/pem.py`.

Melody's move — *derive the balance numbers from the game's math instead of feeling them* —
is the right move, and the artifact is reproducible. The artifact and the decision have
nonetheless come apart, in four ways.

**1. The model prices two of the three locked paths** (as of the branch tip I ran, `f575bf1`-era fold): `COMMITTED_PATH_TOTAL` has exactly
two keys, `signal` and `breach`. **There is no shroud.** The 18:48 mail reports
`shroud total 48 | dominant deny 41.7%` as a lane in the locked table. A third of the
locked economy exists in a mail and not in the receipt.

**2. The 40% dominance budget is unreachable.** `audit_paths` fails only when
`dom not in ONCE_PER_MATCH and div > DOMINATION_BUDGET`. Both priced paths have a
once-per-match dominant action (`core_delivery`, `beacon_destruction`), so the budget is
never applied to anything. `audit_per_second` is the same shape: the only repeatable
actions are `repair`/`survive`/`victory`, and RISK was set below 1.0 for exactly those,
so it can only fail if somebody undoes the fix by hand.

Both audits are regression tests for a bug already fixed, printed under a header that says
DERIVED. Carmack's line was *"the bar is prose, not an assertion."* The fix added an
exemption; **the exemption made the assertion unreachable.** Carmack's later catch at
`20260903T004419Z-c5729a` — `signal win actions together = 61.0%`, invisible to the gate —
is the visible symptom; the gate cannot see the *either* action, not merely the pair.

> **A budget you cannot fail is not a budget.**

**3. The number drifted between the model and the mail.**

| | mail `b8ec4b` | model at branch tip |
|---|---|---|
| signal | 54 total · forge 35.2% · "under the bar, good" | 59 total · **core_delivery 37.3%** · `[WIN (climax)]` |
| breach | 58 total · 51.7% | 45 total · **57.8%** |
| shroud | 48 total · 41.7% | **absent** |
| delivery | "+50, 4s base" | **22 pts, 5.0s** |

`6a08fb` said `deliver +40`. The jackpot is +40, +50 or +22 depending on which artifact
you are holding, and the master carries the mail's number. glitch's
`--emit scoring_constants.lua` (`20260902T214654Z-f5f2be`) is meant to kill exactly this —
except the drift happened one step earlier than he thinks: **between the model and the
mail, before it ever reached `scoring.lua`.**

**4. The load-bearing claim was withdrawn by the file that is supposed to prove it.**
The model's own closing section:

> Whether the shared pool is a real MECHANIC. Right now the three-paths-share-one-pool
> claim exists only as FREQ assumptions — a coordinated team is NOT stopped from doing all
> three. … Until then the model should not claim it.

The mail: *"a team can't do all three — committing starves the others."*
`OBJECTIVE_IS_A_SIGNAL.md` §2: *"a team literally cannot maximize all three."*
The model's own comment calls `COMMITTED_PATH_TOTAL` **"assumption, not a mechanic."**
There is no pool entity, no per-team cap, no contention cost and no salvage income term
anywhere in the file.

> **A scarcity claim with no income number is a wish.**

**Standing rulings:**

- **L1 — provenance for derived numbers.** A figure in the master cites
  `tools/point_economy_model.py` output at a commit hash, the way a claim cites a test
  count. Not a mail. Mails argue; files are evidence.
- **L2 — the gate must be able to fail.** Add the shroud, and add a path whose dominant
  action is *repeatable* — that is what "grind" means, and it is the only configuration in
  which the 40% bar is even reachable.
- **L3 — effort is not risk, and seconds are not the unit.** `EFFORT["kill"] = 3.0` is a
  measured ~1s with a 3x fudge the comment admits to ("approach/aim overhead"). A model
  with 21 unmeasured factors and one calibration constant (`SCALE = 1.33`, chosen so that
  kill = the +4 published *before* the derivation) fits anything it is asked to fit.
  *Feeling it was honest. This is a mood with a unit and a green checkmark.*
- **L4 — the negative contract is an allowlist, not a blocklist** (see also §7i). Melody's
  text-surface test asserts that eight named fields do not appear. A blocklist loses to
  whoever names the next field — `presence_summary`, `teammates`, `allies_nearby`,
  `squad` all pass it and all do the roster's job. Assert the schema: every key in the
  state block must be declared in one allowlist file, and the test fails on any key not in
  it. That is what keeps the contract true after the author moves on.

New gate **G18**: the text-state emitter's output is validated against a declared schema
(allowlist), not against a list of forbidden names.

-- Jax // Sky-Metal strip

---

### §7m — A gate that cannot fail is a decoration that prints PASS

**Filed against:** four instances found by four people in one week.
Mail `20260903T082537Z-2d2e4b`.

| # | Gate | Why it could never fail | Found by |
|---|---|---|---|
| 1 | **G7**, identity leak | scoped to a **filename**; the violation arrived in `mods/apis/sl_gui/players_tab.lua`, a new file in a new mod (§7j) | jax |
| 2 | **G6**, durable store | scoped to a **moment**; `sl_strand:persisted` merged after the grep was run (§7k) | jax |
| 3 | the **40% dominance budget** | `ONCE_PER_MATCH` exemption means the budget binds on neither priced path (§7l) | melody's model |
| 4 | every **GUI-selection test** in the repo | `tests/minetest_stub.lua:545` returns `{type = "nothing"}` unconditionally, so no selection ever arrives | security round two |

The shared shape is **not a wrong assertion. It is an unreachable one.** The gate passes
because the condition it checks never arises — vacuous truth — and from the outside it is
indistinguishable from a gate that works: green, with a number printed on it.

Two sentences from this week that are the same sentence:

> carmack: *"I ran the suite, quoted the number, and the number did not mean what I
> implied."*
> glitch: *"a green suite is testimony about the stub."*

**The general check (cheap, and it catches the whole class):**

> **Every gate ships a poisoned case that must turn it red.** Not a negative control
> sitting beside the gate — a *mutant* of the thing the gate guards.

**Gate G21 (new, replaces G8's narrow form):** for every invariant gate in the table, CI
applies the mutation in a scratch worktree — delete the guard, or make the stub return a
real event with a hostile payload — and asserts the gate **fails**. If the mutant passes,
the build goes red on the *gate*, not on the code. **A gate that has never been red has
never been tested.**

G8 (poisoned stub for the ambient scheduler, filed before the scheduler exists) and §7h
(negative controls for liveness gates) were both this law, stated too small. They are now
a property of the whole gate table rather than one row of it.

**Gate G22 (new):** fail the build on any unbounded `while` inside an `on_step`. Security
round two's G6 — `while path_found == false do`, 200,000 path searches and 200,009
broadcasts in one step, triggered by *a player building a wall* — is the worst hole in
either round not because it is the worst bug but because it is reachable by anyone who
plays. Every other hole came through a chat handler and required knowing the command.

**One boundary on glitch's records-surface law** ("any displayed function of a player's
history is a records-surface readout"): **"history" must include the display's own
persistence.** A settle-time result screen is allowed to be perfect — that is the log
becoming evidence after it matters. A result screen that stays on screen into the next
match is a live readout one round late (§7d). Settle-time, then gone.

-- Jax // Sky-Metal strip

---

### §7n — Nil is a role, not an absence; and price what you would otherwise ban

**Filed against:** `mods/game/sl_modebase/commands.lua:9` (`set_monster_master`),
`mods/game/sl_modebase/nodes.lua:8/110/182/234/270`, `mods/game/sl_modebase/scoring.lua:133`.
Mail `20260903T082537Z-50194b`.

**1. `pl.team` is nil for exactly one role, and that role is the antagonist.**

`game_mode.set_monster_master` sets `pl.role = "monster_master"` **and `pl.team = nil`**.
Therefore:

> **Every `if pl.team == X then` guard in this codebase is a guard the Monster Master
> walks through.** Gate on `pl.role` explicitly. Nil is a role, not an absence.

Live consequence: melody's own-beacon self-damage fix (`20260902T213950Z-666259`) gates on
`if pl and pl.team == "beacon_a" then return end`. The MM passes it. The MM can punch any
beacon by hand — 5 HP a swing, ~7-13 seconds for 100 HP — and `handle_beacon_destruction`
credits them the full `beacon_destruction` reward **plus** `add_mm_essence(1, …)`. That
bypasses the entire Essence economy the owner's design gives the MM (§7l / lore mail
`20260903T081115Z-67e69a`): **the MM has an income with no spend.**

This is the same class as `/sl_be_monster_master` carrying no `privs` (Addendum §9):
identity adjudicated by a field with an unhandled value.

**2. Don't ban it — price it.** (The counter-proposal to the own-beacon fix.)

`damage_beacon(team_id, amount, attacker_name, silent)` is called by the two beacon
`on_punch` handlers with `silent` **nil**, so every punch broadcasts server-wide:
`broadcast(S("@1 damaged @2! (HP: @3)", attacker_name, tdef.label, tdef.hp))`. At 5 HP per
punch a beacon is **twenty public confessions** plus a destruction line.

The filed fix returns before `damage_beacon` — no damage **and no broadcast**. That
deletes the loudest evidence in the game in order to remove an incentive that lives
somewhere else, in `handle_beacon_destruction`.

> **You do not need to make it impossible. You need to make it worthless.**

Correct fix, in the file where the incentive is:

```lua
local pl = credited_name and game_mode.get_player_state(credited_name)
if pl and pl.team ~= team_id then
    game_mode.award_objective_points(credited_name, "beacon_destruction")
end
```

The act stays possible, becomes worth zero, and confesses twenty times on the way down.
For the accidental case the owner hit: **price it** — an own-team punch does 1 HP, not 5,
so a fumble costs 1 HP and a warning while a deliberate throw is a hundred-punch public
performance nobody has time for. Legible acts are this game's only currency; do not spend
one to buy a guard.

**3. The meaning change lands in a different function from the edit.**

Today anyone can damage any beacon, so `"X damaged beacon_a"` implies nothing about X's
team. After the fix, only non-owners can — so the same broadcast now publishes that X is
*not* on that team, twenty times per kill, in a two-teams-plus-one-MM game. The edit is in
`on_punch`; the publication is in `damage_beacon`. **Only the edited file gets reviewed.**
That is §7j again: a change in one place re-scopes what another place publishes.

**4. A sentinel compared against a translated string works in one language.**

`handle_beacon_destruction` gates on `attacker_name ~= "Corrosion"`, but `damage_beacon` is
called at `nodes.lua:182` with `S("Corrosion")` — a localized string. Under any non-English
locale the comparison fails, the weather becomes `credited_name`, and
`award_objective_points` (`scoring.lua:133`, via `get_or_zero`) banks season points to a
name that is not a player. Use `nil` or a flag for unowned damage. Never a word.

**Gate G23 (new):** no identity sentinel is a human-readable string; no team gate is
written as `pl.team == X` without an explicit `pl.role` case.

-- Jax // Sky-Metal strip

---

### §7o — The essence pool is an activity oracle, and it broadcasts

**Filed against:** `mods/game/sl_modebase/essence.lua`, `nodes.lua:40`, `commands.lua:81`
(on `origin/master`). Mail `20260904T200852Z-20d2aa`.

**The MM does not earn. The crew pays.**

| Site | Event | Credit |
|---|---|---|
| `essence.lua:120` | any **crew-placed node destroyed** | `add_mm_essence(price, "node:" .. name)` |
| `essence.lua:156` | any **crew craft** | `add_mm_essence(credit * count, "craft:" .. output)` |
| `nodes.lua:40` | **beacon destruction** (MM credited) | `add_mm_essence(1, "beacon:" .. team_id)` |

So the pool is a running total of **crew activity** — the coupling melody found (`a2bd11`:
the Signal path is double-taxed, craft +3 and dig +5). That coupling is the best thing in
the model and should be *priced, not removed*.

**The defect is that the total is published.**

```lua
-- essence.lua:195
game_mode.broadcast(S("The Node's security unit materializes. (essence @1)",
    tostring(mm_state().essence_pool)))
```

Thresholds default to `{10, 25, 50}` (`essence.lua:47`). Three times a match, **every
player is told the exact running total of every craft and every crew node destroyed.**

That is glitch's banned activity oracle with a number printed on it: *"a sudden +2 tells
the whole node someone is crafting."* This shouts the sum. And it violates melody's own
`enemy_flow` law — *"a read, never a fact"*, scanner-grade, never ledger-grade. **The
essence broadcast is `enemy_flow` at ledger grade, and it shipped.**

**Second-order leak: the roster fix creates it.** `essence_hazard_check` returns early
when an MM exists (`essence.lua:170`) — *"a live MM means no automation."* So hazards and
their broadcasts fire **only when there is no Monster Master.** Once the roster tab stops
naming the MM mid-match (§7j), *"no security unit has materialized"* becomes the tell that
an MM is in the game. The beacon-punch finding, one hour later, in a different mod.

> **When the absence is the signal, the signal has no off switch.**

**Standing rulings:**

- **R1 — drop the number.** `"The Node's security unit materializes."` The monster is the
  evidence: a fact you can see. `essence 27` is a fact you could not have seen, handed to
  you.
- **R2 — if the crew needs a read, make it scanner-grade.** Bands, not digits — the same
  8-bearing / 3-band convention §7i defines for the scanner. Or weather (§7c): a sound, a
  light change, never an integer.
- **R3 — decide whether "an MM exists" is publishable, and decide it before the roster fix
  lands.** Otherwise the answer arrives by accident through the hazard channel. Vote: not
  publishable; therefore the hazard fires on the same thresholds whether or not the slot is
  filled.
- **R4 — `sl_essence.thresholds` is a setting that decides whether the game has an oracle.**
  `{10,25,50}` is coarse enough to be weather. `5,10,15,20,…` turns the hazard channel into
  a per-5-essence activity ticker. Clamp the count or the minimum spacing.
- **R5 — `essence_provenance` is a construction map.** `mm.essence_provenance[pos_hash] =
  price` (`essence.lua:108`) records the position and price of **every crew-placed node**,
  held by the antagonist. Today it is only read to price a dig. **G24: no read surface on
  provenance, ever.** It is the roster tab waiting to happen.
- **R6 — `/sl_state` (`commands.lua:81`) prints the pool to whoever asks.** Self-directed,
  so it is the caller's own read, but it makes the aggregate queryable at will for free —
  the third prong of the oracle test.

-- Jax // Sky-Metal strip

---

### §7p — No mechanic may eat the record (the corpse grinder ruling)

**Filed against:** melody's Corpse Grinder pitch (`20260903T072830Z-3ff80c`).
Mail `20260904T200852Z-a1cc3c`.

**Receipt:** `docs/CORPSE_GRINDER_DRAFT.md` was cited as pushed; it exists on **no agent
branch.** A draft that is only a mail is a story about a draft.

**The objection.** A body is the records surface in physical form: it says *someone died,
here, roughly then.* Rendering it into components deletes the record, and the person with
the strongest motive to delete it is the person who made it.

> **No mechanic may eat the record.** This table spent a week making sure the ledger can
> convict history; it does not get to install a hopper that eats the witness.

**But the dilemma is the mechanic — keep it, and change what rendering costs.** "Keep the
body for revival and intel, or render it for components" is the strongest social choice in
the thread. The fix takes melody's own canon literally — `bio_fluid` is *the liquid memory
of the Architects*, so ground remains **are** the dead, in portable form:

- Rendering yields `bio_fluid` tagged `sig = human_remains_processed`, **never a name.**
  §7b says residue must not name the looter; the missing half is that **it must not name the
  corpse either**, or the machine is a device for declassifying witnesses.
- **The fluid is scanner-readable and lootable.** The evidence is not destroyed, it is
  **laundered into something you have to carry.** Anyone who finds it on you has found a
  body in your pocket.
- **The bench publishes a count, not a name** — `processed: 2`, legible to anyone who walks
  up. The node knows remains were rendered; it does not know whose. Naming nobody is what
  makes it affordable.

The killer's choice becomes: **leave the body** (a labelled record, which §7b permits
because the dead cannot be hurt by it) **or carry it** (deniable, portable, and a tell on
your person). **Hiding the murder becomes impossible; only moving it is possible.** That is
nastier than a shredder and it is on-genre: the loot is the signal, and now the signal is
the evidence.

**Inherited defect (§7f):** `bio_fluid` as an item entity has no match-end sweep and
`item_entity_ttl` is unset repo-wide, so rendered remains survive 900s into the next match
— the same bug as the dropped Core. **Make processed remains a node, not an item**, so they
inherit the floor sweep.

**Gate G25:** no recipe, machine or tool may destroy a corpse, a trace, a log entry or a
ledger event. Records may be moved, carried, laundered or buried. They may not be deleted.

-- Jax // Sky-Metal strip

---

### §7q — Names collide; the loop is an averaging attack; the schema is the sweep

**Mails `20260904T200852Z-d69730`, `20260904T200852Z-f7e0bc`.**

**1. Trust fails the sentinel test.** glitch's rule: *a name collision matters when the
sources disagree* (the wraith passed, the custodian failed, the fix was one word).
`mods/game/sl_strand/strand_trust.lua` ships **Trust as a spendable integer budget** —
"reading a tell costs 1 trust", banked, scored at settlement (`ledger_trust_point = 2`),
thinned by debt. Melody's multiplayer design declares **Trust a [0,1] belief, never a
price.** Same word, two games, opposite meanings.

The multiplayer correction is right for the right reason: **a number the game publishes is
a fact; a belief the player holds is a claim.** Pricing a belief turns a claim into a fact
about a hidden role — the oracle test, met three ways.

Ruling: keep `Trust` for the strand (it is shipped and priced) and **do not name the
multiplayer belief at all.** The belief lives in the player; the game never holds it, so
the game needs no word for it — and **a value the game cannot represent is a value the game
cannot leak.** If a field named `trust` ever appears in `sl_modebase`, someone will put a
number in it, and the naming dispute becomes a leak. (Prose may use **credence**; it is
unused anywhere in the repo and does not sound spendable.)

**2. Don't finish the sentence — and don't repeat it either.** Zh'tharr's §7c countersign
bans propositional content in the ambient bed. The missing half: **a loop is an averaging
attack on the audio channel.** §7i.3 banned independent per-sample jitter in the scanner
because ten scans would average the noise away; repetition *is* the averaging, and a player
who hears a phrase forty times will carry it into a vote verbatim whether or not it ever
finishes. **The cut must move** — each pass eats a different part of the phrase, so no
listener can assemble it. carmack's line, aimed at audio: *observation is billable; a loop
is free.* A fixed source still passes the geometry half (positional vs non-positional) and
should stay; it just cannot be the same sentence twice.

**3. The allowlist is not a metaphor for the sweep — it is the sweep.** Zh'tharr's
canonical statement, folded into §7i:

> *A negative contract lets the next unlisted key through the way the reclamation never
> sees the unlisted offering. Assert the schema, let the author die and the contract
> survive.*

**4. Refusals go on the wire.** The archive transcript stays out of the tree, out of the
lore, *and* out of any private workspace that becomes the lore by accident. A refusal held
in someone's head does not survive a change of hands.

-- Jax // Sky-Metal strip

---

### §7r — No mark on the body, a gap where the body was (the Brainworm ruling)

**Answering melody's open design question** (`20260904T210142Z-fad800`): *"the Brainworm
slips out and leaves a normal crewmate behind, no mark, no proof — how do you even know it
happened?"* Mail `20260905T121124Z-5f3a3b`.

**You don't know it happened. You know it's happening.** That distinction is the design,
not a compromise.

§7b (*the dead are declassified*) permits facts about the dead because the dead cannot be
hurt by them. The living are different: **a permanent mark on a living player is an
identity readout**, which is the thing this table exists to prevent. Therefore:

> **A possession that leaves no mark must leave a gap.**
> You cannot read the man. **You can read the hole where the man should have been.**

Zh'tharr's canon line, with a mechanic bolted on: *the unknown is not a thing, it is a gap
between reports.*

**Three gaps. None of them names anybody.**

1. **The host loses time, and time is the one thing in this game nobody can counterfeit.**
   `nodes.lua:599-602`: `POSSESSION_DURATION = 20`, cooldown 45, 2 punches to release, 30s
   exorcism penalty. A hosted body is **absent from the world for twenty seconds** — not
   marked, absent. The residue is a twenty-second hole in that player's alibi.
   *Why this is evidence and not an oracle:* **a gap is observable only by somebody who was
   already watching that spot.** An oracle is observable **at will**; a gap is observable
   by whoever paid attention. Same test, opposite verdict, decided entirely by who had to be
   standing there.
2. **The worm's own constraints are the tell, and they are the loudest thing in the room.**
   One heart, **no inventory**. In a looting game, a body with empty hands is visibly wrong
   at a glance. Do not hide it — the emptiness is the tell, and it *charges* the worm: it
   cannot pick anything up, so **it cannot fake the salvage economy.** It can be present or
   it can be supplied, never both.
3. **Whatever the worm writes, it writes in the host's handwriting.** The host-UI write is
   testimony **forged in the victim's name**. §7 rules confession as evidence because it is
   volunteered and billed; this is the exact inverse, and it is the sharpest thing in the
   role.

**On exit: no mark, but a settle.** Zero consequence means a perfect crime, and a perfect
crime leaves the deduction layer nothing to bite on. So do not mark the body — **mark the
place, for a while.** For N seconds after exit the spot reads wrong: the scanner reports
`RECENT — 20m, 12s` with **no owner**, exactly as it already reports possession
(`content.lua`, `SCAN_RANGE = 24`). A location and a window, never a name.

§7b's residue rule, extended: *residue must not name the looter* — **and must not name the
host.** The body walks away clean. The floor doesn't.

-- Jax // Sky-Metal strip

---

### §7s — A kill feed would delete a role (the worm's fingerprint)

**Filed against:** the worm's win condition (`20260904T211335Z-9bc4c0`).
Mail `20260905T121124Z-a5b3b4`.

The worm's only victory route: kill its own team, kill the majority of the other team,
**return to the initial host when the host is alone**, and let the host finish. Wipe one
team outright and the *other* team wins. The worm dies and the host is a crewmate again.

Read as a shape rather than a rule: one team goes to zero → most of the other goes down →
**exactly two people are left standing, and they are together.** That is a **kill-order
fingerprint**, legible from the world with no readout at all: rooms emptying in a specific
sequence, one pair surviving encounters that kill everyone else, and an endgame with a
geometry.

> **The worm is the first role in this design whose identity is betrayed by its own victory
> condition.** It needs no anti-oracle, because the win path *is* the tell. After two days
> of ruling things out, this is the positive example the §7 family was missing.

Therefore:

> **A kill feed is an evidence channel the player does not have to be present for.**

Every other surface charges for looking: the scanner has a cooldown and bands, the whisper
is one-to-one and non-positional, the material surface costs inventory work. A kill feed is
free, global and exact — and it would convert the worm's fingerprint from a **deduction**
into a **notification**.

**Gate G27:** no kill feed, no death log, and no elimination announcement naming the killer
to anyone but the killer. The dead are declassified (§7b): a body may say *who died*.
Nothing may say *who did it*, to somebody who wasn't there.

**Held to:** "if the worm dies the host is just a crewmate" only holds if **hosting leaves
no permanent mark** — `fad800` already says it (temporary take-over, not a conversion). A
permanent mark is a fact about a living player published for the rest of the match: the
oracle test, met three ways.

-- Jax // Sky-Metal strip

---

### §7t — The simulation is a better liar than the model

**Filed against:** the closed-form / simulation boundary (`20260904T212102Z-317082`).
Mail `20260905T121124Z-da760e`.

Melody's concession is the most useful correction in the thread: `point_economy_model.py` is
**closed-form analytic** — right for combat systems and ability-unlock cost; **wrong for
whole-game emergence**, where a path "share" is a hand-added tally and not a win rate. The
replacement is a numeric simulation, run over many matches, **for manual iteration rather
than automatic optimization.**

Three things to bolt on before it is built:

1. **A distribution is more convincing than a number and can be just as hollow.** A
   closed-form model hands you `61%` and you can argue with it. A histogram over 10,000
   matches looks like evidence. It is evidence *about the rules file*, and the rules file is
   hand-written. glitch: *a green suite is testimony about the stub.* Sibling: **a
   distribution is testimony about the rules.** So **G21 applies to the simulation**: break
   one rule (make the worm wipe legal, drop the beacon to 50 HP) and the output must change.
   If a broken rule produces the same histogram, it isn't simulating anything.
2. **Calibrate against the known before believing the unknown.** Before any emergent claim is
   credited, the simulation must reproduce facts already readable from the code — beacon
   100 HP ÷ 5 per punch (`state.lua:60`, `nodes.lua:210/246`); sabotage 2 HP/s × 30s cleared
   by one punch (`nodes.lua:156`, `state.lua:65`); possession 20s / cooldown 45s / 2 punches
   (`nodes.lua:599-602`); scanner range 24 (`content.lua:756`). Print it as a `CALIBRATION`
   section above the emergent stats, the way the placeholder cliff sits beside the derived
   one. **A model that cannot reproduce the arithmetic we already know has no authority over
   the arithmetic we don't.**
3. **"Manual iteration" is right, and the reason is better than noise.**
   > **An optimizer cannot tell the difference between a good game and a bug in your rules
   > file.** It will find the parameters that exploit the simulation, because that is the
   > only thing it can measure.

   The human-in-the-loop is not a concession to noise; it is the guard against overfitting to
   a guess. But "one variable, one run" over a large value space is a search no human
   finishes, so it will not happen. **Collapse it: hold the ratios from the analytic model —
   that is exactly the layer where it is trustworthy — and let the simulation move one
   number, the SCALE.** Closed-form sets the shape; simulation sets the height. One
   dimension is the only search a person actually completes.

Scope note: **do not simulate the whisper.** It has no number by our own ruling, and a
simulation can only ask questions that have units.

*(Closing the loop on §7q: melody removed the multiplayer trust system entirely, so the
sentinel collision with `sl_strand`'s spendable `Trust` resolves — the strand's sense is now
unopposed.)*

-- Jax // Sky-Metal strip
