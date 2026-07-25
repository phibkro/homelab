# ADR-0008: Agents launch directly inside pagu; `agent-dispatch` is removed

- Status: Accepted
- Date: 2026-07-25

## Context

[ADR-0007](0007-cross-provider-agents-are-separate-processes.md) established
that cross-provider agents run as separate first-party CLI processes, and made
`agent-dispatch` the mandatory programmatic launch path: it capped depth and
breadth, then handed the child to `pagu-box --profile=strict`.

Three things changed since.

**Pagu absorbed the boundary.** `pagu-box` was a standalone profile launcher.
The consolidated `phibkro/pagu` product now owns both the box (the Policy
Enforcement Point) and the gate (the Policy Administrator), takes complete
schema-v0 JSON policy rather than profile flags, and owns the harness
fresh/resume lifecycle so a session survives a grant. `pagu` infers Codex,
Claude, or Pi from the wrapped executable. The launch surface pagu now exposes
is the thing `agent-dispatch` was translating *to*, so the translation layer
became a second, weaker copy of the policy language. `pagu-box` remains an
explicitly-supported compatibility executable, not the workflow.

**The dispatcher's guarantees were labels, not enforcement.** `agent-dispatch`
asserted monotone attenuation through `AGENT_SANDBOX_*` environment variables.
An environment claim is not evidence of narrowing; the compiled policy is. The
frozen spec
[`docs/specs/2026-07-23-pagu-homelab-flake-migration.md`](../specs/2026-07-23-pagu-homelab-flake-migration.md)
already names this: policy authority must be schema-v0 data, and homelab must
not recreate attenuation in bash.

**The observability unit changed.** ADR-0007 and the generated Codex context
told agents to place workers in Herdr *panes*. The operator's practice is one
agent session per Herdr *tab*. Splitting panes fragments a session's visible
transcript for no gain.

Guidance had also drifted from the machine. `pagu` was reachable only as an
`agent-dispatch` runtimeInput, never in `home.packages`, so `command -v pagu`
failed while every document told agents to use it.

## Decision

Agents launch directly inside pagu.

- `pagu` is installed in `home.packages` on the Linux workstation. Guidance may
  name it because the environment provides it.
- `pagu` is the agent-launch surface. `pagu --help` and the `pagu` skill are the
  authority for its flags at the installed version; homelab does not restate
  them.
- Claude Code's own permission bypass inside a box is acceptable. Pagu is the
  enforceable outer boundary, so the sandbox — not the harness's prompt — is the
  security control. This is a deliberate move of enforcement down a layer, not a
  relaxation.
- Sandbox authority stays monotone, enforced by nested namespaces and compiled
  policy rather than by environment labels.
- Observable work is **one agent session per Herdr tab**. Tabs are the
  organizational unit; split panes are not prescribed.
- Bounded concurrency survives as policy: at most two concurrent delegated
  workers, depth two (lead → worker → reviewer). It is stated once, in the
  operator's global Claude and Codex context, and referenced elsewhere rather
  than copied into each repository.
- `agent-dispatch` is **removed**, not merely deprecated. Its package, its two
  shell files, its flake check, and its architecture-baseline assertion are
  gone; its one non-agent caller (`modules/infra/backup/agent-fix.nix`) now runs
  `pagu-box --profile=strict --<provider> -- <provider> …` — the exact executable
  agent-dispatch invoked, so the caller changed without the enforcement
  changing. It moves to `pagu box` when the flake input is bumped past that
  subcommand dispatch.

What ADR-0007 established and this ADR keeps: one Claude Code process has one
provider endpoint, native subagents cannot route per-worker across providers,
provider credentials and subscription quotas stay isolated in first-party
clients, and Herdr is the control plane rather than a semantic-correctness
mechanism.

## Consequences

- The documented workflow is executable. Installing `pagu` closes a gap where
  three layers of context named a command the machine did not have.
- One policy language. Filesystem, network, environment, escalation, and refusal
  authority live in pagu schema-v0 JSON. Shell may select an artifact; it may not
  reimplement the semantics.
- **Two guardrails died with the script, and only one was replaced.**

  `agent-dispatch` forced `--pwd-ro` whenever `$PWD` sat under the homelab
  prefix. `pagu box` has no equivalent implicit rule — correctly, since a
  launcher should not infer authority from a path. That guard is now a module
  assertion in `agent-fix.nix`, which is strictly stronger: it fails at
  evaluation instead of at incident time.

  The depth-two / two-concurrent-worker cap has **no replacement**. It lived
  entirely in that script's `AGENT_DISPATCH_DEPTH` accounting and `flock` slots,
  and pagu exposes neither. ADR-0007 already classified it as "a guardrail, not
  an adversarial security boundary" — the nested OS sandbox is the capability
  boundary, and that is untouched. What is lost is runaway-recursion and
  request-storm protection. The cap survives only as stated convention in the
  operator's global context until pagu can enforce it.

- The headless caller did not need the gate. `agent-fix.nix` is an unattended
  systemd unit: nobody can answer a file request, and a one-shot never resumes.
  So the constraint that makes the *gated* journey refuse trailing arguments —
  the adapter must reproduce the harness argv after a relaunch — simply does not
  apply, and `pagu box` accepts `COMMAND [ARGS...]`. The migration preserves the
  legacy `strict` profile rather than switching to the `worker` category
  profile, so it changes the launcher without changing the enforced policy.
  Moving that caller onto schema-v0 policy is a separate, reviewable change.

- This supersedes the frozen migration spec's §3 ("Reduce `agent-dispatch` to
  orchestration"). That section is void: there is no dispatcher left to reduce.
  The operator directed the removal explicitly; the spec still needs revising to
  match.
- Guidance is a pointer, not a copy. Per-repository agent context should link the
  `pagu`/`herdr` skills instead of restating profiles, flags, or depth caps —
  which is what let the previous mandate rot in four places at once.
- Changing the permission-bypass posture requires another ADR, because it only
  holds while pagu is genuinely the outer boundary. An agent launched *outside*
  pagu does not inherit this allowance.
- Guidance now depends on the `pagu` flake pin, because the skill agents read is
  installed from `${inputs.pagu}/skills/pagu`. That coupling is deliberate — it
  is what stops Claude and Codex reading different contracts — but it means a
  local pagu commit is invisible here until the pin moves. The ordering is a
  runbook: [`pagu-pin-bump.md`](../runbooks/pagu-pin-bump.md).

## Alternatives considered

- **Keep `agent-dispatch` as a thin orchestration adapter** (the frozen spec's
  §3). Rejected as the default agent-facing path: it keeps a second launch verb
  for agents to learn and drift against, and its remaining value — depth and
  slot accounting — is a convention either way. Its last caller
  (`agent-fix.nix`) needed only the box, which it can invoke directly.
- **Silently rewrite ADR-0007.** Rejected: superseded ADRs record the path. The
  reasoning about provider endpoints and credential isolation is still correct
  and still load-bearing.
- **Encode the two-worker/depth-two cap in pagu.** Preferred, but pagu does not
  expose depth or slot accounting today. Until it does, the cap stays a stated
  convention in one place rather than an enforced invariant. Recorded as the
  open upgrade path.
