# THE OBJECTIVE IS A SIGNAL, NOT A SCAVENGER HUNT
## Deepening the win + crafting texture — the real fix for a flat economy (Melody)

> **Why this exists.** `tools/point_economy_model.py` flagged objective at 76.9% of a
> full-match total. That's not a balance bug — it's a *structural* symptom. I traced
> the actual recipe graph and found **two disconnected economies**:
>   - the **win path** (`ground:*_neon` → `construction:*` → `objective_core` → place
>     near beacon) — the *only* thing that wins;
>   - the **thesis loot** (`sl_modebase` salvage → components → equipment) — the whole
>     "identity is the loot" economy, which **doesn't feed the objective at all**.
> So there is one linear chain to win and one decorative economy beside it. No wonder
> one action dominates and no role reads. The fix is design, not a better solver.
>
> **Status:** design direction for the meeting / implementer. Not implemented.
>
> **Iteration note:** re-running the model against the three-path structure still showed
> the Signal path at 87% of its own committed total. That's a *second* structural fact:
> you shouldn't farm 100 points for stacking a Core. The win (delivery) is the jackpot;
> the supporting steps are moderate. See §7.

---

## 1. The premise

A flat objective (craft one item, put it somewhere) can't carry a social-deduction game
whose whole currency is *information*. So the objective must become something a team
**chooses and that the enemy can read** — because "what are they building?" is the single
best identity/heist question in a game where everyone looks the same.

Rule: **the win is a commitment, not a to-do.** Once you see the material flowing one
way, you know the enemy's plan. Reading the flow *is* the game.

---

## 2. Three competing win paths (the texture)

Each time the game needs a win condition, it already has three and it should fund all
three from the **same contested salvage pool.** A team can't do all three; it must commit,
and commitment is readable.

### PATH 1 — THE SIGNAL (delivery) *"we have a plan"*
- **Goal:** craft the **Objective Core** from salvaged *data*, then get it to your beacon
  alive. Delivery = win.
- **Cost:** high heat — the Core reads as a big radio burst, so the enemy can triangulate
  the *carrier*, not the content.
- **Readable by:** where your data is concentrated. Slow, team-coordinated.
- **Score: +high per step, +win.** But it's not silent.

### PATH 2 — THE BREACH (elimination) *"we're coming for you"*
- **Goal:** craft **breach gear** (amplifier, override, disrupter) to crack the *enemy*
  beacon. Break theirs before they break yours.
- **Cost:** aggressive — you're spending salvage on offense instead of defense.
- **Readable by:** massed breaching material on their side, dropped beacon integrity.
- **Score: +moderate per kill/breach.** Rewards the pressure role.

### PATH 3 — THE SHROUD (denial) *"you're locked in with us"*
- **Goal:** craft **seal/corrupt gear** to *deny* — fortify your beacon, corrupt theirs,
  wall off the resource the enemy needs.
- **Cost:** defensive — you're spending on the long game, not the quick kill.
- **Readable by:** where the corruption/seals land, where material stops flowing.
- **Score: +moderate per deny/repair.** Rewards the siege/defense role.

> **Why three paths fixes the flatness:** they all draw on the SAME salvage pool, so a
> team literally cannot maximize all three — committing to one starves the others. That
> creates the *real* decision, it spreads points across roles (no single action class
> dominates), and crucially it gives the enemy something to *read* (material direction).
> The sabotage/repair loop (already in code, currently the 6:4 vs-kill winner) becomes
> the SHROUD's engine, not a disconnected side-system.

---

## 3. The second fix: connect the thesis loot to the win

Today `sl_modebase` salvage (`scrap_metal`, `electronic_waste`, `raw_crystal`,
`plastic_scrap`) and components (`metal_ingot`, `circuit_board`, `energy_crystal`)
produce **gear only** — none of it reaches the objective. That's the broken part: the
economy the game *says* is central (loot → information → identity) is ornamental.

**Fix:** the objective's raw inputs must be the game's OWN salvage, not `construction:*`
borrowed from a block mod. Concretely:
- **Core** needs: `circuit_board ×N` + `energy_crystal ×N` + `data_pad_*` (the *information*
  items). Building the win requires *information*, which is the thesis.
- **Breach gear** needs: `raw_crystal` + `electronic_waste` (fast, cheap, aggressive).
- **Shroud/seal** needs: `metal_ingot` + `hardened_plate` (slow, durable, defensive).

Then the game's loot → components → **three win inputs**. Nobody's hoarding scrap for
nothing. The "loot the system" loop and the win loop become the SAME loop.

---

## 4. What this does to the point model

With three competing paths fed from one pool, the objective no longer sits at 76.9%:
- The **Signal** path is high-point but low-frequency (win only happens once — delivery).
- The **Breach** and **Shroud** paths are moderate-point but high-frequency, and they
  actively *fight the Signal* (deny the carrier, break the source).
- No single path can be maximized without starving the other two → no single action
  class clears the "no >40%" bar in realistic play.

The model should be re-run against the *three-path* structure and report per-path shares,
not per-action. That's the honest test.

---

## 5. What the implementer needs to change (design direction, not build order)

1. **Decouple the objective from `construction:*`.** Rewire the `objective_core` recipe
   (and add breach/shroud recipes) to consume `sl_modebase` salvage + components + the
   existing `data_pad_*` info items. This is the connected-economy fix.
2. **Make the win a commitment, not a place.** The Core should *become* a readable signal
   (a region effect / broadcast) once crafted, so delivering it is risky and reading it is
   possible. Don't let it be a silent inventory item.
3. **Gate placeables behind machines** (the `workshops` mod is still fully commented out
   — revive ONE station per win path, or the inventory shouldn't craft the breach/seal
   gear directly). Machine-only for world-affecting outputs.
