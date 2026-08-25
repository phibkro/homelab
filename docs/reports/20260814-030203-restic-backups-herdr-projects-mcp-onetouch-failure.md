---
date: 2026-08-14
summary: A new nori.backups job could never initialize its repo on the onetouch SFTP target — workstation pushed to the chroot root, which sshd forces to stay root-owned, so the chrooted restic user cannot mkdir there. Fix moves each client into a restic-owned per-host namespace (the shape pi already used) provisioned from the inventory.
---

# `restic-backups-herdr-projects-mcp-onetouch` failure — no writable parent for a new repo

## What failed

`restic-backups-herdr-projects-mcp-onetouch.service` on workstation, every night
since 2026-08-12 03:00 (three fires: 08-12, 08-13, 08-14). Exit 1 in
`ExecStartPre`, `OnFailure` → `notify@`.

```
Fatal: repository does not exist: unable to open config file:
       Lstat /herdr-projects-mcp/config: file does not exist
Is there a repository at the following location?
       sftp:restic@aurora.saola-matrix.ts.net:/herdr-projects-mcp
Fatal: Fatal: create repository at sftp:restic@aurora.saola-matrix.ts.net:/herdr-projects-mcp
       failed: MkdirAll /herdr-projects-mcp/snapshots: permission denied
```

Repo absent → `initialize = true` → `restic init` → denied. The job never had a
successful run; there is no snapshot history to lose.

Trigger: `6d3a5df` (2026-08-11 12:58) added `modules/services/herdr-projects-mcp`
carrying `nori.backups.herdr-projects-mcp.include = [ … ]`. First timer fire was
the next night. It is the first *new* onetouch job declared since the OneTouch
drive moved to aurora on 2026-06-11.

## Root cause

Structural, not job-specific: **workstation pushed its repos to the SFTP chroot
root, and the chroot root can never be writable by the pushing user.**

`sshd_config(5)` on `ChrootDirectory`: *all components of the pathname must be
root-owned directories that are not writable by any other user or group.*
`modules/infra/backup/restic-target/runtime.nix` chroots the `restic` user to
`/mnt/backup`, which is the ext4 mount root — root:root 0755, and must stay that
way or sshd rejects the session outright.

Workstation's target was `repository = "sftp:restic@aurora…:"`, so each per-job
repo derived as `<repository>/<job>` = `/<job>` — a direct child of that
permanently-unwritable root.

```
                 /mnt/backup            root:root 0755   ← chroot root, sshd-mandated
   before        ├── user-data/         restic:restic    ← hand-chowned 2026-06-11
                 ├── sonarr/            restic:restic    ← hand-chowned 2026-06-11
                 └── herdr-projects-mcp ✗ mkdir denied   ← nobody hand-created it
```

Existing jobs worked only because a one-time `chown -R restic:restic
/mnt/backup/{…}` was run when the drive moved (that step is documented in the
module). Writing *inside* an already-restic-owned job dir needs no permission on
the parent, so all ten pre-existing jobs kept passing — which is exactly why this
stayed invisible for two months.

The module comment asserted the opposite of the truth: *"Per-job subdirs
(/mnt/backup/<job>) are restic-owned; restic creates them via `initialize = true`
on first push."* Under this layout restic can create them only if their parent is
restic-owned, and the parent is the chroot root. The invariant sat on the
convention rung — "remember to mkdir on aurora when you add a job" — and nothing
enforced it.

The entry plane already had the fix without naming it: `modules/profiles/entry-plane.nix`
scoped pi to `sftp:restic@aurora…:/pi` (added after the 2026-06 `/caddy` +
`/authelia` cross-host collision). `/mnt/backup/pi` is an ordinary restic-owned
directory, so pi can create new job repos on its own. Workstation was the host
still pushing to the bare root.

## The fix

