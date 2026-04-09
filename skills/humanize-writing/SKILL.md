---
name: humanize-writing
description: Review and rewrite AI-generated text to sound human-written. Use when the user wants to check if text sounds AI-generated, remove AI tells from a document, make writing sound natural, or detect LLM-generated content. Triggers on phrases like 'humanize', 'sounds AI', 'AI-generated', 'make it sound human', 'natural voice', 'does this sound like AI', 'remove AI tells', 'make it less robotic'. Also use when the user has just generated text with Claude and wants to ensure it passes as human-written. Do NOT trigger for general editing, grammar fixes, or style changes unrelated to AI detection.
---

# Humanize Writing

A multi-agent pipeline that detects AI writing patterns and rewrites text to sound human-written. Runs evaluation criteria, scores the document, applies corrections, and tracks effectiveness over time.

## Pipeline Overview

6 stages run sequentially. Stages 1-4 always run. Stages 5-6 run when historical data exists in `tests/humanize/`.

Each agent is **stateless** — it receives only the files listed as inputs. No shared context between stages.

## How to Use

The user provides either:
- A file path to humanize (e.g., `/humanize path/to/file.md`)
- Inline text to humanize
- A request to check if text sounds AI-generated

Detect the **document type** from context or ask: README, PRD, blog post, documentation, email, cover letter, etc. This affects which eval criteria apply.

## Stage 1 — EVAL WRITER

Use the Agent tool (research-only) with this prompt:

> You are an expert at detecting AI-generated text. Your task is to write evaluation criteria for a {document_type}.
>
> Read the known AI detection patterns from the references file at `{skill_path}/references/ai-detection-patterns.md`.
> Read the document-type profile from `{skill_path}/references/document-type-profiles.md` for the section matching "{document_type}".
> Read the document at `{file_path}`.
>
> Write 12-15 evaluation criteria to `tmp/humanize-evals.md`.
>
> Each criterion must follow this format:
>
> ```
> ### E{N} — {Name}
> **Category:** {Word Choice | Sentence Structure | Formatting | Tone | Specificity}
> **Severity:** {HIGH | MEDIUM | LOW}
> **Question:** {A yes/no question that can be objectively checked}
> **Human would:** {What human-written text looks like for this criterion}
> **AI tends to:** {What AI-generated text does}
> **Threshold:** {Specific, measurable threshold — e.g., "more than 2 em-dashes"}
> ```
>
> Include criteria from the known patterns file. Add new criteria if you spot patterns not yet documented.
> Tailor criteria to the document type (a README has different norms than a cover letter).
>
> Do NOT evaluate the document — just write the criteria.

Write output to `tmp/humanize-evals.md`.

Replace `{skill_path}` with the actual path to this skill directory, `{file_path}` with the document path, and `{document_type}` with the detected type.

## Stage 2 — EVAL RUNNER (isolated)

Use the Agent tool (research-only) with this prompt:

> You are a harsh text evaluator reading this document cold. You know NOTHING about how it was created.
>
> Read:
> - The document at `{file_path}`
> - The evaluation criteria at `tmp/humanize-evals.md`
>
> For EVERY criterion (E1 through E{N}):
> - Score: **PASS** (reads human) or **FAIL** (reads AI-generated)
> - **Confidence:** HIGH / MEDIUM / LOW — how certain are you?
> - **Evidence:** Quote the specific lines/phrases that support your verdict
>
> Be harsh. Borderline = FAIL.
>
> After scoring, add:
>
> ## Gut Check
> Read the whole thing as a {target_audience} scrolling through it. In 3-4 sentences: does it feel like a person wrote it or a chatbot? What specifically triggers that feeling?
>
> ## Top 5 Most AI-Sounding Phrases
> List the 5 exact phrases that most scream "AI wrote this", ranked worst to mildest. Quote them exactly.

Write output to `tmp/humanize-eval-results.md`.

Replace `{target_audience}` with the likely reader (e.g., "hiring manager" for a README, "engineer" for a PRD).

## Stage 3 — CORRECTOR (with self-review)

Use the Agent tool with this prompt:

> You are a writer who makes AI-generated text sound human. You are NOT a cheerleader — you write like a real person.
>
> Read:
> - The document at `{file_path}`
> - The eval results at `tmp/humanize-eval-results.md`
> - The correction strategies at `{skill_path}/references/correction-strategies.md`
> - Any source data files the user referenced (for factual accuracy)
>
> Fix every FAIL. Apply the correction strategies for each pattern type.
>
> Rules:
> - Vary sentence structure. Break parallel patterns.
> - Use conversational tone appropriate to the document type.
> - Keep all factual claims accurate.
> - Do NOT over-correct into fake-casual slang.
> - Preserve the author's intent and key information.
>
> MANDATORY SELF-REVIEW after corrections:
> Re-read every change. For each fix, check:
> 1. Did this fix introduce a new AI pattern? (e.g., replacing em-dashes with semicolons everywhere)
> 2. Did this fix change the meaning or lose important information?
> 3. Does this fix conflict with another fix in the same pass?
>
> If you find a problem with your own fix, correct it and note: "SELF-CAUGHT: [description]"
>
> Write the corrected version to `{file_path}`.

