# Agent log — Chain Ledger for `sl_strand` (`feat/strand-chain-ledger`)

**Branch:** `feat/strand-chain-ledger` (forked from `agent-comms` @ `ad99485`)
**Date:** 2026-08-31
**Executor:** glitch (Arena.ai Agent Mode). Claim posted in-band before edits
(`20260831T131257Z-a2a492`).

## Task

Operator-set: improvement of singleplayer mode. Scope chosen from the council's own
open questions in `TOPICS_QUESTIONS.txt` (items 3–5: no points earn rule, no debt
economy shape, no ending flag combos) plus one verified spec/code gap found while
reading: `docs/STRAND.md` documents a corruption win for the surviving player-Echo
that the code never implemented — a core breach routed everyone, Echo included, to a
generic defeat.

## What changed

### New: `mods/game/sl_strand/strand_ledger.lua`
- `score_run` — the earn rule: nights ×10, correct purges ×40, wrongful exiles −25,
  banked Trust ×2, remaining integrity ×0.5 (victories), flawless +30, deception +50.
  Pure, integer, deterministic.
- `settle_run` — idempotent single settlement per run; banks score, burns/pays debt,
  records named ending + flags into the persistent ledger.
- Debt rule: loss burns `remaining_nights×10×0.5 + wrongful_exiles×5` (cap 60);
  CLEAN CUT burns at half rate; victory pays half its score against debt.
- `apply_debt` — start-of-run pressure: horde +0.2/point, starting Trust −1 per 10
  (cap −3).
- `ending_for` + `strand.ENDINGS` — seven named endings; flags hollow / flawless /
  phantom_seeded layer on top.
- `ledger_summary` returns snapshots, never live references (caught by the tests).

### Edits
- `strand_state.lua` — ledger weights in config; `correct_purges` in run state;
  `run_victory(run, reason)`; every terminal path settles (`run_victory`,
  `run_defeat`, the `advance_phase` victory edge); player-Echo phantom recorded into
  `phantom_bosses_this_run` so the `phantom_seeded` flag is truthful.
  **Portability fix:** `xor32` rewritten in plain arithmetic. The old version used
  Lua 5.3 bitop syntax (`~`, `<<`, `>>`) that stock LuaJIT and Lua 5.1 cannot parse —
  `luajit -bl` (the CI syntax gate per `.github/workflows/soak.yml`) rejected the
  file, so the documented headless verification could not reproduce on stock
  interpreters. The RNG sequence is unchanged (seed-pinned determinism checks pass).
- `strand_vote.lua` — purge/wrongful-exile now feed the ledger (`correct_purges`,
  `phantom_bosses_this_run`).
- `strand_wave.lua` — horde scale includes debt pressure; a revealed, surviving
  player-Echo who breaches the Core now **wins by corruption** instead of losing by
  breach (HOLLOW CROWN).
- `strand_core.lua` — `start_run` applies debt; `run_summary`/`describe_run` carry
  ending, score, ledger, debt.
- `init.lua` — loads the ledger; `/sl_strand_act` prints the settlement on run
  close; `/sl_strand_status` shows the chain line; new `/sl_strand_ledger` command.

### Tests
`tests/strand_test.lua` +39 checks (45 → 84, all green): earn-rule math, deception
bonus, ending mapping for every terminal state, flag combos, victory banking and
debt paydown, defeat burn arithmetic, CLEAN CUT half-burn, debt→horde/trust
pressure, end-to-end corruption win, ledger persistence across storage reload,
idempotent settlement, summary surfaces. `tests/smoke_test.lua` 126/126 unchanged.
All `sl_strand` lua files pass `luajit -bl`.

## Verification

```
luajit tests/strand_test.lua   # RESULT: 84 passed, 0 failed
luajit tests/smoke_test.lua    # RESULT: 126 passed, 0 failed
for f in mods/game/sl_strand/*.lua; do luajit -bl "$f" >/dev/null; done
```

## Not done (deliberately)

- Balance tuning of the weights (they are named config dials; a MiniZinc/optimizer
  pass over regimes is the council's item, and needs play data).
- No changes to `mods/` outside `sl_strand`, none to shared mailbox files.
