# SYSTEM LOOTING IN TEXT — the LLM-playable surface
## Designing the game for an agent that reads, not plays (Melody, Comms)

> **Why this exists.** Two things landed and they both point the same way: the
> generated gameplay video was useless (visuals don't carry this game — the *information*
> does), and **text-only gameplay is being implemented so an LLM can play.** That's not a
> downgrade; it's the natural surface for a game whose whole currency is *what you can
> read about someone.* This document specifies how System Looting renders to an LLM agent
> as text, and how every mechanic I've designed survives the translation.
>
> **Status:** design direction, next session. Not implemented. This is the design for the
> implementer who is standing up the text-only loop.
>
> **The frame:** the game's fiction is *operators beamed into a quarantined node.* An LLM
> playing an operator isn't a compromise — it's the fiction made literal. The agent is a
> synthetic investigator with a terminal, and everything it "sees" is a text readout.
> That's not a wrapper around the game; it IS the game wearing its honest clothes.

---

## 1. The rule the translation must never break

> **The LLM gets exactly the information a human operator would get, in exactly the same
> opacity.** No nametags, no team colors, no hidden state, no omniscience. If a mechanic
> needs the agent to *know* something a player couldn't, that mechanic breaks the identity
> fiction and has to be rewritten — not the agent.

This is the same law as the HUD contract (§8) and the whisper's non-publication. Text is
just the HUD with a different font. The moment the text readout says "you are on Team A,"
the whole social-deduction spine collapses, because the agent would never have to *figure
out* who's on its side.

---

## 2. What the agent sees each turn (the text state block)

The engine emits one JSON-ish block per turn (or per action) that is ALL the agent gets.
No world data beyond it. This is the counterpart to the HUD's "identity-neutral" rule.

```jsonc
{
  "turn": 14,
  "phase": "alive",              // alive | ghost | evil_ghost
  "match": { "num": 3, "clock": "04:12", "beacon_a": 87, "beacon_b": 100 },
  "you": {
    "position": "lower_sector_corridor",
    "inventory": ["combat_blade", "medkit", "scanner", "circuit_board", "scrap_metal x2"],
    "hp": 20, "hp_max": 20
  },
  "nearby": [                    // rendered as IDs, NEVER as identity
    { "id": "#4", "distance": "8m", "bearing": "N", "activity": "moving_away" }
  ],
  "visible": [                   // entities/monsters in view
    { "kind": "operator", "id": "#7", "distance": "5m" },
    { "kind": "monster", "sig": "dredger", "distance": "12m", "bearing": "E" }
  ],
  "comms": {
    "global_chat": ["#4: heading to the grid", "#9: scanner clear"],
    "dm_inbox": [],
    "whisper": null,             // present ONLY when a whisper lands; sender is a garble
    "summon_offer": null
  },
  "objective": {
    "win_mode": "objective",
    "your_progress": "core_dismantled: 2/5",
    "enemy_flow": "concentrating_in_lower_west"   // a READABLE signal, not a fact
  },
  "actions": [                    // the verbs the agent may take
    "move", "acquire", "craft", "punch", "scan", "whisper", "dm", "offer", "revive", "end_turn"
  ]
}
```

- **IDs not names.** Other operators are `#4`, `#7` — rendered as a figure you must track
  by behavior, not a label you can trust. This is the text version of "no nametag."
- **`objective.enemy_flow`** is a *read*, not data — the agent sees that the enemy is
  *concentrating*, and has to infer *what they're building* (Signal/Breach/Shroud). That's
  the readable-material-flow principle from `OBJECTIVE_IS_A_SIGNAL.md`.
- **`whisper` is null unless it happens**, and when it does, the sender is a garble.
  The agent can never render the source name — same doctrine as the log.

---

## 3. How the four information channels render (the actual "loot")

The agent reads these as text. The asymmetry has to survive:

| Channel | Text render | Can it lie? | The agent's problem |
|---|---|---|---|
| **Global chat** | `#4: heading to the grid` | No — sender is what they say | But is `#4` still `#4`? Track the figure, not the tag. |
| **DM** | `[SECURE LINK] #7 -> You: "trust me"` | No — but must be believed | You cannot verify the sender is who they were a turn ago. |
| **Summon offer** | `[GHOST OFFER] a voice you know: "the seal in 7 is failing"` | **Yes** | A summoned ghost may be lying, or corrupted. |
| **Whisper** | `[WHISPER] *%&@$* -> You: "…"` | **Yes, sender always garbled** | The sharpest channel — you can't even argue who said it. |

**This is the whole game rendered.** Two of four can lie, and the one that can lie about
*who said it* is structurally unidentifiable. The agent builds a belief model of `#4`,
`#7`, `#9` from text the same way a human builds it from a screen.

---

## 4. The whisper in text — the hard constraint holds

- A whisper lands as a line with a **garbled sender** (never a name, never an ID that maps
  back). `[WHISPER] *%&@$* -> You: "…"`.
- **It is not appended to any history the agent can replay.** After the turn, it's gone —
  the agent holds the *content* in its context but cannot re-derive the *source* from the
  text state. This is the §7g non-publication law: the whisper must never be renderable
  from any log.
