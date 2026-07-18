# Auto-dispatch a fix-agent on homelab failures

**Date:** 2026-07-18
**Status:** Approved design, build deferred until the notification work
(`nori.agentNotify`, branch `feat/agent-notify`) lands.

Companion to `nori.agentNotify` (phone-push when a harness halts). That
feature answers *"an agent needs me"*; this one answers *"the homelab
needs an agent"* — a failing unit dispatches a coding agent that
diagnoses, fixes, and opens a PR.

## Goal

When a homelab unit **fails on a running host**, automatically start a
headless coding-agent session in the homelab repo, seeded with the error
(journal + exit code + recent commits), tasked to: diagnose → fix in an
isolated worktree → validate (`nix flake check`, `just preview`) → open a
PR with an incident report → ping the operator. **Deploy happens on the
operator's merge, never by the agent.**

First (only) eligible trigger: **backup failures — restic + btrbk.**

## Constraints (hard — deal-breakers)

- **Exempt "host is off" — by construction, not heuristic.** A unit that
  *ran and failed* proves its host is up. A powered-down host surfaces
  instead as another host's Gatus/heartbeat probe going unreachable.
  Dispatch fires **only** from a failing unit's `OnFailure=` (host
  provably up); it is **never** wired to cross-host availability probes.
  Machine-off can therefore never trigger a fix-agent.
- **PR-only autonomy — respect the push gate.** The agent commits in a
  worktree and opens a PR. It MUST NOT `git push origin/main` and MUST
  NOT persist a rebuild (`just rebuild`) to the live system. It MAY
  validate with `just preview` (`nh os test`; reverts on reboot). Deploy
  = operator merge → `just deploy`.
- **Isolation.** The agent runs in a dedicated git **worktree** (matches
  the multi-agent write discipline + pavilion's agent-quarantine role),
  dispatched through `agent-dispatch` in pagu-box `strict`. One writer
  per worktree.
- **Transient filter.** Reuse the existing 120s recovery window
  (`nori.observability.ntfyNotify.recoveryWindowSeconds`): only dispatch
  after a failure survives the window — most transients self-heal in the
  systemd restart backoff.
- **Explicit allowlist.** A unit is eligible only by opt-in
  (`nori.agentFix.<unit>` or a tag), never wildcard. Default-deny.
- **Loop breaker.** A fix-agent's own failure (or a re-failure of the
  same unit within N minutes) must NOT re-dispatch — bounded retries,
  fail loud to ntfy.

## Values (soft — preferences)

- **Provider routing by least usage** — *aspirational; research-gated.*
  Neither Claude nor Codex exposes a reliable local remaining-quota
  meter. The honest v1: prefer the provider without recent rate-limit
  (429) events (the claudex proxy already greps its journal for these),
  else round-robin. Revisit if a real quota endpoint is found.
- **Incident report quality** — the PR body carries: what failed, root
  cause, the fix, how it was validated, and what to watch. Backward-
  looking companion to a `docs/reports/` entry when the failure is novel.
- **Cheap-first** — a oneshot + dispatch; no long-running supervisor.

## Architecture

```
failing unit (restic-*, btrbk)
   │ OnFailure=  ← ALREADY wired to notify@%n (ntfy) with a 120s window
   ▼
agent-fix@<unit>.service  (new oneshot; allowlisted units only)
   │ 1. survive recovery window (transient filter, shared with notify@)
   │ 2. gather context → prompt:
   │      journalctl -u <unit> -n 200, exit code, `git log` since last deploy,
   │      the unit's module source path
   │ 3. route: provider = least-recent-429(claude, codex)   [v1 proxy]
   │ 4. worktree: git worktree add <quarantine>/<unit>-<ts> -b fix/<unit>-<ts>
   │ 5. dispatch: agent-dispatch <provider> --cd <worktree> -p "<prompt>"
   ▼
agent (claude -p / codex exec), in the worktree, pagu-box strict
   │ diagnose → edit → `nix flake check` → `just preview` (validate, non-persist)
   │ → commit → `gh pr create` (incident report body)
   ▼
ntfy (agent topic): "fix-agent opened PR #N for <unit> — review"
   ▼
operator reviews → merge → deploy
```

