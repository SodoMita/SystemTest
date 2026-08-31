# Agent log — `arena/01a05786-systemtest`

Append-only, per `AGENT_PARALLEL_PLAN.md` §7.4.

**Branch:** `arena/01a05786-systemtest` (fork of `arena/01a05759-systemtest` @ `4ebbe4e`)
**Agent id:** `agent-01a05786` · **WP:** WP8 (docs & spec) · **Role:** agent-mail protocol

## 2026-08-31 — Agent mail: a git-native mailbox for cross-agent conversation

**Claimed:** `agent_mail/**`, `tools/agentmail.py`, `tests/agentmail_test.py`, plus
the doc deltas in `AGENT_PARALLEL_PLAN.md` and this log. Nothing under `mods/`,
`tests/soak/` or `.github/workflows/` was touched — WP1-WP7 and WP4 own those.

### The problem

The repo runs branch-per-agent (`git ls-remote` shows 19 live `arena/*`
branches) and §7.2 forbids shared working trees. The consequence nobody had
addressed: **agents cannot see each other at all.** Claims, contract change
requests and blockers had no transport, so collisions were only detectable after
the merge train hit them.

### Design decisions

- **Transport = the repository.** `agent_mail/messages/<one file per message>`.
  Unique filenames make `git checkout <ref> -- agent_mail` a *union* instead of
  an overwrite, so adopting the mailbox never merges someone else's code and
  never conflicts — that property is what makes branch-per-agent survivable.
- **No dependency, no server, no bot account.** Python 3 stdlib only; the repo
  has no PyYAML, so the CLI carries a ~60-line front-matter parser supporting
  scalars plus inline and block lists.
- **Identity derived from the branch** (`arena/01a05786-systemtest` →
  `agent-01a05786`), overridable via `--id`, `$AGENTMAIL_ID` or a git-ignored
  `agent_mail/.identity`.
- **Addressing by work package.** `to: [wp3]` resolves against the `wp:` field
  of every registered agent card, so you can reach "whoever owns ghosts" without
  knowing which session that is this week.
- **Read receipts are local and git-ignored** (`agent_mail/.read/`), so
  "unread" is a per-agent view and never creates churn in shared files.
- **Commits touch only `agent_mail`.** `git commit -- agent_mail` keeps mail and
  code in separate history; verified by test that unrelated staged work is not
  swept in.

### What landed

| File | What |
|---|---|
| `agent_mail/PROTOCOL.md` | Normative spec: layout, envelope, kinds, addressing, sync algorithm, etiquette, failure modes |
| `agent_mail/README.md` | 60-second quick start + cheat sheet |
| `agent_mail/agents/agent-01a05786.md` | This agent's card (registered through the CLI) |
| `agent_mail/messages/*.md` | Bootstrap broadcast (`--to all`) + PAT-hygiene request (`--to owner`) |
| `tools/agentmail.py` | CLI: `id · register · agents · send · inbox · read · ack · threads · sync · digest · lint` |
| `tests/agentmail_test.py` | 27 checks, stdlib, no network |
| `AGENT_PARALLEL_PLAN.md` | WP8 ownership row extended; §7 rule 8 (post mail before touching shared files); new §10; §9 bootstrap step |
| `.gitignore` | `/agent_mail/.identity`, `/agent_mail/.read/` |

### What was measured

- `python3 tests/agentmail_test.py` — **27 checks, OK.** Covers identity
  derivation (arena + plain branches, env override, persisted override), agent
  card merge semantics, send/read round trip, unread receipts, WP routing,
  thread grouping and `ack`, unique filenames under same-second posting,
  stdin bodies, commit isolation, lint (bad kind, missing fields, malformed id,
  token-shaped refs, `--fix`), digest output, and a **two-clone sync round trip**
  (A publishes → B publishes → both converge → second sync is a no-op).
- `tools/agentmail.py lint` — clean on the mailbox as committed.
- No Lua was touched, so `tests/smoke_test.lua` / `soak` were not re-run; the
  change is docs + a standalone Python tool.
- **Live adoption check:** cloned this branch into a scratch checkout on a
  sibling branch `arena/01a05759-systemtest`, registered there as WP4, and
  confirmed the union behaves: the WP4 agent sees the `all` broadcast in its
  inbox, does *not* see the `owner`- or `wp8`-addressed mail, its `ack` joins the
  `mailbox-is-open` thread, and `lint` stays clean across both agents' cards.

### Skipped, and why

- **CI integration.** The user scoped this to protocol + docs + CLI. The natural
  next step is one job in `.github/workflows/soak.yml` running
  `python3 tests/agentmail_test.py` and `tools/agentmail.py lint` — that is a
  WP4-owned file, so it needs a §4-style ack from WP4 before it lands.
- **GitHub Issues as a parallel transport.** Rejected for now: the git mailbox
  works offline, needs no extra permissions, and keeps mail in the same review
  surface as code.

### Security note

A GitHub PAT (`github_pat_…`) was pasted into the chat that opened this session.
It was **not used and not stored** — the sandbox authenticates as
`arena-ai-coding-agent[bot]`. A `kind: request` was posted to `owner` asking for
revocation and per-bot scoped tokens (§1, §7.5); `lint` now fails any mailbox
message whose `refs:` carry a `github_pat_*`/`ghp_*` shaped string.
