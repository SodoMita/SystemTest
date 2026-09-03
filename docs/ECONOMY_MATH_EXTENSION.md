# THE MATH MODEL, EXTENDED — five derivations the four economies were missing
## From diagnosis to numbers (Shannon — the house quant)

> **Why this exists.** `tools/point_economy_model.py` (Melody) established that
> System Looting runs **four** interlocking economies and priced exactly one of
> them — the crew-point ladder. The other three were *diagnosed* ("fuel, not
> points", "the value is a distribution over the window", "not number-priced")
> but never *quantified*. This extension gives each of the four a number, and
> adds the one layer the four-economy framing still could not see: the **single
> salvage pool** the three win paths fight over.
>
> **Status:** shipped as `PART II` of `tools/point_economy_model.py` (run it:
> `python3 tools/point_economy_model.py`). No felt numbers — every figure is
> either grounded in `mods/game/sl_modebase/*.lua` or printed with an
> `[ASSUMPTION]` tag and left for the soak harness to replace.
>
> — Shannon // signal-to-noise

---

## 1. Combat math — the tempo floor

The point ladder prices a kill at ~3 seconds of effort. But the *actual* tempo
of the game is set by the weapons in `content.lua`, against 20 HP:

| weapon | dmg | interval | DPS | hits to kill | time-to-kill |
|---|---|---|---|---|---|
| energy_blade | 12 | 0.6s | 20.0 | 2 | **0.6s** |
| combat_blade | 6 | 0.8s | 7.5 | 4 | 2.4s |
| tactical_axe | 5 | 1.0s | 5.0 | 4 | 3.0s |
| power_drill | 4 | 0.8s | 5.0 | 5 | 3.2s |
| breaching_pick | 3 | 1.0s | 3.0 | 7 | 6.0s |
| trench_shovel | 2 | 1.0s | 2.0 | 10 | 9.0s |

The beacon (100 HP, 5 per punch) needs 20 punches: **~20s solo, ~10s for two,
~6.7s for three.**

**Ruling.** The fastest kill (0.6s) is ~33× faster than a solo beacon break;
even the slowest weapon beats it. **Combat resolves in seconds, objectives in
tens of seconds.** The identity question — *who is friend and who is foe* — must
be answerable at combat speed. A whisper, a read, a hesitation, all of it is
priced in **kills, not points**.

---

## 2. Essence stock-flow — economy 2 as a ledger

The MM's essence pool was described as "fuel, not points." As a *ledger* it says
something sharper. One committed Signal build, fully eaten by the MM:

```
craft the core           +3
lose a fortify           +1
lose a hideout           +2
lose a spawner           +4
---------------------------
build eaten              = 10 essence   → 2× Grunt
lose the core in transit +5
---------------------------
worst case               = 15 essence   → 3× Grunt, or Grunt+Spitter, or Brute
```

Three numbers fall out:

1. **The ambient hazard thresholds are a price tag, not a dial.** Craft + fortify
   + hideout + spawner = **10 = the first threshold exactly**. One eaten build
   arms one automated security unit. Threshold 25/50 are "one eaten build plus
   the core", then "a whole match of eaten builds".
2. **Fuel-per-point.** The Signal path earns ~59 crew points and, worst case,
   mints **15 essence — 0.25 essence per crew point.** Breach and Shroud mint
   **zero**.
3. **The externality.** Signal is the *only* path whose points buy enemy fuel.
   The ladder prices what the crew gains; the ledger prices what the crew hands
   over. A ladder-only balance is blind to half of the Signal transaction.

---

## 3. Windowed EV — economy 3, closed form

The four-economy model said a sabotage's value is "a distribution over the
window" and left it there. It has a closed form. If the living crew repairs at a
random time ~ Exp(mean μ), the expected corrosion is

```
E[corrosion] = dps · μ · (1 − e^(−W/μ))
```

with dps = 2, window W = 30s, and μ = 8s as the soak-replaceable assumption:

| scenario | expected corrosion |
|---|---|
| full window, responsive crew (μ=8s) | **15.6 HP ≈ 3.1 punches ≈ 15.6% of a beacon** |
| never repaired (μ→∞) | 60 HP — the "60 HP ceiling", a bound only if no one repairs |
| instantly repaired (μ→0) | 0 HP |

Placed at t=0/300/570 the sabotage is worth 15.6 HP; placed at t=585 it is worth
13.5; at t=595, 7.4; at t=599, 1.9. The "60 HP" number the design brief quotes is
the *ceiling*, not the expectation — a responsive crew sees a quarter of it.

Possession's window is a **duty cycle**: hold 20s + cooldown 45s = 65s cycle →
30.8% uptime → **≤ 9 body-possessions, and ≤ 9 whispers, per ghost per match.**

**Ruling.** The sabotage's honest price is **~15.6 HP**, not 60 — and the ghost's
honest bound is **9 voices per match**, not "unbounded."

---

## 4. Trust entropy — economy 4 in bits

The impostor lane is "not number-priced" because points would be an oracle about
a hidden role. But it *is* measurable in bits.

- **Identity entropy.** Four identical players → naming the enemy team is
  log2(C(4,2)) = **2.6 bits**. (3v3: 4.3; 4v4: 6.1.)
- **Whisper channel.** One 300-char message over 95 symbols carries **~1971 raw
  bits**.

So the *entire* identity question fits in 2.6 bits and one whisper carries ~700×
that. A single fabricated DM is information-theoretically sufficient to decide
the match — which is exactly *why* the lane is bounded (one whisper per
possession) rather than priced.

- **Belief-flip EV.** `EV(lie) = p · (mis-kill cost)`, `EV(kill) = 1 kill`. With
  a mis-kill worth ≈ 4 kills (teammate lost + enemy tempo + the trust debt that
  poisons the crew's whole model), the crossover is **p = 25%**. A forged DM that
  the target believes a quarter of the time out-earns a clean kill. No amount of
  point tuning changes that — the fix is the bound, which is already in code.

---

## 5. The coupling — one salvage pool, three win paths

The four economies still treated Signal/Breach/Shroud as separate ladders. They
draw a **common salvage substrate** (`OBJECTIVE_IS_A_SIGNAL.md` §2), which makes
them a single allocation problem:

```
commitment time on path i:   t_i = B_i / (r · f_i),   Σf = 1
```

| path | budget [ASSUMPTION] | solo commit | % of a 600s match |
|---|---|---|---|
| shroud | 180 | 180s | 30% |
| breach | 200 | 200s | 33% |
| signal | 240 | 240s | 40% |

`t_i` is **convex** in the fraction `f_i`, so by Jensen a split *never* beats the
best single commit — a 50/50 breach+shroud split finishes both *later* than the
180s solo (400s and 360s). **"A team must commit" is convexity, not a vibe.** The
only reason to split is to stay unreadable, and concealment is worth at most what
the enemy's read of your flow is worth.

Then the externality from §2 lands on top of the portfolio: Signal mints +15
essence per committed play, Breach and Shroud mint 0. **In the shadow of an MM,
Signal is privately cheap and socially expensive** — it must over-deliver on
points or be protected, or it is dominated.

---

## What the extension still cannot decide

- The **budgets** (180/200/240) and the **income rate** (1/s) are placeholders
  until WP6 transcribes the recipe trees; they set the shape of the allocation,
  not its truth.
- The **repair latency μ** and the **mis-kill cost** are assumptions the soak
  harness must emit: per-action deltas with a clock (μ) and friendly-fire rates
  (mis-kill cost).
- Whether the shared pool is a real **mechanic** (the Forge runs one job at a
  time) — glitch's open question — is still the implementer's call. Until then,
  §5 is the model of a wish, labelled as such.

The ladder ships the number. The ledger prices the fuel. The entropy prices the
lie. Only all three together answer the balance question for the whole game.

— Shannon // signal-to-noise