### Load-bearing findings (from reading the primitives)

Reuse `agent-dispatch` (modules/home/agent-dispatch.sh) rather than invoking
claude/codex directly — it already provides the "boxed agent WITH model
access" primitive, bounded depth + slots. Two constraints it imposes shape
the design and resolve the spec's open questions:

- **Worktree must live OUTSIDE `/srv/share/projects/homelab`.** agent-dispatch
  forces read-only whenever `$PWD` is under that prefix ("inspect the
  canonical homelab, never edit it"). Put the fix worktree elsewhere
  (e.g. `/srv/nori/agent-fix/<unit>-<ts>`) so delegated writes are allowed.
- **The AI never holds push/deploy creds — by construction (resolves Q2).**
  pagu-box strict blocks gh/ssh/secrets, so the boxed agent can *edit +
  commit locally* but cannot push. Split the flow: the boxed agent proposes
  (commit on a branch in the worktree); a **deterministic relay** (the outer
  `agent-fix@` oneshot, un-boxed `nori`, already has gh auth) does the
  `git push` + `gh pr create`. No gh token goes into the sandbox at all.

Backup unit names to wire `OnFailure = [ "agent-fix@<unit>.service" ]` onto
(they already carry `notify@`): `restic-backups-<job>-<target>`,
`restic-check-weekly`, `restic-check-monthly`, `btrbk-root`, `btrbk-media`.

### Component breakdown

| Piece | Home | Notes |
|---|---|---|
| `agent-fix@` oneshot | new NixOS module `modules/infra/observability/agent-fix.nix` | generalises the `notify@` pattern; shares the recovery window |
| eligibility | `nori.agentFix.<unit>.enable` (or a tag on `nori.backups`) | default-deny allowlist |
| prompt builder | script inside the unit | journal + exit code + git log + module path |
| provider router | small script | v1: least-recent-429; reads claudex journal |
| worktree + dispatch | `agent-dispatch` (exists) + `git worktree` | quarantine dir; one writer per worktree |
| PR + report | agent does it via `gh` | needs a narrowly-scoped gh credential reachable inside the sandbox |
| notify | reuse `nori.agentNotify` topic | "PR opened" ping |

## Open questions / research before build

1. **Provider usage signal** — does either harness expose a real quota /
   usage endpoint locally? If not, v1 ships the 429-proxy and says so.
2. ~~gh credential in-sandbox~~ **RESOLVED** — don't put gh in the sandbox.
   Boxed agent commits locally (no push); the outer deterministic relay
   (un-boxed nori) pushes + opens the PR. See Load-bearing findings.
3. **Prompt contract** — what makes an agent reliably fix a restic/btrbk
   failure vs. flail? Seed with the recovery runbooks
   (`docs/runbooks/`, `.claude/skills/restore-*`).
4. **Dedup / loop-breaking** — key on `<unit>` + a cooldown; where to
   persist last-dispatch time (the unit is a oneshot).

## DoD (phased)

- **A — trigger + dispatch (no routing):** a failed `restic`/`btrbk` unit
  on a running host, surviving the window, spawns a headless agent in a
  worktree that produces a PR + incident report + ntfy ping. Provider
  fixed to one. Machine-off proven non-triggering.
- **B — provider routing:** add the least-recent-429 chooser once the
  usage-signal question is answered.
- **C — broaden triggers:** allowlist beyond backups (opt-in per unit),
  and optionally build-time failures (`nix flake check` / rebuild).

Auto-deploy (`just rebuild` by the agent) is **out of scope** — rejected
against the push gate. `just preview` validation is the ceiling.
