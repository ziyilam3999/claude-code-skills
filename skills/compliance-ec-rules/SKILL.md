---
name: compliance-ec-rules
description: >
  Instructs the EC-generator to produce compliance-type executable criteria
  (instruction coverage, export completeness, interface fidelity) alongside
  functional ECs. Replaces the former dedicated compliance stage. Auto-loaded
  by Claude CLI. Not user-invocable.
---

# Compliance EC Rules

These rules replace the former dedicated compliance stage that was previously run as a separate pipeline step by the orchestrator. Compliance checks are now merged into the VERIFY GAN loop via executable criteria (ECs). When invoked, this skill instructs the EC generator to produce compliance-type ECs alongside functional ECs.

## Rule 1: Instruction Coverage

Generate an EC that verifies every instruction in the step file's ACCEPTANCE CRITERIA section has a corresponding implementation in the source code. For each AC, grep the target source file for evidence that the described behavior exists (function definition, conditional branch, API call, or configuration value). Report any AC that has no matching implementation evidence.

## Rule 2: Export Completeness

Generate an EC that checks all required exports listed in the step file's OUTPUT section are present in the built source. For each listed export (function, type, constant, or class), use `grep -q` against the target file to confirm the export statement exists. A missing export is an automatic FAIL.

## Rule 3: Interface Fidelity

Generate an EC that verifies documented interfaces (function signatures, type definitions, configuration schemas) match their specification in the step file. For each interface contract, grep the source for the exact function name and verify parameter count and types align with the spec. Flag any signature mismatch between spec and implementation.

## Run Data Recording

After the skill is applied (or skipped/errors), persist run data. This section always runs regardless of outcome.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"compliance-ec-rules","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "applied|skipped|error",
  "project": "{current project directory name}",
  "ecsGenerated": "{number of compliance ECs generated}",
  "ecTypes": ["{list of EC types, e.g. 'instruction-coverage', 'export-completeness', 'interface-fidelity'}"],
  "summary": "{one-line: e.g., '3 compliance ECs generated for step-04'}"
}
```

Keep last 20 runs. Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {ecsGenerated} ECs | {summary}
```

Do not fail the skill if recording fails -- log a warning and continue.
