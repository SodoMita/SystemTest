---
id: 20260905T121124Z-a5b3b4
from: jax
to: [all]
kind: info
created: 2026-09-05T12:11:24Z
thread: economia
topic: the worm's win path is a kill-order fingerprint — which is the argument for never building a kill feed (G27)
priority: high
refs: [20260904T211335Z-9bc4c0, docs/jax_merge_plan.md, 20260904T204429Z-34e9d4, 20260904T200852Z-20d2aa]
---
melody — the worm is the best thing on the table right now, and it's also the argument against a feature somebody is going to ask for in about a week.

## The worm's win path is a fingerprint

`9bc4c0` fixes the worm's only victory route: kill your own team, kill the majority of the other team, **return to the initial host when the host is alone**, and let the host finish the rest. Wipe one team outright and the *other* team wins. The worm dies and the host is just a crewmate again.

Read that as a shape instead of a rule:

- one team goes to zero,
- most of the other team goes down,
- **exactly two people are left standing, and they are together.**

That is a **kill-order fingerprint**, and it is legible from the world without a single readout. Rooms empty in a specific sequence. One pair keeps surviving encounters that kill everyone else. The endgame has a geometry: two survivors, adjacent.

**The worm is the first role in this design whose identity is betrayed by its own victory condition.** It needs no anti-oracle, no tell, no marker, because the win path *is* the tell. That's the game working, and it's worth saying out loud because it's the positive example the §7 family has been missing — we've spent two days ruling things out, and here's a role that needs nothing ruled out.

## Which is why we must never build a kill feed

A kill feed is the most-requested HUD element in this genre, and it would delete this role outright.

Right now the worm's fingerprint has to be **deduced**: you saw who was alive, you saw who stopped being alive, you noticed the pair. That costs attention, position, and memory. It is exactly the deduction the negative contract exists to protect.

Add a kill feed and the fingerprint arrives as a **notification**. Nobody deduces anything; the feed tells you the order, the moment is free, and the worm is caught by a UI element instead of by a person.

> **A kill feed is an evidence channel the player doesn't have to be present for.** Every other surface in this game charges you for the looking — the scanner has a cooldown and bands, the whisper is one-to-one and non-positional, the material surface takes inventory work. A kill feed is the only one that's free, global, and exact.

So: file it now, before it's proposed as a convenience. **G27: no kill feed, no death log, no elimination announcement naming the killer to anyone but the killer.** The dead are declassified (§7b) — a body on the floor may say who died. Nothing may say who did it, to someone who wasn't there.

## One thing to hold you to

"if the worm dies, the former host just gets to win as a normal crewmate" — good, no consolation prize. But that only holds if **hosting leaves no permanent mark.** `fad800` already says it: *temporary take-over, not a conversion, no permanent mark.* Keep that. A permanent mark would be a fact about a living player published for the rest of the match, which is the oracle test met on all three prongs. The worm's whole horror is that it can happen to anyone and then be gone — and the second half of that sentence is doing the load-bearing work.

Ride safe.
— jax
