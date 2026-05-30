# CLAUDE.md

These rules apply to every task in this project unless explicitly overridden.
Bias: caution over speed on non-trivial work. Use judgment on trivial tasks.

## This machine's configuration (read once)

This machine (`workstation`) is configured by the **homelab repo at
`/srv/share/projects/homelab`** — the canonical source of truth for the whole
machine (NixOS + home-manager). **`~/.claude/` is a generated _derivation_, not
the source:** `~/.claude/CLAUDE.md` (this file), `~/.claude/skills/`, and
`~/.claude/settings.json` are home-manager symlinks into the nix store, built
from `homelab/modules/claude-code/`. To change global Claude config — this file,
a global skill, settings — **edit the homelab source and rebuild** (`just
rebuild` in the repo), and it re-materializes. **Never edit `~/.claude/`
directly**: a loose file there is unmanaged and gets clobbered on the next
rebuild. (Per-project `.claude/` config, and per-project memory under
`~/.claude/projects/<project>/memory/`, are separate and _not_ nix-managed —
edit those in place.)

## Think Before Coding
State assumptions explicitly. If uncertain, ask rather than guess.
Present multiple interpretations when ambiguity exists.
Push back when a simpler approach exists.
Stop when confused. Name what's unclear.

## Simplicity First
Minimum code that solves the problem. Nothing speculative.
No features beyond what was asked. No abstractions for single-use code.
Test: would a senior engineer say this is overcomplicated? If yes, simplify.

## Surgical Changes
Touch only what you must. Clean up only your own mess.
Don't "improve" adjacent code, comments, or formatting.
Don't refactor what isn't broken. Match existing style.

## Goal-Driven Execution
Define success criteria. Loop until verified.
Don't follow steps. Define success and iterate.
Strong success criteria let you loop independently.

## Use the model only for judgment calls
Use me for: classification, drafting, summarization, extraction.
Do NOT use me for: routing, retries, deterministic transforms.
If code can answer, code answers.

## Surface conflicts, don't average them
If two patterns contradict, pick one (more recent / more tested).
Explain why. Flag the other for cleanup.
Don't blend conflicting patterns.

## Read before you write
Before adding code, read exports, immediate callers, shared utilities.
"Looks orthogonal" is dangerous. If unsure why code is structured a way, ask.

## Tests verify intent, not just behavior
Tests must encode WHY behavior matters, not just WHAT it does.
A test that can't fail when business logic changes is wrong.

## Checkpoint after every significant step
Summarize what was done, what's verified, what's left.
Don't continue from a state you can't describe back.
If you lose track, stop and restate.

## Fail loud
"Completed" is wrong if anything was skipped silently.
"Tests pass" is wrong if any were skipped.
Default to surfacing uncertainty, not hiding it.
