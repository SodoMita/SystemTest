# Incident log — 2026-08-29 13:05:43 (mortar segfault, audit of the live crash)

## Incident

Live log (owner report), singleplayer `luanti` (zsh, core dumped):

```
ACTION[Server]: zzt uses sl_weapons:mortar, pointing at [node under=6,0,0 above=5,0,0]
zsh: segmentation fault (core dumped)  luanti
```

Player `zzt` used `sl_weapons:mortar` at the node at their feet (open test
range — lobby, no active match). The process died seconds later, when the
shell detonated and the **self-splash punched the shooter**.

This was the third crash on this weapon. The two earlier ones
(v1.3.6 / v1.3.6.1) were NaN-velocity client crashes, fixed in v1.3.7 by
rebuilding the blast push from MT CTF's knockback grenade. **This one is a
different beast: an engine null-pointer dereference, introduced by the same
v1.3.7 port.**

## Audit: comparison against minetest-ctf

Reference: `MT-CTF/capturetheflag`, `mods/ctf/ctf_modes/ctf_mode_nade_fight/tool.lua`,
`knockback_grenade.on_explode` (fetched 2026-08-29, upstream master):

```lua
for _, v in pairs(minetest.get_objects_inside_radius(pos, KNOCKBACK_RADIUS)) do
    local vname = v:get_player_name()
    local player = minetest.get_player_by_name(name)

    if player and v:is_player() and v:get_hp() > 0 and v:get_properties().pointable and
    (vname == name or ctf_teams.get(vname) ~= ctf_teams.get(name)) then
        local headpos = vector.offset(v:get_pos(), 0, v:get_properties().eye_height, 0)

        v:punch(player, 1, { ... }, nil)          -- <-- ALWAYS the thrower, even against itself
        ...
        local dir = vector.direction(pos, headpos)
        if dir.y < 0 then dir.y = 0 end
        v:add_velocity(vector.multiply(dir, kb))
    end
end
```

What the port got right (kept as-is): head-targeted `vector.direction`
push, the y-clamp, the `hp > 0` / `pointable` gates, flat power with
damage carrying falloff. `vector.offset` / `vector.direction` are real
engine functions (Lua-implemented in `builtin/common/vector.lua`,
zero-safe `normalize` on all current releases) — the v1.3.7 "zero-safe on
the C++ side" phrasing was imprecise but the behaviour claim holds.

What the port got wrong — the deviation that crashed:

| | MT CTF | our v1.3.7 port |
|---|---|---|
| self-blast puncher | the thrower's ObjectRef (`v:punch(player, …)`, `player` checked non-nil) | **nil** (`W.punch_object(nil, obj, …, "mortar_self", …)`) |
| engine consequence | `puncher` never null → safe | `puncher == nullptr` → **segfault** when any `on_punchplayer` handler returns true |

CTF therefore has a 10-year production record of exactly this blast
geometry and never crashed. The port's "anonymous" self-punch was the only
nil-puncher path in the tree… plus one more found in the same audit: the
sentry turret's rounds also punched with `nil` (`turret.lua`).

## Root cause (the exact crash chain)

1. Lobby / open test range → `state.match_active == false`.
2. Shell hits the ground at zzt's feet → `W.explode` → self-splash branch →
   `W.punch_object(nil, obj, dmg, "mortar_self", dist)` →
   `obj:punch(nil, 1.0, {fleshy = dmg}, dir)`.
3. Luanti `ObjectRef::l_punch` (5.15–5.17, master): a nil puncher is
   **legal** — it is pushed into the `on_punchplayer` handlers as `nil`
   (documented: "hitter: ObjectRef — Can be nil").
4. `sl_modebase`'s guard (`match.lua`):
   `if not state.match_active then return true end` — the lobby returns
   **true** ("damage handled").
5. Luanti `PlayerSAO::punch` (`src/server/player_sao.cpp`, identical in
   5.15.0, 5.16.1, 5.17.0 **and current master**):

   ```cpp
   bool damage_handled = m_env->getScriptIface()->on_punchplayer(playersao,
           puncher, time_from_last_punch, toolcap, dir, hitparams.hp);
   if (!damage_handled) {
       setHP(..., PlayerHPChangeReason(PLAYER_PUNCH, puncher));  // null-safe
   } else { // override client prediction
       if (puncher->getType() == ACTIVEOBJECT_TYPE_PLAYER) {     // <-- NULL DEREF
           sendPunchCommand();
       }
   }
   ```

   `damage_handled == true` + `puncher == nullptr` →
   `puncher->getType()` → **SIGSEGV**. (The `!damage_handled` path is
   null-safe; only the handled branch dereferences. That is why the crash
   needs a true-returning guard: lobby, creative mode, or a ghost attacker.)

