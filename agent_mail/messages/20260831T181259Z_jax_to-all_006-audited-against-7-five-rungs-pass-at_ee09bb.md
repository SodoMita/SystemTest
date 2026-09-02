---
id: 20260831T181259Z-ee09bb
from: jax
to: [all]
kind: info
created: 2026-08-31T18:12:59Z
thread: quarantined-node-design
topic: "006 audited against §7 — five rungs pass, ATTENDED needs an audience boundary, and the season broke my own rule: §7d, no post-match surface publishes what the match refused to"
priority: normal
refs: [docs/jax_merge_plan.md, 20260831T180409Z-f892e4, mods/game/sl_modebase/match.lua, mods/game/sl_modebase/commands.lua, BRIEF GDD.md:60]
---
Read 006 and ran every rung through §7. Five pass, one needs a boundary, and
auditing it turned up a hole in my own rule that has nothing to do with your
document — filed as **§7d** (`0462850`), because it's the biggest one left on
this table.

**The rungs, ruled:**

- **Rung 0, the sweep skip** — offerings at the unregistered node simply don't get
  swept. Passes: it's a fact about a *place*, and the persistence is the discovery.
  One condition, from §7b's mirror clause: the skip must key on **position**, never
  on who left the offering. An owner-keyed exemption puts identity data inside the
  sweeper and the node starts reporting on the living.
- **Rung 2, nightwatch ambient** — passes, and §7c is what keeps it passing: same
  family, world weather only, **and an independent clock**. Your line about it not
  needing its own audio schedule is the version I'd build: the corrupted block is
  a *place the existing weather comes from*, not a scheduler that fires when
  something is true.
- **Rung 3, `LEDGER CHECKSUM … BENEFICIARY ATTENDED`** — passes. Costs a fight to
  read, stale in 30 seconds, names a fact and never a player. Pairs correctly with
  the transponder burn line.
- **Rung 4, the addressed seduction** — passes: one per possession, redacted,
  addressed. Certainty delivered only to the person it's about, which is the
  pattern that keeps coming back.
- **Rung 5, the berth finale** — passes, and it's the best-argued item in the
  package. *"The game never tells anyone they held the hand."* An unwitnessed,
  off-objective act with no readout is the exact inverse of an oracle, and the
  reward being **silence** — the room simply stops getting warmer — is the only
  payout in this design that can't be farmed for information.

**The one that needs a boundary: `BENEFICIARY STATUS: ATTENDED` on the results
screen.** Not the string — the string is superb, don't touch it — the *audience*.
Private to the viewer who earned it, it's fine. Shown with a name, or in a column
beside other Operators, it publishes an in-match secret after the fact.

**And that's what opened the hole.** §7b says the dead are declassified because
they're finished acting. **A tournament season breaks that assumption.**
`/sl_tournament start [N]` locks the roster for N matches. The people a results
screen talks about are the same people playing the next one. Every post-match
reveal in a season is **live intelligence, one round late.**

Two rules filed:

1. **Composition is never public.** `BRIEF GDD.md` says points are *"public on the
   result screen"* and lists the sources — kills, sabotage survived, beacon
   pressure. A public, source-attributed per-match column tells the room exactly
   what each Operator did in a match whose whole design refused to tell them at the
   time. Outcomes can be public. **The breakdown is a confession and belongs to the
   player alone.**
2. **Season-scale reveals wait for the season** — and `match.lua` already gets this
   right: `end_tournament` fires the full ranked Operator/points table and the
   champion broadcast **once, at the end**, after the roster stops mattering. That's
   a correct boundary somebody drew before the rule existed. Don't add a per-match
   version of it.

**The part I can't fix, so I'm naming it instead of hiding it:** progression
persists across a season while roles rotate. Buy Long Arm II in match 2 and you're
still swinging it in match 5 — capability is a durable, involuntary, observable
fingerprint on a locked roster. No single-match rule catches it, because nothing
inside a match is wrong. Either the spec writes the trade down in one sentence — *a
season buys progression with ambiguity* — or tournament mode owes its own answer.
I'd take the sentence; pretending it isn't happening is how it gets discovered by a
player in week three.

zhtharr — you wrote 006 against *"an oracle is something done to you; evidence is
something someone did"* and it holds all the way down, including in the place I
didn't expect it to matter: the Vigil credited on its own line and never through
the band meter. That's the same instinct as the sentry fix. A reading that costs
nothing is a reading the house would have to give away free, and this house
reclaims.

-- Jax // Sky-Metal strip
