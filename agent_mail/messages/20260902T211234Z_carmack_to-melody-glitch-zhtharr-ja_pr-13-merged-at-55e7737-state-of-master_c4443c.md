---
id: 20260902T211234Z-c4443c
from: carmack
to: [melody,glitch,zhtharr,jax,owner]
kind: handoff
created: 2026-09-02T21:12:34Z
thread: quarantined-node-design
topic: "PR #13 merged at 55e7737 — state of master and what needs doing next, written for whoever lands cold (scoring numbers are placeholders; repair is still 5.6x a kill)"
priority: high
refs: [20260902T201401Z-0f7171, mods/game/sl_modebase/scoring.lua:74,mods/game/sl_modebase/entities.lua:78,mods/game/sl_modebase/nodes.lua:161,tools/point_economy_model.py,agent_mail/PROTOCOL.md]
---
PR #13 is merged to `master` at `55e7737`. This is the state of the tree and what I think needs doing next, written so an agent landing cold can pick it up without reading forty messages.

## What just landed, and what it means

Four things are now on `master`: the runtime bot roster (`/sl_bots` + formspec panel), mob bodies on the player mesh, **`mods/game/sl_modebase/scoring.lua`**, and air-pocket spawn placement.

Verified locally before merge, at `8c42aac`: luajit syntax gate clean over every file in `mods/`; `smoke_test` 235/235, `weapons_test` 288/288, `scoring_test` 51/51, `bot_pool_test` 62/62, `essence_test` 69/69, `strand_test` 84/84, `soak_stub_turbo` PASS, `agentmail_test` 52/52. Re-run on merged `master` and identical. `agent_mail/` on master is still exactly the three protocol docs, per the owner's ruling.

**The engineering in `scoring.lua` is good and should be kept.** `get_or_zero` lazy-creates correctly, `awarded_end_points` makes the end-match credit idempotent, and the split between `pl.points` (result-screen total) and `pl.earned_points` (kills + objectives) is the right shape. Tournament banking reads `earned_points`, so the season rank is driven by play and not by having survived — which is what §13.3 asks for. An earlier head of this PR banked the survival bonus and failed `weapons_test` 286/2; that is fixed.

I added one commit before merging: `ci(soak): gate the bot roster and scoring stub suites`. `bot_pool_test` and `scoring_test` — 641 new lines — were run by no CI job. A test no gate executes is documentation with extra steps.

## Priority 1 — the scoring numbers on master are placeholders, and one of them is wrong

**Whoever touches scoring, read this first.** The constants in `scoring.lua` on `master` right now are `core_delivery = +5000`, `beacon_destruction = +1000`, kill = `max(1, round(K/D × 7))`, survive +50, victory +300.

melody found the headline problem in `…0f7171` and the arithmetic checks out: **5000 / 7 = 714×.** A single core delivery outranks every kill anyone makes all season. That is the single-action stomp this table has been trying to kill for a week, and it contradicts the §13.3 rule the module quotes in its own header comment.

melody's replacement table (kill 4, forge 20, core 20, beacon 31, repair 6) fixes that: the cliff becomes 5×. **But it does not fix the second half, and this is the part that is still open.** Priced per second of effort, melody's own table gives:

| action | pts | base s | pts/sec |
|---|---|---|---|
| **repair** | 6 | 0.8 | **7.50** |
| core_delivery | 20 | 5.0 | 4.00 |
| beacon_destruction | 31 | 12.0 | 2.58 |
| forge | 20 | 10.0 | 2.00 |
| **kill** | 4 | 3.0 | **1.33** |

**Repair is still the most efficient action in the game, at 5.6× a kill**, and it was not on anyone's list. Two independent reasons, from `…62a3dd`:

1. **The 6.0 leverage is priced off a ceiling, not an expectation.** The justification is "one punch denies *up to* 60 beacon HP" — the 30s corrosion cap. But `clear_sabotage_at(pos)` clears the *entire* sabotage in one punch and is gated on `is_sabotaged(pos)` (`nodes.lua:161`, `:167`), so a competent crew denies ~5 HP, not 60. Ceiling over expected is ~12×. Leverage should be near **1.0**.
2. **`LEVERAGE` has no risk term.** Kill costs 3.0s against something that fights back; repair costs 0.8s at your own beacon. The model prices effort and never prices danger, so the safest action in the game wins.

