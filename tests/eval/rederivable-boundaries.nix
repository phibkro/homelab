/*
  Re-derivable nested Btrfs boundaries from the nori.fs registry.
  Pins the single classification through disko subvolumes, btrbk filtering,
  Restic exclusions, and automatic/manual locked migration units.
  Real filesystem behavior is covered by tests/subvolume-migration_test.sh.
*/
{ inputs, lib, ... }:
let
  config = inputs.self.nixosConfigurations.workstation.config;
  fs = config.nori.fs;
  parentPaths = [
    "/home"
    "/srv/share"
  ];
  rederivable = lib.filterAttrs (
    _: entry:
    entry.tier == "re-derivable"
    && lib.any (parent: lib.hasPrefix (parent + "/") entry.path) parentPaths
  ) fs;
  paths = map (entry: entry.path) (lib.attrValues rederivable);
  steamNames = [
    "home-steam-common"
    "home-steam-shadercache"
    "home-steam-downloading"
    "home-steam-workshop-content"
    "srv-share-steam-common"
    "srv-share-steam-shadercache"
    "srv-share-steam-downloading"
    "srv-share-steam-workshop-content"
  ];
  steamPaths = map (name: fs.${name}.path) steamNames;
  steamProtectedPaths = [
    "/home/nori/.local/share/Steam/steamapps/compatdata"
    "/home/nori/.local/share/Steam/userdata"
    "/home/nori/.local/share/Steam/config"
    "/home/nori/.local/share/Steam/steamapps/appmanifest-test.acf"
    "/home/nori/.local/share/Steam/steamapps/workshop/appworkshop_test.acf"
  ];
  isExcluded =
    path: lib.any (excluded: path == excluded || lib.hasPrefix (excluded + "/") path) userData.exclude;
  subvolumes = config.disko.devices.disk.main.content.partitions.root.content.subvolumes;
  subvolumeName =
    path:
    let
      parent = lib.findFirst (
        p: lib.hasPrefix (p + "/") path
      ) (throw "No backed-up parent for ${path}") parentPaths;
      mountOption =
        lib.findFirst (lib.hasPrefix "subvol=") (throw "No source subvolume for ${parent}")
          config.fileSystems.${parent}.options;
    in
    lib.removePrefix "subvol=" mountOption + lib.removePrefix parent path;
  userData = config.nori.backups.user-data;
  rootSubvols = config.services.btrbk.instances.root.settings.volume."/".subvolume;
  migrationPaths = import ../../src/infra/common/nixos/storage/subvolume-paths.nix;
  expectedExcludes = lib.concatMap (path: lib.attrValues (migrationPaths.forPath path)) paths;
  homeService = config.systemd.services.nori-subvolume-migration-home;
  shareService = config.systemd.services.nori-subvolume-migration-srv-share;
  homeSteamService = config.systemd.services.nori-subvolume-migration-home-steam;
  shareSteamService = config.systemd.services.nori-subvolume-migration-srv-share-steam;
  checks = {
    projectsExcluded = rederivable.srv-share-projects.path == "/srv/share/projects";
    steamRegistry =
      builtins.all (name: fs.${name}.tier == "re-derivable") steamNames
      &&
        map (name: fs.${name}.atBoot) steamNames == builtins.genList (_: false) (builtins.length steamNames)
      && builtins.all (
        name:
        fs.${name}.stoppedProcesses == [
          "steam"
          "steamwebhelper"
        ]
      ) steamNames
      &&
        steamPaths == [
          "/home/nori/.local/share/Steam/steamapps/common"
          "/home/nori/.local/share/Steam/steamapps/shadercache"
          "/home/nori/.local/share/Steam/steamapps/downloading"
          "/home/nori/.local/share/Steam/steamapps/workshop/content"
          "/srv/share/SteamLibrary/steamapps/common"
          "/srv/share/SteamLibrary/steamapps/shadercache"
          "/srv/share/SteamLibrary/steamapps/downloading"
          "/srv/share/SteamLibrary/steamapps/workshop/content"
        ];
    noMountOverlay = builtins.all (
      path:
      subvolumes.${subvolumeName path}.mountpoint == null && !(builtins.hasAttr path config.fileSystems)
    ) paths;
    restic = builtins.all (path: builtins.elem path userData.exclude) expectedExcludes;
    steamResticSplit =
      builtins.all (path: builtins.elem path userData.exclude) steamPaths
      && builtins.all (path: !(isExcluded path)) steamProtectedPaths;
    snapshotFilter =
      builtins.all (path: !(builtins.hasAttr (lib.removePrefix "/" path) rootSubvols)) paths
      && builtins.hasAttr "home" rootSubvols
      && builtins.hasAttr "srv/share" rootSubvols;
    steamSnapshotFilter = builtins.all (
      path: !(builtins.hasAttr (lib.removePrefix "/" path) rootSubvols)
    ) steamPaths;
    homeRemainsAutomatic =
      builtins.elem "multi-user.target" homeService.wantedBy
      && !(lib.hasInfix "--require-stopped-process" homeService.serviceConfig.ExecStart);
    homeSteamRequiresManualStart =
      homeSteamService.wantedBy == [ ]
      && lib.all (process: lib.hasInfix process homeSteamService.serviceConfig.ExecStart) [
        "steam"
        "steamwebhelper"
      ]
      && builtins.all (path: lib.hasInfix path homeSteamService.serviceConfig.ExecStart) (
        builtins.filter (path: lib.hasPrefix "/home/" path) steamPaths
      );
    shareSteamRequiresManualStart =
      shareSteamService.wantedBy == [ ]
      && lib.all (process: lib.hasInfix process shareSteamService.serviceConfig.ExecStart) [
        "steam"
        "steamwebhelper"
      ]
      && builtins.all (path: lib.hasInfix path shareSteamService.serviceConfig.ExecStart) (
        builtins.filter (path: lib.hasPrefix "/srv/share/" path) steamPaths
      );
    projectsRequireManualStart =
      shareService.wantedBy == [ ]
      && !(lib.hasInfix "--require-stopped-process" shareService.serviceConfig.ExecStart);
  };
  failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
if failed == [ ] then
  "ok — re-derivable paths use null-mountpoint subvolumes, parent-derived snapshot/restic filters, automatic caches, manual Steam/project migrations, and retained Steam save data"
else
  throw ''
    re-derivable boundary mismatch: ${lib.concatStringsSep ", " failed}

      checks: ${builtins.toJSON checks}
      paths: ${lib.concatStringsSep ", " paths}
      Steam paths: ${lib.concatStringsSep ", " steamPaths}
      protected Steam paths: ${lib.concatStringsSep ", " steamProtectedPaths}
      Restic exclusions: ${lib.concatStringsSep ", " userData.exclude}
      root snapshot subvolumes: ${lib.concatStringsSep ", " (lib.attrNames rootSubvols)}
  ''
