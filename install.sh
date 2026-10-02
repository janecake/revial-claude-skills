#!/usr/bin/env bash
# Install the Revial Claude Code skills into ~/.claude/skills/.
# Default: symlink, so `git pull` in this repo updates what Claude uses.
#   --copy : install independent copies instead.
set -euo pipefail

MODE="symlink"
[[ "${1:-}" == "--copy" ]] && MODE="copy"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/skills"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
BACKUP="$DEST/.backup-$(date +%Y%m%d-%H%M%S)"

[[ -d "$SRC" ]] || { echo "No skills/ directory at $SRC" >&2; exit 1; }
mkdir -p "$DEST"

for path in "$SRC"/*/; do
  name="$(basename "$path")"
  target="$DEST/$name"

  # Already the symlink we would create — nothing to do.
  if [[ -L "$target" && "$(readlink "$target")" == "${path%/}" ]]; then
    echo "  ok       $name (already linked)"
    continue
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$BACKUP"
    mv "$target" "$BACKUP/$name"
    echo "  backed up $name -> ${BACKUP/#$HOME/~}/$name"
  fi

  if [[ "$MODE" == "copy" ]]; then
    cp -R "${path%/}" "$target"
    echo "  copied   $name"
  else
    ln -s "${path%/}" "$target"
    echo "  linked   $name"
  fi
done

echo
echo "Installed to ${DEST/#$HOME/~}. Open Claude Code and type / to confirm they are listed."
