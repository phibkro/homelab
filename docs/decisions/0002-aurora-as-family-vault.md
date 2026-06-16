# ADR-0002: Aurora as family vault; workstation as sleep-friendly compute

- Status: Accepted
- Date: 2026-06-11

## Context

Today's homelab concentrates almost everything on **workstation**: the HTTP entry plane (Caddy + Authelia + Blocky-authoritative), every family-tier service (Vaultwarden, Radicale, Miniflux, Glance, Heim), every media reader (Immich, Jellyfin, Calibre-web, Komga, Navidrome), the whole `*arr` bundle, the desktop, and the entire storage stack (root SN750 + IronWolf media + OneTouch backup target). Aurora has been a single-role immich-machine-learning offload host since the GPU-thrash incident in April; pi runs the network appliance functions; pavilion is the agent quarantine.

Three latent problems compound:

1. **Power.** Workstation idles ~250 W. Family-tier surface gets used minutes per day; workstation is up 24/7 to serve it. ~6 kWh/day baseline, mostly wasted.
2. **Single point of failure.** Any workstation outage (reboot, kernel panic, hardware failure, ill-timed `nixos-rebuild switch`) takes down family passwords, family calendar, photos, RSS, and the SSO that fronts them. Pi covers observability; nothing covers the family surface.
3. **Replication is theatre.** Irreplaceable data (photos, home-videos, projects, archive, library) lives on IronWolf with restic copies on the OneTouch and `@restic-local` IronWolf subvol — but all on workstation, sharing one PSU, one kernel, one room's airflow. One failure domain. The "3-2-1" claim doesn't survive scrutiny.

Two discoveries shaped what's tractable:

- **Irreplaceable media is small** — ~334 GB total across @photos/@home-videos/@projects/@library/@archive. The 3 TB mass on `/mnt/media` is `@downloads`, which is re-derivable. Previous reasoning assumed the irreplaceable tier was much bigger; correcting for actual size unlocks placement options.
- **Aurora's idle Toshiba HDD (932 GB)** comfortably holds all irreplaceable media plus working headroom. The Force MP510 NVMe (894 GB), freed when the Windows partition was retired, is similarly available.

Hardware constraints:

