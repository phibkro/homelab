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
| 2 | Reformat IronWolf Pro to btrfs | deferred |
| 3 | VM dry-run install | done; `vm-test` retained for testing |
| 4 | Bare-metal install on nori-station | **DONE** |
| 5 | Service migration | not started |
| 6 | Desktop environment (Hyprland) | not started |

Reactive (no scheduled trigger): Cloudflare Tunnel + Access, email
digest reports, second media drive, deploy-rs. See DESIGN.md.

## Current state of nori-station

NixOS booting on bare metal. Reachable from the Mac at `192.168.1.181`
(LAN) and on the tailnet as `nori-station-1` (the canonical
`nori-station` name is held by the offline ghost of the old Ubuntu
node — see "loose ends"). User `nori` exists with passwordless wheel
sudo and TTY password set manually post-install. SSH is key-only;
the Mac's ed25519 key is in `common.nix`.

What's installed: only the baseline from `common.nix` (SSH, Tailscale,
basic packages, firewall, locale). No service modules yet — Jellyfin,
Ollama, Samba etc. are Phase 5.

## Loose ends to address opportunistically

These are minor and shouldn't block Phase 5 from starting; surface only
when relevant.

1. **Tailscale name collision.** New install registered as
   `nori-station-1`. Two paths to canonical:
   - Delete the offline `nori-station` (Ubuntu ghost) from the admin
     console at `login.tailscale.com/admin/machines`, then on the new
     node: `sudo tailscale logout && sudo tailscale up --ssh
     --hostname=nori-station`.
   - Or restore `/var/lib/tailscale/` from the rsync backup *before*
     starting tailscaled (would need a brief stop). This preserves the
     original device identity.
2. **`vm-test` ghost** on the tailnet (offline). Delete via admin
   console or leave alone.
3. **`common-cpu-amd-pstate` not imported** in `hosts/nori-station/hardware.nix`
   — explicitly omitted for first-install simplicity. Add back if/when
   AMD pstate tuning matters.
4. **Modules directory still has the old shape.** `modules/.gitkeep`
   placeholder remains. The DESIGN.md target shape is
   `modules/{services,desktop,common}/`. Refactor when the first real
   module gets written (Tailscale identity restore is a likely first).
5. **`hosts/common.nix` lives at hosts root**, not in `modules/common/`
   per DESIGN.md L335–348 layout. Cosmetic; move when modules land.

## Phase 5 starting points

DESIGN.md L186–289 has the service table and backup patterns. A
reasonable order:

1. **Tailscale identity restore.** Stop tailscaled, restore
   `/var/lib/tailscale/` from `nori-backup-20260424T223707Z/tailscale-state/`,
   start. Closes loose end #1.
2. **`/srv/share` and `/home` rsync** of human files from the Ubuntu
   backup — set this up before Samba so the share has data.
3. **Samba.** Pattern A backup. Modest scope (one share initially).
4. **Ollama + Open WebUI.** Models from `nori-backup-20260424T223707Z/ollama-share/`.
   Pattern A for Ollama, Pattern C2 (sqlite .backup) for Open WebUI.
5. **Jellyfin.** Reads from IronWolf which is still exfat at this
   point — fine for a first pass; reformat to btrfs in Phase 2 later.
6. **`backup-restic.nix` module.** Implements Pattern A/B/C as
   reusable building blocks for service onboarding going forward.
7. **`hosts/nori-pi/`.** New host, USB SSD root, restic target. Adds
   the second host to the flake.

Any service flow should land its restic backup config (Pi target +
Hetzner target) at the same time the service comes up. Don't defer
backups. Adding restic to a service later is the same amount of work
as adding it during onboarding, but only one of them produces a
backup-from-day-zero.

## Working style with this user

`memory/feedback_style.md`. Short: answer first, push back on weak
decisions, don't manufacture concerns, don't flatter. Call out XY
problems. CS student with FP background; technical fluency assumed.

## On first turn

If the user's opening is open-ended ("where are we?", "what now?"),
respond with one paragraph of status, the immediate next concrete
action they'd take, and at most two open questions. Don't dump the
roadmap. They're already the architect; you're implementing alongside.
