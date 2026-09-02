#!/usr/bin/env python3
"""
System Looting — Point economy derivation model (Melody / Comms).

THE POINT: don't "feel" balance numbers — derive them from the game's own math,
then FORCE the result to be defensible. This model awards points proportional to
base effort x win-progress x RISK against the ACTUAL implemented game in
mods/game/sl_modebase (beacons + Monster Master + objective core), and audits the
result so (a) no single action dominates a win path, (b) no SAFE action out-earns
a CONTESTED one per second, and (c) no objective is a single-action stomp.

WHY THIS REVISION EXISTS (2026-09-02, melody, folding carmack `…62a3dd`):
  arena/01a062f5-systemtest partially implemented the score with PLACEHOLDER
  values (kill = K/D x 7 from MT-CTF, core_delivery = +5000, beacon_destruction
  = +1000, survive +50, victory +300). Two defects:

  1. THE CLIFF. 5000/7 = 714x — a single core delivery outranks every kill all
     season, the single-action stomp we've been killing all week, and it
     contradicts the §13.3 owner rule ("points come primarily from killing crew")
     that the scorer itself quotes. Fixed here: objective vs kill ~5x, not 714x.

  2. REPAIR OUT-EARNS A KILL 5.6x/s — carmack's catch. The 6.0 leverage was priced
     off the 60-HP CEILING ("one punch denies UP TO 60 beacon HP"), but
     clear_sabotage_at(pos) clears the WHOLE sabotage in one punch, so a competent
     crew denies ~5 HP, not 60. Ceiling/expected ~12x. AND the model priced effort
     but never DANGER, so the safest action in the game (repair at your own beacon,
     nothing trying to stop you) out-earned the most contested one (a kill).
     Fixed: repair priced off EXPECTED corrosion denied, plus a RISK term so
     contested actions out-earn safe ones.

Run:  python3 tools/point_economy_model.py

Grounded constants (verified from mods/game/sl_modebase on arena/01a062f5-systemtest):
  player HP         = 20              (content.lua "hp_max or 20")
  combat blade      = 6 dmg / 0.8s    (content.lua:63)
  energy blade      = 12 dmg / 0.6s   (content.lua:97)
  beacon HP         = 100             (state.lua:60 beacon_hp)
  beacon punch      = 5 dmg / punch   (nodes.lua:210,246) -> 20 punches (~7-13s
                                        with blade interval + repositioning)
  sabotage corrosion= 2 dmg / sec     (nodes.lua:156), duration 30s (state.lua:65)
                      -> CEILING 60 HP, but one punch clears it (nodes.lua:161)
                         so EXPECTED denial for a responsive crew is ~5-10 HP
  match duration    = 600s default    (state.lua:62)
  objective core    = crafted (+3 essence, essence.lua:148), delivered within
                      8 blocks of own beacon (nodes.lua) -> core_delivery wins
  win conditions    = elimination (default true) + objective (default false)
  no heal path      = damage_beacon only ever subtracts (nodes.lua:84) -> a single
                       player cannot loop repair + destruction on one beacon
"""


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
    # Slot it within 8 blocks of your beacon. The delivery act is quick once you
    # have the core; the BUILD is priced separately (forge), this is the slot.
    "core_delivery":      5.0,
    # 100 HP / 5 per punch = 20 punches (~7s energy, ~13s combat) + repositioning
    # and contest. The whole-team Breach win, not a per-10-HP tick.
    "beacon_destruction": 12.0,
    # ONE punch clears a sabotage charge. This is the clock only; the win-progress
    # and the risk are priced below.
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
#     happen (~5-10 HP of a 100-HP beacon = ~5-10% of the elimination win). Priced
#     off the 60-HP ceiling gave 6.0; the expected value is ~1.0 (carmack).
#   core_delivery / beacon_destruction WIN the match -> the biggest credits. They
#     terminate the match, so they are NOT farmable (that is what makes a high
#     per-second value defensible — you can only do it once per match).
# =====================================================================
WIN_PROGRESS = {
    "kill":               1.0,  # removes one enemy contributor. BASELINE.
    "forge":              1.2,  # the build — the enemy can READ it happening.
    "core_delivery":      2.5,  # THE objective win. The slot climax.
    "beacon_destruction": 1.5,  # elimination win — long, readable, contested.
    "repair":             1.0,  # FIXED: ~1.0, priced off EXPECTED corrosion, not the
                                # 60-HP ceiling (was 6.0). Prices like a kill.
    "survive":            0.4,  # low direct win-progress.
    "victory":            0.4,  # shared team label, not a personal action.
}

