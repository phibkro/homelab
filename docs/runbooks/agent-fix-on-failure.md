# Fix-agent on failure (`nori.agentFix`)

`nori.agentFix` implements an allowlisted `OnFailure=` path that can dispatch a
coding agent to diagnose a failed unit and propose a PR. The agent never
deploys.

**Current state:** implemented but disarmed.
`infra/workstation/default.nix` sets `nori.agentFix.enable = false`; no
`agent-fix@…` services or failure edges are deployed. It was disabled after
simultaneous backup failures exhausted workstation memory on 2026-08-30.

The remaining sections describe the dormant mechanism so it can be reviewed
before any operator-approved re-arm.

## Flow when enabled

```
unit fails ─OnFailure→ ├─ notify@       (ntfy: a service is down)
                       └─ agent-fix@<unit>  (nori, oneshot)
   survive recovery window (~120s; transient self-heal → quiet exit)
   cooldown check (6h per unit)                     [/var/lib/agent-fix/<unit>.last]
   clone origin/main → /srv/nori/agent-fix/<unit>-<ts>   (OUTSIDE the homelab prefix)
   pagu-box --profile=strict --<provider>  (EDITS + writes report; NO push)
   nix flake check  → passes = ready PR · fails = DRAFT PR   (never blocks the PR)
   git push + gh pr create   (always)  →  nori-alert (agents topic)
```

The agent is boxed (model access, no push/deploy); a deterministic un-boxed
relay does the push + PR. Fixes base on `origin/main`, never the operator's
working tree.

## When one fires — where everything is

| Artifact | Where |
|---|---|
| **PR** (the thread) | `gh pr list` / GitHub — draft if it fails `nix flake check` |
| **Run log** (orchestrator + the agent's session output) | `journalctl -u agent-fix@<unit>.service` |
| **Resumable conversation** | `~/.claude/projects/-srv-nori-agent-fix-<unit>-<ts>/<session-id>.jsonl` |
| **Work clone** (the agent's edits + incident report) | `/srv/nori/agent-fix/<unit>-<ts>/` (persists; not torn down with the box) |
| **Incident report** | `<clone>/docs/reports/<ts>-<unit>-failure.md` (also in the PR diff) |
| **Cooldown state** | `/var/lib/agent-fix/<unit>.last` |
| **Outcome ping** | agents ntfy topic (`nori-agents-…`) |

The PR body itself carries the resume + journal commands — start there.

## Review + steer the agent's thread

The boxed agent's session persists to your real `~/.claude` (bound by the
box's `--claude` preset). **Resume it un-boxed** to review its
reasoning and give feedback:

```bash
cd /srv/nori/agent-fix/<unit>-<ts>          # full file context
claude --resume <session-id>                # or: claude --resume  (picks from this dir)
```

`<session-id>` is in the PR body, or:

```bash
ls -t ~/.claude/projects/-srv-nori-agent-fix-<unit>-*/*.jsonl | head -1
```

Resuming runs as you (un-boxed), so you can correct it, ask why it made a
choice, and push the fix further. When satisfied, mark the PR ready + merge —
that's the only path to deploy.

## Verify the disarmed state

Use read-only checks:

```bash
nix eval --json .#nixosConfigurations.workstation.config.nori.agentFix.enable
systemctl list-unit-files 'agent-fix@*'
```

The evaluated value must be `false`.
The running host must list no deployed template.
Do not start `agent-fix@…` as a dry run while the feature is disabled.

## Re-arm / disarm

`nori.agentFix.enable` is the activation gate.
`nori.agentFix.units` selects the allowlisted units only when that gate is true.
The current declaration derives the Btrbk units, but the false gate keeps the
mechanism absent.

Re-arming changes live failure automation and grants the deterministic relay
GitHub publication authority. It requires explicit operator approval, source
review, focused resource/concurrency verification, and a normal workstation
deployment. `provider` defaults to `claude`; `cooldownSeconds` defaults to 6h.

## Gotchas

- **Quiet fire = transient self-heal.** On a real `OnFailure` the agent sleeps
  ~120s and re-checks `is-active` first; a unit that recovered produces a
  near-empty journal entry and no PR. Not a failure.
- **Draft PR** = the agent's proposal doesn't pass `nix flake check` — a human
  is needed; resume the thread.
- **No new PR within 6h** = the per-unit cooldown; `/var/lib/agent-fix/<unit>.last`.
- **`origin/main` must be green** — the agent's own `nix flake check` runs
  against it; a red main can't produce a passing fix.
- **Sessions accumulate** under `~/.claude/projects/-srv-nori-agent-fix-*` (one
  per fire). Prune periodically if they pile up.
- **Design + rationale**: `docs/specs/2026-07-18-agent-fix-on-failure-design.md`.
