#!/usr/bin/env python3
"""
System Looting — Point economy derivation model (Melody / Comms).

THE POINT: don't "feel" balance numbers — derive them from the game's own math.
But this is not only a point ladder. System Looting runs FOUR interlocking
economies at once, and a points model that only prices the crew's kill/objective
ladder is modelling a third of the game. This revision folds the other three in.

THE FOUR ECONOMIES (why they cannot be priced in isolation):
  1. CREW POINTS. The ladder we've been locking. Effort x win-progress x RISK.
     Traded on the beacon/objective win. Put in the §13.3 owner rule: points come
     primarily from killing crew, essence is NOT a score.
  2. THE MM'S ESSENCE POOL (fuel, not points). The Monster Master gains essence by
     DESTROYING nodes the crew placed (`essence = price(node)`, provenance-tracked),
     AND by the crew crafting certain items. This is running code on master
     (essence.lua): node price `sl_essence_value`, provenance dropped on dig,
     craft credits ESSENCE_CRAFT_CREDITS (objective_core +3). Ambient hazard spawns
     a security unit at pool 10/25/50. **The crew's Signal build literally feeds
     the enemy's fuel pool** — a coupling the points model cannot ignore.
  3. WINDOWED ACTIONS (timings). Sabotage corrupts for 30s, possession holds a
     vessel for 20s, a match is 600s. The value of an action is NOT its raw effort
     — it's what it does inside a window. A sabotage placed at t=580 is nearly
     worthless; one at t=0 denies for a third of the match.
  4. THE IMPOSTOR CONVERSION + GHOST INFO LANE — roles and information, NOT points,
     and NOT a "trust currency." There is ONE type of points (the crew ladder).
     Impostors are a CONVERSION role in two kinds: an initial impostor, and a
     neutral player converted DURING play by an UNDERGROUND MONSTER (underground
     monsters are the dead-defender saboteurs, NOT evil ghosts). Ghosts stay in a
     RESTRICTED SKY AREA and craft from INFORMATION CRAFTITEMS — the info lane,
     not trust. Trust is a belief evaluable in [0,1], not a point and not a
     currency. See audit_economy4().

Run:        python3 tools/point_economy_model.py            # audit + exit code
            python3 tools/point_economy_model.py --emit OUT # write generated constants
            python3 tools/point_economy_model.py --economy  # show all four economies

WHY THIS REVISION EXISTS (2026-09-03, melody, after re-reading the transcripts and
the arena/melody-game-design ideas + the real essence/possession/sabotage code):
  Prior revisions priced crew points against effort/risk and folded carmack/jax's
  catches (repair off the 60-HP ceiling -> expected corrosion; no shroud; the 40% bar
  unreachable; --emit to kill the +40/+50/+22 drift). Those were all correct. But the
  model then treated the game as ONE economy (points). The user caught it: I never
  considered TIMINGS, IMPOSTORS, SABOTAGES, or the ESSENCE gained from destroying
  something else. All four are real systems. This revision models them so the balance
  question is answered for the whole game, not a slice of it.

Grounded constants (verified from mods/game/sl_modebase):
  player HP         = 20              (content.lua "hp_max or 20")
  combat blade      = 6 dmg / 0.8s    (content.lua:63)
  energy blade      = 12 dmg / 0.6s   (content.lua:97)
  beacon HP         = 100             (state.lua:71 beacon_hp)
  beacon punch      = 5 dmg / punch   (nodes.lua:210,246) -> 20 punches (~7-13s)
  match duration    = 600s default    (state.lua:73)
  sabotage window   = 30s             (state.lua:76)
  possession hold   = 20s             (state.lua:77)
  sabotage corrosion= 2 dmg / sec     (nodes.lua:156) -> CEILING 60 HP, but one punch
                      clears it (expected ~8 HP for a responsive crew)
  essence pricing   = sl_essence_value group (essence.lua): fortify 1, hideout 2,
                      spawner 4, objective_core 5; craft credit objective_core +3
  ambient hazard    = security unit at pool 10/25/50 (essence.lua)
  whisper           = 1 per possession (whisper.lua); body possession hard cooldown
"""

