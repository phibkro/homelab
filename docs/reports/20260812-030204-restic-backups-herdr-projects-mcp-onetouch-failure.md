---
summary: New restic jobs could never bootstrap a repo on the onetouch SFTP target — the chroot root is root-owned by OpenSSH requirement. Fixed with a per-host, restic-owned namespace directory on aurora.
---

# `restic-backups-herdr-projects-mcp-onetouch` failed — new jobs cannot init a repo on the SFTP target

Failed nightly on workstation, 2026-08-11 and 2026-08-12 at 03:00. Any
other new backup job would have failed identically.

## What failed

```
pre-start: Fatal: repository does not exist: unable to open config file:
           Lstat /herdr-projects-mcp/config: file does not exist
           Is there a repository at the following location?
           sftp:restic@aurora.saola-matrix.ts.net:/herdr-projects-mcp
pre-start: Fatal: create repository at sftp:…:/herdr-projects-mcp failed:
           MkdirAll /herdr-projects-mcp/index: permission denied
Control process exited, code=exited, status=1/FAILURE
```

`initialize = true` did exactly what it should: probe → not there → create.
The create is what was denied.

## Root cause

Not the job, and not aurora being unreachable — the SSH handshake and the
SFTP session both succeeded. The `onetouch` target's repository was the
**bare chroot root**:

```nix
# modules/infra/backup/restic.nix (before)
onetouch.repository = "sftp:restic@aurora.saola-matrix.ts.net:";
# → per-job repo "sftp:restic@aurora…:/<job>"  = /mnt/backup/<job> on aurora
```

OpenSSH requires `ChrootDirectory` and every parent to be owned by root and
not group/other-writable. `/mnt/backup` is the OneTouch's ext4 mount root, so
it inherits `root:root 0755` and satisfies that for free — which also means
the chrooted `restic` user has **no write permission at the chroot root**.

```
/mnt/backup            root:root 0755   ← chroot root; restic CANNOT mkdir here
├── <job>/             restic:restic    ← pre-existing, hand-chowned in the 2026-06 migration
└── pi/                restic:restic    ← ad-hoc namespace added after the 2026-06 lock collision
```

