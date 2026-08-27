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

## 2026-08-26 — CI diagnosis: syntax gate fails on pre-existing goto files

Local reproduction with a **stock Lua 5.1 build** (same parser class as CI's
`luac5.1 -p`): exactly six pre-existing files fail the syntax gate, all using
LuaJIT-only `goto`:

- mods/apis/sl_gui/achievement_tracking.lua (WP5)
- mods/apis/sl_gui/crafting_system.lua (WP6)
- mods/apis/sl_gui/running_system.lua (WP5)
- mods/content/dialogue/trigger_manager.lua (WP5)
- mods/content/dialogue/yaml.lua (WP5)
- mods/content/sl_scary/init.lua (unassigned content mod)

This explains the failed `soak` run 33021498379 on commit 340c1af and will
fail every push until resolved. Filed as **issue #1** per §7.6 (no cross-WP
patches from this session) with three resolution options; decision belongs to
WP4 (gate) + the owning WPs (files).

All `sl_modebase` files — including this session's scanner — are strict-5.1
clean, and `tests/smoke_test.lua` passes 67/67 under the stock Lua 5.1
interpreter (same runtime class CI uses for that step).
## 2026-08-26 — WP3: cloud-cage containment enforcement

**Claimed:** still WP3. Continuing after the possession work; `tests/**` and
`aaa_botmatch/**` remain untouched (WP4).

**The gap.** `MATCH_LOOP_SPEC.md` says a contained ghost "cannot freely return
to the map during ordinary ghost state" and "may observe the match only
through intentionally limited, designed channels". Nothing enforced either.
`spawn.lua` grants ghosts `fly` + `noclip` (which they need in order to exist
at y=100) and then never checks their position again. The cage built by
`build_cloud_cage()` is an 11x11 glass slab with four corner pylons — no
walls, no ceiling, no floor under most of it. A dead player could fly straight
down and watch the whole match from overhead.

This is the same class of bug as the chat seal that was already fixed: a ghost
is barred from *speaking* to the living, but unrestricted *looking* is an
equally strong information channel — and it is free, which undercuts the
Ghost Altar ritual whose entire design purpose is to make ghost information
cost three rare components.

**Implementation** (`nodes.lua`, ghost section):

- `game_mode.cage_breach_distance(pos)` — pure helper, returns how far a
  position lies outside the cage plus the reason (`horizontal`/`descent`), or
  nil. Exposed so WP4 can assert containment without poking internals.
- `game_mode.is_contained(name)` — the exemption policy in one place.
- `game_mode.return_to_cage(player, reason)` — reposition + rate-limited
  warning (one per 5 s, so a stuck ghost is not chat-spammed).
- `game_mode.containment_step(dtime)` — 1 Hz sweep, wrapped additively onto
  `sabotage_step` like the possession tick, reusing WP2's globalstep.

Chose a **soft leash over a solid box**: a sealed cage would fight noclip,
risk trapping a player on a bad spawn, and need far more committed geometry
than WP1 has built yet. The leash degrades safely — worst case it teleports
someone who was already out of bounds.

**Exemptions** (each maps to a spec rule, verified in the checks below):
altar-summoned ghosts (the designed channel), evil ghosts (map access is the
revival bargain), the Monster Master, all living players, and any time no
match is active.

### Measured

- `tests/smoke_test.lua` — 67/67, unchanged.
- Containment checks (scratch harness): 9/9 — free movement inside, pull-back
  on descent and on horizontal drift, breach helper correctness, and all four
  exemption paths.
- Possession checks re-run after chaining a second wrapper onto
  `sabotage_step`: 16/16, no regression.
- Lua syntax clean.

### Skipped and why

- Soak run — still no Luanti binary in this workspace (env exit code 2); CI
  covers it.
- Tuning `CAGE_RADIUS` / `CAGE_FLOOR_MARGIN` against a real arena: the current
  24 / 12 are sized for the harness arena (cage at y+40). Once WP1 commits the
  hand-built arena these want a balance pass — that is a `balance/*` branch
  per §6, not this one.
