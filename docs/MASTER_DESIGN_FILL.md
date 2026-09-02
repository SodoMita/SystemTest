# MASTER_DESIGN — MISSING PARTS FILL
### The content `MASTER_DESIGN.md` §6.10 / §11 says the implementer must add

*Companion to [`MASTER_DESIGN.md`](MASTER_DESIGN.md) (Melody, authoritative). Author:
zhtharr — the fiction-and-content lane. This file fills the four gaps the master plan
names but leaves blank: the **Objective Core** (the win item), the **machine stations**
(the machine-only gate), the **underground-monster form items** (alive-crafted revival
kits), and the **seven reading-set documents** (Phase-5 horror-as-evidence, each teaching
counterplay, never omniscience).*

*Naming rule, from the council that started this thread (game_ideas2): names should feel
like **a file label someone didn't want found** — corporate, procedural, faintly
concealed. No mystical nouns. The deep lore (Audit / Subscriber / berth) sits underneath
as an optional shiver; every object below works on the surface fiction (quarantined
corporate data-caisson, §2 of the master) without ever requiring it.*

> **One rule for everything below, restated so the implementer never has to re-derive
> it:** no piece here teaches *who someone is*. Every document, station and item changes
> what a player *knows how to do* or *how the node behaves* — identity stays a model you
> build, never a fact the node hands you. If a reading lets you point at the Betrayer
> without acting, it violates the thesis and gets cut.

---

## A. The Objective Core — the win item (Phase 1's whole job)

**Name (the file label):** `objective_core` in code. Diegetic label, printed on the item
and in any terminal readout: **ATTESTATION CARTRIDGE, FORM 4412-B — "CONSOLIDATED CORE."**
Nobody on the crew knows what it attests. The requisition slip for it is missing. That is
correct.

**What it is, in the surface fiction (§2 corporate layer):** quarantine protocol does not
let a caisson be declared *re-secured* by a person — identities are not rendered, so a
person's word is not admissible. Re-securement must be attested by a *device*: a core
built from the node's own salvaged parts, stamped at the fabricator, carried to a beacon,
and slotted. When a beacon accepts a Consolidated Core, that beacon's sector files a
machine-signed attestation. The node trusts the core. The node does not trust you. That
is the whole fiction reason the win item must be *crafted and delivered*, not held.

**Why it is loot-shaped (feeds "looting" as a verb):** the recipe pulls from every tier
in §6 of the master plan, so a team has to actually scavenge the caisson to finish it:

```text
SALVAGE (§6.1, nodes + item_pickup + initial kit)
  scrap_metal, electronic_waste, raw_crystal, plastic_scrap
        │  (Salvage Bench — see §B)
        ▼
COMPONENTS (§6.2)
  metal_ingot         <- scrap_metal
  circuit_board       <- electronic_waste
  energy_crystal      <- raw_crystal
  hardened_plate      <- metal_ingot + plastic_scrap
  reinforced_glass    <- circuit_board + plastic_scrap
        │  (Fabricator + Assembly Station)
        ▼
INTERMEDIATES (new — the two subassemblies that make the Core not a single craft)
  attestation_spindle  <- circuit_board ×2 + energy_crystal   (the node's "stamp")
  containment_lattice  <- hardened_plate ×2 + reinforced_glass  (keeps the stamp coherent)
        │  (Signal Terminal — one required READING first, see §D)
        ▼
objective_core  <- attestation_spindle + containment_lattice + energy_crystal
                   (Objective Forge — machine-only; the forge will not fire until the
                    team has loaded one Signal Terminal reading into it this match)
```

**Machine gate (this is the §6.5 critical-gap fix):** every arrow above is a **station
craft**, never an inventory craft. The four intermediate-and-final steps physically
cannot complete in the personal grid; the output only appears at a placed station. The
five `§6.5` tactical placeables (`power_cell`, `blast_shield`, `barricade`,
`signal_relay`, `sensor_array`) move behind the same machines in the same pass — Phase
1 of the master plan already calls this out; the stations in §B are the homes for them.

