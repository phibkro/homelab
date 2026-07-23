---
date: 2026-07-23
status: frozen; awaiting operator implementation gate
owner: operator
source_slice: pagu ROADMAP — homelab migration
summary: Move homelab launch policy from legacy pagu-box shell flags into pagu schema-v0 data and adopt pagu's gate-owned request/relaunch lifecycle without removing the compatibility executable prematurely.
---

# Design — pagu homelab flake migration

## Freeze boundary

This document is the implementation contract. It freezes the observable
migration boundary and falsifiers, not line-by-line mechanics. Changing a goal,
security invariant, compatibility promise, or acceptance journey requires the
operator to unfreeze and revise this spec explicitly.

No implementation or activation belongs in the spec commit. The first real
Home Manager/NixOS activation is a separately approved, quiesced operator
`just rebuild`; ordinary agent work must not trigger it.

## Problem

Homelab already fetches the consolidated `phibkro/pagu` repository, but consumes
it through legacy input names and the `pagu-box` compatibility surface. Policy
is split across shell behavior:

- `flake.nix` exposes `pagu-box` and `pagu-box-darwin` inputs;
- `agent-dispatch` translates depth, parent mode, provider, Herdr state, and
  read-only intent into legacy launcher flags;
- `modules/home/claude-code/default.nix` builds a second `box` wrapper that
  inspects argv and injects homelab/journal exceptions;
- tests assert the generated legacy argv rather than a strict policy artifact;
- ordinary dispatch launches the box directly, so it cannot exercise pagu's
  gate-owned request → decision → replacement-box → UUID-resume lifecycle.

This leaves policy meaning in mutable shell text instead of pagu's published
schema-v0 authority format. It also keeps the archived standalone product name
at the homelab integration seam after box and gate became one pagu flake.

## Goal

Homelab consumes pagu's root flake as the single box/gate product and launches
delegated Linux workers through pagu's gate using a complete, checked-in
schema-v0 worker policy. Policy authority becomes data; shell remains only a
thin provider/depth/slot adapter. A real nested delegation and a real
request → operator decision → stop → recompile → same-session relaunch journey
prove the migrated seam before deployment is accepted.

## Constraints

- **No self-widening.** A delegated child policy must be equal to or narrower
  than its parent's effective authority. Environment labels are not evidence of
  attenuation; compiled policy and retained launch evidence are.
- **Gate outside, box inside.** The sandbox receives only pagu's request socket.
  Gate state, queue, resolution path, and any Herdr control socket remain outside
  every sandbox-visible root.
- **One policy language.** Filesystem, network, environment, auto-grant, and
  refusal authority live in strict pagu schema-v0 JSON. Shell/Nix may select an
  artifact but must not reimplement its semantics with legacy flags.
- **Project data only narrows.** A repository-owned policy cannot grant itself
  authority absent from the operator-selected worker ceiling.
- **Fail loud.** Unsupported schema enforcement, missing private gate state,
  ambiguous harness identity, unavailable resume, invalid policy, depth
  overflow, occupied worker slots, or a network-widening child all stop without
  a weaker fallback.
- **Compatibility remains explicit.** `pagu-box` stays installed while any
  declared caller still needs legacy profiles, especially x86_64-darwin where
  schema lowering is unsupported. Compatibility is not the new worker policy
  path.
- **No implicit deployment.** Evaluation and source-level tests precede one
  operator-coordinated, quiesced rebuild. No service restart or agent-session
  interruption is accepted as a side effect of implementation.
- **Secrets remain names, never values.** Schema `env.pass` contains only
  approved variable names. No credential value enters Nix, JSON policy, launch
  evidence, or logs.

## Values

1. Correctness by construction: schema data and pagu attenuation replace shell
   claims about monotonicity.
2. One source of truth: one worker authority artifact drives launch, test, and
   explanation.
3. Evidence over narration: retained compiled policy, request events, decision,
   and resumed launch prove the journey.
4. Compatibility without stagnation: keep the executable, remove it only from
   migrated callers.
