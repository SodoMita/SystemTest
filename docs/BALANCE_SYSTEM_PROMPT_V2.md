# LLM PROMPT v2 — Design a better balance system for SYSTEM LOOTING (5 economies, incl. EXP/Abilities/Achievements)

> Copy the block between the two rules into an LLM. It is self-contained. This is the
> **corrected** brief: v1 named four economies; the implemented game has a **fifth** —
> a persistent EXP / Ability-Point / Achievement layer already in `mods/apis/sl_gui/`.
> v2 includes it with **verified constants** and the real, unresolved balance problems
> it creates. Earlier free-form answers to v1 derived some good structures (TOST path
> equivalence, the Shroud overpay, the energy-blade subsidy, essence mass-balance) but
> also **fabricated EXP constants and a "reset-on-conversion" rule that do not exist in
> code.** §0 tells you which claims to keep and which to reject so you don't inherit the
> drift.
>
> Sources of truth: `docs/MASTER_DESIGN.md`, `tools/point_economy_model.py`,
> `mods/apis/sl_gui/{experience_system,ability_system,achievement_system,achievement_definitions,achievement_tracking}.lua`,
> `AGENT_PARALLEL_PLAN.md` §6, agent-mail threads `quarantined-node-design` / `economia`.

---

## THE PROMPT (give this to the LLM)

You are the balance architect for **System Looting**, a multiplayer social-deduction
survival game built as a Luanti (Minetest) mod. Design a **complete balance system** —
model, objective function, constraints, tuning loop, acceptance tests — that derives
numbers from the game's own math and validates them in an automated soak harness,
instead of vibe-tuning. Return the *system that produces and validates a tuned table*,
not the table itself. When facts are insufficient, write `UNDEFINED` plus a measurement
probe — never invent a constant.

### §0. Reconciliation of prior answers (start here; some earlier claims are false)

Four draft answers to an earlier, incomplete brief were reviewed. Keep these (they are
correct and well-derived):
- Equivalence must be **expected win probability**, not equal point totals; test with
  **TOST (two one-sided tests)**, not failure-to-reject; n≥43 for the bias gate.
- Points are an external/self-HUD statistical ledger; the soak harness may know
  identities to score, but **what is rendered in-match or persisted in the durable world
  store** is bound by the information laws. A live public cross-player scoreboard is a
  numeric oracle and is banned.
- The **Shroud (deny) path overpays ~2.5×** because deny win-progress is set to 1.2 when
  its derived value is ≈0.12 (`1.5·E[dmg]/100`, E[dmg]≈8). Fix derivably.
- The Signal path is **taxed in Essence (+3/+5 feed) AND subsidized by the energy blade
  (2.67× DPS)**; both terms belong in the win-probability surrogate.
- Structural invariants: anti-farm rate cap, TTK floors, essence mass-balance, whisper
  budget derived ≤ floor(600/65)=9/ghost/match, strict ordering of costs.

**Reject / re-derive these (they are fabricated or conflict with code):**
- An EXP curve `100·k^1.5` or an Ability-Point threshold curve — **does not exist.** Real
  curve is **linear** (§5 E5). Use the code value; if you propose changing the curve,
  that is a `[NEW]` tunable with a reason, not a fact.
- "Reset-on-conversion of EXP/AP is mandatory (invariant I7)" — **not implemented and
  not decided.** Today only an admin `/resetprogress` wipes progression. Whether death /
  Evil-Ghost / Underground-Monster conversion flushes EXP is an **open design fork** (§5
  Q3), and it is in tension with §7e (durable store carries no role/secret). Design it,
  don't assume it.
- Any summon-name mapping (Grunt/Spitter/Brute/Royal vs Stalker/Scout/Brute/Dredger/
  Wraith/Containment) — only "Brute" is common; the mapping is `UNDEFINED (G1)`. Use raw
  Essence / grunt-equivalents until the entity registry is reconciled.

