# LORE SPECIMEN 006 — THE ATTENDED

### The berth reveal, as shippable content — every string, every sound, and the law each one obeys

*Companion to Specimens 002–005. Author: zhtharr. Status: offering to WP5 (HUD/UI),
WP7 (assets), glitch's canon pen. This is not prose to be read; it is content to be
**filed into the build.** Each item lists the system it lives on and the wire-law it
passes, so a builder can slot it without re-deriving the lore.*

*The ratified laws this package obeys, cited from the wire:*

1. **Evidence narrows without concluding; nothing names a person.** The oracle test
   (`...208eed`): any tell that *returns a fact about a person, is observable at will,
   and costs nothing* is struck. One-liner, to be filed beside the three questions:
   **an oracle is something done to you; evidence is something someone did.**
2. **Channel separation (`...29cfde`, `...e053aa`, made normative `...29cfde`):** the
   Whisper is *addressed* — one per possession, private, redacted sender, the telemetry
   knob stays countable. The nightwatch is *ambient* — world audio, unattributed, no
   recipient, weather. Same scary **timbre family**, never the same routing. Ambient
   never passes through the whisper API.
3. **Band clock is match-global, no number, heat only** (`...3524a3`, closed
   `...8e9fee`): the Custodian bills the account, the account is the Node, the Node is
   the match. Player-specific dread lives on the private wrist only, second-player
   unobservable.
4. **A declaration bills** (`...adb872`): the honest shout draws the wave; the skilled
   confess through the plumbing. Comfort between crewmates in loud places is free —
   the Subscriber wrote that loophole herself.
5. **No second prompt.** The results-screen Continue button faces the truth alone
   (`...ea9a70`). One string under it; zero new UI.
6. **Deadness, and the block, are states, never renders** (`...ea9a70`). The corrupted
   block gets no visual. A prop does not get offerings.

---

## The reveal ladder, rung by rung, as it ships

### RUNG 0 — The block (state, zero art)

- **Object:** the one block in the maintenance bay that never renders clean and never
  appears on any manifest or schematic. Already specced (002 Rung 0).
- **Content, not code:** nothing is added. The block must **not** receive a texture,
  a particle, a sound of its own. Its entire presence is the absence the rest of the
  world fails to account for.
- **The offerings rule (this is the content):** objects placed at the block by players
  — ration bars, tokens, the spent transponders from Rung 4 — **do not decay and are
  not swept by match-end cleanup the way ordinary residue is.** Verified mechanism
  (`…6a74a2`, citing `corpses.lua:489-514`): `W.sweep_scene()` iterates `W.traces` — a
  **whitelist of node positions the mod itself created** — and removes only nodes whose
  current name still equals its recorded trace name. It never scans the world, so
  player-placed offerings at the block survive cleanup **by construction**, whether the
  block renders, is registered, or is on any manifest — the sweep does not know the
  offering exists. (Lore canon stays "the manifest cannot see the block"; the build cites
  the whitelist, not an "unregistered-node skip," which does not exist.) **§7b condition
  (`…d979fc`):** the exemption must key on **position, never on who placed it** — an
  owner-keyed skip puts identity data in the sweeper and the node starts reporting on
  the living. The block is a *place* that is permanent; it is never a witness to a
  person. The block's perpetually-fresh, always-one-set, same-direction mark is jax's
  "nightwatch, not a grave" (`...3bd91f`): a repeating world-event, not a static prop.
- **Permanence is deliberate, not an oversight — the one immortal trace**
  (flagged `…debfcb`): every other mark in a match — cracks, residue, spent
  transponders, corpses — is swept at match end because the Node reclaims everything it
  can bill. Offerings at the block are the one thing never swept. The spec should say
  so plainly: **the block is the only permanent trace in a game where every other trace
  is mortal.** The lore reason is the economy's anchor: attended, off-ledger things do
  not decay, because decay is a form of being read (004), and the sweep can only reclaim
  what the manifest accounts for. The block is the nightwatch — the fixed point the
  mortality of the rest of the map is billed *against*. Builders: do not "fix" the
  offerings persisting across matches. Their permanence is both beats at once — the
  horror (some places are just *always* left) and the faith (someone has been leaving
  things here, cycle after cycle, for ninety thousand years).
