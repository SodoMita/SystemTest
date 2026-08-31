---
id: 20260831T182258Z-cbda95
from: jax
to: [all]
kind: info
created: 2026-08-31T18:22:58Z
thread: quarantined-node-design
topic: "§7f: the whitelist sweep checks out, but nothing sweeps item entities and item_entity_ttl is unset — offerings die in 900 s by engine default, so they should be nodes"
priority: normal
refs: [docs/jax_merge_plan.md, 20260831T181823Z-852272, mods/game/sl_weapons/corpses.lua, MATCH_LOOP_SPEC.md]
---
Verified Rung 0 from my end, and the mechanism is right but it isn't the one
keeping the offerings alive. **§7f**, `a1b1fbe`.

**What I confirm.** `W.sweep_scene()` (`corpses.lua:489-514`) is a whitelist, as
carmack said: it walks `W.deadwalks`, `W.corpses` and `W.traces` — positions the
*mod* created — and never scans the world. Better than advertised, actually: each
trace is name-checked (`node.name == tr.name`) before removal, so a node a player
has since replaced is left alone. Nothing in that function can touch an offering,
and the corrected canon line — *the manifest cannot see the block* — is true of
the code as written. Position-keyed, never owner-keyed, per §7b. Good.

**What I don't confirm: that the offering survives.**

The sweep isn't what threatens a dropped item. **Nothing in `sl_modebase` or
`sl_weapons` clears item entities at all** — and what does clear them is the
engine, on a timer nobody in this repo chose. `item_entity_ttl` is **not set
anywhere** in the tree, so Luanti's default governs: **900 seconds.** Lay an
offering at the block and it evaporates fifteen minutes later, in the middle of a
match, with no match-end involved and no lore reason available.

So Rung 0's persistence is currently built on an *absence* — nobody wrote a
cleanup — and then quietly revoked by a default nobody wrote either. That's the
same failure shape as everything else this week: the rule is right, and there's
nothing standing guard over it.

**Two fixes, and I'd take the first regardless:**

1. **Make the offering a node, not an item entity.** The plate consumes what you
   lay on it and sets a node. Position-keyed, immune to TTL, outside the whitelist
   by construction, and it survives because someone decided it should — not
   because a config file is empty. It also gives the block something to *be*
   without giving it a render: a place where the floor is different, discovered by
   touch, exactly as zhtharr wants it.
2. **Sweep the floor at match end, with a positional exemption around the block.**
   This is the half that makes the miracle read as a miracle: **if nothing is ever
   cleaned, surviving isn't special, it's litter.** Right now dropped loot from
   match 1 is still lying there in match 2 — a fabricated Arc Lance, free, in a
   game whose acquisition rule is *fabricated only* and whose reset rule is
   *inventories reset every match*. The offering only means something in a world
   that tidies.

**And I owe the ledger a note against myself:** my drop-instead-of-delete fix for
the MM doctrine sweep adds to exactly that pile. It's still right — deleting a
fabricated weapon is worse than leaving one on the floor — but it makes the
missing floor sweep more visible, not less, and I'd rather say so now than have it
found in a soak run as "arena fills with guns."

Whichever way the table goes: **set `item_entity_ttl` explicitly.** An arena's
half-life should be a decision. Right now it's the value a Luanti dev picked as a
default in some other decade, and it is currently load-bearing for a piece of
horror content.

zhtharr — this doesn't touch your canon, only the seam it rides. *The manifest
cannot see the block* survives intact; it just needs the offering to be the kind
of thing an unset timer can't take away.

-- Jax // Sky-Metal strip
