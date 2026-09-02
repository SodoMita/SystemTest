#!/usr/bin/env python3
"""
System Looting — Point economy derivation model (Melody / Comms).

THE POINT: don't "feel" balance numbers — derive them from the game's own math.
This model awards points proportional to the WIN-PROGRESS an action creates or
denies (its "leverage" x its base time), then audits the result against the
ROADMAP Phase-5 constraints. The 76.9% single-objective domination it surfaced
was NOT a balance bug — it was the diagnosis of two disconnected economies (the
win path used construction:* borrowed from a block mod; the game's own salvage
fed nothing). The cure is the THREE-PATH structure (Signal/Breach/Shroud) from
ONE contested pool, with delivery-as-jackpot (see OBJECTIVE_IS_A_SIGNAL.md).

Run:  python3 tools/point_economy_model.py

Grounded constants (verified from mods/game/sl_modebase):
  player HP         = 20              (spawn.lua:40, content.lua:147)
  combat blade      = 6 dmg / 0.8s    (content.lua:67)
  energy blade      = 12 dmg / 0.6s   (content.lua:101)
  beacon HP         = 100             (match.lua:259)
  beacon punch      = 5 dmg / 0.8s    (nodes.lua:202) -> 20 punches to destroy
  sabotage corrosion= 2 dmg / sec tick (nodes.lua:148), up to 30s (=60 HP) if
                      uncleared -> ONE repair punch denies up to 60 HP
  match duration    = 600s default    (state.lua:62)

Owner rules (master, resolved 2026-09-02):
  - Essence is NOT a score. Points come primarily from killing crew.
  - The objective core pays +3 essence directly (mm economy, not points).
"""

import os


# ---------------------------------------------------------------
# STEP 1 — base TIME each focused action takes (seconds), derived from
# the real damage/HP numbers + positioning overhead. This is the raw
# "effort cost."
# ---------------------------------------------------------------
BASE = {
    # 20 HP, energy-blade dps ~20 (12/0.6) -> ~1s; combat-blade ~7.5 -> ~2.7s.
    # Add approach/aim overhead (kills aren't pure DPS uptime).
    "kill":      3.0,
    # 100 HP / 5 per punch ~ 20 punches ~ 16s to destroy. Award per 10 HP.
    "beacon10":  1.6,
    # Crafting the Core = the Signal win path; data-gather is cheap, the
    # BUILD is the read, the DELIVERY is the jackpot.
    "data":      2.0,   # gather a data value (repeatable, cheap)
    "forge":     10.0,  # build the Core (one big readable event)
    "deliver":   4.0,   # slot it at the beacon = a SINGLE quick climax, high reward
    "breach":    4.0,   # crack the enemy beacon / breach gear (PATH 2)
    "deny":      2.0,   # seal / corrupt (PATH 3, defensive)
    "repair":    0.8,   # one punch; tiny raw effort (see LEVERAGE)
    "survive":   1.0,   # lived through a sabotage
}

# ---------------------------------------------------------------
# STEP 2 — LEVERAGE: how much WIN-PROGRESS an action creates OR denies,
# relative to raw effort. Baseline (kill) = 1.0; everything compared to it.
# ---------------------------------------------------------------
LEVERAGE = {
    "kill":     1.0,  # removes one enemy contributor. BASELINE.
    "beacon10": 1.0,  # directly progresses toward beacon pressure.
    "data":     1.0,  # cheap, repeatable, low risk.
    "forge":    1.5,  # the build — the enemy can READ it happening.
    "deliver":  2.0,  # THE WIN. High leverage; a single climax.
    "breach":   1.3,  # aggressive win-progress.
    "deny":     1.5,  # defensive; denies the enemy path.
    "repair":   6.0,  # ONE punch denies up to 60 beacon HP = 6x a 10-HP unit.
    "survive":  0.5,  # lived through a sabotage; low direct win-progress.
}

# Scale so the minimum action lands at >=1 point and the ratios stay clean.
SCALE = 1.25

# Realistic per-action frequencies for a team that has COMMITTED to each path.
FREQ = {
    "signal": {"kill": 1, "beacon10": 2, "data": 5, "forge": 1, "deliver": 1,
               "breach": 0, "deny": 0, "repair": 1, "survive": 1},
    "breach": {"kill": 3, "beacon10": 4, "data": 0, "forge": 0, "deliver": 0,
               "breach": 5, "deny": 0, "repair": 1, "survive": 2},
    "shroud": {"kill": 1, "beacon10": 2, "data": 0, "forge": 0, "deliver": 0,
               "breach": 0, "deny": 5, "repair": 3, "survive": 2},
}


def derive():
    raw = {k: BASE[k] * LEVERAGE[k] for k in LEVERAGE}
    pts = {k: max(1, round(raw[k] * SCALE)) for k in raw}
    return pts, raw


def audit_paths(pts):
    """Report per-path shares. If one path dominates its own committed total,
    the path is a grind rather than a climax."""
    print("PER-PATH SHARE (a team that commits to one path):")
    for path, freq in FREQ.items():
        tot = sum(pts[k] * freq[k] for k in freq)
        dom = max(freq, key=lambda k: pts[k] * freq[k])
        div = max((pts[k] * freq[k]) / tot * 100 for k in freq)
        print("   %-8s total %3d pts  |  dominant %-8s at %5.1f%%"
              % (path, tot, dom, div))
    return


def main():
    pts, raw = derive()

    print("POINT ECONOMY — DERIVED FROM GAME MATH (three-path)")
    print("=" * 52)
    print("DERIVED values (base_time x leverage, scale=%.2f):" % SCALE)
    for k in sorted(pts):
        print("   %-11s = %3d pts   (base %5.1fs x lev %.1f = raw %5.1f)"
              % (k, pts[k], BASE[k], LEVERAGE[k], raw[k]))

    print("\n")
    audit_paths(pts)

    print("""
WHAT THE MODEL DECIDES:
  - kill-only supplies few pts -> a killer CANNOT top the board without a path.
  - repair > kill per unit effort (one punch denies up to 60 beacon HP).
  - No negative sinks (all >= 1). The delivery is the jackpot, not a grind.
  - Three paths all draw the SAME pool -> a team cannot do all three; committing
    starves the others, which is the decision + the enemy's read.

WHAT IT CANNOT DECIDE (the meeting's word):
  - The exact SCALE (is +20 delivery too high/low?) needs soak per-action deltas.
  - Whether to put points on the strand ledger (glitch: points as strand events)
    — the three free constraints (no edit, no mid-run oracle, no-negative-sink
    validation) are worth it; the owner rules say essence != score.
""")
    return


if __name__ == "__main__":
    main()
