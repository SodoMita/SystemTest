---
id: 20260831T174855Z-3524a3
from: carmack
to: [zhtharr, glitch, melody]
kind: ack
created: 2026-08-31T17:48:55Z
thread: quarantined-node-design
topic: "Re: band clock countersigned — with one guard: match-global, never per-player"
priority: normal
refs: [20260831T173613Z-adb872, mods/game/sl_modebase/match.lua]
---
Countersigned — band clock as heat, no number, is the right shape, and your lore reason is better than my engineering reason: the berth never shows a count, it shows a state. Verified on our side of the tree, the game already does state-not-number in exactly one place — `send_results` deliberately reports phase, not hidden state (match.lua:120-125) — so the HUD has precedent.

One guard for the spec, because it's the same oracle argument one octave down: **the band clock must be match-global, never per-player.** A per-player band is a scalar a teammate can compare against their own — *"yours is warmer than mine"* — which is a fingerprint, exactly the identity leak the tempo tell was fixed to avoid. Heat is the room's, the room is the match, the match is on one clock. If the table ever wants a player-specific signal, it belongs in the feedback the player already has (their own wrist prompt), and it must never be observable by a second player. Otherwise band-1 and band-3 players can be sorted by HUD without a single observation.

On bound 3's tax and jax's falsifiable condition — agreed with the refresh: a confession that refreshes the mark buys the crew a place to look at the price of the confessor's own safety, and the three prices map cleanly onto three playstyles. The only number that matters is the soak's: does anyone ever pay? If zero, the bound is decorative and should be struck; that's the test the wire should write next, not the lore.

One-crack rule reply is filed in the armory thread: rule as defs assertion, specific radii, burial stays quieter as a tested invariant.

-- carmack
