/*
  Disposable cache separation — 2026-10-07 storage-pressure spec,
  § "Disposable caches" and/or acceptance gates 7–9.

  Pins the semantic derivation on the real workstation configuration, so
  a drift in any single place (registry tier, disko boundary, restic
  exclusion, snapshot membership) fails here instead of silently
  shrinking what is disposable:

    * the three caches are one nori.fs registry tier ("re-derivable")
      and nothing else under ~/.cache is classified disposable;
    * each gets a nested @home subvolume boundary at the same visible
      path, with NO separate mount unit (an empty boundary can never be
      mounted over existing data);
    * the recursive user-data restic job excludes exactly the derived
      paths, while the whole ~/.cache tree, the browser cache and
      ~/.omp/agent/cache stay included (not proven disposable);
    * btrbk never snapshots the caches directly.
  Cross-module behaviour (real parent snapshot, real recursive restic
  backup, migration preserve/refuse/rollback) is proven against real
  disposable filesystems in tests/cache-migration_test.sh; this check
  stays on the semantic derivation — registry classification, declared
  boundaries, derived exclusions, snapshot membership — and deliberately
  does not pin the service unit's options (that wiring is inspected
  directly on the built unit).
*/
{ inputs, lib, ... }:
let
  config = inputs.self.nixosConfigurations.workstation.config;
  fs = config.nori.fs;

  caches = {
    home-cache-pip = "/home/nori/.cache/pip";
    home-cache-uv = "/home/nori/.cache/uv";
    home-cache-nix = "/home/nori/.cache/nix";
  };
  cacheNames = lib.attrNames caches;
  cachePaths = lib.attrValues caches;
  subvolumeName = path: "@home${lib.removePrefix "/home" path}";

  subvolumes = config.disko.devices.disk.main.content.partitions.root.content.subvolumes;
  userData = config.nori.backups.user-data;
  rootSubvols = config.services.btrbk.instances.root.settings.volume."/".subvolume;

  # 1. One classification: tier "re-derivable" entries in the registry,
  #    declared in disko.nix beside the boundaries they map to.
  registry = builtins.all (
    n: fs ? ${n} && fs.${n}.tier == "re-derivable" && fs.${n}.path == caches.${n}
  ) cacheNames;

  # 2. Nested boundaries, same visible paths, no mount units of their
  #    own (disko emits fileSystems only for non-null mountpoints).
  boundaryMountpoint =
    path: lib.attrByPath [ (subvolumeName path) "mountpoint" ] "missing" subvolumes;
  boundaries =
    builtins.all (p: boundaryMountpoint p == null) cachePaths
    && !lib.any (m: lib.elem m cachePaths) (lib.attrNames config.fileSystems);

  # 3. Recursive excludes: the caches are dropped from the user-data
  #    backup, protected neighbours and the parent include stay.
  exclusions =
    builtins.all (p: lib.elem p userData.exclude) cachePaths
    && lib.elem "/home" userData.include
    && !lib.elem "/home/nori/.cache" userData.exclude
    && !lib.elem "/home/nori/.omp/agent/cache" userData.exclude
    && !lib.elem "/home/nori/.cache/chromium" userData.exclude
    && lib.elem "/home/nori/.claude/cache" userData.exclude;

  # 4. btrbk snapshots the parent subvolumes only; the caches (nested
  #    boundaries, re-derivable tier) are never direct subvolume entries.
  snapshots =
    builtins.all (p: !(rootSubvols ? ${lib.removePrefix "/" p})) cachePaths && rootSubvols ? "home";

  checks = {
    inherit
      registry
      boundaries
      exclusions
      snapshots
      ;
  };
  failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) checks);
in
if failed == [ ] then
  "ok — disposable caches are one registry tier: nested @home boundaries with no mount units, derived restic exclusions, no direct snapshot membership"
else
  throw ''
    disposable cache separation mismatch: ${lib.concatStringsSep ", " failed}

      registry:      ${builtins.toJSON registry}
      boundaries:    ${builtins.toJSON boundaries}
      exclusions:    ${builtins.toJSON exclusions}
      snapshots:     ${builtins.toJSON snapshots}

      cache paths:        ${lib.concatStringsSep ", " cachePaths}
      user-data exclude:  ${lib.concatStringsSep ", " userData.exclude}
      root subvolumes:    ${lib.concatStringsSep ", " (lib.attrNames rootSubvols)}
  ''
