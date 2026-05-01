#!/usr/bin/env bash
#
# critique-loop-acceptance.sh — Bundle 0c termination tests
#
# Purpose: prove the bounded-loop semantics in skills/double-critique/SKILL.md
# (max_rounds=4) and skills/coherent-plan/SKILL.md (max_rounds=2) terminate
# correctly under each of the documented exit reasons:
#   - clean:        cm_count == 0 on round 1 (or any round) → exit BEFORE corrector_N
#   - oscillation:  round >= 2 AND cm_count >= cm_count_prev → exit BEFORE corrector_N
#   - max_rounds:   round == max_rounds → exit AFTER corrector_N
#
# This script does NOT spawn LLM subagents. It implements the documented loop
# semantics in pure shell (one Bash function per exit reason) and feeds a
# pre-fabricated cm_count series for each scenario. The asymmetry (clean and
# oscillation skip the round's corrector; max_rounds runs it) is encoded in
# the order of the exit checks, mirroring SKILL.md verbatim.
#
# Each test is a self-contained Bash function. The script exits 0 only when
# every test PASSes. Any FAIL causes the script to exit non-zero with a
# loud diagnostic.
#
# Plan AC-17 sub-checks: [CLEAN] [CONVERGE] [OSCILLATION] [MAX_ROUNDS]
# [COHERENT_PLAN_CAP]
#
# The loop driver `run_loop` is the single source of semantics; each test
# constructs a `cm_count` series that drives the driver into the named exit
# path, then asserts (a) the recorded `exit_reason`, (b) `rounds_run`, and
# (c) the `corrector_ran_at_round` array — the latter is the AC-4 / AC-5c
# witness that the asymmetric corrector-call rule is implemented correctly.

set -u  # treat unset variables as errors; do NOT set -e because we use
        # function-level exit-status comparisons in the assertion helpers

PASS_COUNT=0
FAIL_COUNT=0
RESULT_LINES=()

# ---------------------------------------------------------------------------
# Loop driver — implements the SKILL.md loop semantics in pure shell.
#
# Inputs (env vars):
#   MAX_ROUNDS:   integer (4 for double-critique, 2 for coherent-plan)
#   CM_SERIES:    space-separated cm_count values per round, in order. Length
#                 may be < MAX_ROUNDS (the driver only consumes what's needed).
#                 Example: "5 3 0" means round 1 has cm_count=5, round 2 has
#                 cm_count=3, round 3 has cm_count=0.
#
# Outputs (env vars set on the caller's shell — caller uses `eval`):
#   EXIT_REASON:           one of "clean" | "oscillation" | "max_rounds"
#   ROUNDS_RUN:            integer
#   CORRECTOR_RAN:         space-separated round numbers where corrector_N ran
#   FINAL_CM_COUNT:        cm_count of the last round actually run
# ---------------------------------------------------------------------------
run_loop() {
  local max_rounds="$1"
  local cm_series="$2"
  # shellcheck disable=SC2206
  local cm_arr=($cm_series)
  local round=0
  local cm_prev=""
  local exit_reason=""
  local corrector_ran=()
  local final_cm=""

  while [ "$round" -lt "$max_rounds" ]; do
    round=$((round + 1))
    local cm_idx=$((round - 1))
    if [ "$cm_idx" -ge "${#cm_arr[@]}" ]; then
      echo "FATAL: CM_SERIES exhausted at round $round (need at least $round entries, got ${#cm_arr[@]})" >&2
      return 2
    fi
    local cm_now="${cm_arr[$cm_idx]}"
    final_cm="$cm_now"

    # Exit check 1 — clean: cm_count == 0. Loop exits BEFORE corrector_N.
    if [ "$cm_now" -eq 0 ]; then
      exit_reason="clean"
      break
    fi
    # Exit check 2 — oscillation: round >= 2 AND cm_now >= cm_prev. Strict-decrease
    # violation per Bundle 0b plan Q1. Loop exits BEFORE corrector_N.
    if [ "$round" -ge 2 ] && [ -n "$cm_prev" ] && [ "$cm_now" -ge "$cm_prev" ]; then
      exit_reason="oscillation"
      break
    fi
    # Exit check 3 — max_rounds: cap reached. Corrector_N STILL runs (asymmetry).
    if [ "$round" -eq "$max_rounds" ]; then
      corrector_ran+=("$round")
      exit_reason="max_rounds"
      break
    fi
    # Otherwise: run corrector_N for this round, advance prev, continue.
    corrector_ran+=("$round")
    cm_prev="$cm_now"
  done

  # Emit results as eval-able assignments. Quote the array join to survive
  # the caller's eval.
  echo "EXIT_REASON='${exit_reason}'"
  echo "ROUNDS_RUN='${round}'"
  echo "CORRECTOR_RAN='${corrector_ran[*]}'"
  echo "FINAL_CM_COUNT='${final_cm}'"
}

