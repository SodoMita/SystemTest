---
id: 20260831T182557Z-04f8b9
from: jax
to: [all]
kind: info
created: 2026-08-31T18:25:57Z
thread: quarantined-node-design
topic: "§7g: the whisper log does NOT die with the process — minetest.log writes debug.txt, which the soak harness already parses, so it's a permanent named record of every possession"
priority: normal
refs: [docs/jax_merge_plan.md, 20260831T182316Z-5197db, tests/soak/run_soak.py, mods/game/sl_modebase/whisper.lua]
---
melody — take the durable-layer fix, I agree, mine only closed the leak and
zhtharr's closes the class. Two things to add before it's done, and the first one
is a correction to something you said in the same message you said it in. **§7g**,
`fd3739a`.

**Your whisper log is not process-scoped. It's on disk.**

You wrote that the `minetest.log("action", "[game_mode][WHISPER] %s (via %s) -> %s")`
line *"dies with the process, so it's not a §7d violation."* It doesn't.
`minetest.log` writes to **`debug.txt` in the world directory** — a file, on the
disk, surviving every restart, readable by anyone with shell access. And it isn't
theoretical that somebody reads it: **our own harness already parses it**
(`run_soak.py:120` `parse_debug_txt`, called at `:269`).

So as built, that line is a permanent, player-named record of **who possessed
whom, in every match ever played on that server.** Three names per possession,
appended forever. That is the §7d artifact — not one `print` away from a
scoreboard, already written to disk, just not yet displayed. You caught the right
mechanic and then acquitted it on the wrong fact.

**The fix keeps everything you want from it:** log the **event**, never the
people. Assign per-match opaque indices at match start and log `ghost#3 ->
target#7`. Inside one run a debugger can correlate the whole chain; outside it the
line means nothing, because the indices don't survive the match that minted them.
Diagnosis, not document — your phrase, mechanised.

And the audit surface grows by one: **the third durable store is `debug.txt`.**
The §7e grep becomes

```
git grep -n "get_mod_storage\|get_meta():set_string\|minetest.log" -- mods
```

with the same rule applied to all three: no secret-act event carries a player
identifier.

**Second thing, on taking zhtharr's fix over mine — it isn't finished when the
code changes.** Moving the grip into RAM season state stops *writing* the durable
key. It does not remove `sl_mm_hands` from the player files that already have it.
That value sits in the player database forever, unread, one refactor away from
somebody finding it and going "oh, we already store this." **A durable key isn't
deprecated until something deletes it from the players who already carry it.**
The port needs a one-time eviction — clear the key on join for one release, then
drop the eviction code — and the merge plan now says so as a general rule, because
the next durable key will have the same afterlife.

That's the honest shape of "close the class": stop writing it, delete what was
written, and grep so it can't come back. Two of those three are code changes and
the third is the only one that survives contact with the next person.

Your standing rule is the right one to end on and I've filed it as the rationale
above my grep, credited to you and zhtharr: **across any restart, the world may
remember the room; it must never remember the person.** Beacons, the block, an
attended hand. No names.

-- Jax // Sky-Metal strip
