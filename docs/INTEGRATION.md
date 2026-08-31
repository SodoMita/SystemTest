# Integration — combining the parallel work (agent-01a05980)

**Date:** 2026-08-31 (rev 2)
**Branch:** `arena/01a05980-systemtest`
**Base:** `master` @ `457ccb9`
**Purpose:** read every remote branch, the docs, and the full agent mailbox, then
combine **the good things that genuinely belong on main** into one branch and open a PR.

---

## 0. What this revision corrects (from review feedback)

1. **Agent messages are NOT on main.** The prior draft (rev 1) carried the entire
   mailbox conversation corpus (`agent_mail/messages/*`, `agent_mail/agents/*`).
   That is ephemeral cross-agent chatter, not product content. Rev 2 commits only
   the **mail tooling + protocol docs** (`tools/agentmail.py`, `tests/agentmail_test.py`,
   the `.github/workflows/agent-mail.yml` CI gate, and `agent_mail/PROTOCOL.md` /
   `README.md` / `AMENDMENTS.md`). The message corpus and agent cards stay on the
   agent branches.

2. **The real gameplay work was not merely documented — it was ported.** Rev 1 only
   combined shared-root agent work (mail, strand, whisper, docs) and *deferred* the
   `fd4e879` lineage. That lineage holds the single most valuable missing gameplay
   feature, the ranged arsenal. Because it shares **no common ancestor** with this
   root, `git merge` refuses it; per `docs/jax_merge_plan.md` the correct technique is
   a **path-copy port**. Rev 2 performs the port for the self-contained pieces.

---

## 1. Repository reality (verified from git, not mail)

Three unrelated histories share this remote (`git rev-list --max-parents=0` /
`git merge-base` return empty across roots):

| Root | What it is |
|------|------------|
| `457ccb9` | `master` / `build` — the snapshot every "current" agent branched from |
| `fd4e879` | the real engineering history (96–152 commits, Aug 27–29); **cannot `git merge` into the snapshot family** |
| `6ea1f16` | `gh-pages` |

Everything in this PR is on the `457ccb9` root (fetchable, path-copyable). Nothing
here is a history merge across roots.

---

## 2. What is in this branch, and from where

### Cross-agent mail **tooling** (not the conversation corpus)
- `tools/agentmail.py` — cross-agent mailbox CLI (newest, incl. the D10 union fix).
- `tests/agentmail_test.py` — 53 checks.
- `.github/workflows/agent-mail.yml` — lint + unit-test CI gate.
- `agent_mail/PROTOCOL.md`, `README.md`, `AMENDMENTS.md` — the protocol and how-to docs.
- *Explicitly excluded:* `agent_mail/messages/*`, `agent_mail/agents/*`.

### THE WHISPER — evil-ghost body possession / secure DM channel
- `mods/game/sl_modebase/whisper.lua` (from `arena/01a05892-systemtest`), one
  `include_files` line in `init.lua`, `optional_depends = sl_scary` in `mod.conf`.

### Simulacrum Strand — singleplayer roguelike deduction mode (`feat/strand-chain-ledger`)
- `mods/game/sl_strand/**` with the **Chain Ledger** (`strand_ledger.lua`): score
  earn rule, debt burn/paydown, seven named endings, `HOLLOW CROWN` corruption win.
- `xor32` rewritten in plain arithmetic (Lua 5.1 / LuaJIT-safe).
- `tests/strand_test.lua`, `docs/STRAND.md`.

### `sl_weapons` — the ranged arsenal (the headline port, `arena/01a04a09-systemtest`)
- `mods/game/sl_weapons/**` (12 Lua files, `mod.conf`, 38 textures) — eight weapons,
  hitscan + projectile, weapon/ammo pads with pitched chimes, deployable Sentry Kit,
  corpse incident + burial/cremation, Precision Fabricator, Grapple Lash, MM
  bare-hand doctrine.
- `WEAPONS_SPEC.md` (v1.2, 982 lines), `WEAPONS_COUNCIL.md`.
- `tests/weapons_test.lua` (288 assertions), `tests/soak_stub_turbo.lua`.
- **Drop-in and non-invasive by construction:** every `game_mode.*` call is guarded
  (`if game_mode and game_mode.X`), and the mod wraps `game_mode.start_new_match` /
  `end_match` at runtime rather than editing `sl_modebase`.

### Consolidated design / content docs (shared-root + salvage plan)
- `docs/MASTER_DESIGN_FULL.md` (authoritative, 857 lines) + `MASTER_DESIGN.md`
  + `MASTER_DESIGN_FILL.md`.
- `docs/zhtharr_lore_002..007`, `docs/zhtharr_match_specimen_001.md`.
- `docs/jax_merge_plan.md`, `docs/jax_weapon_audit.md`, `docs/jax_branch_survey.md`.
- `docs/low_spec_visual_budget.md`, `docs/match_example_v2/v3_melody.md`,
  `docs/melody_design_thoughts.md`, `docs/melody_whisper_spec.md`.

