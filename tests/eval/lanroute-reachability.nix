{
  pkgs,
  inputs,
  lib,
  ...
}:

/**
  Eval test — `nori.lanRoutes.<n>.reachability` lowers into Caddy's
  client-address boundary.

  One internal route and one internet route share the wildcard vhost.
  The generated config must contain exactly one private/tailnet client
  matcher (for the internal route) and a final 404 catch-all. This catches
  the dangerous regressions: gating neither route, gating the public route,
  or letting an unknown/forged Host header fall through.
*/

let
  evalConfig = import (pkgs.path + "/nixos/lib/eval-config.nix");

  result = evalConfig {
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
          nori.lanRoutes = {
            private = {
              port = 8080;
              runsOn = "workstation";
            };
            family = {
              port = 9090;
              runsOn = "workstation";
              audience = "family";
              reachability = "internet";
              noAuthReason = "test backend provides its own native account gate";
            };
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

  caddyConfig = result.config.services.caddy.virtualHosts."*.test.lan".extraConfig;
  clientGate = "client_ip private_ranges 100.64.0.0/10";
  gateCount = builtins.length (lib.splitString clientGate caddyConfig) - 1;
  privateHostPresent = lib.hasInfix "host private.test.lan" caddyConfig;
  familyHostPresent = lib.hasInfix "host family.test.lan" caddyConfig;
  catchAllPresent = lib.hasInfix "respond 404" caddyConfig;
in
if gateCount == 1 && privateHostPresent && familyHostPresent && catchAllPresent then
  "ok — internal route is client-gated, internet route is not, unknown hosts fail closed"
else
  throw ''
    lanRoute reachability did not lower safely into Caddy.
    private host present: ${toString privateHostPresent}
    family host present:  ${toString familyHostPresent}
    client gate count:    ${toString gateCount} (expected: 1)
    catch-all present:    ${toString catchAllPresent}

    Generated Caddy config:
    ${caddyConfig}
  ''
