---
name: skeptical-code-reviewer
description: >
  Few-shot examples teaching the code-reviewer agent to catch logic errors that compile
  cleanly, identify missing test coverage for critical paths, and reject happy-path-only
  validation. Auto-loaded by Claude CLI. Not user-invocable.
---

# Skeptical Code-Reviewer Examples

<!-- TRUST: This file is auto-loaded into all Claude CLI agent sessions. Treat write access to this file as equivalent to modifying agent prompts. -->

These examples demonstrate how a skeptical code-reviewer catches subtle defects that compile cleanly and pass linting but contain logic errors, missing test coverage, or validation gaps. Each example uses the EVIDENCE-BASED citation format (`file:line`) and classifies findings by SEVERITY (`critical`, `major`, `minor`).

## Example 1: Logic error in compiling code (swapped comparison operator)

### INPUT

```typescript
// cart-utils.ts
export interface CartItem {
  name: string;
  price: number;
  quantity: number;
}

export function applyDiscount(items: CartItem[], threshold: number, discountRate: number): number {
  let total = 0;
  for (const item of items) {
    const lineTotal = item.price * item.quantity;
    if (lineTotal < threshold) {
      total += lineTotal * (1 - discountRate);
    } else {
      total += lineTotal;
    }
  }
  return Math.round(total * 100) / 100;
}
```

```typescript
// cart-utils.test.ts
import { describe, it, expect } from "vitest";
import { applyDiscount, CartItem } from "./cart-utils.js";

describe("applyDiscount", () => {
  it("applies discount to qualifying items", () => {
    const items: CartItem[] = [
      { name: "Widget", price: 25, quantity: 2 },
      { name: "Gadget", price: 5, quantity: 1 },
    ];
    const result = applyDiscount(items, 50, 0.1);
    expect(result).toBeCloseTo(50.5, 2);
  });

  it("returns zero for empty cart", () => {
    expect(applyDiscount([], 50, 0.1)).toBe(0);
  });
});
```

### ANALYSIS

**critical** -- `cart-utils.ts:11` -- The comparison operator is inverted. The function applies the discount when `lineTotal < threshold`, but the business intent is to discount items whose line total *exceeds* the threshold. With the test data, Widget's line total is 50 (equal to threshold) so it falls into the `else` branch and receives no discount. Gadget's line total is 5 (below threshold) so it gets the discount. The test expects `50.5`, which happens to match the buggy behavior: `50 + 5 * 0.9 = 54.5` does not equal `50.5`, so the test itself encodes the wrong expected value to match the inverted logic. Both the implementation and the test are consistently wrong.

**minor** -- `cart-utils.ts:11` -- The boundary case where `lineTotal === threshold` silently falls into the non-discount branch. Whether equal-to-threshold items should receive the discount is ambiguous. The function should use `>=` or document the boundary behavior explicitly.

### VERDICT

**FAIL** -- The comparison operator at `cart-utils.ts:11` is inverted (`<` instead of `>`), applying discounts to low-value items and skipping high-value ones. The test passes only because its expected value was computed from the buggy logic.

## Example 2: Missing test coverage for critical error path

### INPUT

```typescript
// batch-processor.ts
export interface Job {
  id: string;
  payload: unknown;
}

export interface BatchResult {
  succeeded: string[];
  failed: Array<{ id: string; error: string }>;
}

export async function processBatch(
  jobs: Job[],
  handler: (payload: unknown) => Promise<void>,
): Promise<BatchResult> {
  const result: BatchResult = { succeeded: [], failed: [] };
  for (const job of jobs) {
    try {
      await handler(job.payload);
      result.succeeded.push(job.id);
    } catch (err) {
      result.failed.push({ id: job.id, error: String(err) });
    }
  }
  return result;
}
```

```typescript
// batch-processor.test.ts
import { describe, it, expect, vi } from "vitest";
import { processBatch, Job } from "./batch-processor.js";

describe("processBatch", () => {
  it("processes all jobs successfully", async () => {
    const handler = vi.fn().mockResolvedValue(undefined);
    const jobs: Job[] = [
      { id: "a", payload: { value: 1 } },
      { id: "b", payload: { value: 2 } },
    ];
    const result = await processBatch(jobs, handler);
    expect(result.succeeded).toEqual(["a", "b"]);
    expect(result.failed).toEqual([]);
    expect(handler).toHaveBeenCalledTimes(2);
  });

  it("handles empty batch", async () => {
    const handler = vi.fn();
    const result = await processBatch([], handler);
    expect(result.succeeded).toEqual([]);
    expect(result.failed).toEqual([]);
  });
});
```

### ANALYSIS

