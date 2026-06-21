---
generated: true
source: flake-parts/packages/docs-backups.nix
regenerate: nix build .#docs-backups
---

# `nori.backups` — generated reference

Two-section artifact: module overview (RFC 145 doc-comments
from the concern's `default.nix`) + per-option schema
(`nixosOptionsDoc` over the eval'd options tree). The
concern file's path is shown in the per-option "Declared by"
lines below.

Backup concern — schema + collection + adapter wiring.

This `default.nix` carries the `nori.backups` schema (Reader) and
the assertions (placement: appliance ≠ paths-backups; agent ≠
`nori.backups`). It also imports the adapter siblings (Writer):
`restic`, `btrbk`, `btrbk-replication`, `btrbk-replica-target`,
`verify`. Each adapter conditionally activates from declared
`nori.backups.<X>` entries + its own gates (e.g.
`btrbk-replica-target`'s `hostName == "workstation"` gate);
adapters are inert otherwise.

`restic-target.nix` is the one adapter NOT in the aggregator —
it's per-host opt-in via direct import on `aurora/default.nix`
(declares the SFTP-chrooted `restic` user that workstation pushes to).

# backups concern — overview {#sec-functions-library-backups}


## `homelab.backups.options.nori.backupTargets` {#function-library-homelab.backups.options.nori.backupTargets}

nori.backups + nori.backupTargets — declarative restic backup model.

Two-layer schema:

  nori.backupTargets.<target>  — WHERE backups go (the destination
                                 repo bases). Declared once at
                                 host scope.
  nori.backups.<job>           — WHAT to back up (paths, prepare
                                 commands, retention). Declared per
                                 service module alongside the
                                 service definition.

The generator fans out: each (job, target) pair becomes its own
`services.restic.backups.<job>-<target>` and corresponding
`restic-backups-<job>-<target>.service` systemd unit with its own
OnFailure → notify@ wiring. That's deliberate — independent units
mean independent failure modes. A wedged OneTouch USB controller
(2026-06-04 incident) doesn't take down the mp510-local backups,
and ntfy alerts disambiguate which target failed.

Service modules look like:

  nori.backups.sonarr = { include = [ "/var/lib/sonarr" ]; };

  nori.backups.vaultwarden = {
    include = [ "/var/lib/vaultwarden" "/var/backup/vaultwarden" ];
    prepareCommand = ''
      ${pkgs.sqlite}/bin/sqlite3 /var/lib/vaultwarden/db.sqlite3 \
        ".backup '/var/backup/vaultwarden/db.sqlite3'"
    '';
  };

By default every job writes to every declared target. Override
selectively via `targets = [ "onetouch" ];` per job.

Three pattern shapes from docs/reference/services.md § "Backup-correctness
patterns" fit this schema:
  * Pattern A (filesystem-only)   → include = [...];
  * Pattern B (built-in dump)     → include lists the dump dir
  * Pattern C2 (external dump)    → include + prepareCommand

DynamicUser services: point `include` at /var/lib/private/<n>,
not /var/lib/<n> (which is a symlink restic would store as a
symlink → 0-byte snapshot). Enforced by the `badPaths` assertion
below; see .claude/skills/gotcha-dynamicuser-statedirectory-symlink/




## Option schema

## nori.backups

Restic backup decisions per service / cross-cutting concern.

Each entry MUST set exactly one of:

 - ` include ` — list of paths to back up (Pattern A; add
   ` prepareCommand ` for Pattern C2)
 - ` skip ` — string explaining why this service has no backup
   (covered elsewhere, stateless, intentionally re-derivable)

The two-state schema forces every service module to make an
explicit decision rather than silently being uncovered. The
paired flake check (` every-service-has-backup-intent ` in
flake.nix) enforces that every modules/services/\*\*.nix
contains a nori.backups.<n> declaration.

Active backups (those with non-null ` include `) fan out across
all ` targets ` listed (default: every declared
nori.backupTargets entry). The generated systemd unit names
follow ` restic-backups-<jobName>-<targetName> `.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  sonarr = { include = [ "/var/lib/sonarr" ]; };
  vaultwarden = {
    include = [ "/var/lib/vaultwarden" "/var/backup/vaultwarden" ];
    prepareCommand = "sqlite3 ... .backup ...";
    timer = "*-*-* 04:30:00";
    # targets defaults to all declared nori.backupTargets; # multi-line: ok
    # override here to limit, e.g.:
    # targets = [ "onetouch" ];
  };
  gatus = { skip = "memory-only storage; no on-disk state."; };
}

```

*Declared by:*
 - `modules/infra/backup`



## nori.backups.<name>.exclude



Paths to exclude from the backup. Mirrors restic’s
` --exclude `. Use for ephemeral subdirs under a
service’s state path that re-fill from scratch (qBit
` incomplete/ `, browser caches, etc.) — pinning their
chunks in old snapshots costs real bytes on the backup
drive. Ignored when ` include ` is null.



*Type:*
list of string



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "/var/lib/qBittorrent/qBittorrent/incomplete"
]
```

*Declared by:*
 - `modules/infra/backup`



## nori.backups.<name>.include



Filesystem paths to back up. Passed through to
restic’s positional arguments (the restic NixOS
module’s ` paths ` option). For DynamicUser services,
point at /var/lib/private/<name> directly — the
/var/lib/<name> symlink would otherwise be stored as
just the symlink record (caught by the assertion
below). Set to ` null ` (default) for explicit opt-out;
pair with the ` skip ` field documenting the reason.



*Type:*
null or (list of string)



*Default:*

```nix
null
```

*Declared by:*
 - `modules/infra/backup`



## nori.backups.<name>.prepareCommand



Bash command(s) to run before each restic backup.
Used for Pattern C2 (sqlite3 .backup before restic).
Null = Pattern A (filesystem-only). Ignored when
` include ` is null. Same prepareCommand runs once per
target; the dump output it produces gets included in
every target’s snapshot.



*Type:*
null or strings concatenated with “\\n”



*Default:*

```nix
null
```

*Declared by:*
 - `modules/infra/backup`



## nori.backups.<name>.pruneOpts



Restic forget/prune options. Default derived from ` tier `. Ignored when ` include ` is null.



*Type:*
list of string



*Default:*

````nix
# derived from `tier`: # multi-line: ok
# service       → 7d / 4w / 12m
# user          → 14d / 4w / 12m
# irreplaceable → 14d / 8w / 12m / 5y

````

*Declared by:*
 - `modules/infra/backup`



## nori.backups.<name>.skip



When ` include ` is null, this records why backup is
intentionally skipped. Required for opt-out — the
schema can’t otherwise tell “intentionally skipped”
from “forgotten”.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - `modules/infra/backup`



## nori.backups.<name>.targets



Backup targets this job should fan out to. Default
(null) = every declared nori.backupTargets entry —
belt-and-suspenders coverage. Override with a subset
when a job should NOT write to a particular target
(e.g. a service whose data is too large for the
always-mounted target).



*Type:*
null or (list of string)



*Default:*

```nix
lib.attrNames config.nori.backupTargets
```

*Declared by:*
 - `modules/infra/backup`



## nori.backups.<name>.tier



Value tier per docs/reference/storage.md “Value tiers” — drives
the default ` pruneOpts ` retention curve (see
` pruneOpts ` defaultText below). Per-service repos
default to ` service `; cross-cutting ` user-data ` and
` media-irreplaceable ` repos override. Override
` pruneOpts ` directly to deviate.



*Type:*
one of “service”, “user”, “irreplaceable”



*Default:*

```nix
"service"
```

*Declared by:*
 - `modules/infra/backup`



## nori.backups.<name>.timer



` OnCalendar ` systemd timer expression. Default 03:00
UTC daily. All targets for a job share the same timer;
they fire concurrently. Stagger across jobs when
concurrent USB I/O on the OneTouch becomes a
bottleneck. Ignored when ` include ` is null.



*Type:*
string



*Default:*

```nix
"*-*-* 03:00:00"
```

*Declared by:*
 - `modules/infra/backup`


