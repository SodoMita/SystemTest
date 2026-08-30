# SYSTEM LOOTING — SINGLEPLAYER: "SOLO PROTOCOL"

> **Design revision — August 2026.** Singleplayer is a mode of the existing
> match loop, not a second game. One human operator is inserted through the
> REAL pipeline (ready check → countdown → insertion → rules) alongside a crew
> of identical AI salvage units. The Simulation itself plays the Monster
> Master with escalating horde waves, and one unit on the operator's own crew
> is secretly **the Echo**. Purge it before the clock runs out.

The mode lives in `mods/game/sl_solo/` and is an orchestration layer over two
systems this repository already ships:

- [`aaa_botmatch`](mods/game/aaa_botmatch) in **mob mode** — the embodied
  AI-player harness: boxman bodies identical to real players, A* pathfinding,
  damage routed through the real `on_punchplayer` pipeline, full rule parity
  (teams, lives, phases, chat seal, sabotage, possession).
- [`sl_modebase`](mods/game/sl_modebase) — match state machine, beacons,
  sabotage/corrosion, ghost economy, HUD, results, clean reset.

No harness code was modified. `sl_solo` wraps runtime hooks (`botmatch.behave`,
`botmatch.on_match_inserted`, `botmatch.attribute_kill`, mob-body
`on_rightclick`) and `game_mode.end_match` at load time, the same way the
harness itself hooks `game_mode`.

---

## The pitch (council session)

- **Deception:** faces are worthless by design — every unit is the same neon
  boxman, nametags are globally hidden. The Echo is one of YOUR three crew
  units; you learn who is who by tracking behavior, positions and radio
  handles (`UNIT-A`, `UNIT-B`, …; rivals are `UNIT-X/Y/Z`).
- **Horror:** the Simulation speaks in wave announcements and plays the
  Monster Master role itself — no human MM, no spawner unit, no essence.
  Waves of `sl_modebase` monsters plus `sl_scary` horror entities escalate
  around both cores and the midfield altar.
- **Tower defense horde:** beacons are the towers-that-matter. Corruption,
  corrosion, repairs and destruction all flow through the existing WP3/WP2
  systems — waves pressure CORE A and CORE B alike.
- **Roguelike run shape:** a protocol is a bounded run with three difficulty
  presets, a results report, and an immediate clean restart at a higher
  difficulty. Permadeath rules are inherited unchanged: first death → cloud
  cage; the AI dead stay dead.

### The tells (the deduction surface)

The Echo is never announced. It is only observable:

1. **Corruption on CORE A is always the Echo while it lives.** Solo doctrine
   suppresses AI evil-ghost revival entirely, so no rival evil ghost can ever
   fake this signal. (The human operator may still revive as an evil ghost —
   that choice is theirs, per the core design.)
2. **It refuses to brawl.** It drifts away from rival crew instead of
   engaging; loyal units push the objective.
3. **It loiters** on a 6 m ring around its own core and at the midfield
   crate — close enough to look busy, far enough to look wrong.
4. **Cowardice:** it flees hostiles at 7 m, while loyal units stand and punch
   at melee range.
5. **Witnesses:** each sabotage has a 50 % chance that a nearby loyal unit
   names the lurker on the radio; if YOU are within 18 m you glimpse the
   designation yourself.
6. **Deflection:** its chatter blames the machines, or you.
7. **The hunt:** past a difficulty-gated fraction of the clock (standard:
   70 %), a living Echo stops pretending and attacks the crew.

### Resolution

- **Kill the Echo → protocol COMPLETE.** Its death unmasks it publicly, the
  run ends in a victory report (waves survived, sabotages, loyal kills).
- **Timer expiry / CORE A destroyed / rival crew wiped while it lives →
  protocol FAILED** ("the Echo walked out amid the carnage").
- **Kill a loyal unit** and the simulation logs your doubt — and your crew is
  one defender poorer. Murder is legal; it is just expensive.

### Difficulty presets

| Preset | Duration | Waves | Wave gap | Echo sabotage window | Hunt after |
|---|---|---|---|---|---|
| `recruit`  | 420 s | 4 | 70 s | 55–95 s | never |
| `standard` | 540 s | 6 | 60 s | 45–80 s | 70 % of clock |
| `nightmare`| 660 s | 9 | 50 s | 35–60 s | 45 % of clock |

Wave composition escalates: stalkers from wave 1, scouts/brutes/dredgers,
signal wraiths, and containment horrors later; per-wave cap 6/9/12.

---

## Player-facing flow

