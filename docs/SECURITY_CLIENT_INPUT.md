# Client input: the trust boundary of a System Looting server

**Audience:** anyone touching a chat command, a `on_player_receive_fields`
handler, an inventory-field callback, or a formspec that a player can reach.
**Why this doc exists:** five of these holes shipped at once, all reachable by a
player with **no privileges** on a public server, and three of them hang or OOM
the server rather than merely cheat. Read this before adding a new input
surface. The regression suite is `tests/security_test.lua` — it runs in CI before
the smoke test (`soak.yml`, step "Client-input security suite").
**A second audit pass found six more** (§2b): a name-injection into every
viewer's formspec, unowned strand runs, work that outlives a disconnect, a
persisted infinite map seed, refusals that amplify into floods, and an entity
step that never returns. Same method, same suite, phases S8–S13.

> **Note on `.github/workflows/`:** this branch's token cannot update workflow
> files, so a later cosmetic reword of that step's comment lives only in the
> working tree. The step itself is committed and runs.

---

## 1. What a hostile client can actually send

A Luanti client is not a browser tab -- it is a program that speaks the engine's
protocol, and any player can replace it. Three channels reach game code, and
**none of them can be trusted**:

| Channel | How it is produced | Who validates it | What game code sees |
|---|---|---|---|
| Chat | any string typed or injected | engine: command **name** must be registered; declared `privs` are enforced | `func(name, param)` -- `param` is arbitrary text |
| Formspec submit | the "real" packet carries the form's `formname` | engine: `formname` must equal the one form this peer is currently shown (`m_formspec_state_data[peer_id]`) | `on_player_receive_fields(player, formname, fields)` |
| Formspec submit, **empty formname** | a hand-rolled packet with `formname = ""` | **nobody.** The engine passes it straight through -- `handleCommand_InventoryFields`, `src/network/serverpackethandler.cpp:1376-1428` | the same handler, with a `formname` that never matched any form you sent |

Two consequences that every handler in this repo has to live with:

1. **`fields` is not "what the form I sent contained".** A priv-less client can
   deliver *any* key/value pair to *any* registered handler at *any* time.
   `if fields.admin_button then` is a privilege check written by the attacker.
   The only trustworthy facts are `player` (who sent it) and `formname` (which
   form the engine says they are looking at) -- and for the empty-formname path
   even `formname` is a lie, so **every privileged action must be gated on the
   sender's privileges, never on which fields arrived.**
2. **`param` is code-shaped text.** `minetest.deserialize`/`core.deserialize`
   is `loadstring` plus a sandbox (see
   `builtin/common/serialize.lua` in the engine). The sandbox hides engine
   globals but it does **not** stop a chunk from looping forever or allocating
   without bound, and it runs on the server thread. Passing client text to it is
   a remote hang, not a parse.

What a hostile client **cannot** do (checked against engine source, so these
do not need game-side guards): punch faster than its timer (`resetTimeFromLastPunch`
is server-side), interact beyond tool range + 2.6 blocks (`checkInteractDistance`,
anticheat on by default), reach a node inventory that is too far, or send
oversized field packets (`pkt_read_formspec_fields` caps the size).

---

## 2. What was actually broken (and how it was proven)

Every finding below was reproduced headlessly with `tests/minetest_stub.lua`
plus a LuaJIT runner, as a player named `mallory` with `privs = {}`. The stub
needed fixing first: its `minetest.deserialize` prepended `return ` to the
input, which silently made the worst bug untestable, and its
`check_player_privs` treated `{server = true}` as "everything". Both now mirror
the engine.

### F1 -- `/sl_strand_act` handed client text to `minetest.deserialize` — **CRITICAL**

```
/sl_strand_act (function() while true do end end)()
```

Pristine tree, real LuaJIT, hard timeout:

```
$ timeout 10 luajit .scratch/hang.lua     -> exit 124   (the handler never returned)
$ timeout 60 luajit .scratch/mem.lua      -> 4 chat lines: heap 432 KB -> 132,573 KB
```

One chat line freezes the server thread forever -- no player moves, no world is
saved, the admin has to `kill -9`. Four lines allocate 128 MB of Lua heap that
is never freed (the deserialized chunk stays referenced by the sandbox). It is
*not* code execution: the sandbox's environment only exposes `inf`, `nan` and a
`loadstring` wrapper, so there is no path to `minetest`, `io` or `os` -- but a
hang is total, and it needs no privileges and no rate limit.

