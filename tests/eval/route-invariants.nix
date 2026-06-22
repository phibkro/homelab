{
  pkgs,
  inputs,
  lib,
  ...
}:

/**
  Eval test — cross-product invariants over `nori.lanRoutes`.

  Layer 1: pure NixOS-eval, sub-second. Verifies that the module
  assertions in `modules/infra/networking/default.nix` actually FIRE
  on the failure modes they're written for — the "test the test"
  pattern. Without this, a regression that drops an assertion would
  silently pass `nix flake check` because no production config
  violates the invariant TODAY.

  Invariants exercised:

   - port uniqueness    two routes on the same port → must throw
   - runsOn ∈ nori.hosts  a route whose `runsOn` isn't a registry
                          key → must throw

  Pattern: build the same homelab config in two variants — one valid
  (sanity baseline, must NOT throw), one with the invariant violated
  (must throw). `builtins.tryEval` captures the eval outcome without
  letting the throw propagate.

  Invoked as `eval-route-invariants` via flake.nix:checks.${system}.
*/

let
  evalConfig = import (pkgs.path + "/nixos/lib/eval-config.nix");

  # Build a config with a payload that the caller can mutate. The
  # shared scaffolding mirrors the e2e nixosTest config — same module
  # bundle, same minimal scaffolding to satisfy module-system
  # assertions.
  mkConfig =
    extraConfig:
    evalConfig {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        inputs.sops-nix.nixosModules.sops
        ../../modules/infra/hosts.nix
        ../../modules/infra/placement.nix
        ../../modules/infra/capabilities
        ../../modules/infra/storage
        ../../modules/infra/backup
        ../../modules/infra/networking
        (
          { lib, ... }:
          {
            networking.hostName = "pi";
            nori.domain = "test.lan";
            nori.lanIp = lib.mkForce "10.0.0.20";
            nori.hosts.pi = {
              tailnetIp = "100.0.0.1";
              lanIp = "10.0.0.10";
              role = "appliance";
              roleOneLiner = "";
              codename = "test";
              hardware = "test";
              primaryJob = "test";
            };
            nori.hosts.workstation = {
              tailnetIp = "100.0.0.2";
              lanIp = "10.0.0.20";
              role = "workhorse";
              roleOneLiner = "test";
              codename = "test";
              hardware = "test";
              primaryJob = "test";
            };
            nori.services.blocky.enable = true;
            nori.blocky.role = "self-hosted";
            nori.backupTargets.test-stub = {
              repository = "sftp:stub@stub:/stub";
              description = "test";
            };
            sops.age.keyFile = "/etc/sops-test-age.txt";
            sops.age.sshKeyPaths = lib.mkForce [ ];
            sops.defaultSopsFile = ../secrets/test.yaml;
            sops.secrets.restic-password = { };
            system.stateVersion = "26.05";
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            boot.loader.grub.devices = [ "nodev" ];
          }
        )
        extraConfig
      ];
    };

  # Forcing `system.build.toplevel` is what makes module assertions
  # actually fire — they're collected at config eval and emitted as
  # a `throw` when toplevel is realized.
  forceAssertions = cfg: builtins.tryEval cfg.config.system.build.toplevel.drvPath;

  # Variant A — valid config (baseline). All routes pass invariants.
  validConfig = mkConfig {
    nori.lanRoutes = {
      foo = {
        port = 8080;
        runsOn = "workstation";
      };
      bar = {
        port = 9090;
        runsOn = "pi";
      };
    };
  };

  # Variant B — two routes on the same port. Must throw via the
  # port-uniqueness assertion.
  duplicatePortConfig = mkConfig {
    nori.lanRoutes = {
      foo = {
        port = 8080;
        runsOn = "workstation";
      };
      bar = {
        port = 8080;
        runsOn = "pi";
      };
    };
  };

  # Variant C — runsOn references a host not in nori.hosts. Must
  # throw via the runsOn-membership assertion.
  unknownRunsOnConfig = mkConfig {
    nori.lanRoutes.typo = {
      port = 8080;
      runsOn = "wokrstation"; # intentional typo
    };
  };

  # Variant D — a family-audience route with exposeOnTailnet. Direct
  # all-peer access bypasses the OIDC auth Caddy fronts → must throw via
  # the new auth-bypass assertion.
  exposeFamilyConfig = mkConfig {
    nori.lanRoutes.secret = {
      port = 8080;
      runsOn = "workstation";
      audience = "family";
      exposeOnTailnet = true;
    };
  };

  # Variant E — functional check (not "test the test"): a cross-host route
  # must generate an APPLIANCE-SCOPED firewall rule, not an all-peer hole.
  # Evaluated AS workstation (the backend host) so the generator emits the
  # Caddy-reach rule admitting pi (the appliance) and leaves the all-peer
  # port list empty.
  scopedReachConfig = mkConfig {
    networking.hostName = lib.mkForce "workstation";
    nori.lanRoutes.app = {
      port = 8080;
      runsOn = "workstation";
      audience = "operator";
    };
  };
  scopedFw = scopedReachConfig.config.networking.firewall;
  # pi's test tailnetIp is 100.0.0.1 (see mkConfig scaffolding).
  reachRuleScopedToAppliance = lib.hasInfix "ip saddr 100.0.0.1 tcp dport 8080 accept" scopedFw.extraInputRules;
  portNotOpenToAllPeers = !(lib.elem 8080 scopedFw.interfaces.tailscale0.allowedTCPPorts);

  validResult = forceAssertions validConfig;
  duplicatePortResult = forceAssertions duplicatePortConfig;
  unknownRunsOnResult = forceAssertions unknownRunsOnConfig;
  exposeFamilyResult = forceAssertions exposeFamilyConfig;

  validPasses = validResult.success;
  duplicatePortFails = !duplicatePortResult.success;
  unknownRunsOnFails = !unknownRunsOnResult.success;
  exposeFamilyFails = !exposeFamilyResult.success;
in
if
  validPasses
  && duplicatePortFails
  && unknownRunsOnFails
  && exposeFamilyFails
  && reachRuleScopedToAppliance
  && portNotOpenToAllPeers
then
  "ok — route invariants fire (dup port, unknown runsOn, family+exposeOnTailnet) + cross-host reach is appliance-scoped"
else
  throw ''
    Route-invariant assertions did not behave as expected.
    valid baseline:           success=${toString validResult.success} (expected: true)
    duplicate port:           success=${toString duplicatePortResult.success} (expected: false)
    unknown runsOn:           success=${toString unknownRunsOnResult.success} (expected: false)
    family + exposeOnTailnet:  success=${toString exposeFamilyResult.success} (expected: false)
    reach scoped to appliance: ${toString reachRuleScopedToAppliance} (expected: true)
    port NOT open to all peers: ${toString portNotOpenToAllPeers} (expected: true)

    If an assertion flipped, a regression in
    modules/infra/networking/default.nix dropped/changed an invariant.
    If the scoping checks flipped, the appliance-scoped Caddy-reach rule
    regressed (cross-host backend exposed to all tailnet peers again).
  ''
