# Humanize Writing Skill

A Claude skill that detects AI writing patterns and rewrites text to sound human-written. Built from a real pipeline run that improved a GitHub profile README from 3/15 PASS to 15/15 PASS on AI-detection criteria.

## Quick Start

Say any of these to trigger the skill:
- "humanize this document"
- "does this sound AI-generated?"
- "make it sound human"
- "remove AI tells from this"
- `/humanize-writing path/to/file.md`

## How the Pipeline Works

```
Stage 1: EVAL WRITER ──→ Writes 12-15 detection criteria tailored to document type
Stage 2: EVAL RUNNER ──→ Scores document against criteria (PASS/FAIL with evidence)
Stage 3: CORRECTOR   ──→ Fixes every FAIL + mandatory self-review
Stage 4: RE-EVALUATOR ─→ Re-scores corrected version, shows before/after
Stage 5: EFFECTIVENESS ─→ Tracks cross-run trends (only after first run)
Stage 6: RETROSPECTIVE ─→ KEEP/CHANGE/ADD/DROP analysis (only after first run)
```

Stages 1-4 always run sequentially. Stages 5-6 run when `tests/humanize/` contains prior reports.

All agents are **stateless** — each only sees the files listed as its inputs.

## File Structure

```
~/.claude/skills/humanize-writing/
├── SKILL.md                              # Pipeline orchestration (the skill itself)
├── README.md                             # This file
├── references/
│   ├── ai-detection-patterns.md          # Known AI patterns (P1-P12, grows over time)
│   ├── document-type-profiles.md         # What "human" means per document type
│   └── correction-strategies.md          # How to fix each pattern type
├── assets/
│   └── eval-template.md                  # Format template for eval criteria
└── evals/
    └── evals.json                        # 3 test cases for skill-creator evaluation
```

## Supported Document Types

| Type | Tone Benchmark | Key Differences |
|------|---------------|-----------------|
| GitHub README | Casual-professional, first-person, personality welcome | Project motivation > feature lists |
| PRD | Professional, opinionated, decision rationale expected | Domain jargon OK, generic ACs flagged |
| Blog Post | Conversational, personal anecdotes, strong opinions | "In today's..." opening = instant FAIL |
| Email / Cover Letter | Warm professional, specific references | Perfect grammar is suspicious |
| Documentation | Clear, minimal, code-first | Uniform explanations flagged |

Profiles are in `references/document-type-profiles.md`. Add new types there.

## Known AI Detection Patterns (Seeded from Run 1)

| ID | Pattern | Severity | Threshold |
|----|---------|----------|-----------|
| P1 | Em-dash overuse | HIGH | >2 per document |
| P2 | Buzzword chains | HIGH | 3+ jargon words in one clause |
| P3 | Filler phrases | MEDIUM | Any instance of "passionate about", "leveraging", etc. |
| P4 | Bold-dash template repetition | HIGH | 3+ consecutive items with same template |
| P5 | Perfect parallel structure | MEDIUM | 4+ items with identical grammatical start |
| P6 | Connector monotony | HIGH | Same connector used 5+ times |
| P7 | Systematic emoji placement | MEDIUM | 3+ consecutive items with emoji prefix |
| P8 | Section length symmetry | LOW | All sections within ±20% length (high false-positive) |
| P9 | Press release tone | HIGH | Third-person corporate voice for personal content |
| P10 | Missing personality | MEDIUM | Zero humor, asides, or rough edges |
| P11 | Absent first-person voice | MEDIUM | No casual "I built...", "I got tired of..." |
| P12 | Vague quantifiers | LOW | "various", "multiple", "numerous" instead of numbers |

Patterns are in `references/ai-detection-patterns.md`. New patterns graduate here after 3+ observations.

## Effectiveness Tracking

After each run, the pipeline writes:
- `tests/humanize/effectiveness-{date}.md` — per-run metrics + cross-run trends
- `tests/humanize/retrospective-{date}.md` — KEEP/CHANGE/ADD/DROP proposals

### Metrics Tracked
- **FAIL count** before and after correction
- **Application rate** — applied fixes / total FAILs
- **Regressions** — criteria that went PASS→FAIL after correction
- **Self-caught issues** — problems the corrector found in its own fixes
- **Criteria effectiveness** — which criteria fail most often, which have false positives

## Continuous Improvement

### Automatic (built into the pipeline)
- Stage 5 compares this run against all prior runs
- Stage 6 proposes criteria changes and identifies new patterns
- After 3+ observations, a pattern graduates to `references/ai-detection-patterns.md`

### Manual (via skill-creator)

#### Run evals
```
/skill-creator run evals for humanize-writing
```
This runs the 3 test cases in `evals/evals.json`:
1. **github-readme-humanize** — AI-generated README with heavy tells
2. **blog-post-humanize** — AI-generated blog with cliche patterns
3. **human-written-false-positive** — Genuinely human text (should NOT be flagged)

#### Grade results
skill-creator's grader agent checks each expectation against the output.

#### A/B compare skill versions
After editing SKILL.md or references, use skill-creator's comparator agent to blind-test old vs new.

#### Optimize triggering
```
/skill-creator improve description for humanize-writing
```
Uses `improve_description.py` to tune the skill description for better trigger accuracy.

### Improvement Triggers
| Trigger | Action |
|---------|--------|
| Every 3 real-world runs | Run effectiveness analysis, check for new patterns |
| A FAIL persists after correction | Investigate: eval too strict or corrector too weak? |
| False positive on human text | Calibrate threshold or add false-positive note to criterion |
| New AI model release | Test skill against newer model outputs, update patterns |

## Origin Story

**Run 1 (2026-03-16):** GitHub profile README for Anson Lam.
- Before: 3/15 PASS (12 FAILs including 15 em-dashes, uniform bullet templates, zero personality)
- After: 15/15 PASS (all criteria passed)
- Key fixes: em-dash elimination, varied bullet structure, first-person voice, personality asides
- 12 patterns documented from this run (P1-P12)