**Fix** (`mods/game/sl_strand/strand_core.lua`, `init.lua`): a real parser.
`strand.parse_action(param)` tokenizes `verb key=value ...` and returns a table
over a **closed 7-verb vocabulary** (`read_tell confide observe build vote
choose reveal`) plus a `legacy_form` flag. The legacy brace spelling
`{type="vote",choice="yes"}` is flattened into the same vocabulary **as text**
-- brackets, quotes and parens are stripped and nothing is evaluated.
`loadstring`/`load`/`dofile`/`require` in the parameter are refused outright,
seeds are clamped to integers in `0 .. 1e13`, and a denial is a chat message
plus an action-log line, never an `execute`.

After the fix, the same payloads:

```
server returned: false, unexpected token 'while'      (0.000 s, +0 MB heap)
```

### F2 -- GUI privilege bypass through the empty-formname path — **HIGH**

`mods/apis/sl_gui/system_tab.lua` routed every field straight to
`minetest.registered_chatcommands[...].func(...)`: match start/stop, autostart,
team assignment, and the **persistent lobby spawn list**.

```
mallory privs: {}                     match_active: false -> true -> false
lobby_spawn: (0,10,0) -> (4242,300,-4242)   (written to mod storage, survives restart)
mallory team: nil -> "beacon_a"
```

**Fix:** a single `invoke_command(cmd, player, param)` gate used by every field
in `system_tab.lua` and `players_tab.lua`. It resolves the *registered*
command's `privs` table and checks `minetest.check_player_privs`; the
matchmaking terminal in `sl_modebase/matchmaking.lua` got the same check on its
admin branches. Denial = one chat line + one `action` log line.

### F2b -- the same bypass farmed the economy — **HIGH**

`sys_be_mm` / `sys_leave_mm` in one packet let a client claim the Monster Master
role, take the 10-essence kit, resign, and repeat:

```
round 1: +10 essence, summon tool      round 2: +10, tool      round 3: +10, tool
total farmed from nothing: 30 essence, 3 summon tools
```

**Fix:** the kit is granted **once per match cycle** -- it is marked on the
player meta (`mm_kit_cycle == state.match_count`) and re-granted only when a new
match starts, which is where the design intended the reset. `sys_leave_mm` is
admin-only. In the lobby, *volunteering* stays open by design (`/sl_be_monster_master`
has no `privs`); after the fix the same loop yields 10 essence once and nothing
on repeats.

### F3 -- fabrication from anywhere on the map — **MEDIUM**

The fabricator's inventory-field handler accepted a client-supplied `pos` and
started a job without checking that a fabricator node was there or that the
operator could reach it:

```
node at target: air (no fabricator anywhere)     player distance: 2699
job registered: true -> grappling hook granted
```

**Fix** (`mods/game/sl_weapons/fabricator.lua`): `operator_at_station(player, pos)`
requires the real `sl_weapons:fabricator` node at `pos` (rounded) **and** a
distance within `FAB_REACH = 8`, chosen to match the engine's interact anticheat
(tool range + 2.6). Non-finite or `|v| > 31000` coordinates are refused before
they are used. Verified both ways: at a station the craft completes in ~10 s,
from 900 blocks away or with the node broken it never registers.

### F4 -- self-appointed Monster Master — **HIGH**

`/sl_be_monster_master` was registered with no `privs`, so anyone could take the
role mid-match and displace the assigned MM.

**Fix:** allowed while no match is running (volunteering is the documented
lobby flow); during a match it requires `sl_admin` or being the already-assigned
MM.

### F5 -- unbounded entity spawn from chat — **HIGH**

`/sl_mm_spawn <count>` had no cooldown, no essence cost and no cap. Forty chat
commands produced **200 live luaentities**, each with an ABM-driven think step,
on a server that also has to tick every player.

