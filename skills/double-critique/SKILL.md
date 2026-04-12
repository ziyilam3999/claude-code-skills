---
name: double-critique
description: >
  Deep multi-agent critique pipeline that finds logical gaps, unsupported claims, missing edge
  cases, and internal contradictions in any document — then fixes them. Two independent critics
  review the document cold (seeing nothing about how it was made) to catch problems the author
  is blind to. Use when the user wants to review, critique, stress-test, or improve a PRD,
  SPEC, design doc, plan, RFC, or any important document before it ships. Also use when the
  user says "critique this", "review this document", "find problems in", "stress test",
  "is this document solid", "what did I miss", "double critique", "run critique pipeline",
  "/double-critique path/to/file". Do NOT use for simple proofreading, grammar fixes, or formatting
  — this is a deep structural and logical review.
---

# Double-Critique Pipeline

Run a looping critique pipeline on the document at `$ARGUMENTS`: one-shot Researcher and Drafter, then a bounded Critic-N / Corrector-N loop, then a 3-stage feedback loop that extracts learnings, tracks effectiveness, and updates the knowledge base.

## Loop Configuration

max_rounds: 4

The loop runs at most `max_rounds = 4` critic/corrector pairs. Exit conditions are checked in this exact order each round: (1) `clean` — `blocker_count == 0`; (2) `oscillation` — `round >= 2 AND blocker_count >= previous round's blocker_count`; (3) `max_rounds` — `round == max_rounds`. Oscillation is checked before `max_rounds` so that a run which both oscillates and hits the cap reports the more informative reason.

**FORCING FUNCTION:** If `max_rounds` is not declared in this SKILL.md, the orchestrator MUST **halt** before Stage 1 and print a loud error mentioning `max_rounds`. This is the F58-driven gate that prevents silent fallback to the pre-loop 2-round shape. Do not run any agent if this line is missing. (refuse run without max_rounds)

## Why This Pipeline Works

The core insight: authors can't see their own blind spots. When you write a document, your brain fills in gaps automatically. Two independent critics who see ONLY the finished document — with zero context about how it was made — catch things you never would. Isolation is the key: an informed reviewer unconsciously confirms decisions; an uninformed one challenges them.

Each stage is an independent Agent subagent. No shared context between stages — only file artifacts passed forward. Each agent receives at most 2 inputs: the original document + one prior artifact. Critics are fully isolated: they see ONLY the document, nothing else.

## How to Use

```
/double-critique path/to/document.md
```

Works on any document type: PRD, SPEC, design doc, plan, RFC, architecture decision record. The pipeline creates a `tmp/` directory and writes each stage's output to `tmp/dc-{N}-{role}.md` for auditability.

If `$ARGUMENTS` is empty or the file doesn't exist, stop and ask the user for the file path.

## Pipeline Overview

| Stage | Role | Inputs | Output | Why It Exists |
|-------|------|--------|--------|---------------|
| 1 | Researcher | Document + KB | `tmp/dc-1-researcher.md` | Check claims against reality + build document inventory |
| 2 | Drafter | Document + Research | `tmp/dc-2-drafter.md` | Apply fixes with an editor's red pen |
| 3..N | Critic-N / Corrector-N loop | Latest corrected doc (isolated critic) + rubric | `tmp/dc-{2N+1}-critic-round{N}.md`, `tmp/dc-{2N+2}-corrector-round{N}.md` | Loop until `blocker_count == 0`, oscillation, or `max_rounds` |
| 7 | Orchestrator | `tmp/dc-loop-state.json` + all critic files | Appended to `$ARGUMENTS` | Compile the Critique Log (not an agent call) |
| 8 | Extractor | Round-1 + round-N artifacts + per-round count table | `tmp/dc-8-extractor.md` | Figure out which rounds actually helped + track regressions |
| 9 | Effectiveness | Extraction + history | `tests/double-critique/effectiveness-{date}.md` | Track trends across runs, including Loop Stats |
| 10 | Retrospective | Effectiveness + KB | `tests/double-critique/retrospective-{date}.md` | Update the knowledge base with what we learned |

---

## Stage 0 — PRE-FLIGHT (not an agent)

Before launching any agent, the orchestrator (you) performs these cleanup steps:

1. **Forcing-function check — halt on missing `max_rounds`:** re-read the Loop Configuration section above. If the `max_rounds:` line is missing or the value cannot be parsed as a positive integer, **halt** immediately with a loud error: `"double-critique: max_rounds not declared in SKILL.md; refuse to run without max_rounds. Add 'max_rounds: 4' to the Loop Configuration section and retry."` Do not continue. This prevents silent fallback to the pre-loop 2-round shape (F58). The halt must fire before Stage 1.
2. Create `tmp/` directory if it doesn't exist.
3. **Delete all stale artifacts:** `rm tmp/dc-*.md tmp/dc-loop-state.json` — this prevents stages from reading leftover files from prior runs (Run 11 bug: Critic-2 reviewed a stale document from 3 days earlier). The loop-state file must also never survive across runs.
4. Verify the source document at `$ARGUMENTS` exists and is non-empty.

