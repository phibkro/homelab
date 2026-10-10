/*
  Re-derivable nested Btrfs boundaries from the nori.fs registry.
  Pins the single classification through disko subvolumes, btrbk filtering,
  Restic exclusions (including failure-preserved migration artifacts), and
  the automatic-home/manual-share locked migration units. Real filesystem
  behavior is covered by tests/subvolume-migration_test.sh.
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
  subvolumes = config.disko.devices.disk.main.content.partitions.root.content.subvolumes;
  subvolumeName = path: "@${lib.removePrefix "/" path}";
  userData = config.nori.backups.user-data;
  rootSubvols = config.services.btrbk.instances.root.settings.volume."/".subvolume;
  expectedExcludes = lib.concatMap (
    path:
    let
      parent = lib.dirOf path;
      base = lib.baseNameOf path;
    in
    [
      path
      (parent + "/." + base + ".nori-subvolume-migration-staging")
      (parent + "/." + base + ".nori-subvolume-migration-rollback")
    ]
  ) paths;
  homeService = config.systemd.services.nori-subvolume-migration-home;
  shareService = config.systemd.services.nori-subvolume-migration-srv-share;
  homeStart = homeService.serviceConfig.ExecStart;
  shareStart = shareService.serviceConfig.ExecStart;
  checks = {
    registry =
      rederivable.home-cache-pip.path == "/home/nori/.cache/pip"
      && rederivable.home-cache-uv.path == "/home/nori/.cache/uv"
      && rederivable.home-cache-nix.path == "/home/nori/.cache/nix"
      && rederivable.srv-share-projects.path == "/srv/share/projects"
      && builtins.length paths == 4;
    noMountOverlay = builtins.all (
      path:
      subvolumes.${subvolumeName path}.mountpoint == null && !(builtins.hasAttr path config.fileSystems)
    ) paths;
    restic = builtins.all (path: builtins.elem path userData.exclude) expectedExcludes;
    snapshotFilter =
      builtins.all (path: !(builtins.hasAttr (lib.removePrefix "/" path) rootSubvols)) paths
      && builtins.hasAttr "home" rootSubvols
      && builtins.hasAttr "srv/share" rootSubvols;
    homeRemainsAutomatic =
      homeService.wantedBy == [ "multi-user.target" ]
      && builtins.all (path: lib.hasInfix path homeStart) [
        "/home/nori/.cache/nix"
        "/home/nori/.cache/pip"
        "/home/nori/.cache/uv"
      ]
      && !(lib.hasInfix "/srv/share/projects" homeStart)
      && lib.hasInfix "nori-storage-pressure" homeStart
      && lib.hasInfix "with-lock" homeStart;
    projectsRequireManualStart =
      shareService.wantedBy == [ ]
      && lib.hasInfix "/srv/share/projects" shareStart
      && lib.hasInfix "nori-storage-pressure" shareStart
      && lib.hasInfix "with-lock" shareStart;
  };
  failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
if failed == [ ] then
  "ok — re-derivable paths use null-mountpoint subvolumes, parent-derived snapshot/restic filters, automatic locked home-cache setup, and a manual locked projects migration"
else
  throw ''
    re-derivable boundary mismatch: ${lib.concatStringsSep ", " failed}

      checks: ${builtins.toJSON checks}
      paths: ${lib.concatStringsSep ", " paths}
      Restic exclusions: ${lib.concatStringsSep ", " userData.exclude}
      root snapshot subvolumes: ${lib.concatStringsSep ", " (lib.attrNames rootSubvols)}
      home migration command: ${homeStart}
      share migration command: ${shareStart}
  ''
