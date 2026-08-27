#!/usr/bin/env python3
"""
tests/soak/run_soak.py — live-engine soak test for System Looting.

Launches a real Luanti server with the aaa_botmatch harness enabled.
Simulated AI players then play full matches (insertion, combat, deaths,
ghost cage, altar ritual, evil-ghost revival, sabotage/repair, disconnect/
reconnect, timer/expiry) while the harness harvests:

  * BUGS     — every Lua error triggered during simulated play is caught
               by the harness ([botmatch][BUG] lines + stats.bugs) and
               every raw engine ERROR line is collected from debug.txt.
  * BALANCE  — per-match winner/duration, per-team kills/deaths/beacon
               damage, per-bot phase funnels, event counters (summons,
               offers, revivals, sabotages, repairs, disconnects,
               destructions), plus aggregates: win rates, side bias,
               average duration, kill/death totals.

Verdict: PASS only when all requested matches complete, no [botmatch][BUG]
events were recorded, and no engine ERROR lines appear in debug.txt.

Usage:
    python3 tests/soak/run_soak.py [--matches 3] [--seed 1337]
        [--timeout 600] [--engine /usr/games/luanti]
        [--report out.json] [--keep-world]

CI-friendly: exit code 0 = pass, 1 = fail, 2 = environment error.
"""

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GAME_ID = REPO.name  # Luanti derives the game id from the folder name

# Engine ERROR lines that are known-harmless noise for headless runs.
ERROR_NOISE = (
    "[botmatch][BUG]",  # counted separately via stats.bugs
)


def find_engine(cli_value: str | None) -> str:
    candidates = [cli_value, os.environ.get("LUANTI_BIN")]
    for name in ("luanti", "minetest"):
        candidates.append(shutil.which(name))
    for c in candidates:
        if c and Path(c).exists() and os.access(c, os.X_OK):
            return c
    raise SystemExit(
        "ERROR: no Luanti/Minetest engine found. Install it or pass --engine PATH "
        "(exit 2)"
    )


def link_game() -> None:
    """Expose the repo to the engine's game search paths (both old and new dirs)."""
    for base in (Path.home() / ".luanti" / "games", Path.home() / ".minetest" / "games"):
        base.mkdir(parents=True, exist_ok=True)
        link = base / GAME_ID
        if link.is_symlink() or link.exists():
            try:
                if link.resolve() == REPO.resolve():
                    continue
                link.unlink()
            except OSError:
                continue
        try:
            link.symlink_to(REPO)
        except OSError as e:
            print(f"WARNING: could not link game into {base}: {e}")


def make_world(world: Path, args) -> Path:
    world.mkdir(parents=True, exist_ok=True)
    (world / "world.mt").write_text(
        f"gameid = {GAME_ID}\nbackend = sqlite3\nmg_name = singlenode\n"
    )
    conf = world.parent / "soak.conf"
    conf_text = (
        "\n".join(
            [
                "creative_mode = false",
                "enable_damage = false",
                "max_users = 8",
                "time_speed = 0",
                # NOTE: mg_name in world.mt is ignored by Luanti 5.10 (Debian);
                # the config file is the reliable override. Without singlenode,
                # v7 terrain regenerates over arena nodes on block eviction.
                "mg_name = singlenode",
                "sl_botmatch.enabled = true",
                f"sl_botmatch.bots = {args.bots}",
                f"sl_botmatch.matches = {args.matches}",
                f"sl_botmatch.seed = {args.seed}",
                f"sl_botmatch.match_duration = {args.match_duration}",
                f"sl_botmatch.lives = {args.lives}",
                f"sl_botmatch.disconnect_test = {'true' if not args.no_disconnect else 'false'}",
                f"sl_botmatch.turbo = {'true' if args.turbo else 'false'}",
                f"sl_botmatch.mob_mode = {'true' if args.mob else 'false'}",
                f"sl_botmatch.auto_start = {'true' if args.mob else 'false'}",
            ]
        )
        + "\n"
    )
    if args.inter_match_delay is not None:
        conf_text += f"sl_botmatch.inter_match_delay = {args.inter_match_delay}\n"
    conf.write_text(conf_text)
    return conf


def parse_debug_txt(path: Path) -> tuple[list[str], list[str]]:
    """Return (engine_errors, harvested_bug_lines)."""
    errors, bugs = [], []
    if not path.exists():
        return errors, bugs
    for line in path.read_text(errors="replace").splitlines():
        if "ERROR" not in line:
            continue
        if "[botmatch][BUG]" in line:
            bugs.append(line.strip())
        elif not any(n in line for n in ERROR_NOISE):
            errors.append(line.strip())
    return errors, bugs


