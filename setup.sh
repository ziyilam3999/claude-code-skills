#!/usr/bin/env bash
# Install Claude Code skills by symlinking to ~/.claude/skills/
# Usage: ./setup.sh              (install all skills)
#        ./setup.sh ship         (install only the ship skill)
#        ./setup.sh --list       (list available skills)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

if [ "${1:-}" = "--list" ]; then
  echo "Available skills:"
  for d in "$REPO_DIR"/skills/*/; do
    name="$(basename "$d")"
    echo "  $name"
  done
  exit 0
fi

mkdir -p "$SKILLS_DIR"

install_skill() {
  local name="$1"
  local src="$REPO_DIR/skills/$name"
  if [ ! -d "$src" ]; then
    echo "ERROR: Skill '$name' not found in $REPO_DIR/skills/"
    return 1
  fi
  ln -sfn "$src" "$SKILLS_DIR/$name"
  echo "  Installed: $name"
}

if [ -n "${1:-}" ]; then
  echo "Installing skill: $1"
  install_skill "$1"
else
  echo "Installing all skills..."
  for d in "$REPO_DIR"/skills/*/; do
    name="$(basename "$d")"
    install_skill "$name"
  done
fi

echo ""
echo "Done. Skills are symlinked to $SKILLS_DIR"
echo "Restart Claude Code to pick up new skills."
