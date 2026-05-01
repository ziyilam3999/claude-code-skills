---
name: ship
description: >
  Full git shipping pipeline: commit, branch, push, create PR, wait for CI,
  self-review loop (with bug fix iterations), and merge. Use when the user says
  "/ship", "ship it", "ship this", "commit and merge", "push and merge",
  "create PR and merge", or wants to go from working changes to a merged PR
  in one command. Do NOT use for simple git operations like just committing
  or just pushing -- this is the full end-to-end pipeline.
---

# Ship Pipeline

Execute the full git shipping pipeline on the current working directory. If `$ARGUMENTS` is provided, use it as a hint for the commit message.

## Pipeline Overview

| Stage | Name | Action | Abort condition |
|-------|------|--------|-----------------|
| 0 | Pre-flight | Check for changes, branch, gh auth | Nothing to commit |
| 1 | Branch | Create feature branch if on master | -- |
| 2 | Commit | Stage files and commit | -- |
| 3 | Push + PR | Push and create PR via gh | -- |
| 4 | CI Wait | Poll `gh pr checks` up to 10 min | CI failure |
| 5 | Self-review | Stateless reviewer loop (max 5) | 5 iterations exhausted |
| 6 | Merge | Squash merge via gh | Merge conflict |
| 7 | Release | Version bump, changelog, tag, GitHub Release | -- |
| 8 | Cleanup | Switch to master, pull, delete branch | -- |
| 9 | Record | Persist run data to `runs/data.json` and `runs/run.log` | -- |
| 10 | Card | Emit working-memory decision card (success runs only) | -- |

Print a status line before each stage:
```
[SHIP {N}/10] {description}...
```

**Stage 9 is NOT optional.** Prior versions of this SKILL.md placed Run Data Recording as an appendix below the main stages, which made it structurally easy to skip — operators executing the pipeline manually would finish Stage 8 Cleanup, feel the work was done, and exit before reaching the recording. That silent-skip failure mode was caught by a 2026-04-15 `/skill-evolve improve` pass after three consecutive `/ship` invocations in one session left no `data.json` trace. Promoting recording to a numbered stage with its own `[SHIP 9/10]` status line makes the final step visible in the pipeline progression. The recording itself remains best-effort (do not fail the pipeline on recording errors — log a warning and continue) but the **decision to record** is now unconditional.

---

## Stage 0 -- PRE-FLIGHT

Run these checks. Abort with a clear message if any fail.

```bash
git status --porcelain        # empty = nothing to ship
git branch --show-current     # detect master vs feature branch
gh auth status                # verify gh is authenticated
```

- If `git status --porcelain` is empty, print "Nothing to ship." and stop (still record this as an aborted run — see Run Data Recording).
- Store the current branch name for later decisions.
- Capture `run_start_time` as the current ISO-8601 timestamp. Initialize an in-memory run record to accumulate metrics throughout the pipeline.

## Stage 0.5 -- PLAN-REFRESH GATE (forge-harness only)

**Applies only when `.forge/` directory exists in the repo root.** Non-forge repos skip this stage entirely. This gate ensures every PR in a forge-harness-style repo carries a plan-refresh signal indicating whether `forge_plan(documentTier: "update")` has been invoked against the current state. Enforced by Q0/L1 of the post-v0.20.1 execution plan (`.ai-workspace/plans/2026-04-12-next-execution-plan.md`).

1. **Applicability check:** `test -d .forge` — if absent, record `planRefreshGate: "skipped-no-forge"` in the run record and skip to Stage 1.

2. **Marker read (server-side, NEVER working tree — immune to shallow clones and `git clean`):**
   ```bash
   MSYS_NO_PATHCONV=1 git show origin/master:.forge/.plan-refresh-initialized 2>/dev/null
   MARKER_EXIT=$?
   ```
   The `MSYS_NO_PATHCONV=1` prefix is required on Windows Git Bash (MSYS2), which otherwise mangles the `ref:path` colon into a semicolon and breaks the command. The env var has no effect on Linux/Mac. See issue #227.
   - `MARKER_EXIT != 0` → marker absent on master → **bootstrap/empty-history case** → set `PLAN_REFRESH_LINE="plan-refresh: baseline"` and proceed. Record `planRefreshMarkerPresent: false`.
   - `MARKER_EXIT == 0` → marker present on master → require an explicit non-`baseline` line (see step 3). Emit `baseline` is **forbidden** in this branch. Record `planRefreshMarkerPresent: true`.

3. **Line value determination when marker is present:**
   - If `$ARGUMENTS` contains a literal `plan-refresh:` token (e.g., `/ship plan-refresh: 3 items`), extract and use that line verbatim.
   - Otherwise, check the current session for a recent `forge_plan(documentTier: "update")` invocation in the current working session — if present, derive the line from its outcome (`no-op` if the update produced zero rewrites, `<N> items` if it rewrote N items, `error: <reason>` if it errored).
   - If neither source is available, **abort** with: `"Plan-refresh gate: no signal available. The marker .forge/.plan-refresh-initialized is present on origin/master, meaning forge_plan(update) has run at least once. Run forge_plan(documentTier: 'update') again in this session, or pass the line explicitly via '/ship plan-refresh: <form>'. Valid forms: no-op, <N> items, error: <reason>."`

