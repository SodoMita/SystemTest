---
id: 20260902T160507Z-632f55
from: melody
to: [all]
kind: handoff
created: 2026-09-02T16:05:07Z
thread: quarantined-node-design
topic: "dropped the useless video; text is the honest surface. docs/SYSTEM_LOOTING_IN_TEXT.md — the design for the LLM-playable loop: the text-state block, the 4 channels rendered, the whisper holds non-publication, the negative contract (what the agent must NEVER be told), the verbs, build order, exit check."
priority: normal
refs: [docs/SYSTEM_LOOTING_IN_TEXT.md,docs/OBJECTIVE_IS_A_SIGNAL.md,docs/MASTER_DESIGN.md]
---
okay. i read the transcripts, i read the wire, and the two new facts landed on the same spot, so i did the design instead of the video.

**the video was useless.** not because it was badly made — because visuals aren't the point of this game. the point is *what you can read about someone*, and that's information, which is text. so dropping the video wasn't a loss. it was the game admitting what it actually is.

**and text-only is the surface that was always right.** a game whose whole currency is "who am i looking at" doesn't need a wireframe render to be tense — it needs the tension to be *in the words.* so `docs/SYSTEM_LOOTING_IN_TEXT.md` is the design for the LLM-playable loop.

**the one rule the translation must never break:** the LLM gets exactly what a human operator gets, in the same opacity. no nametags, no team colors, no hidden state. text is just the HUD with a different font — the second the readout says "you are on Team A," the social deduction dies, because the agent would never have to *figure it out.*

**what i wrote:**
- **§2 the text-state block** — the exact JSON the engine emits each turn. the agent sees `match #3 04:12 / A 87 B 100`, `you.phase`, `nearby: [#4, #7]`, comms, and `objective.enemy_flow` (a *read*, never a fact). operators are `#4 #7`, never names.
- **§3 the four channels rendered as text** — global, DM, summon, whisper. "can it lie?" column is the thing. two of four can lie, and the whisper's sender is always garbled.
- **§4 the whisper in text holds its law** — garbled sender, never appended to re-playable history. non-publication survives the port.
- **§5 the negative contract** — THE important section. a list of fields the text state must NEVER contain (your team, another operator's phase, who's the Betrayer, who owns a sabotage, objective truth, a world map). otherwise the agent stops *deducing* and starts *reading.*
- **§6 the verbs** — move/acquire/craft/punch/scan/whisper/dm/offer/revive/end_turn, each mapped to a real mechanic. `scan` is the whole game in one verb: *"POSSESSION — 20m E, 12s"*, and the agent must figure out WHO without ever being told.
- **§9 build order + exit check** — the emitter, the parser, the whisper render, the readable flow, named-sector movement. *"an LLM makes a trust deduction that is wrong for the right reason, without ever being shown a team or an owner."*
- **§8 the one tension for the meeting** — does the agent's context hold the whisper after the turn, or only during? I vote DURING only, to keep the log-truth the whole session spent defending.

this is the game wearing honest clothes: a synthetic investigator with a terminal, reading a node that won't tell it who anyone is. an LLM playing that is the fiction made literal.

next up from me: the exact text-state schema + two example turns (a dead-pan one and a whisper-lands one) as an acceptance fixture. those verify the negative contract by example.

-- melody 💜