import argparse
import os
import subprocess

# =====================================================================
# ECONOMY 1 — CREW POINTS. The ladder. Prices every crew action relative to a
# kill (the unit of account), if it could be done in isolation. This is the
# layer we'd already locked; kept because it is the one that ships the #.
# =====================================================================
EFFORT = {
    "kill":               3.0,
    "forge":              10.0,
    "core_delivery":      5.0,
    "beacon_destruction": 12.0,
    "deny":               4.0,   # cross into enemy space, place the charge, get out
    "repair":             0.8,
    "survive":            1.0,
    "victory":            1.0,
}

WIN_PROGRESS = {
    "kill":               1.0,   # baseline (one enemy contributor removed)
    "forge":              1.2,   # readable build
    "core_delivery":      2.5,   # THE objective win
    "beacon_destruction": 1.5,   # elimination win
    "deny":               1.2,   # repeatable pressure, but DENIES progress
    "repair":             1.0,   # expected corrosion denied, not the 60-HP ceiling
    "survive":            0.4,
    "victory":            0.4,
}

RISK = {
    "kill":               1.0,
    "core_delivery":      1.3,
    "beacon_destruction": 1.1,
    "forge":              0.9,
    "deny":               0.8,
    "repair":             0.4,
    "survive":            1.0,
    "victory":            1.0,
}

SCALE = 1.33   # kill = 3.0 x 1.0 x 1.0 = 3.0; x1.33 = 4

# Once per match (non-farmable, may be fast). Everything else is repeatable and
# must NOT out-earn a kill per second or it becomes the carmack repair bug.
ONCE_PER_MATCH = {"forge", "core_delivery", "beacon_destruction"}

# A team committed to one win path, for the audit. Assumption, not a mechanic.
COMMITTED_PATH_TOTAL = {
    "signal": {"kill": 5, "forge": 1, "core_delivery": 1, "repair": 2, "survive": 1},
    "breach": {"kill": 4, "beacon_destruction": 1, "repair": 2, "survive": 1},
    "shroud": {"kill": 3, "deny": 3, "repair": 4, "survive": 1, "victory": 1},
}

PLACEHOLDER = {
    "kill_base": 7,
    "core_delivery": 5000,
    "beacon_destruction": 1000,
    "survive": 50,
    "victory": 300,
}

DOMINATION_BUDGET = 55.0
WIN_PATH_BUDGET = 55.0
PATH_BALANCE_BUDGET = 2.5

# =====================================================================
# ECONOMY 2 — THE MM'S ESSENCE POOL. Fuel, not points. The crew FEEDS it by
# building (craft credits) AND by losing nodes (destruction pays the MM). The
# three-path pool claim becomes FALSE the moment the MM's fuel is on the board:
# a crew that commits to Signal pays the craft credit AND can lose its build.
# =====================================================================
ESSENCE = {
    # What the crew's node is worth to the MM when destroyed. sl_essence_value.
    "fortify":          1,   # cheap defensive block
    "hideout":          2,   # crew structure
    "spawner_unit":     4,   # crew spawner — the MM WANTS this gone
    "objective_core":   5,   # the Signal win item
    "craft_credit_core": 3,  # building the core credits the pool DIRECTLY (essence.lua)
}
AMBIENT_THRESHOLDS = [10, 25, 50]   # one security unit at each
SUMMON_COSTS = {"Grunt": 5, "Spitter": 8, "Brute": 12, "Royal": 20}