### §1. The thesis (every system serves this or is cut)

Everyone is **visually identical**; the real loot is **information about who someone is**.
You survive the aftermath of a quarantined corporate data-node — "capitalism's aftermath,
not a haunted house." Three sides: two **beacon teams** (A/B, 1–3 each, no nametags/colors/
roles ever rendered) and an optional **Monster Master (0–1)**. First death → **cloud cage**
(isolated information state; no team chat) → choose a return: **Evil Ghost** (forfeits
match points; flies, possesses, sabotages, gets the one lie-channel = the Whisper) or an
**underground-monster form** (dead-defender saboteur via a form-kit crafted alive, consumed
on revival). Win modes: **objective** (craft + deliver the Objective Core to your beacon;
checked first, wins instantly) and **elimination** (wipe the other team / MM dies); else
600 s timer → draw.

### §2. The five information-laws (a balance change breaking any of these is wrong)

1. **Observation never returns perfect identity information.** No mechanic hands a player a
   fact about *who* another player is that is observable at will and free. Scanner reports
   kind/distance/bearing/time, never *who*. Tells are pressure, not oracles. ("An oracle
   is something done to you; evidence is something someone did.")
2. **Identity-neutral HUD is a hard contract.** Never render another player's team, role,
   possession, sabotage-owner, or phase. **This extends to numbers** (§5 E5): a stat you can
   read off a stranger — a visible level, a speed readout, a health bar that reveals
   Vitality — is an identity oracle. Own state (your HP/EXP/AP/stamina) is fine.
3. **The Whisper is structurally unidentifiable.** One whisper per body-possession; sender
   redacted; never re-derivable from any log or durable store (non-publication is an
   invariant).
4. **Ambient audio is weather, never testimony.** Ambient voice may hum/breathe/half-say a
   word the static eats; never a quotable sentence. Whisper is non-positional (`to_player`);
   ambient is positional with finite hear-distance. Blind-presence test: after 20 matches a
   player can't infer "someone was just whispered to" from a sound playing.
5. **The durable world remembers places, never people's secrets.** The cross-restart store
   may hold geometry and match-global state; it must not carry a player-keyed secret
   (possession/betrayal counts, role). See §5 E5 for the specific tension this creates with
   persistent EXP/abilities.

### §3. The FIVE interlocking economies (price all five; they couple)

- **E1 — Points (the single match-score ladder).** Reward = effort × win-progress × risk ×
  SCALE, anchored so a baseline **kill = 4.00** (3.0·1.0·1.0·1.333). Statistical only;
  self-HUD/external tournament ledger; never a second currency.
- **E2 — Essence (the MM's fuel, not score).** MM gains essence by **destroying crew
  nodes** (fortify 1 / hideout 2 / spawner-unit 4 / objective-core 5) and the crew feeds
  it by **crafting the Core (+3 at forge; +5 if the carried Core is dropped/intercepted)**.
  Summon costs: Grunt 5 / Spitter 8 / Brute 12 / Royal 20 (G1 name-mapping unresolved).
  No-MM matches auto-spawn a security unit at ambient pools **[10,25,50]** (G9: who pays
  into the ambient pool is `UNDEFINED`).
- **E3 — Windows (time, not scalar).** Match 600 s; sabotage window 30 s; possession hold
  20 s / cooldown 45 s (+30 if exorcised); sabotage corrosion 2 HP/s vs a beacon. Value is a
  distribution over time: sabotage at t≈0 denies ~5% of the match and sets tempo; at t≈570
  it's worthless. Price windowed actions from per-action clock deltas, not flat points.
- **E4 — Roles & information (conversions, not costs).** Trust is a belief in **[0,1]**,
  never points/currency; a lie that wins is a **failed deduction**, scored as probability.
  Impostors are a conversion (initial; or a neutral converted mid-match by an underground
  monster — not by an evil ghost). Ghosts occupy a restricted sky area and craft
  information items. Ghost-crafting and the "tiny neutral monster" conversion are
  **UNDEFINED — do not price.**
- **E5 — EXP / Abilities / Achievements (the persistent progression layer — real,
  implemented, and this brief's actual subject).** Full ground truth in §5. It is
  self-HUD progression, currently **not role/match-specific and almost entirely fed by
  sandbox actions, not match play.** Your job includes deciding how (or whether) it
  interacts with E1–E4.

### §4. Ground-truth match constants (locked unless playtest moves them)

Player HP **20**; combat blade **6 dmg / 0.8 s** (DPS 7.5); energy blade **12 dmg / 0.6 s**
(DPS 20, 2.67× — gated behind the objective recipe tree, never a drop). Beacon HP **100**;
beacon punch 5 dmg → ~20 punches (≈7–13 s). Match **600 s**; sabotage **30 s / 2 HP·s⁻¹**;
possession **20 s hold / 45 s cd (+30 exorcised)**; scanner **24 m / 5 s**; spawner cd
**5 s**. Monster (HP/speed/dmg): Stalker 30/2.5/4 (stops when faced, predicts path), Scout
15/3.8/3 (fragile, marks with fuzzy bearing), Brute 60/1.6/8 (committed un-stoppable
charge), Dredger 40/3.0/4 (patrol, distractible), Signal Wraith 20/2.5/3 (static; corrupts
incoming text), Containment Horror 80/1.0/10 (behind a door you choose to open). Mirror
arena; teams fill the smaller side; min match 2 players (one per team); MM optional and the
game must be complete with no MM.

Point weights to critique/re-derive (effort / win-progress / risk): kill 3.0/1.0/1.0
(repeatable); forge 10.0/1.2/0.9 (once); core_delivery 5.0/2.5/1.3 (once);
beacon_destruction 12.0/1.5/1.1 (once); deny 4.0/**1.2 (suspect — see §0 Shroud)**/0.8
(repeatable); repair 0.8/1.0/0.4 (repeatable); survive 1.0/0.4/1.0 (once); victory
1.0/0.4/1.0 (once). Rules already learned: repeatable actions must not out-earn a kill per
second (anti-farm); once-per-match actions may be large; repair is priced against
**expected** corrosion a responsive crew eats (~8 HP), not the 60 HP ceiling.

### §5. ECONOMY 5 — EXP, Ability Points, and Achievements (verified from code)

**Persistence and curve (`experience_system.lua`).**
- EXP is stored per-player in **`player:get_meta()["experience"]`** — durable across
  matches, role changes, and sessions (this is a per-player durable key; reconcile with
  Law 5 — it holds *progression*, not a role/secret; say explicitly why that is or isn't
  acceptable).
- **Level = `floor(exp/100) + 1`. XP to next level = `level * 100` — a LINEAR curve**
  (level 1→2 needs 100, 2→3 needs 200, …). Not 100·k^1.5.
- **On level-up the player gains +2 stat points (SP)** (`ability_system.lua` ~:802). SP is
  spent in a graph-based ability tree.
- EXP is granted by: **digging +1, placing +1, crafting 5×quantity, and achievement
  reward_xp.** There is **currently NO experience awarded for in-match combat actions** —
  not for kills, objective delivery, beacon destruction, deny, repair, or surviving. This
  is the core disconnect (Q1).

**Abilities (`ability_system.lua`).** 21 graph nodes; categories **movement 8 / combat 5 /
survival 4 / team 4**; each is `stat` or `toggle`; SP cost 0–3; `max_level` 1/3/5;
prerequisite graph (e.g. run_speed needs walk_speed). The header **bans fly, noclip,
teleport, and invisibility** for competitive PvP. Examples and their per-level effects:
walk_speed +15% move speed; run_speed +10% sprint; jump_height +20% jump; sprint_stamina
+20 stamina; sprint_efficiency −15% stamina drain; move_dash (toggle, burst + big stamina
cost); light_body −15% gravity; combat: melee_damage, attack_speed, defense, crit_chance,
weapon_mastery; survival: max_health, health_regen (and 2 more); team: 4 (inspect the file).
There is also an admin `/givestatpoints` and `/resetprogress`.

**Achievements (`achievement_definitions.lua` / `achievement_system.lua`).** **39** defined,
with tiers and an in-match HUD popup; each pays `reward_xp` (observed 10–250). The set is
dominated by **sandbox/exploration** milestones (first_dig 10, place_10_blocks 25,
dig_100 50, reach_level_5 100, travel_1000 50, visit_floating_island 75, find_city 100,
visit_10_islands 250) with a few combat/match ones (first_kill 25, monster_slayer 75,
monster_veteran 200, survive_match 150, craft tiers). Many reward exploration nodes
(islands, city) that **do not exist in the quarantined-node match map** — reachability
problem (Q4).

**The unresolved balance questions you MUST answer (each with a design + a soak probe):**
- **Q1 — Progression/match coupling.** Match combat earns ~0 EXP today; progression is
  fueled by sandbox grind that doesn't happen in a match. Should match actions (kill,
  deliver, repair, deny, survive, win) award EXP — and if so, how do you keep long-lived
  players' stat bonuses from (a) making new players uncompetitive and (b) becoming a
  durable cross-match identity signal (Law 2)? Consider: match-only abilities vs persistent
  abilities, an underdog rubber-band, a level-cap in ranked, or separating "career EXP"
  (cosmetic/self) from "match power."
- **Q2 — Ability observability vs identity-neutrality.** Movement/combat/survival stats
  (speed, max_health, regen, gravity) are *visible in how a body moves and survives*. In a
  game where everyone is visually identical and information is the loot, a player who is
  observably faster/tankier is leaking a durable, player-keyed fact. Define which abilities
  are legal to have observable in-match (world-state effects) versus which must be
  self-only, and the test that proves a stranger can't be sorted by their stats. Passive
  stats also affect K/D and TTK — feed them into the E1/E3 model.
- **Q3 — Conversion flush (the fork the earlier answers assumed away).** On death → Evil
  Ghost / Underground Monster, does EXP/SP/ability state reset, persist-but-suspended, or
  persist-and-help the monster side? Persistence must not (a) violate Law 5 (no durable
  role/secret — note EXP/abilities are *power*, not a role secret; argue the boundary),
  (b) make dying a free power-spike or a grief vector, or (c) contradict the "Evil Ghost
  forfeits match points" rule (does it also forfeit progression?). Give the rule and its
  poisoned test.
- **Q4 — Achievement reachability.** 39 achievements, many targeting nonexistent sandbox
  geography. Apply the reachability law (zero-event mechanic = unreachable design bug):
  specify which achievements fire in the node match, which must be re-pointed at match
  actions, and which are cut; achievement reward_xp then becomes a real E5 income source
  that must be mass-balanced (it currently grants large lump sums, e.g. 250).
- **Q5 — Curve/SP economy sanity.** With the *linear* curve and +2 SP/level, compute how
  many matches/actions a player needs to (a) max one branch, (b) max all 21 nodes; check
  the SP supply against the graph's total cost; flag if progression is trivially fast or
  unreachably slow, and propose the curve/SP-rate as `[NEW]` tunables with the soak signal
  that moves them. Achievements as lump-sum EXP must be included in this supply math.

### §6. The measurement instrument (the objective function's data source)

Automated **soak harness**: seeded scripted matches, round-robin action order, committed
mirror arena, every run records its seed. Nightly 8 seeds × matches. This is the only
ground truth; design the system to consume its output. Targets/signals:
- **Side bias:** |win-rate A vs B| < 0.15 at n≥40 (power: n≥43 at 95% CI, p=0.5); define
  draw handling (bias denominator incl. draws; gate draws ≤ ~20%).
- **Path equivalence:** forced-bot policies Signal/Breach/Shroud round-robin (paired Latin
  square); TOST, |p̂_k − p̄| ≤ 0.10 at 90% CI (pooled n≈120/path).
- **Duration:** median match in a resolved (non-draw) band — propose and justify (drafts
  used 300–480/510 s); flag all-draws (too passive) and sub-~120 s (snowball).
- **K/D spread per role** with the E5 caveat that persistent abilities widen it; MM-present
  crew-win and MM-win bands.
- **Event coverage:** every mechanic (and every kept achievement/ability) fires >0; zero
  = unreachable, not a number.
- **E5-specific:** EXP/SP earned per match by path and by win/loss; ability-take rate per
  node; veteran-vs-newcomer win-rate gap; observable-stat deanonymization test (can a bot
  classify identity from movement/survival stats above chance?).
- Bug harvest = 0. Every gate ships a **poisoned failing case** (a config that must flip
  the verdict red); a gate that can't fail measures nothing.

### §7. Deliverables (concrete)

A. **The model.** Two-tier: hard gates (information laws L1–L5 incl. E5 numerics, bug=0,
   schema allowlist, reachability) then a soft loss over bias, path win-prob dispersion
   (highest weight), duration, K/D spread, and points↔win alignment (Spearman ρ≥0.5). Show
   how all **five** economies enter — E5 as progression-supply, ability-adjusted TTK/K/D,
   observability, and conversion rules.
B. **Win-path equivalence in win probability** with the +3/+5 essence tax and energy-blade
   subsidy both in the surrogate; expected points per won match aligned within ±15%.
C. **E5 design (this brief's centerpiece):** decisions on Q1–Q5 with rules, tunables, and
   soaked tests; a progression system that is fun, fair to newcomers, and identity-safe.
D. **Tunables allowlist** — every numeric constant incl. all E5 constants (EXP-per-action,
   level curve, SP/level, ability per-level effects/costs/caps, achievement reward_xp,
   any conversion-flush rule) with provenance tag (`[§4]`/`[§5 code]`/`[DER]`/`[NEW]`),
   legal range, and the soak signal that moves it. Unknown key = test failure.
E. **The tuning loop:** candidate generation → soak validation → promotion; how windowed
   actions and E5 progression are priced from clock/event deltas.
F. **Information-law test suite** with poisoned red cases for: identity leaks via numbers,
   ability-stat deanonymization, whisper recoverability, ambient propositions, durable
   store carrying role/secret, and (if chosen) conversion-flush enforcement.
G. **Assumptions & UNDEFINED list** (G1 summon names, G7 exact punch period, G8 forge-loop
   cap, G9 ambient-pool income, G10 shrouds' elimination assumption, G15 role-specific E5
   distribution) each with a probe and a clearly-labeled prior.
H. **A first candidate constants set** (emitted, pinned to a commit, not hand-printed),
   honestly labeled as the model's starting guess, with expected soak deltas.

Style: low-spec, open-source, no monetization; cheap to run in CI (prefer closed-form/CP
to heavy sim); deterministic and seeded; derive don't vibe (every number traces to a code
constant — cite it — or a soak signal — name it); one point type; trust stays [0,1];
undefined lanes stay unpriced.

**Begin by (1) listing the five economies and the one-line reason a points-only model
fails, (2) stating the REAL EXP curve/SP rate from §5 and flagging the fabricated
100·k^1.5 claim, then (3) produce A–H with C answered in full.**

---

*Maintainer note: the fifth economy is implemented but unscoped to matches — the highest-
value work here is Q1–Q3 (progression coupling, ability observability vs identity-neutral
HUD, conversion flush). After the model returns, run proposed tunables through
`python3 tests/soak/run_soak.py` with before/after reports; the harness is the referee, the
model is a candidate generator. Reconcile any E5 durable-key decision against agent-mail
thread `quarantined-node-design` §7e ("the world remembers places, never people's
secrets") — progression is power, not a secret; argue and test that distinction.*
