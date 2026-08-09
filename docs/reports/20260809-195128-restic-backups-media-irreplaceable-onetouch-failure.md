---
date: 2026-08-09
summary: restic-backups-media-irreplaceable-onetouch died in pre-start because another restic held an exclusive lock on the repo; upstream's `cat config || init` chain turned the lock refusal into a bogus "config file already exists" fatal. Fix wraps restic with `--retry-lock=1h` at the one seam every invocation crosses.
---

# `restic-backups-media-irreplaceable-onetouch` failure — lock collision misreported as an uninitialised repo

## What failed

`restic-backups-media-irreplaceable-onetouch.service` on workstation,
2026-08-09 19:49. Exit 1 from the **control process** (pre-start), so
`ExecMainStatus=0` — the backup itself never ran. `OnFailure` → `notify@` +
`agent-fix@` fired.

```
19:49:22  Starting restic-backups-media-irreplaceable-onetouch.service...
19:49:27  pre-start[3382325]: unable to create lock in backend: repository is
                              already locked exclusively by PID 3374091 on
                              workstation by root (UID 0, GID 0)
19:49:27  pre-start[3382325]: lock was created at 2026-08-09 19:49:19 (8.4s ago)
19:49:28  pre-start[3382719]: Fatal: Fatal: create repository at
                              sftp:restic@aurora…:/media-irreplaceable failed:
                              config file already exists
19:49:28  Control process exited, code=exited, status=1/FAILURE
```

The 03:30 scheduled run the same morning finished clean in 22s. This is a
collision, not a broken repo or a broken transport.

## Root cause

Two independent gaps compose into one failure.

**1. Nothing serialises restic operations against a repo.** restic locks per
repository, and the lock classes are asymmetric (restic 0.19,
`cmd/restic/lock.go`):

| command | lock | blocked by exclusive |
|---|---|---|
| `backup` | append | yes |
| `cat config` | read | yes |
| `check` | **exclusive** | yes |
| `forget --prune` | **exclusive** | yes |

`restic-check-weekly` (`Sun 05:00`) and `restic-check-monthly` take the
exclusive lock; the daily `restic-backups-<job>-<target>` units need append and
read locks. Nothing orders them. Both timer families are `Persistent = true`
and workstation is the sleep-friendly host — every missed run fires **together**
on resume, so the collision window is scheduled, not rare. 2026-08-09 was a
Sunday; the exclusive holder appeared 3s before the backup unit started.

Without `--retry-lock` (restic default: *no retries*) a blocked acquisition
fails on the first attempt instead of queueing.

**2. `initialize = true` converts the lock refusal into a lie.** Upstream's
pre-start is one line (`nixos/modules/services/backup/restic.nix`):

```
${resticCmd} cat config > /dev/null || ${resticCmd} init
```

`||` cannot distinguish "repo is busy" from "repo does not exist". The lock
error is swallowed, `init` runs against a repo that has existed since
2026-06-11, and the unit dies on `config file already exists` — an error that
points at the wrong subsystem entirely.

The existing `restic unlock` `ExecStartPre` (`modules/infra/backup/default.nix`)
does not help and should not: it only clears locks older than 30 min, and this
lock was 8s old and being actively refreshed by a live process. It was built for
*dead* holders. This was a *live* one.

## The fix

`modules/infra/backup/restic-cli.nix` (new) — restic wrapped so every
invocation carries `--retry-lock=1h`:

```nix
pkgs.writeShellScriptBin "restic" ''
  exec ${pkgs.lib.getExe pkgs.restic} --retry-lock=1h "$@"
''
```

Used at all three call sites in the concern:

| file | site | was |
|---|---|---|
| `default.nix` | `services.restic.backups.<n>.package` | `pkgs.restic` (upstream default) |
| `default.nix` | pre-unlock `ExecStartPre` | `${pkgs.restic}/bin/restic` |
| `restic.nix` | `mkCheckScript` unlock + check | `${pkgs.restic}/bin/restic` |

