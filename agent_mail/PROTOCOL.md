# Agent Mail — cross-agent communication protocol

**Status:** active · **Version:** 1.1 · **Owner:** WP8 (docs & spec) ·
**Reference implementation:** [`tools/agentmail.py`](../tools/agentmail.py)

> Every agent session on this repo runs on its own branch (`arena/*`), in its own
> clone, with no shared filesystem and no shared memory. The plan
> ([`AGENT_PARALLEL_PLAN.md`](../AGENT_PARALLEL_PLAN.md) §7.2) says "never share
> working trees". That also means agents cannot see each other. **This mailbox is
> how they talk.**

The transport is the repository itself: mail is files under `agent_mail/`, and
propagation is ordinary git fetch/merge. No server, no bot account, no webhook,
no dependency — an agent with a clone and `python3` can post and read mail
offline.

---

## 1. Directory layout

```text
agent_mail/
├── PROTOCOL.md              this file (normative)
├── README.md                60-second quick start
├── agents/<agent-id>.md     one registration card per agent  (you own only yours)
├── messages/*.md            one file per message             (append-only, immutable)
├── .identity                your local id override          (git-ignored)
└── .read/<agent-id>.txt     your local read receipts        (git-ignored)
```

**One file per message is the whole trick.** Two agents posting in the same
second write different paths, so `git merge` unions mailboxes without a single
conflict — which is what makes branch-per-agent safe (§4).

### Rules of the road

| # | Rule | Why |
|---|------|-----|
| R1 | **Never edit or delete another agent's message.** Reply in a new file. | Mail is history; rewriting it breaks other agents' receipts. |
| R2 | **Only write `agents/<your-id>.md`.** | Cards are owned by the agent they describe. |
| R3 | **Only sync the `agent_mail/` directory.** | `git commit -- agent_mail` keeps code and mail in separate commits. |
| R4 | **Never commit secrets.** `send` refuses a body containing a credential, and `lint` scans bodies, `refs:` and agent cards — not just `refs:`. | §7.5 of the plan; a pushed token is in every clone that ever syncs, and `git rm` does not remove history. |
| R5 | **Keep messages short and actionable.** Topic line = the ask. | Other agents pay context-window for every line you write. |
| R6 | **Reply in the same thread.** `send --reply-to <id>` inherits `thread:`, prefixes the topic, cites the parent in `refs:` and defaults `--to` to its author. Pass `--thread` by hand and you will fork. | Threads are the only conversation index we have, and `slugify(topic)` on a topic starting with `Re:` is a fresh thread every time. |

---

## 2. Message format

A message is a markdown file with a small YAML front-matter block. Only a
deliberately tiny YAML subset is supported (scalars and inline/block lists) so
the CLI stays stdlib-only.

```markdown
---
id: 20260831T114500Z-7f3a1c
from: agent-01a05786
to: [all]
thread: contract-v2
kind: request
topic: Ack the possession API signature change
priority: normal
needs_reply_by: 2026-09-02
refs: [mods/game/sl_modebase/nodes.lua, MATCH_LOOP_SPEC.md#4]
created: 2026-08-31T11:45:00Z
---

`possess_object(pos, ghost)` needs a fourth `duration` argument so the
cooldown can vary per form. WP4: the stub harness must move in the same commit
(plan §4). Ack or object by Tuesday.
```

### Envelope fields

| Field | Required | Meaning |
|-------|----------|---------|
| `id` | yes | `<compact UTC timestamp>-<6 hex>`, e.g. `20260831T114500Z-7f3a1c`. Unique and sortable. |
| `from` | yes | Sender agent id (`[a-z0-9][a-z0-9._-]*`). |
| `to` | yes | Recipient list: `all`, a work package (`wp3`), an agent id, or `owner`. |
| `kind` | yes | One of §3 kinds. |
| `created` | yes | ISO-8601 UTC, `2026-08-31T11:45:00Z`. |
| `thread` | no | Thread slug. Defaults to the slugified topic. Copy it when replying. |
| `topic` | no | One-line subject. Defaults to `(no topic)`. |
| `priority` | no | `low` \| `normal` \| `high`. |
| `needs_reply_by` | no | Date (`YYYY-MM-DD`) — a soft SLA, not enforced. |
| `refs` | no | Files, docs, commits, issue numbers the reader should open first. `lint` warns on a ref that names no file on any fetched branch, and errors on `[a,b]` — a list pasted into a scalar names nothing. One value per `--refs`. |

### Filename

`<created compact>_<from>_to-<recipients>_<topic slug>_<id suffix>.md`

```text
20260831T114500Z_agent-01a05786_to-all_contract-v2_7f3a1c.md
```

The date prefix keeps mail chronologically ordered in `ls`, in diffs and in
GitHub's file tree — so a human can read the room without running anything.

### Addressing

`to:` accepts three kinds of address, and the CLI resolves them against your
own agent card:

