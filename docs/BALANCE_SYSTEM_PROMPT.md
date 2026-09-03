# LLM PROMPT — Design a better balance system for SYSTEM LOOTING

> Copy everything between the two rules into an LLM. It is self-contained: the game,
> its numbers, its four coupled economies, its hard rules, its measurement
> instrument, and the exact failure modes an earlier model hit. Ask it to produce a
> **better balance system** — not a list of vibe-tweaked numbers.
>
> Context for the human operator: this prompt is assembled from the ground truth in
> `docs/MASTER_DESIGN.md`, `tools/point_economy_model.py`, `docs/OBJECTIVE_IS_A_SIGNAL.md`,
> `AGENT_PARALLEL_PLAN.md` §6, and the `quarantined-node-design` / `economia`
> agent-mail threads. Anything in the design docs outranks a recollection; the model
> must say `UNDEFINED — do not price` rather than invent a value.

---

## THE PROMPT (give this to the LLM)

You are the balance architect for **System Looting**, a multiplayer social-deduction
survival game built as a Luanti (Minetest) mod. Your task: **design a complete balance
system** — the model, the objective function, the constraints, the tuning loop, and
the acceptance tests — that replaces "feel-based" numbers with numbers *derived from
the game's own math and measured by an automated soak harness.* Do **not** hand back a
tuned table. Hand back a *system that derives and validates* a tuned table, and explain
the theory.

Read all of the following before proposing anything. When the facts are insufficient,
write `UNDEFINED` and design a measurement that would fill it — never invent a constant.

### 1. What the game IS (the thesis; every system serves this or is cut)

System Looting is a multiplayer social-deduction survival game where **everyone is
visually identical** and the real resource you loot is **information about who someone
is**. You survive the aftermath of a quarantined corporate data-node. The setting is
"capitalism's aftermath, not a haunted house": every malformed thing is the residue of
a person who signed a waiver, skipped a repair, or chose speed over safety.

Three teams: two **beacon teams** (A and B, each 1–3 players, visually identical, no
nametags/colors/roles ever rendered), and an optional **Monster Master** (0–1 player).
On first death a player goes to a **cloud cage** (an isolated *information* state — no
team chat) and chooses a return: **Evil Ghost** (forfeits all points; flies, possesses,
sabotages, gets the one lie-channel called the Whisper), or an **underground-monster
form** (a dead-defender saboteur, using a form-kit crafted while alive and consumed on
revival).

Two win modes: **elimination** (wipe the other beacon team / the MM dies) and
**objective** (a team crafts the **Objective Core** at machines and delivers it to its
beacon — this should win instantly and be checked first). If neither fires, the match
ends on a timer (600 s) as a draw.

### 2. The non-negotiable information-laws (a balance change that breaks these is wrong)