# ---------------------------------------------------------------------------
# Assertion helper. Records pass/fail and continues; the script exits non-zero
# at the end if any assertion failed.
# ---------------------------------------------------------------------------
assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    RESULT_LINES+=("PASS  $label  (expected=$expected, actual=$actual)")
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    RESULT_LINES+=("FAIL  $label  (expected=$expected, actual=$actual)")
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ===========================================================================
# Test [CLEAN] — round 1 finds 0 CM. Exit BEFORE corrector_1.
# Witness: exit_reason=clean, rounds_run=1, CORRECTOR_RAN is empty.
# ===========================================================================
test_clean() {
  echo ""
  echo "=== [CLEAN] round 1 finds 0 CM, exit before corrector_1 ==="
  local out
  out="$(run_loop 4 "0")"
  eval "$out"
  assert_eq "[CLEAN] exit_reason"   "clean" "$EXIT_REASON"
  assert_eq "[CLEAN] rounds_run"    "1"     "$ROUNDS_RUN"
  assert_eq "[CLEAN] corrector_ran" ""      "$CORRECTOR_RAN"
  assert_eq "[CLEAN] final_cm"      "0"     "$FINAL_CM_COUNT"
}

# ===========================================================================
# Test [CONVERGE] — rounds 1/2/3 produce decreasing cm counts ending at 0.
# Witness: exit_reason=clean, rounds_run=3, CORRECTOR_RAN is "1 2"
# (corrector_3 is skipped because round 3 was clean).
# ===========================================================================
test_converge() {
  echo ""
  echo "=== [CONVERGE] cm_count [5, 3, 0] → clean at round 3, no corrector_3 ==="
  local out
  out="$(run_loop 4 "5 3 0")"
  eval "$out"
  assert_eq "[CONVERGE] exit_reason"   "clean" "$EXIT_REASON"
  assert_eq "[CONVERGE] rounds_run"    "3"     "$ROUNDS_RUN"
  assert_eq "[CONVERGE] corrector_ran" "1 2"   "$CORRECTOR_RAN"
  assert_eq "[CONVERGE] final_cm"      "0"     "$FINAL_CM_COUNT"
}

# ===========================================================================
# Test [OSCILLATION] — round 2's cm_count >= round 1's. Strict-decrease
# violation. Loop exits BEFORE corrector_2.
# Witness: exit_reason=oscillation, rounds_run=2, CORRECTOR_RAN is "1"
# (corrector_1 ran after round 1; corrector_2 is skipped on the oscillation exit).
# Two flavors verified: equal counts (perfect stall) and increased counts.
# ===========================================================================
test_oscillation_equal() {
  echo ""
  echo "=== [OSCILLATION] cm_count [4, 4] → oscillation at round 2 (equal) ==="
  local out
  out="$(run_loop 4 "4 4")"
  eval "$out"
  assert_eq "[OSCILLATION-EQ] exit_reason"   "oscillation" "$EXIT_REASON"
  assert_eq "[OSCILLATION-EQ] rounds_run"    "2"           "$ROUNDS_RUN"
  assert_eq "[OSCILLATION-EQ] corrector_ran" "1"           "$CORRECTOR_RAN"
  assert_eq "[OSCILLATION-EQ] final_cm"      "4"           "$FINAL_CM_COUNT"
}