# =====================================================================
# STEP 3 — RISK: how DANGEROUS / contested the action is. The missing term
# carmack flagged. A contested action fights back (you could die, you could
# lose the core); a safe one does not. This is what stops the safest action
# from out-earning the most contested one per second.
#   kill = 1.0 (reference contested baseline). Safe actions are DISCOUNTED
#   below 1.0; the single most dangerous action (carrying the core through
#   contested space) gets a mild premium.
# =====================================================================
RISK = {
    "kill":               1.0,  # contested baseline.
    "core_delivery":      1.3,  # carrying the win item through contested space.
    "beacon_destruction": 1.1,  # under fire the whole time.
    "forge":              0.9,  # at your own base, but readable/defended.
    "repair":             0.4,  # at your own beacon, nothing trying to stop you.
    "survive":            1.0,
    "victory":            1.0,
}

# Kills are the unit of account (carmack): everything is priced relative to one
# kill so the model structurally cannot violate the §13.3 owner rule. A kill is
# target points = 4.
SCALE = 1.33  # kill raw = EFFORT[3.0] x WIN_PROGRESS[1.0] x RISK[1.0] -> 3.0; x1.33 = 4.

# ONCE_PER_MATCH actions: there is at most ONE of these per match (you forge one
# core, you deliver it once, you destroy one beacon — any of them ends the match).
# They are NOT farmable, so a high per-second value is defensible. The real
# invariant (carmack's repair bug) is about REPEATABLE actions: spamming a safe
# action must never out-earn the contested baseline (a kill) per second.
#   - forge: one core per match (the Signal build), readable/defended but not spammable.
#   - core_delivery / beacon_destruction: terminate the match.
ONCE_PER_MATCH = {"forge", "core_delivery", "beacon_destruction"}


def derive():
    raw = {k: EFFORT[k] * WIN_PROGRESS[k] * RISK[k] for k in EFFORT}
    pts = {k: max(1, round(raw[k] * SCALE)) for k in raw}
    return pts, raw


