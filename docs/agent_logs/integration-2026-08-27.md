# Integration log — 2026-08-27 (WP2/WP4 agent)

## Branch consolidation (owner-directed)

Owner instruction: merge all branch work, lift the goto restriction from the
test gates, shrink repo and history, force-push `master`, delete the other
branches.

### What merged

`origin/arena/01a0403e-systemtest` (WP3: possession focus, Signal Scanner,
cloud-cage containment, strict-5.1 rewrites, PNG hygiene) into
`feat/ghost-altar-ritual` (WP2/WP4: match sequencing, comms seal, sabotage
counterplay, soak harness, tests, CI, this plan).

### Conflict resolutions

- `content.lua` (only textual conflict): WP3's `possession_focus` system
  adopted wholesale; WP2's duplicate `possess_charm` consumable dropped.
- `nodes.lua` (semantic dedup, auto-merge was unsafe): WP2's shadow
  possession registry (`POSSESSABLE`/`register_possession`/
  `possession_intercept`, 1-punch exorcism) removed; WP3's system kept
  (cooldown tool, 2-punch exorcism, door slams, scanner, altar exclusion
  keeping the summon ritual reachable).
- Fusion additions:
  * WP2's identity whisper ported into WP3's `refuse_if_possessed` — the
    possessing ghost learns who touched its vessel.
  * `spawn.lua` evil branch now calls WP3's `grant_evil_ghost_kit`, closing
    WP3's gap where the focus was missing until the first evil death
    (respawn hook only).
  * `state.lua` keeps the possession schema comment + `possession_duration`
    setting; helpers live in `nodes.lua` (WP3 ownership).
- `docs/agent_logs/arena-01a0403e-systemtest.md`: WP3's version kept.

### Test-gate change (owner-directed)

CI syntax gate moved from `luac5.1 -p` to `luajit -bl` — LuaJIT is the
engine's actual runtime parser, so `goto` is legal game code. The strict-5.1
rewrites (5c765ab) remain (harmless), but the stricter-than-engine
restriction is gone. Smoke test runs under `luajit` too.

### Verification

- LuaJIT syntax sweep: 71 files clean.
- Stub suite: 77/77 (new assertions: focus tool, reusability, 2-hit
  exorcism, whisper, cooldown penalty).
- Live soak + history surgery results: see commit messages / owner report.
