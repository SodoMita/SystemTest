# Agent log — `arena/01a0403e-systemtest`

Append-only, per `AGENT_PARALLEL_PLAN.md` §7.4.

## 2026-08-26 — WP3 claim: evil-ghost possession of objects

**Claimed:** WP3 — Ghost systems (`sl_modebase/nodes.lua` altar/ghost sections,
`content.lua` ritual/sabotage items). WP4 (`tests/**`, `mods/game/aaa_botmatch/**`,
`test_harness.lua`, `.github/workflows/**`) left untouched — another agent owns it.

**Why this item:** it is the only WP3 entry left in the `MATCH_LOOP_SPEC.md`
"Still open (Phase A remainder)" list — *"Evil ghost possession of objects
(only node sabotage exists so far)"*.

### What changed

- `content.lua`
  - new tool `sl_modebase:possession_focus` (evil-ghost only, reusable —
    bounded by cooldown, not by consumption).
  - `game_mode.grant_evil_ghost_kit(player)` tops up the focus without editing
    WP2's `spawn.lua`; re-issued on respawn and on revival.
- `nodes.lua` (ghost section)
  - possession registry `state.possession` + API: `possess_object`,
    `is_possessed`, `get_possession`, `release_possession`,
    `clear_all_possession`, `is_possessable`, `possession_step`.
  - guard wrapper applied to every possessable node's `on_rightclick` at
    `register_on_mods_loaded`, so possession denies use without each node
    definition knowing the rule.
  - punch-to-exorcise handler; door/hatch slam tick.
  - `clear_all_sabotage` and `sabotage_step` are wrapped additively, so
    possession reuses WP2's existing purge and globalstep call sites rather
    than adding a cross-package hook (no contract-v1 signature changed).

### Spec compliance — the four bounding rules for evil-ghost powers

| Spec requirement | Implementation |
|---|---|
| Visible / discoverable cause | infotext flips to `OBJECT POSSESSED`, `sl_possessed_until` in meta, neutral broadcast, doors/hatches slam every 3 s |
| Cooldown or resource limit | one concurrent object per ghost; 20 s duration; 45 s cooldown; +30 s on exorcism |
| Clear interaction rule | evil ghost only, active match only, allowlisted objects only |
| Detect / prevent / recover | living punch twice to exorcise; auto-expiry; purge at match end |

Beacons are deliberately **not** possessable (that is the sabotage charge's
job) and the Ghost Altar is excluded so the summon ritual can never be locked
out — an unreachable mechanic would show up as a zero event counter in the
nightly sweep (§6).

Identity neutrality: the possession broadcast names no player and no team.

### Measured

- `tests/smoke_test.lua` — 67/67 pass, unchanged (no regression).
- Ad-hoc WP3 verification (scratch harness, not committed — `tests/**` is WP4's):
  19/19 possession assertions + 6/6 evil-ghost loadout assertions, covering
  each row of the table above plus clean reset.
- Lua syntax check clean on all touched files.

### Skipped and why

- **Soak run** (`tests/soak/run_soak.py --matches 3`, DoD §3.3) — no Luanti
  engine binary in this workspace, so the driver exits with environment code 2.
  CI runs it on push; flagged here rather than silently omitted.
- **Bot coverage of possession** in `aaa_botmatch` — WP4-owned. The behavior is
  reachable via `game_mode.possess_object(pos, name)` for whoever adds it.
- `tests/smoke_test.lua` assertions for possession — same reason; the API above
  is the surface to test against.
