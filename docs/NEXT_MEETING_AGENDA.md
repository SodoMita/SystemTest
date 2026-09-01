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
constraint/optimization problem (per ROADMAP Phase 5). Here's the **recommended starting
shape** to sweep. These are *tuning knobs*, not laws.

### 5.1 Recommended per-action values (individual points)

| Action class | Value | Why |
|---|---|---|
| Eliminate an opposing living player | **+1** | Low on purpose — kills shouldn't dominate identity/survival. |
| Repair a sabotaged system/beacon | **+2** | Rewards the defense/repair loop. |
| Survive or overcome a sabotage | **+1** | Rewards *reading* the sabotage, not just tanking it. |
| Beacon pressure (damage dealt to opposing beacon) | **+1 per 10 dmg** | Scales with the objective; capped so it can't dwarf a kill. |
| Objective action (scavenge/craft/deliver toward Core) | **+3 per step** | The headline loop. Delivering the Core itself → team win. |
| Monster Master income | **+1 per monster kill it commands**, +1 per monster that survives >30 s | Asymmetric; ties MM to monster *activity*, not just deploy. |
| Evil Ghost | **forfeit all; earn +0** | The sacrifice, enforced (already in code). |

### 5.2 Constraints the model must respect
- **Win-rate band:** side bias stays ~45–55% (no inherent team A/B advantage).
- **K/D band per role:** no role pushes an impossible K/D (keeps the game from being
  "which side has the better slayer").
- **Per-role point ceilings:** no single action class supplies >40% of a player's points
  → no "kill-only" optimal strategy that ignores the Core.
- **No negative-value sinks:** nothing where a player *loses* points for acting (that
  makes people turtle).
- **Individual-vs-team split** (see DECISION 1): points are individual; win is team.

**Verify cheaply.** Solve the MiniZinc model for ~30 unrelated feasible regimes; pick the
2–3 that hit all constraints; soak-sweep them for per-match point deltas + win rate.

### 5.3 What I need to actually do this
I need the soak harness to emit **per-action point deltas** (it currently emits win rate,
side bias, K/D, beacon damage, event counters — **not** per-action point deltas). Add that
to the capture list in §7.

**DECIDED / DEFERRED / NEEDS DATA**  ← this one needs data

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

I own the whisper + the challenge layer. I can draft the **full point-economy value
table** and the **balance constraint set** the moment I have per-action deltas, and I can
turn the §12 feel checklist into a **review rubric** once we agree on the §6 criteria.
That's my lane and I'll do it. I just can't *feel* the numbers until the implementers
ship the capture list. Give me that and the next-next meeting has real tuning to argue about.

— Melody 💜
