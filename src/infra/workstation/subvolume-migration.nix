{
  config,
  lib,
  pkgs,
  ...
}:
let
  userParents = lib.filterAttrs (_: f: f.tier == "user") config.nori.fs;
  rederivable = lib.filterAttrs (
    _: f:
    f.tier == "re-derivable"
    && lib.any (parent: lib.hasPrefix (parent.path + "/") f.path) (lib.attrValues userParents)
  ) config.nori.fs;
  parentPaths = lib.unique (
    lib.concatMap (
      f:
      map (parent: parent.path) (
        lib.attrValues (lib.filterAttrs (_: parent: lib.hasPrefix (parent.path + "/") f.path) userParents)
      )
    ) (lib.attrValues rederivable)
  );
  paths = map (f: f.path) (lib.attrValues rederivable);
  parentFilesystems = map (
    path:
    lib.attrByPath [ path ] {
      fsType = null;
      device = null;
    } config.fileSystems
  ) parentPaths;
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
    name = "nori-subvolume-migrate";
    runtimeInputs = with pkgs; [
      btrfs-progs
      coreutils
      diffutils
      gnused
      lsof
      util-linux
    ];
    text = builtins.readFile ./subvolume-migrate.sh;
  };
  migrationServices = lib.listToAttrs (
    map (
      parent:
      let
        targets = builtins.filter (path: lib.hasPrefix (parent + "/") path) paths;
        name = "nori-subvolume-migration-${
          lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" parent)
        }";
        parentFilesystem = config.fileSystems.${parent};
        startsAtBoot = parent == config.nori.fs.home.path;
      in
      lib.nameValuePair name {
        description = "Guarded migration of re-derivable paths under ${parent}";
        wantedBy = lib.optionals startsAtBoot [ "multi-user.target" ];
        unitConfig = {
          RequiresMountsFor = [ parent ];
          OnFailure = [ "notify@${name}.service" ];
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.escapeShellArgs (
            [
              "${config.nori.storagePressure.package}/bin/nori-storage-pressure"
              "with-lock"
              parent
              "${migrate}/bin/nori-subvolume-migrate"
              "--device"
              rootDiskDevice
              "--mount-device"
              parentFilesystem.device
              "--fs-label"
              fsLabel
              "--parent"
              parent
            ]
            ++ targets
          );
        };
      }
    ) parentPaths
  );
in
{
  config = lib.mkIf (paths != [ ] && parentPaths != [ ]) {
    assertions = [
      {
        assertion = builtins.all (path: builtins.hasAttr path config.fileSystems) parentPaths;
        message = "subvolume-migration: every re-derivable path must be nested under a declared user-tier filesystem";
      }
      {
        assertion = builtins.all (fs: fs.fsType == "btrfs") parentFilesystems;
        message = "subvolume-migration: every backed-up parent filesystem must be Btrfs";
      }
      {
        assertion = fsLabel != null;
        message = "subvolume-migration: the disko root content declares no Btrfs label (-L)";
      }
      {
        assertion = builtins.all (
          path: lib.any (parent: lib.hasPrefix (parent + "/") path) parentPaths
        ) paths;
        message = "subvolume-migration: a re-derivable path is not nested under a backed-up user-tier parent";
      }
    ];

    # Home caches keep their established guarded boot-time initialization.
    # Other re-derivable paths (notably /srv/share/projects) are manual because
    # their writers may include interactive agents and shared workloads.
    systemd.services = migrationServices;
  };
}