## Stages 1-2 — Single-shot Pre-Loop

Run these two stages **once**, sequentially. Full prompts are in `references/stage-prompts-core.md`.

### Stage 1 — RESEARCHER
**Role:** Fact-checker, librarian, and document analyst. Builds a structured inventory of the document, then verifies claims against the codebase and knowledge base.
**Inputs:** Document at `$ARGUMENTS` + `hive-mind-persist/knowledge-base/` files + `hive-mind-persist/memory.md`
**Output:** `tmp/dc-1-researcher.md`
**Why:** Documents often contain assumptions that sound right but aren't. The Researcher checks them against reality — environment compatibility, deployment feasibility, codebase evidence, and failure modes.

Auto-detects its own environment — no manual placeholder injection needed.

See `references/stage-prompts-core.md` > Stage 1 for the full agent prompt.

### Stage 2 — DRAFTER
**Role:** Editor with a red pen. Applies research findings to improve the document.
**Inputs:** Document at `$ARGUMENTS` + `tmp/dc-1-researcher.md`
**Output:** `tmp/dc-2-drafter.md`
**Why:** Translates research findings into concrete document improvements while preserving the author's voice. Verifies upstream claims before incorporating them. Uses **evidence-gated verification** — must paste actual code/config evidence for every "I verified X" claim.

See `references/stage-prompts-core.md` > Stage 2 for the full agent prompt.

## Stages 3..N — Critic-N / Corrector-N Loop

The orchestrator runs a bounded loop. Each round spawns a fully isolated critic followed (conditionally) by a corrector. Full prompt templates are in `references/stage-prompts-core.md` > "Critic-N (ISOLATED) — Loop Template" and "Corrector-N — Loop Template". The critic must emit findings as a JSON array conforming to `references/severity-rubric.md`.

**Loop state** lives in `tmp/dc-loop-state.json`. The orchestrator owns this file. **No agent prompt ever references this file or any data it contains** — this preserves isolation (F24).

Initialize loop state before the first round:
```json
{"round": 0, "max_rounds": 4, "per_round": [], "exit_reason": null, "latest_corrected_doc": "tmp/dc-2-drafter.md"}
```

Then loop:

1. `round += 1`.
2. **Spawn Critic-N.** Substitute `{N}` with `round` and `{CORRECTED_DOC_PATH}` with `latest_corrected_doc` in the Critic-N template. Write the critic's output to `tmp/dc-{2*round+1}-critic-round{round}.md`. For diagnostic purposes and AC-14, also save the exact prompt text sent to the critic at `tmp/dc-agent-prompts/critic-round{round}.txt`.
3. **Parse the critic JSON.** Locate the single fenced code block containing a JSON array. `JSON.parse` it. On parse failure: loud error, log the raw output, abort the pipeline (F45, P44 — never silent).
4. **Compute round metrics:**
   - `blocker_count = count(findings where blocks_ship == true AND evidence != "UNVERIFIED")`
   - `critical = count(severity == "CRITICAL")`, `major = count(severity == "MAJOR")`, `minor = count(severity == "MINOR")`
   - `novel = count(novel == true)`, `unverified = count(evidence == "UNVERIFIED")`
5. **Append to `per_round`:**
   ```json
   {"round": N, "blocker_count": B, "critical": C, "major": M, "minor": m, "novel": X, "unverified": U}
   ```
