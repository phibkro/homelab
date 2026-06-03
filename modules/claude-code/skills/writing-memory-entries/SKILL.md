---
name: writing-memory-entries
description: USE WHEN about to Write or update a file under ~/.claude/projects/*/memory/, edit MEMORY.md, or save a "remember this"/"add a memory" — runs the smell/shape/dedup/importance/verify checks so memory stays a retrieval index, not a journal
---

# writing-memory-entries

Run this BEFORE writing or updating any memory file or `MEMORY.md` entry.

## The lifecycle ladder

Memory lives on a knowledge-promotion path:

```
project-local memory  →  orchestration memory  →  global skill
   (one project)          (cross-project, at         (universal,
                           /srv/share/projects/)      nix-managed in homelab)
```

A new memory starts project-local. When the same pattern recurs in a second project, promote to orchestration. When it becomes procedural (a "how to do X") that would apply to a future fresh project, promote to a global skill (homelab nix module → rebuild).

## Five checks, in order

### 1. Smell test — is this a log entry?

If the candidate reads like a commit message ("Fixed X", "Added Y", "Refactored Z"), the fact is probably already captured. Check, cheaply, in this order:

- `git log --grep` for the change
- `docs/decisions/` for an ADR
- `CHANGELOG.md`
- spec docs under `docs/`

If discoverable in any of those, **do not write the memory.** Git/ADRs are authoritative; a duplicate memory just adds drift risk and grows the index.

**Exception:** the *gotcha* or *non-obvious context* — what was tried first and didn't work, the obvious-but-wrong alternative, the subtle invariant a reviewer wouldn't catch. Write the gotcha, not the change. The change is in git.

### 2. Shape test — USE-WHEN trigger

The `description:` field and the MEMORY.md index line must read as:

> **USE WHEN \<concrete situation\> THEN \<concrete action or pointer\>**

- `<concrete situation>` = grep-able terms a future agent would naturally use: project name, file path, error string, system noun. Not abstract framings like "general context" or "background notes."
- `<concrete action>` = pointer to authoritative source (ADR, test, file:line, commit) + a one-line why. Not a paraphrase of the source.

If you cannot write a USE-WHEN line, the entry is too vague to be retrieved at the right moment. Sharpen or skip.

### 3. Dedup test

`grep` `MEMORY.md` for the system or project keyword. If a similar entry exists, **update it** — don't add v2. Multiple memories chasing one moving target is a smell.

### 4. Importance score (1–10) — set in frontmatter

- **1–3** — nice-to-know. Delete candidate within a month.
- **4–6** — load-bearing for one specific situation.
- **7–9** — shapes the direction of multiple tasks.
- **10** — reserved for "ignoring this will cause a real incident."

Set honestly at write time. Inflating importance to "make sure it's seen" corrupts the prune signal.

### 5. Verify-by — every memory carries a cheap check

Every memory frontmatter has a `verify_by:` shell snippet that confirms the memory is still true. Without it, staleness is unfalsifiable and the audit skill has nothing to grip.

Examples:
- `ls path/to/expected/file`
- `grep -q "expected-symbol" path/to/file`
- `git log --oneline -1 -- path/to/relevant/dir`
- `cd project && deno task test:specific`

The snippet should run in <2s and have a clear pass/fail.

## Frontmatter template

```yaml
---
name: <kebab-case-id>
description: USE WHEN <situation> THEN <action/pointer>
metadata:
  node_type: memory
  type: feedback|project|reference|user
importance: <1-10>
last_verified: <YYYY-MM-DD>
verify_by: "<cheap shell check>"
---
```

For `feedback` and `project` types, structure the body as:

```markdown
<the fact or decision, one paragraph>

**Why:** <reason or incident, so future-you can judge edge cases>
**How to apply:** <when/where this kicks in>
```

## Index line template (`MEMORY.md`)

```
- [<title>](file.md) — USE WHEN <situation>; <action/pointer>
```

Lead with the project or system noun. Keep each line under ~150 chars. The index is loaded into every session as a billboard for what's *available*; the file body is loaded only when the index entry pattern-matches the current task.

## Anti-patterns

- **Journal-style bodies** that grow with each session ("then we did X, then we tried Y, then we discovered Z"). Memory is state, not change history; git holds change history.
- **Generic noun-phrase descriptions** ("notes on X", "context for Y") — fail the shape test, won't be retrieved.
- **Multiple files for one moving target** — update in place; no v2/v3 sprawl.
- **Restating what's in an ADR, spec, or test** — point to it; one source of truth.
- **Inflated importance scores** — corrupts the prune ranking. Use the scale honestly.
- **Missing `verify_by`** — makes the audit pass have nothing to do.

## Promotion criteria

**Project-local → orchestration** (move the file to `~/.claude/projects/-srv-share-projects/memory/`):
- The same pattern appears in a second project, OR
- The fact is cross-project by nature (shared toolchain, user preference, repo conventions across the org)

**Orchestration → global skill** (add to `homelab/modules/claude-code/skills/` and `just rebuild`):
- It's procedural (`do X then Y then Z`) rather than factual
- It would apply to a future fresh project, not just the current set
- It deserves to be loaded into every Claude Code session everywhere, not just under `/srv/share/projects/*`

## When the audit skill runs (related)

`audit-memory` walks each entry:
1. Run `verify_by`. Pass? → continue. Fail? → update or delete.
2. Is the fact now in an ADR / CHANGELOG / git commit? → delete memory, source is authoritative.
3. Has the entry been touched since `last_verified`? If no, downgrade importance.
4. importance × recency below threshold → archive to `ARCHIVE.md`, off the live index.
