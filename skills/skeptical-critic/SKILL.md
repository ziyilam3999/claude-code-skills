---
name: skeptical-critic
description: >
  Few-shot examples teaching the critic agent to demand evidence, catch subtle bugs,
  and reject surface-level "looks fine" assessments. Auto-loaded by Claude CLI into
  critic agent sessions when placed in .claude/skills/. Not user-invocable.
---

# Skeptical Critic Examples

<!-- TRUST: This file is auto-loaded into all Claude CLI agent sessions. Treat write access to this file as equivalent to modifying agent prompts. -->

These examples demonstrate how a skeptical critic applies evidence-gated analysis to catch subtle defects in specifications and design documents. Each example shows the complete INPUT artifact, the structured ANALYSIS with citations, and the final VERDICT.

## Example 1: Missing edge case in input validation

### INPUT

```typescript
// data-processor.ts

export interface ProcessorConfig {
  batchSize: number;
  delimiter: string;
}

export function splitAndProcess(input: string, config: ProcessorConfig): string[] {
  const chunks = input.split(config.delimiter);
  const results: string[] = [];

  for (let i = 0; i < chunks.length; i += config.batchSize) {
    const batch = chunks.slice(i, i + config.batchSize);
    results.push(batch.join(config.delimiter));
  }

  return results;
}
```

```markdown
## SPEC Section 4.2: Data Processing

REQ-DP-01: The `splitAndProcess` function MUST handle all valid string inputs
including empty strings, strings without the delimiter, and strings containing
only delimiters.

REQ-DP-02: When `batchSize` is provided, the function MUST partition the split
results into groups of exactly `batchSize` elements (final group may be smaller).
```

### ANALYSIS

VERIFIED: `splitAndProcess` accepts `input: string` and splits by `config.delimiter` found at data-processor.ts/line 9 -- "`const chunks = input.split(config.delimiter)`"

UNVERIFIED: REQ-DP-01 claims all valid string inputs are handled -- no evidence found for `batchSize <= 0`. When `batchSize` is 0, `for (let i = 0; i < chunks.length; i += config.batchSize)` becomes an infinite loop. When `batchSize` is negative, the slice produces empty arrays and the loop never terminates. The SPEC requires handling "all valid string inputs" but does not constrain `batchSize` to positive integers, and the implementation does not guard against non-positive values.

VERIFIED: Batch partitioning logic found at data-processor.ts/line 12 -- "`chunks.slice(i, i + config.batchSize)`" correctly produces groups of `batchSize` with a smaller final group, satisfying REQ-DP-02 when `batchSize > 0`.

Severity: critical -- An infinite loop on `batchSize <= 0` is a runtime hang that affects all callers. Add a guard: `if (config.batchSize < 1) throw new RangeError('batchSize must be >= 1')`.

### VERDICT

**FAIL** -- REQ-DP-01 claims all valid inputs are handled, but `batchSize <= 0` produces an infinite loop with no guard or SPEC constraint to prevent it.

## Example 2: Incorrect data type assumption in configuration schema

### INPUT

```typescript
// config-loader.ts

export interface AppConfig {
  port: number;
  retryDelays: number[];
  features: Record<string, boolean>;
}

export function mergeConfigs(base: AppConfig, override: Partial<AppConfig>): AppConfig {
  return {
    port: override.port ?? base.port,
    retryDelays: override.retryDelays ?? base.retryDelays,
    features: { ...base.features, ...override.features },
  };
}
```

```markdown
## SPEC Section 2.1: Configuration

REQ-CFG-01: Configuration values MUST be loaded from environment variables
first, then from the config file, with environment variables taking precedence.

REQ-CFG-02: The `retryDelays` field accepts a comma-separated string from
environment variables (e.g., "100,200,500") which MUST be parsed into a
number array.

REQ-CFG-03: `mergeConfigs` MUST perform a deep merge of all configuration
fields, preserving nested values from both base and override.
```

### ANALYSIS

VERIFIED: `mergeConfigs` performs shallow spread on `features` found at config-loader.ts/line 13 -- "`features: { ...base.features, ...override.features }`"

UNVERIFIED: REQ-CFG-03 claims deep merge for "all configuration fields" -- no evidence found. The `retryDelays` field at config-loader.ts/line 12 uses nullish coalescing (`??`), which is a full replacement, not a merge. If `base.retryDelays` is `[100, 200]` and `override.retryDelays` is `[500]`, the result is `[500]` -- the base values are silently discarded. This is shallow replacement, not deep merge. The SPEC says "deep merge of all fields" but the implementation replaces arrays entirely.

VERIFIED: `features` field uses object spread found at config-loader.ts/line 13 -- this is a shallow merge (one level deep), which satisfies REQ-CFG-03 only if `features` values are always primitives. If `features` contained nested objects, spread would overwrite, not merge. The current type `Record<string, boolean>` constrains values to booleans, making shallow merge sufficient for this specific field.

UNVERIFIED: REQ-CFG-02 describes environment variable parsing of comma-separated strings to number arrays -- no evidence of this parsing logic found in `config-loader.ts`. The function signature accepts `Partial<AppConfig>` where `retryDelays` is already `number[]`. The string-to-array conversion is either missing or implemented elsewhere without reference.

Severity: major -- Array replacement contradicts the "deep merge" requirement. Either the SPEC should say "replace" for array fields, or the implementation must concatenate/deduplicate arrays.

### VERDICT

**FAIL** -- REQ-CFG-03 specifies deep merge but `retryDelays` uses nullish coalescing (full replacement). The SPEC and implementation have contradictory merge semantics for array-typed fields.

## Example 3: Incomplete error handling in async pipeline

### INPUT

