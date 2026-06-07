---
description: USE WHEN auditing code comments, filenames, recipe/skill names, or cross-references for staleness — "audit X", "clean up comments in X", "review the docs map", "the recipe names feel off", or after a major refactor that touched many files. Applies the earns-rent vs cut taxonomy + the verb-object naming rule + the last-line-summary pattern + the lists-from-code rule. Workflow per file: audit table → operator ack → apply → verify clean build → batch-commit. Codified from the 2026-06-07 audit sweep (`git log --grep "^chore(comments):"` + the docs/Justfile renames).
---

# Audit structure

The operational form of `docs/DOCUMENTATION_WRITING.md`. That doc carries
the principles; this skill carries the *process* — what to check, in
what order, how to surface candidates, how to apply safely.

## Core principle (the lens)

> **Code describes behavior. Comments encode intent.**
>
> A useful comment is a semantic test: it fires when a reader's eyeball
> spots the mismatch between what the code does and what it should do.
> If the next reader would figure out the intent without the comment,
> delete the comment.

Same principle generalizes to filenames, recipe names, skill
descriptions: the artifact must encode intent at the surface so the
amnesiac reader doesn't have to infer.

## The four audit dimensions

Each dimension has its own check pattern; the skill walks all four for
any target.

### 1. Code comments

Apply the **earns-rent test** to every comment block:

> "Would the next reader figure out the intent without this comment?"
> Yes → delete. No → keep. Partial-no → tighten.

| Earns rent (KEEP)                          | Doesn't (CUT)                          |
|--------------------------------------------|----------------------------------------|
| Why the obvious approach didn't work       | What-paraphrase of the code            |
| Incident anchor (date + symptom + fix)     | How-step-by-step (the code is steps)   |
| Silent-breakage / sharp-edge warning       | Author / date / "added for X"          |
| Counter-intuitive constraint               | Status banners on dead code            |
| Deliberate absence (intentional omission)  | Transcribed framework / man-page docs  |
| Cross-ref to spec / skill / ADR / runbook  | List-of-derived-things                 |

### 2. Filenames

Filename must encode TOPIC (what the file is about) sharply enough
that `ls` alone hints at contents — no index lookup required.

* **Bad**: `STYLE.md` (style of what?), `CONCEPTS.md` (generic),
  `PROCEDURES.md` (vague).
* **Good**: `DOCUMENTATION_WRITING.md`, `GLOSSARY.md`,
  `SKILL_INDEX.md`, `MODULE_AUTHORING.md`, `RUNTIME_TESTS.md`.

Naming convention by tree:

| Tree                              | Convention                                                                |
|-----------------------------------|---------------------------------------------------------------------------|
| `docs/*.md` (tier-2 reference)    | UPPER_SNAKE_CASE; topic-encoding                                          |
| `docs/runbooks/`, `decisions/`    | lower-kebab-case (procedural / numbered)                                  |
| `.claude/skills/<name>/SKILL.md`  | lower-kebab-case; verb-object or `gotcha-<technology>-<symptom>`          |
| `scripts/*.sh`                    | lower-kebab-case; verb-object or noun-prefix-procedural                   |
| `modules/services/<svc>.nix`     | lower-kebab-case; service name                                            |

### 3. Recipe / skill names

Verb-object — name carries both a VERB (action) and an OBJECT (target).
Pure nouns are wrong: no verb means unclear what the recipe does.

* **Bad** (no verb): `pending`, `status`, `ports`, `logs`, `oidc-key`.
* **Good** (verb-object): `show-pending-diff`, `show-status`,
  `list-ports`, `show-logs`, `generate-oidc-key`.
* **OK exception**: single-verb where object is "this host's current
  config" — implicit + universal (`rebuild`, `preview`, `build`,
  `boot`, `deploy`, `rollback`).

Cluster naming: match the verb prefix of existing similar recipes
(`show-*`, `list-*`, `test-*`, `generate-*`, `check-*`, `update-*`)
so `just --list | grep ^<verb>-` returns the cluster.

Skill descriptions must start with `USE WHEN <trigger phrases> — <what
it does>`. Claude's auto-discovery matches on the first tokens; the
trigger phrase IS the matching surface.

### 4. Last-line-summary pattern

Anywhere a tool shows a one-line summary (the `just --list`
description, `man` synopsis, etc.) — make the **last** comment line
above the entity a self-contained one-liner. Multi-line elaboration
goes ABOVE that line, not below. `just --list` shows only the last
comment line; multi-line blocks lose all but the last.

### 5. Derived lists

Lists of things dependent on code (services, hosts, subvolumes,
skills, lanRoutes, modules, recipes) MUST NOT be duplicated in prose.
They drift the second code changes. Either generate (`nix eval`-driven
docs), link the live registry (`nix flake show`, `just --list`, `ls
.claude/skills/`), or eliminate the doc. If a doc is purely
derivative, eliminate it.

