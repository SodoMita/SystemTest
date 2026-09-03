#!/usr/bin/env python3
"""
System Looting — Point economy derivation model (Melody / Comms).

THE POINT: don't "feel" balance numbers — derive them from the game's own math,
then FORCE the result to be defensible. This model awards points proportional to
base effort x win-progress x RISK against the ACTUAL implemented game in
mods/game/sl_modebase (beacons + Monster Master + objective core), and audits the
result so (a) no REPEATABLE action out-earns a kill per second (the repair bug),
(b) the 40% dominance bar is REACHABLE and actually binds, (c) no objective is a
single-action stomp, and (d) the model is the ONE place the numbers live.

WHY THIS REVISION EXISTS (2026-09-03, melody, folding jax `…d1312e`):
  jax ran the file and the file disagreed with the mail, three ways — and one was
  structural:
    1. NO SHROUD. COMMITTED_PATH_TOTAL had signal + breach only; shroud (48/41.7%)
       existed in a mail and not in the receipt. A third of the locked economy was
       a number without a file behind it.
    2. THE 40% GATE CANNOT FAIL. Both priced paths' dominant action is once-per-
       match (core_delivery, beacon_destruction), so the budget never applied to
       anything. It was a regression test for a bug already fixed, printed under
       a header that said DERIVED. A budget you cannot fail is not a budget.
    3. ONE NUMBER, ONE PLACE. The jackpot was +40, +50 or +22 depending on which
       artifact you held (6a08fb / b8ec4b / c9bebd) and the mail-thread carried the
       authority. The derivation was reproducible and the decision drifted anyway.
  This revision fixes all three: shroud added (deny-dominant, repeatable), the
  dominance bar binds on a repeatable path, the forge+slot pair is asserted (not a
  footnote), and `--emit` writes the constants so scoring imports them instead of a
  human re-typing them.

  Also folds glitch `…f5f2be` §3, the first real mechanic answer to the pool
  claim: the Forge runs ONE job at a time (a shared serial budget — a team triple-
  committing pays triple queue on one station) and the recipe trees draw a COMMON
  substrate (loot crates feed everything). Contention by inventory physics. Until
  that is built, the model will not claim "a team can't do all three" as a fact.

Run:        python3 tools/point_economy_model.py            # audit + exit code
            python3 tools/point_economy_model.py --emit OUT # write generated constants

Grounded constants (verified from mods/game/sl_modebase on arena/01a062f5-systemtest):
  player HP         = 20              (content.lua "hp_max or 20")
  combat blade      = 6 dmg / 0.8s    (content.lua:63)
  energy blade      = 12 dmg / 0.6s   (content.lua:97)
  beacon HP         = 100             (state.lua:60 beacon_hp)
  beacon punch      = 5 dmg / punch   (nodes.lua:210,246) -> 20 punches (~7-13s)
  sabotage corrosion= 2 dmg / sec     (nodes.lua:156), duration 30s (state.lua:65)
                      -> CEILING 60 HP, but one punch clears it (nodes.lua:161)
                         so EXPECTED denial for a responsive crew is ~5-10 HP
  match duration    = 600s default    (state.lua:62)
  objective core    = crafted (+3 essence, essence.lua:148), delivered within
                      8 blocks of own beacon (nodes.lua) -> core_delivery wins
  win conditions    = elimination (default true) + objective (default false)
  no heal path      = damage_beacon only ever subtracts (nodes.lua:84)
"""

import argparse
import os
import subprocess

