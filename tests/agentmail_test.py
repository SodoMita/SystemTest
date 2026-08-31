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

    def test_send_refuses_a_credential_in_the_body(self):
        """Mail is append-only and pushed to every clone, so the guard has to
        fire at composition time - lint is far too late."""
        before = len(list((self.root / "agent_mail" / "messages").glob("*.md")))
        proc = run(self.root, "send", "--to", "all", "--topic", "Here is the PAT",
                   "-m", "use this: ghp_16C7e42F292c6912E7710c838347Ae178B4a")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("refusing to send", proc.stderr)
        self.assertNotIn("16C7e42F292c6912E7710c838347Ae178B4a", proc.stderr,
                         "the error must not echo the credential")
        self.assertEqual(len(list((self.root / "agent_mail" / "messages")
                                  .glob("*.md"))), before,
                         "nothing should have been written")
        # documented escape hatch for false positives still works
        self.mail("send", "--to", "all", "--topic", "False positive",
                  "-m", "ghp_16C7e42F292c6912E7710c838347Ae178B4a",
                  "--allow-secret")
        self.assertEqual(len(list((self.root / "agent_mail" / "messages")
                                  .glob("*.md"))), before + 1)

    def test_send_refuses_a_credential_in_the_body(self):
        """Mail is append-only and pushed to every clone, so the guard has to
        fire at composition time - lint is far too late."""
        before = len(list((self.root / "agent_mail" / "messages").glob("*.md")))
        proc = run(self.root, "send", "--to", "all", "--topic", "Here is the PAT",
                   "-m", "use this: ghp_16C7e42F292c6912E7710c838347Ae178B4a")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("refusing to send", proc.stderr)
        self.assertNotIn("16C7e42F292c6912E7710c838347Ae178B4a", proc.stderr,
                         "the error must not echo the credential")
        self.assertEqual(len(list((self.root / "agent_mail" / "messages")
                                  .glob("*.md"))), before,
                         "nothing should have been written")
        # documented escape hatch for false positives still works
        self.mail("send", "--to", "all", "--topic", "False positive",
                  "-m", "ghp_16C7e42F292c6912E7710c838347Ae178B4a",
                  "--allow-secret")
        self.assertEqual(len(list((self.root / "agent_mail" / "messages")
                                  .glob("*.md"))), before + 1)

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
            "refs: [github_pat_EXAMPLEONLYnotarealtoken1234567890]\n---\nbody\n",
            encoding="utf-8")
        proc = run(self.root, "lint")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("github fine-grained pat", proc.stdout)
        # the finding must not quote the credential back out
        self.assertNotIn("EXAMPLEONLYnotarealtoken1234567890", proc.stdout)

    def test_lint_detects_token_in_body(self):
        """R4 said 'never commit secrets'; v1 only ever inspected `refs:`."""
        self.mail("send", "--to", "all", "--topic", "innocent",
                  "-m", "body with no credentials at all")
        msg = sorted((self.root / "agent_mail" / "messages").glob("*.md"))[-1]
        text = msg.read_text(encoding="utf-8").replace(
            "body with no credentials at all",
            "here you go: ghp_16C7e42F292c6912E7710c838347Ae178B4a")
        msg.write_text(text, encoding="utf-8")
        proc = run(self.root, "lint")
        self.assertNotEqual(proc.returncode, 0,
                            "a token in the body must fail lint")
        self.assertIn("github classic token", proc.stdout)

    def test_lint_flags_undeliverable_recipient(self):
        msgs = self.root / "agent_mail" / "messages"
        msgs.mkdir(parents=True, exist_ok=True)
        (msgs / "20260101T000000Z_agent-x_to-typo_lost_000003.md").write_text(
            "---\nid: 20260101T000000Z-000003\nfrom: agent-x\nto: [agnt-01a05786]\n"
            "kind: request\ncreated: 2026-01-01T00:00:00Z\n---\nanyone there?\n",
            encoding="utf-8")
        proc = run(self.root, "lint")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("cannot be delivered", proc.stdout)

    def test_lint_warns_but_passes_on_non_routable_wp(self):
        msgs = self.root / "agent_mail" / "messages"
        msgs.mkdir(parents=True, exist_ok=True)
        (msgs / "20260101T000000Z_agent-x_to-wp9_orphan_000004.md").write_text(
            "---\nid: 20260101T000000Z-000004\nfrom: agent-x\nto: [wp9]\n"
            "kind: info\ncreated: 2026-01-01T00:00:00Z\n---\nhello wp9\n",
            encoding="utf-8")
        proc = run(self.root, "lint")
        self.assertEqual(proc.returncode, 0,
                         "an unrouted wp is a warning, not a failure")
        self.assertIn("no registered agent claims wp", proc.stdout)

    def test_lint_json_reports_severities(self):
        import json
        self.mail("send", "--to", "agnt-nobody", "--topic", "typo", "-m", "x")
        data = json.loads(run(self.root, "lint", "--json").stdout)
        self.assertGreaterEqual(data["errors"], 1)
        self.assertEqual(data["findings"][0]["severity"], "error")


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
        # 1, not 2: `scratch/no-mail` has no agent_mail/ and is skipped; the only
        # branch consulted is our own, which is unioned for messages/ so that
        # mail pushed onto it by somebody else still arrives.
        self.assertIn("merged mailboxes from 1 remote branch", out)
        self.assertIn("already up to date", out)
        self.assertFalse((self.root / "scratch.txt").exists()
                         or "scratch.txt" in self.git("ls-files"))

    def test_sync_sees_mail_pushed_onto_its_own_branch(self):
        """Regression: §4 skipped the branch you stand on, so a second agent
        posting onto a shared branch was invisible to the branch's owner
        (observed 2026-08-31, message 20260831T120255Z-a417f9)."""
        self.mail("send", "--to", "all", "--topic", "B owns this branch",
                  "-m", "resident post", "--commit")
        self.git("push", "-q", "-u", "origin", "arena/01a05786-systemtest")

        # a second agent pushes mail onto B's branch from their own clone
        guest = self.tmp / "guest"
        subprocess.run(["git", "clone", "-q", str(self.origin), str(guest)],
                       check=True, capture_output=True)
        for key, value in (("user.email", "g@example.invalid"), ("user.name", "Guest")):
            subprocess.run(["git", "-C", str(guest), "config", key, value], check=True)
        subprocess.run(["git", "-C", str(guest), "checkout", "-q",
                        "arena/01a05786-systemtest"], check=True)
        run(guest, "id", "--set", "guest")
        run(guest, "register", "--wp", "WP1", "--role", "passing through")
        run(guest, "send", "--to", "all", "--topic", "Posted onto your branch",
            "-m", "shared branch post", "--commit")
        subprocess.run(["git", "-C", str(guest), "push", "-q", "origin",
                        "arena/01a05786-systemtest"], check=True)

        # B syncs without pulling first: sync alone must make the mail visible
        self.mail("sync", "--commit")
        self.assertIn("Posted onto your branch", self.mail("inbox", "--all"))

        # and the unpushed local card must survive the messages/-only union
        self.assertTrue((self.root / "agent_mail" / "agents"
                         / "agent-01a05786.md").is_file())

        # publishing still needs a real merge: sync must refuse rather than let
        # a force-push erase the guest's commit
        proc = run(self.root, "sync", "--push")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("refusing to push", proc.stderr)
        self.git("pull", "-q", "--rebase", "origin", "arena/01a05786-systemtest")
        self.mail("sync", "--commit", "--push")
        published = subprocess.run(
            ["git", "-C", str(self.origin), "log", "--format=%s",
             "arena/01a05786-systemtest"],
            capture_output=True, text=True).stdout
        self.assertIn("Posted onto your branch", self.mail("inbox", "--all"))
        self.assertEqual(len(list((self.root / "agent_mail" / "messages")
                                  .glob("*.md"))), 2)

    def test_sync_refuses_to_push_over_a_diverged_branch(self):
        """A silent push failure is the worst failure here: the agent believes
        its mail is published, so nobody ever answers it."""
        self.mail("send", "--to", "all", "--topic", "First", "-m", "one", "--commit")
        self.git("push", "-q", "-u", "origin", "arena/01a05786-systemtest")

        # somebody else moves the same branch, so our next push would be rejected
        rival = self.tmp / "rival"
        subprocess.run(["git", "clone", "-q", str(self.origin), str(rival)],
                       check=True, capture_output=True)
        for key, value in (("user.email", "r@example.invalid"), ("user.name", "Rival")):
            subprocess.run(["git", "-C", str(rival), "config", key, value], check=True)
        subprocess.run(["git", "-C", str(rival), "checkout", "-q",
                        "arena/01a05786-systemtest"], check=True)
        run(rival, "id", "--set", "rival")
        run(rival, "send", "--to", "all", "--topic", "Diverged",
            "-m", "rival posted", "--commit")
        subprocess.run(["git", "-C", str(rival), "push", "-q", "origin",
                        "arena/01a05786-systemtest"], check=True)

        self.mail("send", "--to", "all", "--topic", "Second", "-m", "two", "--commit")
        proc = run(self.root, "sync", "--push")
        self.assertNotEqual(proc.returncode, 0,
                            "a diverged push must not exit 0")
        self.assertIn("refusing to push", proc.stderr)
        self.assertIn("pull --rebase", proc.stderr)

        # the mail sync pulled in is staged; commit it, rebase, and the same
        # command succeeds with both messages published
        self.mail("sync", "--commit")
        self.git("pull", "-q", "--rebase", "origin", "arena/01a05786-systemtest")
        out = self.mail("sync", "--commit", "--push")
        self.assertIn("pushed arena/01a05786-systemtest", out)
        listing = self.mail("inbox", "--all")
        self.assertIn("Diverged", listing)
        self.assertIn("Second", listing)

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

    def test_find_secrets_masks_and_ignores_prose(self):
        hits = self.m.find_secrets("token: ghp_16C7e42F292c6912E7710c838347Ae178B4a")
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0][0], "github classic token")
        self.assertNotIn("16C7e42F292c6912E7710c838347Ae178B4a", hits[0][1],
                         "the finding must be masked, not a second leak")
        self.assertEqual(self.m.find_secrets(
            "never paste tokens; the ghp_ pattern is rejected by lint"), [])
        self.assertEqual(self.m.find_secrets(
            "see agent_mail/PROTOCOL.md and tools/agentmail.py"), [])

    def test_id_collision_re_rolls_then_fails_loudly(self):
        """`write_text` truncates, so a collision must never overwrite."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = self.m.rand_suffix
            self.m.rand_suffix = lambda n=6: "abcdef"
            try:
                msg, path = self.m.build_message(
                    root, "agent-a", ["all"], "Collision", "first", "info",
                    None, "normal", [], None)
                self.assertTrue(path.is_file())
                self.assertIn("abcdef", path.name)
                with self.assertRaises(SystemExit) as caught:
                    self.m.build_message(
                        root, "agent-a", ["all"], "Collision", "second", "info",
                        None, "normal", [], None)
                self.assertIn("collided", str(caught.exception))
                self.assertEqual(path.read_text(encoding="utf-8").count("first"), 1,
                                 "the original message must survive untouched")
            finally:
                self.m.rand_suffix = original


if __name__ == "__main__":
    unittest.main(verbosity=2)