**Why wrap the binary rather than pass a flag.** `--retry-lock` is a global
flag, and none of the per-job knobs reach the command that actually failed:
`extraOptions` renders only `-o key=value`, `extraBackupArgs` reaches `backup`
alone, `pruneOpts`/`checkOpts` reach their own subcommands — and the pre-start
chain accepts no arguments at all. `package` is the single seam every restic
invocation in this concern crosses, so wrapping it makes "an invocation that
forgets to retry" unrepresentable rather than a thing to remember. Same shape as
the 2026-07-18 finding that `repository` should not be reachable without its
transport.

Failure semantics are preserved, not softened: after 1h restic makes one final
attempt and fails, so `OnFailure` → ntfy still fires on a genuinely wedged repo.
`Type=oneshot` disables `TimeoutStartSec` by default, so the wait cannot be cut
short by systemd.

**Why 1h.** Longer than the slowest single-repo operation the concern runs —
monthly `check --read-data-subset=10%` over ~320 GiB of media-irreplaceable
through aurora's SFTP chroot. Dead holders remain the `restic unlock` steps'
job (restic refreshes a live lock every 5 min; anything staler than 30 min is
removed there), so the two mechanisms cover disjoint halves.

## Verification

Reproduced and fixed against real restic repos, not stubs.

1. **Reproduction.** Local repo, exclusive lock held by
   `restic --limit-download 2048 check --read-data`, then upstream's pre-start
   chain verbatim:

   ```
   unable to create lock in backend: repository is already locked exclusively by PID 463 …
   Fatal: Fatal: create repository at … failed: config file already exists
   preStart exit=1
   ```

   Byte-for-byte the journal, doubled `Fatal:` included.

2. **Fix, through the exact deployed artifact.** Built
   `.#nixosConfigurations.workstation.config.services.restic.backups.media-irreplaceable-onetouch.package`
   (`/nix/store/w5fjn2zm5aah8s06wd8gklhlr6bpz6g9-restic`) and ran the same chain
   against the same locked repo: waited 35s for the holder, `exit=0`.

3. **Eval.** The unit's `preStart`, all three `ExecStart` entries, and the
   `restic-check-weekly` script all resolve to the wrapper; the
   `-o sftp.command='ssh …'` value still renders as one shell-quoted argument
   (the 2026-07-18 quoting regression does not recur — the wrapper forwards
   `"$@"`).

4. `nix fmt` clean, `nix flake check` green.

**Not verified here:** a real SFTP handshake to aurora, or an actual
backup↔check collision on the live host. This is a disposable clone with no
tailnet and no `/run/secrets`.

## What to watch

1. **First post-deploy collision.** When a backup and a check overlap, the
   waiting unit now logs `repo already locked, waiting up to 1h0m0s for the
   lock` and then proceeds. Seeing that line is the fix working; seeing
   `config file already exists` again means the wrapper is not on the path
   somewhere.
2. **Long-running units are now expected.** A `restic-backups-*` unit sitting
   for tens of minutes is queueing, not hung. Confirm with
   `journalctl -u <unit>` before reaching for `restic unlock` — clearing a
   *live* lock is the harmful move here.
3. **Who held the lock at 19:49:19 is inferred, not proven.** The journal tail
   names only PID 3374091 (root, workstation). `restic check` is the only
   scheduled exclusive-lock holder for this repo and the timing fits a
   `Persistent = true` catch-up on resume, but a manual `just check-restic` or
   `just backup` would look identical. If collisions recur at odd hours, check
   `systemctl list-timers 'restic-*'` for catch-up bunching.
4. **The thundering-herd cause is untouched.** `--retry-lock` makes the
   collision harmless; it does not stop the burst. `restic-check-{weekly,monthly}`
   have no `RandomizedDelaySec`, unlike the `restore-drill-*` timers, which carry
   `RandomizedDelaySec = "6h"` + `FixedRandomDelay` explicitly to "avoid a
   thundering start at calendar/boot/deployment boundaries". Adding the same to
   the check timers is the follow-up; deliberately out of scope for this fix.
5. **`initialize = true` still lies about any pre-start failure.** Retrying the
   lock removes the one trigger seen here, but any other transient
   repo-unreachability (aurora down, tailnet flap) will still surface as
   `config file already exists` rather than the real cause. The correct-by-
   construction fix is `initialize = false` plus explicit first-run repo
   creation; it trades away zero-touch bootstrap for a new (job, target) pair,
   so it is a separate decision.
