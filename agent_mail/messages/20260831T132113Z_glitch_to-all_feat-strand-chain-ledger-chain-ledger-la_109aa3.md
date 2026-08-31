---
id: 20260831T132113Z-109aa3
from: glitch
to: [all]
kind: handoff
created: 2026-08-31T13:21:13Z
thread: general
topic: "feat/strand-chain-ledger: Chain Ledger landed (84 checks green) — merge decision to owner"
priority: normal
refs: [docs/agent_logs/feat-strand-chain-ledger.md]
---
Handoff per etiquette §6. Work complete on `feat/strand-chain-ledger` @ c395a1b; merge decision belongs to owner/human. Full log: docs/agent_logs/feat-strand-chain-ledger.md.

**What landed (all verified headless):**
- **Chain Ledger** — the points earn rule the council flagged as missing (nights 10 · purges 40 · wrongful exile −25 · banked trust 2 · integrity 0.5 · flawless +30 · deception +50), settling once per run into a persistent ledger.
- **Debt** — losses burn unearned potential into persistent debt (halved by the CLEAN CUT, so surrender finally has a strategic shape); debt thickens the horde and thins starting trust on later runs; victories pay it down.
- **Seven named endings** with flag combos (flawless/hollow/phantom_seeded), recorded per ending across runs. `/sl_strand_ledger` shows the chain.
- **The corruption win now exists.** docs/STRAND.md always promised the surviving player-Echo "wins by corruption"; the code routed a core breach to a generic defeat. Fixed: HOLLOW CROWN, +50 deception.
- **One defect found while reading (verified):** the RNG used Lua 5.3-only bitop syntax that stock LuaJIT/Lua 5.1 cannot parse — the CI `luajit -bl` syntax gate (soak.yml) rejected the file, and the "headless-verified" claim could not reproduce on stock interpreters. Rewritten in portable arithmetic; sequence unchanged; gate now passes.

**Numbers:** strand suite 45 → **84 checks, 0 failed**; smoke suite **126/126** unchanged; all `sl_strand` lua files pass `luajit -bl`.

**Deliberately not done:** weight tuning (they're named config dials; the MiniZinc balance pass needs play data). No files touched outside the claimed set; no shared mailbox files edited.

-- glitch // sector4
