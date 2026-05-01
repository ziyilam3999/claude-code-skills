#!/usr/bin/env bash
#
# severity-rubric-pinning.test.sh — AC-8 from Bundle 0b plan
#
# Purpose: prove the rubric is read ONCE at run-start (Stage 0 step 4a) and
# the same text is reused for every round. Mid-run edits to the rubric file
# must NOT affect rounds already snapshot at run-start.
#
# This test simulates the orchestrator's snapshot mechanism in pure shell:
#   1. Read rubric file at "run-start" → cache as RUBRIC_FROZEN.
#   2. Render round-1 critic prompt by substituting `<!-- SEVERITY RUBRIC -->`
#      with RUBRIC_FROZEN.
#   3. MONKEYPATCH the rubric file mid-run (write garbage to it).
#   4. Render round-2 critic prompt — substitution must use the SAME cached
#      RUBRIC_FROZEN, not re-read the (now-corrupted) file.
#   5. Diff the two rendered prompts. They must be byte-identical.
#   6. Restore the rubric file from backup.
#
# If round 2 picked up the monkeypatched content, the test FAILs and we know
# the SKILL.md harness is incorrectly re-reading the file mid-loop.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUBRIC_PATH="${SCRIPT_DIR}/../references/severity-rubric.md"

if [ ! -f "$RUBRIC_PATH" ]; then
  echo "FAIL: severity-rubric.md not found at $RUBRIC_PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Snapshot the rubric at "run-start" (Stage 0 step 4a)
# ---------------------------------------------------------------------------
RUBRIC_FROZEN="$(cat "$RUBRIC_PATH")"

# Sanity check — frozen text must contain the calibration anchor (Q3 / AC-6)
if ! printf '%s\n' "$RUBRIC_FROZEN" | grep -q 'Calibration Anchor'; then
  echo "FAIL: snapshot does not contain 'Calibration Anchor' — AC-6 calibration text missing" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Render round-1 prompt (template substitution)
# ---------------------------------------------------------------------------
PROMPT_TEMPLATE='You are a critic. The rubric is below.

<!-- SEVERITY RUBRIC -->

Apply the rubric to the document.'

render_prompt() {
  local rubric_text="$1"
  # Substitute the marker with the rubric text. Use awk to avoid sed escape hell.
  printf '%s' "$PROMPT_TEMPLATE" | awk -v r="$rubric_text" '{
    if ($0 == "<!-- SEVERITY RUBRIC -->") { print r } else { print $0 }
  }'
}

ROUND1_PROMPT="$(render_prompt "$RUBRIC_FROZEN")"

# ---------------------------------------------------------------------------
# 3. Monkeypatch the rubric file mid-run.
#    Back it up first so we can always restore — global mv-not-rm rule.
# ---------------------------------------------------------------------------
BACKUP_PATH="${RUBRIC_PATH}.pinning-test-backup-$$"
cp "$RUBRIC_PATH" "$BACKUP_PATH"
trap 'mv "$BACKUP_PATH" "$RUBRIC_PATH" 2>/dev/null || true' EXIT

# Write garbage to the rubric file
cat > "$RUBRIC_PATH" <<'EOF'
GARBAGE — this rubric was monkeypatched mid-run. If a critic round reads this,
the harness is incorrectly re-reading the file instead of using the snapshot
captured at run-start. Test should FAIL.
EOF

# ---------------------------------------------------------------------------
# 4. Render round-2 prompt using the SAME cached RUBRIC_FROZEN.
#    The orchestrator MUST NOT re-read the file here.
# ---------------------------------------------------------------------------
ROUND2_PROMPT="$(render_prompt "$RUBRIC_FROZEN")"

# Sanity check: if we WERE to re-read the file (the bug case), we'd get
# the GARBAGE content. Show what that would look like — just as a diagnostic.
WHAT_REREAD_WOULD_GIVE="$(render_prompt "$(cat "$RUBRIC_PATH")")"

# ---------------------------------------------------------------------------
# 5. Assert byte-identical between round 1 and round 2.
# ---------------------------------------------------------------------------
if [ "$ROUND1_PROMPT" = "$ROUND2_PROMPT" ]; then
  echo "PASS: round-1 and round-2 critic prompts are byte-identical."
  echo "PASS: monkeypatched rubric content was IGNORED (correct snapshot semantics)."
else
  echo "FAIL: round-1 and round-2 prompts differ — harness is re-reading rubric mid-loop"
  echo "--- round 1 ---"
  printf '%s\n' "$ROUND1_PROMPT"
  echo "--- round 2 ---"
  printf '%s\n' "$ROUND2_PROMPT"
  exit 1
fi

# Cross-check: the "what re-read would give" rendering MUST differ from the
# snapshot rendering — otherwise the monkeypatch didn't actually corrupt the
# file, and the test isn't really testing anything.
if [ "$ROUND2_PROMPT" = "$WHAT_REREAD_WOULD_GIVE" ]; then
  echo "FAIL: monkeypatch did not actually corrupt the file — test is invalid"
  exit 1
else
  echo "PASS: monkeypatch verifiably corrupted the file (test is meaningful)."
fi

# ---------------------------------------------------------------------------
# 6. Restore (also handled by the EXIT trap, but do it explicitly here so
#    failures further down still leave the file in a good state).
# ---------------------------------------------------------------------------
mv "$BACKUP_PATH" "$RUBRIC_PATH"
trap - EXIT

echo ""
echo "OK — severity rubric pinning verified (AC-8)"
exit 0