```text
JOIN SOLO WORLD  ->  crew waiting in the lobby (6 identical boxmen)
/solo_start [recruit|standard|nightmare]
  -> ready check (bots auto-ready) -> countdown -> INSERTION
  -> you anchor CORE A with 3 crew units; 3 rivals hold CORE B
  -> waves begin (~35 s in); the Echo starts corruption windows
  -> /solo_status, /solo_help anytime; right-click = prox-scan designation
  -> purge the Echo (4 baton strikes) -> victory report
  -> /solo_start again, harder. The dead stay dead. Faces tell you nothing.
```

Commands: `/solo_start [difficulty]`, `/solo_stop`, `/solo_status`,
`/solo_help`. The operator kit at insertion: **Signal Scanner**
(`sl_modebase:scanner` — sweeps corruption/possession, never identities) and
the **Expulsion Baton** (`sl_solo:expulsion_baton`, 4 strikes to purge).

## Server setup

Solo runs on a local (or any) server with the embodied-AI harness enabled.
Add to the world/server settings and restart:

```text
sl_botmatch.enabled = true
sl_botmatch.mob_mode = true
sl_botmatch.auto_start = false      # bots wait in the lobby for YOU
sl_botmatch.disconnect_test = false # no fake mid-run disconnects
sl_botmatch.bots = 6                # >= 4 required; 6 recommended
```

The game bundle ships these as a commented block in `minetest.conf`, and
`sl_solo.*` options are documented in `settingtypes.txt`. Without the
harness, `/solo_start` refuses politely and `/solo_help` explains the setup.

---

## Technical contract

### Ownership & load order

- `sl_solo` depends on `sl_modebase`; the `aaa_botmatch` harness loads first
  by its `aaa_` prefix and is gated by its own settings.
- `sl_solo` is inert without the harness: it registers commands, explains
  setup, and touches nothing else.

### Runtime hooks (installed lazily, once each)

| Hook | Purpose |
|---|---|
| `botmatch.behave` wrap | per-bot: the Echo's custom AI; combat reflex after default behavior |
| `botmatch.on_match_inserted` wrap | roster, designations, Echo selection, operator kit, director arming |
| `botmatch.attribute_kill` wrap | PvP kill attribution → guilt ledger + death reports |
| mob-body `on_rightclick` wrap | badge scan (proximity-gated designation reveal) |
| `game_mode.end_match` wrap (at load) | classify → cleanup → report; botmatch's telemetry hook wraps this wrapper, preserving the chain |

### Damage & death paths kept real

- Operator → suspect: engine punch → mob body `on_punch` →
  `botmatch.external_punch` → registered `on_punchplayer` handlers.
- Monster → bot: mode monsters punch bot refs (`p:punch`), which a FakePlayer
  would drop; `sl_solo.install_punch_bridges` rawsets a bridge that routes the
  damage through `botmatch.external_punch`, so waves can kill AI crew through
  the real death chain (cloud cage, eliminations, clean reset).
- `sl_scary` mobs already apply damage directly (`set_hp`) — unchanged.
- Sabotage: the Echo calls `game_mode.register_sabotage` directly — same
  visible marker, corrosion ticks, punch-repair counterplay, match-end purge.

### Files

| File | Role |
|---|---|
| `mods/game/sl_solo/init.lua` | state, config/presets, commands, HUD, harness hooks, win/loss, report |
| `mods/game/sl_solo/director.lua` | the Simulation: wave composition, spawning, hostile scans, cleanup |
| `mods/game/sl_solo/traitor.lua` | the Echo: behavior, sabotage, witnesses, hunt, death reveal |
| `mods/game/sl_solo/crew.lua` | roster/designations, chatter, badge scan, combat reflex, damage bridge |

### Tests

`tests/solo_test.lua` (81 assertions) boots the **real** harness + modebase +
solo on the engine stub and drives full runs end to end: roster math, hidden
Echo selection (deterministic via `sl_solo.traitor_index`), wave deployment,
the CORE A corruption tell, corrosion, guilt ledger, purge → victory report,
clean restart into a second difficulty, abort reporting, and command guards.
It also fixed one stub fidelity bug: `get_connected_players` now returns a
fresh table like the engine (the harness appends to the returned list; the
live-table version looped forever).

```bash
lua5.1 tests/solo_test.lua    # singleplayer end-to-end
lua5.1 tests/smoke_test.lua   # core match loop (126 assertions)
```

Deliberately out of scope for the first cut (candidates for the next run):
solo-specific map (the deterministic harness arena is used), unlock/meta
progression between runs, operator evil-ghost balance pass, and a formspec
Solo terminal node for mouse-driven launches.
