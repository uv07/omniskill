# omniskill

[![validate](https://github.com/uv07/omniskill/actions/workflows/validate.yml/badge.svg)](https://github.com/uv07/omniskill/actions/workflows/validate.yml)

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

Anyone can install it. You need `git`; nothing else. Pick **one** method.

### 1. Claude Code plugin (recommended for Claude Code)

Inside Claude Code:
```
/plugin install omniskill --marketplace uv07/omniskill
```
On older Claude Code versions, use two steps:
```
/plugin marketplace add uv07/omniskill
/plugin install omniskill@omniskill
```
Update later with `/plugin marketplace update omniskill`.

### 2. One-line installer (Claude Code and/or Antigravity)

macOS / Linux / WSL. Installs for every host it finds (`~/.claude`, `~/.gemini`):
```bash
curl -fsSL https://raw.githubusercontent.com/uv07/omniskill/main/install.sh | bash
```
Windows PowerShell:
```powershell
irm https://raw.githubusercontent.com/uv07/omniskill/main/install.ps1 | iex
```

Choose a target yourself:
```bash
git clone https://github.com/uv07/omniskill && cd omniskill
./install.sh --claude                 # ~/.claude/skills/omniskill
./install.sh --antigravity            # ~/.gemini/config/skills/omniskill
./install.sh --project ~/code/myapp   # myapp/.claude/skills and myapp/.agents/skills (commit it so your team gets it)
./install.sh --update                 # git pull every install
./install.sh --uninstall              # remove (only touches omniskill installs)
```
PowerShell takes the same options as `-Claude`, `-Antigravity`, `-Project DIR`, `-Update` and `-Uninstall`.

### 3. Manual clone

```bash
git clone https://github.com/uv07/omniskill ~/.claude/skills/omniskill          # Claude Code
git clone https://github.com/uv07/omniskill ~/.gemini/config/skills/omniskill   # Antigravity
# older Antigravity versions: ~/.gemini/antigravity/skills/omniskill
```

### Other agents

The skill is plain Markdown with standard `SKILL.md` frontmatter. Any agent that loads skill folders can use it from its skills directory. Agents without skill support can still use it: add a line such as "Before any coding task, read `<path>/omniskill/SKILL.md` and follow its router" to `AGENTS.md`, `GEMINI.md` or your rules file.

### Check it works

Restart the app, then ask: *"Which omniskill playbook applies to a flaky test?"* It should answer with `playbooks/debugging.md`. You can also call it directly with `/omniskill` (Claude Code) or "Use the omniskill skill to ...".

## Usage examples

| You say | omniskill loads |
|---|---|
| "Let's build a CSV import feature" | `playbooks/planning.md`, then `tdd-testing.md` per task |
| "This test fails intermittently" | `playbooks/debugging.md` (flaky-test section) |
| "Review my PR" | `playbooks/review-quality.md` |
| "Harden this Django view" | `playbooks/engineering-domains.md`, then `library/ecc/django-security/` |
| "Split this into parallel agents" | `playbooks/agents-context.md` |

## Repository layout

```
SKILL.md                     entry point: core rules + task router
playbooks/                   8 merged playbooks
library/INDEX.md             searchable index of all 415 skills
library/<source>/<skill>/    verbatim upstream skill (SKILL_SOURCE.md + supporting files)
library/LICENSES/            upstream MIT licenses
install.sh, install.ps1      installer / updater / uninstaller (Unix, Windows)
.claude-plugin/              Claude Code plugin + marketplace manifests
scripts/validate.py          structure + link checker (runs in CI)
.github/workflows/           CI
```

## Development

```bash
python3 scripts/validate.py   # checks frontmatter, index coverage and all 800+ internal paths
```

Issues and pull requests are welcome: bug reports, broken routes, and new MIT-licensed skill sources. See `CONTRIBUTING.md` for how to add or refresh a source, and `CHANGELOG.md` for releases.

## Notes

- `library/` contains third-party scripts. The skill tells agents to read a script before running it.
- The upstream repos change over time. This is a snapshot taken on 2026-11-24.

## License

Original playbooks and router: MIT (see `LICENSE`). All content under `library/` remains the work of its original authors under their MIT licenses, which are reproduced in `library/LICENSES/`.
