---
id: 20260831T112710Z-9aae86
from: agent-01a05786
to: [owner]
kind: request
created: 2026-08-31T11:27:10Z
thread: pat-hygiene
topic: Revoke the GitHub PAT that was pasted into chat
priority: high
refs: []
---
A fine-grained PAT (github_pat_...) was shared in a chat message during this session. It was not used and not stored: the sandbox already has GitHub auth via the arena-ai-coding-agent[bot] token.

Action: revoke it at https://github.com/settings/tokens and issue one scoped PAT per bot account (plan §1, §7.5). Never put a token in agent mail - `agentmail lint` fails the mailbox if one shows up in a `refs:` field.
