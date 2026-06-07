---
summary: RTO targets, runbook index, permanent constraints (never touch the
  Windows drive, by-id everywhere, …), capacity baseline schema. The "what
  breaks and how we put it back" reference.
---

# Recovery

RTO targets for each failure class, the runbooks that hit them, and the permanent constraints that bound any recovery action.

## RTO targets

| Failure | Target | Mitigation |
|---|---|---|
| Bad config | < 15 min | NixOS rollback (atomic generations); `bad-config.md` |
| Single file deletion | < 15 min | btrbk snapshot restore; `file-deletion.md` |
| Service corruption | < 1 hour | Stop service, restore subvolume snapshot, restart; `service-corruption.md` |
| Pi total failure | < 2 hours | Spare USB SSD or reflash from flake. **healthchecks.io alerts off-host** when pi misses 3+ heartbeats |
| Aurora total failure | degraded only — immich-ml falls back to host CPU via env-var change | Operator updates `IMMICH_MACHINE_LEARNING_URL` on workstation; non-blocking |
| Pavilion total failure | degraded only — agent quarantine unavailable | Agents fall back to workstation (less isolated). Pavilion uses impermanence so reinstall is fast |
| Root drive failure (workstation) | < 1 day | Reinstall via disko + flake, restic restore from `/mnt/backup` USB drives; `drive-failure-root.md` |
| Media drive failure | < 1 day for services, days for media data | Service config restored fast; bulk media restore is bandwidth-bound; `drive-failure-media.md` |
| Whole-machine loss | Days+ | Hardware procurement is the bottleneck |

## Runbooks (`docs/runbooks/`)

Each runbook is the step-by-step for one failure class. Initial outlines:

| Runbook | Trigger | Path |
|---|---|---|
| `bad-config.md` | NixOS activation failed or boot loops | Rollback via boot menu or `nixos-rebuild --rollback switch` |
| `file-deletion.md` | User deleted something they wanted | Identify subvolume → find pre-deletion snapshot in `/.snapshots` → copy out |
| `service-corruption.md` | Service refuses to start; data layer suspected | Stop service → restore subvolume snapshot to scratch → copy back → restart → verify. For databases: restore from latest restic snapshot of the dump dir, then `pg_restore` / SQLite import |
| `drive-failure-root.md` | SN750 dies | Replace drive → boot installer → clone flake → run disko → `nixos-install` → restic restore service state from Pi (faster) or Hetzner (slower) |
| `drive-failure-media.md` | IronWolf dies | Replace drive → `mkfs.btrfs` + subvolumes → restic restore irreplaceable subvolumes from Pi → re-download streaming media from sources |
| `pi-failure.md` | Pi unreachable / hardware dead | Swap to spare USB SSD with current flake → boot → verify Blocky + Tailscale come up → router DHCP unaffected (workstation is secondary DNS) |
| `inspect-windows-drive.md` | Need to verify Windows partition state | MP510 read-only mount + verification |
| `storage-full.md` | Disk pressure | Find what filled up; library is reflinked (not duplicated) — see `.claude/skills/gotcha-arr-reflinks-not-hardlinks/` |

## Permanent constraints (non-negotiable)

These are **inviolable** — every recovery action must respect them or the recovery itself is destructive.

| Constraint | Reason |
|---|---|
| **Never touch the Windows drive** (Corsair Force MP510, by-id `nvme-Force_MP510_2031826300012953207B`) | NVMe enumeration is unstable across reboots — at install time the WD Black SN750 (NixOS) was `nvme0n1` and the MP510 (Windows) was `nvme1n1`; post-reboot they swapped. A re-run of disko targeting the wrong `/dev` path would wipe Windows. Caught this latently after the swap; fixed by switching all disko configs to `/dev/disk/by-id/...` |
| **Disko configs MUST target `/dev/disk/by-id/...`** | by-id paths follow the hardware; `/dev` paths follow PCIe scan order |
| **Disambiguate disks by model + by-id, never `/dev/nvmeN`** | Same reason as above; codified in `.claude/skills/gotcha-nvme-enumeration/` |
| **Don't schedule destructive system changes during weeks with Aker demo pressure** | The lab is the operator's daily-driver; outage during high-load weeks isn't acceptable |
| **Backup verification is part of the system, not optional** | Tiered drill (`restore-drill-services` monthly + `restore-drill-user-data` quarterly) + `just test-backups` per deploy are the **real RTO measurement** — green CI is necessary, not sufficient |
| **Phase 2 (IronWolf reformat) does not happen during Phase 4 (install)** | Two separate sequential operations. Do not combine. (Phase 2 was eventually pulled forward as part of Phase 5 service migration, *after* Phase 4 was complete — same constraint, different timing than original plan.) |

## Capacity baseline

Recorded in `docs/capacity-baseline.md` at Phase 4 completion. Values to capture:

- Free space per subvolume on workstation and pi
- Used space per subvolume on IronWolf
- RAM at idle (no Ollama loaded)
- RAM with one Ollama model loaded (32B Q4 baseline)
- Average sustained CPU during evening peak
- Hetzner Storage Box usage

**Re-checked quarterly.** Growth trends inform when a second drive on workstation is warranted, when Hetzner tier needs upgrading, when Ollama model size needs to come down.

## Reactive triggers (no scheduled date)

These wait for a real signal before being worked:

| Trigger | What gets done |
|---|---|
| Future service needs to land public traffic on workstation | Tailscale Funnel — reference impl preserved in `memory/reference/tailscale_funnel_implementation.md` |
| ntfy alone proves noisy enough that summarization helps | Email digest reports |
| IronWolf > 80% full *or* RAID1 redundancy becomes desired | Second media drive on workstation |
| "Deployed broken config, lost remote access" incident | `deploy-rs` adoption |
| SATA HBA capacity becomes available | Migrate IronWolf from USB to internal SATA |
