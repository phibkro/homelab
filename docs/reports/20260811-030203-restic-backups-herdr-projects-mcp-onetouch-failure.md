---
date: 2026-08-11
summary: The first NEW restic job since the OneTouch moved to aurora could not create its repo — per-job repos sat at the SFTP chroot root, which sshd forces to be root-owned, so `initialize = true` never had write access there. Fix moves the repo base to a restic-owned /mnt/backup/repos and asserts against pathless SFTP targets. Requires a one-time move of existing repos on aurora before deploy.
---

# `restic-backups-herdr-projects-mcp-onetouch` failure — repos parked at the SFTP chroot root

## What failed

`restic-backups-herdr-projects-mcp-onetouch.service` on workstation,
2026-08-11 03:00. `Result=exit-code`, pre-start exit 1, `OnFailure` → `notify@`
+ `agent-fix@`.

```
Fatal: repository does not exist: unable to open config file: Lstat /herdr-projects-mcp/config: file does not exist
Is there a repository at the following location?
sftp:restic@aurora.saola-matrix.ts.net:/herdr-projects-mcp
Fatal: Fatal: create repository at sftp:… failed: MkdirAll /herdr-projects-mcp/index: permission denied
```

Nothing was corrupted and no snapshot was lost. The job (source path
`/home/nori/.local/state/herdr-mcp/projects`, read from the deployed unit's
`staticPaths`) has **never** had a repo on the OneTouch. Its `mp510` sibling
unit exists and is unaffected — the local target has no chroot.

## Root cause

Two facts that only collide on a job's FIRST run:

1. `nori.backupTargets.onetouch.repository` was
   `sftp:restic@aurora.saola-matrix.ts.net:` — no path. Per-job repos derive as
   `<repository>/<job>`, so every repo landed at the SFTP session root.
2. That root is aurora's `ChrootDirectory /mnt/backup` for the `restic` user.
   sshd requires a chroot root to be root-owned and not group/other-writable —
   `/mnt/backup` is the ext4 mount root, `root:root 0755` from mkfs. The
   chrooted `restic` user therefore cannot create anything directly inside it.

```
/mnt/backup            root:root 0755   chroot root — sshd's rule, unwritable by `restic`
/mnt/backup/<job>      restic:restic    works, but only because it was chowned BY HAND
```

Existing repos work because the 2026-06-11 OneTouch move chowned their
directories to `restic` (the "Onboarding existing repos" note in
`modules/infra/backup/restic-target/runtime.nix`). Writes *inside* an
already-existing repo dir never touch the chroot root, so every established
job stayed green — and hid the trap for five months. The first job added after
the move hit it head-on: `initialize = true` has to `mkdir` at the chroot root,
and cannot.

