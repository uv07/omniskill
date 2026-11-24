#!/usr/bin/env bash
# omniskill installer for Claude Code and Google Antigravity.
#
#   curl -fsSL https://raw.githubusercontent.com/uv07/omniskill/main/install.sh | bash
#   ./install.sh [--claude] [--antigravity] [--project DIR] [--update] [--uninstall]
#
# With no target flag it installs globally for every host it detects
# (~/.claude, ~/.gemini). Installs are git clones, so --update is a git pull.
set -euo pipefail

REPO_URL="${OMNISKILL_REPO:-https://github.com/uv07/omniskill.git}"
BRANCH="${OMNISKILL_BRANCH:-main}"
targets=()
action=install
project=""

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --claude)       targets+=("$HOME/.claude/skills/omniskill") ;;
    --antigravity)  targets+=("$HOME/.gemini/config/skills/omniskill") ;;
    --project)      project="${2:?--project needs a directory}"; shift ;;
    --update)       action=update ;;
    --uninstall)    action=uninstall ;;
    -h|--help)      usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
  shift
done

if [ -n "$project" ]; then
  targets+=("$project/.claude/skills/omniskill" "$project/.agents/skills/omniskill")
fi

if [ ${#targets[@]} -eq 0 ]; then
  [ -d "$HOME/.claude" ] && targets+=("$HOME/.claude/skills/omniskill")
  [ -d "$HOME/.gemini" ] && targets+=("$HOME/.gemini/config/skills/omniskill")
  if [ ${#targets[@]} -eq 0 ]; then
    echo "No ~/.claude or ~/.gemini found; defaulting to Claude Code." >&2
    targets+=("$HOME/.claude/skills/omniskill")
  fi
fi

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

for dest in "${targets[@]}"; do
  case "$action" in
    install)
      if [ -d "$dest/.git" ]; then
        echo "update   $dest"; git -C "$dest" pull --ff-only --quiet
      elif [ -e "$dest" ]; then
        echo "skip     $dest (exists and is not a git clone; remove it or use --uninstall)" >&2
        continue
      else
        echo "install  $dest"; mkdir -p "$(dirname "$dest")"
        git clone --quiet --depth 1 --branch "$BRANCH" "$REPO_URL" "$dest"
      fi ;;
    update)
      if [ -d "$dest/.git" ]; then echo "update   $dest"; git -C "$dest" pull --ff-only --quiet
      else echo "skip     $dest (not installed)"; fi ;;
    uninstall)
      if [ -f "$dest/SKILL.md" ] && grep -q '^name: omniskill' "$dest/SKILL.md"; then
        echo "remove   $dest"; rm -rf "$dest"
      else echo "skip     $dest (not an omniskill install)"; fi ;;
  esac
done

[ "$action" = uninstall ] || echo "Done. Restart Claude Code / Antigravity to load the skill."
