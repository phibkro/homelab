---
summary: Recovery targets, runbook index, disk preservation constraints,
  and capacity observations for workstation and the Ansible Pi.
---

# Recovery

These are recovery targets, not measured guarantees for the current revision. Older runbooks may retain installation history; validate their paths and runtime owner against current inventory before executing them.

RTO targets for each failure class, the runbooks that hit them, and the permanent constraints that bound any recovery action.

## Current recovery posture

The two SSDs hold hot data; IronWolf Pro holds cold data. OneTouch is the
external workstation backup destination selected by `inventory/backup.nix`.
The [September 19 evidence](../archive/reports/2026-09-19-backup-evidence.md)
records the enabled destination, workstation service-state restore, and Pi
backup checks. The
[Pi host reconstruction drill](../archive/reports/2026-09-21-pi-host-reconstruction-drill.md)
connects clean configuration and reboot to a current Pi-hole snapshot in a
disposable guest. It does not measure physical replacement recovery.
Existing MP510 archives, local filesystem snapshots, and application dumps are
preserved. None establishes current backup coverage by itself. Same-disk
snapshots and dumps do not survive loss of that disk.

Aurora reuse is conditional on renewed connectivity. The September 6 check
found it offline. The September 19 Pi inspection established a strict
host-key-checked session through `pi.saola-matrix.ts.net`; the hostname,
Tailscale address, and remote host key agreed. Reverify host identity during
an incident. Do not use the stale address-form entry for `100.100.71.3`.

## RTO targets

| Failure | Target | Mitigation |
|---|---|---|
| Bad config | < 15 min | NixOS rollback (atomic generations); `bad-config.md` |
| Single file deletion | < 15 min | btrbk snapshot restore; `file-deletion.md` |
| Service corruption | < 1 hour | Stop service, restore subvolume snapshot, restart; `service-corruption.md` |
| Pi total failure | < 2 hours | The disposable ARM reconstruction and Pi-hole restore completed in 49 minutes. Physical replacement remains unmeasured. Reinstall supported Debian, converge Ansible, and restore only inspected state; `pi-failure.md` |
| Root drive failure (workstation) | < 1 day | Reinstall via disko + flake, inspect preserved archives for restorable state; `drive-failure-root.md` |
| Media drive failure | < 1 day for services, days for media data | Recovery depends on verified surviving copies; no media backup coverage established; `drive-failure-media.md` |
| Whole-machine loss | Days+ | Hardware procurement is the bottleneck |

## Runbooks (`docs/runbooks/`)

Each runbook is the step-by-step for one failure class. Initial outlines:

| Runbook | Trigger | Path |
|---|---|---|
| `bad-config.md` | NixOS activation failed or boot loops | Rollback via boot menu or `nixos-rebuild --rollback switch` |
| `file-deletion.md` | User deleted something they wanted | Identify subvolume → find pre-deletion snapshot in `/.snapshots` → copy out |
| `service-corruption.md` | Service refuses to start; data layer suspected | Stop service → restore subvolume snapshot to scratch → copy back → restart → verify. For databases: restore from latest restic snapshot of the dump dir, then `pg_restore` / SQLite import |
| `drive-failure-root.md` | SN750 dies | Replace drive → boot installer → clone flake → run disko → `nixos-install` → inspect existing archives before attempting state restore; preserve all surviving disks |
| `drive-failure-media.md` | IronWolf dies | Assess surviving copies → provision only an approved replacement disk → restore verified content or re-acquire available sources |
| `pi-failure.md` | Pi unreachable / hardware dead | Reinstall supported Debian → converge `infra/pi/` Ansible → restore selected state → verify DNS, routes, authentication and monitoring |
| `storage-full.md` | Disk pressure | Find what filled up; library is reflinked (not duplicated) — see `Mnemopi recall: gotcha-arr-reflinks-not-hardlinks` |
| `tailscale-acl.md` | Tailscale admin UI ACL recovery | Live ACL lives only in admin UI; this snapshots `tailscale-acl.json` for editor-regression + account-loss recovery |
| `agent-fix-on-failure.md` | An armed backup/check unit fails (`nori.agentFix`) | Recovery window survives → boxed agent diagnoses + opens a PR (draft if unfixed). Find the run at `journalctl -u agent-fix@<unit>` and resume its conversation via `claude --resume` (handle in the PR body) to steer + merge |

For migration-specific mount, identity, capacity, backup, and restore gates, use
the [OneTouch cutover runbook](../runbooks/onetouch-backup-cutover.md).

## Forward-direction runbooks (not recovery)

| Runbook | Trigger | Path |
|---|---|---|
| [Historical Grafana OIDC proposal](../archive/plans/grafana-oidc-bootstrap.md) | Design history | Unimplemented proposal; review current runtime before reuse |
| [Historical ntfy bootstrap proposal](../archive/plans/ntfy-auth-bootstrap.md) | Design history | Current Pi role already enforces deny-all; use its Ansible configuration |

## Permanent constraints (non-negotiable)

These are **inviolable** — every recovery action must respect them or the recovery itself is destructive.

| Constraint | Reason |
|---|---|
| **Preserve existing data and verify disk identity before recovery** | MP510 is an SSD with preserved historical archives, distinct from the OneTouch backup destination. Its historical Windows label in older plans is not authority to format it. Formatting or repartitioning requires a separate reviewed recovery procedure and explicit operator approval. |
| **Disko configs MUST target `/dev/disk/by-id/...`** | by-id paths follow the hardware; `/dev` paths follow PCIe scan order |
| **Disambiguate disks by model + by-id, never `/dev/nvmeN`** | Same reason as above; codified in `Mnemopi recall: gotcha-nvme-enumeration` |
| **Don't schedule destructive system changes during weeks with Aker demo pressure** | The lab is the operator's daily-driver; outage during high-load weeks isn't acceptable |
| **Backup verification is part of the system, not optional** | Require fresh snapshots and disposable restore evidence for the affected data; an enabled policy, green CI, or retained same-disk snapshots do not establish coverage |

## Capacity baseline

Recorded in `docs/reference/capacity-baseline.md` at Phase 4 completion. Values to capture:

- Free space per subvolume on workstation and pi
- Used space per subvolume on IronWolf
- RAM at idle (no Ollama loaded)
- RAM with one Ollama model loaded (32B Q4 baseline)
- Average sustained CPU during evening peak
- MP510 repository size and retained OneTouch archive inventory

**Re-checked quarterly.** Growth trends inform when a second drive on workstation is warranted, when Ollama model size needs to come down.

## Reactive triggers (no scheduled date)

These wait for a real signal before being worked:

| Trigger | What gets done |
|---|---|
| Genexis ISP modem allows bridge mode, OR ~$200 router enters budget | Stand up real LAN router (OPNsense/OpenWRT); migrate DNS/egress policy from `infra/pi/ansible/roles/firewall` and `services/tailscale/ansible` to the router. Then retire that effect; the same inventory can drive a router-side generator. See `docs/roadmap.md § "Architectural debt"` for the rationale. |
| ntfy alone proves noisy enough that summarization helps | Email digest reports |
| IronWolf > 80% full *or* RAID1 redundancy becomes desired | Second media drive on workstation |
| "Deployed broken config, lost remote access" incident | `deploy-rs` adoption |