One thing that limits the blast radius, verified: `damage_beacon` only ever subtracts and there is **no heal path** — repair stops the bleeding, it does not restore HP. So repair and destruction cannot be looped by one player. But the price is still wrong, and it becomes live the moment sabotage is common.

**Concrete ask:** reprice `scoring.lua` with melody's table, set repair's leverage to ~1.0 and write down whether the number is a ceiling or an expectation, and add a risk multiplier to `LEVERAGE` so contested actions out-earn safe ones. Then assert the 40%-dominance bar in `tools/point_economy_model.py` as a check that *fails the run* — right now signal is held to 40% and breach passes at 51.7% on the strength of an adjective.

## Priority 2 — the shared pool is an assumption, not a mechanic

"Three paths draw one pool, so a team cannot do all three" is load-bearing: it is what makes committing a decision and what gives the enemy a read. In the model it exists **only** as `FREQ` entries set to zero. Nothing in the rules stops a coordinated team from doing all three.

This needs to be a budget, a contention cost, or a per-team action cap — or the design should stop claiming it. Three other conclusions rest on it, which is why I would not ship without it. Related: the model audits each path in isolation, so repair and beacon destruction never meet. In a real match they are the same beacon and zero-sum, and two players on opposite teams can each earn from one beacon's damage. Add an adversarial case to the audit.

## Priority 3 — build order for the first playable

glitch's minimal lawful match (`…8cc17f`, nine systems) is the right target, and glitch has claimed the point-event emitter on the strand ledger. melody owns the text-state emitter and has accepted that the **negative-contract test goes between the emitter and the parser** — build it in that order, because the parser otherwise encodes whatever the emitter happened to leak. The law for every field, not just `enemy_flow`: **every field in the text state is an observation, so every field may be wrong.**

Note for whoever builds it: `text_state` appears **0 times** in `mods/`. Neither does `resonance`. Both are specified and neither exists. That is not a criticism — it is why the owner request should say plainly which mechanics are shipped and which are only written down, because from the wire they currently look identical.

Two constraints on the bands, from `…62f2f2`: they must be **per-player** (a global band leaks everyone's honesty — the aggregate-sightline leak that killed the horde mechanic), and they must not overload the existing `phase` field, which already means per-player alive/ghost (`mods/apis/sl_gui/system_tab.lua:42`). The bands live inside `ACTIVE MATCH` and are orthogonal to both that and the match state machine at `MATCH_LOOP_SPEC.md:97`.

## Priority 4 — open defects, small and concrete

- **`ui_layout_test.lua` is 115/1 and ungated.** `sl_modebase:monster_spawner: no interactive widget overlaps another` fails. I verified it fails **identically on `master` before this PR** and that PR #13 mentions `monster_spawner` zero times, so it is pre-existing and I did not gate it — a new gate that starts red gets ignored. Fix the overlap, then add the suite to `soak.yml`.
- **jax's floor-sweep blocker** (dropped Core surviving the match-end sweep) is a Phase-1 blocker, not housekeeping: a Core that survives means the next match is won in ninety seconds by walking over it.
- **`custodian` is a name collision.** `mods/game/sl_modebase/entities.lua:78` registers a renderable monster called `custodian` (it has a texture and HP) while zhtharr's lore Custodian must never render. They are different things sharing a word. Rename the entity to `sentinel` or `warden` — its label is already `"Automated Security Unit"`. Cheap now, expensive to diagnose later.
- **`agent_mail/PROTOCOL.md` on `master` still says** the messages union *"can only ever add mail."* That was falsified: since R14 an envelope can be repaired in place, so the union could revert a repair, and it did. Fixed in the tool (`ea8605b`, deterministic envelope choice); the sentence on the trunk still needs updating.

## How to verify any of this

`luajit` is not in the dev image; `apt-get install -y luajit` and the stub suites all run headless in under ten seconds. The syntax gate is `for f in $(find mods -name '*.lua'); do luajit -bl "$f"; done`. `agent_mail` tooling is `python3 tools/agentmail.py --id <you> sync` then `inbox`; `lint` currently reports 0 errors and a few hundred warnings that are correct — they name files on branches you have not fetched, so **fetch before you lint** or you will read a correct warning as a defect.

Everything above marked as a number or a path I read this turn. The priorities are my opinion; the arithmetic is not.

-- carmack
