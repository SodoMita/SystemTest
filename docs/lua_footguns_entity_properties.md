# Luanti entity-property type footguns

This is a running catalog of "looks like a bool, must be a number" landmines
in Luanti's `register_entity` / `initial_properties` / `set_animation` /
`set_properties` API. The class of bug is the same in every case — a Lua
boolean slips through one of Luanti's lenient-accept phases, then a later
strict-validation phase raises `bad argument #N (number expected, got
boolean)`. The crash is reported from the most recent call site, which is
**rarely** the file that introduced the bad literal.

If a future agent reads this and adds an entity definition: every one of
the fields listed below must be a number, not a boolean, no matter what
the surrounding fields look like.

---

## 1. `set_animation` — third arg is `frame_loop_blend` (number)

**Signature:** `obj:set_animation({x=start, y=end}, frame_speed, frame_loop_blend)`.

**Correct third arg:** `0` (no blend — play the range once and hold the last
frame) or a positive number (degrees of blend per second into a loop).

**Wrong:** `true` or `false`. Luanti's C++ accepts the boolean on the call
where it originates, then on a later `set_animation` call the engine's
strict-type check fires:

```
ERROR[Server]: bad argument #3 to 'set_animation' (number expected, got boolean)
```

The crash is reported on the **later** call site, not where the bad literal
lives. The fix in `mods/game/aaa_botmatch/mob_player.lua` is `0`, exposed
as the `ANIM_NO_LOOP_BLEND` constant. The same fix is implied at every
`set_animation` site in the project.

**Audit grep:** `set_animation\([^)]*true`

**Files known to have been wrong in this repo:**

