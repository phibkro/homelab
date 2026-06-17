---
name: wrap-session
description: Run an end-of-session wrap-up so the next agent (likely you, with zero context) lands cleanly — push pending commits, refresh the project's orientation docs if reality shifted, update durable memory, verify clean state, and end with a compact handoff (summary, suggested skills, references). Use when the user signals the session is wrapping up — "wrap up", "ending session", "that's it for now", "we're done", "session end", "done for today", or "anything else before we end?".
---

# Session wrap-up

A new agent with zero context should be able to read the project's orientation docs
+ `git log --oneline -10` + the latest commit bodies and know exactly where you left
off. If they'd be confused, the wrap-up isn't done.

> **Project-specific bits live in the project's own `CLAUDE.md`/`AGENTS.md`** — which
> docs are the source of truth, the health-check command, where durable memory lives.
> This skill is the project-agnostic skeleton; defer to the project supplement for
> specifics.

## Live context at invocation

- Working tree: !`git status --short`
- Pending unpushed commits: !`git log --oneline @{u}.. 2>/dev/null || echo "(branch not tracking remote)"`
- Recent commit history: !`git log --oneline -10`

## Procedure

### 1. Push pending commits

If any local-only commits exist, push them — local-only commits are invisible to the
next agent. If a push fails, surface the reason and stop; don't force-push without an
explicit go-ahead.

### 2. Refresh the orientation docs if reality shifted

Walk the project's source-of-truth docs (e.g. `CONTEXT.md`, `AGENTS.md`, `README`,
`CLAUDE.md`) and update what changed this session. The drift cost is asymmetric: a
stale doc misleads the next agent immediately; an up-to-date one costs nothing.

- **Current state** — architecture, status, what's shipped vs. in progress.
- **Outstanding** — prune what's done; add what this session surfaced.
- **Rule of three** — if a new pattern landed twice or more this session, codify it
  (a skill if the trigger is clean, otherwise a "How to" in the docs).

### 3. Update durable memory if cross-session facts shifted

If the project keeps cross-session memory, update it (don't duplicate what's already
in the docs — memory is for cross-project / user-personal facts). Resolved items get
archived, not deleted; new items the next session needs get added.

### 4. Verify clean state

Spot-check nothing is mid-flight: `git status` clean, and the project's health check
green (test suite / CI / status command — see the project supplement). If something
is unreachable or mid-migration, surface it explicitly.

### 5. End with a compact handoff

The bridge for the next agent. Three sections, kept tight — **link, don't duplicate**,
and redact secrets (API keys, tokens, PII):

- **Summary** — what changed (commits pushed, decisions made), one non-obvious thing
  learned worth carrying forward, and the immediate next concrete action.
- **Suggested skills** — which skill the next agent should reach for to resume (e.g.
  "resume at `tdd` for the half-built parser", "`grill-with-docs` the open design").
- **References** — paths/links to the artifacts (commits, docs, ADRs, issues), not
  their contents. If the user named a focus for next session, tailor the handoff to it.

Specific beats thorough: a fresh agent reading this should orient in under 30 seconds.

## What this skill does NOT do

- Push without checking the commit history first (force-push is destructive — surface
  and ask).
- Delete memory without archiving first (recovery from archive is cheap; deletion is
  permanent).
- Run in-flight work — restart services, run migrations, change config. That's work,
  not wrap-up.

If the session ended mid-task, say so in the summary rather than masking the loose
end. An honest "X deferred because Y; next session picks it up at Z" beats pretending
it's done.
