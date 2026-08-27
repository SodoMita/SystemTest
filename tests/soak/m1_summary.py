#!/usr/bin/env python3
"""Summarize an M1 sweep directory of soak reports against the exit check.

Exit criteria (AGENT_PARALLEL_PLAN.md, milestone M1):
  * every run: 0 harness bugs, 0 engine errors, all requested matches done
  * sweep-wide: both elimination wins and timer draws observed
  * sweep-wide: every event counter > 0

Exit code 0 = M1 exit check satisfied, 1 = not satisfied.
"""
import json
import sys
from pathlib import Path

REQUIRED_EVENTS = [
    "ghost_summons", "offers", "revivals", "sabotages", "repairs",
    "possessions", "exorcisms", "disconnects", "beacon_destructions",
]


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/m1_sweep")
    reports = sorted(out.glob("*.json"))
    if not reports:
        print(f"[m1] no reports in {out}")
        return 1

    failures = []
    totals = {e: 0 for e in REQUIRED_EVENTS}
    wins = {}
    matches_total = 0
    duration_sum = 0.0
    kd = [0, 0]

    for rp in reports:
        rep = json.loads(rp.read_text())
        label = rp.stem
        stats = rep.get("stats") or {}
        completed = stats.get("matches_completed", 0)
        requested = rep.get("requested_matches", 0)
        bugs = stats.get("bugs") or []
        errors = rep.get("engine_errors") or []
        matches_total += completed
        print(f"[m1] {label}: {completed}/{requested} matches, "
              f"{len(bugs)} bugs, {len(errors)} engine errors, "
              f"verdict={rep.get('verdict')}")
        if completed < requested:
            failures.append(f"{label}: {completed}/{requested} matches")
        if bugs:
            failures.append(f"{label}: {len(bugs)} harness bug(s)")
        if errors:
            failures.append(f"{label}: {len(errors)} engine error(s)")

        for m in stats.get("matches", []):
            w = m.get("winner", "?")
            wins[w] = wins.get(w, 0) + 1
            duration_sum += m.get("duration_s", 0)
            for ev in REQUIRED_EVENTS:
                totals[ev] += (m.get("events") or {}).get(ev, 0)
            for b in (m.get("bots") or {}).values():
                kd[0] += b.get("kills", 0)
                kd[1] += b.get("deaths", 0)

    elim_wins = wins.get("beacon_a", 0) + wins.get("beacon_b", 0) + wins.get("beacons", 0)
    draws = wins.get("draw", 0)
    zero_events = [e for e, v in totals.items() if v == 0]

    print("\n[m1] === sweep aggregate ===")
    print(f"[m1] matches: {matches_total}")
    print(f"[m1] endings: eliminations={elim_wins} draws={draws} winners={wins}")
    print(f"[m1] avg duration: {duration_sum / max(1, matches_total):.1f}s")
    print(f"[m1] kills/deaths: {kd[0]}/{kd[1]}")
    print(f"[m1] events: " + "  ".join(f"{k}={v}" for k, v in sorted(totals.items())))

    if elim_wins == 0:
        failures.append("no elimination endings observed")
    if draws == 0:
        failures.append("no timer/draw endings observed")
    if zero_events:
        failures.append("zero-count events (unreachable mechanics?): " + ", ".join(zero_events))

    print()
    if failures:
        print("[m1] M1 EXIT CHECK: NOT SATISFIED")
        for f in failures:
            print(f"[m1]   - {f}")
        return 1
    print("[m1] M1 EXIT CHECK: SATISFIED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