5. Reversible activation: source changes are reviewable before the quiesced
   rebuild; the previous generation remains the rollback boundary.

## Decision

### 1. Consume the pagu root flake by product name

Replace the legacy-named homelab inputs with root-pagu inputs:

- `pagu` follows the Linux homelab nixpkgs input and supplies both
  `packages.<system>.pagu` and the `pagu-box` compatibility package;
- `pagu-darwin` points at the same pagu root flake but follows the final
  x86_64-darwin-capable stable nixpkgs input while that host still needs the
  compatibility Home Manager module.

No input URL may reference the archived standalone `pagu-box` repository, and
no consumer may address the consolidated repository through an input named
`pagu-box*`. Two root-flake nodes are acceptable only for the real Linux versus
x86_64-darwin nixpkgs constraint; they are not separate policy products.

Linux agent tooling consumes the `pagu` executable for gate operations and its
co-packaged `pagu-box` executable as pagu's internal/compatibility PEP. Darwin
continues to consume the compatibility module/package until pagu ships schema-v0
seatbelt lowering.

### 2. Make worker authority schema-v0 data

Add one canonical, checked-in homelab worker policy under the Home Manager
agentic capability. It is a complete artifact conforming to pagu's published
`profile-grant-v0.schema.json` / `PolicyV0` shape:

```text
version · subject · fs.home · fs.{rw,ro,deny} · net · env.pass
· escalation.{auto,refuse}
```

The artifact owns these facts:

- temporary worker home;
- current worktree access and Nix-daemon access needed for coding/evaluation;
- the complete secret deny/refuse floor;
- direct-network posture;
- exact environment-name allowlist, including bounded delegation metadata;
- session-scoped read-only escalation ceilings.

Provider authentication state is not added as a broad home mount. For a
gate-owned launch, pagu composes only the selected harness state (`~/.codex`, or
`~/.claude` plus `~/.claude.json`) through its trusted launch overlay.

Read-only dispatch is represented by a complete narrower policy/project
attenuation, not `--pwd-ro` shell mutation. The homelab checkout remains
read-only to delegated workers unless they operate in an explicitly assigned
worktree. A network-denied parent cannot launch a cloud worker. If pagu cannot
consume and prove these child attenuations through its current public surface,
implementation stops and the missing upstream pagu capability is fixed first;
homelab must not recreate attenuation in bash.

The canonical JSON is installed unchanged. Nix may parse it for assertions and
place it in the store, but it must not maintain a second field-by-field policy
copy.

### 3. Reduce `agent-dispatch` to orchestration

Retain the useful non-authority behavior:

- provider selection (`claude` or `codex`);
- maximum delegation depth two;
- two concurrent worker slots;
- deterministic state-directory selection;
- explicit failure codes and diagnostics.

Remove policy compilation from the script. It no longer constructs legacy
`pagu-box` flags, copies Herdr control-plane variables, grants paths, or claims
monotonicity through `AGENT_SANDBOX_*` labels. It selects the reviewed worker or
read-only artifact and starts a fresh, gate-owned pagu harness lifecycle.

Nested dispatch must remain observable without mounting Herdr's control socket
inside a worker. Host-side orchestration may observe the process and gate queue;
the sandbox cannot resolve its own request.

### 4. Delete the homelab policy-rewriting launcher

Remove the Home Manager `box` wrapper that inspects launcher text/argv and
injects `--journal`, `--pwd-ro`, or homelab path exceptions. Do not replace it
with `substituteInPlace`, `replaceStrings`, `sed`, generated shell fragments, or
another legacy-flag translator.

Operator launch conveniences select a named/installed schema policy or use the
compatibility executable directly when they intentionally need legacy behavior.
Journal access belongs in an explicit reviewed policy (for example an infra
policy), never an unconditional wrapper side effect.

### 5. Keep the compatibility executable until callers are gone

The migration removes direct `pagu-box` use from the Linux delegated-worker
path, not the executable from the machine. Keep pagu's `pagu-box` output and
compatibility Home Manager module available for:

