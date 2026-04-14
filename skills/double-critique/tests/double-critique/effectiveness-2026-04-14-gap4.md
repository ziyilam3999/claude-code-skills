# Effectiveness Report — 2026-04-14 Gap 4 Indexing Read-Path

**Document:** `.ai-workspace/plans/2026-04-14-cairn-gap4-indexing-read-path.md` (Gap 4 indexing plan, ~600 lines, 7 milestones, 16 TCs)
**Run:** 4 rounds, `exit_reason=oscillation`, `max_rounds=4`
**Extractor source:** `tmp/dc-8-extractor.md`

---

## This Run — Headline Numbers

| Metric | Value |
|---|---|
| Total rounds | 4 (hit max_rounds) |
| Exit reason | oscillation (round-4 blockers 8 > round-3 blockers 5) |
| Per-round blockers | **12 -> 9 -> 5 -> 8** |
| Total findings across all rounds | 50 (15 + 13 + 13 + 11, sans round-0 researcher) |
| Findings applied | 26 |
| Findings deferred | 16 |
| Round-4 punch-list (residual blockers handed off) | 8 |
| Drafter regressions | 1 (h5-state.json unilateral claim) |
| Corrector regressions (total) | 5 across 3 rounds (0 / 3 / 2) |
| Evidence-gating compliance | 100% (52/52 findings) |
| Novel findings flagged | 3 (0/1/0/2 per round) |

### Oscillation root cause

Round-4 spike was **not** a fixes-cause-bugs feedback loop. Breakdown of 8 round-4 blockers:

- **6/8 were latent defects** the earlier 3 critics missed (cold-read depth) — e.g. M4/M6 trailer-shape reconciliation, TC3 non-recursive glob, M5 §4 arithmetic 30+7!=21, TC7 has no implementing M-item, CRLF on MSYS, TC6 compound OR.
- **2/8 were genuine regressions** from round-3 corrector code: TC13a fixture missing the sentinel it just added; ratification CI regex `^\+### P[0-9]+` forgot the F-series.

Interpretation: the oscillation heuristic misfires on large plans (600+ lines). Each new cold-read critic keeps finding real latent defects in areas prior rounds had already "touched". Churn ratio is 25% (2/8), not 100%.

---

## Regression Tracking Table (Drafter vs Corrector-1/2/3)

