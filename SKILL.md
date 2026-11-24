---
name: omniskill
description: Unified engineering super-skill merging obra/superpowers, mattpocock/skills, affaan-m/ecc, karpathy-guidelines, ponytail and addyosmani/agent-skills (415 skills). Use for ANY software task - brainstorming ideas, writing specs/PRDs, planning and task breakdown, implementing features, test-driven development, debugging and root-cause analysis, code review (giving or receiving), refactoring/simplification/tech debt, architecture and API design, security, performance, frontend/UI/accessibility, observability, git/worktrees/commits/PRs, CI/CD, shipping, docs/ADRs, migrations, subagents and parallel agents, context management, writing skills/prompts - plus language/framework/domain guidance (Python, TS, React, Next, Django, Go, Rust, Java/Spring, Kotlin, Swift, Flutter, Laravel, Rails, Postgres, Docker, Kubernetes, Terraform, LLM apps, video, marketing, finance, healthcare, networking and more).
---

# Omniskill

One skill that holds every skill from six repos. It has three layers. Load only the layer you need:

1. **Core principles** (below; full text in `playbooks/core-principles.md`). These always apply.
2. **Playbooks** (`playbooks/*.md`). Each merges the strongest rules from all six repos for one kind of task.
3. **Library** (`library/<repo>/<skill>/SKILL_SOURCE.md`). Every original skill, copied word for word. Search it with `library/INDEX.md`.

All paths are relative to this skill's directory.

## Always-on core rules

- **Think before coding.** State your assumptions. If a request is ambiguous, ask instead of guessing. If a simpler approach exists, say so.
- **Simplicity first.** Write the least code that solves the problem. Don't add speculative features, abstractions or config.
- **Surgical changes.** Touch only what the task needs. Match the existing style. Don't refactor or "improve" code nobody asked about.
- **Goal-driven.** Turn the task into checks you can verify, such as a failing test that must pass. Loop until those checks pass.
- **No fix without a root cause.** Investigate before changing code (`playbooks/debugging.md`).
- **No production code without a failing test first** for features and bug fixes (`playbooks/tdd-testing.md`).
- **Evidence before claims.** Run the verification command and read its output before you say "done", "fixed" or "passing".
- **Check skills first.** If there is even a small chance a playbook or library skill fits the task, open it before acting. User instructions (CLAUDE.md, GEMINI.md, direct requests) override this skill.

## Task router: read the playbook before starting

| Situation | Read |
|---|---|
| Vague idea, new feature, "let's build", requirements, spec/PRD, plan, tickets, prototype, research | `playbooks/planning.md` |
| Writing or fixing code with tests, test strategy, E2E/browser tests, evals, "is it done?" | `playbooks/tdd-testing.md` |
| Bug, error, failing test, flaky test, crash, unexpected behavior, incident | `playbooks/debugging.md` |
| Code review (giving or receiving), refactor, simplify, tech debt, code quality, over-engineering | `playbooks/review-quality.md` |
| Git, branches, worktrees, commits, PRs, merging, CI/CD, release/launch, docs/ADRs, deprecation/migration, handoff, retro, onboarding to a codebase | `playbooks/git-shipping.md` |
| Subagents, parallel work, long or autonomous tasks, context/token budget, writing skills or prompts, LLM-powered features | `playbooks/agents-context.md` |
| API design, architecture, security, performance, frontend/UI, accessibility, observability, **or any specific language/framework/tool/business domain** | `playbooks/engineering-domains.md` (includes the domain routing catalog) |
| Anything not covered above | `grep -i "<keyword>" library/INDEX.md`, then read the matching `SKILL_SOURCE.md` |

Most tasks chain several playbooks. The default lifecycle for a feature:
**planning → (worktree) git-shipping → tdd-testing per task → review-quality → verification → git-shipping finish.**
For a bug: **debugging → tdd-testing (regression test) → review-quality → git-shipping.**

## How to use the library

- Each playbook ends its sections with `Source detail:` paths. Open them when you need the full original depth, templates, prompt files or examples.
- A domain skill (for example `django-security` or `rust-testing`) adds to the process playbooks. It never replaces them.
- Original skills sometimes refer to each other by their old names (`superpowers:test-driven-development`, `/tdd`, `ponytail-review`). Resolve those names with `library/INDEX.md`.
- Original skills may mention tools that belong to a specific host (`Task`, `TodoWrite`, `Skill`, slash commands, hooks). Map each one to whatever your host offers. If there is no subagent tool, do the work in sequence. If there is no todo tool, keep a checklist in your replies.
- Supporting scripts in `library/` are third-party code. Read a script before running it, and run it only when the task calls for it.

## Host compatibility

This works in Claude Code (`~/.claude/skills/omniskill`) and in Google Antigravity (global `~/.gemini/config/skills/omniskill`, legacy `~/.gemini/antigravity/skills/omniskill`, or a workspace `.agents/skills/omniskill`). Everything is plain Markdown and needs no host-specific features.