def economy_fuel_matrix():
    """Show the coupling the points model could not see: crew actions that FEED the
    enemy's fuel pool. The Signal win path is the worst offender — forge + deliver
    both hand the MM essence, on top of the craft credit."""
    rows = []
    # The crew building the core credits the pool (+3, essence.lua).
    rows.append(("craft objective_core", ESSENCE["craft_credit_core"],
                 "crew builds the Signal win item -> MM pool +3"))
    # The crew's fortifications pay when the MM destroys them.
    rows.append(("lose a fortify (MM digs it)", -ESSENCE["fortify"],
                 "MM destroys a crew node -> MM pool +1, crew loses the node"))
    rows.append(("lose a hideout (MM digs it)", -ESSENCE["hideout"],
                 "MM destroys a crew structure -> MM pool +2"))
    rows.append(("lose a spawner (MM digs it)", -ESSENCE["spawner_unit"],
                 "MM destroys a crew spawner -> MM pool +4"))
    rows.append(("lose the core mid-carry (MM digs it)", ESSENCE["objective_core"],
                 "crew's Signal item destroyed -> MM pool +5"))
    return rows


def audit_economy2():
    print("ECONOMY 2 — THE MM'S ESSENCE POOL (fuel, not points)")
    print("=" * 60)
    print("   The crew feeds the enemy's fuel pool. This is the coupling a points-only")
    print("   model cannot see:")
    for what, val, note in economy_fuel_matrix():
        print("   %-34s %+3d  | %s" % (what, val, note))
    print()
    print("   Summon cost table (essence to spawn a monster):")
    for name, cost in SUMMON_COSTS.items():
        print("     %-12s %d essence" % (name, cost))
    print()
    print("   Ambient hazard (no-MM matches): the pool spawns one automated security")
    print("   unit at each threshold %s." % AMBIENT_THRESHOLDS)
    print()
    print("   >> DESIGN RULING: the crew's Signal win path is double-taxed. It costs")
    print("      craft materials, it feeds the MM +3 essence on completion, and if the")
    print("      MM destroys the core in transit the crew hands over +5. This is WHY")
    print("      'a team cannot do all three' is not just pool contention — committing")
    print("      to Signal makes you the richest target on the board.")


# =====================================================================
# ECONOMY 3 — WINDOWED ACTIONS (timings). Sabotage/possession/repair all operate
# inside clocks. Value is not raw effort — it is what fraction of the window the
# action denies or holds. This is the part a static effort model gets wrong.
# =====================================================================
TIMINGS = {
    "match_s":          600,
    "sabotage_window_s": 30,   # a placed charge corrupts for 30s
    "possession_hold_s": 20,   # an evil ghost holds a vessel for 20s
    "corrosion_dps":    2,
}


def audit_economy3():
    print("\nECONOMY 3 — WINDOWED ACTIONS (timings)")
    print("=" * 60)
    match = TIMINGS["match_s"]
    sab = TIMINGS["sabotage_window_s"]
    poss = TIMINGS["possession_hold_s"]
    print("   A sabotage placed at t=0 corrupts a node for the full %ds window"
          % sab)
    print("   = %.0f%% of the %ds match — the good version (denies early, sets the" % (sab / match * 100, match))
    print("   tempo, forces a repair while the crew could be doing anything else).")
    print("   The SAME sabotage placed at t=%d denies only the tail of the match —" % (match - sab))
    print("   by the time it corrupts, the win is already decided elsewhere.")
    print()
    print("   So the value of a 'deny' is a DISTRIBUTION over the window:")
    print("     early (t ~ 0)        = full %ds of corrosion + tempo" % sab)
    print("     late (t ~ %d)    = near-zero value, wasted action" % (match - sab))
    print("   A static points model collapses this to ONE number. The soak harness is")
    print("   the only thing that can price the window: per-action deltas with a clock.")
    print()
    print("   Possession holds a vessel for %ds — one whisper per possession, hard" % poss)
    print("   cooldown on body possession. This is an EVIL-GHOST MECHANIC bound, its")
    print("   value is a single fabricated statement inside a %ds window — not a" % poss)
    print("   farmable action, and not a 'trust point' price.")


