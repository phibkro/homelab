---
date: 2026-07-18
summary: restic-check-weekly failed every run against the onetouch SFTP target — the check scripts dropped the target's extraOptions, so restic ssh'd to aurora with no identity file. Fix passes transport config into the check loop.
---

# `restic-check-weekly` failure — check scripts ignored target transport config

## What failed

`restic-check-weekly.service` on workstation, Sun 2026-07-12 05:00. Exit 1,
`OnFailure` → `notify@` fired.

Every `mp510` (local path) pair passed. Every `onetouch` (SFTP) pair failed
identically:

```
subprocess ssh: restic@aurora.saola-matrix.ts.net: Permission denied (publickey).
Fatal: unable to open repository at sftp:restic@aurora.saola-matrix.ts.net:/user-data
```

Not a one-off. Every weekly run since the OneTouch moved to aurora (2026-06-11)
failed the same way; `restic-check-monthly` carried the identical bug.

## Root cause

A backup target carries two things: **where** the repo is (`repository`) and
**how to reach it** (`extraOptions`, `environmentFile`). The generated backup
units get both — `modules/infra/backup/default.nix` does
`inherit (tgt) extraOptions environmentFile` when building
`services.restic.backups.<job>-<target>`.

The check scripts got only the first. `pairsShell` in
`modules/infra/backup/restic.nix` emitted `"<job> <target> <repoPath>"` lines
and the loop ran a bare `restic -r "$repo" check`.

```
backup unit   restic -o sftp.command='ssh -i /run/secrets/restic-ssh-key …' -r <repo> backup   ✓
check loop    restic                                              -r <repo> check           ✗
```

For `onetouch` those dropped options are load-bearing: the SSH identity
(`-i /run/secrets/restic-ssh-key`), `IdentitiesOnly`, `BatchMode`, and the
pinned `UserKnownHostsFile=/etc/ssh/aurora_known_hosts`. Without them restic
spawns plain `ssh restic@aurora`, root has no key aurora's chrooted `restic`
user accepts, and the SFTP session dies before the version packet.

Why the heredoc shape caused it: `while read job target repo` splits on
whitespace, so a quoted `sftp.command='ssh -o … -i …'` value could not be
carried through that channel at all. The data shape made the correct behaviour
unrepresentable.

**Backups themselves were never affected.** The daily
`restic-backups-<job>-onetouch` units use the correct transport. This was a
failure of *verification*, not of *backup* — but it meant the onetouch repos
have gone unchecked since the aurora migration.

## The fix

`modules/infra/backup/restic.nix` — replace the whitespace-delimited heredoc
with one generated `check_repo` call per (job, target), carrying the target's
transport alongside the repo path:

```
check_repo <job> <target> <repo> <envfile|-> [-o <opt>]...
```

`extraOptions` are `lib.escapeShellArg`-quoted per element, matching what
`default.nix:643` already does for the pre-unlock `ExecStartPre`. `check_repo`
`shift`s off the four fixed args and forwards `"$@"` to restic, so quoting
survives as single argv elements.

Also closes the sibling gap: `environmentFile` (for future S3/B2/Hetzner
targets needing ambient credentials) is sourced inside a subshell per pair, so
one target's credentials can't leak into the next target's invocation. It was
silently ignored before; no target uses it today.

Both cadences now share one `mkCheckScript` generator parameterised by check
flags — weekly `[ ]`, monthly `[ "--read-data-subset=10%" ]`. One construct,
one place for this class of bug to be fixed.

Failure semantics preserved: serial iteration, accumulate `fail=1` rather than
short-circuit, non-zero aggregate exit so `OnFailure` → ntfy still fires.

## Verification

Eval + real-journey run, not just a build:

1. `nix eval .#nixosConfigurations.workstation.config.systemd.services.restic-check-weekly.script`
   — 19 `check_repo` calls; every `onetouch` line carries the `-o sftp.command=…`
   flag; repo paths byte-match the ones in the failing journal
   (`sftp:restic@aurora.saola-matrix.ts.net:/user-data`).
2. Extracted that script, swapped the restic store path for a stub that logs
   argv and fails one repo, ran under `bash -e` (matching NixOS `makeJobScript`).
   Confirmed: the `sftp.command` value arrives as **one** argv element; a mid-loop
   failure does not abort the remaining pairs under `set -e`; aggregate exit is 1.
3. `nix fmt` clean, `nix flake check` green.

Not verified here: an actual SFTP handshake to aurora. This is a disposable
clone with no tailnet or `/run/secrets` — see below.

## What to watch

1. **Confirm the real handshake after deploy.** The publickey path is exactly
   the seam a stub can't test. On workstation:
   `just check-restic` (→ `systemctl start restic-check-weekly.service`), then
   watch for `[<job> @ onetouch]` pairs reaching `no errors were found` rather
   than `Permission denied (publickey)`.
2. **Expect a slow first run, and possibly real findings.** The onetouch repos
   have not been metadata-checked since 2026-06-11. If genuine corruption
   accumulated, this is the run that surfaces it — a `check` failure now is a
   *different* failure from the one fixed here. Read the error text, don't
   pattern-match on the red.
3. **Stale locks.** Five weeks of aborted `check` runs may have left exclusive
   locks on the onetouch repos. Backup units self-heal via the `mkBefore`
   `restic unlock` `ExecStartPre`; the **check units have no such pre-step**. If
   the first run reports a locked repo, `restic unlock` against that repo
   manually. Adding the same self-healing pre-step to the check units is a
   candidate follow-up, deliberately out of scope for this minimal fix.
4. **The structural gap remains.** Nothing prevents the next consumer of
   `nori.backupTargets` from reading `repository` while forgetting
   `extraOptions` — the same bug, one file over. `restore-drill-*` in
   `verify.nix` is currently safe only because it hardcodes the local
   `/mnt/backup-local` root and never touches a remote target; the moment a
   drill points at `onetouch` it reintroduces this. The correct-by-construction
   fix is a single helper that renders `(target, job) → full restic argv`, used
   by all three consumers, so `repository` is not reachable without its
   transport. Worth doing when a third consumer appears.
