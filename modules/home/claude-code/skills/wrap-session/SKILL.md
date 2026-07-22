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

## Context-rot checkpoint mode

Use this mode when the Herdr manager reports that this lane is near its context
threshold (approximately 20% remaining), or when the manager explicitly requests
a context-rot handoff. This is an early in-flight checkpoint, not an ordinary
session ending. The monitor detects context pressure and wakes the manager; this
skill does not infer pressure from conversation prose or mutate other panes.

When this mode is selected, run it before the ordinary push step below:

1. Read the project instructions, `git status --short`, `git log --oneline -10`,
   and the project's existing SSoT edge document (`CONTEXT.md`, an active
   `PATH-*.md`, or `handoff.md`). If there is no unambiguous existing edge
   document, stop and report the blocker; never create a parallel handoff store.
2. Determine a filesystem-safe lane name and create
   `handoff/<lane>-<YYYYMMDDTHHMMSSZ>` from the current branch.
3. Run the bounded project gate when feasible. Record its exact command and
   result. A red or unavailable gate belongs in `left`; it is not `verified`.
4. Stage intended WIP, excluding the edge document, and commit it as the
   durable WIP checkpoint. Do not discard unrelated changes. If a documented
   skip mechanism is needed for knowingly red WIP, explain why in `left`.
5. Resolve the WIP commit with `git rev-parse HEAD`, then write the following
   compact contract into the existing edge document and commit that document
   separately:

   ```markdown
   ## Context-rot handoff
   - done: <completed artifacts or "none">
   - verified: <gate command + result tied to WIP SHA, or "none — reason">
   - left: <unfinished work>
   - current edge: <one line stating exactly where work is>
   - next concrete action: <one executable action>
   - gotchas / traps: <successor hazards and claims to re-check>
   - wip branch: <handoff/...>
   - wip branch sha: <full 40-character WIP SHA>
   ```

   The WIP SHA is the durable referent. The edge-document commit is its child;
   a commit cannot contain its own SHA. Verify the WIP SHA exists and is an
   ancestor of the handoff branch tip, and leave the tree clean.
6. Use the `handoff <pane>` relaunch recipe after the checkpoint. It validates
   the branch, edge document, WIP SHA, and ancestry; exits the old provider;
   and launches a new provider process in the same pane seeded with:
   `read <edge-doc>, verify <WIP SHA>/<branch tip>, continue from the next
   concrete action`. Never use `--resume`, `--continue`, or `fork` here.

The successor must independently inspect Git and run the named gate. Treat the
summary as a routing hint, not evidence. A rotted agent summarizing itself is
self-validation, so every verified claim must be tethered to the committed WIP
SHA, Git history, edge document, and gate. Do not push, merge, or alter unrelated
project state as part of this context refresh; the fresh session may invoke the
ordinary wrap-up mode later when it actually ends.

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
