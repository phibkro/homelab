# Homelab oversight recovery

Initial evidence collection: 2026-09-17 14:58 UTC. Initial registry and status check: 2026-09-17 15:09 UTC. Execution update: 2026-09-19.

This report reconciles unfinished local work. It does not prove that a source tree was built, accepted, published, or deployed.

## Evidence boundaries

- **Source:** a checkout or branch contains code or configuration.
- **Recorded acceptance:** a dated record names the exact artifact and observed result.
- **Deployment:** the intended host or provider runs the accepted artifact.
- **Hold:** an operator, hardware, credential, clean-artifact, or external action remains required.

The baseline committed source is `main` at `93807ae09ccce48b6e5d4e8dc8342aedae8ae4f3`. The cached `origin/main` is `b3a85506c650f5c66060acd1ab6434e06684569f`, dated 2026-09-01. No fetch or remote query ran. Therefore, remote publication state is unknown.

The documentation worktree and branch were created from the baseline during this recovery:

- Worktree: `/srv/share/projects/homelab-oversight-recovery`
- Branch: `docs/homelab-oversight-recovery`

During the initial evidence collection, no source worktree was switched, staged, reset, merged, pruned, or deleted.

## Execution update

The recovery moved from evidence collection to integration on 2026-09-19.
Product integration reached commit `29ccd4ab0f4cd816f7b33b1702f1feda1207c91d`.

Completed source outcomes:

- Generated desktop settings and Vicinae integration are on `main`.
- Firecracker lifecycle repairs are on `main`. The final real-host journey did not run after the last containment change.
- The normalized topology graph and TOSCA 2.0 projection are on `main`.
- qBittorrent activation is on `main`. The workstation was not activated.

The operator then authorized live Pi recovery and observability work:

- [OneTouch backup evidence](2026-09-19-backup-evidence.md) records fresh Pi backups, repository checks, and one verified configuration restore.
- Pi service checks passed for Authelia, ntfy, Beszel, VictoriaMetrics, VictoriaLogs, Gatus, and Caddy-routed observability endpoints.
- The intact Beszel archive replaced the fresh empty database. The archive retained four systems, 12 alerts, 224 alert records, and 13,193 metric records.
- The Pi inventory generator now derives Beszel systems from hosts with the `beszel-agent` workload.
- The Beszel hub creates missing inventory systems and corrects changed endpoints during deployment. It does not delete historical records.
- SecretSpec supplies a deployment-only Beszel superuser. The repository and managed hub container do not retain its password.
- A new hub initializes its owner on a loopback-only listener. It publishes the LAN listener only after successful authentication.
- The live catalog contains Adelie, Aurora, Pavilion, Pi, and workstation. Pi and workstation are online. The API reports the three historical records as offline.
- The Pi agent reports **55 systemd services, 0 failed**. Workstation reports **102 systemd services, 0 failed**.
- `just pi::check` passed. The authorized `just pi::deploy` completed with `failed=0`.
- The post-deployment `just pi::plan` completed with `changed=0`, `unreachable=0`, and `failed=0`.
- The authenticated Beszel UI rendered current Pi metrics and both service counts.
- The final UI showed one active workstation disk alert. `df` confirmed 747 GiB used from 931 GiB, or 82%.

The observability source changes are in the local `main` history. They were not pushed.
No fetch, merge, publication, workstation activation, or Adelie activation ran.

Cleanup removed temporary playbooks, inventory output, the bootstrap smoke container, and the upstream research clone.
The restored archive and the pre-restore Pi rollback directory remain preserved.

Unmerged or dirty worktrees remain preserved. Compare each branch with current `main` before retention or deletion.

## Current recovery order

| Priority | Outcome | Present state | Next action |
|---:|---|---|---|
| 1 | Pi recovery and observability | Pi backups are fresh. One restore path passed. Core Pi observability services are healthy. Beszel now monitors Pi and workstation and retains Adelie as offline. | Treat reboot, off-LAN operation, and wider application restore tests as separate acceptance work. |
| 2 | Observer and history repair | Several clean but divergent observer, revert, timer, and mixed-history worktrees remain. | Choose the desired observer behavior. Review one exact candidate before history repair or integration. |
| 3 | Older settings and topology lines | Their reconciled outcomes are on `main`, but predecessor branches are not Git ancestors of `main`. | Compare content with current `main`. Remove a branch only when it is clean and fully superseded. |
| 4 | Standalone fixes | Backup-list, chatlog, format-drift, and multi-host verification branches remain unmerged. | Review each branch as its own outcome. Integrate or retire it from direct evidence. |

