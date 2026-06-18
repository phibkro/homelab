{
  pkgs,
  inputs,
  lib,
  ...
}:

/**
  Eval test — `nori.lanRoutes` → `services.blocky.customDNS.mapping`
  auto-generation.

  Layer 1 of the testing methodology: pure NixOS-eval, sub-second
  (post-cache), no VM. Catches schema regressions + cross-module
  composition errors before they surface in nixosTest.

  Asserts that for each route declared in `nori.lanRoutes.<X>`, the
  resulting `services.blocky.settings.customDNS.mapping` contains
  `<X>.${nori.domain}` → `nori.lanIp` — the registry-to-DNS mapping
  the lanRoutes pipeline promises.

  Builds the homelab config explicitly using
  `nixpkgs/nixos/lib/eval-config.nix` (no flake build, no closure
  realization for services). Imports the same module bundle as the
  nixosTest does, plus the sops-stub fixture.

  Invoked as the `eval-lanroute-customdns` flake check via
  flake.nix:checks.${system}.
*/

let
  evalConfig = import (pkgs.path + "/nixos/lib/eval-config.nix");

  result = evalConfig {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      ../fixtures/sops-stub.nix
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
          nori.lanRoutes.foo = {
            port = 8080;
            runsOn = "workstation";
          };
          nori.lanRoutes.bar = {
            port = 9090;
            runsOn = "workstation";
          };
          nori.services.blocky.enable = true;
          nori.blocky.role = "self-hosted";
          # Stub backup target so the appliance assertion passes.
          nori.backupTargets.test-stub = {
            repository = "sftp:stub@stub:/stub";
            description = "test";
          };
          sops.secrets.restic-password = { };
          # Minimal scaffolding to satisfy NixOS module-system assertions.
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

  inherit (result.config.services.blocky.settings) customDNS;
  inherit (customDNS) mapping;

  expected = {
    "foo.test.lan" = "10.0.0.20";
    "bar.test.lan" = "10.0.0.20";
  };

  hasMapping = name: target: (mapping.${name} or null) == target;
  allExpected = lib.all (n: hasMapping n expected.${n}) (lib.attrNames expected);
in
if allExpected then
  "ok — lanRoutes → blocky customDNS mapping correct"
else
  throw ''
    lanRoute customDNS mapping mismatch.
    expected: ${builtins.toJSON expected}
    actual:   ${builtins.toJSON mapping}
  ''