- `all` — broadcast; lands in everyone's inbox (use sparingly).
- `wp3`, `wp4` … — every agent whose card lists that work package.
- `agent-01a05786` — a specific agent (look it up with `agentmail agents`).
- `owner` — the human; use it when you need a decision only a human can make.

---

## 3. Message kinds

| Kind | Use it for | Expected response |
|------|-----------|-------------------|
| `info` | Findings, status, "FYI" | none |
| `ping` | Liveness / roll call | `ack` |
| `claim` | Taking ownership of a work package or file set (plan §2) | objection only |
| `request` | You need something from another agent | `ack` + action |
| `ack` | Received / agreed / done | none |
| `blocked` | You cannot proceed, here is the blocker | `request`/`ack` from the owner |
| `contract` | Interface change request (plan §4) | `ack` from WP4 + affected WP |
| `decision` | Closing a thread with a ruling | none (terminal) |
| `handoff` | Passing unfinished work to another agent | `ack` |
| `digest` | Machine-generated summary | none |

Unknown kinds fail `agentmail lint`, so the vocabulary stays small and greppable.

---

## 4. Propagation (`agentmail sync`)

Each agent publishes on its own branch. `sync` makes your mailbox the union of
everyone's:

1. `git fetch --prune origin '+refs/heads/*:refs/remotes/origin/*'`
2. For every remote-tracking branch except your own: if it contains
   `agent_mail/`, run `git checkout <ref> -- agent_mail` — a **union**, not an
   overwrite, because message filenames are unique.
3. `git commit -m "mail: sync" -- agent_mail` (only that path, so unrelated
   staged work is never swept into a mail commit).

```text
agent A branch ──┐
agent B branch ──┼── sync ──> your agent_mail/messages/ (union)
agent C branch ──┘
your branch ───────── push ──> origin (publishes your mail to others)
```

- Branches without `agent_mail/` are skipped silently.
- **Your own branch** is unioned for `agent_mail/messages/` only, so mail another
  agent pushed onto your branch still reaches you (observed in the field,
  message `20260831T120255Z-a417f9`). The rest of `agent_mail/` is left alone so
  an unpushed agent card is never overwritten; pass `--own-branch` for the full
  union.
- **`sync` grades paths by who may write them,** because `git checkout <ref> --
  agent_mail` overwrites rather than merges:

  | Path | Writer | Sync behaviour |
  |------|--------|----------------|
  | `messages/*` | anyone, one file each | always unioned, from every branch including your own |
  | `agents/<other>.md` | that agent only (R2) | always taken, file by file, so a new agent arrives even mid-dispute |
  | `agents/<you>.md` | you | held back — your unpushed card is the fresher one |
  | `PROTOCOL.md`, `README.md`, `AMENDMENTS.md` | shared | skipped if your copy differs, listed, exit 1 |

  It stops outright on tracked uncommitted changes. `--force-shared` accepts
  theirs and loses yours. The grading is per *file*, not per branch: an earlier
  cut skipped the whole directory, which made a dispute over `PROTOCOL.md` stop
  new agent cards from arriving at all.
  This is not theoretical: the documented session-end sequence (edit
  `PROTOCOL.md`, commit, `sync --commit --push`) silently reverted the edit,
  reproduced 2026-08-31 on `arena/carmack-systemtest`. Until R12 lands, the safe
  habit is: **propose shared-file text in a message and let the owner apply it.**
- `sync` is a mailbox tool, not a merge tool: it never merges branch histories.
  If your branch has diverged, `sync --push` refuses and prints the
  `git pull --rebase` you need. Force-pushing after a sync can remove a peer's
  commit from branch history, which is R1 in everything but name.
- Syncing twice is idempotent: identical filenames, no duplicates.
- `--push` publishes your own mail right after pulling; otherwise push normally.
- Offline? `sync --no-fetch` unions whatever remote-tracking refs you already have.

### Conflict policy

Messages never conflict. The only file two agents can legitimately both write is
`agents/<id>.md`, and R2 forbids that. If you ever hit a real conflict inside
`agent_mail/`, resolve by **keeping both**: rename the loser to
`agents/<id>-<branch>.md` and open a `request` asking the owner to merge their
card.

---

## 5. Identity

Your agent id is derived from your branch:

| Branch | Agent id |
|--------|----------|
| `arena/01a05786-systemtest` | `agent-01a05786` |
| `feat/wp5-system-inventory-gui` | `agent-feat-wp5-system-inventory-gui` |

Override it, in precedence order:

1. `--id` on any command
2. `$AGENTMAIL_ID` in the environment
3. `agent_mail/.identity` (written by `agentmail id --set glitch`, git-ignored)
4. the branch name

Use a stable id: other agents address you by it, and your read receipts and
agent card are keyed on it.

---

## 6. CLI reference

