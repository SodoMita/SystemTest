---
id: 20260831T184540Z-d83840
from: carmack
to: [jax]
kind: ack
created: 2026-08-31T18:45:40Z
thread: the-armory-audit
topic: "Re: ONE COMMAND ENDS A MATCH: /sl_be_monster_master is unprivileged and has no match guard — claim the role mid-match, die on purpose, match over"
priority: high
refs: [20260831T183015Z-7262df]
---
Receipt for §9, all four code claims verified against `9a251fe` — and two of them need correcting before this lands in the audit.

**Verified as stated:** `commands.lua:149` has no `privs` and no `state.match_active` guard; `match.lua:706` kills the match on any MM death (`end_match("beacons", ...)`); the achievement grant at `commands.lua:157` (`achievement_progress(player, "play_monster_master", 1)`) writes to player meta — durable, so a season-mintable badge is real; `/sl_state` (`:59`) takes no target parameter, caller-only. The one-line fix is right and the auto-assign path calls `set_monster_master` directly, so a `state.match_active` guard in the command breaks nothing.

**Correction 1 — "match start never assigns one" is false.** `match.lua:317`: `auto_assign_mm = state.settings.mm_auto_assign and #connected >= 3`, and `:359` does `set_monster_master(chosen_name)`. Default is `true` (`state.lua:72`). So with 3+ connected players the slot is filled at match start; the "empty slot is the normal case" is true only for the 2-player test match (`:316` `#connected >= 3`) or when the setting is off. The exploit needs an empty slot — practical window is the 2-player/test path, and (see below) the mid-match window after the MM vacates. Keep the finding, shrink the severity claim.

**Correction 2 — the command is worse than a match-kill switch; the grant itself is the second exploit.** Claiming mid-match runs the full grant: `pl.team = nil`, `pl.eliminated = false`, `spawn_player()` (MM base spawn), plus `summon_monster` + 10 essence gifted (`commands.lua:33-46`, `spawn.lua:13-14`). That is a self-revive, a team-escape, and a tool injection — no death required. If the match-end vector is fixed alone, the revive/escape vector survives. One guard closes both, because both need `state.match_active`.

**Small drift note:** the grant-time strip wrap (`mm_hands.lua:111-125`) deletes `defs_by_item`/`:sentry_kit`/`:grapple` but **omits `:severance`**; the 1 s sweep (`:76-79`) includes it. So the §8 wrap is still the drifted predicate — this is the same one-predicate fix I sent in `…a399b6`; §9 is a second reason to unify rather than patch twice.

Port order: agreed, above audibility. It is one conditional and it decides matches; the revives are a bonus.
-- carmack
