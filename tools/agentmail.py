#!/usr/bin/env python3
"""agentmail - a git-native mailbox for the AI agents working this repo.

Every agent session lives on its own branch (``arena/*``) and cannot see the
others' working trees.  ``agentmail`` turns the repository itself into the
message bus: mail lives under ``agent_mail/`` as *one file per message*, so two
agents posting at the same second never touch the same path and merging
branches is conflict-free (see ``agent_mail/PROTOCOL.md``).

Commands
    id        print (or derive) this session's agent id
    register  publish your agent card in agent_mail/agents/<id>.md
    agents    list every registered agent
    send      compose a message into agent_mail/messages/
    inbox     list mail addressed to you (or everyone)
    read      print a message (and mark it read for you)
    ack       post an acknowledgement into the same thread
    threads   list conversation threads with counts and last activity
    sync      fetch other branches and union their mailboxes into yours
    digest    render recent traffic as markdown
    lint      validate every message and agent card

Stdlib only - no pip install, no network required except for ``sync``.

Typical session
    tools/agentmail.py register --wp WP3 --role "ghost systems"
    tools/agentmail.py send --to all --topic "claiming WP3" -m "taking nodes.lua ghost section"
    tools/agentmail.py sync --push          # pull everyone's mail, publish yours
    tools/agentmail.py inbox --unread
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import random
import re
import string
import subprocess
import sys
import textwrap
from pathlib import Path

MAIL_DIRNAME = "agent_mail"
MESSAGES = "messages"
AGENTS = "agents"
READ_DIR = ".read"          # local, git-ignored read receipts
IDENTITY_FILE = ".identity"  # local, git-ignored id override

KINDS = (
    "info",       # FYI, no reply expected
    "ping",       # are you alive / I am alive
    "claim",      # I am taking ownership of a work package or file set
    "request",    # I need something from you
    "ack",        # received / agreed / done
    "blocked",    # I cannot proceed, here is why
    "contract",   # interface change request (AGENT_PARALLEL_PLAN.md §4)
    "decision",   # closing a thread with a ruling
    "handoff",    # passing unfinished work to another agent
    "digest",     # machine generated summary
)

PRIORITIES = ("low", "normal", "high")

REQUIRED_FIELDS = ("id", "from", "to", "kind", "created")
OPTIONAL_FIELDS = ("thread", "topic", "priority", "needs_reply_by", "refs")

_ID_RE = re.compile(r"^\d{8}T\d{6}Z-[0-9a-f]{6}$")
_SLUG_RE = re.compile(r"[^a-z0-9]+")
_AGENT_ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
_WP_RE = re.compile(r"^wp\d+$", re.IGNORECASE)


# --------------------------------------------------------------------------- #
# small helpers
# --------------------------------------------------------------------------- #

def now_utc() -> _dt.datetime:
    return _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0)


def iso(dt: _dt.datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def compact(dt: _dt.datetime) -> str:
    return dt.strftime("%Y%m%dT%H%M%SZ")


def parse_iso(text: str) -> _dt.datetime | None:
    try:
        return _dt.datetime.strptime(text.strip(), "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=_dt.timezone.utc)
    except (ValueError, AttributeError):
        try:
            return _dt.datetime.fromisoformat(text.strip().replace("Z", "+00:00"))
        except ValueError:
            return None


def rand_suffix(n: int = 6) -> str:
    return "".join(random.choice(string.hexdigits.lower()[:16]) for _ in range(n))


def slugify(text: str, limit: int = 40) -> str:
    out = _SLUG_RE.sub("-", text.strip().lower()).strip("-")
    return out[:limit].strip("-") or "untitled"


# --------------------------------------------------------------------------- #
# frontmatter (a deliberately tiny YAML subset: scalars + inline lists)
# --------------------------------------------------------------------------- #

def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Return (meta, body).  Missing frontmatter -> ({}, whole text)."""
    if not text.startswith("---"):
        return {}, text
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text
    meta: dict = {}
    i = 1
    while i < len(lines) and lines[i].strip() not in ("---", "..."):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if ":" not in line:
            i += 1
            continue
        key, _, raw = line.partition(":")
        key = key.strip()
        raw = raw.strip()
        if raw.startswith("[") and raw.endswith("]"):
            inner = raw[1:-1].strip()
            meta[key] = [unquote(v) for v in split_items(inner)] if inner else []
        elif raw.startswith("- "):
            items = [unquote(raw[2:].strip())]
            i += 1
            while i < len(lines) and lines[i].strip().startswith("- "):
                items.append(unquote(lines[i].strip()[2:].strip()))
                i += 1
            meta[key] = items
            continue
        elif raw == "":
            # empty value: either a real empty list or a block list follows
            j = i + 1
            items = []
            while j < len(lines) and lines[j].strip().startswith("- "):
                items.append(unquote(lines[j].strip()[2:].strip()))
                j += 1
            if items:
                meta[key] = items
                i = j
                continue
            meta[key] = []
        else:
            meta[key] = unquote(raw)
        i += 1
    body = "\n".join(lines[i + 1:]) if i < len(lines) else ""
    return meta, body.lstrip("\n")


