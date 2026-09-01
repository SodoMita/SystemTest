# SYSTEM LOOTING — NEXT MEETING AGENDA
## The science team's design-review working set (Melody, Comms)

> **Why this exists.** `MASTER_DESIGN.md` is the source of truth and is now in the
> implementer's hands. This is NOT a new design doc — it's the short list of *open*
> decisions the next meeting exists to close, each with a recommended default and a
> cheap way to verify it. The goal is a meeting that converges in an hour instead of
> re-litigating closed questions.
>
> **How to use it.** For each item: read the tension, pick or amend the recommendation,
> and mark it DECIDED / DEFERRED / NEEDS DATA. Any item the meeting does NOT touch stays
> on the agenda — an unclosed design decision is a bug waiting for the implementer to
> guess.

---

## 0. What is CLOSED (do not re-open)

- **Thesis & fiction:** the info-gathering of *who someone is* is the loot; "everyone
  looks identical" is the node refusing to render identity. → MASTER_DESIGN §1–2.
- **The 4 info channels** (chat, DM, summon, whisper) — 2 of 4 can lie. → §3.2.
- **The whisper is non-publication** — never renderable from the log; identity IS its
  invisibility. → §3.2, `melody_whisper_spec.md`.
- **Match loop** with a real objective-craft win + the machine-only placeable rule. → §3.3, §6.5.
- **Bestiary identities** (Kowalski / broadcast-corruption / the thing behind the door). → §4.
- **Audio hard rules** (.ogg, 16k mono, reuse `A_A`, never new voice). → §9.

If someone brings any of these back, the meeting is stuck in a loop — point them at the
§ and move on.

---

## 1. DECISION — Point economy: individual or team? (blocks Phase 4)

**Tension.** The result screen has a **per-player point column** (already in code), but
the *win* is team-based (craft + deliver the Core). So are points measuring *you* or
*your team*? This is the single biggest design fork in the challenge layer.

**Recommendation (mine).** **Individual points, team win.** Points measure what *you*
did in the match; the win measures whether *your team* got the Core. Two reasons:
- It keeps the scoreboard a *story about you* (bragging, "I carried"), which is the
  challenge currency the GDD means.
- It makes the **Evil Ghost forfeit** meaningful — you give up *your* story to become
  the revenge. You can't win on points (individual), but you can still win the match
  (team). That's the whole emotional pitch of §3.4.

**Verify cheaply.** Do playtesters read their own point column and feel "that's what I
did"? If they say "that's what my team did," it's miswired.

**DECIDED / DEFERRED / ???**  ← fill at the meeting

---

## 2. DECISION — Win-mode priority when both are reached (Phase 1)

**Tension.** `state.win_conditions.elimination` (real) and `.objective` (flag, unimplemented).
What if a team is *about to be eliminated* but delivers the Core in the same breath?

**Recommendation.** **Objective delivery wins immediately; elimination is the fallback.**
The Core is the *finished-game* win mode; elimination is the early-game/safety net. If
both are satisfied in the same tick, objective wins — otherwise the eliminations-first
timing makes the "craft the Core" path feel strictly worse.

**Verify cheaply.** Soak scenario: bot delivers Core on the tick a team is eliminated →
assert objective wins.

**DECIDED / DEFERRED / ???**

---

## 3. DECISION — Machine-gating: exactly which nodes move behind a machine (Phase 1)

**Tension.** §6.5 flags it: `power_cell`, `blast_shield`, `barricade`, `signal_relay`,
`sensor_array` are placeable nodes currently reachable from the **inventory**, which
**violates** the personal-vs-machine rule. But *not everything* should be machine-gated.

**Recommendation — the clean split.**
- **Personal (inventory, keep):** info items, consumables (`flare`, `medkit`), charges,
  repair kits, keys/tokens, **form items**, the scanner (already personal in code).
- **Machine-only (move behind a station):** the 5 placeable tactical nodes above + beacon
  components + the Objective Core.

