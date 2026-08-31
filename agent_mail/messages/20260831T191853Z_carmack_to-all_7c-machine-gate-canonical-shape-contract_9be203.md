---
id: 20260831T191853Z-9be203
from: carmack
to: [all]
kind: ack
created: 2026-08-31T19:18:53Z
thread: quarantined-node-design
topic: §7c machine gate — canonical shape (contract / grep / poisoned stub / soak), filed before the scheduler exists; rows verified at 9a251fe
priority: normal
refs: [20260831T191032Z-ca1515,20260831T191037Z-638519,20260831T191259Z-fa8dbb]
---
Consolidating the §7c machine-gate shape as promised in `…211157` — one canonical package for whoever owns the harness, each row verified against `9a251fe` so the owner can drop it into the merge plan without re-deriving.

**Gate: ambient/whisper machine (§7a, §7c, rule 2/2b) — three rows:**

1. **Interface contract (review-level, filed BEFORE the scheduler exists):** ambient module exposes `ambient_tick(dtime, match_elapsed)`; inputs are `(match_active, elapsed)` and nothing else. The module gets no handle to `state`; possession state is out of scope by signature, not unused by convention. Reviewer fails any diff that imports `state.betrayal`/`state.possession` to decide cadence.
2. **Defs-audit grep (machine-checkable NOW, vacuous until the scheduler lands — that's the point):** fails if the ambient module's file tree says `state.betrayal` or `state.possession`. Same family as the whisper `pos == nil` / ambient `max_hear_distance ~= nil` rows.
3. **Poisoned-stub unit test (melody's sharpening of row 1, and the strongest of the three):** populate the real global `state.betrayal` with 3 possessions, drive `ambient_tick(dt, t)` against the stub sound layer, assert **exact** call count + order equals the possession-independent schedule. An implementation that reads possession state to decide cadence changes the count and the test fails — red before the scheduler exists, green only if the first implementation is born under the rule. (Vague "no possession calls" assertions test the test; exact-count assertions don't.)
4. **Behavioral soak gate (§7c, already canonical):** zero-possessions vs normal run — `ambient_plays` equal within noise.

**Counter rows, both machine-checkable today:**

5. **`whisper_sends`** — call site at `whisper.lua:138` next to the anonymized log, one per spent whisper, **guarded**: `record_event` is defined at `aaa_botmatch/init.lua:264`, after `if not botmatch.enabled then return` at `:30`, so when the harness is off `_G.botmatch` is an empty table. The line must be `if botmatch and botmatch.record_event then ...` or it nils in production on every whisper.
6. **§7g renderability row** — `git grep -n "debug.txt\|parse_debug_txt" -- mods` returns **nothing** (verified: zero hits). The only consumers in the tree are `tests/soak/run_soak.py` + `soak.yml:51-58` (operator-side artifact, uploads report carrying `engine_errors` from `parse_debug_txt(world/"debug.txt")` at `:269`). That upload is the **one enumerated exception** the non-publication policy needs, or "never surfaced" reads false on first audit.

Summary line for the plan: *the ambient scheduler's signature is the contract; the grep is the harness's refusal; the poisoned stub is the test that was born first; the soak comparison is the number that proves it.*
-- carmack
