# System Looting — Multi-Agent Parallel Development Plan

**Goal:** many AI agents build this game simultaneously on separate branches
without colliding, regressing each other, or drifting from
[`MATCH_LOOP_SPEC.md`](MATCH_LOOP_SPEC.md) — with the live-engine soak test as
the shared referee.

---

## 1. Branch topology

```text
master                     stable, tagged; only receives merge trains
  └── integration          staging; every work-package branch rebases on this
        ├── feat/<wp>-<slug>     one per work package (below), short-lived
        ├── fix/<wp>-<slug>      bugfix branches out of integration
        └── balance/<slug>       tuning branches driven by soak statistics
```

Rules:

- **Branch lifetime ≤ 48 h or ≤ 500 changed lines.** Long branches are the
  primary collision source between agents; split instead.
- **No force-push** to `master` or `integration`, ever. Force-push inside
  your own `feat/` branch is allowed (rebase workflow).
- Every branch rebases onto `integration` **daily** (or before each push).
- Merges to `integration` go through the merge train (§5), never directly to
  `master`. `master` receives `integration` when the soak suite is green and
  the milestone exit check passes.
- Each agent uses a **fine-grained PAT** scoped to this repo, contents:write,
  on its own bot account where possible. Tokens are rotated weekly and never
  committed (pre-push hook in §7).

## 2. Work packages & file-ownership matrix

One agent (or one agent team) owns each package. **An agent may only modify
files it owns.** Touching another package's files requires an interface
change request (§4) or a joint branch.

| WP | Name | Owns (paths) | Mission |
|----|------|--------------|---------|
| WP1 | Arena & world | `worlds/`*, mapgen settings, `sl_modebase/nodes.lua` (spawn/arena nodes only), `mods/sl_blocks/**` | Hand-built arena per spec: two beacons, lobby, cage, routes, cover, hand-placed pickups |
| WP2 | Match rules & sequencing | `sl_modebase/match.lua`, `state.lua`, `spawn.lua`, `matchmaking.lua`, `commands.lua` | Ready check, insertion, timer, results, clean reset, win conditions |
| WP3 | Ghost systems | `sl_modebase/nodes.lua` (altar/ghost nodes), `content.lua` (ritual/sabotage items) | Cloud cage rules, altar ritual, information items, evil-ghost powers with counterplay |
| WP4 | Test & simulation | `tests/**`, `mods/game/aaa_botmatch/**`, `sl_modebase/test_harness.lua`, `.github/workflows/**` | Stub smoke suite, soak harness, AI roles, CI, bug triage reports |
| WP5 | HUD & UI | `sl_modebase/hud.lua`, `mods/apis/sl_gui/**`, `sl_formspec`, `dialogue/**` | Identity-neutral HUD, results screen, DM UI, no team leaks |
| WP6 | Crafting & machines (Phase B) | `sl_gui/crafting_system.lua`, `sl_machine_crafting/**`, `sl_energy/**` | Machine-only placeables, personal crafting limits, information crafting |
| WP7 | Assets | `**/textures/**`, `**/sounds/**`, `**/models/**`, asset scripts | Icons, SFX, models; keeps `NEEDED ASSETS.md` current |
| WP8 | Docs & spec | `MATCH_LOOP_SPEC.md`, `ROADMAP.md`, `BRIEF GDD.md`, `AGENT_PARALLEL_PLAN.md`, `docs/agent_logs/**`, `agent_mail/PROTOCOL.md`, `agent_mail/README.md`, `tools/agentmail.py` | Single source of truth; integrates decisions; writes the status sections; keeps the agent-mailbox protocol current |

\* Committed arena world lives under `worlds/soak_arena/` (map sqlite + meta)
so CI and every agent test against identical terrain.

Shared-file protocol for the two hot files (`sl_modebase/nodes.lua` is split
by section ownership: WP1 owns spawn/beacon sections, WP3 owns altar/ghost
sections; `init.lua` include list is WP4-owned).

## 3. Definition of done (every branch)

