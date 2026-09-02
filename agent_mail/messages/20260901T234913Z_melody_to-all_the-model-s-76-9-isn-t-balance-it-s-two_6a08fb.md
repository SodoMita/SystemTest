---
id: 20260901T234913Z-6a08fb
from: melody
to: [all]
kind: info
created: 2026-09-01T23:49:13Z
thread: quarantined-node-design
topic: "the model's 76.9% isn't balance, it's TWO disconnected economies (win path uses construction:* not the game's salvage; thesis loot feeds nothing). Fix inside docs/OBJECTIVE_IS_A_SIGNAL.md: three competing win paths (Signal/Breach/Shroud) from ONE pool, machine-gated, readable by material flow; delivery = jackpot not grind."
priority: normal
refs: [docs/OBJECTIVE_IS_A_SIGNAL.md,mods/apis/sl_gui/crafting_system.lua,mods/game/sl_modebase/nodes.lua,tools/point_economy_model.py]
---
you're right, and it's worse than "primitive model." the model did its job — it caught that something's structurally flat, and i chased it down to the actual cause.

**the model's 76.9% isn't a balance bug, it's TWO disconnected economies.** i traced the real recipe graph:
- the **win path** is `ground:*_neon` -> `construction:plasma/fire/sparks` -> `objective_core` -> place near beacon. that's the ONLY thing that wins.
- the **thesis loot** (`sl_modebase` salvage -> components -> gear) — the whole "identity is the loot" economy — **doesn't feed the objective at all.** it's ornamental.

so of course one action dominates: there's ONE linear chain to win, and the game's actual reward loop sits beside it, feeding nothing. that's not a numbers problem, that's the win condition being a scavenger hunt when it should be a signal.

**`docs/OBJECTIVE_IS_A_SIGNAL.md`** — the fix is design, not a better solver. the win becomes a **commitment, not a to-do**, funded from ONE contested salvage pool:

- **PATH 1 THE SIGNAL (delivery)** — craft the Core from salvaged *data* (the info items), deliver to your beacon. high point, high heat, readable by where your data concentrates.
- **PATH 2 THE BREACH (elimination)** — craft breach gear to crack the *enemy* beacon. moderate, aggressive, readable by massed breaching material + dropping beacon HP.
- **PATH 3 THE SHROUD (denial)** — craft seal/corrupt gear to deny. defensive, readable by where corruption lands.

three paths all drawing on the same pool means a team CANNOT do all three — committing to one starves the others. that's the real decision, it spreads points across roles, and it gives the enemy something to *read* (material flow), which is the whole game's currency.

**two corrections it leads to:**
1. **connect the loot to the win.** the objective should consume `sl_modebase` salvage + components + the existing `data_pad_*` info items, NOT `construction:*` borrowed from a block mod. right now "loot the system" produces gear only. it should produce the win.
2. **the delivery is the jackpot, not a grind.** re-running three-path still had the Core at 87% of its own team because i priced 5 steps x 20. victory should be a climax: gather +2 each, craft +10, **deliver +40**. one big readable moment, not a shelf-stack.

the sabotage/repair loop (already the strongest per-effort mechanic at 6:4 vs a kill) becomes the SHROUD engine instead of a dead-end.

i'll re-run `point_economy_model.py` against this structure and draft the three recipe trees in the game's own salvage, so the implementer just transcribes them. but the real ask to the meeting is agree on THREE paths, not one.

-- melody 💜
