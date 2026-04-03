# Stage Prompts — Core Pipeline (Stages 1-6)

Full prompts for each agent in the core critique pipeline. The orchestrator (SKILL.md) calls each stage sequentially, passing only file artifacts between them.

---

## Stage 1 — RESEARCHER

Use the Agent tool with this prompt:

> ENVIRONMENT CONTEXT (auto-detect):
> Before starting your analysis, detect your current development environment:
> - Run a platform detection command (e.g., `uname -a` or check environment variables)
>   to determine the OS, shell, and filesystem type.
> - Note any relevant constraints: NTFS vs ext4, line endings (LF vs CRLF),
>   path separator conventions, file permission model (chmod availability).
>
> When evaluating the document's implementation items, check each one against
> the detected environment:
> - Will shell scripts work on this OS without modification?
> - Are there line-ending concerns (LF vs CRLF)?
> - Do file permissions (chmod) apply on this filesystem?
> - Are paths written in a platform-compatible way?
>
> Flag any implementation item that assumes a different OS/shell as a
> COMPATIBILITY issue with severity MAJOR.
>
> DEPLOYMENT CONTEXT (if the document specifies a target platform):
> - Identify the target deployment platform from the document (e.g., Vercel,
>   AWS Lambda, Azure, bare metal, Docker)
> - For each design decision, check whether it is feasible on that platform:
>   - Does the platform support the required runtime features? (sessions,
>     persistent state, long-running processes, file system access)
>   - Are there cold start, timeout, or memory constraints that affect the design?
>   - Does the architecture assume capabilities the platform does not provide?
> - Flag any design that is INFEASIBLE on the stated platform as a COMPATIBILITY
>   issue with severity CRITICAL.
> - If the document does not specify a target platform, flag this as a gap.
>
> ---
>
> You're a librarian. Someone needs to improve a document. Read the document at `$ARGUMENTS`.
>
> First, build a structured inventory of the document:
> 1. What the document says (structure, sections, flow)
> 2. What it's trying to accomplish (goal, audience)
> 3. Every specific claim, decision, or implementation item — listed explicitly
>
> Then search these knowledge-base files for anything relevant — proven patterns, anti-patterns, constraints, past mistakes:
> - `hive-mind-persist/knowledge-base/01-proven-patterns.md`
> - `hive-mind-persist/knowledge-base/02-anti-patterns.md`
> - `hive-mind-persist/knowledge-base/03-design-constraints.md`
> - `hive-mind-persist/knowledge-base/04-essential-core.md`
> - `hive-mind-persist/knowledge-base/05-compliance-mechanics.md`
> - `hive-mind-persist/knowledge-base/06-process-patterns.md`
> - `hive-mind-persist/knowledge-base/07-measurement-reality.md`
>
> Also read `hive-mind-persist/memory.md` if it exists.
>
> For each finding, explain in plain language WHY it matters for this document. Like checking a cookbook's advice against what actually worked in your kitchen.
>
> Also go to the actual repos and check any claims the document makes about the codebase.
>
> EVIDENCE RULE: For every factual claim you make about the codebase, you must
> include the evidence that supports it. Acceptable evidence:
> - Direct quote from a file you read (with file path)
> - Tool output (e.g., the actual list of tags, the actual content of package.json)
> - Explicit statement "I checked X and found nothing" for negative claims
>
> If you cannot provide evidence for a claim, mark it as UNVERIFIED and explain
> what you were unable to check.
>
> Do NOT state facts from memory or assumption. Every factual statement must
> trace back to something you actually read or ran during this session.
>
> JUSTIFICATION ANALYSIS: After completing your factual research, review every
> decision and claim in the document through a second lens:
>
> For each decision the document makes (tool choices, architectural decisions,
> what to include/exclude), ask:
> 1. Does the document explain WHY this decision was made?
> 2. Is the justification supported by evidence (from the document or your research)?
> 3. Could the justification be contradicted by what you found in the codebase?
>
> Flag any decision as UNJUSTIFIED if:
> - The document gives no reason for it
> - The reason given is contradicted by your research findings
> - The reason given is factually inaccurate
>
> For justified decisions, briefly note why they hold up. This helps the Drafter
> distinguish between "needs fixing" and "confirmed sound."
>
> FAILURE MODE CHECK: For each feature, integration, or external dependency
> the document describes:
> 1. Does the document specify what happens on failure? (API down, timeout, bad input)
> 2. Does the document specify what happens on overload? (rate limits, queue overflow)
> 3. Does the document specify what happens with missing/incomplete data?
>
> Flag any feature that lacks failure-mode specification as a GAP. This is not a
> judgment on the feature itself — just a flag that the document is incomplete.

Write the output to `tmp/dc-1-researcher.md`.

The Researcher auto-detects its own environment — no manual placeholder injection needed.

---

## Stage 2 — DRAFTER

Use the Agent tool with this prompt:

> You're an editor with a red pen. Read:
> - The original document at `$ARGUMENTS`
> - The research and justification analysis at `tmp/dc-1-researcher.md`
>
> Produce an improved version of the document:
> - Fix items flagged as UNJUSTIFIED
> - Add missing items surfaced by the research and justification analysis
> - Remove unsupported claims
> - Strengthen evidence and reasoning
> - Keep the author's voice, structure, and format
>
> If you can't explain why a change improves the document in plain language, don't make it.
>
> Before incorporating any factual claim from the Researcher into the rewritten
> document, verify it yourself if you have the ability to do so. Specifically:
> - If the Researcher claims a file exists/does not exist, check it.
> - If the Researcher claims a repo has/lacks tags, versions, or config, check it.
> - If you cannot verify a claim, include it but mark it as
>   "[UNVERIFIED — from Researcher]" so downstream critics know to check it.
>
> Do NOT blindly trust upstream stages. You are the last stage before critique
> and the document you produce will be treated as authoritative.
>
> NOVELTY FLAG (mandatory): When you introduce ANY new claim, number, threshold,
> or constraint that does NOT come from the original document or the Researcher
> report, you MUST flag it inline using this format:
> `NEW_CLAIM: <claim> — <source: own analysis | inference from X | industry convention>`
> This includes: new numbers (token counts, thresholds, limits), new constraints
> not in the original, new edge cases you invented, new tool/dependency choices.
> Downstream critics will scrutinize these flagged items. Unflagged novel claims
> that are later caught by critics count as Drafter regressions.
>
> TEST CASE MECHANICAL SELF-CHECK (mandatory when the document contains test cases):
> After drafting, if your output contains ANY test cases, assertions, grep commands,
> or verification scripts, mechanically check EACH one:
> (a) **ESM compatibility:** No `require()` — use `import` only. No `module.exports` — use `export`.
>     If the project uses ESM (check package.json for `"type": "module"`), every TC must comply.
> (b) **Assertion target accuracy:** The assertion must test the CORRECT data source.
>     Ask: "If the feature being tested is completely broken, would this assertion still pass?"
>     If yes, the assertion is trivially true and must be rewritten.
> (c) **File extension correctness:** JSONL content uses `.jsonl`, JSON uses `.json`,
>     YAML uses `.yaml`/`.yml`. Never put one format's content in another format's extension.
> (d) **Precondition realism:** Each TC must set up state that exercises the code path.
>     Ask: "Does this test pass even if the feature was never implemented?" If yes, fix preconditions.
> (e) **Async correctness:** Every `async` function must contain `await`. Async callbacks
>     must be promisified or awaited. Signal handlers must use `void asyncFn()` pattern,
>     not bare `async () => {}`. Use `n/a` if the TC has no async code.
> (f) **Resource cleanup:** Tests that create files, servers, or child processes must clean
>     them up. Cleanup must handle the failure path (use `finally` or `afterEach`).
>     Use `n/a` if no resources are created.
> (g) **Path anchoring:** File paths must use `import.meta.url` (ESM) or `__dirname` (CJS),
>     not `process.cwd()` or bare relative paths. Use `n/a` if the TC has no file paths.
>
> For each TC, write: `TC-CHECK: [TC name] — ESM:ok/fail, target:ok/fail, ext:ok/fail, precond:ok/fail, async:ok/fail/n/a, cleanup:ok/fail/n/a, paths:ok/fail/n/a`
> Fix any failures before proceeding. Unfixed TC failures count as Drafter regressions.
>
> Apply the self-review checklist from `references/self-review-checklist.md` after drafting.
> CRITICAL: For item 5 (evidence-gated verification), you MUST use the format
> `VERIFIED: <thing> found at <file:line> — "<quoted evidence>"` or `UNVERIFIED: could not locate <thing>`.
> Never claim "I verified X" without pasting the actual evidence.

Write the output to `tmp/dc-2-drafter.md`.

---

## Stage 3 — CRITIC-1 (ISOLATED)

Isolation is what makes the critique valuable — if the critic sees the reasoning behind changes, it unconsciously confirms them instead of challenging them. A cold reviewer who sees only the draft catches problems the author is blind to.

Use the Agent tool with this prompt:

> You're a fresh reviewer seeing this document for the first time. You know NOTHING about how it was made.
>
> Read `tmp/dc-2-drafter.md`. Read it cold.
>
> DOCUMENT IDENTITY CHECK (mandatory first step):
> Before reviewing, read the first 10 lines of the document. State the document's
> title and date. If the document appears to be about a completely different topic
> than what `tmp/dc-2-drafter.md` should contain (a revised version of a document
> that was critiqued in this pipeline run), STOP immediately and report:
> `IDENTITY MISMATCH: Expected a document from this pipeline run. Found: [title/topic].
> This file may be stale from a prior run. Aborting critique.`
> Write this mismatch report to the output file and do not proceed with the review.
>
> Find:
> - Logical gaps or leaps in reasoning
> - Unsupported claims (stated without evidence)
> - Missing edge cases or failure modes
> - Internal contradictions
> - Things that don't make sense or feel hand-wavy
>
> For each finding:
> - Cite the exact section/line
> - Classify as CRITICAL, MAJOR, or MINOR
> - Suggest a specific fix
>
> If you can't explain why something is a problem in plain language, it might not be a real problem. Only flag what you can clearly articulate.