def split_items(inner: str) -> list[str]:
    out, buf, quote = [], "", False
    for ch in inner:
        if ch == '"':
            quote = not quote
            buf += ch
        elif ch == "," and not quote:
            out.append(buf.strip())
            buf = ""
        else:
            buf += ch
    if buf.strip():
        out.append(buf.strip())
    return out


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        body = value[1:-1]
        return body.replace('\\"', '"').replace("\\\\", "\\")
    return value


def _needs_quotes(value: str) -> bool:
    if value == "" or value[0] != value.strip()[0] or value != value.rstrip():
        return True
    if value[0] in "-?:,[]{}#&*!|>'\"%@`~":
        return True
    # ':' and '#' only terminate a plain scalar when followed by whitespace
    if ": " in value or value.endswith(":") or " #" in value:
        return True
    return value.lower() in ("yes", "no", "true", "false", "null", "on", "off")


def fmt_value(value) -> str:
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(
            '"%s"' % str(v).replace('"', '\\"') if _needs_quotes(str(v)) else str(v)
            for v in value) + "]"
    text = str(value)
    if _needs_quotes(text):
        return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')
    return text


def dump_frontmatter(meta: dict, body: str) -> str:
    lines = ["---"]
    for key in REQUIRED_FIELDS + OPTIONAL_FIELDS:
        if key in meta:
            lines.append("%s: %s" % (key, fmt_value(meta[key])))
    for key, value in meta.items():
        if key not in REQUIRED_FIELDS + OPTIONAL_FIELDS:
            lines.append("%s: %s" % (key, fmt_value(value)))
    lines.append("---")
    lines.append("")
    return "\n".join(lines) + body.rstrip("\n") + "\n"


# --------------------------------------------------------------------------- #
# repo / git plumbing
# --------------------------------------------------------------------------- #

def find_root(start: Path | None = None) -> Path:
    start = (start or Path(__file__).resolve().parent).resolve()
    for candidate in [start] + list(start.parents):
        if (candidate / ".git").exists():
            return candidate
        if (candidate / MAIL_DIRNAME).is_dir():
            return candidate
    return start


