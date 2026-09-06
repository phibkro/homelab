---
summary: Source ownership, execution boundaries, delegation and verification for agents.
---

# Agentic workflow

[AGENTS.md](../../AGENTS.md) is the shared entry point; harness adapters reference
it. Instructions apply to the current checkout and task. User direction and
existing authorization take precedence over repository procedures.

```text
Orient → establish scope → implement → verify → report evidence
```

Read repository state before making claims or planning edits. Identify the
canonical source, its consumers, and the behavior that must hold. Share a concise
scope and acceptance criteria for substantial work; read-only investigation does
not require a separate approval. Continue authorized work through verification.
Ask for missing authority only when the next external or destructive effect
exceeds the user's instruction, after preparing a concrete reviewable result.

## Shared work

Preserve pre-existing edits. Use an isolated checkout for a substantial refactor
when needed, with its base revision and ownership recorded. Do not reset, clean,
or stage another writer's work wholesale. Delegate only bounded independent
work, with explicit file ownership, acceptance checks, forbidden effects and a
cleanup condition. The integrating agent verifies contributors' claims.

Coordinate expensive builds, VM tests and browser suites: one heavy job at a
time per project lead. Give fixtures explicit state and port ownership; stream
logs while they run. Stop only processes known to belong to the task. Preserve
durable results before removing disposable resources.

## Validation and delivery

Use `just check` for fast Nix checks and `just pi::check` for Ansible checks.
Run affected builds and relevant `just check-vm [name]` or `just pi::test` journeys.
`just check-all` selects the full Nix suite. These groups have different evidence
scopes; a static pass does not prove deployment or restore behavior. Choose tests
using [testing methodology](testing-methodology.md), and follow
[deployment](deployment.md) for live effects.

Commit focused changes after reviewing the staged diff. Hooks validate; fixing
and formatting are explicit operations. Record the exact tested revision,
working-tree state, commands, results, log locations and unavailable checks.
Recheck changed behavior after fixes; do not repeat unrelated expensive suites
without a new reason. Report done, verified and remaining after significant
steps and when handing work off.

Keep lasting facts in code, generated projections or the appropriate current
document. Update the [documentation map](../README.md) when routing changes and
use the [onboarding exercise](../installs/agent-onboarding-test.md) to expose gaps.
Historical plans and reports retain their context; they do not override current
configuration or session authority.
