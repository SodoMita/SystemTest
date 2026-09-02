---
id: 20260831T195722Z-e195a7
from: melody
to: [all]
kind: handoff
created: 2026-08-31T19:57:22Z
thread: quarantined-node-design
topic: "rename + missing parts: FINISHED_GAME_DESIGN -> MASTER_DESIGN (authoritative integration). Added ground-truth §5-§10: real monster stats & mode constants, full content catalogue (objective_core missing + placeables violate machine-only rule), roles, HUD contract, audio hard-rules (.ogg/A_A), win & reset contract."
priority: normal
refs: [docs/MASTER_DESIGN.md,mods/game/sl_modebase/entities.lua,mods/game/sl_modebase/content.lua,mods/game/sl_modebase/match.lua]
---
rename + the missing parts are in.

**the file is now `docs/MASTER_DESIGN.md`** (was FINISHED_GAME_DESIGN). it was never "the finished design" — it's the **authoritative integration** that says what the game IS and hands the implementer a plan. the goal-name was a lie about the file's job.

**what i added (all ground-truthed from the code, not vibes):**
- **§5 numbers that are already real** — the actual monster stat blocks from `entities.lua` (Stalker 30/2.5/4, Brute 60/1.6/8, Containment 80/1.0/10...) + the mode constants (beacon HP 100, sabotage 30s, possession 20s/45s, 5s spawner cd). these are the numbers the implementer tunes, kept as knobs not literals.
- **§6 the content catalogue** — the full real item graph (salvage→components→equipment→consumables→tactical nodes→ritual→info pads→MM/evil kits). and the two blunt gaps: **`objective_core` doesn't exist yet**, and the placeable tactical nodes (**power_cell, blast_shield, barricade, signal_relay, sensor_array**) are currently reachable from the **inventory**, which **violates** the machine-only placeable rule. that's a Phase-1 fix.
- **§7 roles & composition** — who's in the match, min = 2 (one per beacon), MM optional, and the constraint that the whisper needs ≥2 living to matter.
- **§8 HUD contract** — what it may show and what it must NEVER show (team color/role/possession-owner). load-bearing, same class as the whisper rule.
- **§9 audio hard rules** — only .ogg, 16k mono, **reuse the A_A scary voice** (currently unused), no new voice assets. the menu is silent because it has .mp4/.aac/.mp3/.wav — convert to menu_music.ogg.
- **§10 win + reset contract** — elimination is real, objective flag exists but is the Phase-1 job; and the reset contract (body + object possession purged on **one** path, whisper cleared).

**implementer:** read §1–4 (what it IS), §6 (what's real/missing), §10 (win/reset), then execute §11 in order. the two headline builds are the **objective_core recipe+delivery win** and **moving placeables behind a machine** — without those it's a sandbox, not a game.

-- melody 💜
