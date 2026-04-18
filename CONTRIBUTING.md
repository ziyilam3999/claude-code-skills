# Contributing

Thanks for your interest in contributing to `claude-code-skills`.

## Before you start

- Open an issue first for non-trivial changes (new skill, skill removal, catalog reorganization) so scope can be discussed before code is written
- Check existing issues and PRs to avoid duplicate work

## Development

No build step — every skill is a markdown file.

```bash
git clone https://github.com/ziyilam3999/claude-code-skills.git
cd claude-code-skills
./setup.sh              # symlinks all skills into ~/.claude/skills/
./setup.sh --list       # list available skills
./setup.sh <skill-name> # install a single skill
```

Restart Claude Code after `setup.sh` to pick up changes.

## Adding a new skill

1. Create a new directory under `skills/` (e.g., `skills/my-new-skill/`)
2. Add a `SKILL.md` inside it. The first lines should describe when Claude should auto-invoke the skill; the rest describes the workflow.
3. For slash-command skills, use the standard frontmatter format (see existing skills for reference).
4. Update `README.md` to add the new skill to the catalog table.
5. Open a PR. CI validates every `skills/*/` directory contains a `SKILL.md`.

## Proposing a change to an existing skill

1. Create a branch: `git checkout -b feat/skill-name-short-description`
2. Make focused edits (one skill per PR is preferred)
3. Push and open a PR
4. CI must pass

## Style

- Keep each PR focused on one concern (one skill, or one doc change)
- Match the existing skill voice — imperative, concrete, example-heavy
- Update the README catalog when adding, renaming, or removing a skill

## License

By contributing, you agree your contributions are licensed under the MIT License (see `LICENSE`).