- **Jellyfin NVENC HEVC encoding requires RTX 5060 Ti** (workstation's Blackwell). Aurora's GTX 950M is Maxwell — NVENC supports H.264 only, no HEVC/AV1; software fallback hammers the i7-6700HQ.
- **Ollama** wants the 5060 Ti's 16 GiB VRAM. Aurora can't substitute.
- **`@downloads`** (2.7 TB) is bound to Jellyfin transcoding + `*arr` write paths, so it cannot leave workstation without dragging Jellyfin and the arr stack with it (which then hit the Maxwell ceiling).

## Decision

Reorganise hosts so storage matches its consumers and so the family-tier surface lives on always-on hardware that isn't workstation.

```
BEFORE                                       AFTER
─────────────────────────────────────        ─────────────────────────────────────
┌─ workstation ─────────────────────┐        ┌─ workstation ─────────────────────┐
│ Everything except observability.  │        │ Sleep-friendly compute.           │
│ HTTP entry plane.                 │        │ GPU (Ollama, Jellyfin), bulk      │
│ Family-tier surface.              │        │ downloads, *arr stack, desktop.   │
│ All irreplaceable data            │        │ Cold replica of /mnt/family/*     │
│ (single failure domain).          │        │ on MP510. Wakes via WoL.          │
│ Idle ~250W, 24/7.                 │        │ ~250W when on, 0W asleep.         │
└───────────────────────────────────┘        └───────────────────────────────────┘

┌─ aurora ──────────────────────────┐        ┌─ aurora ──────────────────────────┐
│ Single-role immich-ml offload.    │        │ Always-on family vault.           │
│ ~25W.                             │        │ Caddy + Authelia + Blocky-#1.     │
│                                   │        │ Family-tier services + photo/     │
│                                   │        │ book/music readers.               │
│                                   │        │ /mnt/family (live) + OneTouch     │
│                                   │        │ (restic vault). ~25-30W.          │
└───────────────────────────────────┘        └───────────────────────────────────┘

┌─ pi ──────────────────────────────┐        ┌─ pi ──────────────────────────────┐
│ Network appliance: DNS, obs,      │        │ Unchanged. + Blocky-#2 secondary  │
│ alert, Tailscale.                 │        │ when route-data extraction lands. │
└───────────────────────────────────┘        └───────────────────────────────────┘

┌─ pavilion ────────────────────────┐        ┌─ pavilion ────────────────────────┐
│ Agent quarantine only.            │        │ Agent quarantine + weekly         │
│                                   │        │ tertiary replica of family/*.     │
└───────────────────────────────────┘        └───────────────────────────────────┘
```

### Per-host role

- **Aurora** — always-on family/data vault.
  - Primary `/mnt/family/*` (irreplaceable tier) on the Toshiba HDD.
  - Caddy + Authelia + Blocky-authoritative-#1 (HTTP entry plane).
  - Family-tier services: Vaultwarden, Radicale, Miniflux, Glance, Heim.
  - Photo/book/music readers: Immich (server + DB + ML), Calibre-web, Komga, Navidrome.
  - OneTouch (physically moved from workstation) attached as `/mnt/backup` — restic destination for every host.
- **Workstation** — sleep-friendly compute.
  - SN750: root + `/var/lib` for workstation services + `/srv/share`/`/srv/nori`.
  - MP510 (Windows partition wiped): `/mnt/backup-local` (workstation-side restic-local target, replacing IronWolf's `@restic-local` subvol) **and** `/mnt/family-replica/*` (cold replica of aurora HDD, btrfs send/receive nightly).
  - IronWolf: trimmed to `@downloads` + `@streaming` only.
  - Ollama, Open-WebUI, Jellyfin (NVENC), full `*arr` bundle, qBittorrent, Stremio, desktop.
  - Wakes via WoL when Jellyfin streams / arr scrapes / Samba `/mnt/media` access happens.
- **Pi** — unchanged. Network appliance (DNS forwarder, observability, alerting, Tailscale).
  - Gains Blocky-authoritative-#2 as a secondary resolver once the routes-as-data refactor lands (P1/P2).
- **Pavilion** — agent quarantine **plus tertiary irreplaceable-media replica.**
  - btrfs send/receive weekly from aurora → pavilion subvol (~334 GB). Cadence chosen low because pavilion has anti-write posture; weekly still gives a third independent host copy.

### Replication topology for irreplaceable data

```
                  Immich / Calibre / Komga / Navidrome
                                │
                                ▼
        ┌──────────────────────────┐       ┌──────────────────────────┐
        │ AURORA HDD               │       │ WORKSTATION MP510        │
        │ Live, hot                │──────▶│ Cold replica             │
        │ btrfs subvols            │ nightly│ btrfs receive            │
        │ Toshiba 932 GB           │       │ Force NVMe 894 GB        │
        │ ─ FAILURE DOMAIN 1 ─     │       │ ─ FAILURE DOMAIN 2 ─     │
        └────────────┬─────────────┘       └──────────────────────────┘
                     │
              ┌──────┴──────┐
              ▼             ▼
        daily         weekly
              │             │
        ┌─────▼──────────┐  ┌▼─────────────────────┐
        │ ONETOUCH (USB) │  │ PAVILION HDD subvol  │
        │ Encrypted      │  │ Tertiary replica     │
        │ snapshot vault │  │ btrfs receive        │
        │ (restic)       │  │ WD 640 GB            │
        │ Seagate 5 TB   │  │                      │
        │ ─ DOMAIN 3 ─   │  │ ─ DOMAIN 4 ─         │
        └────────────────┘  └──────────────────────┘
```

Four copies across four host-level failure domains. Residual risk: total-apartment loss (fire, flood, theft of all hardware). Operator-accepted.

### Cloud off-site (Hetzner): rejected

The previously-deferred Hetzner Storage Box restic target is **no longer planned**. Three host-level replicas plus an encrypted snapshot vault cover every single-component failure mode (drive, PSU, kernel, host). The residual risk is a total-apartment loss (fire, flood, theft of all hardware) which the operator explicitly accepts. Hetzner adds ongoing cost (~36 EUR/yr), a third-party dependency, and a recovery path tied to off-LAN bandwidth — without addressing the residual risk it would meaningfully reduce only if a *second* off-site copy in a different region existed.

### Storage convention: drives are first-class movable resources

Per-drive concerns (Samba shares, `nori.fs.<X>` declarations, the backup-target shape) follow the drive when it physically moves between hosts. Mechanism: extending `nori.fs.<X>` with an optional `samba = { … };` block whose generator emits on whichever host imports the declaration. Concrete consequence: when OneTouch unplugs from workstation and replugs into aurora, the `nori.backupTargets.onetouch` entry moves from workstation's config to aurora's config and the rest of the system follows.

## Consequences

### Positive

- **Power: ~5 kWh/day saved** (~1800 kWh/year) when workstation sleeps during inactive media + arr windows. Real money at current NO electricity prices.
- **Family-tier services survive workstation maintenance/outage.** Aurora's uptime is now the family's continuity, and aurora is a low-thermal-stress laptop without rolling kernel upgrades / Hyprland config experiments / restic-backup IO every night.
- **Four-copy replication across four host-level failure domains** for irreplaceable media. From one effective failure domain to four; from "restic to a drive in the same chassis" to genuine cross-host redundancy.
- **Drives become first-class movable resources.** Future re-cabling decisions (e.g. someday moving IronWolf to aurora if a better GPU arrives there) are configuration changes, not architecture changes.
- **The abstractions this requires** (`nori.services.<svc>.tags` + `enableByTag`, `nori.lanRoutes.<X>.upstreams` for HA pools, `nori.fs.<X>.samba`, replication consistency verifier, cross-host restore drill) **are useful beyond this migration**. Per-service placement becomes declarative; tag-based bulk opt-in supports future host additions; route pools enable per-route HA when wanted.
- **Workstation's blast radius shrinks.** A failed `nixos-rebuild switch` no longer takes down family services. Restart experiments (kernel parameters, driver bumps, sleep tuning) become low-stakes.

### Constraints

- **Aurora outage now takes down the family surface.** Pre-migration that role belonged to workstation; the SPOF moved but didn't disappear. Aurora's failure profile is different — laptop-class hardware, single SSD, single HDD, no redundant PSU — and is now load-bearing. Mitigation: pi's secondary Blocky + the family-tier-on-aurora services are stateless or have backups; recovery from aurora hardware loss is "restore from OneTouch onto the next available host."
- **Workstation requires reliable Wake-on-LAN** for media access. WoL has been working historically but isn't currently verified for the new lifecycle. Phase 19 in the migration plan covers this.
- **Total-apartment loss is an accepted residual risk** (no off-site copy). Operator-acknowledged trade-off. If risk tolerance changes, ADR-NNNN can re-introduce Hetzner; the `nori.backupTargets` schema already supports it.
- **New family-tier service additions need aurora capacity checks.** Aurora HDD has ~600 GB headroom over the irreplaceable tier; aurora SSD has ~100 GB after root. Postgres-heavy or large-state services need explicit sizing.
- **Migration cost is one weekend of operator-supervised work** (Stages 3-4 in the plan): MP510 wipe + data sync + service state migration + Caddy cutover + OneTouch physical move. Stages 1-2 are autonomous.

### Structurally enforced

- **Per-service placement is declarative.** A service runs where `nori.services.<svc>.enable = true`. Move = flip the flag on aurora, unset on workstation. No file moves, no import changes.
- **Routes follow services automatically.** `nori.lanRoutes.<X>.upstreams` derives Caddy reverse-proxy targets from the placement registry; flipping `enable` re-routes Caddy on the next rebuild.
- **Samba shares follow the drive.** `nori.fs.<X>.samba` ensures the share lives wherever the disko entry does.
- **Replication consistency is monitored.** `just test-replicas` (added with the verifier module) detects silent drift between aurora primary and the replica targets; cross-host restore drill catches stale credentials before they bite during recovery.
- **The placement test stays unchanged.** Fate-sharing breaks the function, not "feels lightweight." Aurora doesn't violate this — family services genuinely need to survive workstation outage; pavilion's tertiary-replica role doesn't break the impermanence posture because writes happen weekly rather than daily.

### Reversibility

The migration plan (`docs/plans/2026-06-11-aurora-migration.md`) calls out per-phase reversibility. The Nix-only phases (P1-P8) are `git revert`-able. The MP510 wipe (P9) and the IronWolf subvol deletes (P14) are one-way; both are gated on verified copies of the affected data being present elsewhere. The OneTouch physical move (P13) is reversible by re-plugging into workstation. Service state migrations (P11) are recoverable from the pre-migration restic snapshot.

## Alternatives considered

### A. Status quo, just enable hypridle suspend + WoL on workstation

Tempting because it requires almost no architectural work; matches the user's earliest framing ("can we just turn off auto-suspend or fix the resume bug?"). Rejected because:

- Family services still die when workstation does — the primary motivation for the work doesn't get addressed.
- Replication remains theatre — single-host failure domain.
- The 5 kWh/day power saving only materialises if workstation is genuinely idle, but family-tier traffic keeps waking it.

This path is what we'd choose if power were the only concern. The replication and SPOF concerns make it insufficient.

### C. Move `/mnt/media` (IronWolf + downloads) to aurora; full media migration

The architecturally cleanest answer — every media service lives near its data. The binding constraint is GPU capability:

| Workload | Required hardware | Workstation | Aurora |
|---|---|---|---|
| Ollama LLM inference | Modern 14+ GiB VRAM | RTX 5060 Ti 16 GB Blackwell ✓ | GTX 950M Maxwell 2 GB ✗ |
| Jellyfin HEVC/AV1 NVENC encode | Pascal+ NVENC | ✓ | Maxwell — H.264 only ✗ |
| Immich ML inference | Modest CUDA | ✓ | ✓ (already runs here) |
| `@downloads` bulk storage | 3+ TB drive | IronWolf ✓ | (no drive of that size) ✗ |
| Family-tier always-on | Low-power 24/7 | (idle 250W, wasteful) | (laptop ~25W) ✓ |

Aurora can do Immich ML and family-tier services well; it can't do Ollama or modern Jellyfin transcoding. Software fallback on the i7-6700HQ Skylake-H is not acceptable for the operator's actual viewing patterns.

Secondary rejection reasons:

- Migration cost balloons: 3 TB physical move (vs ~334 GB), restic repo path migration touches every service, Samba bookmark churn on every client.
- Jellyfin direct-play works for some clients/codecs but not as a general policy.

Revisit conditions: aurora gains a modern GPU (Quadro P400, Arc A310, used GTX 1650+ — any Pascal+ NVENC). At that point this ADR can be superseded.

### D. Hybrid mirror — aurora HDD mirrors IronWolf primary; both can serve

Sounded promising as "best of both worlds." Rejected because:

- Two-way sync (rather than the chosen aurora-primary + workstation-replica model) opens conflict resolution: what happens if Immich on aurora and a Samba write on workstation touch overlapping content? Btrfs send/receive doesn't merge; rsync needs `--update` heuristics that aren't atomic.
- The operator's actual workflow is one-write-source-at-a-time. Conflict-resolution complexity doesn't earn rent.
- Adds storage redundancy on workstation that the replication topology already provides via MP510.

### E. Modest scope — only Vaultwarden / Radicale / Miniflux / Glance / Heim to aurora; photos + Immich stay on workstation

Surface-level appealing because it's the smallest set of moves. Rejected because:

- Immich (photos) is the most-used family-tier service AND the highest-impact irreplaceable data. Leaving it on workstation defeats both the SPOF and the replication objectives.
- The work to set up the Caddy/Authelia/Blocky-authoritative trio on aurora is the same regardless of how many services follow; doing it for only 5 services wastes the setup.

The chosen scope (Path B) is the sweet spot: everything that can move without hitting the Maxwell-NVENC ceiling does move.

### Hetzner Storage Box (cloud off-site) — explicitly rejected

Discussed under "Decision" above. The residual risk profile (total apartment loss only) doesn't justify the ongoing cost + dependency. Path forward if risk tolerance changes: the `nori.backupTargets` schema already supports remote SFTP targets (landed 2026-06-10), so re-introducing Hetzner is a single registry entry — no architectural change.

## See also

- Plan: `docs/plans/2026-06-11-aurora-migration.md` (the *how*)
- `docs/reference/storage.md` § value tiers — vocabulary used here
- `docs/reference/topology.md` § service placement — the fate-sharing test this ADR honours
- ADR-0001 § "Code is the single source of truth" — the practice that makes the per-host opt-in registry the authoritative answer to "where does X run?"
- `modules/effects/backup.nix` — `nori.backupTargets` (remote-URL support already landed)
- `modules/effects/fs.nix` — `nori.fs` (the `samba` block extension is part of P4)
- `modules/effects/lan-route.nix` — extensions for `port` auto-aggregation + `upstreams` land in P1
