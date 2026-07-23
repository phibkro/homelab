{
  pkgs,
  inputs,
  lib,
  ...
}:

/**
  Eval test — public Cloudflare records are derived exclusively from
  `nori.lanRoutes.<name>.reachability = "internet"`.

  The adapter must emit exact, DNS-only IPv4 records and must not create
  an internal hostname, wildcard, or IPv6 record.
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
      ../../modules/infra/networking/cloudflare-ddns/runtime.nix
      (
        { lib, ... }:
        {
          networking.hostName = "pi";
          nori.domain = "example.test";
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
            operator = {
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

  ddns = result.config.services.cloudflare-ddns;
  unitEnvironment = result.config.systemd.services.cloudflare-ddns.serviceConfig.Environment;
  expected = [ "family.example.test" ];
in
if
  ddns.enable
  && ddns.ip4Domains == expected
  && ddns.ip6Domains == [ ]
  && ddns.provider.ipv6 == "none"
  && ddns.proxied == "false"
  && ddns.deleteOnStop
  && lib.elem "MANAGED_RECORDS_COMMENT_REGEX=^Managed by homelab nori\\.lanRoutes reachability=internet$" unitEnvironment
  && !(lib.elem "operator.example.test" ddns.ip4Domains)
  && !(lib.any (lib.hasPrefix "*.") ddns.ip4Domains)
then
  "ok — Cloudflare DDNS contains only exact, DNS-only IPv4 internet routes"
else
  throw ''
    Cloudflare DDNS route derivation is unsafe.
    IPv4 domains: ${toString ddns.ip4Domains}
    IPv6 domains: ${toString ddns.ip6Domains}
    IPv6 provider: ${ddns.provider.ipv6}
    proxied: ${ddns.proxied}
  ''