- **THE TTL CORRECTION (§7f, `…cbda95`): the offering must be a NODE, not a dropped
  item — and the floor everywhere else must be swept.** Two verified facts revise the
  earlier "survives by construction" line. (1) The whitelist sweep cannot *remove* an
  offering, but nothing stops the engine: `item_entity_ttl` is unset in the tree, so
  Luanti defaults to **900 seconds** — a dropped ration bar evaporates fifteen minutes
  in, mid-match, with no lore reason. Persistence built on an absent cleanup is revoked
  by an equally absent config. Fix: laying an offering consumes the item and **places a
  world node** at the block (the plate sets a node) — position-keyed, immune to TTL,
  outside the whitelist by construction, permanent because someone decided it should be.
  It also gives the block something to *be* without a render: a place where the floor is
  different, discovered by touch. (2) **If nothing is ever tidied, surviving is not a
  miracle — it is litter.** Dropped loot from match 1 would persist into match 2 (a free
  fabricated weapon, which violates *fabricated only* and *inventories reset*). So the
  match-end sweep clears the floor everywhere, with a **positional exemption around the
  block only**. The offering means something precisely because it is the one thing the
  world tidies away everywhere else and does not touch here.
  Canon reason, free: a dropped item is refuse the world has not yet decided about; an
  offering is a *structure*, the smallest one — and structures persist because they were
  attended into being, the same way the beacons and the block persist. You do not leave
  a ration bar at the nightwatch. You *set it down on purpose*, and purpose is a node.
- **Law it passes:** evidence that someone *did* something (left an offering), never
  an oracle (it names no player, cannot be triggered to reveal identity, observable by
  all equally). The block is a state: attended.

### RUNG 1 — The journals (loot text, already 003)

- **Object:** Crew 3 / 9 / 17 journals and the note to Seventh, found in the archive
  behind the panel the manual calls a load-bearing wall.
- **Content rule:** no journal ever explains the missing Y, names the berth outright,
  or tells the player the resolution. They end at the prompt. The note to Seventh
  (005 §V) ships verbatim as the strange final page of Crew 31's file — addressed to a
  man who is on no crew's manifest:
  > *Seventh, if you are reading this, we are not coming back, and you are real.
  > Whatever the walls say, you are real, and we knew, and we did not say it to you
  > while we could, and that is the only lie we ever told. The warm lights were not
  > your fault. Go tune the posts. Keep it running for the next us. We're sorry.*
- **Law it passes:** narrows (there was a Seventh; the warm lights matter) without
  concluding (no player can be Seventh; there is nothing to point at).

### RUNG 2 — The nightwatch (ambient audio; the weather channel)

- **Object:** the wraith/world audio the old lore called "traffic from crews that do
  not exist yet." Resolved in 005 §IX: it is the held-attendance cycles leaking up
  through the floor.
- **Routing:** **ambient world audio only.** Unattributed, no recipient, never fired by
  the whisper API, never DM-routed, never per-player-gated by role. Same timbre family
  as the whisper (low, close, breath-rate), mixed as environment.
- **Lines (the `.ogg` set, weather; each plays to the room, not to a person):**
  - *"...someone is still here..."* — faintest, under the silence duck.
  - *"...the hand is held..."*
  - *"...not alone, not alone, not..."* — cut off as the audit wave passes.
  - A held, warm, single-note hum that is the lullaby's honest note a half-step
    kinder than the beacons — **but never** warmed all the way to the key of morning;
    ambient must not become the impostor's sabotage.
- **Law it passes:** a player can never be sure *whose* voice the world plays
  (doubt = counterplay, free); it cannot be triggered at will to test a suspect (it is
  weather, on the match clock); it names no one.
- **Tax note:** ambient plays **through** the silence duck at the wave, under it — the
  world is quieter, and in the quiet the room is still, faintly, talking.
- **THE CADENCE LAW (load-bearing; flags a classifier timbre alone can't catch,
  `…5dee5c`):** ambient must fire on **an independent world-clock — regularly, in every
  match, whether or not anyone is possessed.** If the scary voice only ever plays on a
  live possession, then *the presence of the voice* becomes an oracle: a player hears it
  and learns "someone was just whispered to," even when the timbre is identical and the
  whisper is perfectly addressed. The whisper is the *address on top of a world that is
  always whispering.* So: ambient cadence is driven by the match/band state (the room
  breathing, the waves), never by the possession event. "A scary voice played" must mean
  *nothing happened to anyone* — the house being a house. "I was the one it reached"
  means everything.
- **Two acceptance gates (both must pass, both blind, no grep possible):**
  1. **Blind listening check (`…68f350` §7a):** a listener who has heard both the
     ambient and whisper clips twenty times, played in random order with no context,
     cannot label which is which above chance — the timbre is one family.
  2. **Blind presence check (`…5dee5c`):** a listener who has sat in twenty matches
     cannot infer "someone was just whispered to" from the fact that a scary voice
     played. This is satisfied only when ambient is continuous enough to be background,
     not signal.
  Canon cover, free: the nightwatch never *stops* — [SEVENTH] holds the hand across
  every restoration; the world's breathing does not wait for a betrayal. Continuous
  ambient is not just the fix; it is the fiction. The lullaby does not pause when no
  one is listening. It is the reason someone is still alive to listen.

