# Fix-agent on failure (`nori.agentFix`)

**What**: an allowlisted unit fails → after the recovery window, a coding agent
is dispatched to diagnose + propose a fix as a **PR**. The PR opens **whether or
not the fix succeeds** — it's the durable indicator that a system is failing and
a started thread to fix it. PR-only: the agent never deploys.

**Armed on** (`modules/machines/workstation/default.nix`):
`restic-check-weekly` · `restic-check-monthly` · `btrbk-root` · `btrbk-media`.

## Flow

```
unit fails ─OnFailure→ ├─ notify@       (ntfy: a service is down)
                       └─ agent-fix@<unit>  (nori, oneshot)
   survive recovery window (~120s; transient self-heal → quiet exit)
   cooldown check (6h per unit)                     [/var/lib/agent-fix/<unit>.last]
   clone origin/main → /srv/nori/agent-fix/<unit>-<ts>   (OUTSIDE the homelab prefix)
   agent-dispatch <provider>  (pagu-box strict: EDITS + writes report; NO push)
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

The boxed agent's session persists to your real `~/.claude` (agent-dispatch
binds it via pagu-box `--claude`). **Resume it un-boxed** to review its
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

## Manual dry run (no real failure needed)

```bash
systemctl start agent-fix@restic-check-weekly.service
journalctl -u agent-fix@restic-check-weekly.service -f
```

## Arm / disarm

`nori.agentFix.units = [ … ];` in `modules/machines/workstation/default.nix`
(empty list = template deployed but nothing auto-triggers). `provider` defaults
to `claude`; `cooldownSeconds` defaults to 6h.

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
