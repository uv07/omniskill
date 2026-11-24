#!/usr/bin/env bash
# Apply the GitHub description, website and topics for omniskill. Needs `gh auth login`.
set -euo pipefail
REPO="${1:-uv07/omniskill}"
gh repo edit "$REPO" \
  --description "415 AI coding agent skills in one: the all-in-one SKILL.md for Claude Code & Google Antigravity. TDD, debugging, code review, planning, git, security, plus language, framework & domain guides. Merged from superpowers, ECC, mattpocock, Karpathy & more." \
  --homepage "https://github.com/uv07/omniskill#install" \
  --enable-issues --enable-discussions=false --enable-wiki=false
TOPICS=(claude-code claude-skills agent-skills claude-code-plugin skills antigravity google-antigravity ai-agents ai-coding llm prompt-engineering tdd code-review debugging developer-tools anthropic claude ai-coding-assistant agentic-coding skill-md)
args=(); for t in "${TOPICS[@]}"; do args+=(--add-topic "$t"); done
gh repo edit "$REPO" "${args[@]}"
echo "Metadata applied to $REPO. Upload assets/banner.png under Settings > Social preview (GitHub has no API for it)."