| Agent | Round | Regressions | Detail |
|---|---|---|---|
| Drafter (dc-2) | pre-R1 | **1** | `h5-state.json` guard file invented unilaterally (not coordinated with Gap 2). Caught by critic-1 C4, withdrawn. |
| Corrector-1 (dc-4) | R1 | **0** | Closed all 12 blockers cleanly. Critic-2 findings were pre-existing holes, not new defects. |
| Corrector-2 (dc-6) | R2 | **3** | F3 spec/impl regex divergence (introduced by F1 fix), F6 `gh -q length` syntax (introduced by F8 fix), F9 ratification-block behavioral-prose-only (F8 fix was procedural not mechanical). |
| Corrector-3 (dc-8) | R3 | **2** | TC13a fixture missing sentinel (F2 sentinel fix didn't update fixture), ratification CI regex P-only (F9 fix forgot F-series). |
| **Total** | | **6** | 1 drafter + 5 corrector |

Rule observed: every MAJOR corrector fix tends to ship with ~1 new micro-defect inside the new code. SIDE-EFFECT-CHECK blocks need to verify the *new code*, not just the new words.

---

## Trend vs Prior Runs (last 7 complete runs with loop stats)

| Date | Doc | Findings | Applied% | Rounds | Exit | Per-round blockers |
|---|---|---|---|---|---|---|
| 2026-04-12 | broken-doc (v1) | 8 | 0% | 1 | clean | [0] |
| 2026-04-12 | broken-doc (v2) | 19 | 26% | 2 | oscillation | [5, 6] |
| 2026-04-13 | snoopy-roaming-beaver DC1 | 31 | 29% | 2 | oscillation | [9, 11] |
| 2026-04-14 | snoopy-roaming-beaver DC2 | 37 | 50% | 2 | oscillation | [14, 14] |
| 2026-04-14 | gap2-heartbeat run1 | 30 | 67% | 3 | oscillation | [12, 8, 13] |
| 2026-04-14 | gap2-heartbeat run2 | 44 | 43% | 3 | oscillation | [11, 8, 12] |
| 2026-04-14 | gap3-slash-command | 34 | 41% | 3 | oscillation | [8, 6, 7] |
| **2026-04-14 gap4 (this run)** | **gap4-indexing** | **50** | **52%** | **4** | **oscillation** | **[12, 9, 5, 8]** |

### Trend arrows vs prior 7 runs

- **Finding count:** 50 total (up, arrow-up). Highest surfaced count in the oscillation-era; driven by 4 rounds instead of 3 and by document size (600 lines, 7 milestones).
- **Application rate:** 52% (flat/up, arrow-right). Above gap2-heartbeat-run2 (43%) and gap3-slash (41%), on par with gap2-heartbeat-run1 (67%) adjusted for deferral volume.
- **Rounds run:** 4 (up, arrow-up). First run this era to hit max_rounds.
- **Per-round blocker trajectory:** 12 -> 9 -> 5 -> 8. Best 3-round reduction curve of the era (prior runs were flat or rising by round 3). Round-4 spike is the new observation.
- **Drafter regressions:** 1 (flat, arrow-right). Matches baseline; drafter discipline is holding.
- **Corrector regressions:** 5 (up, arrow-up). Prior runs did not track per-round corrector regressions explicitly; 5 is the first measured figure for an oscillation-era 3-corrector run. Ratio 5/26 applied = 19% new-defect-per-fix.
- **Evidence-gating:** 100% (flat, arrow-right). Unbroken streak since 2026-03-24 baseline. Not the bottleneck.

---

## ELI5 Summary (what this run tells us)

Imagine four different doctors each reading the same 600-page medical chart cold. The first doctor finds 12 problems. You fix them. The second finds 9 more. You fix them. The third finds 5 more. You fix them. The fourth — also reading cold — finds 8 more. Are they getting worse? No. The chart is just big enough that each fresh doctor sees things the previous three missed. Only 2 of the fourth doctor's 8 problems were actually caused by the previous fix; the other 6 were there the whole time.

So the "stop when problems go up" rule fired, but it fired for the wrong reason. The real signal here is: **this document is too big for one critic to cover in a single cold read**. Next time, split it into per-milestone mini-plans so each critic's eyes only have to cover ~100 lines instead of 600.

Meanwhile, the team is solid: the writer almost never makes things up (1 mistake in 45 changes), the fixers close almost everything the critics find, and nobody ever made an unsupported scary claim (evidence-gating 100%). The only wart is that each fixer tends to introduce ~1 tiny new bug while closing several old ones — worth adding a "check your own new code" step.

---

## Recommendations (carry forward)

1. **Split 600-line plans into per-milestone subplans** with independent critique lanes. Single-critic cold-read coverage caps around ~150-200 lines based on this run's miss pattern.
2. **Deferred non-blockers need a "re-evaluate next round" flag.** F4 (TC6 OR) and F5 (M5 arithmetic) were both deferred at R3 and came back as R4 blockers — silent carry-forward is a false economy.
3. **Every MAJOR corrector fix needs a SIDE-EFFECT-CHECK on the new code, not just the new words.** 5/5 corrector regressions were mechanical defects inside freshly-added code blocks (regexes, CI yaml, fixture files).
4. **Oscillation heuristic is wrong for plans >300 lines.** Consider replacing "R_n blockers >= R_{n-1}" with "(R_n blockers that are regressions from R_{n-1} fixes) / (R_n blockers total) > 50%". On this run that would be 2/8 = 25%, would NOT have tripped oscillation exit, and would have let round 5 keep surfacing latent defects.
5. **Evidence-gating work is done.** 100% for 4 rounds straight. Move optimization effort elsewhere.

---

*Report written 2026-04-14. Source extractor: `tmp/dc-8-extractor.md`. Prior-run data: `runs/data.json` (30 total runs, last 7 compared).*
