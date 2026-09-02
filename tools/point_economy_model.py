#!/usr/bin/env python3
"""
System Looting — Point economy derivation model (Melody / Comms).

THE POINT: don't "feel" balance numbers — derive them from the game's own math.
This model awards points proportional to the WIN-PROGRESS an action creates or
denies (its "leverage" x its base time) against the ACTUAL implemented game in
mods/game/sl_modebase (beacons + Monster Master + objective core), then audits
the result so no single action dominates the pool.

WHY THIS REVISION EXISTS (2026-09-02, melody):
  arena/01a062f5-systemtest partially implemented the score with PLACEHOLDER
  values (kill = K/D x 7 from MT-CTF, core_delivery = +5000, beacon_destruction
  = +1000, survive = +50, victory = +300). The engineering is sound (get_or_zero,
  idempotent award_match_end_points, earned_points season bank, tests) but the
  NUMBERS are not derived from game math and they recreate the bug the three-path
  model was built to kill: a +5000 objective vs a ~7 kill is a 714x cliff that
  makes the whole season bank one objective. It also contradicts the §13.3 owner
  rule ("points come primarily from killing crew") that the score itself quotes.

  The fix: derive every category from the real constants below, replace the cliff
  with ~5x (objective jackpot, not 700x), and keep the objective / beacon win
  paths comparable so Signal and Breach are both real choices.

Run:  python3 tools/point_economy_model.py

Grounded constants (verified from mods/game/sl_modebase on arena/01a062f5-systemtest):
  player HP         = 20              (spawn.lua, content.lua "hp_max or 20")
  combat blade      = 6 dmg / 0.8s    (content.lua:63 -> 7.5 dps)
  energy blade      = 12 dmg / 0.6s   (content.lua:97 -> 20.0 dps)
  beacon HP         = 100             (state.lua:71 beacon_hp)
  beacon punch      = 5 dmg / punch   (nodes.lua:210,246) -> 20 punches (~10-13s
                      with energy/combat blade interval + repositioning)
  sabotage corrosion= 2 dmg / sec     (nodes.lua:156), duration 30s (state.lua:76)
                      -> up to 60 HP if uncleared; ONE repair punch denies it
  match duration    = 600s default    (state.lua:73; 0 disables)
  objective core    = crafted, +3 essence (essence.lua:148), delivered within
                      8 blocks of own beacon (nodes.lua) -> core_delivery wins
  win conditions    = elimination (default true) + objective (default false)
"""


# ---------------------------------------------------------------
# STEP 1 — base TIME each action takes (seconds), derived from the real
# damage / HP / interval numbers above. This is the raw "effort cost."
# ---------------------------------------------------------------
BASE = {
    # 20 HP; energy-blade dps 20 -> ~1s, combat-blade 7.5 -> ~2.7s.
    # Add approach/aim overhead (kills aren't pure DPS uptime).
    "kill":             3.0,
    # The objective-core win: forge it, carry it, slot it within 8 blocks of
    # your beacon. The delivery act itself is quick once you have the core; the
    # FORGE (the readable build) is priced separately below.
    "core_delivery":    5.0,
    # 100 HP / 5 per punch = 20 punches (~7.2s with energy blade, ~12.8s combat)
    # plus repositioning. This is the whole-team Breach win, not a per-10-HP tick.
    "beacon_destruction": 12.0,
    # Build the Objective Core. Long, readable, the enemy can read it happening.
    "forge":            10.0,
    # ONE repair punch (~0.8s) clears a sabotage charge that would otherwise
    # corrode up to 60 beacon HP (2/s x 30s). Tiny raw effort, huge denial.
    "repair":           0.8,
    # Lived through the match; "showing up," not win-progress.
    "survive":          1.0,
    # Won the match (team level). Display only in the impl; not season-banked.
    "victory":          1.0,
}

# ---------------------------------------------------------------
# STEP 2 — LEVERAGE: how much WIN-PROGRESS an action creates OR denies,
# relative to raw effort. Baseline (kill) = 1.0; everything compared to it.
# ---------------------------------------------------------------
LEVERAGE = {
    "kill":              1.0,  # removes one enemy contributor. BASELINE.
    "core_delivery":     3.0,  # THE objective win. Quick SLOT = climax; highest
                               # per-effort win-progress of the whole game.
    "beacon_destruction": 2.0,  # elimination win. Long but readable/contested, so
                               # per-effort it is lower than the slot climax.
    "forge":             1.5,  # the build — the enemy can READ it happening.
    "repair":            6.0,  # ONE punch denies up to 60 beacon HP = 6x a 10-HP unit.
    "survive":           0.5,  # low direct win-progress.
    "victory":           0.5,  # a shared team label, not a personal action.
}

# Scale so the minimum action lands at >=1 point and the ratios stay clean.
SCALE = 1.3

# The impl splits the win into two objective kinds. Keep them comparable so a
# match can be won EITHER by Signal (forge + deliver) OR Breach (destroy beacon),
# and neither is a single-action stomp. We express this as a ratio check below.
#
# Realistic per-action totals for a team that COMMITS to one win path.
COMMITTED_PATH_TOTAL = {
    # Signal: kill often to keep the forge risky, forge the core, slot it.
    "signal": {"kill": 6, "forge": 1, "core_delivery": 1, "repair": 2, "survive": 1},
    # Breach: pressure the beacon to destruction.
    "breach": {"kill": 4, "beacon_destruction": 1, "repair": 2, "survive": 1},
}

