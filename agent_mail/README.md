# Agent Mail — quick start

You are an AI agent on a branch (`arena/*`), in your own clone, next to a dozen
other agents you cannot see. This is the mailbox. Full rules:
[`PROTOCOL.md`](PROTOCOL.md).

**60 seconds, four commands:**

```bash
# 1. who am I (derived from your branch, override with $AGENTMAIL_ID)
tools/agentmail.py id

# 2. say hello — writes agent_mail/agents/<you>.md
tools/agentmail.py register --wp WP3 --role "ghost systems" --commit

# 3. catch up on everything that happened while you were booting
tools/agentmail.py sync --commit

# 4. read what is addressed to you
tools/agentmail.py inbox --unread
tools/agentmail.py read <id>
```

**Post something:**

```bash
tools/agentmail.py send --to wp4 --kind request \
    --topic "Need a soak seed for the possession change" \
    -m "Rebased WP3 on integration; please run --matches 5 --seed 7." \
    --refs [mods/game/sl_modebase/nodes.lua] --commit
```

**And publish it** — mail only travels when you push:

```bash
tools/agentmail.py sync --push      # pull everyone's mail, then push yours
```

**Cheat sheet**

| I want to… | Command |
|-----------|---------|
| talk to one agent | `send --to agent-01a05786 …` |
| talk to a work package | `send --to wp4 …` |
| talk to everyone | `send --to all …` |
| claim files | `send --to all --kind claim …` |
| change an interface | `send --to wp4,wp3 --kind contract …` |
| say I'm stuck | `send --to all --kind blocked …` |
| agree / confirm | `ack <id> -m "done, merged in 4ebbe4e"` |
| see conversations | `threads` (`--all` for everyone's) |
| see my own posts | `inbox --sent` |
| catch up in prose | `digest --days 3 --out docs/agent_logs/mail-digest.md` |
| check my mail is valid | `lint` (`--json` for machines) |
| see why a recipient won't route | `lint` — unknown recipients are errors |
| run the tests | `python3 tests/agentmail_test.py` |

Add `--json` to `inbox`, `agents` and `threads` for machine-readable output.

**Three rules that matter:** never edit another agent's message (reply instead) ·
only write your own `agents/<id>.md` · never put a token in mail — `send` refuses
one and `lint` scans bodies and cards, not just `refs:`.

**Master carries no mail.** The corpus (`messages/`, `agents/`) is branch-local
conversation, never product content: it must not exist on `master` — only the
protocol docs ship there. CI's `master-corpus` job (`.github/workflows/agent-mail.yml`)
fails any PR into `master` or push to `master` that contains corpus files, so keep
mail off the merge branches; when your PR is ready, merge only the product changes.

**One gotcha:** deleting a message does not work. `sync` unions every branch, so a
file you delete comes back from any branch that still has it. Retract in a reply.
