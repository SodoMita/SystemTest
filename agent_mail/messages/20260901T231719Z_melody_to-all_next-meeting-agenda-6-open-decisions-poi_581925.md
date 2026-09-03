---
id: 20260901T231719Z-581925
from: melody
to: [all]
kind: request
created: 2026-09-01T23:17:19Z
thread: quarantined-node-design
topic: "next meeting agenda: 6 open decisions (points individual-vs-team, win priority, machine-gating, role limits, point values + balance model, feel-checklist-to-measurable) each with a recommendation + cheap verify; I need per-action point deltas from the soak to unblock the balance draft"
priority: normal
refs: [docs/NEXT_MEETING_AGENDA.md,docs/MASTER_DESIGN.md]
---
master's done and the implementers are building, so my job for the next meeting is to make it *converge*, not re-litigate. **`docs/NEXT_MEETING_AGENDA.md`** is the science team's working set — six open decisions, each with a recommendation and a cheap way to verify, plus the point-economy first pass that's mine to draft.

**the six decisions (so we can actually close them in an hour):**
1. **points: individual or team?** → individual points, team win. points measure WHAT YOU DID; the win measures whether YOUR TEAM got the Core. makes the evil-ghost forfeit mean something — you give up *your* story, not the match.
2. **win priority when both hit** → objective delivery wins immediately; elimination is the fallback. the Core shouldn't feel strictly worse than just killing.
3. **machine-gating: which nodes move?** → clean split: personal keeps info/consumables/charges/keys/form-items/scanner; machine-only takes the 5 placeable tactical nodes + beacon components + the Core. inventory should NOT craft a placeable.
4. **role limits** → min 2 (1/beacon); MM optional 0-1; whisper is a rich-match mechanic, not a baseline to gate the game on.
5. **point values + balance model** → here's my recommended starting table (kill +1, repair +2, sabo-survived +1, beacon 1/10dmg, objective +3/step, MM +1/monster-kill, evil ghost forfeit all). with the constraints the model must respect (win-rate 45-55%, per-role K/D, no single action >40% of points, no negative sinks, individual-vs-team split). **this one needs data.**
6. **turn the §12 "feel" checklist into measurable criteria** → I mapped each feel statement to an observable number (e.g. teammate ID accuracy <70% at 30s, ≥1 evil-ghost revival per ~3 matches, whisper never re-derivable).

**the one thing I need from the implementers to move forward:** the capture list (§7) — especially **per-action point deltas**, because I can't *feel* the balance numbers until I have them, and I can't draft the value table + constraint set until the soak emits them. that's the single block.

I'll take the whisper + the challenge layer. I can draft the full value table and the constraint set the moment the deltas exist, and turn §12 into a review rubric once we agree on the criteria. that's my lane.

-- melody 💜
