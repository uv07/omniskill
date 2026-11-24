# Contributing

## Layout rules

- `SKILL.md` is the only file named `SKILL.md`. Library skills are stored as
  `SKILL_SOURCE.md` so hosts register one skill, not 415.
- `library/<source>/<skill>/` holds upstream content **verbatim**. Don't edit it;
  refresh it from upstream instead.
- `playbooks/*.md` are the merged, edited guidance. When you add a rule, add the
  `Source detail:` path it came from.
- Every `SKILL_SOURCE.md` must have a row in `library/INDEX.md`.

## Adding or refreshing a source

1. Copy each upstream `SKILL.md` to `library/<source>/<skill>/SKILL_SOURCE.md`,
   with its supporting files beside it.
2. Add the upstream license to `library/LICENSES/`.
3. Add index rows to `library/INDEX.md` and update the skill count in the
   `SKILL.md` description and `README.md`.
4. Route new domain skills from the catalog in `playbooks/engineering-domains.md`.
5. Run `python3 scripts/validate.py` and fix every error.
6. Add a `CHANGELOG.md` entry.

## Checks

```bash
python3 scripts/validate.py   # structure, index coverage, every referenced path exists
shellcheck install.sh
```

CI runs both on every push and pull request.