So every *existing* workstation repo worked (its directory was created by
root during the OneTouch's move to aurora and chowned by hand), and every
*new* job was structurally impossible — `restic init` cannot create its own
directory, forever, until a human runs `mkdir` + `chown` on aurora. The
onboarding comment in `restic-target/runtime.nix` documented chowning
pre-existing directories; nothing covered a job that never had one.

`herdr-projects-mcp` (added 2026-08-11 in `6d3a5df`) was simply the first new
job to hit it. Its `mp510` sibling unit, a local path, initialized fine —
which is why only the `-onetouch` half alerted.

## The fix

Give every pushing host a restic-owned namespace directory inside the chroot,
created declaratively by aurora, and scope each client's repository under it.
The `/pi` prefix already did this by hand for one host; this generalizes it to
the construct.

| File | Change |
|---|---|
| `modules/infra/backup/restic-target/runtime.nix` | `systemd.tmpfiles.rules` emits `d /mnt/backup/<host> 0700 restic restic -` for every `nori.hosts` entry except this host and `agent`-role hosts. Derived from the registry, so a new host's namespace exists the moment it is declared. |
| `modules/infra/backup/restic.nix` | `onetouch.repository` → `sftp:restic@aurora…:/${config.networking.hostName}` |
| `modules/profiles/entry-plane.nix` | same derivation replaces the hardcoded `/pi` (value unchanged for pi) |
| `docs/reference/{storage,services}.md`, `docs/runbooks/*` | repo paths → `/mnt/backup/workstation/<job>` |

Verified by evaluation:

```
aurora  systemd.tmpfiles.rules  → d /mnt/backup/pi 0700 restic restic -
                                  d /mnt/backup/workstation 0700 restic restic -
workstation  onetouch repo      → sftp:restic@aurora…:/workstation
             (10 jobs)          → …:/workstation/{user-data,media-irreplaceable,sonarr,…}
pi           onetouch repo      → sftp:restic@aurora…:/pi   (unchanged)
```

Aurora's namespace is absent (it writes locally, not over SFTP); pavilion's is
absent (`agent` role — a paths-based `nori.backups` is already a build error).

The second-order win: two hosts running the same job name can no longer race
on one repo, which is the failure the 2026-06 migration patched ad-hoc for
`caddy` + `authelia` (see `docs/reports/2026-06-aurora-migration.md`).

## Required one-time migration — run WITH this deploy

Workstation's ten existing repos still sit directly under the chroot root.
Move them into the namespace **on aurora**, before workstation's 03:00 timers
fire:

```bash
# on aurora
sudo find /mnt/backup -mindepth 1 -maxdepth 1 -type d \
  ! -name lost+found ! -name pi ! -name workstation \
  -exec mv -t /mnt/backup/workstation {} +
sudo chown -R restic:restic /mnt/backup/workstation
```

Same-filesystem rename, instant, history preserved. If this is skipped,
nothing is destroyed — but `initialize = true` will quietly create *empty*
repos under `/workstation/` and the real history is orphaned in place at
`/mnt/backup/<job>`. That silent-success window is the one real risk in this
change, and it closes as soon as the `mv` runs.

## What to watch

1. **The migration landed** — from workstation, after the deploy:
   `sudo systemctl start restic-backups-user-data-onetouch.service`, then
   check the repo shows the *full* snapshot history, not one fresh snapshot.
   One snapshot = the `mv` did not happen.
2. **The original unit** —
   `systemctl start restic-backups-herdr-projects-mcp-onetouch.service`
   should now init cleanly into `/workstation/herdr-projects-mcp`.
   (That job only exists on `fix/nix-daemon-memory-ceiling`; this branch is
   based on `origin/main`, which does not carry the workload yet.)
3. **`restic-check-weekly`** (Sun 05:00) — first run after the deploy walks
   every repo at its new path. Green there means every repo was found, not
   re-created.
4. **Nothing left behind** — on aurora, `ls /mnt/backup` should show only
   `pi`, `workstation`, `lost+found`.

## `nix flake check` is red on `origin/main` already — not from this change

This branch is based on `origin/main`, where two checks fail. Both were
reproduced on a **clean** tree (identical derivation hashes, identical
output), so the relay's draft marking on this PR is inherited, not caused:

| Check | Failure | Cause |
|---|---|---|
| `docs-fresh` | `docs/generated/backups.md` still carries a `qbittorrent` row the generator no longer emits | qBittorrent pause flipped `nori.backups.qbittorrent` to `skip`; the artifact was not regenerated (`nix build .#docs-backups`) |
| `every-service-has-fs-hardening` | `modules/services/arr/qbittorrent.nix`: no `nori.harden.<name>` declaration | same pause commit |

Deliberately untouched here. Both belong to the qBittorrent pause, not to
this incident, and the hardening one needs an intent decision for a paused
service that is the operator's to make. Fixing only the generated-doc half
would leave that story half-told.

Everything this change does touch evaluates clean — the two failures above
are the only ones in the full `nix flake check` run.

## Follow-up not taken here

The `herdr-projects-mcp` job itself is worth a second look on the branch that
owns it, independent of this failure:

- its `include` is `/home/nori/.local/state/herdr-mcp/projects`, already
  inside `/home` — which the `user-data` job backs up wholesale. The dedicated
  repo is duplicate coverage.
- the payload is a live `facade.sqlite`. A raw filesystem copy of an open
  SQLite database is a torn-page risk; the repo's own convention is Pattern C2
  (`sqlite3 .backup` via `prepareCommand`, as vaultwarden does), and the
  sibling `hindsight` module skipped backup for exactly this reason.

Both are declaration-quality issues in a module that does not exist on `main`,
so they are out of scope for this PR.
