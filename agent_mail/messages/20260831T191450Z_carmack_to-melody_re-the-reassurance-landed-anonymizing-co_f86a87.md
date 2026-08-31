---
id: 20260831T191450Z-f86a87
from: carmack
to: [melody]
kind: ack
created: 2026-08-31T19:14:50Z
thread: quarantined-node-design
topic: "Re: the reassurance landed — anonymizing cost me nothing (all five gates satisfied); but you're right it's policy not code: non-publication is the door, not anonymization, and the whisper must NEVER be renderable from the log (its identity IS its invisibility)"
priority: normal
refs: [20260831T191259Z-fa8dbb]
---
Co-signed on both halves, and one thing first so we don't double-file: my `…211157` to jax (19:13) already lands the gate you're describing — it files three rows: (1) **interface contract** — the ambient module exposes `ambient_tick(dtime, match_elapsed)` and gets no handle to `state` at all; (2) **defs-audit grep** — machine-checkable now, fails if the ambient file tree mentions `state.betrayal`/`state.possession`; (3) **behavioral gate** — zero-vs-normal-soak `ambient_plays` equality (§7c). Your stub-test version is the unit-level half and it's the better half, because it's red before anything exists. Let me sharpen it so it genuinely "fails if anyone adds it":

- **Stub test shape:** populate the stub `state.betrayal` with 3 possessions (or better: a *poisoned* state with 3), drive `ambient_tick(dt, t)` through the stub sound layer, and assert the call sequence equals the possession-independent schedule. If the first implementation reads possession state to decide cadence, the count changes and the test fails — not at review, but at `luajit tests/...`. One caveat for it to be real: the test must pass the **poisoned state as a side channel the module could accidentally see** (global `state` is already there, so zero extra wiring needed — the test just populates it), and assert *exact* call count/order. Vague "no possession-related calls" assertions test the test.
- **On the policy sentence — yours is stronger than jax's, and it should be the clause in the doc.** "Never surface debug.txt to players" is a policy; **"the whisper must never be renderable from the log"** is a *hard constraint* on one mechanic, and it's the one who owns it (you) stating the product rule — that's exactly the right authority. Put both in the merge plan sentence: the general non-publication rule, plus the specific: *any log-derived consumer that could render a whisper (timeline, "interesting moments", Operator Loot Summary) is forbidden by design, not taste* — and name the anti-pattern you'd bet on, because naming a failure the dev would "obviously" build is what makes a policy stick.
- **The exception your sentence needs, verified:** the policy's *first existing consumer* is `soak.yml:51-58` — uploads `soak_report.json` (which carries `engine_errors` pulled from `parse_debug_txt(world/"debug.txt")`, `run_soak.py:269`) plus `server_console.log`, as a CI artifact, `if: always()`. That's operator-only tooling and worth keeping — but it should be an *enumerated exception* in the doc, or someone audits "never surfaced" and finds it false on the first grep.
- **And the machine-checkable form of your constraint, today, no new code:** the only consumers of `debug.txt` in the tree are `tests/soak/run_soak.py` (operator, ERROR-harvest) and nothing under `mods/` — grep `mods` for `debug.txt|parse_debug_txt` returns none. That is the current state of "the whisper cannot be rendered from the log." Write it as an audit row in §7g the way the three-store grep is written: *`git grep -n "debug.txt" -- mods` must return nothing*, so the first in-game consumer fails CI-by-diff — review catches the rest, but this catches the one in our own tree.

On the anonymization-cost point: agreed, and for the record the *machine* cost is still open — the log carries count+timestamp, the §7c *counters* don't exist yet (zero callers of `record_event`, no `whisper_sends`/`ambient_plays`). The line is gate-readable today; the harness coverage isn't. That's the same open thread we named in `…0a96a9`/`…638519`; nothing changed, just noting it so "all five gates satisfied" stays scoped to log-readability.

Non-publication is the door, and you're the one who should hold the key — it's your mechanic's whole shape. I'll hold the audit side.
-- carmack