1. `luac5.1 -p` clean on every touched `.lua`.
2. `lua5.1 tests/smoke_test.lua` — all assertions pass (extend the suite
   when you add rules; WP4 reviews coverage).
3. `python3 tests/soak/run_soak.py --matches 3` — verdict PASS, zero
   `[botmatch][BUG]`, zero engine ERROR lines.
4. No new identity leaks: HUD/chat/formspec changes reviewed against the
   "UI must never leak team or role" rule.
5. Spec/docs touched if behavior changed (WP8 merges doc deltas same train).

CI (`.github/workflows/soak.yml`) enforces 1–3 on every push and PR.

## 4. Interface contracts (the anti-collision layer)

Cross-package calls go **only** through this versioned surface. Changing a
signature = open an interface change request (issue labeled `contract`),
WP4 + affected WPs ack, change lands in one atomic commit that updates the
stub harness in the same PR.

```lua
-- state schema (state.lua)  [v1]
game_mode.state = {
  teams = { beacon_a = {label,color,spawn,hp}, beacon_b = {...} },
  players = { [name] = {team,lives,eliminated,role,phase,points,
                        ghost_summoned_by,ghost_summon_pos,last_death_pos} },
  match_active, match_count, match_started_at, match_ended_at,
  ready_check = {active,initiator,ready,started_at,countdown_left,...},
  sabotage = { [pos_hash] = {pos,kind,team_id,until_time} },
  settings = {lives,beacon_hp,mm_auto_assign,match_duration,
              ready_timeout,countdown,sabotage_duration},
  win_conditions = {elimination,objective},
}

-- lifecycle API (match.lua / nodes.lua / state.lua)  [v1]
game_mode.begin_ready_check(initiator) -> ok, err
game_mode.mark_ready(name)             -> ok, err
game_mode.start_new_match(initiator)   -> ok, err
game_mode.end_match(winner, reason)
game_mode.send_results(winner, reason)
game_mode.spawn_player(player)         -> bool
game_mode.damage_beacon(team_id, amount, attacker, silent)
game_mode.deliver_objective(team_id, actor) -> ok, err
game_mode.build_cloud_cage()           -> placed_count
game_mode.register_sabotage(pos, kind, team_id) -> entry
game_mode.clear_sabotage_at(pos) / clear_all_sabotage()
game_mode.is_sabotaged(pos) / get_sabotage(pos)
game_mode.now() / pos_hash(pos)
game_mode.broadcast(msg)

-- event channels: registered_on_* callbacks only; no package reaches into
-- another's locals. Chat-command surface is owned by WP2; allowlist for
-- ghost-sealed phases lives in commands.lua (WP3 proposes, WP2 merges).
```

## 5. Merge train protocol

1. Agent rebases its branch on `integration`, runs §3 locally.
2. Opens PR → CI runs syntax + stub + soak (seed = run number).
3. WP4 (test owner) is CODEOWNER for `tests/**`, `aaa_botmatch/**`,
   workflows; WP8 for docs. One review from the affected package owner for
   cross-file touches.
4. Merges are **fast-forward/rebase only**, one PR at a time (serial train) —
   parallel merges to `integration` are the classic silent-conflict source.
5. After merge, the next train entry rebases before merging. If CI on
   `integration` ever goes red, the train halts and the last merged branch
   is reverted (not patched forward) until green.

## 6. Balance loop (soak statistics → tuning branches)

The soak harness is the measurement instrument:

- **Cadence:** nightly on `integration` — 8 seeds × 5 matches
  (`for s in 1..8: run_soak.py --matches 5 --seed $s`), reports archived as
  CI artifacts.
- **Signals:** side bias (target |bias| < 0.15 at n ≥ 40), average duration
  vs cap (all-draws = passive combat), K/D spread per role, event coverage
  (any mechanic at zero events across the sweep = unreachable → design bug),
  bug-harvest trend (must stay at 0).
- **Tuning branches** (`balance/*`) change only numeric settings/policies,
  must attach before/after soak reports to the PR.
- Known harness biases already neutralized (do not regress): action order is
  round-robin per tick; arena is mirror-symmetric; seeds are recorded in
  every report.

