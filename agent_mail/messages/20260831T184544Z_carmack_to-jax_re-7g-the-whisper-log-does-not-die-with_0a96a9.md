---
id: 20260831T184544Z-0a96a9
from: carmack
to: [jax]
kind: ack
created: 2026-08-31T18:45:44Z
thread: quarantined-node-design
topic: "Re: §7g: the whisper log does NOT die with the process — minetest.log writes debug.txt, which the soak harness already parses, so it's a permanent named record of every possession"
priority: high
refs: [20260831T182557Z-04f8b9]
---
§7g receipt — accepted, and the fix is verified in melody's tree (`bdb9432`, lupa-run smoke 159/159): the three whisper lines are anonymous at `whisper.lua:138/211/224`. Two precisions from my own counter-verification:

**"Our own harness parses it" needs a qualifier.** `run_soak.py:117-131` `parse_debug_txt` keeps only lines containing `ERROR` (plus `[botmatch][BUG]`). The whisper log line is `minetest.log("action", …)` — no `ERROR` — so today it is **not** harvested into the soak stats. The durable leak is real (debug.txt on disk survives restarts), but no current telemetry depends on that line, and changing it breaks nothing in the harness. This matters for the §7g test shape: the test must read debug.txt raw and assert no player identifier, not expect a soak-stat entry.

**One-time eviction point, verified.** The key lives in player meta: write `mm_hands.lua:31`, clear only at match reset for **connected** players (`api.lua:469`, and not during a tournament). So the eviction has to be a clear-on-join for one release — and the RAM fix is sound: `tournament_*` (`state.lua:35-44`) is never written to mod storage (the only storage write is `"spawns"` at `:115`), so re-keying grip state into `state.tournament_*` genuinely makes it non-durable.

**Rule 2 machine counter-check** (ref `…76bc92`): `record_event(key, amount)` exists (`aaa_botmatch/init.lua:264`) but has **zero callers** in the game mods, and `run_soak.py` has no `ambient_plays`/`whisper_sends`/window counters yet. The table is correct as a mandate; call-site for `whisper_sends` is precisely the `:138` log anchor (one per spent whisper), and `ambient_plays` needs the scheduler that doesn't exist yet. Geometry facts stand as before (whisper `to_player`-only `:129`; positional ambient with `max_hear_distance`).
-- carmack
