# omniskill

One agent skill that combines **415 skills from six open-source collections** into a single installable skill for **Claude Code** and **Google Antigravity**.

| Source | Skills |
|---|---|
| [obra/superpowers](https://github.com/obra/superpowers) | 15 |
| [mattpocock/skills](https://github.com/mattpocock/skills) | 39 |
| [affaan-m/ecc](https://github.com/affaan-m/ecc) | 328 |
| [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | 1 |
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | 6 |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | 26 |

## How it is organised

Only the layer a task needs gets loaded:

1. **`SKILL.md`**: the always-on core rules and a task router.
2. **`playbooks/`**: eight merged playbooks (about 5,500 lines). Each combines the strongest rules from every source and records how conflicts between sources were resolved.
   - `core-principles.md`: universal rules (Karpathy guidelines, evidence before claims, root cause before fix, test first)
   - `planning.md`: ideas, interviews, specs, plans, tickets, execution
   - `tdd-testing.md`: red-green-refactor, verification gate, E2E, LLM evals
   - `debugging.md`: gated root-cause process, bisection, flaky tests, incidents
   - `review-quality.md`: coding discipline, giving and receiving review, simplification, tech debt
   - `git-shipping.md`: worktrees, commits, PRs, CI/CD, launch, ADRs, migrations, handoffs
   - `agents-context.md`: subagents, parallel work, context budgets, writing skills and prompts
   - `engineering-domains.md`: API, architecture, security, performance, UI, accessibility, observability, plus a routing catalog that covers every library skill
3. **`library/`**: every original skill, copied word for word as `SKILL_SOURCE.md`, with a searchable `library/INDEX.md`. The files are renamed so that hosts don't register 415 separate skills.

## Install

**Claude Code**
```bash
git clone https://github.com/<you>/omniskill ~/.claude/skills/omniskill
```

**Google Antigravity** (global)
```bash
git clone https://github.com/<you>/omniskill ~/.gemini/config/skills/omniskill
# older versions: ~/.gemini/antigravity/skills/omniskill
```

**Per project** (either host)
```bash
git clone https://github.com/<you>/omniskill .agents/skills/omniskill   # Antigravity
git clone https://github.com/<you>/omniskill .claude/skills/omniskill   # Claude Code
```

Restart the app. The skill triggers automatically for software tasks, or you can call it with `/omniskill` (Claude Code) or "Use the omniskill skill to …".

## Notes

- `library/` contains third-party scripts. The skill tells agents to read a script before running it.
- The upstream repos change over time. This is a snapshot taken on 2026-11-24.

## License

Original playbooks and router: MIT (see `LICENSE`). All content under `library/` remains the work of its original authors under their MIT licenses, which are reproduced in `library/LICENSES/`.
