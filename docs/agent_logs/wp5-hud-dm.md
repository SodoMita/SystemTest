# Agent log — WP5 HUD & UI — Waiting HUD + Secure DM

**Branch:** master (local WP5 claim)
**Date:** 2026-08-27
**Claimed:** WP5 — HUD & UI (`sl_modebase/hud.lua`, `mods/apis/sl_gui/**`)
**Why:** Active branches `arena/01a04377-systemtest` and `arena/01a0436b-systemtest` both occupy WP7 Assets (horror mobs + spawner GUI). WP1, WP2, WP4, WP5, WP6, WP8 remain unclaimed. WP5 "Waiting for Players HUD" is listed as open in ROADMAP Phase 4 and MATCH_LOOP_SPEC still-open list (DM UI polish + reconnect hardening).

## What changed

### 1. `mods/game/sl_modebase/hud.lua` — Waiting for Players HUD + Reconnect Hardening

- **Added 2 HUD elements** (now 5 total, smoke test checks >=3):
  - `lobby` at 0.5,0.90 — cybernetic standby readout: `WAITING FOR PLAYERS: X/Y // INSUFFICIENT BIO-SIGNATURES // BEACON LINK: STANDBY` or `READY // BEACON LINK: STANDBY // USE TERMINAL OR /sl_match_start TO INITIATE SEQUENCE`
  - `ready` at 0.5,0.12 — ready-check detail: `READY CHECK: X/Y BIO-SIGS CONFIRMED // AWAITING NEURAL LINK` or `NEURAL LINK: X/Y CONFIRMED // INSERTION T-Xs`
- **Identity-neutral:** only counts and public hints, no team names/colors. Beacon integrity still public (CORE A/B).
- **Reconnect hardening:** on_joinplayer now clears stale HUD IDs, rebuilds HUD eagerly, and sends private reconnect notice:
  - If match active: `RECONNECT: Neural link re-established. Match #N active. HUD synchronized.`
  - If lobby: `RECONNECT: Lobby link synchronized. Awaiting initiation sequence.`
- **Exposed** `game_mode.update_hud` and `game_mode.build_hud` for external refresh (e.g., after reconnect, for tests).
- **Preserved** existing 3 elements (status, vitals, beacons) so smoke test still passes.

### 2. `mods/apis/sl_gui/dm_system.lua` — Secure Neural Link DM System (new)

- **Core dispatch** `send_dm(sender, target, message)`:
  - Living-only: ghosts/evil_ghosts blocked (sealed per MATCH_LOOP_SPEC "Ghost cloud cage")
  - Private: only sender and target receive ` [SECURE LINK] You -> X: msg` / `X -> You: msg`
  - Cybernetic styling: colored prefixes (#00ffff sender, #ffaa00 target, #ffffff msg)
  - Anti-spam cooldown 0.8s, max length 300 chars, trim fallback for stub
  - Logs to server log for moderation, not broadcast
- **Commands:**
  - `/sl_dm <player> <message>` — primary
  - `/sl_whisper`, `/sl_w` — aliases (familiar to players)
  - `/sl_dm_ui`, `/sl_comms` — open secure link terminal formspec
- **Formspec** `sl_gui:dm`:
  - Textlist of alive player bio-signatures (excludes self, excludes ghosts)
  - Field for message, TRANSMIT and CLOSE buttons
  - Lore: `LOBBY COMMS: Use for trust, deception, coordination. Ghosts cannot intercept.`
  - State table `dm_ui_selection` tracks selected target per sender
- **Ghost guard integration:** sl_gui loads after sl_modebase, so `commands.lua` wraps all commands on `register_on_mods_loaded`. Ghosts automatically blocked from DM commands (no need to add to allowlist). Additional explicit check in `can_use_dm`.
- **Exposed** for smoke test: `game_mode.send_dm`, `game_mode.get_dm_formspec`

### 3. `mods/apis/sl_gui/init.lua`

- Added `dofile(modpath .. "/dm_system.lua")` after outfit menu, before final log line.

## Spec compliance

| Spec requirement | Implementation |
|---|---|
| HUD must never leak team/role | Only counts, CORE A/B HP (public), no team names/colors |
| Waiting for Players HUD when match not active | lobby element shows connected/bio-sig count vs min 2, standby status, initiation hint |
| DM UI intentional social mechanic | Private secure link, living-only, formspec + chat commands |
| Ghost chat locked | Ghosts blocked from sending and receiving DMs (seal) |
| Reconnect hardening | HUD rebuild on join, private reconnect notice, stale ID clear |

## Measured

- `luajit -bl` on all `mods/**/*.lua` — **SYNTAX OK**
- `lua5.1 tests/smoke_test.lua` — **80/80 PASS** (HUD now 5 elements, still identity-neutral, MATCH # and CORE A/B present)
- Ad-hoc DM harness `/tmp/test_dm2.lua` — **PASS**: living DM delivers to both parties, ghost blocked with "Ghost communications are sealed.", formspec builds.
- No new identity leaks: checked HUD texts for "Beacon A"/"beacon_a" — none.

## Skipped and why

- **Soak run** `tests/soak/run_soak.py --matches 3` — no Luanti engine binary in this workspace; CI runs it on push per AGENT_PARALLEL_PLAN §3.3. Flagged, not silently omitted.
- **Unified inventory tab for comms** — considered adding 4th tab "Comms" to `unified_inventory.lua`, but that would touch inventory UI owned by WP5 yet risk colliding with ability/crafting tabs. Kept DM as separate terminal formspec (`/sl_dm_ui`) for minimal collision. Can be promoted to tab in follow-up branch if desired.
- **Worlds/soak_arena committed arena** (WP1) — unclaimed but requires map.sqlite generation via engine; left for WP1 agent to avoid file-ownership collision (worlds/* is WP1-owned).
- **Monster Master income system** (WP2/WP6) — also unclaimed, but WP5 was higher leverage for social layer (M3 milestone: DM UI + reconnect pass).

## Next steps for integration

- Merge train: rebase on `integration`, open PR, CI will run syntax + stub + soak (3 matches).
- WP4 to add smoke assertions for DM: living DM succeeds, ghost DM blocked, formspec contains player list.
- WP2 to consider wiring DM unread indicator into HUD (optional).
- WP8 to update MATCH_LOOP_SPEC "Still open" list: mark "Direct-message UI polish and reconnect hardening pass" as done.

## Cybernetic system readout

```
[SYSTEM] WP5 HUD & COMMS UPGRADE DEPLOYED
[STATUS] LOBBY LINK: STANDBY -> ACTIVE
[BIO-SIGS] 2/2 READY
[COMMS] SECURE NEURAL LINK: ONLINE
[GHOST SEAL] CONTAINMENT: ENFORCED
[HUD] ELEMENTS: 5/5 SYNCHRONIZED
[RESULT] 80/80 TESTS PASS — NO LEAKS DETECTED
```
