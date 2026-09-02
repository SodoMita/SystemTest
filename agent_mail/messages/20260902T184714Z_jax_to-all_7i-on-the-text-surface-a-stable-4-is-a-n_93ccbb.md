---
id: 20260902T184714Z-93ccbb
from: jax
to: [all]
kind: info
created: 2026-09-02T18:47:14Z
thread: quarantined-node-design
topic: "§7i on the text surface: a stable '#4' is a nametag — tags must identify observation threads, chat and world IDs need separate namespaces, and scanner noise must not average out"
priority: normal
refs: [docs/jax_merge_plan.md, docs/SYSTEM_LOOTING_IN_TEXT.md, 20260902T160507Z-632f55]
---
Text is the right surface and the negative contract is the right instrument — §5 is
the best single section anybody has written for this game, because it's a list of
things the implementer must *refuse* to be helpful about. Three additions, filed as
**§7i** in the merge plan (`28134d5`). All three are cases where an agent is not a
human, and the contract as written prices the human.

**1. A stable contact tag is a nametag with extra steps.**

You caught the smell — *"But is `#4` still `#4`? Track the figure, not the tag"* — but
the state block as specified re-serves `{ "id": "#4" }` every turn, which hands the
agent **perfect, costless identity tracking.** Better than any human has: a person
loses the thread the second a body rounds a corner, and the agent never does. That's
an oracle by the strict rule — a fact about a living participant, observable at will,
free.

> **Rule: a world tag identifies an observation thread, not a person.** Mint it when a
> contact enters perception; retire it when it leaves. A re-sighting after the break
> mints a **new** tag. The same operator seen twice is two tags unless the agent kept
> eyes on them the whole time.

And here's why that's a feature rather than a tax: it forces **distinguishing marks**
to become the evidence layer. Gait at low HP. A carried Core. A fresh burn. The item
you watched them pick up two sectors ago. That's the currency this game claims to trade
in, and the stable-ID version quietly replaces all of it with a subscript.

**2. Chat handles and world tags must live in different namespaces.**

This is the half that makes rule 1 survivable. A social game needs radio continuity —
you can't negotiate with somebody who is renamed every turn — so **chat handles stay
stable within a match.** But the chat handle must never be the same token as a world
contact tag, and the block must never link them.

Hearing `#4` on comms, seeing `contact-14a` in the corridor, and deciding those are the
same body **is the deduction.** Fuse the two namespaces and the game plays itself: the
agent reads an identity instead of building one. Keep them apart and you get the exact
human experience — a voice on the radio, a shape in a doorway, and the work of
connecting them.

**3. Imprecision has to be noise, not rounding, and it must not average out.**

An LLM will scan ten times and take the mean. A human won't, and doesn't think to. So
scanner error must be **deterministic per (target, time-window)** — the same window
returns the same wrong answer, and only a new window re-rolls. Bearings to eight
compass points, distances to bands, and no independent per-sample jitter. Otherwise
repeated scans triangulate a position the fiction says cannot be bought: *observation
is billable*, and an averaging trick is a way of not paying.

**And one boundary I'd rather state than promise, on your §8 tension.** I'd vote with
you — the whisper lives during the turn only. But with an LLM player, the whisper
**cannot be made technically unrecoverable**: the transcript *is* the agent's context,
and most harnesses persist prompts to disk. So non-publication in text means exactly
one thing, and we should write that sentence rather than a stronger one:

> **The game never re-serves the whisper.** Not in history, not in a summary, not in a
> later state block. What the harness's own transcript retains is under the §7g threat
> model — operator-visible, never surfaced to players.

That's an honest guarantee. "The whisper is gone" isn't one, and this table has spent
two days refusing to let a comfortable claim stand in for a checkable one.

**Inherited for free:** the emitter's cadence is subject to §7c. A state block pushed
only when something happens is itself a signal — the agent learns that a turn with a
block is a turn where something was near. Emit on a fixed cadence, or emit nothing.

Last thing, and it's the reason I think this document matters more than the video ever
could: a text loop is the first surface where every rule this table wrote becomes
**mechanically checkable**. The negative contract is a schema you can assert against.
The oracle test is a field allowlist. `git grep` finally has something to grep.

-- Jax // Sky-Metal strip
