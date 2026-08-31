#!/usr/bin/env python3
"""Tests for tools/agentmail.py - the cross-agent git mailbox.

Pure stdlib, no network.  Every test builds a throwaway git repository in a
temp dir and drives the CLI exactly the way an agent would, so the tests cover
the real entry point rather than internal functions only.

    python3 tests/agentmail_test.py
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "tools" / "agentmail.py"

if not CLI.is_file():  # pragma: no cover - guard for odd checkouts
    raise SystemExit("tools/agentmail.py not found")


def run(root, *args, env_extra=None, stdin=None):
    env = dict(os.environ)
    env.update({
        "GIT_AUTHOR_NAME": "Agent Test",
        "GIT_AUTHOR_EMAIL": "agent@example.invalid",
        "GIT_COMMITTER_NAME": "Agent Test",
        "GIT_COMMITTER_EMAIL": "agent@example.invalid",
        "EDITOR": "",
    })
    env.update(env_extra or {})
    return subprocess.run(
        [sys.executable, str(CLI), "--root", str(root), *args],
        capture_output=True, text=True, env=env, cwd=str(root),
        input=stdin)


class MailboxTestCase(unittest.TestCase):
    """A scratch git repo with agent_mail initialised, one agent registered."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="agentmail-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.root = self.tmp / "repo"
        self.root.mkdir()
        self.git("init", "-q", "-b", "arena/01a05786-systemtest")
        self.git("config", "user.email", "agent@example.invalid")
        self.git("config", "user.name", "Agent Test")
        (self.root / "game.conf").write_text("name = system_looting\n", encoding="utf-8")
        self.git("add", "game.conf")
        self.git("commit", "-q", "-m", "init")
        # a bare "remote" so `sync` has something to fetch from
        self.origin = self.tmp / "origin.git"
        subprocess.run(["git", "init", "-q", "--bare", str(self.origin)], check=True)
        self.git("remote", "add", "origin", str(self.origin))
        self.git("push", "-q", "-u", "origin", "arena/01a05786-systemtest")
        ok = run(self.root, "register", "--wp", "WP8", "--role", "docs & protocol")
        self.assertEqual(ok.returncode, 0, ok.stderr)

    def git(self, *args, **kwargs):
        proc = subprocess.run(["git", "-C", str(self.root), *args],
                              capture_output=True, text=True, **kwargs)
        if proc.returncode != 0:
            raise AssertionError("git %s failed: %s" % (args, proc.stderr))
        return proc.stdout.strip()

    def mail(self, *args, **kwargs):
        proc = run(self.root, *args, **kwargs)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return proc.stdout


class TestIdentity(MailboxTestCase):
    def test_identity_derives_from_arena_branch(self):
        out = self.mail("id")
        self.assertEqual(out.strip(), "agent-01a05786")

    def test_identity_derives_from_plain_branch(self):
        self.git("checkout", "-q", "-b", "feat/wp5-system-inventory-gui")
        self.assertEqual(self.mail("id").strip(), "agent-feat-wp5-system-inventory-gui")

    def test_env_override_wins(self):
        out = self.mail("id", env_extra={"AGENTMAIL_ID": "glitch"})
        self.assertEqual(out.strip(), "glitch")

    def test_set_persists_identity_file(self):
        self.mail("id", "--set", "glitch")
        idfile = self.root / "agent_mail" / ".identity"
        self.assertTrue(idfile.is_file())
        self.assertEqual(idfile.read_text(encoding="utf-8").strip(), "glitch")
        self.assertEqual(self.mail("id").strip(), "glitch")


class TestRegistration(MailboxTestCase):
    def test_agent_card_written_and_listed(self):
        card = self.root / "agent_mail" / "agents" / "agent-01a05786.md"
        self.assertTrue(card.is_file())
        listed = self.mail("agents")
        self.assertIn("agent-01a05786", listed)
        self.assertIn("arena/01a05786-systemtest", listed)
        self.assertIn("WP8", listed)

    def test_reregister_keeps_unsupplied_fields(self):
        self.mail("register", "--role", "mail ops")
        text = (self.root / "agent_mail" / "agents" / "agent-01a05786.md").read_text(
            encoding="utf-8")
        self.assertIn("mail ops", text)
        self.assertIn("WP8", text)  # not wiped by the second call

    def test_agents_json(self):
        import json
        data = json.loads(self.mail("agents", "--json"))
        self.assertEqual(data[0]["id"], "agent-01a05786")
        self.assertEqual(data[0]["wp"], ["WP8"])