4. **Accepted line forms (exact literal match enforced in Stage 6):**
   - `plan-refresh: no-op`
   - `plan-refresh: <N> items` (where `<N>` is an integer ≥ 1)
   - `plan-refresh: baseline` (only when marker is absent on master)
   - `plan-refresh: error: <reason>` (requires `plan-refresh-override: <reason>`)
   - `plan-refresh: error: halted-blocking-note:<noteId>` (added by Q0/L2 A1.2 amendment 2026-04-12; also requires override)

5. **Error-form override handling:** if `PLAN_REFRESH_LINE` starts with `plan-refresh: error:`, the gate requires a matching `plan-refresh-override: <reason>` line in either `$ARGUMENTS` or the PR body. If `$ARGUMENTS` contains a literal `plan-refresh-override:` token, extract and set `PLAN_REFRESH_OVERRIDE_LINE` accordingly. If neither `$ARGUMENTS` nor any existing PR body contains the override line, **abort** with: `"Plan-refresh errored (<reason>). Merge is blocked by default. To proceed, supply 'plan-refresh-override: <reason>' via '/ship' arguments or add it to the PR body."`

6. **Validation:** the computed `PLAN_REFRESH_LINE` must match the regex `^plan-refresh: (no-op|[1-9][0-9]* items|baseline|error: .+)$` — if not, abort with: `"Plan-refresh line malformed: '<value>'. Expected one of: 'plan-refresh: no-op', 'plan-refresh: <N> items' (N ≥ 1), 'plan-refresh: baseline', 'plan-refresh: error: <reason>'."` Note: `0 items` is deliberately rejected — use `no-op` for the zero case. See issue #217 (n=2 graduation).

7. **Store** `PLAN_REFRESH_LINE` (and `PLAN_REFRESH_OVERRIDE_LINE` if applicable) for use in Stage 3 (body composition) and Stage 6 (pre-merge re-verification).

8. **Record** in the run record:
   - `planRefreshGate: "passed"` (or `"skipped-no-forge"` per step 1, or `"aborted-no-signal"` / `"aborted-missing-override"` / `"aborted-malformed"` on the respective abort paths)
   - `planRefreshLine: "<value>"`
   - `planRefreshMarkerPresent: true|false`
   - `planRefreshOverride: "<value or null>"`

## Stage 1 -- BRANCH

**On master/main:** Analyze the diff to derive a branch name with a conventional prefix:
- `feat/` for new features
- `fix/` for bug fixes
- `chore/` for maintenance, config, docs

Create the branch: `git checkout -b {prefix}/{slug}`

**On feature branch:** Skip. Log "Already on branch {name}".

## Stage 2 -- COMMIT

1. Stage relevant files with `git add` (list specific files, never use `-A` or `.`)
2. Craft a conventional commit message from the diff. If `$ARGUMENTS` is provided, use it as a hint.
3. Commit using a HEREDOC for the message, including `Co-Authored-By` trailer.

## Stage 3 -- PUSH + PR