6. **Exit checks (in this exact order — matches Decision #3 of the plan and AC-7):**
   - If `blocker_count == 0`: set `exit_reason = "clean"`, break out of the loop.
   - If `round >= 2 AND blocker_count >= per_round[round-2].blocker_count`: set `exit_reason = "oscillation"`, break.
   - If `round == max_rounds`: set `exit_reason = "max_rounds"`, break.
7. **Spawn Corrector-N.** Substitute `{N}`, `{CORRECTED_DOC_PATH}`, and `{CRITIC_FINDINGS_PATH}` (= the critic output path from step 2) in the Corrector-N template. Write the corrector's output to `tmp/dc-{2*round+2}-corrector-round{round}.md`. Set `latest_corrected_doc` to this new path.
8. Persist `tmp/dc-loop-state.json` after each round so the state survives context loss (F30).
9. Return to step 1.

**On loop exit:**
- Copy `latest_corrected_doc` (if the loop exited via Corrector output) or the final corrector output to `$ARGUMENTS` and to `tmp/dc-final.md`.
- Note: when the loop exits with `exit_reason = "clean"` on round N, the last-applied document is the corrector output from round N-1 (or `tmp/dc-2-drafter.md` if round 1 was already clean). The round-N critic found zero blockers, so no further correction was needed.
- Persist `tmp/dc-loop-state.json` with the final `exit_reason`.

**exit_reason precedence (canonical):** `clean` → `oscillation` → `max_rounds`.

---

## Stage 7 — ORCHESTRATOR EPILOGUE (not an agent)

After the loop exits, the orchestrator (you) performs these steps directly:

1. Read `tmp/dc-loop-state.json` and every `tmp/dc-*-critic-round*.md` file it references.
2. For each round in `per_round`, tally `{critical, major, minor, blocker_count, novel, unverified}` and list which findings were applied (blocking, now fixed) vs. deferred (non-blocking, preserved in the `<!-- deferred:critic-N -->` block) vs. skipped (the corrector explicitly rejected a blocking finding — these MUST be listed with the corrector's stated reason).
3. Append a `## Critique Log` section to the file at `$ARGUMENTS` using the template from `assets/critique-log-template.md`. The summary line must read:
   ```
   Loop ran {roundsRun} round(s), exit_reason={exit_reason}, final blocker_count={N}, total findings applied={N}, total findings deferred={N}.
   ```
4. Report the same summary to the user along with the critique log.

---

## Stages 8-10 — Feedback Loop

Run these stages **sequentially** after Stage 7. Full prompts are in `references/stage-prompts-feedback.md`.

### Stage 8 — EXTRACTOR
**Role:** Sports analyst reviewing game tape. Figures out which stages actually helped.
**Inputs:** All 6 `tmp/dc-*.md` artifacts + Critique Log
**Output:** `tmp/dc-8-extractor.md`
**Why:** Without this, we keep running all 6 stages forever even if some contribute nothing. This is how the pipeline learns about itself. Also tracks **regression counts** (defects introduced by Drafter and Corrector-1) and **evidence-gating compliance** as first-class metrics.

See `references/stage-prompts-feedback.md` > Stage 8 for the full agent prompt.

### Stage 9 — EFFECTIVENESS
**Role:** Doctor reviewing the patient's chart across multiple visits.
**Inputs:** `tmp/dc-8-extractor.md` + historical reports in `tests/double-critique/`
**Output:** `tests/double-critique/effectiveness-{date}.md`
**Why:** One run tells you nothing. Tracking trends across runs reveals which stages consistently help and which are dead weight. Now includes **regression tracking table** and **evidence-gating compliance** as first-class metrics alongside finding counts and application rates.

Replace `{date}` with today's date in YYYY-MM-DD format.

See `references/stage-prompts-feedback.md` > Stage 9 for the full agent prompt.

### Stage 10 — RETROSPECTIVE
**Role:** Team retrospective facilitator. Updates the knowledge base with what we learned.
**Inputs:** Effectiveness report + `hive-mind-persist/knowledge-base/` files + `hive-mind-persist/memory.md`
**Output:** `tests/double-critique/retrospective-{date}.md` + updates to `hive-mind-persist/memory.md` and optionally `hive-mind-persist/knowledge-base/`
**Why:** Like writing notes in a recipe book — if you don't write down what you learned, you'll make the same mistakes next time.

Replace `{date}` with today's date in YYYY-MM-DD format.

See `references/stage-prompts-feedback.md` > Stage 10 for the full agent prompt.

---

## Execution Notes

- Run stages 1-6 **sequentially** — each depends on the previous stage's output.
- Stage 7 is orchestrator work, not an agent call.
- Run stages 8-10 **sequentially** after Stage 7 — this is the feedback loop.
- Stage 8 reads all `tmp/dc-*.md` artifacts. Stage 9 reads historical reports. Stage 10 updates KB/memory.
- Replace `{date}` in stage prompts with today's date (YYYY-MM-DD format).
- If `$ARGUMENTS` is empty or the file doesn't exist, stop and ask the user for the file path.
- Environment detection: Stage 1 (Researcher) auto-detects its own environment — no orchestrator injection needed.
- Create `tmp/` directory if it doesn't exist before starting.

## Run Data Recording

After the pipeline completes (or errors out), persist run data. This section always runs.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"double-critique","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "complete|no-issues|error",
  "project": "{current project directory name}",
  "documentPath": "{path to reviewed document}",
  "totalFindings": "{N total findings summed across all rounds}",
  "criticalCount": "{N critical summed across rounds}",
  "majorCount": "{N major summed across rounds}",
  "minorCount": "{N minor summed across rounds}",
  "applicationRate": "{percentage of findings applied, e.g. 85}",
  "stagesCompleted": "{number of stages that ran, 0-10}",
  "roundsRun": "{N critic rounds actually executed, 1..max_rounds}",
  "exitReason": "clean|oscillation|max_rounds",
  "maxRounds": "{value of max_rounds for this run, e.g. 4}",
  "perRoundBlockers": "[N_round1, N_round2, ...]  // blocker_count for each round, in order",
  "summary": "{one-line: e.g., 'spec.md, 8 findings (2C/3M/3m), 88% applied, 3 rounds (clean)'}"
}
```

The loop fields are **additive and backward compatible** (P50). Existing runs without `roundsRun`/`exitReason`/`maxRounds`/`perRoundBlockers` load cleanly — readers should treat missing fields as undefined, not as errors.

**Outcome values:**
- `complete` — review ran, findings were found and addressed
- `no-issues` — review ran, zero findings
- `error` — skill could not complete (file not found, agent failure, etc.)

Keep last 20 runs (older runs are permanently discarded). Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {documentPath} | {criticalCount}C/{majorCount}M/{minorCount}m | {applicationRate}% applied | {summary}
```

Do not fail the skill if recording fails — log a warning and continue.
