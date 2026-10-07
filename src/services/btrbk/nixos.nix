{
  config,
  lib,
  pkgs,
  ...
}:

let
  /*
    Classify nori.fs paths by their physical btrfs namespace. Family
    paths must never fall through to the root namespace: their source
    filesystem is the Toshiba vault mounted at /mnt/family.
  */
  inherit (config.nori) fs;

  onMedia = _: f: lib.hasPrefix "/mnt/media/" f.path;
  onFamily = _: f: lib.hasPrefix "/mnt/family/" f.path;
  onRoot = n: f: !(onMedia n f) && !(onFamily n f);
  # @downloads is re-derivable; intentionally excluded from snapshots.
  isSnapshotted = _: f: f.tier != "re-derivable";

  rootSubvols = lib.mapAttrs' (_: f: lib.nameValuePair (lib.removePrefix "/" f.path) { }) (
    lib.filterAttrs (n: f: onRoot n f && isSnapshotted n f) fs
  );

  mediaSubvols = lib.mapAttrs' (_: f: lib.nameValuePair (lib.removePrefix "/mnt/media/" f.path) { }) (
    lib.filterAttrs (n: f: onMedia n f && isSnapshotted n f) fs
  );

  familySubvols = lib.mapAttrs' (
    _: f: lib.nameValuePair (lib.removePrefix "/mnt/family/" f.path) { }
  ) (lib.filterAttrs (n: f: onFamily n f && f.tier == "irreplaceable") fs);

  /*
    Root snapshots also leave the system NVMe: the IronWolf's @snapshots
    subvolume (mounted beside the media snapshots) receives them with
    btrbk send/receive. The target is a directory, not a nori.fs entry,
    because nori.fs tiers select what the snapshot and restic generators
    protect; this directory is their output. Mode 0700 keeps received
    /home and /var/lib copies out of the Samba `media` share and
    Jellyfin's read-only /mnt/media view.
  */
  rootRetention = config.nori.inventory.backup.retention.workstationRoot;
  ironwolf = config.nori.inventory.disks."ironwolf-pro";
  ironwolfSnapshots = "${ironwolf.mountPoint}/.snapshots";
  rootTarget = "${ironwolfSnapshots}/workstation-root";

  /*
    ── pressure guard ──────────────────────────────────────────────

    One measurement and classification construct for alarms,
    maintenance, and snapshot guards is `nori-storage-pressure`
    (config.nori.storagePressure.package; imported by the common
    storage concern, so this module never depends on the disk-alert
    module being selected). Contract, as implemented by that package:

      nori-storage-pressure check <path>
        0   healthy or warning — snapshot may proceed
        75  critical allocation pressure
        1   measurement error; never healthy
        prints the measurement as JSON (fs_type, fs_uuid, state, …)
      nori-storage-pressure with-lock <path> <command...>
        non-blocking exclusive lock for the filesystem owning <path>,
        held for the duration of <command>; 75 when already held.

    The guard replaces the instance's plain `btrbk … run` ExecStart and
    is given every path the instance actually touches: each snapshotted
    subvolume source, the snapshot directory, and every receive target.
    A btrbk instance routinely spans two physical filesystems — the
    workstation root instance reads /home, /srv/share, /var/lib and
    /.snapshots on the system NVMe while it receives into
    /mnt/media/.snapshots/workstation-root on the IronWolf; the media
    instance's subvolumes are IronWolf subvolumes even though
    /mnt/media itself is a directory on the root filesystem — so the
    filesystem is never inferred from a volume key or a parent
    directory.

    Behaviour:

      * every touched path is resolved to the filesystem that contains it
        (the kernel mount table; a receive target is a plain directory
        inside its destination mount) and measured through `check`; the
        filesystem identity (`fs_uuid`) comes from that same measurement,
        and paths or mountpoints sharing one physical filesystem collapse
        to one lock,
      * a measurement error, an unknown status, a non-btrfs filesystem, a
        missing filesystem identity, an unresolvable path, or missing
        tooling fails the unit instead of silently skipping a snapshot
        (no ExecCondition, no success reported for a skipped snapshot),
      * every distinct filesystem is locked for the whole operation, in
        a deterministic (sorted identity) order, by re-entering this
        script through `with-lock` once per filesystem; a lock held by
        the allocation-maintenance worker propagates as 75, so
        maintenance and snapshots never race on any of them,
      * under critical pressure on any touched filesystem, only the
        cleanup the instance's own configuration already permits runs —
        `btrbk -c /etc/btrbk/<name>.conf prune`, under the same locks —
        and nothing more aggressive is applied,
      * the snapshot is taken only after re-checking every filesystem
        inside those locks, so the gate cannot straddle a maintenance
        window and the post-prune state is what decides,
      * exit status is preserved: btrbk's own status (or 75 when a lock
        is busy, or the failing measurement's status) reaches systemd,
        so the existing OnFailure → notify@ wiring reports a refused
        snapshot as a failure.
  */
  pressureGuard = pkgs.writeShellApplication {
    name = "btrbk-pressure-guard";
    /*
      coreutils/jq are pinned here; `nori-storage-pressure` and `btrbk`
      come from the unit's systemd `path`, so the same script can be
      exercised against a disposable fixture (a Nix build sandbox cannot
      run the real probe: no host /run/lock and no host btrfs to
      measure). inheritPath keeps the unit-provided PATH visible.
    */
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.util-linux
    ];
    inheritPath = true;
    text = ''
      usage='usage: btrbk-pressure-guard <config> <run|snapshot> <path>...'

      die() {
        code=$1
        shift
        printf 'btrbk-pressure-guard: %s\n' "$*" >&2
        exit "$code"
      }

      # Resolve our own path so the lock-holding re-entry can re-exec us
      # even when we were invoked through PATH.
      self=$0
      if [ "''${self#/}" = "$self" ]; then
        self=$(command -v -- "$self") || die 1 "cannot resolve my own path: $0"
      fi

      # ── lock-holding re-entry ───────────────────────────────────────
      # `with-lock` holds one filesystem lock across its command, so
      # holding several distinct filesystems is this script calling
      # itself through `with-lock` once per level, in the order the top
      # level fixed. Acquisition is non-blocking: a lock another owner
      # holds propagates as 75.
      if [ "''${1-}" = --hold ]; then
        shift
        index=''${1-}
        action=''${2-}
        conf=''${3-}
        command=''${4-}
        shift 4
        reps=("$@")
        if [ -z "$index" ] || [ -z "$action" ] || [ -z "$conf" ] || [ "''${#reps[@]}" -eq 0 ]; then
          die 1 "$usage"
        fi
        if [ "$index" -lt "''${#reps[@]}" ]; then
          exec nori-storage-pressure with-lock "''${reps[$index]}" "$self" \
            --hold "$((index + 1))" "$action" "$conf" "$command" "''${reps[@]}"
        fi
        if [ "$action" = prune ]; then
          exec btrbk -c "$conf" prune
        fi
        # Re-check every filesystem while all locks are held: the gate
        # and the snapshot cannot straddle a maintenance window, and a
        # state that is still critical after the prune refuses the
        # snapshot.
        for rep in "''${reps[@]}"; do
          status=0
          nori-storage-pressure check "$rep" > /dev/null || status=$?
          case "$status" in
            0) ;;
            75) die 75 "critical allocation pressure on $rep inside the filesystem lock: refusing a new snapshot" ;;
            *) die "$status" "storage pressure check failed (exit $status) on $rep inside the filesystem lock" ;;
          esac
        done
        exec btrbk -c "$conf" "$command"
      fi

      # ── top level ───────────────────────────────────────────────────
      if [ "$#" -lt 3 ]; then
        die 1 "$usage"
      fi
      conf=$1
      command=$2
      shift 2
      paths=("$@")

      for tool in nori-storage-pressure btrbk jq findmnt; do
        command -v "$tool" > /dev/null 2>&1 || die 1 "$tool is not on PATH"
      done

      # The filesystem a path lives on is the mount containing it: a btrbk
      # receive target is a plain directory inside its destination mount,
      # and a directory that does not exist yet belongs to the filesystem
      # where it would be created. Resolution reads the kernel mount table
      # (findmnt); the filesystem identity and the classification come from
      # nori-storage-pressure, so nothing here re-measures a filesystem.
      resolve_mount() {
        probe=$1
        while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
          probe=$(dirname -- "$probe")
        done
        findmnt --noheadings --output TARGET --target "$probe"
      }

      declare -A representative=()
      declare -A seen=()
      critical=0
      for path in "''${paths[@]}"; do
        mount=$(resolve_mount "$path") || die 1 "cannot resolve the filesystem containing $path"
        if [ -z "$mount" ]; then
          die 1 "cannot resolve the filesystem containing $path"
        fi
        measurement=
        status=0
        measurement=$(nori-storage-pressure check "$mount") || status=$?
        case "$status" in
          0|75) ;;
          *) die "$status" "storage pressure check failed (exit $status) on $mount (for $path)" ;;
        esac
        fs_type=$(printf '%s' "$measurement" | jq -r '.fs_type // empty') \
          || die 1 "cannot read the measurement for $mount"
        fs_uuid=$(printf '%s' "$measurement" | jq -r '.fs_uuid // empty') \
          || die 1 "cannot read the measurement for $mount"
        # btrbk snapshots btrfs subvolumes; anything else is a
        # configuration error the guard must not paper over.
        if [ "$fs_type" != btrfs ]; then
          die 1 "btrbk needs btrfs; $mount (for $path) is ''${fs_type:-unknown}"
        fi
        # The lock key is the filesystem identity, so several mountpoints or
        # paths of one physical filesystem take one lock, not several.
        if [ -z "$fs_uuid" ]; then
          die 1 "no filesystem uuid reported for $mount; refusing to snapshot without a lockable identity"
        fi
        if [ -z "''${seen[$fs_uuid]:-}" ]; then
          seen[$fs_uuid]=1
          representative[$fs_uuid]=$mount
        fi
        if [ "$status" -eq 75 ]; then
          critical=1
        fi
      done

      keys=()
      while IFS= read -r key; do
        keys+=("$key")
      done < <(printf '%s\n' "''${!seen[@]}" | sort)
      reps=()
      for key in "''${keys[@]}"; do
        reps+=("''${representative[$key]}")
      done

      if [ "$critical" -eq 1 ]; then
        if [ "$command" != run ]; then
          die 75 "critical allocation pressure: refusing $command on a snapshot-only instance"
        fi
        # Retention-only cleanup scoped to this instance's own config:
        # `prune` deletes only what the declared retention already
        # allows and creates nothing new.
        printf 'critical allocation pressure: pruning per the instance retention policy before any new snapshot\n' >&2
        prune_status=0
        "$self" --hold 0 prune "$conf" "$command" "''${reps[@]}" || prune_status=$?
        if [ "$prune_status" -ne 0 ]; then
          die "$prune_status" "btrbk retention-only prune failed (exit $prune_status)"
        fi
      fi

      exec "$self" --hold 0 run "$conf" "$command" "''${reps[@]}"
    '';
  };

  /*
    Every path an instance actually touches, derived from its own
    configuration: the snapshotted subvolume sources, the snapshot
    directory each of them writes to, and every receive target. These
    drive both the guard's measurements/locks and the unit's
    RequiresMountsFor, so the unit waits for the real source and target
    mounts instead of a parent directory that may sit on a different
    filesystem.
  */
  instancePaths =
    name:
    let
      settings = config.services.btrbk.instances.${name}.settings;
      join =
        base: rel:
        if lib.hasPrefix "/" rel then
          rel
        else if base == "/" then
          "/${rel}"
        else
          "${base}/${rel}";
      snapshotDirOf =
        cfg:
        cfg.snapshot_dir or settings.snapshot_dir
          or (throw "btrbk instance `${name}` declares no snapshot_dir; the pressure guard cannot locate the snapshot filesystem.");
      forVolume =
        volume: vcfg:
        let
          subvolumes = vcfg.subvolume or { };
        in
        map (sub: join volume sub) (lib.attrNames subvolumes)
        ++ [ (join volume (snapshotDirOf vcfg)) ]
        ++ map (sub: join volume (snapshotDirOf subvolumes.${sub})) (lib.attrNames subvolumes)
        ++ lib.attrNames (vcfg.target or { })
        ++ lib.concatMap (subcfg: lib.attrNames (subcfg.target or { })) (lib.attrValues subvolumes);
    in
    lib.unique (lib.concatLists (lib.mapAttrsToList forVolume settings.volume));
