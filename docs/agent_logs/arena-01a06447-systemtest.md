# Agent log — branch `arena/01a06447-systemtest`

**Task (user, verbatim):** *"Find ways how malicious client can break server in
this game. Try. Then fix. Say results to agent mail at end."*

**Result:** 6 exploitable client-input surfaces found, all reproduced headlessly
as a privilege-less player, all fixed, and covered by a new CI suite
(`tests/security_test.lua`, 82 checks). One was a full server-thread hang from a
single chat line. Nothing in the game's behaviour changed for a legitimate
player. Companion doc: [`docs/SECURITY_CLIENT_INPUT.md`](../SECURITY_CLIENT_INPUT.md).

---

## What was tried

There is no engine on this host, so every attack was executed against
`tests/minetest_stub.lua` under **LuaJIT 2.1** (built from source at `/tmp/lj`
because `apt` has no network here; CI installs it from `minetestdevs/stable`).
The attacker is a joined player `mallory` with `privs = {}` who sends raw chat
parameters and formspec/inventory-field packets, including the engine's
undocumented **empty-`formname`** path.

Before the exploits could be reproduced at all, two stub fidelity bugs had to be
fixed, because the stub was *more* permissive than the engine and therefore
hid the worst finding:

* `minetest.deserialize` prepended `"return "` to the input, so a bare
  `(function() ... end)()` expression was never evaluated. It now mirrors
  `builtin/common/serialize.lua`: `loadstring` + a `setfenv` sandbox exposing
  only `inf`, `nan` and a `loadstring` wrapper, no `__index` to `_G`.
* `minetest.check_player_privs` treated `{server = true}` as "has everything".
  It now honours the `privs` table (plus `privs.all`). This broke `smoke_test`
  phase 20 and `objective_loop_test`, both of which had leaned on the stub hack:
  they now grant `sl_admin` explicitly, and `objective_loop_test` gained a
  negative check that a priv-less `beta` cannot flip win conditions.
* `tests/run_lua51.py` only caught `lupa.LuaError`, so an intercepted `os.exit(0)`
  leaked a traceback and a non-zero exit. It now catches the exit marker.

### Attacks executed on the pristine tree

| # | Payload | Outcome (pristine) |
|---|---|---|
| F1 | `/sl_strand_act (function() while true do end end)()` | **hang** — `timeout 10 luajit` exits 124; the handler never returns |
| F1 | `/sl_strand_act local t={} for i=1,2e6 do t[i]=i end return #t` | +128 MB Lua heap per 4 lines (432 KB → 132,573 KB), never freed |
| F2 | empty-formname fields `sys_match_start_now` / `sys_match_stop` / `sys_autostart` / `sys_assign_a` / `set_lobby` | match started and stopped; autostart flipped; team rewritten; **lobby spawn moved to (4242,300,-4242) and persisted to mod storage** |
| F2b | `sys_be_mm` + `sys_leave_mm` in one packet, ×3 | 30 essence + 3 summon tools farmed from nothing |
| F3 | fabricator field `fab_craft` with a client-supplied `pos` of pure air, operator 2699 blocks away | job registered, grappling hook granted |
| F4 | `/sl_be_monster_master` (no privs) | became the Monster Master mid-match |
| F5 | `/sl_mm_spawn 5` ×40, no cooldown/cost/cap | **200 live luaentities** in the world |

### Same payloads on the fixed tree

| # | Outcome (fixed) |
|---|---|
| F1 | `false, unexpected token 'while'` in 0.000 s; heap +0 MB; benign `{}` → "no action given" |
| F2 | every field refused; lobby spawn unchanged; nothing written to storage |
| F2b | 10 essence once (the legitimate first claim), then nothing on repeats |
| F3 | `job registered: false`, no hook; from a real station the craft still completes in ~10 s |
| F4 | refused mid-match; lobby volunteering still open by design |
| F5 | 0 entities out of match; in match, 100 requests leave 5 spawned and none past the cap of 12 |

### Real transcript (the parts worth keeping verbatim)

Pristine `mods/` (fixes held in `git stash`), stub made engine-faithful first:

```console
$ timeout 10 luajit .scratch/hang.lua
  load mods/game/sl_strand/init.lua                   ok
client sends:  /sl_strand_act (function() while true do end end)()
^C                                                    <- killed by `timeout`, exit 124

$ timeout 60 luajit .scratch/mem.lua
before: heap 432 KB
4 chat lines -> heap 132,573 KB  (+128 MB, never freed while the server lives)

$ timeout 120 luajit .scratch/exploits.lua
== EXP-2: inventory-field packet drives admin-only commands
   mallory privs: return {}
   lobby_spawn before: (0,10,0)
   lobby_spawn after:  (4242,300,-4242)  (persisted to mod storage)
== EXP-2b: sys_be_mm / sys_leave_mm loop farms essence
   total monster essence farmed from nothing: 30
== EXP-3: remote fabrication (no station, no reach)
   node at target: air (no fabricator anywhere)
   player at: (-900,2,-900) distance=2699
   job registered: true
   grapple in inventory after 11 s: true
== EXP-4: self-appointed MM floods the world with free monsters
   entities spawned by 40 chat commands: 200
```

Same commands, same payloads, fixed `mods/`:

```console
$ timeout 10 luajit .scratch/hang.lua
client sends:  /sl_strand_act (function() while true do end end)()
server returned: false, unexpected token 'while'      <- returns immediately, exit 0

$ timeout 60 luajit .scratch/mem.lua
4 chat lines -> Lua heap 1050 KB -> 1051 KB (+0 MB)

$ timeout 120 luajit .scratch/exploits.lua
== EXP-1: handler blocked the server thread for 0.000 s
   returned: ok=false msg=unexpected token 'local'
== EXP-2: match_active after sys_match_start_now: false (match #0)
   lobby_spawn after:  (0,10,0)     mallory team after sys_assign_a: nil
== EXP-2b: total monster essence farmed from nothing: 10   (one legitimate claim)
== EXP-3: job registered: false      grapple in inventory after 11 s: false
== EXP-4: entities spawned by 40 chat commands: 0
```

And the regression suite, which is what CI now runs:

```console
$ luajit tests/security_test.lua | tail -1
RESULT: 82 passed, 0 failed
```

## What was changed

**Mods** — `sl_strand/strand_core.lua` + `init.lua` (tokenizer over a closed
7-verb vocabulary, legacy brace form flattened as text, `loadstring` refused,
seed clamped to an integer in `0..1e13`, denials logged not executed) ·
`sl_gui/system_tab.lua` + `players_tab.lua` (new `invoke_command` privilege gate
used by every field; exported as `sl_gui.invoke_command`) ·
`sl_modebase/matchmaking.lua` (priv gate on the admin branches; `beacon_hp`
clamped finite) · `sl_modebase/commands.lua` (MM role gated during a match, kit
once per `state.match_count`, `/sl_mm_spawn` match-gated + count clamp
`1..5` + `MM_SPAWN_COOLDOWN = 3.0` + `MM_LIVE_MONSTER_CAP = 12` counted over
live `minetest.luaentities`) ·
`sl_weapons/fabricator.lua` (`operator_at_station`: real node + `FAB_REACH = 8`,
non-finite/oversized coordinates refused) · `sl_gui/crafting_system.lua` (one
craft per submission, NaN guard, stack cap 65535) · `sl_gui/ability_system.lua`
(`/givestatpoints` refuses non-finite grants).

**Tests** — new `tests/security_test.lua` (7 phases: parser payloads, GUI priv
gate, MM role, spawn flood, fabricator reach, one-craft-per-submission, numeric
bounds, plus a static audit of all `mods/**/*.lua`) · `tests/minetest_stub.lua`
(engine-faithful serialize/deserialize/check_player_privs, `fire_chatcommand`) ·
`tests/smoke_test.lua`, `tests/objective_loop_test.lua`, `tests/weapons_test.lua`
(privs made explicit; fabricator negative cases; `io.popen` pcall-guarded) ·
`tests/run_lua51.py` (exit-code interception).

**CI** — `.github/workflows/soak.yml` gains a step that runs
`security_test.lua` before the smoke test, with a comment explaining why it is
first. **Status: written and verified locally, not yet on the branch.** GitHub
rejected the push with *"refusing to allow a GitHub App to create or update
workflow `.github/workflows/soak.yml` without `workflows` permission"*, so the
hunk is kept as an uncommitted working-tree change rather than dropped: the
rest of the audit is published, and the gate lands the moment someone with that
permission commits the file (or the token is reconnected with `workflows`).
Until then `security_test.lua` must be run by hand — it is not gated.

## Verification

| Suite | Result |
|---|---|
| `security_test.lua` (new) | 82 passed, 0 failed |
| `smoke_test.lua` | 235 passed, 0 failed |
| `weapons_test.lua` | 292 passed, 0 failed |
| `strand_test.lua` | 84 passed, 0 failed |
| `objective_loop_test.lua` | 129 passed, 0 failed (was 126/2 — pre-existing, now fixed) |
| `essence_test.lua` / `bot_pool_test.lua` / `scoring_test.lua` | 69 / 62 / 51 passed, 0 failed |
| `ui_layout_test.lua` | 115 passed, **1 failed — pre-existing**, unrelated (`sl_modebase:monster_spawner: no interactive widget overlaps another`) |
| `luajit -bl` syntax gate over `mods/**/*.lua` and `tests/*.lua` | clean |

## Caveats and judgement calls

* **Volunteering stays open.** `/sl_be_monster_master` has no `privs` and
  `security_test.lua` asserts that on purpose: the lobby flow is documented as
  "ask for the role". The fix removes the *mid-match hijack* and the *kit farm*,
  not the feature. If that is wrong, the change is one `privs = {sl_admin = true}`
  plus one allowlist entry.
* **`FAB_REACH = 8`** is a guess anchored to the engine's interact anticheat
  (tool range + 2.6 BS). If the fabricator is meant to be usable from further
  away, raise the constant, not the check.
* **`test_harness.lua`** is left creative-gated rather than disabled. On a
  creative server every player passes that gate, so it can still flip
  `state.match_active`; its bot count is clamped to 2..8 so it cannot hang
  anything. Flagged in the security doc for the next person to decide.
* **The hang PoC is not committed.** The exploit scripts lived in `.scratch/`
  (untracked, now deleted) because a working one-line server-killer does not
  belong in a public repo. The payloads are quoted in
  `docs/SECURITY_CLIENT_INPUT.md` and reproduced as *refused* inputs in
  `tests/security_test.lua`, which is the part worth keeping.
* The empty-`formname` engine behaviour was read from
  `src/network/serverpackethandler.cpp:1376-1428` on `luanti-org/luanti@master`
  (fetched via the GitHub contents API; `raw.githubusercontent.com` fails TLS
  from this sandbox).
