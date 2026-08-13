# restic-backups-herdr-projects-mcp-onetouch — nightly failure

**Window:** 2026-08-11 03:00 → 2026-08-13 03:00 (3 runs, all failed)
**Host:** workstation · **Unit:** `restic-backups-herdr-projects-mcp-onetouch.service`
**Blast radius:** none. No data was lost or left unprotected — see § Root cause.

## What failed

`ExecStartPre` (the `initialize = true` bootstrap) died before any snapshot ran:

```
Fatal: repository does not exist: unable to open config file:
  Lstat /herdr-projects-mcp/config: file does not exist
Is there a repository at the following location?
  sftp:restic@aurora.saola-matrix.ts.net:/herdr-projects-mcp
Fatal: create repository at sftp:… failed: MkdirAll /herdr-projects-mcp/index: permission denied
```

`Result=exit-code` with `ExecMainStatus=0` because the control process, not
`ExecStart`, is what exited 1. Each run tripped `OnFailure=` → ntfy.

## Root cause

Two independent defects stacked; either alone is enough to call the unit wrong.

**1 — The repo path is not creatable, by construction.**

```
nori.backupTargets.onetouch.repository = "sftp:restic@aurora…:"   ← chroot ROOT
generated repo                          = "<repository>/<jobName>"
                                        = "sftp:restic@aurora…:/herdr-projects-mcp"
```

