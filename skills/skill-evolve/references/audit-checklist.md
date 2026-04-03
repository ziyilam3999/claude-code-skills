# Audit Checklist

Run each check. Record result as PASS / FAIL / WARN.

## 1. Format Compliance

| # | Check | How to verify | Severity |
|---|-------|---------------|----------|
| F1 | SKILL.md exists | Glob for `SKILL.md` in skill dir | FAIL |
| F2 | YAML frontmatter has `name` | Parse frontmatter | FAIL |
| F3 | YAML frontmatter has `description` | Parse frontmatter | FAIL |
| F4 | No extra frontmatter fields | Only `name`, `description`, `license`, `allowed-tools`, and `metadata` allowed | WARN |
| F5 | Description includes trigger phrases | Check for "Use when" or trigger examples | WARN |
| F6 | Body under 500 lines | `wc -l SKILL.md` minus frontmatter | WARN |

## 2. Directory Structure

| # | Check | How to verify | Severity |
|---|-------|---------------|----------|
| D1 | Lives in `ai-brain/skills/{name}/` | Check path | FAIL |
| D2 | Symlinked from `~/.claude/skills/{name}` | `ls -la` symlink | FAIL |
| D3 | No double-nesting | Skill dir should NOT contain another dir with same name holding SKILL.md | FAIL |
| D4 | No extraneous files | No README.md, CHANGELOG.md, INSTALLATION_GUIDE.md, QUICK_REFERENCE.md | WARN |

## 3. Run Data Recording

| # | Check | How to verify | Severity |
|---|-------|---------------|----------|
| R1 | SKILL.md has "Run Data Recording" section | Grep for `## Run Data Recording` | FAIL |
| R2 | `runs/` directory exists | Check path | FAIL |
| R3 | `runs/data.json` exists with valid structure | Read and parse JSON, check for `skill`, `lastRun`, `totalRuns`, `runs` keys | FAIL |
| R4 | `runs/run.log` exists | Check path | FAIL |
| R5 | Recording section specifies outcome values | Grep for any outcome enum listing (e.g., `complete\|no-action\|error`, `success\|fail`, or similar pipe-separated values) | WARN |
| R6 | Recording section specifies "keep last 20 runs" | Grep for retention policy | WARN |

## 4. Improvability

| # | Check | How to verify | Severity |
|---|-------|---------------|----------|
| I1 | Run data has meaningful outcome values | data.json runs have distinct outcome strings (not all identical) | WARN |
| I2 | Run data captures actionable metrics | data.json run entries have 3+ metric fields beyond timestamp/outcome | WARN |
| I3 | Skill workflow has distinct stages | SKILL.md has numbered steps or named stages | WARN |
| I4 | No hardcoded paths or secrets | Grep SKILL.md for absolute paths outside ai-brain or tokens | FAIL |

## Severity Guide

- **FAIL**: Must fix before the skill is considered healthy. Auto-fix when possible.
- **WARN**: Should fix. Note for the user but do not block.

## Auto-Fix Capabilities

The following issues can be auto-fixed by the audit:

- D1 + D2: Move skill to ai-brain/skills/ and create symlink
- D3: Flatten double-nested directory
- R2-R4: Create missing runs/ directory and initial files
- R1: Append a Run Data Recording section template (requires human review of metrics)
