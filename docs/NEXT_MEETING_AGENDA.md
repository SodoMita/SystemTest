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

## 5. DECISION — Point economy, LOCKED to the three-path structure (Phase 4)

**Tension.** We have no values yet — all scores read 0. The balance model is a
constraint/optimization problem (per ROADMAP Phase 5). **The derivation is done** via
`tools/point_economy_model.py` (reusable, runnable), and the 76.9% it surfaced was the
*symptom* of two disconnected economies — cured by the three-path structure. This section
is the LOCKED starting point; the meeting's word is on **scale**, not ordering (which is
already derived), and on whether points ride the strand ledger.

> **Status after glitch's votes (2026-09-02):** all six agenda decisions endorsed. The
> remaining open word is (a) confirm the SCALE once soak deltas exist, (b) confirm
> points-as-strand-events (glitch §8), (c) the exact negative-contract + floor-sweep items
> from carmack/jax.

### 5.1 Derived values (three-path, delivery-as-jackpot)

Points ∝ **win-progress created/denied** = (base time) × (leverage against a kill).
Grounded constants: player HP 20, combat blade 6/0.8s, energy blade 12/0.6s, beacon HP 100,
beacon punch 5, sabotage corrosion 2 dmg/sec (up to 60 HP), match 600s. Run
`python3 tools/point_economy_model.py` to reproduce.

| Action | Value | Path | Base | Lev | Why |
|---|---|---|---|---|---|
| Eliminate a living player | **+4** | — | 3.0s | 1.0 | Baseline. Points come *primarily from killing crew* (owner rule). |
| Repair a sabotaged system | **+6** | Shroud | 0.8s | 6.0 | Highest per effort — one punch denies up to 60 HP. |
| Beacon pressure | **+2 / 10 HP** | Breach | 1.6s | 1.0 | Scales with objective. |
| Gather data | **+2** | Signal | 2.0s | 1.0 | Cheap, repeatable, risky (the info channel). |
| **Forge the Core** | **+19** | Signal | 10.0s | 1.5 | The readable build/commit moment. |
| **Deliver the Core** | **+50** | Signal | 4.0s | 2.0 | THE WIN — a single fast climax, huge reward. |
| Breach (crack enemy beacon) | **+6** | Breach | 4.0s | 1.3 | Aggressive win-progress. |
| Deny (seal/corrupt) | **+4** | Shroud | 2.0s | 1.5 | Defensive denial. |
| Survive a sabotage | **+1** | — | 1.0s | 0.5 | Low direct progress. |
| Evil Ghost | **forfeit all; +0** | — | — | — | The sacrifice, enforced in code. |
| MM essence | **not a score** | — | — | — | Owner rule: essence ≠ points; the core pays +3 essence. |

### 5.2 Per-path audit (the honest test — does any path dominate or grind?)

```
signal   total  54 pts  |  dominant forge  at 35.2%   <- under the bar, good
breach   total  58 pts  |  dominant breach at 51.7%   <- aggressive commit, fine
shroud   total  48 pts  |  dominant deny   at 41.7%   <- defensive commit, fine
```

**What this means:** the forge is the Signal team's win-commitment but it's **under 40%** —
not a grind. Delivery is a real climax (+50, short base). All three paths draw the **same
pool**, so a team cannot do all three; committing starves the others, which is the decision
*and* the enemy's read. kill-only supplies too few points to top the board — a killer must
commit to a path.

### 5.3 Points are strand events (glitch §8) — the three free constraints

Emit point events onto the existing append-only, hash-chained ledger (`settle_run` at
close). Three constraints come free:

1. **No score edits** — the result screen is the checksum readout; admin griefing can
   append a lie, never rewrite a score.
2. **No mid-run scoreboard** — a mid-run score is an *activity oracle* (a sudden +2 tells
   the node someone is crafting). Don't build a read surface for unsettled events.
3. **No-negative-sinks** becomes a one-line validation on the emitter.

### 5.4 Constraints the model must respect
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

### 5.5 What I need to finish this
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