def print_report(report: dict) -> None:
    stats = report.get("stats") or {}
    print("\n" + "=" * 66)
    print("SYSTEM LOOTING — SOAK TEST REPORT")
    print("=" * 66)
    print(f"engine           : {stats.get('engine', '?')}")
    print(f"seed             : {stats.get('seed', '?')}")
    print(f"matches completed: {stats.get('matches_completed', 0)}"
          f" / {report['requested_matches']}")

    agg = stats.get("aggregate") or {}
    if agg:
        wr = agg.get("win_rate", {})
        print("\n-- balance aggregate " + "-" * 44)
        print(f"win rate     : A={wr.get('beacon_a', 0):.2f}  "
              f"B={wr.get('beacon_b', 0):.2f}  draw={wr.get('draw', 0):.2f}")
        print(f"side bias    : {agg.get('side_bias', 0):+.2f}  (|bias| < 0.34 is acceptable for small samples)")
        print(f"avg duration : {agg.get('avg_duration_s', 0):.1f} s")
        print(f"kills/deaths : {agg.get('kills_total', 0)} / {agg.get('deaths_total', 0)}")
        ev = agg.get("events", {})
        print("events       : " + "  ".join(f"{k}={v}" for k, v in sorted(ev.items())))

    for m in stats.get("matches", []):
        print(f"\n-- match {m.get('id')}: winner={m.get('winner')} "
              f"duration={m.get('duration_s', 0):.1f}s reason={m.get('reason', '')[:48]}")
        for team in ("beacon_a", "beacon_b"):
            t = m.get("teams", {}).get(team, {})
            print(f"   {team}: K/D={t.get('kills', 0)}/{t.get('deaths', 0)} "
                  f"dmg_dealt={t.get('damage_dealt', 0)} dmg_taken={t.get('damage_taken', 0)} "
                  f"hp_end={t.get('hp_end', '?')}")
        for name, b in sorted((m.get("bots") or {}).items()):
            print(f"   {name}: team={b.get('team')} K/D={b.get('kills', 0)}/{b.get('deaths', 0)} "
                  f"lives_used={b.get('lives_used', 0)} final={b.get('final_phase')}"
                  f"{' EVIL' if b.get('revived_evil') else ''}")

    bugs = stats.get("bugs", [])
    print("\n-- bug harvest " + "-" * 50)
    print(f"harness-caught Lua errors : {len(bugs)}")
    for b in bugs[:10]:
        print(f"   [{b.get('context')}] {str(b.get('error'))[:110]}")
    print(f"engine ERROR lines        : {len(report.get('engine_errors', []))}")
    for e in report.get("engine_errors", [])[:10]:
        print(f"   {e[:110]}")
    print("=" * 66)
    print(f"VERDICT: {report['verdict']}")
    print("=" * 66)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--matches", type=int, default=3)
    ap.add_argument("--bots", type=int, default=4)
    ap.add_argument("--seed", type=int, default=1337)
    ap.add_argument("--match-duration", type=int, default=90)
    ap.add_argument("--lives", type=int, default=3)
    ap.add_argument("--no-disconnect", action="store_true",
                    help="skip the disconnect/reconnect scenario")
    ap.add_argument("--turbo", action="store_true",
                    help="turbo profile: adjacent bases, tiny beacon HP, fast "
                         "swings — matches resolve in ~5 s")
    ap.add_argument("--mob", action="store_true",
                    help="mob mode: bots get pathfinding entity bodies; "
                         "matches are admin-driven (for soak: still auto)")
    ap.add_argument("--inter-match-delay", type=int, default=None)
    ap.add_argument("--timeout", type=int, default=600,
                    help="wall-clock seconds before the run is aborted")
    ap.add_argument("--engine", default=None, help="path to luanti/minetest binary")
    ap.add_argument("--world", default=None, help="world dir (default: temp, deleted)")
    ap.add_argument("--report", default=None, help="write JSON report to this path")
    ap.add_argument("--keep-world", action="store_true")
    args = ap.parse_args()

    engine = find_engine(args.engine)
    link_game()

    tmp_root = None
    if args.world:
        world = Path(args.world)
        shutil.rmtree(world, ignore_errors=True)
    else:
        tmp_root = tempfile.mkdtemp(prefix="sl_soak_")
        world = Path(tmp_root) / "world"
    conf = make_world(world, args)

    cmd = [engine, "--server", "--world", str(world), "--gameid", GAME_ID,
           "--config", str(conf)]
    print(f"[soak] engine : {engine}")
    print(f"[soak] world  : {world}")
    print(f"[soak] cmd    : {' '.join(cmd)}")

    stdout_path = world.parent / "server_console.log"
    stats_path = world / "botmatch_stats.json"
    proc = subprocess.Popen(
        cmd, stdout=open(stdout_path, "wb"), stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL, cwd=str(world.parent),
    )

    stats = None
    deadline = time.time() + args.timeout
    try:
        while time.time() < deadline:
            if proc.poll() is not None:
                print(f"[soak] server exited early with code {proc.returncode}")
                break
            if stats_path.exists():
                try:
                    data = json.loads(stats_path.read_text())
                    stats = data
                    done = data.get("matches_completed", 0)
                    if data.get("finished_at") or done >= args.matches:
                        # let the final write settle, then stop the server
                        time.sleep(2)
                        try:
                            stats = json.loads(stats_path.read_text())
                        except json.JSONDecodeError:
                            pass
                        break
                except json.JSONDecodeError:
                    pass  # mid-write; retry next poll
            time.sleep(2)
    finally:
        if proc.poll() is None:
            proc.send_signal(signal.SIGINT)
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=10)

    engine_errors, bug_lines = parse_debug_txt(world / "debug.txt")
    completed = (stats or {}).get("matches_completed", 0)
    harness_bugs = (stats or {}).get("bugs", [])

    failures = []
    if completed < args.matches:
        failures.append(f"only {completed}/{args.matches} matches completed")
    if harness_bugs:
        failures.append(f"{len(harness_bugs)} harness-caught Lua error(s)")
    if engine_errors:
        failures.append(f"{len(engine_errors)} engine ERROR line(s)")
    if bug_lines and not harness_bugs:
        failures.append(f"{len(bug_lines)} [botmatch][BUG] line(s) without stats entry")

    report = {
        "verdict": "PASS" if not failures else "FAIL",
        "failures": failures,
        "requested_matches": args.matches,
        "seed": args.seed,
        "engine": engine,
        "world": str(world),
        "stats": stats,
        "engine_errors": engine_errors,
        "bug_lines": bug_lines,
    }
    print_report(report)
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2))
        print(f"[soak] report written to {args.report}")

    if tmp_root and not args.keep_world:
        shutil.rmtree(tmp_root, ignore_errors=True)
    elif args.keep_world:
        print(f"[soak] world kept at {world}")

    return 0 if not failures else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(2)
