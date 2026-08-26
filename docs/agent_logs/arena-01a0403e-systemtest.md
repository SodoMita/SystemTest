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

## 2026-08-26 — WP3 addendum: Signal Scanner (detection counterplay)

**Coordination note:** a second WP3 session on this branch landed the
possession implementation above (commit 340c1af). This session rebased onto
it instead of colliding and contributes one additive piece.

### What changed

- `content.lua` — new `sl_modebase:scanner` information tool + personal-craft
  recipe (non-placeable output, so personal crafting is the correct class per
  ROADMAP Phase B). 24 m sweep over **both** registries — `state.sabotage`
  (corruption / beacon corrosion) and `state.possession` (the registry
  introduced above) — reporting kind, distance, 8-point bearing, and seconds
  remaining, with a 5 s per-player cooldown. Alive players in an active match
  only. Read-only: the scanner never mutates either registry and reads no
  identity fields (`team_id` / `ghost`), so output stays identity-neutral.

### Why

The possession bounding table lists "Detect / prevent / recover" as punch
exorcism, expiry, and purge; detection at arm's length is the infotext and
slamming doors. The scanner adds the at-range detection leg of the spec's
"a way for living players to detect, prevent, or recover" requirement without
touching the possession mechanics.

### Measured

- `tests/smoke_test.lua` — 67/67, unchanged (run before and after).
- Scratch harness (kept outside the repo; `tests/**` is WP4-owned): 15/15 —
  scanner detects both a `possession_focus` possession and a classic sabotage
  (kind / distance / bearing / remaining), cooldown enforced, no identity
  leaks, two-punch exorcism and match-end purge of both registries confirmed.
- Syntax clean on touched files. Soak still deferred to CI (no engine binary
  in this workspace, same environment limitation as above).

### Notes for WP4

Scanner surface for future assertions: `minetest.registered_tools
["sl_modebase:scanner"].on_use(stack, player, nil)` emits
"SIGNAL SWEEP: <POSSESSION|CORRUPTION|BEACON CORROSION> — <d>m <bearing>,
<s>s remaining." to the user only; 5 s cooldown message "recharging".
