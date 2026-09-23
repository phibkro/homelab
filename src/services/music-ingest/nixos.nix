{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nori.services."music-ingest";

  resourceType = lib.types.submodule {
    options = {
      path = lib.mkOption {
        type = lib.types.str;
        description = "Absolute path bound to a music-ingest resource.";
      };
      filesystem = lib.mkOption {
        type = lib.types.str;
        description = "Declared filesystem identity for the resource binding.";
      };
    };
  };

  resourceNames = [
    "staging"
    "inflight"
    "master"
  ];

  normalizePath =
    path:
    let
      step =
        segments: segment:
        if segment == "" || segment == "." then
          segments
        else if segment == ".." then
          if segments == [ ] then [ ] else lib.init segments
        else
          segments ++ [ segment ];
      segments = lib.foldl' step [ ] (lib.splitString "/" path);
    in
    "/${lib.concatStringsSep "/" segments}";

  # The role map is the single source for bindings, mount requirements and
  # tmpfiles. Quarantine is deliberately derived from staging, not supplied as
  # a fourth independent resource that could drift onto another filesystem.
  rawRolePaths = {
    staging = cfg.resources.staging.path;
    inflight = cfg.resources.inflight.path;
    master = cfg.resources.master.path;
    quarantine = "${cfg.resources.staging.path}/.conflicts";
  };
  rolePaths = lib.mapAttrs (_: normalizePath) rawRolePaths;
  bindPaths = map (name: rolePaths.${name}) resourceNames;

  pathContains =
    parent: child:
    if parent == "/" then
      child != "/" && lib.hasPrefix "/" child
    else
      parent == child || lib.hasPrefix "${parent}/" child;

  pathPairs = [
    {
      a = rolePaths.staging;
      b = rolePaths.inflight;
    }
    {
      a = rolePaths.staging;
      b = rolePaths.master;
    }
    {
      a = rolePaths.inflight;
      b = rolePaths.master;
    }
  ];

  pathsAreDisjoint = lib.all (
    { a, b }: a != b && !(pathContains a b) && !(pathContains b a)
  ) pathPairs;

  ingest = pkgs.writeShellApplication {
    name = "music-ingest";
    runtimeInputs = [
      pkgs.b3sum
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux
    ];
    text = builtins.readFile ./ingest.sh;
  };
in
{
  options.nori.services."music-ingest" = {
    resources = lib.mkOption {
      type = lib.types.submodule {
        options = {
          staging = lib.mkOption {
            type = resourceType;
            description = "Syncthing-managed source resource.";
          };
          inflight = lib.mkOption {
            type = resourceType;
            description = "Durable same-filesystem claim resource.";
          };
          master = lib.mkOption {
            type = resourceType;
            description = "Canonical published music resource.";
          };
        };
      };
      description = "Explicit filesystem bindings consumed by music-ingest.";
    };

    stabilitySeconds = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 60;
      description = "Minimum mtime age before a source is eligible.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "Persistent systemd timer cadence.";
    };

    jitter = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "Maximum timer start jitter.";
    };

    extensions = lib.mkOption {
      type = lib.types.str;
      default = "flac jpg jpeg png webp";
      description = "Space-separated case-insensitive eligible extensions.";
    };
  };

  config = {
    assertions = [
      {
        assertion = lib.all (
          name:
          let
            path = cfg.resources.${name}.path;
          in
          path != "" && lib.hasPrefix "/" path
        ) resourceNames;
        message = "nori.services.music-ingest resource paths must be absolute.";
      }
      {
        assertion = pathsAreDisjoint;
        message = "nori.services.music-ingest staging, inflight, and master paths must be normalized, distinct, and disjoint.";
      }
      {
        assertion =
          cfg.resources.staging.filesystem != ""
          && cfg.resources.inflight.filesystem != ""
          && cfg.resources.master.filesystem != "";
        message = "nori.services.music-ingest resource filesystem identities must be non-empty.";
      }
      {
        assertion = cfg.resources.staging.filesystem == cfg.resources.inflight.filesystem;
        message = "nori.services.music-ingest staging and inflight bindings must share a filesystem identity.";
      }
    ];

    users.groups.media = lib.mkDefault { };
    users.groups.music-ingest = { };
    users.users.music-ingest = {
      isSystemUser = true;
      group = "music-ingest";
      extraGroups = [ "media" ];
      home = "/var/empty";
      description = "Bounded music-ingest sweep principal";
    };

    # The shared capability concern turns this declaration into BindPaths,
    # RequiresMountsFor, /mnt and /srv isolation, and the default-deny baseline.
    # Quarantine is inside staging and therefore needs no second bind mount.
    nori.harden."music-ingest" = {
      binds = bindPaths;
    };

    # Acquisition paths are outside backup intent: staging is replicated input
    # and inflight is recoverable sweep state. The published master is covered
    # by its canonical media filesystem backup policy.
    nori.backups."music-ingest".skip =
      "staging is replicated input and inflight is recoverable acquisition state; the published master belongs to the canonical media backup policy.";

    systemd.tmpfiles.rules = [
      "d ${rolePaths.staging} 02775 root media - -"
      "d ${rolePaths.inflight} 02770 music-ingest media - -"
      "d ${rolePaths.master} 02775 root media - -"
      "d ${rolePaths.quarantine} 02770 music-ingest media - -"
    ];

    systemd.services."music-ingest" = {
      description = "Bounded music-ingest sweep";
      after = [ "local-fs.target" ];
      unitConfig = {
        RequiresMountsFor = lib.mkAfter [ rolePaths.quarantine ];
        OnFailure = [ "notify@music-ingest.service" ];
      };
      environment = {
        MUSIC_INGEST_STAGING = rolePaths.staging;
        MUSIC_INGEST_INFLIGHT = rolePaths.inflight;
        MUSIC_INGEST_MASTER = rolePaths.master;
        MUSIC_INGEST_STABILITY_SECONDS = toString cfg.stabilitySeconds;
        MUSIC_INGEST_EXTENSIONS = cfg.extensions;
      };
      serviceConfig = {
        Type = "oneshot";
        User = "music-ingest";
        Group = "music-ingest";
        SupplementaryGroups = [ "media" ];
        ExecStart = "${ingest}/bin/music-ingest";
        UMask = "0002";
        ProtectSystem = "strict";
        PrivateDevices = true;
        Nice = 12;
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "batch";
      };
    };

    systemd.timers."music-ingest" = {
      description = "Periodic bounded music-ingest sweep";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.interval;
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = cfg.jitter;
      };
    };
  };
}
