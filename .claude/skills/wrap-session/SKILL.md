---
description: USE WHEN the user signals session end — reconciles source, evidence, forward work, verification, publication authority, and the handoff for a fresh agent.
when_to_use: User signals the session is wrapping up with phrases such as "wrap up", "ending session", "done for today", or "anything else before we end?".
---

# Homelab session wrap-up

A fresh agent must be able to recover the project state from durable repository
artifacts. The primary entry points are `AGENTS.md`, `STATE.md`,
`docs/roadmap.md`, and recent commits. `CLAUDE.md` is only a harness entry point
to `AGENTS.md`; it does not own project state.

## Procedure

### 1. Resolve or expose incomplete work

Inspect the working tree and the task's verification evidence. Finish every
reachable action. If an external decision or credential blocks work, record the
exact boundary and completed prerequisites. Do not hide an incomplete journey
behind a summary or a green unrelated check.

Preserve operator-owned edits. Do not fold unrelated dirty files into a commit.

### 2. Reconcile durable state

Update only the authoritative artifact for each fact:

| Fact | Authoritative home |
|---|---|
| Current mission and lifecycle | `STATE.md` |
| Forward work and explicit deferrals | `docs/roadmap.md` |
| Current architecture and procedures | `docs/reference/` and `docs/runbooks/` |
| Accepted contract | `docs/specs/` |
| Dated runtime evidence | `docs/archive/reports/` |
| Host, workload, route, and backup declarations | `src/inventory/` and generated projections |

Remove completed items from the roadmap. Keep historical reports and frozen
contract bodies intact. Add a status or supersession note when later work changes
how an old spec must be read.

Codify a repeated procedure only after it has occurred enough to justify owning
it. Put a cleanly triggered procedure in `.claude/skills/<name>/`; put current
operator guidance in the narrowest reference or runbook.

### 3. Verify the changed boundary

Run the specific journey that exercises the work. Then run the repository checks
required by the changed files. Record exact commands, results, the tested
revision, dirty state, and boundaries that remain unproven.

Useful read-only summaries include:

```bash
git status --short --branch
just overview
just show-status
```

These summaries do not replace a relevant build, runtime journey, or deployment
acceptance.

### 4. Commit coherent repository changes

Review the actual diff and commit only the paths owned by the completed task.
Use explicit pathspecs. Do not commit unrelated operator work.

A local commit is durable on this workstation but is not published. State that
boundary accurately.

### 5. Publish only with operator authority

A push is an external effect. Push only when the current conversation contains
applicable operator authorization. Otherwise, report the local commits and their
relation to the cached upstream reference.

Never force-push or rewrite remote history without separate explicit authority.
A failed push does not authorize a different publication method.

### 6. Retain only durable memory

Use the active harness's memory interface when a cross-conversation fact will
improve future work. Do not write legacy Claude memory directories or duplicate
facts already owned by repository source, STATE, roadmap, or reports.

### 7. End with the handoff

Report:

- commits and repositories changed;
- the exact verification that passed or failed;
- deployment and publication state;
- unresolved operator-owned decisions;
- the next concrete action from `docs/roadmap.md`.

Do not restart services, run new drills, publish, or change credentials merely
because the session is ending. Those remain normal task effects with their usual
authority gates.
