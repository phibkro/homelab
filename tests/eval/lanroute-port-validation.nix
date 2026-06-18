{
  pkgs,
  inputs,
  lib,
  ...
}:

/**
  Eval test — `nori.lanRoutes.<X>.port` validates as 16-bit unsigned.

  Layer 1: pure NixOS-eval. Verifies that the port option's type
  constraint (`types.port` = 0-65535) FIRES on out-of-range values.

  The test passes if eval throws when given port=99999, and ALSO
  passes if eval succeeds with a valid port. The mechanism:
  evaluate two config variations and assert one throws, one doesn't.

  Demonstrates the negative-path eval test pattern (per
  docs/reference/testing-methodology.md): write a test that asserts
  a BAD config fails, not just that a good config succeeds.
*/

let
  evalConfig = import (pkgs.path + "/nixos/lib/eval-config.nix");

  mkConfig =
    port:
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
            nori.lanRoutes.test = {
              inherit port;
              runsOn = "workstation";
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
      ];
    };

  # Force the config's lanRoutes attribute to evaluate. tryEval
  # captures whether the eval throws.
  forceEval = cfg: builtins.tryEval cfg.config.nori.lanRoutes.test.port;

  validResult = forceEval (mkConfig 8080);
  invalidResult = forceEval (mkConfig 99999);

  validPasses = validResult.success && validResult.value == 8080;
  invalidFails = !invalidResult.success;
in
if validPasses && invalidFails then
  "ok — port type validates: 8080 passes, 99999 throws"
else
  throw ''
    Port validation test failed.
    valid port 8080:   success=${toString validResult.success} value=${
      toString (validResult.value or "n/a")
    }
    invalid port 99999: success=${toString invalidResult.success}
    expected: valid passes (success=true, value=8080), invalid fails (success=false)
  ''