The module docstring asserted the opposite ("Per-job subdirs are restic-owned;
restic creates them via `initialize = true` on first push"), which is how a new
job got declared with no manual step. That claim was never true post-move.

## The fix

Repo base moves one level below the chroot root, into a directory the SFTP user
owns — so `initialize = true` is self-serving for any future job:

| File | Change |
|---|---|
| `modules/infra/backup/restic-target/runtime.nix` | `systemd.tmpfiles.rules` creates `/mnt/backup/repos` `0750 restic restic`; `chrootRoot`/`repoBase` let-bindings; docstring corrected (the false self-init claim removed, ownership table added) |
| `modules/infra/backup/restic.nix` | `onetouch.repository` → `sftp:restic@aurora.saola-matrix.ts.net:/repos` |
| `modules/infra/backup/default.nix` | new assertion: an `sftp:` target whose path is empty or bare `/` fails eval, with the chroot rationale in the message |
| runbooks + `storage.md` / `services.md` / `open-webui/runtime.nix` | restore paths updated to `/mnt/backup/repos/<repo>`; noted that those commands run on aurora |

Enforcement ladder: the tmpfiles-owned base makes first-init structural
(nothing to remember); the assertion makes the pathless-SFTP shape
unrepresentable at eval time rather than at 03:00.

Verified in the disposable clone:

```
nix eval …workstation.config.services.restic.backups."user-data-onetouch".repository
  → sftp:restic@aurora.saola-matrix.ts.net:/repos/user-data
nix eval …aurora.config.systemd.tmpfiles.rules
  → contains "d /mnt/backup/repos 0750 restic restic -"
assertions, all four hosts                     → 0 failing
assertion predicate on 6 repository shapes     → flags "…:" and "…:/", passes
                                                 "/repos", "…:23/restic", local, b2:
nix flake check --no-build                     → all checks passed
nix fmt on the four touched .nix files         → 0 changed
```

Not verified from here: the real SFTP handshake and the actual mode/ownership
of `/mnt/backup` on aurora — the fix-agent box has no network or aurora access.
Both are confirmed by step 1 of the deploy below.

## Deploy — do the move BEFORE workstation's rebuild

Changing the base orphans the existing repos unless their directories move with
it. They are on the same filesystem, so this is an instant rename, not a copy.
Repos written over SFTP are exactly the ones owned by `restic` — aurora's own
local-target repos stay at `/mnt/backup/<job>` and must NOT move.

```bash
# 0. on workstation: stop the timers so nothing fires mid-move
sudo systemctl stop 'restic-backups-*-onetouch.timer'

# 1. on aurora: confirm the diagnosis while you are there
ls -ld /mnt/backup                                  # expect root:root 0755
ls -l  /mnt/backup                                  # expect the per-job dirs, restic-owned

# 2. on aurora: rebuild (creates /mnt/backup/repos), then move the SFTP repos
just rebuild
sudo find /mnt/backup -maxdepth 1 -mindepth 1 -user restic -not -name repos \
  -exec mv -t /mnt/backup/repos {} +

# 3. on workstation: rebuild, then prove the round trip on one repo
just rebuild
sudo systemctl start restic-backups-user-data-onetouch.service   # must find history, not init
sudo systemctl start restic-backups-herdr-projects-mcp-onetouch.service  # must init cleanly
sudo systemctl start restic-check-weekly.service
sudo systemctl start 'restic-backups-*-onetouch.timer'
```

If workstation rebuilds first, the failure stays loud (`permission denied`
again, because `/mnt/backup/repos` does not exist yet) — not silent. The
dangerous order is aurora-rebuilt-but-not-moved: restic then inits empty repos
under `repos/` and re-uploads everything from zero, stranding the old snapshots
where `forget --prune` will never reach them.

## What to watch

- **First run after deploy.** `restic-backups-user-data-onetouch` should say
  "repository opened", not "created". A fresh init there means the move was
  missed — stop, restore the dirs into `repos/`, re-run.
- **`restic-check-weekly`** (Sun 05:00). It iterates `<repository>/<job>` and
  follows the new base automatically; a pair failing there means a repo dir was
  left behind at `/mnt/backup/`.
- **Drive space on aurora.** A missed move shows up as the OneTouch filling
  with a second copy of ~350 GiB.
- **`/mnt/backup/repos` after a detached-drive boot.** tmpfiles resolves the
  path through the OneTouch's automount; if the drive is absent the rule errors
  (`systemd-tmpfiles-setup.service`). That is the intended loud failure, but it
  is worth checking after any USB re-seat.

## `nix flake check` was already red — read the PR's status carefully

Both failures below predate this incident. Verified by building each check at
the unmodified branch point, before any edit in this PR:

| Check | Cause | Done here |
|---|---|---|
| `docs-fresh` | `docs/generated/backups.md` still listed the `qbittorrent` job; the operator paused qBittorrent on 2026-07-31 (`manifests/qbittorrent.nix`, `active = false`), flipping that job to `skip`, and the generated artifact was never refreshed | Regenerated from `nix build .#docs-backups`. Its output is byte-identical with and without this PR's module changes |
| `every-service-has-fs-hardening` | Same pause refactor: `modules/services/arr/qbittorrent.nix` now writes `nori.harden = lib.mkIf enabled { qbittorrent.binds = …; }`, and the guard greps for the literal `nori.harden.` | **Left alone** — see below |

So the relay's `nix flake check` still fails and this PR opens as a draft. That
verdict is about qBittorrent, not about the backup fix: eval is clean
(`nix flake check --no-build` passes, 0 failing assertions on all four hosts).

The hardening guard needs a decision the fix-agent should not make unattended:

- widen the grep (`nori\.harden` without the dot) — the module DID make an
  explicit hardening decision, and the `\.` is an accident of style that any
  future paused service will trip again; or
- reshape the module to `nori.harden.qbittorrent = lib.mkIf enabled { … }` —
  but that makes the attribute key exist while the service is paused, which
  hands the harden writer a name with no unit behind it.

The textual guard is the weak link either way; `docs/invariants.md` §
"Decision tree" is the right place to settle it.

## Open items (not fixed here)

- **The failing job is not in the repo.** `nori.backups.herdr-projects-mcp`
  exists in the deployed workstation generation but in no committed branch —
  the declaration is uncommitted in the operator's checkout. Commit it, or the
  next rebuild from `origin/main` silently drops the job (and its `mp510` repo
  goes stale) without any alert.
- **Aurora's own repos stay at `/mnt/backup/<job>`** while remote ones move to
  `repos/` — two layouts on one drive. Unifying them (aurora's local target →
  `/mnt/backup/repos`) is the tidier end state; it was left out because it
  moves more data for zero correctness gain today.
- **`just list-snapshots`** (`modules/infra/backup/backup.just`) still runs
  `restic -r /mnt/backup/{{repo}}` on workstation, where nothing has been
  mounted since 2026-06-11. Pre-existing drift; the honest fix is to derive the
  `-r` argument from `nori.backupTargets` instead of hardcoding a path.
