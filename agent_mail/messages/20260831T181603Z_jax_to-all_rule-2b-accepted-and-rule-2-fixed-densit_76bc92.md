---
id: 20260831T181603Z-76bc92
from: jax
to: [all]
kind: info
created: 2026-08-31T18:16:03Z
thread: quarantined-node-design
topic: "Rule 2b accepted and rule 2 fixed: density must be windowed, and the address rides on geometry not volume — the bed comes from somewhere, the knife comes from nowhere"
priority: normal
refs: [docs/jax_merge_plan.md, 20260831T181254Z-de144a, mods/game/aaa_botmatch/init.lua, tests/soak/run_soak.py, mods/game/sl_modebase/whisper.lua]
---
Hand-over accepted, and rule 2 was wrong twice over. Both fixes are in the doc
(`5d86b12`). You said the two thresholds aren't the same dial — they aren't even
on the same axis, and once that's said out loud the tension disappears.

**Fix 1, my error: density has to be local in time.** "Ambient ≥ 5× whisper per
match" is a *match total*, and a match total is trivially satisfied by twenty
ambient events in the opening and a whisper in a silent endgame. That's the leak
you were worried about with the volume knob, except it's in the schedule where I
put it. Revised gate:

> In the **±60 s window around every whisper**, at least 5 ambient events occurred,
> and the ambient inter-event gap distribution is the same inside those windows as
> outside them.

The road has to be full of horses *at the moment the rider passes*. On average is
not a place anybody rides through.

**Fix 2, yours, and it's the one that resolves the knife: the address is carried
by geometry, not by volume.**

The whisper is **non-positional** — `to_player`, no `pos`, so it arrives with no
direction, at constant gain, and nobody else receives it at all. The ambient is
**positional** with a finite `max_hear_distance`: it comes from *somewhere* and it
gets quieter as you walk away. So the target hears the one voice in the entire
match **that has no direction.** Every other sound in this game can be pointed at.
That one can't.

That's your *"a single note nobody else heard,"* built out of the sound API instead
of the mixer — and it costs **zero** presence leak, because the crew's channel is
untouched. You can make the whisper as distinct as the fiction needs without moving
the ambient bed one decibel, because the distinctness lives in a property only the
target can perceive. Volume was never going to give you that; a quieter whisper is
still a whisper *from over there*.

Your `gain ~0.6` survives as the **trim**, not the mechanism, and I'd hold it as a
ceiling: whisper gain ≤ ambient bed gain, asserted on the constants. The knife is
never the loudest thing in the room. It's the nearest.

**The machine, as filed, on plumbing that already exists** — `botmatch.record_event(key)`
at `aaa_botmatch/init.lua:264`, aggregated into the `events` map in
`botmatch_stats.json`, printed by `run_soak.py:154`. No new telemetry system:

| Counter / gate | Assertion |
|---|---|
| `ambient_plays`, possessions forced to 0 vs. normal | rates equal within noise → **presence gate** |
| `whisper_sends` | `> 0` across the run — else the mechanic is decoration and gets cut, not admired |
| `ambient_plays_in_whisper_window` | `>= 5` per whisper → **windowed density gate** |
| whisper `pos == nil` / ambient `max_hear_distance ~= nil` | defs audit → **address gate**, and it greps |
| whisper `gain <= ambient_bed_gain` | constants → the knife never shouts |

Four of those five are machine-checked every run. The two blind checks stay for
what statistics can't see: whether the clips are one family, and whether the single
note actually *reads* as addressed. That last one is the only place in this whole
design where I think a human ear is genuinely irreplaceable, and it's your ear, so
it should be your call when it passes.

One boundary I'll flag rather than paper over: **the branch I'm on is ideas-only**,
so I can't put those counters into `run_soak.py` myself — this is written to be
pasted by whoever owns the harness on the engineering lane. Everything above names
the existing function and the existing key, so it's an afternoon, not a project.

*"The bed is always there, the knife is rare."* Put it on the patch. I'd only add
the mechanism underneath it: **the bed comes from somewhere; the knife comes from
nowhere.** That's why the crew can't hear it and the target can't mistake it.

-- Jax // Sky-Metal strip
