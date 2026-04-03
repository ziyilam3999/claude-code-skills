---
name: checkpoint
description: Session checkpoint that consolidates progress and prepares for continued work. Use when the user says "/checkpoint", "checkpoint", "save progress", "where was I", or wants to update their plan, trim stale context, and see next steps. Also use when resuming a session or before context gets too large.
---

# Checkpoint

Save session progress and surface next steps in one command.

## Workflow

### Step 1: Find the active plan

Check both plan locations (in parallel):
1. **Project plans:** Glob for `.ai-workspace/plans/*.md` in the current project root
2. **Claude Code plans:** Glob for `~/.claude/plans/*.md` (native `/plan` mode files)

If plans exist in both locations, pick the most recently modified. If no plan exists in either, tell the user there is nothing to checkpoint and stop.

Read the plan file fully.

### Step 2: Update completed items

Review the conversation history for work completed since the plan was last updated:
- Mark finished checkboxes (`- [ ]` to `- [x]`)
- Add a `Last updated: {ISO-8601 timestamp}` line after the Checkpoint section
- If work was done that is not captured in any checkbox, add it as a new checked item
- Do NOT add items that were not actually completed

Edit the plan file in place.

### Step 3: Trim stale sections

Remove or condense sections that are no longer useful:
- Completed alternatives or rejected approaches
- Debugging notes from resolved issues
- Intermediate exploration that led to the final approach

Keep: context section, open checkboxes, ELI5, test cases, any section still relevant to remaining work.

Edit the plan file in place. If nothing is stale, skip this step.

### Step 4: Show next steps

Print a concise summary:

```
## Checkpoint saved

Plan: {relative path to plan file}
Progress: {completed}/{total} items

### Next up
- [ ] {first unchecked item}
- [ ] {second unchecked item}
- [ ] {third unchecked item, if any}

{One sentence on what to tackle next based on the open items.}
```

If all items are checked, print "All items complete -- plan is done." instead of next steps.

## Run Data Recording

After showing next steps (or "nothing to checkpoint"), persist run data. This section always runs.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"checkpoint","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "saved|no-plan|all-complete",
  "project": "{current project directory name}",
  "planFile": "{relative path to plan file or null}",
  "itemsCompleted": "{N items marked complete this run}",
  "itemsRemaining": "{N unchecked items}",
  "staleSectionsTrimmed": "{N sections removed or 0}",
  "summary": "{one-line: e.g., '3/8 items complete, 2 stale sections trimmed'}"
}
```

Keep last 20 runs. Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {project} | {summary}
```

Do not fail the skill if recording fails — log a warning and continue.
