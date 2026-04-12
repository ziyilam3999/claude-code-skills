---
name: coherent-plan
description: Quick consistency review for small plans and strategy docs. Finds contradictions, fixes them, and produces a coherent final version. Use when the user says "/coherent-plan", "review this plan", "check for contradictions", or wants a fast consistency pass on a plan file (under ~150 lines). For large implementation specs (200+ lines with architecture and file specs), use /double-critique instead.
---

# Coherent Plan

Single-pass consistency review for small plans. Lighter and faster than /double-critique.

## When to Use

- Strategy docs, dogfood plans, workflow specs under ~150 lines
- Iterative plan refinement (multiple review rounds in one session)
- Any plan where a quick contradiction check beats a full 10-stage pipeline

## Workflow

The argument is a file path. If omitted, ask for it.

### Step 1: Inventory

Read the plan file. Build an inventory of every claim, decision, stance, and step. List them as bullet points grouped by section. Note any version numbers, dates, or specific technical claims.

### Step 2: Cross-check

Compare every item against every other item. Flag:

- **Contradictions** — X says A, Y says not-A
- **Stale references** — version numbers, file paths, or states that were true earlier but got superseded
- **Orphaned steps** — steps that reference removed or renamed concepts
- **Scope drift** — items that don't serve the stated goal
- **Missing links** — steps that assume context not present in the document

Print findings as a numbered list with severity (CRITICAL / MAJOR / MINOR) and the two conflicting locations.

### Step 3: Fix

For each finding:
- CRITICAL/MAJOR: Fix directly in the plan. Take a clear stance (don't hedge).
- MINOR: Fix if trivial, otherwise note as a comment for the author.

Write the corrected plan back to the same file.

### Step 4: Report

Print a summary:
```
## Coherent Plan Review

File: {path}
Findings: {N} ({critical} critical, {major} major, {minor} minor)
Fixed: {count}
Noted: {count}

### Changes
- {one-line description of each fix}
```

**Escalation rule:** If `critical >= 1` OR `major >= 3`, print the banner block below **above** the `## Coherent Plan Review` summary, so it lands before the summary in terminal scrollback and cannot be buried. Then print the summary as usual. Also print the numbered `Options after escalation` block below immediately after the banner.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ESCALATED — coherent-plan threshold exceeded
  {critical} critical, {major} major blocking-class findings
  Recommended next step: /double-critique {path}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Options after escalation:
  1. Run `/double-critique {path}` — deeper multi-round critique loop (recommended when the plan is complex or high-stakes).
  2. Fix the flagged issues yourself, then rerun `/coherent-plan {path}` — cheapest path when the findings are actionable and small.
  3. Ignore and ship as-is — only valid for low-stakes plans where you judge remaining findings as acceptable.
  4. Split the plan — extract the complex section into its own file, coherent-plan the simpler remainder, double-critique the complex extract.
  5. Reduce scope, rerun `/coherent-plan` — trim what the plan is trying to do until findings drop below threshold.

STATUS: ESCALATED
```

The final `STATUS: ESCALATED` sentinel is a machine-readable signal for any downstream automation. When the threshold is not crossed, omit the banner, options block, and sentinel entirely — no `STATUS: OK` line is printed, because absence is the default.

Also persist `"escalated": true|false` in the `runs/data.json` entry for this run (next section). The threshold is intentionally lightweight — coherent-plan never loops, and never attempts to emulate double-critique. It only flags when a plan has outgrown coherent-plan's single-pass scope.

## Run Data Recording

After the review completes (or errors out), persist run data. This section always runs.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"coherent-plan","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "complete|no-issues|error",
  "project": "{current project directory name}",
  "filePath": "{path to reviewed plan file}",
  "findingsTotal": "{N total findings}",
  "critical": "{N critical}",
  "major": "{N major}",
  "minor": "{N minor}",
  "fixed": "{N fixes applied}",
  "noted": "{N noted but not fixed}",
  "escalated": "{true if critical >= 1 or major >= 3, else false}",
  "summary": "{one-line: e.g., 'plan.md, 5 findings (1 critical, 2 major, 2 minor), 4 fixed'}"
}
```

**Outcome values:**
- `complete` — review ran, findings were found and addressed
- `no-issues` — review ran, zero findings
- `error` — skill could not complete (file not found, parse error, etc.)

Keep last 20 runs (older runs are permanently discarded). Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines). When `escalated == true`, append the literal token ` | ESCALATED` at the end of the line so historical escalations are greppable via `grep ESCALATED skills/coherent-plan/runs/run.log`. When `escalated == false`, do not add any escalation marker (absence is the default).

Non-escalated line format:
```
{timestamp} | {outcome} | {project} | {critical}C/{major}M/{minor}m | {fixed} fixed | {summary}
```

Escalated line format:
```
{timestamp} | {outcome} | {project} | {critical}C/{major}M/{minor}m | {fixed} fixed | {summary} | ESCALATED
```

Do not fail the skill if recording fails — log a warning and continue.