# A team COMMITTED to one win path (assumption, not a mechanic — carmack's P2).
# Frequencies are placeholders for the audit; they do NOT enforce the pool.
COMMITTED_PATH_TOTAL = {
    "signal": {"kill": 5, "forge": 1, "core_delivery": 1, "repair": 2, "survive": 1},
    "breach": {"kill": 4, "beacon_destruction": 1, "repair": 2, "survive": 1},
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

# The 40% dominance budget. A REPEATABLE action exceeding this share of its own
# committed path means the path is won by spamming one thing (a grind). A WIN
# action is allowed to exceed it — it IS the climax — but is flagged so it is a
# decision, not an adjective, per carmack ("the bar is prose not an assertion").
DOMINATION_BUDGET = 40.0


def audit_paths(pts):
    """Per-committed-path share, with a REAL failing assertion for the budget."""
    print("COMMITTED-PATH SHARE (a team commits to one win path):")
    failures = []
    for path, freq in COMMITTED_PATH_TOTAL.items():
        tot = sum(pts[k] * freq[k] for k in freq)
        dom = max(freq, key=lambda k: pts[k] * freq[k])
        div = max((pts[k] * freq[k]) / tot * 100 for k in freq)
        kind = "WIN (climax)" if dom in ONCE_PER_MATCH else "REPEATABLE (grind?)"
        flag = ""
        if dom not in ONCE_PER_MATCH and div > DOMINATION_BUDGET:
            flag = "  << FAIL: repeatable action exceeds %.0f%% budget" % DOMINATION_BUDGET
            failures.append((path, dom, div))
        print("   %-8s total %3d pts  |  dominant %-18s at %5.1f%%  [%s]%s"
              % (path, tot, dom, div, kind, flag))
    # Signal win actions together (forge + slot) — the real objective credit.
    sig = COMMITTED_PATH_TOTAL["signal"]
    sig_tot = sum(pts[k] * sig[k] for k in sig)
    sig_win = (pts["forge"] * sig["forge"] + pts["core_delivery"] * sig["core_delivery"])
    sig_win_pct = sig_win / max(1, sig_tot) * 100
    print("   signal win actions (forge + slot) together = %2.1f%% of the signal path"
          % sig_win_pct)
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
        print("   >> PLACEHOLDER %6.1fx EXCEEDS the 50x budget. A single objective\n"
              "      outranks every kill in the season bank — the exact single-action\n"
              "      stomp this model exists to prevent, and it contradicts the §13.3\n"
              "      owner rule the scorer itself quotes." % p_ratio)
    # Also flag the derived one if it drifts (it should not).
    if d_ratio > 20:
        print("   >> derived %5.1fx also over the 20x budget — repricing needed." % d_ratio)
    else:
        print("   >> derived %5.1fx is within the 20x budget (the jackpot, not a nuke)." % d_ratio)
    return d_ratio, p_ratio


def audit_adversarial(pts):
    """The zero-sum beacon. One beacon is a single 100-HP pool. The destroying
    team pushes it toward 0; the defending team CLEARS sabotages that would
    corrode it. Both teams draw from the SAME pool — the model must not reward
    both as if they were independent (carmack's P2 point). Because there is NO
    heal path (damage_beacon only subtracts), repair and destruction cannot be
    looped by one player."""
    print("\nADVERSARIAL BEACON (one beacon = one 100-HP pool, zero-sum):")
    beacon_hp = 100
    punch = 5
    corrosion_per_s = 2
    sabotage_s = 30
    ceiling = corrosion_per_s * sabotage_s
    expected_denied = 8  # responsive crew clears it in ~4s before meaningful corrosion
    punches_to_kill = beacon_hp / punch
    print("   destroying beacon:  %d HP / %d per punch = %.0f punches = 1 beacon_destruction"
          % (beacon_hp, punch, punches_to_kill))
    print("   sabotage corrosion:  %d HP/s for up to %ds  -> CEILING %d HP"
          % (corrosion_per_s, sabotage_s, ceiling))
    print("   ...but one punch clears it -> EXPECTED denied for a responsive crew ~%d HP"
          % expected_denied)
    print("   -> repair priced off the EXPECTED %.0f HP (≈%.0f%% of the beacon),"
          % (expected_denied, expected_denied / beacon_hp * 100))
    print("      NOT the %.0f-HP ceiling (that inflated leverage to 6.0; expected ~1.0)." % ceiling)
    print("   no heal path (damage_beacon only subtracts): a single player cannot\n"
          "   loop repair + destruction on one beacon. Good — caps the exploit.")


def main():
    pts, raw = derive()

    print("POINT ECONOMY — DERIVED FROM GAME MATH (beacons + MM + core)")
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
    print("VERDICT (DRIVEN BY THE DERIVED MODEL — the live gate):")
    ok = True
    if pps_violations:
        ok = False
        print("   FAIL  repeatable action out-earns a kill per second: %s"
              % ", ".join(pps_violations))
    else:
        print("   PASS  no repeatable action beats a kill per second (repair bug fixed).")
    if path_failures:
        ok = False
        print("   FAIL  repeatable action exceeds %.0f%% of its path: %s"
              % (DOMINATION_BUDGET, ", ".join("%s@%.1f%%" % (p, d) for p, d in path_failures)))
    else:
        print("   PASS  no repeatable action exceeds the %.0f%% budget."
              % DOMINATION_BUDGET)
    print("   %s" % ("ALL DERIVED CHECKS PASS — the table is defensible."
                     if ok else "DERIVED CHECKS FAIL — reprice before shipping."))
    print("""
PLACEHOLDER BASELINE (documented evidence, NOT a live gate — this branch is already
re-priced). The old scoring.lua constants were kill=K/D×7, core=+5000, beacon=+1000,
survive=+50, victory=+300. That produced a %.0fx objective-vs-kill cliff, which is the
single-action stomp this model was written to prevent and which contradicts the §13.3
owner rule the scorer itself quoted. Shown here so the defect is reproducible, not so
it gates the derived table.""" % p_ratio)

    print("""
WHAT THE MODEL DECIDES (now that it can be abused, it is harder to abuse):
  - kill is a small, FLAT value (K/D compounding is an oracle — the more you have
    killed, the more your next kill is worth). A flat per-kill value cannot top
    the board alone; you need a win path.
  - core_delivery is the jackpot at ~%dx a kill, NOT %dx (was 714x). It is the
    Objective win and the biggest single credit — but not bigger than the season.
  - repair is priced off EXPECTED corrosion (~8 HP) not the 60-HP ceiling, and is
    DISCOUNTED for risk (safe action). It no longer out-earns a kill per second.
  - every action carries a RISK term, so contested actions out-earn safe ones.
    Effort alone was optimising toward "the cheapest, easiest action wins".
  - win actions (core_delivery, beacon_destruction) MAY have a high per-second
    value: they terminate the match and cannot be farmed.

WHAT IT CANNOT DECIDE (the meeting's word):
  - The exact SCALE (is +22 core or +4 kill too low/high?) needs the soak harness
    to emit per-action point deltas. This model fixes the RATIOS + the RISK shape;
    the soak fixes the base.
  - Whether the shared pool is a real MECHANIC. Right now the three-paths-share-one-
    pool claim exists only as FREQ assumptions — a coordinated team is NOT stopped
    from doing all three. That needs a budget / contention cost / per-team cap in
    the GAME, not the model (carmack P2). Until then the model should not claim it.
  - Whether to put points on the strand ledger (glitch: points as strand events)
    — worth the three free constraints; the owner rules say essence != score.
""" % (d_ratio, p_ratio))
    return 0 if ok else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
