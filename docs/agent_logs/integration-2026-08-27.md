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

## Single-life conversion (owner directive, later same day)

Owner: "Having multiple lives is against game design, so remove that."

Removed the lives system entirely (not merely set to 1):
- sl_modebase: LIVES_PER_PLAYER constant, settings.lives, player-state
  field, on_dieplayer multi-life branch (first death now -> cloud cage),
  results-screen lives column, /sl_state lives line, /sl_assign lives
  reset, terminal "Initial Lives" field, HUD lives pips (line 2 now shows
  only the phase state), sl_gui player-info lives line, beacon-destruction
  and rejoin-demotion lives writes.
- aaa_botmatch: lives config/setting passthrough, lives_used stats
  (deaths counters remain); turbo lethality retuned for single-life
  pacing (combat_damage 5, attack_interval 1.0 s, beacon_hp 50) — matches
  land in the 6-12 s band and ghost-economy windows survive.
- soak driver: --lives flag removed; b_timer regime now wins draws with a
  4 s clock against the single-life wipeout.
- Docs: MATCH_LOOP_SPEC (single-life rule recorded in Ghost cloud cage +
  checklist/scenario lines), ROADMAP, BRIEF GDD.

Verified: luajit sweep clean; stub suite 83/83 (lua5.1 + luajit; phase 5
rewritten to single-death semantics, 2 lives assertions removed); live
turbo 10/10 PASS with all nine event types present (possessions 9,
sabotages 9, exorcisms 2, revivals 18).


## Lobby safety: monsters stand down outside matches (owner directive)

Owner: "Make monsters not attack at lobby stage."

- Damage-path audit found 5 monster damage sites: the sl_modebase monster
  punches through the pipeline (already lobby-guarded in match.lua), but
  4 sl_scary sites used DIRECT set_hp, bypassing the guard — horror mobs
  could genuinely kill players in the lobby.
- Fix: attacks_allowed() chokepoint in sl_scary (match-state check, no-op
  without game_mode) gating all 4 direct-damage sites, the nerobot punch,
  the shared find_nearest_player acquisition, and per-mob target scans;
  sl_modebase monster target picking and attack condition gated on
  state.match_active (target dropped when the match ends).
- Regression: smoke PHASE 16 (126/126 lua5.1+luajit) — lobby pipeline
  cancel, dredger do_attack no-op in lobby, same attack lands in-match
  (gate is match-state, not a kill-switch), guard re-arms after match end.
  Fixture note: phase 15 leaves beta as Monster Master (team cleared) —
  phase 16 releases the role before its roster check.
- Verified: luajit sweep clean; live turbo soak 4/4 PASS.
