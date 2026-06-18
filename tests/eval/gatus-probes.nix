{
  pkgs,
  inputs,
  lib,
  ...
}:

/**
  Eval test — `nori.lanRoutes.<X>.monitor` → `services.gatus.settings.endpoints`
  auto-generation.

  Layer 1: pure NixOS-eval, sub-second. Verifies the registry-to-Gatus
  pipeline that modules/infra/networking/default.nix promises: each
  route whose `monitor != null` produces exactly ONE gatus endpoint
  with the route's name + derived URL + ntfy alert tail. Routes
  without `monitor` set produce ZERO endpoints (they exist in the
  caddy + DNS planes only).

  Why this catches a real regression class: the homelab's observability
  surface is "the operator knows when a service is down." That depends
  on the lanRoutes → gatus endpoints generator being correct. A schema
  change that silently drops endpoints would still pass `nix flake
  check` because eval succeeds — but the operator would have lost
  alerting on the affected services. This test pins the contract.

  Invoked as `eval-gatus-probes` via flake.nix:checks.${system}.
*/

let
  evalConfig = import (pkgs.path + "/nixos/lib/eval-config.nix");

  result = evalConfig {
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

          # Three routes — two with monitor, one without. The
          # generator should emit endpoints ONLY for the first two.
          nori.lanRoutes.alpha = {
            port = 8080;
            runsOn = "workstation";
            monitor = { };
          };
          nori.lanRoutes.beta = {
            port = 8081;
            runsOn = "pi";
            monitor.path = "/api/health";
          };
          nori.lanRoutes.no-probe = {
            port = 8082;
            runsOn = "workstation";
            # monitor unset → no gatus endpoint expected.
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
    ];
  };

  endpoints = result.config.services.gatus.settings.endpoints;
  endpointNames = map (e: e.name) endpoints;

  hasEndpoint = name: lib.elem name endpointNames;
  endpointBy = name: lib.findFirst (e: e.name == name) null endpoints;

  # Both monitored routes appear; the un-monitored one doesn't.
  alphaPresent = hasEndpoint "alpha";
  betaPresent = hasEndpoint "beta";
  noProbeAbsent = !(hasEndpoint "no-probe");

  # Path override flows through — beta should use /api/health, alpha the default /.
  alphaUrl = (endpointBy "alpha").url or "";
  betaUrl = (endpointBy "beta").url or "";
  alphaPathRight = lib.hasSuffix ":8080/" alphaUrl;
  betaPathRight = lib.hasSuffix "/api/health" betaUrl;

  # Every emitted endpoint should have an ntfy alert wired.
  allHaveNtfyAlert = lib.all (e: lib.any (a: a.type or "" == "ntfy") (e.alerts or [ ])) endpoints;
in
if
  alphaPresent && betaPresent && noProbeAbsent && alphaPathRight && betaPathRight && allHaveNtfyAlert
then
  "ok — lanRoutes.<X>.monitor → gatus endpoints mapping correct"
else
  throw ''
    Gatus probe-registry mismatch.
      alpha (monitor={}, expect present, default path):    present=${toString alphaPresent} pathRight=${toString alphaPathRight}  url=${alphaUrl}
      beta  (monitor.path=/api/health, expect present):    present=${toString betaPresent} pathRight=${toString betaPathRight}  url=${betaUrl}
      no-probe (no monitor, expect absent):                absent=${toString noProbeAbsent}
      all emitted endpoints have ntfy alert:                ${toString allHaveNtfyAlert}
    Endpoint names emitted: ${builtins.toJSON endpointNames}
  ''
