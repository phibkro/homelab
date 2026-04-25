# Resumption guide

You are an agent continuing the nori-station NixOS migration. A previous
session got us to the Phase 4 starting line. This doc is the orientation
brief — read it first.

## Where state lives

- **Repo:** `/Users/nori/Documents/nix-migration` (local), pushed to
  `git@github.com:phibkro/homelab` (public, `main`).
- **Project memory** (auto-loaded when you're working in this directory):
  `~/.claude/projects/-Users-nori-Documents-nix-migration/`. Index file
  is `MEMORY.md`; specific files cover user profile, project state,
  working-style preferences, and gotchas.
- **Git history:** `git log --oneline` is a commit-by-commit narrative
  of what was decided and why. The first commit is `chore: initialize
  nix-migration repo scaffolding`.
- **Inventory:** `inventory-nori-station-20260424T220429Z/` (gitignored)
  captures the Ubuntu source system in detail. Read selectively if you
  need to understand a specific Ubuntu service before migrating it.

## Phase status

| Phase | What | State |
|---|---|---|
| 0 | Inventory + flake skeleton | done |
| 1 | Backups (rsync + partclone) | done; verified on One Touch |
| 2 | Reformat IronWolf Pro to btrfs | deferred (post-Phase-4) |
| 3 | VM dry-run install (UTM) | done; `vm-test` on tailnet |
| 4 | Bare-metal install on nori-station | **READY, not started** |
| 5 | Service migration | not started |
| 6 | Desktop environment | not started; user wants non-Gnome |

## When the user says "go" on Phase 4

1. Read `docs/baremetal-install.md` end-to-end before doing anything.
2. Walk the user through it section by section. Don't dump the whole
   thing at once. Ask for screenshots/output between sections.
3. The same loop pattern as Phase 3 applies: error → fix in repo → push
   → user `git pull && nixos-install` again. Expect 1–2 iterations on
   the nvidia driver package and possibly nixos-hardware module names.

## What we know is going to be ~fine on Phase 4

The flake builds, the btrfs subvol layout boots, systemd-boot installs,
the user setup with passwordless sudo + SSH key works. All proven on
Phase 3.

## What we're betting on the first time

- **`hardware.nvidia.package = nvidiaPackages.production`** is current
  enough for Blackwell (driver 575+). If not: try `beta` or `latest`,
  or pin an explicit version.
- **`nixos-hardware.nixosModules.{common-cpu-amd, common-pc-ssd}`**
  exist on master. If install evaluation errors on either name, drop
  the offending one — they're tweaks, not requirements.
- **UEFI NVRAM persists boot entries on this Gigabyte board.** UTM
  needed `bootctl install` after the first reboot; real hardware
  shouldn't. If it does, the recovery is in `docs/vm-install.md`.

## What to capture during/after Phase 4

- The `flake.lock` generated in `/tmp/homelab/` during the install. Pull
  it to the Mac, commit, push so future installs are reproducible.
- Whether `production` was the right nvidia package attribute. If we
  had to change it, lock that decision into `hosts/nori-station/hardware.nix`.

## What's deferred — surface only when relevant

- Cloudflared (no public services yet — resurface when one is needed)
- Restoring Tailscale identity from the rsync backup (vs. fresh
  registration)
- IronWolf Pro reformat to btrfs (Phase 2)
- Desktop environment selection (Phase 6)
- sops-nix wiring (introduce when the first secret is needed)
- Adding `common-cpu-amd-pstate` back to nori-station hardware

See `memory/project_nori_migration.md` for full context on each.

## Working style with this user

Read `memory/feedback_style.md`. Short version: answer first, reasoning
after. Push back on weak decisions. Don't manufacture concerns. Don't
flatter. Call out when a question hides an XY problem. The user is a
CS student with FP background — assume technical fluency.

## What to do immediately after reading this

If the user's first message is open-ended ("what now?", "where are we?"),
respond with: a one-paragraph status, the immediate next concrete action
(start Phase 4 when they're at nori-station with a USB ready), and
two-to-three open questions to confirm intent. Don't dump the whole
roadmap.