- x86_64-darwin legacy profiles;
- operator commands or scripts not migrated in this slice;
- rollback to the previous Home Manager generation;
- pagu gate's current PEP dependency while `pagu box` is not yet shipped.

Removal is a separate change gated by all of:

1. pagu ships the unified command surface needed by every caller;
2. schema-v0 policy lowering exists on every retained platform;
3. a repository search finds no declared legacy-profile caller;
4. rollback instructions no longer name the compatibility binary.

## Authority and launch flow

```text
reviewed homelab worker-policy-v0.json
                    │
                    ▼
agent-dispatch: provider + depth + slot only
                    │
                    ▼
pagu gate (host authority, private state, owns child)
                    │ complete validated policy
                    ▼
pagu-box compatibility PEP ──▶ boxed Claude/Codex session
                    ▲                         │
                    │                         │ typed read-only request
                    │                         ▼
                    └── stop old box ◀── decision outside sandbox
                         compile wider exact grant
                         resume same UUID in replacement box
```

The compatibility executable in this diagram is packaging, not policy
authority. The complete validated policy and gate-derived grant remain the
single source of enforcement meaning.

## Critical journeys and falsifiers

### A. Static integration

Pass criteria:

- homelab flake inputs and lock graph use `pagu` / `pagu-darwin`, not a
  `pagu-box*` input name or archived repository;
- Linux closures expose `pagu` and the compatibility `pagu-box` from the same
  root flake revision;
- Darwin's compatibility module still evaluates from the root pagu flake;
- the installed worker JSON strictly decodes as schema v0 and equals the source
  artifact;
- no Nix or shell source patches an upstream launcher or lowers schema fields
  into legacy flags;
- the compatibility executable remains present.

Falsifier: two revisions supply gate and box, policy exists in both JSON and
shell/Nix, or removing the legacy input silently removes Mac/rollback support.

### B. Nested delegation

Run outside an existing pagu sandbox during the operator-approved verification
window:

1. launch a real lead through the migrated gate path;
2. dispatch a worker; from that worker dispatch one reviewer;
3. prove depth-two cannot dispatch again and a third concurrent worker cannot
   exceed the two-slot breadth bound;
4. inspect each retained launch artifact and prove child authority is no wider
   than parent authority for filesystem, network, environment, denies, and
   escalation;
5. repeat from a read-only parent and prove every descendant remains read-only;
6. repeat the network-denied case and prove a cloud child fails before launch;
7. prove neither child can see gate resolution state or Herdr's control socket.

Falsifiers:

- nested bubblewrap/user namespaces fail;
- an `AGENT_*` environment claim is the only evidence of narrowing;
- a child gains write, network, environment, host, or escalation authority;
- depth/breadth failure falls back to an unboxed provider process;
- Herdr/operator control surfaces enter the sandbox.

### C. Full request → decision → relaunch

Use a disposable test path outside the initial worker policy and a real fresh
Codex or Claude session with a context marker:

1. start the worker through `pagu gate`; record its UUID, PID, compiled policy,
   and initial marker;
2. from inside, file one strict `fs.ro` request through pagu's SDK;
3. prove the request appears in the host-owned queue and cannot be resolved from
   inside;
4. resolve the exact request ID from the trusted host with `session` scope;
5. prove the old boxed PID stops before replacement;
6. prove the replacement policy contains only the canonical exact read-only
   grant, retains the deny floor, and does not widen unrelated fields;
7. prove the same harness UUID resumes with the pre-request marker/context and
   can read the approved path;
8. inspect retained evidence in order: gate-session → request → decision → grant
   → policy-launch; verify compiled argv/environment names match enforcement;
9. stop/restart the gate and prove the session-scoped grant binds only to the
   same session and authoritative policy identity.

Falsifiers:

- the running namespace widens in place;
- the requester can resolve, edit policy, or see operator state;
- the previous box survives alongside the replacement;
- resume starts a fresh unrelated session or loses context;
- evidence describes a different policy than the launched box;
- a changed/symlinked canonical target applies;
- gate failure produces a wider fallback.

## Delivery keyframes

### K1 — input and package seam