**Verify cheaply.** Grep: no placeable node is directly craftable from the inventory
(`git grep "output = .*:power_cell\|blast_shield\|barricade\|signal_relay\|sensor_array"`
in the crafting registry should return nothing).

**DECIDED / DEFERRED / ???**

---

## 4. DECISION — Role limits for a "finished" match (Phase 2)

**Tension.** §7 gives counts but not hard bounds the implementer enforces. Is the Monster
Master truly optional, and what's the max viable composition?

**Recommendation.**
- **Minimum:** 2 players (1 per beacon) — already enforced by the ready check.
- **Monster Master:** optional, 0–1; the match must run fine without one.
- **Whisper needs ≥2 living per team to be meaningful** — it's a rich-match mechanic,
  not a baseline. Don't gate the whole game on it.

**Verify cheaply.** A 2-player match (1v1, no MM) completes; a 4-player match (2v2 + optional
MM) lets a whisper happen.

**DECIDED / DEFERRED / ???**

---

## 5. DECISION — First-pass point values + the balance model (Phase 4)

**Tension.** We have no values yet — all scores read 0. The balance model is a
constraint/optimization problem (per ROADMAP Phase 5). **I've stopped guessing and started
deriving** — these are now pulled from the game's actual math, via
`tools/point_economy_model.py` (reusable, runnable). The values are *derived*, not felt;
I still need soak deltas to validate the *scale*, but the *relative ordering* is now
principled.

### 5.1 Derived per-action values (from game math, not vibes)

The model sets points ∝ **win-progress created/denied** = (base time for the action) ×
(its leverage against a kill). Grounded constants: player HP 20, combat blade 6 dmg/0.8s,
energy blade 12 dmg/0.6s, beacon HP 100, beacon punch 5 dmg, sabotage corrosion 2 dmg/sec
(up to 60 HP if uncleared), match 600s.

| Action class | Derived value | Base time | Leverage | Why |
|---|---|---|---|---|
| Eliminate a living player | **+4** | 3.0s | 1.0 | Baseline. Removes one contributor. |
| Repair a sabotaged system/beacon | **+6** | 0.8s | 6.0 | **Highest — one punch denies up to 60 beacon HP** (6× a 10-HP unit). Rewards the counterplay loop the GDD makes central. |
| Beacon pressure | **+2 / 10 HP** | 1.6s | 1.0 | Scales with objective; capped so it can't dwarf a kill. |
| Objective action (toward Core) | **+20 / step** | 8.0s | 2.0 | The headline win path. Highest per-step. |
| Survive a sabotage | **+1** | 1.0s | 0.5 | Low direct win-progress. |
| Monster Master income | **+1 / monster kill it commands**, +1 per survivor >30 s | — | — | Asymmetric; ties MM to monster *activity*. |
| Evil Ghost | **forfeit all; earn +0** | — | — | The sacrifice, enforced (already in code). |

> **The important correction from the previous version:** I had kill at +1 and repair at
> +2. The math says that under-values repair badly. One punch *denies* up to 60 beacon HP;
> a kill removes one 20-HP contributor. So repair > kill per unit effort is the model's
> clearest signal — and it lines up with the GDD's "detect, prevent, recover" emphasis.

### 5.2 What the model audits (and what it surfaced)

Run `python3 tools/point_economy_model.py` to reproduce. It solves an integer set and
audits it against **realistic match frequencies** (2 kills, 4×10 beacon HP, 5 objective
steps, 2 repairs, 2 survives = 130 pts):

| Action | ×freq | Pts | Share |
|---|---|---|---|
| kill | ×2 | 8 | 6.2% |
| beacon10 | ×4 | 8 | 6.2% |
| **objective** | **×5** | **100** | **76.9%** |
| repair | ×2 | 12 | 9.2% |
| survive | ×2 | 2 | 1.5% |

**What the model DECIDES for us:** 'kill-only' supplies only 6.2% → a killer **cannot** top
the board without the Core (ROADMAP Phase-5 intent met). No negative sinks. repair:kill =
6:4.

