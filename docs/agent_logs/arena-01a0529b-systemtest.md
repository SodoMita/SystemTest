# Agent log — arena/01a0529b-systemtest — SINGLEPLAYER (Solo Protocol)

**Branch:** `arena/01a0529b-systemtest`
**Date:** 2026-08-30
**Task:** "Council, imagine singleplayer mode for game in this repository.
Assistant agent will do technical tasks." — design + implement singleplayer
for System Looting.

## Council outcome (implemented)

Kept the game's own pillars (identity-ambiguous deception via identical
boxmen, Monster Master horde pressure, single-life death economy) and mapped
the council's Among Us / Horror / TD-Horde / Roguelike brief onto them:

- One operator + 3 identical AI crew on CORE A vs 3 AI rivals on CORE B.
- The Simulation plays Monster Master (wave director, no human MM).
- Hidden **Echo** traitor inside the operator's crew with observable tells:
  internal-only corruption (rival evil-ghost revival suppressed in solo),
  refusal to brawl, core-lurking, early fleeing, witness lines, deflection
  chatter, difficulty-gated endgame hunt.
- Win = purge the Echo; loss = timer / CORE A falls / rivals wiped with the
  Echo alive. Murder of loyal units is legal but logged as guilt.

## What changed

### 1. `mods/game/sl_solo/` — NEW mod (init/director/traitor/crew)
Orchestration layer over `aaa_botmatch` mob mode + `sl_modebase`. No harness
or modebase files modified; everything hooks at runtime:
`botmatch.behave`, `botmatch.on_match_inserted`, `botmatch.attribute_kill`,
mob-body `on_rightclick`, and a load-time wrap of `game_mode.end_match`
(botmatch's telemetry hook wraps the wrapper; chain preserved).

Notable plumbing:
- FakePlayer `punch` bridge (rawset): mode monsters punch bot refs, which
  FakePlayer would silently no-op; bridge routes through
  `botmatch.external_punch` so waves kill AI crew through the real death
  chain (cage, eliminations, reset).
- The Echo sabotages via `game_mode.register_sabotage` — visible marker,
  corrosion, punch-repair, match-end purge all inherited.
- Solo doctrine: `bot.bm.revived_at = -1` for all AI units → no AI evil
  ghosts → CORE A corruption is always the Echo (crisp deduction signal).
- Operator kit: `sl_modebase:scanner` + new `sl_solo:expulsion_baton`
  (fleshy 6 → 4 strikes to purge a 20 hp unit).
- Commands `/solo_start|stop|status|help`; solo HUD line; three difficulty
  presets (`recruit`/`standard`/`nightmare`) driving duration, wave tempo,
  Echo cadence, hunt gate.

### 2. `tests/solo_test.lua` — NEW end-to-end suite (81 assertions)
Boots the REAL `aaa_botmatch` + `sl_modebase` + `sl_solo` on the stub and
drives full solo runs: harness boot, roster math (4/3 split), deterministic
Echo (`sl_solo.traitor_index`), waves, the CORE A corruption tell +
corrosion, guilt ledger, purge → victory report, clean restart into another
difficulty, honest abort reporting, command guards.

### 3. `tests/minetest_stub.lua` — additive engine fidelity
- **Bug fix (found by the new suite):** `get_connected_players` returned the
  live `M.connected` table; the harness appends bots to the returned list →
  unbounded growth → infinite loop in `get_connected_player_names`. Now
  returns a fresh table like the engine. (Smoke suite unaffected: 126/126.)
- Additions for loading the real harness under the stub: `settings:set /
  set_bool`, `get_version`, `get_worldpath`, `find_path`, `get_modpath`
  per-mod lookup (old fallback preserved), richer entity object surface.

### 4. Docs
- `SINGLEPLAYER.md` — council pitch, tells table, difficulty presets, player
  flow, server setup, technical contract, test story, out-of-scope list.
- `MATCH_LOOP_SPEC.md`, `ROADMAP.md` — status entries.
- `settingtypes.txt` — `sl_solo.*` settings; `minetest.conf` — commented
  solo block with the harness settings.

## Verification

- `lua5.1 tests/solo_test.lua` → 81 passed, 0 failed (ran under the lupa
  Lua 5.5 runtime in the sandbox; `unpack`/`loadstring` shims only).
- `lua5.1 tests/smoke_test.lua` → 126 passed, 0 failed (no regressions).
- luaparser syntax pass on all new/modified Lua files.

## Known limits / next candidates
- Uses the deterministic harness arena (WP1 hand-built map still pending).
- No between-run meta progression; no solo formspec terminal (commands only).
- Operator evil-ghost route inherited as-is; balance pass pending.
- Live-engine mob-mode soak for solo (needs a Luanti binary; absent here).