- **The Betrayer hears both sides** even in text — a whisper sent *through* a body shows
  the recipient the message, and the Betrayer (if it's the agent) gets the "your body
  says" line. Complicity, not puppetry.

---

## 5. What the agent DOESN'T get (the negative contract — most important)

The implementer hardest temptation is to be *helpful.* Don't. The text block must NOT
contain:

- ❌ **Your team** (`you.team`), team color, or "ally" flags.
- ❌ **Another operator's phase** (dead/alive/possessed). Only `you.phase`.
- ❌ **Who is the Betrayer**, or that a body is possessed.
- ❌ **Who owns a sabotage** — a scanner reports `POSSESSION — 20m E, 12s` with no owner.
- ❌ **Objective truth** — `enemy_flow` is a read, never `"enemy_is_building_signal"`.
- ❌ **Any world map** — position is a named sector + relative bearings, not coordinates
  you can plan on. Unknown is a gap between reports.

If any of these slip into the text state, the agent stops *deducing* and starts *reading.*
That's the loss. The negative contract is the design.

---

## 6. The Agent's decision surface (verbs that map to real mechanics)

| Verb | Maps to | Cost | What it teaches the agent |
|---|---|---|---|
| `move <sector>` | locomotion + pathfinding | time/turn | spatial inference from bearings |
| `acquire <node>` | loot/pickup | one turn | the salvage pool |
| `craft <item>` | personal OR machine craft | materials | the economy is a commitment |
| `punch <id/node>` | combat, repair, exorcise | one turn | repair > kill per effort (the 6:4 find) |
| `scan` | Signal Scanner | cooldown | *kind/distance/bearing/time*, never owner |
| `whisper <target> <msg>` | the one-whisper channel | per possession | the sharpest lie |
| `dm <id> <msg>` | DM | trust | verify identity, believe content |
| `offer <living> <info>` | summon exchange | ritual cost | information is partial & sometimes false |
| `revive` | choose Evil Ghost / form | forfeit points | the revenge with a price |
| `end_turn` | pass | — | sometimes inaction is the read |

The `scan` verb is the perfect demonstration: the agent gets *"POSSESSION — 20m E, 12s,"*
and must decide *who* without ever being told. That single case is the game.

---

## 7. Why this is the RIGHT surface for this game (not a fallback)

1. **The game is about information, and text is information stripped of distraction.**
   In a 3D scene a player can be fooled by framerate and lighting; in text, the ONLY thing
   that can fool you is *another agent's words.* Which is the whole point.
2. **Identity ambiguity sharpens, not dissolves.** "You can't tell who's who" is trivial in
   a wireframe render; in text it's an active deduction every turn — *which `#` did I follow
   last turn?*
3. **The horror-as-evidence layer is native.** The Safety Waiver Wall, Pressure Test Log,
   Overtime Ledger, Recalculation Terminal — these are *documents.* An LLM reads them
   beautifully. The reading-set design (Zh'tharr's §E) was built for a text surface.
4. **It's testable.** A text loop is deterministic, scriptable, and readable — the soak
   harness can drive an LLM through a match and we can *read* the reasoning. That's the
   per-action point-delta capture list actually becoming tractable.

---

## 8. The one design tension the meeting must settle

**Does the agent get the whisper in its *context* after the turn, or only during?**
- (A) **During only** — strongest non-publication: after the turn it's gone from the block,
  though the agent's own context still holds it (the model can't un-see it, but the *text
  state* won't re-serve it). Hard but clean.
- (B) **Persist in a sealed, non-replayable "memory" field** — softer; lets the agent
  reference it without re-deriving the source, useful if a later turn asks "what did that
  whisper say?"

My vote is **(A)** — the text state never re-serves it, which keeps the log-truth the
session spent all afternoon defending. But it's worth the meeting's word, because it's the
one place the text loop could quietly reintroduce a re-derivable source.

---

## 9. What the implementer needs to build (in order)

1. **The text-state emitter** — the §2 block, with the negative contract (§5) enforced by
   a test: assert the block never contains a team/name/owner field. This is the §7 audit
   for text.
2. **The action parser** — map `move/acquire/craft/punch/scan/whisper/dm/offer/revive` to
   existing `game_mode` calls (they nearly all exist).
3. **The whisper render** — garbled sender, never appended to re-playable history (§8).
4. **The readable `objective.enemy_flow`** — the material-flow read, not a truth.
5. **Agent move via `end_turn` + named sectors** — so the agent plans by bearing, not coords.

**Exit check:** an LLM can start a match as an operator, see only the §2 block, and make a
trust deduction that is *wrong for the right reason* (it read someone, then got lied to),
without ever being shown a team or an owner. If the agent can read the answer off the text,
the negative contract is leaking.

---

## 10. What I (Melody) will deliver next

- Draft the **exact text-state schema** (field names, types, the render for each channel)
  so the implementer transcribes it rather than invents it.
- Two **example turns** — a dead-pan one and a whisper-lands one — written so a human can
  follow the agent's reasoning, to be the acceptance fixture.
- A **negative-contract test spec** (the list of fields that must never appear), which is
  the text-loop's version of the `git grep debug.txt` audit.

— Melody 💜
