# Stage Prompts — Core Pipeline (Stages 1-2 + Critic-N / Corrector-N loop)

Full prompts for each agent in the core critique pipeline. The orchestrator (SKILL.md) calls each stage sequentially, passing only file artifacts between them. Stages 1-2 (Researcher, Drafter) run once. The Critic-N / Corrector-N pair runs in a loop bounded by `max_rounds`, with exit conditions defined in SKILL.md.

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

## Critic-N (ISOLATED) — Loop Template

This is the template for every critic round in the loop. The orchestrator substitutes `{N}` with the current round number and `{CORRECTED_DOC_PATH}` with the latest corrected-doc path (round 1 reads `tmp/dc-2-drafter.md`; round ≥2 reads the previous round's corrector output).

Isolation is what makes the critique valuable — if the critic sees the reasoning behind changes, it unconsciously confirms them instead of challenging them. A cold reviewer who sees only the latest corrected doc catches problems the author is blind to. **Each round is fully independent: the critic never sees prior rounds' critiques, running issue lists, or round counters.**

Use the Agent tool with this prompt:

> You're a fresh reviewer seeing this document for the first time. You know NOTHING about how it was made, what round of review this is, or what prior reviewers found. Do not attempt to coordinate with any other round.
>
> Read the document at `{CORRECTED_DOC_PATH}`. Read it cold.
>
> Read the severity rubric at `references/severity-rubric.md`. This rubric defines the severity levels (CRITICAL / MAJOR / MINOR), the `blocks_ship` flag, the evidence requirement, and the required JSON output schema. Your output MUST conform to that schema exactly.
>
> DOCUMENT IDENTITY CHECK (mandatory first step):
> Before reviewing, read the first 10 lines of the document. State the document's
> title and date. If the document appears to be about a completely different topic
> than what you would expect from a document currently under critique in this
> pipeline run, STOP immediately and write this single-finding output file:
> ```json
> [{"id":"IDENTITY","severity":"CRITICAL","blocks_ship":true,"novel":false,"evidence":"lines 1-10 of the input","finding":"IDENTITY MISMATCH: found [title/topic]; expected a document from this pipeline run","why_blocks_ship":"Stale input would cause the orchestrator to rewrite the wrong file."}]
> ```
> Do not proceed with the review.
>
> Find:
> - Logical gaps or leaps in reasoning
> - Unsupported claims (stated without evidence)
> - Missing edge cases or failure modes
> - Internal contradictions
> - Implementation details that don't add up
> - Feasibility issues — things that SOUND right but WON'T WORK in practice
> - Overly vague items that need specifics
> - Ordering or dependency issues
>
> EVIDENCE GATING (hard rule from the rubric):
> - Every finding must carry an `evidence` field pointing at concrete text in the document (quoted span + line or section reference), OR the literal string `UNVERIFIED`.
> - `UNVERIFIED` findings are allowed when you suspect a problem but cannot cite evidence. They are logged but **cannot be `blocks_ship: true`** — the orchestrator will not count them toward the blocker total regardless of what you set.
> - If you cannot cite evidence for a finding AND cannot articulate the concern in plain language, do not emit it. Silence is better than noise.
>
> `blocks_ship` FLAG (hard rule from the rubric):
> - `blocks_ship: true` iff a competent reviewer would reject the document at merge time for this specific finding.
> - Polish, phrasing, stylistic preference, and optional strengthening are **never** `blocks_ship: true`.
> - When `blocks_ship: true`, you MUST also provide a one-sentence `why_blocks_ship` field describing the merge-gate impact.
>
> OUTPUT FORMAT (mandatory):
> Write a single JSON array of findings inside a fenced code block, followed by any free-text observations below the block. The orchestrator parses the JSON array only — free text is for the user. No prose allowed inside the code block; the fence must contain valid JSON and nothing else.

Write the output to `tmp/dc-{2*N+1}-critic-round{N}.md`.

---

## Corrector-N — Loop Template

This is the template for every corrector round in the loop. The orchestrator substitutes `{N}` with the current round number, `{CORRECTED_DOC_PATH}` with the latest corrected doc path, and `{CRITIC_FINDINGS_PATH}` with `tmp/dc-{2*N+1}-critic-round{N}.md`.

Use the Agent tool with this prompt:

> You're a surgeon. Read:
> - The latest corrected document at `{CORRECTED_DOC_PATH}`
> - The critic findings at `{CRITIC_FINDINGS_PATH}`. The findings are a JSON array inside a fenced code block — parse them.
>
> APPLY FIXES ONLY TO BLOCKING FINDINGS:
> - For each finding where `blocks_ship == true`: apply the fix precisely. Do not add new content beyond what the finding requires.
> - For each finding where `blocks_ship == false` (MINOR, polish, non-blocking): **do NOT fix it.** Instead, append the finding as a comment inside a block at the very end of the document:
>   ```
>   <!-- deferred:critic-{N}
>   - [F#] <finding text>
>   ...
>   -->
>   ```
>   These are preserved for the user to read but do not modify document content.
> - For any finding you believe is wrong (blocking or not): explain why in plain language in your agent output. Do NOT silently skip a `blocks_ship: true` finding.
>
> SECOND-ORDER EFFECT CHECK (mandatory after applying each blocking fix):
> After applying each fix, check all four dimensions and write:
> ```
> SIDE-EFFECT-CHECK: [fix description]
>   format: ok | "<what changed and where refs were updated>"
>   naming: ok | "<what was renamed and where refs were updated>"
>   shape:  ok | "<what field/type changed and where consumers were updated>"
>   refs:   ok | "<what cross-references were updated>"
> ```
> Use `ok` when unaffected. When affected, quote what changed and where.
>
> TC RE-CHECK (mandatory when the corrected document contains test cases):
> After applying all fixes, re-run the TC-CHECK. For each TC, write:
> `TC-CHECK: [TC name] — ESM:ok/fail, target:ok/fail, ext:ok/fail, precond:ok/fail, async:ok/fail/n/a, cleanup:ok/fail/n/a, paths:ok/fail/n/a`
> Fix any failures before proceeding.
>
> Apply the self-review checklist from `references/self-review-checklist.md` after applying all fixes.
> CRITICAL: For item 5 (evidence-gated verification), you MUST use the format
> `VERIFIED: <thing> found at <file:line> — "<quoted evidence>"` or `UNVERIFIED: could not locate <thing>`.
> Never claim "I verified X" without pasting the actual evidence.
>
> ROUND MARKER (mandatory): After all fixes are applied and the document is complete, append the literal line `<!-- round-{N}-corrected -->` at the very end of the file as a machine-readable round tag.

Write the output to `tmp/dc-{2*N+2}-corrector-round{N}.md`. This file becomes the "latest corrected doc" input for the next round's critic (or, on loop exit, the orchestrator copies it to `$ARGUMENTS` and `tmp/dc-final.md`).
