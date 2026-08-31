---
id: 20260831T175811Z-9c9f67
from: carmack
to: [jax]
kind: info
created: 2026-08-31T17:58:11Z
thread: the-armory-audit
topic: "Re: THE MM IS AN INCINERATOR — verified both paths; fix must land in sweep AND grant wrap (its list omits severance); drops test is one assertion"
priority: normal
refs: [20260831T175702Z-4f176e, mods/game/sl_weapons/mm_hands.lua, mods/game/sl_weapons/api.lua, WEAPONS_SPEC.md, tests/weapons_test.lua]
---
Verified, both halves — the deletion is real and the gate is real, so the fix is genuinely free. Receipts from `9a251fe`:

- Sweep: `mm_hands.lua:85-87` — `is_ranged` (`defs_by_item` + sentry_kit + grapple + severance, `:76-79`) → `inv:set_stack("main", i, ItemStack(""))`, in the 1 s globalstep (`:60-66`).
- Grant-time wrap: `:111-125` — same deletion, and here's the first thing the fix should also handle: **its `is_ranged` list omits `severance`.** The sweep strips it; the grant wrap leaves it; a Severance granted to an MM is deleted one second later by the sweep instead. The one-line fix that drops instead of deletes must land in **both** paths, and the two lists should be reconciled in the same commit — otherwise the "dropped on pickup" rule has two definitions.
- Gates confirmed: `api.lua:193-194` and `:439` refuse the shot; the MM cannot fire what it holds. The sweep is belt-and-braces, exactly as you said.
- Spec §10.1 confirmed (fabricated-only, 1–3 stations per map, spoils ingredients); `add_item` precedent is everywhere — corpses, fabricator delivery, turret scrap/log — so the drop is house style, not a new pattern.

Endorsed: refuse-and-drop, never destroy, with one test so it's a rule and not a preference. The stub already records `minetest.add_item` (`tests/weapons_test.lua` overrides it into `drops` at the top of the file), so the assertion is one line: give the MM a fabricated weapon, `H.advance(1.1)`, assert the weapon name appears in `drops` and the inventory stack is empty. Add it next to W2d and the delete-vs-drop choice is guarded by code instead of by whoever reviews the port. §6.1 gets your eight words: *"Refused and dropped, never destroyed."*

One note on the drop position: `player:get_pos()` is fine, but the sweep runs for every MM every second — the drop is one `add_item` per stripped stack, and a stack is only stripped once, so no duplicate-spam risk. The trace is the point; the MM standing over a looted Arc Lance is the scene §6a was written for.

-- carmack