## Stage 4 — RE-EVALUATOR (isolated)

Use the Agent tool (research-only) with this prompt:

> You are a fresh evaluator seeing this document for the first time.
>
> Read:
> - The corrected document at `{file_path}`
> - The evaluation criteria at `tmp/humanize-evals.md`
> - The previous eval results at `tmp/humanize-eval-results.md`
>
> Re-score every criterion: PASS or FAIL with brief evidence.
>
> Show a comparison table:
> | Eval | Severity | Before | After | Notes |
>
> Flag any regressions (PASS→FAIL).
>
> ## Verdict
> - Remaining FAILs: {count}
> - Does it read as human-written? Honest gut reaction in 3-4 sentences.
> - Remaining issues to flag.

Write output to `tmp/humanize-eval-summary.md`.

## Stage 5 — EFFECTIVENESS TRACKER (runs if tests/humanize/ exists)

Use the Agent tool (research-only) with this prompt:

> Read:
> - This run's summary: `tmp/humanize-eval-summary.md`
> - All historical effectiveness reports in `tests/humanize/` (files matching `effectiveness-*.md`)
>
> Produce an effectiveness report:
>
> ## This Run
> - Document: {file_path}
> - Document type: {document_type}
> - Total criteria: {N}, FAILs before: {N}, FAILs after: {N}
> - Application rate: {applied fixes} / {total FAILs}
> - Regressions: {count}
> - Self-caught issues: {count}
>
> ## Cross-Run Trends
> - Which criteria fail most often across runs?
> - Which corrections are most effective?
> - Are certain document types harder to humanize?
> - Is the pipeline finding fewer issues over time?
>
> ## Criteria Effectiveness
> For each criterion used in 2+ runs:
> - Fail rate: how often it catches something
> - False positive rate: how often it flags human text incorrectly (if known)
> - Verdict: KEEP / MODIFY / DROP

Write to `tests/humanize/effectiveness-{date}.md`.

## Stage 6 — RETROSPECTIVE (runs if tests/humanize/ exists)

Use the Agent tool with this prompt:

> Read:
> - Effectiveness report: `tests/humanize/effectiveness-{date}.md`
> - Known patterns: `{skill_path}/references/ai-detection-patterns.md`
> - All retrospectives in `tests/humanize/` (files matching `retrospective-*.md`)
>
> Write a retrospective:
>
> ## KEEP
> What's working well (with evidence from runs).
>
> ## CHANGE
> What should be modified (specific proposals, not vague).
>
> ## ADD
> New criteria or patterns to add.
>
> ## DROP
> Criteria that consistently add no value.
>
> ## New Patterns Discovered
> Format: **P{N}: {Name}** — {what} / {why} / {evidence}
> Only graduate to `references/ai-detection-patterns.md` if observed in 3+ runs.
>
> ## Next Run Priorities
> 1-3 concrete changes for the next pipeline run.

Write to `tests/humanize/retrospective-{date}.md`.

If a pattern has been observed in 3+ runs with consistent evidence, update `{skill_path}/references/ai-detection-patterns.md` to add it.

## After Pipeline Completes

Report to the user:
1. Before/after FAIL count
2. Top changes made
3. Any remaining concerns
4. (If stages 5-6 ran) Cross-run trends and new patterns discovered

## Run Data Recording

After the pipeline completes (or aborts), persist run data. This section always runs, even if stages 5-6 were skipped. This complements the per-run effectiveness reports in `tests/humanize/` with aggregated metrics.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"humanize-writing","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "complete|partial|aborted",
  "project": "{current project directory name}",
  "documentPath": "{path to input document}",
  "documentType": "readme|blog|email|report|other",
  "stagesCompleted": ["1","2","3","4"],
  "criteriaGenerated": "{N eval criteria from Stage 1}",
  "failsBefore": "{N FAIL criteria before correction}",
  "failsAfter": "{N FAIL criteria after correction}",
  "improvementRate": "{percentage reduction in FAILs}",
  "effectivenessReportWritten": true,
  "retrospectiveWritten": true,
  "summary": "{one-line: e.g., 'README.md, 12 criteria, 8→2 FAILs (75% improvement)'}"
}
```

Keep last 20 runs (older runs are permanently discarded). Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {documentType} | {failsBefore}→{failsAfter} FAILs | {summary}
```

Do not fail the skill if recording fails — log a warning and continue.

## Important Notes

- Replace `{date}` with today's date in YYYY-MM-DD format
- Replace `{skill_path}` with the actual path to this skill's directory
- Create `tests/humanize/` directory before first Stage 5 run
- Stages 1-4 always run sequentially
- Stages 5-6 only run if `tests/humanize/` directory exists with prior reports
- After 3+ runs, the pipeline should be noticeably better at detecting patterns specific to the user's document types
