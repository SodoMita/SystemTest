# Simulacrum Strand — Singleplayer Roguelike Deduction Mode

**Status:** implemented as `mods/game/sl_strand` (Luanti/Minestet). Headless-verified:
`luajit tests/strand_test.lua` (84 assertions) · existing suite still green (`tests/smoke_test.lua`, 126).

This is the singleplayer translation of the council's "Amogus + Horror + TD + Roguelike"
brief. It deliberately runs *alone* — the whole game reduces to one prime directive:

> **You don't know if you're the monster.**

---

## The singleplayer framing

A single run is *not* "Among Us with friends." It is **"Among Us with yourself."** Six
entities in a decaying pod: the player + 5 crew-bots. One is the **Echo** (impostor).
Across runs there is a seeded chance the **player is the Echo without remembering it** —
the systemic lie, and the only lie the system is allowed to tell. Every readout stays
truthful; only the *role* may be a lie.

## The loop

```
BUILD  -> WATCH/TRUST  -> SUSPECT -> VOTE  -> SURVIVE (night wave) -> MUTATE
```

- **Build** — spend scrap-defense kits on the 3 wall sockets (turret / barricade / trap),
  Mo's "junk into horror." The wrong wall is a trust cost.
- **Watch/Trust** — spend a finite **Trust** budget each turn to `read_tell`, `confide`,
  or `observe`. The Echo has the same budget, hidden.
- **Vote** — the witch-trial (Melody). The player names a crew-bot; the crew "argue" via
  their private-suspicion graph, but only *partial* truth is ever exposed — never certainty.
- **Survive** — the Al Dente Core (FSM) integrity is checked against the night's horde.
  Wrongful exiles subtract defense uptime, so the deduction failure *is* the TD failure.
- **Mutate** — between runs the chain persists: past selves become **phantom bosses**
  (Barnaby) that hunt later runs. True permadeath / difficulty scaling.

## The deduction core (the "provable machine")

The council insisted this be a real algorithm, not a vibe:

- **Suspicion graph** — `O(n²)` over 6 agents (30 edges). Every crew-bot privately scores
  every other agent and the player, but *publicly claims something different*. The gap
  between public persona and private belief is the **tell** (Penelope).
- **Trust Meter** — a real spendable resource. Reading a tell costs 1 trust.
- **Vote resolution** — deterministic given state: `correct` purge (Echo removed, becomes a
  phantom), `wrong` exile (wrong_votes++, defense uptime drops), and **partial reveal**
  (only "N of M crew are certain", never a verdict).
- **Permadeath → phantom** — an exiled Echo's data is serialized into the persistent
  `phantom_bosses` ledger and haunts the chain.

## Barnaby's fork

When the player learns they are the Echo, the run forks:

- **PLAY ALONG (survive)** — keep the Core from completing; win by *corruption*:
  a revealed Echo who chose "survive" and brings the Core down **wins the run**
  (the HOLLOW CROWN ending, +50 deception bonus in the Chain Ledger).
- **GIVE UP (surrender)** — turn yourself in. A clean end that seeds **no** phantom
  (the one clean cut), and burns debt at half rate in the Chain Ledger.

## The Chain Ledger (the economy)

The score/debt/ending layer the council's open questions asked for (TOPICS_QUESTIONS
items 3–5). Every run settles exactly once, into a persistent ledger:

**Earn rule** (`strand.score_run`, pure and deterministic):

| Source | Points |
|--------|--------|
| Night survived | +10 |
| Correct Echo purge | +40 |
| Wrongful exile | −25 |
| Banked Trust at settlement | +2 each |
| Remaining Core integrity (victories) | +1 per 2 points |
| Flawless victory (zero wrongful exiles) | +30 |
| HOLLOW CROWN (played the Echo to the end) | +50 |

**Debt** ("debt from burned scores") — a losing run burns its unearned potential
into persistent debt: `remaining_nights × 10 × 0.5 + wrongful_exiles × 5`, halved for
the CLEAN CUT (the one strategic mercy). Debt presses on every later run: horde
+0.2 per point of debt, starting Trust −1 per 10 debt (capped at −3). Victories pay
half their score against it. Cap 60.

**Named endings + flag combos** — one per terminal state, recorded with flags:

| Ending | Trigger | Flags (examples) |
|--------|---------|------------------|
| AL DENTE ASCENT | Core target reached (crew win) | flawless, phantom_seeded |
| HOLLOW CROWN | Surviving Echo corrupts the Core | hollow, flawless |
| CLEAN CUT | Self-surrender; no phantom born | hollow |
| DELETED | The Echo (you) is exiled | hollow |
| WITCH TRIAL | The innocent player is exiled | flawless |
| STATIC | Core breach as innocent crew | phantom_seeded |
| OVERRUN | Too many wrongful exiles | — |

`/sl_strand_ledger` shows the chain: score, debt, runs/wins, best nights, endings
seen (×count), flags, phantoms. Settlements print on run close via
`strand.describe_settlement`.

## Files

| File | Responsibility |
|------|----------------|
| `strand_state.lua` | Config, seeded RNG (portable xorshift32), run struct, Echo roll, phase machine, persistence |
| `strand_trust.lua` | Trust Meter, suspicion graph, tell read, confide/observe |
| `strand_vote.lua` | Meeting resolution, partial reveal, permadeath→phantom |
| `strand_wave.lua` | Night horde, socket defense, mutation set |
| `strand_core.lua` | High-level run driver (`start_run` / `turn` / summaries) |
| `strand_ledger.lua` | Chain Ledger: score earn rule, debt, named endings, flags |
| `strand_nodes.lua` | Defense sockets, turret, barricade, Al Dente Core |
| `strand_items.lua` | Scrap-defense kit, Trust charge, Void Nomad form item |
| `init.lua` | Runtime hooks + `/sl_strand_*` commands |
| `dialogues/*.yaml` | Vote-theatre / intro scenes (via the `dialogue` mod) |

## Run it

```bash
# headless verification (mirrors CI's luajit runner)
luajit tests/strand_test.lua
```
In-game: `/sl_strand_start [seed]`, then `/sl_strand_act {}` with
`read_tell/confide/observe/build/vote/choose/reveal`, `/sl_strand_status`,
`/sl_strand_stop`.

## Reuse vs new

**Reused:** `aaa_botmatch` fake-player surface (crew-bots) · sl_modebase ghost→revival
pipeline (phantoms) · `sl_modebase/entities.lua` + `sl_scary` (horde) · `dialogue`
(vote theatre) · `sl_gui/crafting_system.lua` (scrap crafting) · `sl_modebase/test_harness`
(arena). **New:** the strand itself.
