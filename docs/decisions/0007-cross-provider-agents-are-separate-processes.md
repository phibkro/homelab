# ADR-0007: Cross-provider agents run as separate processes

- Status: Accepted
- Date: 2026-07-16

## Context

Claude Code's model picker and native `Agent` tool select model identifiers, not provider transports. One Claude Code process has one `ANTHROPIC_BASE_URL` and authentication path. A direct Anthropic Fable lead cannot make selected native subagents inherit the local ClaudeX/Codex OAuth gateway, while a ClaudeX process cannot switch a selected Fable model back to first-party Anthropic authentication.

A compatibility gateway can expose both providers only by centralizing both credentials and paying through API credentials supported by that gateway. That would stop using the operator's separate Claude and Codex subscription quotas and would widen the credential boundary.

## Decision

Cross-provider delegation uses separate first-party CLI processes:

- `claude --model claude-fable-5` is the planning/orchestration lead using Anthropic authentication.
- `codex` workers use OpenAI Codex OAuth directly.
- Herdr is the terminal multiplexer and control plane. Its panes, worktree commands, status detection, waits, transcript reads, and socket API let the Fable lead dispatch and supervise Codex workers without pretending they share one native Agent tree.
- Programmatic cross-provider launches go through `agent-dispatch`, never raw `claude`/`codex`. It caps delegation at depth two and two concurrent workers.
- Every dispatched child runs under pagu-box `strict`. Sandbox capability is monotone: a child receives the parent's effective PWD mode or a narrower read-only mode, never additional host paths; a network-denied `paranoid` parent cannot spawn a cloud child because that would widen network access. Linux namespace nesting makes the outer sandbox an inescapable ceiling even if the inner CLI requests broader permissions.

The pinned Herdr package and upstream Herdr skill are installed on the Linux workstation alongside the nixpkgs Codex CLI. The Intel Mac remains on its stable, minimal package lifecycle. ClaudeX remains available when the whole Claude Code harness should run on GPT; it is not the mixed-provider orchestration boundary.

## Consequences

- Provider credentials and subscription quotas remain isolated in their first-party clients.
- Each worker has an independent process and context; task handoff must be explicit through prompts, files, commits, issues, or Herdr pane output.
- Delegation may narrow sandbox access but cannot widen it. A read-only parent produces a read-only child; a paranoid parent fails rather than regaining remote network.
- Depth/concurrency environment tracking prevents accidental recursion and request storms; it is a guardrail, not an adversarial security boundary. The nested OS sandbox is the capability boundary.
- Herdr supplies visibility and process coordination, not semantic correctness. Existing one-writer-per-file/worktree and external verification rules still apply.
- Native Claude Code agents remain useful for same-provider work, but cannot be advertised as per-worker provider routing.

## Alternatives considered

- **Choose Fable inside ClaudeX.** Rejected: the picker does not change the process-wide gateway; CLIProxyAPI has only Codex OAuth in this deployment.
- **Choose GPT workers inside direct Claude Code.** Rejected: native agents inherit the lead process's Anthropic transport.
- **OpenRouter as the single endpoint.** Viable when unified metered API billing is desired; rejected as the default because it bypasses separate subscription quotas and centralizes credentials. It remains a useful alternate profile.
- **Teach CLIProxyAPI both providers.** Rejected for the default: larger credential/trust surface and the same API-vs-subscription trade-off. Separate processes make the provider seam explicit.