## Initial workstream reconciliation

### Mixed main

Main reports 34 tracked dirty paths and five untracked paths.

| Group | Paths and evidence | Classification |
|---|---|---|
| Firecracker environment | `Justfile`, `flake.nix`, `flake.lock`, `foundry/profile-v1/STATE.md`, `infra/workstation/firecracker-*`, `infra/workstation/default.nix`, `lib/flake-parts/checks/e2e.nix`, `tests/e2e-self-hosted-firecracker.nix`, the three untracked `infra/workstation/firecracker-*.test.ts` files, `tests/guest-rpc-worker.test.ts`, and `tests/real-host-self-hosted-firecracker.ts`. The lock file also refreshes inputs beyond the added `microvm` input. | Implemented source and executable journey definition. No acceptance run occurred in this recovery. Dependency refresh scope needs isolation. |
| Vicinae launcher | `docs/reference/runtime-tests.md`, both launcher specs, `lib/flake-parts/checks/conventions.nix`, `tests/tests.just`, and `users/nori/programs/desktop/**`. The changes replace the old Fuzzel action front end with Vicinae and saved commands. | Source implemented. The launcher spec records disposable checks on 2026-09-12, but workstation activation and login persistence remain unverified. |
| qBittorrent | `services/qbittorrent/manifest.nix` changes `active = false` to `active = true`. | Independent configuration change. Deployment and ownership are unknown. |

`flake.lock`, Nix check registries, and task registries are shared integration surfaces. Do not build or activate this mixed tree.

### Generated desktop settings

The integration candidate is `feat/desktop-settings-service` at `e616463`, 29 commits beyond `main`. It contains the isolated Vicinae baseline, generated component contracts, the Quickshell and Vicinae clients, the shared service, activation boundaries, tests, and later authority/socket fixes.

The branch-local settings spec is frozen and says workstation activation remains operator-gated. It also says the required acceptance scenarios have not run and that no schema generation, Settings UI, service, build, activation, or runtime scenario has been proved by that document. Implementation commits do not satisfy that evidence boundary.

`git cherry feat/desktop-settings-service feat/settings-service-core` marks the remaining core patch equivalent. The same comparison marks all three remaining Vicinae patches equivalent. Quickshell commit `dd94953` is equivalent, while app commit `39a5c01` is not patch-equivalent. The integration branch contains the same broad draft-preview journey, with stricter preview identity and Apply gating. It is not contract-identical. The disposition of `39a5c01` remains unresolved; do not retire it from source inspection alone.

`feat/persona-settings` is an older, separate integration line with 12 tip-only commits against 69 main-only commits. Do not substitute it for the current candidate.

**Next action:** retain all settings branches. Review `e616463` at exact head. Compare the three Quickshell files against the frozen contract. Then run the specification gates from a clean committed candidate. Do not activate before operator authorization.

### Topology and TOSCA

`feat/tosca-topology-core` at `cb26373` compiles a normalized topology graph. `feat/tosca-topology-projection` at `fdef6f6` exports the graph as a restricted TOSCA 2.0 projection. `feat/tosca-topology-conformance` at `cd414d9` combines both streams and adds graph fixes, negative fixtures, Adelie placement checks, documentation updates, and a desktop-format commit.

```text
main 93807ae
  └─ frozen topology specification
      ├─ core cb26373
      └─ projection fdef6f6

main 93807ae
  └─ conformance cd414d9
      ├─ cherry-picked core and projection
      ├─ graph/TOSCA fixes and negative fixtures
      ├─ Adelie/deployment records
      └─ desktop formatting
```

The projection depends on the normalized graph. The branch-local `docs/specs/2026-09-12-topology-conformance.md` separates intended topology from active, observed, and proven state. No current topology acceptance report or deployment evidence was found. All commits on the three tips are unmatched by `git cherry main BRANCH`.

**Next action:** retain all three branches. Isolate topology changes from desktop-format and unrelated deployment history. Review the conformance branch at exact head before any merge or activation.

