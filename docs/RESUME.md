# Resumption guide

You are an agent continuing the nori homelab buildout. Phase 4
(bare-metal NixOS install on nori-station) just finished. This doc is
the orientation brief — read it first, then `docs/DESIGN.md` for
canonical architecture.

## Where state lives

- **Repo:** `/Users/nori/Documents/nix-migration` (local), pushed to
  `git@github.com:phibkro/homelab` (public, `main`).
- **Canonical design:** `docs/DESIGN.md`. Two-host topology
  (nori-station + nori-pi), seven-layer architecture, three named
  backup patterns (A/B/C), disko-from-day-zero. Source of truth for
  *why* decisions are what they are.
- **Project memory** (auto-loaded when working in this directory):
  `~/.claude/projects/-Users-nori-Documents-nix-migration/`. Index is
  `MEMORY.md`; files cover user, project state, gotchas, working style.
- **Git history:** `git log --oneline` — commit-by-commit narrative.
- **Inventory** (gitignored): `inventory-nori-station-20260424T220429Z/`
  captures Ubuntu source. Use selectively when migrating specific
  services in Phase 5.

## Phase status

| Phase | What | State |
|---|---|---|
| 0 | Inventory + flake skeleton | done |
| 1 | Backups (rsync + partclone) | done; verified on One Touch |
| 2 | Reformat IronWolf Pro to btrfs | **DONE** (pulled forward; see below) |
| 3 | VM dry-run install | done; `vm-test` retained for testing |
| 4 | Bare-metal install on nori-station | done |
| 5 | Service migration | in progress (tailscale module + media data; services pending) |
| 6 | Desktop environment (Hyprland) | not started |

Reactive (no scheduled trigger): Cloudflare Tunnel + Access, email
digest reports, second media drive, deploy-rs. See DESIGN.md.

## Current state of nori-station

NixOS on bare metal. Reachable from the Mac at `192.168.1.181` (LAN)
and on the tailnet at canonical `nori-station` (renamed from
`nori-station-1` after deleting the offline Ubuntu ghost). User
`nori` with passwordless wheel sudo, TTY password set manually
post-install. SSH key-only.

`modules/common/{base,users,tailscale}.nix` plus `default.nix` is the
new shape per DESIGN.md L335-348; `hosts/common.nix` is gone. The
tailscale module is the first service module — declares
`extraUpFlags = [ "--ssh" "--hostname=${networking.hostName}" ]` so
any future re-auth lands the canonical hostname.

`disko` applied to both NVMe root (SN750, btrfs label `nixos`, six
subvolumes) and IronWolf media (4 TB, btrfs label `media`, five
subvolumes per DESIGN L130-138). Both disko configs target by-id
paths, not `/dev/nvme*` — see "Disk identity" below.

Media tree current state:

```
/mnt/media/home-videos  18 GB  partial OneTouch Footage transfer
/mnt/media/photos       53 GB  IronWolf memories + partial OneTouch memories
/mnt/media/projects     18 GB  IronWolf projects + _exports/ subdir
/mnt/media/streaming     0     intentional, re-derivable per DESIGN tier
```

Files under `/mnt/media/` are owned `nori:users`. The OneTouch
contributions in `home-videos` and `photos` are mid-migration leftovers
the user wanted to review later (the OneTouch is the backup, doesn't
strictly need to live on the IronWolf too); not load-bearing.

## Disk identity (read this before anything that touches `/dev/nvmeN`)

NVMe `/dev` enumeration is unstable across reboots. At install time,
`/dev/nvme0n1` was the SN750; post-reboot it's `/dev/nvme1n1`. The
disko configs are by-id-pinned to prevent accidentally targeting the
wrong drive. Always disambiguate by model:

- WD Black SN750 1TB → NixOS root, btrfs label `nixos`
  by-id `nvme-WDS100T3X0C-00SJG0_204526810532`
- Corsair Force MP510 960GB → Windows, **never touch**
  by-id `nvme-Force_MP510_2031826300012953207B`
- Seagate IronWolf Pro 4TB → media btrfs, label `media`
  by-id `ata-ST4000NE001-2MA101_WS24X543`
- Seagate One Touch 5TB → external backup drive, exfat, normally on
  the Mac at `/Volumes/One Touch`. UUID `2A05-DC62`.

## Loose ends to address opportunistically

1. **`common-cpu-amd-pstate`** not imported in `hosts/nori-station/hardware.nix`.
   Explicitly omitted for first-install simplicity. Add back if/when
   AMD pstate tuning matters.
2. **OneTouch leftovers in `/mnt/media/home-videos` and `/mnt/media/photos`**
   from a partial Mac→host rsync that was killed mid-flight (openrsync
   was throughput-limited at ~8 MB/s vs gigabit's ~110 MB/s). User wanted
   to review later. Either clean wipe + re-restore from IronWolf-only
   (deterministic), or leave merged.
3. **scripts/backup.sh** has no restore-time verification. Pre-Phase-5
   rsync-to-exfat backups should be treated as snapshots-of-intent, not
   guaranteed sources of truth. Phase 5+ uses restic for this reason.

## Phase 5 starting points

DESIGN.md L186-289 has the service table and backup patterns. The arc
that's already happened (sequence below picks up after):

- ✅ Tailscale module landed; canonical hostname restored.
- ✅ Phase 2 (IronWolf btrfs reformat) pulled forward; media subvolumes
  in place; IronWolf irreplaceables restored.

What's next, roughly in order:

1. **Samba.** First true service module (`modules/services/samba.nix`).
   Pattern A backup. Modest scope — one or two shares to start
   (`/srv/share`, maybe `/mnt/media/streaming` once Jellyfin's there).
2. **Ollama + Open WebUI.** Models from
   `nori-backup-20260424T223707Z/ollama-share/` on the One Touch.
   Pattern A for Ollama, Pattern C2 (sqlite `.backup`) for Open WebUI.
3. **Jellyfin.** Reads `/mnt/media/streaming` (currently empty) and
   `/mnt/media/home-videos` (has the OneTouch Footage import).
4. **`backup-restic.nix` module.** Implements Pattern A/B/C as reusable
   building blocks. Worth landing before more services so each new
   service onboards with backup config in the same PR.

**`nori-pi` is deferred** — no NixOS-bootable USB SSD on hand yet.
The existing Raspberry Pi runs PiOS and can fill the interim role for
DNS (Blocky via apt) and/or as a restic target if it has a USB HDD
attached. When a fresh SSD lands, do the NixOS Pi properly and migrate
those interim services into `hosts/nori-pi/` declaratively.

Restic backups need a target. Until either the NixOS Pi or PiOS-as-
interim is set up, services can run unbacked-up (acceptable for short
stretches if data is re-derivable) or back up to a temporary local
path on root. Don't let "no Pi yet" become an excuse to defer restic
configs indefinitely; land the modules with a placeholder target.

## Working style with this user

`memory/feedback_style.md`. Short: answer first, push back on weak
decisions, don't manufacture concerns, don't flatter. Call out XY
problems. CS student with FP background; technical fluency assumed.

## On first turn

If the user's opening is open-ended ("where are we?", "what now?"),
respond with one paragraph of status, the immediate next concrete
action they'd take, and at most two open questions. Don't dump the
roadmap. They're already the architect; you're implementing alongside.
