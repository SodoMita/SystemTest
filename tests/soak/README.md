# Soak Test — Live Luanti Server + AI Players

Runs the **real engine** (`luanti --server`) with the `aaa_botmatch` harness.
Simulated players play complete matches through the real `sl_modebase` code
paths — no stubs — while the harness harvests bugs and balance telemetry.

## Run

```bash
python3 tests/soak/run_soak.py                 # 3 matches, seed 1337
python3 tests/soak/run_soak.py --matches 10 --seed 7 --report balance.json
```

Exit codes: `0` pass · `1` test failure · `2` environment error (no engine).

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