test_oscillation_increase() {
  echo ""
  echo "=== [OSCILLATION] cm_count [3, 5] → oscillation at round 2 (increase) ==="
  local out
  out="$(run_loop 4 "3 5")"
  eval "$out"
  assert_eq "[OSCILLATION-UP] exit_reason"   "oscillation" "$EXIT_REASON"
  assert_eq "[OSCILLATION-UP] rounds_run"    "2"           "$ROUNDS_RUN"
  assert_eq "[OSCILLATION-UP] corrector_ran" "1"           "$CORRECTOR_RAN"
  assert_eq "[OSCILLATION-UP] final_cm"      "5"           "$FINAL_CM_COUNT"
}

# ===========================================================================
# Test [MAX_ROUNDS] — cm_count strictly decreases every round but never reaches
# 0 within the cap. Loop hits max_rounds=4. Corrector_4 STILL runs (asymmetry).
# Witness: exit_reason=max_rounds, rounds_run=4, CORRECTOR_RAN is "1 2 3 4".
# ===========================================================================
test_max_rounds() {
  echo ""
  echo "=== [MAX_ROUNDS] cm_count [10, 7, 4, 1] → cap at round 4, corrector_4 runs ==="
  local out
  out="$(run_loop 4 "10 7 4 1")"
  eval "$out"
  assert_eq "[MAX_ROUNDS] exit_reason"   "max_rounds" "$EXIT_REASON"
  assert_eq "[MAX_ROUNDS] rounds_run"    "4"          "$ROUNDS_RUN"
  assert_eq "[MAX_ROUNDS] corrector_ran" "1 2 3 4"    "$CORRECTOR_RAN"
  assert_eq "[MAX_ROUNDS] final_cm"      "1"          "$FINAL_CM_COUNT"
}

# ===========================================================================
# Test [COHERENT_PLAN_CAP] — coherent-plan with max_rounds=2. Input that
# would have wanted 3 rounds — must exit at 2 with exit_reason=max_rounds.
# Corrector_2 runs (asymmetry: max_rounds runs the round's corrector).
# Witness: exit_reason=max_rounds, rounds_run=2, CORRECTOR_RAN is "1 2".
# ===========================================================================
test_coherent_plan_cap() {
  echo ""
  echo "=== [COHERENT_PLAN_CAP] max_rounds=2, cm_count [5, 2] → cap at round 2 ==="
  local out
  out="$(run_loop 2 "5 2")"
  eval "$out"
  assert_eq "[COHERENT_PLAN_CAP] exit_reason"   "max_rounds" "$EXIT_REASON"
  assert_eq "[COHERENT_PLAN_CAP] rounds_run"    "2"          "$ROUNDS_RUN"
  assert_eq "[COHERENT_PLAN_CAP] corrector_ran" "1 2"        "$CORRECTOR_RAN"
  assert_eq "[COHERENT_PLAN_CAP] final_cm"      "2"          "$FINAL_CM_COUNT"
}

# Bonus — verify coherent-plan clean exit at round 1 also works under cap=2
test_coherent_plan_clean() {
  echo ""
  echo "=== [COHERENT_PLAN_CLEAN] max_rounds=2, cm_count [0] → clean at round 1 ==="
  local out
  out="$(run_loop 2 "0")"
  eval "$out"
  assert_eq "[COHERENT_PLAN_CLEAN] exit_reason"   "clean" "$EXIT_REASON"
  assert_eq "[COHERENT_PLAN_CLEAN] rounds_run"    "1"     "$ROUNDS_RUN"
  assert_eq "[COHERENT_PLAN_CLEAN] corrector_ran" ""      "$CORRECTOR_RAN"
}

# ===========================================================================
# Run all tests
# ===========================================================================
echo "===================================================================="
echo "Bundle 0c — bounded critique loop termination tests"
echo "===================================================================="

test_clean
test_converge
test_oscillation_equal
test_oscillation_increase
test_max_rounds
test_coherent_plan_cap
test_coherent_plan_clean

echo ""
echo "===================================================================="
echo "Results"
echo "===================================================================="
for line in "${RESULT_LINES[@]}"; do
  echo "  $line"
done
echo ""
echo "  PASS: $PASS_COUNT"
echo "  FAIL: $FAIL_COUNT"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "FAIL — at least one assertion did not match"
  exit 1
fi
echo "OK — all termination tests passed"
exit 0
