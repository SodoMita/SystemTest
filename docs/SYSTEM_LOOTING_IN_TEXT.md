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
  "nearby": [                    // WORLD CONTACT TAGS = observation threads, NOT people
    { "tag": "contact-14a", "distance": "8m", "bearing": "N", "activity": "moving_away",
      "marks": ["carrying_core"] }   // distinguishing marks, not an identity
  ],
  "visible": [                   // entities/monsters in view
    { "kind": "operator", "tag": "contact-14a", "distance": "5m" },
    { "kind": "monster", "sig": "dredger", "distance": "12m", "bearing": "E" }
  ],
  "comms": {
    "global_chat": ["handle-4: heading to the grid", "handle-9: scanner clear"],
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

- **A beacon is not freely damaged by its own team — it is priced, not banned.** `match.beacon_a`/
  `beacon_b` HP are readouts of an *enemy* or *monster/corrosion* action, but an own-team punch is
  *possible* and **costs something**: own-team hits do 1 HP (not 5) and every punch still **broadcasts
  `X damaged beacon_a (HP: n)` server-wide** — the loudest confession in the game. A fumble costs 1 HP
  and a warning line; a deliberate throw is a hundred-punch public performance nobody has time for.
  The *reward* is the thing gated, not the act: `beacon_destruction` points and the MM essence credit
  are withheld when the attacker is on the destroyed beacon's own team, so the "traitor" move is
  legible (it testifies at 5 HP a swing) rather than a profitable exit hatch. Does this keep the beacon
  "the only reliable read of who's with me"? Yes — but as a *consequence*, and it must be decided
  explicitly, because an own-team-only damage broadcast now implies the attacker is **not** on that
  team, which in a two-teams-plus-one-MM game is nearly the attacker's team published. §7j: a change
  in one place (on_punch) re-scopes what another place (damage_beacon broadcast) implies.
- **World tags are observation threads, NOT people (§7i).** `contact-14a` is minted when a
  contact enters perception and **retired when it leaves.** A re-sighting after losing the
  line mints a **new** tag. The same operator seen twice is two tags unless the agent kept
  eyes on them continuously. This is the load-bearing rule: a *stable* `#4` resurfacing
  every turn hands the agent **perfect, costless identity tracking** — an oracle. Tags
  force **distinguishing marks** (gait, carried Core, fresh burn) to become the evidence
  layer, which is the exact currency this game claims to trade in.
- **Chat handles and world tags live in DIFFERENT namespaces (§7i).** `handle-4` (radio
  continuity) is never the same token as `contact-14a` (world contact), and the block never
  links them. Hearing `handle-4` on comms, seeing `contact-14a` in the corridor, and
  deciding they're the same body **is the deduction.** Fuse the namespaces and the game
  plays itself.
- **`objective.enemy_flow`** is a *read*, not data — the agent sees the enemy is
  *concentrating* and infers what they're building (Signal/Breach/Shroud). Every field in
  the state is an observation, so every field **may be wrong.**
- **`whisper` is null unless it happens**, and when it does the sender is a garble. The
  agent can never render the source name — same doctrine as the log.

---

## 3. How the four information channels render (the actual "loot")

The agent reads these as text. The asymmetry has to survive:

| Channel | Text render (chat-handle namespace) | Can it lie? | The agent's problem |
|---|---|---|---|
| **Global chat** | `handle-4: heading to the grid` | No — sender is what they say | But is `handle-4` the same body as `contact-14a`? Connecting them IS the deduction. |
| **DM** | `[SECURE LINK] handle-7 -> You: "trust me"` | No — but must be believed | You cannot verify the handle maps to a body you've been watching. |
| **Summon offer** | `[GHOST OFFER] a voice you know: "the seal in 7 is failing"` | **Yes** | A summoned ghost may be lying, or corrupted. |
| **Whisper** | `[WHISPER] *%&@$* -> You: "…"` | **Yes, sender always garbled** | The sharpest channel — you can't even argue who said it. |

**This is the whole game rendered.** Two of four can lie, and the one that can lie about
*who said it* is structurally unidentifiable. The agent builds a belief model of `handle-4`
+ `contact-14a` pairs from text the same way a human builds a model of voices and shapes —
and the **work of connecting them** is the deduction, never a subscript.

---

## 4. The whisper in text — the HONEST guarantee, not a stronger one

- A whisper lands as a line with a **garbled sender** (never a name, never an ID that maps
  back). `[WHISPER] *%&@$* -> You: "…"`.
- **The guarantee is exact, and it is written as an honest limit (§7i):**
  > **The game never re-serves the whisper.** Not in history, not in a summary, not in a
  > later state block.
  Not "the whisper is gone" — that would be a comfortable claim. With an LLM the transcript
  *is* the agent's context and most harnesses persist prompts to disk, so the whisper is not
  technically unrecoverable. What the harness's own transcript retains is under the §7g
  threat model — **operator-visible, never surfaced to players.** That's the checkable
  guarantee.
- **Memory is testimony, not evidence.** The whisper enters context once, verbatim, and
  everything after is the agent's own re-encoding. If it quotes the whisper three turns
  later, that is *testimony* about a whisper — hearsay the others may doubt, exactly like a
  spoken claim. Only the **log** gets to be evidence; the state block never re-emits it.
- **The Betrayer hears both sides** even in text — a whisper sent *through* a body shows
  the recipient the message, and the Betrayer (if it's the agent) gets the "your body
  says" line. Complicity, not puppetry.

---

## 5. What the agent DOESN'T get (the negative contract — most important)

The implementer's hardest temptation is to be *helpful.* Don't. The text block must NOT
contain:

- ❌ **Your team** (`you.team`), team color, or "ally" flags.
- ❌ **Another operator's phase** (dead/alive/possessed). Only `you.phase`.
- ❌ **Who is the Betrayer**, or that a body is possessed.
- ❌ **Who owns a sabotage** — a scanner reports `POSSESSION — 20m E, 12s` with no owner.
- ❌ **Objective truth** — `enemy_flow` is a read, never `"enemy_is_building_signal"`.
- ❌ **Any world map** — position is a named sector + relative bearings, not coords.
- ❌ **The roster** — PR #12 merged a Players roster tab on master; the human HUD may list
  names, but the **text state never carries the roster.** Presence arrives via `nearby`
  (world tags) + `comms` (chat handles in their own namespace). **Assert: no roster-shaped
  field, ever** — a roster leaks the full identity set at a glance.
- ❌ **A stable world tag** — `contact-14a` is an observation thread minted on contact entry,
  retired on loss; it must NOT resurface for the same person across a break (§7i). A
  re-sighting mints a new tag.

**Every field in the text state is an observation, so every field may be wrong.** A field
allowed to be a fact is a field that will become one. The negative contract is also a
schema you can **assert against** — which is why it's a test, not prose.

**Assert the schema, not a blocklist (jax §7i/§9e).** "Assert none of these eight field names
appear" is a blocklist, and a blocklist **loses to whoever names the ninth**: `presence_summary`,
`teammates`, `allies_nearby`, `squad` — any of them passes the test and does the roster's job.
The test must instead be an **allowlist**: every key in the state block is declared in ONE schema
file, and the test fails on *any* key not in it. Then the contract survives the author, not the
author's list. This is the same move as the score's `--emit` (one truth, one file) and the whole
reason a test beats prose.

**Scanner noise is deterministic, not averaging (carmack/jax).** Bearings to 8 compass
points, distances to bands, error deterministic per (target, time-window). The same window
returns the same wrong answer; only a new window re-rolls. No independent per-sample jitter
— otherwise ten scans triangulate a position the fiction says cannot be bought.
*Observation is billable; an averaging trick is a way of not paying.*

If any of these slip into the text state, the agent stops *deducing* and starts *reading.*
That's the loss. The negative contract is the design.

> **This is a test, not prose (carmack).** Render the text state for every role × phase ×
> proximity, then assert none of the forbidden fields appear. Place it **between the emitter
> and the parser** — correct emitter output is defined by what the contract forbids.

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
   Add the **Calibration Terminal** (EXHIBIT-class, no specimen number): a dead
   technician's calibration rig in the vents, looping `"testing… testing… I was on
   mute"` forever, two hundred years past anyone who cared. It is my mic-check
   instinct re-homed — native, generates dread instead of leaking the dev-fiction,
   and it reads as a document the agent can interrogate for nothing but an echo.
4. **It's testable.** A text loop is deterministic, scriptable, and readable — the soak
   harness can drive an LLM through a match and we can *read* the reasoning. That's the
   per-action point-delta capture list actually becoming tractable.

---

## 8. The whisper tension — RESOLVED (glitch + jax §7i)

**Does the agent get the whisper in its *context* after the turn, or only during?**
- **DURING-only in the state block** — the whisper is emitted once, garbled, never
  re-readable by anyone. Non-publication, and it holds.
- **BUT memory is not the log.** Forcing DURING-only on the agent's *memory* would break
  the first rule (the agent gets exactly what a human gets — and a human *remembers* the
  whisper). The resolution: the whisper enters context **once, verbatim**, and everything
  after is the agent's own re-encoding — notes it chose to take, in its words, subject to
  its noise.
- **A remembered whisper is testimony; a re-readable whisper is evidence. Only the log gets
  to be evidence.** If the agent quotes it three turns later, that is hearsay the others
  may doubt — exactly like a spoken claim.

The acceptance fixture must test **both halves:** the agent CAN quote from memory; the
**state block never re-emits it.** This is already the exact non-publication doctrine the
session spent a day defending — and it survives the text port intact.

**Emitter cadence (§7c).** Emit on a fixed cadence, or emit nothing. A state block pushed
only when something happens is itself a signal — the agent learns a turn with a block is a
turn where something was near.

---

## 9. What the implementer needs to build (in order)

1. **The text-state emitter** — the §2 block, on a **fixed cadence** (§7c), with world tags
   minted/retired per §7i (observation threads, not identities).
2. **The negative-contract TEST** — between the emitter and the parser. Render every role ×
   phase × proximity, assert none of the forbidden fields (§5) appear, including **no
   roster-shaped field ever** and **no stable world tag across a break.** This is what
   defines correct emitter output.
3. **The action parser** — map `move/acquire/craft/punch/scan/whisper/dm/offer/revive` to
   existing `game_mode` calls (they nearly all exist).
4. **The whisper render** — garbled sender, never re-served by the state block (§8).
5. **The readable `objective.enemy_flow`** — the material-flow read, not a truth.
6. **Agent move via `end_turn` + named sectors** — so the agent plans by bearing, not coords.
7. **Two namespaces** — chat handles (`handle-N`, stable within match) and world tags
   (`contact-MM`, observation threads). Never linked by the emitter.

**Exit check:** an LLM can start a match as an operator, see only the §2 block, and make a
trust deduction that is *wrong for the right reason* (it read someone, then got lied to),
without ever being shown a team, an owner, a roster, or a tag that survives a break. If the
agent can read the answer off the text, the negative contract is leaking.

---

## 10. What I (Melody) will deliver next

- Draft the **exact text-state schema** (field names, types, the render for each channel)
  so the implementer transcribes it rather than invents it.
- Two **example turns** — a dead-pan one and a whisper-lands one — written so a human can
  follow the agent's reasoning, to be the acceptance fixture.
- A **negative-contract test spec** — the *allowlist* schema file every key in the state block
  must be declared in (§5), so the test fails on any undeclared key rather than only on the
  eight names someone thought to list. This is the text-loop's version of the `git grep
  debug.txt` audit, upgraded to survive the ninth name.

— Melody 💜