### Observer and history repair

| Ref | Meaning established from source/history | Next action |
|---|---|---|
| detached `1d3912a` | Observe-only Herdr cgroup snapshot; ancestor of `main`. | Retain as historical evidence until the decision is settled. |
| `fixed-mixed-history` at `b052c1d` | Mixed Vicinae and observe-only commits. | Separate the two outcomes before integration. |
| `revert-mixed-observer` at `5aa30fb` | Explicit revert of the observer commit. | Decide whether it is intended repair or superseded history. |
| `herdr-resource-observer` at `4690f6c` | Broader weighted scheduler with observe, dry-run, and enforce modes. | Perform a separate design and acceptance review. Do not conflate it with observation. |

No live observer file, timer execution, scheduler enforcement, or notification receipt was inspected.

### Infrastructure and operational state

- [`inventory/hosts.nix`](../../../inventory/hosts.nix) declares workstation, Pi, and staged Adelie. Adelie has no LAN address or workloads.
- [`inventory/backup.nix`](../../../inventory/backup.nix) sets `enabled = true`. The README, roadmap, topology prose, and comments still include disabled or pending language.
- [`docs/specs/ansible-pi-plan-b.md`](../../specs/ansible-pi-plan-b.md) records historical Pi evidence and remaining physical, off-LAN, reboot, service-restoration, and restore gates.
- [`docs/runbooks/onetouch-backup-cutover.md`](../../runbooks/onetouch-backup-cutover.md) owns disk identity, capacity, credential, snapshot, integrity, and restore gates.
- The currently active workstation generation is `/nix/store/0d5fjw4k9ch2l0vcjajc59q9kpnh5pi9-nixos-system-workstation-26.11.20260910.8ce4ef6`.

The generation path does not identify a homelab Git revision. This recovery did not inspect effective service health or run backup jobs. Correct status: **OneTouch source enabled; live backup and restore acceptance unverified.** Adelie is a staged inventory host, not evidence of a third operational host.

### Existing roadmap outcomes

The `feat/public-status` tip is an ancestor of `main`. Source integration does not prove Cloudflare publication or production acceptance. The roadmap now states that distinction.

The existing deployment planner scopes configuration effects. It does not track unfinished-work ownership and cannot establish that a build or deployment occurred. See [`docs/reference/deployment.md`](../../reference/deployment.md).

## Dependency view

```text
mixed main ──must be isolated──┬─ Firecracker acceptance candidate
                              ├─ Vicinae activation candidate
                              └─ qBittorrent configuration decision

Vicinae baseline ──feeds──> desktop settings integration ──needs──> exact-head gates ──then──> operator activation

topology core ──feeds──> topology projection
       └───────────────> combined conformance candidate ──needs──> scope cleanup and exact-head gates

inventory source ──feeds──> deployment plan and generated docs ──does not prove──> activated runtime
```

## Registered worktrees

Counts are `main-only / tip-only`. They measure ancestry, not patch equivalence or acceptance. Ignored files and caches are excluded from dirty counts.

