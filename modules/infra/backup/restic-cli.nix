/**
  The restic CLI every unit in this concern invokes: plain restic plus a
  repository-lock retry window.

  restic serialises work on a repo with a lock — `backup` takes an append
  lock, `cat config` a read lock, `check` and `forget --prune` an
  EXCLUSIVE one (restic 0.19 `cmd_{check,forget}.go` → `openWithExclusiveLock`).
  Without `--retry-lock` a blocked acquisition fails on the spot, and
  nothing serialises the daily `restic-backups-<job>-<target>` timers
  against the weekly/monthly `restic-check-*` timers. Both timer families
  are `Persistent = true`, so on a host that sleeps (workstation) every
  missed run fires together on resume — the collision window is not rare,
  it is scheduled.

  Worse, the collision surfaces as a MISLEADING failure: upstream's
  `initialize = true` pre-start is `restic cat config || restic init`, so
  the lock error gets swallowed by `||` and the unit dies on
  `create repository … failed: config file already exists`. That is the
  2026-08-09 media-irreplaceable@onetouch incident verbatim.

  Wrapping the binary — rather than threading the flag through call sites
  — is what makes the gap unrepresentable. `extraOptions` renders only
  `-o key=value`, `extraBackupArgs` reaches `backup` alone, and the
  pre-start chain (where the incident actually landed) accepts no
  arguments at all. `package` is the single seam every invocation crosses.
*/
pkgs:

let
  /*
    Longer than the slowest single-repo operation this concern runs: the
    monthly `check --read-data-subset=10%` over ~320 GiB of
    media-irreplaceable pulled through aurora's SFTP chroot. A lock still
    held past this is a real fault, and failing then keeps
    OnFailure → ntfy honest rather than waiting forever.

    Locks left by DEAD processes are explicitly NOT this window's job:
    restic refreshes a live lock every 5 min, and the `restic unlock`
    steps (ExecStartPre in ./default.nix, per-pair in ./restic.nix) clear
    anything staler than 30 min. This window covers the other half —
    a lock held by a process that is genuinely still working.
  */
  retryLock = "1h";
in
pkgs.writeShellScriptBin "restic" ''
  exec ${pkgs.lib.getExe pkgs.restic} --retry-lock=${retryLock} "$@"
''
