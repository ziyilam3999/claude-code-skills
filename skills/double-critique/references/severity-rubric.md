# Severity Rubric for Critique Findings

This rubric is read by every Critic-N in the double-critique loop. The loop's exit condition depends on the `blocks_ship` boolean on every finding, so the rubric is the single source of truth for how that flag is set.

## Severity Levels

- **CRITICAL** — Would ship-break production, break correctness, cause data loss, or leave the document in a state that misleads a downstream consumer into making the wrong decision. A CRITICAL finding is almost always `blocks_ship: true`.
- **MAJOR** — Missing AC or binary test criterion, unsupported claim, contradiction with verified source, broken cross-reference, wrong file path, wrong command syntax, or a structural gap that a competent reviewer would reject at merge time. Typically `blocks_ship: true`.
- **MINOR** — Polish, phrasing, optional strengthening, stylistic preference, non-blocking redundancy, or a small omission that does not affect correctness. **MINOR is never `blocks_ship: true`.**

## The `blocks_ship` Flag

`blocks_ship` is a boolean that every finding must carry. It is the mechanical exit condition for the critique loop:

- `blocks_ship: true` iff the finding would cause a competent reviewer to **reject the document at merge time**. If the reviewer would say "fix this before I approve," it blocks ship.
- `blocks_ship: false` otherwise — even for MAJOR findings that are informational or advisory. Polish, preference, stylistic nit, and "nice to have" are **never** `blocks_ship: true`.

Setting `blocks_ship: true` is a judgment call — but it is a judgment about merge-gate behavior, not about how interesting the finding is. When in doubt, ask: "Would a staff engineer block the PR on this?"

## Evidence Requirement (P55, P61)

Every finding must carry an `evidence` field. Acceptable values:

- A direct quote from the document with a line or section reference: `"line 42: \"<exact quoted span>\""`
- A structural reference: `"Section: Risks & Mitigations, row 3"`
- `"UNVERIFIED"` — use this when you suspect a problem but cannot point at concrete evidence in the document.

**`UNVERIFIED` findings do not count toward the blocker total.** They are logged so the user can investigate, but they cannot block the critique loop. This prevents critics from inventing blockers to justify another round.

## Novelty Flag

Every finding must carry a `novel: true|false` flag. A finding is `novel: true` if it introduces a concern not implied by the document itself — for example, a claim about codebase behavior the document does not make. Novel findings get heightened scrutiny downstream (P61).

## Required JSON Output Schema

Critics must emit findings as a JSON array inside a fenced code block. Each finding is one object:

```json
{
  "id": "F1",
  "severity": "CRITICAL",
  "blocks_ship": true,
  "novel": false,
  "evidence": "line 42: \"the API returns 200 on success\"",
  "finding": "Section 3 claims the API returns 200 on success but Section 7 lists 204 as the success code — contradiction.",
  "why_blocks_ship": "A downstream test author would implement the wrong assertion based on whichever section they read first."
}
```

Required keys: `id`, `severity`, `blocks_ship`, `novel`, `evidence`, `finding`. When `blocks_ship: true`, `why_blocks_ship` is **also required** and must be one sentence describing the merge-gate impact.

### Wrong example

```json
{
  "id": "F1",
  "severity": "MAJOR",
  "blocks_ship": true,
  "novel": false,
  "evidence": "UNVERIFIED",
  "finding": "The tone of Section 2 feels slightly unclear."
}
```

Wrong because: (1) tone/clarity is polish, not a merge-gate concern — should be MINOR with `blocks_ship: false`; (2) `blocks_ship: true` combined with `evidence: UNVERIFIED` is a contradiction — unverified findings never block; (3) no `why_blocks_ship` justification.

### Right example

```json
{
  "id": "F2",
  "severity": "MAJOR",
  "blocks_ship": true,
  "novel": false,
  "evidence": "AC-6: 'grep -A2 Stage 0 SKILL.md | grep -q max_rounds'",
  "finding": "AC-6 assumes the halt clause appears within 2 lines of a 'Stage 0' header; the plan's Step 4 places the halt clause at the end of the Stage 0 section, beyond that window.",
  "why_blocks_ship": "The AC would false-fail on a correct implementation because the grep window is narrower than the intended placement."
}
```

## Isolation Reminder

You will not see prior rounds' critiques or the running issue list. Do not attempt to coordinate with other rounds or reference prior findings. Flag only what you can evidence from the document you are reviewing right now. Each round is an independent cold read.