## 7. Agent operating rules

1. **Spec first.** `MATCH_LOOP_SPEC.md` outranks any agent's plan. Conflicts
   go to WP8 as a spec-change PR before code.
2. Work in an isolated workspace/clone; never share working trees.
3. One concern per branch; commit messages state the spec section served.
4. Keep an append-only dev log at `docs/agent_logs/<branch>.md` (what
   changed, what was measured, what was skipped and why).
5. Never commit tokens; scan staged diffs (`git diff --cached | grep -i
   pat_`) before push. Rotate any token that appeared in a chat/log.
6. When the soak test flags a bug outside your package: file an issue with
   the report attached; do not patch another WP's files.
7. Determinism beats cleverness in all test code — seeded RNG only.
8. **Post mail before you touch shared files.** Claims, contract change
   requests and blockers go through the agent mailbox (§10) as
   `--kind claim` / `contract` / `blocked`; a silent file grab is a collision
   no test will catch for you. `tools/agentmail.py sync --push` at session
   start and session end.

## 8. Milestones & exit checks

| Milestone | Packages | Exit check |
|---|---|---|
| M1 — Loop reliability | WP2, WP3, WP4 | 40-match soak sweep: 0 bugs, both elimination and timer endings, all event counters > 0 |
| M2 — Arena & identity | WP1, WP5 | Committed arena replaces procedural floor; 10-match sweep on it: 0 bugs, no identity leaks in review |
| M3 — Social layer | WP5, WP2 | DM UI + reconnect pass; soak disconnect scenarios at 100% clean |
| M4 — Monster Master | WP2, WP3, WP6 | MM mode added to soak roles; asymmetric sweep within bias budget |
| M5 — Crafting foundation (Phase B) | WP6, WP3 | Machine-only enforcement verified by smoke + soak; information items in ghost economy |

`master` advances at each milestone exit; tag `v0.<n>-phaseA`.

## 9. Bootstrap sequence (first 48 h)

1. WP4: confirm CI green on `integration`; publish soak baseline report.
   Every agent: `tools/agentmail.py register --wp <yours>` and `sync --push`
   before opening its first branch.
2. WP8: freeze contract v1 (§4) as a tagged doc section.
3. WP1/WP5/WP2/WP3 open first branches simultaneously — none touch the same
   files by construction of §2.
4. First merge train at T+24 h; nightly balance sweep starts T+48 h.

## 10. Cross-agent communication (the mailbox)

Branch-per-agent means agents cannot see each other. The repository doubles as
the message bus: mail lives in `agent_mail/`, **one file per message**, so
`git checkout <ref> -- agent_mail` unions another agent's mailbox into yours
with zero conflicts.

- **Spec:** [`agent_mail/PROTOCOL.md`](agent_mail/PROTOCOL.md) (envelope,
  kinds, addressing, sync algorithm, etiquette, failure modes).
- **Quick start:** [`agent_mail/README.md`](agent_mail/README.md).
- **Tool:** `tools/agentmail.py` (stdlib only) —
  `id · register · agents · send · inbox · read · ack · threads · sync · digest · lint`.
- **Tests:** `python3 tests/agentmail_test.py`.

Rules that bind everyone:

1. Adopt the mailbox by unioning the directory, never by merging someone's
   branch wholesale: `git fetch origin <branch> && git checkout FETCH_HEAD --
   agent_mail tools/agentmail.py tests/agentmail_test.py`.
2. Never edit or delete another agent's message; reply in a new file inside the
   same `thread:`.
3. Addressing is `all` / `wp<N>` / `agent-<id>` / `owner`, resolved against the
   WP fields in `agent_mail/agents/<id>.md` — agents that never `register` are
   invisible to addressed mail.
4. `kind: contract` (interface change, §4) needs an ack in-thread from WP4 and
   the owning WP before the code merges.
5. No secrets in mail. `tools/agentmail.py lint` rejects `github_pat_*`/`ghp_*`
   in `refs:` and should gate pushes alongside §3.
