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
   - operator stays internal  an operator route with internet
                              reachability → must throw
   - public SSO is coherent   an internet OIDC route with an internal
                              auth portal → must throw

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

  # Variant D — management routes must never cross the internet boundary.
  internetOperatorConfig = mkConfig {
    nori.lanRoutes.admin = {
      port = 8080;
      runsOn = "workstation";
      audience = "operator";
      reachability = "internet";
    };
  };

  # Variant E — an internet OIDC route is unusable when its issuer/login
  # portal remains internal. The assertion makes the broken redirect graph
  # unrepresentable instead of leaving it to fail after deployment.
  internetOidcInternalAuthConfig = mkConfig {
    nori.lanRoutes = {
      auth = {
        port = 9091;
        runsOn = "pi";
        audience = "public";
      };
      app = {
        port = 8080;
        runsOn = "workstation";
        audience = "family";
        reachability = "internet";
        oidc = {
          clientName = "Test App";
          redirectPath = "/callback";
          tokenEndpointAuthMethod = "client_secret_basic";
        };
      };
    };
  };

  validResult = forceAssertions validConfig;
  duplicatePortResult = forceAssertions duplicatePortConfig;
  unknownRunsOnResult = forceAssertions unknownRunsOnConfig;
  internetOperatorResult = forceAssertions internetOperatorConfig;
  internetOidcInternalAuthResult = forceAssertions internetOidcInternalAuthConfig;

  validPasses = validResult.success;
  duplicatePortFails = !duplicatePortResult.success;
  unknownRunsOnFails = !unknownRunsOnResult.success;
  internetOperatorFails = !internetOperatorResult.success;
  internetOidcInternalAuthFails = !internetOidcInternalAuthResult.success;
in
if
  validPasses
  && duplicatePortFails
  && unknownRunsOnFails
  && internetOperatorFails
  && internetOidcInternalAuthFails
then
  "ok — route invariants fire on duplicate port + unknown runsOn + unsafe internet exposure"
else
  throw ''
    Route-invariant assertions did not behave as expected.
    valid baseline:        success=${toString validResult.success} (expected: true)
    duplicate port:        success=${toString duplicatePortResult.success} (expected: false)
    unknown runsOn:        success=${toString unknownRunsOnResult.success} (expected: false)
    internet operator:     success=${toString internetOperatorResult.success} (expected: false)
    public OIDC/internal auth: success=${toString internetOidcInternalAuthResult.success} (expected: false)

    If any of these flipped, a regression in
    modules/infra/networking/default.nix dropped a module assertion.
  ''
