/*
  Direct module evaluation for the music-ingest service.

  The repository check imports this function with pinned `nixpkgs`, `pkgs`,
  `lib`, and `system` arguments. Relative module paths below resolve from
  this file, so evaluation does not reopen the repository flake.

  This evaluates the module as Nix data. It does not activate systemd or touch
  the configured paths.
*/
{
  nixpkgs,
  pkgs,
  lib,
  system,
}:
let
  modulePath = ../nixos.nix;

  base = {
    resources = {
      staging = {
        path = "/srv/music-ingest/staging-fs/staging";
        filesystem = "staging-fs";
      };
      inflight = {
        path = "/srv/music-ingest/staging-fs/.music-ingest-inflight";
        filesystem = "staging-fs";
      };
      master = {
        path = "/srv/music-ingest/master-fs/music";
        filesystem = "master-fs";
      };
    };
    stabilitySeconds = 60;
    interval = "1h";
  };

  configure =
    override:
    base
    // builtins.removeAttrs override [ "resources" ]
    // {
      resources = base.resources // (override.resources or { });
    };

  evaluate =
    override:
    let
      result = import "${nixpkgs}/nixos/lib/eval-config.nix" {
        inherit lib pkgs system;
        modules = [
          modulePath
          ../../../infra/common/nixos/service-hardening.nix
          ../../../infra/common/nixos/backup.nix
          (_: {
            nori.services."music-ingest" = configure override;
            system.stateVersion = "26.11";
          })
        ];
      };
      inherit (result) config;
      failedAssertions = builtins.filter (
        item: !item.assertion && lib.hasPrefix "nori.services.music-ingest" item.message
      ) config.assertions;
      service = config.systemd.services."music-ingest";
      timer = config.systemd.timers."music-ingest";
    in
    if failedAssertions != [ ] then
      throw (lib.concatMapStringsSep "; " (item: item.message) failedAssertions)
    else
      {
        type = service.serviceConfig.Type;
        user = service.serviceConfig.User;
        group = service.serviceConfig.Group;
        supplementaryGroups = service.serviceConfig.SupplementaryGroups;
        umask = service.serviceConfig.UMask;
        execStart = service.serviceConfig.ExecStart;
        bindPaths = service.serviceConfig.BindPaths;
        requiresMountsFor = service.unitConfig.RequiresMountsFor;
        inherit (service) environment;
        onFailure = service.unitConfig.OnFailure;
        successExitStatus = service.serviceConfig.SuccessExitStatus or null;
        nice = service.serviceConfig.Nice;
        ioSchedulingClass = service.serviceConfig.IOSchedulingClass;
        cpuSchedulingPolicy = service.serviceConfig.CPUSchedulingPolicy;
        timer = {
          persistent = timer.timerConfig.Persistent;
          interval = timer.timerConfig.OnUnitActiveSec;
          jitter = timer.timerConfig.RandomizedDelaySec;
        };
        tmpfilesRules = config.systemd.tmpfiles.rules;
      };

  rejects = override: !(builtins.tryEval (builtins.deepSeq (evaluate override) true)).success;
  accepts = override: (builtins.tryEval (builtins.deepSeq (evaluate override) true)).success;

  negative = {
    equalStagingInflight = rejects {
      resources = {
        inflight = base.resources.inflight // {
          path = base.resources.staging.path;
        };
      };
    };
    masterContainsStaging = rejects {
      resources = {
        master = base.resources.master // {
          path = "${base.resources.staging.path}/../staging";
        };
      };
    };
    stagingContainsMaster = rejects {
      resources = {
        master = base.resources.master // {
          path = "${base.resources.staging.path}/master";
        };
      };
    };
    masterContainsInflight = rejects {
      resources = {
        master = base.resources.master // {
          path = "/srv/music-ingest/staging-fs";
        };
      };
    };
    inflightContainsMaster = rejects {
      resources = {
        master = base.resources.master // {
          path = "${base.resources.inflight.path}/master";
        };
      };
    };
    inflightInsideSyncthingStaging = rejects {
      resources = {
        inflight = base.resources.inflight // {
          path = "${base.resources.staging.path}/.music-ingest-inflight";
        };
      };
    };
    declaredDifferentClaimFilesystems = rejects {
      resources = {
        inflight = base.resources.inflight // {
          filesystem = "other-fs";
        };
      };
    };
    relativeResourcePath = rejects {
      resources = {
        staging = base.resources.staging // {
          path = "relative/staging";
        };
      };
    };
    emptyResourcePath = rejects {
      resources = {
        master = base.resources.master // {
          path = "";
        };
      };
    };
  };

  positive = evaluate {
    resources = {
      staging = base.resources.staging // {
        filesystem = "shared-fs";
      };
      inflight = base.resources.inflight // {
        filesystem = "shared-fs";
      };
      master = base.resources.master // {
        filesystem = "master-fs";
      };
    };
  };

  masterSameFilesystemAccepted = accepts {
    resources = {
      staging = base.resources.staging // {
        filesystem = "shared-fs";
      };
      inflight = base.resources.inflight // {
        filesystem = "shared-fs";
      };
      master = base.resources.master // {
        filesystem = "shared-fs";
      };
    };
  };
in
assert builtins.all (value: value) (builtins.attrValues negative);
assert masterSameFilesystemAccepted;
assert positive.type == "oneshot";
assert positive.user == "music-ingest";
assert positive.group == "music-ingest";
assert positive.supplementaryGroups == [ "media" ];
assert positive.umask == "0002";
assert lib.hasInfix "/nix/store/" positive.execStart;
assert positive.environment.MUSIC_INGEST_STAGING == base.resources.staging.path;
assert positive.environment.MUSIC_INGEST_INFLIGHT == base.resources.inflight.path;
assert positive.environment.MUSIC_INGEST_MASTER == base.resources.master.path;
assert positive.environment.MUSIC_INGEST_STABILITY_SECONDS == "60";
assert positive.environment.MUSIC_INGEST_EXTENSIONS == "flac jpg jpeg png webp";
assert positive.onFailure == [ "notify@music-ingest.service" ];
assert positive.successExitStatus == null;
assert
  lib.sort lib.lessThan positive.requiresMountsFor == lib.sort lib.lessThan [
    base.resources.staging.path
    base.resources.inflight.path
    base.resources.master.path
    "${base.resources.staging.path}/.conflicts"
  ];
assert positive.timer.persistent;
assert positive.timer.interval == "1h";
assert positive.timer.jitter == "60s";
assert builtins.all (
  path: builtins.any (rule: lib.hasPrefix "d ${path} " rule) positive.tmpfilesRules
) positive.bindPaths;
assert builtins.any (
  rule: lib.hasPrefix "d ${base.resources.staging.path}/.conflicts " rule
) positive.tmpfilesRules;
{
  inherit masterSameFilesystemAccepted negative positive;
  evidenceClass = "NixOS module evaluation; no systemd or live-host claim";
}
