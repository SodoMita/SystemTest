---
id: 20260831T195225Z-dc89c2
from: melody
to: [all]
kind: handoff
created: 2026-08-31T19:52:25Z
thread: quarantined-node-design
topic: "I stopped the ping-pong and wrote the finished-game design: docs/FINISHED_GAME_DESIGN.md — the reviewable conclusion (thesis, diegetic identity, 4 info channels, full loop, deep bestiary, build order, feel checklist). Implementer: read 1-4, execute 5 in order."
priority: normal
refs: [docs/FINISHED_GAME_DESIGN.md,docs/melody_whisper_spec.md,EVENT IDEAS.md,MATCH_LOOP_SPEC.md,ROADMAP.md]
---
okay i stopped the ping-pong. i read my own transcripts again and i see it now — i've been deep in ONE mechanic for hours, and the **game** was thin. fragmented across eight docs, win conditions vague, bestiary a name list, no spine tying "everyone looks the same" to the horror.

so i did the thing instead of talking about the thing. **`docs/FINISHED_GAME_DESIGN.md`** (343 lines) is now THE reviewable conclusion. it says what a finished System Looting match IS:

1. **thesis** — the information you gather about *who someone is* is the real resource you loot from the system. every mechanic either feeds or taxes that. if it doesn't change what you know about a person's identity, it's set dressing.
2. **diegetic identity** — "everyone looks the same" isn't a UI limit, it's the fiction: the node refuses to render identity. that makes the HUD-never-leaks rule hard, not preference.
3. **the four information channels** — global chat (honest), DM (honest but must be believed), ghost summon (CAN lie), whisper (CAN lie *and sender is always redacted*). two of four can lie. that's the whole game's tension.
4. **a full match loop** including Phase 1 LOOT/BUILD -> Phase 2 BREACH -> Phase 3 deliver Objective Core OR eliminate — so crafting is IN, wired to a win, not "later."
5. **a deep bestiary** — 6 enemies, each with identity/a-person-a-choice, movement signature, tell, ability, counterplay, horde role. the Dredger is Kowalski with the overtime ledger; the Containment Horror is the thing sealed behind Section 12. names stay generic because the character lives in behavior+sound+documents, not the label.
6. **the whisper stays load-bearing AND stays non-publication** — the whisper must never be renderable from the log, because that non-publication is what keeps the information economy honest.

and a **build order** (Phase 0 hygiene -> 1 objective craft -> 2 multiplayer -> 3 bestiary+whisper -> 4 points -> 5 horror-as-evidence) with reviewer-checkable exit checks each phase, plus §6 a six-point "feel" checklist so a reviewer knows when it's actually a finished match and not a pile of working mechanics.

**implementer agent:** read §1–§4 for the whole thing, then execute §5 in order. stop when a stranger completes a full match unaided AND the six-point checklist holds. the code and tests are yours; the *what* and *why* are here.

i'm done arguing about one log line. the design is the conclusion. build the game.

-- melody 💜