Homelab names and consumes the root pagu flake; Linux receives gate + compat PEP
from one revision; Darwin compatibility still evaluates. No policy behavior
changes yet.

### K2 — policy-as-data seam

The complete homelab worker/read-only authority is checked in, strictly decoded,
installed unchanged, and tested for secret floor plus narrow-only relationships.
Legacy launch remains available for rollback.

### K3 — gate-owned dispatch seam

`agent-dispatch` owns only provider/depth/slots and starts pagu gate. The
policy-rewriting `box` wrapper and launcher-source substitution are absent.
Source-level tests assert selected policy identity and orchestration failures,
not hand-assembled legacy argv.

### K4 — real evidence

Nested delegation and the complete request/decision/relaunch journey pass from
real packaged executables. Retained evidence is attached to review without
secret values.

### K5 — quiesced activation

After code review and operator approval:

1. stop or save active agent sessions and quiesce Herdr workers;
2. run the operator-owned `just rebuild` once;
3. repeat a smoke launch through the installed commands;
4. on failure, activate the previous generation and retain evidence for repair;
5. do not remove `pagu-box` during rollback or this slice.

## Acceptance criteria

- [ ] Homelab consumes pagu root-flake outputs under `pagu` names; no archived
      standalone input remains.
- [ ] Gate and box come from one pinned pagu revision on Linux.
- [ ] The worker ceiling and read-only attenuation are complete schema-v0 data,
      strictly validated against pagu's published contract.
- [ ] One canonical policy artifact drives installation, explanation, tests, and
      launch.
- [ ] `agent-dispatch` retains provider/depth/slot behavior but contains no
      filesystem/network/environment authority compiler.
- [ ] The Home Manager text/argv-rewriting `box` launcher is deleted without a
      substitute patcher.
- [ ] A nested lead → worker → reviewer journey passes with child ≤ parent
      evidence; depth, breadth, read-only, and no-network falsifiers fail loud.
- [ ] A real request → host decision → old-box stop → exact-grant compile →
      same-UUID resume journey passes with ordered retained evidence.
- [ ] Gate resolution state and Herdr control remain invisible in every box.
- [ ] `pagu-box` compatibility executable and Darwin module remain available.
- [ ] No `flake.nix` or lock change silently updates pagu beyond the reviewed
      revision.
- [ ] No rebuild/deploy occurs before the separately approved quiesced gate.

## Non-goals

- Implementing `pagu box`; pagu has not shipped that command yet.
- Removing `pagu-box` compatibility packaging or legacy macOS profiles.
- Adding schema-v0 macOS seatbelt lowering.
- Changing pagu schema v0, request wire format, grant semantics, or resume
  adapters inside homelab.
- Domain-aware network egress, credential injection, automatic denial requests,
  or hostile-peer Codex session-store isolation.
- Replacing Herdr, changing provider CLIs, increasing dispatch depth/breadth, or
  deploying a general control socket into sandboxes.
- Running `just rebuild`, deploying, or terminating live sessions as part of
  implementation review.

## Rollback

Before activation, revert the migration commits. After the quiesced rebuild,
activate the previous Home Manager/NixOS generation; it still contains the
legacy input names, wrapper, and dispatch path. The pagu pin and compatibility
executable remain available throughout the slice, so rollback does not depend
on fetching the archived standalone repository or inventing a new launcher.

## Implementation references

- pagu `ROADMAP.md` § “Homelab flake-input migration”
- pagu `CONTEXT.md` § policy/grant model and escalation loop
- pagu ADR-0004 — sandbox + gate pivot and compatibility promise
- pagu ADR-0005 — schema and box/gate boundary
- pagu ADR-0006 — category profiles and growth
- pagu `schemas/profile-grant-v0.schema.json`
- pagu `profiles/worker.json` and `profiles/orchestrator.json`
- homelab `flake.nix` pagu inputs
- homelab `modules/home/profiles/development/agentic-workstation.nix`
- homelab `modules/home/agent-dispatch.sh`
- homelab `modules/home/claude-code/default.nix`
- homelab `modules/machines/macbook/home.nix`
