# Claude Code Skills

A collection of custom skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Anthropic's CLI for Claude. These skills extend Claude Code with specialized workflows for shipping code, reviewing documents, managing sessions, and more.

## What are Claude Code Skills?

Skills are markdown files that teach Claude Code new capabilities. When installed, they appear as slash commands (e.g., `/ship`, `/checkpoint`) or auto-load to improve Claude's behavior in specific contexts.

## Skill Catalog

### User-Invocable Skills

| Skill | Command | Description |
|-------|---------|-------------|
| **ship** | `/ship` | Full git shipping pipeline: commit, branch, push, PR, CI wait, self-review loop, merge, release |
| **coherent-plan** | `/coherent-plan` | Quick consistency review for plans and strategy docs. Finds contradictions, fixes them |
| **double-critique** | `/double-critique` | Deep multi-agent critique pipeline. Two independent critics review a document cold |
| **checkpoint** | `/checkpoint` | Session checkpoint that consolidates progress and prepares for continued work |
| **humanize-writing** | `/humanize-writing` | Review and rewrite AI-generated text to sound human-written |
| **flutter** | `/flutter` | Flutter/Dart development patterns including Riverpod, go_router, and mobile best practices |
| **skill-evolve** | `/skill-evolve` | Skill lifecycle manager: create, audit, and improve custom skills |
| **mailbox** | `/mailbox` | Cross-session messaging between Claude Code agents via git-backed mailbox |

### Auto-Loaded Skills

These skills load automatically to improve Claude's behavior. No slash command needed.

| Skill | Purpose |
|-------|---------|
| **skeptical-code-reviewer** | Teaches the code reviewer to catch logic errors and missing test coverage |
| **skeptical-critic** | Teaches the critic agent to demand evidence and catch subtle bugs |
| **skeptical-evaluator** | Teaches the evaluator to mechanically verify results, not trust surface-level checks |
| **compliance-ec-rules** | Generates compliance-type executable criteria for instruction coverage |

## Install

```bash
git clone https://github.com/ziyilam3999/claude-code-skills.git
cd claude-code-skills
./setup.sh
```

This symlinks all skills to `~/.claude/skills/`. Restart Claude Code to pick them up.

### Install a Single Skill

```bash
./setup.sh ship          # install only the ship skill
./setup.sh checkpoint    # install only checkpoint
./setup.sh --list        # see available skills
```

### Mailbox Note

The mailbox skill auto-creates a local mailbox directory (`~/claude-code-mailbox/`) on first use. No additional setup needed.

## Updating

```bash
cd claude-code-skills
git pull
```

Skills are symlinked, so pulling updates takes effect immediately (restart Claude Code for the changes to load).

## License

MIT