in
/*
  Selected only by the Workstation `backup-source` system profile. btrbk
  snapshots the workstation's root, optional non-re-derivable media
  subvolumes, and the family vault; the activation script also enables
  the btrfs quota on /mnt/media/downloads and keeps it off the root
  filesystem.
*/
{
  /**
    btrbk — same-disk rollback snapshots, not independent backups.
    These provide the "single file
    deletion" recovery path per RECOVERY.md RTO targets (target: <15 min
    to restore an accidentally-deleted file).

    Instances are split by physical btrfs namespace:
      root (SN750):       /home, /srv/share, /srv/nori, /var/lib → /.snapshots
                          sent to /mnt/media/.snapshots/workstation-root
      media (IronWolf):   non-re-derivable /mnt/media/* → /mnt/media/.snapshots
      family (Toshiba):   irreplaceable /mnt/family/* → /mnt/family/.snapshots

    The media instance is declared only when nori.fs has a non-re-derivable
    media entry. The family filter is explicit so family paths can never
    become root subvolume names.

    @var/lib is added explicitly because it is a NixOS-managed StateDirectory,
    not a structural FS location. Intentionally excluded:
      @       (system root — covered by NixOS generations)
      @nix    (re-derivable from the flake)
      @downloads (re-derivable — filtered out)

    Root keeps one week on the system NVMe, where retained history
    competes with live data. The IronWolf receives every run as a
    read-only snapshot: off the system disk, still inside the workstation,
    so restic to the OneTouch remains the independent backup. The target
    starts with the latest snapshot only and moves to weekly/monthly
    history in a dated second phase; both values and the switch rule live
    in `retention.workstationRoot` in `src/inventory/backup.nix`.

    Family keeps its existing window. Cold media has a shorter window: it
    is mostly append-only archives, and local snapshots are an
    accidental-deletion tool rather than an independent backup. Keeping
    years of deleted media on the already-near-capacity IronWolf defeats
    that distinction.
  */
  services.btrbk = {
    instances = {
      root = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = rootRetention.localSnapshotPreserve;
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          volume."/" = {
            /*
              `latest` sends every daily snapshot, so the IronWolf copy is
              at most one run old. `target_preserve` selects which older
              received snapshots stay there ("no" in phase 1).
            */
            target.${rootTarget} = {
              target_preserve_min = "latest";
              target_preserve = rootRetention.ironwolfTargetPreserve;
            };
            /*
              rootSubvols has `home` + `srv/share` from nori.fs (user
              tier). var/lib is a btrfs subvolume but not in nori.fs
              (StateDirectory paths are NixOS-managed, not a structural
              FS location services consume) — added explicitly.
            */
            subvolume = rootSubvols // {
              "var/lib" = { };
            };
          };
        };
      };
    }
    // lib.optionalAttrs (familySubvols != { }) {
      family = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = "14d 8w 12m";
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          volume."/mnt/family".subvolume = familySubvols;
        };
      };
    }
    // lib.optionalAttrs (mediaSubvols != { }) {
      media = {
        onCalendar = "daily";
        settings = {
          snapshot_preserve_min = "2d";
          snapshot_preserve = config.nori.inventory.backup.retention.coldMedia.localSnapshotPreserve;
          snapshot_dir = ".snapshots";
          timestamp_format = "long";
          volume."/mnt/media".subvolume = mediaSubvols;
        };
      };
    };
  };

  /*
    /mnt/media is a directory on the root filesystem, which is btrfs as
    well: without the IronWolf mount btrbk would receive the history onto
    the NVMe it is meant to relieve. RequiresMountsFor mounts the
    IronWolf snapshot subvolume first, or fails the unit.
  */
  assertions = [
    {
      assertion =
        ironwolf.attachedHost == config.networking.hostName
        && (config.fileSystems.${ironwolfSnapshots}.fsType or null) == "btrfs";
      message = "btrbk root target ${rootTarget} needs the attached IronWolf btrfs mounted at ${ironwolfSnapshots}.";
    }
  ];
  systemd.tmpfiles.rules = [ "d ${rootTarget} 0700 root root - -" ];

  /*
    Alert via ntfy template in src/services/ntfy/nixos/notify.nix, and wrap
    each instance's ExecStart in the pressure guard (see the snapshot-policy
    doccomment in the `let` block above).

    RequiresMountsFor lists the real source and target paths the instance
    touches, so systemd pulls in every filesystem the run reads or receives
    into; a parent directory can sit on a different filesystem (the media
    instance's subvolumes are IronWolf subvolumes even though /mnt/media is
    on the root filesystem).

    `nori-storage-pressure` and `btrbk` reach the guard through the unit's
    PATH, which concatenates with the upstream module's entries, so
    `/run/wrappers` (the sudo backend btrbk shells out through) and any
    stream_compress helpers stay in place. mkForce is required on ExecStart:
    a plain definition would concatenate with upstream's ExecStart string
    into multiple ExecStart lines instead of replacing it.
  */
  systemd.services = lib.mkIf (config.services.btrbk.instances != { }) (
    lib.mapAttrs' (
      name: _:
      lib.nameValuePair "btrbk-${name}" {
        unitConfig = {
          OnFailure = [ "notify@btrbk-${name}.service" ];
          RequiresMountsFor = instancePaths name;
        };
        path = [
          config.nori.storagePressure.package
          pkgs.btrbk
        ];
        serviceConfig.ExecStart = lib.mkForce (
          lib.escapeShellArgs (
            [
              "${pressureGuard}/bin/btrbk-pressure-guard"
              "/etc/btrbk/${name}.conf"
              (if config.services.btrbk.instances.${name}.snapshotOnly then "snapshot" else "run")
            ]
            ++ instancePaths name
          )
        );
      }
    ) config.services.btrbk.instances
  );

  /*
    ── btrfs qgroup quota on @downloads ────────────────────────────
    Cap @downloads at 2540 GiB on the IronWolf (3726 GiB btrfs) to
    prevent the 100%-full metadata-exhaustion wedge pattern (see
    docs/runbooks/storage-full.md). At 100% btrfs can't even reclaim
    via subvolume delete because metadata writes need reserve — that's
    the actual recovery-hostile failure mode, not "disk full" itself.

    With the cap: qBit-as-writer hits ENOSPC on the @downloads quota
    well before the filesystem hits the metadata wall. Recovery path
    stays open (delete from @downloads to free; quota doesn't apply
    to the system pool's metadata budget).

    Headroom math (2026-09-26): 3053 GiB used, @downloads 2406 GiB
    referenced. The first btrbk-root send adds about 350 GiB (326 GiB
    data plus metadata), leaving about 998 GiB of non-download data.
    Disk-alert fires at 95% (3540 GiB), so a full @downloads may use
    3540 - 998 ≈ 2540 GiB: about 134 GiB above today's downloads. The
    previous 3300G cap no longer fit: it allowed ~890 GiB more
    downloads with only 670 GiB free.

    Tune via the 2540G literal below. Shrink it when other IronWolf
    data grows: the phase-2 root history (`retention.workstationRoot`)
    adds an estimated 110-160 GiB over six months.

    btrfs qgroup overhead: ~5% on metadata-heavy ops (modifying CoW
    ref counts on every write). Acceptable cost for the wedge guard
    on a non-CPU-bound media drive.

    Activation runs on every nixos-rebuild switch. `quota enable` is
    idempotent (no-op if already on). `qgroup limit` overwrites the
    existing limit cleanly. First-time enable triggers a rescan that
    may run for an hour on the multi-TiB filesystem; the limit takes
    effect after rescan completes.

    IMPORTANT — target path: /mnt/media itself is NOT a mountpoint
    (the downloads subvolume mounts directly under it). Targeting
    /mnt/media resolves to the root filesystem (SN750) and enables
    quotas there — wrong FS, expensive. Use /mnt/media/downloads, the
    real IronWolf mountpoint and the subvolume being capped. The family
    namespace is separate at /mnt/family and is not part of this quota.

    Quotas on the root filesystem are never wanted: none of its qgroups
    carry a limit, and qgroup accounting turns every btrbk retention
    delete into minutes of btrfs-cleaner work whose commits stall any
    writer on /, /home and /srv/share (2026-09-27: 36 snapshot deletes
    left commits taking up to 55 s for over half an hour). An earlier
    version of this script left them enabled there, so activation now
    turns them off on the root filesystem and refuses to enable them
    unless the downloads mount is a different filesystem.
  */
  system.activationScripts.btrfs-quota-media.text = ''
    root_uuid=$(${pkgs.util-linux}/bin/findmnt -no UUID /)
    if [ -n "$root_uuid" ] && [ -d "/sys/fs/btrfs/$root_uuid/qgroups" ]; then
      echo "Disabling btrfs quotas on the root filesystem"
      ${pkgs.btrfs-progs}/bin/btrfs quota disable / \
        || echo "WARNING: failed to disable btrfs quotas on the root filesystem"
    fi
    if ${pkgs.util-linux}/bin/mountpoint -q /mnt/media/downloads; then
      downloads_uuid=$(${pkgs.util-linux}/bin/findmnt -no UUID /mnt/media/downloads)
      if [ "$downloads_uuid" = "$root_uuid" ]; then
        echo "WARNING: /mnt/media/downloads is on the root filesystem; skipping IronWolf quota setup"
      else
        ${pkgs.btrfs-progs}/bin/btrfs quota enable /mnt/media/downloads >/dev/null 2>&1 || true
        downloads_id=$(${pkgs.btrfs-progs}/bin/btrfs subvolume list /mnt/media/downloads \
          | ${pkgs.gawk}/bin/awk '$NF == "@downloads" { print $2 }')
        if [ -n "$downloads_id" ]; then
          ${pkgs.btrfs-progs}/bin/btrfs qgroup limit 2540G "0/$downloads_id" /mnt/media/downloads \
            || echo "WARNING: failed to set @downloads quota (rescan in progress?)"
        fi
      fi
    else
      echo "WARNING: /mnt/media/downloads is not mounted; skipping IronWolf quota setup"
    fi
  '';

  /**
    Every snapshot operation takes the per-filesystem allocation lock, so the
    guard and the maintenance worker must be able to open the same lock file.
    The pressure module emits the lock directory as
    `/run/lock/nori-storage-pressure 0770 root <lockGroup>` with per-UUID lock
    files 0660 root:<lockGroup>; the owning group is the btrbk group, and root
    (the maintenance worker) can always open it.
  */
  nori.storagePressure.lockGroup = lib.mkIf (config.services.btrbk.instances != { }) "btrbk";
  users.users.btrbk.extraGroups = lib.mkIf (config.services.btrbk.instances != { }) [
    config.nori.storagePressure.lockGroup
  ];
}
