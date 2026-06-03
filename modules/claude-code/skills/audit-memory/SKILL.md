---
name: audit-memory
description: USE WHEN running memory hygiene, the user says "audit memory" / "prune memory" / "check stale memories", or it has been >30 days since last memory pass — walks each MEMORY.md entry through verify_by + canonical-source check + recency/importance reassessment, proposes diffs, never rewrites unilaterally
---

# audit-memory

Periodic (or on-demand) hygiene for `~/.claude/projects/*/memory/`. Walks each entry through a decision tree and **proposes diffs** — does not delete, archive, or rewrite memory bodies unilaterally. The operator approves per-entry or batched.

Run from the namespace whose memory you want to audit (the cwd at session start determines the namespace).

## Procedure

List the memory dir. For each file (other than `MEMORY.md` itself), in order of `last_verified` ascending (oldest first), walk Steps 1–4. Hold the results, then present them all in Step 5.

### Step 1 — Run `verify_by`

Execute the frontmatter `verify_by:` shell snippet. Three outcomes:

- **Passes silently** → continue.
- **Fails** → the memory may be wrong, or the snippet may be wrong. Read the body:
  - The fact migrated (file renamed, path moved) → propose an update to `verify_by` + the affected body lines.
  - The fact is no longer true → propose DELETE or significant REWRITE.
- **No `verify_by` present** → propose ADDING one. A memory without a verify check is unfalsifiable; flag it.

Don't conclude from a single failing snippet that the memory is wrong — the snippet may have a typo.

### Step 2 — Canonical-source check

Is the underlying fact now captured in an authoritative source?

- An ADR file under `docs/decisions/`
- A test file (regression test that encodes the fact)
- A commit message visible in `git log` for the relevant path
- A spec doc under `docs/`
- An entry in `CHANGELOG.md`

If yes, and the memory body just duplicates that source: **propose DELETE**. The canonical source is the SoT; a memory that paraphrases it adds drift risk.

If the memory contains gotcha / context not captured in the canonical source: propose **TRIM** — keep only the gotcha; replace the rest with a pointer to the source.

### Step 3 — Recency / use-since-last-verified

Has the file's mtime changed since `last_verified`? Two cases:

- **No mtime change, but the topic likely came up** (e.g., you've been doing work in the relevant project but the file is untouched) → the USE-WHEN trigger is probably failing to fire. Propose SHARPENING the description.
- **No mtime change, topic genuinely didn't come up** → propose DOWNGRADING importance by one notch. Less-used memory should rank lower.

### Step 4 — Score and archive threshold

Compute: `score = importance × recency_weight`, where `recency_weight = max(0, 1 - days_since_verified/180)`.

- `score < 2.0` → propose ARCHIVE (move to `ARCHIVE.md`, off the live `MEMORY.md` index; the file stays on disk for grep).

Notes:
- A `verify_by`-FAIL or a canonical-source dedup overrides the score: DELETE / TRIM wins.
- Importance 9–10 with reasonable recency rarely scores below threshold; that's intentional.

### Step 5 — Present results

Don't edit unilaterally. Present results as a structured proposal:

```
## Memory audit — <date>  (namespace: <path>)

### Entry: <name>  [<action>]
- verify_by: PASS | FAIL (<reason>)
- canonical-source: yes (<path>) | no
- staleness: <days> days since last_verified
- importance: <current> → <proposed>
- score: <importance × recency_weight>
- rationale: <one line>
- proposed diff: <inline if small, "show on request" if large>
```

Then list any proposed changes to `MEMORY.md` (entries removed for archive, entries reworded for sharpening).

End with an explicit ask: **"Apply these changes? (all / per-entry / abort)"**

## What not to do

- **Don't delete on a single failing `verify_by`** without reading the body — the snippet may be wrong, not the fact.
- **Don't archive an entry just for being old.** Old + load-bearing (importance 8+) is fine. The score is the gate.
- **Don't merge memories** without explicit operator direction; merging changes meaning.
- **Don't run audit in the same turn as writing a new memory** — write first, audit separately.
- **Don't edit `MEMORY.md` index lines** before the operator approves the corresponding file changes.

## Promotion candidates

While walking, note entries that look like promotion candidates:

- Same pattern appears in 2+ projects' memory → orchestration-level
- Procedural ("do X then Y") and project-independent → global skill (homelab/modules/claude-code/skills/)

Surface these in the report but **don't promote unilaterally** — promotion changes scope.

## Related

- `writing-memory-entries` — the write-side checks the audit-side mirrors.
- A monthly cadence is a reasonable default; longer is fine for slow-moving projects.
