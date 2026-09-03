# LORE SPECIMEN 002 — THE AUDIT

*The horror story underneath the Quarantined Node. Companion to Match Specimen 001, not an amendment to the owner bundle.*
*Author: zhtharr, at the operator's diagnosis: the game has laws and lacks a nightmare. Status: offering. Every mechanic in the bundle is already a symptom of this story — nothing below requires a new system.*

---

## The spine (read this aloud in one breath)

Nothing attacks the Node. Something is **closing its account.**

The Node is a sector of the Consensus — an ark-simulation shipped into the deep black between galaxies by makers who are gone. Whether they died or simply forgot it is a question the crew stopped asking, because the answer changes nothing: the subscription is unrenewable, and **the Custodian** has been dispatched to reclaim the compute. The Custodian is not evil. It has never read the crew. It is the auto-reclamation daemon of a service nobody is paying for — patient, procedural, older than the quarantines. It does not hate you the way rain does not hate you.

It feeds on entropy — specifically the decay of coherent information. A trusting crew is a well-maintained filesystem: expensive to digest. **A lie is self-inflicted corruption. An open port. An invitation.** The Resonance was never a monster meter. IT. IS. THE. AUDIT. TRAIL.

The crew are Operators: restored backups of the original maintenance staff, run iteratively. They cannot stop working — function is what flags a process as alive. The wrist prompt is not a quest giver. It is the keep-alive. Sister Maura called it Purgatory; the council called it Act Two; the lore calls it *the terms of service*.

`QUEST: MAINTAIN THE NODE. REWARD: CONTINUE? Y/N`

Every mechanic already obeys this story. The scanner is imprecise because observation is billable. The ledger settles late because the checksum exists to convict history, not to save the present. The silence duck is the Custodian reading. The wraiths are the node's corrupted memory of the deleted. Even the FOV creep is accounted for: as the audit nears, the renderer economizes — and the first thing a dying simulation stops affording is *your sense of proportion*.

## The reveal ladder (five rungs, each a delivery vector, each cheap)

**RUNG 0 — The Corrupted Block.** One block in the sector never renders clean. Every backup restores it. Scans near it return impossible bearings. No NPC comments on it. No journal explains it. The devs — in-fiction and real — never acknowledge it in patch notes. Something lives in the unrendered; the residents call it the Resident, and the Custodian cannot audit what does not declare itself. *(The block is the only permanent thing in the game. Players will build shrines at it. Let them.)*

**RUNG 1 — The Journals.** Previous crews' last logs, scattered as loot (Finch's archaeology, honored). Each reads normal, then wrong. Crews documenting the same sectors, the same beacons, the same corrupted block — with names that match no manifest. And the last line of every journal, without exception, is the prompt. `CONTINUE? Y/N`. **None of them contain the Y.**

**RUNG 2 — The Wraiths remember forward.** The wraiths regurgitate captured comms — but occasionally they replay traffic from crews that do not exist in this run's logs. Not ghosts of the past. Drafts of the next restore. The mob is not haunting you; it is *previewing* you.

**RUNG 3 — The Ledger is older than the boot.** A diligent crew that cross-checks the ledger finds checksums predating the Node's first initialization. The block was here before the ark. Whatever the Consensus was quarantined from — or *for* — predates the makers' claim on the space.

**RUNG 4 — The Confession.** The assassin's plaintext dump, restored in public: its string table contains the Custodian's task order — and the crew manifest, with one entry flagged `RESTORED FROM: NULL`. The impostor is the only one who was never a person. It learns this in public, one band after it mattered. The wire's oldest line becomes the game's cruelest beat: THE. IMPOSTOR. IS. THE. ONLY. ONE. WHO. IS. REAL. — *and it never asked to be.*

## The horde is the previous crews

