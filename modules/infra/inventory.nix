{ lib, ... }:

/**
  Typed, read-only projection of the pure pre-evaluation inventory.

  Values are injected by `modules/machines/default.nix`; modules consume this
  interface but cannot use it to select imports. Compiler-private module paths
  and future artifact handles never enter the projection.
*/

let
  inherit (lib) mkOption types;

  identityOptions = {
    tailnetIp = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    lanIp = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    role = mkOption {
      type = types.enum [
        "workhorse"
        "appliance"
        "agent"
        "client"
      ];
    };
    roleOneLiner = mkOption { type = types.str; };
    codename = mkOption { type = types.str; };
    hardware = mkOption { type = types.str; };
    primaryJob = mkOption { type = types.str; };
  };

  hostType = types.submodule {
    options = identityOptions // {
      kind = mkOption {
        type = types.enum [
          "nixos"
          "home-manager"
        ];
      };
      profiles = mkOption { type = types.listOf types.str; };
      workloads = mkOption { type = types.listOf types.str; };
    };
  };

  profileType = types.submodule {
    options = {
      description = mkOption { type = types.str; };
      workloads = mkOption { type = types.listOf types.str; };
    };
  };

  workloadType = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "service"
          "job"
        ];
      };
      active = mkOption {
        type = types.bool;
        default = true;
        description = "Whether the placed workload currently realizes its user-facing runtime and endpoints.";
      };
      tags = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      endpoints = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = "Resolved, secret-free endpoint metadata; validated by the networking route schema when projected.";
      };
      hosts = mkOption { type = types.listOf types.str; };
      profiles = mkOption { type = types.listOf types.str; };
      artifact = mkOption {
        type = types.nullOr artifactType;
        default = null;
      };
    };
  };

  artifactType = types.submodule {
    options = {
      kind = mkOption { type = types.enum [ "static-web" ]; };
      immutable = mkOption { type = types.bool; };
      source = mkOption {
        type = types.submodule {
          options = {
            repository = mkOption { type = types.str; };
            ref = mkOption { type = types.str; };
          };
        };
      };
      consumer = mkOption {
        type = types.submodule {
          options = {
            kind = mkOption {
              type = types.enum [
                "nix-package"
                "release-archive"
                "oci-image"
                "legacy-host-build"
              ];
            };
            unit = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
          };
        };
      };
      legacyException = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              owner = mkOption { type = types.str; };
              reason = mkOption { type = types.str; };
              removalTrigger = mkOption { type = types.str; };
              verification = mkOption { type = types.str; };
            };
          }
        );
        default = null;
      };
    };
  };

  datasetType = types.submodule {
    options = {
      description = mkOption { type = types.str; };
      valueTier = mkOption {
        type = types.enum [
          "replaceable"
          "curated"
          "irreplaceable"
        ];
      };
      canonicalFormat = mkOption { type = types.str; };
      storage = mkOption {
        type = types.submodule {
          options = {
            filesystem = mkOption { type = types.str; };
            relativePath = mkOption { type = types.str; };
          };
        };
      };
      producers = mkOption { type = types.listOf types.str; };
      consumers = mkOption { type = types.listOf types.str; };
      derivedFormats = mkOption { type = types.listOf types.str; };
      delivery = mkOption {
        type = types.submodule {
          options = {
            protocol = mkOption { type = types.str; };
            transcodeOnDemand = mkOption { type = types.listOf types.str; };
            persistentDerivative = mkOption { type = types.bool; };
          };
        };
      };
    };
  };

  deploymentTargetType = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "nixos"
          "home-manager"
        ];
      };
      profiles = mkOption { type = types.listOf types.str; };
      workloads = mkOption { type = types.listOf types.str; };
      buildAttribute = mkOption { type = types.str; };
    };
  };

  deploymentType = types.submodule {
    options = {
      targets = mkOption { type = types.attrsOf deploymentTargetType; };
      buildOrder = mkOption { type = types.listOf types.str; };
      activationOrder = mkOption { type = types.listOf types.str; };
    };
  };
in
{
  options.nori.inventory = {
    currentHost = mkOption {
      type = types.str;
      readOnly = true;
      description = "Host whose NixOS configuration is currently evaluating.";
    };
    currentWorkloads = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      description = "Workload identifiers resolved from this host's explicit profiles and direct additions.";
    };
    hosts = mkOption {
      type = types.attrsOf hostType;
      readOnly = true;
      description = "Public-safe host identity, profile, and resolved workload inventory.";
    };
    profiles = mkOption {
      type = types.attrsOf profileType;
      readOnly = true;
      description = "Explicit reusable profile descriptions and workload membership.";
    };
    workloads = mkOption {
      type = types.attrsOf workloadType;
      readOnly = true;
      description = "Public-safe workload identity and resolved placement.";
    };
    datasets = mkOption {
      type = types.attrsOf datasetType;
      readOnly = true;
      description = "Public-safe canonical dataset ownership, storage, producer, consumer, and delivery contracts.";
    };
    deployment = mkOption {
      type = deploymentType;
      readOnly = true;
      description = "Public-safe build targets and backend-before-entry-plane activation order derived from host inventory.";
    };
  };
}
