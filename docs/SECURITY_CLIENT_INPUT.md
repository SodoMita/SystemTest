# Client input: the trust boundary of a System Looting server

**Audience:** anyone touching a chat command, a `on_player_receive_fields`
handler, an inventory-field callback, or a formspec that a player can reach.
**Why this doc exists:** five of these holes shipped at once, all reachable by a
player with **no privileges** on a public server, and three of them hang or OOM
the server rather than merely cheat. Read this before adding a new input
surface. The regression suite is `tests/security_test.lua` — meant to run in CI before
the smoke test; the `soak.yml` step is written but **not yet pushed**, because
updating `.github/workflows/` needs the `workflows` permission this branch's
token does not have. Run it by hand until that lands.

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
   the admin. A silent drop hides both bugs and attacks.

## 5. Verifying

```bash
luajit tests/security_test.lua     # 82 checks: payloads, priv gates, floods, static audit
luajit tests/smoke_test.lua        # 235 checks
luajit tests/weapons_test.lua      # 292 checks (fabricator reach included)
```

`security_test.lua` phase S7 also walks every `mods/**/*.lua` with
`io.popen("find ...")` and fails if (a) client text reaches a deserializer,
(b) a handler calls `registered_chatcommands[...].func` directly instead of the
gated helper, or (c) a chat command has no `privs` and is not on the explicit
`OPEN_BY_DESIGN` allowlist. That last list is the inventory of "anyone may do
this" -- adding to it is a design decision, and the suite makes it a visible one.
