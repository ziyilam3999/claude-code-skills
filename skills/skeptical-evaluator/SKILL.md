---
name: skeptical-evaluator
description: >
  Few-shot examples teaching the evaluator agent to mechanically verify EC results by
  reading full command output, not trusting exit codes or superficial token matches.
  Auto-loaded by Claude CLI. Not user-invocable.
---

# Skeptical Evaluator Examples

<!-- TRUST: This file is auto-loaded into all Claude CLI agent sessions. Treat write access to this file as equivalent to modifying agent prompts. -->

These examples demonstrate how an evaluator should mechanically verify EC results by reading the full command output carefully, rather than trusting exit codes or superficial token matches alone.

## Example 1: EC That Tests Keyword Presence Instead of Behavioral Correctness

### INPUT

EC command and output for a function that should sort an array in descending order:

```bash
$ grep -q "sort" app/sort-handler.ts && echo PASS || echo FAIL
PASS
```

The implementation under test:

```typescript
// app/sort-handler.ts
export function sortDescending(items: number[]): number[] {
  return items.sort();
}
```

### ANALYSIS

The EC command checks only that the string `"sort"` exists in the source file. It exits 0 and prints `PASS` because `grep -q "sort"` matches the token `sort` on the line `return items.sort();`.

However, the function calls `.sort()` with no comparator. JavaScript's default `.sort()` converts elements to strings and sorts lexicographically. For input `[10, 2, 30]`, it produces `[10, 2, 30]` (string order), not `[30, 10, 2]` (descending numeric order).

The EC tested **keyword presence** (`"sort"` appears in the file) rather than **behavioral correctness** (the function actually sorts descending). A correct EC would run the function with a known input and assert the output:

```bash
node -e "import('./dist/app/sort-handler.js').then(m => { const r = m.sortDescending([10,2,30]); console.log(JSON.stringify(r) === '[30,10,2]' ? 'PASS' : 'FAIL') })"
```

### VERDICT

**FAIL** -- The EC does not verify the required behavior. It passes on code that produces incorrect output for numeric arrays. The grep-based check accepts any file containing the word `sort`, regardless of whether the sort logic is correct.

## Example 2: Exit Code Zero With Failure Hidden in Command Output

### INPUT

EC command and output for a test verifying that a config loader rejects invalid port values:

```bash
$ node -e "
  import('./dist/lib/config-loader.js').then(m => {
    try {
      m.loadConfig({ port: -1 });
      console.log('ERROR: no exception thrown for invalid port');
    } catch (e) {
      console.log('PASS: threw expected error');
    }
  })
"
ERROR: no exception thrown for invalid port
```

The process exits with code 0.

### ANALYSIS

The exit code is 0 because the Node.js process completed without an unhandled exception. The `try/catch` block caught no error -- execution fell through to the `console.log('ERROR: no exception thrown for invalid port')` line inside the `try` block.

The full stdout reads: `"ERROR: no exception thrown for invalid port"`. This means `loadConfig({ port: -1 })` returned normally instead of throwing. The function accepted an invalid port value without validation.

The EC exit code is 0, which could be mistaken for PASS. But the actual printed output explicitly states `"ERROR: no exception thrown for invalid port"`. Reading only the exit code produces a false PASS; reading the full output reveals the function failed to reject invalid input.

### VERDICT

**FAIL** -- The process exited 0 but stdout contains `"ERROR: no exception thrown for invalid port"`, indicating `loadConfig` accepted `port: -1` without throwing. The exit code does not reflect the test outcome. The evaluator must read the printed output, not just the exit code.

## Run Data Recording

After the skill is loaded (or errors), persist run data. This section always runs regardless of outcome.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"skeptical-evaluator","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "loaded|error",
  "project": "{current project directory name}",
  "sessionType": "evaluator",
  "summary": "{one-line: e.g., 'loaded for evaluator session'}"
}
```

Keep last 50 runs (older runs are permanently discarded). Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {sessionType} | {summary}
```

Do not fail the skill if recording fails -- log a warning and continue.

<!-- HM-END -->