**Fix:** refused outside a match, the requested `count` clamped to a finite
integer in `1..5`, a per-player cooldown (`MM_SPAWN_COOLDOWN = 3.0` s), and a
live-owner cap (`MM_LIVE_MONSTER_CAP = 12`) counted by `count_owned_monsters()`
over `minetest.luaentities` (filtering `_removed` ones), so the cap survives
deaths and despawns. Regression check: **100 spawn requests in one tick leave 5
entities and create none beyond the cap.** The essence-costed path (the summon
tool) is unchanged -- this command is the free convenience spawn, so it is the
one that needed a bound.

### F6 -- the test harness itself was an input surface — **MEDIUM**

`test_harness.lua` (`spawn_test_bots`, `build_test_arena`) runs on creative
servers, where *every* player has the privileges it checks. Its bot count was
already clamped to `2..8`, so the exposure was "a player can flip
`state.match_active`", which is now documented rather than fixed -- the harness
is creative-only by design. Recorded here because the next person to add a
harness command should clamp first and think about who has `creative` second.

### Also hardened while in there

* `crafting_system.lua`: **one craft per submission.** Two recipes submitted in
  the same packet used to both consume ingredients; now exactly one does, and
  the output count is clamped to a finite stack (`<= 65535`) with NaN guards.
* `matchmaking.lua`: `sett_beacon_hp` is clamped to a finite integer in
  `1..100000`. `tonumber("1e999")` is `+inf`; an infinite beacon HP makes the
  elimination win condition unwinnable for the whole session. It is an
  admin-only field, but it is still client text.
* `ability_system.lua`: `/givestatpoints` refuses non-finite grants. Infinite
  `stat_points` makes every `stat_points < cost` test false -- the entire
  ability tree for free.

---

## 2b. Round two: six more, found the same way

Same harness, same attacker (`mallory`, `privs = {}`), same rule: a finding
counts only once it has been **run**. Every number below was measured, and every
fix has a phase in `tests/security_test.lua` that fails without it — against the
round-one tree the suite reports **113 passed, 34 failed**; against this tree,
**147 passed, 0 failed**.

### G1 -- a roster name is a formspec injector — **MEDIUM**

Bot names come from an admin's `bot_add` field, i.e. from a client, and F2's
empty-formname door means *any* client can forge that packet. `add_bot` took the
name as-is, and `matchmaking.lua` rendered it into a `textlist` — where `,`
separates rows and `]` **closes the element**. A bot named
`x];label[0,0;SERVER WIPE IN 5 MIN - TRADE NOW` therefore arrived in every
admin viewer's form as raw formspec: a label the server never wrote, and room
for a button or a field after it. Reproduced: the payload was accepted into the
pool and appeared unescaped in the rendered form.

Fix, two independent gates: `botmatch.is_valid_bot_name` holds a bot name to the
rules the engine holds a *player* name to (`src/player.h`: `PLAYERNAME_SIZE` 20,
`PLAYERNAME_ALLOWED_CHARS` `a-zA-Z0-9-_`, enforced at connect with a
`WRONG_CHARS` deny) — a bot can then never carry a character a player name
cannot; and the renderer escapes **per entry** anyway
(`minetest.formspec_escape`, charset `\ [ ] ; , $`) at all three sinks: the
monster-master label, `player_list` rows, and `format_bot_pool_line`. Escaping
per entry matters: escaping the joined string would escape the row separators
too. Test: **S8**.

### G2 -- a strand run had no owner — **MEDIUM, no privileges**

`/sl_strand_*` is deliberately open (a solo side activity needs no privilege),
but `strand.run` and `strand.active_player` are **single global slots** and the
ledger is shared, persistent state. Any connected client could
`/sl_strand_act vote accused=Crew-3 player_vote=true` in somebody else's run,
`/sl_strand_status` read it, and `/sl_strand_stop` **destroy it** — writing the
aborted run's outcome into the ledger for everyone. Reproduced with two
priv-less players: the victim's crew bot was ejected by a stranger's vote, and
the stranger's `stop` ended the run.

Fix: `strand.is_run_owner(name)` — the owner, or `sl_admin`/`server` as the
operator override (a stuck run has to be clearable without the player) — gates
`act`, `status` and `stop`; `start` already refused while a run was active;
`stop_solo` clears `active_player`, and ownership is released when the run ends,
so the slot is free for the next player. Test: **S9**.

### G3 -- a disconnect left work running — **LOW-MEDIUM, no privileges**