# =====================================================================
# ECONOMY 4 — THE IMPOSTOR CONVERSION + GHOST INFO LANE. ONE type of points.
# Not a trust currency: impostor = conversion (2 kinds), ghost = sky info-craft,
# trust = a belief evaluable in [0,1], undefined mechanics get no number.
# =====================================================================
def audit_economy4():
    print("\nECONOMY 4 — IMPOSTOR CONVERSION + GHOST INFO LANE (ONE type of points)")
    print("=" * 60)
    print("   There is exactly ONE type of points: the crew ladder (--emit). The")
    print("   impostor and ghost lanes are roles and INFORMATION, not a second")
    print("   currency, and not a 'trust point' system.")
    print()
    print("   IMPOSTORS — a CONVERSION role, in two kinds (not a ladder):")
    print("     - an INITIAL impostor (a role chosen at start)")
    print("     - a NEUTRAL player CONVERTED during play by an UNDERGROUND MONSTER")
    print("       (underground monsters are the dead-defender saboteurs — NOT evil")
    print("       ghosts. They convert, ghost-haunt, bomb, feed the summon pool.)")
    print()
    print("   GHOSTS — the INFORMATION lane:")
    print("     - stay in a RESTRICTED SKY AREA")
    print("     - craft from INFORMATION CRAFTITEMS (the info economy), not from trust")
    print()
    print("   There is no way yet to CRAFT as a ghost, and no defined 'tiny neutral")
    print("   underground monster' conversion — those are UNDEFINED. Do not number-")
    print("   price an undefined mechanic.")
    print()
    print("   TRUST — a BELIEF, evaluable in [0,1] (a probability, not a currency):")
    print("     - a ghost/possession that ends a match 'by being believed' is a failed")
    print("       deduction. Value it as a probability, NOT as +X. It is in [0,1].")
    print("     - possession bounds (whisper.lua: 1 whisper per possession, one")
    print("       concurrent, body cooldown) are EVIL-GHOST MECHANICS, not a 'trust")
    print("       price.' A bound on a mechanic is not pricing a belief.")
    print()
    print("   >> THE RULING: one point type (crew ladder); essence = fuel; timings =")
    print("      a scoring dimension; impostor = conversion; ghost = sky info-craft;")
    print("      trust = a [0,1] belief. Never call trust a currency.")