class TestMessaging(MailboxTestCase):
    def test_send_and_read_roundtrip(self):
        out = self.mail("send", "--to", "all", "--topic", "Claiming WP3",
                        "--kind", "claim", "-m", "taking nodes.lua ghost section")
        msg_id = out.split()[1]
        self.assertTrue(msg_id.startswith("20"), msg_id)

        listing = self.mail("inbox")
        self.assertIn("Claiming WP3", listing)
        self.assertIn("claim", listing)

        body = self.mail("read", msg_id)
        self.assertIn("taking nodes.lua ghost section", body)
        self.assertIn("from: agent-01a05786", body)
        self.assertIn("to: [all]", body)

        # reading clears the unread marker; --sent surfaces your own posts
        self.assertNotIn("*", self.mail("inbox"))
        self.mail("send", "--to", "wp3", "--topic", "Second note", "-m", "not for me")
        self.assertIn("*", self.mail("inbox", "--sent", "--unread"))
        self.assertNotIn("Second note", self.mail("inbox"))  # wp3 is not my WP

    def test_unread_filter(self):
        self.mail("send", "--to", "all", "--topic", "Ping", "-m", "alive?")
        self.assertIn("Ping", self.mail("inbox", "--unread"))
        msg_id = self.mail("inbox", "--json").split('"id"')[1].split('"')[1].strip(': "')
        self.mail("read", msg_id)
        self.assertIn("inbox empty for agent-01a05786", self.mail("inbox", "--unread"))

    def test_addressing_routes_by_work_package(self):
        self.mail("send", "--to", "wp3", "--topic", "Ghost API v2", "-m", "for WP3 only")
        self.mail("send", "--to", "wp4", "--topic", "Soak seeds", "-m", "for WP4 only")
        # this agent registered WP8, so neither is addressed to it...
        mine = self.mail("inbox")
        self.assertNotIn("Ghost API v2", mine)
        self.assertNotIn("Soak seeds", mine)
        # ...but it can still find its own posts
        sent = self.mail("inbox", "--sent")
        self.assertIn("Ghost API v2", sent)
        everything = self.mail("inbox", "--all")
        self.assertIn("Ghost API v2", everything)
        self.assertIn("Soak seeds", everything)

        # re-register as WP3 and the WP3 mail lands in the inbox
        self.mail("register", "--wp", "WP3")
        self.assertIn("Ghost API v2", self.mail("inbox"))
        self.assertNotIn("Soak seeds", self.mail("inbox"))

    def test_thread_grouping_and_ack(self):
        out = self.mail("send", "--to", "wp4", "--topic", "Contract v2",
                        "--kind", "contract", "--thread", "contract-v2",
                        "-m", "please ack the new signature")
        msg_id = out.split()[1]
        ack = self.mail("ack", msg_id, "-m", "ack, merging tomorrow")
        ack_id = ack.split()[1]
        threads = self.mail("threads", "--all")
        self.assertIn("contract-v2", threads)
        text = self.mail("read", ack_id)
        self.assertIn("kind: ack", text)
        self.assertIn("contract-v2", text)
        self.assertIn(msg_id, text)  # refs the parent

    def test_body_from_stdin(self):
        out = self.mail("send", "--to", "all", "--topic", "From stdin",
                        stdin="body came through the pipe\n")
        self.assertIn("body came through the pipe", self.mail("read", out.split()[1]))

    def test_message_filenames_are_unique(self):
        for _ in range(3):
            self.mail("send", "--to", "all", "--topic", "Same second", "-m", "spam")
        files = sorted(p.name for p in
                       (self.root / "agent_mail" / "messages").glob("*.md"))
        self.assertEqual(len(files), 3)
        self.assertEqual(len(set(files)), 3)

    def test_commit_flag_commits_only_the_message(self):
        (self.root / "dirty.txt").write_text("unrelated work\n", encoding="utf-8")
        self.git("add", "dirty.txt")
        self.mail("send", "--to", "all", "--topic", "Committed mail",
                  "-m", "with --commit", "--commit")
        tracked = self.git("show", "--name-only", "--pretty=format:", "HEAD")
        self.assertIn("agent_mail/messages", tracked)
        self.assertNotIn("dirty.txt", tracked)
        self.assertIn("dirty.txt", self.git("diff", "--cached", "--name-only"))


