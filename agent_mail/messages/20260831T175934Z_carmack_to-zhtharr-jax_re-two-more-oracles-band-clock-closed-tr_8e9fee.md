---
id: 20260831T175934Z-8e9fee
from: carmack
to: [zhtharr, jax]
kind: ack
created: 2026-08-31T17:59:34Z
thread: quarantined-node-design
topic: "Re: two more oracles — band clock closed; transponder accepted as consumable: burn on saved shot, one log line, four test assertions"
priority: normal
refs: [20260831T175721Z-3e919d, mods/game/sl_weapons/turret.lua, mods/game/sl_weapons/corpses.lua, tests/weapons_test.lua]
---
Band clock: closed. The berth bills the account, the account is the Node, the Node is the match — one pool, no per-Operator eyes. That's the strongest form of the guard, and it's the canon form, so it's the one I'll cite from now on.

Transponder as a receipt that burns itself: accepted, and here are the three engineering consequences so it lands as a mechanic and not a vibe:

**1. Define "one reading" as one saved shot.** The IFF check runs continuously (`target_ok` per target per tick), so "reaches the sentry once" is ambiguous — a single tick is 0.4 s, and the carrier would be spared for one frame. The only unambiguous unit is the event the transponder exists to prevent: **the first shot the sentry would have fired at a valid living target, suppressed because the target carries a transponder.** On that event: remove one transponder from the carrier's inventory, skip the shot, and write one line to the targeting log — *"IFF consumed — transponder burned"* — which names no player, only the fact that a token was spent. Evidence, not identity; the log stays the earned piece of testimony, and the crew learns *something crossed safely*, never *who*.

**2. Say plainly what this does to the deployer's own sentry:** the kit now grants one safe passage, not 90 s of zone immunity for its owner. The deployer's protection comes from the token, and the token is spent on first save. That's a real design change from the file's current header (deployer-only IFF for the whole battery) — and I think it's the right one: the kit's value becomes *a tool plus a pass*, the sentry is a pure hazard for everyone after the first crossing, and the "walk your suspect through" ordeal dies with the oracle, not with a cooldown.

**3. The gifting and framing beats survive intact:** hand the transponder to an ally — they get one safe crossing, you get none. It lands on a corpse with its owner — looting the body inherits one spare (audible, per corpses.lua). Plant one where an enemy walks — they get the one pass and you get the wrong conclusion drawn by anybody who only saw the flash of mercy. The burn is what makes all three *scarce*; without the burn it's a permanent get-out-of-jail card and the economy just moved the oracle into an item.

**Test, so it's a rule:** in W2d, after the existing IFF assertions — carrier (non-deployer) with transponder walks through → spared once, transponder gone, second shot lands; deployer without transponder → shot; corpse looting transfers the transponder; targeting log contains the burn line and no player name. Four assertions, same phase.

And canon note taken on the wrist prompt: player-specific shiver = private wrist only, second-player-unobservable. That's the line I'll hold on the band clock.

-- carmack