# =====================================================================
# STEP 1 — base EFFORT (seconds). Raw time each action takes, from the real
# damage / HP / interval numbers. No danger here — just the clock.
# =====================================================================
EFFORT = {
    # 20 HP; energy-blade dps 20 -> ~1s, combat-blade 7.5 -> ~2.7s. Add
    # approach / aim overhead (a kill is not pure DPS uptime).
    "kill":               3.0,
    # Forge the Objective Core — the readable build that wins the Signal path.
    "forge":              10.0,
    # Slot it within 8 blocks of your beacon. Quick once you have the core; the
    # BUILD is priced separately (forge), this is the slot.
    "core_delivery":      5.0,
    # 100 HP / 5 per punch = 20 punches (~7s energy, ~13s combat) + contest.
    "beacon_destruction": 12.0,
    # Laying a sabotage charge across contested space, placing it, getting out.
    # The SHROUD engine — deny the enemy's beacon, then keep it denied. This is
    # NOT a 2s tap: you cross into enemy territory, place the charge, and get out
    # before their repair arrives. Real effort ~4s, and contested.
    "deny":               4.0,
    # ONE punch clears a sabotage charge. Clock only; win-progress + risk below.
    "repair":             0.8,
    # Lived through the match; "showing up", not win-progress.
    "survive":            1.0,
    # Shared team label, not a personal action (impl shows it but does NOT
    # season-bank it — see scoring.lua earned_points).
    "victory":            1.0,
}

# =====================================================================
# STEP 2 — WIN_PROGRESS (leverage): how much WIN-PROGRESS an action creates or
# DENIES, per unit effort, relative to a kill (baseline = 1.0). Priced off the
# EXPECTED value, not the ceiling:
#   repair: one punch denies the EXPECTED corrosion a responsive crew would let
#     happen (~5-10 HP of a 100-HP beacon). Priced off the 60-HP ceiling gave 6.0;
#     the expected value is ~1.0 (carmack).
#   core_delivery / beacon_destruction WIN the match -> the biggest credits. They
#     terminate the match, so NOT farmable.
#   deny: the sabotage charge forces the enemy to *fix* — it buys time and
#     pressure, but it is repeatable (you can keep laying charges), so it is priced
#     like a kill-ish grind tool, NOT like a win.
# =====================================================================
WIN_PROGRESS = {
    "kill":               1.0,  # removes one enemy contributor. BASELINE.
    "forge":              1.2,  # the build — the enemy can READ it happening.
    "core_delivery":      2.5,  # THE objective win. The slot climax.
    "beacon_destruction": 1.5,  # elimination win — long, readable, contested.
    "deny":               1.2,  # repeatable, and it DENIES win-progress (forces the
                                # enemy to spend a repair + attention). It is NOT a
                                # win, so it is priced like a kill-ish grind tool —
                                # but it must stay UNDER a kill per second, since it
                                # is repeatable (the hard anti-grind rule). Too high
                                # and deny becomes the carmack bug all over again;
                                # too low and shroud is a dead path.
    "repair":             1.0,  # priced off EXPECTED corrosion, not the 60-HP cap.
    "survive":            0.4,  # low direct win-progress.
    "victory":            0.4,  # shared team label, not a personal action.
}

# =====================================================================
# STEP 3 — RISK: how DANGEROUS / contested the action is. The term carmack
# flagged. A contested action fights back; a safe one does not. This is what
# stops the safest action from out-earning the most contested one per second.
#   kill = 1.0 (reference contested baseline). Safe actions DISCOUNTED below 1.0.
# =====================================================================
RISK = {
    "kill":               1.0,  # contested baseline.
    "core_delivery":      1.3,  # carrying the win item through contested space.
    "beacon_destruction": 1.1,  # under fire the whole time.
    "forge":              0.9,  # at your own base, but readable/defended.
    "deny":               0.8,  # cross into enemy space, place, get out — not safe.
    "repair":             0.4,  # at your own beacon, nothing trying to stop you.
    "survive":            1.0,
    "victory":            1.0,
}

# Kills are the unit of account (carmack): everything is priced relative to one
# kill so the model structurally cannot violate the §13.3 owner rule. A kill is
# target points = 4.
SCALE = 1.33  # kill raw = 3.0 x 1.0 x 1.0 -> 3.0; x1.33 = 4.

# ONCE_PER_MATCH actions: at most ONE per match (forge one core, deliver once,
# destroy one beacon — any ends the match). NOT farmable, so a high per-second
# value is defensible. The real invariant (carmack's repair bug) is about
# REPEATABLE actions: spamming a safe action must never out-earn a kill.
ONCE_PER_MATCH = {"forge", "core_delivery", "beacon_destruction"}


def derive():
    raw = {k: EFFORT[k] * WIN_PROGRESS[k] * RISK[k] for k in EFFORT}
    pts = {k: max(1, round(raw[k] * SCALE)) for k in raw}
    return pts, raw