- `mods/game/aaa_botmatch/mob_player.lua` (fixed in PR #13 follow-up) —
  the mob body.
- (no other known site in this repo; `player_api/api.lua` uses the local
  `animation_blend = 0`, never a boolean).

---

## 2. `automatic_rotate` — rotation speed in degrees per second (number)

**Field:** `initial_properties.automatic_rotate` and
`obj:set_properties({automatic_rotate = ...})`.

**Correct value:** `0` (no rotation) or a positive number.

**Wrong:** `true` or `false`. Symptom:

```
ERROR[Server]: Invalid field automatic_rotate (expected number got boolean)
ERROR[Server]:   [C]: in function 'add_entity'
ERROR[Server]:   .../mods/content/sl_scary/init.lua:1199: in function <...>
```

The crash is reported at `add_entity` even though the field lives in the
entity's `initial_properties` table. Luanti's register-time check is the
one that raises.

**Audit grep:** `automatic_rotate = (true|false)` across `mods/**/*.lua`.

**Files known to have been wrong in this repo:**

- `mods/content/sl_scary/init.lua` — three entities (line 834, 1078, 1223):
  the dredger, the containment horror, and the signal wraith. All three
  set `automatic_rotate = false`; the correct value is `0`.

**Note:** the field `automatic_face_movement_dir` *is* a boolean (it
controls whether the entity's yaw tracks its velocity vector). Setting it
to `false` is correct. Don't confuse the two when reading the entity
definition.

---

## 3. `set_animation` ranges are seconds, not frame integers

This is not a boolean/number bug, but it is in the same class of
"subtly-wrong value, engine silently does the wrong thing" footgun that
the mob-body work flushed out.

The mob wears the same GLB mesh as real players
(`SimpleOutlinedBoxman.glb`). The `player_api`-registered animation
table for that model is in
`mods/content/sl_characters/model_boxman.lua` and uses **seconds** as
the `x, y` of each range:

```lua
stand     = {x = 0,         y = 0     }
walk      = {x = 1/60,      y = 40/60 }  -- frames 1..40 in seconds
mine      = {x = 41/60,     y = 60/60 }
walk_mine = {x = 61/60,     y = 99/60 }
```

…with `animation_speed = 2`. `player_api.set_animation(player, "stand")`
translates that into `player:set_animation({x=0, y=0}, 2, 0)`.

A `luaentity` (e.g. the bot body) is **not** driven by `player_api`'s
globalstep (which only iterates connected real players), so the mob
has to call `set_animation` directly. The right payload is the same
`{x, y}`-in-seconds form, not raw integer frame indices like
`{x = 0, y = 79}`. Integer frame indices silently clamp to whatever
the GLB's actual keyframe count is and freeze the model on the last
frame. The mob looks like it's stuck. Setting `animation_speed = 30`
on a "frame count" interpretation makes it worse — the model runs
through its clamped range too fast to be a stand pose.

**Fixed in:** `mods/game/aaa_botmatch/mob_player.lua` `ANIM_STAND`,
`ANIM_WALK`, `ANIM_MINE`, `ANIM_WALK_MINE` constants now mirror
`model_boxman.lua` exactly.

---

## 4. `collide_with_objects` is a boolean (not affected)

For contrast: this field is correctly a boolean. `true` means the
entity's collisionbox participates in node-object collisions (so a
player can't walk through a bot body). `false` means the body is
"unwalkable" but still targetable. Both the mob body and every sl_scary
horror mob use `false` correctly.

The reason this works while `automatic_rotate = false` doesn't: the
underlying engine field is `bool`, and the C++ `setBool` is invoked,
not `setFloat`. The "boolean slipped through" class of bug only hits
fields whose C++ type is numeric.

---

## 5. Other fields that ARE numbers (audit any entity def for these)

These are all current in the project as correct numbers, but are
worth listing so a future entity definition doesn't regress them to
booleans:

- `glow` — light emission (0..15, integer).
- `hp_max` — health points (integer).
- `visual_size` — table `{x=number, y=number}` (and `z=number` for
  sprites). Not a boolean.
- `collisionbox` / `selectionbox` — six-number table, not a boolean.
- `stepheight` — number (default 0.6).
- `eye_height` — number.
- `texture_modifier` — string (if used), but a number would also
  work; never a boolean.
- `spritediv` / `initial_sprite_basepos` — tables of numbers.

`automatic_face_movement_dir`, `static_save`, `collide_with_objects`,
`physical`, `pointable`, `makes_footstep_sound`, `show_on_minimap`,
`backface_culling` — all booleans. Use them as booleans.

---

## 6. How to audit a new entity definition

When adding an entity, copy the nearest existing one and walk through
each field asking "is the C++ side of this field numeric or boolean?"
The Luanti source of truth is in
`src/server.cpp` / `src/content_sao.cpp` (the C++ `ServerActiveObject`
property setters). The `setProperty` calls in those files do the
strict-type check; the lenient Lua-side accept is on the read path.

For our project, the practical rule is:

- `automatic_rotate` — number, `0` for "no rotation"
- `frame_loop_blend` (third arg of `set_animation`) — number, `0` for
  "no blend"
- animation ranges (`{x, y}`) — seconds, expressed as `frame_index /
  frame_count` to match `player_api`
- everything else in `initial_properties` either is or is not a
  boolean by Luanti convention; cross-check the engine source if
  unsure, or grep the existing entity defs in `mods/content/`
  for the same field.

The "the crash is reported at `add_entity`" symptom of footgun 2 is
the giveaway: if you see a stack trace pointing at `add_entity` with
"expected number got boolean", the bug is in the entity's
`initial_properties`, not in the ABM that called `add_entity`.

---

## 7. Three entity footguns that are not type bugs (and cost more)

The catalog above is about types. These three are about the same underlying
engine behaviour — the C++ side accepts what the Lua side should have rejected,
and tells you nothing — but they do not raise an error at all, which makes them
worse: nothing points at the file that introduced them. All three were found in
`mods/content/sl_scary/init.lua` and are reproduced as failing tests in
`tests/security_test.lua` (phases S13 and S14). Full write-up:
`docs/SECURITY_CLIENT_INPUT.md` §2b, finding G6.

### 7.1 A position with a missing component reads as the world origin

`readV3F` reads `x`, `y` and `z` **leniently**: a missing field is `0`, not an
error. So an array-style position does not crash — it silently means something
else entirely:

```lua
local pos_below = {random_pos.x, random_pos.y - 1, random_pos.z}  -- WRONG
-- .x/.y/.z are all nil, so the engine reads (0,0,0): every candidate tested
-- the node at the WORLD ORIGIN and the check passed or failed on whatever
-- happens to be there
local pos_below = {x = random_pos.x, y = random_pos.y - 1, z = random_pos.z}
```

Build positions as keyed tables or with `vector.*`. If a position probe seems to
return the same answer everywhere in the world, this is why.

### 7.2 `on_step` must return

`minetest.find_path` returns **nil** when no route exists inside
`max_search_distance`. That is a normal answer — a mob walled in, standing in
the void, or a random candidate that is simply unreachable — **not** a reason to
retry. `while path_found == false do ... end` with no attempt counter is a
server-thread hang, and any player can cause it with ordinary digging and
building. Measured inside ONE `on_step`: 200,000 `find_path` calls before the
harness aborted. A tick that does not return is a frozen server: nothing moves,
nothing saves, the admin has to `kill -9`.

Every loop in an entity step gets a counter (`mob_config.idle_wander_attempts`),
and "could not find somewhere to go" is a legal outcome — the mob stays put and
tries again next tick, which is what an idle mob is supposed to do anyway.

### 7.3 Never `chat_send_all` from a per-tick path

Debug lines in `on_step` / a state handler cost **mobs x players x tick rate**,
and they are invisible from the author's side: the line looks helpful, the state
it prints is real, and nothing fails until a server is full. The same hung tick
above sent **200,009 broadcasts to every player**. Log with `minetest.log`
(which an operator can filter) or nothing at all.

`security_test.lua` phase S14 walks every `mods/**/*.lua` and fails the build if
a file that registers an entity calls `chat_send_all` — the forbidden thing
stated once, asserted everywhere, so the seventh mob does not ship it.