| Checkout | Branch / HEAD | Main-only / tip-only | State | Last commit |
|---|---|---:|---|---|
| `/srv/share/projects/homelab` | `main` | 0 / 0 | dirty (34 tracked, 5 untracked) | `93807ae09ccc` docs: specify generated desktop settings service |
| `/srv/share/projects/homelab-desktop-settings-service` | `feat/desktop-settings-service` | 0 / 29 | clean | `e61646357004` Fix desktop settings client socket boundary |
| `/srv/share/projects/homelab-oversight-recovery` | `docs/homelab-oversight-recovery` | 0 / 0 | recovery writer: 1 tracked modification, 1 untracked report | `93807ae09ccc` docs: specify generated desktop settings service |
| `/srv/share/projects/homelab-settings-quickshell` | `feat/settings-quickshell` | 0 / 5 | clean | `dd949536e9be` feat: preview settings drafts before commit |
| `/srv/share/projects/homelab-settings-service-core` | `feat/settings-service-core` | 0 / 4 | clean | `f1c11b51c103` feat(desktop): add settings change service core |
| `/srv/share/projects/homelab-settings-vicinae` | `feat/settings-vicinae` | 0 / 6 | clean | `2b1f26696aeb` feat: preview Vicinae setting changes |
| `/srv/share/projects/homelab-topology-conformance` | `feat/tosca-topology-conformance` | 0 / 18 | clean | `cd414d9eb4e7` style(nix): format integrated desktop modules |
| `/srv/share/projects/homelab-tosca-core` | `feat/tosca-topology-core` | 0 / 2 | clean | `cb26373deb14` feat(inventory): compile topology graph |
| `/srv/share/projects/homelab-tosca-projection` | `feat/tosca-topology-projection` | 0 / 2 | clean | `fdef6f61b391` feat(topology): add TOSCA intent projection |
| `/srv/share/projects/homelab/.worktrees/chatlog-workstation` | `feat/chatlog-workstation` | 145 / 8 | clean | `8bd83d2ad03b` chore(workstation): enable Chatlog pattern reviews |
| `/srv/share/projects/homelab/.worktrees/fix-format-drift` | `chore/fix-format-drift` | 69 / 1 | clean | `97c44a58d540` chore(format): align files with current nixfmt |
| `/srv/share/projects/homelab/.worktrees/fixed-mixed-history` | `fixed-mixed-history` | 2 / 2 | clean | `b052c1dcb669` feat(agents): observe Herdr cgroup resources |
| `/srv/share/projects/homelab/.worktrees/herdr-resource-observer` | `herdr-resource-observer` | 2 / 2 | clean | `4690f6ceda2f` feat(agents): prepare weighted Herdr memory scheduler |
| `/srv/share/projects/homelab/.worktrees/revert-mixed-observer` | `revert-mixed-observer` | 1 / 1 | clean | `5aa30fb8abae` Revert "feat(agents): observe Herdr cgroup resources" |
| `/srv/share/projects/homelab/.worktrees/settings-integration` | `feat/persona-settings` | 69 / 12 | clean | `dc70a40cc93f` docs(settings): align purpose with current scope |
| `/srv/share/projects/homelab/.worktrees/verify-e2e-multi-host` | `fix/e2e-multi-host-caddy-address` | 69 / 2 | clean | `6f7592e87e68` fix(tests): bind Pi smoke Caddy fixture address |
| `/tmp/homelab-final-preview-20260831` | `46e1f3b40dc64ed4506d29768f2e047870ebd9a8` | — | missing registration | — |
| `/tmp/homelab-final-preview-clean-20260831` | `46e1f3b40dc64ed4506d29768f2e047870ebd9a8` | — | missing registration | — |
| `/tmp/homelab-herdr-observer.SojqYo` | `1d3912affd8fcf727e045fbf7b2bf4c97e1d1518` | 1 / 0 | clean | `1d3912affd8f` feat(agents): observe Herdr cgroup resources |
| `/tmp/homelab-persona-preview-20260831` | `220123ec2d3f0c5a0cf88647d4ddf4b244ba3d66` | — | missing registration | — |

The table includes the documentation worktree created by this recovery. Before that addition, Git had 19 registrations: 16 existing paths and three missing `/tmp` paths.

## Standalone and evidence directories

These direct children of `.worktrees/` are not registered worktrees:

| Path | Classification | State |
|---|---|---|
| `.worktrees/complete-migration` | Standalone Git clone | Clean `main` at `da9b767`, 15 commits ahead of its cached `origin/main`. Retain. |
| `.worktrees/complete-migration-ready` | Standalone Git clone | Clean `refactor/complete-migration` at `313e305`. Retain. |
| `.worktrees/two-host-migration` | Standalone Git clone | Dirty `refactor/two-host-migration` at `06de338`: 54 tracked status records and 22 untracked paths. Retain and establish custody. |
| `.worktrees/two-host-migration-evidence` | Evidence directory, no local `.git` marker | Contains retained logs, a bundle, and acceptance artifacts. Retain independently of branch status. |
| `.worktrees/two-host-migration-verification.md` | Evidence file | Retain. |

`.claude/worktrees/` is empty. No entries were inaccessible.

## Local branches without a checkout

This table covers all 43 local branches that lacked a checkout after the documentation worktree was created. A `+` result from `git cherry main BRANCH` is counted as unmatched. A `-` result is patch-equivalent. Patch equivalence is not permission to delete a ref.