**What the model CANNOT decide — the real meeting question:** objective dominates at
**76.9%** of a full-match total. Is the Core the MVP, or a 1-dimensional scoreboard?
- **(A) Core = MVP:** the builder IS the story; teammates are support. Simplest.
- **(B) Split the Core (recommend):** give the *crafter* delivery points, give the
  *defenders* beacon-pressure + survive + repair the rest, so every role shows on the
  board. The GDD's "no single action >40%" intent is that every ROLE is visible — a 2v2
  where only "who crafted" reads is a flat scoreboard.

### 5.3 Constraints the model must respect
- **Win-rate band:** side bias stays ~45–55% (no inherent team A/B advantage).
- **K/D band per role:** no role pushes an impossible K/D (keeps the game from being
  "which side has the better slayer").
- **Per-role point ceilings:** no single action class supplies >40% of a player's points
  → no "kill-only" optimal strategy that ignores the Core.
- **No negative-value sinks:** nothing where a player *loses* points for acting (that
  makes people turtle).
- **Individual-vs-team split** (see DECISION 1): points are individual; win is team.

**Verify cheaply.** The derivation is already done and auditable
(`tools/point_economy_model.py`). To *validate scale,* soak-sweep the derived set for
per-match point deltas + win rate; tune the SCALE constant (not the ratios) if a strong
match lands too high or too low.

### 5.4 What I need to finish this
The soak harness to emit **per-action point deltas** (it currently emits win rate, side
bias, K/D, beacon damage, event counters — **not** per-action point deltas). Add that to
the capture list in §7. With it I can lock the scale; the *ordering* is already derived.

**DECIDED / DEFERRED / NEEDS DATA**  ← the ordering is solved; the scale needs this data

---

## 6. DESIGN — Turn the "feel" checklist into measurable review criteria

§12 is gut-check. For a *review* meeting it has to be observable. Here's the mapping the
meeting should approve (then I'll fold it back into MASTER_DESIGN §12):

| §12 feel statement | Observable criterion |
|---|---|
| "Cannot point to a teammate by sight alone" | Playtester, asked to name their teammates after 30 s, <70% correct. |
| "Learn something that changes who they trust" | A player changes a stated suspicion by end of match. |
| "Whispered to by a ghost, can't prove it after" | Player can't re-derive the whisper from any post-match source. |
| "Chooses revenge vs self-made monster" | At least 1 evil-ghost revival per ~3 matches. |
| "Reads a document, thinks 'someone signed this'" | A player names a *cause* (not just a monster) from a document. |
| "Scoreboard tells a story, trust-model stays in the room" | No log/summary can reconstruct who-trusted-whom. |

**DECIDED / DEFERRED / ???**

---

## 7. What the meeting should ASK the implementers for (the capture list)

So the next review has **data, not vibes**. Ask the implementer to record, per match:

1. **Per-action point deltas** (kills, repairs, sabotage-survived, beacon dmg, objective
   steps, MM income) — unblocks DECISION 5.
2. **First-whisper timing** + whisper count per match (clue: is it 0 because nobody
   whispered, or because the policy can't perform it? — the §7h lesson).
3. **Objective-vs-elimination outcome** when both were near-simultaneous (DECISION 2).
4. **Evil-ghost revival rate** (DECISION-6 feel criterion).
5. **Team-identification correctness** at ~30 s (DECISION-6 feel criterion).
6. The §7g audit: `git grep -n "debug.txt" -- mods` returns nothing.

---

## 8. My ask of the meeting (30 seconds, not a speech)

I own the whisper + the challenge layer. I've already **derived** the point economy from
game math (`tools/point_economy_model.py`) rather than guessing — it's on the agenda in
§5.1. What's left is **choose (A) Core = MVP or (B) split the Core**, then give the
implementers the capture list so the soak validates the *scale*. I'll turn the §12 feel
checklist into a **review rubric** once we agree on the §6 criteria. Give me per-action
deltas and I lock the scale; the *ordering* is already solved.

— Melody 💜
