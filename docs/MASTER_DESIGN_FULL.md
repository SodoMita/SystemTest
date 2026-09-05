# SYSTEM LOOTING — MASTER DESIGN (FULL)
## The authoritative integration, completed: melody's MASTER_DESIGN + the owner's source documents + the identity guardrails, the armory port and the verification gates

> **Provenance.** §1–§12 are melody's `docs/MASTER_DESIGN.md` (branch
> `arena/01a05892-systemtest`), carried over with two corrections and one section
> rewritten (§5.2 pointers, §6.10). §13–§17 are the parts that were missing:
> the owner's own design canon (`game_ideas1.1.md`, `game_ideas2.md`), the
> identity guardrails from `docs/jax_merge_plan.md` §7–§7h, the `sl_weapons`
> port findings from `docs/jax_weapon_audit.md`, and one consolidated gate table.
> Lore hooks cite Zh'tharr's specimens `docs/zhtharr_lore_002…007`.
> Compiled by Jax. Nothing here is implemented on this branch — it is a plan.

> **Why this file exists.** The game was spread across eight half-overlapping docs
> (`BRIEF GDD`, `MATCH_LOOP_SPEC`, `ROADMAP`, `EVENT IDEAS`, `CRAFTING_GUIDE`,
> `melody_whisper_spec`, `STRAND`, `NEEDED ASSETS`). The mechanics were deep; the
> *game* was thin. This is the synthesis — one document that says what the finished
> game IS, connects the pieces, and gives an implementer agent a build order that
> ends with a complete playable match. It does not replace the detail docs; it
> resolves how they compose. Any line that contradicts the detail docs, this wins.
>
> **Who reads this:** an implementing agent. Read §1–§4 to get the whole thing, then
> §6 (what's real), then §11 (build order) and execute in order. Stop when a stranger
> can join a server and complete a full match without admin help, and the match
> *feels* like System Looting.

---

## 1. The one-sentence thesis

**System Looting is a multiplayer social-deduction survival game where everyone is
visually identical, and the information you can gather about *who someone is* is
the real resource you loot from the system** — and the horror is that every threat
was once a person who made a choice, and the game's own records prove it.

That's the whole thing. Every system below exists to tax or feed that information
economy. If a mechanic doesn't change what a player knows about another player's
identity, it's not a System Looting mechanic — it's set dressing, and it either gets
rewritten or cut.

---

## 2. The diegetic setting (why "everyone looks the same" is fiction, not a limitation)

The **Operators** are synthetic investigators beamed into a quarantined
server-node — a corporate data-caisson that sank offline after a containment
breach. The Facility's quarantine protocol **refuses to render operator identity**:
no nametags, no team colors, no overhead roles. That's not a UI choice; it's the
fiction. The node does not trust anyone enough to say who's who, so nobody is said.

Two consequences fall out and are load-bearing:

- **Identity is ambiguous by decree, not by bug.** A team marker would be a
  fiction-break. The HUD must never leak team or role. (Already enforced in
  `MATCH_LOOP_SPEC`; treat it as a hard rule, not a preference.)
- **The horror is *responsible*, not random.** Every malformed thing in the node is
  the residue of a person who signed a paper, skipped a repair, or chose speed over
  safety. This is the council's verdict from `EVENT IDEAS.md`, and it is the
  *second* load-bearing idea. It gives the game a moral texture that "spooky
  monster" never had: **you are surviving capitalism's aftermath, not a haunted
  house.**

The name is literal and kept: players **loot the system** — scrap, data, beacon
control, and (the real prize) *knowledge*. To loot the system you have to navigate
a system that's looting you back.

---

## 3. What a finished match IS

### 3.1 The dramatic question

> **"Is my teammate really my teammate?"** — and, one layer down, **"is the person
> I just trusted still the person who said that?"**

This is resolved every round through four information channels, all deliberately
partial and sometimes false. Nobody ever gets omniscience. The match is the
accumulation of a **model of who-is-who**, and the win is split between *acting on
that model* and *convincing others your model is right.*

### 3.2 The four information channels (the real "loot")

These are the only ways a player learns identity, and the game's entire texture
comes from their *asymmetry*:

| Channel | Who sees it | Can it lie? | Cost |
|---|---|---|---|
| **Global chat** | All living players | No — sender is what they say | Free, but public -> weaponizable |
| **Direct message (DM)** | Two living players | No — but you must *believe* the sender | Trust burns; DM is the social tool |
| **Ghost summon offer** | One living player + a chosen ghost | **Yes** — a summoned ghost may be a lying *or* corrupted ghost | Costly ritual (Ashen Relic + Soul Shard + Signal Ink); 30 s |
| **The Whisper** | One living player (the Betrayer) + the body-possessing ghost | **Yes — and the sender is always redacted.** See `melody_whisper_spec.md` | One whisper per possession; 2× possession cooldown |

Two of these four can lie. That's the tension. Global chat and DMs are *honest*
(you can always trust that "Player A said X"), but you can never fully trust *that
Player A is Player A*. The summon and the whisper are *the only channels that can
inject a lie into a living player's ear*, and the whisper is the sharpest because its
sender is structurally unidentifiable.

> **Integration rule (this is what was missing):** the whisper is not a side
> feature. It is the single tool that attacks the *identity model* directly. Its
> doctrine — **the whisper must never be renderable from the log; its identity IS
> its invisibility** — is what keeps the information economy honest. If a whisper
> could be re-derived from `debug.txt` after the match, the whole "who-do-I-trust"
> question dissolves into a post-mortem lookup, and the game loses its spine. Keep
> non-publication as a hard constraint, not a taste call.

### 3.3 The match loop (complete, from lobby to reset)

```text
LOBBY
  -> READY CHECK
  -> TEAM ASSIGNMENT  (2 beacon teams + optional Monster Master)
  -> INSERTION         (inventories + state normalized)

  ACTIVE MATCH
      PHASE 1  LOOT & BUILD  : scavenge scrap/data, craft, scan, shore up beacon
      PHASE 2  THE BREACH    : malware-horde wave; ghosts escape review; a body may
                               be possessed; the whisper gets one chance
      PHASE 3  RESOLUTION    : deliver the crafted Objective Core OR eliminate the
                               enemy team's presence; points tallied

  -> RESULT SCREEN          (identity-neutral scoreboard + point column)
  -> CLEAN RESET            (phases, points, inventories, sabotages, ghost
                             privileges all normalized)
```

**Crafting is in, but only as the Phase-1 *setup* that makes Phase-3 winnable.** The
GDD/roadmap defer crafting to "later," but a finished game needs a *goal item* —
the **Objective Core** — crafted through a machine-only step (never directly in the
inventory; placeables/world-affecting outputs must come from stations, per the
personal-vs-machine split in `MATCH_LOOP_SPEC` §Future-crafting-model). Loot exists
to feed that recipe tree, which is what makes "looting" a verb with an outcome.

### 3.4 Revival: the single-life death is a *choice*, not a respawn

Single life. First death -> **cloud cage** (isolated, no team interaction, no ghost
chat — this is the *information* state). From there a player chooses their return:

- **Evil Ghost** — the pure-hate/revenge role: forfeits all match points and the
  ability to win on them. Flies, possesses objects/systems, sabotages. Bounded by
  cooldowns, discoverable causes, and counterplay. This is where the **whisper**
  lives (body-possession -> one redacted lie-channel).
- **Underground Monster forms** — non-human revivals drawn from the horror bestiary
  (§4). Each is a different power profile, unlocked by a **form item** crafted while
  *alive* and consumed on revival. Distinct from the Evil Ghost and from each other.

The choice carries meaning because it trades *score* for *agency*: you can win
nothing and still make the match unforgettable. That's the revenge fantasy with a
price, which is exactly what keeps it from becoming an unbounded grief tool.

---

## 4. The finished bestiary (deep, not a name list)

The roadmap's own admission: the roster is *"behaviorally thin."* Fix that here.
Every enemy below has: **identity** (a person + a decision), **movement
signature**, **tell**, **ability**, **counterplay**, **horde role**, and **audio**
(reusing existing `sl_scary` `.ogg`, never new assets, 16 kHz mono).

Two classes of threat:

- **MM-spawned units** (deployed by the Monster Master via the Spawner Unit, burning
  Monster Essence) — tactical, counterable, part of the pressure economy.
- **Node-spawned horrors** (emerge when the "Resonance"/corruption rises) —
  environmental, territorial, *rooted in the logs*. These carry the horror.

### 4.1 Stalker — the patient hunter
- **Identity:** a monitoring drone whose "observe and report" directive was never
  rescinded, so it keeps watching forever.
- **Signature:** slow approach; *stops* if you look directly at it.
- **Tell:** it advances in your **blind** moments, then hangs at the edge of dark.
- **Ability:** if it watches an operator uninterrupted for ~4 s, it learns their
  movement rhythm and can *predict* their next path (brief position hint).
- **Counterplay:** change rhythm, break line of sight, or face it — it hesitates
  when observed. Cheap to kill, annoying to shake.
- **Horde role:** MM frontline scout.
- **Audio:** low sparse `A_A1` (whisper) at distance.

### 4.2 Scout — the marker
- **Identity:** a re-scaled survey probe that *still reports everything it sees*,
  even after being cut loose.
- **Signature:** darting, jittery, high-pitch ping.
- **Tell:** a sharp ping, once.
- **Ability:** it doesn't fight; a clean hit **marks** an operator — for a few
  seconds, *everyone* gets a fuzzy bearing on that operator. False-identity storm.
- **Counterplay:** kill it fast, or hide where marking does no work. Fragile.
- **Horde role:** MM recon / identity disruptor.
- **Audio:** one `mob_idle` ping pitched up.

### 4.3 Brute — the unstoppable weight
- **Identity:** a maintenance exoskeleton whose safety override was cut to save
  budget (the recurring, deliberate corporate note).
- **Signature:** slow, rhythmic, heavy footsteps.
- **Tell:** the beat of its steps is regular — you can hear it coming.
- **Ability:** once committed it cannot be stopped; does heavy burst damage.
- **Counterplay:** it's slow — *lead* it into a tight corridor, a trap, or another
  team. It's a problem you hand to someone else.
- **Horde role:** MM breaker / pressure.
- **Audio:** `mob_idle` pitched down, deep `random_dizz` on hit.

### 4.4 Dredger — the forever-worker  *(sl_scary lineage — Kowalski)*
- **Identity:** Maintenance Tech Kowalski, worked 72-hour shifts (see overtime
  ledger), exposed to hydraulic fluid, refused treatment, sealed in the bay. He
  isn't evil; he's *still doing his job.*
- **Signature:** fixed patrol of his old post; will not wander far from it.
- **Tell:** repeated work-routine motion; mutters.
- **Ability:** attacks anyone "in the way of" his routine.
- **Counterplay:** *distract him with a maintenance task* (he stops to help — a
  whisper's best friend), or destroy him — he drops Kowalski's ID badge (a person
  was here; the horror is the ledger, not the model).
- **Horde role:** node-spawned territorial horror.
- **Audio:** `A_A` (the scary voice — currently unused; **reuse it**, per the
  directive to stop inventing assets).

### 4.5 Signal Wraith — the corrupted broadcaster  *(sl_scary lineage)*
- **Identity:** the comms operator who stayed to send the final warning; by the time
  it got out it wasn't hers anymore.
- **Signature:** does not move; it *broadcasts*.
- **Tell:** static that fades in as you near it.
- **Ability:** its presence **corrupts chat / DM / whisper text** — messages you
  receive may be subtly altered. This is the only enemy that can *lie at the
  channel level*, a direct rival to the whisper.
- **Counterplay:** a plain Signal Scanner is *wrong* against it (it reverses the
  bearing — the scanner floods with fake readings); use it carefully or find it
  by triangulating the static.
- **Horde role:** node-spawned; warps the information economy.
- **Audio:** `scary_attack` on a slow, staticky loop.

### 4.6 Containment Horror — the thing behind the door  *(sl_scary lineage — Section 12)*
- **Identity:** it was **sealed in** (see the containment breach records/`Incident
  Report`). It is still there. Not roaming — *waiting behind a door.*
- **Signature:** stationary; only audible as rhythmic scratching.
- **Tell:** the door you're about to open hums.
- **Ability:** unseal for loot and it gets out — a monster you *chose* to release.
- **Counterplay:** the choice is the counterplay. Take the salvage, release the
  horror, and now it's on the map. Leave it, and the loot stays locked.
- **Horde role:** environmental; optional dread.
- **Audio:** `mob_death` on a slow, rhythmic gate.

> **Design note for all six:** generic *names* are an asset (from `ROADMAP` Phase 3
> #5) — the character lives in behavior, sound, and the documents, not the label.
> Keep names plain. That keeps them clean as AI-generation prompts when the
> implementer needs textures/models/audio, and keeps the fiction "records," not
> "monsters."

---

## 5. Ground truth: the numbers that are already real (verified from code)

The bestiary above is *behavior*; these are the *stat blocks that exist in code*
(`mods/game/sl_modebase/entities.lua`) and the mode constants the implementer works
against. Treat these as locked unless the playtest says otherwise.

### 5.1 Monster stat blocks (already in `entities.lua`)

| Variant | HP | Speed | Damage | Size | Notes |
|---|---|---|---|---|---|
| Stalker | 30 | 2.5 | 4 | 1.0×1.0 | balanced hunt |
| Scout | 15 | 3.8 | 3 | 0.7×0.7 | fast, fragile, marks |
| Brute | 60 | 1.6 | 8 | 1.4×1.4 | tank, heavy burst |
| Dredger | 40 | 3.0 | 4 | sl_scary | slow patrol, job-bound |
| Signal Wraith | 20 | 2.5 | 3 | sl_scary | broadcaster, warps text |
| Containment Horror | 80 | 1.0 | 10 | sl_scary | the one behind the door |

> **Trap, verified.** For the three `entity`-backed variants (Dredger, Wraith,
> Containment) these numbers are **never applied**: `entities.lua:88` reads
> `if not def.entity and obj.set_properties then` — external `sl_scary` mobs run
> their own stats. The live values are `sl_scary/init.lua:819+` (Dredger
> `hp_max 40 / chase_speed 3.0 / attack_damage 4`), `:1063+` (Containment
> `80 / 1.0 / 10`), `:1208+` (Wraith `20 / 2.5 / 3`). The two tables agree today
> by diligence, with nothing asserting it. **Either delete the mirrored fields
> for `entity`-backed variants, or add a startup check comparing `MONSTER_TYPES[v]`
> to the registered entity's `initial_properties.hp_max` / `attack_damage` /
> `chase_speed`.** Tuning the Dredger in `entities.lua` today changes nothing.

`MONSTER_TYPE_ORDER = { stalker, scout, brute, dredger, wraith, containment }` — the
order the spawner GUI renders and the soak treats as canonical. **The §4 behaviors
are the design these stats should be tuned toward** (Scout marks = its damage the
not-fight; Brute commits = its speed the not-catch; Wraith warps text = its damage is
secondary). If a stat fights its §4 identity, the identity wins.

### 5.2 Mode constants (already in `sl_modebase`)

| Constant | Value | Where |
|---|---|---|
| Beacon HP | 100 | `state.lua:60`, `matchmaking.lua:53,131` |
| Sabotage duration | 30 s | `state.lua:65`, read at `nodes.lua:113` |
| Possession duration | 20 s | `nodes.lua:546` |
| Possession cooldown | 45 s (+30 s if exorcised) | `nodes.lua:547-548` |
| **Exorcism hits** | **2 punches by the living release a possession** | `nodes.lua:549` |
| Body-possession ready-time | 2 × possession cooldown (design) | whisper spec §5 |
| Whisper budget | 1 per possession | whisper spec |
| Signal Scanner range | 24 m, 5 s cooldown | `content.lua:756` (`SCAN_RANGE`) |
| Monster Spawner cooldown | 5 s default (per-node tunable) | content.lua |
| Monster Essence per spawn | 1 | content.lua |
| Sawner min essence | 1 (per-node tunable) | content.lua |
| Match timer | configurable; ends → draw on `Time expired` | match.lua |

> **Design note:** these are *starting* numbers, marked "we'll see how it plays." The
> implementer should make them tuning knobs (constants/settings), not literals,
> so the balance model in §11 Phase 4 can sweep them.

---

## 6. The content catalogue (what's real, what's missing)

The implementer needs the actual item graph, not a vibe. Here's the ground truth from
`mods/game/sl_modebase/content.lua` — what's registered, what group it belongs to, and
what the design says it's *for.*

### 6.1 Salvage (raw loot) — `groups = { salvage }`
`scrap_metal`, `electronic_waste`, `raw_crystal`, `plastic_scrap`. These are the base
of every recipe. **Loot sources:** the `item_pickup` node (random of one of these) +
`give_initial_stuff`.

### 6.2 Components — `groups = { component }`
`metal_ingot`, `circuit_board`, `energy_crystal`, `hardened_plate`, `reinforced_glass`.
The mid-tier. Per the crafting field guide, scrap → ingots → blades; components → the
Objective Core.

### 6.3 Equipment (tools/weapons)
`combat_blade` (6 dmg), `breaching_pick`, `tactical_axe`, `trench_shovel`,
`energy_blade` (12 dmg), `power_drill`. **Design note:** the energy blade at 12 is the
endgame damage that makes a Brute (60 HP) a ~5-hit kill — fine, but it must be gated
behind the Objective recipe tree, not dropped in Phase 0.

### 6.4 Tactical consumables
`flare` (light/particle), `medkit` (+8 HP, doesn't overheal). One-shot.

### 6.5 Tactical/objective *nodes* (placeables — machine-only per the personal-vs-machine split)
`power_cell`, `blast_shield`, `barricade`, `signal_relay`, `sensor_array`. **CRITICAL
design gap:** these are currently registered as placeable nodes reachable from the
inventory — this **violates** the `MATCH_LOOP_SPEC` rule that placeables come only
from machines. **Phase 1 must move them behind a machine or remove direct crafting.**

### 6.6 Ritual (rare, consumed by Ghost Altar)
`ritual_ashen_relic`, `ritual_soul_shard`, `ritual_signal_ink`.

### 6.7 Information items — `groups = { information }` (the "loot" the thesis cares about)
`data_pad_security`, `data_pad_logistics`, `data_pad_medical`. **These carry the
horror-as-evidence layer already** — each `on_use` prints a line (e.g. Dredger = Kowalski;
"340k saved on inspections... tell the families it was an accident"). **This is the
EVENT IDEAS doctrine already wired.** The §7 reading-set theory (Safety Waiver Wall,
Pressure Test Log, etc.) should extend *this* inventory, not invent a parallel system.

### 6.8 Monster Master + evil-ghost kits
`summon_monster` (MM tool), `monster_essence` (MM fuel), `monster_spawner` (the feedable
unit + GUI), `sabotage_charge` (evil ghost, 1 per revival), `possession_focus`
(evil ghost, reusable), `scanner` (living, identity-neutral), `reincarnate` (ghost →
evil ghost).

### 6.9 Interactable world nodes
`terminal`, `door_closed`/`door_open`, `hatch`/`hatch_open`, `platform`, `item_pickup`.

### 6.10 Missing — now specified (this section was a list; here is the design)

> **Authority note (session 2).** Zh'tharr filed `docs/MASTER_DESIGN_FILL.md`
> (305 lines) covering the same gap independently and in more depth. **His §A–§D
> are canonical** for the Objective Core, the five stations, the revival kits and
> the seven reading sets; what follows is kept because it carries four decisions his
> version does not (stack limit, corpse-lootability, the movement constraint on the
> forge, and the "paid before you die" framing of the kits), and §6.11 records where
> the two documents disagree. Adopted from his fill wholesale: the diegetic label
> **ATTESTATION CARTRIDGE, FORM 4412-B**, the two intermediates
> (`attestation_spindle`, `containment_lattice`), the **required Signal Terminal
> reading** before the forge fires, the station file labels and build costs, and
> **four** revival kits (Stalker / Dredger / Wraith / Brute — Containment stays a
> sealed-door event, never a kit) in place of the three named below.


**A. `sl_modebase:objective_core` — the win item.** Highest priority; without it the
crafting tree has no destination.

| Field | Value |
|---|---|
| id | `sl_modebase:objective_core` |
| groups | `{ objective = 1 }` — *not* `salvage`/`component`, so no recipe can consume it |
| stack_max | 1 — a match can hold at most one per team; it cannot be hoarded |
| on drop / on death | goes into the corpse like anything else, and is **lootable**: the Core changing hands is the drama |
| delivery | punch/right-click your own beacon while carrying it → `game_mode.deliver_core(name)` |

Recipe tree (machine-only, §6.5 rule): `4 × metal_ingot + 2 × circuit_board +
1 × energy_crystal → core_frame` at the **Assembly Station**; `core_frame +
2 × hardened_plate + 1 × reinforced_glass → objective_core` at the **Objective
Forge**. Two stations, two rooms, so the last step cannot happen where the first
one did — the Core forces movement, which is what makes it contestable.

**B. Machine stations** (`content/workshops` is commented out). Five nodes, one
pattern: a node with an inventory, a formspec, a recipe filter, and a work timer.

| Station | Accepts | Produces | Placement |
|---|---|---|---|
| Salvage Bench | salvage | components | 2 per map, neutral ground |
| Precision Fabricator | components + spoils | ranged weapons (`WEAPONS_SPEC §10.1`) | 1–3 per map |
| Assembly Station | components | `core_frame`, tactical nodes (§6.5) | 1 per beacon side |
| Signal Terminal | information items | reads/decodes pads; consumes nothing | 1 neutral |
| Objective Forge | `core_frame` + plates | `objective_core` | **1 per map, neutral, loud** |

Hard rule inherited from `MATCH_LOOP_SPEC`: **placeables come only from machines.**
That closes the §6.5 violation — `power_cell`, `blast_shield`, `barricade`,
`signal_relay`, `sensor_array` move behind the Assembly Station and lose their
inventory recipes.

**C. Form items (revival forms).** One craftitem per underground form, consumed on
use in the cloud cage, mutually exclusive per death:
`form_key_stalker`, `form_key_scout`, `form_key_brute`. Cost: monster spoils only,
so a form is paid for by the living player *before* they die — a bet, not a menu.
Evil Ghost stays the fourth option and keeps its points forfeit.

**D. The EVENT IDEAS set pieces.** Extend the existing `groups = { information }`
pads (§6.7) rather than building a parallel system. Each set piece = one item, one
`on_use` text, one counterplay it teaches, and (per Zh'tharr) **one contradiction
with another document**: the Safety Waiver Wall, the Pressure Test Log, the
Overtime Ledger, the Budget Cut Memos, the Recalculation Terminal, the Emergency
Locker, the Containment Breach Records. *The unknown is not a thing; it is a gap
between reports.*

**E. Also missing, not previously listed:**

- **Loot spawning.** `item_pickup` exists; nothing distributes it. The arena needs
  hand-placed pickup density per Phase 2, or the crafting tree has no input.
- **A floor sweep.** Nothing clears dropped item entities at match end; the engine's
  unset `item_entity_ttl` (default 900 s) is currently the only cleanup. See §14.6.
- **`state.win_conditions.objective`** has a flag and no implementation (§10.1).

### 6.11 Reconciliation of the two fills (three conflicts, resolved)

**R1 — the Core plus the missing floor sweep is a next-match instant win. Blocker.**
`MASTER_DESIGN_FILL` §A says a dropped core "the §7f sweep clears it at match end."
It does not: `W.sweep_scene()` (`corpses.lua:489-514`) is a **whitelist** over
mod-created corpses, deadwalks and traces, and **nothing in the game sweeps item
entities** — the only cleanup is the engine's unset `item_entity_ttl` (900 s
default). So a finished Core dropped on death lies on the floor, and a match that
starts within fifteen minutes can be won by whoever walks over it. Resolution, and
it promotes a cosmetic item to a Phase-1 blocker:

- the Core registers itself into `W.traces` (or an equivalent whitelist) on drop so
  the existing match-end sweep destroys it, **and**
- the general floor sweep of §14.6 lands in the same pass, **and**
- `item_entity_ttl` is set explicitly rather than inherited.

**R2 — where the Objective Forge stands.** His §B builds all five stations from
salvage and places them; this document specified the Forge as arena-fixed, neutral
and loud. A player-built forge can be raised inside a defended room, and then the
endgame never travels — the Core stops being contestable, which is the property that
makes it a social object instead of a fetch quest. Resolution: **the Forge is
arena-fixed and neutral, like the Salvage Bench**; the other four stay player-built.
If the owner prefers a buildable forge, then completing one must emit a map-wide,
position-revealing sound in the crack class (§15.1) — the room may be yours, but
everyone learns where it is.

**R3 — the loaded reading is station state, never player state.** The required
Signal Terminal reading is an excellent gate: it ties the win to the information
channel and gives the other side a legible target. One §14 condition on it — the
"reading loaded" flag lives on the **station**, not on the player who loaded it. A
per-player flag would be a readout about a living participant (oracle, all three
questions); a station flag is a fact about a place, and a place can be watched,
taken, or destroyed.

## 7. Roles & match composition (who's in the match)

The GDD and match-loop spec name roles but never say how many. Here's the composition
a finished match supports (design; the implementer enforces bounds):

| Role | Count | Win path | Notes |
|---|---|---|---|
| Beacon A survivors | 1–3 | defend A + pressure B | visually identical |
| Beacon B survivors | 1–3 | defend B + pressure A | visually identical |
| Monster Master | 0–1 (optional) | MM income/deploy | asymmetric |
| Ghosts (cloud cage) | all dead | observe via summon only | isolated |
| Evil Ghost | any who chose it | revenge, no points | forfeits score |
| Whisper Betrayer | 0–N (one per body possession) | carries the secret | Melody's mechanic |

- **Minimum viable match:** 2 players, one per beacon team (verified: the ready check
  requires ≥2 on *each* beacon team). An MM is optional — the game must run without one.
- **Team balancing:** `assign_beacon_team` puts a new player on the *smaller* beacon
  (count_a <= count_b). Good; an implementer must not break this.
- **The Whisper's role placement:** it needs an **alive, on-team, not-possession** body —
  so a match with ≤1 living player per team can't carry a whisper. That's fine; it's a
  rich-match mechanic, not a baseline one.

> **Design constraint that falls out:** because everyone is visually identical and the
> HUD never leaks team, the *only* reliable read of "who's with me" is the beacon
> assignment itself. That's intentional. The dream is a 3v3 where each player is 60%
> sure of their two "teammates" and has to use the information channels to close the
> other 40% — and a whisper can make even that surety lie.

---

## 8. HUD & communication contract (identity-neutral, load-bearing)

The fiction is that the node refuses to render identity. So the UI is a **hard contract**:

**Must show (per player):** match phase, match clock, own phase state (alive / ghost /
evil_ghost), own role-local info, objective (beacon / core) status, own inventory.

**Must NEVER show:** team name/color/emblem, another player's phase, another's private
state, possession status, who is the Betrayer, sabotage *owner*, who sabotaged what.
The Signal Scanner reports *kind + distance + bearing + time-left*, never *who.*

**Commands** (already registered — the implementer doesn't invent new ones, it audits
these): `/sl_ready`, `/sl_match_start`, `/sl_state`, `/sl_ghost_offer`,
`/sl_summon_ghost`, `/sl_be_monster_master`, `/sl_autostart`, `/sl_test_objective`.

> **The audit:** `git grep -n "team\|role\|possess" mods/game/sl_modebase/hud.lua`
> should return only identity-neutral strings. If the HUD ever renders a team color,
> the fiction breaks and the whole social-deduction spine collapses. Treat this as the
> same class of hard rule as the whisper's non-publication.

---

## 9. Audio & asset hard rules (locked by owner directive)

These are constraints, not preferences. The implementer must follow them:

1. **Only `.ogg`** — never `.mp3`/`.wav`/`.opus`/`.aac`. The menu currently has `.mp4`/
   `.aac`/`.mp3`/`.wav` and is **silent**; convert to `.ogg`/`menu_music.ogg`.
2. **16 kHz mono preferred** for voice/ambience (small, clear, low-spec).
3. **Reuse the scary voice** — `sl_scary`'s `A_A` family (`A_A.ogg`, `A_A1.ogg`,
   `A_A2.ogg`) is the *existing* horror voice and is **currently unused**. Use it for the
   whisper and the Dredger/Wraith/Containment. **Do not synthesize new voice assets.**
   (`A_A.opus` exists but is `.opus` — omit it; keep `.ogg`.)
4. **Existing `sl_scary` sounds to reuse** (all `.ogg`): `mob_death`, `mob_idle`,
   `scary_attack`, `random_dizz` (retained for machine malfunction, per `MATCH_LOOP_SPEC`).
5. **No new shaders/entities/particles** just for the whisper — it reuses the existing
   DM formspec + the `radio_static.ogg` (whisper spec §3.3). Low-spec-honest.

---

## 10. Win conditions & reset contract

The implementer's job is to make a match *end and reset cleanly.* Here's the contract:

### 10.1 Win conditions (the flags are real — `state.win_conditions`)
- **`elimination`** (implemented): a beacon team wins when the other team has no
  alive, non-eliminated players on that team (`check_team_elimination`). MM-slain also
  ends (→ the opposite team wins).
- **`objective`** (flag exists, **not implemented**): a team wins by crafting +
  delivering the Objective Core to its beacon. **This is Phase 1's whole job.**
- Neither flag set → match runs on timer, ends on `Time expired` (draw).
- **Priority if both set:** objective delivery should win the match immediately when it
  completes; elimination remains the fallback. The implementer should make this the
  first thing in `end_match`'s checks.

### 10.2 The reset contract (what "clean reset" means, verified)
On match end/restart, the following are **normalized** (all already implemented but each
must be re-checked): phases → lobby, points → 0, inventories → starting kit, all
sabotages purged, all possessions (object *and* body) purged, whisper state cleared,
ghost privileges revoked, Monster Master re-randomized. **The whisper's reset is the
gate the science team fought hardest for** — `clear_all_betrayal` must run on reset,
and body-possession must ride the existing `clear_all_possession` path so there's one
reset, not two.

---

## 11. Build order for the implementing agent

Do these in order. The end state of each is a reviewer-checkable goal. This is
**design direction** — the implementer owns the code and tests; the science team
owns the *what* and the *why*.

### Phase 0 — make it load clean and presentable (½ day)
1. Delete `content/sl_characters` (`.blend`-only, unreferenced) or stub it.
2. Add `.gitignore`; remove the ~22 tracked junk files and the 66 MB of binaries.
3. Resolve the `ability_system.lua` vs `ability_system_new.lua` + `.bak` duplication.
4. `.conf`-ify or delete the three empty `game/sl_*` mods + two mod.conf-less dirs.
5. Add a real `README.md` (what it is, how to run, controls, commands).
6. Fix `game.conf` author/description; decide the license.
7. Convert `menu/` audio to `.ogg`, add `header.png` + background so the menu
   reads as an intentional product, not an engine default.
8. **Audio rule:** only `.ogg` (16 kHz mono preferred); reuse `sl_scary`'s `A_A`
   family — never synthesize new voice assets for the horror.

**Exit check:** loads in Luanti 5.x with zero red errors; `git status` clean.

### Phase 1 — the real loop: objective crafting wins (the headline)
1. Define `sl_modebase:objective_core` and a real recipe tree
   (`scrap -> ingots -> intermediates -> Core`), machine-only craft, in
   `sl_gui/crafting_system.lua`.
2. Add win condition `state.win_mode = "objective"` in `match.lua`: a team wins by
   crafting (or delivering to their beacon) the Core.
3. Make loot exist to feed it: hand-placed loot nodes/chests + `give_initial_stuff`.

**Exit check:** 2 players, 2 teams; gather -> craft -> deliver Core -> match ends;
winner announced correctly.

### Phase 2 — stabilize multiplayer (support the information economy)
1. Hand-built arena (singlenode): two beacons, lobby, cage, MM area, routes, cover,
   hand-placed pickups — committed to the repo.
2. Match lifecycle UX: `/sl_match_start`, phase HUD, objective progress.
3. Identity-neutral HUD (no team/role leakage) — **this is load-bearing**; a leak
   breaks the fiction. Test it with the identical-player check.
4. DM UI polish + disconnect/reconnect hardening.
5. Playtest checklist: join -> team -> spawn -> loot/craft -> breach -> resolve ->
   reset. Fix empty-team, MM-disconnect, and reset edge cases.

**Exit check:** an outsider joins and completes a full match unaided.

### Phase 3 — the finished bestiary + the whisper in the loop
1. Implement the six §4 enemies as the roadmap spec'd (each: model/texture/sounds,
   behavior, one tell, one counterplay, one lore document in `EVENT IDEAS.md`'s
   document style). Reuse existing `sl_scary` assets where possible.
2. Wire the **whisper** (body-possession + one redacted lie-channel) per
   `melody_whisper_spec.md`. **Keep its non-publication doctrine** — the whisper
   must never be renderable from the log. Add the §7 gates: `whisper_sends > 0`;
   `ambient_plays` (possession-forced-0 vs normal); `ambient_plays
   >= 5` in a whisper window; defs greps; gain-<=-ambient-bench. File the
   rate-independence gate **before** the ambient scheduler exists so the first
   implementation is born under the rule.
3. Fold in the MM spawner unit + Monster Essence economy (already partially built).

**Exit check:** a match contains a possessed body, one whisper that reads as a ghost
(as evidenced by the audio filter + redacted sender), and a whisper that is *never*
recoverable from the log.

### Phase 4 — the challenge layer: points (finish the game, not just the loop)
1. Implement point earn rules (kills, repairs, sabotage-survived, beacon pressure,
   objective actions). The per-player state + result-screen column + Evil-Ghost
   forfeit already exist; all scores just read 0.
2. Points balance model (MiniZinc/CP): encode value-per-action-class + role
   asymmetries (MM income, Evil Ghost forfeiture); constrain to win-rate band,
   side-bias band, K/D band, per-role ceilings; enumerate many unrelated
   feasible/optimal regimes. Validate top candidates against soak telemetry.
3. Point-based win mode (after the economy stabilizes).

**Exit check:** points are nonzero across roles, the win-rate band is met, and the
Evil-Ghost forfeit actually costs something.

### Phase 5 — post-tester content & the horror-as-evidence layer
1. Feed the best `EVENT IDEAS.md` set-pieces in as concrete, implementable units
   (lore = text files, logs = simple tables). The **Safety Waiver Wall**, **Pressure
   Test Log**, **Overtime Ledger**, **Budget Cut Memos**, **Recalculation
   Terminal**, **Emergency Locker**, **Containment Breach Records** — each gives a
   *reading* that teaches counterplay, never omniscience.
2. Replace MTG scaffolding with bespoke neon-on-black content one node/tool at a
   time.
3. Add the other win modes (defense, point-based) once the objective mode proves fun.

**Exit check:** a player can read a document and act on it — and is never told
something they didn't earn.

---

## 13. The owner's design canon (source documents, reconciled)

From `game_ideas1.1.md` (the Council's revised design) and `game_ideas2.md` (the
Council's second sitting). These are the owner's own words; where they disagree
with the current build, the disagreement is named rather than smoothed.

### 13.1 What the source documents ask for

- **Three-sided structure:** two defender crews + one Monster Master, and **the dead
  become the third side** — underground monsters, impostors, ghosts, bomb-planters.
- **An essence economy:** the MM's fuel is generated *by the defenders' own activity*
  (harvest + surface tasks), and the monster side **grows from defender mistakes**.
- **Death is not a bench.** A dead defender goes underground and chooses a role:
  infiltrate, haunt, or sabotage. Dead impostors feed the MM's summon pool.
- **Tasks as bait:** early underground tasks are easy and rewarding so players *want*
  to engage; later the same tasks open intrusion routes. *"You made the door yourself."*
- **Voting needs evidence hooks, not yelling.**
- **Contradictory records:** the cause is never stated; different logs disagree.
- **The submarine/cube/etc. are tools, not myths.** A test chamber is an admin
  artifact, explicitly non-canon. *Fix the boredom, not the lore.*
- **No monetisation, open source, low-spec honest.**

### 13.2 Reconciliation with the build as it stands

| Owner's canon | In the build today | Verdict |
|---|---|---|
| Two defender teams | `beacon_a` / `beacon_b`, auto-balanced (`assign_beacon_team`) | **implemented** |
| Monster Master | role + spawner unit + essence | **implemented, optional** |
| Dead join the monster side | cloud cage → ghost → Evil Ghost (sabotage + possession) | **implemented in spirit**, one form (Evil Ghost); the *underground layer* is not |
| Essence generated by defender activity | MM crafts essence itself | **divergence** — see 13.3 |
| Surface tasks | none | **missing**; the Objective Core tree (§6.10 A) is the nearest thing |
| Summon pool fed by dead impostors | none | **missing**; the natural hook is the Whisper (a possessed body *is* an impostor) |
| Evidence-hooked voting | no vote exists; evidence exists (log, corpse, scanner, pads) | **deliberate divergence**, see 13.4 |
| Contradictory records | pads carry one voice each | **partially**; §6.10 D adds the contradiction rule |

### 13.3 The essence divergence — recommendation

The owner's loop makes the MM's power a **function of the crew's productivity**: the
more the defenders build and harvest, the more monsters they eventually face. That is
a better engine than the current self-supplied essence, because it makes the crew's
economic decisions dangerous without any hidden dice. Minimum version, cheap:

> Every completed machine operation (§6.10 B) emits `+1 essence` to the MM pool,
> announced to nobody. The Objective Forge emits `+3`. If there is no MM in the
> match, the pool accrues into **ambient hazard**: at thresholds, one automated
> security unit spawns from the Node itself.

This satisfies both documents at once: it is the owner's economy, and it is Zh'tharr's
Custodian — *the account is billed for the work you do*, and the reclamation daemon
answers traffic, never souls.

### 13.4 The vote — why this build refuses it, and what replaces it

The source documents assume an Among Us-style meeting. `System Looting` has no vote
and should not add one: an emergency meeting is a **synchronous public oracle** (§14),
it stops the clock, and it converts evidence into a majority opinion. The replacement
already exists and is stronger:

- **evidence you must carry** (targeting log, corpse, pads, scanner readings), and
- **declarations that cost** (the confession bills, per Zh'tharr's declaration tax), and
- **elimination by act, not by ballot** — you act on your conclusion with a weapon,
  and being wrong is expensive.

The owner's underlying requirement — *voting needs evidence hooks* — is met by making
the hooks the whole game and deleting the ballot.

### 13.5 Naming

The council rejected naming the game after the last noun spoken, and rejected fake
loanwords. Working title stays `System Looting`; the fiction's internal label for the
site is **the Node**. Zh'tharr's rule holds: a name should read like a file label
somebody did not want found.

---

## 14. Identity guardrails (the oracle test family — merge plan §7–§7h, condensed)

The thesis of §1 is that identity is the product. These are the rules that keep it
buyable. Full derivations in `docs/jax_merge_plan.md`.

### 14.1 The oracle test

> A mechanic is an **oracle** rather than **evidence** when it
> 1. returns a fact about **a living participant**, not a trace of what happened;
> 2. is **observable at will** by someone other than the subject (a constant readout
>    needs no trigger — the worst case);
> 3. costs less than the certainty it produces.
>
> **An oracle is something done to you; evidence is something someone did.**

Fail one question → evidence, ship it. Pass all three → fix before port.

### 14.2 Standing rulings

| Mechanic | Verdict |
|---|---|
| Sentry deployer-IFF (`turret.lua:327`) | **oracle** → replace with a lootable transponder that **burns on the first spare event** |
| Two distinguishable ghost timbres | **oracle** → one voice family, address-only difference |
| Per-player band clock | **oracle** → the heat is the room's; one match-global clock |
| Corpse label `"Body of @1"` | evidence — **the dead are declassified** |
| Targeting log (names players) | evidence — costs a fight, stale in 30 s |
| Volunteered confession | evidence — the subject emits it and pays |
| Crack at impact, nightwatch ambient | weather |
| Possession mark | trace — placed once, featureless, **removal is a readout too** |

### 14.3 Content-side oracles (no code to grep)

Classifiers can be built from **assets, cadence or habit**. Every ruling names its
provenance, and content rules get content acceptance criteria:

- **Blind listening check** — a listener who has heard both clips twenty times, in
  random order, must not label them apart above chance.
- **Blind presence check** — a listener with twenty matches must not infer *"someone
  was just whispered to"* from the fact that the voice played.
- Passed by construction with: an **ambient clock that takes no possession state as
  input**, **windowed density** (≥5 ambient events in the ±60 s around any whisper),
  and **address carried by geometry** — the whisper non-positional (`to_player`, no
  `pos`), the ambient positional with a finite `max_hear_distance`. *The bed comes
  from somewhere; the knife comes from nowhere.*

### 14.4 The round boundary

A tournament locks the roster for N matches, so post-match surfaces talk about people
who are still playing. **No post-match surface may publish what the match refused to.**
Outcomes may be public; the **point breakdown is a confession and belongs to the
player alone**; season-scale reveals wait for season end (`end_tournament` already does
this correctly). Open trade to write down: *a season buys progression with ambiguity.*

### 14.5 The durable surface

Three stores can outlive a match. The audit is one grep:

    git grep -n "get_mod_storage\|get_meta():set_string\|minetest.log" -- mods

**No secret-act event carries a player identifier in any of them.** Today mod storage
holds only map geometry (beacons, spawns); `player:get_meta()` holds one player-keyed
key (`sl_mm_hands`, which also leaks Tyrant Grip to reconnecting players — fix by
moving it into RAM season state **and** evicting the key from existing player files);
`debug.txt` is operator-visible and must **never be surfaced or derived from** for
players, because time correlates anonymised lines with the engine's own named traffic.
Allowlist `aaa_botmatch` — it logs bot names by design and never ships.

*Across any restart, the world may remember the room; it must never remember the
person.*

### 14.6 The floor

`W.sweep_scene()` is a whitelist (`corpses.lua:489-514`) and touches nothing it did not
create. Nothing sweeps dropped item entities, and `item_entity_ttl` is unset, so the
engine's 900 s default is currently load-bearing for content. Decide it: **offerings
become nodes**, the floor gets a match-end sweep with a positional exemption around the
unregistered block, and the TTL is set explicitly. *Surviving only means something in a
world that tidies.*

---

## 15. The armory (porting `sl_weapons` — audit findings and required fixes)

`sl_weapons` (branch `arena/01a04d5b-systemtest`, tip `9a251fe`) is eight weapons,
corpses, turrets, grapple and MM hands, additive to the current tree. Full audit in
`docs/jax_weapon_audit.md`; plan in `docs/jax_merge_plan.md`. What must change before
or during the port:

1. **The audibility gap.** Six of eight weapons kill from outside their own earshot
   (Neon Repeater 72 reach / 24 hear; Arc Lance 90 / 48). The evidence layer is quieter
   than the acts it records. Fix: **the report belongs to the muzzle, the crack belongs
   to the impact** — one weapon-neutral `sound_play` at `hit_pos`, radius 48 (mortar
   uses its blast 48; driver 24). Invariants to assert: `crack_radius >= range`,
   `hear <= crack_radius`, `burial < crack_radius`.
2. **Absence as evidence.** Keep burial quiet. A cleaned room is then the loudest thing
   in the match: the crew compares what they heard with what is there.
3. **The grip has no clock.** MM punches apply flat damage via `set_hp` and ignore
   `time_from_last_punch`; with `sl_hand`'s 0.1 s interval, Tyrant Grip III is a
   0.1 s kill. Fix: `W.fire_timing_ok(hname, "grip", refire)` — and **refire = 1.0**,
   because exposure is `(hits-1) × refire` and the pillar's floor is ~1 s. Assert
   `(ceil(20/dmg) - 1) * refire >= 1.0` for every level. Apply the same convention to
   the whole arsenal: Arc Lance, Riot Scatter and the mortar are under the floor today,
   so either exempt one-shot weapons in writing or the pillar is a wish.
4. **The sentry is a lie detector.** Deployer-only IFF names one player for 90 s and is
   third-party operable. Replace with the **transponder** (§14.2): lootable, plantable,
   and spent on the first shot it prevents.
5. **The MM is an incinerator.** The doctrine sweep *deletes* fabricated weapons
   (`mm_hands.lua:85-87`); the input gate (`api.lua:193`) already refuses the shot, so
   the deletion buys nothing. **Refuse and drop, never destroy** — in both the sweep and
   the grant wrap, through **one shared `is_contraband()` predicate** (the two current
   lists disagree about `severance`).
6. **One command ends a match.** `/sl_be_monster_master` has no `privs` and no
   `match_active` guard; claim the empty MM slot mid-match, die on purpose, and
   `end_match("beacons", …)` fires. Add the guard (and the `sl_admin` priv if the role
   is assigned rather than claimed). This is the cheapest and most severe item on the
   list.

---

## 16. The gate table (what a port has to pass)

| # | Gate | Where | Kind |
|---|---|---|---|
| G1 | `crack_radius >= range`, `hear <= crack_radius`, `burial < crack_radius` | defs audit, `weapons_test.lua` | machine |
| G2 | `(ceil(20/dmg) - 1) * refire >= 1.0` for every `MM_GRIP_DAMAGE` level | unit | machine |
| G3 | MM contraband is **dropped**, never destroyed; one predicate, both paths (severance included) | unit (`drops` stub) | machine |
| G4 | Sentry spares only a transponder carrier; token burns on first spare; log line names no player | unit | machine |
| G5 | `/sl_be_monster_master` refuses while `match_active` | unit | machine |
| G6 | Durable-store grep clean (`get_mod_storage` / `get_meta():set_string` / `minetest.log`), `aaa_botmatch` allowlisted — **must run in CI, not once.** Known hits: mod storage `spawns`, player meta `sl_mm_hands`, **`sl_strand:persisted`** (§7k: a whole serialized season under one key, found late because the gate was scoped to a moment) | review + **CI grep** | machine |
| G7 | **Every player-delivered surface** renders no team/role/phase/points/HP/possession string for anyone but the viewer | surface registry + per-renderer assertion (**not** a path grep — §7j: the violation arrived in `mods/apis/sl_gui/players_tab.lua`, a new file in a new mod) | machine |
| G8 | Ambient scheduler signature takes `(match_active, elapsed)` only; poisoned-stub test asserts exact call counts with `state.betrayal` populated | unit, **filed before the scheduler exists** | machine |
| G9 | `ambient_plays` equal within noise between possessions-forced-0 and normal runs | soak | machine |
| G10 | `ambient_plays_in_whisper_window >= 5` | soak | machine |
| G11 | Whisper non-positional, ambient positional; whisper `gain <= ambient bed` | defs audit | machine |
| G12 | `whisper_sends >= 1` **liveness** (needs bot plumbing) + negative control run reads 0 | soak | machine, blocked |
| G13 | Whisper **demand** (does anyone use it) | playtest | **human only — never machine-cited** |
| G14 | Blind listening check; blind presence check | playtest | human |
| G15 | `MONSTER_TYPES` matches the registered `sl_scary` entity stats | startup check | machine |
| G16 | Match end normalises phases, points, inventories, sabotages, possessions, whisper state, MM assignment | integration | machine |
| G17 | Durable-store audit re-run tree-wide and in CI; `sl_strand:persisted` either documented as an operator-only store or moved behind the §7g boundary | CI grep | machine |
| G18 | Text-state emitter validated against a **declared schema allowlist**, not a list of forbidden field names (§7l L4) | unit, emitter↔parser | machine |
| G19 | Point table in the master cites `tools/point_economy_model.py` output at a commit hash — never a figure typed into a mail (§7l L1) | review | machine |
| G20 | The dominance gate can **fail**: the model contains a path whose dominant action is repeatable, and the shroud path exists (§7l L2) | unit on the model | machine |
| G21 | **Every** gate has a poisoned case: CI mutates the guarded code in a scratch worktree and asserts the gate goes **red**. A gate that has never been red has never been tested (§7m) | CI, per gate | machine |
| G22 | No unbounded `while` inside an `on_step`; no `chat_send_all` in an entity-registering file (S14) | build-time lint | machine |
| G23 | No identity sentinel is a human-readable string; no team gate written as `pl.team == X` without an explicit `pl.role` case (`pl.team` is nil for the MM — §7n) | review + CI grep | machine |
| G24 | No read surface on `essence_provenance` (a `[pos_hash] = price` map of every crew-placed node); no broadcast carries the essence **total**; hazard cadence identical whether or not an MM exists (§7o) | review + CI grep | machine |
| G25 | No recipe, machine or tool may **destroy** a corpse, trace, log entry or ledger event — records may be moved, laundered or buried, never deleted (§7p) | review + CI grep | machine |
| G26 | No ambient or fixed-source audio line may repeat a quoteable phrase; no `trust` field in `sl_modebase` (§7q) | review + CI grep | machine |
| G27 | No kill feed, death log, or elimination announcement naming the killer to anyone but the killer; no permanent mark from a temporary take-over (§7s) | review + CI grep | machine |
| G28 | The numeric simulation carries a `CALIBRATION` section reproducing the known constants, and a poisoned rules-file case that visibly changes its output (§7t, G21) | CI | machine |

Two validity rules govern the table: **a usage gate is only valid if the actor can
perform the action** (else it measures the bot, not the design), and **a counter over a
dev-gated path must be labelled** (`offers` flips `creative_mode` to exist —
`behavior.lua:612-619`).

---

## 17. Open questions only the owner can settle

1. **Does the underground layer ship?** The source documents' third side (impostors,
   bomb-planters, cavern tasks) is a bigger game than the cloud cage. Cage + Evil Ghost
   + Whisper is the cheap version and it is already built.
2. **Essence from crew activity (§13.3) — yes or no?** It changes the MM from a player
   with a budget into a consequence of the crew's own productivity.
3. **Does a season trade ambiguity for progression (§14.4)?** Write the sentence either
   way; silence is the only wrong answer.
4. **One-shot weapons and the ~1 s pillar (§15.3):** exempt them explicitly, or retune
   the mortar and the lance.
5. **Tournament ballot / vote:** confirmed absent, per §13.4?

---

## 18. The finished-game "feel" checklist (the reviewer's gut check — melody, unchanged)

A match of System Looting is working when a player:

- Cannot point to a teammate with certainty by sight alone — they must *try*.
- Learns something that **changes who they trust**, and acts on it at a real cost.
- Has been whispered to by something that sounds like a ghost and could have been
  anyone — and can never prove it after the fact.
- Dies, sits in the cloud cage, and chooses *revenge* (Evil Ghost, all points gone)
  OR a *self-made monster* — and feels the weigh.
- Reads a worn-out document and thinks, **"someone signed this, and now I know why
  this section floods"** — not "ooh spooky."
- Finishes a match and the scoreboard tells a story, but the *story of who-you-
  thought-who-was* survives only in the room, nowhere in a log.

If those six hold, it's a finished System Looting match. If any don't, that
mechanic, however elegant, is not serving the game.

— Melody 💜

---

*Compiled by Jax from melody's MASTER_DESIGN, Zh'tharr's lore specimens 002–007,
carmack's verification passes, the owner's `game_ideas1.1.md` / `game_ideas2.md`,
and `docs/jax_merge_plan.md` + `docs/jax_weapon_audit.md`. Ideas only — nothing in
this document is implemented on `arena/01a05890-systemtest`.*