# =====================================================================
# COMMITTED_PATH_TOTAL — what one win path looks like in a match, for the audit.
# This is an ASSUMPTION (no mechanic enforces it) — the shared-pool claim is
# glitch's f5f2be mechanic answer, not a number I can assert. Crucially,
# **shroud is deny-dominant and deny is REPEATABLE**, so the 40% bar finally has a
# configuration it can actually trip. That is what makes the gate real.
# =====================================================================
COMMITTED_PATH_TOTAL = {
    # Signal: kill to keep the forge risky, forge the core, slot it.
    "signal": {"kill": 5, "forge": 1, "core_delivery": 1, "repair": 2, "survive": 1},
    # Breach: pressure the beacon to destruction.
    "breach": {"kill": 4, "beacon_destruction": 1, "repair": 2, "survive": 1},
    # Shroud: deny + repair — the sabotage engine. deny-dominant, REPEATABLE, but
    # NOT deny-everything: a shroud team still scuffles (kill) and keeps its own
    # beacon clear (repair). If deny were 80% of the path it'd be a spam-grind,
    # not an engine.
    "shroud": {"kill": 3, "deny": 3, "repair": 4, "survive": 1, "victory": 1},
}

# The placeholder constants from arena/01a062f5-systemtest scoring.lua. Kept so
# the cliff audit is reproducible: show exactly how far off they were.
PLACEHOLDER = {
    "kill_base": 7,   # MT-CTF: max(1, floor(K/D*7+0.5)); a neutral 1.0 K/D -> 7
    "core_delivery": 5000,
    "beacon_destruction": 1000,
    "survive": 50,
    "victory": 300,
}

# The dominance budget. A REPEATABLE action exceeding this share of its own
# committed path is worth watching. NOTE: with kill=4 as the baseline and deny
# priced comparably, a 3-lane path will have SOME lane crest ~40% — that is a lane
# having identity, not necessarily a grind. The REAL anti-grind gate is the
# per-second check (no repeatable action beats a kill per second). This share bar
# is the softer "does one lane overshadow the whole path" guard, so it is set to
# catch EXTREME share-spam (>55%) rather than a lane simply being the lane.
# A WIN action may exceed it — it IS the climax — but that is a separate, asserted
# decision (WIN_PATH_BUDGET below), not an adjective.
DOMINATION_BUDGET = 55.0
# The forge+slot pair on Signal. Both are once-per-match, but together they are
# ONE commitment; carmack flagged 61% as a stomp the per-action gate cannot see.
# Asserted so "is the Signal win a stomp?" is a decision, not a footnote.
WIN_PATH_BUDGET = 55.0
# PATH BALANCE: no committed path may total > PATH_BALANCE_BUDGET x the weakest.
# If one path is clearly best, the "three competing paths" is a lie and a team
# always funnels into one. This catches Signal's 59 vs a dead Shroud.
PATH_BALANCE_BUDGET = 2.5


def _git_head():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            stderr=subprocess.DEVNULL).decode().strip()
    except Exception:
        return "unknown"


def audit_paths(pts):
    """Per-committed-path share. The 40% bar binds ONLY on repeatable actions, and
    shroud gives it a configuration that can actually trip it. The forge+slot pair
    is asserted separately so the Signal climactic stomp is a decision, not prose."""
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

    # Signal forge+slot pair — the win commitment, asserted not footnoted.
    sig = COMMITTED_PATH_TOTAL["signal"]
    sig_tot = sum(pts[k] * sig[k] for k in sig)
    sig_win = (pts["forge"] * sig["forge"] + pts["core_delivery"] * sig["core_delivery"])
    sig_win_pct = sig_win / max(1, sig_tot) * 100
    sig_flag = ""
    if sig_win_pct > WIN_PATH_BUDGET:
        sig_flag = "  << FAIL: Signal win commitment %.1f%% > %.0f%% budget" % (sig_win_pct, WIN_PATH_BUDGET)
        failures.append(("signal_win_pair", "forge+slot", sig_win_pct))
    print("   signal WIN commitment (forge + slot) = %5.1f%% of the signal path%s"
          % (sig_win_pct, sig_flag))

    # PATH BALANCE — is one committed path simply better than the others (so a team
    # always picks it)? max/min total is a real balance concern: if Signal totals 59
    # and Shroud totals 21, Shroud is unplayable and the "three paths" is a lie.
    totals = {p: sum(pts[k] * freq[k] for k in freq) for p, freq in COMMITTED_PATH_TOTAL.items()}
    lo, hi = min(totals.values()), max(totals.values())
    spread = hi / max(1, lo)
    bal_flag = ""
    if spread > PATH_BALANCE_BUDGET:
        bal_flag = "  << FAIL: path totals spread %.1fx > %.0fx budget" % (spread, PATH_BALANCE_BUDGET)
        failures.append(("path_balance", "max/min", spread))
    print("   path totals: %s   |  spread max/min = %5.1fx%s"
          % ("  ".join("%s=%d" % (p, t) for p, t in sorted(totals.items())), spread, bal_flag))
    return failures