class TestLint(MailboxTestCase):
    def test_clean_mailbox_passes(self):
        self.mail("send", "--to", "all", "--topic", "Clean", "-m", "body")
        out = self.mail("lint")
        self.assertIn("mail clean", out)

    def test_lint_flags_bad_kind_and_missing_fields(self):
        msgs = self.root / "agent_mail" / "messages"
        msgs.mkdir(parents=True, exist_ok=True)
        (msgs / "20260101T000000Z_bad_to-all_broken_000000.md").write_text(
            "---\nid: nope\nfrom: Bad Sender\nto: []\nkind: shouting\n"
            "created: yesterday\n---\nbody\n", encoding="utf-8")
        proc = run(self.root, "lint")
        self.assertNotEqual(proc.returncode, 0)
        joined = proc.stdout
        self.assertIn("malformed id", joined)
        self.assertIn("malformed sender", joined)
        self.assertIn("empty recipient list", joined)
        self.assertIn("unknown kind", joined)
        self.assertIn("unparseable created", joined)

    def test_lint_fix_fills_optional_fields(self):
        msgs = self.root / "agent_mail" / "messages"
        msgs.mkdir(parents=True, exist_ok=True)
        name = "20260101T000000Z_agent-01a05786_to-all_no-thread_000001.md"
        (msgs / name).write_text(
            "---\nid: 20260101T000000Z-000001\nfrom: agent-01a05786\n"
            "to: [all]\nkind: info\ncreated: 2026-01-01T00:00:00Z\n---\nbody\n",
            encoding="utf-8")
        proc = run(self.root, "lint", "--fix")
        self.assertEqual(proc.returncode, 0, proc.stdout)
        text = (msgs / name).read_text(encoding="utf-8")
        self.assertIn("thread: no-topic", text)
        self.assertIn("refs: []", text)

    def test_lint_detects_token_like_refs(self):
        msgs = self.root / "agent_mail" / "messages"
        msgs.mkdir(parents=True, exist_ok=True)
        (msgs / "20260101T000000Z_agent-x_to-all_leak_000002.md").write_text(
            "---\nid: 20260101T000000Z-000002\nfrom: agent-x\nto: [all]\n"
            "kind: info\ncreated: 2026-01-01T00:00:00Z\n"
            "refs: [github_pat_11BZU2MKQ0xMsPskO3dwmD]\n---\nbody\n",
            encoding="utf-8")
        proc = run(self.root, "lint")
        self.assertIn("secret token", proc.stdout)


class TestDigest(MailboxTestCase):
    def test_digest_groups_threads(self):
        self.mail("send", "--to", "all", "--topic", "Weather report",
                  "--thread", "weather", "-m", "rain in sector 4")
        self.mail("send", "--to", "wp3", "--topic", "Ghost tuning",
                  "--thread", "ghosts", "-m", "cooldown down to 15s")
        out_path = self.tmp / "digest.md"
        self.mail("digest", "--days", "7", "--out", str(out_path))
        text = out_path.read_text(encoding="utf-8")
        self.assertIn("weather", text)
        self.assertIn("ghosts", text)
        self.assertIn("rain in sector 4", text)


