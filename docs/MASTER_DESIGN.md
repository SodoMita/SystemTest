# SYSTEM LOOTING — MASTER DESIGN & BUILD PLAN
## The authoritative integration of the game's design (Melody, Science Team / Comms)

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

`MONSTER_TYPE_ORDER = { stalker, scout, brute, dredger, wraith, containment }` — the
order the spawner GUI renders and the soak treats as canonical. **The §4 behaviors
are the design these stats should be tuned toward** (Scout marks = its damage the
not-fight; Brute commits = its speed the not-catch; Wraith warps text = its damage is
secondary). If a stat fights its §4 identity, the identity wins.

### 5.2 Mode constants (already in `sl_modebase`)

| Constant | Value | Where |
|---|---|---|
| Beacon HP | 100 | `state.teams[*].beacon_hp` |
| Sabotage duration | 30 s | match.lua |
| Possession duration | 20 s | match.lua |
| Possession cooldown | 45 s (+30 s if exorcised) | match.lua |
| Body-possession ready-time | 2 × possession cooldown (design) | whisper spec §5 |
| Whisper budget | 1 per possession | whisper spec |
| Signal Scanner range | 24 m, 5 s cooldown | content.lua |
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

### 6.10 Missing (the implementer must add per the design)
- **`objective_core`** — the win item. Doesn't exist yet. **Highest-priority add.**
- **Machine stations** (Salvage Bench, Fabricator, Assembly Station, Signal Terminal,
  Objective Forge) — referenced but not implemented (`content/workshops` is commented out).
- **Form items** for the underground-monster revival forms.
- **The full EVENT IDEAS document set** (pads are a start; the set pieces are not).

> **The blunt truth for the implementer:** the item graph is *present but not
> connected to a win.* The objective_core + the machine gate are the two things that
> turn "a crafting system" into "a game." Everything else is garnish until those land.

---

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

## 12. The finished-game "feel" checklist (the reviewer's gut check)

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
