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

Run a 6-stage dual-critique pipeline on the document at `$ARGUMENTS`, followed by a 3-stage feedback loop that extracts learnings, tracks effectiveness, and updates the knowledge base.

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
| 3 | Critic-1 | Draft only (isolated) | `tmp/dc-3-critic1.md` | Cold reviewer catches what the author can't see |
| 4 | Corrector-1 | Draft + Critique | `tmp/dc-4-corrector1.md` | Surgical fixes — only what was flagged |
| 5 | Critic-2 | Corrected only (isolated) | `tmp/dc-5-critic2.md` | Second cold reviewer catches side effects from Round 1 fixes |
| 6 | Corrector-2 | Corrected + Critique | `$ARGUMENTS` + `tmp/dc-6-final.md` | Final pass — consistency check and cleanup |
| 7 | Orchestrator | Both critiques | Appended to `$ARGUMENTS` | Compile the Critique Log (not an agent call) |
| 8 | Extractor | All 6 artifacts | `tmp/dc-8-extractor.md` | Figure out which stages actually helped + track regressions |
| 9 | Effectiveness | Extraction + history | `tests/double-critique/effectiveness-{date}.md` | Track trends across runs |
| 10 | Retrospective | Effectiveness + KB | `tests/double-critique/retrospective-{date}.md` | Update the knowledge base with what we learned |

---

## Stage 0 — PRE-FLIGHT (not an agent)

Before launching any agent, the orchestrator (you) performs these cleanup steps:

1. Create `tmp/` directory if it doesn't exist
2. **Delete all stale artifacts:** `rm tmp/dc-*.md` — this prevents stages from reading leftover files from prior runs (Run 11 bug: Critic-2 reviewed a stale document from 3 days earlier)
3. Verify the source document at `$ARGUMENTS` exists and is non-empty

## Stages 1-6 — Core Critique Pipeline

Run these stages **sequentially**. Each depends on the previous stage's output. Full prompts are in `references/stage-prompts-core.md`.

### Stage 1 — RESEARCHER
**Role:** Fact-checker, librarian, and document analyst. Builds a structured inventory of the document, then verifies claims against the codebase and knowledge base.
**Inputs:** Document at `$ARGUMENTS` + `hive-mind-persist/knowledge-base/` files + `hive-mind-persist/memory.md`
**Output:** `tmp/dc-1-researcher.md`
**Why:** Documents often contain assumptions that sound right but aren't. The Researcher checks them against reality — environment compatibility, deployment feasibility, codebase evidence, and failure modes. Also builds the structured inventory that the old Reader stage used to produce (merged here after 8 runs of zero evaluative contribution from Reader).

Auto-detects its own environment — no manual placeholder injection needed.

See `references/stage-prompts-core.md` > Stage 1 for the full agent prompt.

### Stage 2 — DRAFTER
**Role:** Editor with a red pen. Applies research findings to improve the document.
**Inputs:** Document at `$ARGUMENTS` + `tmp/dc-1-researcher.md`
**Output:** `tmp/dc-2-drafter.md`
**Why:** Translates research findings into concrete document improvements while preserving the author's voice. Verifies upstream claims before incorporating them.

When the document contains test cases, applies a mandatory **test case mechanical self-check** (ESM syntax, assertion targets, file extensions, precondition realism) before the general self-review. Uses **evidence-gated verification** — must paste actual code/config evidence for every "I verified X" claim.

See `references/stage-prompts-core.md` > Stage 2 for the full agent prompt.

### Stage 3 — CRITIC-1 (ISOLATED)
**Role:** Cold reviewer. Sees ONLY the draft — no research, no history, no original.
**Inputs:** `tmp/dc-2-drafter.md` only
**Output:** `tmp/dc-3-critic1.md`
**Why:** Isolation is the point. If the critic sees the reasoning behind changes, it unconsciously confirms them instead of challenging them. A cold reviewer catches logical gaps, unsupported claims, and contradictions that informed reviewers miss.

See `references/stage-prompts-core.md` > Stage 3 for the full agent prompt.

### Stage 4 — CORRECTOR-1
**Role:** Surgeon. Fixes only what Critic-1 flagged — no new content.
**Inputs:** `tmp/dc-2-drafter.md` + `tmp/dc-3-critic1.md`
**Output:** `tmp/dc-4-corrector1.md`
**Why:** Separating critique from correction prevents the critic from self-censoring ("I shouldn't flag this because I don't know how to fix it").

Applies a mandatory **second-order effect check** after each fix (format changes, naming, data shapes) then the self-review checklist. Uses **evidence-gated verification** — must paste actual code/config evidence for every "I verified X" claim.

See `references/stage-prompts-core.md` > Stage 4 for the full agent prompt.

### Stage 5 — CRITIC-2 (ISOLATED)
**Role:** Second cold reviewer. Sees ONLY the corrected version — no prior critique, no history.
**Inputs:** `tmp/dc-4-corrector1.md` only
**Output:** `tmp/dc-5-critic2.md`
**Why:** Fixes have side effects. Corrector-1 is too close to its own changes to see them. A second cold reviewer catches problems introduced by Round 1 corrections — things that SOUND right but WON'T WORK in practice.

See `references/stage-prompts-core.md` > Stage 5 for the full agent prompt.

### Stage 6 — CORRECTOR-2
**Role:** Final fixer. Applies Round 2 critique and verifies internal consistency.
**Inputs:** `tmp/dc-4-corrector1.md` + `tmp/dc-5-critic2.md`
**Output:** Writes back to `$ARGUMENTS` + copy to `tmp/dc-6-final.md`
**Why:** Final quality gate before the document is returned to the user.

Applies the self-review checklist from `references/self-review-checklist.md` after fixes. Uses **evidence-gated verification**.

See `references/stage-prompts-core.md` > Stage 6 for the full agent prompt.

---

## Stage 7 — ORCHESTRATOR EPILOGUE (not an agent)

After all 6 agent stages complete, the orchestrator (you) performs these steps directly:

1. Read `tmp/dc-3-critic1.md` and `tmp/dc-5-critic2.md`
2. Count findings from each critique round (CRITICAL/MAJOR/MINOR counts)
3. Append a `## Critique Log` section to the file at `$ARGUMENTS` using the template from `assets/critique-log-template.md`:
   - How many findings from each critique round (CRITICAL/MAJOR/MINOR counts)
   - Which findings were applied vs. rejected (with brief reasons)
   - Summary of what changed across both rounds
4. Report a summary to the user: total findings, what changed, and the critique log

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
  "totalFindings": "{N total findings across both critique rounds}",
  "criticalCount": "{N critical}",
  "majorCount": "{N major}",
  "minorCount": "{N minor}",
  "applicationRate": "{percentage of findings applied, e.g. 85}",
  "stagesCompleted": "{number of stages that ran, 0-10}",
  "summary": "{one-line: e.g., 'spec.md, 8 findings (2C/3M/3m), 88% applied, 10 stages'}"
}
```

**Outcome values:**
- `complete` — review ran, findings were found and addressed
- `no-issues` — review ran, zero findings
- `error` — skill could not complete (file not found, agent failure, etc.)

Keep last 20 runs. Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {documentPath} | {criticalCount}C/{majorCount}M/{minorCount}m | {applicationRate}% applied | {summary}
```

Do not fail the skill if recording fails — log a warning and continue.