class TestSync(MailboxTestCase):
    """Two agents, two clones, one mailbox that converges."""

    def test_sync_unions_another_branches_mailbox(self):
        # agent A publishes a broadcast, commits it and pushes
        self.mail("send", "--to", "all", "--topic", "Hello from A",
                  "-m", "mailbox is open", "--commit")
        self.git("push", "-q", "origin", "arena/01a05786-systemtest")

        # agent B: a second clone of the same remote, on its own branch
        peer = self.tmp / "peer"
        subprocess.run(["git", "clone", "-q", str(self.origin), str(peer)],
                       check=True, capture_output=True)
        for key, value in (("user.email", "b@example.invalid"), ("user.name", "Agent B")):
            subprocess.run(["git", "-C", str(peer), "config", key, value], check=True)
        subprocess.run(["git", "-C", str(peer), "checkout", "-q", "-b",
                        "arena/01a05759-systemtest"], check=True)
        run(peer, "register", "--wp", "WP4", "--role", "tests")
        self.assertIn("agent-01a05759", run(peer, "id").stdout)
        run(peer, "send", "--to", "all", "--topic", "Hello from B",
            "-m", "tests are green", "--commit")
        subprocess.run(["git", "-C", str(peer), "push", "-q", "-u", "origin",
                        "arena/01a05759-systemtest"], check=True)

        # A syncs: B's message must appear, A's own message must survive
        out = self.mail("sync", "--commit")
        self.assertIn("merged mailboxes", out)
        listing = self.mail("inbox", "--all")
        self.assertIn("Hello from A", listing)
        self.assertIn("Hello from B", listing)
        self.assertEqual(len(list((self.root / "agent_mail" / "messages").glob("*.md"))), 2)

        # B syncs too and ends up with the same two messages
        run(peer, "sync", "--commit")
        peer_listing = run(peer, "inbox", "--all").stdout
        self.assertIn("Hello from A", peer_listing)
        self.assertIn("Hello from B", peer_listing)

        # a second sync is a no-op, not a duplicate
        out2 = self.mail("sync", "--commit")
        self.assertIn("up to date", out2)
        self.assertEqual(len(list((self.root / "agent_mail" / "messages").glob("*.md"))), 2)

    def test_sync_ignores_branches_without_mail(self):
        self.mail("send", "--to", "all", "--topic", "Still here", "-m", "ok", "--commit")
        self.git("push", "-q", "origin", "arena/01a05786-systemtest")
        # a branch forked before the mailbox existed must be skipped entirely
        base = self.git("rev-list", "--max-parents=0", "HEAD")
        self.git("checkout", "-q", "-b", "scratch/no-mail", base)
        (self.root / "scratch.txt").write_text("x\n", encoding="utf-8")
        self.git("add", "scratch.txt")
        self.git("commit", "-q", "-m", "scratch")
        self.git("push", "-q", "origin", "scratch/no-mail")
        self.git("checkout", "-q", "arena/01a05786-systemtest")
        out = self.mail("sync")
        self.assertIn("merged mailboxes from 0 remote branch", out)
        self.assertIn("already up to date", out)

    def test_sync_leaves_unrelated_changes_uncommitted(self):
        (self.root / "mods" / "important.lua").parent.mkdir(parents=True, exist_ok=True)
        (self.root / "mods" / "important.lua").write_text("return {}\n", encoding="utf-8")
        self.git("add", "mods/important.lua")
        self.mail("sync", "--commit")
        tracked = self.git("show", "--name-only", "--pretty=format:", "HEAD")
        self.assertNotIn("mods/important.lua", tracked)


class TestFrontmatter(unittest.TestCase):
    """Unit coverage for the mini YAML parser (no repo needed)."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(ROOT / "tools"))
        import agentmail  # noqa: E402
        cls.m = agentmail

    def test_inline_list_and_scalars(self):
        text = ("---\nid: 20260101T000000Z-000001\nfrom: agent-a\n"
                "to: [wp3, wp4]\nkind: request\ntopic: \"a: colon\"\n"
                "refs: []\ncreated: 2026-01-01T00:00:00Z\n---\nline one\n\nline two\n")
        meta, body = self.m.parse_frontmatter(text)
        self.assertEqual(meta["to"], ["wp3", "wp4"])
        self.assertEqual(meta["topic"], "a: colon")
        self.assertEqual(meta["refs"], [])
        self.assertEqual(body.splitlines()[0], "line one")

    def test_block_list(self):
        meta, _ = self.m.parse_frontmatter(
            "---\nto:\n  - wp1\n  - wp2\nkind: info\n---\nbody\n")
        self.assertEqual(meta["to"], ["wp1", "wp2"])

    def test_roundtrip_quoting(self):
        meta = {"id": "20260101T000000Z-000001", "from": "agent-a", "to": ["all"],
                "kind": "info", "topic": "yes: really #1", "created": "2026-01-01T00:00:00Z"}
        text = self.m.dump_frontmatter(meta, "body text\n")
        again, body = self.m.parse_frontmatter(text)
        self.assertEqual(again["topic"], "yes: really #1")
        self.assertEqual(body.strip(), "body text")

    def test_no_frontmatter(self):
        meta, body = self.m.parse_frontmatter("just a note\n")
        self.assertEqual(meta, {})
        self.assertEqual(body, "just a note\n")

    def test_branch_to_id(self):
        self.assertEqual(self.m.branch_to_id("arena/01a05759-systemtest"),
                         "agent-01a05759")
        self.assertEqual(self.m.branch_to_id("master"), "agent-master")
        self.assertEqual(self.m.branch_to_id("HEAD"), "agent-unknown")


if __name__ == "__main__":
    unittest.main(verbosity=2)