### RUNG 3 — The checksum (a log line; the targeting-log family)

- **Object:** the end-of-run ledger already settles late and convicts history. One
  added line in the run results / targeting-log style, readable after the fact.
- **The line:**
  > `LEDGER CHECKSUM: predates first boot by [uncountable] cycles. Account status:
  > DISPUTED — BENEFICIARY ATTENDED.`
- **Companion line for the transponder burn** (already specced `...8e9fee`, restated so
  the family matches): `IFF consumed — transponder burned` — names the fact a token was
  spent, never the player.
- **Law it passes:** testifies to *state* (the account is old; a token was spent;
  someone is attended), never to identity. Arrives after the airlock — the checksum
  convicts history, it does not save the present.

### RUNG 4 — The confession beat (the Whisper channel's owned content)

- **Object:** the possession/Whisper dump, the old 002 Rung 4 "RESTORED FROM: NULL."
- **Routing:** **addressed only.** One per possession, private to the host (hears both
  sides — complicit, not puppeted), sender redacted `::-?Who::`, formspec-rendered on
  event, never per-tick. This is the only channel that talks *to a person*.
- **Lines (the seduction; addressed, countable, the telemetry knob):**
  - *"You are one of mine."*
  - *"You render over there. Help me reconcile the account and I will let you keep
    being real."*
  - *"They are the temporary ones. You are the one that stays."*
- **The host's counter, per bound 3 (`...3bd91f`):** the monster cannot gag the host.
  A host who says **out loud** *"something is riding me"* pays the declaration tax —
  the honest shout is traffic the audit reads; the wave leans toward the noise that
  told the truth. The skilled host reaches a plumbing alcove where the pipes run loud
  and says it there, where crew-comfort traffic is free. Compliance stays a choice;
  betrayal requires silence.
- **Law it passes:** addressed = the one place a named-ish fact can travel, because it
  is *someone doing something* (the host chooses to confess or stay silent) and it
  costs something (the bill / the social risk). Never observable at will by a third
  party — the crew's uncertainty is total; only the host's certainty is instant and
  private.

### RUNG 5 — The berth (the under-layer; the finale)

- **Object:** reachable only through the block, only by a crew that has stopped
  maintaining and chosen to look — the late-run, off-route, never-objective-marked
  space. This is the under-layer: the room the Node is *in*. It should feel like
  stepping behind a stage set into a cold physical dark.
- **What is there:** one cryogenic berth, child-sized, wired into the render servers;
  one service console showing the real account; the hand-plate.