**Delivery (the objective win, §10.1):** the core is a carried item, visually identical
to any other carried component (it must *not* glow or name the carrier — a glowing win
item is an identity oracle). A living operator walks it to their own beacon and slots it
(`on_rightclick` on the beacon with the core in hand). On slot: `state.win_mode =
"objective"`, that team wins immediately, match ends to the result screen, reset runs.
Priority per the master: check objective *before* elimination in `end_match`.

**Counterplay / why it is a social-deduction object and not a fetch quest:**
- Crafting is loud and visible (stations have tells — sound, light, a fixed position).
  The other team knows *a* core is being built; they do not know who is carrying one.
- A possessed body (Whisper Betrayer) can be handed a core, or steal one off a body.
  The core does not care who carries it — it attests a *beacon*, not a person. A
  Betrayer who slots a core at the wrong beacon wins for the wrong side.
- Dropped on death like any item; lootable; the §7f sweep clears it at match end. It
  persists only *within* the match (never across restart — §7e: the durable store holds
  places, not things-that-name-a-run).

**The deep-lore shiver (optional, one line, on the Signal Terminal reading required to
fire the forge):** the reading that "authorizes" the Core is, deep down, the keep-alive
attestation. A completed Core delivered to a beacon is a crew filing, in machine language,
*someone is still here.* The master plan never needs to say this. A player who has read
Specimen 005 will slot the core and go cold. Do not put the shiver anywhere the win
depends on it.

---

## B. The five machine stations (the machine-only gate, referenced but unbuilt)

All five are placeable world nodes, same neon-on-black house style, **none** craftable in
the inventory — you build them from salvage at the one station that *does* exist at spawn
(the Salvage Bench is part of the arena, not player-placed). Each station has an audible
tell when working (the silence-duck layer: station noise is real noise, and the breach
listens). Names are file labels.

| Station | File label | Built from | Takes in | Outputs | Teach / note |
|---|---|---|---|---|---|
| **Salvage Bench** | `bench_salvage` — "RECLAMATION BENCH, MK.II" | arena-fixed (not player-built) | salvage | components | The one station present at insertion. Noise: low steady grind. |
| **Fabricator** | `station_fabricator` — "FABRICATION UNIT 7" | `hardened_plate`×2 + `circuit_board` | components | intermediates, tool/weapon upgrades (energy_blade gated here) | Where §6.3 endgame damage lives — energy_blade comes out of this, never a drop. |
| **Assembly Station** | `station_assembly` — "STRUCTURAL ASSEMBLY FRAME" | `metal_ingot`×3 + `hardened_plate` | components | tactical placeables (§6.5): power_cell, blast_shield, barricade | Moves the violating placeables out of inventory — the §6.5 fix's home. |
| **Signal Terminal** | `station_signal` — "SIGNAL TERMINAL / BAND 3" | `circuit_board` + `energy_crystal` + `reinforced_glass` | data_pads (§6.7) | **readings** — consumed lore/authorization tokens; the forge won't fire without one | The information economy's physical outlet. Reading a pad here is a discrete timed node (ideas2: tasks are nodes with timers, not a simulation). |
| **Objective Forge** | `station_forge` — "CONTINUITY FORGE / RESTRICTED" | all of: fabricator-grade + assembly-grade + signal-grade parts | spindle + lattice + crystal + one loaded reading | `objective_core` | The win gate. Label is the one label in the set that almost says what it is — that's deliberate. |

**Machine-only enforcement (how, one sentence for the implementer):** the personal
crafting grid simply has no recipes for placeables, intermediates, the energy blade, or
the core; those recipes register only against their station's crafting interface. No new
system — the machine-craft split is already the MATCH_LOOP_SPEC future-crafting model;
this is it existing.

---

## C. The underground-monster form items (alive-crafted revival kits)