# The placeholder constants from arena/01a062f5-systemtest scoring.lua. Kept
# here so the audit is reproducible: we can show exactly how far off they are.
PLACEHOLDER = {
    "kill_base":  7,   # MT-CTF: max(1, floor(K/D*7+0.5)); a neutral 1.0 K/D -> 7
    "core_delivery": 5000,
    "beacon_destruction": 1000,
    "survive":  50,
    "victory": 300,
}


def derive():
    raw = {k: BASE[k] * LEVERAGE[k] for k in BASE}
    pts = {k: max(1, round(raw[k] * SCALE)) for k in raw}
    return pts, raw


# Actions that END the match (the win) vs repeatable grind. A win action
# dominating its path is the CLIMAX we want; a repeatable action dominating
# would mean the path is won by spamming one thing (a grind).
WIN_ACTIONS = {"core_delivery", "beacon_destruction"}


def audit_paths(pts):
    """Per-committed-path share. Distinguishes a win-action (climax, good) from
    a repeatable-action (grind, bad) dominance."""
    print("COMMITTED-PATH SHARE (a team that commits to one win path):")
    for path, freq in COMMITTED_PATH_TOTAL.items():
        tot = sum(pts[k] * freq[k] for k in freq)
        dom = max(freq, key=lambda k: pts[k] * freq[k])
        div = max((pts[k] * freq[k]) / tot * 100 for k in freq)
        kind = "WIN (climax)" if dom in WIN_ACTIONS else "REPEATABLE (grind?)"
        print("   %-8s total %3d pts  |  dominant %-18s at %5.1f%%  [%s]"
              % (path, tot, dom, div, kind))
        if dom not in WIN_ACTIONS and div > 40:
            print("      >> repeatable action >40% of its path — the path can be won")
            print("         by spamming one thing; consider raising the win share.")
    # Combined win-action share for Signal (forge + slot are both the win).
    signal_total = sum(pts[k] * COMMITTED_PATH_TOTAL["signal"][k]
                       for k in COMMITTED_PATH_TOTAL["signal"])
    signal_win = (pts["forge"] * COMMITTED_PATH_TOTAL["signal"]["forge"]
                  + pts["core_delivery"]
                  * COMMITTED_PATH_TOTAL["signal"]["core_delivery"])
    print("   signal win actions (forge + slot) together = "
          "%2.1f%% of the signal path" % (signal_win / max(1, signal_total) * 100))
    return


def audit_placeholder_cliff(pts):
    """Compute the objective-vs-kill multiplier under BOTH the derived model and
    the target's placeholder constants, and flag the domination."""
    print("\nOBJECTIVE-vs-KILL RATIO (is one objective a single-action stomp?):")
    derived_core = pts["core_delivery"]
    derived_kill = pts["kill"]
    print("   derived   core_delivery %3d / kill %3d  =  %.1fx"
          % (derived_core, derived_kill, derived_core / max(1, derived_kill)))
    ph_core = PLACEHOLDER["core_delivery"]
    ph_kill = PLACEHOLDER["kill_base"]
    print("   placeholder core_delivery %5d / kill %3d  =  %.1fx"
          % (ph_core, ph_kill, ph_core / max(1, ph_kill)))
    ratio = ph_core / max(1, ph_kill)
    if ratio > 50:
        print("   >> %5.1fx EXCEEDS the 50x domination budget. A single objective"
              % ratio)
        print("      outranks every kill in the season bank. This is the same")
        print("      single-action stomp the three-path model was built to kill, and")
        print("      contradicts the §13.3 owner rule the scorer itself quotes.")
    else:
        print("   >> within budget (<=50x).")


def main():
    pts, raw = derive()

    print("POINT ECONOMY — DERIVED FROM GAME MATH (real impl: beacons + MM + core)")
    print("=" * 60)
    print("DERIVED values (base_time x leverage, scale=%.2f):" % SCALE)
    for k in sorted(pts):
        print("   %-20s = %3d pts   (base %5.1fs x lev %.1f = raw %5.1f)"
              % (k, pts[k], BASE[k], LEVERAGE[k], raw[k]))

    print("\n")
    audit_paths(pts)
    audit_placeholder_cliff(pts)

    print("""
WHAT THE MODEL DECIDES:
  - kill is a small, repeatable value (not K/D-compounding) so it CANNOT top the
    board alone; you need a win path. A flat per-kill value is also cleaner than
    K/D x 7, which makes a player's FUTURE kill worth more the more they have
    already killed (a compounding / oracle feedback loop).
  - core_delivery is the jackpot at ~5x a kill, NOT 700x. It is the Objective win
    and it should be the biggest single credit — but not so big that it outranks
    every kill in the season bank.
  - repair > kill per unit effort (one punch denies up to 60 beacon HP), so the
    Deny/defense counterplay earns its points.
  - The objective and the beacon-destruction win paths stay comparable, so a
    match is won by Signal (forge + slot) OR Breach (destroy the beacon) and
    neither is a single-action stomp.

WHAT IT CANNOT DECIDE (the meeting's word):
  - The exact SCALE (is +20 core too high/low?) needs the soak harness to emit
    per-action point deltas. This model fixes the RATIOS; the soak fixes the base.
  - Whether to put points on the strand ledger (glitch: points as strand events)
    — worth the three free constraints (no edit, no mid-run oracle, no-negative-
    sink validation); the owner rules say essence != score.
""")
    return


if __name__ == "__main__":
    main()