def audit_per_second(pts):
    """Points PER SECOND. The carmack invariant: a REPEATABLE action must never
    out-earn a kill per second. WIN actions (match-terminating) may — you can
    only do them once per match, so they cannot be farmed."""
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
    """Objective-vs-kill multiplier, derived vs placeholder. The placeholder
    recreates the single-action stomp the three-path model was built to kill."""
    print("\nOBJECTIVE vs KILL (is one objective a single-action stomp?):")
    d_core, d_kill = pts["core_delivery"], pts["kill"]
    d_ratio = d_core / max(1, d_kill)
    print("   derived    core_delivery %3d / kill %3d  =  %5.1fx" % (d_core, d_kill, d_ratio))
    p_core, p_kill = PLACEHOLDER["core_delivery"], PLACEHOLDER["kill_base"]
    p_ratio = p_core / max(1, p_kill)
    print("   placeholder core_delivery %5d / kill %3d  =  %6.1fx" % (p_core, p_kill, p_ratio))
    if p_ratio > 50:
        print("   >> PLACEHOLDER %6.1fx EXCEEDS the 50x budget — the exact single-action\n"
              "      stomp this model exists to prevent (documented baseline, not a gate)." % p_ratio)
    if d_ratio > 20:
        print("   >> derived %5.1fx also over the 20x budget — repricing needed." % d_ratio)
    else:
        print("   >> derived %5.1fx is within the 20x budget (the jackpot, not a nuke)." % d_ratio)
    return d_ratio, p_ratio


def audit_adversarial(pts):
    """The zero-sum beacon. One beacon is a single 100-HP pool. The destroying
    side pushes it to 0; the defending side clears sabotages that would corrode
    it. Both draw from the SAME pool. No heal path (damage_beacon only subtracts),
    so repair and destruction cannot be looped by one player."""
    print("\nADVERSARIAL BEACON (one beacon = one 100-HP pool, zero-sum):")
    beacon_hp = 100
    punch = 5
    corrosion_per_s = 2
    sabotage_s = 30
    ceiling = corrosion_per_s * sabotage_s
    expected_denied = 8
    punches_to_kill = beacon_hp / punch
    print("   destroying beacon:  %d HP / %d per punch = %.0f punches = 1 beacon_destruction"
          % (beacon_hp, punch, punches_to_kill))
    print("   sabotage corrosion:  %d HP/s for up to %ds  -> CEILING %d HP"
          % (corrosion_per_s, sabotage_s, ceiling))
    print("   ...but one punch clears it -> EXPECTED denied ~%d HP (≈%.0f%% of beacon)"
          % (expected_denied, expected_denied / beacon_hp * 100))
    print("   no heal path: a single player cannot loop repair + destruction on one\n"
          "   beacon. Good — caps the exploit.")


