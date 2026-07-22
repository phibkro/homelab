/**
  nori.alerts channel auth split — the boundary this PR adds.

  2026-07-23: FLEET/AGENT alerts moved off ntfy.sh (public rate limit)
  onto a self-hosted hub that denies anonymous publish; CRITICAL INFRA
  alerts deliberately stay on ntfy.sh (uptime-independent of the
  homelab). The split is structural — per-channel `baseUrl` +
  `authTokenSecret` (modules/infra/observability/alerts.nix) — not a
  convention two producers have to remember. This test proves the
  structure holds by running the real nori-alert binary against a stub
  receiver and inspecting the actual HTTP request it sent:

   • an unauthenticated channel (stand-in for the ntfy.sh-backed infra
     channel) posts with NO Authorization header
   • an authenticated channel (stand-in for the pi-hub-backed agents
     channel) posts WITH `Authorization: Bearer <token>`, token read
     from the sops secret named by authTokenSecret

  Doesn't test the real pi ntfy hub or the real ntfy.sh (both external
  services) — that's covered by the runbook's manual curl verification
  (docs/runbooks/ntfy-auth-bootstrap.md § 5) and is out of reach for a
  hermetic nixosTest. This test's job is narrower and fully in-repo:
  does nori-alert's shell code actually attach the header when the
  option is set, and actually omit it when the option is unset.

  Invoked via `nix build .#checks.<system>.e2e-alerts-channel-auth`.
*/
{
  pkgs,
  lib,
  inputs,
  ...
}:

pkgs.testers.runNixOSTest {
  name = "e2e-alerts-channel-auth";

  node.specialArgs = { inherit inputs; };

  nodes.pi =
    { config, lib, ... }:
    {
      imports = [
        inputs.sops-nix.nixosModules.sops
        ../modules/infra/observability/alerts.nix
      ];

      environment.etc."sops-test-age.txt".source = ./keys/test-age.txt;
      sops.age.keyFile = "/etc/sops-test-age.txt";
      sops.age.sshKeyPaths = lib.mkForce [ ];
      sops.defaultSopsFile = ./secrets/test.yaml;
      sops.secrets.ntfy-channel = { };
      sops.secrets.ntfy-publisher-token = { };

      networking.hostName = "pi";

      # Two channels, one stub URL — the only variable under test is
      # whether authTokenSecret is set. "infra" mirrors the real infra
      # channel (ntfy.sh, no auth); "agents" mirrors the real agents
      # channel now pointed at the self-hosted hub (auth required).
      nori.alerts.channels.infra = {
        topicSecret = config.sops.secrets.ntfy-channel.path;
        baseUrl = "http://127.0.0.1:9999";
      };
      nori.alerts.channels.agents = {
        topicSecret = config.sops.secrets.ntfy-channel.path;
        baseUrl = "http://127.0.0.1:9999";
        authTokenSecret = config.sops.secrets.ntfy-publisher-token.path;
      };
      nori.alerts.routes.operator = [ "infra" ];
      nori.alerts.routes.agents = [ "agents" ];

      # Same stub-receiver pattern as e2e-disk-alert.nix — captures
      # headers (not just the body) so the test can assert on the
      # Authorization header's presence/absence, not just delivery.
      systemd.services.test-ntfy-receiver = {
        description = "Stub — captures ntfy POSTs from nori-alert";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          Type = "simple";
          StateDirectory = "test-ntfy";
          ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "test-ntfy-receiver.py" ''
            import http.server
            class H(http.server.BaseHTTPRequestHandler):
                def do_POST(self):
                    n = int(self.headers.get("Content-Length", 0))
                    body = self.rfile.read(n).decode("utf-8", errors="replace")
                    with open("/var/lib/test-ntfy/messages", "a") as f:
                        f.write(f"PATH={self.path}\n")
                        for k, v in self.headers.items():
                            f.write(f"HDR {k}: {v}\n")
                        f.write(f"BODY={body}\n---\n")
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"ok")
                def log_message(self, *a, **k):
                    pass
            http.server.HTTPServer(("127.0.0.1", 9999), H).serve_forever()
          ''}";
        };
      };

      nixpkgs.config = lib.mkForce {
        allowAliases = true;
        allowBroken = false;
        allowUnfree = false;
      };
      documentation.enable = lib.mkForce false;
    };

  testScript = ''
    start_all()
    pi.wait_for_unit("multi-user.target")
    pi.wait_for_unit("test-ntfy-receiver.service")

    with subtest("unauthenticated channel (operator/infra) posts with no Authorization header"):
        pi.succeed("rm -f /var/lib/test-ntfy/messages")
        pi.succeed(
            "nori-alert --audience operator --severity warning "
            "--category test --title infra-test --body body-infra"
        )
        captured = pi.succeed("cat /var/lib/test-ntfy/messages")
        assert "PATH=/test-channel" in captured, (
            f"alert posted to wrong path: {captured!r}"
        )
        assert "Authorization" not in captured, (
            f"infra channel must NOT carry a token — leaked one: {captured!r}"
        )

    with subtest("authenticated channel (agents) posts with the configured bearer token"):
        pi.succeed("rm -f /var/lib/test-ntfy/messages")
        pi.succeed(
            "nori-alert --audience agents --severity warning "
            "--category test --title agents-test --body body-agents"
        )
        captured = pi.succeed("cat /var/lib/test-ntfy/messages")
        assert "HDR Authorization: Bearer tk_test_not_a_real_ntfy_token" in captured, (
            f"agents channel missing the expected bearer token: {captured!r}"
        )
  '';
}
