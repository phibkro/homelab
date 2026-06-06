# CLAUDE.md

These rules apply to every task in this project unless explicitly overridden.
Bias: caution over speed on non-trivial work. Use judgment on trivial tasks.

## This machine's configuration (read once)

This machine (`workstation`) is configured by the **homelab repo at
`/srv/share/projects/homelab`** — the canonical source of truth for the whole
machine (NixOS + home-manager). **`~/.claude/` is a generated _derivation_, not
the source:** `~/.claude/CLAUDE.md` (this file), `~/.claude/skills/`, and
`~/.claude/settings.json` are home-manager symlinks into the nix store, built
from `homelab/home/claude-code/`. To change global Claude config — this file,
a global skill, settings — **edit the homelab source and rebuild** (`just
rebuild` in the repo), and it re-materializes. **Never edit `~/.claude/`
directly**: a loose file there is unmanaged and gets clobbered on the next
rebuild. (Per-project `.claude/` config, and per-project memory under
`~/.claude/projects/<project>/memory/`, are separate and _not_ nix-managed —
edit those in place.)

**Working across the several projects on this machine** — which repo is what,
how to build/test each, the shared conventions and gotchas — is mapped in
`/srv/share/projects/homelab/docs/PROJECTS.md` (also surfaced at
`/srv/share/projects/AGENTS.md`). Read it before orchestrating multiple repos.

## Tooling is a `nix shell` away (don't get stuck on a missing command)

Almost any tool is available ad-hoc without installing anything — run it via
`nix shell nixpkgs#<pkg> -c <cmd>` (e.g. `nix shell nixpkgs#jq -c jq .`) or
`nix run nixpkgs#<pkg> -- <args>`. A "command not found" on PATH is rarely a
dead end: reach for nixpkgs first (node, pnpm, ripgrep, jq, shellcheck, …).

For work _inside a project_, prefer the project's own dev shell if it has one
(`nix develop`, or `direnv` auto-loads it from `.envrc`): it pins the exact
toolchain (node/pnpm/etc.) via the project's own `flake.lock`. Some projects
also ship a **supply-chain sandbox** — run untrusted dev commands (`pnpm
install`, test, build) through `scripts/dev-sandbox.sh` (bubblewrap: repo
read-write, `$HOME` secrets invisible, env scrubbed, network droppable with
`--no-net`), so a malicious dependency can't read your keys or escape the repo.

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

## Run the real journey
For anything touching a security, I/O, network, or system boundary, watch the
real end-to-end journey run against the real system — including the model, the
network, the cloud — before calling it "verified." Green or stubbed tests are
necessary, not sufficient: a stub removes exactly the seam where the bug hides,
so the bug lives in what the stub faked. The cost is seconds; the findings are real.

## Correctness by construction
Make illegal states unrepresentable — reach for types first; reserve runtime
checks for what types can't express. Pre-launch (no external API consumers yet),
prefer the correct model over backwards-compat — change public shapes freely to
reach it; a compromise shape kept only for compat is a worse model.
Deep dive: `~/.claude/artifacts/correctness-by-construction.md`.

## Config is explicit at boundaries
No hidden defaults at module / API / system boundaries — the caller declares the
intent, not the receiver. A surprising default is a bug waiting to surface; an
opaque "we'll guess" path is worse than a loud "you must declare." If a value
matters, expose it. If it doesn't, lift it out of config entirely — don't bury
it as a default no reader will discover.

## Design only when the work is conceptual
Brainstorming/design earns its keep for conceptual/ambiguous work — new
abstractions, mental models, cross-cutting decisions. Mechanical, well-shaped work
(a localized fix, an obvious addition, a known refactor) skips straight to TDD
(or `diagnose` for a bug); code in a design doc is illustrative, not the
implementation. Two modes: **feature** (research → analysis → abstraction-design →
TDD → wrap) vs **task/issue** (research → solve → match conventions, no
abstraction phase). The `dev-loop` skill routes this.

## Explore the state of the art first
Before inventing a codebase-local solution, look up how this shape of problem is
solved in the wild (reliable sources), then match it to the codebase's shape.
Don't jump straight to local invention — this holds in both modes above.

## One construct per problem
Unify mechanisms that share an underlying problem; introduce separate constructs
only for genuinely separate problems (e.g. separate presentations sharing one
dispatch). Collapsing parallel systems into one construct is the win, even if the
diff widens.

## Dependencies: judge by attack surface, not bundle size
Take a dependency when it's reliable and improves correctness/quality; one already
in the tree (even transitively) adds ~no attack surface and beats hand-rolling.
Hand-roll only the security-critical core and fiddly/unreliable deps. "Minimal
trusted core" means minimize attack surface, not dependency count.

## Commit to the working branch (solo dev)
This is a solo-with-agents workflow: commit directly to the working branch
(usually `main`). Don't create or suggest feature branches — this overrides any
generic "branch off the default branch first" habit. Pushing is the operator's call.

## Memory hygiene
At session start, announce which `MEMORY.md` entries are relevant to the task — don't silently use or ignore them.
When you touch a memory file, update `last_verified` to today's date.
Same fact appears in a second project's memory → flag for promotion to the orchestration namespace. Procedural + project-independent → flag for promotion to a `homelab/home/claude-code/skills/` skill. The `writing-memory-entries` skill has the full criteria.