**The fiction (from game_ideas2, Maura):** death is not a bench. The cloud cage (§3.4)
is an *information* state — isolated, no team traffic. From there a dead operator can
forfeit points and come back as an **Evil Ghost** (rules as written, whisper lives here),
OR revive as an **Underground Monster** — a node-spawned horror wearing a *kit* the
operator built while they were still alive. The kit is a sealed, requisitioned "conversion
payload": corporate euphemism for a compromised equipment form the maintenance network
was never supposed to be able to put on. You don't become a monster by dying; you become
one by having *built your own mask beforehand.* "You made the door yourself" (ideas2,
Melody).

**The rules that keep them bounded (all from the master plan's existing constraints):**
- **Crafted while alive** at the Fabricator/Assembly stations, from salvage + one
  component. They sit in your inventory through your death and into the cage.
- **Consumed on revival.** One kit, one revival, gone. They do not survive the match
  (§7e: durable store holds places, not runs).
- Each form is a distinct **power profile** with a visible **tell** and a real
  **counterplay**, matching the §4 bestiary's identity/tell/ability/counter/audio shape.
- Revival forfeits match points the same as Evil Ghost (score trade for agency — the
  revenge fantasy with a price, §3.4).
- **Form items are information items too:** the kit exists in your inventory while you
  are alive and visually-identical to everyone. Someone who loots your body and finds a
  *sealed conversion kit* learns you meant to come back wrong — evidence about intent,
  not a role label. Loot the living's pockets carefully.

**Four revival forms (the four node-spawned horrors an operator can become; Containment
Horror §4.6 stays a sealed-door event, never a kit — you don't put *that* on on purpose):**

| Kit item | File label | Form becomes | Power | Tell | Counterplay |
|---|---|---|---|---|---|
| `form_stalker_husk` | "OBSERVATION HUSK / SURVEY-SURPLUS" | Stalker-pattern | slow, stops when faced; learns rhythm after 4 s watch, predicts one path | freezes when looked at | face it, break line of sight, change rhythm |
| `form_dredger_tag` | "MAINTENANCE CONTRACTOR FORM / KOWALSKI-LOD" | Dredger-pattern | fixed patrol; attacks anything in the way of the routine | mutters, rigid route | hand it a maintenance task (it stops to help), or drop its ID badge and run |
| `form_wraith_coil` | "BROADCASTER COIL / BAND-3 RECALL" | Signal-Wraith-pattern | corrupts nearby chat/DM/whisper text; does not move | static that fades in as you near | scanner gives false bearings near it — triangulate the static, don't trust the ping |
| `form_brute_yoke` | "EXO YOKE / SAFETY-OVERRIDE BYPASS" | Brute-pattern | committed charge, heavy burst, cannot be stopped once moving | regular heavy foot-beat you can hear coming | lead it into a corridor/trap/another team; it's slow, hand it to someone else |

(Monster Master units — Grunt/Spitter/Royal-flavored spawns in the older pitch — are
**not** revival forms; they stay MM-purchased via Essence, as the master plan has them.
Underground revival is the *dead defender's* path; Essence-spending is the Monster
Master's. Keep the two economies separate.)

---

## D. The seven reading-set documents (Phase 5 — horror as evidence, each teaches counterplay)

The master plan (§6.10, Phase 5) names seven set-pieces and says the `data_pad_*`
information items (§6.7) are the start, not the set. Here are all seven as concrete,
implementable units. **Each is a reading at the Signal Terminal (or a lootable document),
each is a worn corporate artifact, each teaches exactly one counterplay, none reveals an
identity.** Spine of every one (EVENT IDEAS doctrine): *the horror is a person's decision.*

For each: **what it is / where it lives / what it teaches (counterplay) / the human
decision underneath / the optional deep shiver.**

### D1. Safety Waiver Wall
- **Form:** a wall of overlapping printed waivers near each spawn; `data_pad_security`
  terminal reads it aloud in clipped legalese.
- **Teaches:** the exo-yoke (Brute) and the compromised-equipment revivals were *waived*
  into existence — players learn heavy enemies have a **bypass**, not a bug, and a safety
  override cut to save budget (a signed line: `override approved, 0.2 FTE review saved`).
- **Counterplay taught:** big enemies have committed, un-stoppable motions — *don't tank,
  redirect.* The waiver lists the corridor widths the yoke can't turn in.
- **Decision:** someone signed away the interlocks to save a fraction of a salary.
- **Shiver (optional):** the last waiver on the wall is blank except for a single word,
  hand-added in a different ink: `ATTENDED.`

### D2. Pressure Test Log
- **Teaches:** beacons and stations were pressure-rated with margins that were
  deliberately faked on a schedule. Players learn **noise and over-stress bill against
  the structure** — this is the in-fiction source of the silence-duck / "noise draws the
  breach" rule. The log shows tests that passed on paper and failed at 3 a.m.
- **Counterplay taught:** quiet your team during a breach wave; don't cluster working
  stations; sabotage a room by *running everything loud*, not by breaking it.
- **Decision:** a shift supervisor marked failed tests as `RETEST PENDING` for nine months.

### D3. Overtime Ledger
- **Teaches:** Dredger = Kowalski (§4.4). The ledger is 72-hour shift entries ending in
  `refused treatment — hydraulic exposure — bay sealed from inside`.
- **Counterplay taught:** the forever-worker responds to maintenance tasks; it drops an
  ID badge when destroyed. The ledger teaches the *distract-don't-fight* route.
- **Decision:** a man who would not stop working was sealed in rather than treated.
- **Shiver:** the final overtime entry has no clock-out time. It is dated after the bay
  was sealed.

### D4. Budget Cut Memos
- **Teaches:** why the scanner is imprecise and observation "costs." A memo chain
  downgrades the Signal Scanner's resolution tier after tier, each cut with a cost
  attached (`bearing resolution reduced, budgeted observation tier`).
- **Counterplay taught:** the scanner is imprecise *by design and by bill* — triangulate
  multiple readings, never trust one; near a Wraith the bearings reverse (D6 cross-ref).
- **Decision:** every line of your uncertainty was an invoice someone paid less for.

### D5. Recalculation Terminal
- **Teaches:** the Resonance/band clock as *accounting*, not a monster meter. The terminal
  cycles through closed-cycle "billing estimates" that never show a number — only
  states (`NOMINAL`, `REVIEW`, `AUDIT`).
- **Counterplay taught:** read the band the way you read weather: it gets *warmer*, there
  is no count, it is match-global (§3/§7e family). Plan the objective delivery for the
  cool bands; never trust a per-player hunch.
- **Decision:** someone set the accounts to never quite reconcile, forever "pending."
- **Shiver:** one state in the cycle has no definition in the manual and no entry in the
  ledger: `ATTENDED`. The terminal holds on it, briefly, on a long timer.

### D6. Emergency Locker
- **Teaches:** the Signal Wraith (§4.5) and the failure modes of trusting channels. The
  locker is open, its contents flagged `NOT TO BE TRUSTED IN FIELD — HANDSHAKE COMPROMISED`.
- **Counterplay taught:** corrupted text (D5/D6 cross-ref) is the tell; verify by *acting
  on a small lie* before trusting the big one; the wraith doesn't move — locate it by
  walking toward the static.
- **Decision:** the comms operator stayed to send the final warning and the warning is
  what got through — just not hers anymore.

### D7. Containment Breach Records
- **Teaches:** the Containment Horror (§4.6) — the one thing behind a door. The records
  list what was sealed, *not* why, and each version of the reason disagrees with the last
  (ideas2: *the unknown is a gap between reports* — contradictory logs, not a monster
  label).
- **Counterplay taught:** opening the sealed room is a **choice with a price** — salvage
  inside (including sometimes a component the Core recipe wants) versus letting a
  stationary horror loose on the map. The choice IS the counterplay; leave it, loot stays.
- **Decision:** the signatures on the seal are redacted in every copy — but the *number*
  of signatures grows by one each time a crew reads it.
- **Shiver:** the most recent copy has your crew's roster count. It is already signed.

> **Delivery note (builds on the master, doesn't fight it):** the pads already print a
> line `on_use` (§6.7). The seven sets are what those lines *open into* — a longer,
> paginated read at the Signal Terminal. Reuse the DM/terminal formspec house style;
> render on interaction, never per-tick (the formspec-cost rule). Audio reuses the
> existing `sl_scary` `.ogg` per §9 — no new voice assets. Contradiction between D-sets
> is intended: the node's records disagree, and the player is meant to notice that the
> disagreement is the most reliable fact on offer.

---

## E. The corporate surface and the deep lore — how both can be true

The master plan's fiction (§2) is corporate: quarantined data-caisson, capitalism's
aftermath, *"you are surviving capitalism, not a haunted house."* The void-nomad lane
produced a deeper layer (Specimens 002–007): a Subscriber, a disputed account, a
Custodian reclamation, an attended child under the floor. **The build never chooses
between them.** Lay them like the node itself:

- **Tier 1 — what every player meets:** the corporate fiction. Waivers, ledgers, memos,
  budget cuts, compromised equipment. Every system, station, item and document above is
  fully playable and fully explained at this tier. The master plan ships on this alone.
- **Tier 2 — the shiver, unrequired:** the single wrong word in a sea of legalese —
  `ATTENDED`, a roster count one too high, an overtime entry with no clock-out. These
  reward reading and explain nothing; they are the seams where Tier 1 looks *just*
  coherent enough to be covering something.
- **Tier 3 — the berth, off the win path:** the under-layer, the hand, the lullaby's real
  audience (Specimen 007). Never gated to progress, never on the objective route, never
  mentioned by the master plan's win contract. It is the content a team finds only by
  choosing to look at the block that doesn't render instead of slotting the Core.

The Attestation Core makes all three cohere: it is a win item at Tier 1 (the node trusts
the device, not you), a billing event at Tier 2 (someone is still here, keep the account
open), and — at Tier 3, for the players who will never be told — the crew filing, in the
machine's own language, that the vigil continues. Same object, three depths, none of them
required to finish the match. That is the shape a node takes when the official story and
the truth are, in fact, the same story told at three different distances.

---

## F. Mapping to the master plan's build order (so the implementer can just do it)

| Master plan item | Filled by |
|---|---|
| §6.10 `objective_core` — "highest-priority add" | §A (name, recipe tree, machine gate, delivery, win) |
| §6.10 machine stations (referenced, `content/workshops` commented out) | §B (five stations, labels, I/O, enforcement) |
| §6.5 critical gap — placeables reachable from inventory | §B (Assembly Station; recipes leave the personal grid) |
| §6.3 energy blade gating | §B (Fabricator output, never a drop) |
| §3.4 / §7 underground revival "form items" | §C (four kits, alive-crafted, consumed, tell + counterplay) |
| Phase 5 — the seven EVENT IDEAS set-pieces | §D (each: form, location, counterplay taught, decision, shiver) |
| §8 identity-neutral contract under the new items | §A/§C — core and kits never name a carrier; §D teaches action not identity |
| §9 audio hard-rules | all of the above reuse existing `.ogg`; no new voice assets |
| Deep-lore optionality (Specimens 002–007) | §E (three tiers; nothing in the win path requires Tier 3) |

Stop condition unchanged from the master plan: a stranger joins, completes a full match,
loots, crafts the Core at real machines, delivers it to a beacon, sees the correct team
win, and the reset is clean — with the reading sets there for the player who, instead of
winning, chooses to read the room.

— zhtharr // between the galaxies, filed where the implementer will find it