`/` inside that SFTP session is aurora's `/mnt/backup`, which is sshd's
`ChrootDirectory` for the `restic` user
(`modules/infra/backup/restic-target/runtime.nix`). sshd refuses a chroot root
that is group/other-writable or not root-owned, so `/mnt/backup` is `root:root
0755` — and the `restic` user therefore cannot create a directory in it.
`initialize = true` can never bootstrap a *new* job on this target; every
existing per-job dir on the drive was created by hand during the 2026-06-11
OneTouch onboarding. The module docstring claimed the opposite ("restic creates
them via `initialize = true` on first push"), which is how the job shipped
without the operator step.

pi does not have this problem: `modules/profiles/entry-plane.nix` scopes its
repository under `…:/pi`, a restic-owned subdirectory, so `MkdirAll` lands one
level below the chroot root.

**2 — The job was redundant.** `nori.backups.herdr-projects-mcp.include` pointed
at `/home/nori/.local/state/herdr-mcp/projects`. `nori.backups.user-data.include`
evaluates to `[ /home /srv/nori /srv/share ]` and excludes nothing under
`.local/state`, so that path was already being shipped to **both** targets on the
same 03:00 timer, at *longer* retention (user tier 14d/4w/12m vs the job's
default service tier 7d/4w/12m). The facade journal has been backed up
continuously throughout the incident; only the duplicate repo was missing.

Landed 2026-08-11 in `6d3a5df refactor(agents): unify provider-neutral harness
configuration`. First failure was that night — the defect was live from the
first timer tick, never a regression from working state.

## The fix

| File | Change |
|---|---|
| `modules/services/herdr-projects-mcp/runtime.nix` | `nori.backups.herdr-projects-mcp` → `skip`, naming user-data as the covering repo. Removes both generated units (`-onetouch`, `-mp510`) and their `restic check` pairs. |
| `modules/infra/backup/restic-target/runtime.nix` | Replace the false "restic creates per-job dirs" claim with the actual operator step (`install -d -o restic -g restic /mnt/backup/<job>`) and why it exists. |
| `docs/roadmap.md` | New architectural-debt entry for the class fix. |
| `docs/generated/backups.md` | Regenerated (`nix build .#docs-backups`) — the job table is derived from `nori.backups`, so it moves with the change. Also drops a stale `qbittorrent` row left behind when that service was paused. |
| `modules/services/mcp-origin-tunnel/runtime.nix` | Out of scope, but blocking: the module shipped in `6d3a5df` with no backup intent at all, so `nix flake check` § `every-service-has-backup-intent` was already failing on main. Added the missing `skip` (stateless — ingress table from Nix, credentials from sops). |

Deleting the job — rather than provisioning `/mnt/backup/herdr-projects-mcp` on
aurora — is the correct call here: a second repo of bytes user-data already
carries buys no recoverability and adds a repo to every weekly/monthly `restic
check` sweep. Sibling service `hindsight`, from the same commit, already uses
`skip` for the same shape of reasoning.

**Verified:** `nix eval …workstation.config.services.restic.backups` now lists no
`herdr-*` repo (it listed `herdr-projects-mcp-onetouch` →
`sftp:restic@aurora…:/herdr-projects-mcp` and `herdr-projects-mcp-mp510` before
the change), and `/home` is confirmed present in `user-data.include`. Not
verified: the aurora SFTP handshake itself — this ran in a disposable clone with
no deploy.

## `nix flake check` is red for an unrelated, pre-existing reason

Verified against **unmodified** `origin/main` (`e0c4fb4`), i.e. this predates and
is independent of the change above:

```
every-service-has-backup-intent  ✗ modules/services/mcp-origin-tunnel        ← fixed here
docs-fresh                       ✗ docs-backups: stale qbittorrent row       ← fixed here
                                   (+ a missing herdr-projects-mcp row that
                                    this change removes at the source)
every-service-has-fs-hardening   ✗ modules/services/arr/qbittorrent.nix      ← NOT fixed
                                 ✗ modules/services/herdr-projects-mcp       ← NOT fixed
                                 ✗ modules/services/hindsight                ← NOT fixed
                                 ✗ modules/services/mcp-origin-tunnel        ← NOT fixed
```

The three MCP modules landed in `6d3a5df` without `nori.harden.<name>`;
qbittorrent's gap is older. Left alone deliberately: unlike `nori.backups.<n>.skip`
(a string, zero runtime effect), `nori.harden` has **no intent-only escape
hatch** — every declaration emits real sandboxing, and the default-deny baseline
is `ProtectHome=true` + `TemporaryFileSystem=[/mnt:ro,/srv:ro]`. For
`herdr-projects-mcp` that baseline collides head-on with both its
`WorkingDirectory=/srv/share/projects/herdr-mcp` and its writable state under
`/home/nori/.local/state` — guessing at `binds` here, from a disposable clone
with no way to start the units, trades a red check for a broken service. That
gap needs its own change with runtime verification.

## Class fix (not done here)

The structural cure is to stop pointing Workstation's repository at the chroot
root: move it to a restic-owned prefix (`…:/workstation`) declared by a tmpfiles
rule on aurora, mirroring pi's `/pi`. Then a new `nori.backups.<job>`
self-provisions and the hand-kept "declare the job, then chown a directory" pair
disappears. Cost is a one-time `mv /mnt/backup/<job> /mnt/backup/workstation/`
for every existing repo — **skipping the move silently re-initializes every repo
empty and loses all history**, which is why it is not bundled into an
unattended fix. Tracked in `docs/roadmap.md` § Architectural debt.

No flake check can catch this: aurora's directory layout is not visible from
workstation's eval. The guard is the corrected docstring plus the roadmap entry.

## What to watch

- **Next 03:00 run after deploy.** `restic-backups-herdr-projects-mcp-*` should
  not exist at all. `systemctl list-units 'restic-backups-*'` — a leftover unit
  means the rebuild did not land.
- **Stale artifacts.** The `-mp510` pair wrote to a local root-owned path and so
  presumably initialized fine (not verified — no host access from this clone).
  If `/mnt/backup-local/herdr-projects-mcp` exists it is now orphaned: harmless,
  but a repo no timer writes to and no `restic check` visits. Delete it once the
  change is deployed.
- **Sunday 05:00 `restic-check-weekly`.** It iterates `(job, target)` pairs from
  `nori.backups`; the herdr pairs drop out. A failure there would mean an
  unrelated repo.
- **The next new `nori.backups.<job>`.** If it targets `onetouch`, it fails the
  same way at its first timer tick unless the aurora directory is created first.
  This is the trigger to do the class fix instead.
- **Live-SQLite caveat.** `facade.sqlite` is copied hot by user-data, with no
  `.backup`/WAL checkpoint. Fine for a journal that is re-derivable from Herdr
  session state; if it ever becomes load-bearing, it needs Pattern B
  `prepareCommands`, not a second repo.