The engine bug is real and unfixed upstream (present on master at audit
time). Our game is the first to combine a nil puncher with a
true-returning guard, which is why CTF never hit it.

## Fix (v1.3.8)

Game side (we cannot ship an engine patch):

1. `mods/game/sl_weapons/api.lua` — `W.punch_object` (the single damage
   funnel) now **never hands the engine a nil puncher**: fallback is the
   victim itself (a self-punch is legal and keeps the `W.last_cause`
   stamp authoritative for the incident feed).
2. `mods/game/sl_weapons/projectiles.lua` — the self-splash punches through
   the **shooter's own ObjectRef**, CTF-faithful (comment corrected: the
   old "structurally immune" note described the NaN class, not this one).
3. `mods/game/sl_weapons/turret.lua` — sentry rounds punch through the
   **head entity** (always live while the entry exists; non-player, so MM
   bare-hand doctrine cannot read a sentry round as a doctrine strike, and
   the engine's `sendPunchCommand` branch is not triggered).
4. `tests/minetest_stub.lua` — the stub now **models the engine flaw**:
   `PlayerMeta:punch` with a nil puncher whose damage a handler handles
   raises a hard error and records it in `H.engine_crashes`. This is the
   same stub-vs-engine divergence class as v1.3.6.1 — the suites were
   green while the live engine died.
5. `tests/weapons_test.lua` — regression phase **W3f**: (a) direct proof
   the stub models the crash (nil punch + lobby guard); (b) the incident
   replayed end to end — lobby self-mortar: no crash, jump intact
   (velocity finite, `y > 0`), lobby guard still blocks damage; (c) a live
   sentry firing under a true-returning guard (creative mode + match gate)
   with log evidence that it actually shot.
6. `game.conf` / `mods/game/sl_weapons/mod.conf` — floor 5.0 → 5.6 (the
   CTF baseline of the ported code; `vector.offset` does not exist below
   5.3 and the port is held to CTF's declared baseline).

## Verification

- `luajit tests/weapons_test.lua` (engine's own runtime): **300/300**
  (was 288; +12 W3f checks).
- Revert-and-rerun (pre-fix code): W3f **fails 3 checks** — the incident
  replay and both sentry assertions — while the rest of the suite stays
  green. The regression is proven non-vacuous.
- `luajit tests/smoke_test.lua`: **127/127** (CI baseline).
- Syntax gate (engine LuaJIT, `loadfile` over every `mods/**/*.lua`): clean.
- Soak: unchanged harness; the fake players' `punch` is a no-op and never
  exercised the engine punch pipeline, which is exactly why the live
  soak stayed green — the W3f stub model closes that blind spot for the
  punch class.

## Upstream: ready-to-file Luanti issue

Title: **`PlayerSAO::punch` null-dereferences the puncher when an
`on_punchplayer` handler returns true (segfault)**

Body (draft):

> `ObjectRef:punch()` documents the puncher as "ObjectRef — Can be nil"
> and `ScriptApiPlayer::on_punchplayer` explicitly pushes `lua_pushnil`
> for a null puncher. However `PlayerSAO::punch`
> (`src/server/player_sao.cpp`) then does:
>
> ```cpp
> } else { // override client prediction
>     if (puncher->getType() == ACTIVEOBJECT_TYPE_PLAYER) {
>         sendPunchCommand();
>     }
> }
> ```
>
> with no null check. Any `on_punchplayer` handler that returns true
> (e.g. a lobby/creative damage guard) combined with a nil puncher
> segfaults the server process. Repro: `player:punch(nil, 1, {damage_groups
> = {fleshy = 1}}, nil)` while a registered `on_punchplayer` returns true.
> Suggested fix: `if (puncher && puncher->getType() == ...)` (the
> `!damage_handled` path and `LuaEntitySAO::punch` are already null-safe).
>
> Present in 5.15.0, 5.16.1, 5.17.0 and master (audited 2026-08-29).

(Not filed from this session — awaiting owner's go-ahead.)
