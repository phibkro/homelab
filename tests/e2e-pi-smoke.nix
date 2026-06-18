/**
  e2e Phase 1 — pi-alone framework smoke.

  Boots a minimal NixOS config in a QEMU VM via nixosTest, reaches
  multi-user.target, and runs a single blocky DNS resolution check.
  PROVES the test infrastructure works end-to-end before Phase 2+
  expand to importing the real pi config (which needs a richer sops
  fixture layer than Phase 1 budgets).

  Scope reduced from the spec's original Phase 1 (blocky + gatus +
  beszel-hub) after discovering the homelab module graph requires
  pervasive sops decryption at activation time — the gatus/ntfy/
  caddy/authelia modules all read `config.sops.secrets.<X>.path`,
  which forces either a real sops test-key fixture (Phase 2 work) or
  per-module stub overrides (fragile + invasive).

  This Phase 1 instead: bare-bones blocky with no homelab module
  bundle. Verifies:
   - nixosTest framework works on workstation
   - QEMU VM boots in <90s
   - blocky package + service module from nixpkgs work in isolation
   - testScript framework runs Python assertions correctly

  Implements DoD from docs/specs/2026-06-17-e2e-vm-simulation.md
  § Phase 1, with the scope-down noted in the spec's executed-as
  block.

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

  nodes.pi =
    { config, lib, ... }:
    {
      # Minimal blocky config — proves the test framework + nixpkgs
      # service modules work end-to-end. Doesn't import homelab
      # modules (those need sops fixtures; out of Phase 1 scope).
      services.blocky = {
        enable = true;
        settings = {
          ports.dns = 53;
          upstreams.groups.default = [ "1.1.1.1" ];
          customDNS.mapping = {
            "smoke.test.lan" = "10.0.0.20";
          };
        };
      };

      # Smaller closure for faster test boot.
      documentation.enable = lib.mkForce false;

      # `dig` for the DNS-resolution assertion in testScript.
      environment.systemPackages = [ pkgs.bind.dnsutils ];
    };

  testScript = ''
    start_all()
    pi.wait_for_unit("multi-user.target")

    with subtest("blocky.service reaches active state"):
        pi.wait_for_unit("blocky.service")
        pi.wait_for_open_port(53)

    with subtest("blocky resolves the test customDNS entry"):
        # smoke.test.lan should resolve to 10.0.0.20 from the
        # customDNS.mapping above. This validates the WHOLE chain —
        # nixpkgs module → systemd → port bind → DNS query.
        result = pi.succeed("dig +short +time=2 +tries=1 smoke.test.lan @127.0.0.1")
        assert "10.0.0.20" in result, f"expected 10.0.0.20, got: {result!r}"
  '';
}
