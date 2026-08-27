# Soak Test — Live Luanti Server + AI Players

Runs the **real engine** (`luanti --server`) with the `aaa_botmatch` harness.
Simulated players play complete matches through the real `sl_modebase` code
paths — no stubs — while the harness harvests bugs and balance telemetry.

## Run

```bash
python3 tests/soak/run_soak.py --turbo                  # ~5 s per match
python3 tests/soak/run_soak.py                          # realistic clocks
python3 tests/soak/run_soak.py --turbo --matches 10 --seed 7 --report bal.json
```

Exit codes: `0` pass · `1` test failure · `2` environment error (no engine).

### Turbo profile (`--turbo`)

Bases are placed **next to each other** (`beacon_spacing = 4`), beacon HP
drops to 20, swings land every 0.5 s, respawn takes 0.5 s, countdown is 1 s.
Same code paths, compressed clocks: **matches resolve in ~5 s** (measured:
4.4/5.4/6.1 s). Every individual setting still overrides the profile
(`sl_botmatch.beacon_spacing`, `.attack_interval`, `.combat_damage`,
`.respawn_delay`, `.countdown`, `.beacon_hp`).

### Mob mode (`--mob`) — playtest with a human admin

Bots get **physical entity bodies with engine pathfinding** (A* via
`minetest.find_path`), the same player model/texture as real players,
real collision and gravity while alive, flight while ghostly. They are
punchable by the admin — damage routes through the same `on_punchplayer`
handlers as any combat — and every rule (teams, lives, phases, chat seal,
rituals, sabotage, possession) applies to them identically.

- **With `--mob` in the driver** (`auto_start`): fully headless soak of the
  mob mode itself.
- **For manual playtesting**, enable in server config without auto_start:

  ```
  sl_botmatch.enabled = true
  sl_botmatch.mob_mode = true
  ```

  Join as admin, then `/sl_match_start` — bots auto-mark ready, countdown,
  insertion. You are the only human; bots fill both teams and play the full
  loop around you. Punch a mob to fight it; it pathfinds, dies, ghosts,
  revives, and sabotages exactly like a player would.

Requirements: a Luanti/Minetest server binary (`luanti`, `minetest`,
`--engine PATH`, or `$LUANTI_BIN`) and Python 3.8+.

## What the bots exercise

| Spec scenario | Mechanism |
|---|---|
| Insertion | ready check → countdown → team spawns |
| Scavenge / move / combat | runner + brawler roles, PvP through the real `on_punchplayer` chain |
| Lives / death transitions | deaths through the real `on_dieplayer` handler |
| Ghost cloud cage | ghosts contained at `ghost_spawn` |
| Summoning | carrier walks to the Ghost Altar with the ritual kit |
| Ghost information | summoned ghost runs the real `/sl_ghost_offer` |
| Evil ghost | revival, bounded sabotage of beacons |
| Sabotage counterplay | living bots punch-repair corrupted nodes |
| Disconnect / reconnect | one scripted drop per match |
| Match end + clean reset | elimination or timer, then restart without stale state |

## Outputs

- `botmatch_stats.json` in the world dir — per-match and aggregate telemetry.
- Console report — win rates, **side bias** (|bias| < ~0.34 acceptable at
  n=3; use ≥ 30 matches for balance conclusions), K/D, beacon damage,
  phase funnels, event counters.
- Bug harvest — every Lua error during simulated play is pcall-caught by the
  harness (`[botmatch][BUG]` lines + `stats.bugs`); raw engine `ERROR` lines
  from `debug.txt` are collected separately. Any occurrence fails the run.

## Balance loop

Seed sweeps feed the balance work package:

```bash
for s in 1 2 3 4 5 6 7 8; do
  python3 tests/soak/run_soak.py --matches 5 --seed $s --report bal_$s.json || true
done
```

Watch: side bias drift, average duration vs `match_duration` cap (all draws
means combat is too passive), `kills/deaths` ratio, event coverage
(`ghost_summons`/`sabotages` at zero across many matches means a mechanic is
unreachable — a design bug, not a test bug).

## How the harness works (and its limits)

`aaa_botmatch` loads before all mods (the `aaa_` prefix), wraps the callback
registration functions, and replays collected handlers for its simulated
players — so mod logic runs exactly as it would for real clients. Player
lookups (`get_player_by_name`, `get_connected_players`,
`get_player_information`) are routed through the bot registry.

Limits, by design: no real network clients (protocol, media transfer, and
client-side rendering are untested), no formspec interaction, and handlers
registered by the engine builtin itself are only partially covered.