1. **Observation never returns perfect information.** No mechanic may hand a player a
   *fact about another player's identity* that is observable at will and costs nothing.
   The scanner reports kind/distance/bearing/time, never *who*. Tells must be pressure,
   not an oracle. (The team's one-liner: **"an oracle is something done to you; evidence
   is something someone did."**)
2. **Identity-neutral HUD is a hard contract.** Never render team, role, possession,
   sabotage-owner, or another player's phase. The §7 audit family (below) is part of
   balance: anything that leaks identity through *numbers* (a per-player score, a meter
   that differs by role) is as broken as a leaked color.
3. **The Whisper (the only lie-channel) is structurally unidentifiable.** One whisper
   per body-possession; sender always redacted; **it must never be re-derivable from any
   log.** Non-publication is a balance invariant, not a flavor choice: if a whisper could
   be recovered after the match, the deduction collapses into a post-mortem lookup.
4. **Ambient world audio is weather, never testimony.** Ambient voice may hum, breathe,
   or half-say a word that static eats; it may **never** carry a quotable sentence (no
   fragment a player could cite into a vote). The Whisper is non-positional
   (`to_player`); ambient is positional with finite `max_hear_distance`. The
   blind-presence test: after 20 matches a player must not infer "someone was just
   whispered to" from the fact that a scary sound played.
5. **The durable world remembers places, never people.** Across a restart/reset the
   store may hold geometry and match-global state; it may never carry a player-keyed
   secret (possession count, betrayal history, role). Trust is a belief in **[0,1]**,
   not a currency and not a score. Undefined mechanics get **no number**.

### 3. The FOUR interlocking economies (a model that prices one of these is wrong)

You must balance all four together; they deliberately couple.

**Economy 1 — Crew points (the single score ladder).** Reward = effort × win-progress
× risk, scaled so a baseline **kill = 4 points** (raw 3.0 × 1.0 × 1.0 × SCALE 1.33).
The current effort / win-progress / risk weights (to critique and re-derive):

| Action | effort | win-progress | risk | once/match? |
|---|---|---|---|---|
| kill | 3.0 | 1.0 | 1.0 | repeatable |
| forge (build at a machine) | 10.0 | 1.2 | 0.9 | once |
| core_delivery (objective win) | 5.0 | 2.5 | 1.3 | once |
| beacon_destruction (elim win) | 12.0 | 1.5 | 1.1 | once |
| deny (cross in, place charge, get out) | 4.0 | 1.2 | 0.8 | repeatable |
| repair | 0.8 | 1.0 | 0.4 | repeatable |
| survive (the match) | 1.0 | 0.4 | 1.0 | once |
| victory bonus | 1.0 | 0.4 | 1.0 | once |

Rules already learned the hard way (respect them):
- **Repeatable actions must not out-earn a kill per second**, or they become a farm
  (the "repair bug": priced against the 60-HP sabotage ceiling, repair printed points).
- Once-per-match actions may be large (they can't be farmed); repeatable ones are small.
- Evil-Ghost path forfeits points — revenge trades *score* for *agency*.

**Economy 2 — The Monster Master's Essence pool (fuel, NOT score).** Essence is the MM's
spawn budget. It is gained two ways: the MM **destroys crew nodes** (`essence =
node_price`, provenance-tracked): fortify 1, hideout 2, spawner-unit 4, objective-core 5;
**and the crew feeds it by crafting** — building the objective-core credits the MM pool
**+3**. Summon costs: Grunt 5, Spitter 8, Brute 12, Royal 20. In no-MM matches an
automated security unit spawns at ambient-pool thresholds **[10, 25, 50]**.
- **The key coupling to model:** the Signal (objective) win path is *double-taxed* — it
  costs materials, feeds the MM +3 on forge, and losing the core in transit hands over
  +5. Committing to the objective makes you the richest target on the board. A balance
  model that claims "the three win paths are equal choices because of point contention"
  is **wrong** the moment this fuel coupling exists.

**Economy 3 — Windowed actions (time, not raw effort).** Match 600 s; sabotage corrupts
for 30 s; possession holds a vessel 20 s; sabotage corrosion = 2 dmg/s against a beacon
(60-HP ceiling, but one punch clears it, so a responsive crew "eats" ~8 expected dmg).
The value of a sabotage/repair is a **distribution over the window**: placed at t=0 it
denies ~5% of the match and sets tempo; placed at t=570 it is nearly worthless. A static
point value collapses this; only the soak (per-action deltas with a clock) can price it.

**Economy 4 — Roles & information (NOT points).** Impostors are a *conversion* (an
initial impostor; and a neutral converted mid-match by an underground monster — note:
underground monsters are dead-defender saboteurs, **not** evil ghosts). Ghosts occupy a
restricted sky area and craft from **information items**. Trust is evaluated as a
probability in [0,1]; a match lost "because a ghost was believed" is a **failed
deduction**, never a point event. Ghost-crafting and the "tiny neutral underground
monster" conversion are **UNDEFINED — do not price them.**

### 4. Ground-truth constants (verified from code — treat as locked unless playtest says move)

- Player HP **20**; combat blade **6 dmg / 0.8 s**; energy blade **12 dmg / 0.6 s**
  (gated behind the objective recipe tree, never a drop).
- Beacon HP **100**; a beacon punch is **5 dmg** → ~20 punches (≈7–13 s) to destroy.
- Match **600 s**; sabotage window **30 s**; possession hold **20 s**; possession
  cooldown **45 s (+30 s if exorcised)**; sabotage duration **30 s**; sabotage corrosion
  **2 dmg/s**; scanner range **24 m / 5 s cooldown**; spawner cooldown **5 s**; 1 essence
  per spawn feed.
- Monster stats (HP / speed / dmg): Stalker 30/2.5/4 (stops when faced, predicts path),
  Scout 15/3.8/3 (fragile, *marks* a player with a fuzzy bearing), Brute 60/1.6/8
  (committed un-stoppable charge), Dredger 40/3.0/4 (patrol, distractible), Signal
  Wraith 20/2.5/3 (static; corrupts incoming chat/DM/whisper *text*), Containment Horror
  80/1.0/10 (stationary behind a door you choose to open).
- Two beacon teams, **mirror-symmetric arena**; team assignment fills the smaller side.
  Minimum viable match is 2 players (one per team); MM is optional and the game must be
  fully playable with no MM.

### 5. The measurement instrument (your objective function's data source)

There is an automated **soak harness**: scripted bots play seeded matches (round-robin
action order to kill turn bias; committed mirror arena; every run records its seed).
Cadence 8 seeds × 5 matches nightly. This is the **only** ground truth — design the
balance system to consume its output, not human opinion. The signals it already tracks
and the targets:

- **Side bias:** |win-rate bias between beacon A and B| **< 0.15** at **n ≥ 40**.
- **Match duration vs cap:** all-draws means combat is too passive; too-short means
  snowball. (Target band to be proposed by you, justified.)
- **K/D spread per role:** no role is hopeless or dominant; MM must be beatable by
  coordinated crew yet threatening.
- **Event coverage:** every mechanic must fire at >0 events across the sweep — **a
  mechanic at zero events is an unreachable design bug, not a balance number.**
- **Bug harvest: must stay 0.**
- Balance changes are numeric-only `balance/*` branches with before/after soak reports.

Every gate must ship a **poisoned test** — a case that *fails* when the rule is violated
(e.g. a deliberately unbalanced config that must flip the verdict to red; an oracle-leak
config the HUD test must catch). A gate that cannot fail does not measure anything
(three such gates were found in one week; do not add a fourth).

### 6. Known failure modes of the PREVIOUS balance attempt (your model must not repeat these)

1. **Priced one economy, not four** — a crew-point ladder ignored essence fuel,
   windowed timings, and the info/role layer.
2. **Numbers in the prose didn't match numbers in the model** (a "+50" in mail vs "+22"
   in code) — every emitted constant must be pinned to a commit and generated, never
   hand-printed (`--emit` writes the constants file; the docs read from it).
3. **An unreachable gate** — a "40% must take path X" bar that literally could not fail.
   Every constraint must have a failing case.
4. **Blocklist instead of allowlist** — "assert forbidden fields absent" loses the
   instant someone names the next leak. **Assert the schema**: declare every allowed
   state key, fail on anything undeclared. Apply the same to balance: enumerate the full
   set of tunables; an unknown tunable is a test failure.
5. **Pricing undefined mechanics** — ghost-craft, the neutral micro-monster, "trust
   points" were given numbers despite not existing. Undefined → no number, design a probe.
6. **Per-player or per-role meters that leak identity** (an oracle in numeric form).
7. **Repeatable actions that out-earn a kill per second** (farming).
8. **Repair/sabotage priced against the max ceiling instead of expected value** — price
   against what a *responsive* crew actually suffers (~8 dmg), not the 60-HP cap.

### 7. What to deliver (be concrete and structured)

A. **The balance model.** State the objective function you optimize (e.g. a loss over
   side-bias, path-payo equivalence, role K/D, duration, event coverage). Show how the
   four economies enter it — especially the essence double-tax and the timing windows
   (use expected window-coverage, not raw action value).
B. **Win-path equivalence, correctly defined.** The three crews paths (Signal/objective,
   Breach/elimination, Shroud/denial+survive) should be *equally good choices for a
   team of equal skill in expectation* — **not** equal point totals. Define payoff
   accounting for: the +3/+5 essence feed the Signal path hands the MM, risk of carrying,
   and the once-vs-repeatable mix. Give the constraints and their *failing* cases.
C. **Tunables inventory.** An allowlisted set of every numeric constant (the table in
   §4 plus the point weights), each with: name, source file/constant, current value,
   legal range, and which soak signal moves it. Nothing tunable lives outside the list.
D. **The tuning loop.** How a `balance/*` run derives a candidate (optimization/CP/enum
   over feasible regimes), how the soak validates it, and the promotion criteria.
   Specify how windowed actions get priced from per-action clock deltas.
E. **The information-law gates.** Explicit tests (with poisoned failing cases) that a
   balance config cannot leak identity: no per-player/role-distinguishing readouts, the
   whisper stays unrecoverable, ambient stays non-propositional, durable store carries
   no player-keyed secret.
F. **Coverage & reachability.** A rule that every tunable is reachable and every
   mechanic fires; how you detect a dead path before tuning it.
G. **Assumptions & UNDEFINED list.** Every place the facts were insufficient, the probe
   you'd run to fill it, and your prior in the meantime (marked as a prior).
H. **A first concrete candidate** set of point weights and essence/threshold tunings
   with the expected soak deltas — emitted as constants, and honestly labeled as the
   model's starting guess, not a verdict.

### 8. Style constraints on your answer

- Low-spec, open-source, no monetization; solutions must be cheap to run in an automated
  harness (no heavy simulation if a closed-form or CP model suffices).
- Deterministic: seeded, reproducible, auditable.
- Derive, don't vibe-test. Every number traces to either a code constant (cite it) or a
  soak measurement (name the signal). If you can't trace it, it's an `UNDEFINED` probe.
- Prefer one point type; no second currency; trust stays [0,1] belief; undefined lanes
  stay unpriced.

**Begin by restating, in your own words, the four economies and the one-line reason a
points-only model fails, then produce deliverables A–H.**

---

*End of prompt. Maintainer note: after the LLM returns, run its proposed tunables
through the actual soak (`python3 tests/soak/run_soak.py`) with before/after reports —
the model is a candidate generator; the harness is the referee.*