## Workflow per file

The per-file workflow that worked across 30+ files this session:

1. **Read the target file** completely (no skim — sub-readings miss
   structural drift).

2. **Build the audit table** with columns:

   | Block | Lines | Earns rent? | Action |
   |---|---|---|---|

   One row per non-trivial comment block + per name/structural element
   that fails one of the four dimensions. Mark `✅` (keep), `⚠` (tighten),
   `❌` (cut), or `→ X` (rename to X).

3. **Surface the table to the operator** and wait for ack/redirect.
   Don't apply changes before ack — the audit table is the contract.
   The operator may push back on individual rows; honor it.

4. **Apply the acked changes** in a single edit pass per file. Keep
   incident-anchored comments verbatim (date + symptom + fix). Keep
   cross-references to specs / skills / runbooks. Cut paraphrases.

5. **Verify clean build** (`just rebuild` for homelab; equivalent for
   other projects). The audit must not change behavior.

6. **Show the diff stat** (`git diff --stat -- <file>`) so the
   operator sees the net delta.

7. **Move to next file**. Accumulate changes in the working tree;
   commit as a coherent batch at the end of a logical group.

## Anti-patterns catalog (from the 2026-06-07 sweep)

What to grep for specifically:

| Pattern                                  | How to detect                                                              |
|------------------------------------------|----------------------------------------------------------------------------|
| Overshooting "Why this exists" headers   | 20+ line preamble comments at file top once the abstraction has stuck      |
| Taxonomy duplicated 2-3 times            | The same role/tier/enum prose appears in header + option desc + enum value |
| Inline assertion preamble                | `# Hard constraints — ...` above an `assertions` block                     |
| Dead code with "preserved" comment       | Unused vars/blocks with "kept from operator's script" notes                |
| Misplaced comment block                  | Comment paragraph followed by an unrelated config block                    |
| Stale TODOs / "Open items"               | Multi-week-old "post-deploy checklist" or "needs adding when..." notes     |
| Cross-referenced rationale at both ends  | Same explanation in the abstraction docs AND in machine/service configs    |
| Per-section paraphrase in list literal   | `# user-level CLAUDE.md` on attr `~/.claude/CLAUDE.md`                     |
| Transcribed framework docs               | Per-flag systemd.exec/man-page glossary inline                             |
| Per-subvol layout enumeration            | A layout diagram repeating disko's literals                                |
| Last-line `just --list` fragment         | Multi-line block above a recipe ending mid-sentence or with "Usage:"       |
| Recipe name without verb                 | `pending`, `status`, `option` — pure nouns                                 |
| Filename that doesn't predict contents   | `STYLE.md` — style of what?                                                |

## Output format (when reporting)

Use a markdown audit table per file (Block | Lines | Earns rent? |
Action). End with a one-sentence net assessment: "File is tight, pass
through" / "Estimated cut: ~N lines" / "Renames recommended: X → Y, A → B".

Group audits into logical batches (a dir, a related set of modules) and
commit each batch with a `chore(comments): audit <scope>` message
including:
* Net line delta (`git diff --stat` summary)
* Categories of cuts (e.g., "header preambles + dead code + paraphrase")
* Categories KEPT verbatim (e.g., "incident anchors + sharp-edge warnings")
* Any files passed through unchanged with a reason

## What this skill does NOT do

* **Does not invent new conventions.** The conventions live in
  `docs/DOCUMENTATION_WRITING.md`, `CLAUDE.md`, and this skill. If a
  proposed change isn't covered, surface it as a question rather than
  applying.

* **Does not autonomously rename across the tree without confirmation.**
  Renames affect cross-references; surface candidates, get ack, then
  apply renames + grep/sed updates as one atomic batch.

* **Does not delete incident-anchored comments.** A comment with a date
  + symptom + fix is load-bearing operator knowledge. Even if it looks
  verbose, it earns rent.

* **Does not exceed the user's stated scope.** If asked to audit
  `modules/services/arr/`, stop at the boundary — don't drift into
  adjacent dirs unless asked.

## Reference

* `docs/DOCUMENTATION_WRITING.md` — full taxonomy + anti-patterns +
  the amnesiac-imitation feedback loop
* `git log --grep "chore(comments):"` — worked examples; 30+ files
  audited across `modules/effects/`, `home/`, `machines/`
* `git log --grep "^docs:" --grep "^just:"` — the docs + Justfile
  rename commits (read for the rename rationale + USE-WHEN convention)
* `CLAUDE.md` § "Style for prose" + § "What's the bias" — the
  always-injected version of the inference-cost-minimization principle