Per-host namespace for every client, generated on both sides from the same fact
(the client's hostname), so a new job — or a new pushing host — needs no
aurora-side step.

| File | Change |
|---|---|
| `modules/infra/backup/restic.nix` | `repository = "sftp:restic@aurora…:/${config.networking.hostName}"` (was bare `:`) |
| `modules/infra/backup/restic-target/runtime.nix` | tmpfiles `d /mnt/backup/<client> 0700 restic restic -` for every inventory host but this one; comment corrected + migration note |
| `modules/profiles/entry-plane.nix` | hardcoded `/pi` → `/${config.networking.hostName}` — same string today, same rule as every other client |
| `docs/reference/storage.md` | repo-path column now `/mnt/backup/<host>/<svc>` + why the `<host>` level is load-bearing |

```
                 /mnt/backup            root:root 0755   ← unchanged, sshd-mandated
   after         ├── workstation/       restic:restic 0700   ← tmpfiles, from inventory
                 │   └── herdr-projects-mcp/  ← restic init creates this itself
                 ├── pi/                restic:restic 0700
                 └── pavilion/          restic:restic 0700   ← empty until it pushes
```

Derivation strength moves from *convention* (hand-mkdir per job) to *generate*
(the namespace exists because the host is in `inventory/hosts.nix`). It also
retires the cross-host job-name collision class that produced the 2026-06 nightly
"repository already locked" alerts, for remote clients.

Verified by evaluation (no deploy):

```
.#nixosConfigurations.workstation.…onetouch.repository → sftp:restic@aurora…:/workstation
.#nixosConfigurations.pi.…onetouch.repository          → sftp:restic@aurora…:/pi   (unchanged)
.#nixosConfigurations.aurora.config.systemd.tmpfiles.rules
        → d /mnt/backup/{pavilion,pi,workstation} 0700 restic restic -
```

Not verifiable from the fix box: aurora's actual `/mnt/backup` ownership and the
SFTP handshake — this clone has no journal access and no key for aurora. The
permission model above is read off `sshd_config(5)` plus the module source; the
journal's error text matches it exactly, but the end-to-end journey is unrun.

## Required before workstation rebuilds — one-time, on aurora

Workstation's ten existing onetouch repos sit at the chroot root. After this
change it looks for them one level down. **If they are not moved first, the
backup units will silently `init` empty repos under `/mnt/backup/workstation/`
and orphan the entire snapshot history** — no alert, because initializing a
missing repo is normal behaviour.

```bash
# on aurora, before `just rebuild` on workstation
sudo systemctl start mnt-backup.mount
sudo mv /mnt/backup/{bazarr,jellyfin,jellyseerr,lidarr,media-irreplaceable,prowlarr,radarr,sonarr,stremio,user-data} \
        /mnt/backup/workstation/
sudo chown -R restic:restic /mnt/backup/workstation
```

The `mv` is a same-filesystem rename — metadata only, instant, no data copied.
`/mnt/backup/workstation` is created by this change's tmpfiles rule, so rebuild
aurora first, then move, then rebuild workstation. Confirm with
`ls /mnt/backup/workstation` (ten dirs) and `ls /mnt/backup` (aurora's own repos,
`pi/`, `pavilion/`, `workstation/` — nothing else).

## What to watch

1. **First night after deploy (03:00–04:30).** All eleven
   `restic-backups-<job>-onetouch` units must reach `snapshot … saved`.
   `herdr-projects-mcp` is the new one — it should `create repository` and take
   its first snapshot without help.
2. **`restic-check-weekly` the following Sunday 05:00.** It iterates
   `<repository>/<job>` from the same target, so it follows the move for free —
   which also makes it the detector for a forgotten migration: a repo it reports
   as freshly-empty means history was left at the old path. Snapshot counts per
   pair should match the pre-move counts.
3. **Aurora's `systemd-tmpfiles-setup.service`.** It now touches `/mnt/backup`,
   an `x-systemd.automount` path. Expect a boot-time spin-up of the OneTouch;
   a failure there means the drive is absent — a real backup-plane signal, not
   noise to silence.
4. **Disk use on the OneTouch.** A jump of roughly the current repo total is the
   signature of the orphan-history failure mode (old repos still at the root,
   new empty ones filling under `/workstation/`).

## Two things this fix does not do

**Aurora's own repos still live at the chroot root.** `nori.backupTargets.onetouch`
on aurora is the local path `/mnt/backup`, and root can create dirs there, so
aurora is not exposed to this bug. But `/mnt/backup/<job>` for aurora and
`/mnt/backup/<client>/<job>` for clients is an asymmetric namespace, and an
aurora job name can still collide with a *directory name* at the root. Making it
uniform (`/mnt/backup/aurora/<job>`) means migrating aurora's own repos too —
deliberately deferred; it is not on the path of this failure.

**`nori.backups.herdr-projects-mcp` is redundant coverage.** Its `include` is
`/home/nori/.local/state/herdr-mcp/projects`, which is already inside `/home` and
therefore already inside the `user-data` job (and not in its `exclude` list). The
separate job buys service-tier retention, not coverage. Worth a look on the
branch that owns that module — but a `skip = "…"` there would only have hidden
the structural bug until the next genuinely new job.

## Base-branch mismatch (read before reviewing the PR)

Per `docs/runbooks/agent-fix-on-failure.md` the fix agent clones **`origin/main`**
(`c0f6121`). The failing job does not exist there — `modules/services/herdr-projects-mcp`
lives on `fix/nix-daemon-memory-ceiling`, which is what workstation actually runs
and where `origin/HEAD` points. The two branches have diverged (11 commits / 1
commit).

All four files edited here are byte-identical across both branches in the regions
touched, so the change applies to either. But the runbook's assumption — "the
deployed system is `origin/main`" — is currently false, and the next fix-agent
fire will again diagnose a unit whose declaration it cannot see. Either point
`nori.agentFix` at the deployed branch or merge `fix/nix-daemon-memory-ceiling`
into `main`.