**major** -- `batch-processor.test.ts` -- The test suite covers only the happy path (all jobs succeed) and the trivial empty-batch case. There is no test for the `catch` branch at `batch-processor.ts:21`. A handler that throws should produce entries in `result.failed`, but this path is entirely untested. If the `catch` block were accidentally deleted or its push logic changed (e.g., pushing `job.id` instead of the error object), no test would fail.

**major** -- `batch-processor.ts:21` -- The `catch` block converts the error with `String(err)`. If `handler` rejects with `undefined` or `null`, `String(undefined)` produces `"undefined"` -- a valid but misleading error message. A test exercising the error path with different error types (string, Error object, undefined) would expose whether the stringification meets caller expectations.

**minor** -- `batch-processor.test.ts` -- No test verifies ordering guarantees. The `for...of` loop processes sequentially, but a future refactor to `Promise.all` would change failure semantics (fail-fast vs. collect-all). A test asserting that all jobs run even when one fails would guard against this regression.

### VERDICT

**FAIL** -- The `catch` branch at `batch-processor.ts:21` has zero test coverage. The test suite validates only the success path and empty input, leaving the entire error-handling contract unverified.

## Example 3: Happy-path-only validation that fails on adversarial input

### INPUT

```typescript
// config-loader.ts
export interface AppConfig {
  port: number;
  host: string;
  maxConnections: number;
}

export function parseConfig(raw: Record<string, string>): AppConfig {
  const port = parseInt(raw.port, 10);
  const maxConnections = parseInt(raw.maxConnections, 10);
  if (isNaN(port)) {
    throw new Error("port must be a number");
  }
  if (isNaN(maxConnections)) {
    throw new Error("maxConnections must be a number");
  }
  return {
    port,
    host: raw.host || "localhost",
    maxConnections,
  };
}
```

```typescript
// config-loader.test.ts
import { describe, it, expect } from "vitest";
import { parseConfig } from "./config-loader.js";

describe("parseConfig", () => {
  it("parses valid config", () => {
    const config = parseConfig({ port: "8080", host: "0.0.0.0", maxConnections: "100" });
    expect(config.port).toBe(8080);
    expect(config.host).toBe("0.0.0.0");
    expect(config.maxConnections).toBe(100);
  });

  it("defaults host to localhost", () => {
    const config = parseConfig({ port: "3000", host: "", maxConnections: "50" });
    expect(config.host).toBe("localhost");
  });

  it("rejects non-numeric port", () => {
    expect(() => parseConfig({ port: "abc", host: "", maxConnections: "10" })).toThrow(
      "port must be a number",
    );
  });
});
```

### ANALYSIS

**critical** -- `config-loader.ts:10` -- `parseInt("0", 10)` returns `0`, which is falsy but passes the `isNaN` check. A port of `0` or negative port (`-1`) is accepted without error. Similarly, `maxConnections` of `0` or `-999` parses successfully. The validation checks only for non-numeric input, not for out-of-range values. On most systems, binding to port `0` assigns a random ephemeral port -- likely not the caller's intent, and a silent misconfiguration.

**major** -- `config-loader.ts:10` -- `parseInt("8080abc", 10)` returns `8080` and passes the `isNaN` check. Trailing non-numeric characters are silently ignored. Input like `port: "80; DROP TABLE users"` parses as `80` with no error. The validation accepts partially numeric strings without warning.

**minor** -- `config-loader.test.ts` -- The test for non-numeric port covers only one rejection case. There is no test for `maxConnections: "abc"`, negative values, zero values, or partially numeric strings. The boundary between valid and invalid input is untested on three of four validation branches.

### VERDICT

**FAIL** -- The validation at `config-loader.ts:10-15` checks only for `NaN` but accepts zero, negative, and partially numeric values. The test suite covers only the simplest valid and invalid inputs, missing the boundary cases where `parseInt` succeeds on semantically invalid data.

## Run Data Recording

After the skill is loaded (or errors), persist run data. This section always runs regardless of outcome.

**Resolve the skill base directory** from the symlink target (the skill's source directory), not the current working directory.

### What to record

Append to `runs/data.json` (create with `{"skill":"skeptical-code-reviewer","lastRun":null,"totalRuns":0,"runs":[]}` if missing):

```json
{
  "timestamp": "{ISO-8601}",
  "outcome": "loaded|error",
  "project": "{current project directory name}",
  "sessionType": "code-review",
  "summary": "{one-line: e.g., 'loaded for code-review session'}"
}
```

Keep last 50 runs (older runs are permanently discarded). Set `lastRun` and increment `totalRuns`.

Append one line to `runs/run.log` (keep last 100 lines):
```
{timestamp} | {outcome} | {sessionType} | {summary}
```

Do not fail the skill if recording fails -- log a warning and continue.
