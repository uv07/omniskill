#!/usr/bin/env python3
"""Validate the omniskill repo structure. Stdlib only. Exit code 1 on any error.

Checks:
  1. SKILL.md has valid frontmatter (name, description <= 1024 chars).
  2. Every `library/...` or `playbooks/...` path referenced in SKILL.md,
     playbooks/*.md and library/INDEX.md exists.
  3. Every library/**/SKILL_SOURCE.md is listed in library/INDEX.md.
  4. No file named SKILL.md exists under library/ (hosts would register it).
  5. The skill count stated in SKILL.md matches the library.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATH_RE = re.compile(r"`((?:library|playbooks)/[^`\s]+)`")
errors = []


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip()
    return fm


skill = (ROOT / "SKILL.md").read_text(encoding="utf-8")
fm = frontmatter(skill)
if fm is None:
    errors.append("SKILL.md: missing YAML frontmatter")
else:
    if fm.get("name") != "omniskill":
        errors.append(f"SKILL.md: name should be 'omniskill', got {fm.get('name')!r}")
    desc = fm.get("description", "")
    if not desc:
        errors.append("SKILL.md: description is empty")
    elif len(desc) > 1024:
        errors.append(f"SKILL.md: description is {len(desc)} chars (max 1024)")

docs = [ROOT / "SKILL.md", ROOT / "library" / "INDEX.md", *sorted((ROOT / "playbooks").glob("*.md"))]
refs = 0
for doc in docs:
    for n, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
        for ref in PATH_RE.findall(line):
            ref = ref.rstrip(".,;:)")
            if any(ch in ref for ch in "*<>{}") or "/x/" in ref:
                continue  # glob or placeholder, not a concrete path
            refs += 1
            if not (ROOT / ref).exists():
                errors.append(f"{doc.relative_to(ROOT)}:{n}: missing path {ref}")

index = (ROOT / "library" / "INDEX.md").read_text(encoding="utf-8")
sources = sorted((ROOT / "library").rglob("SKILL_SOURCE.md"))
for src in sources:
    rel = src.relative_to(ROOT).as_posix()
    if rel not in index:
        errors.append(f"library/INDEX.md: not listed: {rel}")

for bad in (ROOT / "library").rglob("SKILL.md"):
    errors.append(f"{bad.relative_to(ROOT)}: rename to SKILL_SOURCE.md so hosts do not register it")

m = re.search(r"\((\d+) skills\)", fm.get("description", "") if fm else "")
if m and int(m.group(1)) != len(sources):
    errors.append(f"SKILL.md says {m.group(1)} skills, library has {len(sources)}")

print(f"skills: {len(sources)}  playbooks: {len(docs) - 2}  path refs checked: {refs}")
if errors:
    print(f"\n{len(errors)} error(s):")
    for e in errors:
        print("  -", e)
    sys.exit(1)
print("OK")
