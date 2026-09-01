# THE WHISPER — Possessed Betrayer Voice Channel

> **Design by:** Melody (Science Team / Comms). **Status:** DESIGN SPEC — ready to build.
> **Owner ask:** yes. **Jax's knife:** yes — this is the one that "stops being a document" the day it lands.
> **Thesis:** a living player has one voice that is *supposed* to be silent. Give that voice a channel and the whole attribution spine of this game turns into a knife.

---

## 1. The one-sentence pitch

When an evil ghost possesses a *living* player (not an object — a **body**), the ghost gets a **private line out through that body**: the Betrayer can keep walking, keep acting human, keep being on a team — but they now carry a voice the ghost whispers through, and that voice is the only channel a ghost has ever had that can *lie to a living player's face*.

The ghost is famously sealed from chat. The loop in that seal is: **the seal applies to the ghost, not to the body the ghost wears.**

---

## 2. Why this is the mechanic (values → concrete)

| My value | How this delivers it concretely |
|---|---|
| **Not incomplete** | Every path closes: what happens if the Betrayer dies, disconnects, is exorcised, the match ends, the ghost re-possesses — all defined (see §7 edge cases). Nothing left as "we'll figure it out." |
| **Not unpolished** | Reuses the *existing* `dm_system.lua` formspec and the *existing* neon color language (`#00ffff` link, `#ffaa00` incoming). One new audio cue (`whisper`) so it *feels* like a ghost, not another chat window. No new shader/entity/particle = survives low-spec. |
| **Right stress, not too much** | The ghost gets **one** whisper *per possession*, on a **cooldown**, and the Betrayer **hears it too** (so they're complicit, not just a puppet). When the ghost is exorcised the channel dies and the Betrayer is *left alone with what they heard*. Stress is about *consequence*, not volume. |
| **Not too little stress** | It creates a genuine fork: a living player can now be carrying a ghost and *not know it*, or know it and be unable to prove it. That's a decision every round, not the same dread every round. |
| **Visually consistent** | Zero new visual identity. The Betrayer is visually identical (GDD:106 intact). The *only* signal is the whisper's audio filter and the fact that sometimes a "trusted" DM arrives with a faint sub-bass underneath. |
| **Not boring** | It's a brand-new *information channel* in a game whose whole currency is information. It doesn't replace a role; it upgrades the neutral-dread economy into a *relationship* economy. |

---

## 3. The rules (the whole thing, concrete)

### 3.1 Entrance
- An evil ghost uses the existing **Possession Focus** but targets a **living player** (not a node). This is an extension of `game_mode.possess_object` — a new `possess_player(target_name)` path alongside it.
- The Betrayer must be **alive**, **on a beacon team**, and **not already possessed**.
- Possessing a body is *expensive*: it costs the same one-concurrent-possession slot and a **longer** cooldown than object possession (say `possession_duration` is unchanged, but the ready-time after body-possession doubles).

### 3.2 The channel
- Once possessed, the ghost can send **one whisper per possession** via a new `game_mode.ghost_whisper(ghost_name, target_name, message)`.
- `target_name` is any **living** player — the Betrayer is **optional**, not required, as the recipient.
- **The Betrayer always hears both sides of the channel** (every send and every receive) — they are the vessel, not a black RAT.

### 3.3 Presentation (visual + audio consistency)
- Sent as the **existing DM channel** — `[SECURE LINK]` — with two differences that read as *ghost*, not as *human*:
  - The sender name is **redacted / garbled** (`[SECURE LINK] SEALED_SOURCE -> You: "…"`), never a clean player tag. This preserves identity-neutrality and sells "a voice that isn't a name." (Token is alphanumeric + underscore only — `?-`/`[ ]` are Lua pattern magic and would break `string.find`.)
  - A **low soft-whisper** plays *instead of* the normal `click`. Reuses the already-present `radio_static.ogg` as the low-spec-honest choice — the only sound change, no new asset required.
- **The Betrayer is NOT told "you are possessed."** They just get a weird message. Half the horror is *their* uncertainty.

### 3.4 Counterplay (living, immune to the ghost)
- Living players punch the Betrayer **twice** just like exorcising a possessed object → the possession is released (the ghost is pushed out), the channel dies, and the ghost eats an **extra cooldown** (`POSSESSION_EXORCISM_PENALTY`).
- **The Betrayer cannot exorcise themselves** — only other living players can. (This prevents a possessed person from just "proving" it by hitting themselves.)
- A **Signal Scanner** sweep reads a body-possession as `POSSESSION` at range (same code path as object possession, so it's free) — but it never says *who*.

### 3.5 The dilemma (why it's a knife, not a grief tool)
- The ghost has **one whisper per possession**, and the Betrayer **hears every word**. So the whisper cuts both ways:
  - Ghost → get an innocent killed, or sow a lie, or just *terrify* a target with words that name nobody.
  - Betrayer → becomes complicit, is now a witness who can't speak, and knows they're carrying something they can't explain.
- There's no "free murder." There's a **permanent, low-grade dread** that a teammate is *carrying* something. That's Melody's whole brand: dread without a spammable wrench.

---

## 4. Files (Jax asked for three mechanics + a file each — here's this one's files)

| File | Role |
|---|---|
| `mods/game/sl_modebase/whisper.lua` | **The additive build.** `possess_player`, `ghost_whisper`, `release_betrayal`, `clear_all_betrayal`, the exorcism punchplayer handler, the leave-player cleanup, the `/sl_whisper_ghost` command, and additive wrappers over `clear_all_possession` / `possession_step` so body possessions ride the existing single reset + 1 Hz tick. |
| `mods/game/sl_modebase/init.lua` | Add `"whisper.lua"` to the include list (own mod, no cross-package edit). |
| `tests/smoke_test.lua` | PHASE 10c — body possession, one-whisper budget, 2-hit player exorcism, self-exorcism block, match-end purge. |

> **No cross-package edits.** The design originally proposed touching `dm_system.lua` (WP5's), `content.lua`/`nodes.lua` (WP3's). Instead the build stays fully additive in `sl_modebase` and reuses the exported `game_mode.*` seams. This respects the claim-before-touch rule (R1 etiquette) and avoids a merge conflict with a teammate's branch.

---

## 5. Numbers to start (tuning knobs, marked — "we'll see how it plays")

| Constant | Value | Why |
|---|---|---|
| Whispers per possession | **1** | One voice per body. Two = spam = griefing. |
| Whisper cooldown | `POSSESSION_COOLDOWN` (45s) | Same rhythm as object possession. |
| Body-possession ready-time | `2 × POSSESSION_COOLDOWN` | Costly — a body is worth more than a door. |
| Betrayer exorcism hits | **2** (reuse `POSSESSION_EXORCISM_HITS`) | Same as object — one muscle memory. |
| Whisper max length | `DM_MAX_LEN` (300) | Reuse; a ghost shouldn't novel. |

---

## 6. What this does NOT do (bounded, so it doesn't become a grief tool)

- The ghost **cannot** whisper a message *and* control the Betrayer's movement. A body-possession is the *channel*, not the *driver* — the human still moves, still plays, still talks to their team. The ghost does **not** get their body.
- It **cannot** be spammed: one whisper per possession, hard gate.
- It **cannot** out the ghost: sender is always redacted, never `[SECURE LINK] GhostName`.
- It **cannot** be used outside an active match, or on a ghost, or on an `evil_ghost`.

---

## 7. Edge cases (this is where "complete" lives)

- **Betrayer dies (single-life) while possessed** → possession releases, channel closes, no leak of who they were carrying. Ghost pays no extra penalty (the body was already taken).
- **Betrayer disconnects** → possession releases on leave (hook into `clear_all_possession` / leaveplayer), channel closes.
- **Ghost re-possesses after the cooldown** → fresh single whisper, Betrayer may or may not be a new body. Old Betrayer keeps their memory but loses the channel.
- **Match ends / resets** → all body-possessions purged, all whisper state cleared (`match.lua`), same as `clear_all_possession`.
- **Betrayer is exorcised mid-whisper** → the message is **dropped** (never delivered after the fact).
- **Target is a ghost / evil_ghost / offline** → send fails with a friendly error, ghost keeps the whisper charge (don't waste it on the void).
- **Betrayer was already possessed (body)** → blocked ("This body is already spoken through").
- **Betrayer also holds an object** (object possession + body possession from *different* ghosts) → allowed; each channel independent, each one-whisper. This is a feature — two ghosts can each be in one body *and* one object, and that's a genuine mess for the living to read.

---

## 8. How to tell it's working (test, not vibes)

- The soak harness has a scenario slot for **"a ghost possesses a living player and whispers"** — extend `tests/soak` behavior so a bot-Betrayer can be target+recipient deterministically.
- Headless smoke: a new assertion in `tests/smoke_test.lua` — "ghost whisper delivers redacted to target and audible echo to Betrayer; second whisper is refused; exorcism drops a pending whisper; match end purges everything."
- The stress knob is the **one-whisper** budget. Playtest reads: "did the whisper make a *decision*, or was it just a scare?" If players start whispering on cooldown just to be creepy, we've made it too weak. If they never use it, too strong. That's a tuning test, and the knob is visible.

---

## 9. Written down so I can quote it at myself

This is the file. Not a paragraph. If anyone asks me "is the design done?" — the answer is "the thing I care about most has a file, and a build will tell us if it's good." Everything else can wait in the lore doc.

— Melody 💜
