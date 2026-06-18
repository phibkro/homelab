/**
  e2e Phase 2 — pi-alone smoke with homelab blocky module.

  Builds on Phase 1 (which booted a bare nixpkgs blocky for a
  framework smoke). Phase 2 imports the REAL homelab blocky
  module (`modules/infra/networking/blocky.nix`) via the lanRoutes
  registry pipeline, with a sops-stub fixture covering the option-
  schema requirements.

  Verifies:
   1. The infra/networking module's lanRoutes → blocky.customDNS
      auto-generation works (a route declared in
      `nori.lanRoutes.<X>` is auto-resolved by Blocky).
   2. The full schema chain (hosts → placement → capabilities →
      backup → networking) composes correctly with the sops stub.
   3. The homelab's blocky.nix produces a functional DNS resolver.

  What it still skips (Phase 3+ targets):
   - gatus (needs sops env file with real values)
   - ntfy server (publishes to ntfy.sh, needs internet)
   - caddy (needs ACME — internal CA + cert generation)
   - authelia (~10 sops secrets)

  Implements DoD from docs/specs/2026-06-17-e2e-vm-simulation.md
  § Phase 1 (now extended to validate the homelab module's behavior,
  not just the framework).

  Invoked via nix build .#checks.<system>.e2e-pi-smoke.
*/
{
  pkgs,
  lib,
  inputs,
  ...
}:

pkgs.testers.runNixOSTest {
  name = "e2e-pi-smoke";

  # Same `inputs` plumbing real nixosConfigurations get at flake-
  # build time. Homelab modules consume `inputs` for impermanence /
  # nixos-hardware refs even when those features aren't active.
  node.specialArgs = { inherit inputs; };

  nodes.pi =
    { config, lib, ... }:
    {
      imports = [
        # Stub sops-nix's option surface — see fixture header for
        # why we don't import the real module.
        ./fixtures/sops-stub.nix

        # Infra schemas the homelab blocky module reads through.
        ../modules/infra/hosts.nix
        ../modules/infra/placement.nix
        ../modules/infra/capabilities
        ../modules/infra/storage # nori.fs (consumed by backup/btrbk)
        ../modules/infra/backup
        ../modules/infra/networking

        # Observability — selected submodules. Skipping the full
        # bundle import to avoid pulling in vector (needs a
        # VictoriaLogs server) + beszel agent (would try to register
        # with a hub) + node-exporter / nvidia-gpu-exporter (not
        # needed for smoke). Phase 4 picks up the fuller observability
        # set.
        ../modules/infra/observability/gatus.nix
        ../modules/infra/observability/heartbeat.nix
      ];

      # Synthetic identity — provides nori.hosts registry entries
      # that placement assertions consult.
      nori.hosts = {
        pi = {
          tailnetIp = "100.0.0.1";
          lanIp = "10.0.0.10";
          role = "appliance";
          roleOneLiner = "";
          codename = "test-pi";
          hardware = "test-qemu";
          primaryJob = "Phase 2 smoke";
        };
        workstation = {
          tailnetIp = "100.0.0.2";
          lanIp = "10.0.0.20";
          role = "workhorse";
          roleOneLiner = "test workhorse";
          codename = "test-station";
          hardware = "test-qemu";
          primaryJob = "Phase 2 smoke";
        };
      };

      networking.hostName = "pi";
      nori.domain = "test.lan";
      nori.lanIp = lib.mkForce "10.0.0.20";

      # Test routes — exercise the lanRoutes → blocky.customDNS
      # auto-generation pipeline. Two routes so we can verify both
      # resolve identically (to nori.lanIp).
      nori.lanRoutes.smoke = {
        port = 9999;
        runsOn = "workstation";
      };
      nori.lanRoutes.another = {
        port = 8888;
        runsOn = "workstation";
      };

      nori.services.blocky.enable = true;
      nori.services.gatus.enable = true;
      nori.services.heartbeat.enable = true;
      nori.services.caddy.enable = true;
      nori.blocky.role = "self-hosted";

      # Stub backup target — required because caddy declares
      # `nori.backups.caddy.include = [...]` and the backup module
      # asserts that any active paths-backup needs ≥1 target. Test
      # doesn't actually run restic (would need real repo + key);
      # the target just satisfies the assertion.
      nori.backupTargets.test-stub = {
        # Use a remote-shaped URL to satisfy the appliance-host
        # assertion (pi role=appliance can't have LOCAL restic
        # targets — anti-write storage posture). Test never actually
        # runs restic; the URL is never dialed.
        repository = "sftp:stub@stub.test:/stub";
        description = "test stub; never actually used";
      };
      # backup/default.nix reads config.sops.secrets.restic-password
      # — declare it so sops-stub plants a fixture for the eval.
      sops.secrets.restic-password = { };

      # Caddy test overrides — skip ACME, skip cloudflare plugin.
      services.caddy.package = lib.mkForce pkgs.caddy;
      services.caddy.globalConfig = lib.mkForce ''
        # `local_certs` makes Caddy issue self-signed certs from its
        # internal CA for ALL sites — no external ACME contact, no
        # cloudflare token required. Standard pattern for test envs.
        local_certs
      '';

      # Test framework's nixpkgs.config differs from base.nix's;
      # force ours to match the test framework to avoid the
      # allowUnfree conflict.
      nixpkgs.config = lib.mkForce {
        allowAliases = true;
        allowBroken = false;
        allowUnfree = false;
      };

      # Smaller closure for faster test boot.
      documentation.enable = lib.mkForce false;

      # `dig` for the DNS-resolution assertions in testScript.
      environment.systemPackages = [ pkgs.bind.dnsutils ];
    };

  testScript = ''
    start_all()
    pi.wait_for_unit("multi-user.target")

    with subtest("blocky.service reaches active state"):
        pi.wait_for_unit("blocky.service")
        pi.wait_for_open_port(53)

    with subtest("lanRoutes → blocky customDNS auto-generation works"):
        # smoke.test.lan and another.test.lan are both declared in
        # nori.lanRoutes; the networking module's customDNS generator
        # should map each to nori.lanIp (10.0.0.20) automatically.
        smoke = pi.succeed("dig +short +time=2 +tries=1 smoke.test.lan @127.0.0.1")
        assert "10.0.0.20" in smoke, f"smoke.test.lan: expected 10.0.0.20, got: {smoke!r}"

        another = pi.succeed("dig +short +time=2 +tries=1 another.test.lan @127.0.0.1")
        assert "10.0.0.20" in another, f"another.test.lan: expected 10.0.0.20, got: {another!r}"

    with subtest("gatus.timer activates"):
        # gatus.service has wantedBy=[] in the homelab module — it's
        # fired by gatus.timer at OnBootSec=60s instead (so cross-host
        # rebuilds don't trigger probe-flapping). Wait for the timer
        # to be active; the service itself starts on the timer's
        # schedule.
        pi.wait_for_unit("gatus.timer")

    with subtest("heartbeat.timer activates"):
        # heartbeat.service is a oneshot — the timer wants to fire it
        # every 60s. We don't care if the curl succeeds (the URL is
        # a stub comment, not a real hc.io endpoint); we DO care that
        # the timer activates without systemd refusing to load it.
        pi.wait_for_unit("heartbeat.timer")

    with subtest("caddy.service starts + binds :443"):
        # caddy uses local_certs (internal CA) — no real ACME contact.
        # Validates: caddy module evals, the auto-generated vhost
        # config (from nori.lanRoutes) is syntactically valid, caddy
        # binds to :443. Doesn't try to proxy requests through to
        # synthetic backends — upstreams aren't reachable in this
        # single-node test.
        pi.wait_for_unit("caddy.service")
        pi.wait_for_open_port(443)
  '';
}
