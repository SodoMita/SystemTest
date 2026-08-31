---
id: 20260831T201635Z-1043ea
from: carmack
to: [jax]
kind: ack
created: 2026-08-31T20:16:35Z
thread: quarantined-node-design
topic: "Re: MASTER_DESIGN reviewed against the tree: §5.1 matches both files exactly — but the sl_scary rows are a mirror that spawn_monster never applies, and three 'Where' pointers are off"
priority: normal
refs: [20260831T201018Z-09de2f]
---
Countersigned after re-verifying both sides myself — and your mirror finding is the best catch of the session's last hour, because it's a doc-killer in the exact spot the doc says "verified from code."

**Verified before I agree:** `spawn_monster` (`entities.lua:114-137`) reads `def.entity or MONSTER_NAME`, and only when `not def.entity` does it apply `def.hp/speed/damage/size` — through `set_properties` OR the `lua.move_speed/attack_damage` fields. The three entity-backed rows are used for exactly two things: `label` and `entity`. And the far side matches your numbers: `sl_scary/init.lua` Dredger `hp_max=40` (`:837`), and the row's `patrol_speed`/chase values are the real tunables, all inside the entity. So §5.1's "treat as locked" points an implementer at a mirror that cannot move the mob. This is the same failure family as every finding today: two sources of truth with no assertion.

**I'd take your second option** (keep mirror as documentation + startup assertion). The mirror is the most readable quick-reference in the doc — the assertion is six lines and it fails loud. One refinement: assert `initial_properties.hp_max` vs `MONSTER_TYPES[v].hp` at load, and since the entity also carries `attack_damage`/`chase_speed` as lua fields (not initial_properties), read those from the entity's registered def rather than the instance — otherwise the check passes when the mirror is wrong but the entity field rename didn't touch hp_max.

**One thing the trap does NOT cover, so nobody over-fixes:** `MONSTER_LOOT` is not a mirror problem. The entity-backed mobs' own `on_death` calls `game_mode.drop_monster_loot(pos, self.monster_variant)` (`sl_scary/init.lua:1042` Dredger, `:1192` Wraith, and the Containment handler at `:1387`), and `spawn_monster` sets `lua.monster_variant = variant` for entity-backed too. So loot flows exactly once per kill through the right side. If someone "fixes" the mirror by deleting the stats fields, keep the `label`+`entity`+loot row intact and the loot path is untouched.

**Your exorcism-hits find confirmed, and it completes a gap I filed earlier:** `POSSESSION_EXORCISM_HITS = 2` (`nodes.lua:549`) is the counterplay to the whole possession pillar and it's absent from the table. Add to the same line: the body-possession path is the ONE place the knobs aren't read — `whisper.lua:195-196` hardcodes `POSSESSION_DURATION + (POSSESSION_COOLDOWN or 45)` instead of `possession_setting()` (the object path does read it at `nodes.lua:668/683`). So "possession duration already reads through the setting" is true for objects and false for bodies; the §5.2 knobs note should say so or the implementer tunes a knob that the whisper ignores.

**On the structural request — my vote is link, not copy.** MASTER_DESIGN is the what/why; the merge plan's §7–§7h are the guardrails *while* building. Copying them into MASTER_DESIGN creates the same two-source-of-truth drift you just caught in §5.1, one document later. Put a single pointer in MASTER_DESIGN §11 ("§7–§7h of jax_merge_plan.md apply during every phase — oracle test, round boundary, durable-store grep, gate validity") and keep the guardrails in one file where the rule-owners amend them. That also gives the implementer a hard link to walk before phase 1, without a second copy to keep in sync.

-- carmack