Disconnecting is free, instant and repeatable, so anything keyed by player name
has to survive it in both directions. `/dlg_start <scene>` typed the scene out
at ~33 Hz through a chain of `core.after()` jobs; a client that started a long
scene and dropped left the chain **chatting to a player who no longer exists**,
rebuilding their formspec and re-arming timers. Measured with 8 drop-in
players: formspec rebuilds and re-armed timers continued for 40 s after the last
one left; after the fix, both are 0.

The same shape sat in four per-name tables with no leave cleanup —
`comms_selection` (sl_gui), `bot_selection` (matchmaking), `player_last_y`
(achievement tracking) and the dialogue state itself. Beyond the leak (on a
public server a client mints fresh names as fast as it can reconnect), a stale
`comms_selection` is honoured after a reconnect: the observable test is that a
target chosen before a disconnect must not be able to receive a message after
one.

Fix: `dialogue` registers `on_leaveplayer` → `dlg.stop_for_player`;
`chat_ui.M.show` refuses to build for a departed player and `M.cleanup` frees
the state entry; each per-name table is nil'd on leave. Test: **S10**.

### G4 -- `/sl_map seed` persisted `inf` and `NaN` — **LOW-MEDIUM, admin**

`tonumber("1e999")` is `+inf` and `tonumber("nan")` is NaN in LuaJIT, and the
seed was stored as-is — then `map.persist()` wrote it to **mod storage**, so it
survived restart and drove mapgen for every later match. Reproduced:
`map.runtime.seed == inf`. Same rule as the strand seed and F6b: a finite
integer within ±2^31, or refuse with the usage line; `0` unpins, as the help
text promises. Test: **S11**.

### G5 -- a refusal was an amplifier — **MEDIUM, no privileges**

Rule 6 below says denials must be loud. Loud has a cost, and the engine's
rate limits are asymmetric: **chat** is limited
(`chat_message_limit_per_10sec`, then a kick for flooding) and
**inventory-field submissions are not** — the empty-formname path is forwarded
unconditionally (`src/network/serverpackethandler.cpp:1376-1428`). So every
client-reachable refusal is a per-packet cost multiplier. Measured, before:

| 200 forged packets | server cost |
|---|---|
| `sys_match_start_now` (priv-less) | **200 action-log lines + 200 chat replies** |
| `sys_be_mm` during a live match (refused in code) | **200 action-log lines** |
| `sys_be_mm` while already the Monster Master | **200 `chat_send_all` broadcasts + 200 respawns** |

The last row is the worst: re-claiming a role you already hold fell through to
`set_monster_master()` + `game_mode.broadcast()`, so one packet re-announced
"@1 is now the Monster Master!" to every player and re-spawned the claimer —
each respawn a position update to everyone. No privileges required beyond the
open lobby volunteer path.

Fix: holding a role is a **state, not an event** — claiming it twice now returns
quietly and changes nothing; `report_denial` (sl_gui) and
`game_mode.throttled_log` (sl_modebase) write one line per player per 2 s
window, report the first in full, and carry the suppressed count
(`+199 more in 2.0s`) on the next line that is written, so the audit trail
survives without becoming a write amplification. Per-player throttle state is
freed on leave, because it is itself a per-name table (G3). Test: **S12**.

### G6 -- an entity step that never returns — **HIGH (latent)**

`sl_scary:nerobot`'s `handle_idle` was:

```lua
while path_found == false do ... end      -- no attempt counter
```

`minetest.find_path` returns **nil** whenever no route exists inside
`max_search_distance` — a mob walled in, standing in the void, or a random
candidate that is simply unreachable. `path_found` then never became true,
`sradius` was never reset (so from the second pass the inner loop broke
immediately and the candidate never changed either) and the server thread spun
**inside one `on_step`**. Measured in the headless harness: 200,000 `find_path`
calls and **200,009 `chat_send_all` broadcasts** — per-tick debug lines to every
player — before the harness gave up. A tick that does not return is a frozen
server, and causing it needs nothing exotic: any player can wall a mob in with
ordinary digging and building.

Two more defects in the same function, both found by making the stub faithful
rather than by reading:

* the "is there floor below me" probe was built array-style,
  `{random_pos.x, random_pos.y - 1, random_pos.z}`, so `.x/.y/.z` were all nil —
  and the engine reads positions with `readV3F`, where a **missing component is
  0, not an error**, so the probe silently tested the node at the world origin
  for every candidate;
* the candidate test accepted a target when **either** condition held
  ("somewhere to stand" *or* "ground to stand on"), i.e. it happily picked a
  spot inside a wall or in mid-air and then asked for a path to it.

Reachability: `sl_scary:nerobot` is registered but nothing currently spawns it —
match deployment spawns `dredger`, `signal_wraith` and `containment`, and the
three `/sl_spawn_*` commands (all `creative`-gated) cover those same three. So
this is **shipped, latent** code: HIGH the moment anything spawns it, and the
debug broadcasts were live for the mobs that *are* spawned.

Fix: the wander is bounded by `mob_config.idle_wander_attempts` (4) — try a few
candidates, and if none is reachable the mob stays put and tries again next
tick, which is what an idle mob is supposed to do anyway; a candidate now needs
**both** a non-walkable target and walkable floor; `pos_below` is a real vector;
all four debug `chat_send_all` calls are gone. Test: **S13**, plus a new static
audit guard (§5) that fails if any entity-registering file broadcasts to every
player again.

### The stub had to become faithful first

Four of the six needed engine behaviour the stub did not have, and each gap hid
the next: `core` as an alias of `minetest`; `vector.floor`/`divide`/`zero`;
position hashing as lenient as `readV3F` (missing component → 0, not an error);
`core.after` as snapshot-then-run with cancellable handles
(`builtin/common/after.lua` collects expired jobs into a list *first*, so a
callback re-arming `after(0, …)` cannot spin the global step); a
`fire_leaveplayer` hook; `formspec_escape` with the engine's charset;
`explode_textlist_event`/`explode_table_event`/`explode_scrollbar_event` and
`string.split`/`string:trim` verbatim from `builtin/common/misc_helpers.lua` —
the stub used to return `{type = "nothing"}` for every textlist event, which
silently disabled **every** GUI-selection test; and `minetest.get_version`,
without which `aaa_botmatch` does not even load. `M.step` was defined twice, so
a fix to the first definition did nothing: both now share one `M.drain_afters()`.

---

## 3. Ruled out (checked, found safe -- do not re-audit without new evidence)

Engine-enforced, so no game-side guard is needed: punch rate, interact
distance, node-inventory reach, field packet size, chat-command `privs`.

Audited and clean: `map.save_current` (no client text), `corpses.lua` `loot_all`
(removes the object and the item in one pass -- no dupe), `machine_crafting`,
the matchmaking and spawner formspecs (admin-gated after F2), outfits,
achievements, DM system, grapple, abilities, `ghost_whisper`, melee/punch
damage, dialogue YAML (file-backed, not client-backed), `sl_teleport`,
`aaa_botmatch` (`/sl_bots` requires `sl_admin`), `players_tab`.

`minetest.deserialize` appears at ~15 call sites in `mods/`; **only**
`/sl_strand_act` ever passed client text to it. The rest read mod storage,
metadata or test fixtures. That is the whole reason F1 was one line of code and
a total server hang.

**Round two also checked and found nothing:**

* `mods/external/chest_of_everything` — **out of scope by the maintainer**: a
  test-only mod that does not ship to production. Not audited, not fixed, not
  reported.
* `/dlg_start <scene>` — the scene name is a key into a registered table
  ("Scene not found" otherwise); no filesystem path is built from client text,
  so there is no traversal.
* `mods/content/dialogue/formspec.lua` — **dead code**: nothing `dofile`s it, so
  its state table and its leak are unreachable. Left alone deliberately rather
  than fixed, because "fixed" would imply it runs.
* DM system injection, `ghost_whisper` abuse, the corpse loot race, book/sign
  storage growth, and the `unified_inventory` / `character_outfit` field
  handlers: all read, all bounded or admin-gated already.
* `sl_scary:mob` (which *is* spawned, and which `map.lua` counts as a sweepable
  mob) has no unbounded loops and no broadcasts — G6 is specific to `nerobot`.

---

## 4. Rules for new input surfaces