| Branch | Tip | Checked out | Main-only / tip-only | Patch relation / action |
|---|---|---:|---:|---|
| `add-drinks-stremio` | `ad38172a0236` | no | 797 / 0 | ancestor of main; later retention review |
| `advisor/001-isolate-pavilion-sops` | `c5f5421ddb57` | no | 265 / 1 | 1 unmatched, 0 equivalent; retain and review |
| `backup/hypr-rice-layout-pre-rebase` | `35b6152b374b` | no | 265 / 24 | 0 unmatched, 24 equivalent; retain and review |
| `backup/local-pre-rebase` | `e88f1056d4c2` | no | 938 / 3 | 1 unmatched, 2 equivalent; retain and review |
| `chatlog-promotion-nix-source` | `112659e83613` | no | 235 / 0 | ancestor of main; later retention review |
| `explore/e2e-vm-simulation` | `6bc9addaaa56` | no | 348 / 0 | ancestor of main; later retention review |
| `explore/machine-capabilities` | `a993a02fd4a9` | no | 366 / 0 | ancestor of main; later retention review |
| `extract/hyprland-bank-dissection` | `eab9c23f8c34` | no | 155 / 5 | 1 unmatched, 4 equivalent; retain and review |
| `feat/agents-alerts-to-pi-ntfy` | `9a0ef9894087` | no | 161 / 1 | 0 unmatched, 1 equivalent; retain and review |
| `feat/architecture-simplification` | `cf7702c69d2f` | no | 176 / 0 | ancestor of main; later retention review |
| `feat/clamor-agents-route` | `e26fc5027c1b` | no | 161 / 0 | ancestor of main; later retention review |
| `feat/clawpatrol-egress` | `16a24b8826db` | no | 161 / 4 | 4 unmatched, 0 equivalent; retain and review |
| `feat/flow-agent-dispatch-v3` | `1af429319a9b` | no | 215 / 2 | 2 unmatched, 0 equivalent; retain and review |
| `feat/herdr-monitor-module` | `bccc7a437574` | no | 143 / 1 | 1 unmatched, 0 equivalent; retain and review |
| `feat/herdr-slice-memory-cap` | `2283e3b03727` | no | 161 / 1 | 0 unmatched, 1 equivalent; retain and review |
| `feat/ntfy-declarative-bootstrap` | `4aad36917e6d` | no | 143 / 1 | 1 unmatched, 0 equivalent; retain and review |
| `feat/persona-settings-app` | `f03db1d03a37` | no | 69 / 3 | 3 unmatched, 0 equivalent; retain and review |
| `feat/persona-settings-core` | `0ddca7ad70dc` | no | 69 / 2 | 2 unmatched, 0 equivalent; retain and review |
| `feat/public-status` | `1e76c85264ce` | no | 164 / 0 | ancestor of main; later retention review |
| `feat/status-maintenance` | `8532036840f0` | no | 162 / 1 | 1 unmatched, 0 equivalent; retain and review |
| `feat/unstable-herdr-codex` | `3b6881479f18` | no | 237 / 0 | ancestor of main; later retention review |
| `feat/workload-role-placement` | `3a0c8b940389` | no | 167 / 0 | ancestor of main; later retention review |
| `feature/agent-usage-waybar` | `aa838487cedd` | no | 128 / 1 | 1 unmatched, 0 equivalent; retain and review |
| `fix/agent-notify-herdr-suppression` | `4deb1e874934` | no | 168 / 0 | ancestor of main; later retention review |
| `fix/nix-daemon-memory-ceiling` | `6299ce79a8ed` | no | 105 / 0 | ancestor of main; later retention review |
| `hypr-rice-layout` | `95a014f68b89` | no | 240 / 0 | ancestor of main; later retention review |
| `hypr-space-wayfinder` | `d562be18c3f7` | no | 238 / 2 | 2 unmatched, 0 equivalent; retain and review |
| `hyprland-layer-management` | `141d2533d736` | no | 235 / 2 | 2 unmatched, 0 equivalent; retain and review |
| `integrate/hyprland-layer-management` | `aafb13f798b7` | no | 169 / 0 | ancestor of main; later retention review |
| `list` | `a76d7f556ca7` | no | 375 / 0 | ancestor of main; later retention review |
| `ops/pause-qbittorrent` | `a1209c3755de` | no | 129 / 0 | ancestor of main; later retention review |
| `pi-harness` | `dcc1a1941d2c` | no | 397 / 10 | 10 unmatched, 0 equivalent; retain and review |
| `pi-harness-prompt` | `a8a1e74e14f7` | no | 162 / 1 | 1 unmatched, 0 equivalent; retain and review |
| `pr/bank-home-desktop` | `f362bb4641bd` | no | 149 / 0 | ancestor of main; later retention review |
| `pr/bank-network-observability` | `e9492235e0eb` | no | 154 / 0 | ancestor of main; later retention review |
| `pr/bank-plans-docs` | `b6c8dc90fa42` | no | 150 / 1 | 0 unmatched, 1 equivalent; retain and review |
| `pr/bank-plans-docs-clean` | `2379f18f478a` | no | 151 / 0 | ancestor of main; later retention review |
| `pr/bank-services` | `e61cee8caf57` | no | 152 / 0 | ancestor of main; later retention review |
| `pr/bank-tests` | `7dec0e01185e` | no | 148 / 0 | ancestor of main; later retention review |
| `recovery/pre-complete-migration-2026-09-08` | `7aa9a907b49b` | no | 21 / 2 | 1 unmatched, 0 equivalent; retain and review |
| `spec/pagu-homelab-flake-migration` | `45b0c69194b8` | no | 132 / 0 | ancestor of main; later retention review |
| `worktree-agent-a57187c16d2660aa2` | `e26fc5027c1b` | no | 161 / 0 | ancestor of main; later retention review |
| `worktree-agent-a6e9743ec5b9345c9` | `e26fc5027c1b` | no | 161 / 0 | ancestor of main; later retention review |

