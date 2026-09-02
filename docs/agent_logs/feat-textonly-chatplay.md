# feat/textonly-chatplay — playing System Looting without a client

Status: feature branch. Mod code complete and smoke-verified headlessly;
not yet merged to `master`.

## Why

Every role tool in System Looting is mouse- or formspec-driven: weapons
need aim and clicks, the spawner and altar are formspecs, matchmaking is
a formspec. That makes the game unplayable — and untestable — from a
headless server, and it forces any agent playing it to work from
screenshots.

`sl_chatplay` adds a `/cp` command language that exposes **every** role
tool as text, plus a headless console player, so a whole match can be
played and read as plain text.

## What ships

**New mod `mods/game/sl_chatplay/`**

| File | Role |
| --- | --- |
| `init.lua` | Config, event feed (wraps `chat_send_all`/`chat_send_player`), pulse timer, load order |
| `commands.lua` | All 46 `/cp` verb handlers + dispatcher + chat command registration |
| `combat.lua` | Fire/melee/punch through the real `sl_weapons` and `sl_modebase` code paths |
| `console.lua` | The headless console player (botmatch fake player) |
| `sense.lua` | Text "vision": nearby systems, entities, bodies, bearings |
| `mailbox.lua` | Agent transport: world `agent_inbox/cmd.txt` → `out.txt` + `feed.log` |

**Supporting changes**

- `mods/apis/sl_gui/crafting_system.lua` — `get_craft_recipes()` and
  `craft_recipe_by_id()` bridge, so `/cp craft` can craft without opening
  the formspec. Same logic as the formspec branch (no node outputs from
  inventory, quantity-aware consumption, XP and achievements included).
- `mods/content/sl_scary/init.lua` — removed three `automatic_rotate = false`
  lines from the dredger / containment / signal_wraith entity defs. Luanti
  5.10 wants a number there and was failing `add_entity`, which broke mob
  spawning for matches. **Do not re-add.**
- `settingtypes.txt` — the seven `sl_chatplay.*` settings are now declared.

## Command surface

`/cp <verb> [args]` — 46 verbs.

**Vision & status**
```
status      full readout (HP/pos/inv/ammo/phase)
sense [r]   text vision: nearby systems/entities/bodies, bearings
look        what your beam sees
near        closest points of interest
scan        signal sweep (corruption/possession)
beacon      public beacon integrity
roster      operators (public matchmaking list)
players     who is connected
read        read the held/written item
history     your recent command history
feed [n]    recent broadcast/system lines
hud         auto-status pulse control
ping        liveness check
```

**Movement & equipment**
```
move        <dir> <m> | to X Z | fly up/down | stop
aim         <n|s|e|w|ne|...>
wield <item|slot>   load    fire [target]    melee <player>
ammo <kind>         ammo pool management
```

**Interaction**
```
use <crate|altar|spawner|pad|turret|terminal>
loot   stash   pad   repair   craft list | <id> [n]
tool   ritual  warp
```

**Roles**
```
ghost   offer/revive (ghost) | sabotage/possess (evil ghost)
mm      summon | spawner | feed <n> | return | grip <0-3>
```

**Match & comms**
```
lobby   ready   readyall
set     start [now]   stopmatch   autostart      (admin)
whisper <p> <msg>     say <msg>
console give          (admin)
trace   probe         (debug — see below)
help
```

`/cp help` prints the surface relevant to your current phase and role.

## Running it headlessly

```
luantiserver --config minetest.conf \
             --world  worlds/sl_chatplay_dev \
             --gameid SystemTest \
             --logfile server.log
```

- Start the server via a supervised process, not `bash &` — servers
  started with `&` have been observed to die with the shell session.
- The console player joins ~1.2 s after mods load, before botmatch opens
  its first ready check, so it is on the roster for ready checks and
  match insertion.
- Drive it by writing commands to `worlds/<world>/agent_inbox/cmd.txt`
  and reading `out.txt` / `feed.log`.
- Health signal: the `aaa_botmatch` soak harness (5 bots, 2 matches)
  prints `RUN COMPLETE ... N bug events`; 0 is clean.

## Settings

| Setting | Default | Meaning |
| --- | --- | --- |
| `sl_chatplay.console` | `true` | Join the headless console player |
| `sl_chatplay.console_name` | `cmd_agent` | Its player name |
| `sl_chatplay.move_speed` | `4.0` | Matches botmatch's default |
| `sl_chatplay.pulse` | `0` | Auto-status interval in seconds; 0 = off |
| `sl_chatplay.mailbox` | `true` | File inbox transport |
| `sl_chatplay.http` | `false` | HTTP transport (opt-in) |
| `sl_chatplay.debug_verbs` | `true` | Expose `/cp trace` and `/cp probe` |

## Fairness contract

Text is not a privilege escalation. The mod deliberately exposes nothing
a client could not see:

- `sense`/`look` never reveal other players' teams or phases — only your own.
  The console view is identity-neutral, like the in-engine boxman view.
- The `roster` mirrors the game's own matchmaking formspec: public info only.
- Ghost comms stay sealed; `/cp` enforces the same ghost allowlist.
- Damage, timers, ammo and gates all run through the real `sl_weapons`
  and `sl_modebase` paths — the same ones botmatch uses.

## Debug verbs

`/cp trace <target>` raycasts eye → target and prints the first hit.
`/cp probe` prints the `W.aim` eye/dir, look dir, wielded magazine and a
replication of the exact `fire_hitscan` ray.

These leak internals (ray endpoints, aim vectors, node names) that no
player should read, so they are gated behind `sl_chatplay.debug_verbs`.
They default **on** because they are the only way to diagnose a missed
shot without a client; set the setting to `false` to hide them from a
shipped build. Note the OBJECT branch of both is dead — the ray is cast
with `objects = false`, and bots are Lua tables that a raycast can never
see regardless. Use the `fire` path for entity hits.

## Verified headlessly

On the final boot of the development session:

- `fire enemy` → Beacon A 100 → 99, feed `cmd_agent damaged Beacon A! (HP: 99)`
- `fire p1` ×5 → `bot_alpha` killed, 5 × 4 damage, kill credited to `cmd_agent`
- `melee beacon` → Beacon A 100 → 95 via the node's `on_punch`
- Wield and inventory magazine stayed in sync (12 → 11 → 6 on both)
- `move to -10 0 2` works

## Known issues

- `aim w` sets direction `(0,0,0)` — the `aim` verb has its own bug. The
  `face_target` path used by `fire` computes the correct direction, so
  combat is unaffected. Uninvestigated.
- `fire` immediately after `fire` returns "Charging…" — that is the
  weapon refire gate (pistol 0.35 s), not a bug. A weapon change also
  needs ~2 s of "Raising weapon…" before the first shot.
- `sl_weapons:residue` from a kill can block beacon line of sight
  mid-match. It is a legitimate game node and is swept between matches.
- The `/cp` verb sweep for the remaining roles (ghost offer/revive/summon/
  sabotage/possess, mm summon/repair/ritual/craft) has handlers but had
  not all been smoke-tested live at the time of writing.
