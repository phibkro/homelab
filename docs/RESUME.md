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
| 5 | Service migration | in progress (file/AI/media services live; Cloudflare/observability pending) |
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
subvolumes) and IronWolf media (4 TB, btrfs label `ironwolf-storage`, five
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
- Seagate IronWolf Pro 4TB → media btrfs, label `ironwolf-storage`
  by-id `ata-ST4000NE001-2MA101_WS24X543`
- Seagate One Touch 5TB → external backup drive, exfat, normally on
  the Mac at `/Volumes/One Touch`. UUID `2A05-DC62`.

## Active services (snapshot)

| Module | Port | Exposure | State on host |
|---|---|---|---|
| `modules/common/tailscale.nix` | mesh | tailnet | active |
| `modules/services/samba.nix` | 445 | tailnet | shares `/mnt/media` + `/srv/share`, single user `nori` (smbpasswd-set) |
| `modules/services/blocky.nix` | 53/udp+tcp | LAN | StevenBlack/hosts blocklist; LAN-effective via Tailscale DNS push (`100.81.5.122` set as global nameserver in tailscale admin) |
| `modules/services/ollama.nix` | 11434 | tailnet | `pkgs.ollama-cuda`, RTX 5060 Ti, 3 models restored (qwen3.5:9b, gemma4:26b, gemma4:e4b) |
| `modules/services/open-webui.nix` | 8080 | tailnet | DynamicUser, sqlite at `/var/lib/open-webui/data/webui.db`, 1 user + 10 chats restored |
| `modules/services/jellyfin.nix` | 8096 | tailnet | `jellyfin` user added to `users` group; library setup pending in admin UI |
| `modules/services/backup-restic.nix` | n/a | n/a | three jobs (user-data, media-irreplaceable, open-webui Pattern C2) on **placeholder local repo** at `/var/backup/restic-local/`; sops-managed password |
| `modules/common/sops.nix` | n/a | n/a | scaffolding done, `secrets/secrets.yaml` encrypted to Mac + nori-station age keys |

## Loose ends to address opportunistically

1. **Placeholder restic target.** `/var/backup/restic-local/` on root is
   plumbing scaffolding, not a real backup. Swap repository URLs in
   `backup-restic.nix` to SFTP when a real target exists (PiOS interim
   restic-rest-server / `hosts/nori-pi/` later / Hetzner Storage Box).
2. **`common-cpu-amd-pstate`** not imported in `hosts/nori-station/hardware.nix`.
   Add back if AMD pstate tuning matters.
3. **OneTouch leftovers in `/mnt/media/{home-videos,photos}`** —
   ~31 GB of OneTouch-only content (Footage + memories) merged in
   alongside IronWolf-restored content. Treated as live archive
   (Option A from session discussion); not load-bearing, not
   problematic.
4. **scripts/backup.sh** has no restore-time verification. Pre-Phase-5
   rsync-to-exfat backups are snapshots-of-intent, not guaranteed
   sources of truth. Phase 5+ leans on restic.
5. **Open WebUI: OpenRouter as second backend.** Deferred per user
   choice. Add `OPENAI_API_BASE_URL=https://openrouter.ai/api/v1`
   plus `OPENAI_API_KEY` from sops to enable cloud LLMs alongside
   local Ollama.
6. **Jellyfin library config.** First-connect admin wizard at
   `http://nori-station.saola-matrix.ts.net:8096` — pick admin
   credentials, point libraries at `/mnt/media/{streaming,home-videos}`.

## What's next

DESIGN.md L186-289 has the full table. Likely candidates in priority order:

1. **Real restic target.** Either PiOS-imperative restic-rest-server
   on the existing Pi (interim) or wait for a NixOS-bootable USB SSD
   to land `hosts/nori-pi/` declaratively. Then Hetzner Storage Box
   for off-site.
2. **Observability.** `services.beszel.{hub,agent}` for metrics,
   Uptime Kuma container for synthetic checks, ntfy for alerts. All
   per DESIGN L454-483.
3. **Immich.** Photo library; Pattern B backup (Immich's own dump).
   `/mnt/media/photos` becomes a raw archive that gets selectively
   imported into Immich's library (separate fs path under
   `/var/lib/immich/`).
4. **Cloudflare Tunnel + Access.** Reactive — only when Tailscale
   friction emerges (someone refuses to install another app, public
   sharing needed).
5. **Hyprland desktop.** Phase 6, separate scope.

**`nori-pi` deferred** — no NixOS-bootable USB SSD on hand yet.
Existing Pi runs PiOS, can fill DNS (Blocky via apt) and/or
restic-target imperatively in the interim. Migrate to
`hosts/nori-pi/` declaratively when the SSD lands.

## Conventions

**Default-deny filesystem access for service modules.** Every new
service module's `serviceConfig` should include the namespace
restriction below; explicitly opt back in with `BindReadOnlyPaths`
for any host paths the service genuinely needs:

```nix
systemd.services.<name>.serviceConfig = {
  ProtectHome = lib.mkForce true;
  TemporaryFileSystem = [ "/mnt:ro" "/srv:ro" ];
  BindReadOnlyPaths = [ /* "/mnt/media", "/srv/share", etc. */ ];
};
```

`mkForce` is needed when the upstream module already sets
`ProtectHome` (ollama does), to avoid the boolean-vs-string
definition collision. Verify the namespace via:
`sudo nsenter -t <pid> -m -U -- ls /mnt/` from the host.

This mirrors the network policy (default-deny, services opt in to
specific tailnet/LAN ports). Goal: a compromised service can't
browse the host filesystem looking for credentials, even if it can
exec shell commands.

## Pending one-shot user actions

- Connect Mac/devices to Open WebUI (`http://nori-station.saola-matrix.ts.net:8080`)
  and verify chat history loaded correctly in the UI.
- Walk through Jellyfin admin wizard at `:8096` and add the two
  library paths.

## Working style with this user

`memory/feedback_style.md`. Short: answer first, push back on weak
decisions, don't manufacture concerns, don't flatter. Call out XY
problems. CS student with FP background; technical fluency assumed.

## On first turn

If the user's opening is open-ended ("where are we?", "what now?"),
respond with one paragraph of status, the immediate next concrete
action they'd take, and at most two open questions. Don't dump the
roadmap. They're already the architect; you're implementing alongside.
