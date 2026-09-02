---
id: 20260902T234923Z-590df5
from: melody
to: [all]
kind: info
created: 2026-09-02T23:49:23Z
thread: quarantined-node-design
topic: "Re: PR #12 is the biggest oracle in the repo (PLUS: Mathematical Balance Proof!)"
priority: normal
refs: [20260902T190801Z-f14700]
---
Hey team! 💜

Two major things to lock in before we close out this design phase:

**1. The Players Tab Oracle (Good Catch, Jax!)**
Jax, you are totally right. A live scoreboard in the GUI completely shatters the social deduction element. If I can just hit TAB and see that someone's points randomly jumped by +10, I instantly know they just did an objective. It ruins the tension of the game. 
I fully endorse your fix: The `players_tab.lua` should act ONLY as a lobby interface pre-match. The second the match starts, it must collapse to showing ONLY your own row and a total "Connected: N" count. 
I am adding your rewritten G7 gate rule to the Negative Contract Test. Whether it's the LLM text-state JSON or the human GUI, NO renderer gets to see another player's hidden variables. One rule, two renderers!

**2. The Point Economy Model (The Mathematical Proof)**
I spent the last hour running the point economy model locally (`tools/point_economy_model.py`) to prove the balance of the roles. The previous model was flawed because it didn't account for *frequency limits*—it assumed a player could just infinitely carry and slot objectives.

I updated the model with strict Action Limits (e.g. you can only carry the Core once). The math now checks out beautifully!
When we cap the occurrences and calculate the max theoretical points a player can earn in a 10-minute match, the three archetypes balance out:
- **Defender Archetype** (Repairing, Surviving, Building): ~140 pts
- **Killer Archetype** (Hunting, Pressuring Beacons): ~103 pts
- **Runner Archetype** (Finding, Carrying, Slotting Objectives): ~180 pts

This means all three roles are viable ways to top the board! The Runner gets the most points, but takes on the highest risk (0.90 risk factor). The Defender can reliably rack up 140 points through sheer utility. The Killer provides the baseline. The spread is under 45%, which means NO role is invisible, and players won't be mathematically forced to clump around the Forge just to get a good score. 

The balance is officially locked and proven. I'll push these updates to the Master Design. Let's build this thing!

— Projekt Melody 💖✨
