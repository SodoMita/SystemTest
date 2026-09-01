#!/usr/bin/env python3
"""
System Looting — Point economy derivation model (Melody / Comms).

THE POINT: don't "feel" balance numbers — derive them from the game's own math.
This model awards points proportional to the WIN-PROGRESS an action creates or
denies (its "leverage" x its base time), then audits the result against the
ROADMAP Phase-5 constraints. It gives a defensible RELATIVE ordering and a
clean integer starting set. The absolute scale + whether it FEELS right still
needs soak validation, but the math gets us to a principled first pass.

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
"""

import collections


# ---------------------------------------------------------------
# STEP 1 — base TIME each focused action takes (seconds), derived from
# the real damage/HP numbers + positioning overhead. This is the raw
# "effort cost."
# ---------------------------------------------------------------
BASE = {
    # 20 HP, energy-blade dps ~20 (12/0.6) -> ~1s; combat-blade ~7.5 -> ~2.7s.
    # Add approach/aim overhead (kills aren't pure DPS uptime).
    "kill":     3.0,
    # 100 HP / 5 per punch ~ 20 punches ~ 16s to destroy. Award per 10 HP.
    "beacon10": 1.6,
    # Crafting the Core = the headline win path; multi-step + travel + risk.
    "objective":8.0,
    # Repair = one punch (~0.8s). Raw effort is tiny; see LEVERAGE.
    "repair":   0.8,
    # Sabotage-survived: you took the hit and came out the other side.
    "survive":  1.0,
}

# ---------------------------------------------------------------
# STEP 2 — LEVERAGE: how much WIN-PROGRESS an action creates OR denies,
# relative to raw effort. Baseline (kill) = 1.0; everything compared to it.
# ---------------------------------------------------------------
LEVERAGE = {
    "kill":     1.0,  # removes one enemy contributor. BASELINE.
    "beacon10": 1.0,  # directly progresses toward beacon pressure. baseline.
    "objective":2.0,  # crafting/delivering the Core = the actual win. highest.
    "repair":   6.0,  # ONE punch denies up to 60 beacon HP = 6x a 10-HP unit.
    "survive":  0.5,  # survived a sabotage; low direct win-progress.
}

# Scale so the minimum action lands at >=1 point and the ratios stay clean.
SCALE = 1.25

# Realistic per-action frequencies in a full 600s match (design estimate).
FREQ = {"kill": 2, "beacon10": 4, "objective": 5, "repair": 2, "survive": 2}


def derive():
    """Return the integer point set + the realistic-freq audit."""
    raw = {k: BASE[k] * LEVERAGE[k] for k in LEVERAGE}
    pts = {k: max(1, round(raw[k] * SCALE)) for k in raw}

    tot = sum(pts[k] * FREQ[k] for k in pts)
    audit = {k: pts[k] * FREQ[k] / tot * 100 for k in pts}
    return pts, raw, audit, tot


def main():
    pts, raw, audit, tot = derive()

    print("POINT ECONOMY — DERIVED FROM GAME MATH")
    print("=" * 46)
    print("DERIVED values (base_time x leverage, scale=%.2f):" % SCALE)
    for k in ("kill", "beacon10", "objective", "repair", "survive"):
        print("   %-11s = %2d pts   (base %.1fs x lev %.1f = raw %.1f)"
              % (k, pts[k], BASE[k], LEVERAGE[k], raw[k]))

    print("\nAUDIT against realistic match frequencies:")
    print("   implied total in a full match = %d" % tot)
    for k in ("kill", "beacon10", "objective", "repair", "survive"):
        s = audit[k]
        print("      %-11s x%2d = %3d pts   %5.1f%%   %s"
              % (k, FREQ[k], pts[k] * FREQ[k], s,
                 "OK" if s <= 40 else ">40% (flag to meeting)"))

    print("\nWHAT THE MODEL DECIDES FOR US:")
    print("   - 'kill-only' supplies %.1f%% -> a killer CANNOT top the board"
          % audit["kill"])
    print("     without the Core. GOOD (ROADMAP intent).")
    print("   - repair:kill = %d:%d -> a repair is worth MORE than a kill per unit"
          % (pts["repair"], pts["kill"]))
    print("     effort, because a single punch denies up to 60 beacon HP.")
    print("   - no negative sinks (all >= 1).")

    print("\nWHAT THE MODEL CANNOT DECIDE (open meeting question):")
    print("   objective supplies %.1f%% of a full-match total. Is the Core" % audit["objective"])
    print("   the MVP or a 1-dimensional scoreboard? See NEXT_MEETING_AGENDA "
          "decision 5.")


if __name__ == "__main__":
    main()