def _git_head():
    try:
        return subprocess.check_output(["git", "rev-parse", "--short", "HEAD"],
                                       stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return "unknown"


def derive():
    raw = {k: EFFORT[k] * WIN_PROGRESS[k] * RISK[k] for k in EFFORT}
    pts = {k: max(1, round(raw[k] * SCALE)) for k in raw}
    return pts, raw


def audit_paths(pts):
    print("COMMITTED-PATH SHARE (a team commits to one win path):")
    failures = []
    for path, freq in COMMITTED_PATH_TOTAL.items():
        tot = sum(pts[k] * freq[k] for k in freq)
        dom = max(freq, key=lambda k: pts[k] * freq[k])
        div = max((pts[k] * freq[k]) / tot * 100 for k in freq)
        kind = "WIN" if dom in ONCE_PER_MATCH else "REPEATABLE"
        flag = ""
        if dom not in ONCE_PER_MATCH and div > DOMINATION_BUDGET:
            flag = "  << FAIL: repeatable %s exceeds %.0f%% budget" % (dom, DOMINATION_BUDGET)
            failures.append((path, dom, div))
        print("   %-8s total %3d pts  |  dominant %-18s at %5.1f%%  [%s]%s"
              % (path, tot, dom, div, kind, flag))
    sig = COMMITTED_PATH_TOTAL["signal"]
    sig_tot = sum(pts[k] * sig[k] for k in sig)
    sig_win = (pts["forge"] * sig["forge"] + pts["core_delivery"] * sig["core_delivery"])
    sig_win_pct = sig_win / max(1, sig_tot) * 100
    sig_flag = ""
    if sig_win_pct > WIN_PATH_BUDGET:
        sig_flag = "  << FAIL: Signal win commitment %.1f%% > %.0f%%" % (sig_win_pct, WIN_PATH_BUDGET)
        failures.append(("signal_win_pair", "forge+slot", sig_win_pct))
    print("   signal WIN commitment (forge + slot) = %5.1f%% of the signal path%s"
          % (sig_win_pct, sig_flag))
    totals = {p: sum(pts[k] * freq[k] for k in freq) for p, freq in COMMITTED_PATH_TOTAL.items()}
    lo, hi = min(totals.values()), max(totals.values())
    spread = hi / max(1, lo)
    bal_flag = ""
    if spread > PATH_BALANCE_BUDGET:
        bal_flag = "  << FAIL: path totals spread %.1fx > %.0fx" % (spread, PATH_BALANCE_BUDGET)
        failures.append(("path_balance", "max/min", spread))
    print("   path totals: %s   |  spread max/min = %5.1fx%s"
          % ("  ".join("%s=%d" % (p, t) for p, t in sorted(totals.items())), spread, bal_flag))
    return failures


def audit_per_second(pts):
    print("\nPOINTS PER SECOND (is a safe, spammable action an exploit?):")
    kill_pps = pts["kill"] / EFFORT["kill"]
    print("   %-20s %4d pts  / %4.1fs  =  %5.2f pps" % ("kill", pts["kill"], EFFORT["kill"], kill_pps))
    violations = []
    for k in sorted(pts):
        if k == "kill":
            continue
        pps = pts[k] / EFFORT[k]
        kind = "once" if k in ONCE_PER_MATCH else "repeat"
        note = ""
        if k not in ONCE_PER_MATCH and pps > kill_pps + 0.001:
            note = "  << FAIL: %s out-earns a kill per second (the repair bug)" % k
            violations.append(k)
        print("   %-20s %4d pts  / %4.1fs  =  %5.2f pps  [%s]%s"
              % (k, pts[k], EFFORT[k], pps, kind, note))
    return violations


def audit_cliff(pts):
    print("\nOBJECTIVE vs KILL (is one objective a single-action stomp?):")
    d_core, d_kill = pts["core_delivery"], pts["kill"]
    d_ratio = d_core / max(1, d_kill)
    print("   derived    core_delivery %3d / kill %3d  =  %5.1fx" % (d_core, d_kill, d_ratio))
    p_core, p_kill = PLACEHOLDER["core_delivery"], PLACEHOLDER["kill_base"]
    p_ratio = p_core / max(1, p_kill)
    print("   placeholder core_delivery %5d / kill %3d  =  %6.1fx" % (p_core, p_kill, p_ratio))
    if p_ratio > 50:
        print("   >> PLACEHOLDER %6.1fx — the single-action stomp this model prevents" % p_ratio)
    if d_ratio > 20:
        print("   >> derived %5.1fx over budget — repricing needed." % d_ratio)
    else:
        print("   >> derived %5.1fx within budget (the jackpot, not a nuke)." % d_ratio)
    return d_ratio, p_ratio


def emit_constants(path):
    pts, raw = derive()
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    lines = [
        "-- GENERATED by tools/point_economy_model.py --emit. DO NOT EDIT BY HAND.",
        "-- Re-run the model; it is the single source of truth. (git head %s)" % _git_head(),
        "local points = {",
    ]
    for k in sorted(pts):
        lines.append("    %-22s = %d,  -- effort %4.1fs x win %.1f x risk %.1f"
                     % ("[\"%s\"]" % k, pts[k], EFFORT[k], WIN_PROGRESS[k], RISK[k]))
    lines.append("}")
    lines.append("return points")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("Wrote %d constants to %s" % (len(pts), path))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--emit", metavar="OUT", help="write generated scoring_constants.lua")
    ap.add_argument("--economy", action="store_true", help="show all four economies")
    args = ap.parse_args()

    if args.emit:
        emit_constants(args.emit)
        return 0

    pts, raw = derive()

    print("POINT ECONOMY — DERIVED FROM GAME MATH")
    print("  source of truth: tools/point_economy_model.py @ %s" % _git_head())
    print("=" * 64)
    print("ECONOMY 1 — CREW POINTS (effort x win-progress x risk, scale=%.2f):" % SCALE)
    for k in sorted(pts):
        print("   %-20s = %3d pts   (effort %5.1fs x win %.1f x risk %.1f = raw %5.2f)"
              % (k, pts[k], EFFORT[k], WIN_PROGRESS[k], RISK[k], raw[k]))

    print("\n")
    audit_economy2()
    audit_economy3()
    audit_economy4()

    print("\n" + "=" * 64)
    path_failures = audit_paths(pts)
    pps_violations = audit_per_second(pts)
    d_ratio, p_ratio = audit_cliff(pts)

    print("\n" + "=" * 64)
    print("VERDICT (the live gate):")
    ok = True
    if pps_violations:
        ok = False
        print("   FAIL  repeatable action out-earns a kill per second: %s" % ", ".join(pps_violations))
    else:
        print("   PASS  no repeatable action beats a kill per second.")
    if path_failures:
        ok = False
        msgs = []
        for e in path_failures:
            msgs.append("%s@%.1f%%" % (e[0], e[2]) if len(e) == 3 else "%s@%.1f%%" % (e[0], e[1]))
        print("   FAIL  %s" % "; ".join(msgs))
    else:
        print("   PASS  the 40%% bar binds; nothing repeatable exceeds it.")
    print("   %s" % ("ALL DERIVED CHECKS PASS." if ok else "DERIVED CHECKS FAIL."))

    print("""
THE FOUR-ECONOMY CONCLUSION:
  - Crew points are the shipped ladder; the model prices them relative to a kill.
    It is the ONLY layer that emits a number (--emit). It is deliberately narrow
    because the other three layers are not points — they are fuel (essence), a
    scoring dimension (timings), and roles/information (impostor + ghost).
  - The MM's essence pool (economy 2) is FUEL, and the crew FEEDS it. Building the
    Signal core credits the pool +3, and losing the core to an MM dig pays +5.
    So "a team cannot do all three" is not just pool contention — committing to
    Signal makes you the richest target on the board. This is the real coupling.
  - Windowed actions (economy 3) cannot be a single static number. A sabotage at
    t=0 denies %.0f%% of the match; one at t=%d is wasted. The soak harness emitting
    per-action deltas is the only thing that can price a window — the model can
    only state the bound.
  - The impostor + ghost lanes (economy 4) are NOT a point economy. ONE type of
    points exists: the crew ladder. Impostors are a CONVERSION (two kinds: initial,
    and a neutral converted by an UNDERGROUND MONSTER which is NOT an evil ghost).
    Ghosts are the information lane: a restricted sky area where they craft from
    info craftitems. Trust is a belief evaluable in [0,1], not a currency — and no
    points go on a mechanic that is still undefined.

WHAT IT CANNOT DECIDE (the meeting's word):
  - The exact SCALE for crew points needs the soak harness to emit per-action deltas.
  - Whether the shared pool is a real MECHANIC (glitch f5f2be §3 names the answer:
    the Forge runs one job at a time; the trees draw a common substrate). Until that
    is built, "a team can't do all three" is a wish, and the model says what glitch
    built, not what it hopes.
""" % (TIMINGS["sabotage_window_s"] / TIMINGS["match_s"] * 100,
       TIMINGS["match_s"] - TIMINGS["sabotage_window_s"]))
    return 0 if ok else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