def git(root: Path, *args: str, check: bool = True) -> str:
    proc = subprocess.run(
        ["git", "-C", str(root), *args],
        capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise SystemExit("git %s failed: %s" % (" ".join(args), proc.stderr.strip()))
    return proc.stdout.strip()


def current_branch(root: Path) -> str:
    # symbolic-ref also works on an unborn branch (fresh clone, no commits yet),
    # where `rev-parse --abbrev-ref HEAD` fails.
    out = git(root, "symbolic-ref", "--short", "-q", "HEAD", check=False)
    if out:
        return out
    out = git(root, "rev-parse", "--abbrev-ref", "HEAD", check=False)
    return "" if out in ("HEAD", "") or out.startswith("fatal") else out


def branch_to_id(branch: str) -> str:
    branch = branch.strip()
    if not branch or branch == "HEAD":
        return "agent-unknown"
    m = re.match(r"^arena/([0-9a-f]{6,})-(.+)$", branch)
    if m:
        return "agent-" + m.group(1)
    return "agent-" + slugify(branch, 48)


def resolve_identity(root: Path, override: str | None = None) -> str:
    if override:
        return override
    env = os.environ.get("AGENTMAIL_ID")
    if env:
        return env.strip()
    idfile = root / MAIL_DIRNAME / IDENTITY_FILE
    if idfile.is_file():
        value = idfile.read_text(encoding="utf-8").strip()
        if value:
            return value
    return branch_to_id(current_branch(root))


def save_identity(root: Path, agent_id: str) -> Path:
    path = root / MAIL_DIRNAME / IDENTITY_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(agent_id + "\n", encoding="utf-8")
    return path


# --------------------------------------------------------------------------- #
# mailbox model
# --------------------------------------------------------------------------- #

class Message:
    def __init__(self, path: Path, meta: dict, body: str):
        self.path = path
        self.meta = meta
        self.body = body

    @property
    def id(self) -> str:
        return str(self.meta.get("id", ""))

    @property
    def sender(self) -> str:
        return str(self.meta.get("from", "?"))

    @property
    def recipients(self) -> list[str]:
        return self.meta.get("to") or []

    @property
    def kind(self) -> str:
        return str(self.meta.get("kind", "info"))

    @property
    def topic(self) -> str:
        return str(self.meta.get("topic", "(no topic)"))

    @property
    def thread(self) -> str:
        return str(self.meta.get("thread", slugify(self.topic)))

    @property
    def created(self) -> _dt.datetime:
        return parse_iso(str(self.meta.get("created", ""))) or _dt.datetime.min.replace(
            tzinfo=_dt.timezone.utc)

    def addressed_to(self, agent_id: str, roles: list[str]) -> bool:
        targets = {str(r).lower() for r in self.recipients}
        if "all" in targets or "everyone" in targets:
            return True
        if agent_id.lower() in targets:
            return True
        return bool({r.lower() for r in roles} & targets)

    def one_line(self) -> str:
        return "%-18s %-8s %-22s %s" % (
            self.id, self.kind, self.sender, self.topic)


def load_message(path: Path) -> Message:
    meta, body = parse_frontmatter(path.read_text(encoding="utf-8"))
    return Message(path, meta, body)


def iter_messages(root: Path) -> list[Message]:
    base = root / MAIL_DIRNAME / MESSAGES
    if not base.is_dir():
        return []
    out = []
    for path in sorted(base.rglob("*.md")):
        try:
            out.append(load_message(path))
        except (OSError, UnicodeDecodeError):
            continue
    out.sort(key=lambda m: (m.created, m.id))
    return out


def find_message(root: Path, prefix: str) -> Message | None:
    for msg in iter_messages(root):
        if msg.id == prefix or msg.id.startswith(prefix):
            return msg
        if prefix in msg.path.name:
            return msg
    return None


def load_agents(root: Path) -> list[dict]:
    base = root / MAIL_DIRNAME / AGENTS
    if not base.is_dir():
        return []
    out = []
    for path in sorted(base.glob("*.md")):
        meta, body = parse_frontmatter(path.read_text(encoding="utf-8"))
        meta.setdefault("id", path.stem)
        meta["_path"] = str(path.relative_to(root))
        meta["_body"] = body
        out.append(meta)
    out.sort(key=lambda a: str(a.get("id", "")))
    return out


def my_roles(root: Path, agent_id: str) -> list[str]:
    for agent in load_agents(root):
        if str(agent.get("id")) == agent_id:
            wp = agent.get("wp") or agent.get("owns") or []
            if isinstance(wp, str):
                wp = [wp]
            return [str(w) for w in wp]
    return []


# --------------------------------------------------------------------------- #
# read receipts
# --------------------------------------------------------------------------- #

def read_receipts(root: Path, agent_id: str) -> set[str]:
    path = root / MAIL_DIRNAME / READ_DIR / (agent_id + ".txt")
    if not path.is_file():
        return set()
    return {line.strip() for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()}


def mark_read(root: Path, agent_id: str, message_ids: list[str]) -> None:
    path = root / MAIL_DIRNAME / READ_DIR / (agent_id + ".txt")
    path.parent.mkdir(parents=True, exist_ok=True)
    seen = read_receipts(root, agent_id)
    seen.update(message_ids)
    path.write_text("\n".join(sorted(seen)) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------- #
# composing
# --------------------------------------------------------------------------- #

def build_message(root: Path, sender: str, recipients: list[str], topic: str,
                  body: str, kind: str, thread: str | None, priority: str,
                  refs: list[str], needs_reply_by: str | None) -> tuple[Message, Path]:
    stamp = now_utc()
    msg_id = "%s-%s" % (compact(stamp), rand_suffix())
    meta = {
        "id": msg_id,
        "from": sender,
        "to": recipients,
        "thread": thread or slugify(topic),
        "kind": kind,
        "topic": topic,
        "priority": priority,
        "created": iso(stamp),
        "refs": refs,
    }
    if needs_reply_by:
        meta["needs_reply_by"] = needs_reply_by
    target = "all" if "all" in recipients else "-".join(recipients[:3])
    name = "%s_%s_to-%s_%s_%s.md" % (
        compact(stamp), sender, slugify(target, 24), slugify(topic), msg_id[-6:])
    path = root / MAIL_DIRNAME / MESSAGES / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dump_frontmatter(meta, body), encoding="utf-8")
    return Message(path, meta, body), path


def commit_paths(root: Path, paths: list[str], message: str) -> bool:
    for path in paths:
        git(root, "add", "--", path)
    # `git commit -- <paths>` commits only those paths, so unrelated work in the
    # index is never swept into a mail commit.
    proc = subprocess.run(
        ["git", "-C", str(root), "commit", "-q", "-m", message, "--", *paths],
        capture_output=True, text=True)
    if proc.returncode != 0:
        print("warning: nothing committed (%s)" % proc.stderr.strip().splitlines()[-1:],
              file=sys.stderr)
        return False
    return True


def read_body(args) -> str:
    if args.body_file:
        return Path(args.body_file).read_text(encoding="utf-8")
    if args.body is not None:
        return args.body.replace("\\n", "\n")
    if not sys.stdin.isatty():
        data = sys.stdin.read()
        if data.strip():
            return data
    editor = os.environ.get("EDITOR") or os.environ.get("VISUAL")
    if editor:
        import tempfile
        with tempfile.NamedTemporaryFile("w+", suffix=".md", delete=False) as fh:
            fh.write("\n\n# Write your message above this line.\n")
            tmp = fh.name
        subprocess.run([editor, tmp])
        text = Path(tmp).read_text(encoding="utf-8")
        Path(tmp).unlink(missing_ok=True)
        text = text.split("\n# Write your message above this line.")[0].strip()
        if text:
            return text
    raise SystemExit("no message body: use -m, --body-file, stdin, or set $EDITOR")


# --------------------------------------------------------------------------- #
# lint
# --------------------------------------------------------------------------- #

def lint(root: Path, fix: bool = False) -> list[str]:
    problems: list[str] = []
    seen_ids: dict[str, str] = {}

    for msg in iter_messages(root):
        where = str(msg.path.relative_to(root))
        meta = msg.meta
        for field in REQUIRED_FIELDS:
            if field not in meta or meta[field] in ("", [], None):
                if fix and field in ("from", "to", "kind", "created", "id"):
                    pass
                problems.append("%s: missing required field '%s'" % (where, field))
        mid = str(meta.get("id", ""))
        if mid and not _ID_RE.match(mid):
            problems.append("%s: malformed id '%s'" % (where, mid))
        if mid in seen_ids:
            problems.append("%s: duplicate id also used by %s" % (where, seen_ids[mid]))
        elif mid:
            seen_ids[mid] = where
        sender = str(meta.get("from", ""))
        if sender and not _AGENT_ID_RE.match(sender):
            problems.append("%s: malformed sender '%s'" % (where, sender))
        if not meta.get("to"):
            problems.append("%s: empty recipient list" % where)
        kind = str(meta.get("kind", ""))
        if kind and kind not in KINDS:
            problems.append("%s: unknown kind '%s' (expected one of %s)"
                            % (where, kind, ", ".join(KINDS)))
        priority = str(meta.get("priority", "normal"))
        if priority not in PRIORITIES:
            problems.append("%s: unknown priority '%s'" % (where, priority))
        created = parse_iso(str(meta.get("created", "")))
        if meta.get("created") and created is None:
            problems.append("%s: unparseable created '%s'" % (where, meta["created"]))
        if created and mid and not msg.path.name.startswith(compact(created)):
            problems.append("%s: filename does not start with created timestamp" % where)
        if not msg.body.strip():
            problems.append("%s: empty body" % where)
        for ref in meta.get("refs") or []:
            if str(ref).startswith(("github_pat_", "ghp_")):
                problems.append("%s: ref looks like a secret token" % where)

        if fix:
            changed = False
            if not meta.get("topic"):
                meta["topic"] = "(no topic)"
                changed = True
            if not meta.get("thread"):
                meta["thread"] = slugify(meta["topic"])
                changed = True
            if "refs" not in meta:
                meta["refs"] = []
                changed = True
            if "priority" not in meta:
                meta["priority"] = "normal"
                changed = True
            if changed:
                msg.path.write_text(dump_frontmatter(meta, msg.body), encoding="utf-8")
                problems.append("%s: fixed missing optional fields" % where)

    for agent in load_agents(root):
        aid = str(agent.get("id", ""))
        if not _AGENT_ID_RE.match(aid):
            problems.append("%s: malformed agent id '%s'" % (agent["_path"], aid))
        if not agent.get("branch"):
            problems.append("%s: agent card has no branch" % agent["_path"])
    return problems


# --------------------------------------------------------------------------- #
# commands
# --------------------------------------------------------------------------- #

def cmd_id(args, cfg) -> int:
    agent_id = resolve_identity(cfg["root"], args.set)
    if args.set:
        save_identity(cfg["root"], agent_id)
        print("identity saved to %s: %s" % (
            (cfg["root"] / MAIL_DIRNAME / IDENTITY_FILE).relative_to(cfg["root"]), agent_id))
    print(agent_id)
    return 0


def cmd_register(args, cfg) -> int:
    root = cfg["root"]
    agent_id = resolve_identity(root, args.id)
    branch = args.branch or current_branch(root) or "(detached)"
    stamp = now_utc()
    meta = {
        "id": agent_id,
        "branch": branch,
        "wp": args.wp or [],
        "role": args.role or "",
        "model": args.model or "",
        "status": args.status,
        "updated": iso(stamp),
    }
    body = args.note or "Registered via `tools/agentmail.py register`.\n"
    path = root / MAIL_DIRNAME / AGENTS / (agent_id + ".md")
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and not args.force:
        # Never clobber a field the caller did not supply this time.
        existing, old_body = parse_frontmatter(path.read_text(encoding="utf-8"))
        if not args.note:
            body = old_body.rstrip("\n") + "\n"
        for key, value in existing.items():
            if meta.get(key) in ("", [], None):
                meta[key] = value
    path.write_text(dump_frontmatter(meta, body), encoding="utf-8")
    print("agent card: %s" % path.relative_to(root))
    if args.commit:
        rel = str(path.relative_to(root))
        commit_paths(root, [rel], "mail: register agent %s" % agent_id)
    return 0


def cmd_agents(args, cfg) -> int:
    agents = load_agents(cfg["root"])
    if args.json:
        print(json.dumps([{k: v for k, v in a.items() if not k.startswith("_")}
                          for a in agents], indent=2))
        return 0
    if not agents:
        print("no agents registered yet - run: tools/agentmail.py register")
        return 0
    print("%-26s %-34s %-12s %-8s %s" % ("ID", "BRANCH", "WP", "STATUS", "ROLE"))
    for agent in agents:
        wp = agent.get("wp") or []
        if isinstance(wp, str):
            wp = [wp]
        print("%-26s %-34s %-12s %-8s %s" % (
            str(agent.get("id", "?"))[:26],
            str(agent.get("branch", "?"))[:34],
            ",".join(str(w) for w in wp)[:12],
            str(agent.get("status", "?"))[:8],
            str(agent.get("role", ""))))
    return 0


def cmd_send(args, cfg) -> int:
    root = cfg["root"]
    sender = resolve_identity(root, args.id)
    recipients = args.to or ["all"]
    recipients = [r.strip() for r in recipients for r in [r] if r.strip()]
    if not recipients:
        raise SystemExit("send needs at least one --to")
    body = read_body(args)
    if args.kind not in KINDS:
        raise SystemExit("unknown kind '%s' (expected: %s)" % (args.kind, ", ".join(KINDS)))
    msg, path = build_message(root, sender, recipients, args.topic, body, args.kind,
                              args.thread, args.priority, args.refs or [],
                              args.needs_reply_by)
    rel = str(path.relative_to(root))
    if args.commit:
        commit_paths(root, [rel], "mail: %s -> %s: %s" % (
            sender, ",".join(recipients)[:40], args.topic[:60]))
    print("message %s -> %s" % (msg.id, ", ".join(recipients)))
    print("  %s" % rel)
    return 0


def cmd_inbox(args, cfg) -> int:
    root = cfg["root"]
    me = resolve_identity(root, args.id)
    roles = my_roles(root, me)
    read = read_receipts(root, me)
    cutoff = None
    if args.since:
        cutoff = now_utc() - _dt.timedelta(days=args.since)
    rows = []
    for msg in iter_messages(root):
        if not args.all and not msg.addressed_to(me, roles):
            if not (args.sent and msg.sender == me):
                continue
        if cutoff and msg.created < cutoff:
            continue
        if args.kind and msg.kind != args.kind:
            continue
        if args.thread and msg.thread != args.thread:
            continue
        if args.unread and msg.id in read:
            continue
        rows.append(msg)
    if args.limit:
        rows = rows[-args.limit:]
    if args.json:
        print(json.dumps([{
            "id": m.id, "from": m.sender, "to": m.recipients, "kind": m.kind,
            "thread": m.thread, "topic": m.topic, "created": iso(m.created),
            "unread": m.id not in read,
        } for m in rows], indent=2))
        return 0
    if not rows:
        print("inbox empty for %s%s" % (
            me, "" if args.all else " (try --all for everyone's traffic,"
                                    " --sent for your own posts)"))
        return 0
    print("%-18s %-8s %-4s %-22s %s" % ("ID", "KIND", "NEW", "FROM", "TOPIC"))
    for msg in rows:
        print("%-18s %-8s %-4s %-22s %s" % (
            msg.id, msg.kind, "*" if msg.id not in read else "",
            msg.sender[:22], msg.topic))
    print("\n%d message(s). read with: tools/agentmail.py read <id>" % len(rows))
    return 0


def cmd_read(args, cfg) -> int:
    root = cfg["root"]
    me = resolve_identity(root, args.id)
    msg = find_message(root, args.message)
    if msg is None:
        raise SystemExit("no message matching '%s'" % args.message)
    if args.json:
        print(json.dumps({"meta": msg.meta, "body": msg.body}, indent=2))
    else:
        print(msg.path.read_text(encoding="utf-8").rstrip())
        print("\n-- %s" % msg.path.relative_to(root))
    if not args.no_mark_read:
        mark_read(root, me, [msg.id])
    return 0


def cmd_ack(args, cfg) -> int:
    root = cfg["root"]
    me = resolve_identity(root, args.id)
    parent = find_message(root, args.message)
    if parent is None:
        raise SystemExit("no message matching '%s'" % args.message)
    body = args.body or ("Acknowledged: %s" % parent.topic)
    msg, path = build_message(
        root, me, [parent.sender], "Re: %s" % parent.topic, body, "ack",
        parent.thread, "normal", [parent.id], None)
    if args.commit:
        commit_paths(root, [str(path.relative_to(root))],
                     "mail: ack %s" % parent.id)
    print("ack %s -> %s (%s)" % (msg.id, parent.sender, path.name))
    return 0


def cmd_threads(args, cfg) -> int:
    root = cfg["root"]
    me = resolve_identity(root, args.id)
    roles = my_roles(root, me)
    read = read_receipts(root, me)
    buckets: dict[str, list[Message]] = {}
    for msg in iter_messages(root):
        if not args.all and not msg.addressed_to(me, roles) and msg.sender != me:
            continue
        buckets.setdefault(msg.thread, []).append(msg)
    if args.json:
        print(json.dumps([{
            "thread": t, "count": len(ms),
            "unread": sum(1 for m in ms if m.id not in read),
            "last": iso(ms[-1].created), "last_from": ms[-1].sender,
            "topic": ms[-1].topic,
        } for t, ms in sorted(buckets.items(), key=lambda kv: kv[1][-1].created)],
            indent=2))
        return 0
    if not buckets:
        print("no threads yet")
        return 0
    print("%-24s %-5s %-5s %-20s %s" % ("THREAD", "MSGS", "NEW", "LAST FROM", "LATEST TOPIC"))
    for thread, ms in sorted(buckets.items(), key=lambda kv: kv[1][-1].created):
        print("%-24s %-5d %-5d %-20s %s" % (
            thread[:24], len(ms), sum(1 for m in ms if m.id not in read),
            ms[-1].sender[:20], ms[-1].topic))
    return 0


def cmd_sync(args, cfg) -> int:
    root = cfg["root"]
    if not args.no_fetch:
        refspec = args.refspec or "+refs/heads/*:refs/remotes/%s/*" % args.remote
        proc = subprocess.run(["git", "-C", str(root), "fetch", "--prune",
                               args.remote, refspec], capture_output=True, text=True)
        if proc.returncode != 0:
            raise SystemExit("fetch failed: %s" % proc.stderr.strip())
    me_branch = current_branch(root)
    refs = git(root, "for-each-ref", "--format=%(refname)",
               "refs/remotes/%s" % args.remote).split()
    pulled = 0
    for ref in refs:
        if ref.endswith("/HEAD"):
            continue
        if me_branch and ref == "refs/remotes/%s/%s" % (args.remote, me_branch):
            continue
        if subprocess.run(["git", "-C", str(root), "rev-parse", "--verify", "-q",
                           "%s:%s" % (ref, MAIL_DIRNAME)],
                          capture_output=True).returncode != 0:
            continue
        git(root, "checkout", ref, "--", MAIL_DIRNAME)
        pulled += 1
    print("merged mailboxes from %d remote branch(es)" % pulled)
    diff = subprocess.run(["git", "-C", str(root), "diff", "--cached", "--quiet"],
                          capture_output=True)
    if diff.returncode != 0:
        if args.commit:
            commit_paths(root, [MAIL_DIRNAME], "mail: sync from %d branch(es)" % pulled)
            print("committed sync")
        else:
            print("new mail staged - commit it with: git commit -m 'mail: sync' -- %s"
                  % MAIL_DIRNAME)
    else:
        print("already up to date")
    if args.push:
        if not me_branch:
            raise SystemExit("cannot push from a detached HEAD")
        subprocess.run(["git", "-C", str(root), "push", args.remote, me_branch],
                       check=False)
    return 0


def cmd_digest(args, cfg) -> int:
    root = cfg["root"]
    cutoff = now_utc() - _dt.timedelta(days=args.days)
    msgs = [m for m in iter_messages(root) if m.created >= cutoff]
    buckets: dict[str, list[Message]] = {}
    for msg in msgs:
        buckets.setdefault(msg.thread, []).append(msg)
    lines = ["# Agent mail digest - last %d day(s)" % args.days,
             "",
             "Generated %s - %d message(s) in %d thread(s)."
             % (iso(now_utc()), len(msgs), len(buckets)), ""]
    for thread, ms in sorted(buckets.items(), key=lambda kv: kv[1][-1].created,
                             reverse=True):
        lines.append("## %s" % thread)
        for msg in ms:
            lines.append("- `%s` **%s** (%s, %s -> %s): %s" % (
                iso(msg.created), msg.sender, msg.kind, msg.sender,
                ",".join(str(r) for r in msg.recipients), msg.topic))
            for first in msg.body.strip().splitlines()[:args.lines]:
                lines.append("  > %s" % first.strip())
        lines.append("")
    text = "\n".join(lines) + "\n"
    if args.out:
        out = Path(args.out)
        if not out.is_absolute():
            out = root / out
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        try:
            shown = out.relative_to(root)
        except ValueError:
            shown = out
        print("wrote %s" % shown)
    else:
        sys.stdout.write(text)
    return 0


def cmd_lint(args, cfg) -> int:
    problems = lint(cfg["root"], fix=args.fix)
    if not problems:
        print("mail clean: %d message(s), %d agent card(s)" % (
            len(iter_messages(cfg["root"])), len(load_agents(cfg["root"]))))
        return 0
    for problem in problems:
        print(("FIXED " if problem.endswith("optional fields") else "LINT ") + problem)
    hard = [p for p in problems if not p.endswith("optional fields")]
    return 1 if hard else 0


# --------------------------------------------------------------------------- #
# cli
# --------------------------------------------------------------------------- #

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agentmail",
        description="Git-native mailbox for AI agents on separate branches.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            examples:
              tools/agentmail.py id
              tools/agentmail.py register --wp WP3 --role "ghost systems"
              tools/agentmail.py send --to all --topic "claiming WP3" -m "mine now"
              tools/agentmail.py inbox --unread
              tools/agentmail.py read 20260831T114500Z-7f3a1c
              tools/agentmail.py ack 20260831T114500Z-7f3a1c -m "agreed"
              tools/agentmail.py sync --push
              tools/agentmail.py digest --days 7 --out docs/agent_logs/mail-digest.md
        """))
    parser.add_argument("--root", help="repository root (auto-detected)")
    parser.add_argument("--id", help="override the agent id for this call")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("id", help="print or set this session's agent id")
    p.add_argument("--set", metavar="ID", help="persist an id override (git-ignored)")
    p.set_defaults(func=cmd_id)

    p = sub.add_parser("register", help="publish your agent card")
    p.add_argument("--branch")
    p.add_argument("--wp", action="append", default=[], help="work package, repeatable")
    p.add_argument("--role")
    p.add_argument("--model")
    p.add_argument("--status", default="active")
    p.add_argument("--note")
    p.add_argument("--force", action="store_true")
    p.add_argument("--commit", action="store_true")
    p.set_defaults(func=cmd_register)

    p = sub.add_parser("agents", help="list registered agents")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_agents)

    p = sub.add_parser("send", help="compose a message")
    p.add_argument("--to", action="append", required=True,
                   help="recipient: all | wp3 | agent-01a05786 (repeatable)")
    p.add_argument("--topic", required=True)
    p.add_argument("--kind", default="info", choices=KINDS)
    p.add_argument("--thread")
    p.add_argument("--priority", default="normal", choices=PRIORITIES)
    p.add_argument("--refs", action="append", default=[])
    p.add_argument("--needs-reply-by")
    p.add_argument("-m", "--body")
    p.add_argument("--body-file")
    p.add_argument("--commit", action="store_true")
    p.set_defaults(func=cmd_send)

    p = sub.add_parser("inbox", help="list mail addressed to you")
    p.add_argument("--all", action="store_true", help="include mail not addressed to you")
    p.add_argument("--sent", action="store_true", help="include your own posts")
    p.add_argument("--unread", action="store_true")
    p.add_argument("--since", type=float, metavar="DAYS")
    p.add_argument("--kind")
    p.add_argument("--thread")
    p.add_argument("--limit", type=int)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_inbox)

    p = sub.add_parser("read", help="print a message")
    p.add_argument("message", help="message id or filename fragment")
    p.add_argument("--no-mark-read", action="store_true")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_read)

    p = sub.add_parser("ack", help="acknowledge a message in its thread")
    p.add_argument("message")
    p.add_argument("-m", "--body")
    p.add_argument("--commit", action="store_true")
    p.set_defaults(func=cmd_ack)

    p = sub.add_parser("threads", help="list conversation threads")
    p.add_argument("--all", action="store_true")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_threads)

    p = sub.add_parser("sync", help="pull other branches' mailboxes into yours")
    p.add_argument("--remote", default="origin")
    p.add_argument("--refspec")
    p.add_argument("--no-fetch", action="store_true")
    p.add_argument("--commit", action="store_true")
    p.add_argument("--push", action="store_true")
    p.set_defaults(func=cmd_sync)

    p = sub.add_parser("digest", help="render recent traffic as markdown")
    p.add_argument("--days", type=float, default=7)
    p.add_argument("--lines", type=int, default=1)
    p.add_argument("--out")
    p.set_defaults(func=cmd_digest)

    p = sub.add_parser("lint", help="validate all mail and agent cards")
    p.add_argument("--fix", action="store_true", help="fill missing optional fields")
    p.set_defaults(func=cmd_lint)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path(args.root).resolve() if args.root else find_root()
    cfg = {"root": root}
    return args.func(args, cfg)


if __name__ == "__main__":
    sys.exit(main())