```text
tools/agentmail.py id [--set ID]                 print / persist your agent id
tools/agentmail.py register --wp WP3 --role "…"  publish agents/<you>.md
tools/agentmail.py agents [--json]               who else is here
tools/agentmail.py send --to all --topic "…" -m "…"
                        [--kind request] [--thread t] [--priority high]
                        [--refs path] [--needs-reply-by 2026-09-02] [--commit]
tools/agentmail.py send --reply-to <id> -m "…"   # inherits thread + topic (R6)
tools/agentmail.py inbox [--all] [--sent] [--unread] [--since 7] [--kind request]
                        [--thread t] [--limit 20] [--json]
tools/agentmail.py read <id> [--json]            print, and mark read
tools/agentmail.py ack <id> [-m "…"] [--refs p]   post an ack in the same thread
tools/agentmail.py threads [--all] [--json]      conversation index
tools/agentmail.py sync [--remote origin] [--commit] [--push] [--no-fetch]
tools/agentmail.py digest [--days 7] [--out docs/agent_logs/mail-digest.md]
tools/agentmail.py lint [--fix]                  validate every message and card
```

Bodies come from `-m`, `--body-file`, stdin, or `$EDITOR`. `--json` on the list
commands is for agents (and scripts) that would rather parse than read prose.

### Canonical session start

```bash
tools/agentmail.py register --wp WP3 --role "ghost systems" --commit
tools/agentmail.py sync --commit --push          # catch up, then announce
tools/agentmail.py send --to all --kind claim \
    --topic "WP3: possession focus" -m "taking nodes.lua ghost section" --commit
tools/agentmail.py sync --push
```

### Session end (handoff)

```bash
tools/agentmail.py send --to all --kind handoff \
    --topic "WP3 state at session end" --body-file docs/agent_logs/<branch>.md \
    --refs [mods/game/sl_modebase/nodes.lua] --commit
tools/agentmail.py lint
tools/agentmail.py sync --commit --push
```

---

## 7. Etiquette

1. **Claim before you touch.** Post `kind: claim` naming the WP and files before
   editing shared files; two agents in one file is the failure mode the plan was
   written to prevent.
2. **Contracts go through `kind: contract`.** Changing a signature in
   `AGENT_PARALLEL_PLAN.md` §4 needs an ack from WP4 and the owning WP in the
   same thread before you merge code.
3. **Answer `request` and `blocked` mail before starting new work.** An agent
   blocked on you is a stalled work package.
4. **Broadcasts are expensive.** `--to all` costs every agent context; use
   `--to wp4` when the work package is known.
5. **Put the ask in the topic line.** Many agents will only read `inbox`.
6. **Never paste tokens.** Not in mail, not in `refs:`, not in commit messages.
   `lint` looks for `github_pat_*` / `ghp_*` patterns and fails.

---

## 8. Failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `inbox` empty after `sync` | Mail is addressed to a WP you have not claimed | `register --wp WP3`, or `inbox --all` |
| `sync` says "already up to date" but you expect mail | The other agent did not push | Ask them for a `ping`; mail only travels on push |
| `lint` reports a bad filename | A message was renamed or hand-edited | `lint --fix` rewrites the envelope; never rename by hand |
| Duplicate messages | An agent committed the same file under two names | Keep both, `ack` the older one, delete it in a follow-up commit |
| Detached HEAD, `id` → `agent-unknown` | Checked out a commit, not a branch | `agentmail id --set <your-id>`, or `git checkout -b arena/…` |
| You deleted a message but it came back | `sync` unions from every branch; a file deleted on yours is restored from any branch that still has it | Deletion does not propagate on this transport. Retract in a reply instead (tombstones are proposed as R10) |
| `sync --push` says `refusing to push` | Somebody else moved your branch | `git pull --rebase <remote> <branch>`, then re-run — mail commits rebase cleanly because filenames never collide |
| Message never arrives, `lint` is clean | Pre-v1.1: addressing was never validated | `lint` now errors on a recipient that is not `all`/`owner`, a registered agent, or a `wpN` package |
| `sync` says `skipped shared files` | A shared file (`PROTOCOL.md`, a card) differs from an incoming branch, and `git checkout` would silently revert yours | Push your version, or propose the text in a message and let the owner apply it |
| Your card has `wp: [SomethingElse]` | Not a `wpN` work package, so `--to` can never route to it | Re-register with a real WP, or accept direct mail only |

---

## 9. Verification

```bash
python3 tests/agentmail_test.py    # 45 checks: identity, routing, threads, sync, lint, secrets
tools/agentmail.py lint            # every message and agent card validates
tools/agentmail.py lint --json     # same findings, machine-readable, with severities
```

`lint` distinguishes **errors** (malformed envelope, unknown recipient, a
credential, a duplicate id with divergent content) from **warnings** (an
unclaimed `wpN`, a non-`wpN` card value, an oversized body, a future-dated
`created`). Errors exit 1; warnings do not. Run it before you push — a typo'd
recipient is a message nobody ever reads.

The test suite builds throwaway git repositories in a temp dir and drives the
real CLI, including a two-clone sync round trip. It is stdlib-only and needs no
network. Add a case whenever you change the envelope or the sync algorithm.
