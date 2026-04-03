---
name: skill-evolve
description: Unified skill lifecycle manager. Create, audit, and improve custom skills. Use when the user says "/skill-evolve", "evolve skill", "audit skill", "improve skill", "create a skill", "check skill health", or wants to manage the lifecycle of custom skills. Subcommands: create, audit, improve, audit-all.
---

# Skill Evolve

Unified entry point for the custom skill lifecycle: create, audit, and improve.

## Subcommand Routing

Parse the argument to determine the subcommand:

| Pattern | Subcommand |
|---------|------------|
| `create <name> [description]` | Create |
| `audit <skill-name>` | Audit |
| `improve <skill-name>` | Improve |
| `audit-all` | Audit All |
| No argument or ambiguous | Ask the user |

## Create

Delegate to `/skill-creator` for the actual creation, but wrap it with lifecycle setup:

1. Invoke the `skill-creator` skill with the user's arguments
2. After skill-creator finishes, run the **Audit** subcommand on the newly created skill
3. Auto-fix any audit failures (recording, directory structure, symlink)

This ensures every new skill starts healthy.

## Audit

Run a health check on a single skill. The argument is a skill name (e.g., `coherent-plan`).

### Step 1: Locate the skill

Search in order:
1. The skill's source repository `skills/{name}/SKILL.md` (resolve via `git rev-parse --show-toplevel`)
2. `~/.claude/skills/{name}/SKILL.md`
3. `~/.claude/skills/{name}/{name}/SKILL.md` (double-nested)

If not found, report and stop.

### Step 2: Run checklist

Read `references/audit-checklist.md` (relative to this skill's base directory). Execute every check in the checklist against the target skill. Record each as PASS / FAIL / WARN.

### Step 3: Auto-fix FAIL items

For each FAIL result, apply the auto-fix if one exists (see checklist Auto-Fix section). Fixes include:
- Move to the skills source directory and create symlink
- Flatten double-nested directories
- Create missing `runs/` directory, `data.json`, `run.log`
- Append a Run Data Recording section template to SKILL.md (mark as needing human review of metric fields)

### Step 4: Report

Print results:
```
## Skill Audit: {name}

| # | Check | Result |
|---|-------|--------|
| F1 | SKILL.md exists | PASS |
| ... | ... | ... |

Summary: {pass} passed, {fail} failed (auto-fixed: {fixed}), {warn} warnings
```

If any FAIL items could not be auto-fixed, list them with remediation steps.

## Improve

Analyze run data and invoke skill-creator's iterate workflow to propose improvements.

### Step 1: Locate and validate

1. Find the skill (same as Audit Step 1)
2. Check `runs/data.json` exists and has runs
3. **Gate**: If fewer than 5 runs, report "Not enough data to improve ({N}/5 runs). Use the skill more and try again." and stop.

### Step 2: Analyze patterns

Read `runs/data.json`. Compute:
- **Outcome distribution**: count of each outcome value (success, failure, error, etc.)
- **Recurring issues**: group `issues` array entries by type, rank by frequency
- **Stage failure rates**: which stages fail most often
- **Trend**: are recent runs better or worse than early runs?
- **Metric anomalies**: any metrics consistently at zero or at ceiling

### Step 3: Compose improvement brief

Write a structured brief:
```
## Improvement Brief: {skill-name}

### Data Summary
- Total runs: {N}
- Outcome distribution: {breakdown}
- Date range: {first} to {last}

### Patterns Found
1. {pattern description + evidence}
2. ...

### Suggested Improvements
1. {concrete change to SKILL.md or resources}
2. ...
```

### Step 4: Invoke skill-creator iterate

Present the improvement brief to the user. If they approve, invoke `/skill-creator` in iterate mode (Step 6) with the brief as context. The skill-creator handles the actual SKILL.md edits.

## Audit All

Batch audit across all custom skills.

1. List all directories in the skill's source repository `skills/` directory
2. Exclude: `skill-evolve` itself, any `_archive` prefixed dirs
3. For each skill, run the **Audit** subcommand (Steps 1-4)
4. Print a summary table:

```
## Skill Health Dashboard

| Skill | PASS | FAIL | WARN | Status |
|-------|------|------|------|--------|
| ship | 14 | 0 | 0 | Healthy |
| coherent-plan | 12 | 2 | 1 | Needs fix |
| ... | ... | ... | ... | ... |

{N} skills audited. {healthy} healthy, {needs_fix} need fixes.
```

5. Offer to auto-fix all failing skills in one pass.

## Run Data Recording

After any subcommand completes, persist run data. This section always runs.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"skill-evolve","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "complete|no-action|error",
  "subcommand": "create|audit|improve|audit-all",
  "project": "{current project directory name}",
  "targetSkill": "{skill name or null for audit-all}",
  "checksRun": "{N checks executed, 0 for create/improve}",
  "passed": "{N passed}",
  "failed": "{N failed}",
  "warned": "{N warnings}",
  "autoFixed": "{N auto-fixed}",
  "improvementTriggered": "{true|false}",
  "stages": {
    "locate": "pass|fail|skip",
    "analyze": "pass|fail|skip",
    "brief": "pass|fail|skip",
    "iterate": "pass|fail|skip"
  },
  "metrics": {
    "runsAnalyzed": "{N runs read from data.json, 0 if not applicable}",
    "patternsFound": "{N patterns identified, 0 if not applicable}",
    "suggestionsGenerated": "{N improvement suggestions produced, 0 if not applicable}"
  },
  "issues": [
    { "stage": "{stage}", "type": "{issue_type}", "description": "{description}" }
  ],
  "summary": "{one-line}"
}
```

**Outcome values:**
- `complete` -- subcommand ran successfully
- `no-action` -- nothing to do (e.g., improve with insufficient data)
- `error` -- subcommand could not complete

Keep last 20 runs. Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {subcommand} | {targetSkill} | {summary}
```

Do not fail the skill if recording fails -- log a warning and continue.