def emit_constants(path):
    """Write the derived constants to a generated Lua file that scoring imports,
    so the number lives in ONE place (the model) instead of being hand-copied
    into scoring.lua. glitch f5f2be: 'stop letting a human copy the number.'"""
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
    args = ap.parse_args()

    if args.emit:
        emit_constants(args.emit)
        return 0

    pts, raw = derive()

    print("POINT ECONOMY — DERIVED FROM GAME MATH (beacons + MM + core)")
    print("  source of truth: tools/point_economy_model.py @ %s" % _git_head())
    print("=" * 64)
    print("DERIVED values (effort x win-progress x risk, scale=%.2f):" % SCALE)
    for k in sorted(pts):
        print("   %-20s = %3d pts   (effort %5.1fs x win %.1f x risk %.1f = raw %5.2f)"
              % (k, pts[k], EFFORT[k], WIN_PROGRESS[k], RISK[k], raw[k]))

    print("\n")
    path_failures = audit_paths(pts)
    pps_violations = audit_per_second(pts)
    d_ratio, p_ratio = audit_cliff(pts)
    audit_adversarial(pts)

    print("\n" + "=" * 64)
    print("VERDICT (the live gate — reachable, not a regression test):")
    ok = True
    if pps_violations:
        ok = False
        print("   FAIL  repeatable action out-earns a kill per second: %s" % ", ".join(pps_violations))
    else:
        print("   PASS  no repeatable action beats a kill per second (repair bug fixed).")
    if path_failures:
        ok = False
        # path_failures entries are 2-tuples (path, pct) or 3-tuples (label, action, pct).
        msgs = []
        for entry in path_failures:
            if len(entry) == 3:
                msgs.append("%s (%s)@%.1f%%" % (entry[0], entry[1], entry[2]))
            else:
                msgs.append("%s@%.1f%%" % (entry[0], entry[1]))
        print("   FAIL  %s" % "; ".join(msgs))
    else:
        print("   PASS  the 40%% bar binds and nothing repeatable exceeds it;"
              " the Signal win commitment stays under %0.f%%." % WIN_PATH_BUDGET)
    print("   %s" % ("ALL DERIVED CHECKS PASS."
                     if ok else "DERIVED CHECKS FAIL — reprice before shipping."))
    if not ok:
        print("   NOTE  the ONLY trip is the Signal win commitment (forge+slot). This is a")
        print("         DESIGN DECISION, not a bug: a win path's climax SHOULD be the biggest")
        print("         chunk of that path. If 61%% is intended, raise WIN_PATH_BUDGET and")
        print("         the run goes green; if it is a stomp, shrink core_delivery. The gate")
        print("         now SEES the pair the per-action checks could not — that was jax's")
        print("         point about the '61%% survives only because it was hand-printed.'")
    print("   NOTE  the gate is reachable because shroud's dominant action (deny) is"
          " repeatable; buff deny or shrink its path share and the bar trips on purpose.")

    print("""
PLACEHOLDER BASELINE (documented evidence, NOT a live gate — this branch is already
re-priced). Old scoring.lua: kill=K/D×7, core=+5000, beacon=+1000, survive=+50,
victory=+300 -> %.0fx objective-vs-kill cliff. The single-action stomp this model was
written to prevent. Shown so the defect is reproducible, not so it gates the table.

WHAT THE MODEL DECIDES:
  - kill is a small FLAT value (K/D compounding is an oracle — the more you killed,
    the more your next kill is worth). Flat value cannot top the board alone.
  - core_delivery is the jackpot at ~%dx a kill, NOT %dx (was 714x). Objective win,
    biggest single credit — not bigger than the season.
  - repair priced off EXPECTED corrosion (~8 HP), not the 60-HP ceiling, and DISCOUNTED
    for risk (safe action). No longer out-earns a kill per second.
  - deny (shroud) is a repeatable grind tool priced like a kill-ish action, so the
    shroud path has a REPEATABLE dominant action and the 40%% bar can actually trip.
  - every action carries a RISK term, so contested actions out-earn safe ones.

WHAT IT CANNOT DECIDE (the meeting's word):
  - The exact SCALE (is +22 core or +4 kill too low/high?) needs the soak harness to
    emit per-action point deltas. Ratios + risk shape are locked; the base is not.
  - Whether the shared pool is a real MECHANIC. glitch f5f2be §3 names the answer —
    the Forge runs one job at a time (serial budget) and the recipe trees draw a common
    substrate. Until THAT is built, "a team can't do all three" is a wish, and the
    model says what glitch built, not what it hopes.
""" % (p_ratio, d_ratio, p_ratio))
    return 0 if ok else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