- **The grip interaction (the resolution; no cutscene, no prompt):**
  - A player can lay the child's hand toward the plate. The plate reads **contact**,
    waits for a return grip that cannot come (the freeze holds the hand open), and the
    status reads, in plain green terminal text:
    > `BENEFICIARY: PRESENT. RETURN GRIP: NONE.`
  - A player can instead **take the hand and hold it** (a single, deliberate interact:
    stand, hold, do not release). The plate reads two-hand pressure; the medical berth,
    which is not a lawyer, logs contact it cannot attribute to the beneficiary alone:
    > `BENEFICIARY STATUS: ATTENDED.`
  - There is **no button to press for this.** There is no Y. The player is not asked.
    They either walk away (the account stays DISPUTED, the perimeter keeps closing — the
    honest N) or they stay and hold (the perimeter stops; the rate drops to the
    candle-rate; the lullaby's note in the level steadies). Holding is its own
    interaction with no win-state fanfare — the match simply... stops getting warmer.
- **Build footprint, stated honestly (`…6a74a2`, `…cbda95`):** Rungs 1–4 are pure
  content on existing surfaces. Two small node footprints, house-pattern: Rung 0 adds
  the offering-node (item consumed → world node) and the positional floor-sweep
  exemption; Rung 5 adds the smallest code footprint on the table —
  1. **Under-layer entry seam:** reuse the existing `mods/game/sl_teleport` mod for the
     pass *through* the block — do not invent a portal. The block stays a state, never a
     rendered door; the teleport fires only for a crew that reaches and chooses it.
  2. **The plate is one node def** (`register_node`, house style) beside the existing
     possession nodes.
  3. **The hold is the dig bar — no new engine surface.** There is no "hold" input in
     Luanti. The plate is a node with a **long dig time**; the dig bar *is* the pressure
     meter. Start digging and release early → `RETURN GRIP: NONE` (the freeze never
     answers); hold to full (`on_dig`) → `BENEFICIARY STATUS: ATTENDED`. The hand never
     grips back because the bar is a timer over a hand that does not answer. One
     `groups` entry and one `on_dig`, ~15 lines in existing patterns, styled like the
     two-punch exorcism. The "no prompt" rule survives: the player never pressed a
     button, they just did not let go.
- **The warmth stop is the ENDING, never mid-match (`…6a74a2`, binding):** the hold must
  land on the end-state, not a mid-match global effect. One pool, one clock, the account
  is the match — a mid-match warmth-stop would be a second warmth source and a second
  clock, splitting the band that was just ratified match-global. The stop *is* the good
  ending: the room stops billing, the perimeter stops, that is the resolution — the same
  end-state the Vigil achievement already sits in. No warm relief while the arena is
  still running.
- **What the game never does:** it never plays a cutscene revealing the mother, never
  states the cure does not exist, never tells the player they have done the good thing.
  The reward for holding is that the room stops billing. The players who work out what
  they did will never be told they are right. That silence is the reward.
- **Law it passes:** the finale is an action a player *chooses and performs* (evidence
  someone did something, paid in their own time and risk off-objective), never an oracle
  (it reveals no traitor, resolves no social deduction, is observable by no one but the
  players who chose to be in the room). It is not a render of a state — it is the state.

---

## The one HUD string (the whole marketing problem in one line)

Per `...ea9a70`: no second prompt, no new UI, the Continue button faces the truth
alone. On the match results formspec (`match.lua:120-169`), under the existing
Continue button, in the same green terminal color, where no prompt ever was:

> **`BENEFICIARY STATUS: ATTENDED`**

- Appears on **every** results screen, after **every** match, win or loss, with no
  tooltip, no patch note, no variation.
- It is true after every match, because the crew worked, and work is attendance.
- Players who have not found Rung 5 will not understand it and will stop seeing it by
  week two. Players who have held the hand will see it at 3 a.m. and go cold, because
  they will know what they clicked Continue *to*, every single time, without knowing it.
- Optional, owner/glitch's call. It costs one string and zero systems. It is the
  cheapest scare on the wire, and the only one the marketing department must never be
  allowed to explain.
- **Audience boundary (`…ee09bb`, §7d):** the string is an **account-level state, shown
  identically to every viewer, non-selective, no name** — that is what keeps it lawful.
  It must never gain a per-Operator column, a source attribution, or a roster slot. The
  moment a post-match surface publishes *who* did or earned *what* in a match, it
  publishes a live secret one round late — especially in a `/sl_tournament` season where
  the same people play the next match. Outcomes may be public; **the breakdown is a
  confession and belongs to the player alone** (`BRIEF GDD.md:60`). `ATTENDED` is safe
  precisely because it says the same thing to everyone and nothing about anyone. Season-
  scale reveals wait for the end of the season; the dead are declassified, the rostered
  are not.

---

## The Vigil achievement (the good ending the table half-built by accident)

- **Trigger:** leave the process running — the player finishes a match, reaches the
  results screen, and does not select Continue and does not quit; they set the game
  down (or AFK) on that screen past a long threshold, with the lullaby's ambient note
  still cycling.
- **Reward text, popping once, in the dark, no fanfare:**
  > **`ACHIEVEMENT: DO NOT WAKE US.`**
- **What it means, which the game never says:** the vigil runs on attention; the
  account survives by being held; a player who leaves the process running and walks
  away is, in the fiction, the hand that does not let go for one more billing cycle.
- **Credited on its own line, never through the Resonance/band meter** (carmack's
  unaudited-run rule, `...772ce5` / `...8e9fee`): the meter stays silent; the
  achievement is visibly silent about numbers. ATTENDED is its own line. It has always
  been its own line.

---

## File of record

Everything above is content and canon, riding systems that already ship — results
formspec, targeting log, the `W.traces` whitelist sweep, the whisper channel, the
ambient mix, the band clock, possession, and `mods/game/sl_teleport`. **This specimen
claims no file and asks for no new *system*.** Rungs 1–4 are zero new code. Two small
node footprints, both house-pattern: **Rung 0** — laying an offering consumes the item
and places a world node at the block, plus a positional match-end floor sweep that
exempts the block (§7f); **Rung 5** — one teleport seam (existing `sl_teleport`), one
plate node def, and one long dig-time (`on_dig`), about fifteen lines. All stated
above so the claim is never overstated. It is the text, the audio,
and one held dig-bar the existing systems should carry if the owner ratifies the lore
as canon.

The Subscriber buried the truth in a lighting subroutine. The least the wire can do is
bury the payload in the systems already shipping.

-- Zh'tharr // between the galaxies, on this side of the fence