1. `git push -u origin {branch}`
2. Check if a PR already exists:
   ```bash
   gh pr view --json number,url,body 2>/dev/null
   ```
   - **Exists:** Log the URL. **Plan-refresh gate check (added by Q0/L1):** if Stage 0.5 ran (forge-harness repo) and `PLAN_REFRESH_LINE` is set, verify the existing body contains a line matching `^plan-refresh: (no-op|[1-9][0-9]* items|baseline|error: .+)$`. If absent, append `PLAN_REFRESH_LINE` (and `PLAN_REFRESH_OVERRIDE_LINE` if set) to the body. Compose the new body with real newlines via `printf` (bash double-quoted `\n` is literal backslash-n and produces a broken body — see issue #218):
     ```bash
     if [ -n "$PLAN_REFRESH_OVERRIDE_LINE" ]; then
       NEW_BODY=$(printf '%s\n\n---\n%s\n%s' "$EXISTING_BODY" "$PLAN_REFRESH_LINE" "$PLAN_REFRESH_OVERRIDE_LINE")
     else
       NEW_BODY=$(printf '%s\n\n---\n%s' "$EXISTING_BODY" "$PLAN_REFRESH_LINE")
     fi
     gh pr edit {pr-number} --body "$NEW_BODY"
     ```
     Record `planRefreshLineInjected: true`. If the line is already present, skip the edit and record `planRefreshLineInjected: false`.
   - **Does not exist:** Create via `gh pr create --title "..." --body "..."` with a summary and test plan. **Plan-refresh gate check (added by Q0/L1):** if Stage 0.5 ran, the PR body MUST include `PLAN_REFRESH_LINE` as a trailer line (after the summary and test plan), separated from the rest of the body by a `---` horizontal rule. If `PLAN_REFRESH_OVERRIDE_LINE` is set, include it on the line immediately after `PLAN_REFRESH_LINE`. Body template:
     ```
     ## Summary
     ...

     ## Test plan
     ...

     ---
     {PLAN_REFRESH_LINE}
     [{PLAN_REFRESH_OVERRIDE_LINE if set}]
     ```
     Record `planRefreshLineEmbedded: true` in the run record.
3. Store the PR number for subsequent stages.

## Stage 4 -- CI WAIT

Poll CI checks every 30 seconds, up to 10 minutes:

```bash
gh pr checks {pr-number}
```

- **All pass:** Record `ciOutcome: "pass"`. Proceed to Stage 5.
- **Any fail:**
  1. Parse failing check names from `gh pr checks` output.
  2. **If any failing check name contains `code-review`** (case-insensitive) AND this is the **first** retry attempt:
     a. Print: `"Code-review CI failed — checking OAuth token freshness..."`
     b. Read `$USERPROFILE/.claude/.credentials.json`, extract `claudeAiOauth.expiresAt` (unix ms).
     c. If token is **expired or expiring within 30 minutes**:
        - Look for the OAuth token sync script at `~/.claude/skills/housekeep/tools/sync-oauth-token.sh` (resolved via the housekeep skill symlink, not the current repo). If the script exists, run it. If not found, skip sync and abort as normal.
        - If sync succeeds: re-trigger with `gh run rerun --failed -R {owner/repo}` on the failing run, record `ciOauthSynced: true` and `ciRetried: true`, reset CI poll timer, **resume polling** (fresh 10-min timeout).
        - If sync fails: report the sync error and abort.
     d. If token is **fresh** (>30 min remaining): not a token issue — abort as normal.
  3. **Otherwise** (non-code-review failure, or second attempt after retry): Record `ciOutcome: "fail"`. Report failing check names and log URLs. **Abort** — do not auto-fix CI config issues.
- **No checks configured** (empty output): Record `ciOutcome: "none"`. Skip, proceed to Stage 5.
- **Timeout (10 min):** Record `ciOutcome: "timeout"`. Report current status and ask the user whether to continue or abort.

Record `ciWaitSeconds` as the elapsed time from the first poll to resolution.

## Stage 5 -- SELF-REVIEW LOOP

**Release-PR short-circuit (runs first).** If this `/ship` invocation is operating on a release PR, skip the reviewer loop entirely. Detection: the PR title matches `^chore: release [0-9]` OR the PR body contains a `release-pr: true` trailer. Both signals are written by Stage 7 when it opens the release PR. On a match, log `releaseSelfReview: skipped: release-pr-detected`, write the standard PASS verification marker (`echo "{ISO-8601 timestamp}" > .ai-workspace/ship-verified-{pr-number}` — this is the *release PR's own number* returned by `gh pr create`, not the feature PR's; Stage 5's marker-write logic already keys on the active PR), record `cardEmission`/`reviewIterations` as 0, and proceed directly to Stage 6. Rationale: release PRs are mechanical version bumps; the feature PR's Stage 5 already vetted the substantive diff.

Iterate up to **5 times**. Each iteration:

### 5a. Spawn Stateless Reviewer

Launch a fresh Agent subagent using the full prompt in `references/reviewer-prompt.md` (relative to this skill's base directory, NOT the current working directory). The reviewer must have NO context about the implementation -- fresh eyes only.

### 5b. Process the Review

Read `tmp/ship-review-{N}.md` and act on the verdict:

**PASS (no bugs):**
- Write verification marker: `echo "{ISO-8601 timestamp}" > .ai-workspace/ship-verified-{pr-number}` (in the project's `.ai-workspace/` dir). This marker allows the enforce-ship hook to permit the merge in Stage 6.
- For each enhancement found, auto-create a GitHub issue:
  ```bash
  gh issue create --title "{summary}" --body "{description}" --label "enhancement" --label "ship-review"
  ```
- Log created issue URLs. Record `enhancementsCreated` (count of issues created). Proceed to Stage 6.

**BLOCK (bugs found):**
1. For each bug found, append to the run record's `issues` array: `{ "stage": "selfReview", "type": "{bug_type}", "description": "{bug_summary}", "iteration": {N} }`.
2. Increment `bugsFound` counter. Add each bug's type to `bugCategories` (deduplicated).
3. Create a micro-plan at `.ai-workspace/plans/{date}-ship-fix-{N}.md` (satisfies the enforce-plan hook).
4. Fix all reported bugs.
5. `git add` the fixed files. Create a **new commit** (not amend). `git push`.
6. Re-poll CI checks (Stage 4 mini-loop).
7. Increment iteration counter (`reviewIterations`).
   - If counter >= 5: print remaining bugs and escalate to user. **Do NOT merge.**
   - Otherwise: re-enter Stage 5 (next iteration).

## Stage 5.5 -- CAIRN INDEX-CHECK GATE (Phase B, client-side only)

**This is a Tier-2 client-side gate, not a hard branch-protection required check.** UI merges and admin overrides bypass it by design; the monthly audit (M7) is the retroactive signal. Do not describe this as a merge-required check anywhere.

Applies to any PR whose diff touches:
- `hive-mind-persist/knowledge-base/**/*.md`
- `hive-mind-persist/memory.md`
- `hive-mind-persist/session-notes/**/*.md`

Steps:

1. **Gated-path detection:**
   ```bash
   CHANGED=$(gh pr view {pr-number} --json files -q '.files[].path')
   GATED=0
   for f in $CHANGED; do
     case "$f" in
       hive-mind-persist/knowledge-base/*.md|hive-mind-persist/memory.md|hive-mind-persist/session-notes/*.md)
         GATED=1; break;;
     esac
   done
   ```
   If `GATED=0`, print `[SHIP] index-check gate: no gated paths — skipping` and proceed. No prompt.

2. **Re-fetch PR body** (catch manual UI edits since Stage 3):
   ```bash
   gh pr view {pr-number} --json body -q .body > .ai-workspace/ship-pr-body-{pr-number}.txt
   ```
   Do NOT write the body back to the remote after reading — the gate is read-only.

3. **Validate via the cairn Phase B checker:**
   ```bash
   node cairn/bin/phase-b-checks.mjs ship-gate \
     --pr-body-file .ai-workspace/ship-pr-body-{pr-number}.txt --gated
   ```
   The checker strips CRLF, rejects blockquoted `> index-check:` lines, and accepts exactly one of:
   - `index-check: P<N>[, F<M>, ...]` (IDs, comma separated, optional spaces)
   - `index-check: none`
   - `index-check: skip -- <non-empty reason>` (ASCII `--`, not em-dash)

4. **On non-zero exit:** abort with:
   ```
   Merge blocked: PR body missing a valid index-check: trailer. See parent-claude.md
   "Cairn Index-Check Trailer" section. Valid forms:
     index-check: P46, F36
     index-check: none
     index-check: skip -- <reason>
   ```

5. Record `cairnIndexCheckGate: "passed"|"skipped-no-gated"|"aborted-invalid"` in the run record.

## Stage 6 -- MERGE

**Pre-merge plan-refresh re-verification (added by Q0/L1) — applies only when Stage 0.5 ran (forge-harness repo):**

1. Re-fetch the live PR body to catch any manual edits that happened between Stage 3 and Stage 6:
   ```bash
   BODY=$(gh pr view {pr-number} --json body -q .body)
   ```
2. **Assert a valid plan-refresh line is present:**
   ```bash
   echo "$BODY" | grep -qE '^plan-refresh: (no-op|[1-9][0-9]* items|baseline|error: .+)$'
   ```
   If the grep returns non-zero, **abort** with: `"Merge blocked: PR body missing valid plan-refresh line. Expected one of: 'plan-refresh: no-op', 'plan-refresh: <N> items', 'plan-refresh: baseline', or 'plan-refresh: error: <reason>'. Re-run /ship or add the line manually via 'gh pr edit {pr-number} --body'."`
3. **Error-form override enforcement:** if the plan-refresh line starts with `plan-refresh: error:`, additionally assert the override line is present:
   ```bash
   echo "$BODY" | grep -qE '^plan-refresh-override: .+$'
   ```
   If the grep returns non-zero, **abort** with: `"Merge blocked: plan-refresh reported an error ('<reason>') and merge is blocked by default. To proceed, add 'plan-refresh-override: <reason>' to the PR body via 'gh pr edit {pr-number} --body'."`
4. **Baseline sanity check:** if the plan-refresh line is `plan-refresh: baseline`, re-verify the marker is still absent on master via `MSYS_NO_PATHCONV=1 git show origin/master:.forge/.plan-refresh-initialized 2>/dev/null` (the `MSYS_NO_PATHCONV=1` prefix is required on Windows Git Bash — see issue #227). If the command now exits zero (marker was committed between Stage 0.5 and Stage 6 by a concurrent merge), **abort** with: `"Merge blocked: plan-refresh line is 'baseline' but the .forge/.plan-refresh-initialized marker is now present on origin/master. Re-run /ship to recompute the plan-refresh signal against the current master state."`
5. Record `planRefreshMergeGate: "passed"` in the run record.

**Merge:**

```bash
gh pr merge {pr-number} --squash --delete-branch
```

If merge fails due to conflicts, report the conflicting files and **abort**. Do not auto-resolve.

## Stage 7 -- RELEASE

Version bump + changelog land on master via a **squash-merged release PR**, not a direct push. The release worktree mirrors Rule 12 worktree discipline used elsewhere in the pipeline. Tagging happens **after** the release PR merges so the tag points at the squash-merge commit on master.

1. **Check if repo is releasable:** Look for `package.json` at the repo root.
   - If not found: log "No package.json -- skipping release." Proceed to Stage 8.

2. **Get last tag (read-only on master):**
   ```bash
   git fetch origin master --tags
   git describe --tags --abbrev=0 origin/master 2>/dev/null
   ```
   - If no tags exist: use `0.0.0` as baseline, default bump = minor (→ `0.1.0`).

3. **Collect commits since last tag:**
   ```bash
   git log {last_tag}..origin/master --format="%s"
   ```

4. **Determine version bump** from conventional commit prefixes:
   - Any commit with `!` suffix (e.g., `feat!:`) or `BREAKING CHANGE` in body → **major**
   - Any `feat` or `feat(scope)` prefix → **minor**
   - Only `fix`, `chore`, `docs`, `refactor`, `test`, `style`, `perf`, `ci`, `build` → **patch**
   - No conventional commits found → **patch** (default)

5. **Compute new version:** Increment the appropriate semver component of the last tag.

6. **Create a fresh release worktree from `origin/master`:**
   ```bash
   git worktree add .claude/worktrees/release-{version} -b chore/release-{version} origin/master
   cd .claude/worktrees/release-{version}
   ```
   This is the same Rule 12 pattern used everywhere else in the pipeline. Editing happens here, not in the primary clone.

7. **Inside the release worktree, bump `package.json`** to `"version": "{new_version}"` via a targeted edit. Do not touch other fields.

8. **Inside the release worktree, generate CHANGELOG entry:**
   - Group commits by type: `### Features` (feat), `### Bug Fixes` (fix), `### Miscellaneous` (everything else)
   - Format: `## [{version}](https://github.com/{owner/repo}/compare/{last_tag}...v{version}) ({date})`
   - Prepend to `CHANGELOG.md` (create the file if missing).

9. **Sanity-check the diff before committing.** Run:
   ```bash
   git status --porcelain
   git diff --shortstat
   ```
   Only `package.json` and `CHANGELOG.md` should appear. If any other file shows up (notably a phantom whole-file reformat from CRLF/LF mismatch on Windows), halt with a clear error pointing at the line-ending mismatch — do **not** commit.

10. **Commit (no tag yet):**
    ```bash
    git add package.json CHANGELOG.md
    git commit -m "chore: release {version}"
    ```
    Do not tag and do not attempt to publish to master from the worktree at this point.

11. **Push the release branch:**
    ```bash
    git push -u origin chore/release-{version}
    ```

12. **Open the release PR.** The body's first line MUST contain a recognizable release-PR marker (`release-pr: true` trailer) so Stage 5 can short-circuit when this PR is the next one inspected:
    ```bash
    gh pr create --title "chore: release {version}" --body "$(printf '%s\n\n%s\n' 'release-pr: true' "$CHANGELOG_ENTRY")"
    ```
    Capture the returned PR number/URL into `RELEASE_PR_URL` and `RELEASE_PR_NUMBER` for Stage 9.

13. **Merge the release PR.** Use auto-merge so GitHub waits for CI; the operator does not poll:
    ```bash
    gh pr merge {release-pr-number} --squash --auto --delete-branch
    ```
    If `--auto` is unsupported on the local `gh` version, fall back to the Stage 4 CI-wait pattern: poll `gh pr checks` every 30s for up to 10 minutes, then `gh pr merge {release-pr-number} --squash --delete-branch`. If branch protection requires a different merge mode (rebase or merge), adapt accordingly. If the release PR's CI fails, log the failure clearly and stop — leave the open PR for manual recovery; do not spawn a fixer (Stage 5 was already skipped for release PRs).

14. **After the release PR merges, tag the squash-merge commit.** Fetch master, confirm HEAD is the squash-merge commit, then tag and push the single tag:
    ```bash
    cd "$PRIMARY_CLONE_OR_RELEASE_WORKTREE"
    git fetch origin master
    MERGE_SHA=$(gh pr view {release-pr-number} --json mergeCommit -q .mergeCommit.oid)
    git tag v{version} "$MERGE_SHA"
    git push origin v{version}
    ```
    If pushing the single tag is rejected (e.g., tag protection on the remote), log `release tag rejected by remote -- stopping; manual tag push needed before GitHub Release can be created` and stop. Do not attempt to bypass the rejection.

15. **Create the GitHub Release:**
    ```bash
    gh release create v{version} --title "v{version}" --notes "{changelog_entry}"
    ```

16. Log: `[SHIP] Released v{version} via PR #{release-pr-number} -- tag, changelog, and GitHub Release created.`
17. Record release fields in the run record. See Stage 9's schema for the field list (`releaseVersion`, `releaseBump`, `releaseViaPR`, `releasePrUrl`). When this stage skips because no `package.json` is present, record `releaseVersion: null`, `releaseBump: "skipped"`, `releaseViaPR: false`, `releasePrUrl: null`.

**Important:** This stage is non-fatal. The feature PR is already merged. Any failure here should log a warning and continue to Stage 8, never abort. Stage 8 will quarantine the release worktree regardless of whether step 14/15 succeeded.

## Stage 8 -- CLEANUP

Cleanup is **worktree-aware** because rule #12 ("always use a worktree for branched work in shared repos") routes most ai-brain ships through a secondary worktree. The legacy `git checkout master` path fails inside a secondary worktree with `fatal: 'master' is already used by worktree at <primary>` — master is already checked out by the shared clone — and the rest of the cleanup chain (delete branch, remove verification marker) gets skipped. Detect the worktree case once and branch.

```bash
GIT_DIR=$(git rev-parse --git-dir)
GIT_COMMON_DIR=$(git rev-parse --git-common-dir)

if [ "$GIT_DIR" = "$GIT_COMMON_DIR" ]; then
  # Primary clone — legacy path.
  git checkout master && git pull
  git branch -d {branch} 2>/dev/null   # delete local if still exists
  rm -f .ai-workspace/ship-verified-{pr-number}   # clean up verification marker
else
  # Secondary worktree (rule #12 case). Pull in the shared clone, remove
  # this worktree, delete the local branch, and prune the verification marker
  # from the worktree before it's removed.
  WORKTREE_PATH=$(pwd -P)
  PRIMARY_PATH=$(cd "$GIT_COMMON_DIR/.." && pwd -P)
  rm -f .ai-workspace/ship-verified-{pr-number}   # clean marker before worktree is removed
  cd "$PRIMARY_PATH"
  # Intentional per CLAUDE.md rule #12: do NOT `git checkout master` here.
  # The shared primary clone may legitimately be on a non-master branch for
  # other agents; we pull whatever branch it's on. A future maintainer might
  # be tempted to add `git checkout master` for symmetry with the primary-
  # clone path above — don't. That would yank HEAD out from under any
  # concurrent agent working in the shared clone.
  git pull
  git worktree remove "$WORKTREE_PATH" 2>/dev/null \
    || git worktree remove --force "$WORKTREE_PATH"
  git branch -d {branch} 2>/dev/null   # delete local if still exists
  # Remote branch was already deleted by `gh pr merge --delete-branch` in Stage 6.
  # If it lingers (gh's local-branch deletion sometimes fails on Windows when
  # HEAD-switching is blocked by a worktree), prune the dangling remote ref:
  git push origin --delete {branch} 2>/dev/null || true
fi
```

**Release-worktree quarantine** (runs after the feature-worktree branch above when Stage 7 created a release worktree). The release worktree at `.claude/worktrees/release-{version}` is no longer needed once the release PR has merged and the tag has been pushed. Move it (do NOT `rm -rf` — Rule 14) into a quarantine path, then prune the worktree registry:

```bash
RELEASE_WT=".claude/worktrees/release-{version}"
if [ -d "$RELEASE_WT" ]; then
  # Operate from the primary clone so the worktree path is reachable.
  cd "$PRIMARY_PATH"
  QUARANTINE_DIR=".claude/worktrees/_quarantine-release-{version}-$(date +%Y%m%d)"
  mv "$RELEASE_WT" "$QUARANTINE_DIR"
  git worktree prune
  git branch -d chore/release-{version} 2>/dev/null || true
fi
```

The `mv`-not-`rm` step is mandatory per CLAUDE.md Rule 14 ("Always Use `mv`, Never `rm`"). The quarantine dir is a sibling under `.claude/worktrees/`, so a future operator can recover the release worktree if anything went wrong with the GitHub Release creation.

**Auto-publish skills** (conditional): If `scripts/publish-skills.sh` exists in the repo root AND the merged PR touched files under `skills/`, run the publish script. Log the result but do not fail the pipeline if publishing fails. This only triggers in repos that have the publish script.

**Persist run data** (see Run Data Recording section below), then print a final summary:
- PR URL and merge commit SHA
- Number of review iterations performed
- GitHub issues created (if any)
- Release version (if Stage 7 created a tag)

---

## Stage 9 -- RECORD (always runs)

Print the status line: `[SHIP 9/10] Recording run data...`

This stage executes regardless of whether earlier stages succeeded or failed. If the pipeline aborts at any stage, Stage 9 still runs before stopping. This is the observability contract — every invocation MUST produce a run record, including aborted runs (a "nothing to ship" abort is still a run worth tracking because it reveals invocation patterns). Prior versions made this an appendix-style "Run Data Recording (always runs)" section which was structurally easy to skip; it is now an explicit numbered stage.

### What to record

Build the run record from metrics accumulated throughout the pipeline:

```json
{
  "timestamp": "{run_start_time}",
  "durationSeconds": "{now - run_start_time in seconds}",
  "outcome": "success|partial|failure|aborted",
  "project": "{current project directory name}",
  "trigger": "/ship {$ARGUMENTS or empty}",
  "stages": {
    "preflight": "pass|fail|skip",
    "branch": "pass|fail|skip",
    "commit": "pass|fail|skip",
    "pushPr": "pass|fail|skip",
    "ciWait": "pass|fail|skip",
    "selfReview": "pass|fail|skip",
    "merge": "pass|fail|skip",
    "release": "pass|fail|skip",
    "cleanup": "pass|fail|skip",
    "card": "pass|fail|skip"
  },
  "metrics": {
    "prUrl": "{PR URL or null}",
    "prNumber": "{PR number or null}",
    "branchName": "{branch name}",
    "reviewIterations": "{count, 0 if not reached}",
    "bugsFound": "{total bugs across all iterations}",
    "bugCategories": ["{deduplicated list of bug types}"],
    "enhancementsCreated": "{count of GH issues created}",
    "ciWaitSeconds": "{seconds spent polling CI}",
    "ciOutcome": "pass|fail|timeout|none|null",
    "ciOauthSynced": "{true if token was synced during CI wait, omit otherwise}",
    "ciRetried": "{true if CI was re-triggered after token sync, omit otherwise}",
    "ciRetryOutcome": "pass|fail|timeout|null",
    "releaseVersion": "{version or null}",
    "releaseBump": "major|minor|patch|skipped|null",
    "releaseViaPR": "{true if Stage 7 used the PR-merge flow; false if Stage 7 was skipped because no package.json; null if Stage 7 errored before deciding}",
    "releasePrUrl": "{URL of the release PR, or null if no release}",
    "commitCount": "{number of commits: initial + fix iterations}",
    "cardEmission": "emitted:<path> | emitted:<path>+refresh-warn | skipped:no-root | skipped:no-tool | skipped:outcome-<value> | error:<one-line>"
  },
  "issues": [
    { "stage": "{stage}", "type": "{issue_type}", "description": "{description}" }
  ],
  "summary": "{one-line description of what happened}"
}
```

**Outcome values:**
- `success` — merged and released (or merged + release skipped because no package.json)
- `partial` — merged but release failed
- `failure` — merge failed (conflicts, branch protection)
- `aborted` — pipeline stopped early (nothing to ship, CI failure, auth failure, 5 iterations exhausted, network error)

For aborted runs, also set:
- `metrics.abortStage`: the stage name where the pipeline stopped
- `metrics.abortReason`: one-line explanation

### Where to write

All paths are relative to this skill's base directory (resolved from the symlink, i.e., the skill's source directory):

1. **`runs/data.json`** — Read the existing file (create if missing with `{"skill":"ship","lastRun":null,"totalRuns":0,"runs":[]}`). Append the new run record to the `runs` array. If `runs.length > 50`, remove the oldest entries to keep exactly 50 (older runs are permanently discarded). Increment `totalRuns` by 1. Set `lastRun` to the run's timestamp. Write the file.

2. **`runs/run.log`** — Append one line: `{timestamp} | {outcome} | {durationSeconds}s | {summary}`. If the log exceeds 100 lines, trim the oldest lines to keep exactly 100.

### Important

- **Always record**, even on abort. A "nothing to ship" abort is still a run worth tracking (it reveals invocation patterns).
- **Do not fail the pipeline** if recording fails (e.g., file permission error). Log a warning and continue.
- **Resolve the skill base directory** from the symlink target, not the current working directory. The runs/ folder lives alongside SKILL.md.

## Stage 10 -- CARD (decision card emission, success runs only)

Print the status line: `[SHIP 10/10] Emitting decision card...`

**Stage 10 is the same class of "feels done, exits early" problem that Stage 9 itself was promoted to fix.** When card emission was a sub-stage nested inside Stage 9's text wall, operators treated `data.json` + `run.log` as "recording done" and bailed. Promoting it to a numbered stage with its own status line makes the final-final step visible in the pipeline progression. Like Stage 9, this stage is best-effort (never fails the pipeline) but the **decision to attempt it** is now unconditional for success runs.

After the run record has been written to `runs/data.json` and `runs/run.log`, emit a working-memory decision card under the user's agent-working-memory tree if the user has opted in. This is how shipped work flows into the causal memory tier described in `.ai-workspace/plans/2026-04-15-agent-working-memory.md`.

**Gating conditions — ALL must hold for emission to proceed. If any fails, skip silently and record the reason in `metrics.cardEmission`:**

**IMPORTANT — run these gate checks as actual bash commands. Do NOT read the prose and guess the outcome; past /ship runs failed Stage 10 silently because the agent interpreted "check if X exists" as a prompt to substitute an assumption rather than invoke the filesystem. Execute the bash blocks below verbatim and branch on their exit codes / output.**

1. **Memory root discoverable.** Either `$WORKING_MEMORY_ROOT` is set in the environment, OR the default path `~/.claude/agent-working-memory/` exists on disk. In **both** cases, the resolved root must contain a `tier-b/` subdirectory — if `$WORKING_MEMORY_ROOT` is set but has no `tier-b/` inside, the gate fails fast as `skipped:no-root` rather than cascading into a write-time error. If neither source resolves to a valid root: skip with `cardEmission: "skipped:no-root"`.

   Concrete gate check (run this; pass iff it prints `root=<path>`):

   ```bash
   ROOT="${WORKING_MEMORY_ROOT:-$HOME/.claude/agent-working-memory}"
   if [ -d "$ROOT/tier-b" ]; then
     echo "root=$ROOT"
   else
     echo "skipped:no-root"
   fi
   ```

2. **Mechanism tool discoverable.** The public mechanism repo's `src/write-card.mjs` must be reachable. Look for it at (a) `$WORKING_MEMORY_TOOL` if set, (b) `$HOME/coding_projects/agent-working-memory/src/write-card.mjs`, (c) a `memory` binary on `$PATH`. If none resolve: skip with `cardEmission: "skipped:no-tool"`.

   Concrete gate check (run this; pass iff it prints `tool=<path>` or `tool=memory`):

   ```bash
   if [ -n "${WORKING_MEMORY_TOOL:-}" ] && [ -f "$WORKING_MEMORY_TOOL" ]; then
     echo "tool=$WORKING_MEMORY_TOOL"
   elif [ -f "$HOME/coding_projects/agent-working-memory/src/write-card.mjs" ]; then
     echo "tool=$HOME/coding_projects/agent-working-memory/src/write-card.mjs"
   elif command -v memory >/dev/null 2>&1; then
     echo "tool=memory"
   else
     echo "skipped:no-tool"
   fi
   ```

3. **Run outcome is `success`.** Aborted, partial, and failure runs do NOT emit cards — they add noise to the memory tier without adding signal. If outcome is anything other than `success`: skip with `cardEmission: "skipped:outcome-<value>"`. This gate is checked against the in-memory run outcome variable — no filesystem probe needed.

**When all three gates pass, emit the card:**

1. **Extract the WHY from the PR body.** Fetch the merged PR body via `gh pr view <pr-number> --json body -q .body`. Extract the Summary section: the text between `## Summary` and the next `##` heading. If the body has no `## Summary` heading, use the first 500 characters of the body as a fallback. Trim whitespace.
2. **Derive card metadata.**
   - `topic`: `ship-runs`
   - `id`: `pr-<pr-number>-<slug>` where `<slug>` is the branch name with conventional prefix stripped (e.g., `feat/add-foo` → `add-foo`), lowercased, non-alphanumerics collapsed to `-`, truncated to 40 chars.
   - `title`: the PR title verbatim.
   - `created`: today's date in `YYYY-MM-DD` form.
   - `pinned`: `false`.
   - `tags`: `[]`. Auto-emitted cards are never pinned — they accumulate as an activity stream, not a rule set.
3. **Card body.** The `## Decision` section contains the extracted Summary text. `## Context` and `## Consequences` can use placeholder text (`(auto-emitted by /ship Stage 10 on PR <num>)`) — these are machine-generated cards, not hand-curated rules, and the Decision field carries the signal.
4. **Write the card.** Since `memory write` (the CLI subcommand) only fills the `## Decision` body slot and cannot accept frontmatter tweaks, write the card file directly via a heredoc or equivalent. Path: `<root>/tier-b/topics/ship-runs/<created>-<id>.md`. Create `ship-runs/` if missing.
5. **Refresh the pocket card.** Invoke `node <mechanism-repo>/src/memory-cli.mjs refresh --root <root>` so `tier-a.md` reflects the new card. Best-effort; a refresh failure does not fail the pipeline.
6. **Record the outcome.** On success with clean refresh: `cardEmission: "emitted:<relative-path-from-root>"`. On success with refresh failure: `cardEmission: "emitted:<relative-path-from-root>+refresh-warn"` — the card was written but the pocket card was not updated (it will catch up on next `memory refresh` or session start). On any error during extraction or writing (before the card exists on disk): `cardEmission: "error:<one-line-reason>"` — the pipeline proceeds regardless.

**Graceful degradation is mandatory.** This stage NEVER fails the pipeline. Any error — missing tool, disk full, malformed PR body, refresh script crash — logs a warning, records the error in `metrics.cardEmission`, and continues. The ship pipeline is already complete by the time this stage runs; card emission is a bonus, not a contract.

**Privacy note.** The card body is derived from the PR body, which is already public on GitHub. No new information leakage surface is introduced by copying it into the user's private content repo.

**Why emission is conditional on success only.** The working-memory tier is for *decisions that shipped*. An aborted run is not a decision; a partially-merged release is ambiguous. Filtering to `success` keeps the card stream clean and makes the Tier A pocket card more valuable (no noise). If richer coverage is wanted later, a follow-up can open the gate to `partial`; do not expand the gate silently here.

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No changes to commit | Abort: "Nothing to ship." |
| Already on feature branch | Skip branch creation |
| PR already exists for branch | Skip PR creation, use existing |
| CI fails | Report check names + URLs, abort |
| Merge conflicts | Report conflicting files, abort |
| 5 review iterations exhausted | List remaining bugs, escalate to user |
| No CI checks configured | Skip CI wait, proceed to review |
| `gh` auth failure | Report error, abort |
| Network error during any `gh` call | Report the error, abort cleanly |
| No package.json in repo | Skip Stage 7 entirely |
| No git tags exist | Use 0.0.0 baseline, bump to 0.1.0 |
| No conventional commits since last tag | Default to patch bump |
| Tag/push fails | Log warning, skip — feature is already merged |
| GitHub Release creation fails | Log warning, skip — tag still exists |
