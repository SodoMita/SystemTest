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
first. **Status: landed** as `5de36d2` — the suite is gated on every push and
pull request. (The first attempt was rejected with *"refusing to allow a GitHub
App to create or update workflow `.github/workflows/soak.yml` without
`workflows` permission"*; it went through once the token had that scope.) A
later cosmetic reword of the step's comment is still an uncommitted
working-tree change, because the token in this sandbox lost that scope again
mid-session — see the round-two caveats.

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

---

# Round two — "find other vulnerabilities, then make a PR"

Same brief, same method, new ground: nothing below is a restatement of F1–F6.
Findings are written up in `docs/SECURITY_CLIENT_INPUT.md` §2b as **G1–G6**;
this log keeps the parts that are about *how*, and the judgement calls.

## What was tried

The round-one pass attacked the doors a client can walk through: chat params,
formspec fields, the empty-`formname` bypass. Round two went looking for the
classes that survive a correct privilege check, because those are the ones a
careful reviewer still ships:

1. **Names the game invents.** Bots, fake players, roster entries — generated
   server-side, so nobody thinks of them as input, then rendered into formspecs
   for every viewer. → **G1**.
2. **Open-by-design commands and the state behind them.** `/sl_strand_*` is
   correctly open; the *run* it touches is one global slot. → **G2**.
3. **Disconnect as an attack.** Join, start something long-lived, leave. Repeat
   with a fresh name. → **G3**.
4. **Numbers that are valid Lua and invalid state.** `1e999`, `nan`, `12.5` —
   round one found two of these; the sweep for the rest found the map seed,
   which is the one that gets **persisted**. → **G4**.
5. **The cost of refusing.** Round one made denials loud (rule 6). Loud, per
   packet, with no rate limit on the packet, is a write amplification — and the
   same asymmetry let a re-claim of an already-held role re-broadcast and
   re-spawn once per packet. → **G5**.
6. **Code a client can reach without sending anything.** Entities: a mob that
   cannot find a path is a *normal* game state, and any player can create it
   with a wall. → **G6**.

Approach that worked: make the stub faithful first, then read the code again.
Four of the six only became visible (or only became reproducible) once the stub
behaved like the engine — `core` as an alias, `vector.floor`/`divide`/`zero`,
position hashing as lenient as `readV3F`, `core.after` snapshot-then-run with
cancellable handles, `fire_leaveplayer`, real `formspec_escape`, real
`explode_*_event` + `string.split`/`trim`, and `minetest.get_version`. The
lenient `readV3F` behaviour is what turned G6's array-style `pos_below` from
"invisible" into "reads the world origin": each fidelity fix unmasked the next.

## Evidence

Before/after, all measured in the headless harness (`.scratch2/`, untracked):

| Finding | Before | After |
|---|---|---|
| G1 | hostile bot name accepted; raw `]label[0,0;…` in the admin's form | refused by the charset gate; escaped per entry at all three sinks |
| G2 | stranger's vote ejected the crew bot; stranger's `stop` ended the run and wrote the ledger | every foreign `act`/`status`/`stop` refused ("that strand belongs to victim"); run + ledger intact |
| G3 | 8 orphans → formspec rebuilds and re-armed timers for 40 s after departure | 0 rebuilds, 0 timers, 0 lines typed to a departed player |
| G4 | `/sl_map seed 1e999` → `runtime.seed = inf`, persisted | `ok = false`, `runtime.seed` unchanged; a finite integer is pinned exactly |
| G5 | 200 packets → 200 log lines + 200 chat replies; 200 refused role claims → 200 log lines; 200 re-claims → 200 broadcasts + 200 respawns | 1 log line + 1 reply per 2 s window (count carried forward); 1 line for 200 refused claims; 0 broadcasts, 0 respawns |
| G6 | one `on_step`: 200,000 `find_path` calls + 200,009 `chat_send_all` broadcasts, then the harness aborted | `on_step` returns immediately; ≤ 4 path searches; 0 broadcasts |

## What was changed

**Mods** — `content/sl_scary/init.lua` (`handle_idle` bounded by
`mob_config.idle_wander_attempts = 4`; a candidate needs **both** a non-walkable
target and walkable floor; `pos_below` is a real vector; four debug
`chat_send_all` calls deleted) · `game/sl_strand/init.lua`
(`strand.is_run_owner` + gates on `act`/`status`/`stop`; `stop_solo` clears
`active_player`; ownership released when the run ends; `sl_admin`/`server`
override) · `game/aaa_botmatch/init.lua` (`botmatch.is_valid_bot_name`:
`^[%w_%-]+$`, ≤ 20 — the engine's own player-name rules) ·
`game/sl_modebase/matchmaking.lua` (`local F = minetest.formspec_escape`; the MM
label, every `player_list` row and `format_bot_pool_line` escaped per entry;
`bot_selection` freed on leave) · `game/sl_modebase/commands.lua`
(`game_mode.throttled_log`; re-claiming a held Monster Master role is a no-op;
`/sl_map seed` requires a finite integer within ±2^31) ·
`content/dialogue/init.lua` + `chat_ui.lua` (`on_leaveplayer` →
`dlg.stop_for_player`; `M.show` refuses for a departed player; `M.cleanup` frees
the state entry) · `apis/sl_gui/system_tab.lua` (`report_denial` throttled per
player per 2 s window, first reported in full, suppressed count carried;
`comms_selection` and the throttle state freed on leave) ·
`apis/sl_gui/achievement_tracking.lua` (`player_last_y` freed on leave).

**Tests** — `tests/security_test.lua` grows from 82 to **147 checks**: six new
phases (S8 roster names, S9 run ownership, S10 disconnect, S11 non-finite world
state, S12 refusal amplification, S13 the entity step that must return), the
audit renumbered S14 with a **fourth static guard** (no `chat_send_all` in any
file that registers an entity) · `tests/minetest_stub.lua` (the fidelity list
above, including `explode_textlist_event`/`explode_table_event`/
`explode_scrollbar_event` and `string.split`/`string:trim` verbatim from
`builtin/common/misc_helpers.lua`, and `minetest.get_version`).

**Docs** — `docs/SECURITY_CLIENT_INPUT.md`: new §2b (G1–G6 with measured
numbers), §3 extended with round two's dead ends, §4 rules 6–11 (throttled
denials, leave cleanup, idempotence, generated names, bounded entity loops,
ownership), §5 rewritten around the 147-check suite and the "run it against the
old tree" discipline.

## Verification (round two)

| Suite | Result |
|---|---|
| `security_test.lua` | **147 passed, 0 failed** (was 82/0) |
| `security_test.lua` against the round-one tree (`git stash push -- mods`) | **113 passed, 34 failed** — every new phase fails without its fix |
| `smoke_test.lua` | 235 passed, 0 failed |
| `weapons_test.lua` | 292 passed, 0 failed |
| `strand_test.lua` / `bot_pool_test.lua` / `scoring_test.lua` | 84 / 62 / 51 passed, 0 failed |
| `essence_test.lua` / `objective_loop_test.lua` | 69 / 129 passed, 0 failed |
| `ui_layout_test.lua` | 115 passed, **1 failed — pre-existing**, unrelated (`sl_modebase:monster_spawner` widget overlap) |
| `soak_stub_turbo.lua` (40 simulated matches) | **SOAK VERDICT: PASS** |
| `luajit -bl` over `mods/**/*.lua` (102 files) and `tests/*.lua` | clean |

The live-engine soak (`tests/soak/run_soak.py`) needs a Luanti server binary;
this sandbox has none, so that CI step is the one thing not reproduced locally.

## Caveats and judgement calls (round two)

* **G6 is latent, and was fixed anyway.** `sl_scary:nerobot` is registered but
  nothing spawns it today: match deployment uses `dredger`, `signal_wraith` and
  `containment`, and the three `/sl_spawn_*` commands (all `creative`-gated)
  cover exactly those. The alternative reading — "unreachable, leave it" — is
  how a server hang ships in the next content drop. The fix is also a behaviour
  improvement for the mobs that *are* live: the four debug broadcasts were not
  nerobot-specific in shape, and the audit guard now keeps the pattern out.
* **The bot-name charset is deliberately the engine's, not a new one.**
  `^[%w_%-]+$` and ≤ 20 characters is `PLAYERNAME_ALLOWED_CHARS` /
  `PLAYERNAME_SIZE` from `src/player.h`. If a future feature needs a bot named
  `Crew 3 (reserve)`, the right move is escaping in the renderer (already there)
  plus a considered widening of this rule — not a silent one.
* **Throttle windows are wall-clock** (`game_mode.now()` →
  `minetest.get_us_time()`), 2.0 s for both `report_denial` and
  `throttled_log`. That is long enough to cap a flood and short enough that a
  genuine second attempt by a confused admin is still explained to them.
* **`mods/content/dialogue/formspec.lua` was left broken.** Nothing `dofile`s
  it, so its state table and its leak cannot be reached; "fixing" dead code
  would only imply it runs. Recorded in §3 so the next reader does not re-find
  it.
* **`mods/external/chest_of_everything` was not audited** — the maintainer says
  it is test-only and will not be in production. Excluded from scope, findings
  and fixes alike.
* **The PoC harness is not committed.** Round two's exploit scripts live in
  `.scratch2/` (untracked, and now ignored) for the same reason round one's did:
  a working hang and a working injection payload do not belong in a public repo.
  The payloads are quoted in the security doc and re-appear in
  `tests/security_test.lua` strictly as *refused* inputs.
* **GitHub token scope flapped mid-session.** `git fetch`/`ls-remote` worked,
  then `gh api` and `git ls-remote` both started returning *Bad credentials* /
  *could not read Username*. Everything above is committed locally on
  `arena/01a06447-systemtest`; if the push or the PR is missing, that is why,
  and reconnecting GitHub in Arena is the fix. The cosmetic `soak.yml` reword is
  still uncommitted for the same permission reason as round one.