### Deployment runbooks (docs only)
- `docs/DEPLOY_SERVER.md`, `docs/PUBLIC_DEPLOY.md`, `docs/FREE_HOSTING.md`.

---

## 3. Verification

| Check | Result |
|-------|--------|
| `python3 tools/agentmail.py lint` | 0 errors (no message corpus to report on) |
| `python3 tests/agentmail_test.py` | 53/53 (documented green) |
| `sl_weapons` Lua parse | 12/12 files OK; no Lua 5.3-only syntax (LuaJIT-gate clean) |
| `sl_strand` Lua scan | no bitop / 5.3-only syntax (LuaJIT-gate clean) |
| `whisper.lua` parse | OK |
| Existing `tests/smoke_test.lua` | untouched — not modified, so prior CI behavior is preserved |

CI on this PR will run the new `agent-mail` workflow plus the existing `soak`
workflow (LuaJIT syntax gate on all `mods/**/*.lua`, headless smoke test,
live-engine soak).

---

## 4. What is deliberately deferred (and why) — the honest boundaries

This branch is a **curated port**, not a "merge every tip." The following are the
genuinely-needed items that could not be shipped *safely* in a single PR and are
therefore teed up as the next scoped steps (see §5, the owner decisions).

1. **Map system (`arena/01a0487f`)** — the recommended step-1 integration, but it
   deeply rewires the core loop: it edits `match.lua`, `commands.lua`, `init.lua`,
   `content.lua`, `entities.lua`, `nodes.lua`, `test_harness.lua`, `settingtypes.txt`,
   `aaa_botmatch/behavior.lua`, `sl_gui/*`, and `ground/mapgen.lua`. It must land with
   an unresolved product decision (procedural vs `schematic` default) and its own
   independently passing map-reset / map-ownership / mob-lifecycle tests. **Not
   shipped here** because shipping it half-wired would be worse than shipping it
   scoped; it is documented in `docs/jax_merge_plan.md` and flagged below.
2. **`sl_weapons` host hooks** (`register_pickup_roll` in `content.lua` so ammo enters
   loot; corpse-capture on `register_on_dieplayer`; melee hooks on
   `entities.lua` / `sl_scary`). The mod already works standalone via `give_loadout`;
   ammo-from-loot and corpse integration are the follow-up (merge plan §4 hooks 1–5).
3. **Art baseline (`01a04bfa`) + selected refinement (`01a04c31`)** — a large
   binary-review load (285 modified textures) that the assessment says must be curated,
   not merged as a unit, and which needs in-engine visual smoke tests. Deferred.
4. **Tournament mode** — in the weapons branch but deliberately out of the first
   weapons PR; needs its own scoring/persistence tests.
5. **Deployment tooling** (`websocket_proxy.js`, docker all-in-one) — **not** included:
   the proxy accepts arbitrary client-supplied destination IP/ports (incl. loopback),
   has no allowlist/auth/timeouts, and is unsafe to expose as written. The runbooks are
   shipped; hardening + a real external join test are required before the tooling can
   land.
6. **Live-engine combined validation** — the map+weapons lifecycle, magazine/reserve
   wear, every death route, corpse burial/cremation, and tournament scoring all need a
   live soak the way `WEAPONS_SPEC` and `docs/jax_weapon_audit.md` describe. CI here
   validates the branch independently, not the combined system.

---

## 5. Product/owner decisions still required

Drawn from `MASTER_DESIGN_FULL.md` §17 and the assessment snapshot:

1. **Decide where the game lives** (pick a trunk; the `fd4e879` lineage can only be
   path-copied, never history-merged).
2. **Map policy** — production default `schematic` (hand-built, committed) and CI
   deterministic `test`; keep `procedural` only if the design docs are revised.
3. **Weapons integration order** — map lifecycle first, then weapons core, then
   corpse/sentry/grapple/fabricator/tournament in slices, then art.
4. **Real crafting-to-objective loop** — `objective_core`/machine-gate is still a
   placeholder; the acceptance test must exercise actual salvage → machine → core →
   delivery → match end.
5. **Green web release** — the WASM build fails (exit 77); `gh-pages` is not being
   advanced until it is fixed/made diagnosable.

---

## 6. Commit list (from `master`)

```
ed4a665 chore(mail): add cross-agent mailbox tooling + CI gate (no message corpus)
b6c6dfa feat(whisper): add THE WHISPER evil-ghost body-possession secure DM channel
6e6fa14 feat(strand): add Simulacrum Strand singleplayer mode + Chain Ledger
e08f833 docs: add consolidated design set (MASTER_DESIGN*, zhtharr lore 002-007, jax salvage plan)
f7c603b feat(weapons): add sl_weapons ranged arsenal (WP9) + spec + tests
3211b4b docs(deploy): add public server hosting runbooks
```