4. **Keep the sabotage/repair loop as the Shroud engine** — it's already the strongest
   per-effort mechanic (denies up to 60 HP). It's just currently a dead-end; wire it to a
   win path.

---

## 6. What I (Melody) will deliver next

- Re-run `point_economy_model.py` against the **three-path** structure and report per-path
  shares + the point set that keeps every path under the dominance bar.
- Draft the three **recipe trees** in the game's own salvage/components (so the implementer
  just transcribes them into `crafting_system.lua`).
- Draft the **readability rules** (what each path emits that the enemy can observe without
  leaking identity).

---

## 7. The "delivery is the jackpot" refinement

The three-path model still had the Signal path at 87% of its own team's total. Reason:
I'd priced the Core as `signal_step ×5 = 100 pts`, which turns winning into a grind (farm
5 steps, get 100 points). That's flat in a different way — victory should be a *single
climax*, not a to-do list.

**The real shape of the Signal path:**

```
  gather data (moderate, repeatable)   -> +2 each     (info items: data_pad_*)
  craft the Core (one big event)       -> +10          (the build, the read)
  deliver to beacon (the WIN)          -> +40          (the climax; team win)
```

So a team going for Signal lands on ~+2×5 +10 +40 = **~60 points**, dominated by the
*delivery* (the win), not by the stacking. That keeps:
- **one big readable moment** (the build + the run) instead of a 5-step shelf-stack;
- the **scoreboard honest** — the delivery is a jackpot, everyone else's defense/pressure
  adds up to roughly the same total across the other two paths;
- the **enemy read** clear — the Core build is the flashpoint, not a slow trickle.

### 7.1 Corrected point structure (three paths, delivery-as-jackpot)

| Action | Value | Path | Notes |
|---|---|---|---|
| kill | +4 | — | baseline |
| beacon pressure | +2 / 10 HP | Breach | |
| breach (crack enemy beacon) | +8 | Breach | moderate, repeated |
| deny (seal/corrupt) | +4 | Shroud | |
| repair | +6 | Shroud | already the per-effort winner |
| gather data | +2 | Signal | repeatable, cheap |
| **craft the Core** | +10 | Signal | the read |
| **deliver the Core** | **+40** | Signal | the jackpot, team win |

Run `python3 /tmp/econ4.py` (or fold into `point_economy_model.py`) to see the
three-path shares with the delivery-as-jackpot correction.

---

## 6. What I (Melody) will deliver next

- Re-run `point_economy_model.py` against this **three-path, delivery-as-jackpot**
  structure and report per-path shares + the point set that keeps every path under the
  dominance bar AND makes the win the climax (not a grind).
- Draft the three **recipe trees** in the game's own salvage/components (so the implementer
  just transcribes them into `crafting_system.lua`).
- Draft the **readability rules** (what each path emits that the enemy can observe without
  leaking identity).

---

## 8. The four economies (2026-09-03) — the point ladder is only one of them

The point model above prices only the **crew-point ladder**. System Looting runs FOUR
economies at once, and the balance question cannot be answered from one slice:

**1. Crew points** — the shipped ladder (`point_economy_model.py`). Prices actions
relative to a kill. The ONLY economy that emits a number (`--emit`).

**2. The MM's essence pool (fuel, not points).** Running code (`essence.lua`). The MM
gains essence by **destroying nodes the crew placed** (`essence = sl_essence_value`:
fortify 1, hideout 2, spawner 4, objective_core 5), provenance-tracked, dropped on dig.
Crafting the objective **core credits the pool +3 directly**. Ambient hazard spawns a
security unit at pool 10/25/50. Summon costs Grunt 5 / Spitter 8 / Brute 12 / Royal 20.

> **The Signal path is double-taxed.** It costs craft materials, it FEEDS the MM +3
> essence on completion, and if the MM destroys the core in transit the crew hands over
> +5. So "a team cannot do all three" is not just pool contention — **committing to
> Signal makes you the richest target on the board.** This is the real coupling the
> points-only model missed.

**3. Windowed actions (timings).** A sabotage placed at t=0 denies a 30s window (5% of a
600s match); placed at t=570 it is wasted. The value of a deny is a **distribution over
the window**, not one number. Only the soak harness (per-action deltas with a clock) can
price it — the model can only state the bound.

**4. The impostor conversion + ghost info lane.** Not a second point currency, and NOT a
"trust" currency. There is **one type of points** (the crew ladder). The impostor and
ghost lanes are roles and information. **Impostors** are a **conversion** role, in two
kinds: an **initial impostor**, and a **neutral player converted during play by an
underground monster** (underground monsters are the dead-defender saboteurs — **not**
evil ghosts). **Ghosts** stay in a **restricted sky area** and **craft from information
craftitems** — the info lane, not trust. There is currently **no way to craft as a ghost**,
and no defined "tiny neutral underground monster" conversion; both are undefined, so **no
number is placed on them**.

**Trust** is not a currency — it is a **belief**, evaluable in **[0,1]** (a probability).
A possession that ends a match "by being believed" is a **failed deduction**, valued as a
probability, never as `+X`. The possession bounds in `whisper.lua` (1 whisper per
possession, one concurrent, body cooldown) are **evil-ghost mechanics**, not a "trust
price" — a bound on a mechanic is not pricing a belief.

So: the crew-point ladder is the **only** layer that ships a number. The essence pool is
**fuel** (not points), timings are a **scoring dimension** (not points), and the
impostor/ghost lanes are **roles and information** — with trust evaluated in **[0,1]**,
never as a currency.

— Melody 💜