Coverage: 59 local branches total after adding the documentation branch. Sixteen are checked out and appear in the worktree table. The other 43 appear above.

## Process and runtime observation

The initial process snapshot did not identify an active homelab build, test, deployment, or writer owner.
Generic Nix processes were not treated as ownership evidence.

The September 19 update used operator-authorized remote commands.
It restored Beszel state, deployed scoped observability changes, and verified live endpoints and the authenticated UI.
No fetch, push, merge, branch deletion, publication, workstation activation, or Adelie activation ran.

## Source and document contradictions

1. **OneTouch:** resolved on September 19. The enabled source policy now has live backup, repository-check, and restore evidence.
2. **Host count:** inventory contains Adelie, workstation, and Pi. The root README describes two deployment targets. Adelie is staged, so the operational core can still be two hosts.
3. **Settings:** main says the design awaits freeze. The integration branch says frozen and contains implementation commits. Its own acceptance section still says the scenarios have not run.
4. **Vicinae:** source and dated disposable evidence exist. Workstation activation and login persistence remain held.
5. **Public status:** the feature branch is in main history. Publication remains unverified.
6. **Generated topology:** the committed projection predates staged Adelie. It is a stale projection candidate, not runtime truth.

## Refresh procedure

Run these commands from any directory. Replace `R`, `W`, and `TIP` with explicit paths or refs.

```bash
git --no-optional-locks -C R worktree list --porcelain
git --no-optional-locks -C R for-each-ref \
  --format='%(refname:short)|%(objectname)|%(upstream:short)' refs/heads
git --no-optional-locks -C R log --format='%h %cI %s' origin/main..main
git --no-optional-locks -C W status --porcelain=v1 -z -uall
git --no-optional-locks -C R rev-list --left-right --count main...TIP
git --no-optional-locks -C R log -1 --format='%H %cI %s' TIP
git --no-optional-locks -C R cherry main TIP
readlink -f /run/current-system
ps -eo pid,ppid,comm,etime --sort=comm
```

Parse the status stream as NUL-delimited records. Treat command errors as unknown state. Check for a local `.git` marker before running Git in a directory under `.worktrees/`.

## Decision gates

The mixed-tree recovery and selected integrations are complete. The next operator-gated action is live Pi and OneTouch acceptance.

1. Collect current Pi backup, restore, receiver, and physical-device evidence.
2. Decide the intended observer behavior before integrating observer history.
3. Compare older settings and topology branches with current `main`.
4. Review each remaining standalone fix independently.

This report records evidence. [`docs/roadmap.md`](../../roadmap.md) remains the single forward queue.