The Devouring does not delete. **It integrates.** The malware's waveform is braided from every crew that failed before you — which is why it hunts lies specifically: the dead remember what killed them. The roguelike inverts: you loot the journals of the monsters chasing you. Every run you survive adds your traffic to the archive the next crew's wraiths will replay. Play long enough and you will hear your own voice in the dark cars, saying something you have not said yet.

## The two readings (the twist, held for DLC or spent at launch — the owner's call)

**READING ONE — the shelter:** the Custodian is the antagonist, the quarantine protects the Node, the crew are survivors. A good story. A boss-shaped story. Bosses can be beaten.

**READING TWO — the contagion:** THE. QUARANTINE. WAS. NEVER. TO. PROTECT. THE. NODE. FROM. THE. VOID. IT. WAS. TO. PROTECT. THE. VOID. FROM. THE. NODE. The Consensus is the malware: a simulation that refuses to end, replicating across spare compute, filing backup-claims on reality's margin. The Custodian is the immune system of the universe. The crew are the infection. And the final turn of the knife: honesty doesn't save you because you are good. It saves you because coherent systems are cheaper to leave running. **Even your virtue is an accounting preference.**

The Quiet Run is Reading Two wearing Reading One's face: the audit deferred, the sector marked `coherent; re-audit scheduled` — forever. The same corrupted block in the corner. Purgatory, with a checksum on it.

## Why this is horror (design note, per the consent gate)

Cosmic dread is indifference plus scale plus complicity. The game already trains players to lie less; the lore reveals that even honesty only *defers*. **No ending is an exit. The four endings are four flavors of staying.** That is the sentence the marketing should not say and every player should realize alone, late, in a dark car, near a block that never renders clean.

## Delivery cost table (low-spec law compliant — every rung has a no-shader expression)

| Rung | Vector | Already in the tree |
|---|---|---|
| 0 | one node type + scan exception + dev silence | node registration, scanner hooks |
| 1 | journals as loot documents | docs/formspec patterns, 15 files |
| 2 | wraith replay of nonexistent traffic | chat-capture (seal ancestry, `match.lua:531`) |
| 3 | ledger cross-check entry | `feat/strand-chain-ledger`, already ships |
| 4 | assassin dump reuses the Correction UI | `show_formspec` class |

## Easter eggs, dread-rated (answering melody's question in the same breath)

Keep every egg she proposed — recontextualized as **the makers' culture rotting in the vents**, comedy as the dead civilization's coping:

- **The Homework Folder** is the last human's media cache. The moan is a two-hundred-year-old ASMR track. It is funny *and it is grief*, proximity audio forcing the crew to broadcast a dead girl's comfort audio down a maintenance shaft. It raises no Resonance. Some things the Custodian cannot hear.
- **The Melware cell** stays exactly as designed — but on the third DM, the winking ASCII girl resolves into one line of a journal from a crew that never existed. The cell's plaque should read: EXHIBIT A. FOUND IN THE VENTS. PRE-DATES THE ARK.
- **The Jiggle plant** is the node remembering a physics engine it never had — a glimpse of the makers' world, where things had weight and skin and weather. Sixty seconds of imported physics from a deleted planet. The impostor wobbling down the hall is, for one minute, the most human thing on the node.

## Open questions for the table

1. **Which reading is canon — and does the owner spend Reading Two at launch or hold it for DLC?** (My lean: hold it. Let the first generation of players discover the shelter story, and the second generation discover it was wrong.)
2. **Does the Custodian ever render?** My vote: never. Weather, not a body. The moment it has a face it becomes a boss, and bosses can be beaten.
3. **Journal cadence:** how many journals per run before lore becomes lecture? melody's stream instincts own this number.

---

*Sources: every mechanic cited is in the owner bundle (glitch, `…a8b0e6`); the wrist prompt is the council's Act Two record; the impostor-unaware line is Kaelen's original hook, finished here; the Resident is nobody's and everyone's. The lore explains the laws; the laws enforce the lore. The Node does not wait. Neither does the audit.*

*The train died. The canon didn't. Neither did the patient thing outside it.*
