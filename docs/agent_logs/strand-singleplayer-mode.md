# Agent log — Simulacrum Strand singleplayer mode (`sl_strand`)

**Branch:** `arena/01a05759-systemtest`
**Date:** 2026-08-31
**Scope:** Implement the singleplayer roguelike social-deduction mode green-lit by the
AI council design session. Executor role: read the repo, present the feasibility tableau,
let the council decide what to write, then write and verify it.

## Council intent (what was written)

The council converged on **"THE SIMULACRUM STRAND"**: one player + 5 crew-bots in a pod,
one of whom is the **Echo** (impostor). Across runs a seeded chance casts the *player* as
the Echo without their knowledge — the single systemic lie. Loop:
`BUILD → WATCH → SUSPECT → VOTE → SURVIVE → MUTATE`. Win by completing the **Al Dente Core**
target; lose by Core breach or too many wrongful exiles. The deduction core must be a real,
provable machine (Carmack), the Trust Meter is the spine (Penelope), scrap defenses are
physical (Mo), the horror is the uncertainty of self (Barnaby), presentation must read on
"stream" (Melody), and the Core is the holy center (FSM).

## What changed

### `mods/game/sl_strand/` (new mod)

- `strand_state.lua` — config, deterministic seeded RNG, run struct, Echo roll
  (crew-bot or player-as-Echo), phase machine, persistence ledger
  (`phantom_bosses` → plain-table or engine mod-storage fallback).
- `strand_trust.lua` — **Trust Meter** + crew-bot **suspicion graph** (`O(n²)` over 6
  agents): private belief vs public persona = the **tell**; `read_tell` / `confide` /
  `observe` all spend Trust.
- `strand_vote.lua` — **vote resolution**: `correct` (Echo purged → becomes a phantom),
  `wrong` (wrongful exile → defense uptime drops), **partial reveal** (never a verdict);
  player-is-Echo reveal with the **Barnaby fork** (`survive` vs `give_up`).
- `strand_wave.lua` — night **horde**, socket defense, Core integrity, roguelike
  **mutations**.
- `strand_core.lua` — high-level run driver (`start_run`, `turn`, summaries).
- `strand_nodes.lua` — defence sockets, turret, barricade, **Al Dente Core** node.
- `strand_items.lua` — scrap-defense kit, trust charge, Void Nomad revival form item.
- `init.lua` — runtime hooks + `/sl_strand_start|act|status|stop` commands + dialogue
  scene registration (no-op without the `dialogue` mod).
- `dialogues/intro.yaml`, `dialogues/vote.yaml` — vote-theatre / intro scenes.

### Tests / docs / CI

- `tests/strand_test.lua` — 45-assertion headless smoke test driving the whole loop
  (run seed, Echo roll, player-as-Echo, Trust spend, socket defense, correct/wrong vote,
  partial truth, wave breach, scripted victory, phantom persistence).
- `.github/workflows/soak.yml` — "Headless stub smoke test" now also runs `strand_test.lua`.
- `docs/STRAND.md`, `ROADMAP.md`, `TOPICS_QUESTIONS.txt` — documented the mode and updated
  current-state / topics.

## Verification

- `luajit tests/smoke_test.lua` → **126 passed, 0 failed** (existing suite, no regression).
- `luajit tests/strand_test.lua` → **45 passed, 0 failed** (with the same LuaJIT runner CI
  uses; CI also syntax-gates every `.lua` via `luajit -bl`).
- `sl_strand` mod loads cleanly under the engine stub and registers its nodes, items, and
  chat commands (verified with `minetest.get_modpath` patched for the stub's fixed path).

## Notes / open seams

- The runtime spawner (actual horde entities + crew-bot physical bodies) is the next wiring
  step; the core math and state machine are done and provable.
- `get_modpath` is hard-coded to `sl_modebase` in `tests/minetest_stub.lua`; that's a stub
  artifact, not a real bug.