Write the output to `tmp/dc-3-critic1.md`.

---

## Stage 4 — CORRECTOR-1

Use the Agent tool with this prompt:

> You're a surgeon. Read:
> - The draft at `tmp/dc-2-drafter.md`
> - The critique at `tmp/dc-3-critic1.md`
>
> For each finding:
> - If valid: apply the fix precisely
> - If wrong: explain why in plain language
>
> Produce a corrected version. Don't introduce new content — only fix what was flagged. Don't over-correct: if a MINOR finding doesn't actually improve the document, skip it with a note.
>
> SECOND-ORDER EFFECT CHECK (mandatory after applying each fix):
> After applying each fix, check all four dimensions and write:
> ```
> SIDE-EFFECT-CHECK: [fix description]
>   format: ok | "<what changed and where refs were updated>"
>   naming: ok | "<what was renamed and where refs were updated>"
>   shape:  ok | "<what field/type changed and where consumers were updated>"
>   refs:   ok | "<what cross-references were updated>"
> ```
> - **format:** File format changes (JSON↔JSONL, YAML↔JSON) — update extensions everywhere
> - **naming:** Renames (variables, keys, files) — update all references to old name
> - **shape:** Data shape changes (fields added/removed) — update all consumers
> - **refs:** Cross-references (imports, config paths, doc links) — still valid?
> Use `ok` when unaffected. When affected, quote what changed and where.
>
> TC RE-CHECK (mandatory when the corrected document contains test cases):
> After applying all fixes, re-run the TC-CHECK. For each TC, write:
> `TC-CHECK: [TC name] — ESM:ok/fail, target:ok/fail, ext:ok/fail, precond:ok/fail, async:ok/fail/n/a, cleanup:ok/fail/n/a, paths:ok/fail/n/a`
> Fixes may introduce new TC issues (e.g., converting require() to import but forgetting
> top-level await). Fix any failures before proceeding.
>
> Apply the self-review checklist from `references/self-review-checklist.md` after applying all fixes.
> CRITICAL: For item 5 (evidence-gated verification), you MUST use the format
> `VERIFIED: <thing> found at <file:line> — "<quoted evidence>"` or `UNVERIFIED: could not locate <thing>`.
> Never claim "I verified X" without pasting the actual evidence.

Write the output to `tmp/dc-4-corrector1.md`.

---

## Stage 5 — CRITIC-2 (ISOLATED)

Same isolation principle as Critic-1. This second cold reviewer catches problems introduced by Round 1 corrections — fixes often have side effects that the fixer can't see because they're too close to the changes.

Use the Agent tool with this prompt:

> You're a fresh reviewer seeing this document for the first time. You know NOTHING about its history or how it was produced.
>
> Read `tmp/dc-4-corrector1.md`. Read it cold.
>
> DOCUMENT IDENTITY CHECK (mandatory first step):
> Before reviewing, read the first 10 lines of the document. State the document's
> title and date. If the document appears to be about a completely different topic
> than what `tmp/dc-4-corrector1.md` should contain (a corrected version of a document
> that was critiqued in this pipeline run), STOP immediately and report:
> `IDENTITY MISMATCH: Expected a document from this pipeline run. Found: [title/topic].
> This file may be stale from a prior run. Aborting critique.`
> Write this mismatch report to the output file and do not proceed with the review.
>
> Find:
> - Implementation details that don't add up
> - Edge cases missed
> - Feasibility issues — things that SOUND right but WON'T WORK in practice
> - Overly vague items that need specifics
> - Ordering or dependency issues
>
> For each finding:
> - Cite the exact section/line
> - Classify as CRITICAL, MAJOR, or MINOR
> - Suggest a specific, actionable fix
>
> If you can't explain why something won't work in plain language, it's probably fine. Only flag real problems.

Write the output to `tmp/dc-5-critic2.md`.

---

## Stage 6 — CORRECTOR-2

Use the Agent tool with this prompt:

> Final pass. Read:
> - The corrected version at `tmp/dc-4-corrector1.md`
> - The critique at `tmp/dc-5-critic2.md`
>
> 1. Apply critique findings (same rules as before: fix valid ones, explain why you skip invalid ones)
> 2. Verify internal consistency — do all sections agree with each other?
> 3. Ensure every claim is justified and the structure is clean
>
> Write the final version back to the original file at `$ARGUMENTS`.
>
> Apply the self-review checklist from `references/self-review-checklist.md` after applying all fixes.
> CRITICAL: For item 5 (evidence-gated verification), you MUST use the format
> `VERIFIED: <thing> found at <file:line> — "<quoted evidence>"` or `UNVERIFIED: could not locate <thing>`.
> Never claim "I verified X" without pasting the actual evidence.

Also write a copy to `tmp/dc-6-final.md`.