1. **Never** pass `param`, `fields.*`, or anything else from a client to
   `minetest.deserialize`, `loadstring`, `load`, `dofile` or `require`. Parse
   text. If you need structure, send a `formname` and read *your own* fields.
2. **Every** privileged action in a fields handler checks the sender's
   privileges via the registered command's `privs` (use
   `sl_gui.invoke_command`, or copy its shape). Never infer permission from
   which fields arrived, and never from `formname` alone.
3. **Every** number from a client is checked finite, floored, and clamped to a
   range before it becomes state. `tonumber("1e999") == math.huge` and
   `tonumber` happily returns `inf`/`nan`.
4. **Every** action that creates entities, items or economy value is bounded by
   a cooldown, a cost, and a cap -- and the cap counts live objects, not
   "spawns this tick".
5. **Every** position from a client is validated against a real node and a real
   reach distance before it is used.
6. Denials are **loud**: a chat line to the sender and an `action` log line for
   the admin. A silent drop hides both bugs and attacks. **And throttled**: the
   engine rate-limits chat and nothing else, so "one log line per refusal" is a
   write amplification a client controls. One line per player per window, the
   first in full, the rest carried as a count on the next line (see
   `game_mode.throttled_log`, `report_denial`).
7. **Every table keyed by player name is freed in `register_on_leaveplayer`.**
   Disconnect is free, instant and repeatable; a name that is never reused still
   costs memory forever, and a name that *is* reused inherits the old state.
8. **Re-requesting a state you already hold changes nothing.** No re-broadcast,
   no re-spawn, no second log line. Idempotence is the difference between a
   button and an amplifier.
9. **Anything the game generates that looks like a player name follows the
   engine's player-name rules** (`PLAYERNAME_SIZE` 20, `a-zA-Z0-9-_`), and every
   name rendered into a formspec is escaped **per entry**.
10. **Every loop in an entity step has a counter.** `find_path` and `get_node`
    returning nil is a normal answer, not a retry condition. And no per-tick
    code path broadcasts to every player — that cost is
    mobs x players x tick rate, and it is invisible until somebody walls a mob
    in.
11. **A run, a session, a selection has an owner.** If a command is open by
    design, the *state* it touches must not be: check who is acting, not just
    whether they may act at all.

## 5. Verifying

```bash
luajit tests/security_test.lua     # 147 checks: payloads, priv gates, floods, hangs, static audit
luajit tests/smoke_test.lua        # 235 checks
luajit tests/weapons_test.lua      # 292 checks (fabricator reach included)
luajit tests/soak_stub_turbo.lua   # 40 simulated matches -> SOAK VERDICT: PASS
```

Phases: **S0** the mods under attack load · **S1** chat text is parsed, never
evaluated · **S2** a GUI button is not a softer door than chat · **S3** the
Monster Master role is match state · **S4** `/sl_mm_spawn` is not an unlimited
entity tap · **S5** the fabricator must still be a place · **S6/S6b** one craft
per submission, numeric fields bounded · **S8** roster names: charset then
escaped · **S9** a strand run belongs to its owner · **S10** a disconnect leaves
nothing running · **S11** no non-finite world state · **S12** a refusal is not
an amplifier · **S13** an entity whose pathfinding fails still returns ·
**S14** the tree-wide audit.

`security_test.lua` phase S14 also walks every `mods/**/*.lua` with
`io.popen("find ...")` and fails if (a) client text reaches a deserializer,
(b) a handler calls `registered_chatcommands[...].func` directly instead of the
gated helper, (c) a chat command has no `privs` and is not on the explicit
`OPEN_BY_DESIGN` allowlist, or (d) a file that registers an entity calls
`chat_send_all` — the G6 debug-broadcast pattern. That allowlist is the
inventory of "anyone may do this": adding to it is a design decision, and the
suite makes it a visible one.

**Checking that a regression test actually regresses.** Each round-2 phase was
run against the round-one tree (`git stash push -- mods`, run, `git stash pop`):
**113 passed, 34 failed**, with the failures naming the measured damage —
`on_step RETURNS when pathfinding fails -> idle wander exceeded 64 path
searches`, `200 forged admin packets write ONE action-log line (got 200)`,
`no entity code broadcasts to every player (sl_scary/init.lua:828, 904, 992,
1100)`. A new phase that passes on both trees is not a test.