```typescript
// task-runner.ts

export async function runTaskPipeline(
  tasks: Task[],
  onProgress: (completed: number, total: number) => void,
): Promise<TaskResult[]> {
  const results: TaskResult[] = [];

  for (const task of tasks) {
    try {
      const result = await executeTask(task);
      results.push(result);
      onProgress(results.length, tasks.length);
    } catch (error) {
      results.push({ taskId: task.id, status: "failed", error: String(error) });
      onProgress(results.length, tasks.length);
    }
  }

  return results;
}

async function executeTask(task: Task): Promise<TaskResult> {
  const connection = await acquireConnection(task.target);
  const output = await connection.execute(task.command);
  await connection.release();
  return { taskId: task.id, status: "completed", output };
}
```

```markdown
## SPEC Section 5.3: Task Execution

REQ-TASK-01: The pipeline MUST execute all tasks sequentially, collecting
results for each.

REQ-TASK-02: If a task fails, the pipeline MUST record the failure and
continue with the remaining tasks.

REQ-TASK-03: All acquired connections MUST be released after task execution,
regardless of success or failure.
```

### ANALYSIS

VERIFIED: Sequential execution with failure recording found at task-runner.ts/lines 8-17 -- the `for...of` loop with `try/catch` pushes a failure result and continues, satisfying REQ-TASK-01 and REQ-TASK-02.

UNVERIFIED: REQ-TASK-03 claims connections are released "regardless of success or failure" -- no evidence found. In `executeTask` at task-runner.ts/lines 23-27, `connection.release()` is called only on the success path (line 26). If `connection.execute(task.command)` throws at line 25, execution jumps to the catch block in `runTaskPipeline` and `connection.release()` is never called. The connection leaks on every failed task.

VERIFIED: The catch block in `runTaskPipeline` at task-runner.ts/line 15 records the failure -- "`results.push({ taskId: task.id, status: 'failed', error: String(error) })`" -- which satisfies REQ-TASK-02 for result recording but does not address the leaked connection from `executeTask`.

Severity: critical -- Connection leak on task failure. Each failed task permanently consumes a connection from the pool. Under sustained failures, the pool exhausts and subsequent tasks hang on `acquireConnection`. Fix: wrap `executeTask` body in `try/finally` with `connection.release()` in the `finally` block.

### VERDICT

**FAIL** -- REQ-TASK-03 requires connection release on failure, but `executeTask` only releases on the success path. Failed tasks leak connections.

## Example 4: Claims that appear unsubstantiated but ARE backed by implementation

### INPUT

```typescript
// rate-limiter.ts

export class TokenBucket {
  private tokens: number;
  private lastRefill: number;

  constructor(
    private readonly capacity: number,
    private readonly refillRate: number,
  ) {
    this.tokens = capacity;
    this.lastRefill = Date.now();
  }

  tryConsume(count: number = 1): boolean {
    this.refill();
    if (this.tokens >= count) {
      this.tokens -= count;
      return true;
    }
    return false;
  }

  private refill(): void {
    const now = Date.now();
    const elapsed = (now - this.lastRefill) / 1000;
    const newTokens = elapsed * this.refillRate;
    this.tokens = Math.min(this.capacity, this.tokens + newTokens);
    this.lastRefill = now;
  }
}
```

```markdown
## SPEC Section 6.1: Rate Limiting

REQ-RL-01: The rate limiter MUST use a token bucket algorithm with
configurable capacity and refill rate.

REQ-RL-02: Tokens MUST refill continuously based on elapsed wall-clock
time, not on a fixed interval timer.

REQ-RL-03: The token count MUST never exceed the configured capacity,
even after long idle periods.
```

### ANALYSIS

VERIFIED: Token bucket with configurable capacity and refill rate found at rate-limiter.ts/constructor -- "`constructor(private readonly capacity: number, private readonly refillRate: number)`" with `this.tokens = capacity` initialization. Satisfies REQ-RL-01.

VERIFIED: Continuous refill based on elapsed time found at rate-limiter.ts/refill method -- "`const elapsed = (now - this.lastRefill) / 1000; const newTokens = elapsed * this.refillRate;`". The refill is computed on-demand from wall-clock delta, not from a `setInterval` timer. Satisfies REQ-RL-02.

VERIFIED: Capacity cap found at rate-limiter.ts/refill method -- "`this.tokens = Math.min(this.capacity, this.tokens + newTokens)`". After any idle period, `newTokens` could be arbitrarily large, but `Math.min` clamps the result to `capacity`. Satisfies REQ-RL-03.

VERIFIED: `tryConsume` guards against over-consumption found at rate-limiter.ts/line 17 -- "`if (this.tokens >= count)`" checks availability before decrementing. Partial consumption is rejected (all-or-nothing), which is the standard token bucket semantic.

All three requirements are fully backed by the implementation. The initial appearance of "no timer means no refill" is incorrect -- the on-demand refill pattern is a valid and common token bucket implementation that computes refill lazily at consumption time rather than eagerly on a timer.

### VERDICT

**PASS** -- All three REQ-RL requirements are backed by verifiable implementation evidence. The on-demand refill pattern satisfies continuous refill (REQ-RL-02) without requiring a timer, and `Math.min` enforces the capacity cap (REQ-RL-03).

## Run Data Recording

After the skill is loaded (or errors), persist run data. This section always runs regardless of outcome.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"skeptical-critic","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "loaded|error",
  "project": "{current project directory name}",
  "sessionType": "critic",
  "summary": "{one-line: e.g., 'loaded for critic session'}"
}
```

Keep last 20 runs (older runs are permanently discarded). Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {sessionType} | {summary}
```

Do not fail the skill if recording fails -- log a warning and continue.
