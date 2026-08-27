#!/usr/bin/env bash
# M1 exit-check sweep (see AGENT_PARALLEL_PLAN.md milestone M1):
# 40 matches across four regimes. Exit criteria evaluated by
# tests/soak/m1_summary.py over the emitted reports:
#   * 0 bug events, 0 engine errors in every run
#   * both elimination wins AND timer draws occur
#   * every event counter > 0 across the sweep
set -u
cd "$(dirname "$0")/../.."
OUT=${1:-/tmp/m1_sweep}
mkdir -p "$OUT"

run() { # label, extra args...
  local label=$1; shift
  echo "[sweep] === $label ==="
  python3 tests/soak/run_soak.py "$@" --timeout 1800 \
    --report "$OUT/$label.json" > "$OUT/$label.log" 2>&1
  echo "[sweep] $label exit=$? -> $OUT/$label.log"
}

# A: elimination-focused (low lives, long clock)
run a_elim  --matches 10 --lives 3 --match-duration 240 --seed 101
# B: timer-forced (high lives, short clock -> draws)
run b_timer --matches 10 --lives 8 --match-duration 40  --seed 202
# C: mixed standard regime
run c_mixed --matches 10 --lives 4 --match-duration 150 --seed 303
# D: wide roster (6 bots, 3v3)
run d_wide  --matches 10 --bots 6 --lives 3 --match-duration 120 --seed 404

python3 tests/soak/m1_summary.py "$OUT"
echo "SWEEP_DONE rc=$?"
