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
    tailnetIp = mkOption { type = types.str; };
    lanIp = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    role = mkOption {
      type = types.enum [
        "workhorse"
        "appliance"
        "agent"
      ];
    };
    roleOneLiner = mkOption { type = types.str; };
    codename = mkOption { type = types.str; };
    hardware = mkOption { type = types.str; };
    primaryJob = mkOption { type = types.str; };
  };

  hostType = types.submodule {
    options = identityOptions // {
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
      kind = mkOption { type = types.enum [ "service" ]; };
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
  };
}
