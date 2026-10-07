{
  config,
  lib,
  pkgs,
  ...
}:
let
  /*
    Runtime half of the disposable-cache separation (2026-10-07
    storage-pressure spec, § "Disposable caches").

    The classification is the nori.fs registry: a tier "re-derivable"
    entry nested under the user-tier home path (declared in disko.nix,
    beside the nested @home subvolume boundaries it maps to). The same
    derivation feeds the restic exclusions in
    src/services/restic-backup/nixos.nix, so one registry tier decides
    what is disposable for snapshots, backups and migration alike.
  */
  homePath = config.nori.fs.home.path;

  cachePaths = lib.mapAttrsToList (_: f: f.path) (
    lib.filterAttrs (
      _: f: f.tier == "re-derivable" && lib.hasPrefix "${homePath}/" f.path
    ) config.nori.fs
  );

  homeFs = config.fileSystems.${homePath};

  /*
    Root Btrfs identity, read back out of the disko layout instead of
    re-typed here: the disk by-id this host pins and the "-L" label of
    the root filesystem disko creates. A layout change (new disk, new
    label) flows into the migration's validation automatically.
  */
  rootDiskDevice = config.disko.devices.disk.main.device;
  rootBtrfsArgs = config.disko.devices.disk.main.content.partitions.root.content.extraArgs;
  valueAfter =
    flag: args:
    let
      len = builtins.length args;
      go =
        i:
        if i >= len then
          null
        else if builtins.elemAt args i == flag then
          (if i + 1 < len then builtins.elemAt args (i + 1) else null)
        else
          go (i + 1);
    in
    go 0;
  fsLabel = valueAfter "-L" rootBtrfsArgs;

  migrate = pkgs.writeShellApplication {
    name = "nori-cache-migrate";
    runtimeInputs = with pkgs; [
      btrfs-progs
      coreutils
      diffutils
      gnused
      lsof
      util-linux
    ];
    text = builtins.readFile ./cache-migrate.sh;
  };
in
{
  config = lib.mkIf (cachePaths != [ ] && config.fileSystems ? ${homePath}) {
    # A mis-shaped classification or an unexpected layout fails the build
    # rather than producing a migration unit that validates the wrong
    # filesystem.
    assertions = [
      {
        assertion = homeFs.fsType == "btrfs";
        message = "cache-migration: ${homePath} is on ${homeFs.fsType}, not btrfs — disposable caches cannot be subvolume boundaries here.";
      }
      {
        assertion = fsLabel != null;
        message = "cache-migration: the disko root content declares no btrfs label (-L); the guarded migration needs the label it validates against.";
      }
      {
        assertion = builtins.all (p: lib.hasPrefix "${homePath}/" p) cachePaths;
        message = "cache-migration: a re-derivable cache path is not nested under ${homePath}: ${lib.concatStringsSep ", " cachePaths}";
      }
    ];

    systemd.services.cache-migration = {
      description = "Convert explicitly disposable caches into nested ${homePath} subvolumes (guarded, idempotent)";
      wantedBy = [ "multi-user.target" ];
      /*
        /home must be mounted before the cache directories can be
        converted. Nothing mounts the cache boundaries themselves — disko
        emits no fileSystems entry for them (mountpoint = null) — so a
        failed or blocked migration cannot hide data behind an empty
        mount; the run is ordered after the /home mount and reports its
        blocker through the shared alert path.

        The run is idempotent and covers the three interesting states:
          * an absent cache directory gets its boundary created up front,
            owned like the cache parent (or the home directory), so the
            boundary exists before the tool that writes the cache starts
            rather than only after a later reboot;
          * a root-owned boundary (an install-time disko creation) adopts
            that same ownership — the boundary directory only;
          * an existing plain directory is copied into a staging
            subvolume and swapped into place with one atomic
            renameat2(RENAME_EXCHANGE), so the path is never absent and
            the staging tree cannot end up nested inside it.
        Refusals are explicit: a busy cache, a missing parent or home
        directory, a symlink, a mount point, or leftover rollback/staging
        state fail the unit loudly instead of guessing.
      */
      unitConfig = {
        RequiresMountsFor = [ homePath ];
        OnFailure = [ "notify@cache-migration.service" ];
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.escapeShellArgs (
          [
            "${migrate}/bin/nori-cache-migrate"
            "--device"
            rootDiskDevice
            "--mount-device"
            homeFs.device
            "--fs-label"
            fsLabel
            "--home"
            homePath
          ]
          ++ cachePaths
        );
      };
    };
  };
}
